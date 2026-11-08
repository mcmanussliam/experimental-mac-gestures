import SwiftUI

struct GestureSettings: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var showingRecorder = ViewState(false)

    var body: some View {
        Form {
            Section("Actions") {
                ForEach(GestureCatalog.bindable) { g in
                    BindingRow(title: g.title, detail: g.detail, symbol: g.symbol, key: g.id)
                }
            }

            Section {
                ForEach(model.customPoses.names, id: \.self) { name in
                    BindingRow(title: name, detail: "Custom pose", symbol: "hand.wave", key: "pose.custom.\(name)") {
                        Button(role: .destructive) { model.deleteCustomPose(name) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Record Custom Pose…") { showingRecorder.value = true }
            } header: {
                Text("Custom poses")
            } footer: {
                Text("Hold any hand shape for three seconds to teach it, then pick what it does.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Always available") {
                ForEach(GestureCatalog.pointer) { g in
                    Label { VStack(alignment: .leading) { Text(g.title); Text(g.detail).font(.callout).foregroundStyle(.secondary) } }
                        icon: { Image(systemName: g.symbol) }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingRecorder.value) { PoseRecorderSheet(recorder: model.poseRecorder) }
    }
}

/// One gesture with a preset picker, or a free-form action for anything else.
private struct BindingRow<Accessory: View>: View {
    @EnvironmentObject private var model: AppModel
    let title: String, detail: String, symbol: String, key: String
    @ViewBuilder var accessory: Accessory

    init(title: String, detail: String, symbol: String, key: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title; self.detail = detail; self.symbol = symbol; self.key = key; self.accessory = accessory()
    }

    private static var customTag: String { "__custom" }

    var body: some View {
        let action = model.binding(for: key)
        let isPreset = GestureCatalog.presets.contains { $0.action == action }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label { VStack(alignment: .leading) { Text(title); Text(detail).font(.callout).foregroundStyle(.secondary) } }
                    icon: { Image(systemName: symbol).frame(width: 20) }
                Spacer()
                Picker("", selection: Binding(
                    get: { isPreset ? action : Self.customTag },
                    set: { model.setBinding(key, $0 == Self.customTag ? (isPreset ? "key:" : action) : $0) })) {
                    ForEach(GestureCatalog.presets) { Text($0.title).tag($0.action) }
                    Divider()
                    Text("Custom…").tag(Self.customTag)
                }
                .labelsHidden()
                .fixedSize()
                accessory
            }
            if !isPreset {
                TextField("Action", text: Binding(get: { action }, set: { model.setBinding(key, $0) }),
                          prompt: Text("key:cmd+shift+4 · media:mute · open:/Applications/Safari.app · shell:…"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Action.parse(action) == nil ? .red : .primary)
            }
        }
    }
}

private struct PoseRecorderSheet: View {
    @ObservedObject var recorder: PoseRecorder
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = ViewState((name: "", action: "none"))

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Record a custom pose").font(.title2.bold())
            Text("Hold the pose in front of the camera for three seconds after you press Record. Tilt it slightly so it's recognised from different angles.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Name", text: $form.value.name, prompt: Text("e.g. ok-sign"))
                Picker("Action", selection: $form.value.action) {
                    ForEach(GestureCatalog.presets) { Text($0.title).tag($0.action) }
                }
            }
            if let p = recorder.progress { ProgressView(value: p) }
            if let m = recorder.message { Text(m).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button(recorder.message == nil ? "Cancel" : "Done") { dismiss() }
                Button("Record") { recorder.record(name: sanitizedName, action: form.value.action) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sanitizedName.isEmpty || recorder.progress != nil)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var sanitizedName: String {
        form.value.name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
    }
}
