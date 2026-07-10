# AI CLI Switcher — 优化历史

> 本文是历史审查与实施记录，不代表当前版本路线图。
> 基于 2026-05-22 代码库多维度审查，按优先级排列。
> **进度：18/19 已完成** | 最后更新：2026-06-05

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

### 5. ✅ `Select-ProfileFromMenu` 菜单中 profile 遍历顺序不稳定
**位置**：`ProviderCore.psm1:571-604`
**问题**：hashtable 枚举顺序不可靠，JSON key 原始顺序已丢失。
**已完成**：新增统一的 profile 排序 helper，菜单和列表均按配置 ID 的 OrdinalIgnoreCase 顺序稳定展示，并增加回归测试。

---

## P2 — 安全

### 6. ✅ 配置文件中存在明文 API Key
**位置**：`providers.json` + `Resolve-ApiKey`
**已完成**：Resolve-ApiKey 追踪密钥来源，明文 apiKey 字段触发 Write-Warning 引导迁移到 apiKeyEnv（commit 1ca42d4）。

### 7. ✅ Web UI 无认证/授权保护
**位置**：`src/web/app.js` + `Manage-*UI.ps1`
**问题**：管理界面监听 localhost，任何本地进程可访问。
**已完成**：`Manage-ProviderUI.ps1` 为每个本地服务生成随机 token，`server.mjs` 通过 `/auth` 设置 HttpOnly/SameSite cookie，并对管理 API 与静态页面启用鉴权；未授权请求仅允许访问健康检查。

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

### 11. ✅ `Invoke-ProviderSession` 启动失败时临时文件残留
**位置**：`ProviderCore.psm1:767-835`
**问题**：launcher 内部抛出异常时临时文件路径未通过 TempFile 返回，无法在 finally 中清理。
**已完成**：EnvSession 增加临时文件登记，launcher 返回前抛错和 CLI 启动失败都会在 finally 中清理临时文件并恢复环境变量。

### 12. ✅ 错误信息中英文混用
**位置**：全局
**已完成**：审查确认所有 throw/Write-Warning 已为中文，无需修改。

### 13. ✅ Web UI 缺少输入验证
**位置**：`src/web/app.js`
**已完成**：collectConfig 增加 baseUrl 非空和 https?:// 格式校验（commit 1ca42d4）。

---

## P4 — 未来考虑

### 14. ProviderCore.psm1 模块过大
**位置**：`src/core/ProviderCore.psm1`（约 1277 行）
**建议**：拆分为 `Core.Json.psm1`、`Core.Session.psm1`、`Core.Shortcut.psm1` 等子模块。等模块超过 1500 行时考虑。

### 15. ✅ 缺少自动化测试
**问题**：无单元测试/集成测试。
**已完成**：已有脚本式集成测试覆盖 setup、server、install、profiles transfer；新增 `tests/core-function-tests.ps1` 直接覆盖 `Read-JsonFile`、`Convert-JsonObjectToHashtable`、`Resolve-ApiKey` 的关键边界。

### 16. 快捷命令 bin 目录污染 PATH 的风险
**位置**：`Sync-ToolShortcuts` 生成的 `bin/` 目录
**问题**：多工具 bin 目录同名 shim 可能冲突；文件数量多（CCP 25 个 + CDP 17 个）。
**状态**：部分缓解。README 已统一推荐 `ccp mi` / `cdp ds` 子命令形式；兼容快捷命令仍保留，避免破坏旧用户习惯。

### 17. ✅ 新用户配置成本偏高
**位置**：`ProviderCore.psm1`、`Invoke-Provider.ps1`、`init.ps1`
**问题**：用户需要手动编辑 JSON、设置多个环境变量、再同步快捷命令。
**已完成**：新增 `ccp setup` / `cdp setup` / `.\init.ps1 setup` 配置向导，自动写入配置、设置用户环境变量、同步快捷命令。

### 18. ✅ 安装脚本部署逻辑重复
**位置**：`Claude-Provider-Profiles-Kit/install.ps1`
**问题**：核心文件和工具 wrapper 的 Copy-Item 逻辑重复，维护成本高。
**已完成**：抽出 `Copy-RequiredFile`、`Deploy-SharedFiles`、`Deploy-ToolFiles`、`Initialize-ConfigFile`，并新增 `-Configure` 安装后配置入口。

### 19. ✅ README 用户路径不够清晰
**位置**：`README.md`、`Claude-Provider-Profiles-Kit/README.md`
**问题**：用户安装、配置字段、开发者架构混在一起，命令风格不统一。
**已完成**：重写为用户优先文档，统一推荐 `ccp setup`、`ccp mi`、`cdp ds`；开发者内容后置。
