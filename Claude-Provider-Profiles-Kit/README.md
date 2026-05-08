# Claude Code 多供应商快捷配置安装包

这是一个可发给同事使用的无密钥安装包。

它的作用：

- 保留每个人自己电脑上的 Claude Code 原配置。
- 只在运行快捷命令时临时覆盖供应商 URL、API Key 和模型。
- 支持 `ccp-mi`、`ccp-ds`、`ccp-xxx` 这类统一前缀快捷命令。
- 支持本地页面管理供应商配置。

本安装包不包含真实 API Key。

旧命令如 `mi-claude`、`provider-claude`、`sync-claude-profiles` 仍会保留，便于兼容已有习惯。

---

## 1. 安装前要求

同事电脑需要先确认：

```powershell
claude --version
```

如果要使用本地管理页面，还需要：

```powershell
node --version
```

---

## 2. 安装

在本目录打开 PowerShell，执行：

```powershell
.\install.ps1
```

如果希望自动把快捷命令目录加入用户 PATH：

```powershell
.\install.ps1 -AddPath
```

安装后建议重开 PowerShell / Windows Terminal。

---

## 3. 安装到哪里

本工具不依赖 `cc-switch`。早期版本使用过 `%USERPROFILE%\.cc-switch\claude-profiles` 作为历史目录；新版安装时会自动迁移旧配置到下面的新目录，旧目录会保留不动。

配置和脚本会安装到：

```powershell
%USERPROFILE%\.claude\provider-profiles
```

快捷命令会安装到：

```powershell
%USERPROFILE%\.claude\bin
```

主配置文件：

```powershell
%USERPROFILE%\.claude\provider-profiles\providers.json
```

---

## 4. 配置 API Key

推荐使用 Windows 用户环境变量，不要把 Key 直接写到 JSON。

示例：

```powershell
[Environment]::SetEnvironmentVariable('MI_CLAUDE_API_KEY', '自己的-小米-key', 'User')
[Environment]::SetEnvironmentVariable('DS_CLAUDE_API_KEY', '自己的-deepseek-key', 'User')
```

设置后重开终端。

---

## 5. 编辑供应商配置

配置文件：

```powershell
%USERPROFILE%\.claude\provider-profiles\providers.json
```

模板来自：

```powershell
providers.example.json
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `displayName` | 显示名称 |
| `shortcut` | 快捷命令名，例如 `mi-claude` |
| `baseUrl` | Anthropic 兼容接口地址 |
| `authEnv` | `ANTHROPIC_AUTH_TOKEN` 或 `ANTHROPIC_API_KEY` |
| `apiKeyEnv` | 从哪个环境变量读取 API Key |
| `apiKey` | 可直接填 Key，但不推荐 |
| `model` | 默认模型，可留空 |
| `haikuModel` | Haiku 映射模型，可留空 |
| `sonnetModel` | Sonnet 映射模型，可留空 |
| `opusModel` | Opus 映射模型，可留空 |

---

## 6. 使用

打开菜单：

```powershell
ccp
```

菜单里可以按编号选择供应商，也可以输入 `列表`、`同步`、`管理`、`帮助`，英文 `list`、`sync`、`manager`、`help` 也保留兼容。

查看所有供应商：

```powershell
ccp-list
```

使用小米：

```powershell
ccp-mi
```

使用 DeepSeek：

```powershell
ccp-ds
```

临时覆盖模型：

```powershell
ccp-ds --model deepseek-model-name
```

非交互调用：

```powershell
ccp-mi -p "帮我总结这个项目"
```

---

## 7. 新增供应商

### 方式 A：页面管理

```powershell
ccp-manager
```

打开页面后新增供应商，点击 `保存并同步`。

页面默认以折叠卡片展示供应商。也可以点击已有供应商的“复制”，生成一个展开的副本后再改配置 ID、快捷命令、接口地址和 Key 来源。

页面按钮说明：

- `保存配置`：写入 `providers.json`。之后 `ccp` 菜单、`ccp-list`、`ccp <profile>` 会在下次运行时直接读取新配置。
- `保存并同步`：先保存，再生成/刷新 `ccp-xxx`、`xxx-claude` 这类快捷命令。新增供应商、修改配置 ID 或修改快捷命令时推荐用这个。
- `重新加载`：只把磁盘上的配置重新读回页面，常用于放弃未保存修改；它不是“生效”必需步骤。

删除供应商需要输入当前配置 ID 确认，避免误删。删除后仍需保存才会写入配置。

如果只点了 `保存配置`，之后又想生成快捷命令，也可以再执行：

```powershell
ccp-sync
```

### 方式 B：手动编辑 JSON

在 `providers.json` 的 `profiles` 中新增一段：

```json
"abc": {
  "displayName": "ABC Provider",
  "shortcut": "abc-claude",
  "baseUrl": "https://example.com/anthropic",
  "authEnv": "ANTHROPIC_AUTH_TOKEN",
  "apiKeyEnv": "ABC_CLAUDE_API_KEY",
  "apiKey": "",
  "model": "",
  "haikuModel": "",
  "sonnetModel": "",
  "opusModel": ""
}
```

然后执行：

```powershell
ccp-sync
```

---

## 8. 常见问题

### 快捷命令找不到

确认该目录在 PATH 中：

```powershell
%USERPROFILE%\.claude\bin
```

可以重新执行：

```powershell
.\install.ps1 -AddPath
```

然后重开终端。

### 报缺少 apiKey

检查环境变量是否存在：

```powershell
$env:MI_CLAUDE_API_KEY
$env:DS_CLAUDE_API_KEY
```

如果刚设置过环境变量，请重开终端。

### 新增供应商后命令不存在

执行：

```powershell
ccp-sync
```

### 不想覆盖已有配置

默认安装不会覆盖已有：

```powershell
%USERPROFILE%\.claude\provider-profiles\providers.json
```

如果确实要用模板覆盖：

```powershell
.\install.ps1 -OverwriteConfig
```

---

## 9. 安全建议

- 不要把真实 API Key 写进聊天、仓库、提交记录。
- 优先用 `apiKeyEnv`。
- 发给别人前，确认 `providers.json` 没有真实 Key。
