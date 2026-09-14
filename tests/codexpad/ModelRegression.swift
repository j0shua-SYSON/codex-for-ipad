import Foundation

@MainActor
final class FakeRPC: CodexRPCServing {
    var inboundHandler: ((RPCInbound) -> Void)?
    var stateHandler: ((CodexRPCClient.State) -> Void)?
    var calls: [(String, JSONValue?)] = []
    var responses: [JSONValue] = []
    var handler: ((String, JSONValue?) async throws -> JSONValue)?
    func connect() async throws { stateHandler?(.connected) }
    func disconnect() { stateHandler?(.disconnected) }
    func request(method: String, params: JSONValue?) async throws -> JSONValue {
        calls.append((method, params))
        return try await handler?(method, params) ?? .object([:])
    }
    func respond(to id: JSONValue, result: JSONValue) async throws { responses.append(result) }
    func respondUnsupported(to id: JSONValue, method: String) async throws {}
    func event(_ method: String, _ params: JSONValue) { inboundHandler?(.notification(method: method, params: params)) }
}

@MainActor
final class Gate {
    var continuation: CheckedContinuation<JSONValue, Never>?
    func response() async -> JSONValue { await withCheckedContinuation { continuation = $0 } }
    func release(_ value: JSONValue) { continuation?.resume(returning: value); continuation = nil }
}

@main
@MainActor
struct ModelRegression {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
        print("PASS: \(message)")
    }
    static func until(_ ready: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !ready() {
            precondition(Date() < deadline, "Timed out awaiting test gate")
            await Task.yield()
        }
    }
    static func model(_ rpc: FakeRPC) -> CodexWorkspaceModel {
        let preferences = UserDefaults(suiteName: "CodexPad.Regression.\(UUID().uuidString)")!
        let model = CodexWorkspaceModel(rpc: rpc, demoMode: false, preferences: preferences)
        model.enginePhase = .ready
        model.threads = ["A", "B"].map {
            CodexThreadRecord(id: $0, title: $0, preview: "", cwd: "/root/\($0)", updatedAt: .now, activity: .idle)
        }
        model.selectedThreadID = "A"
        return model
    }
    static func turn(_ thread: String, _ id: String, status: String = "inProgress") -> JSONValue {
        .object(["threadId": .string(thread), "turn": .object(["id": .string(id), "status": .string(status), "items": .array([])])])
    }
    static func main() async {
        check(CodexFeatureCatalog.parameterSchema(for: "turn/start") != nil, "pinned request schema is loadable")
        check(CodexFeatureCatalog.missingRequiredParameters(method: "turn/start", params: .object([:])).contains("threadId"), "schema requires a thread ID before advanced execution")
        check(CodexFeatureCatalog.parameterReference(for: "turn/start")?.contains("definitions") == true, "nested parameter definitions are available offline")
        let rpc = FakeRPC()
        let m = model(rpc)
        rpc.event("turn/started", turn("A", "turnA"))
        rpc.event("turn/started", turn("B", "turnB"))
        check(m.activeTurnID == "turnA", "background start cannot replace the selected active turn")
        await m.interruptTurn()
        check(rpc.calls.last?.1?["threadId"] == .string("A") && rpc.calls.last?.1?["turnId"] == .string("turnA"), "Stop targets the correct thread/turn pair")
        rpc.event("turn/completed", turn("B", "turnB", status: "completed"))
        check(m.isTurnRunning, "background completion cannot stop the selected turn")
        rpc.event("turn/diff/updated", .object(["threadId": .string("B"), "diff": .string("B diff")]))
        check(m.currentDiff.isEmpty, "background diff does not leak into selected changes")
        rpc.event("turn/plan/updated", .object(["threadId": .string("B"), "plan": .array([.object(["step": .string("B plan"), "status": .string("pending")])])]))
        check(m.plan.isEmpty, "background plan does not leak")
        m.composerText = "draft A"
        m.selectedThreadID = "B"
        check(m.composerText.isEmpty && m.currentDiff == "B diff" && m.plan.first?.text == "B plan", "thread switching restores scoped state")
        m.composerText = "draft B"
        m.selectedThreadID = "A"
        check(m.composerText == "draft A", "drafts survive thread switching")

        let gate = Gate()
        rpc.handler = { method, params in
            if method == "thread/resume" { return await gate.response() }
            return .object([:])
        }
        let resume = Task { await m.resumeThread("A") }
        await until { gate.continuation != nil }
        m.selectedThreadID = "B"
        rpc.event("item/started", .object(["threadId": .string("A"), "item": .object(["id": .string("live"), "type": .string("agentMessage"), "text": .string("Live")])]))
        gate.release(.object(["thread": .object(["id": .string("A"), "cwd": .string("/stale"), "turns": .array([])])]))
        await resume.value
        check(m.selectedThreadID == "B", "stale resume does not steal selection")
        check(m.timelineByThread["A"]?.first?.body == "Live", "stale resume does not erase live events")
        check(m.timelineByThread["A"]?.first?.state == .running, "started messages show Running, not Done")
        check(m.activeTurnID == nil, "resuming another thread cannot resurrect selected turn")

        let sendRPC = FakeRPC()
        let sender = model(sendRPC)
        sender.composerText = "Keep this draft"
        sendRPC.handler = { _, _ in throw CodexRPCError(code: -1, message: "rejected") }
        await sender.sendComposer()
        check(sender.composerText == "Keep this draft", "failed sends restore drafts")
        check(!sender.isTurnRunning && sender.selectedTimeline.isEmpty, "failed sends leave no false completed user message")
        sendRPC.handler = { method, params in
            if method == "turn/start" {
                sendRPC.event("turn/completed", turn("A", "fast", status: "completed"))
                return .object(["turn": .object(["id": .string("fast"), "status": .string("inProgress")])])
            }
            return .object([:])
        }
        await sender.sendComposer()
        check(!sender.isTurnRunning, "late turn/start response cannot resurrect a completed turn")
        check(sendRPC.calls.last?.1?["serviceTier"] == .null, "Provider default explicitly clears a previous service tier")

        let createRPC = FakeRPC()
        let creator = model(createRPC)
        creator.selectedThreadID = nil
        creator.composerText = "Only one thread"
        let creation = Gate()
        createRPC.handler = { method, _ in
            if method == "thread/start" { return await creation.response() }
            return .object(["turn": .object(["id": .string("created-turn"), "status": .string("completed")])])
        }
        let first = Task { await creator.sendComposer() }
        await until { creation.continuation != nil }
        await creator.sendComposer()
        check(createRPC.calls.filter { $0.0 == "thread/start" }.count == 1, "double send cannot create duplicate threads")
        creation.release(.object(["thread": .object(["id": .string("new"), "cwd": .string("/root/workspace")])]))
        await first.value

        let request: JSONValue = .object([
            "threadId": .string("A"), "availableDecisions": .array([.string("decline"), .string("cancel")])
        ])
        sendRPC.inboundHandler?(.request(id: .integer(42), method: "item/commandExecution/requestApproval", params: request))
        let approval = sender.pendingRequests[0]
        await sender.answerCommandDecision(approval, decision: .string("accept"))
        check(sender.pendingRequests.count == 1, "unsupported approval choices cannot be sent")
        await sender.answerCommandDecision(approval, decision: .string("cancel"))
        check(sender.pendingRequests.isEmpty && sendRPC.responses.last?["decision"] == .string("cancel"), "advertised approval decision round trips exactly")

        sendRPC.stateHandler?(.failed("socket closed"))
        check(!sender.enginePhase.isReady && !sender.isTurnRunning, "socket failure clears misleading ready/running UI")
        sender.workspacePath = "/root/workspaces/codexpad-files"
        await sender.unlinkFilesFolder()
        check(sender.workspacePath == "/root/workspaces/codexpad-files", "offline unlink cannot falsely claim saved mount was removed")
        sender.composerText = "offline draft"
        let count = sendRPC.calls.count
        await sender.sendComposer()
        check(sendRPC.calls.count == count && sender.composerText == "offline draft", "offline send neither calls RPC nor loses text")

        let filesRPC = FakeRPC()
        let files = model(filesRPC)
        files.workspacePath = "/root/previous"
        filesRPC.handler = { _, params in
            let command = params?["command"]?.arrayValue?.first?.stringValue
            return .object(["exitCode": .integer(command == "/bin/mountpoint" ? 0 : 1)])
        }
        await files.chooseFilesFolder()
        check(filesRPC.calls.count == 1 && files.workspacePath == "/root/previous", "choosing another folder never unmounts live Files access")
        files.linkedFolderPhase = .disconnected
        filesRPC.calls.removeAll()
        filesRPC.handler = { _, params in
            let command = params?["command"]?.arrayValue?.first?.stringValue
            return .object(["exitCode": .integer(command == "/bin/mkdir" ? 0 : 1), "stderr": .string("Picker cancelled")])
        }
        await files.chooseFilesFolder()
        check(files.linkedFolderPhase == .disconnected && files.workspacePath == "/root/previous", "cancelled Files selection preserves the previous workspace and link state")
        check(!filesRPC.calls.contains { $0.1?["command"]?.arrayValue?.first == .string("/bin/umount") }, "folder selection never silently revokes a bookmark")

        let demo = CodexWorkspaceModel(demoMode: true)
        await demo.start()
        demo.composerText = "fixture send"
        await demo.sendComposer()
        check(demo.errorBanner == nil && !demo.isTurnRunning, "demo sends have a working isolated transport")
        check(demo.selectedTimeline.last?.body.contains("Demo response received") == true, "demo response is explicitly labelled as simulated")
        print("\(checks) model regression assertions passed")
    }
}
