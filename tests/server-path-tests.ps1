#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("provider-server-tests-" + [guid]::NewGuid().ToString('N'))
$originalUserProfile = $env:USERPROFILE
$serverProcess = $null

function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Message
    )
    if ("$Actual" -ne "$Expected") {
        throw "$Message。期望：$Expected，实际：$Actual"
    }
}

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

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    $listener.Start()
    try {
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
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
    New-Item -ItemType Directory -Force -Path $tempHome | Out-Null
    $env:USERPROFILE = $tempHome

    $claudeConfigPath = Join-Path $tempHome '.claude\provider-profiles\providers.json'
    $codexConfigPath = Join-Path $tempHome '.codex\provider-profiles\providers.json'

    Write-JsonFile -Path $claudeConfigPath -Value @{
        version = 1
        profiles = @{
            claude_only = @{
                displayName = 'Claude Only'
                baseUrl = 'https://claude.example.test'
                authEnv = 'ANTHROPIC_AUTH_TOKEN'
                apiKeyEnv = 'CLAUDE_ONLY_API_KEY'
            }
        }
    }

    Write-JsonFile -Path $codexConfigPath -Value @{
        version = 1
        profiles = @{
            codex_only = @{
                displayName = 'Codex Only'
                baseUrl = 'https://codex.example.test'
                apiKeyEnv = 'CODEX_ONLY_API_KEY'
                wireApi = 'responses'
            }
        }
    }

    $port = Get-FreeTcpPort
    $serverPath = Join-Path $repoRoot 'src\server.mjs'
    $serverProcess = Start-Process -FilePath 'node' `
        -ArgumentList @($serverPath, '--port', $port, '--tool', 'claude') `
        -WorkingDirectory $repoRoot `
        -WindowStyle Hidden `
        -PassThru

    $health = $null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 200
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/health" -Method Get -TimeoutSec 1
            break
        }
        catch {}
    }
    Assert-True -Condition ($null -ne $health -and $health.ok) -Message 'server.mjs 应能启动并返回健康检查'

    $tools = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/tools" -Method Get -TimeoutSec 5
    Assert-Equal -Actual $tools.claude.configPath -Expected $claudeConfigPath -Message 'Claude 标签页应指向 Claude 配置文件'
    Assert-Equal -Actual $tools.codex.configPath -Expected $codexConfigPath -Message 'Codex 标签页应指向 Codex 配置文件'

    $claudeConfig = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/claude/config" -Method Get -TimeoutSec 5
    $codexConfig = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/codex/config" -Method Get -TimeoutSec 5

    Assert-True -Condition (Test-JsonProperty -Object $claudeConfig.profiles -Name 'claude_only') -Message 'Claude API 应读取 Claude 配置'
    Assert-True -Condition (-not (Test-JsonProperty -Object $claudeConfig.profiles -Name 'codex_only')) -Message 'Claude API 不应读取 Codex 配置'
    Assert-True -Condition (Test-JsonProperty -Object $codexConfig.profiles -Name 'codex_only') -Message 'Codex API 应读取 Codex 配置'
    Assert-True -Condition (-not (Test-JsonProperty -Object $codexConfig.profiles -Name 'claude_only')) -Message 'Codex API 不应读取 Claude 配置'

    $newCodexConfig = @{
        version = 1
        profiles = @{
            saved_codex = @{
                displayName = 'Saved Codex'
                baseUrl = 'https://saved-codex.example.test'
                apiKeyEnv = 'SAVED_CODEX_API_KEY'
            }
        }
    }

    $putResult = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/codex/config" `
        -Method Put `
        -ContentType 'application/json' `
        -Body ($newCodexConfig | ConvertTo-Json -Depth 20) `
        -TimeoutSec 5

    Assert-True -Condition (Test-JsonProperty -Object $putResult.profiles -Name 'saved_codex') -Message 'Codex PUT 应返回保存后的配置'

    $claudeFile = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($claudeConfigPath)) | ConvertFrom-Json
    $codexFile = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($codexConfigPath)) | ConvertFrom-Json

    Assert-True -Condition (Test-JsonProperty -Object $claudeFile.profiles -Name 'claude_only') -Message '保存 Codex 配置时不应修改 Claude 文件'
    Assert-True -Condition (Test-JsonProperty -Object $codexFile.profiles -Name 'saved_codex') -Message 'Codex PUT 应写入 Codex 文件'

    Write-Output 'server-path-tests: PASS'
}
finally {
    if ($serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    }
    $env:USERPROFILE = $originalUserProfile
    Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}
