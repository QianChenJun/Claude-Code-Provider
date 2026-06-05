#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$scriptPath = Join-Path $repoRoot 'src\tools\Manage-ProviderProfiles.ps1'
$exportHome = Join-Path ([System.IO.Path]::GetTempPath()) ("provider-transfer-export-" + [guid]::NewGuid().ToString('N'))
$importHome = Join-Path ([System.IO.Path]::GetTempPath()) ("provider-transfer-import-" + [guid]::NewGuid().ToString('N'))
$zipImportHome = Join-Path ([System.IO.Path]::GetTempPath()) ("provider-transfer-zip-import-" + [guid]::NewGuid().ToString('N'))
$backupDir = Join-Path ([System.IO.Path]::GetTempPath()) ("provider-transfer-backup-" + [guid]::NewGuid().ToString('N'))
$zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("provider-transfer-backup-" + [guid]::NewGuid().ToString('N') + '.zip')
$originalUserProfile = $env:USERPROFILE
$originalClaudeOneApiKey = $env:CLAUDE_ONE_API_KEY

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Test-JsonProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 20) + "`n"), $encoding)
}

try {
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "未找到导入导出脚本：$scriptPath"
    }

    New-Item -ItemType Directory -Force -Path $exportHome, $importHome, $zipImportHome, $backupDir | Out-Null
    $env:USERPROFILE = $exportHome
    $env:CLAUDE_ONE_API_KEY = 'process-only-claude-key-for-test'

    Write-JsonFile -Path (Join-Path $exportHome '.claude\provider-profiles\providers.json') -Value @{
        version = 1
        profiles = @{
            claude_one = @{
                displayName = 'Claude One'
                baseUrl = 'https://claude.example.test'
                apiKey = 'plain-claude-key-for-test'
                apiKeyEnv = 'CLAUDE_ONE_API_KEY'
                authEnv = 'ANTHROPIC_AUTH_TOKEN'
            }
        }
    }
    Write-JsonFile -Path (Join-Path $exportHome '.codex\provider-profiles\providers.json') -Value @{
        version = 1
        profiles = @{
            codex_one = @{
                displayName = 'Codex One'
                baseUrl = 'https://codex.example.test'
                token = 'plain-codex-token-for-test'
                apiKeyEnv = 'CODEX_ONE_API_KEY'
                wireApi = 'responses'
            }
        }
    }

    $listOutput = & $scriptPath list -Tool all | Out-String
    Assert-True -Condition ($listOutput -notmatch 'plain-claude-key-for-test') -Message 'list 输出不应显示明文 Claude API Key'
    Assert-True -Condition ($listOutput -notmatch 'plain-codex-token-for-test') -Message 'list 输出不应显示明文 Codex token'
    Assert-True -Condition ($listOutput -notmatch 'process-only-claude-key-for-test') -Message 'list 输出不应显示环境变量值'

    $invokeClaude = Join-Path $repoRoot 'src\tools\claude\Invoke-ClaudeProvider.ps1'
    $routeOutput = & pwsh -NoProfile -File $invokeClaude profiles list 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "profiles 子命令路由失败：$routeOutput" }
    Assert-True -Condition ($routeOutput -match 'claude_one') -Message 'ccp profiles list 应路由到导入导出工具并默认查看当前工具'
    Assert-True -Condition ($routeOutput -notmatch 'plain-claude-key-for-test') -Message 'profiles 子命令输出不应显示明文 API Key'

    $allRouteOutput = & pwsh -NoProfile -File $invokeClaude profiles -Tool all 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "profiles -Tool all 子命令路由失败：$allRouteOutput" }
    Assert-True -Condition ($allRouteOutput -match 'claude_one' -and $allRouteOutput -match 'codex_one') -Message 'ccp profiles -Tool all 应默认执行 list 并展示两个工具'

    & $scriptPath export -OutDir $backupDir -Tool all | Out-Null

    $exportedClaude = Get-Content -LiteralPath (Join-Path $backupDir 'claude\providers.json') -Raw | ConvertFrom-Json
    $exportedCodex = Get-Content -LiteralPath (Join-Path $backupDir 'codex\providers.json') -Raw | ConvertFrom-Json

    Assert-True -Condition (-not (Test-JsonProperty -Object $exportedClaude.profiles.claude_one -Name 'apiKey')) -Message '导出 Claude 配置时应移除 apiKey'
    Assert-True -Condition (-not (Test-JsonProperty -Object $exportedCodex.profiles.codex_one -Name 'token')) -Message '导出 Codex 配置时应移除 token'
    Assert-True -Condition (Test-JsonProperty -Object $exportedClaude.profiles.claude_one -Name 'apiKeyEnv') -Message '导出时应保留 apiKeyEnv'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $backupDir 'claude\env-vars-info.json')) -Message '导出时应写入环境变量信息'
    $envVarsInfoText = Get-Content -LiteralPath (Join-Path $backupDir 'claude\env-vars-info.json') -Raw
    $envVarsInfo = $envVarsInfoText | ConvertFrom-Json
    Assert-True -Condition ($envVarsInfoText -notmatch 'process-only-claude-key-for-test') -Message '环境变量信息不应包含变量值'
    Assert-True -Condition ([bool]$envVarsInfo.CLAUDE_ONE_API_KEY.hasValue) -Message '环境变量信息应识别 Process 作用域中已设置的变量'

    $readme = Get-Content -LiteralPath (Join-Path $backupDir 'README.txt') -Raw
    Assert-True -Condition ($readme -match '默认不包含') -Message '导出说明应明确明文密钥不会被导出'

    $env:USERPROFILE = $importHome
    & $scriptPath import -InDir $backupDir -Tool all | Out-Null

    $importedClaude = Get-Content -LiteralPath (Join-Path $importHome '.claude\provider-profiles\providers.json') -Raw | ConvertFrom-Json
    $importedCodex = Get-Content -LiteralPath (Join-Path $importHome '.codex\provider-profiles\providers.json') -Raw | ConvertFrom-Json

    Assert-True -Condition (Test-JsonProperty -Object $importedClaude.profiles -Name 'claude_one') -Message '应能导入 Claude 配置'
    Assert-True -Condition (Test-JsonProperty -Object $importedCodex.profiles -Name 'codex_one') -Message '应能导入 Codex 配置'
    Assert-True -Condition (-not (Test-JsonProperty -Object $importedClaude.profiles.claude_one -Name 'apiKey')) -Message '导入后的 Claude 配置不应包含已脱敏 apiKey'

    Compress-Archive -LiteralPath $backupDir -DestinationPath $zipPath -Force
    $existingImportTempDirs = @{}
    Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Directory -Filter 'provider-import-*' -ErrorAction SilentlyContinue | ForEach-Object {
        $existingImportTempDirs[$_.FullName] = $true
    }
    $env:USERPROFILE = $zipImportHome
    & $scriptPath import -InDir $zipPath -Tool claude | Out-Null
    $newImportTempDirs = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Directory -Filter 'provider-import-*' -ErrorAction SilentlyContinue | Where-Object {
        -not $existingImportTempDirs.ContainsKey($_.FullName)
    })
    Assert-True -Condition ($newImportTempDirs.Count -eq 0) -Message '从 zip 导入后应清理解压临时目录'

    Write-Output 'profile-transfer-tests: PASS'
}
finally {
    $env:USERPROFILE = $originalUserProfile
    if ($null -eq $originalClaudeOneApiKey) {
        Remove-Item Env:\CLAUDE_ONE_API_KEY -ErrorAction SilentlyContinue
    } else {
        $env:CLAUDE_ONE_API_KEY = $originalClaudeOneApiKey
    }
    Remove-Item -LiteralPath $exportHome -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $importHome -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zipImportHome -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
}
