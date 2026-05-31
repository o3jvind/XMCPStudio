// Notes manager — CRUD, scope grouping, portal menu

let _editingNoteId = null;
let _notesById = {};

let _notePortalMenu = null;
let _notePortalId = null;

function _getOrCreateNotePortal() {
  if (!_notePortalMenu) {
    _notePortalMenu = document.createElement('div');
    _notePortalMenu.className = 'dropdown-menu job-portal-menu';
    document.body.appendChild(_notePortalMenu);
  }
  return _notePortalMenu;
}

function closeAllNoteMenus() {
  if (_notePortalMenu) _notePortalMenu.classList.remove('open');
  _notePortalId = null;
}

function toggleNoteMenu(e, note) {
  e.stopPropagation();
  if (_notePortalId === note.id && _notePortalMenu && _notePortalMenu.classList.contains('open')) {
    closeAllNoteMenus();
    return;
  }
  closeAllNoteMenus();

  const btn = e.currentTarget;
  const rect = btn.getBoundingClientRect();
  const menu = _getOrCreateNotePortal();
  menu.innerHTML = '';
  _notePortalId = note.id;

  const editBtn = document.createElement('button');
  editBtn.textContent = 'Edit';
  editBtn.addEventListener('click', (ev) => { ev.stopPropagation(); closeAllNoteMenus(); openNote(note); });

  const copyBtn = document.createElement('button');
  copyBtn.textContent = 'Copy';
  copyBtn.addEventListener('click', (ev) => {
    ev.stopPropagation();
    closeAllNoteMenus();
    postToXojo('openNote', {
      id: 0,
      title: 'Copy of ' + note.title,
      body: note.body,
      tags: note.tags,
      description: note.description || '',
      scope: note.scope || 'global',
    });
  });

  const deleteBtn = document.createElement('button');
  deleteBtn.className = 'danger';
  deleteBtn.textContent = 'Delete';
  deleteBtn.addEventListener('click', (ev) => {
    ev.stopPropagation();
    closeAllNoteMenus();
    if (confirm('Delete "' + note.title + '"?')) postToXojo('deleteNote', { id: note.id });
  });

  menu.appendChild(editBtn);
  menu.appendChild(copyBtn);
  menu.appendChild(deleteBtn);

  const menuHeight = 96;
  const spaceBelow = window.innerHeight - rect.bottom;
  const top = spaceBelow < menuHeight + 8 ? rect.top - menuHeight : rect.bottom + 2;
  const right = window.innerWidth - rect.right;
  menu.style.position = 'fixed';
  menu.style.top = top + 'px';
  menu.style.right = right + 'px';
  menu.style.left = 'auto';
  menu.classList.add('open');
}

function openNote(note) {
  postToXojo('openNote', {
    id: note.id,
    title: note.title,
    body: note.body,
    tags: note.tags,
    description: note.description || '',
    scope: note.scope || 'global',
  });
}

let _allNotes = [];

function renderNotes(notes) {
  _allNotes = notes || [];
  const q = (document.getElementById('noteSearch')?.value || '').trim().toLowerCase();
  _renderNotesFiltered(q ? _filterNotesList(_allNotes, q) : _allNotes);
}

window.filterNotes = function(q) {
  const needle = (q || '').trim().toLowerCase();
  _renderNotesFiltered(needle ? _filterNotesList(_allNotes, needle) : _allNotes);
};

function _filterNotesList(notes, needle) {
  return notes.filter(n =>
    (n.title || '').toLowerCase().includes(needle) ||
    (n.description || '').toLowerCase().includes(needle) ||
    (n.tags || '').toLowerCase().includes(needle)
  );
}

function _renderNotesFiltered(notes) {
  _notesById = {};
  const list = document.getElementById('notesList');
  list.innerHTML = '';
  if (!notes || notes.length === 0) {
    const msg = _allNotes.length > 0 ? 'No matches' : 'No notes yet';
    list.innerHTML = '<div style="padding:8px 12px;font-size:0.8rem;color:var(--text-muted);">' + msg + '</div>';
    return;
  }

  const byScope = { global: [], project: [], orphaned: [] };
  notes.forEach(n => { _notesById[n.id] = n; (byScope[n.scope] || byScope.global).push(n); });

  const scopeLabels = { global: 'Global', project: 'Project', orphaned: 'Orphaned' };

  Object.entries(byScope).forEach(([scope, items]) => {
    if (items.length === 0) return;

    const header = document.createElement('div');
    header.className = 'scope-header';
    header.innerHTML = `<span class="chevron">▾</span> ${scopeLabels[scope]}`;
    header.addEventListener('click', () => {
      header.classList.toggle('collapsed');
      group.style.display = header.classList.contains('collapsed') ? 'none' : '';
    });
    list.appendChild(header);

    const group = document.createElement('div');
    items.forEach(note => {
      const el = document.createElement('div');
      el.className = 'note-item';
      el.dataset.id = note.id;

      const tagsHtml = note.tags
        ? note.tags.split(',').map(t => t.trim()).filter(Boolean)
            .map(t => `<span class="note-tag">${escapeHtml(t)}</span>`).join('')
        : '';

      const titleRow = document.createElement('div');
      titleRow.className = 'note-title-row';

      const nameSpan = document.createElement('span');
      nameSpan.className = 'note-title';
      nameSpan.textContent = note.title;

      const menuBtn = document.createElement('button');
      menuBtn.className = 'job-menu-btn';
      menuBtn.textContent = '⋯';
      menuBtn.addEventListener('click', (e) => { e.stopPropagation(); toggleNoteMenu(e, note); });

      titleRow.appendChild(nameSpan);
      titleRow.appendChild(menuBtn);
      el.appendChild(titleRow);

      if (note.description) {
        const descDiv = document.createElement('div');
        descDiv.className = 'note-desc';
        descDiv.textContent = note.description;
        el.appendChild(descDiv);
      }

      if (tagsHtml) {
        const tagsDiv = document.createElement('div');
        tagsDiv.className = 'note-tags';
        tagsDiv.innerHTML = tagsHtml;
        el.appendChild(tagsDiv);
      }

      el.addEventListener('click', () => openNote(note));

      el.draggable = true;
      el.addEventListener('dragstart', onNoteDragStart);
      el.addEventListener('dragover',  onNoteDragOver);
      el.addEventListener('dragleave', onNoteDragLeave);
      el.addEventListener('drop',      onNoteDrop);
      el.addEventListener('dragend',   onNoteDragEnd);

      group.appendChild(el);
    });
    list.appendChild(group);
  });
}

// Register once at load — see job-manager.js for the same pattern.
document.addEventListener('click', closeAllNoteMenus);

function renderSessions(sessions) {
  const list = document.getElementById('sessionList');
  list.innerHTML = '';
  if (!sessions || sessions.length === 0) {
    list.innerHTML = '<div style="padding:8px 12px;font-size:0.8rem;color:var(--text-muted);">No sessions yet</div>';
    return;
  }
  sessions.forEach(s => {
    const el = document.createElement('div');
    el.className = 'session-item';
    el.dataset.uuid = s.uuid;
    el.title = s.title;
    el.innerHTML = `<div class="session-title">${escapeHtml(s.title)}</div>`
      + (s.date ? `<div class="session-date">${escapeHtml(s.date)}</div>` : '');
    el.addEventListener('click', () => {
      document.querySelectorAll('.session-item').forEach(i => i.classList.remove('active'));
      el.classList.add('active');
      showSessionProgress();
      postToXojo('selectSession', { uuid: s.uuid });
    });
    list.appendChild(el);
  });
}

// ── Drag-to-reorder ───────────────────────────────────────────────────────────

const {
  onDragStart: onNoteDragStart,
  onDragOver:  onNoteDragOver,
  onDragLeave: onNoteDragLeave,
  onDrop:      onNoteDrop,
  onDragEnd:   onNoteDragEnd
} = makeDragHandlers('reorderNote', '.note-item');
