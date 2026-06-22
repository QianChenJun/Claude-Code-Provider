---
name: web-ui-dev
description: 修改或调试 Claude-Provider-Profiles Web 管理界面
trigger: 用户说"修改 Web UI"、"调试前端"、"Web 管理页面"、"UI 问题"
---

# Web UI 开发与调试

## 何时使用

- 修改 Web 管理页面功能或样式
- 调试前后端交互问题
- 新增配置字段到 UI
- 排查保存/同步失败问题

## 必须先阅读的文件

- `src/web/index.html` (页面结构和模板)
- `src/web/app.js` (前端逻辑)
- `src/web/styles.css` (样式)
- `src/server.mjs` (后端 API)

## 技术栈

- **前端**: 纯 Vanilla JavaScript (无框架)
- **后端**: Node.js HTTP 服务 (无外部依赖)
- **构建**: 无(直接 `<script src="app.js">`)
- **设计**: Brutalist 风格(粗边框、高对比度)

## 推荐执行流程

### 1. 启动开发服务器

```powershell
# 方式 1: 通过 init.ps1
.\init.ps1 web

# 方式 2: 直接启动
node src/server.mjs --port 15722 --tool claude --auth-token dev123

# 访问授权入口
# http://127.0.0.1:15722/auth?token=dev123&tool=claude
```

### 2. 修改前端代码

用 PowerShell 工具读写文件:

```powershell
# 读取
$content = [System.IO.File]::ReadAllText("src\web\app.js", [System.Text.Encoding]::UTF8)

# 修改后写回
[System.IO.File]::WriteAllText("src\web\app.js", $newContent, [System.Text.UTF8Encoding]::new($false))
```

### 3. 刷新浏览器验证

- 修改 HTML/CSS/JS 后直接刷新(F5)
- 无需重启服务器或构建

### 4. 检查浏览器 Console

- Network 面板查看 API 请求
- Console 面板查看错误
- 全局变量: `currentConfig`, `toolMemory`, `currentTool`

## API 端点清单

| 端点 | 方法 | 用途 |
|------|------|------|
| `/api/health` | GET | 健康检查 |
| `/auth?token=xxx&tool=xxx` | GET | 认证并设置 Cookie |
| `/api/tools` | GET | 获取所有工具元数据 |
| `/api/{tool}/config` | GET | 读取配置 |
| `/api/{tool}/config` | PUT | 保存配置 + 自动同步快捷命令 |

## 新增配置字段流程

需要同步修改 **3 个地方**:

### 1. 修改 `src/server.mjs`

```javascript
const TOOLS = {
  claude: {
    displayName: 'Claude Code',
    fields: {
      stringKeys: ['displayName', 'baseUrl', 'newField'],  // 新增
      // ...
    }
  }
}
```

### 2. 修改 `src/web/app.js`

```javascript
const TOOL_META = {
  claude: {
    stringKeys: ['displayName', 'baseUrl', 'newField'],  // 新增
    // ...
  }
}
```

### 3. 修改 `src/web/index.html`

在 `<template id="template-claude">` 中添加表单字段:

```html
<label>New Field</label>
<input type="text" data-field="newField" />
```

## 项目内已有可复用模块

- `captureCurrentToolState()` — 保存当前工具状态到内存
- `restoreToolState(tool)` — 从内存恢复工具状态
- `collectConfig()` — 收集所有卡片数据
- `renderConfig(payload)` — 重新渲染配置
- `markDirty()` / `markClean()` — 脏状态管理

## 禁止事项

- ❌ 不要引入 npm 依赖(保持零依赖)
- ❌ 不要破坏 per-tool 内存机制
- ❌ 不要在前端日志打印 token
- ❌ 不要使用 Read/Write/Edit 工具读写代码文件

## 验证方式

```powershell
# 1. JavaScript 语法检查
node --check src\server.mjs
node --check src\web\app.js

# 2. 启动服务器
node src\server.mjs --tool claude

# 3. 浏览器操作验证
# - 新增配置
# - 编辑字段
# - 保存并同步
# - 切换工具标签页
# - 重新加载配置

# 4. 检查配置文件
cat $env:USERPROFILE\.claude\provider-profiles\providers.json

# 5. 检查快捷命令
ccp list
```

## 调试技巧

### 查看前端状态

浏览器 Console:
```javascript
currentConfig       // 当前配置快照
toolMemory          // per-tool 内存缓存
currentTool         // 当前激活工具
isDirty             // 未保存改动标记
```

### 模拟 API 请求

PowerShell:
```powershell
# 读取配置
Invoke-WebRequest -Uri "http://127.0.0.1:15722/api/claude/config" `
  -Headers @{ "X-Provider-Profiles-Token" = "dev123" }

# 保存配置
$body = Get-Content "test-config.json" -Raw
Invoke-WebRequest -Uri "http://127.0.0.1:15722/api/claude/config" `
  -Method PUT -Body $body -ContentType "application/json" `
  -Headers @{ "X-Provider-Profiles-Token" = "dev123" }
```

## 常见问题

### 保存后配置未生效

**原因**: 后端同步脚本失败

**排查**:
1. 检查响应中的 `syncOutput` 字段
2. 手动运行 `ccp sync` 查看错误
3. 检查 PowerShell 执行策略

### 切换工具后改动丢失

**原因**: per-tool 内存未正确保存

**排查**:
1. Console 查看 `toolMemory` 是否有缓存
2. 检查 `captureCurrentToolState()` 是否被调用
3. 确认切换前 `isDirty = true`

### 前端表单校验不生效

**原因**: 前端只做基础校验,后端会二次校验

**解决**: 检查后端返回的错误信息,补充前端实时校验