// Chat handler — diff rendering, plan/permission/ask-user UI.
// sanitizeHTML lives in sanitize.js, which must load before this file.

// ── Diff rendering ────────────────────────────────────────────────────────────

function renderDiff(requestId, filePath, oldContent, newContent) {
  const lines = computeDiffLines(oldContent, newContent);

  const container = document.createElement('div');
  container.className = 'diff-container';
  container.dataset.requestId = requestId;

  container.innerHTML = `
    <div class="diff-header">
      <span class="diff-filepath">${escapeHtml(filePath)}</span>
      <div class="diff-actions">
        <button class="btn btn-danger diff-reject">Reject</button>
        <button class="btn btn-primary diff-accept">Accept</button>
      </div>
    </div>
    <div class="diff-body">${lines}</div>`;

  container.querySelector('.diff-reject').addEventListener('click', () => rejectDiff(requestId));
  container.querySelector('.diff-accept').addEventListener('click', () => acceptDiff(requestId, filePath));

  document.getElementById('chatArea').appendChild(container);
  scrollChatToBottom();
}

function computeDiffLines(oldText, newText) {
  const oldLines = oldText.split('\n');
  const newLines = newText.split('\n');
  let html = '';

  // Simple line-by-line diff (LCS not needed for display purposes)
  let oi = 0, ni = 0;

  while (oi < oldLines.length || ni < newLines.length) {
    const ol = oldLines[oi];
    const nl = newLines[ni];
    if (oi >= oldLines.length) {
      html += `<div class="diff-line added">+ ${escapeHtml(nl)}</div>`;
      ni++;
    } else if (ni >= newLines.length) {
      html += `<div class="diff-line removed">- ${escapeHtml(ol)}</div>`;
      oi++;
    } else if (ol === nl) {
      html += `<div class="diff-line context">  ${escapeHtml(ol)}</div>`;
      oi++; ni++;
    } else {
      html += `<div class="diff-line removed">- ${escapeHtml(ol)}</div>`;
      html += `<div class="diff-line added">+ ${escapeHtml(nl)}</div>`;
      oi++; ni++;
    }
  }
  return html;
}

function acceptDiff(requestId, filePath) {
  document.querySelector(`[data-request-id="${requestId}"]`)?.remove();
  postToXojo('diffAccepted', { requestId, filePath });
}

function rejectDiff(requestId) {
  document.querySelector(`[data-request-id="${requestId}"]`)?.remove();
  postToXojo('diffRejected', { requestId });
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function showPlanApproval(planText) {
  hideThinkingIndicator();
  const el = document.createElement('div');
  el.className = 'permission-prompt plan-approval';
  const html = typeof marked !== 'undefined' ? marked.parse(planText) : escapeHtml(planText).replace(/\n/g, '<br>');
  el.innerHTML = `
    <div class="permission-icon">📋</div>
    <div class="permission-body">
      <div class="permission-title">Claude has a plan — approve to proceed?</div>
      <div class="plan-content">${sanitizeHTML(html)}</div>
      <div class="permission-actions">
        <button class="permission-btn allow">Approve — go ahead</button>
        <button class="permission-btn deny">Reject — revise the plan</button>
      </div>
    </div>`;
  el.querySelector('.allow').addEventListener('click', function() {
    el.querySelector('.permission-actions').remove();
    el.querySelector('.permission-title').textContent = '✓ Plan approved';
    postToXojo('approvePlan', {});
  });
  el.querySelector('.deny').addEventListener('click', function() {
    el.querySelector('.permission-actions').remove();
    el.querySelector('.permission-title').textContent = 'Plan rejected — tell Claude what to change';
    el.classList.add('denied');
    postToXojo('rejectPlan', {});
  });
  document.getElementById('chatArea').appendChild(el);
  scrollChatToBottom();
}

function showAskUserQuestion(questions) {
  hideThinkingIndicator();
  const el = document.createElement('div');
  el.className = 'permission-prompt ask-user-question';

  const hasMulti = questions.some(q => q.multiSelect);

  let bodyHTML = '<div class="permission-icon">❓</div><div class="permission-body">';
  questions.forEach((q, qi) => {
    bodyHTML += `<div class="permission-title">${escapeHtml(q.question)}</div>`;
    bodyHTML += `<div class="permission-actions auq-options" data-qi="${qi}" data-multi="${q.multiSelect ? '1' : '0'}">`;
    (q.options || []).forEach((opt, oi) => {
      bodyHTML += `<button class="permission-btn auq-opt" data-qi="${qi}" data-oi="${oi}" title="${escapeHtml(opt.description || '')}">${escapeHtml(opt.label)}</button>`;
    });
    bodyHTML += '</div>';
  });
  // If any question is multi-select, or there are multiple questions, require an
  // explicit Submit — auto-submit only makes sense for a single single-select.
  if (hasMulti || questions.length > 1) {
    bodyHTML += '<div class="permission-actions auq-submit-row"><button class="permission-btn auq-submit" disabled>Submit</button></div>';
  }
  bodyHTML += '</div>';
  el.innerHTML = bodyHTML;

  const answers = {};
  const selected = {};
  const submitBtn = el.querySelector('.auq-submit');

  function answeredCount() {
    let n = 0;
    questions.forEach((q, qi) => {
      if (q.multiSelect) {
        if (selected[qi] && selected[qi].size > 0) n++;
      } else {
        if (answers[q.question] !== undefined) n++;
      }
    });
    return n;
  }

  function refreshSubmitState() {
    if (!submitBtn) return;
    submitBtn.disabled = answeredCount() < questions.length;
  }

  function lockAndSubmit() {
    el.querySelectorAll('.auq-opt').forEach(b => { b.disabled = true; });
    if (submitBtn) submitBtn.disabled = true;
    postToXojo('askUserAnswer', { answersJSON: JSON.stringify(answers) });
  }

  el.querySelectorAll('.auq-opt').forEach(btn => {
    btn.addEventListener('click', function() {
      const qi = this.dataset.qi;
      const q = questions[qi];
      const label = q.options[this.dataset.oi].label;
      const actionsEl = el.querySelector(`.auq-options[data-qi="${qi}"]`);
      const isMulti = actionsEl.dataset.multi === '1';

      if (isMulti) {
        this.classList.toggle('selected');
        selected[qi] = selected[qi] || new Set();
        if (this.classList.contains('selected')) {
          selected[qi].add(label);
        } else {
          selected[qi].delete(label);
        }
        answers[q.question] = Array.from(selected[qi]).join(', ');
        if (selected[qi].size === 0) delete answers[q.question];
        refreshSubmitState();
      } else {
        actionsEl.querySelectorAll('.auq-opt').forEach(b => b.classList.remove('selected'));
        this.classList.add('selected');
        answers[q.question] = label;

        if (!hasMulti && questions.length === 1) {
          // Single single-select question: auto-submit after brief highlight.
          setTimeout(() => {
            actionsEl.innerHTML = `<span style="color:var(--text-muted);font-size:var(--font-size-sm)">${escapeHtml(label)}</span>`;
            postToXojo('askUserAnswer', { answersJSON: JSON.stringify(answers) });
          }, 200);
        } else {
          refreshSubmitState();
        }
      }
    });
  });

  if (submitBtn) {
    submitBtn.addEventListener('click', lockAndSubmit);
  }

  document.getElementById('chatArea').appendChild(el);
  scrollChatToBottom();
}

function showPermissionPrompt(path, detail, oldStr, newStr) {
  hideThinkingIndicator();
  const el = document.createElement('div');
  el.className = 'permission-prompt';
  const isCmd = !path && detail;
  const isMCP = path && (path.startsWith('mcp__') || path.startsWith('xmcp/'));
  const icon = isCmd ? '💻' : isMCP ? '🔧' : '🔐';
  const toolLabel = path.startsWith('xmcp/')
    ? path.slice(5).replace(/_/g, ' ')
    : path.replace(/^mcp__[^_]+__/, '').replace(/_/g, ' ');
  const title = isCmd
    ? 'Run this command?'
    : isMCP
      ? 'Use tool ' + escapeHtml(toolLabel) + '?'
      : 'Make this edit to ' + escapeHtml((path || '').split('/').pop()) + '?';
  const pathLine = (!isCmd && !isMCP && path)
    ? `<div class="permission-path">${escapeHtml(path)}</div>` : '';
  const detailLine = detail
    ? `<pre class="permission-cmd">${escapeHtml(detail)}</pre>` : '';
  let diffHtml = '';
  if (oldStr || newStr) {
    const oldLines = (oldStr || '').split('\n');
    const newLines = (newStr || '').split('\n');
    let lines = '';
    oldLines.forEach(l => { lines += `<div class="diff-line removed">- ${escapeHtml(l)}</div>`; });
    newLines.forEach(l => { lines += `<div class="diff-line added">+ ${escapeHtml(l)}</div>`; });
    diffHtml = `<div class="permission-diff diff-body">${lines}</div>`;
  }
  el.innerHTML = `
    <div class="permission-icon">${icon}</div>
    <div class="permission-body">
      <div class="permission-title">${title}</div>
      ${pathLine}${detailLine}${diffHtml}
      <div class="permission-actions">
        <button class="permission-btn allow">Yes</button>
        <button class="permission-btn always">Yes, allow all this session</button>
        <button class="permission-btn deny">No</button>
      </div>
    </div>`;
  el.querySelector('.allow').addEventListener('click', function() {
    postToXojo('grantPermission', { path: path, always: false });
    el.remove();
  });
  el.querySelector('.always').addEventListener('click', function() {
    postToXojo('grantPermission', { path: path, always: true });
    el.remove();
  });
  el.querySelector('.deny').addEventListener('click', function() {
    el.classList.add('denied');
    el.querySelector('.permission-actions').remove();
    postToXojo('denyPermission', {});
  });
  document.getElementById('chatArea').appendChild(el);
  scrollChatToBottom();
}
