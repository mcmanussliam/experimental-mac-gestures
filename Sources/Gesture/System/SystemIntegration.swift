import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement

/// Permission state for the two things Gesture needs.
enum Permissions {
    static var camera: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func requestCamera(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { done(ok) } }
    }

    /// Shows the system prompt that deep-links to the Accessibility list.
    static func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openCameraSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.app.error("Launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Sleep / wake, screen lock and fast-user-switching. Gesture stops the camera (and its light)
/// whenever nobody can be using the Mac, and resumes afterwards.
final class SystemEvents {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var reasons = Set<String>()
    private let onChange: (_ active: Bool) -> Void

    init(onChange: @escaping (_ active: Bool) -> Void) {
        self.onChange = onChange
        let ws = NSWorkspace.shared.notificationCenter
        let dn = DistributedNotificationCenter.default()
        observe(ws, NSWorkspace.willSleepNotification, "sleep", inactive: true)
        observe(ws, NSWorkspace.didWakeNotification, "sleep", inactive: false)
        observe(ws, NSWorkspace.screensDidSleepNotification, "display", inactive: true)
        observe(ws, NSWorkspace.screensDidWakeNotification, "display", inactive: false)
        observe(ws, NSWorkspace.sessionDidResignActiveNotification, "session", inactive: true)
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification, "session", inactive: false)
        observe(dn, Notification.Name("com.apple.screenIsLocked"), "lock", inactive: true)
        observe(dn, Notification.Name("com.apple.screenIsUnlocked"), "lock", inactive: false)
    }

    deinit { tokens.forEach { $0.0.removeObserver($0.1) } }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ reason: String, inactive: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let wasActive = self.reasons.isEmpty
            if inactive { self.reasons.insert(reason) } else { self.reasons.remove(reason) }
            if wasActive != self.reasons.isEmpty {
                Log.app.info("System \(self.reasons.isEmpty ? "active" : "inactive", privacy: .public) (\(reason, privacy: .public))")
                self.onChange(self.reasons.isEmpty)
            }
        }
        tokens.append((center, token))
    }
}
