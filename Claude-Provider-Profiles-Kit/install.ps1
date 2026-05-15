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
$codexTargetRoot = Join-Path $env:USERPROFILE '.codex\provider-profiles'
$codexTargetWeb = Join-Path $codexTargetRoot 'web'
$codexBinDir = Join-Path $env:USERPROFILE '.codex\bin'
$exampleConfig = Join-Path $kitRoot 'providers.example.json'
$targetConfig = Join-Path $targetRoot 'providers.json'
$legacyConfig = Join-Path $legacyRoot 'providers.json'
$codexExampleConfig = Join-Path $kitRoot 'codex-providers.example.json'
$codexTargetConfig = Join-Path $codexTargetRoot 'providers.json'
$encoding = [System.Text.UTF8Encoding]::new($false)

function Write-Shim {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Ensure-UserPathItem {
    param(
        [Parameter(Mandatory = $true)][string]$PathItem,
        [switch]$ShouldAdd
    )
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathItems = @()
    if ($userPath) {
        $pathItems = $userPath -split ';' | Where-Object { $_ }
    }
    $exists = $pathItems | Where-Object { $_.TrimEnd('\') -ieq $PathItem.TrimEnd('\') }
    if ($exists) {
        return
    }
    if ($ShouldAdd) {
        $nextPath = (($pathItems + $PathItem) -join ';')
        [Environment]::SetEnvironmentVariable('Path', $nextPath, 'User')
        Write-Output "已加入用户 PATH：$PathItem"
    }
    else {
        Write-Warning "快捷命令目录不在用户 PATH 中：$PathItem"
    }
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning "未找到 claude 命令。请先安装 Claude Code，并验证：claude --version"
}
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    Write-Warning "未找到 codex 命令。请先安装 Codex CLI，并验证：codex --version"
}

New-Item -ItemType Directory -Force -Path $targetWeb | Out-Null
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
New-Item -ItemType Directory -Force -Path $codexTargetRoot | Out-Null
New-Item -ItemType Directory -Force -Path $codexTargetWeb | Out-Null
New-Item -ItemType Directory -Force -Path $codexBinDir | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceScripts 'Invoke-ProviderClaude.ps1') -Destination (Join-Path $targetRoot 'Invoke-ProviderClaude.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'Manage-ClaudeProfiles.ps1') -Destination (Join-Path $targetRoot 'Manage-ClaudeProfiles.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'Sync-ClaudeProfileShortcuts.ps1') -Destination (Join-Path $targetRoot 'Sync-ClaudeProfileShortcuts.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'server.mjs') -Destination (Join-Path $targetRoot 'server.mjs') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'web\index.html') -Destination (Join-Path $targetWeb 'index.html') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'web\styles.css') -Destination (Join-Path $targetWeb 'styles.css') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'web\app.js') -Destination (Join-Path $targetWeb 'app.js') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'Invoke-ProviderCodex.ps1') -Destination (Join-Path $codexTargetRoot 'Invoke-ProviderCodex.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'Manage-CodexProfiles.ps1') -Destination (Join-Path $codexTargetRoot 'Manage-CodexProfiles.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'Sync-CodexProfileShortcuts.ps1') -Destination (Join-Path $codexTargetRoot 'Sync-CodexProfileShortcuts.ps1') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'server-codex.mjs') -Destination (Join-Path $codexTargetRoot 'server-codex.mjs') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'web-codex\index.html') -Destination (Join-Path $codexTargetWeb 'index.html') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'web-codex\app.js') -Destination (Join-Path $codexTargetWeb 'app.js') -Force
Copy-Item -LiteralPath (Join-Path $sourceScripts 'web\styles.css') -Destination (Join-Path $codexTargetWeb 'styles.css') -Force

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

if ($OverwriteConfig) {
    Copy-Item -LiteralPath $codexExampleConfig -Destination $codexTargetConfig -Force
    Write-Output "已写入模板配置：$codexTargetConfig"
}
elseif (Test-Path -LiteralPath $codexTargetConfig) {
    Write-Output "保留已有配置：$codexTargetConfig"
}
else {
    Copy-Item -LiteralPath $codexExampleConfig -Destination $codexTargetConfig -Force
    Write-Output "已写入模板配置：$codexTargetConfig"
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

Write-Shim -Path (Join-Path $codexBinDir 'provider-codex.ps1') -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.codex\provider-profiles\Invoke-ProviderCodex.ps1'
& `$script @args
exit `$LASTEXITCODE
"@

Write-Shim -Path (Join-Path $codexBinDir 'sync-codex-profiles.ps1') -Content @"
#!/usr/bin/env pwsh
`$script = Join-Path `$env:USERPROFILE '.codex\provider-profiles\Sync-CodexProfileShortcuts.ps1'
& `$script @args
exit `$LASTEXITCODE
"@

& (Join-Path $targetRoot 'Sync-ClaudeProfileShortcuts.ps1') | Out-Host
& (Join-Path $codexTargetRoot 'Sync-CodexProfileShortcuts.ps1') | Out-Host

Ensure-UserPathItem -PathItem $binDir -ShouldAdd:$AddPath
Ensure-UserPathItem -PathItem $codexBinDir -ShouldAdd:$AddPath
if ($AddPath) {
    Write-Output "请重新打开 PowerShell / Windows Terminal 后再使用快捷命令。"
}
else {
    Write-Warning "如需自动加入 PATH，请重新执行：.\install.ps1 -AddPath"
}

Write-Output ""
Write-Output "安装完成。下一步："
Write-Output "1. 编辑配置：$targetConfig"
Write-Output "2. 可选编辑 Codex 配置：$codexTargetConfig"
Write-Output "3. 设置自己的 API Key 环境变量。"
Write-Output "4. 重新打开终端后运行：ccp 或 cdp"
Write-Output "5. 可选管理页面：ccp-manager"
