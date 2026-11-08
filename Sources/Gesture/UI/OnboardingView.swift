import SwiftUI

/// First-run setup: permissions, then a quick guide.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var page: ViewState<Page>
    let onFinish: () -> Void

    enum Page: Int { case welcome, camera, accessibility, done }

    init(onFinish: @escaping () -> Void) {
        _page = StateObject(wrappedValue: ViewState(.welcome))
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page.value {
                case .welcome: welcome
                case .camera: camera
                case .accessibility: accessibility
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
        .frame(width: 520, height: 460)
    }

    private var welcome: some View {
        PageLayout(symbol: "hand.raised.fill", title: "Control your Mac with your hands",
                   text: "Gesture uses your camera to follow your hand: move to point, pinch to click, two fingers to scroll, and swipe for Spaces and Mission Control. Video never leaves your Mac.") {
            Button("Get Started") { page.value = .camera }.keyboardShortcut(.defaultAction)
        }
    }

    private var camera: some View {
        PageLayout(symbol: "camera.fill", title: "Camera access",
                   text: "Gesture analyses camera frames on-device to find your hand. Nothing is recorded or sent anywhere.") {
            switch model.cameraAccess {
            case .authorized:
                Label("Camera access granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Continue") { page.value = .accessibility }.keyboardShortcut(.defaultAction)
            case .notDetermined:
                Button("Allow Camera Access") { model.requestCameraAccess() }.keyboardShortcut(.defaultAction)
            default:
                Text("Camera access is turned off for Gesture.").foregroundStyle(.secondary)
                Button("Open Camera Settings") { Permissions.openCameraSettings() }
            }
        }
    }

    private var accessibility: some View {
        PageLayout(symbol: "cursorarrow.motionlines", title: "Pointer control",
                   text: "To move the pointer, click and press shortcuts for you, macOS needs you to allow Gesture in Accessibility settings.") {
            if model.accessibilityTrusted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Continue") { page.value = .done }.keyboardShortcut(.defaultAction)
            } else {
                Button("Open Accessibility Settings") {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                .keyboardShortcut(.defaultAction)
                Text("Turn on Gesture in the list, then come back here.").font(.callout).foregroundStyle(.secondary)
                Button("Skip for Now") { page.value = .done }.buttonStyle(.link)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            Text("You're all set").font(.title.bold())
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                ForEach(GestureCatalog.pointer) { g in
                    GridRow {
                        Image(systemName: g.symbol).font(.title3).frame(width: 28).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.title).bold()
                            Text(g.detail).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Swipes, two-hand zoom and your own custom poses can be set up in Settings.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Start Using Gesture", action: onFinish).keyboardShortcut(.defaultAction).controlSize(.large)
        }
    }
}

/// Shared layout for onboarding pages: big symbol, title, body, then controls.
private struct PageLayout<Controls: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder let controls: Controls

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(.tint)
                .frame(height: 64)
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            VStack(spacing: 10) { controls }.controlSize(.large)
        }
    }
}
