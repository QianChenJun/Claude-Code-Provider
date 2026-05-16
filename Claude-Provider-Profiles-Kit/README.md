# AI CLI Switcher — 安装包

统一的 AI CLI 多供应商切换平台。一个架构，覆盖 Claude Code、Codex CLI 及未来所有 AI 工具。

`ccp` (Claude Code) / `cdp` (Codex CLI) / `ocp` (OpenCode, 即将支持) — 三者共享同一核心模块，命令体系完全对等。

> Windows-only · PowerShell 5.1+ · 不含真实 API Key

---

## 安装前要求

```powershell
claude --version     # Claude Code（可选）
codex --version      # Codex CLI（可选）
node --version       # Web 管理台（可选，需 18+）
```

至少需要安装 Claude Code 或 Codex CLI 中的一个。

---

## 安装

```powershell
.\install.ps1              # 基本安装
.\install.ps1 -AddPath     # 安装并自动加入 PATH
.\install.ps1 -OverwriteConfig  # 用模板覆盖已有配置
```

安装后重开终端。

---

## 验证

```powershell
ccp-list    # Claude Code 供应商列表
cdp-list    # Codex CLI 供应商列表
```

如提示命令不存在，确认 `%USERPROFILE%\.claude\bin` 和 `%USERPROFILE%\.codex\bin` 在 PATH 中：

```powershell
.\install.ps1 -AddPath
```

---

## 配置 API Key

```powershell
# Claude Code
[Environment]::SetEnvironmentVariable('MI_CLAUDE_API_KEY', 'your-key', 'User')
[Environment]::SetEnvironmentVariable('DS_CLAUDE_API_KEY', 'your-key', 'User')

# Codex CLI
[Environment]::SetEnvironmentVariable('MI_CODEX_API_KEY', 'your-key', 'User')
[Environment]::SetEnvironmentVariable('DS_CODEX_API_KEY', 'your-key', 'User')
```

设置后重开终端。

---

## 使用

### Claude Code (`ccp`)

```powershell
ccp                            # 交互菜单
ccp-mi                         # 使用小米 MiMo
ccp-ds                         # 使用 DeepSeek
ccp-mi --model claude-opus-4-7 # 临时覆盖模型
ccp-mi -p "帮我总结"            # 非交互模式
ccp-list                       # 查看所有供应商
ccp-sync                       # 重新生成快捷命令
ccp-manager                    # Web 管理页面
```

兼容旧命令：`mi-claude`、`ds-claude`、`provider-claude`。

### Codex CLI (`cdp`)

```powershell
cdp                            # 交互菜单
cdp-mi                         # 使用小米 MiMo
cdp-ds                         # 使用 DeepSeek
cdp-list                       # 查看所有供应商
cdp-sync                       # 重新生成快捷命令
cdp-manager                    # Web 管理页面
```

兼容旧命令：`mi-codex`、`ds-codex`、`provider-codex`。

---

## 新增供应商

### 方式 A：Web 管理台（推荐）

```powershell
ccp-manager    # 或 cdp-manager
```

点"新增配置"，填写后点"保存并同步"。

### 方式 B：手动编辑

编辑配置文件后运行 `ccp-sync` 或 `cdp-sync`。

配置文件位置：
- Claude Code: `%USERPROFILE%\.claude\provider-profiles\providers.json`
- Codex CLI: `%USERPROFILE%\.codex\provider-profiles\providers.json`

---

## 配置字段

### Claude Code

| 字段 | 说明 |
|------|------|
| `displayName` | 显示名称 |
| `shortcut` | 兼容命令名（默认 `<id>-claude`） |
| `baseUrl` | Anthropic 兼容接口地址 |
| `authEnv` | `ANTHROPIC_AUTH_TOKEN` 或 `ANTHROPIC_API_KEY` |
| `apiKeyEnv` | API Key 环境变量名 |
| `apiKeyFile` | API Key 文件路径 |
| `model` | 默认模型 |
| `haikuModel` / `sonnetModel` / `opusModel` | 模型映射 |
| `cliModel` | `--model` 默认值 |
| `extraEnv` | 额外环境变量（JSON 对象） |

### Codex CLI

| 字段 | 说明 |
|------|------|
| `displayName` | 显示名称 |
| `shortcut` | 兼容命令名（默认 `<id>-codex`） |
| `baseUrl` | OpenAI 兼容接口地址 |
| `apiKeyEnv` / `apiKeyFile` | API Key 来源 |
| `model` | 默认模型 |
| `modelContextWindow` | 上下文窗口大小 |
| `modelReasoningEffort` | `high` / `xhigh` / `max` |
| `supportsWebsockets` | `true` / `false` |
| `queryParams` / `httpHeaders` / `envHttpHeaders` | HTTP 配置 |
| `extraEnv` | 额外环境变量 |

---

## 安装目录

```
%USERPROFILE%\
├── .claude\
│   ├── provider-profiles\       ← Claude 配置 + 核心模块 + 脚本
│   │   ├── providers.json
│   │   ├── server.mjs
│   │   ├── web\
│   │   └── src\
│   └── bin\                     ← ccp, ccp-* 快捷命令
│
├── .codex\
│   ├── provider-profiles\       ← Codex 配置 + 核心模块 + 脚本
│   │   ├── providers.json
│   │   ├── server.mjs
│   │   ├── web\
│   │   └── src\
│   └── bin\                     ← cdp, cdp-* 快捷命令
```

---

## 开发者指南：添加新工具

添加对新 AI CLI（如 OpenCode）的支持只需 ~50 行代码：

1. 在 `src/tools/opencode/` 创建 3 个脚本（Invoke / Sync / Manage）
2. 在 `ProviderCore.psm1` 添加 `Register-ProviderTool` 注册块
3. 在 `install.ps1` 添加部署行

核心逻辑零改动。详见项目 README.md 的 Developer Guide 章节。

---

## 常见问题

### 快捷命令找不到

```powershell
.\install.ps1 -AddPath
# 重开终端
```

### 报缺少 apiKey

```powershell
$env:MI_CLAUDE_API_KEY    # 确认环境变量存在
# 刚设置的变量需要重开终端
```

### 新增供应商后命令不存在

```powershell
ccp-sync    # 或 cdp-sync
```

### 不想覆盖已有配置

默认安装不覆盖已有 `providers.json`。如需强制覆盖：

```powershell
.\install.ps1 -OverwriteConfig
```

---

## 安全建议

- 不要把真实 API Key 写进聊天、仓库、提交记录
- 优先用 `apiKeyEnv`（环境变量）
- 发给别人前确认 `providers.json` 没有真实 Key