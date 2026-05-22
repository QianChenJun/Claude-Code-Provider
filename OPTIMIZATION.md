# AI CLI Switcher — 可优化项清单

> 基于 2026-05-22 代码库多维度审查，按优先级排列。

## P0 — 修复（影响功能正确性）

### 1. `-Profile` 参数泄露到下游 CLI  ⚠️
**位置**：`ProviderCore.psm1` Sync-ToolShortcuts → shim 生成模板
**问题**：shim 调用 `& '$invokeScript' -Profile '$id' @args`，但 Invoke 脚本不认识 `-Profile` 参数，该参数被当作 remaining arg 传给 `claude`/`codex` CLI，导致未知参数警告或错误。
**影响**：所有快捷命令实际运行时都会传入无效参数。
**修复**：Invoke 脚本中增加 `-Profile` 参数识别并排除，或改用环境变量传递。

### 2. `Import-Core.ps1` 缺少错误处理基础设置
**位置**：`src/tools/Import-Core.ps1`
**问题**：无 `$ErrorActionPreference`、无 `Set-StrictMode`，比模块脚本更宽松，错误可能被静默吞掉。
**修复**：添加 `$ErrorActionPreference = 'Stop'` 和 `Set-StrictMode -Version Latest`。

---

## P1 — 优化（提升代码质量）

### 3. CCP/CDP invoke/sync/manage 脚本高度重复（96%~100%）
**位置**：
- `src/tools/claude/Sync-ClaudeShortcuts.ps1` vs `src/tools/codex/Sync-CodexShortcuts.ps1` — 仅 toolName 不同
- `src/tools/claude/Invoke-ClaudeProvider.ps1` vs `src/tools/codex/Invoke-CodexProvider.ps1` — 仅 4 行不同
- `src/tools/claude/Manage-ClaudeUI.ps1` vs `src/tools/codex/Manage-CodexUI.ps1` — 仅 port + toolName 不同
**建议**：合并为单个通用脚本，通过参数 `-ToolName claude|codex` 区分。或者通过 bin shim 传递 toolName 环境变量。

### 4. 配置文件 `shortcut` 字段冗余
**位置**：`~/.claude/provider-profiles/providers.json` 和 `~/.codex/provider-profiles/providers.json`
**问题**：所有 profile 的 `shortcut` 都等于 `{id}-{suffix}`，与自动生成值完全一致，属于冗余配置。现已支持自动生成，可移除。
**建议**：清理配置文件中所有与默认值一致的 `shortcut` 字段。

### 5. `Select-ProfileFromMenu` 菜单中 profile 遍历顺序不稳定
**位置**：`ProviderCore.psm1:252`
**问题**：使用 `$Profiles.GetEnumerator() | Sort-Object Name`，hashtable 枚举顺序不可靠，虽然有排序但 JSON key 原始顺序已丢失。
**建议**：使用 `[ordered]` dictionary 或在 Read-JsonFile 时保持 JSON key 顺序。

---

## P2 — 安全

### 6. 配置文件中存在明文 API Key
**位置**：`providers.json`
**问题**：CCP 和 CDP 的多个 profile 中包含明文 `apiKey` 字段。代码已支持 `apiKeyEnv`、`apiKeyFile`，应逐步迁移。
**建议**：
- 将 `apiKey` 迁移到用户环境变量，改用 `apiKeyEnv` 引用
- 考虑在未来版本中添加警告：检测到明文 apiKey 时提示用户

### 7. Web UI 无认证/授权保护
**位置**：`src/web/app.js` + `Manage-*UI.ps1`
**问题**：管理界面监听 localhost 端口，任何本地进程可访问。虽仅 localhost，但恶意本地脚本可修改配置。
**建议**：评估是否需要简单的 token 认证或确认机制。

---

## P3 — 健壮性 & UX

### 8. `Convert-JsonObjectToHashtable` 对特殊 JSON 类型处理不完整
**位置**：`ProviderCore.psm1:38-71`
**问题**：未显式处理 `System.Decimal`、`System.Single` 等 JSON 数值类型；`PSMemberInfoIntegratingCollection` 在 StrictMode 下的行为依赖 `@()` 包装。
**建议**：增加类型白名单测试，覆盖 JSON 全类型。

### 9. 交互菜单选择错误后无重试提示
**位置**：`ProviderCore.psm1:282`、`:306`
**问题**：`Write-Warning "无效选择：$choice"` 信息不包含有效选项提示。
**建议**：提示用户可用的输入格式（编号 / 配置ID / L/S/M/H/Q）。

### 10. `Resolve-ApiKey` 三级查找的优先级和反馈
**位置**：`ProviderCore.psm1:155-187`
**问题**：apiKeyEnv → apiKeyFile → apiKey 的三级回退逻辑正确，但最终报错时只提示检查 apiKey，未告知前两级是否已尝试。
**建议**：错误信息中说明尝试过的来源和结果。

### 11. `Invoke-ProviderSession` 启动失败时临时文件残留
**位置**：`ProviderCore.psm1:421-472`
**问题**：finally 块清理 `$launchResult.TempFile`，但如果 launcher 内部创建了额外临时文件未通过 TempFile 返回，则无法清理。
**建议**：确认所有临时文件路径都通过 `$launchResult.TempFile` 返回。

### 12. 错误信息中英文混用
**位置**：全局
**问题**：throw 错误信息、Write-Warning 等部分用中文、部分用英文，缺乏统一标准。
**建议**：统一为全中文。

### 13. Web UI 缺少输入验证
**位置**：`src/web/app.js`
**问题**：用户输入的 baseUrl、apiKey 等字段未见 trim/验证/防注入处理。
**建议**：对必填字段添加前端校验（非空、URL 格式等）。

---

## P4 — 未来考虑

### 14. ProviderCore.psm1 模块过大
**位置**：`src/core/ProviderCore.psm1`（~920 行）
**建议**：拆分为 `Core.Json.psm1`、`Core.Session.psm1`、`Core.Shortcut.psm1` 等子模块。

### 15. 缺少自动化测试
**问题**：无单元测试/集成测试。核心模块中的 JSON 解析、环境变量管理、快捷命令生成等逻辑适合单元测试。
**建议**：使用 Pester 框架为核心函数添加测试。

### 16. 快捷命令 bin 目录污染 PATH 的风险
**位置**：`Sync-ToolShortcuts` 生成的 `bin/` 目录
**问题**：多个工具的 bin 目录都加入 PATH 后，同名 shim（如 `mi.ps1`）可能冲突；且生成大量 ps1 文件（当前 CCP 25 个、CDP 17 个）。
**建议**：评估是否使用单一入口命令 + 子命令模式（如 `ccp switch mi`），减少文件数量。
