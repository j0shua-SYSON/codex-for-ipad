import Foundation

/// Real Foundation WebSocket client against a loopback protocol fixture.
/// This tests transport behavior, not upstream Codex or model inference.
@main
@MainActor
struct RPCRegression {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        print("PASS: \(message)")
    }

    static func main() async throws {
        let rpc = CodexRPCClient(endpoint: URL(string: CommandLine.arguments[1])!)
        try await rpc.connect()
        check(rpc.state == .connected, "Foundation WebSocket initializes the production RPC client")
        let value: JSONValue = .object(["text": .string("Unicode: 한글 🧪\nsecond line")])
        let echoed = try await rpc.request(method: "probe/echo", params: value)
        check(echoed == value, "RPC JSON round trips Unicode and multiline content")

        var notificationSeen = false
        var requestSeen = false
        var reply: Task<Void, Error>?
        rpc.inboundHandler = { inbound in
            switch inbound {
            case .notification(let method, _):
                notificationSeen = method == "probe/notification"
            case .request(let id, let method, _):
                requestSeen = method == "probe/request" && id == .string("server-request")
                reply = Task { try await rpc.respond(to: id, result: .object(["accepted": .bool(true)])) }
            }
        }
        _ = try await rpc.request(method: "probe/events")
        try await reply?.value
        let answer = try await rpc.request(method: "probe/answer")
        check(notificationSeen && requestSeen && answer["accepted"] == .bool(true), "server notifications and string-ID requests round trip through the native client")

        do {
            _ = try await rpc.request(method: "probe/error")
            preconditionFailure("Expected protocol error")
        } catch let error as CodexRPCError {
            check(error.code == -32001 && error.isRetryable, "structured protocol errors retain their code")
        }

        let cancelled = Task { try await rpc.request(method: "probe/hang") }
        try await Task.sleep(for: .milliseconds(150))
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Expected cancellation")
        } catch is CancellationError {
            check(true, "cancellation releases a pending RPC continuation")
        }
        _ = try await rpc.request(method: "probe/echo", params: value)

        let disconnected = Task { try await rpc.request(method: "probe/hang") }
        try await Task.sleep(for: .milliseconds(150))
        rpc.disconnect()
        do {
            _ = try await disconnected.value
            preconditionFailure("Expected disconnect failure")
        } catch {
            check(rpc.state == .disconnected, "disconnect rejects pending work")
        }
        try await rpc.connect()
        let reconnected = try await rpc.request(method: "probe/echo", params: value)
        check(reconnected == value && rpc.state == .connected, "old receive tasks cannot poison a replacement connection")

        // No fixture pings: this crosses both the configured 8-second request
        // and 30-second resource timeout boundaries on a live WebSocket.
        let waited = try await rpc.request(method: "command/exec", params: .object(["disableTimeout": .bool(true)]))
        check(waited["exitCode"] == .integer(0), "interactive RPC survives a 35-second idle connection")

        do {
            _ = try await rpc.request(method: "probe/close")
            preconditionFailure("Expected server close")
        } catch {
            if case .failed = rpc.state { check(true, "server close reports failed connection state") }
            else { preconditionFailure("Server close left stale connected state") }
        }
        try await rpc.connect()
        _ = try await rpc.request(method: "probe/echo", params: value)
        rpc.disconnect()
        print("PASS: production RPC transport regression")
    }
}
