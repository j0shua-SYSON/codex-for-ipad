import SwiftUI

struct CodexConversationView: View {
    @ObservedObject var model: CodexWorkspaceModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !model.enginePhase.isReady {
                EngineUnavailableView(model: model)
            } else if let thread = model.selectedThread {
                conversation(thread)
            } else {
                WelcomeWorkspaceView(model: model)
            }
        }
        .background(CodexPalette.canvas)
        .navigationTitle(model.selectedThread?.title ?? "Workspace")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func conversation(_ thread: CodexThreadRecord) -> some View {
        VStack(spacing: 0) {
            conversationHeader(thread)
            Divider().overlay(CodexPalette.line)
            timeline
            ComposerBar(model: model)
        }
    }

    private func conversationHeader(_ thread: CodexThreadRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(thread.title)
                    .font(.headline)
                    .foregroundStyle(CodexPalette.ink)
                    .lineLimit(1)
                Label(thread.cwd, systemImage: "folder")
                    .font(.caption.monospaced())
                    .foregroundStyle(CodexPalette.secondaryInk)
                    .lineLimit(1)
            }
            Spacer()
            EngineStatusPill(phase: model.enginePhase)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(CodexPalette.surface)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let error = model.errorBanner {
                        ErrorBanner(message: error) {
                            model.errorBanner = nil
                        }
                        .padding(.bottom, 12)
                    }

                    let items = model.selectedTimeline
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        TimelineCard(
                            item: item,
                            isFirst: index == 0,
                            isLast: index == items.count - 1 && relevantRequests.isEmpty
                        )
                        .id(item.id)
                    }

                    ForEach(relevantRequests) { request in
                        if request.kind == .question {
                            QuestionRequestCard(request: request) { values in
                                Task { await model.answer(request, values: values) }
                            }
                        } else {
                            ApprovalRequestCard(request: request) { choice in
                                Task { await model.resolve(request, choice: choice) }
                            }
                        }
                    }

                    if model.isTurnRunning {
                        WorkingIndicator()
                            .id("working")
                    }
                    Color.clear.frame(height: 1).id("timeline-end")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: 840)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.selectedTimeline.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: model.pendingRequests.count) { _, _ in
                scrollToEnd(proxy)
            }
            .onChange(of: model.isTurnRunning) { _, _ in
                scrollToEnd(proxy)
            }
        }
    }

    private var relevantRequests: [PendingServerRequest] {
        model.pendingRequests.filter {
            $0.threadID == nil || $0.threadID == model.selectedThreadID
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo("timeline-end", anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.24)) {
                proxy.scrollTo("timeline-end", anchor: .bottom)
            }
        }
    }
}

private struct ComposerBar: View {
    @ObservedObject var model: CodexWorkspaceModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask Codex to change, explain, or verify…", text: $model.composerText, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...7)
                    .focused($isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(CodexPalette.raised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(isFocused ? CodexPalette.cobalt : CodexPalette.line, lineWidth: isFocused ? 1.5 : 0.5)
                    }
                    .accessibilityLabel("Message Codex")
                    .accessibilityIdentifier("codexpad.composer")

                if model.isTurnRunning {
                    Button {
                        Task { await model.interruptTurn() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CodexPalette.danger)
                    .keyboardShortcut(".", modifiers: .command)
                    .accessibilityLabel("Stop the current turn")
                } else {
                    Button {
                        Task { await model.sendComposer() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CodexPalette.cobalt)
                    .disabled(model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Send message")
                    .accessibilityIdentifier("codexpad.send")
                }
            }
            HStack {
                Label("Local iSH workspace", systemImage: "ipad")
                Spacer()
                Text("⌘↩ Send · ⌘. Stop")
            }
            .font(.caption2)
            .foregroundStyle(CodexPalette.secondaryInk)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.bar)
    }
}

private struct WorkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(CodexPalette.cobalt)
                .symbolEffect(.pulse, isActive: !reduceMotion)
            Text("Codex is working on-device")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CodexPalette.secondaryInk)
            Spacer()
        }
        .padding(.leading, 43)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codex is working on-device")
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CodexPalette.danger)
            Text(message)
                .font(.callout)
                .foregroundStyle(CodexPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Dismiss error")
        }
        .codexPanel(padding: 12)
    }
}

private struct WelcomeWorkspaceView: View {
    @ObservedObject var model: CodexWorkspaceModel

    var body: some View {
        ContentUnavailableView {
            Label("Start in your local workspace", systemImage: "ipad.gen2.landscape")
        } description: {
            Text("Codex runs inside the bundled iSH Linux environment. Create a thread to plan, edit, run commands, and review changes without a remote computer.")
        } actions: {
            Button("New thread") {
                Task { await model.createThread() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

private struct EngineUnavailableView: View {
    @ObservedObject var model: CodexWorkspaceModel

    var body: some View {
        ContentUnavailableView {
            Label(model.enginePhase.title, systemImage: "shippingbox.and.arrow.backward")
        } description: {
            switch model.enginePhase {
            case .offline(let message): Text(message)
            default: Text("Preparing Alpine, fakefs, and the local Codex app-server.")
            }
        } actions: {
            if case .offline = model.enginePhase {
                Button("Try again") {
                    Task { await model.retryConnection() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("Starting local Codex engine")
            }
        }
    }
}
