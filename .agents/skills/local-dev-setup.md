---
name: local-dev-setup
description: 初始化 Claude-Provider-Profiles 本地开发环境，检查依赖、配置供应商、同步快捷命令
trigger: 用户说"搭建开发环境"、"初始化开发"、"setup dev"、"开发环境准备"
---

# 本地开发环境搭建

## 何时使用

- 首次克隆项目后需要配置开发环境
- 新增供应商配置后需要同步快捷命令
- 排查开发环境问题(依赖缺失、PATH 未生效)

## 必须先阅读的文件

- `README.md` (快速开始、常用命令)
- `init.ps1` (开发环境快捷入口)
- `Claude-Provider-Profiles-Kit/install.ps1` (安装逻辑)

## 推荐执行流程

### 1. 检查依赖

```powershell
.\init.ps1 check
```

验证:
- PowerShell 版本 (5.1+ 或 7+)
- Node.js 版本 (18+)
- claude / codex CLI 是否已安装

### 2. 配置供应商

```powershell
.\init.ps1 setup
```

交互式配置向导会询问:
- 配置哪个工具 (Claude Code / Codex CLI)
- 配置 ID (如 `mi`, `ds`)
- 显示名称
- 接口地址 `baseUrl`
- 默认模型
- API Key (会写入用户环境变量)

### 3. 同步快捷命令

```powershell
.\init.ps1 sync
```

生成到:
- `%USERPROFILE%\.claude\bin\ccp-*.ps1`
- `%USERPROFILE%\.codex\bin\cdp-*.ps1`

### 4. 启动 Web 管理页面(可选)

```powershell
.\init.ps1 web
```

自动打开浏览器访问 `http://127.0.0.1:15722/auth?token=xxx&tool=claude`

## 常用命令

| 命令 | 用途 |
|------|------|
| `.\init.ps1 check` | 检查依赖 |
| `.\init.ps1 setup` | 新增/更新供应商配置 |
| `.\init.ps1 sync` | 同步快捷命令 |
| `.\init.ps1 web` | 启动 Web 管理台 |
| `.\init.ps1 list` | 查看已注册工具 |

## 项目内已有可复用模块

- `src/core/ProviderCore.psm1` — 核心逻辑模块
- `src/tools/Invoke-Provider.ps1` — 通用供应商启动器
- `src/tools/Sync-Shortcuts.ps1` — 通用快捷命令同步
- `src/tools/Manage-ProviderUI.ps1` — 通用 Web UI 启动器

## 禁止事项

- ❌ 不要使用 Read/Write/Edit 工具读写 PowerShell 脚本(加密环境问题)
- ❌ 不要跳过依赖检查直接配置
- ❌ 不要手动修改 `~/.claude/bin/*.ps1` shim 文件(应修改源码后重新 sync)

## 验证方式

```powershell
# 1. 验证 PATH
$env:Path -split ';' | Select-String '\.(claude|codex)\\bin'

# 2. 验证快捷命令可用
ccp
cdp

# 3. 验证配置列表
ccp list
cdp list

# 4. 验证 API Key 环境变量
$env:MI_CLAUDE_API_KEY
$env:DS_CODEX_API_KEY
```

## 常见问题

### PATH 未生效

**症状**: 提示 `ccp` 或 `cdp` 找不到

**解决**: 重新打开 PowerShell 终端,或手动加载:
```powershell
$env:Path += ";$env:USERPROFILE\.claude\bin;$env:USERPROFILE\.codex\bin"
```

### API Key 未生效

**症状**: 启动 CLI 时提示缺少 API Key

**解决**: 通过 `ccp setup` 重新设置,或手动设置环境变量后重启终端:
```powershell
[Environment]::SetEnvironmentVariable('MI_CLAUDE_API_KEY', 'sk-xxx', 'User')
```

### Web UI 启动失败

**症状**: `.\init.ps1 web` 报错

**解决**:
1. 检查 Node.js 版本: `node --version` (需要 18+)
2. 检查端口占用: `Get-NetTCPConnection -LocalPort 15722 -ErrorAction SilentlyContinue`
3. 手动指定端口: `node src/server.mjs --port 15723 --tool claude`