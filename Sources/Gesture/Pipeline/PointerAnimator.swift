import AppKit
import GestureCore
import QuartzCore

/// Posts pointer motion at the display's refresh rate instead of the camera's: a display link
/// drives `DisplayInterpolator` (GestureCore) and posts its positions. Button presses snap to the
/// engine's exact position, so clicks land precisely where the engine decided. Scroll deltas are
/// likewise spread across display ticks.
final class PointerAnimator: NSObject {
    private let executor: ActionExecutor
    private var link: CADisplayLink?
    private var interpolator = DisplayInterpolator()
    private var lastPosted: Vec2?
    private var lastTick: Double?
    private var dragButton: MouseButton?
    private var pendingScroll = Vec2.zero

    /// Pointer position actually shown, display-relative points (for the HUD ring).
    var onRender: ((Vec2) -> Void)?

    var smoothing: Double {
        get { interpolator.smoothing }
        set { interpolator.smoothing = newValue }
    }
    /// Time constant (seconds) over which buffered scroll deltas are released.
    var scrollSmoothing = 0.03

    private let lock = NSLock()
    private var _postedGlobal: CGPoint?
    /// Last pointer location we posted, CG global coordinates. Thread-safe.
    var postedGlobal: CGPoint? { lock.lock(); defer { lock.unlock() }; return _postedGlobal }

    init(executor: ActionExecutor) {
        self.executor = executor
        super.init()
    }

    func attach(to screen: NSScreen) {
        link?.invalidate()
        let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        l.isPaused = true
        link = l
    }

    /// Forget all motion state (suspend, pause). Doesn't post anything.
    func reset() {
        interpolator.reset()
        dragButton = nil; pendingScroll = .zero
        lastPosted = nil; lastTick = nil
        link?.isPaused = true
        lock.lock(); _postedGlobal = nil; lock.unlock()
    }

    /// Feed one processed camera frame (main thread).
    func push(_ output: EngineOutput) {
        for event in output.events {
            switch event {
            case .move, .drag:
                break   // The target comes from output.cursor below, which also covers frames without motion.
            case .down(let button, let position, _):
                snap(to: position)
                executor.apply([event])
                dragButton = button
            case .up(_, let position, _):
                snap(to: position)
                executor.apply([event])
                dragButton = nil
            case .scroll(let dx, let dy, _):
                pendingScroll += Vec2(dx, dy)
            }
        }
        if output.hud.mode == .paused { reset(); return }

        // No cursor while pressing (a coasting frame): keep the current target.
        let pressing = output.hud.mode == .pressed || output.hud.mode == .dragging
        if output.cursor != nil || !pressing { interpolator.push(output.cursor) }
        if interpolator.hasTarget || pendingScroll.length > 0 { link?.isPaused = false }
    }

    private func snap(to point: Vec2) {
        interpolator.snap(to: point)
        lastPosted = point
        setPosted(point)
        onRender?(point)
    }

    private func setPosted(_ point: Vec2) {
        let origin = executor.displayOrigin
        lock.lock(); _postedGlobal = CGPoint(x: origin.x + point.x, y: origin.y + point.y); lock.unlock()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(lastTick.map { now - $0 } ?? link.duration, 0.05)
        lastTick = now

        // Smooth scrolling: release buffered deltas over a few display frames.
        if pendingScroll.length > 0 {
            let a = 1 - exp(-dt / scrollSmoothing)
            var emit = pendingScroll * a
            if pendingScroll.length < 1 { emit = pendingScroll }
            pendingScroll -= emit
            executor.apply([.scroll(dx: emit.x, dy: emit.y, momentum: false)])
        }

        guard let next = interpolator.tick(dt: dt) else {
            if pendingScroll.length == 0 { link.isPaused = true; lastTick = nil }
            return
        }
        if lastPosted.map({ $0.distance(to: next) >= 0.1 }) ?? true {
            if let b = dragButton { executor.apply([.drag(b, next)]) } else { executor.apply([.move(next)]) }
            lastPosted = next
            setPosted(next)
            onRender?(next)
        }
    }
}
