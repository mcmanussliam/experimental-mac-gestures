import Foundation

/// Click, double-click, right click and drag from thumb–finger pinches on the pointer hand.
///
/// A pinch is an *instant* click: button down and up the moment the fingers meet, so a click
/// never lasts as long as the pinch. Moving while still pinched turns it into a drag, and only
/// then is a button held down (at the click position) until the fingers open.
///
/// Entry uses the filtered features for validity and the raw thumb–finger ratio for timing;
/// release debounces the raw ratio directly, since cascading landmark smoothing with a release
/// dwell would swallow the short open interval between the taps of a double-click.
struct PinchController {
    private enum State {
        case open
        /// Clicked; fingers still together, no button held. `anchor`/`palm` are the hand
        /// position and size at the click, to detect the start of a drag.
        case clicked(MouseButton, anchor: Vec2, palm: Double, clickCount: Int)
        /// Button held down while the hand moves.
        case dragging(MouseButton, clickCount: Int)
    }

    /// What the pinch contributes to this frame's pointer and HUD.
    struct Frame {
        /// 0 = follow the hand … 1 = hold the pointer still.
        var damping: Double
        /// 0 = fingers apart … 1 = fingers together.
        var progress: Double
        /// The button a pinch would press (or is pressing).
        var button: MouseButton
    }

    private var state: State = .open
    private var confirmButton: MouseButton?
    private var confirmSince: Double?
    private var armed = false
    private var openSince: Double?
    private var approach = PinchApproach()
    private var dragSince: Double?
    private var lastClick: (t: Double, pos: Vec2, count: Int)?
    private var lastReach: Vec2?
    private var reachVelocity = Vec2.zero
    private var releaseSince: Double?
    private var lastReliable: Double?
    /// Smoothed rate of change of the observed ratio while pressed (palms/s; positive = opening).
    private var opening: (ratio: Double, t: Double, speed: Double)?

    /// Fingers are together after a click (or dragging): the pinch owns the pointer.
    var isPressing: Bool { if case .open = state { return false }; return true }
    var isDragging: Bool { if case .dragging = state { return true }; return false }
    var isSteadying: Bool { approach.steadying }

    mutating func reset() { self = PinchController() }

    /// Releases any held button (hand lost, pause, pointer change): never leave a button stuck.
    mutating func release(at position: Vec2?) -> PointerEvent? {
        defer {
            state = .open
            confirmButton = nil; confirmSince = nil; releaseSince = nil; lastReliable = nil
            armed = false; openSince = nil; approach.reset(); dragSince = nil; opening = nil
        }
        switch state {
        case .dragging(let button, let count): return .up(button, position ?? .zero, clickCount: count)
        case .open, .clicked: return nil
        }
    }

    /// The pointer is now driven by a different hand, or the same hand after a discontinuity.
    mutating func forgetHand(keepClickHistory: Bool) {
        lastReach = nil; reachVelocity = .zero
        if !keepClickHistory { lastClick = nil }
    }

    /// No fresh observation this frame: drop partial evidence, keep the button state.
    mutating func interrupt() {
        confirmButton = nil; confirmSince = nil; releaseSince = nil; opening = nil
        approach.reset()
    }

    /// The thumb is closing on a finger: the hand is about to click, whatever its other fingers do.
    func isClosing(hand: TrackedHand, config: EngineConfig) -> Bool {
        hand.isPinchCapable && hand.features.indexReach >= config.pinchMinReach
            && hand.observedPinchRatio(.left) < config.pinchEnter
    }

    mutating func update(hand: TrackedHand, canPinch: Bool, damping: Double, time: Double, dt: Double,
                         cursor: inout CursorController, config: EngineConfig, events: inout [PointerEvent]) -> Frame {
        let features = hand.features
        let leftValid = features.indexReach >= config.pinchMinReach && hand.isPinchCapable
        let rightValid = config.enableRightClick && features.middleReach >= config.pinchMinReach
            && features.rightPinchConfidence >= HandRepair.reliable
        let indexRatio = hand.observedPinchRatio(.left)
        let middleRatio = hand.observedPinchRatio(.right)
        let ratio = min(leftValid ? indexRatio : .infinity, rightValid ? middleRatio : .infinity)

        if ratio.isFinite && ratio > config.pinchExit {
            if openSince == nil { openSince = time }
            if let since = openSince, time - since >= config.pinchRearmTime { armed = true }
        } else {
            openSince = nil
        }
        let approachDamping = approach.update(ratio: ratio, eligible: !isPressing && armed && canPinch, time: time, config: config)
        // Fingers curling fast, closing into a fist, sweep the tips past the thumb: not a pinch.
        let reach = Vec2(features.indexReach, features.middleReach)
        if let lastReach { reachVelocity = reachVelocity * 0.5 + (reach - lastReach) * (0.5 / dt) }
        lastReach = reach

        let hinted: MouseButton = rightValid && features.pinchMiddle < features.pinchIndex * config.rightClickMargin ? .right : .left
        var frame = Frame(damping: damping,
                          progress: ramp(config.pinchDampStart - ratio, 0, config.pinchDampStart - config.pinchEnter),
                          button: hinted)

        switch state {
        case .open:
            var candidate: MouseButton?
            if canPinch && armed && hand.isAcquired(config: config) && hand.candidatePose != .fist {
                if rightValid && reachVelocity.y >= -config.pinchMaxCurlSpeed && middleRatio < config.pinchEnter
                    && middleRatio < indexRatio * config.rightClickMargin {
                    candidate = .right
                } else if leftValid && reachVelocity.x >= -config.pinchMaxCurlSpeed && indexRatio < config.pinchEnter {
                    candidate = .left
                }
            }
            if clickIfConfirmed(candidate, hand: hand, time: time, cursor: &cursor, config: config, events: &events) {
                frame.damping = 1
            } else if canPinch && approach.steadying {
                // Closing fingers progressively slow the pointer, so a click lands where aimed.
                frame.damping = max(frame.damping, approachDamping)
            }
        case .clicked(let button, let anchor, let palm, let count):
            frame.damping = startDragIfMoved(button: button, anchor: anchor, palm: palm, clickCount: count, hand: hand,
                                             time: time, cursor: &cursor, config: config, events: &events) ? 0 : 1
        case .dragging(let button, let count):
            frame.damping = continueDrag(button: button, clickCount: count, hand: hand, time: time,
                                         cursor: &cursor, config: config, events: &events)
        }

        switch state {
        case .open: break
        case .clicked(let button, _, _, _), .dragging(let button, _):
            frame.button = button
            frame.progress = 1
        }
        return frame
    }

    /// Clicks once `candidate` has been seen for `pinchConfirmTime`: down and up together.
    private mutating func clickIfConfirmed(_ candidate: MouseButton?, hand: TrackedHand, time: Double,
                                           cursor: inout CursorController, config: EngineConfig,
                                           events: inout [PointerEvent]) -> Bool {
        guard let button = candidate else { confirmButton = nil; confirmSince = nil; return false }
        if confirmButton != button { confirmButton = button; confirmSince = time }
        guard time - (confirmSince ?? time) >= config.pinchConfirmTime, let position = cursor.position else { return false }

        var count = 1
        if button == .left, let last = lastClick, time - last.t <= config.doubleClickInterval,
           last.pos.distance(to: position) <= config.doubleClickRadius {
            count = last.count + 1
        }
        state = .clicked(button, anchor: Self.metric(hand.features.palmCenter, hand.aspect),
                         palm: hand.features.palmScale, clickCount: count)
        releaseSince = nil; lastReliable = time; opening = nil
        armed = false; approach.reset(); dragSince = nil
        events.append(.down(button, position, clickCount: count))
        events.append(.up(button, position, clickCount: count))
        lastClick = button == .left ? (time, position, count) : nil
        cursor.hold(until: time + config.postClickHold)
        return true
    }

    /// After a click with the fingers still together: opening re-arms; moving starts a drag.
    private mutating func startDragIfMoved(button: MouseButton, anchor: Vec2, palm: Double, clickCount: Int,
                                           hand: TrackedHand, time: Double, cursor: inout CursorController,
                                           config: EngineConfig, events: inout [PointerEvent]) -> Bool {
        if shouldRelease(button, hand: hand, time: time, config: config) {
            state = .open
            armed = true   // the opening itself proves the fingers parted; a quick re-tap may follow
            return false
        }
        let travel = Self.metric(hand.features.palmCenter, hand.aspect).distance(to: anchor) / max(palm, 1e-4)
        guard Self.reliable(button, hand: hand) && releaseSince == nil && travel > config.dragStartPalms else {
            dragSince = nil
            return false
        }
        if dragSince == nil { dragSince = time }
        guard let since = dragSince, time - since >= config.dragConfirmTime else { return false }
        // The pointer was held at the click spot, so the drag starts exactly there.
        events.append(.down(button, cursor.position ?? .zero, clickCount: clickCount))
        state = .dragging(button, clickCount: clickCount)
        cursor.lockOffset = true
        return true
    }

    /// Returns the pointer damping: the pointer follows the hand while the pinch is reliable.
    private mutating func continueDrag(button: MouseButton, clickCount: Int, hand: TrackedHand, time: Double,
                                       cursor: inout CursorController, config: EngineConfig,
                                       events: inout [PointerEvent]) -> Double {
        let damping: Double = Self.reliable(button, hand: hand) ? 0 : 1
        guard shouldRelease(button, hand: hand, time: time, config: config) else {
            return releaseSince != nil ? 1 : damping
        }
        cursor.lockOffset = false
        cursor.hold(until: time + config.postClickHold)
        events.append(.up(button, cursor.position ?? .zero, clickCount: clickCount))
        lastClick = nil
        state = .open
        armed = true
        return 1
    }

    private static func metric(_ point: Vec2, _ aspect: Double) -> Vec2 { Vec2(point.x * aspect, point.y) }

    private static func reliable(_ button: MouseButton, hand: TrackedHand) -> Bool {
        let confidence = button == .left ? hand.features.pinchConfidence : hand.features.rightPinchConfidence
        return hand.fresh && confidence >= HandRepair.reliable
    }

    /// A release starts with a wide opening or a fast one, and then only needs to stay open.
    private mutating func shouldRelease(_ button: MouseButton, hand: TrackedHand, time: Double,
                                        config: EngineConfig) -> Bool {
        guard Self.reliable(button, hand: hand) else {
            releaseSince = nil
            return time - (lastReliable ?? time) >= config.handLostTimeout
        }
        lastReliable = time
        let ratio = hand.observedPinchRatio(button)
        var speed = 0.0
        if let opening, time > opening.t {
            let rate = (ratio - opening.ratio) / (time - opening.t)
            speed = opening.speed + (rate - opening.speed) * (1 - exp(-(time - opening.t) / 0.05))
        }
        opening = (ratio, time, speed)
        let starts = ratio > config.pinchExit || (ratio > config.pinchFastExit && speed > config.pinchReleaseSpeed)
        guard releaseSince != nil ? ratio > config.pinchFastExit : starts else {
            releaseSince = nil
            return false
        }
        if releaseSince == nil { releaseSince = time }
        return time - (releaseSince ?? time) >= config.pinchReleaseTime
    }
}
