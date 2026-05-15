#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# 某些 Codex 运行路径下 stdin 不会很快关闭；这里做一个很短的等待，拿不到输入就直接放行，避免 hook 卡死。
$readTask = [Console]::In.ReadToEndAsync()
if (-not $readTask.Wait(200)) {
    exit 0
}

$raw = $readTask.Result
if ([string]::IsNullOrWhiteSpace($raw)) {
    exit 0
}

$payload = $raw | ConvertFrom-Json -Depth 20
$toolName = "$($payload.tool_name)"
if ($toolName -ne 'Bash') {
    exit 0
}

$command = "$($payload.tool_input.command)"
if ([string]::IsNullOrWhiteSpace($command)) {
    exit 0
}

$denyPatterns = @(
    '(?i)\brg(\.exe)?\b',
    '(?i)\bgrep\b',
    '(?i)\bfindstr\b',
    '(?i)\bcat\b',
    '(?i)\btype\b',
    '(?i)\bmore\b',
    '(?i)\bless\b',
    '(?i)\bhead\b',
    '(?i)\btail\b',
    '(?i)\bsed\b',
    '(?i)\bawk\b',
    '(?i)\bGet-Content\b',
    '(?i)\bgc\b'
)

$matched = $false
foreach ($pattern in $denyPatterns) {
    if ($command -match $pattern) {
        $matched = $true
        break
    }
}

if (-not $matched) {
    exit 0
}

$reason = @'
公司加密环境禁止直接使用 rg/grep/cat/type/Get-Content/gc/sed/awk/head/tail 等方式读取或搜索源码。
请改用 PowerShell 明文方式，例如：
1. 单文件读取：.\.codex\tools\Read-PlainText.ps1 -Path README.md
2. 自定义读取：
   $path = "E:\path\file.ext"
   $bytes = [System.IO.File]::ReadAllBytes($path)
   $text = [System.Text.Encoding]::UTF8.GetString($bytes)
3. 搜索文件名或目录：Get-ChildItem -Recurse
4. 搜索内容：Get-ChildItem -Recurse -File | Select-String -Pattern "关键词"
'@

@{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'deny'
        permissionDecisionReason = $reason.Trim()
    }
} | ConvertTo-Json -Depth 6 -Compress
