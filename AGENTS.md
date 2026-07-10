# AI CLI Switcher AI 开发指南

## 项目概述

**AI CLI Switcher** 是一个 Windows 下的 AI CLI 多供应商切换器,用同一套方式管理 Claude Code 和 Codex CLI 的不同供应商配置(小米 MiMo、DeepSeek、OpenRouter、Azure OpenAI 等)。

**核心特性**:
- PowerShell + Node.js 架构,零外部依赖
- 工具注册表设计,所有 AI CLI 通过统一模式扩展
- 临时会话环境隔离,不污染全局环境变量
- Web 管理界面(Brutalist 风格,纯 Vanilla JS)
- 配置备份/导入/导出,自动脱敏 API Key

---

## 技术栈

| 层次 | 技术 |
|------|------|
| **核心逻辑** | PowerShell 7+ (模块化) |
| **Web UI** | Node.js 18+ HTTP 服务 + 纯 Vanilla JS 前端 |
| **配置存储** | JSON (UTF-8 无 BOM) |
| **CLI 参数覆盖** | TOML (Codex `-c` 参数) |
| **测试** | PowerShell 脚本 + Node.js `--check` |
| **CI/CD** | GitHub Actions (PSScriptAnalyzer + JS 语法检查) |

---

## 关键目录与模块职责

```
项目根/
├── src/
│   ├── core/
│   │   └── ProviderCore.psm1      # 核心模块(工具注册表、配置管理、会话隔离)
│   ├── tools/
│   │   ├── Invoke-Provider.ps1         # 通用供应商启动器
│   │   ├── Sync-Shortcuts.ps1          # 通用快捷命令同步
│   │   ├── Manage-ProviderUI.ps1       # 通用 Web UI 启动器
│   │   ├── Manage-ProviderProfiles.ps1 # 配置导入导出
│   │   ├── Import-Core.ps1             # 核心模块加载器
│   │   ├── claude/                     # Claude Code thin wrapper (3 文件)
│   │   └── codex/                      # Codex CLI thin wrapper (3 文件)
│   ├── web/
│   │   ├── index.html            # 单页面应用
│   │   ├── app.js                # 前端逻辑(无框架)
│   │   └── styles.css            # Brutalist 设计风格
│   └── server.mjs                # Node.js HTTP 服务(零依赖)
├── Claude-Provider-Profiles-Kit/ # 发布包
│   ├── install.ps1               # 安装脚本(支持远程引导)
│   ├── providers.example.json    # Claude Code 配置模板
│   └── codex-providers.example.json  # Codex CLI 配置模板
├── config/                       # 额外配置模板
├── tests/                        # 6 个测试文件
├── .github/workflows/ci.yml      # CI 配置
├── init.ps1                      # 开发环境快捷入口
└── README.md                     # 用户文档
```

**安装后目录**:
```
%USERPROFILE%\
├── .claude\
│   ├── provider-profiles\       # 运行时目录
│   │   ├── providers.json       # 用户配置
│   │   ├── server.mjs
│   │   ├── web\
│   │   └── src\                 # 完整源码副本
│   └── bin\                     # 快捷命令
│       ├── ccp.ps1              # 主命令
│       ├── ccp-setup.ps1
│       ├── ccp-mi.ps1           # 供应商快捷命令
│       └── mi.ps1               # 直呼快捷命令
└── .codex\
    └── (同上结构)
```

---

## 核心架构与数据流

### 1. 工具注册表机制

所有 AI CLI 工具通过 `Register-ProviderTool` 注册到全局注册表:

```powershell
# 在 ProviderCore.psm1 中
Register-ProviderTool -Name 'claude' -Config @{
    displayName = 'Claude Code'
    commandPrefix = 'ccp'               # 主命令前缀
    binaryName = 'claude'               # 实际 CLI 命令
    configPath = '~\.claude\provider-profiles\providers.json'
    binPath = '~\.claude\bin'
    defaultShortcutSuffix = 'claude'    # 快捷命令后缀
}
```

**Thin Wrapper 模式**:
```powershell
# src/tools/claude/Invoke-ClaudeProvider.ps1
#!/usr/bin/env pwsh
$ToolName = 'claude'
$ProviderArgs = $args
. "$PSScriptRoot\..\Invoke-Provider.ps1"  # 调用通用启动器
```

### 2. 配置加载与验证流程

```
用户执行 ccp mi
  ↓
Invoke-ClaudeProvider.ps1 (wrapper)
  ↓
Invoke-Provider.ps1 (通用启动器)
  ↓
Import-ProviderCore (加载核心模块)
  ↓
Get-ProviderTool -Name 'claude'
  ↓
Read-JsonFile -Path '~\.claude\provider-profiles\providers.json'
  ↓
Assert-ProviderProfileInput (校验 profileId、baseUrl 格式)
  ↓
Resolve-ApiKey (优先级: apiKeyFile > apiKeyEnv > apiKey)
  ↓
New-EnvSession (创建环境变量会话快照)
  ↓
Set-EnvSessionValue (注入 ANTHROPIC_BASE_URL、ANTHROPIC_API_KEY、extraEnv)
  ↓
调用 claude --model xxx 其他参数
  ↓
Restore-EnvSession (恢复原环境变量)
```

### 3. 快捷命令生成流程

```
用户执行 ccp sync
  ↓
Sync-ClaudeShortcuts.ps1 (wrapper)
  ↓
Sync-Shortcuts.ps1 (通用同步器)
  ↓
Sync-ToolShortcuts -ToolName 'claude'
  ↓
读取 providers.json
  ↓
为每个 profileId 生成 4 种命令:
  - ccp mi              (子命令,推荐)
  - ccp-mi.ps1          (兼容)
  - mi-claude.ps1       (兼容)
  - mi.ps1              (直呼,可能冲突)
  ↓
写入 ~\.claude\bin\*.ps1
  ↓
生成额外命令:
  - ccp-setup.ps1
  - ccp-list.ps1
  - ccp-sync.ps1
  - ccp-manager.ps1
```

### 4. Web UI 前后端交互

```
用户执行 ccp manager
  ↓
Manage-ClaudeUI.ps1 启动 server.mjs --auth-token=xxx
  ↓
浏览器打开 http://127.0.0.1:15723/auth?token=xxx&tool=claude
  ↓
后端设置 HttpOnly Cookie + 302 跳转
  ↓
前端加载 app.js
  ↓
GET /api/claude/config → 渲染配置卡片
  ↓
用户编辑表单 → markDirty()
  ↓
用户点击"保存并同步"
  ↓
collectConfig() 收集数据 → PUT /api/claude/config
  ↓
后端: writeConfig() → 调用 pwsh Sync-ClaudeShortcuts.ps1
  ↓
返回 { config, syncOutput }
  ↓
前端: renderConfig() → markClean() → 显示成功
```

---

## 核心函数清单

### ProviderCore.psm1 导出函数

| 函数 | 用途 |
|------|------|
| `Read-JsonFile` | 读取 JSON 配置文件,转为 Hashtable |
| `Write-Utf8NoBomJson` | 写入 JSON 配置(UTF-8 无 BOM) |
| `ConvertTo-TomlLiteral` | 序列化为 TOML 字面量(Codex `-c` 参数) |
| `Resolve-ApiKey` | 解析 API Key(优先级: file > env > direct) |
| `Assert-ProviderProfileInput` | 校验 profileId、baseUrl、命令冲突 |
| `Upsert-ProviderProfile` | 新增或更新供应商配置 |
| `Invoke-ProviderSetup` | 交互式配置向导 |
| `Select-ProfileFromMenu` | 交互式选择供应商 |
| `Register-ProviderTool` | 注册工具到全局注册表 |
| `Get-ProviderTool` | 获取工具注册信息 |
| `New-EnvSession` | 创建环境变量会话快照 |
| `Set-EnvSessionValue` | 临时注入环境变量 |
| `Restore-EnvSession` | 恢复会话前环境变量 |
| `Invoke-ProviderSession` | 启动供应商会话(注入环境 + 调用 CLI + 恢复) |
| `Sync-ToolShortcuts` | 同步工具的所有快捷命令 |

---

## 本地启动、构建、测试命令

### 开发环境初始化

```powershell
# 1. 检查依赖
.\init.ps1 check

# 2. 配置供应商
.\init.ps1 setup

# 3. 同步快捷命令
.\init.ps1 sync

# 4. 启动 Web 管理台
.\init.ps1 web
```

### 测试命令

```powershell
# 快速测试(核心功能)
pwsh -NoProfile -File tests\core-function-tests.ps1
pwsh -NoProfile -File tests\setup-tests.ps1

# 完整测试(发布前)
pwsh -NoProfile -File tests\core-function-tests.ps1
pwsh -NoProfile -File tests\setup-tests.ps1
pwsh -NoProfile -File tests\install-dryrun-tests.ps1
pwsh -NoProfile -File tests\install-bootstrap-tests.ps1
pwsh -NoProfile -File tests\profile-transfer-tests.ps1
pwsh -NoProfile -File tests\server-path-tests.ps1

# JavaScript 语法检查
node --check src\server.mjs
node --check src\web\app.js

# 静态检查
Get-ChildItem -Recurse -Include '*.ps1','*.psm1' |
  Where-Object { $_.FullName -notlike '*node_modules*' } |
  ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Severity Error }
```

### 常用开发命令

```powershell
# 查看配置列表
ccp list
cdp list

# 启动指定供应商
ccp mi
cdp ds

# Web 管理页面
ccp manager
cdp manager

# 手动同步快捷命令
ccp sync
cdp sync

# 配置导入导出
ccp profiles export -OutDir "$HOME\Desktop\backup"
ccp profiles import -InDir "$HOME\Desktop\backup"
```

---

## 修改代码前必须阅读的文件

| 修改场景 | 必读文件 |
|---------|---------|
| **修改核心逻辑** | `src/core/ProviderCore.psm1` |
| **修改启动流程** | `src/tools/Invoke-Provider.ps1` |
| **修改快捷命令同步** | `src/tools/Sync-Shortcuts.ps1` |
| **修改 Web UI** | `src/web/app.js`, `src/web/index.html`, `src/server.mjs` |
| **修改安装脚本** | `Claude-Provider-Profiles-Kit/install.ps1` |
| **新增工具支持** | `src/core/ProviderCore.psm1` (Register-ProviderTool) + `src/tools/<tool>/` (3 wrapper) |
| **修改配置字段** | `config/*.example.json` + Web UI 3 处 + 对应启动脚本 |

---

## 核心架构约定

### 1. 文件编码与读写

文本文件统一使用 UTF-8；JSON 配置和新建文本文件使用 UTF-8 无 BOM。修改既有文件时应保留原有换行风格，并在写回后复读确认。

需要精确控制编码时可使用 .NET 文件 API：
```powershell
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
```

### 2. 配置文件格式

**Claude Code** (`providers.json`):
```json
{
  "version": 1,
  "profiles": {
    "mi": {
      "displayName": "Xiaomi MiMo",
      "baseUrl": "https://mimo.ai/api",
      "authEnv": "ANTHROPIC_AUTH_TOKEN",
      "apiKeyEnv": "MI_CLAUDE_API_KEY",
      "model": "",
      "haikuModel": "",
      "sonnetModel": "",
      "opusModel": "",
      "cliModel": "",
      "extraEnv": { "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1" }
    }
  }
}
```

**Codex CLI** (`providers.json`):
```json
{
  "version": 1,
  "profiles": {
    "ds": {
      "displayName": "DeepSeek",
      "baseUrl": "https://api.deepseek.com",
      "apiKeyEnv": "DS_CODEX_API_KEY",
      "model": "deepseek-chat",
      "modelContextWindow": 131072,
      "wireApi": "responses",
      "supportsWebsockets": false,
      "queryParams": {},
      "httpHeaders": {},
      "extraEnv": {}
    }
  }
}
```

### 3. API Key 安全处理

**优先级**(从高到低):
1. `apiKeyFile` — 从本地文件读取
2. `apiKeyEnv` — 从环境变量读取(推荐)
3. `apiKey` — 明文存配置文件(不推荐)

**配置向导默认行为**:
- 将 API Key 写入用户环境变量
- 不写入 `providers.json`

**配置导出行为**:
- 自动移除 `apiKey`、`token`、`key` 字段
- 保留 `apiKeyEnv` 名称但不导出环境变量值

### 4. 环境变量会话隔离

**临时注入**:
```powershell
# 启动前快照
$session = New-EnvSession
Add-EnvSessionKey -Session $session -Key 'ANTHROPIC_BASE_URL'
Set-EnvSessionValue -Session $session -Key 'ANTHROPIC_BASE_URL' -Value $baseUrl

# 调用 CLI
& claude --model $model

# 恢复环境
Restore-EnvSession -Session $session
```

**跨终端隔离**:
- 每个终端窗口独立注入
- 进程退出后自动清理
- 不污染全局环境变量

### 5. 快捷命令命名规则

**保留命令**(不允许作为 profileId):
- `list`, `ls`, `help`, `usage`
- `sync`, `manager`, `manage`
- `setup`, `add`, `configure`
- `profiles`

**命令冲突检测**:
- 检查 `profileId` 是否与内置命令冲突
- 检查 `shortcut` 是否与已有命令冲突
- 检查直呼命令是否与系统命令同名(警告)

---

## 已有能力与复用入口

### 配置管理

- ✅ 读取/写入 JSON 配置(UTF-8 无 BOM)
- ✅ 交互式配置向导(Invoke-ProviderSetup)
- ✅ 配置校验(Assert-ProviderProfileInput)
- ✅ 配置备份/导入/导出(Manage-ProviderProfiles.ps1)
- ✅ API Key 脱敏处理

### 环境变量管理

- ✅ 会话快照与恢复
- ✅ 临时注入不污染全局
- ✅ 支持 `extraEnv` 自定义环境变量

### 快捷命令

- ✅ 自动生成 4 种命令形式
- ✅ 命令冲突检测
- ✅ 保留命令保护
- ✅ PATH 自动配置

### Web UI

- ✅ Per-tool 内存状态缓存(切换工具保留未保存改动)
- ✅ 前后端交互(认证、读配置、保存配置、同步快捷命令)
- ✅ 表单校验(前端基础 + 后端严格)
- ✅ 本地 token 授权(timingSafeEqual 防时序攻击)
- ✅ 路径遍历防护

### 测试

- ✅ 环境隔离测试(不污染开发环境)
- ✅ 核心函数单元测试
- ✅ 配置管理集成测试
- ✅ 安装脚本 DryRun 测试
- ✅ Web 服务路径安全测试

---

## 常见开发任务路径

### 任务 1: 新增工具支持(如 OpenCode)

1. 在 `ProviderCore.psm1` 中调用 `Register-ProviderTool`
2. 创建 `src/tools/opencode/` 目录
3. 复制 `claude/` 下 3 个 wrapper 文件,修改 `$ToolName = 'opencode'`
4. 在 `install.ps1` 中增加部署逻辑
5. 在 `src/server.mjs` 和 `src/web/app.js` 增加工具元数据
6. 运行所有测试

### 任务 2: 新增配置字段

**后端**:
1. 修改 `config/*.example.json` 增加示例
2. 修改对应工具的 `Invoke-*Provider.ps1` 处理新字段

**Web UI**(同步修改 3 处):
1. `src/server.mjs` 的 `TOOLS[tool].fields`
2. `src/web/app.js` 的 `TOOL_META[tool]`
3. `src/web/index.html` 的 `<template>` 添加表单字段

### 任务 3: 修改 Web UI 样式

1. 用 PowerShell 工具读取 `src/web/styles.css`
2. 修改 CSS 变量或 Brutalist 风格细节
3. 写回文件
4. 刷新浏览器验证(无需重启服务)

### 任务 4: 调试启动失败

1. 检查 `providers.json` 格式是否合法
2. 检查 API Key 环境变量: `$env:MI_CLAUDE_API_KEY`
3. 手动运行启动器: `pwsh -NoProfile -File src/tools/claude/Invoke-ClaudeProvider.ps1 mi`
4. 检查 `Resolve-ApiKey` 逻辑
5. 检查 `claude` 命令是否在 PATH

### 任务 5: 调试测试失败

1. 单独运行失败的测试文件
2. 检查临时目录权限
3. 检查 Node.js 版本(需要 18+)
4. 检查端口占用(Web 服务测试需要空闲端口)

---

## 高风险区域与禁止随意改动

### 🔴 高风险区域

1. **环境变量会话管理**(`New-EnvSession`、`Restore-EnvSession`)
   - 错误修改会导致环境污染或无法恢复

2. **API Key 解析逻辑**(`Resolve-ApiKey`)
   - 错误修改会导致密钥泄露或无法读取

3. **配置校验逻辑**(`Assert-ProviderProfileInput`)
   - 放宽校验会导致命令冲突或注入攻击

4. **快捷命令同步**(`Sync-ToolShortcuts`)
   - 错误修改会生成错误的 shim 文件,导致命令失效

5. **Web UI 认证机制**(`server.mjs` 的 token 校验)
   - 错误修改会导致未授权访问

### ❌ 禁止事项

- ❌ 不要在未确认编码和换行风格时批量重写文件
- ❌ 不要跳过 `Assert-ProviderProfileInput` 校验
- ❌ 不要在配置文件中明文存储 API Key(应使用环境变量)
- ❌ 不要破坏 Web UI 的 per-tool 内存机制
- ❌ 不要引入 npm 依赖(保持零依赖)
- ❌ 不要修改 `version: 1` 格式(预留版本迁移)

---

## 完成修改后的验证清单

### 修改核心模块后

- [ ] 运行 `tests\core-function-tests.ps1`
- [ ] 运行 `tests\setup-tests.ps1`
- [ ] 手动测试: `ccp list`, `ccp mi`

### 修改 Web UI 后

- [ ] `node --check src\server.mjs`
- [ ] `node --check src\web\app.js`
- [ ] 运行 `tests\server-path-tests.ps1`
- [ ] 启动 Web UI,操作验证(新增、编辑、保存、切换工具)

### 修改安装脚本后

- [ ] 运行 `tests\install-dryrun-tests.ps1`
- [ ] 运行 `tests\install-bootstrap-tests.ps1`
- [ ] 在干净 Windows 虚拟机测试完整安装流程

### 发布前

- [ ] 运行所有 6 个测试文件
- [ ] PSScriptAnalyzer 静态检查
- [ ] JavaScript 语法检查
- [ ] 手动烟雾测试: `ccp`, `cdp`, `ccp manager`
- [ ] 检查 README.md 是否需要更新
- [ ] 检查 CHANGELOG 是否需要更新

---

## 环境变量与外部依赖

### 必需依赖

- **PowerShell**: 7+
- **Node.js**: 18+ (仅 Web UI)
- **claude**: Claude Code CLI 本体(可选)
- **codex**: Codex CLI 本体(可选)

### API Key 环境变量(按需)

```powershell
$env:MI_CLAUDE_API_KEY = "sk-xxx"
$env:DS_CODEX_API_KEY = "sk-xxx"
$env:OPENROUTER_CLAUDE_API_KEY = "sk-xxx"
```

### 可选环境变量

- `CPS_BOOTSTRAP_URL` — 自定义远程安装源
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` — 禁用 Claude Code 遥测

---

## 常见问题排查

### PATH 未生效

**症状**: 提示 `ccp` 或 `cdp` 找不到

**解决**:
1. 重新打开终端
2. 检查: `$env:Path -split ';' | Select-String '\.(claude|codex)\\bin'`
3. 手动加载: `$env:Path += ";$env:USERPROFILE\.claude\bin"`

### API Key 未生效

**症状**: 启动 CLI 时提示缺少 API Key

**解决**:
1. 检查环境变量: `$env:MI_CLAUDE_API_KEY`
2. 重新设置: `[Environment]::SetEnvironmentVariable('MI_CLAUDE_API_KEY', 'sk-xxx', 'User')`
3. 重新打开终端

### 快捷命令失效

**症状**: 运行 `ccp-mi` 报错

**解决**:
1. 手动同步: `ccp sync`
2. 检查 shim 文件: `Get-Content -LiteralPath $env:USERPROFILE\.claude\bin\ccp-mi.ps1 -Raw`
3. 检查配置文件: `Get-Content -LiteralPath $env:USERPROFILE\.claude\provider-profiles\providers.json -Raw -Encoding UTF8`

### Web UI 保存失败

**症状**: 点击保存后提示错误

**解决**:
1. 检查浏览器 DevTools Console
2. 检查后端日志(PowerShell 终端输出)
3. 手动同步: `ccp sync`
4. 检查 PowerShell 执行策略: `Get-ExecutionPolicy`
