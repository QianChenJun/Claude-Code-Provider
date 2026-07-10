---
name: run-tests
description: 运行 AI CLI Switcher 测试套件,包括 PowerShell 和 JavaScript 语法检查
trigger: 用户说"运行测试"、"跑测试"、"test"、"验证修改"
---

# 运行测试套件

## 何时使用

- 修改核心模块、工具脚本、Web UI 后验证
- 发布前完整验证
- 排查测试失败原因

## 必须先阅读的文件

- `tests/*.ps1` (所有测试文件)
- `.github/workflows/ci.yml` (CI 配置)

## 推荐执行流程

### 快速检查(本地开发)

```powershell
# 核心功能测试
pwsh -NoProfile -File tests\core-function-tests.ps1

# 配置管理测试
pwsh -NoProfile -File tests\setup-tests.ps1

# JavaScript 语法检查
node --check src\server.mjs
node --check src\web\app.js
```

### 完整测试(发布前)

```powershell
# 1. 核心功能
pwsh -NoProfile -File tests\core-function-tests.ps1

# 2. 配置管理
pwsh -NoProfile -File tests\setup-tests.ps1

# 3. 安装脚本预检
pwsh -NoProfile -File tests\install-dryrun-tests.ps1

# 4. 远程引导安装
pwsh -NoProfile -File tests\install-bootstrap-tests.ps1

# 5. 配置导入导出
pwsh -NoProfile -File tests\profile-transfer-tests.ps1

# 6. Web 服务路径安全
pwsh -NoProfile -File tests\server-path-tests.ps1

# 7. JavaScript 语法
node --check src\server.mjs
node --check src\web\app.js
```

## 测试覆盖场景

| 测试文件 | 覆盖场景 |
|---------|---------|
| `core-function-tests.ps1` | JSON/TOML 序列化、API Key 解析、配置读写 |
| `setup-tests.ps1` | 配置向导、环境隔离、launcher 回滚、快捷命令同步 |
| `install-dryrun-tests.ps1` | 安装脚本 DryRun 模式 |
| `install-bootstrap-tests.ps1` | 远程引导安装流程 |
| `profile-transfer-tests.ps1` | 配置导入导出、密钥脱敏 |
| `server-path-tests.ps1` | Web 服务授权、路径遍历防护 |

## 修改后必须运行的测试

| 修改的文件/模块 | 必须运行的测试 |
|----------------|---------------|
| `src/core/ProviderCore.psm1` | `core-function-tests.ps1` + `setup-tests.ps1` |
| `src/tools/Invoke-Provider.ps1` | `setup-tests.ps1` |
| `src/tools/Manage-ProviderProfiles.ps1` | `profile-transfer-tests.ps1` |
| `Claude-Provider-Profiles-Kit/install.ps1` | `install-dryrun-tests.ps1` + `install-bootstrap-tests.ps1` |
| `src/server.mjs` / `src/web/*` | `server-path-tests.ps1` + `node --check` |
| 新增工具支持 | **所有测试** |

## 常用命令

```powershell
# 静态检查(PSScriptAnalyzer)
Get-ChildItem -Recurse -Include '*.ps1','*.psm1' |
  Where-Object { $_.FullName -notlike '*node_modules*' } |
  ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Severity Error }

# 快速烟雾测试
ccp
cdp
ccp manager
```

## 验证方式

测试通过标准:
- ✅ 所有测试文件退出码为 0
- ✅ 无 PowerShell 错误输出
- ✅ JavaScript 语法检查通过
- ✅ 手动烟雾测试(`ccp`、`cdp`、`ccp manager`)成功

## 禁止事项

- ❌ 不要跳过测试直接发布
- ❌ 不要只运行部分测试(除非本地快速迭代)
- ❌ 不要在测试失败时修改测试代码绕过失败

## 测试环境隔离

所有测试通过临时 `$env:USERPROFILE` 隔离:
- 不污染开发者真实 `.claude` / `.codex` 配置
- 测试结束后自动清理临时目录
- 每个测试独立运行,互不干扰
