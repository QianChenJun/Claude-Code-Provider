# 安全策略

## 支持范围

安全修复优先应用于最新发布版本和 `main` 分支。旧版本可能不会单独回补修复，建议始终升级到最新 Release。

## 报告安全问题

请不要通过公开 Issue 报告以下问题：

- API Key、Token 或用户配置泄露
- 命令注入、路径穿越或任意文件读写
- Web 管理页面认证绕过
- 安装脚本供应链风险
- 其他可能影响用户系统或凭据安全的问题

请优先使用 GitHub 的 [私密漏洞报告](https://github.com/QianChenJun/Claude-Code-Provider/security/advisories/new) 提交复现步骤、影响范围和建议修复方式。如果该入口不可用，请通过 [维护者 GitHub 主页](https://github.com/QianChenJun) 中提供的联系方式私下联系。维护者确认前，请避免公开披露漏洞细节。

报告中请使用无效示例凭据，并对日志、路径和配置内容进行脱敏。

## 用户安全建议

- 当前配置向导默认把 API Key **明文写入** 用户目录下的 `providers.json`，便于本机快速使用。
- 更安全的做法是改用 `apiKeyEnv`（从用户环境变量读取）或 `apiKeyFile`（从仓库外文件读取），并删除配置里的 `apiKey` 字段。
- 不要把真实 API Key 提交到 git、Issue、聊天记录或截图中。
- 企业或安全敏感环境应下载固定版本的 Release，检查 `install.ps1` 后再执行。
- Web 管理页面仅应监听本机回环地址，不要通过端口转发暴露到局域网或公网。
