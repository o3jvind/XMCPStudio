// Shared HTML sanitizer for markdown-rendered content. Used by both the chat
// view (chat-handler.js, main.js) and the note/job editors. Must be loaded
// before any consumer.

function sanitizeHTML(html) {
  if (!html) return '';

  const allowedTags = new Set([
    'p','br','strong','b','em','i','u','s','strike','del',
    'ul','ol','li','h1','h2','h3','h4','h5','h6',
    'code','pre','blockquote','a','span','div',
    'table','thead','tbody','tr','th','td',
    'hr','sub','sup','mark'
  ]);

  const allowedAttrs = {
    'a':    ['href', 'title'],
    'code': ['class'],
    'pre':  ['class'],
    'td':   ['colspan', 'rowspan'],
    'th':   ['colspan', 'rowspan', 'scope'],
  };

  const parser = new DOMParser();
  const doc = parser.parseFromString(html, 'text/html');

  function cleanNode(node) {
    const children = Array.from(node.childNodes);
    for (const child of children) {
      if (child.nodeType === Node.TEXT_NODE) continue;
      if (child.nodeType === Node.ELEMENT_NODE) {
        const tag = child.tagName.toLowerCase();
        if (!allowedTags.has(tag)) {
          const text = document.createTextNode(child.textContent);
          node.replaceChild(text, child);
          continue;
        }
        const allowed = allowedAttrs[tag] || [];
        const toRemove = [];
        for (const attr of child.attributes) {
          if (!allowed.includes(attr.name)) toRemove.push(attr.name);
        }
        toRemove.forEach(a => child.removeAttribute(a));
        if (tag === 'a') {
          const href = child.getAttribute('href') || '';
          if (/^javascript:/i.test(href.trim())) child.removeAttribute('href');
        }
        cleanNode(child);
      } else {
        node.removeChild(child);
      }
    }
  }

  cleanNode(doc.body);
  return doc.body.innerHTML;
}
