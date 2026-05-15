#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$context = @'
公司加密环境约束：
- 所有文件读取、写入、编辑、搜索优先使用 PowerShell，不要依赖内置文件读取或常见类 Unix 文本命令。
- 读取文本优先使用 [System.IO.File]::ReadAllBytes(...) 后再用 UTF8 解码，必要时先验证是否明文。
- 如果看到 E-SafeNet、乱码、二进制或异常空内容，立即停止基于该结果的编辑，改用 PowerShell 明文验证。
- 单文件读取优先使用 .\.codex\tools\Read-PlainText.ps1。
- 编辑既有文件前先明文复读，修改后再复读抽样确认。
'@

@{
    hookSpecificOutput = @{
        hookEventName    = 'SessionStart'
        additionalContext = $context
    }
} | ConvertTo-Json -Depth 6 -Compress
