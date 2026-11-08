import AppKit
import GestureCore
import QuartzCore

/// On-screen feedback in a click-through overlay: the pointer reticle, and a toast when a gesture
/// runs an action.
@MainActor
final class HUD {
    var showsReticle = true { didSet { if !showsReticle { setReticleVisible(false) } } }

    private let overlay = NSWindow.clickThrough(NSWindow.self, style: .borderless)
    private let reticle = PointerReticle()
    private let toastView = Toast()
    private var screenFrame = NSRect.zero
    private var reticleVisible = false
    private var pointer = CGPoint.zero

    init() {
        let root = CALayer()
        overlay.contentView = NSView()
        overlay.contentView?.layer = root
        overlay.contentView?.wantsLayer = true
        root.addSublayer(reticle.layer)
    }

    func attach(to screen: NSScreen) {
        screenFrame = screen.frame
        overlay.setFrame(screen.frame, display: false)
        overlay.contentView?.layer?.contentsScale = screen.backingScaleFactor
        overlay.orderFrontRegardless()
    }

    /// Display-relative point (top-left origin), from the pointer animator at display rate.
    func setPointer(_ point: Vec2) {
        pointer = CGPoint(x: point.x, y: screenFrame.height - point.y)
        if reticleVisible { reticle.move(to: pointer) }
    }

    func update(_ hud: HUDState) {
        let visible = showsReticle && hud.mode != .noHand && hud.mode != .paused
        if visible != reticleVisible { setReticleVisible(visible) }
        if visible { reticle.update(hud) }
    }

    func toast(_ text: String, symbol: String) { toastView.show(text, symbol: symbol, on: screenFrame) }

    private func setReticleVisible(_ visible: Bool) {
        reticleVisible = visible
        reticle.setVisible(visible, at: pointer)
    }
}

extension NSWindow {
    /// A transparent, click-through window above everything, on every Space.
    static func clickThrough<W: NSWindow>(_ type: W.Type, style: NSWindow.StyleMask) -> W {
        let window = W(contentRect: .zero, styleMask: style, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return window
    }
}
