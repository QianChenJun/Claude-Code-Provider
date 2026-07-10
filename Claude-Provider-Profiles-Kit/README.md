# AI CLI Switcher 安装包

这是给普通用户使用的安装包。它会安装 `ccp`（Claude Code）和 `cdp`（Codex CLI）两套供应商切换命令。

> Windows only · PowerShell 7+ · 不包含真实 API Key

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

**最快 — 一键远程安装**（在 PowerShell 7 中直接粘贴；会把 `~\.claude\bin` / `~\.codex\bin` 加入用户级 PATH）：

```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/QianChenJun/Claude-Code-Provider/main/Claude-Provider-Profiles-Kit/install.ps1).Content)) -AddPath
```

> 远程安装会执行 `main` 分支中的脚本。企业或安全敏感环境建议从 GitHub Releases 下载固定版本，检查 `install.ps1` 后再运行。

**本地解压后安装（推荐用于企业或安全敏感环境）**：

```powershell
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

`-AddPath` 会修改当前 Windows 用户的 PATH。安装后重新打开 PowerShell / Windows Terminal。

预检（不写入任何文件）：

```powershell
.\install.ps1 -DryRun
```

安装后立刻进入配置向导：

```powershell
.\install.ps1 -AddPath -Configure
```

远程版给参数（如 PATH + 配置向导）：

```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/QianChenJun/Claude-Code-Provider/main/Claude-Provider-Profiles-Kit/install.ps1).Content)) -AddPath -Configure
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
管理页只监听 `127.0.0.1`。通过 `ccp manager` / `cdp manager` 打开时会自动携带随机本地 token；未授权请求不能读取或修改配置。

---

## 常用命令

| 操作 | Claude Code | Codex CLI |
|------|-------------|-----------|
| 配置向导 | `ccp setup` | `cdp setup` |
| 启动配置 | `ccp mi` | `cdp mi` |
| 查看列表 | `ccp list` | `cdp list` |
| 同步命令 | `ccp sync` | `cdp sync` |
| Web 管理 | `ccp manager` | `cdp manager` |
| 备份/导入 | `ccp profiles export/import` | `cdp profiles export/import` |

安装脚本也会生成 `ccp-mi`、`cdp-ds`、`mi-claude`、`mi` 等兼容快捷命令，但文档、脚本和日常交流推荐优先使用 `ccp mi` / `cdp ds`。如果配置 ID 与系统命令或其他工具同名，直呼命令可能受 PATH 顺序影响，因此不要把常见命令名当作配置 ID。

---

## 配置备份与迁移

```powershell
ccp profiles export -OutDir "$HOME\Desktop\provider-backup" -Tool all
ccp profiles import -InDir "$HOME\Desktop\provider-backup" -Tool all
ccp sync
cdp sync
```

导出默认会移除 `apiKey` / `token` / `key` 等明文密钥字段；环境变量名会保留，但 API Key 值不会导出。迁移到新机器后需要重新设置对应环境变量。

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

重新写入用户级 PATH：

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
