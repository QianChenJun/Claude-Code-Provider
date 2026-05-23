# AI CLI Switcher 安装包

这是给普通用户使用的安装包。它会安装 `ccp`（Claude Code）和 `cdp`（Codex CLI）两套供应商切换命令。

> Windows only · PowerShell 5.1+ / PowerShell 7+ · 不包含真实 API Key

---

## 安装前准备

至少安装一个 CLI：

```powershell
claude --version     # Claude Code，可选
codex --version      # Codex CLI，可选
node --version       # Web 管理页面需要 Node.js 18+，可选
```

---

## 推荐安装方式

```powershell
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

安装后重新打开 PowerShell / Windows Terminal。

如果想先预检安装会做什么、但不写入任何文件：

```powershell
.\install.ps1 -DryRun
```

如果想安装后立刻进入配置向导：

```powershell
.\install.ps1 -AddPath -Configure
```

---

## 新增供应商

推荐使用配置向导：

```powershell
ccp setup     # 配置 Claude Code 供应商
cdp setup     # 配置 Codex CLI 供应商
```

你只需要按提示填写：

- 配置 ID：例如 `mi`、`ds`、`openrouter`
- 显示名称
- 接口地址 `baseUrl`
- 默认模型 `model`
- API Key

API Key 会写入 Windows 用户环境变量，不会写进配置文件。

---

## 启动

```powershell
ccp mi        # 使用 mi 配置启动 Claude Code
ccp ds        # 使用 ds 配置启动 Claude Code
cdp mi        # 使用 mi 配置启动 Codex CLI
cdp ds        # 使用 ds 配置启动 Codex CLI
```

打开交互菜单：

```powershell
ccp
cdp
```

查看配置：

```powershell
ccp list
cdp list
```

---

## Web 管理页面

```powershell
ccp manager
cdp manager
```

需要 Node.js 18+。Web 页面可新增、复制、删除供应商配置，并一键保存同步快捷命令。

---

## 常用命令

| 操作 | Claude Code | Codex CLI |
|------|-------------|-----------|
| 配置向导 | `ccp setup` | `cdp setup` |
| 启动配置 | `ccp mi` | `cdp mi` |
| 查看列表 | `ccp list` | `cdp list` |
| 同步命令 | `ccp sync` | `cdp sync` |
| Web 管理 | `ccp manager` | `cdp manager` |

安装脚本也会生成 `ccp-mi`、`cdp-ds`、`mi-claude` 等兼容快捷命令，但文档推荐优先使用 `ccp mi` / `cdp ds`。

---

## 配置文件位置

| 工具 | 配置文件 |
|------|----------|
| Claude Code | `%USERPROFILE%\.claude\provider-profiles\providers.json` |
| Codex CLI | `%USERPROFILE%\.codex\provider-profiles\providers.json` |

手动编辑配置后，执行：

```powershell
ccp sync
cdp sync
```

---

## 常见问题

### `ccp` / `cdp` 命令找不到

重新执行：

```powershell
.\install.ps1 -AddPath
```

然后重开终端。

### 提示缺少 API Key

如果刚用 `ccp setup` / `cdp setup` 配置过，请重开终端。

也可以手动设置：

```powershell
[Environment]::SetEnvironmentVariable('MI_CLAUDE_API_KEY', '你的 API Key', 'User')
[Environment]::SetEnvironmentVariable('DS_CODEX_API_KEY', '你的 API Key', 'User')
```

### 不想覆盖已有配置

默认不会覆盖已有 `providers.json`。

只有显式指定才会覆盖：

```powershell
.\install.ps1 -OverwriteConfig
```

---

## 安全建议

- 不要把真实 API Key 写进仓库、聊天或提交记录
- 优先使用配置向导或 `apiKeyEnv`
- 发给别人前确认配置文件没有真实密钥
