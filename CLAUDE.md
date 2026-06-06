# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

XMCPStudio is a macOS desktop app (XOJO) that serves as an AI-assisted cockpit for XOJO development. It provides a chat UI, a job library, notes, and a session browser. AI communication is routed through a swappable `AIBackend`/`AIFrontend` pair — the user selects a backend from the status bar and the UI adapts completely. Current backends: `Claude.ClaudeCodeBackend` (Claude Code CLI via stdin/stdout stream-json) and `Codex.CodexBackend` (OpenAI Codex via JSON-RPC 2.0 over stdio).

**XOJO IDE tools (`get_code`, `set_code`, `revert_project`, `search_docs`, etc.) come from a separate XMCP stdio MCP server**. XMCPStudio does not embed or duplicate them. Users register XMCP once in `~/.claude.json`:

```json
{ "mcpServers": { "xmcp": { "command": "/path/to/XMCP/XMCP" } } }
```

## Development

**Build**: Open `src/XMCPStudio.xojo_project` in XOJO IDE and build for macOS.

**Required plugins**: MBS XOJO Plugin — `DesktopWKWebViewControlMBS` / `WKFrameInfoMBS` (chat and editor WebViews), `NSTaskMBS` / `NSPipeMBS` (AI backend subprocess launch and stdio piping).

**Build automation**: `Build Automation.xojo_code` includes two macOS build steps that automatically copy `web-assets/` and `template-db/xmcpstudio_template.sqlite` into the app bundle. No manual copy needed after editing those directories.

**Release builds / secrets injection**: Run `./inject-secrets.sh` before building in the IDE, then `./restore-secrets.sh` immediately after. If the project was already open when you injected, right-click `SecretsBuiltin` in the Navigator → **Revert to Disk** before building. See `README.md` for the full workflow and keychain setup commands.

**Debug log**: `App.AppendDebugLog` writes to `~/Library/Application Support/<bundle-id>/<bundle-id>_debug.log` (bundle-id dots replaced with underscores). `App.UnhandledException` routes there automatically.

## Source Layout

```text
src/
  App.xojo_code                    — orchestrator: startup, project switching, backend registry, DB bootstrap
  MainWindow.xojo_window           — single-column layout (ChatView fills window)
  ChatView.xojo_code               — DesktopWKWebViewControlMBS, JS↔XOJO bridge, implements AIBackendDelegate
  AIBackend.xojo_code              — abstract base: Start/Shutdown, SendMessage, SetModel/Mode, capability flags, mDelegate
  AIFrontend.xojo_code             — abstract base: SlashCommands, ModeOptions, ToolbarItems, ModelList, SessionList
  AIBackendDelegate.xojo_code      — interface implemented by ChatView; backends call mDelegate.* instead of MainWindow directly
  Module: WS/
    WS.xojo_code                   — module container
    WSServerSocket.xojo_code       — TCP server socket; accepts one Claude IDE connection
    WSClientSocket.xojo_code       — connected client socket; read/write raw bytes
    WSClientDelegate.xojo_code     — interface: OnClientData, OnClientError
  Module: Claude/
    ClaudeCodeBackend.xojo_code    — subprocess + stream-json + WS IDE bridge + lock file
    ClaudeFrontend.xojo_code       — slash commands (built-ins + skill scanning), sessions, async model list fetch
  Module: Codex/
    CodexBackend.xojo_code         — JSON-RPC 2.0 over stdio, approval protocol, model/list fetch
    CodexFrontend.xojo_code        — sessions (filesystem scan of ~/.codex/sessions/), toolbar items
  DBHelper.xojo_code               — all SQLite operations + SeedProject + AsJSONItem helper (no schema work — template is truth)
  EditorHelper.xojo_code           — shared module for NoteEditorWindow + JobEditorWindow: LoadFiles, BuildEditorHTML, ApplyThemeScript, UnsavedChangesDialog
  Secrets.xojo_code                — secret access: keychain in debug (#If DebugBuild), SecretsBuiltin in release
  SecretsBuiltin.xojo_code         — stub in repo; inject-secrets.sh overwrites with secrets before IDE build, restore-secrets.sh restores stub after
  NoteEditorWindow.xojo_window     — native note editor (edit/split/preview)
  JobEditorWindow.xojo_window      — native job editor (mirror of NoteEditorWindow)
  HelpWindow.xojo_window           — help viewer (DesktopWKWebViewControlMBS, loads web-assets/help/)
  ProjectPickerWindow.xojo_window  — shown when folder contains multiple .xojo_project files
  MainMenuBar.xojo_menu            — menu bar definition (File, Edit, Project, Help)
  template-db/
    xmcpstudio_template.sqlite     — schema + 3 global starter notes; copied to App Support on first run
  web-assets/
    index.html
    css/
      variables.css                — design tokens (dark theme)
      chat.css                     — bubbles, markdown, copy buttons, toolbar, slash menu
      sidebar.css                  — job list, session list, notes, search
      modals.css                   — btn classes (modal CSS removed; notes open via native window)
      layout.css                   — three-column flex layout, status bar
      note-editor.css              — note editor window styles
      job-editor.css               — job editor window styles
    js/
      main.js                      — core UI, bridge registration, loadBackendUI, loadToolbarItems, loadSlashCommands, loadModeOptions
      chat-handler.js              — appendToken, finalizeMessage, showDiff
      sanitize.js                  — DOMParser-whitelist sanitizeHTML()
      job-manager.js               — job CRUD, drag-to-reorder, click-to-insert
      notes-manager.js             — notes CRUD, scope grouping, filterNotes
      note-editor.js               — note editor bridge
      job-editor.js                — job editor bridge
      vendor/
        marked.min.js              — Markdown rendering (bundled; CDN blocked by WKWebView)
    help/
      help.css                     — styles for HelpWindow content
      help.js                      — JS for HelpWindow (loaded by HelpWindow.xojo_window)
```

## Key Architectural Rules

**AIBackend + AIFrontend pair**: every AI backend consists of two classes. `AIBackend` handles subprocess communication and streaming. `AIFrontend` owns UI data (slash commands, mode options, toolbar items, model list, session list) — no subprocess knowledge. Adding a new AI means creating one module with these two classes and registering them in `App.RegisterBackends()`. Nothing else changes.

**AIBackendDelegate**: interface implemented by `ChatView`. All backends hold a `mDelegate As AIBackendDelegate` set via `SetDelegate()` and call `mDelegate.*` for all UI callbacks — they never reference `MainWindow.TheViewer` directly. `App.RegisterBackends()` and `App.SwitchBackend()` both call `SetDelegate(MainWindow.TheViewer)` before `Start()`.

**`loadBackendUI(config)`**: the single JS call that refreshes the entire UI on backend switch — models, capabilities, effort options, slash commands, mode options, toolbar items, sessions. Built by `App.BuildBackendUIConfig()` which assembles JSON from the active `AIBackend` + `AIFrontend` pair. `effortOptions` array drives the effort dropdown; Claude gets 5 levels (`low`/`medium`/`high`/`xhigh`/`max`), Codex gets 3 (`low`/`medium`/`high`). Dropdown resets to `medium` on every backend switch.

**JavaScript handles**: all UI logic, streaming text rendering, Markdown formatting, diff display, bridge message dispatch.

**XOJO handles**: SQLite operations, WebSocket bridge lifecycle, lock file management, native window management, shell commands.

**Never call AI directly from JS** — all model communication goes through the active `AIBackend`. The chat UI calls `AIBackend.SendMessage()` and listens for `OnToken` / `OnDone` / `OnError`.

**No auto-approve, no background AI calls.** Every Send is explicit and user-triggered.

## JS ↔ XOJO Bridge

- **JS → XOJO**: `window.webkit.messageHandlers.<name>.postMessage(data)`
- **XOJO → JS**: `Me.EvaluateJavaScript(jsCode)` on the ChatView instance

Message handlers registered in `ChatView.didReceiveScriptMessage`:
`sendMessage`, `xmcpAction`, `openJobEditor`, `insertJobPrompt`, `deleteJob`, `reorderJob`, `createNote`, `editNote`, `deleteNote`, `reorderNote`, `diffAccepted`, `diffRejected`, `stopGeneration`, `newSession`, `selectSession`, `clearChat`, `setBackend`, `setModel`, `setMode`, `setApprovalMode`, `setEffort`, `setTheme`, `compactHistory`, `pickFile`, `ready`, `grantPermission`, `denyPermission`, `approvePlan`, `rejectPlan`, `askUserAnswer`, `openNote`, `openURL`

`xmcpAction` — posted by toolbar buttons (Revert/Build/Debug). Both Claude and Codex use the in-chat permission card flow (no native dialog). Claude: stored in `mPendingXmcpMessage`, shown via `ShowPermissionPrompt`, sent as a user message on approval. Codex: forwarded directly via `HandleUserMessage` (Codex has its own in-chat approval flow).

`setEffort` — posted by the effort dropdown in the status bar. Routes to `App.SetBackendEffort` → `SetReasoningEffort` on the active backend. Claude restarts the subprocess with `--effort <level>`; Codex sends `reasoningEffort` in `turn/start`.

`NoteEditorWindow.EditorView` and `JobEditorWindow.EditorView` each register their own handlers — `saveNote`/`deleteNote`/`closeEditor`/`setDirty` and `saveJob`/`deleteJob`/`closeEditor`/`setDirty`.

Key `EvaluateJavaScript` calls from XOJO into JS:

- `loadBackendUI(config)` — full UI refresh on backend switch
- `appendToken(text)`, `finalizeMessage()` — streaming
- `showUserMessage(text, imageDataUrl?)` — user bubble
- `loadJobs(json)`, `loadSessions(json)`, `loadNotes(json)` — sidebar lists
- `loadSessionChat(messages)` — history replay
- `showDiff(requestId, filePath, oldContent, newContent)` — diff card
- `showPermissionPrompt(path, detail, oldStr, newStr)` — permission card (Ask mode); `oldStr`/`newStr` populate an inline diff so the user sees what will change before approving
- `showPlanApproval(planText)` — plan card (Plan mode)
- `showAskUserQuestion(questionsJSON)` — question card
- `setBackendStatus(name, connected, supportsTools)` — status bar dot
- `insertText(text)`, `insertImageAttachment(name, base64, mediaType)` — input area

## Menus

| Menu | Item | Shortcut | Handler | Purpose |
| --- | --- | --- | --- | --- |
| File | Open Project… | ⌘O | `MainWindow.FileOpenProject` | Folder picker → validates `.xojo_project` → opens in XOJO IDE → restarts active backend with new workspace |
| File | Export Session as Markdown… | ⌘E | `MainWindow.FileExportSession` | Reads active session via `mActiveBackend.GetSessionChatJSON(uuid)`, formats as `## User`/`## Assistant`, `SaveFileDialog` |
| File | Close Window | ⌘W | `NoteEditorWindow` / `JobEditorWindow` | Closes focused editor; `CancelClosing` handles unsaved-changes prompt |
| Project | Revert | ⌘R | `MainWindow.ProjectRevert` | Sends `revert_project` via `xmcpAction` flow |
| Project | Build | ⌘B | `MainWindow.ProjectBuild` | Sends `build_project` via `xmcpAction` flow |
| Project | Debug | ⌘D | `MainWindow.ProjectDebug` | Sends `run_project` via `xmcpAction` flow |
| Help | XMCPStudio Help | ⌘? | `MainWindow.HelpXMCPStudio` | Opens `HelpWindow` with `web-assets/help/` content |
| Edit | Cut/Copy/Paste/Select All/Undo | standard | system-routed to WKWebView | Standard text editing |

## Database Layout

Single SQLite database at `~/Library/Application Support/<bundle-id>/xmcpstudio.sqlite`. Chat sessions are **not** in SQLite — Claude sessions live as `.jsonl` in `~/.claude/projects/<slug>/`, Codex sessions in `~/.codex/sessions/`.

`app_settings` key/value: `theme` = `system`/`dark`/`light`; `active_backend` = backend title string.

**The template DB is the source of truth for the schema.** `DBHelper.InitDB` only opens the connection — no `CREATE TABLE`, no migrations. To change the schema: regenerate template DB, commit, delete local DB to force fresh copy on next launch.

**Schema:**

- `jobs` — `id, name, prompt, description, tags, sort, created`
- `notes` — `id, title, body, tags, description, scope, project_path, sort, created, updated` — `scope` is `"global"` or `"project"` on disk; `"orphaned"` is computed at read time in `GetNotesJSON` when `project_path` no longer exists — never written back to the DB

**Starter content** — `DBHelper.SeedProject(projectPath)` (called from `App.Opening` and `App.SwitchProject`):

- 10 starter jobs seeded once, guarded by `HasAnyJobs()`
- 4 project notes (`Architecture`, `TODO`, `Decisions`, `Glossary`) seeded per-project, guarded by `HasProjectNotes(projectPath)`
- 3 global starter notes ship in the template DB

## Backends

### Claude (Module: Claude)

`Claude.ClaudeCodeBackend` — capability flags all `True`. Two channels:

**stdin/stdout:** Launches `claude` via `NSTaskMBS` with `--output-format stream-json --input-format stream-json --verbose --ide`, plus `--model <model>`, `--effort <level>` (if not `medium`), and mode flag:

| Mode | Flag |
| --- | --- |
| Ask before edits | `--permission-prompt-tool stdio` (default) |
| Edit automatically | `--dangerously-skip-permissions` |
| Plan mode | `--permission-mode plan` |

stdout is read via `NSFileHandleMBS` + `waitForDataInBackgroundAndNotify` (event-driven, no polling). `SetModel`/`SetMode`/`SetReasoningEffort` all reset `SessionId` and restart subprocess.

**WS IDE bridge:** Claude requires `--ide` flag to flush stdout per-line instead of buffering. Before launching, `ClaudeCodeBackend` finds a free port (10000–10999), starts a `WS.WSServerSocket`, and writes a lock file to `~/.claude/ide/<port>.lock`. Claude reads the lock file and connects to the WS server (MCP protocol). XMCPStudio responds to `tools/list` and `tools/call` (IDE tools: `getWorkspaceFolders`, `openDiff`, `AskUserQuestion`, etc.). The WS module (`WS.xojo_code`, `WSServerSocket`, `WSClientSocket`, `WSClientDelegate`) lives in `src/WS/`.

**Streaming:** `stream_event` lines with `content_block_delta` / `text_delta` are fired as tokens immediately. The final `assistant` message is only processed for tool-use (diffs, permission prompts) — text is skipped if streaming already delivered it.

**Permission prompts (Ask mode):** Claude sends `control_request` → inline permission card in UI → user clicks Yes/Yes always/No → `SendControlResponse`. "Yes always" sets `mAutoApprove = True` silently approving all subsequent requests. **Never restart the subprocess from `GrantPermission`** — Claude is waiting for the response.

**Plan mode:** Claude calls `ExitPlanMode` tool in stdout stream. XMCPStudio intercepts it, shows plan-approval card. On approval: restart in Ask mode + send "Plan approved". On rejection: restart in Plan mode.

`Claude.ClaudeFrontend` — `SlashCommands` returns 8 built-ins + scans `~/.claude/commands/` and `<projectPath>/.claude/commands/` for `.md` skill files. `ModelList` returns a cached result (`mCachedModelList`) if already fetched, else the static fallback (Opus 4.8, Opus 4.7, Sonnet 4.6, Haiku 4.5 + hint option). `FetchModelListAsync` fires an async `URLConnection` to `api.anthropic.com/v1/models` (requires keychain entry `Anthropic`/`APIKey`); on success updates cache and calls `loadBackendUI`. `GetSessionChatJSON(uuid)` parses the `.jsonl` file directly in `ClaudeCodeBackend` for session replay.

### Codex (Module: Codex)

`Codex.CodexBackend` — `SupportsPlanMode = False`, `SupportsPermissionPrompts = True`, `SupportsImageInput = True`, `SupportsReasoningEffort = True`.

Launches `codex app-server`, speaks JSON-RPC 2.0 / JSONL over stdio. After `initialize` responds: sends `model/list`, updates `Models` array, calls `loadBackendUI` again. `approvalPolicy` must be `"on-request"` — `"unless-trusted"` crashes the server. `reasoningEffort` (`low`/`medium`/`high`) is sent in both `thread/start` and `turn/start` payloads.

Multi-file approval: each `item/started fileChange` stores all `changes[]` entries (path + unified diff) keyed by item ID. On `item/fileChange/requestApproval` the stored segments are retrieved and each file's removed/added lines are extracted. When more than one file is involved, a `--- path ---` header is prepended before each file's content so the permission card shows clear file boundaries.

`Codex.CodexFrontend` — `SessionList` scans `~/.codex/sessions/` directly (filesystem, not `session_index.jsonl` which doesn't update in real-time). `ModelList` returns `"[]"` — backend populates `Models` array directly. `ToolbarItems` and `SupportsXMCP` are inherited from `AIFrontend`. `GetSessionChatJSON(uuid)` is on `CodexBackend`.

## CSS/JS Conventions

- CSS custom properties in `variables.css`. Dark is default; light via `[data-theme="light"]`; system via `@media (prefers-color-scheme: light)`. `applyTheme(value)` in JS toggles `data-theme` on `document.documentElement`.
- Vendor JS bundled locally — WKWebView sandbox blocks CDN.
- `sanitizeHTML()` on all AI-generated content before DOM insertion.
- **Copy button**: store text in `_messageTexts[id]`, pass only ID in `onclick` — WKWebView JS parser breaks on `}` in inline handlers.
- **Bubble collapse**: `tagIfCollapsible(bubble)` called after bubble is in DOM (`scrollHeight > 200px`). Must be in DOM — `scrollHeight` reads 0 on detached elements.
- **Session chat replay**: call `mActiveBackend.GetSessionChatJSON(uuid)` — both `ClaudeCodeBackend` and `CodexBackend` implement this. Use `AsJSONItem(variant)` helper (defined in `DBHelper` module) when reading child JSON nodes — direct cast to `JSONItem` raises on string values.
- **`confirm()` in WKWebView**: requires `runJavaScriptConfirmPanel` event on the control — without it returns `false` silently.
- **`EvaluateJavaScript` is always async** — never try to read return values. Have JS push state back via bridge instead.
- **`var` not `const` for injected data** — `const` does not create a `window` property in WKWebView. Use `var NOTE_DATA = {...}` / `var JOB_DATA = {...}`.
- **`DragEnter` must NOT return `True`** — acceptance is registered via `AcceptFileDrop` only; returning `True` hangs the drag session.

## App Startup Sequence

1. **Folder picker** — `ChooseProjectFile()`. Retry dialog if no `.xojo_project` found; `ProjectPickerWindow` if multiple.
2. **Open in IDE** — `open -a Xojo <path>`; polls `/tmp/XojoIDE` up to 5 s; `RaiseSelf` brings XMCPStudio back.
3. **DB bootstrap** — copy template DB on first run; `DBHelper.InitDB` opens connection.
4. **Seed** — `DBHelper.SeedProject(projectPath)`.
5. **Backend registry** — `App.RegisterBackends()` creates Claude + Codex pairs. Restores `active_backend` from settings; calls `SetDelegate(MainWindow.TheViewer)` on the active backend only before `Start()`.
6. **Start backend** — `mActiveBackend.Start(projectPath)`: for Claude — subprocess launch; for Codex — subprocess + `initialize` + `model/list`.
7. **Load WebView** — `web-assets/index.html` into ChatView.
8. **JS `ready`** → `loadBackendUI`, `loadJobs`, `loadNotes`, window title set. For Claude: `FetchModelListAsync` triggered to populate live model list.
9. **5 s polling** — `PollXMCPStatus` checks `/tmp/XojoIDE`.

**File → Open Project… (⌘O)** re-runs steps 1–2 and 4–6, refreshes UI.
