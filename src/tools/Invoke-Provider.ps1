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
$runProfiles = $false
$setupProfileId = $null
$profilesArgs = @()

function Convert-ProfilesArgsToInvocation {
    param([Parameter(Mandatory)][object[]]$ArgumentList)

    $action = "$($ArgumentList[0])"
    $parameters = @{}

    for ($j = 1; $j -lt $ArgumentList.Count; $j++) {
        $arg = "$($ArgumentList[$j])"
        if (-not $arg.StartsWith('-')) {
            throw "profiles 参数必须使用命名参数：$arg"
        }

        $name = $null
        $value = $null
        $hasInlineValue = $false
        if ($arg -match '^-([^:=]+)[:=](.*)$') {
            $name = $Matches[1]
            $value = $Matches[2]
            $hasInlineValue = $true
        } else {
            $name = $arg.TrimStart('-')
        }

        switch ($name.ToLowerInvariant()) {
            'tool' {
                if (-not $hasInlineValue) {
                    if ($j + 1 -ge $ArgumentList.Count) { throw 'profiles 参数 -Tool 缺少值。' }
                    $j++
                    $value = "$($ArgumentList[$j])"
                }
                $parameters.Tool = $value
            }
            'outdir' {
                if (-not $hasInlineValue) {
                    if ($j + 1 -ge $ArgumentList.Count) { throw 'profiles 参数 -OutDir 缺少值。' }
                    $j++
                    $value = "$($ArgumentList[$j])"
                }
                $parameters.OutDir = $value
            }
            'indir' {
                if (-not $hasInlineValue) {
                    if ($j + 1 -ge $ArgumentList.Count) { throw 'profiles 参数 -InDir 缺少值。' }
                    $j++
                    $value = "$($ArgumentList[$j])"
                }
                $parameters.InDir = $value
            }
            'compress' {
                $parameters.Compress = if ($hasInlineValue) {
                    [System.Management.Automation.LanguagePrimitives]::ConvertTo($value, [bool])
                } else {
                    $true
                }
            }
            'force' {
                $parameters.Force = if ($hasInlineValue) {
                    [System.Management.Automation.LanguagePrimitives]::ConvertTo($value, [bool])
                } else {
                    $true
                }
            }
            default {
                throw "profiles 参数不支持：-$name"
            }
        }
    }

    return [pscustomobject]@{
        Action     = $action
        Parameters = $parameters
    }
}

for ($i = 0; $i -lt $ProviderArgs.Count; $i++) {
    $a = "$($ProviderArgs[$i])"
    if ($a -in @('list', 'ls', '-List'))     { $showList = $true }
    elseif ($a -in @('help', 'usage', '-Help')) { $showHelp = $true }
    elseif ($a -in @('profiles')) {
        $runProfiles = $true
        if ($i + 1 -lt $ProviderArgs.Count) {
            $profilesArgs = @($ProviderArgs[($i + 1)..($ProviderArgs.Count - 1)])
        }
        break
    }
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

if ($runProfiles) {
    if (-not $profilesArgs -or $profilesArgs.Count -eq 0 -or "$($profilesArgs[0])".StartsWith('-')) {
        $profilesArgs = @('list') + $profilesArgs
    }
    $hasToolArg = @($profilesArgs | Where-Object { "$_" -match '^-Tool([:=]|$)' }).Count -gt 0
    if (-not $hasToolArg) { $profilesArgs += @('-Tool', $ToolName) }

    $profilesScript = if ($tool.Contains('profilesScript') -and $tool.profilesScript) {
        $tool.profilesScript
    } else {
        Join-Path $PSScriptRoot 'Manage-ProviderProfiles.ps1'
    }
    if (-not (Test-Path -LiteralPath $profilesScript)) {
        $fallbackProfilesScript = Join-Path $PSScriptRoot 'Manage-ProviderProfiles.ps1'
        if (Test-Path -LiteralPath $fallbackProfilesScript) {
            $profilesScript = $fallbackProfilesScript
        } else {
            throw "找不到配置导入导出工具：$profilesScript"
        }
    }
    $profilesInvocation = Convert-ProfilesArgsToInvocation -ArgumentList $profilesArgs
    $profilesParameters = $profilesInvocation.Parameters
    $global:LASTEXITCODE = 0
    & $profilesScript $profilesInvocation.Action @profilesParameters
    exit $LASTEXITCODE
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
