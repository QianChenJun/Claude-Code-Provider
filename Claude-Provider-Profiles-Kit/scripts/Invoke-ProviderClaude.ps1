#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Profile,

    [switch]$List,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ClaudeArgs
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $root 'providers.json'
$userSettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
$commandPrefix = 'ccp'

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "配置文件不存在：$Path"
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @{}
    }
    return Convert-JsonObjectToHashtable -Value ($text | ConvertFrom-Json)
}

function Convert-JsonObjectToHashtable {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $map = @{}
        foreach ($key in $Value.Keys) {
            $map[$key] = Convert-JsonObjectToHashtable -Value $Value[$key]
        }
        return $map
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [byte[]]) {
        $items = @()
        foreach ($item in $Value) {
            $items += Convert-JsonObjectToHashtable -Value $item
        }
        return $items
    }
    if ($Value.PSObject -and $Value.PSObject.Properties.Count -gt 0 -and $Value.GetType().Name -eq 'PSCustomObject') {
        $map = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $map[$property.Name] = Convert-JsonObjectToHashtable -Value $property.Value
        }
        return $map
    }
    return $Value
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 40
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

function Get-ProfileValue {
    param(
        [hashtable]$Map,
        [string[]]$Names
    )
    foreach ($name in $Names) {
        if ($Map.ContainsKey($name) -and $null -ne $Map[$name] -and "$($Map[$name])" -ne '') {
            return $Map[$name]
        }
    }
    return $null
}

function Test-HasCliModelArg {
    param([string[]]$Args)
    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq '--model' -or $Args[$i] -eq '-m') {
            return $true
        }
        if ($Args[$i] -like '--model=*') {
            return $true
        }
    }
    return $false
}

function Write-ProfileTable {
    param([hashtable]$Profiles)

    $Profiles.GetEnumerator() |
        Sort-Object Name |
        ForEach-Object {
            $item = $_.Value
            [PSCustomObject]@{
                '配置ID' = $_.Name
                '推荐命令' = "$commandPrefix-$($_.Name)"
                '兼容命令' = $item.shortcut
                '名称' = $item.displayName
                '接口地址' = $item.baseUrl
                '鉴权变量' = $(if ($item.authEnv) { $item.authEnv } else { 'ANTHROPIC_AUTH_TOKEN' })
                '默认模型' = $item.model
            }
        } |
        Format-Table -AutoSize
}

function Write-Usage {
    param([hashtable]$Profiles)

    Write-Output "用法："
    Write-Output "  $commandPrefix                         # 打开交互菜单"
    Write-Output "  $commandPrefix <profile> [claude args]"
    Write-Output "  $commandPrefix-list"
    Write-Output "  $commandPrefix-<profile> [claude args]"
    Write-Output "  $commandPrefix-sync"
    Write-Output "  $commandPrefix-manager"
    Write-Output ""
    Write-Output "兼容旧命令："
    Write-Output "  provider-claude -Profile <profile> [claude args]"
    Write-Output "  provider-claude -List"
    Write-Output "  mi-claude [claude args]"
    Write-Output ""
    Write-Output "可用供应商："
    Write-ProfileTable -Profiles $Profiles
}

function Select-ProfileFromMenu {
    param([hashtable]$Profiles)

    while ($true) {
        $entries = @($Profiles.GetEnumerator() | Sort-Object Name)
        Write-Host ""
        Write-Host "Claude 供应商配置"
        Write-Host "请选择供应商："

        for ($i = 0; $i -lt $entries.Count; $i++) {
            $id = $entries[$i].Name
            $profile = $entries[$i].Value
            $name = if ($profile.displayName) { $profile.displayName } else { $id }
            Write-Host ("  {0}. {1,-18} {2}" -f ($i + 1), "$commandPrefix-$id", $name)
        }

        Write-Host ""
        Write-Host "  L. 查看列表"
        Write-Host "  S. 同步快捷命令"
        Write-Host "  M. 打开管理页面"
        Write-Host "  H. 帮助"
        Write-Host "  Q. 退出"

        $rawChoice = Read-Host "输入编号或配置 ID"
        $choice = if ($null -eq $rawChoice) { '' } else { "$rawChoice".Trim() }
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice -in @('q', 'quit', 'exit', '退出')) {
            return $null
        }

        if ($choice -match '^\d+$') {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $entries.Count) {
                return $entries[$index].Name
            }
            Write-Warning "无效选择：$choice"
            continue
        }

        if ($choice -match '^(l|list|ls|列表|查看)$') {
            Write-ProfileTable -Profiles $Profiles | Out-Host
            continue
        }

        if ($choice -match '^(s|sync|同步)$') {
            & (Join-Path $root 'Sync-ClaudeProfileShortcuts.ps1') | Out-Host
            continue
        }

        if ($choice -match '^(m|manager|manage|管理)$') {
            & (Join-Path $root 'Manage-ClaudeProfiles.ps1') | Out-Host
            continue
        }

        if ($choice -match '^(h|help|usage|帮助)$') {
            Write-Usage -Profiles $Profiles | Out-Host
            continue
        }

        if ($Profiles.ContainsKey($choice)) {
            return $choice
        }

        Write-Warning "未知选择：$choice"
    }
}

$config = Read-JsonFile -Path $configPath
if (-not $config.ContainsKey('profiles')) {
    throw "配置文件必须包含 profiles 对象：$configPath"
}

$showHelp = $false
if ($Profile -in @('list', 'ls', '列表', '查看')) {
    $List = $true
    $Profile = $null
}
elseif ($Profile -in @('help', 'usage', '帮助')) {
    $showHelp = $true
    $Profile = $null
}
elseif ($Profile -in @('sync', '同步')) {
    & (Join-Path $root 'Sync-ClaudeProfileShortcuts.ps1')
    exit $LASTEXITCODE
}
elseif ($Profile -in @('manager', 'manage', '管理')) {
    & (Join-Path $root 'Manage-ClaudeProfiles.ps1')
    exit $LASTEXITCODE
}

if ($List) {
    Write-ProfileTable -Profiles $config.profiles
    exit 0
}

if ($showHelp) {
    Write-Usage -Profiles $config.profiles
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Profile)) {
    $Profile = Select-ProfileFromMenu -Profiles $config.profiles
    if ([string]::IsNullOrWhiteSpace($Profile)) {
        exit 0
    }
}

if (-not $config.profiles.ContainsKey($Profile)) {
    throw "未知配置：$Profile。可用配置：$($config.profiles.Keys -join ', ')"
}

$profileConfig = $config.profiles[$Profile]
$baseUrl = Get-ProfileValue -Map $profileConfig -Names @('baseUrl', 'url')
$authEnv = Get-ProfileValue -Map $profileConfig -Names @('authEnv')
if (-not $authEnv) {
    $authEnv = 'ANTHROPIC_AUTH_TOKEN'
}

$apiKey = Get-ProfileValue -Map $profileConfig -Names @('apiKey', 'token', 'key')
$apiKeyEnv = Get-ProfileValue -Map $profileConfig -Names @('apiKeyEnv', 'tokenEnv', 'keyEnv')
$apiKeyFile = Get-ProfileValue -Map $profileConfig -Names @('apiKeyFile', 'tokenFile', 'keyFile')

if ($apiKeyEnv) {
    $fromEnv = [Environment]::GetEnvironmentVariable($apiKeyEnv, 'User')
    if (-not $fromEnv) {
        $fromEnv = [Environment]::GetEnvironmentVariable($apiKeyEnv, 'Process')
    }
    if (-not $fromEnv) {
        $fromEnv = [Environment]::GetEnvironmentVariable($apiKeyEnv, 'Machine')
    }
    if ($fromEnv) {
        $apiKey = $fromEnv
    }
}

if ($apiKeyFile) {
    $expandedKeyFile = [Environment]::ExpandEnvironmentVariables($apiKeyFile)
    if (Test-Path -LiteralPath $expandedKeyFile) {
        $apiKey = ([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($expandedKeyFile))).Trim()
    }
}

if (-not $baseUrl) {
    throw "配置 '$Profile' 缺少 baseUrl"
}
if (-not $apiKey) {
    throw "配置 '$Profile' 缺少 apiKey。请在 providers.json 中设置 apiKey，或配置 apiKeyEnv/apiKeyFile。"
}

$settings = @{}
if (Test-Path -LiteralPath $userSettingsPath) {
    $settings = Read-JsonFile -Path $userSettingsPath
}
if (-not $settings.ContainsKey('env') -or $null -eq $settings.env) {
    $settings.env = @{}
}

$clearOtherAuthEnv = $true
if ($profileConfig.ContainsKey('clearOtherAuthEnv')) {
    $clearOtherAuthEnv = [bool]$profileConfig.clearOtherAuthEnv
}

if ($clearOtherAuthEnv) {
    foreach ($name in @('ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY')) {
        if ($name -ne $authEnv -and $settings.env.ContainsKey($name)) {
            $settings.env.Remove($name)
        }
    }
}

$settings.env['ANTHROPIC_BASE_URL'] = $baseUrl
$settings.env[$authEnv] = $apiKey

$modelEnvNames = @(
    'ANTHROPIC_MODEL',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'ANTHROPIC_DEFAULT_SONNET_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL'
)
foreach ($name in $modelEnvNames) {
    if ($settings.env.ContainsKey($name)) {
        $settings.env.Remove($name)
    }
}

$model = Get-ProfileValue -Map $profileConfig -Names @('model', 'anthropicModel')
if ($model) {
    $settings.env['ANTHROPIC_MODEL'] = $model
}

$haikuModel = Get-ProfileValue -Map $profileConfig -Names @('haikuModel', 'defaultHaikuModel')
$sonnetModel = Get-ProfileValue -Map $profileConfig -Names @('sonnetModel', 'defaultSonnetModel')
$opusModel = Get-ProfileValue -Map $profileConfig -Names @('opusModel', 'defaultOpusModel')
if ($haikuModel) { $settings.env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = $haikuModel }
if ($sonnetModel) { $settings.env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = $sonnetModel }
if ($opusModel) { $settings.env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = $opusModel }

if ($profileConfig.ContainsKey('extraEnv') -and $profileConfig.extraEnv) {
    foreach ($entry in $profileConfig.extraEnv.GetEnumerator()) {
        $settings.env[$entry.Key] = "$($entry.Value)"
    }
}

$managedEnvNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in @('ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY')) {
    [void]$managedEnvNames.Add($name)
}
foreach ($name in $modelEnvNames) {
    [void]$managedEnvNames.Add($name)
}
foreach ($entry in $settings.env.GetEnumerator()) {
    [void]$managedEnvNames.Add($entry.Key)
}

$originalEnv = @{}
foreach ($name in $managedEnvNames) {
    $current = Get-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
    if ($current) {
        $originalEnv[$name] = $current.Value
    }
    else {
        $originalEnv[$name] = $null
    }
}

$tempSettingsPath = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-profile-{0}-{1}.settings.json" -f $Profile, $PID)

try {
    foreach ($name in $managedEnvNames) {
        if ($settings.env.ContainsKey($name) -and $null -ne $settings.env[$name]) {
            Set-Item -LiteralPath "Env:\$name" -Value "$($settings.env[$name])"
        }
        else {
            Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
        }
    }

    # Only write env overrides to avoid Claude Code merge flattening hooks arrays
    Write-Utf8NoBomJson -Path $tempSettingsPath -Value @{ env = $settings.env }

    $launchArgs = @('--setting-sources', 'project,user,local', '--settings', $tempSettingsPath)
    $cliModel = Get-ProfileValue -Map $profileConfig -Names @('cliModel', 'claudeCliModel')
    if ($cliModel -and -not (Test-HasCliModelArg -Args $ClaudeArgs)) {
        $launchArgs += @('--model', "$cliModel")
    }
    $launchArgs += $ClaudeArgs

    & claude @launchArgs
    exit $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $tempSettingsPath -ErrorAction SilentlyContinue
    foreach ($entry in $originalEnv.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            Remove-Item -LiteralPath "Env:\$($entry.Key)" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -LiteralPath "Env:\$($entry.Key)" -Value "$($entry.Value)"
        }
    }
}
