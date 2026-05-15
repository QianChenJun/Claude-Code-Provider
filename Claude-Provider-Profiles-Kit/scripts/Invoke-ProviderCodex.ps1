#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Profile,

    [switch]$List,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArgs
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $root 'providers.json'
$commandPrefix = 'cdp'

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

function Test-HasCodexModelArg {
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

function ConvertTo-TomlString {
    param([Parameter(Mandatory = $true)][string]$Value)
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    return '"' + $escaped + '"'
}

function ConvertTo-TomlInlineTableKey {
    param([Parameter(Mandatory = $true)][string]$Key)
    return ConvertTo-TomlString -Value $Key
}

function ConvertTo-TomlLiteral {
    param([Parameter(Mandatory = $true)]$Value)

    if ($Value -is [bool]) {
        return $(if ($Value) { 'true' } else { 'false' })
    }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
        $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        return ([System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture))
    }
    if ($Value -is [string]) {
        return ConvertTo-TomlString -Value $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = @()
        foreach ($key in ($Value.Keys | Sort-Object)) {
            $parts += ("{0} = {1}" -f (ConvertTo-TomlInlineTableKey -Key "$key"), (ConvertTo-TomlLiteral -Value $Value[$key]))
        }
        return "{ $($parts -join ', ') }"
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [byte[]]) {
        $parts = @()
        foreach ($item in $Value) {
            $parts += (ConvertTo-TomlLiteral -Value $item)
        }
        return "[{0}]" -f ($parts -join ', ')
    }
    return ConvertTo-TomlString -Value "$Value"
}

function Add-CodexOverride {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)]$Value
    )
    if ($null -eq $Value) {
        return
    }
    $script:configOverrides += @('-c', "$Key=$(ConvertTo-TomlLiteral -Value $Value)")
}

function Get-ConfigMapValue {
    param(
        [hashtable]$Map,
        [string[]]$Names
    )
    foreach ($name in $Names) {
        if ($Map.ContainsKey($name) -and $null -ne $Map[$name]) {
            return $Map[$name]
        }
    }
    return $null
}

function Get-SafeConfigKey {
    param([Parameter(Mandatory = $true)][string]$Value)
    return (($Value -replace '[^A-Za-z0-9_]', '_').Trim('_'))
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
                '兼容命令' = $(if ($item.shortcut) { $item.shortcut } else { "$($_.Name)-codex" })
                '名称' = $item.displayName
                '接口地址' = $item.baseUrl
                '默认模型' = $item.model
            }
        } |
        Format-Table -AutoSize
}

function Write-Usage {
    param([hashtable]$Profiles)

    Write-Output "用法："
    Write-Output "  $commandPrefix                        # 打开交互菜单"
    Write-Output "  $commandPrefix <profile> [codex args]"
    Write-Output "  $commandPrefix-list"
    Write-Output "  $commandPrefix-<profile> [codex args]"
    Write-Output "  $commandPrefix-sync"
    Write-Output "  $commandPrefix-manager"
    Write-Output ""
    Write-Output "兼容命令："
    Write-Output "  provider-codex -Profile <profile> [codex args]"
    Write-Output "  provider-codex -List"
    Write-Output "  codex-profile-manager"
    if ($Profiles.ContainsKey('mi')) {
        Write-Output "  mi-codex [codex args]"
    }
    Write-Output ""
    Write-Output "可用配置："
    Write-ProfileTable -Profiles $Profiles
}

function Select-ProfileFromMenu {
    param([hashtable]$Profiles)

    while ($true) {
        $entries = @($Profiles.GetEnumerator() | Sort-Object Name)
        Write-Host ""
        Write-Host "Codex Provider 配置"
        Write-Host "请选择配置："

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
            & (Join-Path $root 'Sync-CodexProfileShortcuts.ps1') | Out-Host
            continue
        }

        if ($choice -match '^(m|manager|manage|管理)$') {
            & (Join-Path $root 'Manage-CodexProfiles.ps1') | Out-Host
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
    & (Join-Path $root 'Sync-CodexProfileShortcuts.ps1')
    exit $LASTEXITCODE
}
elseif ($Profile -in @('manager', 'manage', '管理')) {
    & (Join-Path $root 'Manage-CodexProfiles.ps1')
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
$providerName = Get-ProfileValue -Map $profileConfig -Names @('providerName', 'name', 'displayName')
$wireApi = Get-ProfileValue -Map $profileConfig -Names @('wireApi')
$model = Get-ProfileValue -Map $profileConfig -Names @('model')
$apiKey = Get-ProfileValue -Map $profileConfig -Names @('apiKey', 'token', 'key')
$apiKeyEnv = Get-ProfileValue -Map $profileConfig -Names @('apiKeyEnv', 'tokenEnv', 'keyEnv')
$apiKeyFile = Get-ProfileValue -Map $profileConfig -Names @('apiKeyFile', 'tokenFile', 'keyFile')

if (-not $providerName) {
    $providerName = $Profile
}
if (-not $wireApi) {
    $wireApi = 'responses'
}
if ($wireApi -ne 'responses') {
    throw "当前仅支持 Codex 官方文档支持的 responses provider：$Profile"
}

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

$safeProfile = Get-SafeConfigKey -Value $Profile
if (-not $safeProfile) {
    throw "配置 '$Profile' 无法生成合法的 Codex provider key"
}
$providerId = "cdp_$safeProfile"
$tempApiKeyEnv = "CODEX_PROVIDER_TOKEN_$($safeProfile.ToUpperInvariant())"
$configOverrides = @()

Add-CodexOverride -Key 'model_provider' -Value $providerId
Add-CodexOverride -Key "model_providers.$providerId.name" -Value $providerName
Add-CodexOverride -Key "model_providers.$providerId.base_url" -Value $baseUrl
Add-CodexOverride -Key "model_providers.$providerId.wire_api" -Value $wireApi
Add-CodexOverride -Key "model_providers.$providerId.env_key" -Value $tempApiKeyEnv

if ($model -and -not (Test-HasCodexModelArg -Args $CodexArgs)) {
    Add-CodexOverride -Key 'model' -Value $model
}

$modelContextWindow = Get-ProfileValue -Map $profileConfig -Names @('modelContextWindow', 'contextWindow')
$modelReasoningEffort = Get-ProfileValue -Map $profileConfig -Names @('modelReasoningEffort')
$modelReasoningSummary = Get-ProfileValue -Map $profileConfig -Names @('modelReasoningSummary')
$modelVerbosity = Get-ProfileValue -Map $profileConfig -Names @('modelVerbosity')
$supportsWebsockets = Get-ConfigMapValue -Map $profileConfig -Names @('supportsWebsockets')
$requestMaxRetries = Get-ConfigMapValue -Map $profileConfig -Names @('requestMaxRetries')
$streamMaxRetries = Get-ConfigMapValue -Map $profileConfig -Names @('streamMaxRetries')
$streamIdleTimeoutMs = Get-ConfigMapValue -Map $profileConfig -Names @('streamIdleTimeoutMs')
$queryParams = Get-ConfigMapValue -Map $profileConfig -Names @('queryParams')
$httpHeaders = Get-ConfigMapValue -Map $profileConfig -Names @('httpHeaders')
$envHttpHeaders = Get-ConfigMapValue -Map $profileConfig -Names @('envHttpHeaders')
$extraEnv = Get-ConfigMapValue -Map $profileConfig -Names @('extraEnv')

if ($null -ne $modelContextWindow) { Add-CodexOverride -Key 'model_context_window' -Value $modelContextWindow }
if ($modelReasoningEffort) { Add-CodexOverride -Key 'model_reasoning_effort' -Value $modelReasoningEffort }
if ($modelReasoningSummary) { Add-CodexOverride -Key 'model_reasoning_summary' -Value $modelReasoningSummary }
if ($modelVerbosity) { Add-CodexOverride -Key 'model_verbosity' -Value $modelVerbosity }
if ($null -ne $supportsWebsockets) { Add-CodexOverride -Key "model_providers.$providerId.supports_websockets" -Value ([bool]$supportsWebsockets) }
if ($null -ne $requestMaxRetries) { Add-CodexOverride -Key "model_providers.$providerId.request_max_retries" -Value $requestMaxRetries }
if ($null -ne $streamMaxRetries) { Add-CodexOverride -Key "model_providers.$providerId.stream_max_retries" -Value $streamMaxRetries }
if ($null -ne $streamIdleTimeoutMs) { Add-CodexOverride -Key "model_providers.$providerId.stream_idle_timeout_ms" -Value $streamIdleTimeoutMs }
if ($queryParams) { Add-CodexOverride -Key "model_providers.$providerId.query_params" -Value $queryParams }
if ($httpHeaders) { Add-CodexOverride -Key "model_providers.$providerId.http_headers" -Value $httpHeaders }
if ($envHttpHeaders) { Add-CodexOverride -Key "model_providers.$providerId.env_http_headers" -Value $envHttpHeaders }

$managedEnvNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$managedEnvNames.Add($tempApiKeyEnv)

if ($extraEnv) {
    foreach ($entry in $extraEnv.GetEnumerator()) {
        [void]$managedEnvNames.Add("$($entry.Key)")
    }
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

try {
    Set-Item -LiteralPath "Env:\$tempApiKeyEnv" -Value "$apiKey"
    if ($extraEnv) {
        foreach ($entry in $extraEnv.GetEnumerator()) {
            Set-Item -LiteralPath "Env:\$($entry.Key)" -Value "$($entry.Value)"
        }
    }

    $launchArgs = @()
    $launchArgs += $configOverrides
    $launchArgs += $CodexArgs

    & codex @launchArgs
    exit $LASTEXITCODE
}
finally {
    foreach ($entry in $originalEnv.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            Remove-Item -LiteralPath "Env:\$($entry.Key)" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -LiteralPath "Env:\$($entry.Key)" -Value "$($entry.Value)"
        }
    }
}
