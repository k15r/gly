#if canImport(AppKit)
import AppKit
import SwiftUI
import WorkDashCore

/// An entry of the `[[` picker.
public struct LinkSuggestion: Identifiable, Equatable {
    public let id: String
    public let symbol: String        // SF Symbol name
    public let title: String
    public let subtitle: String
    /// Markdown inserted in place of `[[query`.
    public let insert: String
    public init(id: String, symbol: String, title: String, subtitle: String, insert: String) {
        self.id = id; self.symbol = symbol; self.title = title; self.subtitle = subtitle; self.insert = insert
    }
}

/// Markdown editor with light live styling, link chips, checklists and the `[[` picker (design P8).
///
/// `text` is the latest known source (store or binding). Local edits go to `onChange` immediately and to
/// `onCommit` debounced (1 s), on focus loss and when the view goes away, with an edit-session id (design P6).
/// An external change replaces the text only while the user isn't editing (design P7).
public struct MarkdownEditor: NSViewRepresentable {
    public var text: String
    public var onChange: ((String) -> Void)?
    public var onCommit: ((_ text: String, _ session: String) -> Void)?
    public var appearance: (ParsedLink.Target) -> LinkAppearance
    public var onOpenLink: (URL) -> Void
    public var suggestions: (String) -> [LinkSuggestion]
    /// Targets an ambiguous typed link could mean (link-disambiguation K5); empty = none.
    public var candidates: (String) -> [LinkSuggestion]

    public init(text: String,
                onChange: ((String) -> Void)? = nil,
                onCommit: ((String, String) -> Void)? = nil,
                appearance: @escaping (ParsedLink.Target) -> LinkAppearance,
                onOpenLink: @escaping (URL) -> Void,
                suggestions: @escaping (String) -> [LinkSuggestion],
                candidates: @escaping (String) -> [LinkSuggestion] = { _ in [] }) {
        self.text = text; self.onChange = onChange; self.onCommit = onCommit
        self.appearance = appearance; self.onOpenLink = onOpenLink; self.suggestions = suggestions; self.candidates = candidates
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = WDTextView.scrollableTextView()
        let textView: WDTextView
        if let own = scroll.documentView as? WDTextView {
            textView = own
        } else {
            let tv = scroll.documentView as! NSTextView
            textView = WDTextView(frame: tv.frame, textContainer: tv.textContainer)
            scroll.documentView = textView
        }
        textView.coordinator = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.typingAttributes = MarkdownAttributes.base()
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        textView.drawsBackground = false
        context.coordinator.textView = textView
        context.coordinator.setText(text)
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.externalUpdate(text)
    }

    public static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.commitNow()
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: WDTextView?
        private var dirty = false
        private var session = UUID().uuidString
        private var timer: Timer?
        private var lastCommitted = ""
        private let picker = LinkPicker()

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func setText(_ text: String) {
            guard let tv = textView else { return }
            tv.string = text
            lastCommitted = text
            restyle()
        }

        func externalUpdate(_ text: String) {
            guard let tv = textView, tv.string != text else { return }
            let editing = tv.window?.firstResponder === tv
            if !dirty && !editing { setText(text) }
            else if !dirty && parent.onCommit == nil { setText(text) }   // binding mode: binding is the truth
        }

        func restyle() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let selection = tv.selectedRanges
            let runs = MarkdownStyler.runs(for: tv.string, appearance: parent.appearance)
            storage.beginEditing()
            MarkdownAttributes.apply(runs, to: storage)
            storage.endEditing()
            tv.needsDisplay = true
            tv.selectedRanges = selection
            tv.typingAttributes = MarkdownAttributes.base()
        }

        // MARK: Editing

        public func textDidBeginEditing(_ notification: Notification) { session = UUID().uuidString }

        public func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            restyle()
            dirty = true
            parent.onChange?(tv.string)
            scheduleCommit()
            updatePicker()
        }

        public func textDidEndEditing(_ notification: Notification) {
            picker.close()
            commitNow()
        }

        private func scheduleCommit() {
            guard parent.onCommit != nil else { return }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.commitNow() }
            }
        }

        func commitNow() {
            timer?.invalidate(); timer = nil
            guard let tv = textView, let commit = parent.onCommit else { dirty = false; return }
            let text = tv.string
            if text != lastCommitted { commit(text, session); lastCommitted = text }
            dirty = false
        }

        /// Writes a programmatic change through the text system (keeps undo and notifications).
        func replace(_ range: NSRange, with string: String) {
            guard let tv = textView, tv.shouldChangeText(in: range, replacementString: string) else { return }
            tv.textStorage?.replaceCharacters(in: range, with: string)
            tv.didChangeText()
        }

        // MARK: Caret skips collapsed link syntax

        public func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
            guard new.length == 0, let storage = textView.textStorage, new.location < storage.length else { return new }
            var effective = NSRange()
            guard storage.attribute(.wdHidden, at: new.location, effectiveRange: &effective) != nil, effective.location < new.location else { return new }
            // Moving forward → jump past the hidden range, otherwise to its start.
            return NSRange(location: new.location >= old.location ? NSMaxRange(effective) : effective.location, length: 0)
        }

        // MARK: Clicks

        func handleClick(at index: Int, command: Bool) -> Bool {
            guard let tv = textView, let storage = tv.textStorage, storage.length > 0 else { return false }
            for i in [index, index - 1] where i >= 0 && i < storage.length {
                var range = NSRange()
                if let checked = storage.attribute(.wdCheckbox, at: i, effectiveRange: &range) as? Bool {
                    replace(range, with: checked ? "[ ]" : "[x]")
                    return true
                }
                if command, let url = storage.attribute(.wdLink, at: i, effectiveRange: &range) as? String, let u = URL(string: url) {
                    // An ambiguous typed link: offer its candidates before creating a page (link-disambiguation K5).
                    if u.host == "missing", let link = LinkParser.links(in: tv.string).first(where: { NSLocationInRange(i, $0.range) }),
                       case .missing(let typed) = link.target {
                        let options = parent.candidates(typed)
                        if !options.isEmpty {
                            showCandidates(options, typed: typed, linkRange: link.range, url: u, at: i)
                            return true
                        }
                    }
                    commitNow()
                    parent.onOpenLink(u)
                    return true
                }
            }
            return false
        }

        private var candidateActions: [CandidateAction] = []

        /// A menu at the link with each candidate and "Create page …".
        private func showCandidates(_ options: [LinkSuggestion], typed: String, linkRange: NSRange, url: URL, at index: Int) {
            guard let tv = textView else { return }
            let menu = NSMenu()
            candidateActions = options.map { o in CandidateAction { [weak self] in self?.replace(linkRange, with: o.insert) } }
            for (o, action) in zip(options, candidateActions) {
                let item = NSMenuItem(title: o.title, action: #selector(CandidateAction.run), keyEquivalent: "")
                item.target = action
                item.image = NSImage(systemSymbolName: o.symbol, accessibilityDescription: nil)
                if !o.subtitle.isEmpty { item.toolTip = o.subtitle }
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let create = CandidateAction { [weak self] in self?.commitNow(); self?.parent.onOpenLink(url) }
            candidateActions.append(create)
            let item = NSMenuItem(title: "Create page “\(typed)”", action: #selector(CandidateAction.run), keyEquivalent: "")
            item.target = create
            menu.addItem(item)
            let rect = tv.segmentRects(for: NSRange(location: index, length: 1)).first ?? .zero
            menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY + 2), in: tv)
        }

        // MARK: `[[` picker

        /// Range of `[[query` directly before the caret, if any.
        private func pickerQuery() -> (range: NSRange, query: String)? {
            guard let tv = textView, tv.selectedRange().length == 0 else { return nil }
            let caret = tv.selectedRange().location
            let ns = tv.string as NSString
            let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
            let before = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
            guard let open = before.range(of: "[[", options: .backwards) else { return nil }
            let query = String(before[open.upperBound...])
            guard !query.contains("]"), !query.contains("[") else { return nil }
            let start = lineStart + (before.distance(from: before.startIndex, to: open.lowerBound))
            return (NSRange(location: start, length: caret - start), query)
        }

        private func updatePicker() {
            guard let tv = textView, let (range, query) = pickerQuery() else { picker.close(); return }
            var items = parent.suggestions(query)
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !items.contains(where: { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                items.append(LinkSuggestion(id: "new:" + trimmed, symbol: "plus.circle", title: "New page “\(trimmed)”",
                                            subtitle: "Creates the page when you open the link", insert: "[[\(trimmed)]]"))
            }
            picker.show(items, in: tv, at: range) { [weak self] chosen in
                guard let self, let current = self.pickerQuery() else { return }
                self.picker.close()
                self.replace(current.range, with: chosen.insert)
            }
        }

        public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard picker.isShown else { return false }
            switch selector {
            case #selector(NSResponder.moveDown(_:)): picker.move(1); return true
            case #selector(NSResponder.moveUp(_:)): picker.move(-1); return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): picker.choose(); return true
            case #selector(NSResponder.cancelOperation(_:)): picker.close(); return true
            default: return false
            }
        }
    }
}

/// Target-action wrapper for menu items built from closures.
final class CandidateAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}

/// Text view that routes clicks on checkboxes and ⌘-clicks on links to the coordinator,
/// and draws link icons and qualifiers into kerning-reserved space (link-disambiguation K3).
public final class WDTextView: NSTextView {
    weak var coordinator: MarkdownEditor.Coordinator?

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let storage = textStorage, storage.length > 0 else { return }
        storage.enumerateAttribute(.wdDecoration, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let deco = value as? LinkDecoration else { return }
            let rects = segmentRects(for: range)
            guard let first = rects.first, let last = rects.last else { return }
            let color = (storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor) ?? .secondaryLabelColor
            if let image = NSImage(systemSymbolName: deco.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: MarkdownAttributes.baseFont.pointSize - 2, weight: .regular)) {
                let size = image.size
                let tinted = NSImage(size: size, flipped: false) { r in
                    image.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true
                }
                tinted.draw(in: NSRect(x: first.minX - LinkDecoration.iconSpace + 2, y: first.midY - size.height / 2,
                                       width: size.width, height: size.height))
            }
            if let q = deco.qualifierText() {
                let attrs: [NSAttributedString.Key: Any] = [.font: LinkDecoration.qualifierFont, .foregroundColor: NSColor.secondaryLabelColor]
                let size = (q as NSString).size(withAttributes: attrs)
                (q as NSString).draw(at: NSPoint(x: last.maxX + 1, y: last.midY - size.height / 2), withAttributes: attrs)
            }
        }
    }

    /// Line-fragment rectangles of a character range, in view coordinates (TextKit 2, with a TextKit 1 fallback).
    func segmentRects(for range: NSRange) -> [CGRect] {
        let origin = textContainerOrigin
        if let tlm = textLayoutManager, let tcm = tlm.textContentManager,
           let start = tcm.location(tcm.documentRange.location, offsetBy: range.location),
           let end = tcm.location(start, offsetBy: range.length), let textRange = NSTextRange(location: start, end: end) {
            var rects: [CGRect] = []
            tlm.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
                rects.append(rect.offsetBy(dx: origin.x, dy: origin.y)); return true
            }
            return rects
        }
        guard let lm = layoutManager, let container = textContainer else { return [] }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rects: [CGRect] = []
        lm.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { r, _ in
            rects.append(r.offsetBy(dx: origin.x, dy: origin.y))
        }
        return rects
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if let coordinator, coordinator.handleClick(at: index, command: event.modifierFlags.contains(.command)) { return }
        super.mouseDown(with: event)
    }
}

// MARK: - Picker popover

@MainActor
@Observable
final class LinkPickerModel {
    var items: [LinkSuggestion] = []
    var selected = 0
    var onChoose: ((LinkSuggestion) -> Void)?
}

@MainActor
final class LinkPicker {
    private let model = LinkPickerModel()
    private var popover: NSPopover?
    var isShown: Bool { popover?.isShown ?? false }

    func show(_ items: [LinkSuggestion], in textView: NSTextView, at range: NSRange, onChoose: @escaping (LinkSuggestion) -> Void) {
        model.items = items
        model.selected = min(model.selected, max(0, items.count - 1))
        model.onChoose = onChoose
        guard !items.isEmpty else { close(); return }
        if popover == nil {
            let p = NSPopover()
            p.behavior = .semitransient
            p.animates = false
            p.contentViewController = NSHostingController(rootView: LinkPickerView(model: model))
            popover = p
        }
        guard let popover, !popover.isShown, let window = textView.window else { return }
        let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
        let rect = textView.convert(window.convertFromScreen(screenRect), from: nil)
        model.selected = 0
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
    }

    func move(_ delta: Int) {
        guard !model.items.isEmpty else { return }
        model.selected = (model.selected + delta + model.items.count) % model.items.count
    }

    func choose() {
        guard model.items.indices.contains(model.selected) else { return }
        model.onChoose?(model.items[model.selected])
    }

    func close() { popover?.close() }
}

struct LinkPickerView: View {
    let model: LinkPickerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.items.prefix(8).enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 8) {
                    Image(systemName: item.symbol).frame(width: 16).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).lineLimit(1)
                        if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(index == model.selected ? Color.accentColor.opacity(0.2) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { model.onChoose?(item) }
            }
        }
        .padding(4)
        .frame(width: 320)
    }
}
#endif
