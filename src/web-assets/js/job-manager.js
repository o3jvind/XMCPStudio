// Job manager — CRUD, drag-to-reorder. Editing happens in JobEditorWindow (native).

let _jobsById = {};
let _allJobs = [];

// Floating dropdown portal — avoids clipping by scrollable sidebar
let _portalMenu = null;
let _portalJobId = null;

function _getOrCreatePortal() {
  if (!_portalMenu) {
    _portalMenu = document.createElement('div');
    _portalMenu.className = 'dropdown-menu job-portal-menu';
    document.body.appendChild(_portalMenu);
  }
  return _portalMenu;
}

function renderJobs(jobs) {
  _allJobs = jobs || [];
  const q = (document.getElementById('jobSearch')?.value || '').trim().toLowerCase();
  _renderJobsFiltered(q ? _filterJobsList(_allJobs, q) : _allJobs);
}

window.filterJobs = function(q) {
  const needle = (q || '').trim().toLowerCase();
  _renderJobsFiltered(needle ? _filterJobsList(_allJobs, needle) : _allJobs);
};

function _filterJobsList(jobs, needle) {
  return jobs.filter(j =>
    (j.name || '').toLowerCase().includes(needle) ||
    (j.description || '').toLowerCase().includes(needle) ||
    (j.tags || '').toLowerCase().includes(needle)
  );
}

function _renderJobsFiltered(jobs) {
  _jobsById = {};
  const list = document.getElementById('jobList');
  list.innerHTML = '';

  if (!jobs || jobs.length === 0) {
    const msg = _allJobs.length > 0 ? 'No matches' : 'No jobs yet';
    list.innerHTML = '<div style="padding:8px 12px;font-size:0.8rem;color:var(--text-muted);">' + msg + '</div>';
    return;
  }

  jobs.forEach(job => {
    _jobsById[job.id] = job;

    const el = document.createElement('div');
    el.className = 'job';
    el.dataset.id = job.id;
    el.draggable = true;

    const text = document.createElement('div');
    text.className = 'job-text';

    const nameSpan = document.createElement('span');
    nameSpan.className = 'job-name';
    nameSpan.textContent = job.name;
    text.appendChild(nameSpan);

    if (job.description) {
      const descSpan = document.createElement('span');
      descSpan.className = 'job-desc';
      descSpan.textContent = job.description;
      text.appendChild(descSpan);
    }

    text.addEventListener('click', () => selectJob(job.id));

    const menuBtn = document.createElement('button');
    menuBtn.className = 'job-menu-btn';
    menuBtn.textContent = '⋯';
    menuBtn.addEventListener('click', (e) => toggleJobMenu(e, job.id));

    el.appendChild(text);
    el.appendChild(menuBtn);

    el.addEventListener('dragstart', onDragStart);
    el.addEventListener('dragover',  onDragOver);
    el.addEventListener('dragleave', onDragLeave);
    el.addEventListener('drop',      onDrop);
    el.addEventListener('dragend',   onDragEnd);

    list.appendChild(el);
  });
}

// Register the document-level click listener exactly once. Previously this
// lived inside the render function, which appended a fresh listener on every
// refresh — a slow leak that grew with every UI update.
document.addEventListener('click', closeAllJobMenus);

function selectJob(id) {
  const job = _jobsById[id];
  if (!job) return;
  document.querySelectorAll('.job').forEach(j => j.classList.remove('active'));
  document.querySelector(`.job[data-id="${id}"]`)?.classList.add('active');
  closeAllJobMenus();

  const ta = document.getElementById('inputText');
  if (ta.value.trim() === '') {
    ta.value = job.prompt;
    resizeTextarea(ta);
    ta.focus();
    return;
  }
  // Existing text — ask XOJO to show a native dialog (Append / Overwrite / Cancel).
  postToXojo('insertJobPrompt', { prompt: job.prompt });
}

window.appendToInput = function(s) {
  const ta = document.getElementById('inputText');
  const sep = ta.value.endsWith('\n') ? '\n' : '\n\n';
  ta.value = ta.value + sep + s;
  resizeTextarea(ta);
  ta.focus();
  ta.selectionStart = ta.selectionEnd = ta.value.length;
};

window.overwriteInput = function(s) {
  const ta = document.getElementById('inputText');
  ta.value = s;
  resizeTextarea(ta);
  ta.focus();
};

function toggleJobMenu(e, id) {
  e.stopPropagation();

  if (_portalJobId === id && _portalMenu && _portalMenu.classList.contains('open')) {
    closeAllJobMenus();
    return;
  }

  closeAllJobMenus();

  const btn = e.currentTarget;
  const rect = btn.getBoundingClientRect();
  const menu = _getOrCreatePortal();

  menu.innerHTML = '';
  _portalJobId = id;

  const editBtn = document.createElement('button');
  editBtn.textContent = 'Edit';
  editBtn.addEventListener('click', (ev) => { ev.stopPropagation(); openJobEditor(id); });

  const copyBtn = document.createElement('button');
  copyBtn.textContent = 'Copy';
  copyBtn.addEventListener('click', (ev) => { ev.stopPropagation(); copyJob(id); });

  const deleteBtn = document.createElement('button');
  deleteBtn.className = 'danger';
  deleteBtn.textContent = 'Delete';
  deleteBtn.addEventListener('click', (ev) => { ev.stopPropagation(); deleteJob(id); });

  menu.appendChild(editBtn);
  menu.appendChild(copyBtn);
  menu.appendChild(deleteBtn);

  // Position: align right edge of menu with right edge of button, open upward if near bottom
  const menuHeight = 96; // approx 3 × 32px rows
  const spaceBelow = window.innerHeight - rect.bottom;
  const top = spaceBelow < menuHeight + 8 ? rect.top - menuHeight : rect.bottom + 2;
  const right = window.innerWidth - rect.right;

  menu.style.position = 'fixed';
  menu.style.top = top + 'px';
  menu.style.right = right + 'px';
  menu.style.left = 'auto';
  menu.classList.add('open');
}

function closeAllJobMenus() {
  if (_portalMenu) {
    _portalMenu.classList.remove('open');
  }
  _portalJobId = null;
}

// ── Editor entry points ───────────────────────────────────────────────────────

function openNewJobModal() {
  // Kept under the legacy name because the "+" button in index.html calls it.
  postToXojo('openJobEditor', { id: 0 });
}

function openJobEditor(id) {
  closeAllJobMenus();
  postToXojo('openJobEditor', { id });
}

function copyJob(id) {
  closeAllJobMenus();
  const job = _jobsById[id];
  if (!job) return;
  postToXojo('openJobEditor', {
    id: 0,
    name:        'Copy of ' + job.name,
    prompt:      job.prompt,
    description: job.description || '',
    tags:        job.tags || '',
  });
}

function deleteJob(id) {
  closeAllJobMenus();
  const job = _jobsById[id];
  const name = job ? job.name : 'this job';
  if (confirm('Delete "' + name + '"?')) postToXojo('deleteJob', { id });
}

// ── Drag-to-reorder ───────────────────────────────────────────────────────────

const { onDragStart, onDragOver, onDragLeave, onDrop, onDragEnd } =
  makeDragHandlers('reorderJob', '.job');
