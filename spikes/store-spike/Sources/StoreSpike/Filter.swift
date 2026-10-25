// Spike 2 (foundation-spikes): minimal filter language -> SQL. Throwaway code.
//
// Grammar (subset for the spike):
//   expr    := and ("OR" and)*
//   and     := unary ("AND" unary)*
//   unary   := "NOT" unary | "(" expr ")" | atom
//   atom    := kind | tagref | comparison
//   kind    := "task" | "info" | "event_note" | "local_event"
//   tagref  := "tag:" NAME | NAME "/*" | NAME          (NAME includes descendants "NAME/...")
//   comparison := IDENT OP VALUE        OP: = != < > <= >= ~ (contains)
//   VALUE   := "quoted" | number | yes | no | +30d | -7d | today | YYYY-MM-DD | bare word
// IDENT is a built-in field (status, priority, due, title, kind) or a property key.
import Foundation
import GRDB

public indirect enum FilterExpr: Equatable {
    case and(FilterExpr, FilterExpr)
    case or(FilterExpr, FilterExpr)
    case not(FilterExpr)
    case kind(String)
    case tag(String, prefixOnly: Bool)          // prefixOnly: "person/*" -> only descendants
    case compare(field: String, op: String, value: String)
}

public struct FilterError: Error, CustomStringConvertible {
    public let description: String
}

// MARK: - Tokenizer + parser

enum Tok: Equatable { case word(String), quoted(String), op(String), lparen, rparen }

func tokenize(_ s: String) throws -> [Tok] {
    var toks: [Tok] = []
    var i = s.startIndex
    while i < s.endIndex {
        let c = s[i]
        if c.isWhitespace { i = s.index(after: i); continue }
        if c == "(" { toks.append(.lparen); i = s.index(after: i); continue }
        if c == ")" { toks.append(.rparen); i = s.index(after: i); continue }
        if c == "\"" {
            var j = s.index(after: i)
            while j < s.endIndex, s[j] != "\"" { j = s.index(after: j) }
            guard j < s.endIndex else { throw FilterError(description: "unterminated quote") }
            toks.append(.quoted(String(s[s.index(after: i)..<j])))
            i = s.index(after: j); continue
        }
        if "=!<>~".contains(c) {
            var j = s.index(after: i)
            if j < s.endIndex, s[j] == "=" { j = s.index(after: j) }
            toks.append(.op(String(s[i..<j]))); i = j; continue
        }
        var j = i
        while j < s.endIndex, !s[j].isWhitespace, !"()=!<>~\"".contains(s[j]) { j = s.index(after: j) }
        toks.append(.word(String(s[i..<j]))); i = j
    }
    return toks
}

struct Parser {
    var toks: [Tok]
    var pos = 0
    static let kinds: Set = ["task", "info", "event_note", "local_event"]

    mutating func parse() throws -> FilterExpr {
        let e = try orExpr()
        guard pos == toks.count else { throw FilterError(description: "unexpected token \(toks[pos])") }
        return e
    }
    func peekWord(_ w: String) -> Bool { pos < toks.count && toks[pos] == .word(w) }
    mutating func orExpr() throws -> FilterExpr {
        var e = try andExpr()
        while peekWord("OR") { pos += 1; e = .or(e, try andExpr()) }
        return e
    }
    mutating func andExpr() throws -> FilterExpr {
        var e = try unary()
        while peekWord("AND") { pos += 1; e = .and(e, try unary()) }
        return e
    }
    mutating func unary() throws -> FilterExpr {
        guard pos < toks.count else { throw FilterError(description: "unexpected end") }
        if peekWord("NOT") { pos += 1; return .not(try unary()) }
        if toks[pos] == .lparen {
            pos += 1
            let e = try orExpr()
            guard pos < toks.count, toks[pos] == .rparen else { throw FilterError(description: "missing )") }
            pos += 1
            return e
        }
        guard case .word(let w) = toks[pos] else { throw FilterError(description: "unexpected \(toks[pos])") }
        pos += 1
        if pos < toks.count, case .op(let op) = toks[pos] {
            pos += 1
            guard pos < toks.count else { throw FilterError(description: "missing value after \(op)") }
            let v: String
            switch toks[pos] {
            case .word(let x), .quoted(let x): v = x
            default: throw FilterError(description: "bad value after \(op)")
            }
            pos += 1
            return .compare(field: w, op: op, value: v)
        }
        if Parser.kinds.contains(w) { return .kind(w) }
        if w.hasPrefix("tag:") { return .tag(String(w.dropFirst(4)), prefixOnly: false) }
        if w.hasSuffix("/*") { return .tag(String(w.dropLast(2)), prefixOnly: true) }
        return .tag(w, prefixOnly: false)
    }
}

public func parseFilter(_ s: String) throws -> FilterExpr {
    var p = Parser(toks: try tokenize(s))
    return try p.parse()
}

// MARK: - Compiler

public struct CompiledFilter {
    public let sql: String
    public let arguments: StatementArguments
}

let builtinFields: Set = ["status", "priority", "due", "title", "kind", "snoozed_until", "start_at"]
let priorityRank = "CASE i.priority WHEN 'none' THEN 0 WHEN 'low' THEN 1 WHEN 'normal' THEN 2 WHEN 'high' THEN 3 WHEN 'urgent' THEN 4 END"
let priorityValues = ["none": 0, "low": 1, "normal": 2, "high": 3, "urgent": 4]

func sqlOp(_ op: String) throws -> String {
    switch op {
    case "=": return "="
    case "!=": return "!="
    case "<", ">", "<=", ">=": return op
    default: throw FilterError(description: "unsupported operator \(op)")
    }
}

/// "+30d", "-7d", "+2w", "today", "2026-12-15" -> Date
func parseDate(_ v: String, now: Date) -> Date? {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: now)
    if v == "today" { return today }
    if let unit = v.last, "dwm".contains(unit), let n = Int(v.dropLast()) {
        switch unit {
        case "d": return cal.date(byAdding: .day, value: n, to: today)
        case "w": return cal.date(byAdding: .day, value: 7 * n, to: today)
        default: return cal.date(byAdding: .month, value: n, to: today)
        }
    }
    let f = DateFormatter()
    f.calendar = cal
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: v)
}

public func compileFilter(_ e: FilterExpr, in db: Database, now: Date = Date()) throws -> CompiledFilter {
    var args: [DatabaseValueConvertible?] = []
    // Resolve property keys at compile time so value lookups hit (key_id, value) indexes directly.
    var keyTypes: [String: (id: String, type: String)] = [:]
    for row in try Row.fetchAll(db, sql: "SELECT id, name, type FROM live_property_keys") {
        keyTypes[row["name"]] = (row["id"], row["type"])
    }

    func tagMatch(_ name: String, prefixOnly: Bool) -> String {
        let like = name.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "/%"
        let cond: String
        if prefixOnly {
            cond = "t.name LIKE ? ESCAPE '\\'"
            args.append(like)
        } else {
            cond = "(t.name = ? OR t.name LIKE ? ESCAPE '\\')"
            args.append(name); args.append(like)
        }
        // Uncorrelated IN: the matching item set is computed once, not per item (see Spike 2 findings).
        return "i.id IN (SELECT it.item_id FROM live_item_tags it JOIN live_tags t ON t.id = it.tag_id WHERE \(cond))"
    }

    func value(_ v: String, type: String) throws -> DatabaseValueConvertible {
        switch type {
        case "number":
            guard let d = Double(v) else { throw FilterError(description: "not a number: \(v)") }
            return d
        case "date":
            guard let d = parseDate(v, now: now) else { throw FilterError(description: "not a date: \(v)") }
            return d
        case "bool":
            return ["yes", "true", "1"].contains(v.lowercased())
        default:
            return v
        }
    }

    func comp(_ field: String, _ op: String, _ v: String) throws -> String {
        if builtinFields.contains(field) {
            if field == "priority", let rank = priorityValues[v], op != "~" {
                args.append(rank)
                return "\(priorityRank) \(try sqlOp(op)) ?"
            }
            let isDate = ["due", "snoozed_until", "start_at"].contains(field)
            if op == "~" { args.append("%\(v)%"); return "i.\(field) LIKE ?" }
            args.append(try value(v, type: isDate ? "date" : "text"))
            return "i.\(field) \(try sqlOp(op)) ?"
        }
        guard let (keyId, type) = keyTypes[field] else { throw FilterError(description: "unknown field or property \(field)") }
        let col: String
        switch type {
        case "number": col = "pv.number_value"
        case "date": col = "pv.date_value"
        case "bool": col = "pv.bool_value"
        case "link": col = "pv.ref_value"
        default: col = "pv.text_value"
        }
        args.append(keyId)
        var cond: String
        if op == "~" || type == "list" {
            // list = JSON array in text_value; "~" and "=" both mean "contains"
            cond = "\(col) LIKE ?"
            args.append(type == "list" ? "%\"\(v)\"%" : "%\(v)%")
            if op == "!=" { cond = "NOT (\(cond))" }
        } else {
            cond = "\(col) \(try sqlOp(op)) ?"
            args.append(try value(v, type: type))
        }
        // Uncorrelated IN over (key_id, value) index instead of a correlated EXISTS per item.
        return "i.id IN (SELECT pv.owner_id FROM live_property_values pv WHERE pv.key_id = ? AND \(cond))"
    }

    func go(_ e: FilterExpr) throws -> String {
        switch e {
        case .and(let a, let b): return "(\(try go(a)) AND \(try go(b)))"
        case .or(let a, let b): return "(\(try go(a)) OR \(try go(b)))"
        case .not(let a): return "NOT \(try go(a))"
        case .kind(let k): args.append(k); return "i.kind = ?"
        case .tag(let n, let p): return tagMatch(n, prefixOnly: p)
        case .compare(let f, let op, let v): return try comp(f, op, v)
        }
    }

    let whereSQL = try go(e)
    return CompiledFilter(sql: "SELECT i.* FROM live_items i WHERE \(whereSQL)", arguments: StatementArguments(args))
}

extension Database {
    public func query(_ filter: String, now: Date = Date()) throws -> [Row] {
        let c = try compileFilter(try parseFilter(filter), in: self, now: now)
        return try Row.fetchAll(self, sql: c.sql, arguments: c.arguments)
    }
}
