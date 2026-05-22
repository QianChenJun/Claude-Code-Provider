# AI CLI Switcher

**通用 AI CLI 多供应商切换器。一个平台，所有工具，零干扰。**

| 工具 | 前缀 | CLI | 状态 |
|------|--------|-----|--------|
| **Claude Code** | `ccp` | Claude Code | 稳定 |
| **Codex CLI** | `cdp` | Codex CLI | 稳定 |
| `ocp` | OpenCode | [计划中](#开发者指南添加新工具) |

> 仅限 Windows · PowerShell 5.1+ · MIT License

---

## 解决什么问题

同时使用多个 AI CLI 工具和供应商非常痛苦：

- 切换供应商意味着手动改配置文件
- 不同终端窗口通过共享环境变量互相干扰
- 每个工具有自己的配置格式、密钥管理和各种怪癖

**AI CLI Switcher** 将每款 AI CLI 统一到一套架构下。三条平等命令 — `ccp`（Claude Code）、`cdp`（Codex CLI）、`ocp`（OpenCode）— 同样的模式、同样的能力。一条命令如 `ccp mi` 或 `cdp ds`，你的终端就获得了隔离的供应商环境。退出即恢复，不留痕迹。

```
终端 1:  ccp mi    → 小米 MiMo（Claude Code）
终端 2:  ccp ds    → DeepSeek（Claude Code）
终端 3:  cdp mi    → 小米 MiMo（Codex CLI）
终端 4:  cdp ds    → DeepSeek（Codex CLI）
          ↑ 全部同时运行，互不干扰
```

---

## 架构

```
┌──────────────────────────────────────────────────────────────┐
│                     Bin Shims（快捷命令）                      │
│     ccp（Claude Code）   cdp（Codex CLI）  ocp（OpenCode）    │
└─────────┬────────────────────┬─────────────────────┬────────┘
          │                    │                     │
          ▼                    ▼                     ▼
┌──────────────────────────────────────────────────────────────┐
│              工具 Wrapper（~3 行，设 $ToolName）               │
│      Invoke-ClaudeProvider      Invoke-CodexProvider          │
└─────────┬────────────────────┬───────────────────────────────┘
          │                    │
          ▼                    ▼
┌──────────────────────────────────────────────────────────────┐
│              通用脚本（dot-source 模式）                        │
│   Invoke-Provider.ps1   Sync-Shortcuts.ps1   Manage-Prov...  │
└─────────┬────────────────────┬───────────────────────────────┘
          │                    │
          ▼                    ▼
┌──────────────────────────────────────────────────────────────┐
│                   ProviderCore.psm1                           │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ JSON/TOML  │  │  环境变量    │  │  交互菜单 / 校验     │  │
│  │ 工具函数   │  │  会话隔离    │  │  快捷命令同步        │  │
│  └────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────────┐│
│  │  工具注册表（Register-ProviderTool / Get-ProviderTool）   ││
│  └──────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────┐
│           统一 Web 管理界面（server.mjs）                      │
│          标签页：Claude Code | Codex CLI                      │
│               http://127.0.0.1:15723/                        │
└──────────────────────────────────────────────────────────────┘
```

核心模块处理**共性**，每个工具只定义**如何启动**其 CLI。

---

## 目录结构

```
.
├── src/
│   ├── core/
│   │   └── ProviderCore.psm1               # 共享核心模块（全部逻辑）
│   ├── tools/
│   │   ├── Import-Core.ps1                 # 引导：定位并导入核心模块
│   │   ├── Invoke-Provider.ps1             # [通用] 供应商启动器
│   │   ├── Sync-Shortcuts.ps1              # [通用] 快捷命令同步
│   │   ├── Manage-ProviderUI.ps1           # [通用] Web 管理界面启动
│   │   ├── claude/
│   │   │   ├── Invoke-ClaudeProvider.ps1   # Wrapper（3 行）
│   │   │   ├── Sync-ClaudeShortcuts.ps1    # Wrapper（3 行）
│   │   │   └── Manage-ClaudeUI.ps1         # Wrapper（5 行）
│   │   └── codex/
│   │       ├── Invoke-CodexProvider.ps1    # Wrapper（3 行）
│   │       ├── Sync-CodexShortcuts.ps1     # Wrapper（3 行）
│   │       └── Manage-CodexUI.ps1          # Wrapper（5 行）
│   ├── web/
│   │   ├── index.html                      # 标签页管理界面
│   │   ├── app.js                          # 前端逻辑
│   │   └── styles.css                      # 样式
│   └── server.mjs                          # 统一 HTTP 服务
│
├── config/
│   ├── providers.example.json              # Claude 配置模板
│   └── codex-providers.example.json        # Codex 配置模板
│
├── Claude-Provider-Profiles-Kit/           # 分发包（用于 zip 发布）
│   ├── install.ps1                         # 安装脚本
│   ├── README.md                           # 用户文档
│   └── *.example.json                      # 配置模板
│
├── .github/workflows/
│   ├── ci.yml                              # 代码检查（PSScriptAnalyzer + JS 语法）
│   └── release.yml                         # 打包 zip + GitHub Release
│
└── OPTIMIZATION.md                         # 可优化项清单及进度
```

---

## 快速开始

### 安装

```powershell
# 从 zip 安装（同事分发）：从 Releases 下载 Claude-Provider-Profiles-Kit.zip
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath

# 从源码安装（开发者）：
git clone https://github.com/QianChenJun/Claude-Provider-Profiles.git
cd Claude-Provider-Profiles\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

重启终端。

### 配置 API Key

```powershell
# Claude Code 供应商
[Environment]::SetEnvironmentVariable('MI_CLAUDE_API_KEY', '你的小米key', 'User')
[Environment]::SetEnvironmentVariable('DS_CLAUDE_API_KEY', '你的DeepSeek key', 'User')

# Codex CLI 供应商
[Environment]::SetEnvironmentVariable('MI_CODEX_API_KEY', '你的小米key', 'User')
[Environment]::SetEnvironmentVariable('DS_CODEX_API_KEY', '你的DeepSeek key', 'User')
```

设置后重启终端。

### 使用

```powershell
# Claude Code
ccp mi                    # 用小米 MiMo 启动 Claude
ccp ds                    # 用 DeepSeek 启动 Claude
ccp                       # 交互菜单

# Codex CLI
cdp mi                    # 用小米 MiMo 启动 Codex
cdp ds                    # 用 DeepSeek 启动 Codex
cdp                       # 交互菜单

# 管理
ccp manager               # Claude 供应商 Web 管理界面
cdp manager               # Codex 供应商 Web 管理界面
```

---

## 命令参考

所有工具遵循**完全相同的命令模式**——只有前缀不同。

### Claude Code（`ccp`）

```powershell
ccp                            # 交互菜单（选择供应商）
ccp mi                         # 直接启动：小米 MiMo
ccp ds                         # 直接启动：DeepSeek
ccp mi --model claude-opus-4-7 # 本次覆盖模型
ccp mi -p "总结一下"            # 非交互模式
ccp list                       # 列出所有已配置供应商
ccp sync                       # 重新生成快捷命令
ccp manager                    # 打开 Web 管理界面
```

### Codex CLI（`cdp`）

```powershell
cdp                            # 交互菜单
cdp mi                         # 直接启动：小米 MiMo
cdp ds                         # 直接启动：DeepSeek
cdp ds --model deepseek-chat   # 本次覆盖模型
cdp list                       # 列出所有已配置供应商
cdp sync                       # 重新生成快捷命令
cdp manager                    # 打开 Web 管理界面
```

### 快捷命令

每个配置自动生成三种快捷命令（以 `mi` 为例）：

```powershell
mi              # 配置 ID 直呼（最简）
mi-claude       # 后缀模式
ccp mi          # 前缀模式
```

所有命令等价，任选其一即可。

### 交互菜单

不带参数运行 `ccp` 或 `cdp` 会显示交互菜单：

```
Claude Code Provider 配置
请选择配置：
  1. ccp-ds                 DeepSeek
  2. ccp-mi                 小米 MiMo

  L. 查看列表    S. 同步快捷命令    M. 打开管理页面    H. 帮助    Q. 退出
输入编号或配置 ID:
```

---

## 配置

### Claude Code

文件：`%USERPROFILE%\.claude\provider-profiles\providers.json`

```json
{
  "version": 1,
  "profiles": {
    "mi": {
      "displayName": "小米 MiMo",
      "baseUrl": "https://your-provider.com/anthropic",
      "authEnv": "ANTHROPIC_AUTH_TOKEN",
      "apiKeyEnv": "MI_CLAUDE_API_KEY",
      "model": "claude-sonnet-4-6",
      "extraEnv": {
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
      }
    }
  }
}
```

| 字段 | 说明 |
|------|------|
| `displayName` | Web UI 和菜单中显示的名称 |
| `baseUrl` | Anthropic 兼容接口地址（必填） |
| `authEnv` | 认证方式：`ANTHROPIC_AUTH_TOKEN` 或 `ANTHROPIC_API_KEY` |
| `apiKey` | 明文 API Key（不推荐，建议用 apiKeyEnv） |
| `apiKeyEnv` | 存放 API Key 的 Windows 环境变量名（推荐） |
| `apiKeyFile` | 从文件读取 Key 的路径 |
| `model` | 默认模型（`ANTHROPIC_MODEL` 环境变量） |
| `haikuModel` / `sonnetModel` / `opusModel` | 模型族映射覆盖 |
| `cliModel` | 默认 `--model` CLI 参数 |
| `extraEnv` | 额外环境变量（JSON 对象） |

### Codex CLI

文件：`%USERPROFILE%\.codex\provider-profiles\providers.json`

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
      "modelReasoningEffort": "high",
      "supportsWebsockets": false
    }
  }
}
```

| 字段 | 说明 |
|------|------|
| `displayName` | Web UI 和菜单中显示的名称 |
| `baseUrl` | OpenAI 兼容接口地址（必填） |
| `apiKeyEnv` / `apiKeyFile` | API Key 来源 |
| `model` | 默认模型名称 |
| `modelContextWindow` | 上下文窗口大小 |
| `modelReasoningEffort` | `high` / `xhigh` / `max` |
| `modelReasoningSummary` | `auto` / `concise` |
| `modelVerbosity` | `low` / `medium` / `high` |
| `supportsWebsockets` | `true` / `false` |
| `requestMaxRetries` | 请求最大重试次数 |
| `streamMaxRetries` | 流式最大重试次数 |
| `streamIdleTimeoutMs` | 流空闲超时（毫秒） |
| `queryParams` | 额外 URL 查询参数（JSON 对象） |
| `httpHeaders` | 额外 HTTP 头（JSON 对象） |
| `envHttpHeaders` | 从环境变量取值的 HTTP 头（JSON 对象） |
| `extraEnv` | 额外环境变量（JSON 对象） |

### 添加供应商

**方式 A：Web UI（推荐）**

```powershell
ccp manager    # 或 cdp manager
```

点击"新增配置"，填写字段，点击"保存并同步"。

**方式 B：手动编辑**

编辑 JSON 文件，然后同步：

```powershell
ccp sync    # 或 cdp sync
```

---

## Web 管理界面

统一 Web 服务为所有已注册工具提供标签页管理。

```powershell
ccp manager    # 端口 15723 启动
cdp manager    # 端口 15724 启动
```

服务会自动检测已有实例并复用。

功能：
- 标签页切换：Claude Code 和 Codex CLI 配置独立管理
- 新增 / 复制 / 删除供应商配置
- 一键保存并同步快捷命令
- ID、命令名、必填字段校验
- 可折叠配置卡片 + 实时预览

需要 [Node.js](https://nodejs.org/) 18+。

---

## 开发者指南：添加新工具

架构遵循**开闭原则**：核心模块对修改关闭，对扩展开放。添加新 AI CLI 工具**零核心逻辑修改**。

### 示例：添加 `opencode` 支持

**步骤 1 — 创建 3 个 wrapper 脚本**（`src/tools/opencode/`）：

**`Invoke-OpenCodeProvider.ps1`**（3 行）：
```powershell
#!/usr/bin/env pwsh
$ToolName = 'opencode'
. "$PSScriptRoot\..\Invoke-Provider.ps1"
```

**`Sync-OpenCodeShortcuts.ps1`**（3 行）：
```powershell
#!/usr/bin/env pwsh
$ToolName = 'opencode'
. "$PSScriptRoot\..\Sync-Shortcuts.ps1"
```

**`Manage-OpenCodeUI.ps1`**（5 行）：
```powershell
#!/usr/bin/env pwsh
[CmdletBinding()]
param([int]$Port = 0, [switch]$Foreground)
$ToolName = 'opencode'
. "$PSScriptRoot\..\Manage-ProviderUI.ps1"
```

**步骤 2 — 注册工具**（在 `ProviderCore.psm1` 中添加）：

```powershell
if (-not $script:ToolRegistry.ContainsKey('opencode')) {
    $root = Join-Path $env:USERPROFILE '.opencode\provider-profiles'
    Register-ProviderTool @{
        name                  = 'opencode'
        commandPrefix         = 'ocp'
        configFileName        = 'providers.json'
        displayName           = 'OpenCode'
        defaultShortcutSuffix = 'opencode'
        executable            = 'opencode'
        configPath            = (Join-Path $root 'providers.json')
        invokeScript          = (Join-Path $root 'src\tools\opencode\Invoke-OpenCodeProvider.ps1')
        syncScript            = (Join-Path $root 'src\tools\opencode\Sync-OpenCodeShortcuts.ps1')
        manageScript          = (Join-Path $root 'src\tools\opencode\Manage-OpenCodeUI.ps1')
        launcher              = {
            param($Profile, $ApiKey, $ProfileId, $RemainingArgs, $Session)
            return @{
                LaunchArgs = @('--provider-url', $Profile.baseUrl) + $RemainingArgs
                EnvVars    = @{ 'OPENCODE_API_KEY' = $ApiKey }
                TempFile   = $null
            }
        }
    }
}
```

**步骤 3 — 添加部署**（在 `install.ps1` 中添加 Copy-Item，参考已有 Claude/Codex 段）。

**步骤 4 — 添加 Web UI 标签**（可选）：在 `app.js` 的 `TOOL_META` 中添加 `opencode` 条目。

**总计：~20 行业务代码。核心模块：0 行修改。**

---

## 安装布局

运行 `install.ps1` 后，文件部署至：

```
%USERPROFILE%\
├── .claude\
│   ├── provider-profiles\
│   │   ├── providers.json              ← Claude 供应商配置
│   │   ├── server.mjs                  ← Web 服务（共享）
│   │   ├── web/                        ← Web UI（共享）
│   │   └── src\
│   │       ├── core\ProviderCore.psm1  ← 核心模块
│   │       ├── tools\Import-Core.ps1   ← 引导
│   │       ├── tools\Invoke-Provider.ps1  ← 通用启动器
│   │       ├── tools\Sync-Shortcuts.ps1   ← 通用同步
│   │       ├── tools\Manage-ProviderUI.ps1← 通用管理 UI
│   │       └── tools\claude\           ← Claude wrapper（3 行）
│   └── bin\                            ← ccp, ccp-*, mi 等快捷命令
│
├── .codex\
│   ├── provider-profiles\
│   │   ├── providers.json              ← Codex 供应商配置
│   │   ├── server.mjs                  ← Web 服务（同代码）
│   │   ├── web/                        ← Web UI（同代码）
│   │   └── src\
│   │       ├── core\ProviderCore.psm1  ← 核心模块（同代码）
│   │       ├── tools\Import-Core.ps1
│   │       ├── tools\Invoke-Provider.ps1  ← 通用启动器
│   │       ├── tools\Sync-Shortcuts.ps1
│   │       ├── tools\Manage-ProviderUI.ps1
│   │       └── tools\codex\            ← Codex wrapper（3 行）
│   └── bin\                            ← cdp, cdp-*, mi 等快捷命令
```

两个工具共享相同的核心代码，但独立运行。

---

## 常见问题

### 快捷命令找不到

```powershell
$env:Path -split ';' | Select-String '\.(claude|codex)\\bin'
.\install.ps1 -AddPath   # 重新加入 PATH，然后重启终端
```

### 报错"缺少 apiKey"

```powershell
$env:MI_CLAUDE_API_KEY    # 确认环境变量存在
# 刚设置的话请重启终端
```

### 终端间模型相互污染

新脚本退出时自动清理。如需手动清理：

```powershell
Remove-Item Env:\ANTHROPIC_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
```

### 工具更新后会出问题吗？

不会。快捷命令调用原始 `claude` / `codex` 二进制文件，不修改任何安装文件。

### 可以在两个工具中使用同一个供应商吗？

可以，但每个工具有自己的配置文件。把一个 profile 从一份配置复制到另一份即可。

---

## 安全

- 切勿将真实 API Key 提交到 git
- 推荐使用 `apiKeyEnv`（环境变量）替代 `apiKey`
- 程序检测到明文 `apiKey` 时会发出警告并引导迁移
- 安装脚本不会覆盖已有 `providers.json`，除非指定 `-OverwriteConfig`
- 环境变量限定当前进程，退出时清理

---

## License

[MIT](LICENSE)
