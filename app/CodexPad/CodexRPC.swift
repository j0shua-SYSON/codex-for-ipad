import Combine
import Foundation

enum RPCInbound: Sendable {
    case notification(method: String, params: JSONValue)
    case request(id: JSONValue, method: String, params: JSONValue)
}

struct CodexRPCError: LocalizedError, Equatable, Sendable {
    let code: Int?
    let message: String

    var errorDescription: String? { message }
    var isRetryable: Bool { code == -32001 }
}

@MainActor
protocol CodexRPCServing: AnyObject {
    var inboundHandler: ((RPCInbound) -> Void)? { get set }
    var stateHandler: ((CodexRPCClient.State) -> Void)? { get set }
    func connect() async throws
    func disconnect()
    func request(method: String, params: JSONValue?) async throws -> JSONValue
    func respond(to id: JSONValue, result: JSONValue) async throws
    func respondUnsupported(to id: JSONValue, method: String) async throws
}

extension CodexRPCServing {
    func request(method: String) async throws -> JSONValue {
        try await request(method: method, params: nil)
    }
}

@MainActor
final class CodexRPCClient: ObservableObject, CodexRPCServing {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var state: State = .disconnected {
        didSet { stateHandler?(state) }
    }

    var inboundHandler: ((RPCInbound) -> Void)?
    var stateHandler: ((State) -> Void)?

    private let endpoint: URL
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var generation = 0

    init(endpoint: URL = URL(string: "ws://127.0.0.1:4500")!) {
        self.endpoint = endpoint
    }

    func connect() async throws {
        guard state != .connected else { return }
        disconnect()
        let connectionGeneration = generation
        state = .connecting

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        let socket = session.webSocketTask(with: endpoint)
        self.session = session
        self.socket = socket
        socket.resume()

        receiveTask = Task { [weak self, weak socket] in
            guard let self, let socket else { return }
            await self.receiveMessages(from: socket)
        }

        do {
            _ = try await request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("codexpad"),
                        "title": .string("CodexPad for iPadOS"),
                        "version": .string(Bundle.main.releaseVersion)
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(true)
                    ])
                ])
            )
            guard generation == connectionGeneration else { throw CancellationError() }
            try await notify(method: "initialized", params: nil)
            state = .connected
        } catch {
            if generation == connectionGeneration { failConnection(error) }
            throw error
        }
    }

    func disconnect() {
        generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        let error = CodexRPCError(code: nil, message: "Codex engine disconnected")
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
        deadlines.values.forEach { $0.cancel() }
        deadlines.removeAll()
        state = .disconnected
    }

    func request(method: String, params: JSONValue? = nil) async throws -> JSONValue {
        guard let socket else {
            throw CodexRPCError(code: nil, message: "Codex engine is not connected")
        }

        let id = nextRequestID
        nextRequestID += 1
        var object: [String: JSONValue] = [
            "id": .integer(Int64(id)),
            "method": .string(method)
        ]
        if let params {
            object["params"] = params
        }

        return try await withTaskCancellationHandler {
          try Task.checkCancellation()
          return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            // Interactive commands (including the Files picker) intentionally
            // have no deadline; all ordinary RPCs must eventually release UI.
            if params?["disableTimeout"]?.boolValue != true {
                let seconds = method == "initialize" ? 10 : max(120, (params?["timeoutMs"]?.intValue ?? 0) / 1000 + 10)
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                    self?.resolveRequest(id: id, with: .failure(CodexRPCError(
                        code: nil, message: "\(method) timed out; its server-side outcome may be unknown."
                    )))
                }
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.send(.object(object), through: socket)
                } catch {
                    self.resolveRequest(id: id, with: .failure(error))
                }
            }
          }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resolveRequest(id: id, with: .failure(CancellationError()))
            }
        }
    }

    func notify(method: String, params: JSONValue? = nil) async throws {
        guard let socket else {
            throw CodexRPCError(code: nil, message: "Codex engine is not connected")
        }
        var object: [String: JSONValue] = ["method": .string(method)]
        if let params {
            object["params"] = params
        }
        try await send(.object(object), through: socket)
    }

    func respond(to id: JSONValue, result: JSONValue) async throws {
        guard let socket else {
            throw CodexRPCError(code: nil, message: "Codex engine is not connected")
        }
        try await send(
            .object(["id": id, "result": result]),
            through: socket
        )
    }

    func respondUnsupported(to id: JSONValue, method: String) async throws {
        guard let socket else {
            throw CodexRPCError(code: nil, message: "Codex engine is not connected")
        }
        try await send(
            .object([
                "id": id,
                "error": .object([
                    "code": .integer(-32601),
                    "message": .string("CodexPad does not support server request \(method)")
                ])
            ]),
            through: socket
        )
    }

    private func receiveMessages(from socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let text):
                    data = Data(text.utf8)
                case .data(let payload):
                    data = payload
                @unknown default:
                    continue
                }
                let value = try JSONDecoder().decode(JSONValue.self, from: data)
                guard self.socket === socket else { return }
                handle(value)
            } catch {
                if !Task.isCancelled, self.socket === socket {
                    failConnection(error)
                }
                return
            }
        }
    }

    private func handle(_ value: JSONValue) {
        guard let object = value.objectValue else { return }
        let method = object["method"]?.stringValue
        let params = object["params"] ?? .object([:])

        if let method, let id = object["id"] {
            inboundHandler?(.request(id: id, method: method, params: params))
            return
        }
        if let method {
            inboundHandler?(.notification(method: method, params: params))
            return
        }
        guard let id = object["id"]?.intValue else { return }
        if let result = object["result"] {
            resolveRequest(id: id, with: .success(result))
            return
        }
        if let error = object["error"]?.objectValue {
            resolveRequest(
                id: id,
                with: .failure(CodexRPCError(
                    code: error["code"]?.intValue,
                    message: error["message"]?.stringValue ?? "Unknown app-server error"
                ))
            )
        }
    }

    private func send(_ value: JSONValue, through socket: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexRPCError(code: nil, message: "Could not encode app-server message")
        }
        try await socket.send(.string(text))
    }

    private func resolveRequest(id: Int, with result: Result<JSONValue, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        deadlines.removeValue(forKey: id)?.cancel()
        continuation.resume(with: result)
    }

    private func failConnection(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        disconnect()
        state = .failed(message)
    }
}

/// Deterministic preview transport. It never touches the guest or credentials.
/// UI automation verifies presentation against this fixture, not live inference.
@MainActor
final class CodexDemoRPCClient: CodexRPCServing {
    var inboundHandler: ((RPCInbound) -> Void)?
    var stateHandler: ((CodexRPCClient.State) -> Void)?
    func connect() async throws { stateHandler?(.connected) }
    func disconnect() { stateHandler?(.disconnected) }
    func respond(to id: JSONValue, result: JSONValue) async throws {}
    func respondUnsupported(to id: JSONValue, method: String) async throws {}

    func request(method: String, params: JSONValue?) async throws -> JSONValue {
        if method == "turn/start", let threadID = params?["threadId"]?.stringValue {
            let turn: JSONValue = .object(["id": .string(UUID().uuidString), "status": .string("completed"), "items": .array([])])
            let item: JSONValue = .object([
                "id": .string(UUID().uuidString), "type": .string("agentMessage"),
                "text": .string("Demo response received. No model or guest command was executed.")
            ])
            inboundHandler?(.notification(method: "item/completed", params: .object(["threadId": .string(threadID), "item": item])))
            inboundHandler?(.notification(method: "turn/completed", params: .object(["threadId": .string(threadID), "turn": turn])))
            return .object(["turn": turn])
        }
        if method == "thread/start" {
            return .object(["thread": .object([
                "id": .string(UUID().uuidString), "name": .string("Demo thread"),
                "cwd": params?["cwd"] ?? .string("/root/workspace"), "turns": .array([])
            ])])
        }
        return .object(["demo": .bool(true), "method": .string(method)])
    }
}

private extension Bundle {
    var releaseVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
