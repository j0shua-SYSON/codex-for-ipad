import SwiftUI

struct EngineStatusPill: View {
    let phase: EnginePhase

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .symbolEffect(.pulse, isActive: isAnimated)
            Text(phase.title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(color.opacity(0.11), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Engine status, \(phase.title)")
    }

    private var icon: String {
        switch phase {
        case .starting, .connecting: "bolt.horizontal.circle"
        case .ready: "ipad.and.arrow.forward"
        case .offline: "pause.circle"
        }
    }

    private var color: Color {
        switch phase {
        case .ready: CodexPalette.teal
        case .offline: CodexPalette.amber
        case .starting, .connecting: CodexPalette.cobalt
        }
    }

    private var isAnimated: Bool {
        switch phase {
        case .starting, .connecting: true
        default: false
        }
    }
}

struct ThreadRow: View {
    let thread: CodexThreadRecord

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: activityIcon)
                .font(.caption.weight(.bold))
                .foregroundStyle(activityColor)
                .frame(width: 18, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(thread.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(CodexPalette.ink)
                        .lineLimit(2)
                    if let nickname = thread.agentNickname {
                        Text(nickname)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CodexPalette.cobalt)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CodexPalette.cobalt.opacity(0.1), in: Capsule())
                    }
                }
                Text(thread.cwd.replacingOccurrences(of: "/root/workspace/", with: ""))
                    .font(.caption.monospaced())
                    .foregroundStyle(CodexPalette.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(thread.title), \(activityLabel), \(thread.cwd)")
    }

    private var activityIcon: String {
        switch thread.activity {
        case .idle: "circle"
        case .running: "play.circle.fill"
        case .waiting: "hand.raised.circle.fill"
        case .offline: "circle.dotted"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var activityColor: Color {
        switch thread.activity {
        case .idle, .offline: CodexPalette.secondaryInk
        case .running: CodexPalette.teal
        case .waiting: CodexPalette.amber
        case .failed: CodexPalette.danger
        }
    }

    private var activityLabel: String {
        switch thread.activity {
        case .idle: "idle"
        case .running: "running"
        case .waiting: "waiting for approval"
        case .offline: "not loaded"
        case .failed: "failed"
        }
    }
}

struct TimelineCard: View {
    let item: TimelineItem
    let isFirst: Bool
    let isLast: Bool

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ActivityLoomMark(
                kind: item.kind,
                state: item.state,
                isFirst: isFirst,
                isLast: isLast
            )
            card
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var card: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Label(item.title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: 12)
                Label(stateLabel, systemImage: stateIcon)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(CodexPalette.secondaryInk)
            }

            if item.kind == .reasoning {
                DisclosureGroup("Show reasoning summary") {
                    bodyText
                        .padding(.top, 8)
                }
                .font(.subheadline)
            } else if !item.body.isEmpty {
                bodyText
            }

            if !item.detail.isEmpty {
                ScrollView(.horizontal) {
                    Text(item.detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(CodexPalette.ink)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(CodexPalette.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityLabel("Output")
            }
        }
        .codexPanel(padding: 15)
        .overlay(alignment: .leading) {
            if differentiateWithoutColor && item.state == .failed {
                Rectangle().fill(CodexPalette.danger).frame(width: 4).clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var bodyText: some View {
        if item.kind == .command {
            Text(item.body)
                .font(.callout.monospaced())
                .foregroundStyle(CodexPalette.ink)
                .textSelection(.enabled)
        } else if let attributed = try? AttributedString(markdown: item.body) {
            Text(attributed)
                .font(.body)
                .foregroundStyle(CodexPalette.ink)
                .textSelection(.enabled)
        } else {
            Text(item.body)
                .font(.body)
                .foregroundStyle(CodexPalette.ink)
                .textSelection(.enabled)
        }
    }

    private var icon: String {
        switch item.kind {
        case .user: "person.fill"
        case .agent: "sparkles"
        case .reasoning: "brain.head.profile"
        case .plan: "checklist"
        case .command: "terminal"
        case .fileChange: "doc.badge.gearshape"
        case .tool: "wrench.and.screwdriver"
        case .search: "globe"
        case .notice: "info.circle"
        }
    }

    private var accent: Color {
        switch item.kind {
        case .user: CodexPalette.secondaryInk
        case .agent, .plan: CodexPalette.cobalt
        case .command, .tool: CodexPalette.teal
        case .fileChange: CodexPalette.amber
        case .reasoning, .search, .notice: CodexPalette.secondaryInk
        }
    }

    private var stateIcon: String {
        switch item.state {
        case .pending: "clock"
        case .running: "arrow.trianglehead.2.clockwise.rotate.90"
        case .completed: "checkmark"
        case .failed: "xmark"
        case .declined: "hand.raised"
        }
    }

    private var stateLabel: String {
        switch item.state {
        case .pending: "Pending"
        case .running: "Running"
        case .completed: "Done"
        case .failed: "Failed"
        case .declined: "Declined"
        }
    }
}

private struct ActivityLoomMark: View {
    let kind: TimelineKind
    let state: TimelineState
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : CodexPalette.line)
                .frame(width: 2, height: 8)
            ZStack {
                Circle()
                    .fill(CodexPalette.canvas)
                    .frame(width: 27, height: 27)
                Circle()
                    .strokeBorder(nodeColor, lineWidth: state == .running ? 3 : 2)
                    .frame(width: 21, height: 21)
                if state == .completed {
                    Circle().fill(nodeColor).frame(width: 7, height: 7)
                }
            }
            Rectangle()
                .fill(isLast ? Color.clear : CodexPalette.line)
                .frame(width: 2)
        }
        .frame(width: 28)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private var nodeColor: Color {
        switch kind {
        case .agent, .plan: CodexPalette.cobalt
        case .command, .tool: CodexPalette.teal
        case .fileChange: CodexPalette.amber
        default: CodexPalette.secondaryInk
        }
    }
}

struct ApprovalRequestCard: View {
    let request: PendingServerRequest
    let resolve: (ApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(request.title, systemImage: request.kind == .fileChange ? "doc.badge.gearshape" : "hand.raised.fill")
                .font(.headline)
                .foregroundStyle(CodexPalette.amber)
            Text(request.message)
                .font(.body)
                .foregroundStyle(CodexPalette.ink)
            if !request.detail.isEmpty {
                Text(request.detail)
                    .font(.callout.monospaced())
                    .foregroundStyle(CodexPalette.ink)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CodexPalette.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    actionButtons
                }
                VStack(alignment: .leading) {
                    actionButtons
                }
            }
        }
        .codexPanel()
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CodexPalette.amber.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch request.kind {
        case .elicitation:
            Button("Decline") { resolve(.decline) }
                .buttonStyle(.borderedProminent)
                .tint(CodexPalette.cobalt)
            Button("Cancel request", role: .cancel) { resolve(.cancel) }
                .buttonStyle(.bordered)
        case .unsupported:
            Button("Dismiss") { resolve(.decline) }
                .buttonStyle(.bordered)
        default:
            Button("Allow once") { resolve(.once) }
                .buttonStyle(.borderedProminent)
                .tint(CodexPalette.cobalt)
            Button("Allow for thread") { resolve(.session) }
                .buttonStyle(.bordered)
            Button("Don’t allow", role: .destructive) { resolve(.decline) }
                .buttonStyle(.bordered)
        }
    }
}

struct QuestionRequestCard: View {
    let request: PendingServerRequest
    let submit: ([String: String]) -> Void

    @State private var answers: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(request.title, systemImage: "questionmark.bubble.fill")
                .font(.headline)
                .foregroundStyle(CodexPalette.cobalt)
            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.header)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CodexPalette.secondaryInk)
                        .textCase(.uppercase)
                    Text(question.prompt)
                        .font(.body)
                    if !question.options.isEmpty {
                        Picker(question.header, selection: answerBinding(for: question.id)) {
                            Text("Choose").tag("")
                            ForEach(question.options, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if question.allowsFreeform || question.options.isEmpty {
                        if question.isSecret {
                            SecureField("Your answer", text: answerBinding(for: question.id))
                                .textFieldStyle(.roundedBorder)
                        } else {
                            TextField("Your answer", text: answerBinding(for: question.id), axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            Button("Send answers") { submit(answers) }
                .buttonStyle(.borderedProminent)
                .disabled(request.questions.contains { answers[$0.id, default: ""].isEmpty })
        }
        .codexPanel()
    }

    private func answerBinding(for id: String) -> Binding<String> {
        Binding(
            get: { answers[id, default: ""] },
            set: { answers[id] = $0 }
        )
    }
}

struct AdvancedServerRequestCard: View {
    let request: PendingServerRequest
    let submit: (String) async -> String?
    let reject: () -> Void

    @State private var resultText = ""
    @State private var validationError: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(request.title, systemImage: "curlybraces.square")
                .font(.headline)
                .foregroundStyle(CodexPalette.cobalt)
            Text(request.method)
                .font(.caption.monospaced())
                .foregroundStyle(CodexPalette.secondaryInk)
                .textSelection(.enabled)
            Text(request.message)
                .font(.body)
            DisclosureGroup("Request parameters") {
                Text(request.rawParams.prettyPrinted)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            TextEditor(text: $resultText)
                .font(.callout.monospaced())
                .frame(minHeight: 130)
                .padding(8)
                .background(CodexPalette.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(CodexPalette.line, lineWidth: 0.5)
                }
                .accessibilityLabel("JSON response for \(request.method)")

            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(CodexPalette.danger)
            }

            ViewThatFits(in: .horizontal) {
                HStack { actionButtons }
                VStack(alignment: .leading) { actionButtons }
            }
        }
        .codexPanel()
        .task {
            if request.method == "item/tool/call" {
                resultText = JSONValue.object([
                    "contentItems": .array([.object([
                        "type": .string("inputText"),
                        "text": .string("")
                    ])]),
                    "success": .bool(true)
                ]).prettyPrinted
            } else {
                resultText = "{}"
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            isSubmitting = true
            validationError = nil
            Task {
                validationError = await submit(resultText)
                isSubmitting = false
            }
        } label: {
            if isSubmitting {
                ProgressView().controlSize(.small)
            } else {
                Text("Send JSON response")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSubmitting || resultText.isEmpty)
        Button("Reject request", role: .destructive, action: reject)
            .buttonStyle(.bordered)
    }
}
