# Proposal

## Why

On a wide window, notes run across the full width, which makes long text hard to read. The text size is fixed at the system size plus one point, with no way to make it larger or smaller.

## What Changes

- **Readable line length:** text in the editor and in read-only views stays within a comfortable width (about 70 characters), centered in wide windows.
- **Text size:** Settings → Appearance offers S, M (default), L and XL. ⌘+ and ⌘− change it and ⌘0 resets it. It applies to notes, the day view and the task and page lists; titles and chips scale along.

## Capabilities

### New Capabilities

None (`appearance` is introduced by `status-colors`, which comes before this change).

### Modified Capabilities

- `appearance`: adds readable line length and text size.

## Impact

- `GlyEditor`: the base font comes from a size setting instead of a constant; the text container gets a maximum width, centered.
- App: an Appearance tab in Settings, ⌘+/⌘−/⌘0 in the View menu, a scale applied to rows and the day view.
- No data, core or MCP changes.
