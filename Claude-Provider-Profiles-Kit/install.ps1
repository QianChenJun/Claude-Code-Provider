#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [switch]$OverwriteConfig,
    [switch]$AddPath
)

$ErrorActionPreference = 'Stop'

$kitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceScripts = Join-Path $kitRoot 'scripts'
$legacyRoot = Join-Path $env:USERPROFILE '.cc-switch\claude-profiles'
$targetRoot = Join-Path $env:USERPROFILE '.claude\provider-profiles'
$targetWeb = Join-Path $targetRoot 'web'
$binDir = Join-Path $env:USERPROFILE '.claude\bin'
$exampleConfig = Join-Path $kitRoot 'providers.example.json'
$targetConfig = Join-Path $targetRoot 'providers.json'
$legacyConfig = Join-Path $legacyRoot 'providers.json'
$encoding = [System.Text.UTF8Encoding]::new($false)

function Write-Shim {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning "未找到 claude 命令。请先安装 Claude Code，并验证：claude --version"
}

New-Item -ItemType Directory -Force -Path $targetWeb | Out-Null
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceScripts 'Invoke-ProviderClaude.ps1') -Destination (Join-Path $targetRoot 'Invoke-ProviderClaude.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'Manage-ClaudeProfiles.ps1') -Destination (Join-Path $targetRoot 'Manage-ClaudeProfiles.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'Sync-ClaudeProfileShortcuts.ps1') -Destination (Join-Path $targetRoot 'Sync-ClaudeProfileShortcuts.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'server.mjs') -Destination (Join-Path $targetRoot 'server.mjs') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'web\index.html') -Destination (Join-Path $targetWeb 'index.html') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'web\styles.css') -Destination (Join-Path $targetWeb 'styles.css') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'web\app.js') -Destination (Join-Path $targetWeb 'app.js') -Force

if ($OverwriteConfig) {
    Copy-Item -LiteralPath $exampleConfig -Destination $targetConfig -Force
    Write-Output "已写入模板配置：$targetConfig"
}
elseif (Test-Path -LiteralPath $targetConfig) {
    Write-Output "保留已有配置：$targetConfig"
}
elseif (Test-Path -LiteralPath $legacyConfig) {
    Copy-Item -LiteralPath $legacyConfig -Destination $targetConfig -Force
    Write-Output "已从旧目录迁移配置：$legacyConfig -> $targetConfig"
}
else {
    Copy-Item -LiteralPath $exampleConfig -Destination $targetConfig -Force
    Write-Output "已写入模板配置：$targetConfig"
}

Write-Shim -Path (Join-Path $binDir 'provider-claude.ps1') -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.claude\provider-profiles\Invoke-ProviderClaude.ps1'
& `$script @args
exit `$LASTEXITCODE
"@

Write-Shim -Path (Join-Path $binDir 'claude-profile-manager.ps1') -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.claude\provider-profiles\Manage-ClaudeProfiles.ps1'
& `$script @args
exit `$LASTEXITCODE
"@

Write-Shim -Path (Join-Path $binDir 'sync-claude-profiles.ps1') -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.claude\provider-profiles\Sync-ClaudeProfileShortcuts.ps1'
& `$script @args
exit `$LASTEXITCODE
"@

& (Join-Path $targetRoot 'Sync-ClaudeProfileShortcuts.ps1') | Out-Host

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathItems = @()
if ($userPath) {
    $pathItems = $userPath -split ';' | Where-Object { $_ }
}
$binInPath = $pathItems | Where-Object { $_.TrimEnd('\') -ieq $binDir.TrimEnd('\') }

if (-not $binInPath) {
    if ($AddPath) {
        $nextPath = (($pathItems + $binDir) -join ';')
        [Environment]::SetEnvironmentVariable('Path', $nextPath, 'User')
        Write-Output "已加入用户 PATH：$binDir"
        Write-Output "请重新打开 PowerShell / Windows Terminal 后再使用快捷命令。"
    }
    else {
        Write-Warning "快捷命令目录不在用户 PATH 中：$binDir"
        Write-Warning "如需自动加入 PATH，请重新执行：.\install.ps1 -AddPath"
    }
}

Write-Output ""
Write-Output "安装完成。下一步："
Write-Output "1. 编辑配置：$targetConfig"
Write-Output "2. 设置自己的 API Key 环境变量。"
Write-Output "3. 重新打开终端后运行：ccp"
Write-Output "4. 可选管理页面：ccp-manager"
