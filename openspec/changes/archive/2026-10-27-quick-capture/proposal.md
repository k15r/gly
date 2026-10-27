# Proposal

## Why

Tasks and page ideas come up while I'm in other apps: in a meeting, in the browser, in a terminal. Today capturing one means switching to WorkDash, finding the right view and pressing ⌘N, so small things get lost or land on paper. WorkDash should be one keystroke away from anywhere.

## What Changes

- **Global shortcut** (default ⌃⌥Space, configurable in Settings) opens a small floating capture panel above any app, while WorkDash runs. It needs no Accessibility permission.
- **Capture panel:**
  - one line, with a preview line underneath of exactly what will be created
  - Tab switches between Task and Page
  - Return saves and closes, without bringing WorkDash to the front
  - ⌘Return saves and opens the new item in WorkDash
  - Esc closes without saving
- **Inline syntax** in the typed text:
  - `#tag/path` adds tags (several allowed)
  - `today`, `tomorrow`, a weekday (`fri`), `3 Nov` or `2026-11-03` sets the due date (tasks)
  - `!` sets high and `!!` urgent priority (tasks)
  - The rest is the title.
- **Always reachable:**
  - a menu bar icon with Quick Capture, Open WorkDash and Quit
  - closing the main window keeps WorkDash running, so the shortcut keeps working
  - an optional "Open at login" setting
- **Settings:** a Capture section with the shortcut, "Show in menu bar" and "Open at login".

Not in this change: capturing links or bookmarks (later, as a third type once bookmarks exist), multi-line notes in the panel, capture through MCP (agents already create tasks and pages).

## Capabilities

### New Capabilities

- `quick-capture`: the global shortcut, the capture panel, the inline syntax, the menu bar item, and staying reachable while the window is closed.

### Modified Capabilities

None. Created tasks and pages behave as specified in `tasks` and `info-pages`.

## Impact

- **Core:** `CaptureParser`, pure, turns typed text into a task or page draft (title, tags, due, priority). It's unit-tested and independent of the UI.
- **App:**
  - a global hotkey registration (Carbon `RegisterEventHotKey`, sandbox-safe)
  - a floating, non-activating panel with the SwiftUI capture view
  - a `MenuBarExtra` scene
  - a Settings section, with the shortcut recorder and the login item (`SMAppService.mainApp`)
- **No store or MCP change:** captures go through the existing `createTask` / `createPage` commands, so undo, attribution and link resolution are unchanged.
