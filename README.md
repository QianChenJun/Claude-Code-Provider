# AI CLI Switcher

**Universal multi-provider switcher for AI CLI tools. One platform, every tool, zero interference.**

| Tool | Prefix | CLI | Status |
|------|--------|-----|--------|
| **Claude Code** | `ccp` | Claude Code | Stable |
| **Codex CLI** | `cdp` | Codex CLI | Stable |
| `ocp` | OpenCode | [Planned](#developer-guide-adding-a-new-tool) |

> Windows-only · PowerShell 5.1+ · MIT License

---

## Why AI CLI Switcher?

Running multiple AI CLI tools across different providers is painful:

- Switching providers means editing config files by hand
- Different terminals interfere with each other through shared environment variables
- Each tool has its own config format, its own key management, its own quirks

**AI CLI Switcher** unifies every AI CLI under one architecture. Three equal commands — `ccp` (Claude Code), `cdp` (Codex CLI), `ocp` (OpenCode) — same pattern, same power. One command like `ccp-mi` or `cdp-ds` and your terminal gets an isolated provider. Exit, and everything is restored. No traces.

```
Terminal 1:  ccp-mi    → Xiaomi MiMo (Claude Code)
Terminal 2:  ccp-ds    → DeepSeek    (Claude Code)
Terminal 3:  cdp-mi    → Xiaomi MiMo (Codex CLI)
Terminal 4:  cdp-ds    → DeepSeek    (Codex CLI)
              ↑ all running concurrently, zero interference
```

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        Bin Shims                             │
│    ccp (Claude Code)    cdp (Codex CLI)    ocp (OpenCode)   │
└─────────┬────────────────────┬─────────────────────┬────────┘
          │                    │                     │
          ▼                    ▼                     ▼
┌──────────────────────────────────────────────────────────────┐
│                  Tool Invoke Scripts (~40 lines each)         │
│      Invoke-ClaudeProvider        Invoke-CodexProvider        │
└─────────┬────────────────────┬───────────────────────────────┘
          │                    │
          ▼                    ▼
┌──────────────────────────────────────────────────────────────┐
│                   ProviderCore.psm1                           │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ JSON / TOML│  │ Env Session  │  │ Interactive Menu     │  │
│  │ Utilities  │  │ Isolation    │  │ Validation / Sync    │  │
│  └────────────┘  └──────────────┘  └──────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────────┐│
│  │  Tool Registry  (Register-ProviderTool / Get-ProviderTool)││
│  └──────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────┐
│           Unified Web Management (server.mjs)                │
│          Tabbed UI: Claude Code  |  Codex CLI                 │
│               http://127.0.0.1:15722/                        │
└──────────────────────────────────────────────────────────────┘
```

The core handles **what** is common. Each tool defines only **how** to launch its CLI.

---

## Repository Structure

```
.
├── src/
│   ├── core/
│   │   └── ProviderCore.psm1            # Shared core module (all logic)
│   ├── tools/
│   │   ├── Import-Core.ps1              # Bootstrap: locate & import core
│   │   ├── claude/
│   │   │   ├── Invoke-ClaudeProvider.ps1  # Claude launcher (thin wrapper)
│   │   │   ├── Sync-ClaudeShortcuts.ps1   # Shortcut sync
│   │   │   └── Manage-ClaudeUI.ps1        # Web manager launcher
│   │   └── codex/
│   │       ├── Invoke-CodexProvider.ps1   # Codex launcher (thin wrapper)
│   │       ├── Sync-CodexShortcuts.ps1    # Shortcut sync
│   │       └── Manage-CodexUI.ps1         # Web manager launcher
│   ├── web/
│   │   ├── index.html                   # Tabbed management UI
│   │   ├── app.js                       # Frontend logic
│   │   └── styles.css                   # Shared styles
│   └── server.mjs                       # Unified HTTP server
│
├── config/
│   ├── providers.example.json           # Claude config template
│   └── codex-providers.example.json     # Codex config template
│
├── Claude-Provider-Profiles-Kit/        # Distribution kit (for zip release)
│   ├── install.ps1                      # Installer script
│   ├── README.md                        # User documentation
│   └── *.example.json                   # Config templates
│
├── .codex/                              # Project-level Codex hooks
│   ├── hooks/                           # Encryption-environment guards
│   └── tools/Read-PlainText.ps1         # E-SafeNet-safe file reader
│
└── .github/workflows/
    ├── ci.yml                           # Lint (PSScriptAnalyzer + JS syntax)
    └── release.yml                      # Package zip + GitHub Release
```

---

## Quick Start

### Install

```powershell
# From zip (colleagues): download Claude-Provider-Profiles-Kit.zip from Releases
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath

# From source (developers):
git clone https://github.com/QianChenJun/Claude-Provider-Profiles.git
cd Claude-Provider-Profiles\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

Restart your terminal.

### Configure API Keys

```powershell
# Claude Code providers
[Environment]::SetEnvironmentVariable('MI_CLAUDE_API_KEY', 'your-mi-key', 'User')
[Environment]::SetEnvironmentVariable('DS_CLAUDE_API_KEY', 'your-ds-key', 'User')

# Codex CLI providers
[Environment]::SetEnvironmentVariable('MI_CODEX_API_KEY', 'your-mi-key', 'User')
[Environment]::SetEnvironmentVariable('DS_CODEX_API_KEY', 'your-ds-key', 'User')
```

Restart terminal after setting.

### Use

```powershell
# Claude Code
ccp-mi                       # Launch Claude with Xiaomi MiMo
ccp-ds                       # Launch Claude with DeepSeek
ccp                          # Interactive menu

# Codex CLI
cdp-mi                       # Launch Codex with Xiaomi MiMo
cdp-ds                       # Launch Codex with DeepSeek
cdp                          # Interactive menu

# Management
ccp-manager                  # Web UI for Claude providers
cdp-manager                  # Web UI for Codex providers
```

---

## Usage Reference

All tools follow the **exact same command pattern** — only the prefix differs.

### Claude Code (`ccp`)

```powershell
ccp                            # Interactive menu (pick a provider)
ccp-mi                         # Direct launch: Xiaomi MiMo
ccp-ds                         # Direct launch: DeepSeek
ccp-mi --model claude-opus-4-7 # Override model for this session
ccp-mi -p "Summarize this"     # Non-interactive mode
ccp-list                       # List all configured providers
ccp-sync                       # Regenerate shortcut commands
ccp-manager                    # Open Web management UI
```

### Codex CLI (`cdp`)

```powershell
cdp                            # Interactive menu
cdp-mi                         # Direct launch: Xiaomi MiMo
cdp-ds                         # Direct launch: DeepSeek
cdp-ds --model deepseek-chat   # Override model
cdp-list                       # List all configured providers
cdp-sync                       # Regenerate shortcut commands
cdp-manager                    # Open Web management UI
```

### Interactive Menu

When you run `ccp` or `cdp` without arguments, an interactive menu appears:

```
Codex CLI Provider 配置
请选择配置：
  1. cdp-ds                 DeepSeek
  2. cdp-mi                 Xiaomi MiMo

  L. 查看列表    S. 同步快捷命令    M. 打开管理页面    H. 帮助    Q. 退出
输入编号或配置 ID:
```

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
      "model": "claude-sonnet-4-6",
      "haikuModel": "",
      "sonnetModel": "",
      "opusModel": "",
      "cliModel": "",
      "extraEnv": {
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
      }
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `displayName` | Name shown in Web UI and menus |
| `shortcut` | Legacy shortcut command (default: `<id>-claude`) |
| `baseUrl` | Anthropic-compatible endpoint URL |
| `authEnv` | Auth method: `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_API_KEY` |
| `apiKeyEnv` | Windows environment variable containing the API key |
| `apiKeyFile` | Alternative: read key from a file |
| `model` | Default model (`ANTHROPIC_MODEL` env var) |
| `haikuModel` / `sonnetModel` / `opusModel` | Model family mapping overrides |
| `cliModel` | Default `--model` CLI argument |
| `extraEnv` | Additional environment variables (JSON object) |

### Codex CLI

File: `%USERPROFILE%\.codex\provider-profiles\providers.json`

```json
{
  "version": 1,
  "profiles": {
    "ds": {
      "displayName": "DeepSeek",
      "shortcut": "ds-codex",
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

| Field | Description |
|-------|-------------|
| `displayName` | Name shown in Web UI and menus |
| `shortcut` | Legacy shortcut (default: `<id>-codex`) |
| `baseUrl` | OpenAI-compatible endpoint URL |
| `apiKeyEnv` / `apiKeyFile` | API key source |
| `model` | Default model name |
| `modelContextWindow` | Context window size |
| `modelReasoningEffort` | `high` / `xhigh` / `max` |
| `modelReasoningSummary` | `auto` / `concise` |
| `modelVerbosity` | `low` / `medium` / `high` |
| `supportsWebsockets` | `true` / `false` |
| `requestMaxRetries` | Max retries for requests |
| `streamMaxRetries` | Max retries for streams |
| `streamIdleTimeoutMs` | Stream idle timeout in ms |
| `queryParams` | Extra URL query parameters (JSON object) |
| `httpHeaders` | Extra HTTP headers (JSON object) |
| `envHttpHeaders` | Headers sourced from env vars (JSON object) |
| `extraEnv` | Additional environment variables (JSON object) |

### Adding a Provider

**Option A: Web UI** (recommended)

```powershell
ccp-manager    # or cdp-manager
```

Click "新增配置", fill in the fields, click "保存并同步".

**Option B: Manual**

Edit the JSON file, then sync:

```powershell
ccp-sync    # or cdp-sync
```

---

## Web Management

A unified Web server provides tabbed management for all registered tools.

```powershell
ccp-manager    # Starts on port 15723
cdp-manager    # Starts on port 15724
```

The server auto-detects if an instance is already running and reuses it.

Features:
- Tabbed interface: switch between Claude Code and Codex CLI configs
- Add / copy / delete provider profiles
- Save and sync shortcut commands in one click
- Validation of IDs, command names, and required fields
- Collapsible profile cards with live preview

Requires [Node.js](https://nodejs.org/) 18+.

---

## Developer Guide: Adding a New Tool

The architecture follows the **Open-Closed Principle**: the core is closed for modification, open for extension. Adding a new AI CLI tool requires **zero changes to core logic**.

### Example: Adding `opencode` support

**Step 1 — Create 3 thin wrapper scripts** (`src/tools/opencode/`):

**`Invoke-OpenCodeProvider.ps1`** (~40 lines):
```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools\Import-Core.ps1')
Import-ProviderCore

$tool = Get-ProviderTool -Name 'opencode'
$config = Read-JsonFile -Path $tool.configPath
if (-not $config.ContainsKey('profiles')) { throw '配置文件必须包含 profiles 对象' }

$profileId = $null; $remaining = @(); $showList = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = "$($args[$i])"
    if ($a -in @('list','ls'))           { $showList = $true }
    elseif ($a -in @('sync'))            { & $tool.syncScript; exit $LASTEXITCODE }
    elseif ($a -in @('manager','manage')){ & $tool.manageScript; exit $LASTEXITCODE }
    elseif (-not $a.StartsWith('-') -and -not $profileId) { $profileId = $a }
    else { $remaining += $a }
}
if ($showList) { Write-ProfileTable -Profiles $config.profiles -Tool $tool; exit 0 }
if (-not $profileId) {
    $profileId = Select-ProfileFromMenu -Profiles $config.profiles -Tool $tool
    if (-not $profileId) { exit 0 }
}
Invoke-ProviderSession -ToolName 'opencode' -ProfileId $profileId -RemainingArgs $remaining
```

**`Sync-OpenCodeShortcuts.ps1`** (~5 lines):
```powershell
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Import-Core.ps1')
Import-ProviderCore
Sync-ToolShortcuts -ToolName 'opencode'
```

**`Manage-OpenCodeUI.ps1`** — same pattern as `Manage-ClaudeUI.ps1`.

**Step 2 — Register the tool** (add to `ProviderCore.psm1`):

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
            # Build tool-specific launch args here
            return @{
                LaunchArgs = @('--provider-url', $Profile.baseUrl) + $RemainingArgs
                EnvVars    = @{ 'OPENCODE_API_KEY' = $ApiKey }
                TempFile   = $null
            }
        }
    }
}
```

**Step 3 — Add deployment** (append to `install.ps1`):
```powershell
# Deploy opencode files
Copy-Item ... (same pattern as Claude/Codex sections)
```

**Step 4 — Add Web UI tab** (optional):
Add `'opencode'` entry to `TOOL_META` in `src/web/app.js` and create a template in `index.html`.

**Total: ~50 lines of tool-specific code. Core: 0 changes.**

---

## Installation Layout

After running `install.ps1`, files are deployed to:

```
%USERPROFILE%\
├── .claude\
│   ├── provider-profiles\
│   │   ├── providers.json              ← Your Claude provider configs
│   │   ├── server.mjs                  ← Web server (shared code)
│   │   ├── web/                        ← Web UI (shared code)
│   │   └── src\
│   │       ├── core\ProviderCore.psm1  ← Core module
│   │       ├── tools\Import-Core.ps1   ← Bootstrap
│   │       └── tools\claude\           ← Claude scripts
│   └── bin\                            ← ccp, ccp-*, *-claude shortcuts
│
├── .codex\
│   ├── provider-profiles\
│   │   ├── providers.json              ← Your Codex provider configs
│   │   ├── server.mjs                  ← Web server (same code)
│   │   ├── web/                        ← Web UI (same code)
│   │   └── src\
│   │       ├── core\ProviderCore.psm1  ← Core module (same code)
│   │       ├── tools\Import-Core.ps1
│   │       └── tools\codex\            ← Codex scripts
│   └── bin\                            ← cdp, cdp-*, *-codex shortcuts
```

Both tools share identical core code but operate independently.

---

## FAQ

### Shortcut command not found

```powershell
$env:Path -split ';' | Select-String '\.(claude|codex)\\bin'
.\install.ps1 -AddPath   # Re-add to PATH, then restart terminal
```

### "Missing apiKey" error

```powershell
$env:MI_CLAUDE_API_KEY    # Verify the variable exists
# If just set, restart terminal
```

### Model pollution between terminals

New scripts auto-clean on exit. If needed manually:

```powershell
Remove-Item Env:\ANTHROPIC_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
```

### Will this break after tool updates?

No. Shortcuts call the original `claude` / `codex` binary. No installation files are modified.

### Can I use the same provider for both tools?

Yes, but each tool has its own config file. Copy the profile entry from one config to the other.

---

## Security

- Never commit real API keys to git.
- Prefer `apiKeyEnv` (environment variable) over inline `apiKey`.
- Installer does not overwrite existing `providers.json` unless `-OverwriteConfig` is specified.
- Environment variables are scoped to the current process and cleaned up on exit.

---

## License

[MIT](LICENSE)