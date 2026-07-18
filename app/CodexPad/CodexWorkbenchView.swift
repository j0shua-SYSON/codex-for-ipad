import SwiftUI

struct CodexWorkbenchView: View {
    @ObservedObject var model: CodexWorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Workbench", selection: $model.workbenchTab) {
                ForEach(WorkbenchTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(16)

            Divider().overlay(CodexPalette.line)

            Group {
                switch model.workbenchTab {
                case .plan: planView
                case .changes: changesView
                case .files: filesView
                case .runtime: runtimeView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CodexPalette.canvas)
        .accessibilityIdentifier("codexpad.workbench")
        .navigationTitle("Workbench")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var planView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Turn plan").codexDisplayTitle()
                    Spacer()
                    Text("\(model.plan.filter(\.isComplete).count)/\(model.plan.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(CodexPalette.secondaryInk)
                }
                if model.plan.isEmpty {
                    ContentUnavailableView(
                        "No plan yet",
                        systemImage: "checklist",
                        description: Text("A structured plan appears here when Codex creates one.")
                    )
                } else {
                    ForEach(model.plan) { step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: planIcon(step.status))
                                .foregroundStyle(planColor(step.status))
                                .frame(width: 22, height: 22)
                            Text(step.text)
                                .font(.body)
                                .foregroundStyle(CodexPalette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(step.text), \(step.status)")
                    }
                }
            }
            .padding(20)
        }
    }

    private var changesView: some View {
        Group {
            if model.currentDiff.isEmpty {
                ContentUnavailableView(
                    "No changes yet",
                    systemImage: "doc.badge.gearshape",
                    description: Text("The current turn’s patch appears here as Codex edits files.")
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(model.currentDiff)
                        .font(.callout.monospaced())
                        .foregroundStyle(CodexPalette.ink)
                        .textSelection(.enabled)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("Current file changes")
            }
        }
    }

    private var filesView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    Task { await model.navigateUpDirectory() }
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 32, height: 32)
                }
                .disabled(model.directoryPath == "/")
                .accessibilityLabel("Parent directory")
                Text(model.directoryPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(CodexPalette.secondaryInk)
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await model.loadDirectory(model.directoryPath) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Refresh directory")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(CodexPalette.surface)

            if let fileName = model.filePreviewName {
                VStack(spacing: 0) {
                    HStack {
                        Button("Back") {
                            model.filePreviewName = nil
                            model.filePreview = ""
                        }
                        Spacer()
                        Text(fileName).font(.subheadline.weight(.semibold))
                        Spacer()
                        Color.clear.frame(width: 44)
                    }
                    .padding(10)
                    ScrollView([.horizontal, .vertical]) {
                        Text(model.filePreview)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            } else {
                List(model.directoryEntries) { entry in
                    Button {
                        Task { await model.openEntry(entry) }
                    } label: {
                        Label(entry.name, systemImage: entry.isDirectory ? "folder.fill" : "doc.text")
                            .foregroundStyle(entry.isDirectory ? CodexPalette.cobalt : CodexPalette.ink)
                    }
                    .accessibilityHint(entry.isDirectory ? "Opens directory" : "Previews file")
                }
                .listStyle(.plain)
            }
        }
    }

    private var runtimeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label("On-device Linux", systemImage: "cpu")
                    .font(.headline)
                    .foregroundStyle(CodexPalette.teal)
                Text("iSH emulates 32-bit x86 Linux in this app. Codex, shell commands, Git, and project files stay on the iPad.")
                    .font(.callout)
                    .foregroundStyle(CodexPalette.secondaryInk)
                Divider()
                ForEach(model.runtimeLog.indices, id: \.self) { index in
                    Text(model.runtimeLog[index])
                        .font(.caption.monospaced())
                        .foregroundStyle(CodexPalette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .codexPanel()
            .padding(16)
        }
    }

    private func planIcon(_ status: String) -> String {
        switch status {
        case "completed": "checkmark.circle.fill"
        case "inProgress", "in_progress": "circle.dotted.circle.fill"
        default: "circle"
        }
    }

    private func planColor(_ status: String) -> Color {
        switch status {
        case "completed": CodexPalette.teal
        case "inProgress", "in_progress": CodexPalette.cobalt
        default: CodexPalette.secondaryInk
        }
    }
}
