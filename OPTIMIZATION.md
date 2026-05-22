# AI CLI Switcher — 可优化项清单

> 基于 2026-05-22 代码库多维度审查，按优先级排列。
> **进度：11/16 已完成** | 最后更新：2026-05-23

## P0 — 修复（影响功能正确性）

### 1. ✅ `-Profile` 参数泄露到下游 CLI
**位置**：`ProviderCore.psm1` Sync-ToolShortcuts → shim 生成模板
**问题**：shim 调用 `& '$invokeScript' -Profile '$id' @args`，`-Profile` 被当作 remaining arg 传给 CLI。
**已完成**：Invoke-Provider.ps1 中增加 `-Profile` 识别逻辑（commit e23a031）。

### 2. ✅ `Import-Core.ps1` 缺少错误处理基础设置
**位置**：`src/tools/Import-Core.ps1`
**问题**：无 `$ErrorActionPreference`、无 `Set-StrictMode`。
**已完成**：添加严格模式设置（commit e23a031）。

---

## P1 — 优化（提升代码质量）

### 3. ✅ CCP/CDP invoke/sync/manage 脚本高度重复（96%~100%）
**位置**：6 个工具专用脚本
**已完成**：合并为 3 个通用脚本（Invoke-Provider / Sync-Shortcuts / Manage-ProviderUI），工具专用脚本改为 2~5 行 thin wrapper（commit e23a031）。

### 4. ✅ 配置文件 `shortcut` 字段冗余
**位置**：4 个示例配置模板
**已完成**：移除模板中的 shortcut 字段（commit e23a031）。用户部署配置未自动修改。

### 5. `Select-ProfileFromMenu` 菜单中 profile 遍历顺序不稳定
**位置**：`ProviderCore.psm1:252`
**问题**：hashtable 枚举顺序不可靠，JSON key 原始顺序已丢失。
**状态**：未处理。影响较小（已有 Sort-Object），可在后续迭代中改用 `[ordered]`。

---

## P2 — 安全

### 6. ✅ 配置文件中存在明文 API Key
**位置**：`providers.json` + `Resolve-ApiKey`
**已完成**：Resolve-ApiKey 追踪密钥来源，明文 apiKey 字段触发 Write-Warning 引导迁移到 apiKeyEnv（commit 1ca42d4）。

### 7. Web UI 无认证/授权保护
**位置**：`src/web/app.js` + `Manage-*UI.ps1`
**问题**：管理界面监听 localhost，任何本地进程可访问。
**状态**：未处理。localhost-only 风险可控，需评估是否需要增加 token/确认机制。

---

## P3 — 健壮性 & UX

### 8. ✅ `Convert-JsonObjectToHashtable` 对特殊 JSON 类型处理不完整
**位置**：`ProviderCore.psm1:38-71`
**已完成**：StrictMode 下 `@()` 包装修复 + 类型检查顺序调整，已覆盖 JSON 全类型（commit c75ee40）。

### 9. ✅ 交互菜单选择错误后无重试提示
**位置**：`ProviderCore.psm1:281`、`:306`
**已完成**：增加有效输入格式提示和可用配置 ID 列表（commit e23a031）。

### 10. ✅ `Resolve-ApiKey` 三级查找的优先级和反馈
**位置**：`ProviderCore.psm1:155-191`
**已完成**：报错信息说明已检查的三种来源及其值（commit e23a031）；额外增加明文 apiKey 警告（commit 1ca42d4）。

### 11. `Invoke-ProviderSession` 启动失败时临时文件残留
**位置**：`ProviderCore.psm1:421-472`
**问题**：launcher 内部抛出异常时临时文件路径未通过 TempFile 返回，无法在 finally 中清理。
**状态**：未处理。临时文件在 %TEMP% 下，OS 会定期清理。风险较低。

### 12. ✅ 错误信息中英文混用
**位置**：全局
**已完成**：审查确认所有 throw/Write-Warning 已为中文，无需修改。

### 13. ✅ Web UI 缺少输入验证
**位置**：`src/web/app.js`
**已完成**：collectConfig 增加 baseUrl 非空和 https?:// 格式校验（commit 1ca42d4）。

---

## P4 — 未来考虑

### 14. ProviderCore.psm1 模块过大
**位置**：`src/core/ProviderCore.psm1`（~926 行）
**建议**：拆分为 `Core.Json.psm1`、`Core.Session.psm1`、`Core.Shortcut.psm1` 等子模块。等模块超过 1500 行时考虑。

### 15. 缺少自动化测试
**问题**：无单元测试/集成测试。
**建议**：使用 Pester 框架为核心函数（Read-JsonFile、Convert-JsonObjectToHashtable、Resolve-ApiKey、Sync-ToolShortcuts）添加测试。

### 16. 快捷命令 bin 目录污染 PATH 的风险
**位置**：`Sync-ToolShortcuts` 生成的 `bin/` 目录
**问题**：多工具 bin 目录同名 shim 可能冲突；文件数量多（CCP 25 个 + CDP 17 个）。
**建议**：评估单一入口命令 + 子命令模式（如 `ccp switch mi`）。