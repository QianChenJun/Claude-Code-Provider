# AI CLI Switcher 安装包

给普通用户使用的安装包，安装后提供：

- `ccp`：Claude Code 供应商切换
- `cdp`：Codex CLI 供应商切换

> Windows only · PowerShell 7+ · 不包含真实 API Key

仓库与源码：https://github.com/QianChenJun/Claude-Code-Provider

---

## 安装前准备

至少安装一个 CLI：

```powershell
claude --version     # Claude Code，可选
codex --version      # Codex CLI，可选
node --version       # Web 管理页面需要 Node.js 18+，可选
```

---

## 安装

**最快 — 一键远程安装**（PowerShell 7）：

```powershell
& ([scriptblock]::Create((iwr https://raw.githubusercontent.com/QianChenJun/Claude-Code-Provider/main/Claude-Provider-Profiles-Kit/install.ps1).Content)) -AddPath
```

**本地解压后安装**（企业或安全敏感环境推荐）：

```powershell
cd <解压目录>\Claude-Provider-Profiles-Kit
.\install.ps1 -AddPath
```

预检（不写文件）：

```powershell
.\install.ps1 -DryRun
```

安装后立刻进入配置向导：

```powershell
.\install.ps1 -AddPath -Configure
```

`-AddPath` 会修改当前 Windows 用户 PATH。安装后请重新打开终端。

> 首次安装默认是**空配置**，不会预置具体供应商。请用 `ccp setup` / `cdp setup` 添加。

---

## 新增供应商

```powershell
ccp setup
cdp setup
```

按提示填写：

- 配置 ID（例如 `ds`、`openrouter`）
- 显示名称
- 接口地址 `baseUrl`
- 默认模型 `model`
- API Key

**当前默认行为：** API Key 会明文写入用户目录下的 `providers.json`。  
若希望从环境变量读取，可在配置中使用 `apiKeyEnv` 并删除 `apiKey` 字段。

---

## 日常使用

```powershell
ccp                 # 菜单
ccp list
ccp my-provider
ccp-my-provider     # 等价快捷命令

cdp my-provider
cdp manager         # Web 管理页（需 Node.js）
```

推荐使用 `ccp <id>` / `cdp <id>`。  
同步会生成 `ccp-<id>` 与兼容 shortcut，**不会**生成裸配置 ID 命令，避免与另一套工具 PATH 冲突。

---

## 配置位置

| 工具 | 路径 |
|------|------|
| Claude Code | `%USERPROFILE%\.claude\provider-profiles\providers.json` |
| Codex CLI | `%USERPROFILE%\.codex\provider-profiles\providers.json` |

备份与迁移：

```powershell
ccp profiles export -OutDir "$HOME\Desktop\provider-backup" -Tool all
ccp profiles import -InDir "$HOME\Desktop\provider-backup" -Tool all
ccp sync
cdp sync
```

导出默认会移除明文密钥字段；`apiKeyEnv` 名称会保留，值不会导出。

---

## 安全建议

- 默认明文 key 仅适合本机个人使用
- 更安全：使用 `apiKeyEnv` / `apiKeyFile`
- 不要把真实 API Key 提交到 git 或公开渠道
- 企业环境请使用固定 Release，并先检查 `install.ps1`

---

## 常见问题

**找不到 `ccp` / `cdp`：** 重新执行 `.\install.ps1 -AddPath` 并重开终端。

**新增配置后命令不存在：**

```powershell
ccp sync
cdp sync
```

**以前的 `any` / `gpt` 这种裸命令呢？**  
当前版本不再生成裸配置 ID 命令，请改用 `ccp any` / `cdp any` 或 `ccp-any` / `cdp-any`。

完整文档见仓库主 [README.md](https://github.com/QianChenJun/Claude-Code-Provider/blob/main/README.md)。
