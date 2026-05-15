# Provider Profiles — Multi-Provider AI CLI Switcher

在多个终端同时使用不同 AI 供应商，一键切换，互不干扰。

支持 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`ccp`) 和 [Codex CLI](https://github.com/openai/codex) (`cdp`)，
两者共享同一套核心架构，拥有完全对等的命令体系和 Web 管理台。

> Windows-only. Requires PowerShell 5.1+ and at least one of: Claude Code, Codex CLI.

---

## Features

- **Multi-Tool Architecture** — `ccp`（Claude Code）和 `cdp`（Codex CLI）是对等的一等公民，共享同一核心模块
- **Terminal Isolation** — 每个终端独立运行不同供应商，互不干扰
- **Zero Pollution** — 启动时临时注入配置，退出后自动还原环境变量，不留残余
- **Web Management** — 统一 Web 管理台（`ccp-manager` / `cdp-manager`），可视化编辑供应商配置
- **Extensible** — 添加新工具（如 Cursor、OpenCode）只需定义一个 launcher 函数，核心零改动

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    bin shims                         │
│   ccp / ccp-mi      cdp / cdp-mi      (future)     │
└────────┬─────────────────┬────────────────┬─────────┘
         │                 │                │
         ▼                 ▼                ▼
┌─────────────────────────────────────────────────────┐
│              Tool Invoke Scripts                     │
│   Invoke-ClaudeProvider    Invoke-CodexProvider      │
└────────┬─────────────────┬──────────────────────────┘
         │                 │
         ▼                 ▼
┌─────────────────────────────────────────────────────┐
│              ProviderCore.psm1 (shared)              │
│  ┌──────────┐ ┌──────────┐ ┌───────────────────┐   │
│  │ JSON/TOML│ │ Env Mgmt │ │ Menu / Validation │   │
│  │ Utils    │ │ Session  │ │ Shortcut Sync     │   │
│  └──────────┘ └──────────┘ └───────────────────┘   │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│              Web Management (server.mjs)             │
│         Unified tabbed UI for all tools              │
└─────────────────────────────────────────────────────┘
```

Each tool is a thin wrapper that defines **how** to launch its CLI, while the core handles **what** is common: config reading, API key resolution, environment isolation, and cleanup.

---

## Quick Start

### Install

**From zip** (recommended for colleagues):

```powershell
# Download Claude-Provider-Profiles-Kit.zip from Releases, then:
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

**From source:**

```powershell
git clone https://github.com/QianChenJun/Claude-Provider-Profiles.git
cd Claude-Provider-Profiles\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

Restart your terminal after installation.

### Verify

```powershell
ccp-list   # Claude Code providers
cdp-list   # Codex CLI providers
```

### Configure API Keys

```powershell
# Claude Code
[Environment]::SetEnvironmentVariable('MI_CLAUDE_API_KEY', 'your-key', 'User')
[Environment]::SetEnvironmentVariable('DS_CLAUDE_API_KEY', 'your-key', 'User')

# Codex CLI
[Environment]::SetEnvironmentVariable('MI_CODEX_API_KEY', 'your-key', 'User')
[Environment]::SetEnvironmentVariable('DS_CODEX_API_KEY', 'your-key', 'User')
```

Restart terminal after setting.

---

## Usage

### Claude Code (`ccp`)

```powershell
ccp                         # Interactive menu
ccp-mi                      # Launch with Xiaomi MiMo
ccp-ds                      # Launch with DeepSeek
ccp-mi --model xxx          # Override model
ccp-mi -p "帮我总结"         # Non-interactive mode
ccp-list                    # List all providers
ccp-sync                    # Regenerate shortcut commands
ccp-manager                 # Open Web management UI (port 15723)
```

Legacy commands still work: `mi-claude`, `ds-claude`, `provider-claude -Profile mi`.

### Codex CLI (`cdp`)

```powershell
cdp                         # Interactive menu
cdp-mi                      # Launch with Xiaomi MiMo
cdp-ds                      # Launch with DeepSeek
cdp-ds --model xxx          # Override model
cdp-list                    # List all providers
cdp-sync                    # Regenerate shortcut commands
cdp-manager                 # Open Web management UI (port 15724)
```

Legacy commands: `mi-codex`, `ds-codex`, `provider-codex`.

Both tools follow the **exact same command pattern** — only the prefix differs.

---

## Configuration

### Claude Code

File: `%USERPROFILE%\.claude\provider-profiles\providers.json`

```json
{
  "version": 1,
  "profiles": {
    "mi": {
      "displayName": "Xiaomi MiMo",
      "shortcut": "mi-claude",
      "baseUrl": "https://your-provider.com/anthropic",
      "authEnv": "ANTHROPIC_AUTH_TOKEN",
      "apiKeyEnv": "MI_CLAUDE_API_KEY",
      "model": "claude-sonnet-4-6"
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `displayName` | Display name in Web UI |
| `shortcut` | Legacy shortcut command (default: `<id>-claude`) |
| `baseUrl` | Anthropic-compatible endpoint |
| `authEnv` | `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_API_KEY` |
| `apiKeyEnv` | Environment variable for API key |
| `apiKeyFile` | File path for API key |
| `model` | Default model (ANTHROPIC_MODEL) |
| `haikuModel` / `sonnetModel` / `opusModel` | Model mapping overrides |
| `cliModel` | Default `--model` value |
| `extraEnv` | Additional environment variables (JSON object) |

### Codex CLI

File: `%USERPROFILE%\.codex\provider-profiles\providers.json`

```json
{
  "version": 1,
  "profiles": {
    "mi": {
      "displayName": "Xiaomi MiMo",
      "shortcut": "mi-codex",
      "baseUrl": "https://your-provider.com/v1",
      "apiKeyEnv": "MI_CODEX_API_KEY",
      "model": "claude-sonnet-4-6"
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `displayName` | Display name |
| `shortcut` | Legacy shortcut (default: `<id>-codex`) |
| `baseUrl` | OpenAI-compatible endpoint |
| `apiKeyEnv` / `apiKeyFile` | API key source |
| `model` | Default model |
| `modelContextWindow` | Context window size |
| `modelReasoningEffort` | `high` / `xhigh` / `max` |
| `supportsWebsockets` | `true` / `false` |
| `queryParams` / `httpHeaders` / `envHttpHeaders` | Extra HTTP config |
| `extraEnv` | Additional environment variables |

### Adding a Provider

**Option A: Web UI (recommended)**

```powershell
ccp-manager   # or cdp-manager
```

Click "新增配置", fill in details, click "保存并同步".

**Option B: Manual edit**

Edit the JSON file, then sync:

```powershell
ccp-sync   # or cdp-sync
```

---

## Adding a New Tool

The architecture is designed for extension. To add support for a new AI CLI (e.g., `opencode`):

### Step 1: Create tool scripts

Create `src/tools/opencode/` with three files:

**`Invoke-OpenCodeProvider.ps1`** (~20 lines):
```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'src\tools\Import-Core.ps1')
Import-ProviderCore
$tool = Get-ProviderTool -Name 'opencode'
# ... same pattern as Invoke-ClaudeProvider.ps1
```

**`Sync-OpenCodeShortcuts.ps1`** (~5 lines):
```powershell
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Import-Core.ps1')
Import-ProviderCore
Sync-ToolShortcuts -ToolName 'opencode'
```

**`Manage-OpenCodeUI.ps1`** (~5 lines):
```powershell
# Same pattern as Manage-ClaudeUI.ps1
```

### Step 2: Register the tool

In `ProviderCore.psm1`, add:

```powershell
if (-not $script:ToolRegistry.ContainsKey('opencode')) {
    Register-ProviderTool @{
        name                  = 'opencode'
        commandPrefix         = 'ocp'
        configFileName        = 'providers.json'
        displayName           = 'OpenCode'
        defaultShortcutSuffix = 'opencode'
        executable            = 'opencode'
        profileRoot           = '.opencode\provider-profiles'
        configPath            = (Join-Path $env:USERPROFILE '.opencode\provider-profiles\providers.json')
        invokeScript          = (Join-Path $env:USERPROFILE '.opencode\provider-profiles\src\tools\opencode\Invoke-OpenCodeProvider.ps1')
        syncScript            = '...'
        manageScript          = '...'
        launcher              = {
            param($Profile, $ApiKey, $ProfileId, $RemainingArgs, $Session)
            # Build launch args for opencode
            return @{ LaunchArgs = @(); EnvVars = @{}; TempFile = $null }
        }
    }
}
```

### Step 3: Add to install script

Add deployment and sync calls in `install.ps1`.

**Total effort: ~50 lines of code. Core logic: ZERO changes.**

---

## Web Management

The unified Web management server provides a tabbed interface for all registered tools.

```powershell
ccp-manager    # Claude Code tab (port 15723)
cdp-manager    # Codex CLI tab (port 15724)
```

Features:
- Add / copy / delete provider profiles
- Save and sync shortcut commands in one click
- Validation of profile IDs and command names
- Collapsible profile cards with preview

Requires [Node.js](https://nodejs.org/) 18+.

---

## Installation Layout

```
%USERPROFILE%\
├── .claude\
│   ├── provider-profiles\
│   │   ├── providers.json          ← Claude config
│   │   ├── server.mjs              ← Web server
│   │   ├── web/                    ← Web UI
│   │   └── src\
│   │       ├── core\ProviderCore.psm1
│   │       ├── tools\Import-Core.ps1
│   │       └── tools\claude\       ← Claude-specific scripts
│   └── bin\                        ← Shortcut commands (ccp, ccp-*)
│
├── .codex\
│   ├── provider-profiles\
│   │   ├── providers.json          ← Codex config
│   │   ├── server.mjs              ← Web server (shared code)
│   │   ├── web/                    ← Web UI (shared code)
│   │   └── src\
│   │       ├── core\ProviderCore.psm1
│   │       ├── tools\Import-Core.ps1
│   │       └── tools\codex\        ← Codex-specific scripts
│   └── bin\                        ← Shortcut commands (cdp, cdp-*)
```

Both tool installations share the same `ProviderCore.psm1` code — it's deployed to both locations so each can operate independently.

---

## FAQ

### Shortcut command not found

```powershell
# Verify PATH
$env:Path -split ';' | Select-String '\.(claude|codex)\\bin'

# Re-add to PATH
.\install.ps1 -AddPath
```

### "Missing apiKey" error

```powershell
# Check environment variable exists
$env:MI_CLAUDE_API_KEY
$env:DS_CODEX_API_KEY

# If just set, restart terminal
```

### New provider command not appearing

```powershell
ccp-sync   # or cdp-sync
```

### Model pollution between terminals

New scripts auto-clean on exit. If needed, manually:

```powershell
Remove-Item Env:\ANTHROPIC_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
```

### Will this break after Claude Code / Codex CLI updates?

No. Shortcuts call the original `claude` / `codex` binary. No installation files are modified.

---

## Security

- Never commit real API keys to git.
- Prefer `apiKeyEnv` over inline `apiKey`.
- The installer does not overwrite existing `providers.json` unless `-OverwriteConfig` is specified.

---

## License

[MIT](LICENSE)