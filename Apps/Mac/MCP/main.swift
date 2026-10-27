// gly-mcp: stdio MCP endpoint for clients like Claude Code (mcp-server design M1).
// A message pipe: every JSON-RPC line from stdin goes over XPC to glyAgent, which runs the MCP server;
// replies are written to stdout. The only state is the client name from `initialize` (for attribution).
import Foundation
import GlyCore

final class Pipe: @unchecked Sendable {
    private let lock = NSLock()
    private var clientName: String?
    let agent = AgentClient()

    var client: String? { lock.lock(); defer { lock.unlock() }; return clientName }

    func remember(clientFrom message: [String: Any]) {
        guard message["method"] as? String == "initialize",
              let params = message["params"] as? [String: Any],
              let info = params["clientInfo"] as? [String: Any], let name = info["name"] as? String else { return }
        lock.lock(); clientName = name; lock.unlock()
    }

    func write(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    func handle(_ line: String) async {
        let data = Data(line.utf8)
        let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let message { remember(clientFrom: message) }
        switch await agent.mcp(data, client: client) {
        case .success(let reply?): write(reply)
        case .success(nil): break
        case .failure(let failure):
            // Requests get a JSON-RPC error instead of hanging; notifications are dropped.
            guard let id = message?["id"] else { return }
            let error: [String: Any] = ["jsonrpc": "2.0", "id": id,
                                        "error": ["code": -32000, "message": "gly agent unavailable: \(failure.message). Open gly and check Settings → Agents."]]
            if let out = try? JSONSerialization.data(withJSONObject: error) { write(out) }
        }
    }
}

let pipe = Pipe()
let group = DispatchGroup()
while let line = readLine(strippingNewline: true) {
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
    group.enter()
    Task { await pipe.handle(line); group.leave() }
}
group.wait()
