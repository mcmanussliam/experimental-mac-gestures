import Foundation

/// The whole gesture pipeline after landmark detection. Pure and deterministic given
/// timestamps, so it can be driven by the camera, a recording, or synthetic tests.
public final class GestureEngine {
    public var config: EngineConfig {
        didSet { if oldValue != config { needsConfigReset = true } }
    }
    public var customPoses = CustomPoseLibrary()
    public private(set) var tracker = HandTracker()
    public private(set) var paused = false

    private var needsConfigReset = false
    private var cursor: CursorController
    private var pointerID: Int?
    private var pointerContinuity = 0
    private var pinch = PinchController()
    private var scroll = ScrollController()
    private var zoom = ZoomController()
    private var pauseHold = PoseHoldRecognizer()
    private var lastTime: Double?
    private var lastEmitted: Vec2?

    public init(config: EngineConfig = EngineConfig()) {
        self.config = config
        self.cursor = CursorController(config: config)
    }

    public func reset() {
        tracker.reset(); cursor.reset(); pointerID = nil; pointerContinuity = 0
        pinch.reset(); scroll.reset(); zoom.reset()
        pauseHold.reset(); lastTime = nil; lastEmitted = nil
    }

    /// Stops cleanly (sleep, camera loss, quit): returns the events needed so no button is left
    /// held down, then forgets all hands.
    public func suspend() -> [PointerEvent] {
        var output = EngineOutput()
        releaseAll(&output)
        reset()
        return output.events
    }

    public func setPaused(_ isPaused: Bool) {
        paused = isPaused
        if isPaused { pointerID = nil; cursor.reset() }
    }

    /// The pointer hand (or, before one is chosen, the first tracked hand), if seen this frame.
    public var pointerHand: TrackedHand? {
        let hand = tracker.hands.first { $0.id == pointerID } ?? tracker.hands.first
        return hand?.fresh == true ? hand : nil
    }

    /// Canonical landmark vector of the pointer hand, for custom pose capture.
    public func currentCanonicalPose() -> [Double]? {
        pointerHand.map { canonicalLandmarks(points: $0.points, aspect: $0.aspect, chirality: $0.chirality) }
    }

    /// - Parameters:
    ///   - screen: size of the target display in points.
    ///   - externalMouse: current system mouse location relative to that display (relative mode).
    public func process(_ frame: HandFrame, screen: Vec2, externalMouse: Vec2? = nil) -> EngineOutput {
        var output = EngineOutput()
        guard frame.timestamp.isFinite, frame.aspect.isFinite, frame.aspect > 0,
              screen.x.isFinite, screen.y.isFinite, screen.x > 0, screen.y > 0 else {
            output.events = suspend()
            return output
        }
        if needsConfigReset {
            releaseAll(&output)
            reset()
            cursor = CursorController(config: config)
            needsConfigReset = false
        }
        let time = frame.timestamp
        let dt = lastTime.map { max(time - $0, 1e-4) } ?? 1.0 / 30
        lastTime = time

        let dropped = tracker.update(frame: frame, config: config)
        if let id = pointerID, dropped.contains(where: { $0.id == id }) {
            releaseAll(&output)
            pointerID = nil
            cursor.reset()
        }
        classifyPoses(at: time)
        togglePauseIfFistHeld(&output, at: time)
        output.hands = tracker.hands.map {
            HandSnapshot(id: $0.id, points: $0.points, pose: $0.poseName, isPointer: $0.id == pointerID,
                         inZone: isInZone($0), chirality: $0.chirality, pinchIndex: $0.features.pinchIndex)
        }
        if paused {
            output.hud.mode = .paused
            return output
        }

        let candidates = tracker.hands.filter { isInZone($0) && ($0.id == pointerID || $0.isAcquired(config: config)) }
        let previousPointer = pointerID
        choosePointer(from: candidates, &output)
        for index in output.hands.indices { output.hands[index].isPointer = output.hands[index].id == pointerID }

        guard let pointer = tracker.hands.first(where: { $0.id == pointerID }) else {
            output.events += scroll.coast(dt: dt, config: config)
            output.hud.mode = .noHand
            runCommandRecognizers(&output, pointer: nil, at: time)
            return output
        }
        if pointer.continuity != pointerContinuity {
            pointerContinuity = pointer.continuity
            if pointerID == previousPointer { cursor.rebase() }
            releaseAll(&output)
            scroll.interrupt()
            pinch.forgetHand(keepClickHistory: true)
        }
        guard pointer.fresh else {
            holdWhileCoasting(&output)
            return output
        }

        let other = candidates.first { $0.id != pointerID && $0.fresh && $0.isAcquired(config: config) }
        updateZoom(pointer: pointer, other: other, aspect: frame.aspect, &output)
        updateScroll(pointer: pointer, aspect: frame.aspect, at: time, &output)

        let canPinch = !zoom.active && !scroll.active && !((other?.pinchLatched ?? false) && !pinch.isPressing)
        // A relaxed hand keeps pointing; only an explicit clutch or interaction freezes it.
        let ownerDamping: Double = !pointer.poseMovesCursor || scroll.active || zoom.active ? 1 : 0
        let press = pinch.update(hand: pointer, canPinch: canPinch, damping: ownerDamping, time: time, dt: dt,
                                 cursor: &cursor, config: config, events: &output.events)
        if pinch.isPressing { scroll.reset() }

        moveCursor(pointer: pointer, damping: press.damping, button: press.button, aspect: frame.aspect,
                   screen: screen, externalMouse: externalMouse, at: time, &output)
        runCommandRecognizers(&output, pointer: pointer, at: time)

        output.hud.cursor = cursor.position
        output.hud.pinchProgress = press.progress
        output.hud.activeButton = press.button
        output.hud.scrollDeflection = scroll.deflection
        output.hud.trackingQuality = trackingQuality(of: pointer)
        output.hud.mode = zoom.active ? .zooming : scroll.active ? .scrolling
            : pinch.isDragging ? .dragging : pinch.isPressing ? .pressed : .pointing
        return output
    }

    private func isInZone(_ hand: TrackedHand) -> Bool {
        hand.features.palmCenter.y <= config.activeZoneBottom
    }

    private func classifyPoses(at time: Double) {
        for hand in tracker.hands where hand.fresh {
            var pose = hand.classifier.classify(hand.features, config: config)
            var name = pose.rawValue
            if hand.features.fingerConfidence.allSatisfy({ $0 >= HandRepair.reliable }), !customPoses.samples.isEmpty,
               let match = customPoses.classify(canonicalLandmarks(points: hand.points, aspect: hand.aspect,
                                                                   chirality: hand.chirality),
                                                threshold: config.customPoseThreshold) {
                name = "custom.\(match.name)"; pose = .unknown
            }
            hand.updatePose(pose, name: name, time: time, commitTime: config.poseCommitTime)
            updatePinchLatch(hand)
        }
    }

    /// Hysteresis-latched pinch, used for the other hand's half of a two-hand zoom.
    private func updatePinchLatch(_ hand: TrackedHand) {
        let ratio = hand.features.pinchIndex
        let valid = hand.features.indexReach >= config.pinchMinReach && hand.isPinchCapable
        if hand.pinchLatched {
            if ratio > config.pinchExit || !valid { hand.pinchLatched = false }
        } else if ratio < config.pinchEnter && valid {
            hand.pinchLatched = true
        }
    }

    private func togglePauseIfFistHeld(_ output: inout EngineOutput, at time: Double) {
        let fist = tracker.hands.first {
            $0.fresh && $0.isAcquired(config: config) && isInZone($0) && $0.pose == .fist && $0.candidatePose == .fist
        }
        guard pauseHold.update(poseName: Pose.fist.rawValue, since: fist?.poseSince ?? time,
                               eligible: fist != nil && !pinch.isPressing, holdTime: config.pauseHoldTime, time: time)
        else { return }
        releaseAll(&output)
        setPaused(!paused)
        output.commands.append(.paused(paused))
    }

    private func choosePointer(from candidates: [TrackedHand], _ output: inout EngineOutput) {
        let previous = pointerID
        if let id = pointerID, !candidates.contains(where: { $0.id == id }) {
            releaseAll(&output)
            pointerID = nil
        }
        let preferred: Chirality? = config.pointerHand == .left ? .left : config.pointerHand == .right ? .right : nil
        if let preferred, !pinch.isPressing,
           let hand = candidates.first(where: { $0.chirality == preferred && $0.fresh }) {
            pointerID = hand.id
        } else if pointerID == nil {
            pointerID = candidates.min { $0.firstSeen < $1.firstSeen }?.id
        }
        if pointerID != previous {
            releaseAll(&output)
            cursor.reset(); lastEmitted = nil
            pinch.forgetHand(keepClickHistory: false)
        }
    }

    /// The pointer hand is tracked but not seen this frame: keep its identity, never act on stale
    /// landmarks, and keep the displayed cursor where it is.
    private func holdWhileCoasting(_ output: inout EngineOutput) {
        pinch.interrupt()
        scroll.interrupt()
        output.cursor = cursor.position
        output.hud.cursor = cursor.position
        output.hud.trackingQuality = 0
        output.hud.mode = pinch.isPressing ? .pressed : scroll.active ? .scrolling : .pointing
    }

    private func updateZoom(pointer: TrackedHand, other: TrackedHand?, aspect: Double, _ output: inout EngineOutput) {
        let spread = other.flatMap { other -> Double? in
            guard other.pinchLatched && pointer.pinchLatched else { return nil }
            return metric(pointer.features.pinchPoint, aspect).distance(to: metric(other.features.pinchPoint, aspect))
        }
        if let command = zoom.update(distance: spread, eitherPinching: pointer.pinchLatched || other?.pinchLatched == true,
                                     canStart: !pinch.isPressing, config: config) {
            output.commands.append(command)
        }
    }

    private func updateScroll(pointer: TrackedHand, aspect: Double, at time: Double, _ output: inout EngineOutput) {
        if pinch.isClosing(hand: pointer, config: config) {
            // A pinch out of a scroll is a click, not a wobble to ride through.
            scroll.reset()
        } else if !zoom.active && !pinch.isPressing {
            // The per-frame candidate pose has its own dwell; the generic pose commit delay would
            // only make scroll entry and exit late.
            output.events += scroll.update(intent: scrollIntent(pointer), anchor: metric(pointer.features.palmCenter, aspect),
                                           palm: pointer.features.palmScale, time: time, config: config)
        } else {
            scroll.reset()
        }
    }

    private func scrollIntent(_ hand: TrackedHand) -> ScrollIntent {
        if hand.candidateName != hand.candidatePose.rawValue { return .release }
        switch hand.candidatePose {
        case .twoFinger: return .engage
        case .unknown: return .ambiguous
        case .open, .point, .fist: return .release
        }
    }

    private func moveCursor(pointer: TrackedHand, damping: Double, button: MouseButton, aspect: Double, screen: Vec2,
                            externalMouse: Vec2?, at time: Double, _ output: inout EngineOutput) {
        // The raw knuckle anchor: the cursor's own 1€ filter is the only smoothing stage, so
        // there is no cascaded lag.
        let position = cursor.update(anchor: HandRepair.knuckleCenter(pointer.raw.points), time: time, aspect: aspect,
                                     screen: screen, externalMouse: externalMouse, damping: damping, config: config,
                                     palmScale: pointer.features.palmScale, dragging: pinch.isDragging)
        output.cursor = position
        if lastEmitted.map({ $0.distance(to: position) >= 0.25 }) ?? true {
            output.events.append(pinch.isDragging ? .drag(button, position) : .move(position))
            lastEmitted = position
        }
    }

    private func runCommandRecognizers(_ output: inout EngineOutput, pointer: TrackedHand?, at time: Double) {
        for hand in tracker.hands where hand.fresh && hand.isAcquired(config: config) {
            let isPointer = hand.id == pointer?.id
            let busy = isPointer && (pinch.isPressing || scroll.active || pinch.isSteadying) || zoom.active
            let eligible = isInZone(hand) && !busy && !hand.pinchLatched

            if let direction = hand.swipe.update(center: metric(hand.features.palmCenter, hand.aspect),
                                                 palm: hand.features.palmScale, open: hand.classifier.extendedCount == 4,
                                                 eligible: eligible, time: time, config: config) {
                output.commands.append(.swipe(direction))
                if isPointer { rewindCursor(to: hand.swipe.lastStrokeStart, &output) }
            }
            if hand.hold.update(poseName: hand.poseName, since: hand.poseSince,
                                eligible: eligible && hand.poseIsCustom && hand.candidateName == hand.poseName,
                                holdTime: config.poseHoldTime, time: time) {
                output.commands.append(.pose(hand.poseName))
            }
        }
    }

    /// A swipe moves the hand a long way; put the pointer back where the stroke began.
    private func rewindCursor(to time: Double, _ output: inout EngineOutput) {
        cursor.rewind(to: time)
        output.cursor = cursor.position
        if let position = cursor.position { output.events.append(.move(position)); lastEmitted = position }
    }

    /// 1 inside the view, falling to 0 within 12% of an edge (the bottom edge is the keyboard zone),
    /// where landmarks get noisy and the hand is about to be lost.
    private func trackingQuality(of hand: TrackedHand) -> Double {
        let center = hand.features.palmCenter
        let margin = min(center.x, 1 - center.x, center.y, config.activeZoneBottom - center.y)
        return ramp(margin, 0.02, 0.12)
    }

    private func metric(_ point: Vec2, _ aspect: Double) -> Vec2 { Vec2(point.x * aspect, point.y) }

    /// Releases any held button and ends every pointer interaction.
    private func releaseAll(_ output: inout EngineOutput) {
        if let up = pinch.release(at: cursor.position) { output.events.append(up) }
        cursor.lockOffset = false
        scroll.reset()
        zoom.reset()
    }
}
