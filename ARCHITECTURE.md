# XMCPStudio — Architecture

XMCPStudio is a macOS desktop app (XOJO) that provides a chat interface for AI-assisted XOJO development.

**The app is a thin client** — it sits between three layers it does not own:

- **UI** — HTML/CSS/JS running inside a `WKWebView`. All rendering, Markdown, streaming, diffs, and sidebar management live here.
- **AI backends** — external CLI processes (`claude`, `codex app-server`) communicating over stdin/stdout. XMCPStudio launches them, pipes messages, and relays tokens back to the UI.
- **SQLite** — jobs, notes, and settings. Chat history is owned by the backends (`~/.claude/`, `~/.codex/`), not by XMCPStudio.

XOJO code is the glue: it manages the subprocess lifecycle, the WebView bridge, the WebSocket IDE channel, and the SQLite connection. It contains no rendering logic and no AI logic.

The XOJO IDE tooling (`get_code`, `set_code`, `revert_project`, etc.) is provided by a **separate** stdio MCP server, **XMCP**, that the active AI backend spawns — XMCPStudio doesn't run those tools.

The architecture is deliberately AI-agnostic. Any model or provider can be added without touching the UI, storage, or IDE integration. The active backend is selected from the status bar and persisted across launches.

---

## Module Overview

```text
App                          — orchestrator, startup, project switching
├── Master classes
│   ├── AIBackend            — abstract: Start/Shutdown, SendMessage, SetModel/Mode
│   ├── AIFrontend           — abstract: SlashCommands, ModeOptions, SessionList, ModelList, ToolbarItems
│   └── AIBackendDelegate    — interface: ChatView implements this; backends call it instead of MainWindow directly
│
├── Module: Claude
│   ├── ClaudeCodeBackend    — subprocess, stream-json, permission prompts, plan mode, WS IDE bridge
│   └── ClaudeFrontend       — slash commands (built-ins + skill scanning), mode options, sessions (.jsonl), model list
│
├── Module: Codex
│   ├── CodexBackend         — JSON-RPC 2.0 over stdio, approval protocol, model/list fetch
│   └── CodexFrontend        — sessions (filesystem scan of ~/.codex/sessions/), toolbar items
│
├── Module: DBHelper         — SQLite, parameterised queries, template DB, SeedProject, AsJSONItem helper
├── Module: EditorHelper     — shared infrastructure for NoteEditorWindow + JobEditorWindow (LoadFiles, BuildEditorHTML, ApplyThemeScript, UnsavedChangesDialog)
├── Module: Secrets          — secret access via `#If DebugBuild`: keychain in debug, SecretsBuiltin in release
└── Module: SecretsBuiltin   — stub in repo; inject-secrets.sh overwrites with secrets before IDE build, restore-secrets.sh restores stub after
```

---

## AIBackend / AIFrontend pair

Every AI backend consists of two classes:

**AIBackend** — subprocess communication, streaming tokens, capability flags:

| Method / Property | Purpose |
|---|---|
| `Start(projectPath)` / `Shutdown()` | Launch / terminate subprocess |
| `SendMessage(text, history())` | Send user turn |
| `SendMessageWithImage(text, b64, mediaType, history())` | Send with image |
| `StopGeneration()` | Interrupt current turn |
| `SetModel(m)` / `SetMode(m)` / `SetReasoningEffort(e)` | Reset `SessionId`, restart subprocess with new args |
| `NewSession()` / `ResumeSession(uuid)` | Session management |
| `SupportsPlanMode`, `SupportsPermissionPrompts`, `SupportsImageInput`, `SupportsReasoningEffort` | Capability flags — drive UI visibility |
| `FireOnToken`, `FireOnDone`, `FireOnError` | Events → App → ChatView |

**AIFrontend** — UI data, no subprocess knowledge:

| Method | Purpose |
|---|---|
| `SlashCommands(projectPath)` | JSON `[{cmd, desc}]` — built-ins + skill file scanning |
| `ModeOptions()` | JSON `[{value, label}]` — ask/auto/plan or empty |
| `ToolbarItems()` | JSON `[{id, label, message}]` — Revert/Build/Debug or empty |
| `ModelList()` | JSON `[{value, label}]` — live or static fallback |
| `SessionList(projectPath)` | JSON `[{uuid, title, date}]` filtered by project |
| `SupportsXMCP()` | Whether toolbar buttons should be active |

Session chat replay (`{role, content}` JSON for sidebar) is owned by each `AIBackend` subclass via `GetSessionChatJSON(uuid)` — not `AIFrontend`.

On every backend switch, `App.BuildBackendUIConfig()` assembles a single JSON object and calls `loadBackendUI(config)` in JS — one call updates models, capabilities, slash commands, mode options, toolbar items, and session list simultaneously.

**AIBackendDelegate** — interface implemented by `ChatView`. All backends call `mDelegate.*` instead of `MainWindow.TheViewer.*` directly, so backends have no compile-time dependency on the window hierarchy.

**Adding a new backend** means creating a module with two classes (`*Backend` + `*Frontend`) and registering them in `App.RegisterBackends()`. No other files change.

---

## Current Backends

### Claude (Module: Claude)

**ClaudeCodeBackend** — all capability flags `True` including `SupportsReasoningEffort`.

Launches `claude` via `NSTaskMBS` (resolved from `~/.local/bin/claude`, `~/.claude/local/claude`, `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, or shell `PATH`) with `--output-format stream-json --input-format stream-json --verbose --ide`, plus `--model`, `--effort` (if not `medium`), and a mode flag:

| Mode | Flag |
| --- | --- |
| Ask before edits | `--permission-prompt-tool stdio` (default) |
| Edit automatically | `--dangerously-skip-permissions` |
| Plan mode | `--permission-mode plan` |

`SetModel`, `SetMode`, and `SetReasoningEffort` all reset `SessionId` before restarting — prevents "No conversation found" errors when switching settings.

**Streaming:** `stream_event` / `content_block_delta` / `text_delta` lines are fired as tokens immediately. The final `assistant` message is only processed for tool-use (diffs, permission prompts) — text is skipped if streaming already delivered it.

**ClaudeFrontend** — `SlashCommands` returns 8 built-ins plus any `.md` files found in `~/.claude/commands/` and `<projectPath>/.claude/commands/`. `ModelList` returns a cached result if already fetched, otherwise the static fallback. `FetchModelListAsync` fires an async `URLConnection` request to `api.anthropic.com/v1/models` (requires API key in keychain under `Anthropic`/`APIKey`); on success it updates the cache and calls `loadBackendUI` to refresh the model dropdown. `GetSessionChatJSON(uuid)` parses the `.jsonl` file for session replay.

### Codex (Module: Codex)

**CodexBackend** — `SupportsPlanMode = False`, `SupportsPermissionPrompts = True`, `SupportsImageInput = True`, `SupportsReasoningEffort = True`.

Launches `codex app-server` via JSON-RPC 2.0 / JSONL over stdio. After `initialize` responds, sends `model/list` to populate the model dropdown dynamically; calls `loadBackendUI` again when the response arrives. `approvalPolicy` must be `"on-request"`. `reasoningEffort` (`low`/`medium`/`high`) is sent in both `thread/start` and `turn/start` payloads.

**CodexFrontend** — `SessionList` scans `~/.codex/sessions/` directly (filesystem, not `session_index.jsonl` which doesn't update in real-time). `ModelList` returns `"[]"` — the backend populates its `Models` array directly after `model/list` responds and calls `loadBackendUI` again. `ToolbarItems` and `SupportsXMCP` are inherited from `AIFrontend`. `GetSessionChatJSON(uuid)` is owned by `CodexBackend` (finds the session file by uuid, parses `response_item` lines for role/content).

---

## XOJO IDE Tools (XMCP, separate process)

The 22 XOJO IDE tools (`get_code`, `set_code`, `revert_project`, `build_project`, `search_docs`, `get_debug_log`, …) live in a **sibling project**: [github.com/o3jvind/XMCP](https://github.com/o3jvind/XMCP). Users register XMCP once in `~/.claude.json`:

```json
{ "mcpServers": { "xmcp": { "command": "/path/to/XMCP" } } }
```

The AI spawns XMCP at session start. XMCPStudio's only runtime relationship with XMCP:

- 5-second IDE socket polling (`/tmp/XojoIDE`) for the status indicator
- Toolbar buttons (Revert/Build/Debug) send tool names as user messages; the AI routes them through XMCP

---

## Chat UI (WebView Bridge)

HTML/CSS/JS loaded into a `WKWebView` (MBS plugin). All files are inlined at load time — WKWebView sandbox blocks external references.

**JS → XOJO:** `window.webkit.messageHandlers.<name>.postMessage(data)`  
**XOJO → JS:** `EvaluateJavaScript(jsCode)` on `ChatView`

Key JS functions called from XOJO:

| Function | Purpose |
|---|---|
| `loadBackendUI(config)` | Full UI refresh on backend switch — models, capabilities, slash commands, mode options, toolbar items, sessions |
| `appendToken(text)` | Stream token into current bubble |
| `finalizeMessage()` | Close bubble, render Markdown, add copy/collapse buttons |
| `showDiff(id, path, old, new)` | Inline diff card with Accept/Reject (via WS `openDiff` — rare in practice) |
| `showPermissionPrompt(path, detail, oldStr, newStr)` | Inline permission card (Ask mode) with optional diff preview |
| `showPlanApproval(planText)` | Inline plan card (Plan mode) |
| `showAskUserQuestion(questionsJSON)` | Inline question card (AskUserQuestion) |
| `loadSessions(json)` | Refresh session list |
| `loadJobs(json)` / `loadNotes(json)` | Refresh sidebar lists |

**Toolbar (input area):**
- Left: Clear, `/` (slash menu — hidden when empty), `+` (file picker)
- Right: Dynamic toolbar items from `loadToolbarItems` (Revert/Build/Debug when `SupportsXMCP = True`), Stop (while generating), Send
- Toolbar buttons post `xmcpAction` → in-chat permission card for both Claude and Codex (no native dialog)

**Status bar selectors** (shown/hidden by capability flags):

- Model dropdown — always visible
- Mode dropdown — Claude only (`SupportsPlanMode`)
- Approval dropdown — Claude only (`SupportsPermissionPrompts`, Ask/Auto)
- Effort dropdown — both backends (`SupportsReasoningEffort`): Claude = Low/Medium/High/X-High/Max, Codex = Low/Medium/High. Resets to Medium on backend switch.

---

## Data Storage

SQLite at `~/Library/Application Support/<bundle-id>/xmcpstudio.sqlite`. Chat history is **not** stored here — Claude sessions live as `.jsonl` files in `~/.claude/projects/<slug>/`, Codex sessions in `~/.codex/sessions/`.

**Tables:** `jobs` (`id, name, prompt, description, tags, sort, created`), `notes` (`id, title, body, tags, description, scope, project_path, sort, created, updated`), `app_settings` (key/value). `scope` is `"global"`, `"project"`, or `"orphaned"` — orphaned is computed at read time in `GetNotesJSON` when `project_path` no longer exists on disk; it is never written back to the DB.

**Template DB** (`src/template-db/xmcpstudio_template.sqlite`) is the schema source of truth — copied to Application Support on first run. `DBHelper.InitDB` only opens the connection; no migrations. To change the schema, regenerate the template DB and delete the local copy.

**Seeding:** `DBHelper.SeedProject(projectPath)` seeds 4 project notes + 10 starter jobs on first encounter; both are guarded by `HasProjectNotes` / `HasAnyJobs`.

---

## Startup Sequence

1. **Folder picker** — user picks a project folder; `ProjectPickerWindow` if multiple `.xojo_project` files
2. **Open in IDE** — `open -a Xojo <project>`; polls `/tmp/XojoIDE` up to 5 s; raises XMCPStudio back to foreground
3. **SQLite** — copies template DB on first run; `DBHelper.InitDB` opens connection
4. **Seed** — `DBHelper.SeedProject(projectPath)`
5. **Backend registry** — `App.RegisterBackends()` creates Claude + Codex instances; restores `active_backend` from settings; calls `SetDelegate(MainWindow.TheViewer)` on the active backend before `Start()`
6. **Start backend** — `mActiveBackend.Start(projectPath)`: for Claude — WS server + lock file + subprocess; for Codex — subprocess + `initialize` + `model/list`
7. **Load WebView** — `web-assets/index.html` loaded into ChatView
8. **JS ready** → `loadBackendUI`, `loadJobs`, `loadNotes` pushed into UI; window title set to `XMCPStudio — <project> (<branch>)`
9. **5 s polling loop** — `PollXMCPStatus` lights the XOJO status indicator
