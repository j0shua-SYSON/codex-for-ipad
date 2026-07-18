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
final class CodexRPCClient: ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var state: State = .disconnected

    var inboundHandler: ((RPCInbound) -> Void)?

    private let endpoint: URL
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]

    init(endpoint: URL = URL(string: "ws://127.0.0.1:4500")!) {
        self.endpoint = endpoint
    }

    func connect() async throws {
        guard state != .connected else { return }
        disconnect()
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
            try await notify(method: "initialized", params: nil)
            state = .connected
        } catch {
            failConnection(error)
            throw error
        }
    }

    func disconnect() {
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

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { [weak self, weak socket] in
                guard let self, let socket else { return }
                do {
                    try await self.send(.object(object), through: socket)
                } catch {
                    self.resolveRequest(id: id, with: .failure(error))
                }
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
                handle(value)
            } catch {
                if !Task.isCancelled {
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
        continuation.resume(with: result)
    }

    private func failConnection(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        state = .failed(message)
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
    }
}

private extension Bundle {
    var releaseVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
