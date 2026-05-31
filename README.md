# XMCPStudio

A macOS desktop app (XOJO) that serves as an AI-assisted cockpit for XOJO development. It provides a chat UI with direct access to the running XOJO IDE — read and write code, navigate the Navigator, run/stop debug sessions, search docs, all without leaving the chat. You choose which AI to use from the status bar.

XMCPStudio itself is the **chat cockpit**: chat UI, AI backend management, the job library, and the notes database. When using Claude Code, it also runs an IDE-integration WebSocket bridge (diff cards, file open, AskUserQuestion, etc.). The 22 **XOJO IDE tools** (`get_code`, `set_code`, `build_project`, `revert_project`, `search_docs`, …) live in a **separate** stdio MCP server called [XMCP](https://github.com/o3jvind/XMCP). The active AI backend spawns XMCP itself once you register it — XMCPStudio doesn't embed it.

## First-run requirements

1. **macOS** — only platform supported.

2. **XOJO IDE** — must be installed and running for the IDE tools to work. XMCP talks to the IDE via its IPC socket at `/tmp/XojoIDE`. XMCPStudio checks for that socket at startup and on project switch to update its status indicator.

3. **At least one AI backend** — XMCPStudio ships with two:

   **Claude Code CLI** (default) — install with:

   ```sh
   curl -fsSL https://claude.ai/install.sh | bash
   ```

   XMCPStudio looks for `claude` at these locations (first match wins):
   - `~/.local/bin/claude`
   - `~/.claude/local/claude`
   - `/opt/homebrew/bin/claude`
   - `/usr/local/bin/claude`
   - Anything on your shell `PATH`

   After installing, run `claude` once in a terminal to sign in. XMCPStudio reuses your existing login — it doesn't ask for credentials separately.

   **Model list:** Claude models are fetched live from the Anthropic API if you add an API key to your keychain. Without a key, a built-in static list is used (Opus 4.8, Sonnet 4.6, Haiku 4.5). To add a key:

   ```sh
   security add-generic-password -s "Anthropic" -a "APIKey" -w "sk-ant-api03-..."
   ```

   **Codex (OpenAI)** — requires a recent version of Codex CLI (needs `app-server` support). Install with the standalone installer:

   ```sh
   curl -fsSL https://chatgpt.com/codex/install.sh | sh
   ```

   Homebrew (`brew install codex`) may also work if it has a recent enough version. XMCPStudio looks for `codex` at `~/.codex/packages/standalone/current/codex`, `~/.local/bin/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, and your shell `PATH`.

   After installing, run `codex` once in a terminal to sign in with your ChatGPT account. Available models are fetched dynamically at startup. Models that work with a ChatGPT account: `gpt-5.4`, `gpt-5.5`. OpenAI API-key models (`o4-mini`, `gpt-4o`, `codex-1`) do **not** work with a ChatGPT login.

   XMCP is auto-loaded by Codex from `~/.codex/config.toml` — register it there once:

   ```toml
   [[mcp_servers]]
   name = "xmcp"
   command = "/Users/you/XMCP/XMCP"
   ```

4. **XMCP MCP server** — the 22 IDE tools. Build it from [github.com/o3jvind/XMCP](https://github.com/o3jvind/XMCP) (it's a XOJO console app) and register it in `~/.claude.json` (for Claude Code):

   ```json
   {
     "mcpServers": {
       "xmcp": { "command": "/path/to/XMCP/XMCP" }
     }
   }
   ```

   The AI spawns XMCP automatically at session start and surfaces the tools as `mcp__xmcp__*`. Without this step, the AI can chat but can't read or edit XOJO code.

5. **MBS XOJO Plugin** — required to build XMCPStudio from source. Used for:
   - `DesktopWKWebViewControlMBS` / `WKFrameInfoMBS` — the chat UI and editor WebViews
   - `NSTaskMBS` / `NSPipeMBS` — subprocess launch and stdin/stdout piping for AI backends

   Download from <https://www.monkeybreadsoftware.de/xojo/>.

6. **A XOJO project to work on** — XMCPStudio prompts for a project folder on startup. Pick the folder containing your `.xojo_project` file.

7. **XOJO's local documentation (optional but recommended)** — XMCP's three docs tools (`search_docs`, `lookup_class`, `list_doc_topics`) read from a `llms-full.txt` file that XOJO's own IDE downloads when you install local docs.

   To install: open the XOJO IDE → **XOJO → Settings** → **General** tab → **Install Local Documentation**. XOJO downloads the docs into `~/Library/Application Support/Xojo/Xojo/<version>/Documentation/`. XMCP auto-detects this path.

   If you skip this step, the docs tools return "docs not configured" when called — everything else still works.

## What you do NOT need

- ❌ No environment variables.
- ❌ No separate authentication for XMCPStudio. It piggybacks on each backend's existing login — Claude Code's and Codex's respectively.

## Build

1. Clone the repo.
2. Open `src/XMCPStudio.xojo_project` in the XOJO IDE.
3. Register the MBS plugin. XMCPStudio reads the MBS serial from the macOS keychain at startup (`App.Opening` → `RegisterMBSPlugin` — see `Secrets.xojo_code`). In debug builds, secrets are always read from the keychain. In release builds, the secrets are burned into `SecretsBuiltin.xojo_code` at build time and the stub is restored immediately after — so credentials are never stored in the repo.

   Add your four MBS license values to the keychain once:

   ```sh
   security add-generic-password -s "MBS" -a "Owner" -w "Your Name"
   security add-generic-password -s "MBS" -a "Product" -w "MBS Complete"
   security add-generic-password -s "MBS" -a "Year"    -w "202611"
   security add-generic-password -s "MBS" -a "Key"     -w "XXXX-XXXX-XXXX-XXXX"
   ```

   The values come from your MBS purchase confirmation email. If the key is missing, a warning is logged but the app still launches — MBS controls will show a nag dialog until a valid key is registered.

4. Build for macOS. Because Xojo CLI headless builds are unreliable on macOS, use the two-step manual build workflow:

   ```sh
   ./inject-secrets.sh   # writes real MBS credentials to SecretsBuiltin.xojo_code
   ```

   **If the project was already open in the XOJO IDE** when you ran `inject-secrets.sh`, the IDE has the old (empty) file cached. Force it to reload before building: right-click `SecretsBuiltin` in the Navigator → **Revert to Disk**, or close and reopen the project.

   Then build in the XOJO IDE (⌘B → Build for macOS). As soon as the build finishes:

   ```sh
   ./restore-secrets.sh  # restores the empty stub immediately
   ```

   ⚠️ Keep the window between these two commands as short as possible — real credentials are on disk while SecretsBuiltin.xojo_code is injected. Do not commit, sync, or back up during this window.

## What the cockpit provides

**Chat UI (XMCPStudio's own surface):**

- Streaming chat with any configured AI backend (Claude Code, Codex), with Markdown rendering, inline diff cards, permission cards, plan-approval cards, and interactive `AskUserQuestion` cards
- Sidebar with sessions (replayed from `.jsonl` transcripts), jobs (saved prompt templates), and notes (global, per-project, and orphaned), each with live search and drag-to-reorder
- Native editor windows for notes and jobs (edit / split / preview Markdown), with unsaved-change protection on close
- Status bar with backend picker, model picker (models fetched dynamically per backend), mode selector (Ask / Edit automatically / Plan — Claude only), approval mode (Ask / Allow all — Claude only), effort selector (Low / Medium / High / X-High / Max for Claude; Low / Medium / High for Codex), and XOJO IDE socket indicator
- File menu: Open Project… (⌘O) to switch project at runtime, Export Session as Markdown… (⌘E)

**XOJO IDE tools (via XMCP — separate process)** — see [XMCP's README](https://github.com/o3jvind/XMCP) for the full list. In short: project navigation & inspection, code read/write, build & run, docs search, diagnostics. The Revert / Build / Debug buttons in XMCPStudio's input toolbar send `revert_project` / `build_project` / `run_project` as user messages to the AI, which routes them through XMCP.

**Direct file access** — the active AI backend can read and write project files directly on disk, independently of XMCP. This is how it edits `.xojo_code` and `.xojo_window` files, applies diffs, and creates new files. XMCP is only needed for operations that require the live IDE (build, run, Navigator inspection, diagnostics).

## Known limitations

These are upstream XOJO IDE scripting API limits, not bugs in XMCPStudio or XMCP:

- **Methods, events, and properties aren't dot-path navigable.** `select_project_item "MyClass.MyMethod"` fails — only top-level Navigator items (classes, modules, windows) can be addressed by path. Use `get_code` / `set_code` against the user's current IDE selection instead, or edit the `.xojo_code` / `.xojo_window` file directly and call `revert_project`.
- **`App` (the `DesktopApplication` subclass) returns empty from `get_code`** even when navigated to. Read its source from disk.
- **Unhandled exceptions in debug runs are caught by the XOJO debugger** and never reach any log. To make exceptions visible to Claude, your project needs an `App.UnhandledException` handler that writes to `/tmp/xmcp_debug.log`, and you must reproduce the crash with a **built** binary (not a debug run). `System.DebugLog` output works in either mode.

See [ARCHITECTURE.md](ARCHITECTURE.md) for a full architectural overview. See [CLAUDE.md](CLAUDE.md) for the JS↔XOJO bridge contract, backend protocol details, and guidance for AI assistants working in this codebase.
