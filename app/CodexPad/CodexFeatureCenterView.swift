import SwiftUI

struct CodexFeatureCenterView: View {
    @ObservedObject var model: CodexWorkspaceModel
    @Environment(\.dismiss) private var dismiss

    @State private var selection: String?
    @State private var searchText = ""
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            List(selection: $selection) {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("COMPLETE CODEX SURFACE")
                            .font(.caption2.monospaced().weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(CodexPalette.secondaryInk)
                        Text("\(CodexFeatureCatalog.compatibleFeatureCount) compatible operations")
                            .font(.headline)
                        Text("\(CodexFeatureCatalog.unavailableFeatureCount) explicit platform exceptions")
                            .font(.caption)
                            .foregroundStyle(CodexPalette.secondaryInk)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("codexpad.feature-summary")
                }

                ForEach(CodexFeatureCategory.allCases) { category in
                    let features = filteredFeatures.filter { $0.category == category }
                    if !features.isEmpty {
                        Section(category.rawValue) {
                            ForEach(features) { feature in
                                FeatureCatalogRow(feature: feature)
                                    .tag(feature.method)
                                    .accessibilityIdentifier("codexpad.feature.\(feature.method)")
                            }
                        }
                    }
                }

                Section("Runtime exceptions") {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Experimental Code Mode").font(.subheadline.weight(.medium))
                            Text("Rusty V8 has no i686-musl build")
                                .font(.caption2)
                                .foregroundStyle(CodexPalette.secondaryInk)
                        }
                    } icon: {
                        Image(systemName: "nosign").foregroundStyle(CodexPalette.amber)
                    }
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Client attestation").font(.subheadline.weight(.medium))
                            Text("No signing provider in this unsigned port")
                                .font(.caption2)
                                .foregroundStyle(CodexPalette.secondaryInk)
                        }
                    } icon: {
                        Image(systemName: "nosign").foregroundStyle(CodexPalette.amber)
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Search every Codex feature")
            .navigationTitle("Feature Center")
        } detail: {
            if let selection, let feature = CodexFeatureCatalog.feature(method: selection) {
                CodexFeatureDetailView(model: model, feature: feature)
                    .id(selection)
            } else {
                ContentUnavailableView(
                    "Choose a Codex feature",
                    systemImage: "square.grid.3x3",
                    description: Text("Every compatible method in the pinned app-server protocol has a route here.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .accessibilityIdentifier("codexpad.feature-center")
    }

    private var filteredFeatures: [CodexFeatureDefinition] {
        guard !searchText.isEmpty else { return CodexFeatureCatalog.features }
        return CodexFeatureCatalog.features.filter {
            $0.method.localizedCaseInsensitiveContains(searchText)
                || $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.category.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }
}

private struct FeatureCatalogRow: View {
    let feature: CodexFeatureDefinition

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feature.category.symbol)
                .foregroundStyle(feature.access == .incompatible ? CodexPalette.secondaryInk : CodexPalette.cobalt)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(feature.method)
                    .font(.caption2.monospaced())
                    .foregroundStyle(CodexPalette.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: accessSymbol)
                .font(.caption)
                .foregroundStyle(feature.access == .incompatible ? CodexPalette.amber : CodexPalette.teal)
                .accessibilityLabel(feature.access.rawValue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title), \(feature.access.rawValue), \(feature.method)")
    }

    private var accessSymbol: String {
        switch feature.access {
        case .native: "rectangle.and.hand.point.up.left"
        case .advanced: "slider.horizontal.3"
        case .automatic: "arrow.trianglehead.2.clockwise.rotate.90"
        case .incompatible: "nosign"
        }
    }
}

private struct CodexFeatureDetailView: View {
    @ObservedObject var model: CodexWorkspaceModel
    let feature: CodexFeatureDefinition

    @State private var parameters = "{}"
    @State private var result = ""
    @State private var isRunning = false
    @State private var confirmsDestructiveRequest = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let reason = feature.incompatibilityReason {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Platform exception").font(.headline)
                            Text(reason).font(.body)
                        }
                    } icon: {
                        Image(systemName: "nosign")
                    }
                    .foregroundStyle(CodexPalette.amber)
                    .codexPanel()
                } else if feature.access == .automatic {
                    Label("This connection feature runs automatically and cannot be repeated in an active JSON-RPC session.", systemImage: "checkmark.seal")
                        .codexPanel()
                } else {
                    if let location = feature.location {
                        Label("Native control: \(location)", systemImage: "rectangle.and.hand.point.up.left")
                            .font(.callout)
                            .foregroundStyle(CodexPalette.teal)
                            .codexPanel(padding: 14)
                    }
                    requestEditor
                }

                if !model.protocolEvents.isEmpty {
                    eventLog
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 56)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(CodexPalette.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            parameters = model.featureDefaultParams(for: feature.method)
        }
        .confirmationDialog(
            "Run destructive Codex operation?",
            isPresented: $confirmsDestructiveRequest,
            titleVisibility: .visible
        ) {
            Button("Run \(feature.method)", role: .destructive) { runRequest() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Review the JSON carefully. This operation can remove or overwrite local Codex data.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(feature.category.rawValue, systemImage: feature.category.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CodexPalette.cobalt)
                Spacer()
                Text(feature.access.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(CodexPalette.raised, in: Capsule())
            }
            Text(feature.title)
                .font(.largeTitle.bold())
                .foregroundStyle(CodexPalette.ink)
            Text(feature.method)
                .font(.callout.monospaced())
                .foregroundStyle(CodexPalette.secondaryInk)
                .textSelection(.enabled)
            Text(feature.summary)
                .font(.body)
                .foregroundStyle(CodexPalette.ink)
        }
    }

    private var requestEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Parameters", systemImage: "curlybraces")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    parameters = model.featureDefaultParams(for: feature.method)
                    result = ""
                }
                .buttonStyle(.borderless)
            }
            Text("Edit the JSON object sent as params. Contextual thread and workspace identifiers are prefilled when available.")
                .font(.caption)
                .foregroundStyle(CodexPalette.secondaryInk)
            TextEditor(text: $parameters)
                .font(.callout.monospaced())
                .frame(minHeight: 180)
                .padding(8)
                .background(CodexPalette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CodexPalette.line, lineWidth: 0.5)
                }
                .accessibilityLabel("JSON parameters for \(feature.method)")

            HStack {
                Button {
                    if feature.isDestructive {
                        confirmsDestructiveRequest = true
                    } else {
                        runRequest()
                    }
                } label: {
                    if isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Run request", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || !model.enginePhase.isReady)
                .accessibilityIdentifier("codexpad.feature-run")

                if !model.enginePhase.isReady {
                    Text("Local engine unavailable")
                        .font(.caption)
                        .foregroundStyle(CodexPalette.secondaryInk)
                }
            }

            if !result.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Result").font(.headline)
                    Text(result)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(CodexPalette.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
        }
        .codexPanel()
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Live protocol events", systemImage: "waveform.path.ecg")
                .font(.headline)
            ForEach(model.protocolEvents.suffix(8).reversed()) { event in
                DisclosureGroup {
                    Text(event.payload)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                } label: {
                    HStack {
                        Text(event.method).font(.caption.monospaced())
                        Spacer()
                        Text(event.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(CodexPalette.secondaryInk)
                    }
                }
            }
        }
        .codexPanel()
    }

    private func runRequest() {
        isRunning = true
        result = ""
        Task {
            result = await model.executeFeature(method: feature.method, parameters: parameters)
            isRunning = false
        }
    }
}
