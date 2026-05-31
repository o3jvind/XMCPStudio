// Note editor — edit/preview toggle, bridge to Xojo

(function() {
  // Inline sanitizer (note editor runs in its own WKWebView; keeping this
  // local avoids a separate-file load dependency).
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

  const note = window.NOTE_DATA || { id: 0, title: '', body: '', tags: '', description: '', scope: 'global' };
  let mode = 'preview'; // 'edit' | 'preview' | 'split'
  let _dirty = false;

  function postToXojo(name, data) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
      window.webkit.messageHandlers[name].postMessage(data || {});
    }
  }

  window.setDirty = function(val) {
    var f = currentFields();
    var s = document.getElementById('scopeSelect');
    postToXojo('setDirty', {
      dirty: val,
      title: f.title,
      body: f.body,
      tags: f.tags,
      description: f.description,
      scope: s ? s.value : 'global'
    });
    _dirty = val;
  };
  function setDirty(val) { window.setDirty(val); }

  function currentFields() {
    var t = document.getElementById('titleInput');
    var b = document.getElementById('bodyInput');
    var g = document.getElementById('tagsInput');
    var d = document.getElementById('descriptionInput');
    return {
      title:       t ? t.value.trim() : '',
      body:        b ? b.value : '',
      tags:        g ? g.value.trim() : '',
      description: d ? d.value.trim() : ''
    };
  }

  function buildUI() {
    const app = document.getElementById('app');
    app.innerHTML = `
      <div class="editor-toolbar">
        <input type="text" id="titleInput" value="${escHtml(note.title)}" placeholder="Title" oninput="setDirty(true)">
        <select id="scopeSelect" oninput="setDirty(true)">
          <option value="global"${note.scope==='global'?' selected':''}>Global</option>
          <option value="project"${note.scope==='project'?' selected':''}>Project</option>
          ${note.scope==='orphaned'?'<option value="orphaned" selected>Orphaned</option>':''}
        </select>
        <span class="toolbar-sep"></span>
        <button class="toggle-btn" id="btnEdit" onclick="setMode('edit')">Edit</button>
        <button class="toggle-btn" id="btnSplit" onclick="setMode('split')">Split</button>
        <button class="toggle-btn active" id="btnPreview" onclick="setMode('preview')">Preview</button>
        <button class="btn-save" onclick="saveNote()">Save</button>
      </div>
      <div class="tags-row">
        <label>Description:</label>
        <input type="text" id="descriptionInput" value="${escHtml(note.description)}" placeholder="Short hint shown under the title" oninput="setDirty(true)">
      </div>
      <div class="tags-row">
        <label>Tags:</label>
        <input type="text" id="tagsInput" value="${escHtml(note.tags)}" placeholder="tag1, tag2" oninput="setDirty(true)">
      </div>
      <div class="panels">
        <div class="edit-panel full" id="editPanel">
          <textarea id="bodyInput" placeholder="Write in Markdown…" oninput="onBodyInput(); setDirty(true)">${escText(note.body)}</textarea>
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

  window.onBodyInput = function() {
    if (mode === 'split' || mode === 'preview') renderPreview();
  };

  function renderPreview() {
    const body = document.getElementById('bodyInput').value;
    const panel = document.getElementById('previewPanel');
    const rendered = typeof marked !== 'undefined' ? marked.parse(body) : escHtml(body).replace(/\n/g, '<br>');
    panel.innerHTML = sanitizeHTML(rendered);
  }

  window.saveNote = function() {
    setDirty(false);
    postToXojo('saveNote', {
      title:       document.getElementById('titleInput').value.trim(),
      body:        document.getElementById('bodyInput').value,
      tags:        document.getElementById('tagsInput').value.trim(),
      description: document.getElementById('descriptionInput').value.trim(),
      scope:       document.getElementById('scopeSelect').value,
    });
  };

  window.deleteNote = function() {
    if (confirm('Delete this note?')) postToXojo('deleteNote', {});
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
