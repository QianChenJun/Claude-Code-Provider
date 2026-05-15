import http from 'node:http';
import { spawn } from 'node:child_process';
import { readFile, writeFile, stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const configPath = path.join(root, 'providers.json');
const webRoot = path.join(root, 'web');
const syncScript = path.join(root, 'Sync-CodexProfileShortcuts.ps1');
const commandPrefix = 'cdp';
const profileIdPattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$/;
const reservedProfileIds = new Set(['list', 'ls', 'help', 'usage', 'sync', 'manager', 'manage']);
const reservedCommandNames = new Set([
  commandPrefix,
  `${commandPrefix}-list`,
  `${commandPrefix}-sync`,
  `${commandPrefix}-manager`,
  'provider-codex',
  'codex-profile-manager',
  'sync-codex-profiles'
]);

const args = process.argv.slice(2);
const portIndex = args.indexOf('--port');
const port = portIndex >= 0 ? Number(args[portIndex + 1]) : 15724;

function sendJson(res, status, data) {
  const body = JSON.stringify(data, null, 2);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store'
  });
  res.end(body);
}

function sendText(res, status, text) {
  res.writeHead(status, { 'content-type': 'text/plain; charset=utf-8' });
  res.end(text);
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
    const length = chunks.reduce((sum, item) => sum + item.length, 0);
    if (length > 1024 * 1024) {
      throw new Error('请求体过大');
    }
  }
  return Buffer.concat(chunks).toString('utf8');
}

async function readConfig() {
  const text = await readFile(configPath, 'utf8');
  return JSON.parse(text);
}

async function writeConfig(config) {
  await writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`, 'utf8');
}

function runPwshScript(scriptPath) {
  return new Promise((resolve, reject) => {
    const child = spawn('pwsh', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath], {
      cwd: root,
      windowsHide: true
    });
    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString('utf8');
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
    });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        const error = new Error((stderr || stdout || `pwsh 退出码：${code}`).trim());
        error.code = code;
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
      }
    });
  });
}

function normalizeProfile(input) {
  const profile = {};
  for (const key of [
    'displayName',
    'shortcut',
    'baseUrl',
    'apiKey',
    'apiKeyEnv',
    'apiKeyFile',
    'model',
    'wireApi',
    'modelReasoningEffort',
    'modelReasoningSummary',
    'modelVerbosity'
  ]) {
    if (Object.prototype.hasOwnProperty.call(input, key)) {
      profile[key] = typeof input[key] === 'string' ? input[key].trim() : input[key];
    }
  }

  for (const key of ['modelContextWindow', 'requestMaxRetries', 'streamMaxRetries', 'streamIdleTimeoutMs']) {
    if (Object.prototype.hasOwnProperty.call(input, key) && input[key] !== '' && input[key] !== null && input[key] !== undefined) {
      profile[key] = Number(input[key]);
    }
  }

  if (Object.prototype.hasOwnProperty.call(input, 'supportsWebsockets') && input.supportsWebsockets !== '' && input.supportsWebsockets !== null && input.supportsWebsockets !== undefined) {
    profile.supportsWebsockets = Boolean(input.supportsWebsockets);
  }

  for (const key of ['queryParams', 'httpHeaders', 'envHttpHeaders', 'extraEnv']) {
    if (input[key] && typeof input[key] === 'object' && !Array.isArray(input[key])) {
      profile[key] = {};
      for (const [entryKey, value] of Object.entries(input[key])) {
        if (`${entryKey}`.trim()) {
          profile[key][`${entryKey}`.trim()] = value;
        }
      }
    }
  }

  profile.wireApi ||= 'responses';
  return profile;
}

function validateProfileId(id) {
  if (!profileIdPattern.test(id)) {
    return '配置 ID 只能使用 1-40 位英文字母、数字、下划线或连字符，并且必须以字母或数字开头';
  }
  if (reservedProfileIds.has(id.toLowerCase())) {
    return '配置 ID 与内置菜单命令冲突';
  }
  return null;
}

function validateCommandName(name) {
  if (!profileIdPattern.test(name)) {
    return '快捷命令只能使用 1-40 位英文字母、数字、下划线或连字符，并且必须以字母或数字开头';
  }
  if (reservedCommandNames.has(name.toLowerCase())) {
    return '快捷命令与内置命令冲突';
  }
  return null;
}

function validateObjectField(profile, fieldName) {
  if (!Object.prototype.hasOwnProperty.call(profile, fieldName)) {
    return null;
  }
  if (!profile[fieldName] || typeof profile[fieldName] !== 'object' || Array.isArray(profile[fieldName])) {
    return `${fieldName} 必须是 JSON 对象`;
  }
  return null;
}

function validateProfile(profile) {
  if (!profile.baseUrl) {
    return 'baseUrl 不能为空';
  }
  if (!/^https?:\/\//i.test(profile.baseUrl)) {
    return 'baseUrl 必须以 http:// 或 https:// 开头';
  }
  if (profile.wireApi !== 'responses') {
    return 'wireApi 当前仅支持 responses';
  }
  for (const fieldName of ['queryParams', 'httpHeaders', 'envHttpHeaders', 'extraEnv']) {
    const error = validateObjectField(profile, fieldName);
    if (error) {
      return error;
    }
  }
  for (const fieldName of ['modelContextWindow', 'requestMaxRetries', 'streamMaxRetries', 'streamIdleTimeoutMs']) {
    if (Object.prototype.hasOwnProperty.call(profile, fieldName) && !Number.isFinite(profile[fieldName])) {
      return `${fieldName} 必须是数字`;
    }
  }
  return null;
}

async function serveStatic(req, res) {
  const url = new URL(req.url, 'http://127.0.0.1');
  const relative = decodeURIComponent(url.pathname === '/' ? 'index.html' : url.pathname.replace(/^\/+/, ''));
  const filePath = path.normalize(path.join(webRoot, relative));
  const relativeToWeb = path.relative(webRoot, filePath);
  if (relativeToWeb.startsWith('..') || path.isAbsolute(relativeToWeb)) {
    sendText(res, 403, '禁止访问');
    return;
  }
  try {
    const fileStat = await stat(filePath);
    if (!fileStat.isFile()) {
      sendText(res, 404, '未找到');
      return;
    }
    const ext = path.extname(filePath);
    const type = {
      '.html': 'text/html; charset=utf-8',
      '.css': 'text/css; charset=utf-8',
      '.js': 'application/javascript; charset=utf-8'
    }[ext] || 'application/octet-stream';
    res.writeHead(200, { 'content-type': type, 'cache-control': 'no-store' });
    createReadStream(filePath).pipe(res);
  } catch {
    sendText(res, 404, '未找到');
  }
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://127.0.0.1');

    if (req.method === 'GET' && url.pathname === '/api/config') {
      const config = await readConfig();
      sendJson(res, 200, config);
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/health') {
      sendJson(res, 200, {
        ok: true,
        root,
        configPath
      });
      return;
    }

    if (req.method === 'PUT' && url.pathname === '/api/config') {
      const body = await readBody(req);
      const incoming = JSON.parse(body);
      if (!incoming || typeof incoming !== 'object' || !incoming.profiles || typeof incoming.profiles !== 'object') {
        sendJson(res, 400, { error: '配置必须包含 profiles 对象' });
        return;
      }

      const next = { version: 1, profiles: {} };
      const usedCommandNames = new Map();
      for (const [id, value] of Object.entries(incoming.profiles)) {
        const idError = validateProfileId(id);
        if (idError) {
          sendJson(res, 400, { error: `${id}: ${idError}` });
          return;
        }
        const profile = normalizeProfile(value || {});
        const error = validateProfile(profile);
        if (error) {
          sendJson(res, 400, { error: `${id}: ${error}` });
          return;
        }
        const commandNames = [profile.shortcut || `${id}-codex`, `${commandPrefix}-${id}`];
        for (const commandName of commandNames) {
          const commandError = validateCommandName(commandName);
          if (commandError) {
            sendJson(res, 400, { error: `${id}: ${commandError}：${commandName}` });
            return;
          }
          const key = commandName.toLowerCase();
          if (usedCommandNames.has(key)) {
            sendJson(res, 400, {
              error: `${id}: 快捷命令与 ${usedCommandNames.get(key)} 冲突：${commandName}`
            });
            return;
          }
          usedCommandNames.set(key, id);
        }
        next.profiles[id] = profile;
      }
      await writeConfig(next);
      sendJson(res, 200, next);
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/sync') {
      const result = await runPwshScript(syncScript);
      sendJson(res, 200, {
        ok: true,
        output: `${result.stdout}${result.stderr}`.trim()
      });
      return;
    }

    await serveStatic(req, res);
  } catch (error) {
    sendJson(res, 500, { error: error.message || String(error) });
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Codex Provider 配置管理： http://127.0.0.1:${port}/`);
  console.log(`配置文件：${configPath}`);
});
