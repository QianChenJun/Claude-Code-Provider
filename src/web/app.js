const profilesEl = document.querySelector('#profiles');
const statusEl = document.querySelector('#status');
const titleEl = document.querySelector('#tool-title');
const summaryEl = document.querySelector('#tool-summary');
const configPathEl = document.querySelector('#config-path');
const tabsEl = document.querySelector('#tool-tabs');

const TOOL_META = {
  claude: {
    displayName: 'Claude Code',
    title: 'Claude Code 配置',
    summary: '保留原配置，只覆盖 Anthropic 兼容接口地址、API Key 和模型映射。',
    configHint: '%USERPROFILE%\\.claude\\provider-profiles\\providers.json',
    templateId: 'template-claude',
    prefix: 'ccp',
    suffix: 'claude',
    stringKeys: [
      'displayName', 'shortcut', 'baseUrl', 'authEnv', 'apiKey',
      'apiKeyEnv', 'apiKeyFile', 'model', 'haikuModel', 'sonnetModel',
      'opusModel', 'cliModel'
    ],
    numberKeys: [],
    booleanKeys: [],
    jsonKeys: ['extraEnv']
  },
  codex: {
    displayName: 'Codex CLI',
    title: 'Codex CLI 配置',
    summary: '保留原配置，只覆盖 OpenAI 兼容接口地址、API Key 和模型。通过 codex -c 临时注入。',
    configHint: '%USERPROFILE%\\.codex\\provider-profiles\\providers.json',
    templateId: 'template-codex',
    prefix: 'cdp',
    suffix: 'codex',
    stringKeys: [
      'displayName', 'shortcut', 'baseUrl', 'apiKey', 'apiKeyEnv',
      'apiKeyFile', 'model', 'modelReasoningEffort', 'modelReasoningSummary',
      'modelVerbosity'
    ],
    numberKeys: ['modelContextWindow', 'requestMaxRetries', 'streamMaxRetries', 'streamIdleTimeoutMs'],
    booleanKeys: ['supportsWebsockets'],
    jsonKeys: ['queryParams', 'httpHeaders', 'envHttpHeaders', 'extraEnv']
  }
};

let currentTool = 'claude';
let currentConfig = { version: 1, profiles: {} };
let isDirty = false;
function markDirty() { isDirty = true; }
function markClean() { isDirty = false; }
const profileIdPattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$/;
const reservedProfileIds = new Set(['list', 'ls', 'help', 'usage', 'sync', 'manager', 'manage', 'setup', 'add', 'configure']);
const reservedCommandNames = new Set([
  'ccp', 'ccp-list', 'ccp-setup', 'ccp-sync', 'ccp-manager',
  'cdp', 'cdp-list', 'cdp-setup', 'cdp-sync', 'cdp-manager'
]);

function setStatus(msg, isError = false) {
  statusEl.textContent = msg;
  statusEl.style.color = isError ? '#b62222' : '#766b5c';
}

function getField(card, name) {
  return card.querySelector(`[data-field="${name}"]`);
}

function getProfileIds() {
  return [...profilesEl.querySelectorAll('.profile-card')]
    .map(c => getField(c, 'id').value.trim()).filter(Boolean);
}

function getUniqueProfileId(base) {
  const norm = (base || 'profile').replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 32) || 'profile';
  const existing = new Set(getProfileIds());
  if (!existing.has(norm)) return norm;
  for (let i = 2; i < 1000; i++) {
    const id = `${norm}_${i}`;
    if (!existing.has(id)) return id;
  }
  throw new Error('无法生成唯一配置 ID');
}

function setCollapsed(card, collapsed) {
  card.classList.toggle('collapsed', collapsed);
  card.querySelector('[data-action="toggle"]').setAttribute('aria-expanded', String(!collapsed));
}

function readJsonField(card, key, id) {
  const value = getField(card, key).value.trim();
  if (!value) return null;
  const parsed = JSON.parse(value);
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error(`${id}: ${key} 必须是 JSON 对象`);
  }
  return parsed;
}

function collectProfileFromCard(card) {
  const meta = TOOL_META[currentTool];
  const profile = {};
  const id = getField(card, 'id').value.trim() || '未命名配置';

  for (const key of meta.stringKeys) {
    const field = getField(card, key);
    if (field && field.value.trim()) profile[key] = field.value.trim();
  }

  for (const key of meta.numberKeys) {
    const field = getField(card, key);
    if (field && field.value.trim()) {
      const num = Number(field.value.trim());
      if (!Number.isFinite(num)) throw new Error(`${id}: ${key} 必须是数字`);
      profile[key] = num;
    }
  }

  for (const key of meta.booleanKeys) {
    const field = getField(card, key);
    if (field && field.value === 'true') profile[key] = true;
    else if (field && field.value === 'false') profile[key] = false;
  }

  for (const key of meta.jsonKeys) {
    const field = getField(card, key);
    if (field) {
      const parsed = readJsonField(card, key, id);
      if (parsed) profile[key] = parsed;
    }
  }

  return profile;
}

function duplicateProfile(card) {
  const sourceId = getField(card, 'id').value.trim() || 'profile';
  const meta = TOOL_META[currentTool];
  const nextId = getUniqueProfileId(`${sourceId}_copy`);
  const profile = collectProfileFromCard(card);
  profile.displayName = profile.displayName ? `${profile.displayName} 副本` : `${nextId} 副本`;
  profile.shortcut = `${nextId}-${meta.suffix}`;
  renderProfile(nextId, profile, { expanded: true });
  const copied = profilesEl.lastElementChild;
  copied.scrollIntoView({ behavior: 'smooth', block: 'center' });
  getField(copied, 'id').focus();
  setStatus(`已复制为 ${nextId}，保存后生效`);
}

function removeProfile(card) {
  const id = getField(card, 'id').value.trim();
  const displayName = getField(card, 'displayName').value.trim() || id || '未命名配置';
  const expected = id || displayName;
  const typed = window.prompt(
    `确认删除 ${displayName}？删除后需点击"保存配置"才写入。\\n请输入配置 ID 确认：${expected}`
  );
  if (typed === null) return;
  if (typed.trim() !== expected) { setStatus('删除已取消：ID 不匹配', true); return; }
  card.remove();
  setStatus(`已移除 ${expected}，保存后生效`);
}

function renderProfile(id, profile = {}, options = {}) {
  const meta = TOOL_META[currentTool];
  const template = document.querySelector(`#${meta.templateId}`);
  const node = template.content.firstElementChild.cloneNode(true);

  getField(node, 'id').value = id;

  for (const key of meta.stringKeys) {
    const field = getField(node, key);
    if (!field) continue;
    if (key === 'shortcut' && !profile[key] && id) {
      field.value = `${id}-${meta.suffix}`;  // 默认推荐值，可被联动覆盖
    } else {
      field.value = profile[key] || '';
    }
  }

  for (const key of meta.numberKeys) {
    const field = getField(node, key);
    if (field) field.value = profile[key] ?? '';
  }

  for (const key of meta.booleanKeys) {
    const field = getField(node, key);
    if (field) field.value = profile[key] === true ? 'true' : profile[key] === false ? 'false' : '';
  }

  for (const key of meta.jsonKeys) {
    const field = getField(node, key);
    if (field) field.value = profile[key] ? JSON.stringify(profile[key], null, 2) : '';
  }

  // ID → shortcut 联动：编辑 ID 时自动填 `${id}-${suffix}`，除非用户已显式改过 shortcut
  const idField = getField(node, 'id');
  const shortcutField = getField(node, 'shortcut');
  // 初始已有显式 shortcut（且与默认值不同）→ 标记为已自定义，不再联动
  const initialShortcut = (profile.shortcut || '').trim();
  const defaultInitial = id ? `${id}-${meta.suffix}` : '';
  node.dataset.shortcutTouched = (initialShortcut && initialShortcut !== defaultInitial) ? '1' : '';
  shortcutField.addEventListener('input', () => {
    node.dataset.shortcutTouched = shortcutField.value.trim() ? '1' : '';
  });
  idField.addEventListener('input', () => {
    if (node.dataset.shortcutTouched) return;
    const newId = idField.value.trim();
    shortcutField.value = newId ? `${newId}-${meta.suffix}` : '';
  });

  node.querySelector('[data-action="toggle"]').addEventListener('click', () => {
    setCollapsed(node, !node.classList.contains('collapsed'));
  });
  node.querySelector('[data-action="copy"]').addEventListener('click', () => {
    try { duplicateProfile(node); } catch (e) { setStatus(e.message, true); }
  });
  node.querySelector('[data-action="remove"]').addEventListener('click', () => removeProfile(node));
  node.addEventListener('input', () => { markDirty(); updatePreview(node); });
  updatePreview(node);
  setCollapsed(node, !options.expanded);
  profilesEl.appendChild(node);
}

function updatePreview(card) {
  const meta = TOOL_META[currentTool];
  const id = getField(card, 'id').value.trim() || '<id>';
  const shortcut = getField(card, 'shortcut').value.trim() || `${id}-${meta.suffix}`;
  const displayName = getField(card, 'displayName').value.trim() || id;
  const baseUrl = getField(card, 'baseUrl').value.trim() || '未填写接口地址';
  const model = getField(card, 'model')?.value.trim() || '';

  card.querySelector('[data-summary-name]').textContent = displayName;
  card.querySelector('[data-summary-meta]').textContent = [
    `ID: ${id}`,
    `命令: ${meta.prefix}-${id}`,
    model ? `模型: ${model}` : '',
    baseUrl
  ].filter(Boolean).join(' / ');
  card.querySelector('[data-preview]').textContent =
    `推荐：${meta.prefix}-${id}；通用：${meta.prefix} ${id}；兼容：${shortcut}`;
}

function renderConfig(config) {
  profilesEl.innerHTML = '';
  currentConfig = config;
  for (const [id, profile] of Object.entries(config.profiles || {})) {
    renderProfile(id, profile);
  }
}

async function loadConfig() {
  const res = await fetch(`/api/${currentTool}/config`, { cache: 'no-store' });
  if (!res.ok) throw new Error(await res.text());
  renderConfig(await res.json());
  markClean();
  setStatus(`已加载 ${TOOL_META[currentTool].displayName} 配置`);
}

function collectConfig() {
  const meta = TOOL_META[currentTool];
  const profiles = {};
  const usedCmds = new Map();

  for (const card of profilesEl.querySelectorAll('.profile-card')) {
    const id = getField(card, 'id').value.trim();
    if (!id) throw new Error('配置 ID 不能为空');
    if (!profileIdPattern.test(id)) throw new Error(`配置 ID 不合法：${id}`);
    if (reservedProfileIds.has(id.toLowerCase())) throw new Error(`配置 ID 与内置命令冲突：${id}`);
    if (profiles[id]) throw new Error(`配置 ID 重复：${id}`);

    const profile = collectProfileFromCard(card);
    // 校验必填字段
    if (!profile.baseUrl) {
      throw new Error(`${id}: baseUrl（接口地址）不能为空`);
    }
    if (!/^https?:\/\/.+/.test(profile.baseUrl)) {
      throw new Error(`${id}: baseUrl 格式不合法，必须以 http:// 或 https:// 开头`);
    }

    const shortcut = profile.shortcut || `${id}-${meta.suffix}`;
    const cmdNames = [shortcut, `${meta.prefix}-${id}`, id];

    for (const name of cmdNames) {
      if (!profileIdPattern.test(name)) throw new Error(`${id}: 快捷命令不合法：${name}`);
      const key = name.toLowerCase();
      if (reservedCommandNames.has(key)) {
        throw new Error(`${id}: 快捷命令与内置命令冲突：${name}`);
      }
      if (usedCmds.has(key)) throw new Error(`${id}: 快捷命令与 ${usedCmds.get(key)} 冲突：${name}`);
      usedCmds.set(key, id);
    }
    profiles[id] = profile;
  }
  return { version: 1, profiles };
}

async function saveConfig(message) {
  const config = collectConfig();
  markClean();
  const res = await fetch(`/api/${currentTool}/config`, {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(config)
  });
  const payload = await res.json();
  if (!res.ok) throw new Error(payload.error || '保存失败');
  renderConfig(payload);
  const ts = new Date().toLocaleTimeString();
  // 后端保存成功时已自动同步快捷命令，syncOutput 为同步脚本输出（含 "同步失败：" 前缀代表失败）
  const sync = payload.syncOutput || '';
  const syncFailed = sync.startsWith('同步失败');
  const base = message || `已保存并同步 ${ts}`;
  setStatus(syncFailed ? `${base}（${sync}）` : base, syncFailed);
}

async function syncShortcuts() {
  const res = await fetch(`/api/${currentTool}/sync`, { method: 'POST' });
  const payload = await res.json();
  if (!res.ok) throw new Error(payload.error || '同步失败');
  return payload.output || '';
}

function switchTool(tool) {
  if (!TOOL_META[tool]) return;
  // 仅在真正切到"另一个"工具且有未保存改动时弹确认
  if (tool !== currentTool && isDirty) {
    const ok = confirm(`当前 ${TOOL_META[currentTool].displayName} 有未保存的改动，切换会丢弃。继续？`);
    if (!ok) return;
  }
  currentTool = tool;
  const meta = TOOL_META[tool];

  titleEl.textContent = meta.title;
  summaryEl.textContent = meta.summary;
  configPathEl.textContent = meta.configHint;

  tabsEl.querySelectorAll('.tab').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tool === tool);
  });

  const url = new URL(window.location);
  url.searchParams.set('tool', tool);
  history.replaceState(null, '', url);

  loadConfig().catch(e => setStatus(e.message, true));
}

// Event handlers
document.querySelector('#add-profile').addEventListener('click', () => {
  markDirty();
  const id = `new_${Date.now().toString().slice(-5)}`;
  // 不传 shortcut，让 ID→shortcut 联动接管（用户改 ID 时自动跟随）
  renderProfile(id, {}, { expanded: true });
  profilesEl.lastElementChild.scrollIntoView({ behavior: 'smooth', block: 'center' });
});

document.querySelector('#save-config').addEventListener('click', async (ev) => {
  const btn = ev.currentTarget;
  const originalText = btn.textContent;
  btn.disabled = true;
  btn.textContent = '保存并同步中…';
  setStatus('正在保存并同步快捷命令…');
  try {
    await saveConfig();
  } catch (e) {
    setStatus(e.message, true);
  } finally {
    btn.disabled = false;
    btn.textContent = originalText;
  }
});


document.querySelector('#reload-config').addEventListener('click', async () => {
  try { await loadConfig(); } catch (e) { setStatus(e.message, true); }
});

document.querySelector('#expand-all').addEventListener('click', () => {
  profilesEl.querySelectorAll('.profile-card').forEach(c => setCollapsed(c, false));
});

document.querySelector('#collapse-all').addEventListener('click', () => {
  profilesEl.querySelectorAll('.profile-card').forEach(c => setCollapsed(c, true));
});

tabsEl.addEventListener('click', e => {
  const tab = e.target.closest('.tab');
  if (tab && tab.dataset.tool) switchTool(tab.dataset.tool);
});

// Init: read tool from URL or default to claude
const initTool = new URL(window.location).searchParams.get('tool');
if (initTool && TOOL_META[initTool]) currentTool = initTool;
switchTool(currentTool);
