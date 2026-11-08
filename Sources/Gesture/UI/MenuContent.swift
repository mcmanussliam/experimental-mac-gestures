import SwiftUI
import GestureCore

/// The menu bar menu (rendered as a native NSMenu).
struct MenuContent: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Text(model.statusText)
        if model.cameraRunning && !model.paused {
            Text(String(format: "%.0f fps · %.0f ms latency", model.stats.fps, model.stats.latencyMs))
        }
        if model.cameraAccess != .authorized || !model.accessibilityTrusted {
            Button("Finish Setting Up…") { (NSApp.delegate as? AppDelegate)?.showOnboarding() }
        }
        Divider()

        Toggle("Gesture Control", isOn: Binding(get: { !model.paused }, set: { model.setPaused(!$0) }))
            .keyboardShortcut("g", modifiers: [.control, .option, .command])
        Picker("Pointer", selection: $model.config.engine.cursorMode) {
            Text("Trackpad-like").tag(CursorMode.relative)
            Text("Direct").tag(CursorMode.absolute)
        }
        Button("Show Camera") { model.showPreview() }
        Divider()

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Gesture") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
