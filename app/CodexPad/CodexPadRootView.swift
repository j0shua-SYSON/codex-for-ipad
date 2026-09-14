import SwiftUI
import UIKit

struct CodexPadRootView: View {
    @ObservedObject var model: CodexWorkspaceModel
    let showTerminal: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showsWorkbench = false
    @State private var showsThreadBrowser = false
    @State private var didConfigureInitialLayout = false
    @State private var searchText = ""
    @State private var windowWidth: CGFloat = 0
    @State private var showsCompactWorkbench = false
    @State private var opensSettingsAfterBrowser = false
    @State private var showsRequests = false

    var body: some View {
        // Measure the containing window, not the detail area that shrinks
        // when an inspector opens. Measuring the latter dismisses the panel
        // as soon as it changes the layout on an 11-inch iPad.
        GeometryReader { geometry in
            workspaceContent
                    .onAppear { windowWidth = geometry.size.width; configureInitialLayout() }
                    .onChange(of: geometry.size.width) { _, width in
                        windowWidth = width
                        prioritizeConversationIfNeeded()
                    }
        }
    }

    private var workspaceContent: some View {
        adaptiveWorkspace
        .inspector(isPresented: $showsWorkbench) {
            CodexWorkbenchView(model: model)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
        .accessibilityIdentifier("codexpad.workspace")
        .tint(CodexPalette.cobalt)
        .background(CodexPalette.canvas)
        .sheet(isPresented: $model.showsSettings, onDismiss: {
            if model.opensFeaturesAfterSettings {
                model.opensFeaturesAfterSettings = false
                model.showsFeatureCenter = true
            } else { model.requestComposerFocus() }
        }) {
            CodexSettingsView(model: model)
        }
        .sheet(isPresented: $model.showsFeatureCenter, onDismiss: model.requestComposerFocus) {
            CodexFeatureCenterView(model: model)
        }
        .sheet(isPresented: $showsCompactWorkbench, onDismiss: model.requestComposerFocus) {
            NavigationStack {
                CodexWorkbenchView(model: model)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsCompactWorkbench = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showsRequests) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(model.pendingRequests) { request in
                            CodexServerRequestView(model: model, request: request)
                        }
                    }.padding()
                }
                .navigationTitle("Pending requests")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsRequests = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showsThreadBrowser, onDismiss: {
            if opensSettingsAfterBrowser {
                opensSettingsAfterBrowser = false
                model.showsSettings = true
            }
        }) {
            NavigationStack {
                sidebar
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showsThreadBrowser = false
                            }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
        .task {
            await model.start()
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            prioritizeConversationIfNeeded()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            prioritizeConversationIfNeeded()
        }
        .onChange(of: verticalSizeClass) { _, _ in
            prioritizeConversationIfNeeded()
        }
        .onChange(of: model.loginURL) { _, url in
            if let url { openURL(url) }
        }
    }

    @ViewBuilder
    private var adaptiveWorkspace: some View {
        if shouldPrioritizeConversation {
            NavigationStack {
                conversation
            }
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                conversation
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    private var conversation: some View {
        CodexConversationView(model: model)
            .toolbar {
                if shouldPrioritizeConversation {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showsThreadBrowser = true
                        } label: {
                            Label("Threads", systemImage: "sidebar.left")
                        }
                        .accessibilityIdentifier("codexpad.threads")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: showTerminal) {
                        Label("Terminal", systemImage: "terminal")
                    }
                    .accessibilityIdentifier("codexpad.terminal")
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("Account settings", systemImage: "person.crop.circle") { model.showsSettings = true }
                        Toggle("Desktop mode", isOn: $model.desktopModeEnabled)
                        if !model.desktopModeEnabled {
                            Toggle("Show all Codex features", isOn: $model.showAllFeaturesInTouchMode)
                        }
                    } label: {
                        Label(
                            model.desktopModeEnabled ? "Desktop mode" : "Touch mode",
                            systemImage: model.desktopModeEnabled ? "cursorarrow.rays" : "hand.tap"
                        )
                    }
                    .accessibilityIdentifier("codexpad.input-mode")

                    if !model.pendingRequests.isEmpty {
                        Button { showsRequests = true } label: {
                            Label("\(model.pendingRequests.count) pending requests", systemImage: "hand.raised")
                        }
                        .accessibilityIdentifier("codexpad.pending-requests")
                    }

                    if model.showsCompleteFeatureSet {
                        Button {
                            model.showsFeatureCenter = true
                        } label: {
                            Label("All Codex features", systemImage: "square.grid.3x3")
                        }
                        .accessibilityIdentifier("codexpad.features")
                        .keyboardShortcut(",", modifiers: [.command, .shift])
                    }

                    Button {
                        Task { await model.createThread() }
                    } label: {
                        Label("New thread", systemImage: "square.and.pencil")
                    }
                    .accessibilityIdentifier("codexpad.new-thread")
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!model.enginePhase.isReady || model.isCreatingThread)

                        Button {
                            if shouldPrioritizeConversation { showsCompactWorkbench = true }
                            else { showsWorkbench.toggle() }
                        } label: {
                            Label(
                                showsWorkbench || showsCompactWorkbench ? "Hide workbench" : "Show workbench",
                                systemImage: "sidebar.right"
                            )
                        }
                        .accessibilityIdentifier("codexpad.toggle-workbench")
                        .accessibilityValue(showsWorkbench || showsCompactWorkbench ? "Shown" : "Hidden")
                        .keyboardShortcut("i", modifiers: [.command, .option])
                }
            }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CODEX / LOCAL")
                            .font(.caption2.monospaced().weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(CodexPalette.secondaryInk)
                        Text("Workspace")
                            .font(.title2.bold())
                            .foregroundStyle(CodexPalette.ink)
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
                                    Task { await model.archiveThread(thread.id) }
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider().overlay(CodexPalette.line)
            Button {
                if showsThreadBrowser {
                    opensSettingsAfterBrowser = true
                    showsThreadBrowser = false
                } else { model.showsSettings = true }
            } label: {
                HStack {
                    Label(model.account.displayName, systemImage: model.account.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle.badge.questionmark")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CodexPalette.secondaryInk)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Account settings, \(model.account.displayName)")
            .accessibilityIdentifier("codexpad.settings")
            .buttonStyle(.plain)
            .background(.bar)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codexpad.sidebar")
        .background(CodexPalette.canvas)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search threads")
        .navigationTitle("CodexPad")
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.selectedThreadID },
            set: { id in
                if shouldPrioritizeConversation {
                    showsThreadBrowser = false
                }
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
        if shouldPrioritizeConversation || windowWidth < 1_100 {
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
            && windowWidth >= 1_100
    }

    private var shouldPrioritizeConversation: Bool {
        dynamicTypeSize.isAccessibilitySize
            || horizontalSizeClass == .compact
            || windowWidth < 800
    }
}
