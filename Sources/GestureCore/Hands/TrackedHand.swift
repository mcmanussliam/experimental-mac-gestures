import Foundation

/// Per-hand state persisted across frames.
public final class TrackedHand {
    public let id: Int
    public internal(set) var chirality: Chirality
    public let firstSeen: Double
    public internal(set) var lastSeen: Double
    public internal(set) var raw: RawHand
    /// 1€-filtered landmarks (user-view normalised).
    public internal(set) var points: [Vec2]
    public internal(set) var features: HandFeatures
    /// Stable (committed) pose name: a `Pose.rawValue` or `custom.<name>`.
    public internal(set) var poseName: String = Pose.unknown.rawValue
    public internal(set) var pose: Pose = .unknown
    public internal(set) var poseSince: Double
    /// True if this hand was observed in the current frame (false while coasting).
    public internal(set) var fresh = true
    /// True if the committed pose came from the custom pose library.
    public internal(set) var poseIsCustom = false
    /// Hysteresis-latched thumb–index pinch (used for zoom / non-pointer hands).
    public internal(set) var pinchLatched = false

    /// Incremented when the track is re-acquired after a discontinuity; consumers that
    /// integrate motion (relative pointer) must not treat the jump as movement.
    public internal(set) var continuity = 0

    var filters: [OneEuroFilter2D]
    /// Knuckle centre (aspect-corrected) and its velocity, for gated association.
    private var center: Vec2 = .zero
    private var velocity: Vec2 = .zero
    /// Consecutive frames whose only nearby detection failed the motion gate.
    var outlierStreak = 0
    var classifier = PoseClassifier()
    var candidateName: String = Pose.unknown.rawValue
    var candidatePose: Pose = .unknown
    var candidateSince: Double
    var swipe = SwipeRecognizer()
    var hold = PoseHoldRecognizer()
    var aspect: Double
    private var visibleSince: Double
    private var observations = 0

    public func isAcquired(config: EngineConfig) -> Bool {
        observations >= 3 && lastSeen - visibleSince >= config.handAcquireTime
    }

    init(id: Int, hand: RawHand, time t: Double, aspect: Double, config: EngineConfig) {
        self.id = id
        self.chirality = hand.chirality
        self.firstSeen = t; self.lastSeen = t
        self.raw = hand
        self.aspect = aspect
        self.visibleSince = t
        self.filters = (0..<Joint.count).map { _ in
            OneEuroFilter2D(minCutoff: config.landmarkMinCutoff, beta: config.landmarkBeta)
        }
        self.points = hand.points
        self.features = HandFeatures.compute(points: hand.points, confidence: hand.confidence, aspect: aspect)
        self.poseSince = t; self.candidateSince = t
        update(with: hand, time: t, aspect: aspect)
    }

    func predictedCenter(at t: Double) -> Vec2 { center + velocity * min(t - lastSeen, 0.1) }

    func update(with hand: RawHand, time t: Double, aspect: Double) {
        if !fresh {
            visibleSince = t; observations = 0
            candidateSince = t; poseSince = t
            hold.reset(); swipe.reset(); pinchLatched = false
        }
        observations += 1
        let k = HandRepair.knuckleCenter(hand.points)
        let newCenter = Vec2(k.x * aspect, k.y)
        let dt = t - lastSeen
        if dt > 1e-4 && dt < 0.2 { velocity = velocity.lerp(to: (newCenter - center) / dt, 0.5) }
        center = newCenter
        outlierStreak = 0
        raw = hand
        lastSeen = t
        fresh = true
        self.aspect = aspect
        if hand.chirality != .unknown { chirality = hand.chirality }
        for i in 0..<Joint.count {
            // Unreliable joints keep their previous filtered position.
            if hand.confidence[i] >= HandRepair.reliable || filters[i].value == nil {
                // Filter in aspect-corrected space so x and y get the same treatment.
                let v = Vec2(hand.points[i].x * aspect, hand.points[i].y)
                let f = filters[i].filter(v, t: t)
                points[i] = Vec2(f.x / aspect, f.y)
            }
        }
        features = HandFeatures.compute(points: points, confidence: hand.confidence, aspect: aspect)
    }

    /// The hand is really somewhere else now: restart smoothing there instead of gliding across.
    func reacquire(with hand: RawHand, time t: Double, aspect: Double) {
        for i in filters.indices { filters[i].reset() }
        velocity = .zero
        lastSeen = t
        continuity += 1
        swipe.reset()
        classifier.reset(); hold.reset()
        pinchLatched = false
        pose = .unknown; poseName = Pose.unknown.rawValue; poseIsCustom = false
        candidateName = poseName; candidatePose = .unknown; candidateSince = t; poseSince = t
        update(with: hand, time: t, aspect: aspect)
    }

    /// Debounced pose commit: a candidate must persist `poseCommitTime` before it replaces the pose.
    func updatePose(_ newPose: Pose, name: String, time t: Double, commitTime: Double) {
        if name != candidateName { candidateName = name; candidatePose = newPose; candidateSince = t }
        if candidateName != poseName && t - candidateSince >= commitTime {
            poseName = candidateName; pose = candidatePose; poseSince = t
            poseIsCustom = poseName.hasPrefix("custom.")
        }
    }

    /// Cursor follows this hand only in "pointing" poses.
    public var poseMovesCursor: Bool { !poseIsCustom && pose.movesCursor }

    public var isPinchCapable: Bool { features.pinchConfidence >= HandRepair.reliable }

    /// Unfiltered thumb–finger tip distance in palms; the measure pinch thresholds apply to.
    public func observedPinchRatio(_ button: MouseButton) -> Double {
        let tip: Joint = button == .left ? .indexTip : .middleTip
        let a = raw[.thumbTip], b = raw[tip]
        return Vec2((a.x - b.x) * aspect, a.y - b.y).length / max(features.palmScale, 1e-4)
    }
}
