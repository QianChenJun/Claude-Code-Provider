import http from 'node:http';
import { spawn } from 'node:child_process';
import { readFile, writeFile, stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.join(root, 'web');

// Tool registry: each tool maps to its config path and sync script
const TOOLS = {
  claude: {
    configPath: path.join(root, 'providers.json'),
    syncScript: path.join(root, 'src', 'tools', 'claude', 'Sync-ClaudeShortcuts.ps1'),
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
    configPath: path.join(root, 'providers.json'),
    syncScript: path.join(root, 'src', 'tools', 'codex', 'Sync-CodexShortcuts.ps1'),
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

const args = process.argv.slice(2);
const portIndex = args.indexOf('--port');
const port = portIndex >= 0 ? Number(args[portIndex + 1]) : 15722;

const profileIdPattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$/;
const reservedProfileIds = new Set(['list', 'ls', 'help', 'usage', 'sync', 'manager', 'manage']);
const reservedCommandNames = new Set([
  'ccp', 'ccp-list', 'ccp-sync', 'ccp-manager',
  'cdp', 'cdp-list', 'cdp-sync', 'cdp-manager',
  'mi-claude', 'ds-claude', 'provider-claude', 'claude-profile-manager', 'sync-claude-profiles',
  'mi-codex', 'ds-codex', 'provider-codex', 'codex-profile-manager', 'sync-codex-profiles'
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
  const text = await readFile(tool.configPath, 'utf8');
  return JSON.parse(text);
}

async function writeConfig(tool, config) {
  await writeFile(tool.configPath, `${JSON.stringify(config, null, 2)}\n`, 'utf8');
}

function runPwshScript(scriptPath) {
  return new Promise((resolve, reject) => {
    const child = spawn('pwsh', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath], {
      cwd: root,
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

function validateCommandName(name) {
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
      sendJson(res, 200, { ok: true, root, tools: Object.keys(TOOLS) });
      return;
    }

    // Tool list
    if (req.method === 'GET' && url.pathname === '/api/tools') {
      const list = {};
      for (const [name, tool] of Object.entries(TOOLS)) {
        list[name] = { displayName: tool.displayName, fields: tool.fields };
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
          const cmdNames = [profile.shortcut || `${id}-${suffix}`, `${prefix}-${id}`];

          for (const cmd of cmdNames) {
            const cmdErr = validateCommandName(cmd);
            if (cmdErr) { sendJson(res, 400, { error: `${id}: ${cmdErr}：${cmd}` }); return; }
            const key = cmd.toLowerCase();
            if (usedCommands.has(key)) {
              sendJson(res, 400, { error: `${id}: 快捷命令与 ${usedCommands.get(key)} 冲突：${cmd}` });
              return;
            }
            usedCommands.set(key, id);
          }
          next.profiles[id] = profile;
        }

        await writeConfig(tool, next);
        sendJson(res, 200, next);
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
  console.log(`Provider Profiles 管理台： http://127.0.0.1:${port}/`);
  console.log(`已注册工具：${Object.keys(TOOLS).join(', ')}`);
  console.log(`配置文件：${TOOLS.claude.configPath}`);
});