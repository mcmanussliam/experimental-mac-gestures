import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import GestureCore

/// The app's single source of truth. Owns the pipeline and everything around it; SwiftUI
/// views (menu, settings, onboarding) observe it.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    /// Edits are saved (overrides only) and applied immediately.
    @Published var config: AppConfig {
        didSet { if config != oldValue { configDidChange() } }
    }
    @Published private(set) var customPoses = AppConfig.loadCustomPoses()
    @Published private(set) var cameraAccess = Permissions.camera
    @Published private(set) var accessibilityTrusted = Permissions.accessibility
    @Published private(set) var paused = false
    @Published private(set) var mode: EngineMode = .noHand
    @Published private(set) var stats = PipelineStats()
    @Published private(set) var cameraStatus = "Starting…"
    @Published private(set) var cameraRunning = false
    @Published private(set) var recordingURL: URL?
    @Published var launchAtLogin = LaunchAtLogin.isEnabled {
        didSet { if launchAtLogin != LaunchAtLogin.isEnabled { LaunchAtLogin.set(launchAtLogin) } }
    }

    let executor = ActionExecutor()
    let animator: PointerAnimator
    let pipeline: Pipeline
    let hud = HUD()
    private(set) lazy var poseRecorder = PoseRecorder(model: self)

    private(set) var systemActive = true
    private var preview: PreviewWindow?
    private var watcher: ConfigWatcher?
    private var systemEvents: SystemEvents?
    private var hotKey: GlobalHotKey?
    private var permissionTimer: Timer?
    private var lastStatsPublish = Date.distantPast
    private var reloading = false

    private init() {
        let config = AppConfig.load()
        self.config = config
        animator = PointerAnimator(executor: executor)
        pipeline = Pipeline(config: config, executor: executor, animator: animator)
        applyPointerSettings()
    }

    func start() {
        pipeline.setCustomPoses(customPoses)
        pipeline.onOutput = { [weak self] output, stats in self?.handle(output, stats) }
        pipeline.onCommand = { [weak self] command, ran in self?.handle(command, ran: ran) }
        pipeline.camera.onStatus = { [weak self] status in self?.cameraStatus = status }
        animator.onRender = { [weak self] point in self?.hud.setPointer(point) }
        hud.showsReticle = config.showPointerRing

        updateScreen()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateScreen() }
        }
        watcher = ConfigWatcher(directory: AppConfig.directory) { [weak self] in
            MainActor.assumeIsolated { self?.reloadConfig() }
        }
        systemEvents = SystemEvents { [weak self] active in
            MainActor.assumeIsolated { self?.setSystemActive(active) }
        }
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            MainActor.assumeIsolated { self?.togglePause() }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        refreshPermissions()
    }

    func shutdown() {
        pipeline.suspend()
    }

    private func refreshPermissions() {
        let camera = Permissions.camera
        if camera != cameraAccess { cameraAccess = camera }
        let trusted = Permissions.accessibility
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        executor.enabled = trusted
        if camera == .authorized && !cameraRunning && systemActive { startCamera() }
    }

    func requestCameraAccess() {
        Permissions.requestCamera { [weak self] _ in self?.refreshPermissions() }
    }

    private func startCamera() {
        do {
            try pipeline.start()
            cameraRunning = true
            cameraStatus = "\(pipeline.camera.deviceName) · \(pipeline.camera.formatDescription)"
        } catch {
            cameraStatus = error.localizedDescription
        }
    }

    private func setSystemActive(_ active: Bool) {
        systemActive = active
        if active {
            if cameraAccess == .authorized { startCamera() }
        } else {
            pipeline.suspend()
            cameraRunning = false
            mode = .noHand
            hud.update(HUDState())
        }
    }

    private func updateScreen() {
        // The first screen is the one with the menu bar.
        guard let screen = NSScreen.screens.first else { return }
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        pipeline.setScreen(CGDisplayBounds(id))
        hud.attach(to: screen)
        animator.attach(to: screen)
    }

    private func handle(_ output: EngineOutput, _ latest: PipelineStats) {
        if output.hud.mode != mode { mode = output.hud.mode }
        hud.update(output.hud)
        preview?.update(output, stats: latest, cameraInfo: pipeline.camera.formatDescription)
        if Date().timeIntervalSince(lastStatsPublish) > 1 { stats = latest; lastStatsPublish = Date() }
    }

    private func handle(_ command: GestureCommand, ran: Bool) {
        if case .paused(let isPaused) = command {
            paused = isPaused
            notifyPauseChange()
        } else if ran {
            let key = command.bindingKey
            let gesture = GestureCatalog.title(forBinding: key)
            let action = GestureCatalog.title(forAction: config.bindings[key] ?? "")
            notify("\(gesture) · \(action)", symbol: GestureCatalog.bindable.first { $0.id == key }?.symbol ?? "hand.raised")
        }
    }

    private func notifyPauseChange() {
        notify(paused ? "Gesture control paused" : "Gesture control resumed",
               symbol: paused ? "hand.raised.slash" : "hand.raised")
    }

    func notify(_ text: String, symbol: String) {
        if config.showNotifications { hud.toast(text, symbol: symbol) }
    }

    func togglePause() { setPaused(!paused) }

    func setPaused(_ isPaused: Bool) {
        guard isPaused != paused else { return }
        paused = isPaused
        pipeline.setPaused(isPaused)
        animator.reset()
        notifyPauseChange()
    }

    func showPreview() {
        if let preview, preview.isVisible { preview.show(); return }
        let window = PreviewWindow(session: pipeline.camera.session, aspect: pipeline.camera.aspect)
        window.activeZoneBottom = config.engine.activeZoneBottom
        window.onClose = { [weak self] in self?.preview = nil }
        preview = window
        window.show()
    }

    func toggleRecording() {
        if recordingURL != nil {
            pipeline.setRecorder(nil)
            recordingURL = nil
        } else if let recorder = try? SessionRecorder(url: SessionRecorder.newSessionURL()) {
            pipeline.setRecorder(recorder)
            recordingURL = recorder.url
        }
    }

    func resetSettings() {
        config = AppConfig()
    }

    func binding(for key: String) -> String { config.bindings[key] ?? "none" }
    func setBinding(_ key: String, _ action: String) { config.bindings[key] = action }

    func saveCustomPose(name: String, samples: [[Double]], action: String) {
        var library = customPoses
        library.samples.removeAll { $0.name == name }
        library.samples += samples.map { CustomPoseSample(name: name, vector: $0) }
        setCustomPoses(library)
        if !action.isEmpty { setBinding("pose.custom.\(name)", action) }
    }

    func deleteCustomPose(_ name: String) {
        var library = customPoses
        library.samples.removeAll { $0.name == name }
        setCustomPoses(library)
        config.bindings["pose.custom.\(name)"] = nil
    }

    private func setCustomPoses(_ library: CustomPoseLibrary) {
        customPoses = library
        AppConfig.saveCustomPoses(library)
        pipeline.setCustomPoses(library)
    }

    private func configDidChange() {
        if !reloading { config.save() }
        pipeline.apply(config)
        applyPointerSettings()
        hud.showsReticle = config.showPointerRing
    }

    private func applyPointerSettings() {
        animator.smoothing = max(config.pointerSmoothingMs, 1) / 1000
        animator.scrollSmoothing = max(config.scrollSmoothingMs, 1) / 1000
    }

    /// The file changed on disk (hand edit, or our own save): pick it up.
    private func reloadConfig() {
        let fresh = AppConfig.load()
        if fresh != config {
            reloading = true
            config = fresh
            reloading = false
            Log.app.info("Config reloaded from disk")
        }
        let poses = AppConfig.loadCustomPoses()
        if poses.samples.count != customPoses.samples.count { customPoses = poses; pipeline.setCustomPoses(poses) }
    }
}
