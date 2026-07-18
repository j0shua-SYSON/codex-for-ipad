import SwiftUI
import UIKit

struct CodexPadRootView: View {
    @ObservedObject var model: CodexWorkspaceModel
    let showTerminal: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsWorkbench = false
    @State private var didConfigureInitialLayout = false
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            CodexConversationView(model: model)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Task { await model.createThread() }
                        } label: {
                            Label("New thread", systemImage: "square.and.pencil")
                        }
                        .accessibilityIdentifier("codexpad.new-thread")
                        .keyboardShortcut("n", modifiers: .command)
                        .disabled(!model.enginePhase.isReady)

                        Button(action: showTerminal) {
                            Label("Terminal", systemImage: "terminal")
                        }
                        .accessibilityIdentifier("codexpad.terminal")
                        .keyboardShortcut("t", modifiers: [.command, .shift])

                        Button {
                            showsWorkbench.toggle()
                        } label: {
                            Label(
                                showsWorkbench ? "Hide workbench" : "Show workbench",
                                systemImage: "sidebar.right"
                            )
                        }
                        .accessibilityIdentifier("codexpad.toggle-workbench")
                        .accessibilityValue(showsWorkbench ? "Shown" : "Hidden")
                        .keyboardShortcut("i", modifiers: [.command, .option])
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $showsWorkbench) {
            CodexWorkbenchView(model: model)
                .inspectorColumnWidth(min: 320, ideal: 420, max: 520)
        }
        .accessibilityIdentifier("codexpad.workspace")
        .tint(CodexPalette.cobalt)
        .background(CodexPalette.canvas)
        .sheet(isPresented: $model.showsSettings) {
            CodexSettingsView(model: model)
        }
        .task {
            configureInitialLayout()
            await model.start()
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            prioritizeConversationIfNeeded()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            prioritizeConversationIfNeeded()
        }
        .onChange(of: model.loginURL) { _, url in
            if let url { openURL(url) }
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CODEX / LOCAL")
                            .font(.caption2.monospaced().weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(CodexPalette.secondaryInk)
                        Text("Workspace")
                            .font(.title2.bold())
                            .foregroundStyle(CodexPalette.ink)
                    }
                    Spacer()
                    EngineStatusPill(phase: model.enginePhase)
                }
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
            }

            Section("Recent threads") {
                ForEach(filteredThreads) { thread in
                    ThreadRow(thread: thread)
                        .tag(thread.id)
                        .contextMenu {
                            Button("Archive", systemImage: "archivebox") {
                                model.selectedThreadID = thread.id
                                Task { await model.archiveSelectedThread() }
                            }
                        }
                }
            }

            Section {
                Button {
                    model.showsSettings = true
                } label: {
                    Label(model.account.displayName, systemImage: model.account.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle.badge.questionmark")
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("codexpad.sidebar")
        .scrollContentBackground(.hidden)
        .background(CodexPalette.canvas)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search threads")
        .navigationTitle("CodexPad")
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.selectedThreadID },
            set: { id in
                Task { await model.selectThread(id) }
            }
        )
    }

    private var filteredThreads: [CodexThreadRecord] {
        guard !searchText.isEmpty else { return model.threads }
        return model.threads.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.cwd.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func prioritizeConversationIfNeeded() {
        if shouldPrioritizeConversation {
            showsWorkbench = false
        }
    }

    private func configureInitialLayout() {
        guard !didConfigureInitialLayout else {
            prioritizeConversationIfNeeded()
            return
        }
        didConfigureInitialLayout = true
        showsWorkbench = !shouldPrioritizeConversation
    }

    private var shouldPrioritizeConversation: Bool {
        dynamicTypeSize.isAccessibilitySize
            || horizontalSizeClass == .compact
            || UIScreen.main.bounds.width < 800
    }
}
