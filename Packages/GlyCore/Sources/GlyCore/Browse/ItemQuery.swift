import Foundation

/// The kinds of items the browser lists (specs/item-browser), with their `items.kind` values.
public enum ItemKind: String, Codable, CaseIterable, Comparable, Sendable {
    case task, page, bookmark, meeting

    public var storedKind: String {
        switch self { case .task: "task"; case .page: "info"; case .bookmark: "bookmark"; case .meeting: "event_note" }
    }

    public init?(storedKind: String) {
        guard let k = Self.allCases.first(where: { $0.storedKind == storedKind }) else { return nil }
        self = k
    }

    public var linkKind: LinkRef.Kind {
        switch self { case .task: .task; case .page: .page; case .bookmark: .bookmark; case .meeting: .meeting }
    }

    public static func < (a: ItemKind, b: ItemKind) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
}

/// What a browser view shows (item-browser I1): plain data with a text form (`is:task #project/atlas due:week review`).
/// All conditions are combined with AND; several tags must all match, each including the tags below it.
public struct ItemQuery: Equatable, Hashable, Codable, Sendable {
    public enum Due: String, Codable, CaseIterable, Sendable { case overdue, today, week, none }
    public enum Changed: String, Codable, CaseIterable, Sendable { case today, days7 = "7d", days30 = "30d" }
    public enum Author: String, Codable, CaseIterable, Sendable { case me, agent }

    public var kinds: Set<ItemKind> = []
    /// Display names; identity is the case-folded key (`TagName.key`).
    public var tags: [String] = []
    public var excludedTags: [String] = []
    public var untagged = false
    /// Task statuses; other kinds aren't affected.
    public var statuses: Set<TaskStatus> = []
    public var due: Due?
    public var priorities: Set<Priority> = []
    public var efforts: Set<Effort> = []
    public var changed: Changed?
    public var author: Author?
    /// Bookmark hosts (lowercased); a host includes its subdomains.
    public var hosts: [String] = []
    /// Words searched in titles and texts (full-text).
    public var text = ""

    public init() {}

    public var isEmpty: Bool { self == ItemQuery() }

    /// One filter of the query, as a chip in the filter bar (item-browser I4).
    public enum Token: Hashable, Sendable {
        case kind(ItemKind), tag(String), excludedTag(String), untagged, status(TaskStatus), due(Due)
        case priority(Priority), effort(Effort), changed(Changed), author(Author), host(String)

        /// The typed form, e.g. `is:task`, `#project/atlas`, `-#ops`, `due:week`.
        public var text: String {
            switch self {
            case .kind(let k): "is:\(k.rawValue)"
            case .tag(let t): "#\(t)"
            case .excludedTag(let t): "-#\(t)"
            case .untagged: "untagged"
            case .status(let s): "status:\(s.rawValue)"
            case .due(let d): "due:\(d.rawValue)"
            case .priority(let p): "prio:\(p.rawValue)"
            case .effort(let e): "effort:\(e.rawValue)"
            case .changed(let c): "changed:\(c.rawValue)"
            case .author(let a): "by:\(a.rawValue)"
            case .host(let h): "host:\(h)"
            }
        }

        /// The token a typed word stands for; nil for a plain word (text).
        public static func parse(_ word: String) -> Token? {
            let lower = word.lowercased()
            if lower == "untagged" { return .untagged }
            if word.hasPrefix("-#"), let t = try? TagName(String(word.dropFirst(2))) { return .excludedTag(t.display) }
            if word.hasPrefix("#"), word.count > 1, let t = try? TagName(String(word.dropFirst())) { return .tag(t.display) }
            guard let colon = lower.firstIndex(of: ":") else { return nil }
            let key = String(lower[..<colon]), value = String(lower[lower.index(after: colon)...])
            guard !value.isEmpty else { return nil }
            switch key {
            case "is": return ItemKind(rawValue: value).map(Token.kind)
            case "status": return TaskStatus(rawValue: value).map(Token.status)
            case "due": return Due(rawValue: value).map(Token.due)
            case "prio", "priority": return Priority(rawValue: value).map(Token.priority)
            case "effort": return Effort(rawValue: value.uppercased()).map(Token.effort)
            case "changed": return Changed(rawValue: value).map(Token.changed)
            case "by": return Author(rawValue: value).map(Token.author)
            case "host": return value.contains(".") ? .host(value) : nil
            default: return nil
            }
        }
    }

    /// The filters in canonical order (kinds, tags, exclusions, untagged, status, due, priority, effort, changed, author, hosts).
    public var tokens: [Token] {
        var t: [Token] = ItemKind.allCases.filter(kinds.contains).map(Token.kind)
        t += tags.map(Token.tag) + excludedTags.map(Token.excludedTag)
        if untagged { t.append(.untagged) }
        t += TaskStatus.allCases.filter(statuses.contains).map(Token.status)
        if let due { t.append(.due(due)) }
        t += Priority.allCases.filter(priorities.contains).map(Token.priority)
        t += Effort.allCases.filter(efforts.contains).map(Token.effort)
        if let changed { t.append(.changed(changed)) }
        if let author { t.append(.author(author)) }
        t += hosts.map(Token.host)
        return t
    }

    /// Adds a filter; single-valued ones (due, changed, author) replace the previous value. A tag also leaves the
    /// exclusions (and the other way round), so a query never asks for both.
    public mutating func add(_ token: Token) {
        func key(_ s: String) -> String { TagName.key(for: s) }
        switch token {
        case .kind(let k): kinds.insert(k)
        case .tag(let s):
            excludedTags.removeAll { key($0) == key(s) }
            if !tags.contains(where: { key($0) == key(s) }) { tags.append(s) }
        case .excludedTag(let s):
            tags.removeAll { key($0) == key(s) }
            if !excludedTags.contains(where: { key($0) == key(s) }) { excludedTags.append(s) }
        case .untagged: untagged = true
        case .status(let s): statuses.insert(s)
        case .due(let d): due = d
        case .priority(let p): priorities.insert(p)
        case .effort(let e): efforts.insert(e)
        case .changed(let c): changed = c
        case .author(let a): author = a
        case .host(let h): if !hosts.contains(h) { hosts.append(h) }
        }
    }

    public mutating func remove(_ token: Token) {
        func key(_ s: String) -> String { TagName.key(for: s) }
        switch token {
        case .kind(let k): kinds.remove(k)
        case .tag(let s): tags.removeAll { key($0) == key(s) }
        case .excludedTag(let s): excludedTags.removeAll { key($0) == key(s) }
        case .untagged: untagged = false
        case .status(let s): statuses.remove(s)
        case .due: due = nil
        case .priority(let p): priorities.remove(p)
        case .effort(let e): efforts.remove(e)
        case .changed: changed = nil
        case .author: author = nil
        case .host(let h): hosts.removeAll { $0 == h }
        }
    }

    public func adding(_ token: Token) -> ItemQuery { var q = self; q.add(token); return q }
    public func removing(_ token: Token) -> ItemQuery { var q = self; q.remove(token); return q }

    /// The same query without tag conditions (tags, exclusions, untagged): the base of the tag tree's counts (I2).
    public func droppingTags() -> ItemQuery { var q = self; q.tags = []; q.excludedTags = []; q.untagged = false; return q }

    /// Reads typed text; words that aren't tokens are the text, in their order.
    public static func parse(_ input: String) -> ItemQuery {
        var q = ItemQuery()
        var words: [String] = []
        for word in input.split(whereSeparator: \.isWhitespace).map(String.init) {
            // `status:open,snoozed` is two tokens.
            let parts = word.contains(":") && word.contains(",") ? Self.expand(word) : [word]
            let tokens = parts.compactMap(Token.parse)
            if tokens.count == parts.count { tokens.forEach { q.add($0) } } else { words.append(word) }
        }
        q.text = words.joined(separator: " ")
        return q
    }

    private static func expand(_ word: String) -> [String] {
        guard let colon = word.firstIndex(of: ":") else { return [word] }
        let key = word[..<colon]
        return word[word.index(after: colon)...].split(separator: ",").map { "\(key):\($0)" }
    }

    /// The canonical text form; `parse(description) == self`.
    public var description: String {
        (tokens.map(\.text) + (text.isEmpty ? [] : [text])).joined(separator: " ")
    }
}

extension ItemQuery: CustomStringConvertible {}
