#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $root 'providers.json'
$binDir = Join-Path $env:USERPROFILE '.codex\bin'
$encoding = [System.Text.UTF8Encoding]::new($false)
$commandPrefix = 'cdp'
$manifestPath = Join-Path $binDir "$commandPrefix-generated-shortcuts.json"
$reservedProfileIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in @('list', 'ls', 'help', 'usage', 'sync', 'manager', 'manage')) {
    [void]$reservedProfileIds.Add($name)
}
$reservedShortcutNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in @($commandPrefix, "$commandPrefix-list", "$commandPrefix-sync", "$commandPrefix-manager", 'provider-codex', 'codex-profile-manager', 'sync-codex-profiles')) {
    [void]$reservedShortcutNames.Add($name)
}
$usedShortcutNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$generatedPaths = [System.Collections.Generic.List[string]]::new()

function Write-Shim {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Assert-ShortcutName {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$') {
        throw "快捷命令名称不合法：$Name"
    }
}

function Assert-ProfileId {
    param([Parameter(Mandatory = $true)][string]$Id)
    Assert-ShortcutName -Name $Id
    if ($reservedProfileIds.Contains($Id)) {
        throw "配置 ID 与内置菜单命令冲突：$Id"
    }
}

function Register-ShortcutName {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Owner
    )
    Assert-ShortcutName -Name $Name
    if ($reservedShortcutNames.Contains($Name)) {
        throw "快捷命令与内置命令冲突：$Name"
    }
    if (-not $usedShortcutNames.Add($Name)) {
        throw "快捷命令重复：$Name（来源：$Owner）"
    }
}

function Add-GeneratedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    [void]$generatedPaths.Add([System.IO.Path]::GetFullPath($Path))
}

Assert-ShortcutName -Name $commandPrefix

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "配置文件不存在：$configPath"
}

New-Item -ItemType Directory -Force -Path $binDir | Out-Null

$configText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($configPath))
$config = $configText | ConvertFrom-Json

Write-Shim -Path (Join-Path $binDir 'provider-codex.ps1') -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.codex\provider-profiles\Invoke-ProviderCodex.ps1'
& `$script @args
exit `$LASTEXITCODE
"@

Write-Shim -Path (Join-Path $binDir "$commandPrefix.ps1") -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.codex\provider-profiles\Invoke-ProviderCodex.ps1'
& `$script @args
exit `$LASTEXITCODE
"@

Write-Shim -Path (Join-Path $binDir "$commandPrefix-list.ps1") -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.codex\provider-profiles\Invoke-ProviderCodex.ps1'
& `$script -List @args
exit `$LASTEXITCODE
"@

Write-Shim -Path (Join-Path $binDir "$commandPrefix-sync.ps1") -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.codex\provider-profiles\Sync-CodexProfileShortcuts.ps1'
& `$script @args
exit `$LASTEXITCODE
"@

Write-Shim -Path (Join-Path $binDir "$commandPrefix-manager.ps1") -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.codex\provider-profiles\Manage-CodexProfiles.ps1'
& `$script @args
exit `$LASTEXITCODE
"@

Write-Shim -Path (Join-Path $binDir 'codex-profile-manager.ps1') -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.codex\provider-profiles\Manage-CodexProfiles.ps1'
& `$script @args
exit `$LASTEXITCODE
"@

Write-Output "已同步：$commandPrefix"
Write-Output "已同步：$commandPrefix-list"
Write-Output "已同步：$commandPrefix-sync"
Write-Output "已同步：$commandPrefix-manager"

foreach ($property in $config.profiles.PSObject.Properties) {
    $id = $property.Name
    $profile = $property.Value
    Assert-ProfileId -Id $id

    $shortcut = $profile.shortcut
    if (-not $shortcut) {
        $shortcut = "$id-codex"
    }
    Register-ShortcutName -Name $shortcut -Owner $id

    $prefixedShortcut = "$commandPrefix-$id"
    Register-ShortcutName -Name $prefixedShortcut -Owner $id

    $path = Join-Path $binDir "$shortcut.ps1"
    Write-Shim -Path $path -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.codex\provider-profiles\Invoke-ProviderCodex.ps1'
& `$script -Profile '$id' @args
exit `$LASTEXITCODE
"@
    Add-GeneratedPath -Path $path
    Write-Output "已同步：$shortcut"

    $prefixedPath = Join-Path $binDir "$prefixedShortcut.ps1"
    Write-Shim -Path $prefixedPath -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.codex\provider-profiles\Invoke-ProviderCodex.ps1'
& `$script -Profile '$id' @args
exit `$LASTEXITCODE
"@
    Add-GeneratedPath -Path $prefixedPath
    Write-Output "已同步：$prefixedShortcut"
}

$nextPathSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($path in $generatedPaths) {
    [void]$nextPathSet.Add($path)
}

if (Test-Path -LiteralPath $manifestPath) {
    $previousText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($manifestPath))
    $previousPaths = @($previousText | ConvertFrom-Json)
    $binFullPath = [System.IO.Path]::GetFullPath($binDir).TrimEnd('\') + '\'
    foreach ($previousPath in $previousPaths) {
        if (-not $previousPath) {
            continue
        }
        $fullPreviousPath = [System.IO.Path]::GetFullPath("$previousPath")
        if ($fullPreviousPath.StartsWith($binFullPath, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not $nextPathSet.Contains($fullPreviousPath) -and
            (Test-Path -LiteralPath $fullPreviousPath)) {
            Remove-Item -LiteralPath $fullPreviousPath -Force
            Write-Output "已移除旧快捷命令：$([System.IO.Path]::GetFileNameWithoutExtension($fullPreviousPath))"
        }
    }
}

$manifestJson = $generatedPaths | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, $encoding)
