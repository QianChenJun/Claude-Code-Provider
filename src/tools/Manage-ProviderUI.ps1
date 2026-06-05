#!/usr/bin/env pwsh
# Generic management UI launcher — dot-sourced by tool-specific wrappers.
# The wrapper must set $ToolName before dot-sourcing and declare param($Port, $Foreground).

$ErrorActionPreference = 'Stop'

if (-not $ToolName) { throw 'Internal error: $ToolName not set by wrapper script.' }

$toolsDir = $PSScriptRoot
$repoLayoutServer = Join-Path (Split-Path -Parent $toolsDir) 'server.mjs'
$installedServer = Join-Path (Split-Path -Parent (Split-Path -Parent $toolsDir)) 'server.mjs'
$server = if (Test-Path -LiteralPath $repoLayoutServer) { $repoLayoutServer } else { $installedServer }
if (-not (Test-Path -LiteralPath $server)) {
    throw "找不到 Web 管理服务入口：$server"
}

. (Join-Path $toolsDir 'Import-Core.ps1')
Import-ProviderCore

$tool = Get-ProviderTool -Name $ToolName
$expectedRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $server)).TrimEnd('\')

function New-ManagerAuthToken {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return ([Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_'))
}

function Get-ManagerStatePath {
    param([Parameter(Mandatory)][int]$ProbePort)
    return (Join-Path ([System.IO.Path]::GetTempPath()) "provider-profiles-manager-$ProbePort.json")
}

function Read-ManagerToken {
    param([Parameter(Mandatory)][int]$ProbePort)

    $statePath = Get-ManagerStatePath -ProbePort $ProbePort
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$state.port -ne $ProbePort) { return $null }
        if (-not $state.token) { return $null }
        $stateRoot = [System.IO.Path]::GetFullPath("$($state.root)").TrimEnd('\')
        if ($stateRoot -ine $expectedRoot) { return $null }
        return "$($state.token)"
    }
    catch {
        return $null
    }
}

function Write-ManagerState {
    param(
        [Parameter(Mandatory)][int]$ProbePort,
        [Parameter(Mandatory)][string]$Token,
        [int]$ProcessId = 0
    )

    $state = [ordered]@{
        port      = $ProbePort
        root      = $expectedRoot
        token     = $Token
        processId = $ProcessId
        updatedAt = (Get-Date).ToString('o')
    }
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Get-ManagerStatePath -ProbePort $ProbePort), ($state | ConvertTo-Json -Depth 5), $encoding)
}

function Get-ManagerOpenUrl {
    param(
        [Parameter(Mandatory)][int]$ProbePort,
        [Parameter(Mandatory)][string]$Token
    )
    $escapedToken = [System.Uri]::EscapeDataString($Token)
    $escapedTool = [System.Uri]::EscapeDataString($ToolName)
    return "http://127.0.0.1:$ProbePort/auth?token=$escapedToken&tool=$escapedTool"
}

function Test-ManagerToken {
    param(
        [Parameter(Mandatory)][int]$ProbePort,
        [Parameter(Mandatory)][string]$Token
    )

    try {
        $headers = @{ 'x-provider-profiles-token' = $Token }
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$ProbePort/api/tools" -Method Get -Headers $headers -TimeoutSec 1
        return ($null -ne $r -and $null -ne $r.claude -and $null -ne $r.codex)
    }
    catch {
        return $false
    }
}

# 统一端口：ccp 与 cdp 共用单个 server 进程，浏览器靠 ?tool= 参数切换 tab
# server 的 /api/{tool}/... 路由根据 tool 名直接定位 config + sync 脚本，跟启动时的 root 无关
if ($Port -eq 0) {
    $Port = 15723
}

function Get-ManagerState {
    param([Parameter(Mandatory)][int]$ProbePort)
    try {
        $candidateToken = Read-ManagerToken -ProbePort $ProbePort
        $requestArgs = @{
            Uri        = "http://127.0.0.1:$ProbePort/api/health"
            Method     = 'Get'
            TimeoutSec = 1
        }
        if ($candidateToken) {
            $requestArgs.Headers = @{ 'x-provider-profiles-token' = $candidateToken }
        }
        $r = Invoke-RestMethod @requestArgs
        if ($null -ne $r -and $r.ok -and $r.root) {
            $actual   = [System.IO.Path]::GetFullPath("$($r.root)").TrimEnd('\\')
            if ($expectedRoot -ieq $actual) {
                if ($r.PSObject.Properties['auth'] -and $r.auth -eq 'token') { return 'Current' }
                return 'Legacy'
            }
            return 'Other'
        }
        if ($null -ne $r -and $r.ok -and $r.PSObject.Properties['auth'] -and $r.auth -eq 'token') {
            return 'Other'
        }
    } catch {}
    return 'Free'
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "未找到 node，无法启动本地配置管理页面。"
}

$selectedPort = $Port
$selectedToken = $null
$state = 'Free'
for ($candidate = $Port; $candidate -lt ($Port + 20); $candidate++) {
    $candidateState = Get-ManagerState -ProbePort $candidate
    if ($candidateState -eq 'Current') {
        $candidateToken = Read-ManagerToken -ProbePort $candidate
        if ($candidateToken -and (Test-ManagerToken -ProbePort $candidate -Token $candidateToken)) {
            $selectedPort = $candidate
            $selectedToken = $candidateToken
            $state = 'Current'
            break
        }
        continue
    }
    if ($candidateState -eq 'Free') {
        $selectedPort = $candidate
        $selectedToken = New-ManagerAuthToken
        $state = 'Free'
        break
    }
}

if (-not $selectedToken) {
    throw "端口 $Port 到 $($Port + 19) 都被占用，或已有服务缺少可复用的授权状态。请指定其他端口。"
}

$openUrl = Get-ManagerOpenUrl -ProbePort $selectedPort -Token $selectedToken

if ($Foreground) {
    Start-Process $openUrl | Out-Null
    if ($state -eq 'Current') {
        Write-Output "复用已运行的后台服务。"
        exit 0
    }
    Write-ManagerState -ProbePort $selectedPort -Token $selectedToken
    node $server --port $selectedPort --tool $ToolName --auth-token $selectedToken
    exit $LASTEXITCODE
}

if ($state -eq 'Free') {
    Write-ManagerState -ProbePort $selectedPort -Token $selectedToken
    try {
        $proc = Start-Process -FilePath 'node' -ArgumentList @($server, '--port', $selectedPort, '--tool', $ToolName, '--auth-token', $selectedToken) `
            -WorkingDirectory (Split-Path -Parent (Split-Path -Parent $toolsDir)) -WindowStyle Hidden -PassThru
    }
    catch {
        Remove-Item -LiteralPath (Get-ManagerStatePath -ProbePort $selectedPort) -ErrorAction SilentlyContinue
        throw
    }
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 200
        if ((Get-ManagerState -ProbePort $selectedPort) -eq 'Current') { $ready = $true; break }
    }
    if (-not $ready) {
        Remove-Item -LiteralPath (Get-ManagerStatePath -ProbePort $selectedPort) -ErrorAction SilentlyContinue
        throw "配置管理页面启动失败：端口 $selectedPort"
    }
    Write-ManagerState -ProbePort $selectedPort -Token $selectedToken -ProcessId $proc.Id
    Write-Output "后台服务已启动，进程 ID：$($proc.Id)"
} else {
    Write-Output "复用已运行的后台服务。"
}

Start-Process $openUrl | Out-Null
Write-Output "配置管理页面已打开：http://127.0.0.1:$selectedPort/"
