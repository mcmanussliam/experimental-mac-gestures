import AppKit

/// A vibrancy pill with an SF Symbol, shown briefly near the bottom of the screen when a gesture
/// runs an action, styled like the system's own HUDs.
@MainActor
final class Toast {
    private let panel: NSPanel
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var pendingHide: DispatchWorkItem?

    init() {
        panel = NSWindow.clickThrough(NSPanel.self, style: [.borderless, .nonactivatingPanel])
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        icon.symbolConfiguration = .init(pointSize: 17, weight: .semibold)
        icon.contentTintColor = .labelColor
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 11, left: 16, bottom: 11, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor), stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            stack.topAnchor.constraint(equalTo: blur.topAnchor), stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur
        panel.alphaValue = 0
    }

    func show(_ text: String, symbol: String, on screenFrame: NSRect) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        label.stringValue = text
        let size = panel.contentView!.fittingSize
        panel.setFrame(NSRect(x: screenFrame.midX - size.width / 2, y: screenFrame.minY + 110,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        pendingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.35; self.panel.animator().alphaValue = 0 }
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }
}
