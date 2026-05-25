#!/usr/bin/env pwsh
# Generic management UI launcher — dot-sourced by tool-specific wrappers.
# The wrapper must set $ToolName before dot-sourcing and declare param($Port, $Foreground).

$ErrorActionPreference = 'Stop'

if (-not $ToolName) { throw 'Internal error: $ToolName not set by wrapper script.' }

$toolsDir = $PSScriptRoot
$server   = Join-Path (Split-Path -Parent (Split-Path -Parent $toolsDir)) 'server.mjs'

. (Join-Path $toolsDir 'Import-Core.ps1')
Import-ProviderCore

$tool = Get-ProviderTool -Name $ToolName

# 统一端口：ccp 与 cdp 共用单个 server 进程，浏览器靠 ?tool= 参数切换 tab
# server 的 /api/{tool}/... 路由根据 tool 名直接定位 config + sync 脚本，跟启动时的 root 无关
if ($Port -eq 0) {
    $Port = 15723
}

function Get-ManagerState {
    param([Parameter(Mandatory)][int]$ProbePort)
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$ProbePort/api/health" -Method Get -TimeoutSec 1
        if ($null -ne $r -and $r.ok -and $r.root) {
            $expected = [System.IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $toolsDir))).TrimEnd('\\')
            $actual   = [System.IO.Path]::GetFullPath("$($r.root)").TrimEnd('\\')
            if ($expected -ieq $actual) { return 'Current' }
            return 'Other'
        }
    } catch {}
    return 'Free'
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "未找到 node，无法启动本地配置管理页面。"
}

$selectedPort = $Port
$state = 'Free'
for ($candidate = $Port; $candidate -lt ($Port + 20); $candidate++) {
    $state = Get-ManagerState -ProbePort $candidate
    if ($state -in @('Current', 'Free')) { $selectedPort = $candidate; break }
}

if ($state -eq 'Other') {
    throw "端口 $Port 到 $($Port + 19) 都被占用，请指定其他端口。"
}

if ($Foreground) {
    Start-Process "http://127.0.0.1:$selectedPort/?tool=$ToolName" | Out-Null
    node $server --port $selectedPort --tool $ToolName
    exit $LASTEXITCODE
}

if ($state -eq 'Free') {
    $proc = Start-Process -FilePath 'node' -ArgumentList @($server, '--port', $selectedPort, '--tool', $ToolName) `
        -WorkingDirectory (Split-Path -Parent (Split-Path -Parent $toolsDir)) -WindowStyle Hidden -PassThru
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 200
        if ((Get-ManagerState -ProbePort $selectedPort) -eq 'Current') { $ready = $true; break }
    }
    if (-not $ready) { throw "配置管理页面启动失败：端口 $selectedPort" }
    Write-Output "后台服务已启动，进程 ID：$($proc.Id)"
} else {
    Write-Output "复用已运行的后台服务。"
}

Start-Process "http://127.0.0.1:$selectedPort/?tool=$ToolName" | Out-Null
Write-Output "配置管理页面已打开：http://127.0.0.1:$selectedPort/"