import Foundation
import GRDB
import MCP
import XCTest
@testable import GlyCore
@testable import GlyMCP

/// specs/agent-access (pages, links, search, context, tag pages) through `GlyTools`.
final class PageToolTests: XCTestCase {
    var db: DatabaseQueue!
    var tools: GlyTools!

    override func setUpWithError() throws {
        db = try StoreFactory.openInMemory()
        tools = GlyTools(writer: db, calendar: FakeEventSource(), hiddenCalendarIDs: { [] }, deviceID: "mac-test01")
    }

    struct Outcome { let value: Value?; let isError: Bool; let text: String }
    func call(_ name: String, _ args: [String: Value] = [:]) async -> Outcome {
        let r = await tools.call(name, arguments: args, client: "claude-code")
        var text = ""
        if case .text(let t, _, _)? = r.content.first { text = t }
        return Outcome(value: r.structuredContent, isError: r.isError ?? false, text: text)
    }
    func field(_ v: Value?, _ k: String) -> Value? { if case .object(let o)? = v { return o[k] } else { return nil } }
    func str(_ v: Value?, _ k: String) -> String? { if case .string(let s)? = field(v, k) { return s } else { return nil } }
    func list(_ v: Value?, _ k: String) -> [Value] { if case .array(let a)? = field(v, k) { return a } else { return [] } }

    func testMeetingNotesFromAnAgent() async throws {
        let r = await call("create_page", ["title": "Atlas sync 2026-10-27", "text": "## Decisions\n- ship", "tags": ["project/atlas"]])
        XCTAssertFalse(r.isError, r.text)
        XCTAssertEqual(str(r.value, "text"), "## Decisions\n- ship")
        XCTAssertEqual(list(r.value, "tags"), ["project/atlas"])
        XCTAssertEqual(str(r.value, "modified_by"), "agent:claude-code@mac-test01")
        let id = str(r.value, "id")!
        let kind = try await db.read { try String.fetchOne($0, sql: "SELECT kind FROM items WHERE id = ?", arguments: [id]) }
        XCTAssertEqual(kind, "info")
    }

    func testPartialPageUpdate() async throws {
        let id = str(await call("create_page", ["title": "P", "text": "old", "tags": ["a/b"]]).value, "id")!
        let r = await call("update_page", ["id": .string(id), "text": "new"])
        XCTAssertEqual(str(r.value, "text"), "new")
        XCTAssertEqual(str(r.value, "title"), "P")
        XCTAssertEqual(list(r.value, "tags"), ["a/b"])
        let unknown = await call("update_page", ["id": "nope", "text": "x"])
        XCTAssertTrue(unknown.isError)
    }

    func testAgentLinksByTitleAndUnresolvedIsReported() async throws {
        let page = str(await call("create_page", ["title": "Atlas architecture"]).value, "id")!
        let t = await call("create_task", ["title": "T", "notes": "details in [[Atlas architecture]], plan in [[Atlas roadmap]]"])
        XCTAssertEqual(str(t.value, "notes"), "details in [Atlas architecture](gly://item/\(page)), plan in [[Atlas roadmap]]")
        XCTAssertEqual(list(t.value, "unresolved"), ["Atlas roadmap"])
    }

    func testTaskWithLinks() async throws {
        let target = str(await call("create_page", ["title": "Target"]).value, "id")!
        let task = str(await call("create_task", ["title": "T", "notes": "[[Target]]"]).value, "id")!
        _ = await call("create_page", ["title": "Linker", "text": "about [[T]]"])
        let r = await call("get_task", ["id": .string(task)])
        XCTAssertEqual(list(r.value, "links"), [.object(["id": .string(target), "kind": "page", "title": "Target", "state": "live",
                                                            "display": "Target", "tags": .array([])])])
        XCTAssertEqual(list(r.value, "backlinks").compactMap { str($0, "title") }, ["Linker"])
    }

    func testFindNotes() async throws {
        _ = await call("create_page", ["title": "Load test results", "text": "p95 is fine"])
        _ = await call("create_task", ["title": "Run load test"])
        let r = await call("search", ["query": "load test", "kind": "page"])
        XCTAssertEqual(list(r.value, "results").compactMap { str($0, "title") }, ["Load test results"])
        XCTAssertEqual(list(r.value, "results").compactMap { str($0, "kind") }, ["page"])
        let all = await call("search", ["query": "load"])
        XCTAssertEqual(list(all.value, "results").compactMap { str($0, "kind") }, ["page", "task"], "grouped by kind")
        let bad = await call("search", ["query": "x", "kind": "note"])
        XCTAssertTrue(bad.isError)
    }

    func testContextOfAPage() async throws {
        let task = str(await call("create_task", ["title": "Do it"]).value, "id")!
        let page = str(await call("create_page", ["title": "Hub", "text": "[[Do it]]"]).value, "id")!
        _ = await call("create_page", ["title": "One", "text": "[[Hub]]"])
        _ = await call("create_page", ["title": "Two", "text": "see [[Hub]]"])
        let r = await call("get_context", ["id": .string(page)])
        XCTAssertEqual(list(r.value, "links").compactMap { str($0, "id") }, [task])
        XCTAssertEqual(list(r.value, "backlinks").compactMap { str($0, "title") }, ["One", "Two"])
        let tag = await call("get_context", ["tag": "project/none"])
        XCTAssertFalse(tag.isError)
        XCTAssertEqual(list(tag.value, "tagged"), [])
    }

    func testDescribeAProjectAndReadTheTagPage() async throws {
        _ = await call("create_task", ["title": "Open", "tags": ["project/atlas"]])
        _ = await call("create_page", ["title": "Notes", "tags": ["project/atlas/logs"]])
        let r = await call("update_tag_page", ["name": "project/atlas", "text": "The **atlas** project"])
        XCTAssertFalse(r.isError, r.text)
        let page = await call("get_tag_page", ["name": "project/atlas"])
        XCTAssertEqual(str(page.value, "text"), "The **atlas** project")
        XCTAssertEqual(list(page.value, "open_tasks").compactMap { str($0, "title") }, ["Open"])
        XCTAssertEqual(list(page.value, "pages").compactMap { str($0, "title") }, ["Notes"])
    }

    func testDeletePage() async throws {
        let id = str(await call("create_page", ["title": "Gone"]).value, "id")!
        let r = await call("delete_page", ["id": .string(id)])
        XCTAssertEqual(r.value, .object(["deleted": .string(id)]))
        let again = await call("get_page", ["id": .string(id)])
        XCTAssertTrue(again.isError)
    }
}

extension PageToolTests {
    func testAmbiguousLinkWithCandidatesAndRetry() async throws {
        let alex = str(await call("create_page", ["title": "Goals", "tags": ["person/alex"]]).value, "id")!
        _ = await call("create_page", ["title": "Goals", "tags": ["person/sam"]])
        let r = await call("create_task", ["title": "T", "notes": "see [[Goals]]"])
        XCTAssertEqual(list(r.value, "unresolved"), ["Goals"])
        let candidates = list(list(r.value, "unresolved_links").first, "candidates")
        XCTAssertEqual(Set(candidates.compactMap { str($0, "display") }), ["Goals · person/alex", "Goals · person/sam"])
        let retry = await call("create_task", ["title": "T2", "notes": "see [[person/alex/Goals]]"])
        XCTAssertEqual(str(retry.value, "notes"), "see [Goals](gly://item/\(alex))")
        XCTAssertEqual(list(retry.value, "unresolved_links"), [])
    }

    func testTwoGoalsPagesDisplayNamesOnLinks() async throws {
        let alex = str(await call("create_page", ["title": "Goals", "tags": ["person/alex"]]).value, "id")!
        _ = await call("create_page", ["title": "Goals", "tags": ["person/sam"]])
        let hub = str(await call("create_page", ["title": "Hub", "text": "[[person/alex/Goals]]"]).value, "id")!
        let r = await call("get_page", ["id": .string(hub)])
        let link = list(r.value, "links").first
        XCTAssertEqual(str(link, "id"), alex)
        XCTAssertEqual(str(link, "display"), "Goals · person/alex")
        XCTAssertEqual(list(link, "tags"), ["person/alex"])
        let back = await call("get_page", ["id": .string(alex)])
        XCTAssertEqual(str(list(back.value, "backlinks").first, "display"), "Hub")
    }

    // MARK: tag-colors 2.1 (specs/agent-access "List tags", "Tag pages over MCP")

    func testTagsBelowAPrefixCarryColors() async throws {
        _ = await call("create_task", ["title": "A", "tags": ["person/alex"]])
        _ = await call("create_task", ["title": "B", "tags": ["person/sam"]])
        _ = await call("update_tag_page", ["name": "person", "color": "green"])
        let r = await call("list_tags", ["prefix": "person/"])
        let tags = list(r.value, "tags")
        XCTAssertEqual(tags.count, 2)
        for t in tags {
            XCTAssertEqual(field(t, "color"), .null, "no own color")
            XCTAssertEqual(str(t, "effective_color"), "green", "inherited from person")
        }
    }

    func testAgentColorsATagAndClearsIt() async throws {
        _ = await call("create_task", ["title": "A", "tags": ["project/atlas/logs"]])
        let r = await call("update_tag_page", ["name": "project/atlas", "color": "orange"])
        XCTAssertFalse(r.isError, r.text)
        XCTAssertEqual(str(r.value, "color"), "orange")
        XCTAssertEqual(str(r.value, "effective_color"), "orange")
        let sub = await call("get_tag_page", ["name": "project/atlas/logs"])
        XCTAssertEqual(str(sub.value, "effective_color"), "orange")
        XCTAssertEqual(str(sub.value, "text"), "", "description untouched")
        let cleared = await call("update_tag_page", ["name": "project/atlas", "color": "automatic"])
        XCTAssertEqual(field(cleared.value, "color"), .null)
    }

    func testUnknownColorIsRejected() async throws {
        let r = await call("update_tag_page", ["name": "x", "color": "chartreuse"])
        XCTAssertTrue(r.isError)
        XCTAssertTrue(r.text.contains("orange") && r.text.contains("automatic"), r.text)
        let none = await call("update_tag_page", ["name": "x"])
        XCTAssertTrue(none.isError, "text or color required")
    }

    // MARK: trash-bin 2.1 (specs/agent-access "Trash over MCP")

    func testAgentUndoesItsOwnDelete() async throws {
        let alex = str(await call("create_page", ["title": "Goals", "text": "grow", "tags": ["person/alex"]]).value, "id")!
        _ = await call("create_page", ["title": "Goals", "tags": ["person/bob"]])
        _ = await call("delete_page", ["id": .string(alex)])          // the wrong one
        let gone = await call("get_page", ["id": .string(alex)])
        XCTAssertTrue(gone.isError)
        XCTAssertTrue(gone.text.contains("in the trash"), gone.text)

        let trash = await call("list_trash")
        let entry = list(trash.value, "items").first
        XCTAssertEqual(str(entry, "id"), alex)
        XCTAssertEqual(str(entry, "kind"), "page")
        XCTAssertEqual(list(entry, "tags"), ["person/alex"])
        XCTAssertEqual(str(entry, "excerpt"), "grow")
        XCTAssertEqual(str(entry, "deleted_by"), "Claude Code")
        XCTAssertNil(field(trash.value, "older_count"))

        let r = await call("restore", ["id": .string(alex)])
        XCTAssertFalse(r.isError, r.text)
        XCTAssertEqual(str(r.value, "id"), alex)
        XCTAssertEqual(list(r.value, "tags"), ["person/alex"])
        XCTAssertEqual(str(r.value, "modified_by"), "agent:claude-code@mac-test01", "attributed to the agent")
        let after = await call("list_trash")
        XCTAssertEqual(list(after.value, "items"), [])
    }

    func testRestoreSomethingThatIsntDeleted() async throws {
        let live = str(await call("create_page", ["title": "Live"]).value, "id")!
        for id in [live, "nope"] {
            let r = await call("restore", ["id": .string(id)])
            XCTAssertTrue(r.isError)
            XCTAssertTrue(r.text.contains("not in the trash"), r.text)
        }
    }

    func testRestoreATaskReturnsItLikeGetTask() async throws {
        let id = str(await call("create_task", ["title": "Call", "tags": ["x"]]).value, "id")!
        _ = await call("delete_task", ["id": .string(id)])
        let gone = await call("get_task", ["id": .string(id)])
        XCTAssertTrue(gone.text.contains("in the trash"), gone.text)
        let r = await call("restore", ["id": .string(id)])
        XCTAssertEqual(str(r.value, "title"), "Call")
        XCTAssertEqual(str(r.value, "status"), "open")
    }

    func testDuplicateCreatePageNamesTheOthers() async throws {
        let alex = str(await call("create_page", ["title": "Profile", "tags": ["person/alex"]]).value, "id")!
        let r = await call("create_page", ["title": "profile", "tags": ["person/sam"]])
        XCTAssertFalse(r.isError, r.text)
        let same = list(r.value, "same_title")
        XCTAssertEqual(same.compactMap { str($0, "id") }, [alex])
        XCTAssertEqual(str(same.first, "display"), "Profile · person/alex")
    }
}
