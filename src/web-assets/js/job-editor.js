// Job editor — edit/preview toggle, bridge to Xojo
// Mirrors note-editor.js. "body" here is the prompt; "description" is a short hint shown in the sidebar.

(function() {
  // Inline sanitizer — job editor runs in its own WKWebView; keeping this
  // local avoids a separate-file load dependency.
  const _SANITIZE_TAGS = new Set([
    'p','br','strong','b','em','i','u','s','strike','del',
    'ul','ol','li','h1','h2','h3','h4','h5','h6',
    'code','pre','blockquote','a','span','div',
    'table','thead','tbody','tr','th','td',
    'hr','sub','sup','mark'
  ]);
  const _SANITIZE_ATTRS = {
    'a':    ['href', 'title'],
    'code': ['class'],
    'pre':  ['class'],
    'td':   ['colspan', 'rowspan'],
    'th':   ['colspan', 'rowspan', 'scope'],
  };
  function sanitizeHTML(html) {
    if (!html) return '';
    const doc = new DOMParser().parseFromString(html, 'text/html');
    (function clean(node) {
      Array.from(node.childNodes).forEach(child => {
        if (child.nodeType === Node.TEXT_NODE) return;
        if (child.nodeType !== Node.ELEMENT_NODE) { node.removeChild(child); return; }
        const tag = child.tagName.toLowerCase();
        if (!_SANITIZE_TAGS.has(tag)) {
          node.replaceChild(document.createTextNode(child.textContent), child);
          return;
        }
        const allowed = _SANITIZE_ATTRS[tag] || [];
        Array.from(child.attributes).forEach(a => {
          if (!allowed.includes(a.name)) child.removeAttribute(a.name);
        });
        if (tag === 'a') {
          const href = (child.getAttribute('href') || '').trim();
          if (/^javascript:/i.test(href)) child.removeAttribute('href');
        }
        clean(child);
      });
    })(doc.body);
    return doc.body.innerHTML;
  }

  const job = window.JOB_DATA || { id: 0, name: '', prompt: '', description: '', tags: '' };
  let mode = 'preview'; // 'edit' | 'preview' | 'split'
  let _dirty = false;

  function postToXojo(name, data) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
      window.webkit.messageHandlers[name].postMessage(data || {});
    }
  }

  window.setDirty = function(val) {
    var f = currentFields();
    postToXojo('setDirty', { dirty: val, name: f.name, prompt: f.prompt, description: f.description, tags: f.tags });
    _dirty = val;
  };
  function setDirty(val) { window.setDirty(val); }

  function currentFields() {
    var n = document.getElementById('nameInput');
    var p = document.getElementById('promptInput');
    var d = document.getElementById('descriptionInput');
    var g = document.getElementById('tagsInput');
    return {
      name:        n ? n.value.trim() : '',
      prompt:      p ? p.value : '',
      description: d ? d.value.trim() : '',
      tags:        g ? g.value.trim() : ''
    };
  }

  function buildUI() {
    const app = document.getElementById('app');
    app.innerHTML = `
      <div class="editor-toolbar">
        <input type="text" id="nameInput" value="${escHtml(job.name)}" placeholder="Job name" oninput="setDirty(true)">
        <span class="toolbar-sep"></span>
        <button class="toggle-btn" id="btnEdit" onclick="setMode('edit')">Edit</button>
        <button class="toggle-btn" id="btnSplit" onclick="setMode('split')">Split</button>
        <button class="toggle-btn active" id="btnPreview" onclick="setMode('preview')">Preview</button>
        <button class="btn-save" onclick="saveJob()">Save</button>
      </div>
      <div class="tags-row">
        <label>Description:</label>
        <input type="text" id="descriptionInput" value="${escHtml(job.description)}" placeholder="Short hint shown under the name" oninput="setDirty(true)">
      </div>
      <div class="tags-row">
        <label>Tags:</label>
        <input type="text" id="tagsInput" value="${escHtml(job.tags)}" placeholder="tag1, tag2" oninput="setDirty(true)">
      </div>
      <div class="panels">
        <div class="edit-panel full" id="editPanel">
          <textarea id="promptInput" placeholder="Prompt (Markdown supported)…" oninput="onPromptInput(); setDirty(true)">${escText(job.prompt)}</textarea>
        </div>
        <div class="preview-panel hidden" id="previewPanel"></div>
      </div>`;
    setMode(mode);
  }

  window.setMode = function(m) {
    mode = m;
    const editPanel    = document.getElementById('editPanel');
    const previewPanel = document.getElementById('previewPanel');
    document.getElementById('btnEdit').classList.toggle('active', m === 'edit');
    document.getElementById('btnSplit').classList.toggle('active', m === 'split');
    document.getElementById('btnPreview').classList.toggle('active', m === 'preview');

    if (m === 'edit') {
      editPanel.className    = 'edit-panel full';
      previewPanel.className = 'preview-panel hidden';
    } else if (m === 'preview') {
      editPanel.className    = 'edit-panel hidden';
      previewPanel.className = 'preview-panel full';
      renderPreview();
    } else { // split
      editPanel.className    = 'edit-panel';
      previewPanel.className = 'preview-panel';
      renderPreview();
    }
  };

  window.onPromptInput = function() {
    if (mode === 'split' || mode === 'preview') renderPreview();
  };

  function renderPreview() {
    const body = document.getElementById('promptInput').value;
    const panel = document.getElementById('previewPanel');
    const rendered = typeof marked !== 'undefined' ? marked.parse(body) : escHtml(body).replace(/\n/g, '<br>');
    panel.innerHTML = sanitizeHTML(rendered);
  }

  window.saveJob = function() {
    setDirty(false);
    postToXojo('saveJob', {
      name:        document.getElementById('nameInput').value.trim(),
      prompt:      document.getElementById('promptInput').value,
      description: document.getElementById('descriptionInput').value.trim(),
      tags:        document.getElementById('tagsInput').value.trim(),
    });
  };

  window.deleteJob = function() {
    if (confirm('Delete this job?')) postToXojo('deleteJob', {});
  };

  function escHtml(s) {
    return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  function escText(s) {
    return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', buildUI);
  } else {
    buildUI();
  }
})();
