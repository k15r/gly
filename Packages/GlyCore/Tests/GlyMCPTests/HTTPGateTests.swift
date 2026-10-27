import Foundation
import XCTest
@testable import GlyMCP

final class HTTPGateTests: XCTestCase {
    let gate = HTTPGate(token: "secret-token", allowedOrigins: ["https://allowed.example/"])

    func req(_ method: String = "POST", _ target: String, _ headers: [String: String] = [:]) -> WireRequest {
        WireRequest(method: method, target: target, headers: headers, body: Data())
    }

    func testTokenInPathOrBearer() {
        XCTAssertEqual(gate.decide(req("POST", "/mcp/secret-token")), .allow(responseHeaders: [:]))
        XCTAssertEqual(gate.decide(req("POST", "/mcp", ["authorization": "Bearer secret-token"])), .allow(responseHeaders: [:]))
    }

    func testWrongToken() {
        XCTAssertEqual(gate.decide(req("POST", "/mcp/old-token")), .respond(status: 401, headers: [:]))
        XCTAssertEqual(gate.decide(req("POST", "/mcp")), .respond(status: 401, headers: [:]))
        XCTAssertEqual(gate.decide(req("POST", "/mcp", ["authorization": "Bearer secret-tokenX"])), .respond(status: 401, headers: [:]))
    }

    func testUnknownPathAndMethod() {
        XCTAssertEqual(gate.decide(req("POST", "/other")), .respond(status: 404, headers: [:]))
        XCTAssertEqual(gate.decide(req("POST", "/mcp/a/b")), .respond(status: 404, headers: [:]))
        XCTAssertEqual(gate.decide(req("GET", "/mcp/secret-token")), .respond(status: 405, headers: ["Allow": "POST"]))
    }

    func testOriginPolicy() {
        XCTAssertEqual(gate.decide(req("POST", "/mcp/secret-token", ["origin": "https://evil.example"])), .respond(status: 403, headers: [:]),
                       "blocked origin is rejected even with the right token")
        XCTAssertEqual(gate.decide(req("POST", "/mcp/secret-token", ["origin": "https://allowed.example"])),
                       .allow(responseHeaders: ["Access-Control-Allow-Origin": "https://allowed.example", "Vary": "Origin"]))
    }

    func testPreflightOnlyForAllowedOrigins() {
        guard case .respond(204, let headers) = gate.decide(req("OPTIONS", "/mcp/secret-token", ["origin": "https://allowed.example"])) else { return XCTFail() }
        XCTAssertEqual(headers["Access-Control-Allow-Origin"], "https://allowed.example")
        XCTAssertNotNil(headers["Access-Control-Allow-Methods"])
        XCTAssertEqual(gate.decide(req("OPTIONS", "/mcp/secret-token", ["origin": "https://evil.example"])), .respond(status: 403, headers: [:]))
        XCTAssertEqual(gate.decide(req("OPTIONS", "/mcp/secret-token")), .respond(status: 405, headers: [:]))
    }

    func testConstantTimeCompare() {
        XCTAssertTrue(HTTPGate.constantTimeEqual("abc", "abc"))
        XCTAssertFalse(HTTPGate.constantTimeEqual("abc", "abd"))
        XCTAssertFalse(HTTPGate.constantTimeEqual("abc", "abcd"))
        XCTAssertFalse(HTTPGate.constantTimeEqual("", "a"))
    }
}
