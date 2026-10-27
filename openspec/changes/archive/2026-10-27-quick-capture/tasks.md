# Tasks

## 1. Core

- [x] 1.1 Add `CaptureParser` and `CaptureDraft` (Q1: tags, priority, due forms with the last-position rule, title, preview string, mapping to `TaskDraft`/`PageDraft`); verify with tests for "Task with tag, due date and priority", "Words that only look like dates", each due form incl. weekday = today → next week and a past `3 Nov` → next year, `!`/`!!`, invalid `#`, page kind ignoring dates and priority, and empty title

## 2. App

- [x] 2.1 Add `GlobalHotKey` (Q2) and the shortcut setting with default ⌃⌥Space and failure reporting; `CapturePanel` + `CaptureView` (Q3: preview line, Tab Task↔Page, Return / ⌘Return / Esc, keep text on accidental close, no activation on Return); verify manually "Capture from another app", "Save and keep working", "Save and open", "Cancel"
- [x] 2.2 Add the `MenuBarExtra` (Q4) and the Settings "Capture" tab (Q5: shortcut recorder, Show in menu bar, Open at login via `SMAppService.mainApp`); verify manually "Change the shortcut", "Window closed", menu bar hidden/shown, open at login on and off

## 3. End to end

- [x] 3.1 Write `docs/manual-checks-quick-capture.md` (neutral test data) and push it as WorkDash tasks with `scripts/manual-checks.py push`; covers capturing from a browser, a full-screen app and with the window closed, the syntax preview, ⌘Return, and undo of a captured task; done when `pull` reports every check passed

## Workflow follow-up

- Run `/opsx:verify quick-capture`, then archive after the manual checks pass.
