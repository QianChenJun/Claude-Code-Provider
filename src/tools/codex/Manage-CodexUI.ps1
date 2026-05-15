#!/usr/bin/env pwsh
[CmdletBinding()]
param([int]$Port = 15724, [switch]$Foreground)
$ErrorActionPreference = 'Stop'

$root     = Split-Path -Parent $PSScriptRoot
$server   = Join-Path (Split-Path -Parent $root) 'server.mjs'
$toolName = 'codex'

. (Join-Path $root 'Import-Core.ps1')
Import-ProviderCore

function Get-ManagerState {
    param([Parameter(Mandatory)][int]$ProbePort)
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$ProbePort/api/health" -Method Get -TimeoutSec 1
        if ($null -ne $r -and $r.ok -and $r.root) {
            $expected = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
            $actual   = [System.IO.Path]::GetFullPath("$($r.root)").TrimEnd('\')
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
    Start-Process "http://127.0.0.1:$selectedPort/" | Out-Null
    node $server --port $selectedPort --tool $toolName
    exit $LASTEXITCODE
}

if ($state -eq 'Free') {
    $proc = Start-Process -FilePath 'node' -ArgumentList @($server, '--port', $selectedPort, '--tool', $toolName) `
        -WorkingDirectory (Split-Path -Parent $root) -WindowStyle Hidden -PassThru
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

Start-Process "http://127.0.0.1:$selectedPort/" | Out-Null
Write-Output "配置管理页面已打开：http://127.0.0.1:$selectedPort/"