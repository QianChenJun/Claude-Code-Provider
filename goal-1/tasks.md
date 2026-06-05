# goal-1 任务清单

## Task 1：验证并收口 Codex `/resume` 跨 profile providerId 修复

- 状态：已完成
- 可验证标准：
  - `src/core/ProviderCore.psm1` 中 Codex launcher 输出统一 `model_provider=cdp`。
  - 不同 profile 仍使用各自 `CODEX_PROVIDER_TOKEN_<PROFILE>` 临时 API Key 环境变量。
  - `tests/setup-tests.ps1` 覆盖上述行为并通过。
- 完成记录：
  - 已确认 `src/core/ProviderCore.psm1` 的 Codex launcher 使用统一 `model_provider=cdp`。
  - 已确认不同 profile 仍生成各自的 `CODEX_PROVIDER_TOKEN_<PROFILE>` 临时环境变量。
  - 已确认 `tests/setup-tests.ps1` 覆盖统一 providerId 与 profile 独立 env_key。
  - 已运行 `pwsh -NoProfile -File tests\setup-tests.ps1`，结果：`setup-tests: PASS`。
  - 已运行 `git diff --check -- src/core/ProviderCore.psm1 tests/setup-tests.ps1 goal-1/input.md goal-1/plan.md goal-1/tasks.md`，未发现 whitespace error；仅提示 Git 未来可能将两个 LF 文件转换为 CRLF。
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认；当前仅完成验证与任务记录，未提交既有未提交代码。

## Task 2：修复菜单 profile 顺序稳定性

- 状态：已完成
- 可验证标准：
  - `Select-ProfileFromMenu` 的展示顺序稳定、可预测。
  - 现有用户命令行为不破坏。
  - 相关测试或可重复脚本验证通过。
- 完成记录：
  - 在 `src/core/ProviderCore.psm1` 新增 `Compare-ProfileId` 与 `Get-SortedProfileEntries`，使用 `OrdinalIgnoreCase` + `Ordinal` 兜底比较，避免依赖 hashtable 枚举顺序或当前区域性排序。
  - `Write-ProfileTable` 和 `Select-ProfileFromMenu` 改为复用同一排序 helper，列表与交互菜单顺序保持一致。
  - `Write-ProfileTable`、`Write-Usage`、`Select-ProfileFromMenu` 的 `Profiles` 参数放宽为 `System.Collections.IDictionary`，兼容 hashtable 与 ordered dictionary。
  - 在 `tests/setup-tests.ps1` 增加菜单列表排序回归测试，验证 `Alpha -> beta -> zeta` 的稳定展示顺序。
  - 更新 `OPTIMIZATION.md`，将优化项 5 标记为完成，进度更新为 `15/19`。
  - 已运行 `pwsh -NoProfile -File tests\setup-tests.ps1`，结果：`setup-tests: PASS`。
  - 已运行 `git diff --check -- src/core/ProviderCore.psm1 tests/setup-tests.ps1 OPTIMIZATION.md goal-1/tasks.md`，未发现 whitespace error；仅提示 Git 未来可能将 LF 文件转换为 CRLF。
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认。

## Task 3：修复启动失败时临时文件清理风险

- 状态：已完成
- 可验证标准：
  - launcher 抛错或 CLI 启动失败时，已创建的临时文件能被清理。
  - 正常启动路径不受影响。
  - 新增或更新测试覆盖异常路径。
- 完成记录：
  - 在 `src/core/ProviderCore.psm1` 的 EnvSession 中新增 `TempFiles` 登记集合，并导出 `Add-EnvSessionTempFile`。
  - `Invoke-ProviderSession` 初始化 `$launchResult = $null`，避免 launcher 返回前抛错时 StrictMode 下 finally 再次报错。
  - `Invoke-ProviderSession` 的 finally 同时清理 session 已登记临时文件与 launcher 返回的 `TempFile`，再恢复环境变量。
  - Claude launcher 在创建 settings 临时文件路径后立即调用 `Add-EnvSessionTempFile`，即使写入后、返回前发生异常也能清理。
  - 在 `tests/setup-tests.ps1` 增加两类回归测试：launcher 返回前抛错、CLI 可执行文件启动失败；均验证临时文件被删除且临时环境变量被恢复。
  - 测试环境变量名改为每次生成唯一值，避免污染或依赖调用环境。
  - 更新 `OPTIMIZATION.md`，将优化项 11 标记为完成，进度更新为 `16/19`，并修正相关行号。
  - 已运行 `pwsh -NoProfile -File tests\setup-tests.ps1`，结果：`setup-tests: PASS`。
  - 已确认 PowerShell 在 `try { exit } finally {}` 下会执行 finally，正常 CLI 退出路径仍会触发临时文件清理。
  - 已运行 `git diff --check -- src/core/ProviderCore.psm1 tests/setup-tests.ps1 OPTIMIZATION.md goal-1/tasks.md`，未发现 whitespace error；仅提示 Git 未来可能将 LF 文件转换为 CRLF。
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认。

## Task 4：大型全面检查-debug 循环（覆盖 Task 1-3）

- 状态：已完成
- 可验证标准：
  - 运行核心 PowerShell 测试和 Node 语法检查。
  - 复查 `git diff`，确认没有无关改动、敏感信息或编码异常。
  - 修复检查中发现的问题，直到可重复通过。
- 完成记录：
  - 已全量复读 `goal-1/input.md`、`goal-1/plan.md`、`goal-1/tasks.md` 后执行本轮检查。
  - 已运行核心 PowerShell 测试：
    - `pwsh -NoProfile -File tests\setup-tests.ps1`：`setup-tests: PASS`
    - `pwsh -NoProfile -File tests\server-path-tests.ps1`：`server-path-tests: PASS`
    - `pwsh -NoProfile -File tests\install-dryrun-tests.ps1`：`install-dryrun-tests: PASS`
    - `pwsh -NoProfile -File tests\install-bootstrap-tests.ps1`：`install-bootstrap-tests: PASS`
  - 已运行 Node 语法检查：
    - `node --check src\server.mjs`：通过
    - `node --check src\web\app.js`：通过
  - 已运行 PowerShell 语法解析检查，覆盖仓库内 `.ps1` / `.psm1`（排除 `.git` / `.playwright-mcp`）：`powershell-parse: PASS`。
  - 已运行 `git diff --check -- src/core/ProviderCore.psm1 tests/setup-tests.ps1 OPTIMIZATION.md goal-1/input.md goal-1/plan.md goal-1/tasks.md`，未发现 whitespace error；仅提示 Git 未来可能将 LF 文件转换为 CRLF。
  - 已对变更文件运行敏感信息扫描，结果：`secret-scan-changed-files: PASS`。
  - 人工复核 diff 时发现 `Add-EnvSessionKey` 重复登记同一环境变量会覆盖第一次记录的原始值，已修复为仅首次记录原始值。
  - 已在 `tests/setup-tests.ps1` 增加重复登记环境变量回归测试，验证恢复时不会保留临时值。
  - 已确认 `Claude-Provider-Profiles-Kit/` 当前只包含安装脚本、示例配置和文档，不包含 `src/core/ProviderCore.psm1` 的发布副本；因此本轮源码改动不存在需同步的安装包源码副本。
  - 当前未跟踪项 `.playwright-mcp/`、`Claude-Provider-Profiles-Kit/同事使用说明.md`、`src/tools/Manage-ProviderProfiles.ps1` 为本 goal 开始前已存在/另行规划项，本轮未修改或回退。
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认。

## Task 5：评估并增强 Web UI 本地访问保护

- 状态：已完成
- 可验证标准：
  - 明确 localhost 管理页面的实际风险边界。
  - 若实施 token 或确认机制，默认路径仍便于用户使用。
  - 服务端和前端请求路径均通过验证。
- 完成记录：
  - 已评估风险边界：原实现仅绑定 `127.0.0.1`，能限制网络侧访问，但 `/api/tools`、`/api/{tool}/config`、`/api/{tool}/sync` 无鉴权，未持有授权的本地 HTTP 请求或浏览器跨站请求仍可尝试读取/修改配置。
  - 在 `src/server.mjs` 中新增随机本地 token 支持：启动参数 `--auth-token` 可指定 token；未指定时服务端自动生成并在控制台输出 `/auth` URL。
  - 在 `src/server.mjs` 中新增 `/auth?token=...&tool=...` 入口，token 正确时设置 `HttpOnly; SameSite=Strict; Path=/; Max-Age=28800` cookie 并跳转到对应工具页。
  - 在 `src/server.mjs` 中对除 `/api/health` 和 `/auth` 外的 API 与静态页面启用鉴权；未授权请求返回 401，健康检查仅暴露服务状态。
  - 在 `src/tools/Manage-ProviderUI.ps1` 中生成随机 token，启动 node 时传入 `--auth-token`，并通过 `/auth` URL 打开浏览器，保持 `ccp manager` / `cdp manager` 默认一键打开。
  - `Manage-ProviderUI.ps1` 增加 manager state 文件，用于复用已运行的当前服务；复用前会验证 state token 是否能访问 `/api/tools`，并跳过旧版未鉴权服务。
  - `Manage-ProviderUI.ps1` 在 node 创建失败或 readiness 失败时清理 state 文件，避免 stale token。
  - 在 `src/web/app.js` 中统一使用 `apiFetch(..., { credentials: 'same-origin' })`，并集中解析 JSON/错误响应，确保前端请求携带同源授权 cookie。
  - 在 `tests/server-path-tests.ps1` 中增加未授权 API 访问应返回 401、通过 `/auth` 后可读取/保存配置的回归验证。
  - 更新 `README.md` 和 `Claude-Provider-Profiles-Kit/README.md`，说明管理页只监听 `127.0.0.1` 且通过 manager 命令自动携带随机本地 token。
  - 更新 `OPTIMIZATION.md`，将 Web UI 认证/授权保护项标记为完成，进度更新为 `17/19`。
  - 已运行验证：
    - `node --check src\server.mjs`：通过
    - `node --check src\web\app.js`：通过
    - `pwsh -NoProfile -File tests\server-path-tests.ps1`：`server-path-tests: PASS`
    - `pwsh -NoProfile -File tests\setup-tests.ps1`：`setup-tests: PASS`
    - `pwsh -NoProfile -File tests\install-dryrun-tests.ps1`：`install-dryrun-tests: PASS`
    - `pwsh -NoProfile -File tests\install-bootstrap-tests.ps1`：`install-bootstrap-tests: PASS`
    - PowerShell 语法解析检查：`powershell-parse: PASS`
    - 变更文件敏感信息扫描：`secret-scan-web-auth-files: PASS`
    - `git diff --check -- src/server.mjs src/web/app.js src/tools/Manage-ProviderUI.ps1 tests/server-path-tests.ps1 README.md Claude-Provider-Profiles-Kit\README.md OPTIMIZATION.md goal-1\tasks.md`：未发现 whitespace error；仅提示 Git 未来可能将 LF 文件转换为 CRLF。
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认。

## Task 6：审查并处理导入导出工具的产品化状态

- 状态：已完成
- 可验证标准：
  - 明确 `src/tools/Manage-ProviderProfiles.ps1` 是保留、集成、文档化还是移除。
  - 若保留，安装包部署、README/使用说明和测试一致。
  - 不泄露 API Key，导出说明准确。
- 完成记录：
  - 已决定保留并产品化 `src/tools/Manage-ProviderProfiles.ps1`，作为 `profiles` 子命令提供 `list` / `export` / `import`。
  - 导出默认移除 profile 中的 `apiKey` / `token` / `key` 明文密钥字段，保留 `apiKeyEnv` / `tokenEnv` / `keyEnv`，并写入只含变量名和是否设置状态的 `env-vars-info.json`。
  - 环境变量是否设置状态已与核心解析逻辑对齐，检查 `User` / `Process` / `Machine` 三个作用域，不写出变量值。
  - `list` 输出不会展示明文密钥或环境变量值，只显示“已配置”/“已设置”等状态。
  - `import` 会在覆盖现有配置前备份，并在导入文件包含明文密钥字段时输出警告。
  - 在 `src/tools/Invoke-Provider.ps1` 接入 `ccp profiles ...` / `cdp profiles ...` 路由：未给 action 或第一个参数是 `-Tool` 时默认执行 `list`；未显式 `-Tool` 时默认限定当前工具；显式 `-Tool all` 可处理两个工具。
  - 修复 PowerShell 字符串数组不能直接作为命名参数 splat 给脚本的问题，路由层改为解析 `profiles` 参数后使用 hashtable splat 调用导入导出脚本。
  - 修复成功执行 PowerShell 脚本后 `$LASTEXITCODE` 可能未初始化的问题，`profiles` 路由默认以 `0` 退出。
  - 已把 `profiles` 加入配置 ID / 快捷命令保留字，避免用户 profile 覆盖内置子命令。
  - 已在工具 registry 中登记 `profilesScript`，并在 `Claude-Provider-Profiles-Kit/install.ps1` 中纳入部署清单；安装提示加入 `ccp profiles` / `cdp profiles`。
  - 已更新 `README.md` 和 `Claude-Provider-Profiles-Kit/README.md`，增加配置备份与迁移说明，并明确导出默认脱敏、不导出 API Key 值。
  - 新增 `tests/profile-transfer-tests.ps1`，覆盖 list 脱敏、`ccp profiles` 路由、默认 action、`-Tool all`、导出脱敏、环境变量信息不泄露值、导入写入目标 USERPROFILE。
  - 更新 `tests/setup-tests.ps1`，验证 `profiles` 配置 ID 会被拒绝；更新 `tests/install-dryrun-tests.ps1`，验证安装 dry-run 会部署导入导出工具。
  - 已运行验证：
    - `pwsh -NoProfile -File tests\profile-transfer-tests.ps1`：`profile-transfer-tests: PASS`
    - `pwsh -NoProfile -File tests\setup-tests.ps1`：`setup-tests: PASS`
    - `pwsh -NoProfile -File tests\install-dryrun-tests.ps1`：`install-dryrun-tests: PASS`
    - `pwsh -NoProfile -File tests\install-bootstrap-tests.ps1`：`install-bootstrap-tests: PASS`
    - `pwsh -NoProfile -File tests\server-path-tests.ps1`：`server-path-tests: PASS`
    - `node --check src\server.mjs`：通过
    - `node --check src\web\app.js`：通过
    - PowerShell 语法解析检查：`powershell-parse: PASS`
    - `git diff --check`：未发现 whitespace error；仅提示 Git 未来可能将 LF 文件转换为 CRLF。
    - 变更文件敏感信息扫描：`secret-scan-changed-files: PASS`
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认。

## Task 7：大型全面检查-debug 循环（覆盖 Task 5-6）

- 状态：已完成
- 可验证标准：
  - 运行相关最小测试和全量关键检查。
  - 手动复核 Web UI / 工具文档 / 安装包一致性。
  - 修复检查中发现的问题，直到可重复通过。
- 完成记录：
  - 已全量复读 `goal-1/input.md`、`goal-1/plan.md`、`goal-1/tasks.md` 后执行本轮检查。
  - 已运行覆盖 Task 5-6 的相关测试：
    - `pwsh -NoProfile -File tests\server-path-tests.ps1`：`server-path-tests: PASS`
    - `pwsh -NoProfile -File tests\profile-transfer-tests.ps1`：`profile-transfer-tests: PASS`
    - `pwsh -NoProfile -File tests\setup-tests.ps1`：`setup-tests: PASS`
    - `pwsh -NoProfile -File tests\install-dryrun-tests.ps1`：`install-dryrun-tests: PASS`
    - `pwsh -NoProfile -File tests\install-bootstrap-tests.ps1`：`install-bootstrap-tests: PASS`
  - 已运行语法和静态检查：
    - `node --check src\server.mjs`：通过
    - `node --check src\web\app.js`：通过
    - PowerShell 语法解析检查，覆盖仓库内 `.ps1` / `.psm1`（排除 `.git` / `.playwright-mcp`）：`powershell-parse: PASS`
    - `git diff --check`：未发现 whitespace error；仅提示 Git 未来可能将 LF 文件转换为 CRLF。
    - 变更文件敏感信息扫描：`secret-scan-changed-files: PASS`
  - 手动复核 Web UI 鉴权时发现 `/api/health` 未授权响应仍暴露服务 `root` 路径和工具清单；已修复为未授权仅返回最小健康状态，授权请求才返回 `root` / `activeTool` / `tools`，并在 `tests/server-path-tests.ps1` 增加回归验证。
  - 手动复核 manager 启动路径时发现源码开发布局下 `Manage-ProviderUI.ps1` 可能查找仓库根目录的 `server.mjs`，而实际文件位于 `src\server.mjs`；已修复为优先选择源码布局 `src\server.mjs`，不存在时再使用安装布局根目录 `server.mjs`，并将 manager state 的 root 校验对齐到实际 server 根目录。
  - manager 复用探测改为优先读取 state token，并携带 `x-provider-profiles-token` 调用 `/api/health`；无可复用 token 的 token 服务不会被误判为可直接复用或空闲端口。
  - 手动复核 profiles 导入工具时发现从 `.zip` 导入后解压临时目录未清理；已在 `Import-Profiles` 中用 `finally` 清理解压目录，并在 `tests/profile-transfer-tests.ps1` 增加 zip 导入临时目录清理回归验证。
  - 已核对安装包部署清单仍包含 `Manage-ProviderProfiles.ps1`，README / Kit README 的 Web token 与 profiles 导入导出说明保持一致。
  - 已核对当前工作区未跟踪项 `.playwright-mcp/`、`Claude-Provider-Profiles-Kit/同事使用说明.md` 未被本 task 修改或回退。
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认。

## Task 8：补齐核心函数自动化测试

- 状态：已完成
- 可验证标准：
  - 覆盖 `Read-JsonFile`、`Convert-JsonObjectToHashtable`、`Resolve-ApiKey`、`Sync-ToolShortcuts` 中至少一个当前缺口。
  - 测试可在 Windows PowerShell / PowerShell 7 路径下稳定运行。
- 完成记录：
  - 新增 `tests/core-function-tests.ps1`，直接覆盖核心函数边界：
    - `Read-JsonFile`：验证顶层 JSON 对象转字典、空白文件返回空字典。
    - `Convert-JsonObjectToHashtable`：验证空对象、空数组、单元素数组、数组内对象、嵌套数组均能保留正确结构。
    - `Resolve-ApiKey`：验证明文 `apiKey`、`apiKeyEnv` 优先级、`apiKeyFile` 覆盖并裁剪空白、缺少密钥时报中文错误。
  - 检查中发现 `Convert-JsonObjectToHashtable` 对空 JSON 对象会保留为 `PSCustomObject`，空数组会被 PowerShell 函数返回语义转换成 `$null`，单元素数组也可能退化为标量；已修复为：
    - 所有 `PSCustomObject`（包括空对象）都转换为 ordered dictionary。
    - JSON 数组用 `List[object]` 收集并用 unary comma 返回，保留空数组、单元素数组和嵌套数组。
  - 更新 `README.md` 开发自检命令，加入 `pwsh -NoProfile -File tests\core-function-tests.ps1`。
  - 更新 `OPTIMIZATION.md`，将自动化测试项标记为完成，进度更新为 `18/19`。
  - 已运行验证：
    - `pwsh -NoProfile -File tests\core-function-tests.ps1`：`core-function-tests: PASS`
    - `pwsh -NoProfile -File tests\setup-tests.ps1`：`setup-tests: PASS`
    - `pwsh -NoProfile -File tests\profile-transfer-tests.ps1`：`profile-transfer-tests: PASS`
    - 受影响 PowerShell 语法解析检查：`affected-powershell-parse: PASS`
    - 全量 PowerShell 语法解析检查：`powershell-parse: PASS`
    - `git diff --check -- src\core\ProviderCore.psm1 tests\core-function-tests.ps1 README.md OPTIMIZATION.md goal-1\tasks.md`：未发现 whitespace error；仅提示 Git 未来可能将 LF 文件转换为 CRLF。
    - 变更文件敏感信息扫描：`secret-scan-task8-files: PASS`
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认。

## Task 9：复查快捷命令 PATH 污染风险与文档表达

- 状态：已完成
- 可验证标准：
  - README 和安装包说明清晰推荐 `ccp <profile>` / `cdp <profile>` 子命令。
  - 兼容快捷命令的风险说明准确，不破坏旧用户习惯。
- 完成记录：
  - 已检索历史记忆，确认安装 dry-run / `-AddPath` 曾存在真实 User PATH 副作用风险；本 task 不改测试隔离逻辑，只补齐用户可见说明。
  - 已复查 `src/core/ProviderCore.psm1` 的 `Sync-ToolShortcuts`：仍保留 `ccp-mi` / `cdp-ds` / `mi-claude` / 配置 ID 直呼命令等兼容 shim，且会拒绝内置命令冲突；本 task 未破坏旧用户习惯。
  - 更新 `README.md`：
    - 一键远程安装示例改为显式 `-AddPath`，避免“安装了但 `ccp` / `cdp` 不在 PATH”的默认体验。
    - 明确 `-AddPath` 会修改当前 Windows 用户级 PATH。
    - 常用命令段明确推荐文档、脚本和日常交流优先使用 `ccp <profile>` / `cdp <profile>` 子命令。
    - 明确兼容快捷命令和配置 ID 直呼命令可能受 PATH 顺序影响，提示不要把常见系统/工具命令名当作配置 ID。
  - 同步更新 `Claude-Provider-Profiles-Kit/README.md`，保持安装包说明与主 README 一致。
  - 更新 `Claude-Provider-Profiles-Kit/install.ps1` 安装完成提示：`-AddPath` 成功时说明只新增 `.claude\bin` / `.codex\bin` 到用户级 PATH，并推荐优先使用 `ccp <profile>` / `cdp <profile>` 子命令；未使用 `-AddPath` 时提示“用户级 PATH”。
  - 已运行 `pwsh -NoProfile -File tests\install-dryrun-tests.ps1`，结果：`install-dryrun-tests: PASS`。
  - 已运行 `pwsh -NoProfile -File tests\setup-tests.ps1`，结果：`setup-tests: PASS`。
  - 已运行受影响 PowerShell 语法解析检查，结果：`affected-powershell-parse: PASS`。
  - 已运行 `git diff --check -- README.md Claude-Provider-Profiles-Kit\README.md Claude-Provider-Profiles-Kit\install.ps1 OPTIMIZATION.md goal-1\tasks.md`，未发现 whitespace error；仅提示 Git 未来可能将 LF 文件转换为 CRLF。
  - 已对 Task 9 相关文件运行敏感信息扫描，结果：`secret-scan-task9-files: PASS`。
  - 过程中有一次 PowerShell 解析检查命令自身字符串插值写法错误导致 `ParserError`，已修正检查命令并重新通过；项目文件不受影响。
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认。

## Task 10：大型全面检查-debug 循环（覆盖 Task 8-9）

- 状态：已完成
- 可验证标准：
  - 全量关键测试通过。
  - 文档、安装包、源码状态一致。
  - 修复检查中发现的问题，直到可重复通过。
- 完成记录：
  - 已全量复读 `goal-1/input.md`、`goal-1/plan.md`、`goal-1/tasks.md` 后执行本轮检查。
  - 已运行全量关键 PowerShell 测试：
    - `pwsh -NoProfile -File tests\core-function-tests.ps1`：`core-function-tests: PASS`
    - `pwsh -NoProfile -File tests\setup-tests.ps1`：`setup-tests: PASS`
    - `pwsh -NoProfile -File tests\profile-transfer-tests.ps1`：`profile-transfer-tests: PASS`
    - `pwsh -NoProfile -File tests\install-dryrun-tests.ps1`：`install-dryrun-tests: PASS`
    - `pwsh -NoProfile -File tests\server-path-tests.ps1`：`server-path-tests: PASS`
    - `pwsh -NoProfile -File tests\install-bootstrap-tests.ps1`：`install-bootstrap-tests: PASS`
  - 已运行 Node 语法检查：
    - `node --check src\server.mjs`：通过
    - `node --check src\web\app.js`：通过
  - 已运行 PowerShell 语法解析检查，覆盖仓库内 `.ps1` / `.psm1`（排除 `.git` / `.playwright-mcp`）：`powershell-parse: PASS`。
  - 已运行 `git diff --check`，未发现 whitespace error；仅提示 Git 未来可能将 LF 文件转换为 CRLF。
  - 已运行变更文件敏感信息扫描：
    - 初始宽松规则命中变量名和测试用假密钥（如 `plain-claude-key-for-test` / `sk-launcher-fail`），判定不是真实泄漏。
    - 改用真实 token 形态的精确规则复扫，结果：`secret-scan-changed-files-refined: PASS`。
  - 已复核 Task 8-9 相关一致性：
    - `README.md` / `Claude-Provider-Profiles-Kit/README.md` 均包含 `core-function-tests` / `profile-transfer-tests`、Web 本地 token、profiles 导入导出、PATH 风险与 `ccp <profile>` / `cdp <profile>` 推荐说明。
    - `Claude-Provider-Profiles-Kit/install.ps1` 部署清单仍包含 `src\tools\Manage-ProviderProfiles.ps1`，安装输出包含 `ccp profiles` / `cdp profiles` 和用户级 PATH 说明。
    - `src/core/ProviderCore.psm1` 仍将 `profiles` 作为配置 ID / 快捷命令保留字，并保留兼容快捷命令生成逻辑。
    - `tests/install-dryrun-tests.ps1` 明确验证 `-DryRun -AddPath` 不修改真实 User PATH，并在 `finally` 中恢复 User PATH。
    - `OPTIMIZATION.md` 保持 `18/19`，没有把仍需最终审视的 PATH 风险项伪装为完全完成。
  - 本轮检查未发现需要新增修复的问题。
  - 当前未跟踪项 `.playwright-mcp/`、`Claude-Provider-Profiles-Kit/同事使用说明.md`、`src/tools/Manage-ProviderProfiles.ps1`、`tests/core-function-tests.ps1`、`tests/profile-transfer-tests.ps1`、`goal-1/` 均未被回退。
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认。

## Task 11：最终最大 review 与修缮

- 状态：已完成
- 可验证标准：
  - 从用户安装路径、CLI 启动路径、Web 管理路径、代码质量、安全性、文档和测试覆盖全面审查。
  - 所有发现的问题已修复或明确记录为暂不处理且有理由。
  - 当前 goal 的显式要求均有证据证明完成。
- 完成记录：
  - 已读取今日 Working Memory，结果为空；本轮以当前工作区、`goal-1/input.md`、`goal-1/plan.md`、`goal-1/tasks.md` 为准。
  - 已从用户安装路径、CLI 启动路径、Web 管理路径、安装包、配置导入导出、安全边界、文档和测试覆盖进行最终 review。
  - 最终审查发现并修复 `OPTIMIZATION.md` 状态表达问题：
    - 已完成的 5 / 7 / 11 项标题补齐 `✅`。
    - `ProviderCore.psm1` 行数从过期的 `~926 行` 更新为当前约 `1277 行`。
  - 最终审查发现并修复开发入口问题：
    - `.\init.ps1 web` 原本直接打开 `http://127.0.0.1:15722/` 并裸启动 `server.mjs`，但当前 Web UI 已启用 token 鉴权，会导致开发入口打开后未授权。
    - 已改为复用 `src\tools\Manage-ProviderUI.ps1`，由统一 manager 逻辑生成 token、复用/启动服务并打开 `/auth` URL。
    - `.\init.ps1 help` 同步补充 `ccp profiles` / `cdp profiles`。
  - 最终审查发现并修复 README 自检命令不完整：
    - `README.md` 开发自检命令补充 `tests\install-dryrun-tests.ps1` 和 `tests\install-bootstrap-tests.ps1`，与实际最终验证范围一致。
  - 已确认 `OPTIMIZATION.md` 仍保留 `18/19`，第 16 项 PATH 污染风险仅标记“部分缓解”，原因是兼容快捷命令仍需保留以不破坏旧用户习惯；当前通过文档推荐子命令和冲突校验降低风险。
  - 已确认安装包部署清单包含新增产品化工具 `src\tools\Manage-ProviderProfiles.ps1`，README / Kit README / install 输出 / Invoke 路由均包含 `profiles` 用法。
  - 已确认 Web UI 未授权健康检查不暴露 root/tools，授权后才返回 manager 复用所需信息；`server-path-tests` 覆盖该行为。
  - 已确认导入导出默认脱敏、环境变量信息不导出值、zip 导入临时目录清理、覆盖前备份均有测试覆盖。
  - 已运行最终验证：
    - `pwsh -NoProfile -File tests\core-function-tests.ps1`：`core-function-tests: PASS`
    - `pwsh -NoProfile -File tests\setup-tests.ps1`：`setup-tests: PASS`
    - `pwsh -NoProfile -File tests\server-path-tests.ps1`：`server-path-tests: PASS`
    - `pwsh -NoProfile -File tests\profile-transfer-tests.ps1`：`profile-transfer-tests: PASS`
    - `pwsh -NoProfile -File tests\install-dryrun-tests.ps1`：`install-dryrun-tests: PASS`
    - `pwsh -NoProfile -File tests\install-bootstrap-tests.ps1`：`install-bootstrap-tests: PASS`
    - `node --check src\server.mjs`：通过
    - `node --check src\web\app.js`：通过
    - PowerShell 语法解析检查，覆盖仓库内 `.ps1` / `.psm1`（排除 `.git` / `.playwright-mcp`）：`powershell-parse: PASS`
    - `git diff --check`：未发现 whitespace error；仅提示 Git 未来可能将 LF 文件转换为 CRLF。
    - 变更文件精确敏感信息扫描：`secret-scan-final: PASS`
  - 本 task 未执行 `git commit`：项目 Git 规范要求修改类 Git 操作需先确认；当前所有代码和文档变更保留在工作区，等待用户确认提交。
