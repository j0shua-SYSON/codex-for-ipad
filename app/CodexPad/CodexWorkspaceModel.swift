import Combine
import Foundation

@MainActor
final class CodexWorkspaceModel: ObservableObject {
    @Published var enginePhase: EnginePhase = .starting
    @Published var threads: [CodexThreadRecord] = []
    @Published var selectedThreadID: String?
    @Published var timelineByThread: [String: [TimelineItem]] = [:]
    @Published var pendingRequests: [PendingServerRequest] = []
    @Published var plan: [PlanStep] = []
    @Published var currentDiff = ""
    @Published var directoryPath = "/root/workspace"
    @Published var directoryEntries: [WorkspaceEntry] = []
    @Published var filePreviewName: String?
    @Published var filePreview = ""
    @Published var runtimeLog: [String] = []
    @Published var account = AccountSummary()
    @Published var composerText = ""
    @Published var workspacePath = "/root/workspace"
    @Published var activeTurnID: String?
    @Published var isTurnRunning = false
    @Published var workbenchTab: WorkbenchTab = .plan
    @Published var showsSettings = false
    @Published var errorBanner: String?
    @Published var loginURL: URL?
    @Published var deviceCode: String?
    @Published var deviceVerificationURL: URL?

    let rpc: CodexRPCClient
    private let demoMode: Bool
    private var didStart = false

    init(
        rpc: CodexRPCClient? = nil,
        demoMode: Bool = ProcessInfo.processInfo.arguments.contains("--codexpad-demo")
    ) {
        let rpc = rpc ?? CodexRPCClient()
        self.rpc = rpc
        self.demoMode = demoMode
        rpc.inboundHandler = { [weak self] inbound in
            self?.handle(inbound)
        }
    }

    var selectedThread: CodexThreadRecord? {
        threads.first { $0.id == selectedThreadID }
    }

    var selectedTimeline: [TimelineItem] {
        guard let selectedThreadID else { return [] }
        return timelineByThread[selectedThreadID] ?? []
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        if demoMode {
            seedDemoWorkspace()
            return
        }
        await connectToLocalEngine()
    }

    func retryConnection() async {
        didStart = true
        await connectToLocalEngine()
    }

    func connectToLocalEngine() async {
        enginePhase = .starting
        errorBanner = nil
        for attempt in 1...10 {
            enginePhase = .connecting(attempt: attempt)
            do {
                try await rpc.connect()
                enginePhase = .ready
                appendRuntime("Connected to Codex app-server on guest loopback")
                await refreshAccount()
                await refreshThreads()
                return
            } catch {
                appendRuntime("Engine probe \(attempt) failed: \(error.localizedDescription)")
                if attempt < 10 {
                    try? await Task.sleep(for: .milliseconds(Int64(350 + attempt * 180)))
                }
            }
        }
        enginePhase = .offline(
            message: "The local Codex service did not become ready. Open Terminal to inspect the guest runtime."
        )
    }

    func refreshThreads() async {
        guard enginePhase.isReady else { return }
        do {
            let response = try await rpc.request(
                method: "thread/list",
                params: .object([
                    "cursor": .null,
                    "limit": .integer(60),
                    "sortKey": .string("recency_at"),
                    "sortDirection": .string("desc")
                ])
            )
            let records = response["data"]?.arrayValue?.compactMap(parseThread) ?? []
            threads = records
            if selectedThreadID == nil {
                selectedThreadID = records.first?.id
                if let id = selectedThreadID {
                    await resumeThread(id)
                }
            } else {
                await loadDirectory(selectedThread?.cwd ?? workspacePath)
            }
        } catch {
            report(error, context: "Could not load threads")
        }
    }

    func refreshAccount() async {
        guard enginePhase.isReady else { return }
        do {
            let response = try await rpc.request(
                method: "account/read",
                params: .object(["refreshToken": .bool(false)])
            )
            guard let raw = response["account"], raw != .null else {
                account = AccountSummary()
                return
            }
            account = AccountSummary(
                authMode: raw["type"]?.stringValue,
                email: raw["email"]?.stringValue,
                plan: raw["planType"]?.stringValue
            )
        } catch {
            report(error, context: "Could not read account")
        }
    }

    func selectThread(_ id: String?) async {
        selectedThreadID = id
        guard let id else { return }
        await resumeThread(id)
    }

    @discardableResult
    func createThread() async -> String? {
        guard enginePhase.isReady else {
            errorBanner = "Start the local engine before creating a thread."
            return nil
        }
        do {
            let response = try await rpc.request(
                method: "thread/start",
                params: .object([
                    "cwd": .string(workspacePath),
                    "approvalPolicy": .string("on-request"),
                    "sandbox": .string("workspace-write"),
                    "personality": .string("pragmatic"),
                    "serviceName": .string("codexpad")
                ])
            )
            guard let thread = response["thread"], let record = parseThread(thread) else {
                throw CodexRPCError(code: nil, message: "thread/start returned no thread")
            }
            upsertThread(record, atFront: true)
            selectedThreadID = record.id
            timelineByThread[record.id] = []
            return record.id
        } catch {
            report(error, context: "Could not create a thread")
            return nil
        }
    }

    func resumeThread(_ id: String) async {
        guard enginePhase.isReady else { return }
        do {
            let response = try await rpc.request(
                method: "thread/resume",
                params: .object(["threadId": .string(id)])
            )
            guard let rawThread = response["thread"] else { return }
            var cwd = workspacePath
            if let record = parseThread(rawThread) {
                upsertThread(record)
                cwd = record.cwd.isEmpty ? workspacePath : record.cwd
            }
            let turns = rawThread["turns"]?.arrayValue ?? []
            timelineByThread[id] = turns.flatMap { turn in
                turn["items"]?.arrayValue?.compactMap(parseTimelineItem) ?? []
            }
            selectedThreadID = id
            await loadDirectory(cwd)
        } catch {
            report(error, context: "Could not resume the thread")
        }
    }

    func loadDirectory(_ path: String) async {
        guard enginePhase.isReady else { return }
        do {
            let response = try await rpc.request(
                method: "fs/readDirectory",
                params: .object(["path": .string(path)])
            )
            directoryPath = path
            filePreviewName = nil
            filePreview = ""
            directoryEntries = (response["entries"]?.arrayValue ?? []).compactMap { raw in
                guard let name = raw["fileName"]?.stringValue else { return nil }
                let child = path == "/" ? "/\(name)" : "\(path)/\(name)"
                return WorkspaceEntry(
                    id: child,
                    name: name,
                    path: child,
                    isDirectory: raw["isDirectory"]?.boolValue ?? false,
                    isFile: raw["isFile"]?.boolValue ?? false
                )
            }.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            report(error, context: "Could not read \(path)")
        }
    }

    func openEntry(_ entry: WorkspaceEntry) async {
        if entry.isDirectory {
            await loadDirectory(entry.path)
            return
        }
        guard entry.isFile else { return }
        do {
            let response = try await rpc.request(
                method: "fs/readFile",
                params: .object(["path": .string(entry.path)])
            )
            guard let encoded = response["dataBase64"]?.stringValue,
                  let data = Data(base64Encoded: encoded) else {
                throw CodexRPCError(code: nil, message: "The file response was not valid base64")
            }
            filePreviewName = entry.name
            filePreview = String(data: Data(data.prefix(200_000)), encoding: .utf8)
                ?? "Binary file — preview unavailable"
        } catch {
            report(error, context: "Could not open \(entry.name)")
        }
    }

    func navigateUpDirectory() async {
        guard directoryPath != "/" else { return }
        let parent = (directoryPath as NSString).deletingLastPathComponent
        await loadDirectory(parent.isEmpty ? "/" : parent)
    }

    func sendComposer() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTurnRunning else { return }
        var threadID = selectedThreadID
        if threadID == nil {
            threadID = await createThread()
        }
        guard let threadID else { return }

        composerText = ""
        let clientID = UUID().uuidString
        upsertTimeline(
            TimelineItem(
                id: clientID,
                kind: .user,
                title: "You",
                body: text,
                detail: "",
                state: .completed,
                timestamp: .now
            ),
            in: threadID
        )
        isTurnRunning = true
        setThreadActivity(.running, id: threadID)

        do {
            let response = try await rpc.request(
                method: "turn/start",
                params: .object([
                    "threadId": .string(threadID),
                    "clientUserMessageId": .string(clientID),
                    "input": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string(text),
                            "text_elements": .array([])
                        ])
                    ])
                ])
            )
            activeTurnID = response["turn"]?["id"]?.stringValue
        } catch {
            isTurnRunning = false
            setThreadActivity(.failed, id: threadID)
            report(error, context: "Could not start the turn")
        }
    }

    func interruptTurn() async {
        guard let threadID = selectedThreadID, let activeTurnID else { return }
        do {
            _ = try await rpc.request(
                method: "turn/interrupt",
                params: .object([
                    "threadId": .string(threadID),
                    "turnId": .string(activeTurnID)
                ])
            )
        } catch {
            report(error, context: "Could not interrupt the turn")
        }
    }

    func archiveSelectedThread() async {
        guard let id = selectedThreadID else { return }
        do {
            _ = try await rpc.request(
                method: "thread/archive",
                params: .object(["threadId": .string(id)])
            )
            threads.removeAll { $0.id == id }
            timelineByThread[id] = nil
            selectedThreadID = threads.first?.id
        } catch {
            report(error, context: "Could not archive the thread")
        }
    }

    func resolve(_ request: PendingServerRequest, choice: ApprovalChoice) async {
        if request.kind == .unsupported {
            do {
                try await rpc.respondUnsupported(to: request.rpcID, method: "unknown")
                pendingRequests.removeAll { $0.id == request.id }
            } catch {
                report(error, context: "Could not dismiss the unsupported request")
            }
            return
        }

        let result: JSONValue
        switch request.kind {
        case .command, .fileChange:
            let decision: String = switch choice {
            case .once: "accept"
            case .session: "acceptForSession"
            case .decline: "decline"
            case .cancel: "cancel"
            }
            result = .object(["decision": .string(decision)])
        case .permissions:
            let requested = request.rawParams["permissions"]?.objectValue ?? [:]
            let permissions: JSONValue = choice == .once || choice == .session
                ? .object(requested.filter { $0.value != .null })
                : .object([:])
            result = .object([
                "permissions": permissions,
                "scope": .string(choice == .session ? "session" : "turn")
            ])
        case .elicitation:
            result = .object([
                "action": .string(choice == .cancel ? "cancel" : "decline"),
                "content": .null,
                "_meta": .null
            ])
        case .question:
            result = .object([:])
        case .unsupported:
            return
        }

        do {
            try await rpc.respond(to: request.rpcID, result: result)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            report(error, context: "Could not answer Codex")
        }
    }

    func answer(_ request: PendingServerRequest, values: [String: String]) async {
        let answers = Dictionary(uniqueKeysWithValues: request.questions.map { question in
            let value = values[question.id, default: ""]
            return (question.id, JSONValue.object(["answers": .array([.string(value)])]))
        })
        do {
            try await rpc.respond(
                to: request.rpcID,
                result: .object(["answers": .object(answers)])
            )
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            report(error, context: "Could not send your answer")
        }
    }

    func signInWithChatGPT() async {
        do {
            let response = try await rpc.request(
                method: "account/login/start",
                params: .object([
                    "type": .string("chatgpt"),
                    "useHostedLoginSuccessPage": .bool(true),
                    "appBrand": .string("codex")
                ])
            )
            loginURL = response["authUrl"]?.stringValue.flatMap(URL.init(string:))
        } catch {
            report(error, context: "Could not start ChatGPT sign-in")
        }
    }

    func signInWithDeviceCode() async {
        do {
            let response = try await rpc.request(
                method: "account/login/start",
                params: .object(["type": .string("chatgptDeviceCode")])
            )
            deviceCode = response["userCode"]?.stringValue
            deviceVerificationURL = response["verificationUrl"]?.stringValue.flatMap(URL.init(string:))
        } catch {
            report(error, context: "Could not start device sign-in")
        }
    }

    func signIn(apiKey: String) async {
        guard !apiKey.isEmpty else { return }
        do {
            _ = try await rpc.request(
                method: "account/login/start",
                params: .object(["type": .string("apiKey"), "apiKey": .string(apiKey)])
            )
            await refreshAccount()
        } catch {
            report(error, context: "Could not save the API key")
        }
    }

    func signOut() async {
        do {
            _ = try await rpc.request(method: "account/logout")
            account = AccountSummary()
        } catch {
            report(error, context: "Could not sign out")
        }
    }

    private func handle(_ inbound: RPCInbound) {
        switch inbound {
        case .notification(let method, let params):
            handleNotification(method: method, params: params)
        case .request(let id, let method, let params):
            handleServerRequest(id: id, method: method, params: params)
        }
    }

    private func handleNotification(method: String, params: JSONValue) {
        let threadID = params["threadId"]?.stringValue ?? selectedThreadID
        switch method {
        case "thread/started":
            if let raw = params["thread"], let record = parseThread(raw) {
                upsertThread(record, atFront: true)
            }
        case "thread/status/changed":
            if let threadID {
                setThreadActivity(parseActivity(params["status"]), id: threadID)
            }
        case "turn/started":
            activeTurnID = params["turn"]?["id"]?.stringValue
            isTurnRunning = true
            if let threadID { setThreadActivity(.running, id: threadID) }
        case "turn/completed":
            isTurnRunning = false
            activeTurnID = nil
            if let threadID { setThreadActivity(.idle, id: threadID) }
            if let items = params["turn"]?["items"]?.arrayValue, let threadID {
                for item in items.compactMap(parseTimelineItem) {
                    upsertTimeline(item, in: threadID)
                }
            }
        case "item/started", "item/completed":
            if let raw = params["item"], let item = parseTimelineItem(raw), let threadID {
                upsertTimeline(item, in: threadID)
            }
        case "item/agentMessage/delta":
            appendDelta(params["delta"]?.stringValue, to: params["itemId"]?.stringValue, detail: false, threadID: threadID)
        case "item/plan/delta", "item/reasoning/summaryTextDelta":
            appendDelta(params["delta"]?.stringValue, to: params["itemId"]?.stringValue, detail: false, threadID: threadID)
        case "item/commandExecution/outputDelta":
            appendDelta(params["delta"]?.stringValue, to: params["itemId"]?.stringValue, detail: true, threadID: threadID)
        case "turn/diff/updated":
            currentDiff = params["diff"]?.stringValue ?? currentDiff
        case "turn/plan/updated":
            parsePlan(params)
        case "serverRequest/resolved":
            if let id = params["requestId"] {
                pendingRequests.removeAll { $0.rpcID == id }
            }
        case "account/updated":
            account.authMode = params["authMode"]?.stringValue
            account.plan = params["planType"]?.stringValue
        case "account/login/completed":
            if params["success"]?.boolValue == true {
                Task { await refreshAccount() }
            } else if let message = params["error"]?.stringValue {
                errorBanner = message
            }
        case "error":
            let message = params["error"]?["message"]?.stringValue ?? "Codex reported an error"
            errorBanner = message
            appendRuntime(message)
        case "warning", "guardianWarning", "deprecationNotice", "configWarning":
            if let message = params["message"]?.stringValue {
                appendRuntime(message)
            }
        default:
            break
        }
    }

    private func handleServerRequest(id: JSONValue, method: String, params: JSONValue) {
        let kind: ServerRequestKind
        let title: String
        switch method {
        case "item/commandExecution/requestApproval":
            kind = .command
            title = "Run this command?"
        case "item/fileChange/requestApproval":
            kind = .fileChange
            title = "Apply these changes?"
        case "item/permissions/requestApproval":
            kind = .permissions
            title = "Grant additional access?"
        case "item/tool/requestUserInput":
            kind = .question
            title = "Codex needs your input"
        case "mcpServer/elicitation/request":
            kind = .elicitation
            title = "A connected tool needs input"
        default:
            appendRuntime("Rejected unsupported server request: \(method)")
            Task {
                do {
                    try await rpc.respondUnsupported(to: id, method: method)
                } catch {
                    report(error, context: "Could not reject unsupported server request")
                }
            }
            return
        }

        let questions = params["questions"]?.arrayValue?.compactMap { raw -> InputQuestion? in
            guard let id = raw["id"]?.stringValue else { return nil }
            let options = raw["options"]?.arrayValue?.compactMap {
                $0["label"]?.stringValue ?? $0["description"]?.stringValue
            } ?? []
            return InputQuestion(
                id: id,
                header: raw["header"]?.stringValue ?? "Question",
                prompt: raw["question"]?.stringValue ?? "",
                options: options,
                allowsFreeform: raw["isOther"]?.boolValue ?? true,
                isSecret: raw["isSecret"]?.boolValue ?? false
            )
        } ?? []

        let detail = params["command"]?.stringValue
            ?? params["cwd"]?.stringValue
            ?? params["permissions"]?.prettyPrinted
            ?? ""
        let request = PendingServerRequest(
            id: UUID().uuidString,
            rpcID: id,
            kind: kind,
            threadID: params["threadId"]?.stringValue,
            title: title,
            message: params["reason"]?.stringValue ?? questions.first?.prompt ?? "Review the request before continuing.",
            detail: detail,
            questions: questions,
            rawParams: params
        )
        pendingRequests.append(request)
        if let threadID = request.threadID {
            setThreadActivity(.waiting, id: threadID)
        }
    }

    private func parseThread(_ raw: JSONValue) -> CodexThreadRecord? {
        guard let id = raw["id"]?.stringValue else { return nil }
        let preview = raw["preview"]?.stringValue ?? ""
        let name = raw["name"]?.stringValue
        let title = name?.isEmpty == false ? name! : (preview.isEmpty ? "New thread" : preview)
        let timestamp = raw["recencyAt"]?.doubleValue
            ?? raw["updatedAt"]?.doubleValue
            ?? raw["createdAt"]?.doubleValue
            ?? Date.now.timeIntervalSince1970
        return CodexThreadRecord(
            id: id,
            title: title,
            preview: preview,
            cwd: raw["cwd"]?.stringValue ?? workspacePath,
            updatedAt: Date(timeIntervalSince1970: timestamp),
            activity: parseActivity(raw["status"]),
            agentNickname: raw["agentNickname"]?.stringValue
        )
    }

    private func parseActivity(_ raw: JSONValue?) -> ThreadActivity {
        switch raw?["type"]?.stringValue {
        case "active": .running
        case "idle": .idle
        case "systemError": .failed
        case "notLoaded": .offline
        default: .idle
        }
    }

    private func parseTimelineItem(_ raw: JSONValue) -> TimelineItem? {
        guard let id = raw["id"]?.stringValue, let type = raw["type"]?.stringValue else { return nil }
        let status = parseTimelineState(raw["status"]?.stringValue)
        switch type {
        case "userMessage":
            let text = raw["content"]?.arrayValue?.compactMap { $0["text"]?.stringValue }.joined(separator: "\n") ?? ""
            return TimelineItem(id: id, kind: .user, title: "You", body: text, detail: "", state: .completed, timestamp: .now)
        case "agentMessage":
            return TimelineItem(id: id, kind: .agent, title: "Codex", body: raw["text"]?.stringValue ?? "", detail: "", state: status, timestamp: .now)
        case "reasoning":
            let summary = raw["summary"]?.arrayValue?.compactMap(\.stringValue).joined(separator: "\n\n") ?? ""
            return TimelineItem(id: id, kind: .reasoning, title: "Reasoning", body: summary, detail: "", state: status, timestamp: .now)
        case "plan":
            return TimelineItem(id: id, kind: .plan, title: "Plan", body: raw["text"]?.stringValue ?? "", detail: "", state: status, timestamp: .now)
        case "commandExecution":
            return TimelineItem(id: id, kind: .command, title: "Command", body: raw["command"]?.stringValue ?? "", detail: raw["aggregatedOutput"]?.stringValue ?? "", state: status, timestamp: .now)
        case "fileChange":
            let paths = raw["changes"]?.arrayValue?.compactMap {
                $0["path"]?.stringValue ?? $0["filePath"]?.stringValue
            }.joined(separator: "\n") ?? ""
            return TimelineItem(id: id, kind: .fileChange, title: "File changes", body: paths, detail: raw.prettyPrinted, state: status, timestamp: .now)
        case "mcpToolCall", "dynamicToolCall", "collabAgentToolCall", "subAgentActivity":
            let name = raw["tool"]?.stringValue ?? raw["kind"]?.stringValue ?? "Tool"
            return TimelineItem(id: id, kind: .tool, title: name, body: raw["server"]?.stringValue ?? "", detail: raw.prettyPrinted, state: status, timestamp: .now)
        case "webSearch":
            return TimelineItem(id: id, kind: .search, title: "Web search", body: raw["query"]?.stringValue ?? "", detail: "", state: status, timestamp: .now)
        default:
            return TimelineItem(id: id, kind: .notice, title: type, body: "", detail: raw.prettyPrinted, state: status, timestamp: .now)
        }
    }

    private func parseTimelineState(_ status: String?) -> TimelineState {
        switch status {
        case "inProgress", "running": .running
        case "failed": .failed
        case "declined": .declined
        case "pending": .pending
        default: .completed
        }
    }

    private func parsePlan(_ params: JSONValue) {
        guard let steps = params["plan"]?.arrayValue ?? params["steps"]?.arrayValue else { return }
        plan = steps.enumerated().map { index, raw in
            PlanStep(
                id: raw["id"]?.stringValue ?? "step-\(index)",
                text: raw["step"]?.stringValue ?? raw["text"]?.stringValue ?? "",
                status: raw["status"]?.stringValue ?? "pending"
            )
        }
    }

    private func appendDelta(_ delta: String?, to itemID: String?, detail: Bool, threadID: String?) {
        guard let delta, let itemID, let threadID,
              var items = timelineByThread[threadID],
              let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        if detail {
            items[index].detail += delta
        } else {
            items[index].body += delta
        }
        timelineByThread[threadID] = items
    }

    private func upsertTimeline(_ item: TimelineItem, in threadID: String) {
        var items = timelineByThread[threadID] ?? []
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        timelineByThread[threadID] = items
    }

    private func upsertThread(_ record: CodexThreadRecord, atFront: Bool = false) {
        if let index = threads.firstIndex(where: { $0.id == record.id }) {
            threads[index] = record
        } else if atFront {
            threads.insert(record, at: 0)
        } else {
            threads.append(record)
        }
    }

    private func setThreadActivity(_ activity: ThreadActivity, id: String) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].activity = activity
    }

    private func appendRuntime(_ line: String) {
        runtimeLog.append(line)
        if runtimeLog.count > 200 {
            runtimeLog.removeFirst(runtimeLog.count - 200)
        }
    }

    private func report(_ error: Error, context: String) {
        let message = "\(context): \(error.localizedDescription)"
        errorBanner = message
        appendRuntime(message)
    }

    private func seedDemoWorkspace() {
        enginePhase = .ready
        account = AccountSummary(authMode: "chatgpt", email: "joshua@example.com", plan: "pro")
        let thread = CodexThreadRecord(
            id: "demo-thread",
            title: "Make the repository update-safe",
            preview: "Make the repository update-safe",
            cwd: "/root/workspace/codex-for-ipad",
            updatedAt: .now,
            activity: .waiting,
            agentNickname: nil
        )
        threads = [
            thread,
            CodexThreadRecord(id: "demo-2", title: "Audit iPad accessibility", preview: "Audit iPad accessibility", cwd: "/root/workspace", updatedAt: .now.addingTimeInterval(-3600), activity: .idle, agentNickname: nil),
            CodexThreadRecord(id: "demo-3", title: "Cross-compile app-server", preview: "Cross-compile app-server", cwd: "/root/workspace", updatedAt: .now.addingTimeInterval(-7200), activity: .idle, agentNickname: "Atlas")
        ]
        selectedThreadID = thread.id
        timelineByThread[thread.id] = [
            TimelineItem(id: "u1", kind: .user, title: "You", body: "Make Codex updates clean and stable without losing the iPad-specific work.", detail: "", state: .completed, timestamp: .now.addingTimeInterval(-180)),
            TimelineItem(id: "p1", kind: .plan, title: "Plan", body: "Separate upstream pins, protocol compatibility, rootfs packaging, and native UI verification.", detail: "", state: .completed, timestamp: .now.addingTimeInterval(-150)),
            TimelineItem(id: "c1", kind: .command, title: "Command", body: "cargo zigbuild --target i686-unknown-linux-musl -p codex-app-server", detail: "Compiling codex-app-server…\nFinished release build", state: .completed, timestamp: .now.addingTimeInterval(-120)),
            TimelineItem(id: "a1", kind: .agent, title: "Codex", body: "The compatibility gate passes against the pinned protocol. I’ve isolated Codex updates behind a manifest and verified pull requests.", detail: "", state: .completed, timestamp: .now.addingTimeInterval(-60))
        ]
        plan = [
            PlanStep(id: "1", text: "Pin upstream source and toolchain", status: "completed"),
            PlanStep(id: "2", text: "Cross-compile the app-server", status: "completed"),
            PlanStep(id: "3", text: "Package the Alpine root", status: "inProgress"),
            PlanStep(id: "4", text: "Run iPad UI and accessibility checks", status: "pending")
        ]
        currentDiff = """
        diff --git a/Dependencies/upstreams.json b/Dependencies/upstreams.json
        +  \"codex\": {
        +    \"revision\": \"6bd3f5e3db82…\",
        +    \"target\": \"i686-unknown-linux-musl\"
        +  }
        """
        runtimeLog = [
            "iSH kernel booted Alpine 3.19",
            "Codex app-server listening on 127.0.0.1:4500",
            "Protocol initialized: v2 experimental capabilities enabled"
        ]
        directoryPath = "/root/workspace/codex-for-ipad"
        directoryEntries = [
            WorkspaceEntry(id: "Sources", name: "app", path: "\(directoryPath)/app", isDirectory: true, isFile: false),
            WorkspaceEntry(id: "Dependencies", name: "Dependencies", path: "\(directoryPath)/Dependencies", isDirectory: true, isFile: false),
            WorkspaceEntry(id: "README", name: "README.md", path: "\(directoryPath)/README.md", isDirectory: false, isFile: true)
        ]
        pendingRequests = [
            PendingServerRequest(
                id: "approval-demo",
                rpcID: .integer(42),
                kind: .command,
                threadID: thread.id,
                title: "Run the hosted build?",
                message: "This starts the public GitHub Actions compatibility workflow.",
                detail: "gh workflow run codex-i686.yml --ref main",
                questions: [],
                rawParams: .object([:])
            )
        ]
    }
}
