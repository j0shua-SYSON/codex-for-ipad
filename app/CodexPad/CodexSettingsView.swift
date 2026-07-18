import SwiftUI

struct CodexSettingsView: View {
    @ObservedObject var model: CodexWorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var apiKey = ""

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Workspace") {
                    TextField("Guest path", text: $model.workspacePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    LabeledContent("Runtime", value: "iSH · Alpine x86")
                    LabeledContent("Transport", value: "Guest loopback")
                }

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
        }
    }
}
