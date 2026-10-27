# Design

## Context

- **The app** is a sandboxed SwiftUI app with one `WindowGroup` and a `Settings` scene, and no app delegate. With a plain `WindowGroup`, macOS already keeps the app running after the last window closes; there's no `applicationShouldTerminateAfterLastWindowClosed`.
- **Writes** go through `AppModel.send(Command)` over XPC to the agent: `createTask(TaskDraft)` (title, body, priority, due, tags, effort) and `createPage(PageDraft)` (title, body, tags). Both resolve `[[links]]` and are undoable and attributed.
- **The agent** is a plain background process without a window system, and stays that way (decision A from exploration).
- **⌘N** already creates a task or page inside the window (`Navigation.requestNew`). Capture is the outside-the-window counterpart.

Motivation is in `proposal.md`, behavior in `specs/quick-capture/spec.md`.

## Goals / Non-Goals

**Goals:**
- **Parsing in Core:** pure, tested, and reusable later (an MCP "capture" tool, links, iPhone).
- **A panel that never steals focus** from the app you were in when you press Return.

**Non-Goals:**
- Links and bookmarks.
- Multi-line notes.
- Natural-language parsing beyond the listed forms ("next week", "in 3 days").
- Capturing while WorkDash isn't running.

## Decisions

### Q1: `CaptureParser` (Core, pure)

`CaptureParser.parse(_ text: String, kind: .task | .page, today: LocalDay) -> CaptureDraft` returns the title, tags, due and priority, plus `consumed` ranges for the preview.

Tokens are whitespace-separated and parsed left to right:
- **Tags:** `#` followed by a valid `TagName`. An invalid one (`#`) stays in the title.
- **Priority:** a standalone `!` → high, `!!` → urgent. The last one wins.
- **Due date (tasks only):**
  - `today` / `tomorrow` (case-insensitive)
  - a weekday name or 3-letter abbreviation → the next such day after today; today's weekday means a week ahead
  - `<d> <Mon>` (with or without `.`, current year, or next year if already past)
  - an ISO date `YYYY-MM-DD`

  A weekday only counts as a due date when it is the **last** non-tag, non-priority token, or is followed only by tags and priority. So "Prepare friday retro" keeps "friday" in its title, while "Call venue fri #x" sets a due date. The same rule applies to the other date forms. This keeps titles intact when a date-like word is part of the sentence.
- **Title:** the remaining tokens joined with single spaces.

`CaptureDraft.taskDraft` and `.pageDraft` map onto the existing drafts. The preview string ("Task · Call venue · due Wed 28 Oct · project/atlas · high") is built in Core too, so it can be tested.

### Q2: Global hotkey

`GlobalHotKey` wraps Carbon `RegisterEventHotKey` and `InstallEventHandler` on the application event target. This works in the sandbox without Accessibility permission (it's the same API menu-bar utilities use) and calls a closure on the main thread.
- **Storage:** the shortcut is a key code plus modifiers in the app's `UserDefaults` (per Mac, not the shared settings).
- **Default:** ⌃⌥Space. Re-registering happens when the setting changes.
- **Collisions:** if registration fails (taken by another app), Settings shows "Shortcut is used by another app".

**Alternative considered:** `NSEvent.addGlobalMonitorForEvents`. Rejected: it needs Accessibility permission and can't consume the key.

### Q3: Floating panel

- **The window:** an `NSPanel` subclass (`CapturePanel`, `.nonactivatingPanel`, `.titled` hidden, `.floating` level, `canJoinAllSpaces`, `fullScreenAuxiliary`) hosting a SwiftUI `CaptureView` through `NSHostingView`.
  - Non-activating means the panel becomes key, so you can type, without activating WorkDash. On Return the panel closes and the previous app is still in front.
  - It's centered in the upper third of the screen with the mouse, Spotlight-like.
- **⌘Return:** saves, then `NSApp.activate`, shows the main window, and navigates to the new item via `Navigation`, using the id from `CommandOK`.
- **Closing:** Esc, or losing key status (clicking elsewhere), closes the panel. The text is kept until a save, so an accidental click doesn't lose it.
- **Shared state:** the panel uses the same `AppModel` and `Navigation` instances as the main window, passed in when created.

### Q4: Menu bar and staying alive

- **Menu bar:** a `MenuBarExtra("WorkDash", systemImage: "checklist")` scene with Quick Capture (showing the shortcut), Open WorkDash and Quit. `isInserted` is bound to the "Show in menu bar" setting (default on).
- **Open WorkDash:** activates the app and opens the main window if none is open (`openWindow` with the `WindowGroup`'s id).
- **Open at login:** `SMAppService.mainApp.register()` / `unregister()`, with its status read back for the toggle.
- **Window closing:** the app already doesn't quit on last-window close, and there's no change there. The Dock icon stays, which is normal macOS behavior.

### Q5: Settings

A "Capture" tab: the shortcut recorder (a small view that records the next key combination with at least one of ⌘⌃⌥, Esc to cancel), "Show in menu bar" and "Open at login".

## Risks / Trade-offs

- **[Carbon is old]** → It's still the supported way to get a sandbox-safe global hotkey, used widely. Wrapped in one small type, so it's easy to replace.
- **[A non-activating panel and text input]** → Some apps keep the cursor visually. The panel calls `makeKeyAndOrderFront` and focuses its field explicitly; the manual check covers typing into it from a full-screen app.
- **[Date words in titles]** → The last-position rule (Q1), plus the preview, which shows how the text was read before saving.
- **[The shortcut clashes with input-source switching]** (⌃Space / ⌃⌥Space on some setups) → Configurable, and registration failure is reported.

## Migration Plan

None. Settings default to: shortcut ⌃⌥Space, menu bar icon shown, open at login off.
