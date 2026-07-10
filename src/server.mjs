import http from 'node:http';
import { spawn } from 'node:child_process';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, writeFile, stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.join(root, 'web');
const args = process.argv.slice(2);

function getArgValue(name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : null;
}

const port = Number(getArgValue('--port') || 15723);
const requestedTool = getArgValue('--tool');
const activeTool = ['claude', 'codex'].includes(requestedTool) ? requestedTool : 'claude';
const userHome = process.env.USERPROFILE || process.env.HOME;
const authToken = getArgValue('--auth-token') || randomBytes(32).toString('base64url');
const authCookieName = 'provider_profiles_auth';

if (!userHome) {
  throw new Error('无法定位用户目录：USERPROFILE/HOME 未设置');
}

function getProfileRoot(toolName) {
  const toolDir = toolName === 'codex' ? '.codex' : '.claude';
  return path.join(userHome, toolDir, 'provider-profiles');
}

function getConfigPath(toolName) {
  return path.join(getProfileRoot(toolName), 'providers.json');
}

function getSyncScript(toolName, scriptName) {
  const isRepoLayout = path.basename(root).toLowerCase() === 'src';
  if (isRepoLayout) {
    return path.join(root, 'tools', toolName, scriptName);
  }
  return path.join(getProfileRoot(toolName), 'src', 'tools', toolName, scriptName);
}

// Tool registry: each tool maps to its config path and sync script
const TOOLS = {
  claude: {
    configPath: getConfigPath('claude'),
    syncScript: getSyncScript('claude', 'Sync-ClaudeShortcuts.ps1'),
    displayName: 'Claude Code',
    fields: {
      stringKeys: [
        'displayName', 'shortcut', 'baseUrl', 'authEnv', 'apiKey',
        'apiKeyEnv', 'apiKeyFile', 'model', 'haikuModel', 'sonnetModel',
        'opusModel', 'cliModel'
      ],
      jsonKeys: ['extraEnv']
    }
  },
  codex: {
    configPath: getConfigPath('codex'),
    syncScript: getSyncScript('codex', 'Sync-CodexShortcuts.ps1'),
    displayName: 'Codex CLI',
    fields: {
      stringKeys: [
        'displayName', 'shortcut', 'baseUrl', 'apiKey', 'apiKeyEnv',
        'apiKeyFile', 'model', 'wireApi', 'modelReasoningEffort',
        'modelReasoningSummary', 'modelVerbosity'
      ],
      numberKeys: [
        'modelContextWindow', 'requestMaxRetries', 'streamMaxRetries',
        'streamIdleTimeoutMs'
      ],
      booleanKeys: ['supportsWebsockets'],
      jsonKeys: ['queryParams', 'httpHeaders', 'envHttpHeaders', 'extraEnv']
    }
  }
};

const profileIdPattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$/;
const reservedProfileIds = new Set(['list', 'ls', 'help', 'usage', 'sync', 'manager', 'manage', 'setup', 'add', 'configure', 'profiles']);
const reservedCommandNames = new Set([
  'ccp', 'ccp-list', 'ccp-setup', 'ccp-sync', 'ccp-manager', 'ccp-profiles',
  'cdp', 'cdp-list', 'cdp-setup', 'cdp-sync', 'cdp-manager', 'cdp-profiles'
]);

function sendJson(res, status, data) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store'
  });
  res.end(JSON.stringify(data, null, 2));
}

function sendText(res, status, text) {
  res.writeHead(status, { 'content-type': 'text/plain; charset=utf-8' });
  res.end(text);
}

function parseCookies(req) {
  const result = new Map();
  const raw = req.headers.cookie || '';
  for (const part of raw.split(';')) {
    const index = part.indexOf('=');
    if (index <= 0) continue;
    result.set(part.slice(0, index).trim(), part.slice(index + 1).trim());
  }
  return result;
}

function isTokenMatch(candidate) {
  if (!candidate || typeof candidate !== 'string') return false;
  const expected = Buffer.from(authToken, 'utf8');
  const actual = Buffer.from(candidate, 'utf8');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function isAuthorized(req) {
  const headerToken = req.headers['x-provider-profiles-token'];
  if (isTokenMatch(Array.isArray(headerToken) ? headerToken[0] : headerToken)) return true;
  return isTokenMatch(parseCookies(req).get(authCookieName));
}

function sendUnauthorized(res) {
  sendText(res, 401, '未授权：请通过 ccp manager / cdp manager 打开管理页面');
}

function sendAuthRedirect(res, toolName) {
  const safeTool = ['claude', 'codex'].includes(toolName) ? toolName : activeTool;
  res.writeHead(302, {
    'set-cookie': `${authCookieName}=${authToken}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800`,
    'location': `/?tool=${encodeURIComponent(safeTool)}`,
    'cache-control': 'no-store'
  });
  res.end();
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
    if (chunks.reduce((s, c) => s + c.length, 0) > 1024 * 1024) {
      throw new Error('请求体过大');
    }
  }
  return Buffer.concat(chunks).toString('utf8');
}

function getTool(name) {
  const tool = TOOLS[name];
  if (!tool) throw new Error(`未知工具：${name}`);
  return tool;
}

async function readConfig(tool) {
  try {
    const text = await readFile(tool.configPath, 'utf8');
    return JSON.parse(text);
  } catch (error) {
    if (error.code === 'ENOENT') return { version: 1, profiles: {} };
    throw error;
  }
}

async function writeConfig(tool, config) {
  await mkdir(path.dirname(tool.configPath), { recursive: true });
  await writeFile(tool.configPath, `${JSON.stringify(config, null, 2)}\n`, 'utf8');
}

function runPwshScript(scriptPath) {
  return new Promise((resolve, reject) => {
    const child = spawn('pwsh', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath], {
      cwd: path.dirname(scriptPath),
      windowsHide: true
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', c => stdout += c.toString('utf8'));
    child.stderr.on('data', c => stderr += c.toString('utf8'));
    child.on('error', reject);
    child.on('close', code => {
      if (code === 0) resolve({ stdout, stderr });
      else {
        const error = new Error((stderr || stdout || `pwsh 退出码：${code}`).trim());
        error.code = code;
        reject(error);
      }
    });
  });
}

function normalizeProfile(input, toolName) {
  const profile = {};
  const tool = TOOLS[toolName];
  const allStringKeys = tool.fields.stringKeys || [];
  const allNumberKeys = tool.fields.numberKeys || [];
  const allBooleanKeys = tool.fields.booleanKeys || [];
  const allJsonKeys = tool.fields.jsonKeys || [];

  for (const key of allStringKeys) {
    if (Object.prototype.hasOwnProperty.call(input, key)) {
      profile[key] = typeof input[key] === 'string' ? input[key].trim() : input[key];
    }
  }

  for (const key of allNumberKeys) {
    if (Object.prototype.hasOwnProperty.call(input, key) && input[key] !== '' && input[key] != null) {
      profile[key] = Number(input[key]);
    }
  }

  for (const key of allBooleanKeys) {
    if (Object.prototype.hasOwnProperty.call(input, key) && input[key] !== '' && input[key] != null) {
      profile[key] = Boolean(input[key]);
    }
  }

  for (const key of allJsonKeys) {
    if (input[key] && typeof input[key] === 'object' && !Array.isArray(input[key])) {
      profile[key] = {};
      for (const [k, v] of Object.entries(input[key])) {
        if (`${k}`.trim()) profile[key][`${k}`.trim()] = v;
      }
    }
  }

  if (toolName === 'codex') {
    profile.wireApi = profile.wireApi || 'responses';
  }

  return profile;
}

function validateProfileId(id) {
  if (!profileIdPattern.test(id)) return '配置 ID 格式不合法（1-40 位字母/数字/下划线/连字符）';
  if (reservedProfileIds.has(id.toLowerCase())) return '配置 ID 与内置命令冲突';
  return null;
}

function validateProfileCommandName(name) {
  if (!profileIdPattern.test(name)) return '快捷命令格式不合法';
  if (reservedCommandNames.has(name.toLowerCase())) return '快捷命令与内置命令冲突';
  return null;
}

function validateProfile(profile, toolName) {
  if (!profile.baseUrl) return 'baseUrl 不能为空';
  if (!/^https?:\/\//i.test(profile.baseUrl)) return 'baseUrl 必须以 http(s):// 开头';
  if (toolName === 'codex' && profile.wireApi && profile.wireApi !== 'responses') {
    return 'wireApi 当前仅支持 responses';
  }
  return null;
}

async function serveStatic(req, res) {
  const url = new URL(req.url, 'http://127.0.0.1');
  const relative = decodeURIComponent(url.pathname === '/' ? 'index.html' : url.pathname.replace(/^\/+/, ''));
  const filePath = path.normalize(path.join(webRoot, relative));
  if (path.relative(webRoot, filePath).startsWith('..') || path.isAbsolute(path.relative(webRoot, filePath))) {
    sendText(res, 403, '禁止访问');
    return;
  }
  try {
    const fileStat = await stat(filePath);
    if (!fileStat.isFile()) { sendText(res, 404, '未找到'); return; }
    const ext = path.extname(filePath);
    const type = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'application/javascript; charset=utf-8' }[ext]
      || 'application/octet-stream';
    res.writeHead(200, { 'content-type': type, 'cache-control': 'no-store' });
    createReadStream(filePath).pipe(res);
  } catch { sendText(res, 404, '未找到'); }
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://127.0.0.1');

    // Health check
    if (req.method === 'GET' && url.pathname === '/api/health') {
      const payload = { ok: true, auth: 'token' };
      if (isAuthorized(req)) {
        payload.root = root;
        payload.activeTool = activeTool;
        payload.tools = Object.keys(TOOLS);
      }
      sendJson(res, 200, payload);
      return;
    }

    if (req.method === 'GET' && url.pathname === '/auth') {
      const token = url.searchParams.get('token');
      if (!isTokenMatch(token)) {
        sendText(res, 403, '授权 token 无效');
        return;
      }
      sendAuthRedirect(res, url.searchParams.get('tool'));
      return;
    }

    if (!isAuthorized(req)) {
      sendUnauthorized(res);
      return;
    }

    // Tool list
    if (req.method === 'GET' && url.pathname === '/api/tools') {
      const list = {};
      for (const [name, tool] of Object.entries(TOOLS)) {
        list[name] = { displayName: tool.displayName, fields: tool.fields, configPath: tool.configPath };
      }
      sendJson(res, 200, list);
      return;
    }

    // Tool-specific routes: /api/{tool}/config, /api/{tool}/sync
    const toolMatch = url.pathname.match(/^\/api\/([a-z]+)\/(config|sync)$/);
    if (toolMatch) {
      const [, toolName, action] = toolMatch;
      const tool = getTool(toolName);

      if (req.method === 'GET' && action === 'config') {
        const config = await readConfig(tool);
        sendJson(res, 200, config);
        return;
      }

      if (req.method === 'PUT' && action === 'config') {
        const body = await readBody(req);
        const incoming = JSON.parse(body);
        if (!incoming?.profiles || typeof incoming.profiles !== 'object') {
          sendJson(res, 400, { error: '配置必须包含 profiles 对象' });
          return;
        }

        const next = { version: 1, profiles: {} };
        const usedCommands = new Map();

        for (const [id, value] of Object.entries(incoming.profiles)) {
          const idErr = validateProfileId(id);
          if (idErr) { sendJson(res, 400, { error: `${id}: ${idErr}` }); return; }

          const profile = normalizeProfile(value || {}, toolName);
          const profErr = validateProfile(profile, toolName);
          if (profErr) { sendJson(res, 400, { error: `${id}: ${profErr}` }); return; }

          const suffix = toolName === 'codex' ? 'codex' : 'claude';
          const prefix = toolName === 'codex' ? 'cdp' : 'ccp';
          const shortcut = profile.shortcut || `${id}-${suffix}`;
          const cmdNames = [shortcut, `${prefix}-${id}`, id];

          for (const name of cmdNames) {
            const cmdErr = validateProfileCommandName(name);
            if (cmdErr) { sendJson(res, 400, { error: `${id}: ${cmdErr}：${name}` }); return; }
            const key = name.toLowerCase();
            if (usedCommands.has(key)) {
              sendJson(res, 400, { error: `${id}: 快捷命令与 ${usedCommands.get(key)} 冲突：${name}` });
              return;
            }
            usedCommands.set(key, id);
          }
          next.profiles[id] = profile;
        }

        await writeConfig(tool, next);
        // 保存即同步：自动重建 bin/*.ps1 shim，免去用户再点"同步"按钮
        let syncOutput = '';
        try {
          const r = await runPwshScript(tool.syncScript);
          syncOutput = `${r.stdout}${r.stderr}`.trim();
        } catch (err) {
          // 配置已保存成功；只是 shim 生成失败 — 仍返回 200，由前端展示同步异常
          syncOutput = `同步失败：${err.message || err}`;
        }
        sendJson(res, 200, { ...next, syncOutput });
        return;
      }

      if (req.method === 'POST' && action === 'sync') {
        const result = await runPwshScript(tool.syncScript);
        sendJson(res, 200, { ok: true, output: `${result.stdout}${result.stderr}`.trim() });
        return;
      }
    }

    await serveStatic(req, res);
  } catch (error) {
    sendJson(res, 500, { error: error.message || String(error) });
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Provider Profiles 管理台： http://127.0.0.1:${port}/auth?token=${encodeURIComponent(authToken)}&tool=${encodeURIComponent(activeTool)}`);
  console.log('本地 API 已启用 token/cookie 访问保护');
  console.log(`已注册工具：${Object.keys(TOOLS).join(', ')}`);
  for (const [name, tool] of Object.entries(TOOLS)) {
    console.log(`${name} 配置文件：${tool.configPath}`);
  }
});
