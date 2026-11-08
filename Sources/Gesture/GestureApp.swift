import AppKit
import SwiftUI

@main
struct GestureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
        } label: {
            Image(systemName: model.menuSymbol)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboarding: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One instance only: a second launch just brings up the first one's settings.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current }
        if !others.isEmpty {
            others.first?.activate()
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            let model = AppModel.shared
            model.start()
            // Same as Settings → Advanced → Record diagnostic session.
            if CommandLine.arguments.contains("--record") { model.toggleRecording() }
            if !UserDefaults.standard.bool(forKey: "onboardingComplete")
                || model.cameraAccess != .authorized || !model.accessibilityTrusted {
                showOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.shutdown() }
    }

    @MainActor func showOnboarding() {
        if onboarding == nil {
            let w = NSWindow(contentViewController: NSHostingController(
                rootView: OnboardingView { [weak self] in
                    UserDefaults.standard.set(true, forKey: "onboardingComplete")
                    self?.onboarding?.close()
                }.environmentObject(AppModel.shared)))
            w.title = "Welcome to Gesture"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            onboarding = w
        }
        onboarding?.center()
        onboarding?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
