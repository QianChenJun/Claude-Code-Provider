# AI CLI Switcher

[![CI](https://github.com/QianChenJun/Claude-Code-Provider/actions/workflows/ci.yml/badge.svg)](https://github.com/QianChenJun/Claude-Code-Provider/actions/workflows/ci.yml)
[![Release](https://github.com/QianChenJun/Claude-Code-Provider/actions/workflows/release.yml/badge.svg)](https://github.com/QianChenJun/Claude-Code-Provider/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4.svg)](#运行要求)

**Windows 下的 AI CLI 多供应商切换器。**

用同一套命令管理 Claude Code、Codex CLI 的不同供应商：DeepSeek、OpenRouter、自建网关，或任意兼容接口。

| 工具 | 命令 | 说明 |
|------|------|------|
| Claude Code | `ccp` | Anthropic / Claude Code 兼容接口 |
| Codex CLI | `cdp` | OpenAI / Codex 兼容接口 |

> 仓库历史名：`Claude-Code-Provider` · 仅限 Windows · PowerShell 7+ · MIT

---

## 为什么需要它

- 手动改配置文件切换供应商太麻烦
- 多个终端共享环境变量，容易互相污染
- Claude Code / Codex CLI 配置格式不同
- API Key 容易误写进仓库或聊天记录

AI CLI Switcher 的做法：

- 每个终端启动时临时注入对应供应商环境，退出后恢复
- 两套 CLI 命令风格统一：`ccp` / `cdp`
- 配置独立存放在用户目录，安装默认不预置具体供应商

```powershell
# 终端 1
ccp my-provider

# 终端 2
cdp my-provider
```

这些会话可以同时运行，互不干扰。

---

## 运行要求

| 依赖 | 要求 | 用途 |
|------|------|------|
| Windows | 10 / 11 | 必需 |
| PowerShell | 7+ | 安装、配置与启动 |
| Node.js | 18+ | 仅 Web 管理页面需要 |
| Claude Code / Codex CLI | 按需安装 | 实际执行对应 AI CLI |

---

## 30 秒快速开始

### 1. 安装

**一键远程安装**（PowerShell 7）：

```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/QianChenJun/Claude-Code-Provider/main/Claude-Provider-Profiles-Kit/install.ps1).Content)) -AddPath
```

**Release 包安装**（企业或安全敏感环境推荐）：

```powershell
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

`-AddPath` 会把 `~\.claude\bin` 与 `~\.codex\bin` 加入当前用户 PATH。安装后请重新打开终端。

预检（不写任何文件）：

```powershell
.\install.ps1 -DryRun
```

> 首次安装默认生成**空配置**（`profiles: {}`），不会预置 `mi` / `ds` 等供应商。请用 `ccp setup` / `cdp setup` 自行添加。

### 2. 添加供应商

```powershell
ccp setup     # Claude Code
cdp setup     # Codex CLI
```

向导会询问配置 ID、显示名称、`baseUrl`、默认模型和 API Key。

**当前默认行为：** API Key 会**明文写入**用户目录下的 `providers.json`，方便本机快速使用。  
更安全的方式见 [安全说明](#安全说明)。

### 3. 使用

```powershell
ccp              # 交互菜单
ccp list         # 查看配置
ccp my-provider  # 启动指定配置
ccp-my-provider  # 等价快捷命令

cdp my-provider
cdp-my-provider
```

推荐日常使用：`ccp <id>` / `cdp <id>`。  
同步还会生成 `ccp-<id>`、兼容 shortcut（如 `my-provider-claude`），**不会**再生成裸配置 ID 命令（避免 Claude / Codex 两边 PATH 抢占）。

---

## 常用命令

| 操作 | Claude Code | Codex CLI |
|------|-------------|-----------|
| 交互菜单 | `ccp` | `cdp` |
| 新增/更新配置 | `ccp setup` | `cdp setup` |
| 启动指定配置 | `ccp <id>` | `cdp <id>` |
| 查看配置列表 | `ccp list` | `cdp list` |
| 同步快捷命令 | `ccp sync` | `cdp sync` |
| 打开 Web 管理页面 | `ccp manager` | `cdp manager` |
| 备份/导入配置 | `ccp profiles export/import` | `cdp profiles export/import` |

---

## Web 管理页面

```powershell
ccp manager
cdp manager
```

- 新增、复制、删除供应商配置
- 保存后自动同步快捷命令
- Claude Code / Codex CLI 标签切换
- 仅监听 `127.0.0.1`，并带本地随机 token

需要 Node.js 18+。

---

## 配置位置

| 工具 | 配置文件 |
|------|----------|
| Claude Code | `%USERPROFILE%\.claude\provider-profiles\providers.json` |
| Codex CLI | `%USERPROFILE%\.codex\provider-profiles\providers.json` |

字段说明：

| 字段 | 说明 |
|------|------|
| `displayName` | 菜单与 Web UI 显示名 |
| `baseUrl` | 供应商接口地址 |
| `apiKey` | 明文 API Key（向导默认写入） |
| `apiKeyEnv` | 从环境变量读取 API Key（更推荐） |
| `apiKeyFile` | 从本地文件读取 API Key |
| `model` | 默认模型 |
| `shortcut` | 兼容快捷命令名；默认 `<id>-claude` / `<id>-codex` |
| `extraEnv` | 启动时额外注入的环境变量 |

Claude 额外字段：`authEnv`、`haikuModel` / `sonnetModel` / `opusModel`、`cliModel`  
Codex 额外字段：`wireApi`、`modelContextWindow`、`modelReasoningEffort`、`modelVerbosity`、`queryParams` 等

配置示例（手动编辑时）：

```json
{
  "version": 1,
  "profiles": {
    "ds": {
      "displayName": "DeepSeek",
      "baseUrl": "https://api.deepseek.com/anthropic",
      "apiKeyEnv": "DS_CLAUDE_API_KEY",
      "model": "deepseek-chat"
    }
  }
}
```

---

## 配置备份与迁移

```powershell
ccp profiles export -OutDir "$HOME\Desktop\provider-backup" -Tool all
ccp profiles import -InDir "$HOME\Desktop\provider-backup" -Tool all
ccp sync
cdp sync
```

- 导出默认会移除 `apiKey` / `token` / `key` 等明文密钥字段
- `apiKeyEnv` 名称会保留，环境变量值不会导出
- 迁移到新机器后需要重新设置密钥

---

## 安全说明

- **默认：** `ccp setup` / `cdp setup` 把 API Key 明文写入用户目录 `providers.json`
- **更安全：** 使用 `apiKeyEnv` 或 `apiKeyFile`，并删除配置中的 `apiKey`
- 不要把真实 API Key 提交到 git、Issue 或聊天记录
- 企业环境建议使用 Release 包并先审查 `install.ps1`
- Web 管理页只应本机访问，不要端口转发到公网

详见 [SECURITY.md](SECURITY.md)。

---

## 常见问题

### 提示 `ccp` / `cdp` 找不到

```powershell
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

然后重开终端，或检查：

```powershell
$env:Path -split ';' | Select-String '\.(claude|codex)\\bin'
```

### 提示缺少 API Key

若配置使用了 `apiKeyEnv`，检查对应环境变量；若使用明文 `apiKey`，检查 `providers.json`。  
刚改过环境变量时，请重新打开终端。

### 新增供应商后命令不存在

```powershell
ccp sync
cdp sync
```

### 以前的裸配置 ID 命令（如 `any`、`gpt`）呢？

从当前版本起，同步**不再生成**裸配置 ID 命令，避免 Claude / Codex 两边互相覆盖。  
请改用：

```powershell
ccp any
cdp any
# 或
ccp-any
cdp-any
```

### 会修改 Claude Code / Codex CLI 本体吗？

不会。只生成 wrapper 与配置，最终仍调用原始 `claude` / `codex`。

---

## 开发

源码目录：

```powershell
.\init.ps1 check
.\init.ps1 setup
.\init.ps1 sync
.\init.ps1 web
.\init.ps1 test      # 运行全部自检
```

或：

```powershell
pwsh -NoProfile -File tests\run-all.ps1
```

更多：

- 贡献指南：[CONTRIBUTING.md](CONTRIBUTING.md)
- AI / 架构说明：[AGENTS.md](AGENTS.md)
- 安全披露：[SECURITY.md](SECURITY.md)

### 添加新工具（概要）

1. 在 `src/tools/<tool>/` 增加 3 个 thin wrapper  
2. 在 `ProviderCore.psm1` 注册工具  
3. 更新 `install.ps1` 部署逻辑  
4. 如需 Web 标签，更新 `src/web/app.js` 与 `src/server.mjs`

---

## 路线图

- OpenCode 支持（规划中，`ocp` 暂不可用）

---

## 参与贡献与反馈

- [Bug 报告](https://github.com/QianChenJun/Claude-Code-Provider/issues/new?template=bug_report.yml)
- [功能请求](https://github.com/QianChenJun/Claude-Code-Provider/issues/new?template=feature_request.yml)
- 代码贡献请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)
- 安全问题请按 [SECURITY.md](SECURITY.md) 私下报告

---

## License

[MIT](LICENSE)
