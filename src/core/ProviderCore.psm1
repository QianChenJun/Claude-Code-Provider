#Requires -Version 5.1

<#
.SYNOPSIS
    ProviderProfiles 核心模块 —— 为所有 AI CLI 工具提供供应商切换共享逻辑。
.DESCRIPTION
    提供 JSON/TOML 工具函数、Profile 管理、环境变量会话管理、交互菜单、
    快捷命令同步，以及工具注册表。
    各工具（Claude Code、Codex CLI 等）通过 Register-ProviderTool 注册后，
    即可复用全部核心能力。
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ============================================================
#  Module State
# ============================================================
$script:ToolRegistry = @{}

# ============================================================
#  JSON Utilities
# ============================================================

function Read-JsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "配置文件不存在：$Path"
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text  = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ([string]::IsNullOrWhiteSpace($text)) { return @{} }
    return Convert-JsonObjectToHashtable -Value ($text | ConvertFrom-Json)
}

function Convert-JsonObjectToHashtable {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) { return $null }

    if ($Value -is [System.Collections.IDictionary]) {
        $map = @{}
        foreach ($key in $Value.Keys) {
            $map[$key] = Convert-JsonObjectToHashtable -Value $Value[$key]
        }
        return $map
    }

    if ($Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [string] -and $Value -isnot [byte[]]) {
        $items = @()
        foreach ($item in $Value) {
            $items += Convert-JsonObjectToHashtable -Value $item
        }
        return $items
    }

    if ($Value.GetType().Name -eq 'PSCustomObject' -and
        @($Value.PSObject.Properties).Count -gt 0) {
        $map = @{}
        foreach ($prop in $Value.PSObject.Properties) {
            $map[$prop.Name] = Convert-JsonObjectToHashtable -Value $prop.Value
        }
        return $map
    }

    return $Value
}

function Write-Utf8NoBomJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 40
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

# ============================================================
#  TOML Serialization (for Codex -c overrides)
# ============================================================

function ConvertTo-TomlLiteral {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Value)

    if ($Value -is [bool]) {
        return ($(if ($Value) { 'true' } else { 'false' }))
    }
    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or
        $Value -is [int64] -or $Value -is [uint16] -or $Value -is [uint32] -or
        $Value -is [uint64] -or $Value -is [single] -or $Value -is [double] -or
        $Value -is [decimal]) {
        return [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [string]) {
        $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
        return "`"$escaped`""
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = @()
        foreach ($key in ($Value.Keys | Sort-Object)) {
            $escapedKey = "$key" -replace '[^A-Za-z0-9_]', '_'
            $parts += "$escapedKey = $(ConvertTo-TomlLiteral -Value $Value[$key])"
        }
        return "{ $($parts -join ', ') }"
    }
    if ($Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [string] -and $Value -isnot [byte[]]) {
        $items = @()
        foreach ($item in $Value) {
            $items += (ConvertTo-TomlLiteral -Value $item)
        }
        return "[$($items -join ', ')]"
    }
    $escaped = "$Value".Replace('\', '\\').Replace('"', '\"')
    return "`"$escaped`""
}

# ============================================================
#  Profile Data Helpers
# ============================================================

function Get-ProfileValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Map,
        [Parameter(Mandatory)][string[]]$Names
    )
    foreach ($name in $Names) {
        if ($Map.ContainsKey($name) -and $null -ne $Map[$name] -and "$($Map[$name])" -ne '') {
            return $Map[$name]
        }
    }
    return $null
}

function Test-HasCliModelArg {
    [CmdletBinding()]
    param([string[]]$Args)

    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq '--model' -or $Args[$i] -eq '-m') { return $true }
        if ($Args[$i] -like '--model=*') { return $true }
    }
    return $false
}

function Resolve-ApiKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Profile,
        [Parameter(Mandatory)][string]$ProfileId
    )

    $apiKey    = Get-ProfileValue -Map $Profile -Names @('apiKey', 'token', 'key')
    $apiKeyEnv = Get-ProfileValue -Map $Profile -Names @('apiKeyEnv', 'tokenEnv', 'keyEnv')
    $apiKeyFile = Get-ProfileValue -Map $Profile -Names @('apiKeyFile', 'tokenFile', 'keyFile')

    if ($apiKeyEnv) {
        $fromEnv = [Environment]::GetEnvironmentVariable($apiKeyEnv, 'User')
        if (-not $fromEnv) { $fromEnv = [Environment]::GetEnvironmentVariable($apiKeyEnv, 'Process') }
        if (-not $fromEnv) { $fromEnv = [Environment]::GetEnvironmentVariable($apiKeyEnv, 'Machine') }
        if ($fromEnv) { $apiKey = $fromEnv }
    }

    if ($apiKeyFile) {
        $expandedKeyFile = [Environment]::ExpandEnvironmentVariables($apiKeyFile)
        if (Test-Path -LiteralPath $expandedKeyFile) {
            $apiKey = ([System.Text.Encoding]::UTF8.GetString(
                [System.IO.File]::ReadAllBytes($expandedKeyFile)
            )).Trim()
        }
    }

    if (-not $apiKey) {
        throw "配置 '$ProfileId' 缺少 apiKey（检查了: apiKey 字段、apiKeyEnv='$apiKeyEnv'、apiKeyFile='$apiKeyFile'）。请在 providers.json 中设置 apiKey、apiKeyEnv 或 apiKeyFile。"
    }

    return $apiKey
}

# ============================================================
#  Display Helpers
# ============================================================

function Write-ProfileTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Profiles,
        [Parameter(Mandatory)][hashtable]$Tool
    )

    $prefix = $Tool.commandPrefix

    $Profiles.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $item = $_.Value
        [PSCustomObject]@{
            '配置ID'   = $_.Name
            '推荐命令' = "$prefix-$($_.Name)"
            '兼容命令' = $(if ($item.shortcut) { $item.shortcut } else { "$($_.Name)-$($Tool.defaultShortcutSuffix)" })
            '名称'     = $item.displayName
            '接口地址' = $item.baseUrl
            '默认模型' = $item.model
        }
    } | Format-Table -AutoSize
}

function Write-Usage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Profiles,
        [Parameter(Mandatory)][hashtable]$Tool
    )

    $prefix = $Tool.commandPrefix

    Write-Output "用法："
    Write-Output "  $prefix                         # 打开交互菜单"
    Write-Output "  $prefix <profile> [$($Tool.name) args]"
    Write-Output "  $prefix-list"
    Write-Output "  $prefix-<profile> [$($Tool.name) args]"
    Write-Output "  $prefix-sync"
    Write-Output "  $prefix-manager"
    Write-Output ""
    Write-Output "可用配置："
    Write-ProfileTable -Profiles $Profiles -Tool $Tool
}

# ============================================================
#  Interactive Menu
# ============================================================

function Select-ProfileFromMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Profiles,
        [Parameter(Mandatory)][hashtable]$Tool,
        [string]$SyncScript,
        [string]$ManageScript
    )

    $prefix = $Tool.commandPrefix

    while ($true) {
        $entries = @($Profiles.GetEnumerator() | Sort-Object Name)
        Write-Host ""
        Write-Host "$($Tool.displayName) Provider 配置"
        Write-Host "请选择配置："

        for ($i = 0; $i -lt $entries.Count; $i++) {
            $id      = $entries[$i].Name
            $profile = $entries[$i].Value
            $name    = $(Get-ProfileValue -Map $profile -Names @('displayName'))
            if (-not $name) { $name = $id }
            Write-Host ("  {0}. {1,-18} {2}" -f ($i + 1), "$prefix-$id", $name)
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
            if ($index -ge 0 -and $index -lt $entries.Count) { return $entries[$index].Name }
            Write-Warning "无效选择：$choice（请输入编号、配置 ID，或 L/S/M/H/Q）"
            continue
        }

        if ($choice -match '^(l|list|ls|列表|查看)$') {
            Write-ProfileTable -Profiles $Profiles -Tool $Tool | Out-Host
            continue
        }

        if ($choice -match '^(s|sync|同步)$') {
            if ($SyncScript) { & $SyncScript | Out-Host }
            continue
        }

        if ($choice -match '^(m|manager|manage|管理)$') {
            if ($ManageScript) { & $ManageScript | Out-Host }
            continue
        }

        if ($choice -match '^(h|help|usage|帮助)$') {
            Write-Usage -Profiles $Profiles -Tool $Tool | Out-Host
            continue
        }

        if ($Profiles.ContainsKey($choice)) { return $choice }
        Write-Warning "未知选择：$choice（可用配置 ID：$(($entries | ForEach-Object { $_.Name }) -join ', ')）"
    }
}

# ============================================================
#  Provider Tool Registry
# ============================================================

function Register-ProviderTool {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$ToolConfig)

    $requiredKeys = @('name', 'commandPrefix', 'configFileName', 'displayName', 'defaultShortcutSuffix', 'executable', 'launcher')
    foreach ($key in $requiredKeys) {
        if (-not $ToolConfig.ContainsKey($key) -or $null -eq $ToolConfig[$key]) {
            throw "工具配置缺少必需字段：$key"
        }
    }

    if ($script:ToolRegistry.ContainsKey($ToolConfig.name)) {
        throw "工具 '$($ToolConfig.name)' 已注册"
    }

    $script:ToolRegistry[$ToolConfig.name] = $ToolConfig
}

function Get-ProviderTool {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    if (-not $script:ToolRegistry.ContainsKey($Name)) {
        throw "未知工具：$Name。已注册工具：$($script:ToolRegistry.Keys -join ', ')"
    }
    return $script:ToolRegistry[$Name]
}

function Get-ProviderTools {
    [CmdletBinding()]
    param()
    return $script:ToolRegistry
}

# ============================================================
#  Environment Session Management
# ============================================================

function New-EnvSession {
    [CmdletBinding()]
    param([string[]]$ManagedKeys = @())

    $session = [ordered]@{
        ManagedKeys  = [System.Collections.Generic.HashSet[string]]::new(
                           [StringComparer]::OrdinalIgnoreCase)
        OriginalEnvs = @{}
    }

    foreach ($key in $ManagedKeys) {
        [void]$session.ManagedKeys.Add($key)
    }

    foreach ($name in $session.ManagedKeys) {
        $current = Get-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
        $session.OriginalEnvs[$name] = $(if ($current) { $current.Value } else { $null })
    }

    return $session
}

function Add-EnvSessionKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Key
    )

    [void]$Session.ManagedKeys.Add($Key)
    $current = Get-Item -LiteralPath "Env:\$Key" -ErrorAction SilentlyContinue
    $Session.OriginalEnvs[$Key] = $(if ($current) { $current.Value } else { $null })
}

function Set-EnvSessionValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Key,
        [string]$Value
    )

    if (-not $Session.ManagedKeys.Contains($Key)) {
        Add-EnvSessionKey -Session $Session -Key $Key
    }

    if ($null -ne $Value) {
        Set-Item -LiteralPath "Env:\$Key" -Value $Value
    }
}

function Restore-EnvSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Session)

    foreach ($entry in $Session.OriginalEnvs.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            Remove-Item -LiteralPath "Env:\$($entry.Key)" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -LiteralPath "Env:\$($entry.Key)" -Value "$($entry.Value)"
        }
    }
}

# ============================================================
#  Provider Session Runner
# ============================================================

function Invoke-ProviderSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToolName,
        [Parameter(Mandatory)][string]$ProfileId,
        [string[]]$RemainingArgs = @()
    )

    $tool = Get-ProviderTool -Name $ToolName

    $configPath = $tool.configPath

    $config = Read-JsonFile -Path $configPath
    if (-not $config.ContainsKey('profiles')) {
        throw "配置文件必须包含 profiles 对象：$configPath"
    }

    if (-not $config.profiles.ContainsKey($ProfileId)) {
        throw "未知配置：$ProfileId。可用配置：$($config.profiles.Keys -join ', ')"
    }

    $profile  = $config.profiles[$ProfileId]
    $apiKey   = Resolve-ApiKey -Profile $profile -ProfileId $ProfileId

    $managedKeys = [System.Collections.Generic.List[string]]::new()
    $toolKeys = if ($tool.ContainsKey('envKeys') -and $tool.envKeys) { $tool.envKeys } else { @() }
    foreach ($key in $toolKeys) { $managedKeys.Add($key) }

    $session = New-EnvSession -ManagedKeys $managedKeys

    try {
        $launchResult = & $tool.launcher $profile $apiKey $ProfileId $RemainingArgs $session

        if ($launchResult.EnvVars) {
            foreach ($entry in $launchResult.EnvVars.GetEnumerator()) {
                Set-EnvSessionValue -Session $session -Key $entry.Key -Value "$($entry.Value)"
            }
        }

        $exe  = $tool.executable
        $args = $launchResult.LaunchArgs

        & $exe @args
        exit $LASTEXITCODE
    }
    finally {
        if ($launchResult -and $launchResult.TempFile) {
            Remove-Item -LiteralPath $launchResult.TempFile -ErrorAction SilentlyContinue
        }
        Restore-EnvSession -Session $session
    }
}

# ============================================================
#  Shortcut Sync
# ============================================================

function Sync-ToolShortcuts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ToolName)

    $tool = Get-ProviderTool -Name $ToolName

    $deployRoot = $tool.configPath | Split-Path -Parent
    $configPath = $tool.configPath
    $binDir     = Join-Path $deployRoot 'bin'

    $prefix             = $tool.commandPrefix
    $suffix             = $tool.defaultShortcutSuffix
    $encoding           = [System.Text.UTF8Encoding]::new($false)
    $manifestPath       = Join-Path $binDir "$prefix-generated-shortcuts.json"
    $generatedPaths     = [System.Collections.Generic.List[string]]::new()
    $usedShortcutNames  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $reservedProfileIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $reservedCmdNames   = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($name in @('list', 'ls', 'help', 'usage', 'sync', 'manager', 'manage')) {
        [void]$reservedProfileIds.Add($name)
    }
    foreach ($name in @($prefix, "$prefix-list", "$prefix-sync", "$prefix-manager", "provider-$($tool.name)")) {
        [void]$reservedCmdNames.Add($name)
        [void]$usedShortcutNames.Add($name.ToLowerInvariant())
    }

    if ($tool.ContainsKey('legacyCommands') -and $tool.legacyCommands) {
        foreach ($name in $tool.legacyCommands) {
            [void]$reservedCmdNames.Add($name)
            [void]$usedShortcutNames.Add($name.ToLowerInvariant())
        }
    }

    function Write-Shim {
        param([string]$Path, [string]$Content)
        [System.IO.File]::WriteAllText($Path, $Content, $encoding)
        [void]$generatedPaths.Add([System.IO.Path]::GetFullPath($Path))
    }

    function Assert-ShortcutName {
        param([string]$Name)
        if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$') {
            throw "快捷命令名称不合法：$Name"
        }
    }

    function Register-ShortcutName {
        param([string]$Name, [string]$Owner)
        Assert-ShortcutName -Name $Name
        if ($reservedCmdNames.Contains($Name)) {
            throw "快捷命令与内置命令冲突：$Name"
        }
        $key = $Name.ToLowerInvariant()
        if (-not $usedShortcutNames.Add($key)) {
            throw "快捷命令重复：$Name（来源：$Owner）"
        }
    }

    New-Item -ItemType Directory -Force -Path $binDir | Out-Null

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "配置文件不存在：$configPath"
    }

    $config = Read-JsonFile -Path $configPath

    $invokeScript = $tool.invokeScript
    $syncScript   = $tool.syncScript
    $manageScript = $tool.manageScript

    Write-Shim -Path (Join-Path $binDir "provider-$($tool.name).ps1") -Content @"
#!/usr/bin/env pwsh
& '$invokeScript' @args
exit `$LASTEXITCODE
"@

    Write-Shim -Path (Join-Path $binDir "$prefix.ps1") -Content @"
#!/usr/bin/env pwsh
& '$invokeScript' @args
exit `$LASTEXITCODE
"@

    Write-Shim -Path (Join-Path $binDir "$prefix-list.ps1") -Content @"
#!/usr/bin/env pwsh
& '$invokeScript' -List @args
exit `$LASTEXITCODE
"@

    Write-Shim -Path (Join-Path $binDir "$prefix-sync.ps1") -Content @"
#!/usr/bin/env pwsh
& '$syncScript' @args
exit `$LASTEXITCODE
"@

    Write-Shim -Path (Join-Path $binDir "$prefix-manager.ps1") -Content @"
#!/usr/bin/env pwsh
& '$manageScript' @args
exit `$LASTEXITCODE
"@

    if ($tool.ContainsKey('legacyCommands') -and $tool.legacyCommands) {
        foreach ($legacy in $tool.legacyCommands) {
            Write-Shim -Path (Join-Path $binDir "$legacy.ps1") -Content @"
#!/usr/bin/env pwsh
& '$invokeScript' @args
exit `$LASTEXITCODE
"@
        }
    }

    Write-Output "已同步：$prefix / $prefix-list / $prefix-sync / $prefix-manager"

    foreach ($entry in $config.profiles.GetEnumerator()) {
        $id      = $entry.Key
        $profile = $entry.Value

        if ($reservedProfileIds.Contains($id.ToLowerInvariant())) {
            throw "配置 ID 与内置菜单命令冲突：$id"
        }
        Assert-ShortcutName -Name $id

        $shortcut = Get-ProfileValue -Map $profile -Names @('shortcut')
        if (-not $shortcut) { $shortcut = "$id-$suffix" }
        # 注册 shortcut（如 mi-claude），与 legacy 命令重名时跳过
        if (-not $usedShortcutNames.Contains($shortcut.ToLowerInvariant())) {
            Register-ShortcutName -Name $shortcut -Owner $id
        }

        $prefixedCmd = "$prefix-$id"
        if (-not $usedShortcutNames.Contains($prefixedCmd.ToLowerInvariant())) {
            Register-ShortcutName -Name $prefixedCmd -Owner $id
        }

        # 配置 ID 直呼快捷命令（如 mi / ds / gpt），配置 ID 唯一，无需前后缀
        if (-not $usedShortcutNames.Contains($id.ToLowerInvariant())) {
            Register-ShortcutName -Name $id -Owner $id
        }

        $shortcutContent = @"
#!/usr/bin/env pwsh
& '$invokeScript' -Profile '$id' @args
exit `$LASTEXITCODE
"@

        Write-Shim -Path (Join-Path $binDir "$shortcut.ps1") -Content $shortcutContent
        Write-Shim -Path (Join-Path $binDir "$prefixedCmd.ps1") -Content $shortcutContent
        Write-Shim -Path (Join-Path $binDir "$id.ps1") -Content $shortcutContent

        Write-Output "已同步：$id / $shortcut / $prefixedCmd"
    }

    # Clean up stale shortcuts
    $nextPathSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $generatedPaths) { [void]$nextPathSet.Add($path) }

    if (Test-Path -LiteralPath $manifestPath) {
        $previousText   = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($manifestPath))
        $previousPaths  = @($previousText | ConvertFrom-Json)
        $binFullPath    = [System.IO.Path]::GetFullPath($binDir).TrimEnd('\') + '\'
        foreach ($prevPath in $previousPaths) {
            if (-not $prevPath) { continue }
            $fullPrev = [System.IO.Path]::GetFullPath("$prevPath")
            if ($fullPrev.StartsWith($binFullPath, [System.StringComparison]::OrdinalIgnoreCase) -and
                -not $nextPathSet.Contains($fullPrev) -and
                (Test-Path -LiteralPath $fullPrev)) {
                Remove-Item -LiteralPath $fullPrev -Force
                Write-Output "已移除旧快捷命令：$([System.IO.Path]::GetFileNameWithoutExtension($fullPrev))"
            }
        }
    }

    $manifestJson = $generatedPaths | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($manifestPath, $manifestJson, $encoding)
}

# ============================================================
#  Module Import Helper
# ============================================================

function Import-ProviderCore {
    [CmdletBinding()]
    param()

    $corePath = $null

    # Strategy 1: Relative to script (works in deployment: ~/.claude/bin -> ~/.claude/provider-profiles/src/core/)
    $candidate = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\core\ProviderCore.psm1'
    if (Test-Path -LiteralPath $candidate) {
        $corePath = [System.IO.Path]::GetFullPath($candidate)
    }

    # Strategy 2: Walk up from script directory
    if (-not $corePath) {
        $dir = Split-Path -Parent $PSScriptRoot
        for ($i = 0; $i -lt 5; $i++) {
            $candidate = Join-Path $dir 'src\core\ProviderCore.psm1'
            if (Test-Path -LiteralPath $candidate) {
                $corePath = [System.IO.Path]::GetFullPath($candidate)
                break
            }
            $parent = Split-Path -Parent $dir
            if (-not $parent -or $parent -eq $dir) { break }
            $dir = $parent
        }
    }

    # Strategy 3: Environment variable
    if (-not $corePath -and $env:PROVIDER_CORE_MODULE) {
        $candidate = $env:PROVIDER_CORE_MODULE
        if (Test-Path -LiteralPath $candidate) {
            $corePath = [System.IO.Path]::GetFullPath($candidate)
        }
    }

    if (-not $corePath) {
        throw "找不到 ProviderCore.psm1。请设置环境变量 PROVIDER_CORE_MODULE 指向模块路径。"
    }

    Import-Module $corePath -Force -DisableNameChecking
}

# ============================================================
#  Built-in Tool Registration (user-home absolute paths)
# ============================================================

$script:UserHome = $env:USERPROFILE

# Claude Code tool — only register if not already present
if (-not $script:ToolRegistry.ContainsKey('claude')) {
    $claudeRoot = Join-Path $script:UserHome '.claude\provider-profiles'
    Register-ProviderTool @{
        name                 = 'claude'
        commandPrefix        = 'ccp'
        configFileName       = 'providers.json'
        displayName          = 'Claude Code'
        defaultShortcutSuffix = 'claude'
        executable           = 'claude'
        profileRoot          = '.claude\provider-profiles'
        legacyCommands       = @('mi-claude', 'ds-claude', 'provider-claude', 'claude-profile-manager', 'sync-claude-profiles')
        envKeys              = @('ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY',
                                 'ANTHROPIC_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL',
                                 'ANTHROPIC_DEFAULT_SONNET_MODEL', 'ANTHROPIC_DEFAULT_OPUS_MODEL')
        configPath           = (Join-Path $claudeRoot 'providers.json')
        invokeScript         = (Join-Path $claudeRoot 'src\tools\claude\Invoke-ClaudeProvider.ps1')
        syncScript           = (Join-Path $claudeRoot 'src\tools\claude\Sync-ClaudeShortcuts.ps1')
        manageScript         = (Join-Path $claudeRoot 'src\tools\claude\Manage-ClaudeUI.ps1')
        launcher             = {
            param($Profile, $ApiKey, $ProfileId, $RemainingArgs, $Session)

            $userSettingsPath = Join-Path $script:UserHome '.claude\settings.json'
            $settings = @{}
            if (Test-Path -LiteralPath $userSettingsPath) {
                $settings = Read-JsonFile -Path $userSettingsPath
            }
            if (-not $settings.ContainsKey('env') -or $null -eq $settings.env) {
                $settings.env = @{}
            }

            $authEnv = Get-ProfileValue -Map $Profile -Names @('authEnv')
            if (-not $authEnv) { $authEnv = 'ANTHROPIC_AUTH_TOKEN' }

            $clearOther = $true
            if ($Profile.ContainsKey('clearOtherAuthEnv')) {
                $clearOther = [bool]$Profile.clearOtherAuthEnv
            }
            if ($clearOther) {
                foreach ($name in @('ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY')) {
                    if ($name -ne $authEnv -and $settings.env.ContainsKey($name)) {
                        $settings.env.Remove($name)
                    }
                }
            }

            $settings.env['ANTHROPIC_BASE_URL'] = $Profile.baseUrl
            $settings.env[$authEnv] = $ApiKey

            $modelEnvNames = @('ANTHROPIC_MODEL', 'ANTHROPIC_DEFAULT_HAIKU_MODEL',
                               'ANTHROPIC_DEFAULT_SONNET_MODEL', 'ANTHROPIC_DEFAULT_OPUS_MODEL')
            foreach ($name in $modelEnvNames) {
                if ($settings.env.ContainsKey($name)) { $settings.env.Remove($name) }
            }

            $model = Get-ProfileValue -Map $Profile -Names @('model', 'anthropicModel')
            if ($model) { $settings.env['ANTHROPIC_MODEL'] = $model }

            $haikuModel  = Get-ProfileValue -Map $Profile -Names @('haikuModel', 'defaultHaikuModel')
            $sonnetModel = Get-ProfileValue -Map $Profile -Names @('sonnetModel', 'defaultSonnetModel')
            $opusModel   = Get-ProfileValue -Map $Profile -Names @('opusModel', 'defaultOpusModel')
            if ($haikuModel)  { $settings.env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = $haikuModel }
            if ($sonnetModel) { $settings.env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = $sonnetModel }
            if ($opusModel)   { $settings.env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = $opusModel }

            if ($Profile.ContainsKey('extraEnv') -and $Profile.extraEnv) {
                foreach ($entry in $Profile.extraEnv.GetEnumerator()) {
                    $settings.env[$entry.Key] = "$($entry.Value)"
                }
            }

            $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "claude-profile-$ProfileId-$PID.settings.json"
            Write-Utf8NoBomJson -Path $tempPath -Value @{ env = $settings.env }

            $launchArgs = @('--setting-sources', 'project,user,local', '--settings', $tempPath)
            $cliModel = Get-ProfileValue -Map $Profile -Names @('cliModel', 'claudeCliModel')
            if ($cliModel -and -not (Test-HasCliModelArg -Args $RemainingArgs)) {
                $launchArgs += @('--model', "$cliModel")
            }
            $launchArgs += $RemainingArgs

            return @{
                LaunchArgs = $launchArgs
                EnvVars    = $settings.env
                TempFile   = $tempPath
            }
        }
    }
}

# Codex CLI tool — only register if not already present
if (-not $script:ToolRegistry.ContainsKey('codex')) {
    $codexRoot = Join-Path $script:UserHome '.codex\provider-profiles'
    Register-ProviderTool @{
        name                 = 'codex'
        commandPrefix        = 'cdp'
        configFileName       = 'providers.json'
        displayName          = 'Codex CLI'
        defaultShortcutSuffix = 'codex'
        executable           = 'codex'
        profileRoot          = '.codex\provider-profiles'
        legacyCommands       = @('mi-codex', 'ds-codex', 'provider-codex', 'codex-profile-manager', 'sync-codex-profiles')
        envKeys              = @()
        configPath           = (Join-Path $codexRoot 'providers.json')
        invokeScript         = (Join-Path $codexRoot 'src\tools\codex\Invoke-CodexProvider.ps1')
        syncScript           = (Join-Path $codexRoot 'src\tools\codex\Sync-CodexShortcuts.ps1')
        manageScript         = (Join-Path $codexRoot 'src\tools\codex\Manage-CodexUI.ps1')
        launcher             = {
            param($Profile, $ApiKey, $ProfileId, $RemainingArgs, $Session)

            $wireApi = Get-ProfileValue -Map $Profile -Names @('wireApi')
            if (-not $wireApi) { $wireApi = 'responses' }
            if ($wireApi -ne 'responses') {
                throw "当前仅支持 Codex 官方文档支持的 responses provider：$ProfileId"
            }

            $safeProfile = (($ProfileId -replace '[^A-Za-z0-9_]', '_').Trim('_'))
            $providerId  = "cdp_$safeProfile"
            $tempKeyEnv  = "CODEX_PROVIDER_TOKEN_$($safeProfile.ToUpperInvariant())"

            Add-EnvSessionKey -Session $Session -Key $tempKeyEnv

            $providerName = Get-ProfileValue -Map $Profile -Names @('providerName', 'name', 'displayName')
            if (-not $providerName) { $providerName = $ProfileId }

            $overrides = @()
            $overrides += @('-c', "model_provider=$providerId")
            $overrides += @('-c', "model_providers.$providerId.name=$providerName")
            $overrides += @('-c', "model_providers.$providerId.base_url=$($Profile.baseUrl)")
            $overrides += @('-c', "model_providers.$providerId.wire_api=$wireApi")
            $overrides += @('-c', "model_providers.$providerId.env_key=$tempKeyEnv")

            $model = Get-ProfileValue -Map $Profile -Names @('model')
            if ($model -and -not (Test-HasCliModelArg -Args $RemainingArgs)) {
                $overrides += @('-c', "model=$model")
            }

            $optFields = @{
                modelContextWindow    = 'model_context_window'
                modelReasoningEffort  = 'model_reasoning_effort'
                modelReasoningSummary = 'model_reasoning_summary'
                modelVerbosity        = 'model_verbosity'
            }
            foreach ($entry in $optFields.GetEnumerator()) {
                $val = Get-ProfileValue -Map $Profile -Names @($entry.Key)
                if ($null -ne $val) { $overrides += @('-c', "$($entry.Value)=$val") }
            }

            $providerOptFields = @{
                supportsWebsockets  = 'supports_websockets'
                requestMaxRetries   = 'request_max_retries'
                streamMaxRetries    = 'stream_max_retries'
                streamIdleTimeoutMs = 'stream_idle_timeout_ms'
            }
            foreach ($entry in $providerOptFields.GetEnumerator()) {
                $val = $null
                if ($Profile.ContainsKey($entry.Key) -and $null -ne $Profile[$entry.Key]) {
                    $val = $Profile[$entry.Key]
                }
                if ($null -ne $val) {
                    $overrides += @('-c', "model_providers.$providerId.$($entry.Value)=$(ConvertTo-TomlLiteral -Value $val)")
                }
            }

            $objectFields = @('queryParams', 'httpHeaders', 'envHttpHeaders')
            foreach ($fieldName in $objectFields) {
                if ($Profile.ContainsKey($fieldName) -and $Profile[$fieldName]) {
                    $tomlVal = ConvertTo-TomlLiteral -Value $Profile[$fieldName]
                    $overrides += @('-c', "model_providers.$providerId.$fieldName=$tomlVal")
                }
            }

            if ($Profile.ContainsKey('extraEnv') -and $Profile.extraEnv) {
                foreach ($entry in $Profile.extraEnv.GetEnumerator()) {
                    Add-EnvSessionKey -Session $Session -Key "$($entry.Key)"
                }
            }

            $launchArgs = $overrides + $RemainingArgs
            $envVars = @{ $tempKeyEnv = $ApiKey }
            if ($Profile.ContainsKey('extraEnv') -and $Profile.extraEnv) {
                foreach ($entry in $Profile.extraEnv.GetEnumerator()) {
                    $envVars["$($entry.Key)"] = "$($entry.Value)"
                }
            }

            return @{
                LaunchArgs = $launchArgs
                EnvVars    = $envVars
                TempFile   = $null
            }
        }
    }
}

# ============================================================
#  Exports
# ============================================================

Export-ModuleMember -Function @(
    'Read-JsonFile',
    'Convert-JsonObjectToHashtable',
    'Write-Utf8NoBomJson',
    'ConvertTo-TomlLiteral',
    'Get-ProfileValue',
    'Test-HasCliModelArg',
    'Resolve-ApiKey',
    'Write-ProfileTable',
    'Write-Usage',
    'Select-ProfileFromMenu',
    'Register-ProviderTool',
    'Get-ProviderTool',
    'Get-ProviderTools',
    'New-EnvSession',
    'Add-EnvSessionKey',
    'Set-EnvSessionValue',
    'Restore-EnvSession',
    'Invoke-ProviderSession',
    'Sync-ToolShortcuts',
    'Import-ProviderCore'
)