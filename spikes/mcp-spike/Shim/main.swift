// Spike 3 (foundation-spikes): stdio MCP shim -> XPC -> WorkDash agent. Stateless. Throwaway code.
// Modes:  wd-mcp --ping | wd-mcp --schedule YYYY-MM-DD | wd-mcp   (MCP stdio server)
import Foundation
import MCP

enum AgentError: Error, CustomStringConvertible {
    case xpc(String), timeout
    var description: String {
        switch self {
        case .xpc(let m): return "WorkDash agent not reachable: \(m). Is WorkDash running and its agent enabled (System Settings → Login Items)?"
        case .timeout: return "WorkDash agent did not answer within 5 s"
        }
    }
}

/// One XPC round trip with timeout; errors become a clear message instead of a hang.
func callAgent(_ body: @escaping (AgentXPC, @escaping (String) -> Void) -> Void) async throws -> String {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
        let c = NSXPCConnection(machServiceName: agentMachServiceName)
        c.remoteObjectInterface = NSXPCInterface(with: AgentXPC.self)
        c.setCodeSigningRequirement(teamCodeRequirement)    // only talk to our own agent
        let lock = NSLock(); var done = false
        func finish(_ r: Result<String, Error>) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }; done = true
            c.invalidate(); cont.resume(with: r)
        }
        c.resume()
        let proxy = c.remoteObjectProxyWithErrorHandler { e in finish(.failure(AgentError.xpc(e.localizedDescription))) } as! AgentXPC
        body(proxy) { finish(.success($0)) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { finish(.failure(AgentError.timeout)) }
    }
}

let args = CommandLine.arguments
if args.count > 1 {
    // Direct client modes for task 4.1 verification. Top-level code is async: await directly
    // (a semaphore here would block the main actor and deadlock the Task).
    do {
        if args[1] == "--ping" { print(try await callAgent { p, r in p.ping(reply: r) }) }
        else if args[1] == "--schedule", args.count > 2 { let d = args[2]; print(try await callAgent { p, r in p.getSchedule(d, reply: r) }) }
        else { print("usage: wd-mcp [--ping | --schedule YYYY-MM-DD]"); exit(64) }
        exit(0)
    } catch {
        FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

let server = Server(name: "workdash", version: "0.1.0-spike", capabilities: .init(tools: .init(listChanged: false)))

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: [
        Tool(name: "get_schedule",
             description: "Appointments for one day from all WorkDash calendar sources, with the user's tags. Date format YYYY-MM-DD; defaults to today.",
             inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["date": .object(["type": .string("string"), "description": .string("YYYY-MM-DD")])]),
             ])),
    ])
}

await server.withMethodHandler(CallTool.self) { params in
    guard params.name == "get_schedule" else {
        return CallTool.Result(content: [.text("unknown tool \(params.name)")], isError: true)
    }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    let date = params.arguments?["date"]?.stringValue ?? f.string(from: Date())
    do {
        let json = try await callAgent { p, r in p.getSchedule(date, reply: r) }
        return CallTool.Result(content: [.text(json)], isError: false)
    } catch {
        return CallTool.Result(content: [.text("\(error)")], isError: true)
    }
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
