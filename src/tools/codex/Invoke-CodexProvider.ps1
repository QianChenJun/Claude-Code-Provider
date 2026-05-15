#!/usr/bin/env pwsh
# Thin wrapper for codex provider launcher.
# Called by generated bin shims: & 'E:\Desktop\Claude-Provider-Profiles\src\tools\codex\Invoke-CodexProvider.ps1' @args
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\tools\Import-Core.ps1')
Import-ProviderCore

$tool = Get-ProviderTool -Name 'codex'
$configPath = $tool.configPath
$config = Read-JsonFile -Path $configPath
if (-not $config.ContainsKey('profiles')) { throw '配置文件必须包含 profiles 对象' }

# Parse args: first non-flag arg is profile, rest are passthrough
$profileId = $null
$remaining = @()

$showList = $false
$showHelp = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    $a = "$($args[$i])"
    if ($a -in @('list', 'ls'))              { $showList = $true }
    elseif ($a -in @('help', 'usage'))       { $showHelp = $true }
    elseif ($a -in @('sync'))                { & $tool.syncScript; exit $LASTEXITCODE }
    elseif ($a -in @('manager', 'manage'))   { & $tool.manageScript; exit $LASTEXITCODE }
    elseif (-not $a.StartsWith('-') -and -not $profileId) { $profileId = $a }
    else                                      { $remaining += $a }
}

if ($showList) { Write-ProfileTable -Profiles $config.profiles -Tool $tool; exit 0 }
if ($showHelp) { Write-Usage -Profiles $config.profiles -Tool $tool; exit 0 }

if (-not $profileId) {
    $profileId = Select-ProfileFromMenu -Profiles $config.profiles -Tool $tool 
        -SyncScript $tool.syncScript -ManageScript $tool.manageScript
    if (-not $profileId) { exit 0 }
}

Invoke-ProviderSession -ToolName 'codex' -ProfileId $profileId -RemainingArgs $remaining