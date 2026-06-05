# Changelog

All notable changes to XMCPStudio will be documented here.

## [Unreleased]

### Improved

- Claude Code backend gives better feedback during long-running sessions

## [0.1.0] — 2026-06-01

Initial public release.

### Added

- Streaming chat UI with Markdown rendering, bubble collapse, and copy buttons
- Claude Code backend (subprocess + stream-json + WebSocket IDE bridge)
- Codex backend (JSON-RPC 2.0 over stdio, `app-server` protocol)
- Inline permission cards with diff preview (Ask mode)
- Inline plan-approval cards (Plan mode)
- Inline AskUserQuestion cards
- Session browser (sidebar) with replay from `.jsonl` transcripts
- Job library — saved prompt templates with drag-to-reorder and native editor
- Notes — global and per-project Markdown notes with native editor (edit/split/preview)
- Model picker with live fetch from Anthropic API (Claude) and dynamic list from Codex
- Effort selector: Low / Medium / High / X-High / Max (Claude); Low / Medium / High (Codex)
- Mode selector: Ask before edits / Edit automatically / Plan mode (Claude only)
- Approval mode: Ask / Allow all (Claude only)
- Backend switcher in status bar with XOJO IDE socket indicator
- File → Open Project… (⌘O) to switch project at runtime
- File → Export Session as Markdown… (⌘E)
- Revert / Build / Debug toolbar buttons via XMCP
- Dark and light theme support
- Native note and job editor windows with unsaved-change protection
- Help window (⌘?)
- MIT License
