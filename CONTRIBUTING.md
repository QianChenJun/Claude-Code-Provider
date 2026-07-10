# 贡献指南

感谢你愿意改进 AI CLI Switcher。项目面向 Windows，核心目标是以统一、安全的方式管理 Claude Code 和 Codex CLI 的多供应商配置。

## 开发环境

- Windows 10/11
- PowerShell 7+
- Node.js 18+
- 可选：PSScriptAnalyzer

克隆仓库后先运行：

```powershell
.\init.ps1 check
```

## 开发原则

- 保持零 npm 依赖，不要为简单能力引入第三方包。
- 只提交与当前问题相关的最小改动。
- 不要在配置、测试、日志或提交记录中包含真实 API Key。
- 修改配置字段时，同步检查示例配置、后端、Web UI 和安装包。
- 修改现有文本文件时保留 UTF-8 无 BOM 编码。

## 验证

提交 Pull Request 前至少运行与改动相关的检查。完整检查命令如下：

```powershell
$tests = @(
  'tests\core-function-tests.ps1'
  'tests\setup-tests.ps1'
  'tests\install-dryrun-tests.ps1'
  'tests\install-bootstrap-tests.ps1'
  'tests\profile-transfer-tests.ps1'
  'tests\server-path-tests.ps1'
)

foreach ($test in $tests) {
  pwsh -NoProfile -File $test
}

node --check src\server.mjs
node --check src\web\app.js
```

如果已安装 PSScriptAnalyzer：

```powershell
Get-ChildItem -Recurse -Include '*.ps1','*.psm1' |
  ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Severity Error }
```

## 提交 Issue

Bug 报告请包含 Windows 版本、PowerShell 版本、相关 CLI 版本、最小复现步骤和已脱敏日志。功能建议请描述实际使用场景和期望行为。

安全漏洞不要提交公开 Issue，请按照 [安全策略](SECURITY.md) 报告。

## 提交 Pull Request

- 从 `main` 创建独立分支。
- 保持 PR 单一目的，并说明用户影响和验证结果。
- 如行为、命令或配置格式发生变化，同步更新 README 或安装包文档。
- 确保 GitHub Actions 全部通过。
