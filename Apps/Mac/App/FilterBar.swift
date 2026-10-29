import SwiftUI
import GlyCore

/// The browser's filter bar (specs/item-browser "Filter bar", item-browser I4): the query's filters as chips with ✕,
/// a field for typed tokens and text, suggestions for the token being typed, and an add-filter menu.
/// It edits the `ItemQuery`, never a string: a completed token becomes a chip, other words are the text.
struct FilterBar: View {
    @Environment(TasksModel.self) private var tasks
    @Environment(WikiModel.self) private var wiki
    @Binding var query: ItemQuery
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(query.tokens, id: \.self) { token in
                        FilterChip(token: token) { query.remove(token) }
                    }
                    TextField(query.tokens.isEmpty ? "Filter: is:task #tag due:week, or words to search" : "Add filter or search",
                              text: $input)
                        .textFieldStyle(.plain).frame(minWidth: 180)
                        .focused($focused)
                        .onSubmit { commit(all: true) }
                        .onKeyPress(.delete) {
                            // Backspace in an empty field removes the last chip.
                            guard input.isEmpty, let last = query.tokens.last else { return .ignored }
                            query.remove(last); return .handled
                        }
                }
                addMenu
            }
            if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { complete(with: s) }.buttonStyle(.borderless).font(.callout)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .onAppear { input = query.text }
        .onChange(of: input) { _, new in
            if new.last?.isWhitespace == true { commit(all: false) } else { applyText() }
        }
        .onChange(of: query.text) { _, new in
            // The text changed from outside (reset, ⌘K "Show all results"): show it.
            if new != textPart(input) { input = new }
        }
    }

    // MARK: Typing

    private var lastWord: String { input.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? "" }
    private var lastWordInProgress: Bool { input.last?.isWhitespace != true && (lastWord.hasPrefix("#") || lastWord.hasPrefix("-#") || lastWord.contains(":")) }

    /// The words that are search text: complete tokens are left out, and so is a token still being typed.
    private func textPart(_ s: String) -> String {
        var words = s.split(whereSeparator: \.isWhitespace).map(String.init)
        if s.last?.isWhitespace != true, let last = words.last, last.hasPrefix("#") || last.hasPrefix("-#") || last.contains(":") { words.removeLast() }
        return ItemQuery.parse(words.joined(separator: " ")).text
    }

    private func applyText() { let t = textPart(input); if query.text != t { query.text = t } }

    /// Turns complete tokens into chips; with `all`, also a last token without a following space (Return).
    private func commit(all: Bool) {
        let parsed = ItemQuery.parse(input)
        for token in parsed.tokens { query.add(token) }
        query.text = parsed.text
        input = parsed.text.isEmpty ? "" : parsed.text + (all ? "" : " ")
    }

    private func complete(with token: String) {
        var words = input.split(whereSeparator: \.isWhitespace).map(String.init)
        if !words.isEmpty, lastWordInProgress { words.removeLast() }
        input = (words + [token]).joined(separator: " ") + " "
        focused = true
    }

    /// Values for the token being typed: tags after `#`/`-#`, kinds after `is:`, and so on.
    private var suggestions: [String] {
        guard lastWordInProgress else { return [] }
        let w = lastWord.lowercased()
        if w.hasPrefix("#") || w.hasPrefix("-#") {
            let prefix = w.hasPrefix("-#") ? "-#" : "#", typed = String(w.dropFirst(prefix.count))
            return tasks.allTagNames().filter { $0.lowercased().contains(typed) }.prefix(8).map { prefix + $0 }
        }
        guard let colon = w.firstIndex(of: ":") else { return [] }
        let key = String(w[..<colon]), typed = String(w[w.index(after: colon)...])
        let values: [String] = switch key {
        case "is": ItemKind.allCases.map(\.rawValue)
        case "status": TaskStatus.allCases.map(\.rawValue)
        case "due": ItemQuery.Due.allCases.map(\.rawValue)
        case "prio", "priority": Priority.allCases.map(\.rawValue)
        case "effort": Effort.allCases.map(\.rawValue)
        case "changed": ItemQuery.Changed.allCases.map(\.rawValue)
        case "by": ItemQuery.Author.allCases.map(\.rawValue)
        case "host": Array(Set(wiki.bookmarks.map(\.host))).sorted()
        default: []
        }
        return values.filter { $0.lowercased().hasPrefix(typed) }.map { "\(key):\($0)" }
    }

    // MARK: Add-filter menu

    private var addMenu: some View {
        Menu {
            Menu("Kind") { ForEach(ItemKind.allCases, id: \.self) { k in option(.kind(k)) } }
            Menu("Tag") { ForEach(tasks.allTagNames(), id: \.self) { t in option(.tag(t)) } }
            Menu("Exclude Tag") { ForEach(tasks.allTagNames(), id: \.self) { t in option(.excludedTag(t)) } }
            option(.untagged)
            Divider()
            Menu("Status") { ForEach(TaskStatus.allCases, id: \.self) { s in option(.status(s)) } }
            Menu("Due") { ForEach(ItemQuery.Due.allCases, id: \.self) { d in option(.due(d)) } }
            Menu("Priority") { ForEach(Priority.allCases.reversed(), id: \.self) { p in option(.priority(p)) } }
            Menu("Effort") { ForEach(Effort.allCases, id: \.self) { e in option(.effort(e)) } }
            Divider()
            Menu("Changed") { ForEach(ItemQuery.Changed.allCases, id: \.self) { c in option(.changed(c)) } }
            Menu("Changed By") { ForEach(ItemQuery.Author.allCases, id: \.self) { a in option(.author(a)) } }
            let hosts = Array(Set(wiki.bookmarks.map(\.host))).sorted()
            if !hosts.isEmpty { Menu("Host") { ForEach(hosts, id: \.self) { h in option(.host(h)) } } }
        } label: { Image(systemName: "plus.circle") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Add a filter")
    }

    private func option(_ token: ItemQuery.Token) -> some View {
        Button(FilterChip.label(token)) { query.add(token) }.disabled(query.tokens.contains(token))
    }
}

/// One filter as a chip; ✕ removes it.
struct FilterChip: View {
    let token: ItemQuery.Token
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Text(Self.label(token)).lineLimit(1)
            Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                .buttonStyle(.plain).opacity(hovering ? 1 : 0.5).help("Remove filter")
        }
        .font(.callout)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Self.tint(token).opacity(0.15), in: Capsule())
        .foregroundStyle(Self.tint(token))
        .onHover { hovering = $0 }
        .help(token.text)
    }

    static func label(_ token: ItemQuery.Token) -> String {
        switch token {
        case .kind(let k): ["task": "Tasks", "page": "Pages", "bookmark": "Bookmarks", "meeting": "Meetings"][k.rawValue] ?? k.rawValue
        case .tag(let t): "#" + t
        case .excludedTag(let t): "not #" + t
        case .untagged: "Untagged"
        case .status(let s): s.rawValue.capitalized
        case .due(let d): "Due: " + ["overdue": "overdue", "today": "today", "week": "this week", "none": "no date"][d.rawValue]!
        case .priority(let p): "Priority: " + p.rawValue
        case .effort(let e): "Effort: " + e.rawValue
        case .changed(let c): "Changed: " + ["today": "today", "7d": "last 7 days", "30d": "last 30 days"][c.rawValue]!
        case .author(let a): a == .agent ? "By an agent" : "By me"
        case .host(let h): h
        }
    }

    static func tint(_ token: ItemQuery.Token) -> Color {
        switch token {
        case .tag, .untagged: .accentColor
        case .excludedTag: .secondary
        case .due: .orange
        default: .primary
        }
    }
}
