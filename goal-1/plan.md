# goal-1 计划

## 需求理解

继续优化当前项目，并严格遵守 Goal Mode：

- 先创建 `goal-[num]/input.md`、`goal-[num]/plan.md`、`goal-[num]/tasks.md`，完成前不修改代码。
- 每次只执行一个 task。
- 每个 task 完成前必须进行自检，确认没有明显漏洞、遗漏和回归风险。
- 若有代码变更，需要按项目 Git 规范处理提交；本仓库 `AGENTS.md` 要求修改类 Git 操作先说明风险并取得确认，因此提交动作需要在用户确认或既有明确授权下执行。
- 每 3 个 task 后插入一次大型全面检查-debug 循环。
- 全部 task 完成后执行最终最大 review，并在证据充分时标记 goal 完成。

## 当前上下文

- 项目：Windows PowerShell 下的 AI CLI 多供应商切换器，管理 Claude Code / Codex CLI provider profiles。
- 主要代码：`src/core/ProviderCore.psm1`、`src/tools/*.ps1`、`src/server.mjs`、`src/web/app.js`、安装包目录 `Claude-Provider-Profiles-Kit/`。
- 已有优化清单：`OPTIMIZATION.md` 显示 19 项中 14 项已完成，剩余重点包括菜单顺序稳定性、Web UI 本地访问保护、临时文件清理、测试补齐等。
- 当前工作区已有未提交变更：
  - `src/core/ProviderCore.psm1`：Codex providerId 改为统一 `cdp`，用于保证 `/resume` 跨 profile 可见。
  - `tests/setup-tests.ps1`：新增 Codex 统一 `model_provider=cdp` 的验证。
  - 未跟踪：`.playwright-mcp/`、`Claude-Provider-Profiles-Kit/同事使用说明.md`、`src/tools/Manage-ProviderProfiles.ps1`。

## 风险

- 工作区已有改动来源不完全明确，不能回退或覆盖不相关用户变更。
- 项目位于可能触发公司加密代理的路径，读取和验证优先使用 PowerShell。
- 修改 PowerShell 核心模块可能影响用户真实 CLI 启动环境，需要用最小测试覆盖关键路径。
- Git 提交会写入本地历史；若未获确认，不主动执行 `git commit`。
- Web UI 安全增强可能影响现有 localhost 使用方式，需要保持默认易用性并提供兼容路径。

## 执行方案

1. 先稳定并验证当前已有 Codex `/resume` 跨 profile 修复，避免继续堆叠未验证变更。
2. 处理 `OPTIMIZATION.md` 中剩余的低风险质量项：菜单顺序、临时文件清理。
3. 每 3 个 task 后运行大型检查-debug 循环，覆盖 Git diff、核心测试、语法检查、关键文档一致性。
4. 再处理较高影响项：Web UI 本地访问保护、导入导出工具是否纳入发布包、测试体系补齐。
5. 全部 task 结束后进行最终 review，从用户路径、代码正确性、安全性、文档、安装包一致性、回归测试六个角度收口。

## 验证方式

- PowerShell 测试：
  - `pwsh -NoProfile -File tests\setup-tests.ps1`
  - `pwsh -NoProfile -File tests\server-path-tests.ps1`
  - `pwsh -NoProfile -File tests\install-dryrun-tests.ps1`
  - `pwsh -NoProfile -File tests\install-bootstrap-tests.ps1`
- Node 语法检查：
  - `node --check src\server.mjs`
  - `node --check src\web\app.js`
- 静态核对：
  - `git diff`
  - `git status --short`
  - 搜索敏感字段和未同步安装包文件。

## 回滚方案

- 每个 task 保持小范围变更，优先使用可读 diff 回退。
- 若某次修改导致测试失败且无法立即定位，先停止继续扩散，保留失败证据，回到上一处最小改动点。
- 不使用 `git reset --hard`、`git checkout --`、`git clean` 等破坏性命令，除非用户单独确认。
