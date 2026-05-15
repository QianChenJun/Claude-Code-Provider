# Claude Code Multi-Provider Profiles (CCP)

Claude Code 多供应商快捷切换工具。

> Windows-only. Requires [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and PowerShell.

English summary: CCP lets you switch between multiple Anthropic-compatible API providers
(Xiaomi MiMo, DeepSeek, OpenRouter, etc.) without editing Claude Code's config each time.
It writes a temporary `settings.json` with overridden `ANTHROPIC_BASE_URL`, API key, and
model mappings, then launches `claude`. On exit it cleans up — no traces left.

另外，本仓库现在附带一个 **Codex CLI 第三方 provider CLI MVP**：
它基于 Codex 官方支持的 `model_provider` / `model_providers` 配置能力，临时注入 `-c`
覆盖项来启动 `codex`，不改你原有 `~/.codex/config.toml`。

---

## 目录

- [原理](#原理)
- [安装](#安装)
- [日常使用](#日常使用)
- [API Key 配置](#api-key-配置)
- [providers.json 写法](#providersjson-写法)
- [新增供应商](#新增供应商)
- [Codex CLI 第三方 provider](#codex-cli-第三方-provider)
- [常见问题](#常见问题)
- [维护建议](#维护建议)
- [License](#license)

---

## 原理

```
ccp-mi
  ↓
读取 providers.json → mi 配置
  ↓
写入临时 settings.json + 设置进程环境变量
  ├── ANTHROPIC_BASE_URL = https://your-provider/anthropic
  ├── ANTHROPIC_AUTH_TOKEN = your-key
  └── ANTHROPIC_MODEL = ...
  ↓
claude --settings <临时文件> [你的参数]
  ↓
Claude Code 启动，所有请求发到该供应商
  ↓
退出后：删除临时文件，恢复原始环境变量
```

核心优势：不修改 Claude Code 本体，不污染全局配置，不残留环境变量。

---

## 安装

### 方式一：下载 zip 安装

从 [Releases](../../releases) 下载最新 `Claude-Provider-Profiles-Kit.zip`，解压后在 PowerShell 中运行：

```powershell
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

`-AddPath` 会自动把快捷命令目录（`%USERPROFILE%\.claude\bin`）加入用户 PATH。
安装后重新打开终端。

### 方式二：从源码安装

```powershell
git clone https://github.com/<your-username>/Claude-Provider-Profiles.git
cd Claude-Provider-Profiles\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

### 安装后验证

```powershell
ccp-list
```

如提示 `ccp-list` 不存在，确认 `%USERPROFILE%\.claude\bin` 在 PATH 中：

```powershell
$env:Path -split ';' | Select-String '\.claude\\bin'
```

---

## 日常使用

```powershell
ccp                    # 交互菜单，按编号选择供应商
ccp-mi                 # 直接启动小米 MiMo
ccp-ds                 # 直接启动 DeepSeek
ccp-mi --model xxx     # 临时覆盖模型
ccp-mi -p "帮我总结"    # 非交互模式
ccp-list               # 查看所有供应商配置
ccp-sync               # 重新生成快捷命令
ccp-manager            # 打开 Web 管理页面
```

兼容旧命令：`mi-claude`、`ds-claude`、`provider-claude -Profile mi` 仍然可用。

---

## API Key 配置

推荐把 Key 放到 Windows 用户环境变量，**不要**写进 `providers.json`。

```powershell
[Environment]::SetEnvironmentVariable('MI_CLAUDE_API_KEY', 'your-key', 'User')
[Environment]::SetEnvironmentVariable('DS_CLAUDE_API_KEY', 'your-key', 'User')
```

设置后重开终端生效。验证：

```powershell
$env:MI_CLAUDE_API_KEY
$env:DS_CLAUDE_API_KEY
```

---

## providers.json 写法

文件位置：`%USERPROFILE%\.claude\provider-profiles\providers.json`

```json
{
  "version": 1,
  "profiles": {
    "mi": {
      "displayName": "Xiaomi MiMo",
      "shortcut": "mi-claude",
      "baseUrl": "https://your-provider.com/anthropic",
      "authEnv": "ANTHROPIC_AUTH_TOKEN",
      "apiKeyEnv": "MI_CLAUDE_API_KEY"
    },
    "ds": {
      "displayName": "DeepSeek",
      "shortcut": "ds-claude",
      "baseUrl": "https://your-provider.com/anthropic",
      "authEnv": "ANTHROPIC_AUTH_TOKEN",
      "apiKeyEnv": "DS_CLAUDE_API_KEY",
      "model": "deepseek-chat",
      "haikuModel": "deepseek-chat",
      "sonnetModel": "deepseek-chat",
      "opusModel": "deepseek-chat"
    }
  }
}
```

| 字段 | 说明 |
|------|------|
| `displayName` | Web 管理页面显示名称 |
| `shortcut` | 兼容旧版快捷命令名（可选，默认 `<id>-claude`） |
| `baseUrl` | 供应商 Anthropic 兼容接口地址 |
| `authEnv` | `ANTHROPIC_AUTH_TOKEN` 或 `ANTHROPIC_API_KEY` |
| `apiKeyEnv` | 从哪个 Windows 环境变量读取 Key |
| `apiKey` | 直接填写 Key（不推荐，优先用 `apiKeyEnv`） |
| `apiKeyFile` | 从文件读取 Key（`%USERPROFILE%\.keys\provider.txt`） |
| `model` | 默认模型，写入 `ANTHROPIC_MODEL` |
| `haikuModel` | Claude Haiku 映射模型 |
| `sonnetModel` | Claude Sonnet 映射模型 |
| `opusModel` | Claude Opus 映射模型 |
| `cliModel` | CLI `--model` 参数默认值 |
| `extraEnv` | 额外环境变量，JSON 对象 |

---

## 新增供应商

### 方式 A：Web 管理页面（推荐）

```powershell
ccp-manager
```

浏览器打开 `http://127.0.0.1:15723/`，点"新增供应商"，填写后点"保存并同步"。

### 方式 B：手动编辑

1. 编辑 `%USERPROFILE%\.claude\provider-profiles\providers.json`，在 `profiles` 里新增条目。
2. 设置环境变量：

```powershell
[Environment]::SetEnvironmentVariable('ABC_CLAUDE_API_KEY', 'your-key', 'User')
```

3. 生成快捷命令：

```powershell
ccp-sync
```

4. 重开终端后使用：

```powershell
ccp-abc
```

---

## 常见问题

### 报错 "缺少 apiKey"

```powershell
ccp-list                  # 确认配置存在
$env:MI_CLAUDE_API_KEY    # 确认环境变量有值
```

刚设置的环境变量需要重开终端。

### 新增供应商后命令不存在

```powershell
ccp-sync
```

重开终端，或确认 `%USERPROFILE%\.claude\bin` 在 PATH 中。

### 模型被上一个供应商污染

上一次运行的环境变量残留到当前终端。手动清理：

```powershell
Remove-Item Env:\ANTHROPIC_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
```

新版脚本已自动在退出时清理，通常不会遇到此问题。

### Claude Code 更新后会失效吗

不会。快捷命令最终调用的是原始 `claude`，不修改 Claude Code 安装文件。

## Codex CLI 第三方 provider

这是当前先落地的 **CLI 级 MVP**，先不改现有 Web 管理页。

安装后会额外生成：

```powershell
cdp
cdp-list
cdp-sync
cdp-<profile>
<profile>-codex
```

Codex 配置文件位置：

```powershell
%USERPROFILE%\.codex\provider-profiles\providers.json
```

支持的最小字段示例：

```json
{
  "version": 1,
  "profiles": {
    "proxy": {
      "displayName": "LLM Proxy",
      "shortcut": "proxy-codex",
      "baseUrl": "https://example.com/v1",
      "apiKeyEnv": "PROXY_CODEX_API_KEY",
      "model": "provider-model-name"
    }
  }
}
```

可选扩展字段：

- `queryParams`
- `httpHeaders`
- `envHttpHeaders`
- `modelContextWindow`
- `modelReasoningEffort`
- `modelReasoningSummary`
- `modelVerbosity`
- `supportsWebsockets`
- `requestMaxRetries`
- `streamMaxRetries`
- `streamIdleTimeoutMs`
- `extraEnv`

使用示例：

```powershell
cdp                    # 交互选择 provider
cdp proxy              # 使用 proxy 配置启动 codex
cdp-proxy              # 直接启动
proxy-codex            # 兼容快捷命令
cdp proxy exec "解释当前仓库结构"
```

说明：

- 当前实现只对 **Codex 官方支持的 `responses` provider** 做临时注入。
- 不修改你原有 `~/.codex/config.toml`，只在当前命令进程内临时注入 provider 和 token。
- 现有 Claude 侧 `ccp`、`ccp-manager` 不受影响。

---

## 维护建议

- API Key 放 Windows 用户环境变量，不写进仓库。
- `providers.json` 只维护供应商差异。
- 新增/修改供应商后运行 `ccp-sync`。
- 不要把真实 Key 提交到 Git。

---

## License

[MIT](LICENSE)
