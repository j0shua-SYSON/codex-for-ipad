import Foundation

enum EnginePhase: Equatable {
    case starting
    case connecting(attempt: Int)
    case ready
    case offline(message: String)

    var title: String {
        switch self {
        case .starting: "Starting local Linux"
        case .connecting: "Connecting to Codex"
        case .ready: "On-device"
        case .offline: "Engine paused"
        }
    }

    var isReady: Bool {
        self == .ready
    }
}

enum ThreadActivity: String, Equatable, Sendable {
    case idle
    case running
    case waiting
    case offline
    case failed
}

struct CodexThreadRecord: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var preview: String
    var cwd: String
    var updatedAt: Date
    var activity: ThreadActivity
    var agentNickname: String?
}

enum TimelineKind: String, Equatable, Sendable {
    case user
    case agent
    case reasoning
    case plan
    case command
    case fileChange
    case tool
    case search
    case notice
}

enum TimelineState: String, Equatable, Sendable {
    case pending
    case running
    case completed
    case failed
    case declined
}

struct TimelineItem: Identifiable, Equatable, Sendable {
    let id: String
    var kind: TimelineKind
    var title: String
    var body: String
    var detail: String
    var state: TimelineState
    var timestamp: Date
}

struct PlanStep: Identifiable, Equatable, Sendable {
    let id: String
    var text: String
    var status: String

    var isComplete: Bool { status == "completed" }
}

struct WorkspaceEntry: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var path: String
    var isDirectory: Bool
    var isFile: Bool
}

enum ServerRequestKind: String, Equatable, Sendable {
    case command
    case fileChange
    case permissions
    case question
    case elicitation
    case advanced
    case unsupported
}

struct InputQuestion: Identifiable, Equatable, Sendable {
    let id: String
    var header: String
    var prompt: String
    var options: [String]
    var allowsFreeform: Bool
    var isSecret: Bool
}

struct PendingServerRequest: Identifiable, Equatable, Sendable {
    let id: String
    let rpcID: JSONValue
    var method: String
    var kind: ServerRequestKind
    var threadID: String?
    var title: String
    var message: String
    var detail: String
    var questions: [InputQuestion]
    var rawParams: JSONValue
}

struct ReasoningEffortOption: Identifiable, Equatable, Sendable {
    var id: String { effort }
    var effort: String
    var description: String
}

struct ModelServiceTierOption: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var description: String
}

struct CodexModelOption: Identifiable, Equatable, Sendable {
    var id: String
    var model: String
    var displayName: String
    var description: String
    var hidden: Bool
    var reasoningEfforts: [ReasoningEffortOption]
    var defaultReasoningEffort: String
    var inputModalities: [String]
    var supportsPersonality: Bool
    var serviceTiers: [ModelServiceTierOption]
    var defaultServiceTier: String?
    var isDefault: Bool
}

struct CollaborationModeOption: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var mode: String?
    var model: String?
    var reasoningEffort: String?
}

enum LinkedFolderPhase: Equatable, Sendable {
    case disconnected
    case choosing
    case linked(name: String)
    case needsRelink(message: String)

    var isLinked: Bool {
        if case .linked = self { return true }
        return false
    }
}

struct ProtocolEvent: Identifiable, Equatable, Sendable {
    let id: String
    var method: String
    var payload: String
    var timestamp: Date
}

struct AccountSummary: Equatable, Sendable {
    var authMode: String?
    var email: String?
    var plan: String?

    var displayName: String {
        email ?? plan?.capitalized ?? "Sign in"
    }

    var isAuthenticated: Bool { authMode != nil }
}

enum WorkbenchTab: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case changes = "Changes"
    case files = "Files"
    case runtime = "Runtime"

    var id: Self { self }
}

enum ApprovalChoice: String {
    case once
    case session
    case decline
    case cancel
}
