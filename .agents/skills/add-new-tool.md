---
name: add-new-tool
description: 为 Claude-Provider-Profiles 新增 AI CLI 工具支持(如 OpenCode)
trigger: 用户说"新增工具支持"、"支持 OpenCode"、"添加新 CLI"
---

# 新增工具支持

## 何时使用

- 需要支持新的 AI CLI 工具(如 OpenCode、Aider、Cursor CLI)
- 已有工具需要修改注册信息
- 理解工具注册表机制

## 必须先阅读的文件

- `src/core/ProviderCore.psm1` (Register-ProviderTool 函数)
- `src/tools/claude/` (3 个 wrapper 示例)
- `Claude-Provider-Profiles-Kit/install.ps1` (部署逻辑)

## 推荐执行流程

假设新增 `opencode` 工具支持:

### 1. 注册工具到核心模块

编辑 `src/core/ProviderCore.psm1`,在模块末尾添加:

```powershell
Register-ProviderTool -Name 'opencode' -Config @{
    displayName = 'OpenCode'
    commandPrefix = 'ocp'
    binaryName = 'opencode'
    defaultShortcutSuffix = 'opencode'
    configPath = Join-Path $env:USERPROFILE '.opencode\provider-profiles\providers.json'
    binPath = Join-Path $env:USERPROFILE '.opencode\bin'
    syncScript = Join-Path $PSScriptRoot '..\tools\opencode\Sync-OpencodeShortcuts.ps1'
    manageScript = Join-Path $PSScriptRoot '..\tools\opencode\Manage-OpencodeUI.ps1'
}
```

### 2. 创建 Thin Wrapper 文件

创建 `src/tools/opencode/` 目录,添加 3 个文件:

**Invoke-OpencodeProvider.ps1**:
```powershell
#!/usr/bin/env pwsh
$ToolName = 'opencode'
$ProviderArgs = $args
. "$PSScriptRoot\..\Invoke-Provider.ps1"
```

**Sync-OpencodeShortcuts.ps1**:
```powershell
#!/usr/bin/env pwsh
$ToolName = 'opencode'
. "$PSScriptRoot\..\Sync-Shortcuts.ps1"
```

**Manage-OpencodeUI.ps1**:
```powershell
#!/usr/bin/env pwsh
$ToolName = 'opencode'
. "$PSScriptRoot\..\Manage-ProviderUI.ps1"
```

### 3. 配置示例模板

创建 `Claude-Provider-Profiles-Kit/opencode-providers.example.json`:

```json
{
  "version": 1,
  "profiles": {
    "mi": {
      "displayName": "Xiaomi MiMo",
      "baseUrl": "https://mimo.ai/api",
      "apiKeyEnv": "MI_OPENCODE_API_KEY",
      "model": "gpt-4"
    }
  }
}
```

### 4. 修改安装脚本

编辑 `Claude-Provider-Profiles-Kit/install.ps1`,在部署逻辑中添加:

```powershell
# OpenCode 工具专用文件
$opencodeToolDir = Join-Path $opencodeRoot 'src\tools\opencode'
Copy-RequiredFile -Source (Join-Path $sourceRoot 'tools\opencode\Invoke-OpencodeProvider.ps1') `
                  -Destination (Join-Path $opencodeToolDir 'Invoke-OpencodeProvider.ps1')
Copy-RequiredFile -Source (Join-Path $sourceRoot 'tools\opencode\Sync-OpencodeShortcuts.ps1') `
                  -Destination (Join-Path $opencodeToolDir 'Sync-OpencodeShortcuts.ps1')
Copy-RequiredFile -Source (Join-Path $sourceRoot 'tools\opencode\Manage-OpencodeUI.ps1') `
                  -Destination (Join-Path $opencodeToolDir 'Manage-OpencodeUI.ps1')

# 生成 OpenCode bin 快捷命令
$opencodeScriptPath = Join-Path $opencodeToolDir 'Invoke-OpencodeProvider.ps1'
$ocpScript = @"
#!/usr/bin/env pwsh
& '$opencodeScriptPath' @args
"@
$ocpScriptPath = Join-Path $opencodeBin 'ocp.ps1'
if (-not $DryRun) {
    [System.IO.File]::WriteAllText($ocpScriptPath, $ocpScript, [System.Text.UTF8Encoding]::new($false))
}
```

### 5. Web UI 支持(可选)

如果需要 Web UI 管理:

**修改 `src/server.mjs`**:
```javascript
const TOOLS = {
  // ... claude, codex
  opencode: {
    displayName: 'OpenCode',
    fields: {
      stringKeys: ['displayName', 'baseUrl', 'apiKeyEnv', 'model'],
      numberKeys: [],
      booleanKeys: [],
      jsonKeys: []
    },
    configPath: path.join(homedir(), '.opencode', 'provider-profiles', 'providers.json')
  }
}
```

**修改 `src/web/app.js`**:
```javascript
const TOOL_META = {
  // ... claude, codex
  opencode: {
    stringKeys: ['displayName', 'baseUrl', 'apiKeyEnv', 'model'],
    numberKeys: [],
    booleanKeys: [],
    jsonKeys: []
  }
}
```

**修改 `src/web/index.html`**:
```html
<template id="template-opencode">
  <div class="profile-card" data-profile-id="">
    <div class="grid">
      <label>Display Name</label>
      <input type="text" data-field="displayName" />
      
      <label>Base URL</label>
      <input type="text" data-field="baseUrl" />
      
      <label>API Key Env</label>
      <input type="text" data-field="apiKeyEnv" />
      
      <label>Model</label>
      <input type="text" data-field="model" />
    </div>
  </div>
</template>
```

### 6. 测试验证

```powershell
# 1. 运行所有测试
pwsh -NoProfile -File tests\core-function-tests.ps1
pwsh -NoProfile -File tests\setup-tests.ps1

# 2. 安装到本地测试
.\Claude-Provider-Profiles-Kit\install.ps1 -DryRun

# 3. 配置新工具
ocp setup

# 4. 启动新工具
ocp mi

# 5. Web UI 测试(如果实现)
ocp manager
```

## 工具注册表字段说明

| 字段 | 必需 | 说明 |
|------|------|------|
| `displayName` | ✅ | 工具显示名称 |
| `commandPrefix` | ✅ | 主命令前缀(如 `ccp`, `cdp`, `ocp`) |
| `binaryName` | ✅ | 实际 CLI 命令(如 `claude`, `codex`, `opencode`) |
| `defaultShortcutSuffix` | ✅ | 快捷命令后缀(如 `mi-claude`, `mi-codex`) |
| `configPath` | ✅ | `providers.json` 路径 |
| `binPath` | ✅ | 快捷命令目录 |
| `syncScript` | ✅ | 快捷命令同步脚本路径 |
| `manageScript` | ✅ | Web UI 启动脚本路径 |

## 禁止事项

- ❌ 不要修改 `Invoke-Provider.ps1` 等通用脚本(除非所有工具都需要)
- ❌ 不要在 wrapper 中硬编码工具特定逻辑(应通过注册表配置)
- ❌ 不要跳过测试验证

## 验证方式

```powershell
# 1. 检查工具注册
$tool = Get-ProviderTool -Name 'opencode'
$tool | Format-List

# 2. 检查快捷命令生成
ocp sync
ls $env:USERPROFILE\.opencode\bin

# 3. 检查配置向导
ocp setup

# 4. 检查启动流程
ocp list
ocp mi
```

## 常见问题

### 工具未注册

**症状**: `Get-ProviderTool -Name 'opencode'` 报错

**原因**: `Register-ProviderTool` 未调用或参数错误

**解决**: 检查 `ProviderCore.psm1` 末尾是否正确注册

### 快捷命令未生成

**症状**: `ocp` 命令找不到

**原因**: 
1. `install.ps1` 未部署 bin 快捷命令
2. PATH 未包含 `~\.opencode\bin`

**解决**: 
1. 检查安装脚本逻辑
2. 运行 `.\install.ps1 -AddPath`

### Web UI 无法切换到新工具

**原因**: `src/server.mjs` 和 `src/web/app.js` 未添加工具元数据

**解决**: 同步修改 3 处(server.mjs, app.js, index.html)