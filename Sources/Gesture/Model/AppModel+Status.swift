import Foundation
import GestureCore

/// Human-facing state for the menu bar and settings.
extension AppModel {
    var statusText: String {
        if cameraAccess == .denied || cameraAccess == .restricted { return "Camera access is off" }
        if cameraAccess == .notDetermined { return "Waiting for camera access" }
        if !accessibilityTrusted { return "Needs Accessibility access" }
        if !systemActive { return "Sleeping" }
        if paused { return "Paused" }
        if !cameraRunning { return cameraStatus }
        switch mode {
        case .noHand: return "Ready, raise a hand"
        case .pointing: return "Tracking"
        case .pressed, .dragging: return "Pressing"
        case .scrolling: return "Scrolling"
        case .zooming: return "Zooming"
        case .paused: return "Paused"
        }
    }

    var menuSymbol: String {
        if paused || !accessibilityTrusted || cameraAccess != .authorized { return "hand.raised.slash" }
        switch mode {
        case .noHand: return "hand.raised"
        case .pressed, .dragging: return "hand.pinch.fill"
        case .scrolling: return "hand.draw.fill"
        default: return "hand.raised.fill"
        }
    }
}
