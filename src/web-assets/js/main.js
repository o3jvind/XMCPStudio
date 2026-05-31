// XMCPStudio — core UI and Xojo bridge

// ── State ────────────────────────────────────────────────────────────────────

const AppState = {
  generating: false,
  currentSessionId: null,
  chatHistory: [],   // { role, content }[]
};

// Pending image attachment from drag-and-drop
// { name, base64, mediaType } or null
let _pendingImage = null;

// ── Bridge helpers ────────────────────────────────────────────────────────────

function postToXojo(name, data) {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
    window.webkit.messageHandlers[name].postMessage(data || {});
  } else {
    console.log('[bridge]', name, data);
  }
}

// ── Init ──────────────────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {
  postToXojo('ready', {});
});

// Open http(s) links in the default system browser instead of inside WKWebView
document.addEventListener('click', (e) => {
  const a = e.target.closest('a[href]');
  if (!a) return;
  const href = a.getAttribute('href');
  if (href && (href.startsWith('http://') || href.startsWith('https://'))) {
    e.preventDefault();
    postToXojo('openURL', href);
  }
});

// ── Chat ──────────────────────────────────────────────────────────────────────

function sendMessage() {
  const ta = document.getElementById('inputText');
  const text = ta.value.trim();
  if ((!text && !_pendingImage) || AppState.generating) return;

  ta.value = '';
  resizeTextarea(ta);

  if (_pendingImage) {
    const img = _pendingImage;
    clearImageAttachment();
    postToXojo('sendMessage', { text, imageBase64: img.base64, imageMediaType: img.mediaType, imageName: img.name });
  } else {
    postToXojo('sendMessage', { text });
  }
}

function insertImageAttachment(name, base64, mediaType) {
  _pendingImage = { name, base64, mediaType };
  var area = document.getElementById('imageAttachmentArea');
  if (!area) {
    area = document.createElement('div');
    area.id = 'imageAttachmentArea';
    area.className = 'image-attachment-area';
    var inputArea = document.getElementById('inputArea');
    inputArea.insertBefore(area, inputArea.firstChild);
  }
  area.innerHTML = '';
  var chip = document.createElement('div');
  chip.className = 'image-attachment-chip';
  var dataUrl = 'data:' + mediaType + ';base64,' + base64;
  chip.innerHTML = '<img class="image-attachment-thumb" src="' + dataUrl + '" alt="">'
    + '<span class="image-attachment-name">' + escapeHtml(name) + '</span>'
    + '<button class="image-attachment-remove" onclick="clearImageAttachment()" title="Remove">✕</button>';
  area.appendChild(chip);
}

function clearImageAttachment() {
  _pendingImage = null;
  var area = document.getElementById('imageAttachmentArea');
  if (area) area.remove();
}

function stopGeneration() {
  postToXojo('stopGeneration', {});
}

function clearChat() {
  document.getElementById('chatArea').innerHTML = '';
  AppState.chatHistory = [];
  postToXojo('clearChat', {});
}

function handleTextareaKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage();
  }
}

function handleTextareaInput(e) {
  resizeTextarea(e.target);
}

function resizeTextarea(ta) {
  ta.style.height = 'auto';
  ta.style.height = Math.min(ta.scrollHeight, 260) + 'px';
}

function newSession() {
  postToXojo('newSession', {});
}

// ── Xojo → JS API (called via EvaluateJavaScript) ────────────────────────────

let _thinkingEl = null;
let _progressEl = null;

function showSessionProgress() {
  clearChatUI();
  if (_progressEl) return;
  _progressEl = document.createElement('div');
  _progressEl.className = 'session-progress';
  _progressEl.innerHTML = '<div class="session-progress-label">Loading session…</div>'
    + '<div class="session-progress-track"><div class="session-progress-bar"></div></div>';
  document.getElementById('chatArea').appendChild(_progressEl);
}

function updateSessionProgress(pct) {
  if (!_progressEl) return;
  _progressEl.querySelector('.session-progress-bar').style.width = pct + '%';
}

function hideSessionProgress() {
  if (_progressEl) { _progressEl.remove(); _progressEl = null; }
}

function showThinkingIndicator(label) {
  if (_thinkingEl) return;
  _thinkingEl = document.createElement('div');
  _thinkingEl.className = 'thinking-indicator';
  _thinkingEl.innerHTML = '<div class="thinking-dot"></div><div class="thinking-dot"></div><div class="thinking-dot"></div>';
  if (label) {
    const lbl = document.createElement('span');
    lbl.className = 'thinking-label';
    lbl.textContent = label;
    _thinkingEl.appendChild(lbl);
  }
  document.getElementById('chatArea').appendChild(_thinkingEl);
  scrollChatToBottom();
}

function hideThinkingIndicator() {
  if (_thinkingEl) {
    _thinkingEl.remove();
    _thinkingEl = null;
  }
}

function showUserMessage(text, imageDataUrl) {
  const el = document.createElement('div');
  el.className = 'message user';
  el.textContent = text;
  if (imageDataUrl) {
    const img = document.createElement('img');
    img.className = 'user-image-preview';
    img.src = imageDataUrl;
    el.appendChild(img);
  }
  document.getElementById('chatArea').appendChild(el);
  scrollChatToBottom();
  AppState.generating = true;
  updateGeneratingUI(true);
  showThinkingIndicator();
}

let _streamingEl = null;
let _streamingRaw = '';
let _toolActivityEl = null;

function _removeToolActivity() {
  if (_toolActivityEl) { _toolActivityEl.remove(); _toolActivityEl = null; }
}

function showError(msg) {
  _streamingEl = null;
  _streamingRaw = '';
  const el = document.createElement('div');
  el.className = 'message assistant';
  el.innerHTML = sanitizeHTML(marked.parse(msg)) + buildMessageActions(msg);
  document.getElementById('chatArea').appendChild(el);
  tagIfCollapsible(el);
  AppState.generating = false;
  updateGeneratingUI(false);
  scrollChatToBottom();
}

function appendToken(token) {
  hideThinkingIndicator();
  _removeToolActivity();
  if (!_streamingEl) {
    _streamingEl = document.createElement('div');
    _streamingEl.className = 'message assistant';
    _streamingEl.innerHTML = '<span class="streaming-text"></span>';
    document.getElementById('chatArea').appendChild(_streamingEl);
  }
  _streamingRaw += token;
  _streamingEl.querySelector('.streaming-text').textContent = _streamingRaw;
  scrollChatToBottom();
}

function finalizeMessage() {
  hideThinkingIndicator();
  _removeToolActivity();
  if (_streamingEl) {
    const html = marked.parse(_streamingRaw);
    _streamingEl.innerHTML = sanitizeHTML(html) + buildMessageActions(_streamingRaw);
    const finalized = _streamingEl;
    _streamingEl = null;
    _streamingRaw = '';
    tagIfCollapsible(finalized);
  }
  AppState.generating = false;
  updateGeneratingUI(false);
  scrollChatToBottom();
}

// If the rendered bubble is tall enough to warrant a collapse toggle, tag it.
// CSS reveals the chevron when .bubble-collapsible is present on the .message;
// clicking the chevron toggles .bubble-collapsed to clamp the height. Called
// from both finalizeMessage (live stream) and loadSessionChat (history replay).
function tagIfCollapsible(bubble) {
  if (!bubble) return;
  if (bubble.scrollHeight > 200) bubble.classList.add('bubble-collapsible');
}

function clearChatUI() {
  document.getElementById('chatArea').innerHTML = '';
  _streamingEl = null;
  _streamingRaw = '';
  _toolActivityEl = null;
  _thinkingEl = null;
  _progressEl = null;
  AppState.generating = false;
  updateGeneratingUI(false);
}

function loadJobs(jsonStr) {
  renderJobs(typeof jsonStr === 'string' ? JSON.parse(jsonStr) : jsonStr);
}

function loadSessions(jsonStr) {
  renderSessions(typeof jsonStr === 'string' ? JSON.parse(jsonStr) : jsonStr);
}

function loadSessionChat(messages) {
  hideThinkingIndicator();
  hideSessionProgress();
  clearChatUI();
  if (!messages || messages.length === 0) return;
  const area = document.getElementById('chatArea');
  const CHUNK = 10;
  let idx = 0;
  function renderChunk() {
    const end = Math.min(idx + CHUNK, messages.length);
    for (; idx < end; idx++) {
      const m = messages[idx];
      const el = document.createElement('div');
      if (m.role === 'user') {
        el.className = 'message user';
        el.textContent = m.content;
      } else {
        el.className = 'message assistant';
        const html = typeof marked !== 'undefined' ? marked.parse(m.content) : escapeHtml(m.content).replace(/\n/g, '<br>');
        el.innerHTML = sanitizeHTML(html) + buildMessageActions(m.content);
      }
      area.appendChild(el);
      if (m.role !== 'user') tagIfCollapsible(el);
    }
    if (idx < messages.length) {
      setTimeout(renderChunk, 0);
    } else {
      scrollChatToBottom();
    }
  }
  renderChunk();
}

function loadNotes(jsonStr) {
  renderNotes(typeof jsonStr === 'string' ? JSON.parse(jsonStr) : jsonStr);
}

function showDiff(requestId, filePath, oldContent, newContent) {
  renderDiff(requestId, filePath, oldContent, newContent);
}

function showToolActivity(toolName, detail) {
  const icons = { openDiff: '✏️', openFile: '📄', getWorkspaceFolders: '📁', getCurrentSelection: '🖊' };
  const icon = icons[toolName] || '🔧';
  if (!_toolActivityEl) {
    _toolActivityEl = document.createElement('div');
    _toolActivityEl.className = 'tool-activity';
    const span = document.createElement('span');
    span.className = 'tool-activity-icon';
    _toolActivityEl.appendChild(span);
    const text = document.createElement('span');
    _toolActivityEl.appendChild(text);
    document.getElementById('chatArea').appendChild(_toolActivityEl);
  }
  _toolActivityEl.querySelector('.tool-activity-icon').textContent = icon;
  _toolActivityEl.querySelectorAll('span')[1].textContent = detail || toolName;
  scrollChatToBottom();
}

function setBackendStatus(name, connected, supportsTools) {
  const dot   = document.getElementById('backendDot');
  const badge = document.getElementById('backendBadge');

  dot.className = 'status-dot ' + (connected ? 'connected' : 'disconnected');

  badge.style.display = (supportsTools === false && name) ? 'inline' : 'none';
}

function loadBackends(backends, activeTitle) {
  const sel = document.getElementById('backendSelect');
  if (!sel) return;
  sel.innerHTML = '';
  backends.forEach(title => {
    const opt = document.createElement('option');
    opt.value = title;
    opt.textContent = title;
    if (title === activeTitle) opt.selected = true;
    sel.appendChild(opt);
  });
}

function loadModels(models, defaultModel) {
  const sel = document.getElementById('modelSelect');
  if (!sel) return;
  sel.innerHTML = '';
  models.forEach(m => {
    const opt = document.createElement('option');
    const value = (typeof m === 'object') ? m.value : m;
    const label = (typeof m === 'object') ? m.label : m;
    const disabled = (typeof m === 'object') && m.disabled === true;
    opt.value = value;
    opt.textContent = label;
    if (disabled) opt.disabled = true;
    if (value === defaultModel) opt.selected = true;
    sel.appendChild(opt);
  });
  sel.onchange = () => {
    clearChatUI();
    postToXojo('setModel', { model: sel.value });
  };
}

function setCapabilities(supportsPlanMode, supportsImageInput, supportsPermissionPrompts, supportsReasoningEffort) {
  const modeSelect = document.getElementById('modeSelect');
  if (modeSelect) modeSelect.style.display = supportsPlanMode ? '' : 'none';
  const approvalSelect = document.getElementById('approvalSelect');
  if (approvalSelect) {
    approvalSelect.style.display = (!supportsPlanMode && supportsPermissionPrompts) ? '' : 'none';
    if (!supportsPlanMode && supportsPermissionPrompts) approvalSelect.value = 'ask';
  }
  const effortSelect = document.getElementById('effortSelect');
  if (effortSelect) effortSelect.style.display = supportsReasoningEffort ? '' : 'none';
}

function setProjectInfo(name, branch) {
  const el = document.getElementById('projectInfo');
  if (!el) return;
  if (!name) { el.textContent = ''; return; }
  const showBranch = branch && branch !== '—';
  el.textContent = showBranch ? `${name} · ${branch}` : name;
}

function setXMCPStatus(connected) {
  // XOJO lamp removed — kept as no-op so existing Xojo call sites don't error
}

function setApprovalSelect(value) {
  const sel = document.getElementById('approvalSelect');
  if (sel) sel.value = value;
}


function loadEffortOptions(options) {
  const sel = document.getElementById('effortSelect');
  if (!sel) return;
  sel.innerHTML = '';
  (options || []).forEach(opt => {
    const o = document.createElement('option');
    o.value = opt.value;
    o.textContent = opt.label;
    if (opt.value === 'medium') o.selected = true;
    sel.appendChild(o);
  });
}

function loadBackendUI(config) {
  loadModels(config.models, config.defaultModel);
  setCapabilities(config.capabilities.supportsPlanMode, config.capabilities.supportsImageInput, config.capabilities.supportsPermissionPrompts, config.capabilities.supportsReasoningEffort);
  loadEffortOptions(config.effortOptions || []);
  loadSlashCommands(config.slashCommands);
  loadModeOptions(config.modeOptions);
  loadToolbarItems(config.toolbarItems || [], config.supportsXMCP || false);
  loadSessions(config.sessions);
}

function loadToolbarItems(items, supportsXMCP) {
  const container = document.getElementById('toolbarActions');
  if (!container) return;
  container.innerHTML = '';
  if (!supportsXMCP || !Array.isArray(items) || items.length === 0) return;
  items.forEach(item => {
    const btn = document.createElement('button');
    btn.className = 'toolbar-text-btn toolbar-icon xmcp-action-btn';
    btn.id = 'xmcpBtn_' + item.id;
    btn.textContent = item.label;
    btn.onclick = () => xmcpAction(item.message);
    container.appendChild(btn);
  });
}

function loadSlashCommands(commands) {
  _slashCommands = Array.isArray(commands) ? commands : [];
  const btn = document.getElementById('slashMenuBtn');
  if (btn) btn.style.display = _slashCommands.length > 0 ? '' : 'none';
}

function loadModeOptions(options) {
  const sel = document.getElementById('modeSelect');
  if (!sel) return;
  const current = sel.value;
  sel.innerHTML = '';
  (options || []).forEach(({ value, label }) => {
    const opt = document.createElement('option');
    opt.value = value;
    opt.textContent = label;
    if (value === current) opt.selected = true;
    sel.appendChild(opt);
  });
}

function xmcpAction(tool) {
  const modeSel = document.getElementById('modeSelect');
  const modeVisible = modeSel && modeSel.style.display !== 'none';
  const mode = (modeVisible && modeSel.value) ? modeSel.value : 'auto';
  postToXojo('xmcpAction', { message: tool, mode: mode });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function scrollChatToBottom() {
  const ca = document.getElementById('chatArea');
  ca.scrollTop = ca.scrollHeight;
}

function updateGeneratingUI(generating) {
  document.getElementById('sendBtn').disabled = generating;
  const stopBtn = document.getElementById('stopBtn');
  stopBtn.style.display = generating ? 'flex' : 'none';
  if (generating) stopBtn.classList.add('generating');
  else stopBtn.classList.remove('generating');
}

function buildMessageActions(rawText) {
  const id = 'msg-' + Math.random().toString(36).slice(2);
  _messageTexts[id] = rawText;
  // The collapse button is only visible when .bubble-collapsible is on the .message
  // ancestor (added by finalizeMessage when scrollHeight crosses the threshold).
  // CSS hides .bubble-collapse-btn by default.
  return `<div class="message-actions">
    <button class="bubble-collapse-btn" onclick="toggleBubbleCollapse(this)" title="Collapse">⌃</button>
    <button class="copy-button" onclick="copyMessage(this, '${id}')" title="Copy">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <rect x="9" y="9" width="13" height="13" rx="2"/>
        <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
      </svg>
    </button>
  </div>`;
}

function toggleBubbleCollapse(btn) {
  const bubble = btn.closest('.message');
  if (!bubble) return;
  const nowCollapsed = bubble.classList.toggle('bubble-collapsed');
  btn.textContent = nowCollapsed ? '⌄' : '⌃';
  btn.title = nowCollapsed ? 'Expand' : 'Collapse';
}

const _messageTexts = {};

const _copyIcon = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>`;
const _checkIcon = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`;

function copyMessage(btn, id) {
  const text = _messageTexts[id] || '';
  const done = () => {
    btn.classList.add('copied');
    btn.innerHTML = _checkIcon;
    setTimeout(() => {
      btn.classList.remove('copied');
      btn.innerHTML = _copyIcon;
    }, 1500);
  };

  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(done).catch(() => fallbackCopy(text, done));
  } else {
    fallbackCopy(text, done);
  }
}

function fallbackCopy(text, done) {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.focus();
  ta.select();
  try { document.execCommand('copy'); done(); } catch (_) {}
  document.body.removeChild(ta);
}

function showToast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 2500);
}

let _slashCommands = [
  { cmd: '/compact', desc: 'Compact conversation history' },
  { cmd: '/clear',   desc: 'Clear conversation history' },
  { cmd: '/review',  desc: 'Review code' },
  { cmd: '/memory',  desc: 'Edit memory files' },
  { cmd: '/init',    desc: 'Initialize project with CLAUDE.md' },
  { cmd: '/config',  desc: 'View/edit configuration' },
  { cmd: '/cost',    desc: 'Show token usage and cost' },
  { cmd: '/status',  desc: 'Show account and model info' },
];

let _slashPortal = null;

function toggleSlashMenu(e) {
  e.stopPropagation();
  if (_slashPortal && _slashPortal.classList.contains('open')) {
    _closeSlashMenu();
    return;
  }
  if (!_slashPortal) {
    _slashPortal = document.createElement('div');
    _slashPortal.className = 'slash-menu';
    document.body.appendChild(_slashPortal);
  }
  _slashPortal.innerHTML = '';
  _slashCommands.forEach(({ cmd, desc }) => {
    const row = document.createElement('button');
    row.className = 'slash-menu-item';
    row.innerHTML = `<span class="slash-cmd">${cmd}</span><span class="slash-desc">${desc}</span>`;
    row.addEventListener('click', (ev) => { ev.stopPropagation(); _selectSlashCommand(cmd); });
    _slashPortal.appendChild(row);
  });
  const btn = document.getElementById('slashMenuBtn');
  const rect = btn.getBoundingClientRect();
  _slashPortal.style.position = 'fixed';
  _slashPortal.style.bottom = (window.innerHeight - rect.top + 4) + 'px';
  _slashPortal.style.left = rect.left + 'px';
  _slashPortal.style.right = 'auto';
  _slashPortal.classList.add('open');
  setTimeout(() => document.addEventListener('click', _closeSlashMenu, { once: true }), 0);
}

function _closeSlashMenu() {
  if (_slashPortal) _slashPortal.classList.remove('open');
}

function _selectSlashCommand(cmd) {
  _closeSlashMenu();
  const ta = document.getElementById('inputText');
  ta.value = cmd;
  resizeTextarea(ta);
  ta.focus();
  ta.selectionStart = ta.selectionEnd = ta.value.length;
}

function pickFile() {
  postToXojo('pickFile', {});
}

// Theme: "system" removes data-theme so prefers-color-scheme kicks in;
// "dark"/"light" set it explicitly. Called from the status-bar select and
// from XOJO at startup (via setTheme(value)) so the persisted choice wins
// over the System default.
function applyTheme(value) {
  var v = value || 'system';
  var root = document.documentElement;
  if (v === 'dark' || v === 'light') {
    root.setAttribute('data-theme', v);
  } else {
    root.removeAttribute('data-theme');
  }
  var sel = document.getElementById('themeSelect');
  if (sel && sel.value !== v) sel.value = v;
}

function setTheme(value) { applyTheme(value); }

function insertText(text) {
  const ta = document.getElementById('inputText');
  const pos = ta.selectionStart;
  ta.value = ta.value.slice(0, pos) + text + ta.value.slice(pos);
  ta.selectionStart = ta.selectionEnd = pos + text.length;
  ta.focus();
  resizeTextarea(ta);
}

// ── Drag-to-reorder (shared) ──────────────────────────────────────────────────
// Returns { onDragStart, onDragOver, onDragLeave, onDrop, onDragEnd } bound to
// a specific xojoMessage and cleanup itemSelector.
function makeDragHandlers(xojoMessage, itemSelector) {
  let srcId = null;
  return {
    onDragStart(e) {
      srcId = this.dataset.id;
      this.classList.add('dragging');
      e.dataTransfer.effectAllowed = 'move';
    },
    onDragOver(e) {
      e.preventDefault();
      e.dataTransfer.dropEffect = 'move';
      this.classList.add('drop-above');
    },
    onDragLeave() {
      this.classList.remove('drop-above', 'drop-below');
    },
    onDrop(e) {
      e.stopPropagation();
      if (srcId === this.dataset.id) return;
      postToXojo(xojoMessage, { fromId: parseInt(srcId), toId: parseInt(this.dataset.id) });
      this.classList.remove('drop-above', 'drop-below');
    },
    onDragEnd() {
      this.classList.remove('dragging');
      document.querySelectorAll(itemSelector).forEach(el => el.classList.remove('drop-above', 'drop-below'));
      srcId = null;
    }
  };
}
