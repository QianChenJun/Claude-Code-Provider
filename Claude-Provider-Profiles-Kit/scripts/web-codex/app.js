const profilesEl = document.querySelector('#profiles');
const template = document.querySelector('#profile-template');
const statusEl = document.querySelector('#status');
const addButton = document.querySelector('#add-profile');
const saveButton = document.querySelector('#save-config');
const saveSyncButton = document.querySelector('#save-sync-config');
const reloadButton = document.querySelector('#reload-config');
const expandAllButton = document.querySelector('#expand-all');
const collapseAllButton = document.querySelector('#collapse-all');

let currentConfig = { version: 1, profiles: {} };
const stringFieldKeys = [
  'displayName',
  'shortcut',
  'baseUrl',
  'apiKey',
  'apiKeyEnv',
  'apiKeyFile',
  'model',
  'modelReasoningEffort',
  'modelReasoningSummary',
  'modelVerbosity'
];
const numberFieldKeys = [
  'modelContextWindow',
  'requestMaxRetries',
  'streamMaxRetries',
  'streamIdleTimeoutMs'
];
const jsonFieldKeys = ['queryParams', 'httpHeaders', 'envHttpHeaders', 'extraEnv'];
const profileIdPattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}$/;
const reservedProfileIds = new Set(['list', 'ls', 'help', 'usage', 'sync', 'manager', 'manage']);
const reservedCommandNames = new Set([
  'cdp',
  'cdp-list',
  'cdp-sync',
  'cdp-manager',
  'provider-codex',
  'codex-profile-manager',
  'sync-codex-profiles'
]);

function setStatus(message, isError = false) {
  statusEl.textContent = message;
  statusEl.style.color = isError ? '#b62222' : '#766b5c';
}

function getField(card, name) {
  return card.querySelector(`[data-field="${name}"]`);
}

function getProfileIds() {
  return [...profilesEl.querySelectorAll('.profile-card')]
    .map((card) => getField(card, 'id').value.trim())
    .filter(Boolean);
}

function getUniqueProfileId(baseId) {
  const normalized = (baseId || 'profile').replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 32) || 'profile';
  const existing = new Set(getProfileIds());
  if (!existing.has(normalized)) {
    return normalized;
  }
  for (let index = 2; index < 1000; index++) {
    const id = `${normalized}_${index}`;
    if (!existing.has(id)) {
      return id;
    }
  }
  throw new Error('无法生成唯一配置 ID');
}

function setCollapsed(card, collapsed) {
  card.classList.toggle('collapsed', collapsed);
  card.querySelector('[data-action="toggle"]').setAttribute('aria-expanded', String(!collapsed));
}

function readJsonField(card, key, id) {
  const value = getField(card, key).value.trim();
  if (!value) {
    return null;
  }
  const parsed = JSON.parse(value);
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error(`${id}: ${key} 必须是 JSON 对象`);
  }
  return parsed;
}

function collectProfileFromCard(card) {
  const profile = {};
  const id = getField(card, 'id').value.trim() || '未命名配置';

  for (const key of stringFieldKeys) {
    const value = getField(card, key).value.trim();
    if (value) {
      profile[key] = value;
    }
  }

  for (const key of numberFieldKeys) {
    const value = getField(card, key).value.trim();
    if (value) {
      const number = Number(value);
      if (!Number.isFinite(number)) {
        throw new Error(`${id}: ${key} 必须是数字`);
      }
      profile[key] = number;
    }
  }

  const supportsWebsockets = getField(card, 'supportsWebsockets').value;
  if (supportsWebsockets === 'true') {
    profile.supportsWebsockets = true;
  } else if (supportsWebsockets === 'false') {
    profile.supportsWebsockets = false;
  }

  for (const key of jsonFieldKeys) {
    const parsed = readJsonField(card, key, id);
    if (parsed) {
      profile[key] = parsed;
    }
  }

  return profile;
}

function duplicateProfile(card) {
  const sourceId = getField(card, 'id').value.trim() || 'profile';
  const nextId = getUniqueProfileId(`${sourceId}_copy`);
  const profile = collectProfileFromCard(card);
  profile.displayName = profile.displayName ? `${profile.displayName} 副本` : `${nextId} 副本`;
  profile.shortcut = `${nextId}-codex`;
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
    `确认删除 ${displayName}？\n\n删除只会先从页面移除，点击“保存配置”或“保存并同步”后才写入。\n如果误删且还没保存，可以点击“重新加载”恢复。\n\n请输入配置 ID 确认：${expected}`
  );

  if (typed === null) {
    return;
  }
  if (typed.trim() !== expected) {
    setStatus('删除已取消：配置 ID 不匹配', true);
    return;
  }

  card.remove();
  setStatus(`已移除 ${expected}，保存后生效`);
}

function renderProfile(id, profile = {}, options = {}) {
  const node = template.content.firstElementChild.cloneNode(true);
  getField(node, 'id').value = id;

  for (const key of stringFieldKeys) {
    const field = getField(node, key);
    if (field) {
      field.value = profile[key] || '';
    }
  }

  for (const key of numberFieldKeys) {
    const field = getField(node, key);
    if (field) {
      field.value = profile[key] ?? '';
    }
  }

  getField(node, 'supportsWebsockets').value = profile.supportsWebsockets === true ? 'true' : profile.supportsWebsockets === false ? 'false' : '';

  for (const key of jsonFieldKeys) {
    const field = getField(node, key);
    if (field) {
      field.value = profile[key] ? JSON.stringify(profile[key], null, 2) : '';
    }
  }

  node.querySelector('[data-action="toggle"]').addEventListener('click', () => {
    setCollapsed(node, !node.classList.contains('collapsed'));
  });
  node.querySelector('[data-action="copy"]').addEventListener('click', () => {
    try {
      duplicateProfile(node);
    } catch (error) {
      setStatus(error.message, true);
    }
  });
  node.querySelector('[data-action="remove"]').addEventListener('click', () => removeProfile(node));
  node.addEventListener('input', () => updatePreview(node));
  updatePreview(node);
  setCollapsed(node, !options.expanded);
  profilesEl.appendChild(node);
}

function updatePreview(card) {
  const id = getField(card, 'id').value.trim() || '<id>';
  const shortcut = getField(card, 'shortcut').value.trim() || `${id}-codex`;
  const displayName = getField(card, 'displayName').value.trim() || id;
  const baseUrl = getField(card, 'baseUrl').value.trim() || '未填写接口地址';
  const model = getField(card, 'model').value.trim();

  card.querySelector('[data-summary-name]').textContent = displayName;
  card.querySelector('[data-summary-meta]').textContent = [
    `ID: ${id}`,
    `命令: cdp-${id}`,
    model ? `模型: ${model}` : '',
    baseUrl
  ].filter(Boolean).join(' / ');
  card.querySelector('[data-preview]').textContent = `推荐：cdp-${id}；通用：cdp ${id}；兼容命令：${shortcut}`;
}

function renderConfig(config) {
  profilesEl.innerHTML = '';
  currentConfig = config;
  for (const [id, profile] of Object.entries(config.profiles || {})) {
    renderProfile(id, profile);
  }
}

async function loadConfig() {
  const response = await fetch('/api/config', { cache: 'no-store' });
  if (!response.ok) {
    throw new Error(await response.text());
  }
  renderConfig(await response.json());
  setStatus('已加载');
}

function collectConfig() {
  const profiles = {};
  const usedCommandNames = new Map();
  for (const card of profilesEl.querySelectorAll('.profile-card')) {
    const id = getField(card, 'id').value.trim();
    if (!id) {
      throw new Error('配置 ID 不能为空');
    }
    if (!profileIdPattern.test(id)) {
      throw new Error(`配置 ID 不合法：${id}`);
    }
    if (reservedProfileIds.has(id.toLowerCase())) {
      throw new Error(`配置 ID 与内置菜单命令冲突：${id}`);
    }
    if (profiles[id]) {
      throw new Error(`配置 ID 重复：${id}`);
    }

    const profile = collectProfileFromCard(card);
    const commandNames = [profile.shortcut || `${id}-codex`, `cdp-${id}`];
    for (const commandName of commandNames) {
      if (!profileIdPattern.test(commandName)) {
        throw new Error(`${id}: 快捷命令不合法：${commandName}`);
      }
      const key = commandName.toLowerCase();
      if (reservedCommandNames.has(key)) {
        throw new Error(`${id}: 快捷命令与内置命令冲突：${commandName}`);
      }
      if (usedCommandNames.has(key)) {
        throw new Error(`${id}: 快捷命令与 ${usedCommandNames.get(key)} 冲突：${commandName}`);
      }
      usedCommandNames.set(key, id);
    }

    profiles[id] = profile;
  }
  return { version: 1, profiles };
}

async function saveConfig(message) {
  const config = collectConfig();
  const response = await fetch('/api/config', {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(config)
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || '保存失败');
  }
  renderConfig(payload);
  setStatus(message || `已保存 ${new Date().toLocaleTimeString()}`);
}

async function syncShortcuts() {
  const response = await fetch('/api/sync', { method: 'POST' });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || '同步失败');
  }
  return payload.output || '';
}

addButton.addEventListener('click', () => {
  const id = `new_${Date.now().toString().slice(-5)}`;
  renderProfile(id, {
    shortcut: `${id}-codex`
  }, { expanded: true });
  profilesEl.lastElementChild.scrollIntoView({ behavior: 'smooth', block: 'center' });
});

saveButton.addEventListener('click', async () => {
  try {
    await saveConfig();
  } catch (error) {
    setStatus(error.message, true);
  }
});

saveSyncButton.addEventListener('click', async () => {
  try {
    setStatus('正在保存并同步...');
    await saveConfig('已保存，正在同步快捷命令...');
    await syncShortcuts();
    setStatus(`已保存并同步 ${new Date().toLocaleTimeString()}`);
  } catch (error) {
    setStatus(error.message, true);
  }
});

reloadButton.addEventListener('click', async () => {
  try {
    await loadConfig();
  } catch (error) {
    setStatus(error.message, true);
  }
});

expandAllButton.addEventListener('click', () => {
  profilesEl.querySelectorAll('.profile-card').forEach((card) => setCollapsed(card, false));
});

collapseAllButton.addEventListener('click', () => {
  profilesEl.querySelectorAll('.profile-card').forEach((card) => setCollapsed(card, true));
});

loadConfig().catch((error) => setStatus(error.message, true));
