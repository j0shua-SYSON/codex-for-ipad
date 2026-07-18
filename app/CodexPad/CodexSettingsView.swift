import SwiftUI

struct CodexSettingsView: View {
    @ObservedObject var model: CodexWorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var apiKey = ""
    @State private var confirmsUnlink = false

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                modelSection
                accountSection
                workspaceSection
                featureSection

                Section("Safety") {
                    Label("Commands and file writes require native approval when Codex requests it.", systemImage: "hand.raised")
                    Label("The app-server is bound only to 127.0.0.1 inside the app.", systemImage: "lock.shield")
                }

                Section("Platform behavior") {
                    Text("iPadOS may suspend active work when CodexPad is backgrounded. Keep the app visible for long turns and builds.")
                    Text("The terminal remains available as a recovery surface from the workspace toolbar.")
                }

                Section("Open source") {
                    LabeledContent("Codex", value: "Apache-2.0")
                    LabeledContent("iSH", value: "GPL with iOS permission")
                    Text("Source and third-party notices are included with every release.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Unlink the Files folder?",
                isPresented: $confirmsUnlink,
                titleVisibility: .visible
            ) {
                Button("Unlink", role: .destructive) {
                    Task { await model.unlinkFilesFolder() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The folder and its files are not deleted. CodexPad only removes its saved access and iSH mount.")
            }
        }
    }

    private var inputSection: some View {
        Section("Input mode") {
            Toggle("Desktop mode", isOn: $model.desktopModeEnabled)
                .accessibilityIdentifier("codexpad.desktop-mode")
            Text(model.desktopModeEnabled
                ? "Optimized for pointer and hardware keyboard. After you click the composer once, focus is restored after sends, stops, navigation, settings, and terminal use."
                : "Optimized for direct touch. The keyboard dismisses naturally while scrolling and after sending.")
                .font(.caption)
                .foregroundStyle(CodexPalette.secondaryInk)

            if !model.desktopModeEnabled {
                Toggle("Show all Codex features", isOn: $model.showAllFeaturesInTouchMode)
                    .accessibilityIdentifier("codexpad.touch-show-all")
                Text("Keeps touch mode behavior while revealing the complete Feature Center and long-tail controls.")
                    .font(.caption)
                    .foregroundStyle(CodexPalette.secondaryInk)
            } else {
                Label("All compatible features are always visible in desktop mode.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CodexPalette.teal)
            }
        }
    }

    private var modelSection: some View {
        Section("Model") {
            if model.availableModels.isEmpty {
                LabeledContent("Catalog") {
                    ProgressView().controlSize(.small)
                }
            } else {
                Picker("Model", selection: modelSelection) {
                    ForEach(model.availableModels.filter { !$0.hidden }) { option in
                        Text(option.displayName).tag(option.id)
                    }
                    if model.availableModels.contains(where: \.hidden) {
                        Section("Hidden provider entries") {
                            ForEach(model.availableModels.filter(\.hidden)) { option in
                                Text("\(option.displayName) - Hidden").tag(option.id)
                            }
                        }
                    }
                }

                if let selected = model.selectedModel {
                    Text(selected.description)
                        .font(.caption)
                        .foregroundStyle(CodexPalette.secondaryInk)
                    Picker("Reasoning", selection: reasoningSelection) {
                        ForEach(selected.reasoningEfforts) { effort in
                            Text(effort.effort.capitalized).tag(effort.effort)
                        }
                    }

                    if model.showsCompleteFeatureSet, !selected.serviceTiers.isEmpty {
                        Picker("Service tier", selection: serviceTierSelection) {
                            Text("Provider default").tag("")
                            ForEach(selected.serviceTiers) { tier in
                                Text(tier.name).tag(tier.id)
                            }
                        }
                    }
                }

                if model.showsCompleteFeatureSet, !model.collaborationModes.isEmpty {
                    Picker("Collaboration", selection: collaborationSelection) {
                        Text("Standard").tag("")
                        ForEach(model.collaborationModes) { mode in
                            Text(mode.name).tag(mode.name)
                        }
                    }
                }
            }

            Button("Refresh model catalog") {
                Task {
                    await model.refreshModels()
                    await model.refreshCollaborationModes()
                }
            }
            .disabled(!model.enginePhase.isReady)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if model.account.isAuthenticated {
                LabeledContent("Signed in", value: model.account.displayName)
                if let plan = model.account.plan {
                    LabeledContent("Plan", value: plan.capitalized)
                }
                Button("Sign out", role: .destructive) {
                    Task { await model.signOut() }
                }
            } else {
                Button("Continue with ChatGPT") {
                    Task { await model.signInWithChatGPT() }
                }
                Button("Use a device code") {
                    Task { await model.signInWithDeviceCode() }
                }
                SecureField("OpenAI API key", text: $apiKey)
                    .textContentType(.password)
                Button("Save API key") {
                    let key = apiKey
                    apiKey = ""
                    Task { await model.signIn(apiKey: key) }
                }
                .disabled(apiKey.isEmpty)
            }

            if let code = model.deviceCode, let url = model.deviceVerificationURL {
                LabeledContent("Device code", value: code)
                Button("Open \(url.host ?? "verification page")") {
                    openURL(url)
                }
            }
        }
    }

    private var workspaceSection: some View {
        Section("Workspace") {
            switch model.linkedFolderPhase {
            case .disconnected:
                Button("Choose folder in Files", systemImage: "folder.badge.plus") {
                    Task { await model.chooseFilesFolder() }
                }
                .disabled(!model.enginePhase.isReady)
                Text("The selected folder is mounted directly into iSH and becomes Codex's working directory.")
                    .font(.caption)
                    .foregroundStyle(CodexPalette.secondaryInk)
            case .choosing:
                HStack {
                    ProgressView()
                    Text("Waiting for Files selection...")
                }
            case .linked(let name):
                LabeledContent("Linked folder", value: name)
                Button("Unlink Files folder", role: .destructive) {
                    confirmsUnlink = true
                }
            case .needsRelink(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(CodexPalette.amber)
                Button("Select folder again") {
                    Task { await model.chooseFilesFolder() }
                }
            }

            TextField("Guest path", text: $model.workspacePath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
            LabeledContent("Runtime", value: "iSH - Alpine x86")
            LabeledContent("Transport", value: "Guest loopback")
        }
    }

    private var featureSection: some View {
        Section("Codex feature coverage") {
            LabeledContent("Compatible operations", value: "\(CodexFeatureCatalog.compatibleFeatureCount)")
            LabeledContent("Platform exceptions", value: "\(CodexFeatureCatalog.unavailableFeatureCount)")
            if model.showsCompleteFeatureSet {
                Button("Open complete Feature Center", systemImage: "square.grid.3x3") {
                    dismiss()
                    DispatchQueue.main.async {
                        model.showsFeatureCenter = true
                    }
                }
                .accessibilityIdentifier("codexpad.open-feature-center")
            } else {
                Text("Turn on Show all Codex features above to reveal advanced, experimental, and long-tail operations while staying in touch mode.")
                    .font(.caption)
                    .foregroundStyle(CodexPalette.secondaryInk)
            }
        }
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { model.selectedModelID ?? model.availableModels.first?.id ?? "" },
            set: { model.selectModel($0) }
        )
    }

    private var reasoningSelection: Binding<String> {
        Binding(
            get: { model.selectedReasoningEffort ?? model.selectedModel?.defaultReasoningEffort ?? "" },
            set: { model.selectedReasoningEffort = $0 }
        )
    }

    private var serviceTierSelection: Binding<String> {
        Binding(
            get: { model.selectedServiceTier ?? "" },
            set: { model.selectedServiceTier = $0.isEmpty ? nil : $0 }
        )
    }

    private var collaborationSelection: Binding<String> {
        Binding(
            get: { model.selectedCollaborationMode ?? "" },
            set: { model.selectedCollaborationMode = $0.isEmpty ? nil : $0 }
        )
    }
}
