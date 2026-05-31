(function() {
  document.getElementById('app').innerHTML = `
<h1>XMCPStudio Help</h1>

<div class="section">
  <h2>Getting Started</h2>
  <p>XMCPStudio is an AI chat cockpit for Xojo development. It connects your AI backend directly to the running Xojo IDE — read and write code, build, run, and search docs without leaving the chat.</p>

  <h3>Requirements</h3>
  <ul>
    <li><strong>Xojo IDE</strong> — must be installed and running. XMCPStudio opens your project in the IDE on startup.</li>
    <li><strong>At least one AI backend</strong> — Claude Code CLI or Codex CLI (see below).</li>
    <li><strong>XMCP MCP server</strong> — provides the 22 Xojo IDE tools. Register it once in <code>~/.claude.json</code> (Claude) or <code>~/.codex/config.toml</code> (Codex).</li>
    <li><strong>MBS Xojo Plugin</strong> — required to build XMCPStudio from source.</li>
  </ul>
</div>

<div class="section">
  <h2>AI Backends</h2>

  <h3>Claude Code <span class="badge">Default</span></h3>
  <p>Install by running this in a terminal:</p>
  <pre><code>curl -fsSL https://claude.ai/install.sh | bash</code></pre>
  <p>Then sign in:</p>
  <pre><code>claude</code></pre>
  <p>XMCPStudio reuses your existing Claude Code login — no separate authentication needed.</p>
  <p>To get a live model list, add your Anthropic API key to the keychain:</p>
  <pre><code>security add-generic-password -s "Anthropic" -a "APIKey" -w "sk-ant-..."</code></pre>
  <p>Without a key, a built-in static list is used.</p>

  <h3>Codex (OpenAI)</h3>
  <p>Requires Codex CLI 0.131.0 or later. Install by running this in a terminal:</p>
  <pre><code>curl -fsSL https://chatgpt.com/codex/install.sh | sh</code></pre>
  <p>Then sign in by running this in a terminal:</p>
  <pre><code>codex</code></pre>
  <p>XMCPStudio reuses your existing Codex login. Models are fetched dynamically at startup. Models that work with a ChatGPT account: <code>gpt-5.4</code>, <code>gpt-5.5</code>.</p>
</div>

<div class="section">
  <h2>XMCP Setup</h2>
  <p>XMCP is a separate stdio MCP server that provides the 22 Xojo IDE tools (<code>get_code</code>, <code>set_code</code>, <code>build_project</code>, <code>revert_project</code>, <code>search_docs</code>, …). Build it from <a href="https://github.com/o3jvind/XMCP">github.com/o3jvind/XMCP</a> and register it once.</p>

  <h3>For Claude Code</h3>
  <p>Add to <code>~/.claude.json</code>:</p>
  <pre><code>{
  "mcpServers": {
    "xmcp": { "command": "/path/to/XMCP/XMCP" }
  }
}</code></pre>

  <h3>For Codex</h3>
  <p>Add to <code>~/.codex/config.toml</code>:</p>
  <pre><code>[[mcp_servers]]
name = "xmcp"
command = "/path/to/XMCP/XMCP"</code></pre>
</div>

<div class="section">
  <h2>Jobs</h2>
  <p>Jobs are saved prompt templates shown in the left sidebar. Click a job to insert its prompt into the input field. Drag to reorder.</p>
  <p>Create a new job with the <strong>+</strong> button at the top of the job list. Open any job with the pencil icon to edit its name, prompt, description, and tags in a full editor with edit, split, and preview modes.</p>
</div>

<div class="section">
  <h2>Notes</h2>
  <p>Notes are Markdown documents stored per project or globally. Use them for architecture decisions, TODOs, glossaries, or anything you want the AI to have context on.</p>
  <p>Create a new note with the <strong>+</strong> button at the top of the notes list. Choose <em>Global</em> scope to make a note available across all projects, or <em>Project</em> to keep it tied to the current project. Open any note with the pencil icon to write in edit, split, or preview mode.</p>
  <p>If you delete a project folder from disk, its notes move to an <em>Orphaned</em> group in the sidebar. Open an orphaned note and change its scope to <em>Global</em> or reassign it to another project.</p>
</div>

<div class="section">
  <h2>Keyboard Shortcuts</h2>
  <table>
    <tr><th>Shortcut</th><th>Action</th></tr>
    <tr><td><span class="kbd">⌘O</span></td><td>Open Project — switch to a different Xojo project</td></tr>
    <tr><td><span class="kbd">⌘E</span></td><td>Export Session as Markdown</td></tr>
    <tr><td><span class="kbd">⌘R</span></td><td>Revert project in IDE</td></tr>
    <tr><td><span class="kbd">⌘B</span></td><td>Build project</td></tr>
    <tr><td><span class="kbd">⌘D</span></td><td>Debug (run) project</td></tr>
    <tr><td><span class="kbd">⌘W</span></td><td>Close window</td></tr>
    <tr><td><span class="kbd">⌘?</span></td><td>Show this help</td></tr>
  </table>
</div>

<div class="section">
  <h2>Status Bar</h2>
  <table>
    <tr><th>Control</th><th>Description</th></tr>
    <tr><td>Backend picker</td><td>Switch between Claude Code and Codex</td></tr>
    <tr><td>Model picker</td><td>Select model — fetched live per backend</td></tr>
    <tr><td>Mode</td><td>Ask before edits / Edit automatically / Plan mode (Claude only)</td></tr>
    <tr><td>Approval</td><td>Ask / Allow all — in Ask mode, each file edit shows a permission card with an inline diff so you can see exactly what will change before approving (Claude only)</td></tr>
    <tr><td>Effort</td><td>Reasoning effort level — Low / Medium / High / X-High / Max (Claude); Low / Medium / High (Codex)</td></tr>
    <tr><td>● indicator</td><td>Green = Xojo IDE socket connected, red = not found</td></tr>
  </table>
</div>

<div class="section">
  <h2>Known Limitations</h2>
  <p>These are Xojo IDE scripting limits, not bugs in XMCPStudio:</p>
  <ul>
    <li><strong>Methods and events are not dot-path navigable.</strong> Use <code>get_code</code> / <code>set_code</code> against the current IDE selection, or edit <code>.xojo_code</code> / <code>.xojo_window</code> files directly and call <code>revert_project</code>.</li>
    <li><strong>The <code>App</code> class returns empty from <code>get_code</code></strong> even when navigated to. Read its source from disk instead.</li>
    <li><strong>Unhandled exceptions in debug runs are caught by the Xojo debugger</strong> and never reach any log. Add an <code>App.UnhandledException</code> handler and reproduce with a built binary to make crashes visible.</li>
  </ul>
</div>
`;
})();
