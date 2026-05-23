#!/usr/bin/env pwsh
# Generic provider launcher — dot-sourced by tool-specific wrappers.
# The wrapper must set $ToolName before dot-sourcing.

$ErrorActionPreference = 'Stop'

if (-not $ToolName) { throw 'Internal error: $ToolName not set by wrapper script.' }

. (Join-Path $PSScriptRoot 'Import-Core.ps1')
Import-ProviderCore

$tool = Get-ProviderTool -Name $ToolName
$configPath = $tool.configPath

$profileId = $null
$remaining = @()
$showList = $false
$showHelp = $false
$runSetup = $false
$setupProfileId = $null

for ($i = 0; $i -lt $ProviderArgs.Count; $i++) {
    $a = "$($ProviderArgs[$i])"
    if ($a -in @('list', 'ls', '-List'))     { $showList = $true }
    elseif ($a -in @('help', 'usage', '-Help')) { $showHelp = $true }
    elseif ($a -in @('setup', 'add', 'configure', '-Setup')) {
        $runSetup = $true
        if ($i + 1 -lt $ProviderArgs.Count) {
            $next = "$($ProviderArgs[$i + 1])"
            if (-not $next.StartsWith('-')) { $i++; $setupProfileId = $next }
        }
    }
    elseif ($a -in @('sync'))                { & $tool.syncScript; exit $LASTEXITCODE }
    elseif ($a -in @('manager', 'manage'))   { & $tool.manageScript; exit $LASTEXITCODE }
    elseif ($a -eq '-Profile')               { if ($i + 1 -lt $ProviderArgs.Count) { $i++; if (-not $profileId) { $profileId = "$($ProviderArgs[$i])" } } }
    elseif (-not $a.StartsWith('-') -and -not $profileId) { $profileId = $a }
    else                                      { $remaining += $a }
}

if ($runSetup) { Invoke-ProviderSetup -ToolName $ToolName -ProfileId $setupProfileId; exit 0 }

$config = Read-JsonFile -Path $configPath
if (-not $config.Contains('profiles')) { throw '配置文件必须包含 profiles 对象' }

if ($showList) { Write-ProfileTable -Profiles $config.profiles -Tool $tool; exit 0 }
if ($showHelp) { Write-Usage -Profiles $config.profiles -Tool $tool; exit 0 }

if (-not $profileId) {
    $profileId = Select-ProfileFromMenu -Profiles $config.profiles -Tool $tool `
        -SyncScript $tool.syncScript -ManageScript $tool.manageScript
    if (-not $profileId) { exit 0 }
}

Invoke-ProviderSession -ToolName $ToolName -ProfileId $profileId -RemainingArgs $remaining
