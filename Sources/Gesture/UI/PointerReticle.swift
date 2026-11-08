import AppKit
import GestureCore
import QuartzCore

/// The reticle drawn around the pointer. It shows what the tracker sees, continuously, because
/// mid-air input has no touch to confirm anything:
///  * the ring tightens around the dot as the fingers close, meeting it at the click;
///  * a click squashes the reticle and leaves a ripple; a held button is a compact filled reticle;
///  * while scrolling the ring becomes a capsule with a knob showing the hand's offset from
///    neutral, so the joystick's speed and direction are visible;
///  * it fades and dashes as tracking weakens near the edge of the camera's view.
///
/// White with a dark hairline outline, like the system arrow, so it reads on any background.
@MainActor
final class PointerReticle {
    let layer = CALayer()

    private let ring = CAShapeLayer()
    private let ringOutline = CAShapeLayer()
    private let dot = CAShapeLayer()
    private let knob = CAShapeLayer()
    private let chevrons = CALayer()
    private let chevronUp = CAShapeLayer()
    private let chevronDown = CAShapeLayer()
    private var lastMode: EngineMode = .noHand

    private static let idleDiameter: CGFloat = 26
    private static let clickDiameter: CGFloat = 12

    init() {
        ringOutline.fillColor = nil
        ringOutline.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
        ring.fillColor = nil
        ring.strokeColor = NSColor.white.cgColor
        dot.strokeColor = NSColor.white.cgColor
        dot.lineWidth = 1
        knob.path = Self.capsule(10, 10)
        knob.fillColor = NSColor.white.cgColor
        knob.opacity = 0
        for (chevron, up) in [(chevronUp, true), (chevronDown, false)] {
            chevron.path = Self.chevron(up: up)
            chevron.fillColor = nil
            chevron.lineWidth = 2
            chevron.lineCap = .round
            chevron.lineJoin = .round
            chevron.strokeColor = NSColor.white.cgColor
            chevrons.addSublayer(chevron)
        }
        chevrons.opacity = 0
        for sublayer in [ringOutline, ring, dot, knob, chevrons] { layer.addSublayer(sublayer) }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 2
        layer.shadowOffset = .zero
        layer.opacity = 0
        setRing(diameter: Self.idleDiameter, height: Self.idleDiameter, width: 1.5)
    }

    func setVisible(_ visible: Bool, at position: CGPoint) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(visible ? 0.18 : 0.25)
        if visible {
            CATransaction.setDisableActions(true)
            layer.position = position
            CATransaction.setDisableActions(false)
        }
        layer.opacity = visible ? 1 : 0
        layer.transform = visible ? CATransform3DIdentity : CATransform3DMakeScale(0.6, 0.6, 1)
        CATransaction.commit()
    }

    func move(to position: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = position
        CATransaction.commit()
    }

    /// Engine state, once per camera frame. Shape changes animate briefly so they read as motion
    /// between frames rather than steps.
    func update(_ hud: HUDState) {
        let mode = hud.mode
        let pressing = mode == .pressed || mode == .dragging
        let wasPressing = lastMode == .pressed || lastMode == .dragging
        let tint = Self.tint(mode: mode, button: hud.activeButton)
        defer { lastMode = mode }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        switch mode {
        case .scrolling: showScroll(hud.scrollDeflection, tint: tint)
        case .zooming: showZoom(tint: tint)
        case .pressed, .dragging: showPress(dragging: mode == .dragging, tint: tint)
        default: showPointing(progress: CGFloat(min(max(hud.pinchProgress, 0), 1)), tint: tint)
        }
        showTracking(quality: hud.trackingQuality)
        CATransaction.commit()

        if pressing && !wasPressing { click(tint: tint) }
        if wasPressing && !pressing { spring(from: 1.15) }
    }

    private func showPointing(progress: CGFloat, tint: NSColor) {
        let diameter = Self.idleDiameter - (Self.idleDiameter - Self.clickDiameter) * progress
        setRing(diameter: diameter, height: diameter, width: 1.5 + progress)
        ring.strokeColor = (progress > 0.05 ? tint.blended(withFraction: 1 - progress, of: .white) ?? tint : .white).cgColor
        setDot(diameter: 5 + 3 * progress, fill: tint.withAlphaComponent(0.6 + 0.4 * progress))
        knob.opacity = 0
        chevrons.opacity = 0
    }

    private func showPress(dragging: Bool, tint: NSColor) {
        let diameter: CGFloat = dragging ? 18 : 14
        setRing(diameter: diameter, height: diameter, width: 2.5)
        ring.strokeColor = tint.cgColor
        setDot(diameter: 9, fill: tint)
        knob.opacity = 0
        chevrons.opacity = 0
    }

    private func showScroll(_ deflection: Vec2, tint: NSColor) {
        let horizontal = abs(deflection.x) > abs(deflection.y)
        let (width, height): (CGFloat, CGFloat) = horizontal ? (44, 22) : (22, 44)
        setRing(diameter: width, height: height, width: 2)
        ring.strokeColor = tint.cgColor
        setDot(diameter: 0.01, fill: tint)
        // Screen y points down, layer y up: content moving down shows the knob low.
        let travel: CGFloat = 11
        knob.position = CGPoint(x: CGFloat(deflection.x) * travel, y: -CGFloat(deflection.y) * travel)
        knob.opacity = 1
        let along = horizontal ? deflection.x : -deflection.y
        chevrons.transform = CATransform3DMakeRotation(horizontal ? -.pi / 2 : 0, 0, 0, 1)
        chevrons.opacity = 1
        chevronUp.opacity = Float(0.3 + 0.7 * max(along, 0))
        chevronDown.opacity = Float(0.3 + 0.7 * max(-along, 0))
    }

    private func showZoom(tint: NSColor) {
        setRing(diameter: 34, height: 34, width: 2)
        ring.strokeColor = tint.cgColor
        setDot(diameter: 7, fill: tint)
        knob.opacity = 0
        chevrons.opacity = 0
    }

    /// Fades and dashes the reticle as tracking weakens, as the hand nears the edge of the view.
    private func showTracking(quality: Double) {
        layer.opacity = Float(0.35 + 0.65 * min(max(quality, 0), 1))
        let dashed = quality < 0.5
        ring.lineDashPattern = dashed ? [3, 3] : nil
        ringOutline.lineDashPattern = ring.lineDashPattern
    }

    private func setRing(diameter: CGFloat, height: CGFloat, width: CGFloat) {
        let path = Self.capsule(diameter, height)
        ring.path = path
        ringOutline.path = path
        ring.lineWidth = width
        ringOutline.lineWidth = width + 1.5
    }

    private func setDot(diameter: CGFloat, fill: NSColor) {
        dot.path = Self.capsule(diameter, diameter)
        dot.fillColor = fill.cgColor
    }

    /// The press: a quick squash of the reticle and a ripple left where the button went down.
    private func click(tint: NSColor) {
        spring(from: 0.8)
        let ripple = CAShapeLayer()
        ripple.path = Self.capsule(16, 16)
        ripple.fillColor = nil
        ripple.strokeColor = tint.cgColor
        ripple.lineWidth = 2
        ripple.position = layer.position
        ripple.opacity = 0
        layer.superlayer?.insertSublayer(ripple, below: layer)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.8; grow.toValue = 2.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.8; fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.36
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { ripple.removeFromSuperlayer() }
        ripple.add(group, forKey: "ripple")
        CATransaction.commit()
    }

    private func spring(from scale: CGFloat) {
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = scale
        spring.toValue = 1
        spring.damping = 14
        spring.stiffness = 420
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "spring")
    }

    private static func tint(mode: EngineMode, button: MouseButton) -> NSColor {
        switch mode {
        case .scrolling: return .systemOrange
        case .zooming: return .systemPurple
        default: return button == .right ? .systemPink : .controlAccentColor
        }
    }

    /// A rounded rect centred on the origin. Circles and capsules share one path structure, so
    /// Core Animation can morph between them.
    private static func capsule(_ width: CGFloat, _ height: CGFloat) -> CGPath {
        let radius = min(width, height) / 2 - 0.01
        return CGPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func chevron(up: Bool) -> CGPath {
        let sign: CGFloat = up ? 1 : -1
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -4, y: sign * 28))
        path.addLine(to: CGPoint(x: 0, y: sign * 32))
        path.addLine(to: CGPoint(x: 4, y: sign * 28))
        return path
    }
}
