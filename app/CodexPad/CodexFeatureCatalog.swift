import Foundation

enum CodexFeatureCategory: String, CaseIterable, Identifiable, Sendable {
    case threads = "Threads & turns"
    case models = "Models & collaboration"
    case files = "Files & search"
    case extensions = "Skills, apps & plugins"
    case mcp = "MCP & environments"
    case account = "Account & configuration"
    case runtime = "Commands & processes"
    case remote = "Remote control"
    case system = "System & compatibility"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .threads: "bubble.left.and.text.bubble.right"
        case .models: "cpu"
        case .files: "folder"
        case .extensions: "puzzlepiece.extension"
        case .mcp: "point.3.connected.trianglepath.dotted"
        case .account: "person.crop.circle"
        case .runtime: "terminal"
        case .remote: "antenna.radiowaves.left.and.right"
        case .system: "gearshape.2"
        }
    }
}

enum CodexFeatureAccess: String, Sendable {
    case native = "Native"
    case advanced = "Advanced"
    case automatic = "Automatic"
    case incompatible = "Unavailable"
}

struct CodexFeatureDefinition: Identifiable, Equatable, Sendable {
    var id: String { method }
    var method: String
    var title: String
    var summary: String
    var category: CodexFeatureCategory
    var access: CodexFeatureAccess
    var location: String?
    var incompatibilityReason: String?

    var isDestructive: Bool {
        let destructiveFragments = [
            "/delete", "/remove", "/uninstall", "/terminate", "/kill",
            "/revoke", "memory/reset", "account/logout", "config/batchWrite"
        ]
        return destructiveFragments.contains { method.contains($0) }
    }
}

enum CodexFeatureCatalog {
    // Keep these blocks literal. scripts/validate-codex-protocol.py compares
    // them with the pinned stable schema and the complete Rust request macro.
    // CODEXPAD_CLIENT_METHODS_BEGIN
    private static let clientMethodLines = """
    initialize
    thread/start
    thread/resume
    thread/fork
    thread/archive
    thread/delete
    thread/unsubscribe
    thread/increment_elicitation
    thread/decrement_elicitation
    thread/name/set
    thread/goal/set
    thread/goal/get
    thread/goal/clear
    thread/metadata/update
    thread/settings/update
    thread/memoryMode/set
    memory/reset
    thread/unarchive
    thread/compact/start
    thread/shellCommand
    thread/approveGuardianDeniedAction
    thread/backgroundTerminals/clean
    thread/backgroundTerminals/list
    thread/backgroundTerminals/terminate
    thread/rollback
    thread/list
    thread/search
    thread/searchOccurrences
    thread/loaded/list
    thread/read
    thread/turns/list
    thread/items/list
    thread/inject_items
    skills/list
    skills/extraRoots/set
    hooks/list
    marketplace/add
    marketplace/remove
    marketplace/upgrade
    plugin/list
    plugin/installed
    plugin/read
    plugin/skill/read
    plugin/share/save
    plugin/share/updateTargets
    plugin/share/list
    plugin/share/checkout
    plugin/share/delete
    app/read
    app/list
    app/installed
    fs/readFile
    fs/writeFile
    fs/createDirectory
    fs/getMetadata
    fs/readDirectory
    fs/remove
    fs/copy
    fs/watch
    fs/unwatch
    skills/config/write
    plugin/install
    plugin/uninstall
    turn/start
    turn/steer
    turn/interrupt
    thread/realtime/start
    thread/realtime/appendAudio
    thread/realtime/appendText
    thread/realtime/appendSpeech
    thread/realtime/stop
    thread/realtime/listVoices
    review/start
    model/list
    modelProvider/capabilities/read
    experimentalFeature/list
    permissionProfile/list
    experimentalFeature/enablement/set
    remoteControl/enable
    remoteControl/disable
    remoteControl/status/read
    remoteControl/pairing/start
    remoteControl/pairing/status
    remoteControl/client/list
    remoteControl/client/revoke
    collaborationMode/list
    mock/experimentalMethod
    environment/add
    environment/info
    environment/status
    mcpServer/oauth/login
    config/mcpServer/reload
    mcpServerStatus/list
    mcpServer/resource/read
    mcpServer/tool/call
    windowsSandbox/setupStart
    windowsSandbox/readiness
    account/login/start
    account/login/cancel
    account/logout
    account/rateLimits/read
    account/rateLimitResetCredit/consume
    account/usage/read
    account/workspaceMessages/read
    account/sendAddCreditsNudgeEmail
    feedback/upload
    command/exec
    command/exec/write
    command/exec/terminate
    command/exec/resize
    process/spawn
    process/writeStdin
    process/kill
    process/resizePty
    config/read
    externalAgentConfig/detect
    externalAgentConfig/import
    externalAgentConfig/import/readHistories
    config/value/write
    config/batchWrite
    configRequirements/read
    account/read
    getConversationSummary
    gitDiffToRemote
    getAuthStatus
    fuzzyFileSearch
    fuzzyFileSearch/sessionStart
    fuzzyFileSearch/sessionUpdate
    fuzzyFileSearch/sessionStop
    """
    // CODEXPAD_CLIENT_METHODS_END

    // CODEXPAD_SERVER_REQUESTS_BEGIN
    private static let serverRequestLines = """
    item/commandExecution/requestApproval
    item/fileChange/requestApproval
    item/tool/requestUserInput
    mcpServer/elicitation/request
    item/permissions/requestApproval
    item/tool/call
    account/chatgptAuthTokens/refresh
    attestation/generate
    currentTime/read
    applyPatchApproval
    execCommandApproval
    """
    // CODEXPAD_SERVER_REQUESTS_END

    // CODEXPAD_SERVER_NOTIFICATIONS_BEGIN
    private static let serverNotificationLines = """
    error
    thread/started
    thread/status/changed
    thread/archived
    thread/deleted
    thread/unarchived
    thread/closed
    skills/changed
    thread/name/updated
    thread/goal/updated
    thread/goal/cleared
    thread/environment/connected
    thread/environment/disconnected
    thread/settings/updated
    thread/tokenUsage/updated
    turn/started
    hook/started
    turn/completed
    hook/completed
    turn/diff/updated
    turn/plan/updated
    item/started
    item/autoApprovalReview/started
    item/autoApprovalReview/completed
    item/completed
    rawResponseItem/completed
    rawResponse/completed
    item/agentMessage/delta
    item/plan/delta
    command/exec/outputDelta
    process/outputDelta
    process/exited
    item/commandExecution/outputDelta
    item/commandExecution/terminalInteraction
    item/fileChange/outputDelta
    item/fileChange/patchUpdated
    serverRequest/resolved
    item/mcpToolCall/progress
    mcpServer/oauthLogin/completed
    mcpServer/startupStatus/updated
    account/updated
    account/rateLimits/updated
    app/list/updated
    remoteControl/status/changed
    externalAgentConfig/import/progress
    externalAgentConfig/import/completed
    fs/changed
    item/reasoning/summaryTextDelta
    item/reasoning/summaryPartAdded
    item/reasoning/textDelta
    thread/compacted
    model/rerouted
    model/verification
    turn/moderationMetadata
    model/safetyBuffering/updated
    warning
    guardianWarning
    deprecationNotice
    configWarning
    fuzzyFileSearch/sessionUpdated
    fuzzyFileSearch/sessionCompleted
    thread/realtime/started
    thread/realtime/itemAdded
    thread/realtime/transcript/delta
    thread/realtime/transcript/done
    thread/realtime/outputAudio/delta
    thread/realtime/sdp
    thread/realtime/error
    thread/realtime/closed
    windows/worldWritableWarning
    windowsSandbox/setupCompleted
    account/login/completed
    """
    // CODEXPAD_SERVER_NOTIFICATIONS_END

    static let clientMethods = lines(clientMethodLines)
    static let serverRequests = lines(serverRequestLines)
    static let serverNotifications = lines(serverNotificationLines)

    private static let nativeMethods: Set<String> = [
        "thread/start", "thread/resume", "thread/archive", "thread/list",
        "thread/read", "turn/start", "turn/interrupt", "review/start",
        "model/list", "collaborationMode/list", "fs/readFile",
        "fs/readDirectory", "account/login/start", "account/logout",
        "account/read", "command/exec"
    ]

    private static let nativeLocations: [String: String] = [
        "thread/start": "New thread button",
        "thread/resume": "Thread browser",
        "thread/archive": "Thread context menu",
        "thread/list": "Thread browser",
        "thread/read": "Conversation",
        "turn/start": "Composer",
        "turn/interrupt": "Composer stop button",
        "review/start": "Changes workbench",
        "model/list": "Composer model picker",
        "collaborationMode/list": "Composer collaboration picker",
        "fs/readFile": "Files workbench",
        "fs/readDirectory": "Files workbench",
        "account/login/start": "Settings > Account",
        "account/logout": "Settings > Account",
        "account/read": "Settings > Account",
        "command/exec": "Files bridge and Advanced controls"
    ]

    private static let incompatibleReasons: [String: String] = [
        "windowsSandbox/setupStart": "Windows sandbox setup cannot run on iPadOS or Alpine/iSH.",
        "windowsSandbox/readiness": "Windows sandbox readiness is not meaningful on iPadOS.",
        "mock/experimentalMethod": "Upstream marks this as a protocol test fixture, not a user feature."
    ]

    static let features: [CodexFeatureDefinition] = clientMethods.map { method in
        let access: CodexFeatureAccess
        if incompatibleReasons[method] != nil {
            access = .incompatible
        } else if method == "initialize" {
            access = .automatic
        } else if nativeMethods.contains(method) {
            access = .native
        } else {
            access = .advanced
        }
        return CodexFeatureDefinition(
            method: method,
            title: title(for: method),
            summary: summary(for: method),
            category: category(for: method),
            access: access,
            location: nativeLocations[method] ?? (method == "initialize" ? "Runs when the local engine connects" : nil),
            incompatibilityReason: incompatibleReasons[method]
        )
    }

    static var compatibleFeatureCount: Int {
        features.filter { $0.access != .incompatible && $0.access != .automatic }.count
    }

    static var unavailableFeatureCount: Int {
        features.filter { $0.access == .incompatible }.count
    }

    static func feature(method: String) -> CodexFeatureDefinition? {
        features.first { $0.method == method }
    }

    private static func lines(_ value: String) -> [String] {
        value.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    private static func category(for method: String) -> CodexFeatureCategory {
        if method.hasPrefix("thread/") || method.hasPrefix("turn/") || method == "review/start" || method == "getConversationSummary" {
            return .threads
        }
        if method.hasPrefix("model") || method.hasPrefix("collaboration") || method.hasPrefix("experimentalFeature") || method.hasPrefix("permissionProfile") {
            return .models
        }
        if method.hasPrefix("fs/") || method.hasPrefix("fuzzyFileSearch") || method == "gitDiffToRemote" {
            return .files
        }
        if method.hasPrefix("skills/") || method.hasPrefix("hooks/") || method.hasPrefix("marketplace/") || method.hasPrefix("plugin/") || method.hasPrefix("app/") {
            return .extensions
        }
        if method.hasPrefix("mcpServer") || method.hasPrefix("config/mcpServer") || method.hasPrefix("environment/") {
            return .mcp
        }
        if method.hasPrefix("account/") || method.hasPrefix("config") || method.hasPrefix("externalAgentConfig") || method == "getAuthStatus" || method == "feedback/upload" {
            return .account
        }
        if method.hasPrefix("command/") || method.hasPrefix("process/") {
            return .runtime
        }
        if method.hasPrefix("remoteControl/") {
            return .remote
        }
        return .system
    }

    private static func title(for method: String) -> String {
        let leaf = method.split(separator: "/").last.map(String.init) ?? method
        let normalized = leaf.replacingOccurrences(of: "_", with: " ")
        var words = ""
        for character in normalized {
            if character.isUppercase, !words.isEmpty, words.last != " " {
                words.append(" ")
            }
            words.append(character)
        }
        return words.prefix(1).uppercased() + String(words.dropFirst())
    }

    private static func summary(for method: String) -> String {
        switch method {
        case "model/list": "Loads every model, reasoning effort, modality, and service tier exposed by the connected Codex provider."
        case "collaborationMode/list": "Loads the collaboration presets supported by this Codex build."
        case "review/start": "Starts a native Codex review for uncommitted changes, a base branch, a commit, or custom instructions."
        case "skills/list": "Lists skills discovered in the active workspace and configured extra roots."
        case "plugin/list", "plugin/installed": "Reads the Codex plugin catalog and installed plugin state."
        case "app/list", "app/installed": "Reads available and installed Codex apps."
        case "mcpServerStatus/list": "Reads configured MCP servers, tools, resources, and authentication status."
        case "remoteControl/enable": "Enables Codex remote control for this local app-server session."
        case "command/exec": "Runs an argv-based standalone command and returns structured stdout, stderr, and exit status."
        case "process/spawn": "Starts an interactive standalone guest process with streamed events."
        case "initialize": "Negotiates the pinned v2 protocol and experimental capability set."
        default: "Exposes the pinned Codex app-server “\(method)” operation through a native, searchable request surface."
        }
    }
}
