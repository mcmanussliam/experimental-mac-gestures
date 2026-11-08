import AVFoundation
import GestureCore
import SwiftUI

struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var cameras = ViewState(CameraCapture.availableCameras())

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(model.statusText)
                    }
                }
                Toggle("Gesture control", isOn: Binding(get: { !model.paused }, set: { model.setPaused(!$0) }))
                if !model.accessibilityTrusted {
                    LabeledContent("Accessibility access is needed to control the pointer") {
                        Button("Open Settings") { Permissions.promptAccessibility(); Permissions.openAccessibilitySettings() }
                    }
                }
            }

            Section("Pointer") {
                Picker("Movement", selection: $model.config.engine.cursorMode) {
                    Text("Trackpad-like").tag(CursorMode.relative)
                    Text("Direct").tag(CursorMode.absolute)
                }
                .pickerStyle(.segmented)
                Text(model.config.engine.cursorMode == .relative
                     ? "Hand movement nudges the pointer, faster movements go further. Make a fist to lift and reposition your hand."
                     : "The pointer goes where your hand is, like touching the screen from a distance.")
                    .font(.callout).foregroundStyle(.secondary)
                Slider(value: $model.pointerSpeed) {
                    Text("Speed")
                } minimumValueLabel: { Image(systemName: "tortoise") } maximumValueLabel: { Image(systemName: "hare") }
                Slider(value: $model.steadiness) {
                    Text("Steadiness")
                } minimumValueLabel: { Image(systemName: "bolt") } maximumValueLabel: { Image(systemName: "scope") }
            }

            Section("Feedback") {
                Toggle("Show ring around the pointer", isOn: $model.config.showPointerRing)
                Toggle("Show a notification when a gesture runs an action", isOn: $model.config.showNotifications)
            }

            Section("Camera") {
                Picker("Camera", selection: $model.config.cameraID) {
                    Text("System default").tag(String?.none)
                    ForEach(cameras.value, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                }
                LabeledContent("Format", value: model.cameraStatus)
            }

            Section {
                Toggle("Open Gesture at login", isOn: $model.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .onAppear { cameras.value = CameraCapture.availableCameras() }
    }

    private var statusColor: Color {
        if model.paused { return .orange }
        if !model.accessibilityTrusted || model.cameraAccess != .authorized || !model.cameraRunning { return .red }
        return .green
    }
}
