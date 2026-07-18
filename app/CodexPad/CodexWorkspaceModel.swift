import Combine
import Foundation

private enum CodexPadPreferenceKey {
    static let desktopMode = "CodexPadDesktopModeEnabled"
    static let showAllFeaturesInTouchMode = "CodexPadShowAllFeaturesInTouchMode"
    static let workspacePath = "CodexPadWorkspacePath"
    static let linkedFilesFolder = "CodexPadLinkedFilesFolder"
    static let linkedFolderDisplayName = "CodexPadLinkedFolderDisplayName"
    static let selectedModel = "CodexPadSelectedModel"
    static let selectedReasoningEffort = "CodexPadSelectedReasoningEffort"
    static let selectedServiceTier = "CodexPadSelectedServiceTier"
    static let selectedCollaborationMode = "CodexPadSelectedCollaborationMode"
}

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
    @Published var desktopModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(desktopModeEnabled, forKey: CodexPadPreferenceKey.desktopMode)
            if !desktopModeEnabled {
                isDesktopComposerEngaged = false
            }
        }
    }
    @Published var showAllFeaturesInTouchMode = false {
        didSet {
            UserDefaults.standard.set(
                showAllFeaturesInTouchMode,
                forKey: CodexPadPreferenceKey.showAllFeaturesInTouchMode
            )
        }
    }
    @Published private(set) var composerFocusGeneration = 0
    @Published var workspacePath = "/root/workspace" {
        didSet {
            UserDefaults.standard.set(workspacePath, forKey: CodexPadPreferenceKey.workspacePath)
        }
    }
    @Published var availableModels: [CodexModelOption] = []
    @Published var selectedModelID: String? {
        didSet { persistOptional(selectedModelID, key: CodexPadPreferenceKey.selectedModel) }
    }
    @Published var selectedReasoningEffort: String? {
        didSet { persistOptional(selectedReasoningEffort, key: CodexPadPreferenceKey.selectedReasoningEffort) }
    }
    @Published var selectedServiceTier: String? {
        didSet { persistOptional(selectedServiceTier, key: CodexPadPreferenceKey.selectedServiceTier) }
    }
    @Published var collaborationModes: [CollaborationModeOption] = []
    @Published var selectedCollaborationMode: String? {
        didSet { persistOptional(selectedCollaborationMode, key: CodexPadPreferenceKey.selectedCollaborationMode) }
    }
    @Published var linkedFolderPhase: LinkedFolderPhase = .disconnected
    @Published var protocolEvents: [ProtocolEvent] = []
    @Published var activeTurnID: String?
    @Published var isTurnRunning = false
    @Published var workbenchTab: WorkbenchTab = .plan
    @Published var showsSettings = false
    @Published var showsFeatureCenter = false
    @Published var errorBanner: String?
    @Published var loginURL: URL?
    @Published var deviceCode: String?
    @Published var deviceVerificationURL: URL?

    let rpc: CodexRPCClient
    private let demoMode: Bool
    private var didStart = false
    private var isDesktopComposerEngaged = false
    private let linkedFolderGuestPath = "/root/workspaces/codexpad-files"

    init(
        rpc: CodexRPCClient? = nil,
        demoMode: Bool = ProcessInfo.processInfo.arguments.contains("--codexpad-demo")
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--codexpad-desktop-mode") {
            desktopModeEnabled = true
        } else if arguments.contains("--codexpad-touch-mode") || demoMode {
            desktopModeEnabled = false
        } else {
            desktopModeEnabled = UserDefaults.standard.bool(forKey: CodexPadPreferenceKey.desktopMode)
        }
        let rpc = rpc ?? CodexRPCClient()
        self.rpc = rpc
        self.demoMode = demoMode
        selectedModelID = UserDefaults.standard.string(forKey: CodexPadPreferenceKey.selectedModel)
        selectedReasoningEffort = UserDefaults.standard.string(forKey: CodexPadPreferenceKey.selectedReasoningEffort)
        selectedServiceTier = UserDefaults.standard.string(forKey: CodexPadPreferenceKey.selectedServiceTier)
        selectedCollaborationMode = UserDefaults.standard.string(forKey: CodexPadPreferenceKey.selectedCollaborationMode)
        if arguments.contains("--codexpad-show-all-features") {
            showAllFeaturesInTouchMode = true
        } else if !demoMode {
            showAllFeaturesInTouchMode = UserDefaults.standard.bool(
                forKey: CodexPadPreferenceKey.showAllFeaturesInTouchMode
            )
        }
        if !demoMode, let savedPath = UserDefaults.standard.string(forKey: CodexPadPreferenceKey.workspacePath) {
            workspacePath = savedPath
        }
        if !demoMode, UserDefaults.standard.bool(forKey: CodexPadPreferenceKey.linkedFilesFolder) {
            linkedFolderPhase = .linked(
                name: UserDefaults.standard.string(forKey: CodexPadPreferenceKey.linkedFolderDisplayName)
                    ?? "Files workspace"
            )
        }
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

    var selectedModel: CodexModelOption? {
        availableModels.first { $0.id == selectedModelID }
    }

    var showsCompleteFeatureSet: Bool {
        desktopModeEnabled || showAllFeaturesInTouchMode
    }

    func composerDidGainFocus() {
        guard desktopModeEnabled else { return }
        isDesktopComposerEngaged = true
    }

    func requestComposerFocus() {
        guard desktopModeEnabled, isDesktopComposerEngaged else { return }
        composerFocusGeneration += 1
    }

    func workspaceDidReturnFromTerminal() {
        requestComposerFocus()
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
                await refreshModels()
                await refreshCollaborationModes()
                await restoreLinkedFolderState()
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

    func refreshModels() async {
        guard enginePhase.isReady else { return }
        do {
            var cursor: String?
            var catalog: [CodexModelOption] = []
            repeat {
                let response = try await rpc.request(
                    method: "model/list",
                    params: .object([
                        "cursor": cursor.map(JSONValue.string) ?? .null,
                        "limit": .integer(100),
                        // Hidden entries remain clearly labelled in the picker,
                        // but are still reachable as part of the complete surface.
                        "includeHidden": .bool(true)
                    ])
                )
                catalog.append(contentsOf: (response["data"]?.arrayValue ?? []).compactMap(parseModel))
                cursor = response["nextCursor"]?.stringValue
            } while cursor != nil

            availableModels = catalog
            let selectedStillExists = catalog.contains { $0.id == selectedModelID }
            if !selectedStillExists {
                selectedModelID = catalog.first(where: \.isDefault)?.id ?? catalog.first?.id
            }
            normalizeModelSelections()
            appendRuntime("Loaded \(catalog.count) models from model/list")
        } catch {
            report(error, context: "Could not load the model catalog")
        }
    }

    func refreshCollaborationModes() async {
        guard enginePhase.isReady else { return }
        do {
            let response = try await rpc.request(
                method: "collaborationMode/list",
                params: .object([:])
            )
            collaborationModes = (response["data"]?.arrayValue ?? []).compactMap { raw in
                guard let name = raw["name"]?.stringValue else { return nil }
                return CollaborationModeOption(
                    name: name,
                    mode: raw["mode"]?.stringValue,
                    model: raw["model"]?.stringValue,
                    reasoningEffort: raw["reasoning_effort"]?.stringValue
                        ?? raw["reasoningEffort"]?.stringValue
                )
            }
            if let selectedCollaborationMode,
               !collaborationModes.contains(where: { $0.name == selectedCollaborationMode }) {
                self.selectedCollaborationMode = nil
            }
        } catch {
            // Collaboration presets are experimental. Keep ordinary model and
            // effort controls usable if an older compatible server omits them.
            appendRuntime("Collaboration presets unavailable: \(error.localizedDescription)")
        }
    }

    func selectModel(_ id: String) {
        guard availableModels.contains(where: { $0.id == id }) else { return }
        selectedModelID = id
        selectedCollaborationMode = nil
        normalizeModelSelections(forceDefaults: true)
    }

    func chooseFilesFolder() async {
        if demoMode {
            linkedFolderPhase = .linked(name: "CodexPad Demo")
            workspacePath = linkedFolderGuestPath
            UserDefaults.standard.set(true, forKey: CodexPadPreferenceKey.linkedFilesFolder)
            directoryPath = linkedFolderGuestPath
            if let selectedThreadID,
               let index = threads.firstIndex(where: { $0.id == selectedThreadID }) {
                threads[index].cwd = linkedFolderGuestPath
            }
            return
        }
        guard enginePhase.isReady else {
            errorBanner = "Start the local engine before linking a Files folder."
            return
        }

        linkedFolderPhase = .choosing
        do {
            try await requireSuccessfulCommand(["/bin/mkdir", "-p", linkedFolderGuestPath])
            _ = try? await runGuestCommand(["/bin/umount", linkedFolderGuestPath])
            // iSH's ios filesystem presents UIDocumentPicker here, stores the
            // security-scoped bookmark, and remounts it during the next boot.
            try await requireSuccessfulCommand(
                ["/bin/mount", "-t", "ios", "CodexPad Files", linkedFolderGuestPath],
                waitsForUser: true
            )
            workspacePath = linkedFolderGuestPath
            UserDefaults.standard.set(true, forKey: CodexPadPreferenceKey.linkedFilesFolder)
            linkedFolderPhase = .linked(
                name: UserDefaults.standard.string(forKey: CodexPadPreferenceKey.linkedFolderDisplayName)
                    ?? "Files workspace"
            )
            if let selectedThreadID {
                do {
                    _ = try await rpc.request(
                        method: "thread/settings/update",
                        params: .object([
                            "threadId": .string(selectedThreadID),
                            "cwd": .string(linkedFolderGuestPath)
                        ])
                    )
                    if let index = threads.firstIndex(where: { $0.id == selectedThreadID }) {
                        threads[index].cwd = linkedFolderGuestPath
                    }
                } catch {
                    appendRuntime("Folder linked; current thread kept its previous cwd: \(error.localizedDescription)")
                }
            }
            await loadDirectory(linkedFolderGuestPath)
            appendRuntime("Linked a Files folder at \(linkedFolderGuestPath)")
        } catch {
            linkedFolderPhase = .needsRelink(message: error.localizedDescription)
            report(error, context: "Could not link the Files folder")
        }
    }

    func unlinkFilesFolder() async {
        if !demoMode, enginePhase.isReady {
            do {
                try await requireSuccessfulCommand(["/bin/umount", linkedFolderGuestPath])
            } catch {
                report(error, context: "Could not unlink the Files folder")
                return
            }
        }
        UserDefaults.standard.set(false, forKey: CodexPadPreferenceKey.linkedFilesFolder)
        UserDefaults.standard.removeObject(forKey: CodexPadPreferenceKey.linkedFolderDisplayName)
        linkedFolderPhase = .disconnected
        workspacePath = "/root/workspace"
        if enginePhase.isReady {
            if let selectedThreadID {
                _ = try? await rpc.request(
                    method: "thread/settings/update",
                    params: .object([
                        "threadId": .string(selectedThreadID),
                        "cwd": .string(workspacePath)
                    ])
                )
                if let index = threads.firstIndex(where: { $0.id == selectedThreadID }) {
                    threads[index].cwd = workspacePath
                }
            }
            await loadDirectory(workspacePath)
        }
    }

    func featureDefaultParams(for method: String) -> String {
        let threadID = selectedThreadID ?? "<thread-id>"
        let path = workspacePath
        let value: JSONValue
        switch method {
        case "memory/reset", "remoteControl/status/read", "config/mcpServer/reload",
             "windowsSandbox/readiness", "account/logout", "account/rateLimits/read",
             "account/usage/read", "account/workspaceMessages/read",
             "externalAgentConfig/import/readHistories", "configRequirements/read":
            return "null"
        case "thread/start":
            value = .object([
                "cwd": .string(path),
                "approvalPolicy": .string("on-request"),
                "sandbox": .string("danger-full-access"),
                "serviceName": .string("codexpad")
            ])
        case "turn/start":
            value = .object([
                "threadId": .string(threadID),
                "input": .array([.object([
                    "type": .string("text"),
                    "text": .string(""),
                    "text_elements": .array([])
                ])])
            ])
        case "turn/steer":
            value = .object([
                "threadId": .string(threadID),
                "input": .array([.object([
                    "type": .string("text"),
                    "text": .string(""),
                    "text_elements": .array([])
                ])])
            ])
        case "turn/interrupt":
            value = .object([
                "threadId": .string(threadID),
                "turnId": .string(activeTurnID ?? "<turn-id>")
            ])
        case "review/start":
            value = .object([
                "threadId": .string(threadID),
                "target": .object(["type": .string("uncommittedChanges")]),
                "delivery": .string("inline")
            ])
        case "model/list":
            value = .object(["cursor": .null, "limit": .integer(100), "includeHidden": .bool(true)])
        case "fs/readFile", "fs/readDirectory", "fs/getMetadata":
            value = .object(["path": .string(path)])
        case "fs/createDirectory":
            value = .object(["path": .string("\(path)/new-folder")])
        case "fs/remove":
            value = .object(["path": .string("\(path)/<path>"), "recursive": .bool(false)])
        case "command/exec":
            value = .object([
                "command": .array([.string("/bin/pwd")]),
                "cwd": .string(path),
                "sandboxPolicy": .object(["type": .string("dangerFullAccess")])
            ])
        case "fuzzyFileSearch":
            value = .object([
                "query": .string(""),
                "roots": .array([.string(path)]),
                "cancellationToken": .null
            ])
        default:
            if method.hasPrefix("thread/") {
                value = .object(["threadId": .string(threadID)])
            } else {
                value = .object([:])
            }
        }
        return value.prettyPrinted
    }

    func executeFeature(method: String, parameters: String) async -> String {
        guard let feature = CodexFeatureCatalog.feature(method: method) else {
            return "Unknown method in the pinned Codex feature catalog."
        }
        if let reason = feature.incompatibilityReason { return reason }
        if feature.access == .automatic {
            return "This operation is managed automatically by the connection lifecycle."
        }
        guard let data = parameters.data(using: .utf8) else {
            return "Parameters are not valid UTF-8."
        }
        let params: JSONValue?
        do {
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            switch decoded {
            case .null: params = nil
            case .object: params = decoded
            default: return "Parameters must be a JSON object or null."
            }
        } catch {
            return "Invalid JSON: \(error.localizedDescription)"
        }

        if demoMode {
            let sample: JSONValue = .object([
                "demo": .bool(true),
                "method": .string(method),
                "params": params ?? .null
            ])
            recordProtocolEvent(method: "response/\(method)", payload: sample)
            return sample.prettyPrinted
        }
        guard enginePhase.isReady else { return "The local Codex engine is not connected." }
        do {
            let response = try await rpc.request(method: method, params: params)
            recordProtocolEvent(method: "response/\(method)", payload: response)
            return response.prettyPrinted
        } catch {
            let message = "\(method) failed: \(error.localizedDescription)"
            appendRuntime(message)
            return message
        }
    }

    func selectThread(_ id: String?) async {
        selectedThreadID = id
        guard let id else { return }
        await resumeThread(id)
        requestComposerFocus()
    }

    @discardableResult
    func createThread() async -> String? {
        guard enginePhase.isReady else {
            errorBanner = "Start the local engine before creating a thread."
            return nil
        }
        do {
            var params: [String: JSONValue] = [
                "cwd": .string(workspacePath),
                "approvalPolicy": .string("on-request"),
                // iSH cannot enforce Codex's Linux seccomp/namespace sandbox.
                // The iPad app container is the execution boundary; approvals
                // remain on-request for commands and file changes.
                "sandbox": .string("danger-full-access"),
                "personality": .string("pragmatic"),
                "serviceName": .string("codexpad")
            ]
            if let selectedModel {
                params["model"] = .string(selectedModel.model)
            }
            if let selectedServiceTier {
                params["serviceTier"] = .string(selectedServiceTier)
            }
            let response = try await rpc.request(
                method: "thread/start",
                params: .object(params)
            )
            guard let thread = response["thread"], let record = parseThread(thread) else {
                throw CodexRPCError(code: nil, message: "thread/start returned no thread")
            }
            upsertThread(record, atFront: true)
            selectedThreadID = record.id
            timelineByThread[record.id] = []
            requestComposerFocus()
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
            applyServerModelSelection(
                modelSlug: response["model"]?.stringValue,
                effort: response["reasoningEffort"]?.stringValue,
                serviceTier: response["serviceTier"]?.stringValue
            )
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
        requestComposerFocus()
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
            var params: [String: JSONValue] = [
                "threadId": .string(threadID),
                "clientUserMessageId": .string(clientID),
                "input": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(text),
                        "text_elements": .array([])
                    ])
                ])
            ]
            if let selectedModel {
                params["model"] = .string(selectedModel.model)
            }
            if let selectedServiceTier {
                params["serviceTier"] = .string(selectedServiceTier)
            }
            if let selectedReasoningEffort {
                params["effort"] = .string(selectedReasoningEffort)
            }
            if let collaborationModePayload {
                params["collaborationMode"] = collaborationModePayload
            }
            let response = try await rpc.request(
                method: "turn/start",
                params: .object(params)
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
        defer { requestComposerFocus() }
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

    func startReview() async {
        guard let threadID = selectedThreadID else {
            errorBanner = "Choose a thread before starting a review."
            return
        }
        if demoMode {
            appendRuntime("Started review of uncommitted changes")
            return
        }
        do {
            let response = try await rpc.request(
                method: "review/start",
                params: .object([
                    "threadId": .string(threadID),
                    "target": .object(["type": .string("uncommittedChanges")]),
                    "delivery": .string("inline")
                ])
            )
            activeTurnID = response["turn"]?["id"]?.stringValue
            isTurnRunning = true
        } catch {
            report(error, context: "Could not start the review")
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
                try await rpc.respondUnsupported(to: request.rpcID, method: request.method)
                pendingRequests.removeAll { $0.id == request.id }
            } catch {
                report(error, context: "Could not dismiss the unsupported request")
            }
            return
        }

        let result: JSONValue
        switch request.kind {
        case .command, .fileChange:
            let isLegacy = request.method == "applyPatchApproval" || request.method == "execCommandApproval"
            let decision: String = if isLegacy {
                switch choice {
                case .once: "approved"
                case .session: "approved_for_session"
                case .decline: "denied"
                case .cancel: "abort"
                }
            } else {
                switch choice {
                case .once: "accept"
                case .session: "acceptForSession"
                case .decline: "decline"
                case .cancel: "cancel"
                }
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
        case .advanced:
            return
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

    func answerAdvancedRequest(_ request: PendingServerRequest, resultText: String) async -> String? {
        guard let data = resultText.data(using: .utf8) else { return "Response is not valid UTF-8." }
        let result: JSONValue
        do {
            result = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            return "Invalid JSON response: \(error.localizedDescription)"
        }
        do {
            try await rpc.respond(to: request.rpcID, result: result)
            pendingRequests.removeAll { $0.id == request.id }
            return nil
        } catch {
            return "Could not answer \(request.method): \(error.localizedDescription)"
        }
    }

    func rejectAdvancedRequest(_ request: PendingServerRequest) async {
        do {
            try await rpc.respondUnsupported(to: request.rpcID, method: request.method)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            report(error, context: "Could not reject \(request.method)")
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
            await refreshModels()
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
        recordProtocolEvent(method: method, payload: params)
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
            requestComposerFocus()
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
        case "thread/settings/updated":
            let settings = params["threadSettings"] ?? .object([:])
            applyServerModelSelection(
                modelSlug: settings["model"]?.stringValue,
                effort: settings["effort"]?.stringValue,
                serviceTier: settings["serviceTier"]?.stringValue
            )
        case "serverRequest/resolved":
            if let id = params["requestId"] {
                pendingRequests.removeAll { $0.rpcID == id }
            }
        case "account/updated":
            account.authMode = params["authMode"]?.stringValue
            account.plan = params["planType"]?.stringValue
            Task { await refreshModels() }
        case "model/rerouted":
            applyServerModelSelection(
                modelSlug: params["toModel"]?.stringValue,
                effort: selectedReasoningEffort,
                serviceTier: selectedServiceTier
            )
            if let toModel = params["toModel"]?.stringValue {
                appendRuntime("Codex rerouted this turn to \(toModel)")
            }
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
        recordProtocolEvent(method: method, payload: params)
        if method == "currentTime/read" {
            Task {
                do {
                    try await rpc.respond(
                        to: id,
                        result: .object([
                            "currentTimeAt": .integer(Int64(Date.now.timeIntervalSince1970))
                        ])
                    )
                } catch {
                    report(error, context: "Could not provide the current time")
                }
            }
            return
        }

        let kind: ServerRequestKind
        let title: String
        switch method {
        case "item/commandExecution/requestApproval", "execCommandApproval":
            kind = .command
            title = "Run this command?"
        case "item/fileChange/requestApproval", "applyPatchApproval":
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
        case "item/tool/call":
            kind = .advanced
            title = "A client tool needs a result"
        case "account/chatgptAuthTokens/refresh":
            kind = .unsupported
            title = "External token refresh unavailable"
        case "attestation/generate":
            kind = .unsupported
            title = "Client attestation unavailable"
        default:
            // Future compatible requests remain visible and answerable instead
            // of deadlocking a turn. The update gate still requires an explicit
            // catalog decision before a newer Codex pin can merge.
            kind = .advanced
            title = "Codex needs an advanced client response"
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
            ?? params["command"]?.arrayValue?.compactMap(\.stringValue).joined(separator: " ")
            ?? params["cwd"]?.stringValue
            ?? params["permissions"]?.prettyPrinted
            ?? ""
        let request = PendingServerRequest(
            id: UUID().uuidString,
            rpcID: id,
            method: method,
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

    private var collaborationModePayload: JSONValue? {
        guard let selectedCollaborationMode,
              let preset = collaborationModes.first(where: { $0.name == selectedCollaborationMode }),
              let selectedModel else { return nil }
        return .object([
            "mode": .string(preset.mode ?? "default"),
            "settings": .object([
                "model": .string(preset.model ?? selectedModel.model),
                "reasoning_effort": (preset.reasoningEffort ?? selectedReasoningEffort).map(JSONValue.string) ?? .null,
                "developer_instructions": .null
            ])
        ])
    }

    private func parseModel(_ raw: JSONValue) -> CodexModelOption? {
        guard let id = raw["id"]?.stringValue,
              let model = raw["model"]?.stringValue else { return nil }
        let efforts = (raw["supportedReasoningEfforts"]?.arrayValue ?? []).compactMap { effort -> ReasoningEffortOption? in
            guard let name = effort["reasoningEffort"]?.stringValue else { return nil }
            return ReasoningEffortOption(
                effort: name,
                description: effort["description"]?.stringValue ?? name.capitalized
            )
        }
        let tiers = (raw["serviceTiers"]?.arrayValue ?? []).compactMap { tier -> ModelServiceTierOption? in
            guard let id = tier["id"]?.stringValue else { return nil }
            return ModelServiceTierOption(
                id: id,
                name: tier["name"]?.stringValue ?? id.capitalized,
                description: tier["description"]?.stringValue ?? ""
            )
        }
        return CodexModelOption(
            id: id,
            model: model,
            displayName: raw["displayName"]?.stringValue ?? model,
            description: raw["description"]?.stringValue ?? "",
            hidden: raw["hidden"]?.boolValue ?? false,
            reasoningEfforts: efforts,
            defaultReasoningEffort: raw["defaultReasoningEffort"]?.stringValue
                ?? efforts.first?.effort
                ?? "medium",
            inputModalities: (raw["inputModalities"]?.arrayValue ?? []).compactMap(\.stringValue),
            supportsPersonality: raw["supportsPersonality"]?.boolValue ?? false,
            serviceTiers: tiers,
            defaultServiceTier: raw["defaultServiceTier"]?.stringValue,
            isDefault: raw["isDefault"]?.boolValue ?? false
        )
    }

    private func normalizeModelSelections(forceDefaults: Bool = false) {
        guard let selectedModel else {
            selectedReasoningEffort = nil
            selectedServiceTier = nil
            return
        }
        if forceDefaults
            || !selectedModel.reasoningEfforts.contains(where: { $0.effort == selectedReasoningEffort }) {
            selectedReasoningEffort = selectedModel.defaultReasoningEffort
        }
        if forceDefaults
            || (selectedServiceTier != nil
                && !selectedModel.serviceTiers.contains(where: { $0.id == selectedServiceTier })) {
            selectedServiceTier = selectedModel.defaultServiceTier
        }
    }

    private func applyServerModelSelection(
        modelSlug: String?,
        effort: String?,
        serviceTier: String?
    ) {
        if let modelSlug,
           let match = availableModels.first(where: { $0.model == modelSlug || $0.id == modelSlug }) {
            selectedModelID = match.id
        }
        normalizeModelSelections()
        if let effort,
           selectedModel?.reasoningEfforts.contains(where: { $0.effort == effort }) == true {
            selectedReasoningEffort = effort
        }
        if let serviceTier,
           selectedModel?.serviceTiers.contains(where: { $0.id == serviceTier }) == true {
            selectedServiceTier = serviceTier
        } else if serviceTier == nil {
            selectedServiceTier = nil
        }
    }

    private func restoreLinkedFolderState() async {
        guard UserDefaults.standard.bool(forKey: CodexPadPreferenceKey.linkedFilesFolder) else {
            linkedFolderPhase = .disconnected
            return
        }
        do {
            try await requireSuccessfulCommand(["/bin/mountpoint", "-q", linkedFolderGuestPath])
            linkedFolderPhase = .linked(
                name: UserDefaults.standard.string(forKey: CodexPadPreferenceKey.linkedFolderDisplayName)
                    ?? "Files workspace"
            )
            workspacePath = linkedFolderGuestPath
        } catch {
            linkedFolderPhase = .needsRelink(
                message: "The saved Files permission needs to be selected again."
            )
            workspacePath = "/root/workspace"
            appendRuntime("Saved Files workspace was not mounted: \(error.localizedDescription)")
        }
    }

    private func runGuestCommand(_ command: [String], waitsForUser: Bool = false) async throws -> JSONValue {
        var params: [String: JSONValue] = [
            "command": .array(command.map(JSONValue.string)),
            "sandboxPolicy": .object(["type": .string("dangerFullAccess")])
        ]
        if waitsForUser {
            params["disableTimeout"] = .bool(true)
        } else {
            params["timeoutMs"] = .integer(30_000)
        }
        return try await rpc.request(method: "command/exec", params: .object(params))
    }

    private func requireSuccessfulCommand(_ command: [String], waitsForUser: Bool = false) async throws {
        let response = try await runGuestCommand(command, waitsForUser: waitsForUser)
        guard response["exitCode"]?.intValue == 0 else {
            let detail = response["stderr"]?.stringValue
                ?? response["stdout"]?.stringValue
                ?? "Guest command failed"
            throw CodexRPCError(code: response["exitCode"]?.intValue, message: detail)
        }
    }

    private func persistOptional(_ value: String?, key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func recordProtocolEvent(method: String, payload: JSONValue) {
        protocolEvents.append(
            ProtocolEvent(
                id: UUID().uuidString,
                method: method,
                payload: payload.prettyPrinted,
                timestamp: .now
            )
        )
        if protocolEvents.count > 200 {
            protocolEvents.removeFirst(protocolEvents.count - 200)
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
        availableModels = [
            CodexModelOption(
                id: "gpt-5.3-codex", model: "gpt-5.3-codex", displayName: "GPT-5.3-Codex",
                description: "Most capable Codex model", hidden: false,
                reasoningEfforts: [
                    ReasoningEffortOption(effort: "medium", description: "Balanced speed and depth"),
                    ReasoningEffortOption(effort: "high", description: "Deeper reasoning"),
                    ReasoningEffortOption(effort: "ultra", description: "Proactive multi-agent reasoning")
                ],
                defaultReasoningEffort: "medium", inputModalities: ["text", "image"],
                supportsPersonality: true,
                serviceTiers: [ModelServiceTierOption(id: "fast", name: "Fast", description: "Priority latency")],
                defaultServiceTier: nil, isDefault: true
            ),
            CodexModelOption(
                id: "gpt-5.2-codex", model: "gpt-5.2-codex", displayName: "GPT-5.2-Codex",
                description: "Stable Codex model", hidden: false,
                reasoningEfforts: [ReasoningEffortOption(effort: "medium", description: "Balanced")],
                defaultReasoningEffort: "medium", inputModalities: ["text", "image"],
                supportsPersonality: true, serviceTiers: [], defaultServiceTier: nil, isDefault: false
            ),
            CodexModelOption(
                id: "codex-legacy-hidden", model: "codex-legacy-hidden", displayName: "Legacy Codex",
                description: "Hidden provider entry", hidden: true,
                reasoningEfforts: [ReasoningEffortOption(effort: "low", description: "Low latency")],
                defaultReasoningEffort: "low", inputModalities: ["text"],
                supportsPersonality: false, serviceTiers: [], defaultServiceTier: nil, isDefault: false
            )
        ]
        selectedModelID = availableModels.first?.id
        selectedReasoningEffort = availableModels.first?.defaultReasoningEffort
        collaborationModes = [
            CollaborationModeOption(name: "Default", mode: "default", model: nil, reasoningEffort: nil),
            CollaborationModeOption(name: "Plan", mode: "plan", model: nil, reasoningEffort: "high")
        ]
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
                method: "item/commandExecution/requestApproval",
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
