# Provider Profiles

Multi-provider switcher for AI CLI tools. Run different providers in different terminals simultaneously.

| Tool | Prefix | CLI | Status |
|------|--------|-----|--------|
| Claude Code | `ccp` | `claude` | Stable |
| Codex CLI | `cdp` | `codex` | Stable |
| (future) | `ocp` | `opencode` | Planned |

> Windows-only. Requires PowerShell 5.1+.

---

## Quick Start

```powershell
# Install from source
git clone https://github.com/QianChenJun/Claude-Provider-Profiles.git
cd Claude-Provider-Profiles\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath

# Restart terminal, then:
ccp-list                    # Claude Code providers
cdp-list                    # Codex CLI providers
ccp-mi                      # Launch Claude with Xiaomi MiMo
cdp-ds                      # Launch Codex with DeepSeek
```

See [Claude-Provider-Profiles-Kit/README.md](Claude-Provider-Profiles-Kit/README.md) for full documentation.

---

## Repository Structure

```
.
├── src/
│   ├── core/
│   │   └── ProviderCore.psm1        ← Shared core module (all tools)
│   ├── tools/
│   │   ├── Import-Core.ps1          ← Bootstrap: locates & imports core
│   │   ├── claude/
│   │   │   ├── Invoke-ClaudeProvider.ps1   ← Claude launcher (thin wrapper)
│   │   │   ├── Sync-ClaudeShortcuts.ps1    ← Shortcut sync
│   │   │   └── Manage-ClaudeUI.ps1         ← Web manager launcher
│   │   └── codex/
│   │       ├── Invoke-CodexProvider.ps1    ← Codex launcher (thin wrapper)
│   │       ├── Sync-CodexShortcuts.ps1
│   │       └── Manage-CodexUI.ps1
│   ├── web/
│   │   ├── index.html               ← Unified tabbed management UI
│   │   ├── app.js                   ← Frontend logic
│   │   └── styles.css               ← Shared styles
│   └── server.mjs                   ← Unified HTTP server (multi-tool)
│
├── config/
│   ├── providers.example.json       ← Claude config template
│   └── codex-providers.example.json ← Codex config template
│
├── Claude-Provider-Profiles-Kit/    ← Distribution kit
│   ├── install.ps1                  ← Installer
│   ├── README.md                    ← User documentation
│   ├── providers.example.json
│   ├── codex-providers.example.json
│   └── src/ → symlink to ../src
│
├── .codex/                          ← Project-level Codex hooks
│   ├── hooks/                       ← Encryption-environment guards
│   └── tools/Read-PlainText.ps1     ← E-SafeNet-safe file reader
│
└── .github/workflows/               ← CI/CD
```

---

## Architecture

### Core Module (`ProviderCore.psm1`)

All shared logic lives here. Tool scripts are **thin wrappers** (~30 lines each) that:

1. Dot-source `Import-Core.ps1`
2. Call `Import-ProviderCore`
3. Delegate to `Invoke-ProviderSession` / `Sync-ToolShortcuts`

The core handles:
- JSON/TOML serialization
- Profile resolution and validation
- API key resolution (env var > file > inline)
- Environment variable session management (set on launch, restore on exit)
- Interactive menu system
- Shortcut generation and cleanup

### Tool Registration

Each tool registers itself via `Register-ProviderTool`:

```powershell
Register-ProviderTool @{
    name           = 'claude'
    commandPrefix  = 'ccp'
    executable     = 'claude'
    configPath     = '~/.claude/provider-profiles/providers.json'
    launcher       = {
        param($Profile, $ApiKey, $ProfileId, $RemainingArgs, $Session)
        # Tool-specific launch logic
        return @{ LaunchArgs = @(); EnvVars = @{}; TempFile = $null }
    }
}
```

The `launcher` is the **only** tool-specific logic. Everything else is shared.

### Adding a New Tool

1. Create `src/tools/<tool>/` with 3 scripts (~50 lines total)
2. Add `Register-ProviderTool` block in `ProviderCore.psm1`
3. Add deployment lines in `install.ps1`

**Core logic: zero changes.**

---

## How It Works

```
User runs: ccp-mi (bin shim)
    ↓
Invoke-ClaudeProvider.ps1 -Profile mi
    ↓
ProviderCore: read config → resolve API key → create env session
    ↓
Claude launcher: build temp settings.json + env vars
    ↓
claude --settings <temp> [user args]
    ↓
Exit → delete temp file → restore original env vars
```

Same flow for `cdp-mi`, with Codex-specific launcher using `-c` TOML overrides instead of settings.json.

---

## Development

### Prerequisites

- PowerShell 5.1+ (pwsh 7+ recommended)
- Node.js 18+ (for Web management)
- Claude Code and/or Codex CLI

### Local Development

Scripts in `src/` work directly from the repository:

```powershell
# From repo root
. .\src\tools\Import-Core.ps1
Import-ProviderCore
Get-ProviderTools    # List registered tools
```

### CI

- `ci.yml`: PSScriptAnalyzer lint + `node --check` syntax validation
- `release.yml`: Package Kit into zip, create GitHub Release

---

## License

[MIT](LICENSE)