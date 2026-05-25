#!/usr/bin/env pwsh
<#
.SYNOPSIS
    远程引导模式（iwr | iex）端到端测试。

.DESCRIPTION
    起本地 HttpListener 服务一个仿 GitHub archive 的 zip，
    用 [scriptblock]::Create() 模拟 iex 场景（$PSCommandPath 为空），
    通过 CPS_BOOTSTRAP_URL 把下载地址重定向到本地服务，
    验证 install.ps1 能正确：
      - 检测远程模式
      - 下载并解压
      - 转发 -DryRun 等参数到解压后的 installer
      - 完整执行不报错
#>
[CmdletBinding()]
param(
    [int]$Port = 18767
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot   = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$installPs1 = Join-Path $repoRoot 'Claude-Provider-Profiles-Kit\install.ps1'
if (-not (Test-Path -LiteralPath $installPs1)) {
    throw "未找到 install.ps1：$installPs1"
}

$tempBase = [System.IO.Path]::GetTempPath()
$stageDir = Join-Path $tempBase ("cps-boot-stage-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$innerDir = Join-Path $stageDir 'Claude-Code-Provider-main'
$zipPath  = Join-Path $tempBase ("cps-boot-" + [guid]::NewGuid().ToString('N').Substring(0,8) + '.zip')
$tempHome = Join-Path $tempBase ("cps-boot-home-" + [guid]::NewGuid().ToString('N').Substring(0,8))

$originalProfile = $env:USERPROFILE
$serverJob = $null

try {
    # 1) 把当前仓库打包成仿 GitHub archive 结构
    New-Item -ItemType Directory -Force -Path $innerDir | Out-Null
    foreach ($item in @('src','config','Claude-Provider-Profiles-Kit')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $item) `
                  -Destination (Join-Path $innerDir $item) `
                  -Recurse -Force
    }
    Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -Force

    # 2) 起本地 HTTP 服务
    $serverJob = Start-Job -ScriptBlock {
        param($port, $zip)
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://127.0.0.1:$port/")
        $listener.Start()
        try {
            $ctx = $listener.GetContext()
            $fs = [System.IO.File]::OpenRead($zip)
            try {
                $ctx.Response.ContentType = 'application/zip'
                $ctx.Response.ContentLength64 = $fs.Length
                $ctx.Response.SendChunked = $false
                $ctx.Response.KeepAlive = $false
                $fs.CopyTo($ctx.Response.OutputStream)
                $ctx.Response.OutputStream.Flush()
            } finally {
                $fs.Dispose()
                $ctx.Response.OutputStream.Close()
                $ctx.Response.Close()
            }
        } finally {
            $listener.Stop()
        }
    } -ArgumentList $Port, $zipPath
    Start-Sleep -Milliseconds 800

    # 3) 隔离 USERPROFILE + 注入 bootstrap URL
    New-Item -ItemType Directory -Force -Path $tempHome | Out-Null
    $env:USERPROFILE = $tempHome
    $env:CPS_BOOTSTRAP_URL = "http://127.0.0.1:$Port/source.zip"

    # 4) 模拟 iex：从字符串创建脚本块（$PSCommandPath 此时为空）
    $installScript = [System.IO.File]::ReadAllText($installPs1, [System.Text.Encoding]::UTF8)
    $sb = [scriptblock]::Create($installScript)
    $output = & $sb -DryRun 2>&1 | Out-String

    # 5) 断言关键执行轨迹
    $assertions = @(
        @{ Pattern = '\[远程引导\] 下载源码';   Msg = '应触发远程引导下载' }
        @{ Pattern = '\[远程引导\] 解压到';     Msg = '应触发远程引导解压' }
        @{ Pattern = '\[远程引导\] 调用本地 install\.ps1'; Msg = '应转发到解压后的 installer' }
        @{ Pattern = '部署核心模块';            Msg = '解压后 installer 应执行部署' }
        @{ Pattern = '预检完成';                Msg = '-DryRun 参数应正确透传' }
    )
    foreach ($a in $assertions) {
        if ($output -notmatch $a.Pattern) {
            Write-Output "FAIL: $($a.Msg)"
            Write-Output '--- output ---'
            Write-Output $output
            Write-Output '--------------'
            throw "断言失败：$($a.Msg)（缺 '$($a.Pattern)'）"
        }
    }

    Write-Output 'install-bootstrap-tests: PASS'
}
finally {
    $env:USERPROFILE = $originalProfile
    Remove-Item Env:CPS_BOOTSTRAP_URL -ErrorAction SilentlyContinue
    if ($serverJob) {
        Receive-Job $serverJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $serverJob -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}