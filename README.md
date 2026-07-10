# AI CLI Switcher

[![CI](https://github.com/QianChenJun/Claude-Code-Provider/actions/workflows/ci.yml/badge.svg)](https://github.com/QianChenJun/Claude-Code-Provider/actions/workflows/ci.yml)
[![Release](https://github.com/QianChenJun/Claude-Code-Provider/actions/workflows/release.yml/badge.svg)](https://github.com/QianChenJun/Claude-Code-Provider/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4.svg)](#运行要求)

**一个 Windows 下的 AI CLI 多供应商切换器。**

用同一套方式管理 Claude Code、Codex CLI 的不同供应商配置：小米 MiMo、DeepSeek、OpenRouter、Azure OpenAI 或任意兼容接口。

| 工具 | 推荐命令 | 说明 |
|------|----------|------|
| Claude Code | `ccp` | Anthropic/Claude Code 兼容接口 |
| Codex CLI | `cdp` | OpenAI/Codex 兼容接口 |
| OpenCode | `ocp` | 规划中，当前尚不可用 |

> 仅限 Windows · PowerShell 7+ · MIT License

---

## 运行要求

| 依赖 | 要求 | 用途 |
|------|------|------|
| Windows | Windows 10/11 | 必需 |
| PowerShell | 7+ | 安装、配置与启动 |
| Node.js | 18+ | 仅 Web 管理页面需要 |
| Claude Code / Codex CLI | 按需安装 | 实际执行对应 AI CLI |

项目通过 GitHub Actions 持续执行 PowerShell 测试、PSScriptAnalyzer 检查和 JavaScript 语法检查。

---

## 30 秒快速开始

### 1. 安装

**一键远程安装（便捷）** — 在 PowerShell 7 中粘贴一行，自动下载源码并安装到 `~/.claude` 与 `~/.codex`，并把 `~\.claude\bin` / `~\.codex\bin` 加入用户级 PATH：

```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/QianChenJun/Claude-Code-Provider/main/Claude-Provider-Profiles-Kit/install.ps1).Content)) -AddPath
```

需要安装后立即进入配置向导：

```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/QianChenJun/Claude-Code-Provider/main/Claude-Provider-Profiles-Kit/install.ps1).Content)) -AddPath -Configure
```

> 远程安装会执行 `main` 分支中的脚本。企业或安全敏感环境建议从 [Releases](https://github.com/QianChenJun/Claude-Code-Provider/releases) 下载固定版本，检查脚本后再运行。

**下载 Release 包（企业或安全敏感环境推荐）**：

```powershell
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

`-AddPath` 会修改当前 Windows 用户的 PATH。安装后重新打开 PowerShell / Windows Terminal。

想先预检会做什么、但不写入任何文件：

```powershell
.\install.ps1 -DryRun
```

远程版预检（需要用 scriptblock 形式才能传参）：

```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/QianChenJun/Claude-Code-Provider/main/Claude-Provider-Profiles-Kit/install.ps1).Content)) -DryRun
```

### 2. 配置供应商

推荐使用配置向导：

```powershell
ccp setup     # 新增或更新 Claude Code 供应商
cdp setup     # 新增或更新 Codex CLI 供应商
```

向导会询问：

- 配置 ID：例如 `mi`、`ds`、`openrouter`
- 显示名称
- 接口地址 `baseUrl`
- 默认模型 `model`
- API Key

API Key 会写入用户环境变量，不会写进 `providers.json`。

### 3. 使用

```powershell
ccp mi        # 用 mi 配置启动 Claude Code
ccp ds        # 用 ds 配置启动 Claude Code
cdp mi        # 用 mi 配置启动 Codex CLI
cdp ds        # 用 ds 配置启动 Codex CLI
```

也可以不带参数打开交互菜单：

```powershell
ccp
cdp
```

---

## 常用命令

所有工具命令风格一致，只是前缀不同：

| 操作 | Claude Code | Codex CLI |
|------|-------------|-----------|
| 交互菜单 | `ccp` | `cdp` |
| 新增/更新配置 | `ccp setup` | `cdp setup` |
| 启动指定配置 | `ccp mi` | `cdp mi` |
| 查看配置列表 | `ccp list` | `cdp list` |
| 同步快捷命令 | `ccp sync` | `cdp sync` |
| 打开 Web 管理页面 | `ccp manager` | `cdp manager` |
| 备份/导入配置 | `ccp profiles export/import` | `cdp profiles export/import` |

每个配置也会生成兼容快捷命令：

```powershell
ccp-mi        # 等价于 ccp mi
cdp-ds        # 等价于 cdp ds
mi            # 配置 ID 直呼命令
```

推荐文档、脚本和日常交流优先使用 `ccp mi` / `cdp ds` 这种子命令形式。`ccp-mi`、`mi-claude`、`mi` 等命令用于兼容和快速输入；如果配置 ID 与系统命令或其他工具同名，直呼命令可能受 PATH 顺序影响，因此不要把常见命令名当作配置 ID。

---

## Web 管理页面

如果你不想手动编辑 JSON：

```powershell
ccp manager
cdp manager
```

功能：

- 新增、复制、删除供应商配置
- 保存配置并同步快捷命令
- Claude Code / Codex CLI 标签页切换
- 基础字段校验

管理页只监听 `127.0.0.1`。通过 `ccp manager` / `cdp manager` 打开时会自动携带随机本地 token；未授权请求不能读取或修改配置。

需要 Node.js 18+。

---

## 配置备份与迁移

导出当前工具配置：

```powershell
ccp profiles export -OutDir "$HOME\Desktop\provider-backup"
cdp profiles export -OutDir "$HOME\Desktop\provider-backup"
```

一次导出两个工具：

```powershell
ccp profiles export -OutDir "$HOME\Desktop\provider-backup" -Tool all
```

导入备份：

```powershell
ccp profiles import -InDir "$HOME\Desktop\provider-backup" -Tool all
ccp sync
cdp sync
```

安全行为：

- 导出默认会移除 `apiKey` / `token` / `key` 等明文密钥字段
- `apiKeyEnv` 等环境变量名会保留，但环境变量值不会导出
- 迁移到新机器后需要重新设置对应 API Key 环境变量

---

## 配置文件位置

| 工具 | 配置文件 |
|------|----------|
| Claude Code | `%USERPROFILE%\.claude\provider-profiles\providers.json` |
| Codex CLI | `%USERPROFILE%\.codex\provider-profiles\providers.json` |

配置示例：

```json
{
  "version": 1,
  "profiles": {
    "ds": {
      "displayName": "DeepSeek",
      "baseUrl": "https://api.deepseek.com",
      "apiKeyEnv": "DS_CODEX_API_KEY",
      "model": "deepseek-chat"
    }
  }
}
```

### 重要字段

| 字段 | 说明 |
|------|------|
| `displayName` | 菜单和 Web UI 显示名称 |
| `baseUrl` | 供应商接口地址 |
| `apiKeyEnv` | 保存 API Key 的环境变量名，推荐使用 |
| `apiKeyFile` | 从本地文件读取 API Key |
| `apiKey` | 明文 API Key，不推荐 |
| `model` | 默认模型 |
| `extraEnv` | 启动 CLI 时额外注入的环境变量 |

Claude Code 额外常用字段：

| 字段 | 说明 |
|------|------|
| `authEnv` | `ANTHROPIC_AUTH_TOKEN` 或 `ANTHROPIC_API_KEY` |
| `haikuModel` / `sonnetModel` / `opusModel` | Claude Code 模型族映射 |
| `cliModel` | 默认传给 Claude Code 的 `--model` 参数 |

Codex CLI 额外常用字段：

| 字段 | 说明 |
|------|------|
| `modelContextWindow` | 上下文窗口大小 |
| `modelReasoningEffort` | 推理强度，如 `high` |
| `modelReasoningSummary` | 推理摘要策略 |
| `modelVerbosity` | 输出详细程度 |
| `supportsWebsockets` | 是否启用 WebSocket |
| `queryParams` / `httpHeaders` / `envHttpHeaders` | 请求参数和请求头 |

---

## 为什么需要它

同时使用多个 AI CLI 和多个供应商时，常见问题是：

- 手动切换供应商要改配置文件
- 不同终端窗口共享环境变量，互相污染
- 不同 CLI 的配置格式不同
- API Key 容易误写进配置文件或提交记录

AI CLI Switcher 的处理方式：

- 每个终端启动时临时注入对应供应商环境
- CLI 退出后恢复原环境
- 每个工具独立配置，命令风格统一
- API Key 默认放用户环境变量

示例：

```powershell
# 终端 1
ccp mi

# 终端 2
ccp ds

# 终端 3
cdp mi
```

这些会话可以同时运行，互不干扰。

---

## 目录结构

```text
.
├── .github/                           # CI、Release、Issue 与 PR 模板
├── src/
│   ├── core/
│   │   └── ProviderCore.psm1          # 共享核心逻辑
│   ├── tools/
│   │   ├── Invoke-Provider.ps1        # 通用启动器
│   │   ├── Sync-Shortcuts.ps1         # 通用快捷命令同步
│   │   ├── Manage-ProviderUI.ps1      # 通用 Web UI 启动器
│   │   ├── claude/                    # Claude Code thin wrappers
│   │   └── codex/                     # Codex CLI thin wrappers
│   ├── web/                           # Web 管理页面
│   └── server.mjs                     # 本地 HTTP 服务
├── config/                            # 示例配置模板
├── docs/                              # 开发记录与补充文档
├── Claude-Provider-Profiles-Kit/      # 发布包内容
├── tests/                             # PowerShell 自检脚本
├── CONTRIBUTING.md                    # 贡献指南
├── SECURITY.md                        # 安全披露策略
└── init.ps1                           # 开发环境快捷入口
```

---

## 开发环境命令

源码目录中可以直接使用：

```powershell
.\init.ps1 check       # 检查 claude / codex / node / pwsh
.\init.ps1 setup       # 配置向导
.\init.ps1 sync        # 同步快捷命令
.\init.ps1 web         # 启动 Web 管理页面
.\init.ps1 list        # 查看已注册工具
```

运行自检：

```powershell
pwsh -NoProfile -File tests\core-function-tests.ps1
pwsh -NoProfile -File tests\setup-tests.ps1
pwsh -NoProfile -File tests\server-path-tests.ps1
pwsh -NoProfile -File tests\profile-transfer-tests.ps1
pwsh -NoProfile -File tests\install-dryrun-tests.ps1
pwsh -NoProfile -File tests\install-bootstrap-tests.ps1
node --check src\server.mjs
node --check src\web\app.js
```

---

## 安装布局

安装后会写入用户目录：

```text
%USERPROFILE%\
├── .claude\
│   ├── provider-profiles\
│   │   ├── providers.json
│   │   ├── server.mjs
│   │   ├── web\
│   │   └── src\
│   └── bin\
│       ├── ccp.ps1
│       ├── ccp-setup.ps1
│       ├── ccp-mi.ps1
│       └── ...
│
├── .codex\
│   ├── provider-profiles\
│   │   ├── providers.json
│   │   ├── server.mjs
│   │   ├── web\
│   │   └── src\
│   └── bin\
│       ├── cdp.ps1
│       ├── cdp-setup.ps1
│       ├── cdp-ds.ps1
│       └── ...
```

---

## 常见问题

### 提示 `ccp` 或 `cdp` 找不到

重新加入用户级 PATH，然后重开终端：

```powershell
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

也可以检查 PATH：

```powershell
$env:Path -split ';' | Select-String '\.(claude|codex)\\bin'
```

### 提示缺少 API Key

检查对应环境变量：

```powershell
$env:MI_CLAUDE_API_KEY
$env:DS_CODEX_API_KEY
```

如果刚通过 `ccp setup` / `cdp setup` 设置过 API Key，请重新打开终端。

### 新增供应商后命令不存在

同步快捷命令：

```powershell
ccp sync
cdp sync
```

### 可以手动编辑 JSON 吗？

可以。编辑后执行：

```powershell
ccp sync
cdp sync
```

### 会修改 Claude Code 或 Codex CLI 本体吗？

不会。这里只生成 wrapper 和配置文件，最终仍调用原始 `claude` / `codex` 命令。

---

## 安全建议

- 不要把真实 API Key 写进仓库、聊天记录或提交信息
- 优先使用 `apiKeyEnv`
- 配置向导默认把 API Key 写入用户环境变量
- 如必须使用 `apiKeyFile`，请把文件放在仓库外
- 安装脚本默认不覆盖已有 `providers.json`，除非使用 `-OverwriteConfig`

---

## 开发者指南：添加新工具

核心通过工具注册表扩展。新增工具通常需要：

1. 在 `src/tools/<tool>/` 添加 3 个 thin wrapper：
   - `Invoke-<Tool>Provider.ps1`
   - `Sync-<Tool>Shortcuts.ps1`
   - `Manage-<Tool>UI.ps1`
2. 在 `ProviderCore.psm1` 中调用 `Register-ProviderTool`
3. 在安装脚本中部署新工具 wrapper
4. 如需 Web UI 标签页，在 `src/web/app.js` 和 `src/server.mjs` 增加元数据

wrapper 示例：

```powershell
#!/usr/bin/env pwsh
$ToolName = 'opencode'
$ProviderArgs = $args
. "$PSScriptRoot\..\Invoke-Provider.ps1"
```

---

## 参与贡献与反馈

- 使用问题或缺陷请提交 [Bug 报告](https://github.com/QianChenJun/Claude-Code-Provider/issues/new?template=bug_report.yml)
- 功能建议请提交 [功能请求](https://github.com/QianChenJun/Claude-Code-Provider/issues/new?template=feature_request.yml)
- 准备提交代码前请阅读 [贡献指南](CONTRIBUTING.md)
- 安全问题请按照 [安全策略](SECURITY.md) 私下报告，不要创建公开 Issue

---

## License

[MIT](LICENSE)
