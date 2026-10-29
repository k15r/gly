# Design

## Context

- **Editor:** `MarkdownAttributes.baseFont` is a static `systemFontSize + 1`. Headings scale from it, and `LinkDecoration` sizes its icon from it. The editor's text container tracks the scroll view's width.
- **SwiftUI views** use semantic fonts (`.body`, `.caption`, `.headline`). On macOS these don't follow a dynamic type setting.

## Goals / Non-Goals

**Goals:**
- One size setting that scales everything that's text-heavy.
- Wide windows stay readable.

**Non-Goals:**
- Choosing the font family. Possible later, through the same setting.
- Scaling Settings, menus or popovers.

## Decisions

### R1: The size setting

`TextSize` (S 0.9, M 1.0, L 1.15, XL 1.3) is stored in the app's defaults as `textSize`. `AppModel.textSize` is observable. The View menu gets "Bigger" (⌘+), "Smaller" (⌘−) and "Actual Size" (⌘0), which step through the sizes. Settings has a new Appearance tab with a segmented picker.

### R2: Editor and read-only text

`MarkdownAttributes.baseFont` becomes `baseFont(scale:)`. `MarkdownEditor` takes a `textScale` parameter and re-styles when it changes, exactly like `showsSource`. `MarkdownReadView` takes the same scale.

### R3: Lists and the day view

The app sets a scaled font environment: an `appFont(_ style:)` helper returns `.system(size: base(style) × scale)` for body, callout, caption and headline. The day view, `TaskRow`, the page rows and the chip styles use it instead of fixed semantic fonts.

### R4: Line length

The editor's text container width is limited to `70 × average character width` at the current base font (about 560 pt at M) plus the insets. The text view is centered in its scroll view by placing the container inset symmetrically when the view is wider (`textContainerInset.width = (bounds.width − maxWidth) / 2`, updated on resize). The read-only view gets `.frame(maxWidth:)` and centering.

## Risks / Trade-offs

- **[Not everything scales]** Sidebar, Settings and popovers keep the system size. → That's intentional (see Non-Goals): they're short labels.
- **[Line length vs. code blocks]** Code lines wrap at the same width. → Acceptable; code in notes is short.
