import Foundation
import XCTest
@testable import GlyMCP

final class HTTPWireTests: XCTestCase {
    func parse(_ chunks: [String]) -> HTTPRequestParser.Outcome {
        var p = HTTPRequestParser()
        var last = HTTPRequestParser.Outcome.incomplete
        for c in chunks { last = p.append(Data(c.utf8)) }
        return last
    }

    func testPostWithBody() {
        let r = parse(["POST /mcp/abc HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"])
        XCTAssertEqual(r, .request(WireRequest(method: "POST", target: "/mcp/abc", headers: ["host": "127.0.0.1", "content-type": "application/json", "content-length": "2"], body: Data("{}".utf8))))
    }

    func testSplitReads() {
        XCTAssertEqual(parse(["POST /mcp HTTP/1.1\r\nContent-Le"]), .incomplete)
        let r = parse(["POST /mcp HTTP/1.1\r\nContent-Le", "ngth: 4\r\n\r\n{\"a", "\"}"])
        guard case .request(let req) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(String(decoding: req.body, as: UTF8.self), #"{"a""#, "exactly Content-Length bytes")
    }

    func testIncompleteBodyWaits() {
        XCTAssertEqual(parse(["POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}"]), .incomplete)
    }

    func testMalformedRequests() {
        XCTAssertEqual(parse(["GARBAGE\r\n\r\n"]), .error(400))
        XCTAssertEqual(parse(["POST mcp HTTP/1.1\r\nContent-Length: 0\r\n\r\n"]), .error(400), "target must start with /")
        XCTAssertEqual(parse(["POST /mcp HTTP/1.1\r\nNoColonHere\r\n\r\n"]), .error(400))
        XCTAssertEqual(parse(["POST /mcp HTTP/1.1\r\nContent-Length: -1\r\n\r\n"]), .error(400))
        XCTAssertEqual(parse(["POST /mcp HTTP/1.1\r\nContent-Length: abc\r\n\r\n"]), .error(400))
    }

    func testMissingAndOversizedLength() {
        XCTAssertEqual(parse(["POST /mcp HTTP/1.1\r\n\r\n"]), .error(411))
        XCTAssertEqual(parse(["POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"]), .error(411))
        XCTAssertEqual(parse(["POST /mcp HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n"]), .error(413))
        XCTAssertEqual(parse([String(repeating: "x", count: 20_000)]), .error(431))
    }

    func testGetAndOptionsNeedNoBody() {
        guard case .request(let r) = parse(["OPTIONS /mcp/t HTTP/1.1\r\nOrigin: https://a.example\r\n\r\n"]) else { return XCTFail() }
        XCTAssertEqual(r.method, "OPTIONS")
        XCTAssertEqual(r.headers["origin"], "https://a.example")
    }

    func testResponseSerialization() {
        let d = HTTPResponseWriter.data(status: 401, headers: [:], body: Data("{}".utf8))
        let s = String(decoding: d, as: UTF8.self)
        XCTAssertTrue(s.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        XCTAssertTrue(s.contains("Content-Length: 2\r\n"))
        XCTAssertTrue(s.contains("Connection: close\r\n"))
        XCTAssertTrue(s.hasSuffix("\r\n\r\n{}"))
    }
}
