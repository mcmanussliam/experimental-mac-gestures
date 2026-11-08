import SwiftUI

struct AdvancedSettings: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var confirmReset = ViewState(false)

    var body: some View {
        Form {
            Section {
                LabeledContent("Configuration file") {
                    Button("Open") { NSWorkspace.shared.open(AppConfig.fileURL) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppConfig.fileURL]) }
                }
            } footer: {
                Text("Every threshold can be tuned here; edits apply as soon as the file is saved. All settings and their defaults are listed in config.defaults.json.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Record diagnostic session", isOn: Binding(get: { model.recordingURL != nil }, set: { _ in model.toggleRecording() }))
                LabeledContent("Sessions") {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: AppConfig.sessionsDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(AppConfig.sessionsDirectory)
                    }
                }
                Button("Show Camera View") { model.showPreview() }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Sessions contain hand landmark positions only (no images). Analyse them with gesture-lab.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings…", role: .destructive) { confirmReset.value = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset.value) {
            Button("Reset", role: .destructive) { model.resetSettings() }
        } message: {
            Text("Gesture bindings and pointer settings are reset. Custom poses are kept.")
        }
    }
}
