#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [int]$Port = 15724,
    [switch]$Foreground
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$server = Join-Path $root 'server-codex.mjs'

function Get-ManagerState {
    param([Parameter(Mandatory = $true)][int]$Port)

    try {
        $apiUrl = "http://127.0.0.1:$Port/api/health"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 1
        if ($null -ne $response -and $response.ok -and $response.root) {
            $expectedRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
            $actualRoot = [System.IO.Path]::GetFullPath("$($response.root)").TrimEnd('\')
            if ($expectedRoot -ieq $actualRoot) {
                return 'Current'
            }
            return 'Other'
        }
    }
    catch {
    }

    try {
        $apiUrl = "http://127.0.0.1:$Port/api/config"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 1
        if ($null -ne $response -and $null -ne $response.profiles) {
            return 'Other'
        }
    }
    catch {
    }

    return 'Free'
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "未找到 node，无法启动本地配置管理页面。"
}

if ($Foreground) {
    $url = "http://127.0.0.1:$Port/"
    Start-Process $url | Out-Null
    node $server --port $Port
    exit $LASTEXITCODE
}

$selectedPort = $Port
$state = 'Free'
for ($candidate = $Port; $candidate -lt ($Port + 20); $candidate++) {
    $state = Get-ManagerState -Port $candidate
    if ($state -eq 'Current' -or $state -eq 'Free') {
        $selectedPort = $candidate
        break
    }
}

if ($state -eq 'Other') {
    throw "端口 $Port 到 $($Port + 19) 都被其他服务占用，请指定其他端口：cdp-manager -Port 15824"
}

$url = "http://127.0.0.1:$selectedPort/"

if ($state -eq 'Free') {
    $managerProcess = Start-Process -FilePath 'node' -ArgumentList @($server, '--port', $selectedPort) -WorkingDirectory $root -WindowStyle Hidden -PassThru

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 200
        if ((Get-ManagerState -Port $selectedPort) -eq 'Current') {
            $ready = $true
            break
        }
    }

    if (-not $ready) {
        throw "配置管理页面启动失败，请检查端口是否被占用：$selectedPort"
    }

    Write-Output "后台服务已启动，进程 ID：$($managerProcess.Id)"
}
else {
    Write-Output "复用已运行的后台服务。"
}

Start-Process $url | Out-Null
Write-Output "配置管理页面已打开：$url"
Write-Output "服务在后台运行；如需前台日志，可执行：cdp-manager -Foreground"
