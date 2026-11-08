import Foundation

/// Scale-invariant geometric description of one hand.
/// "Metric" points are aspect-corrected (x multiplied by image aspect) so that distances
/// are isotropic, expressed in camera-height units.
public struct HandFeatures: Sendable {
    /// Knuckle centre in user-view normalised coordinates (not aspect corrected): the cursor anchor.
    /// Excludes the wrist, which is often outside a laptop camera's frame.
    public var palmCenter: Vec2
    /// Palm scale in camera-height units.
    public var palmScale: Double
    /// Per-finger extension score in [0,1], indexed by Finger.rawValue.
    public var extensionScore: [Double]
    /// Minimum observed confidence along each finger; repaired/stale positions are not evidence.
    public var fingerConfidence: [Double]
    /// Thumb-tip to finger-tip distances, in palms.
    public var pinchIndex: Double
    public var pinchMiddle: Double
    /// Finger tip to wrist distance, in palms.
    public var indexReach: Double
    public var middleReach: Double
    /// Midpoint of thumb and index tips, user-view normalised coordinates.
    public var pinchPoint: Vec2
    /// Lowest joint confidence among the pinch-relevant joints.
    public var pinchConfidence: Double
    public var rightPinchConfidence: Double

    public static func compute(points p: [Vec2], confidence: [Double], aspect: Double) -> HandFeatures {
        @inline(__always) func m(_ j: Joint) -> Vec2 { let v = p[j.rawValue]; return Vec2(v.x * aspect, v.y) }

        let wrist = m(.wrist)
        // Palm scale: robust to in-plane rotation and partial foreshortening.
        let lengthScale = wrist.distance(to: m(.middleMCP))
        let widthScale = m(.indexMCP).distance(to: m(.littleMCP)) * 1.25
        let palm = max(max(lengthScale, widthScale), 1e-4)

        var ext = [Double](repeating: 0, count: 5)
        for f in [Finger.index, .middle, .ring, .little] {
            let j = f.joints.map(m)
            let chain = j[0].distance(to: j[1]) + j[1].distance(to: j[2]) + j[2].distance(to: j[3])
            let straight = chain > 1e-6 ? j[0].distance(to: j[3]) / chain : 0
            let pipDist = max(wrist.distance(to: j[1]), 1e-6)
            let reach = wrist.distance(to: j[3]) / pipDist
            ext[f.rawValue] = 0.5 * ramp(straight, 0.55, 0.92) + 0.5 * ramp(reach, 0.95, 1.35)
        }
        do {
            let j = Finger.thumb.joints.map(m)
            let chain = j[0].distance(to: j[1]) + j[1].distance(to: j[2]) + j[2].distance(to: j[3])
            let straight = chain > 1e-6 ? j[0].distance(to: j[3]) / chain : 0
            let away = j[3].distance(to: m(.indexMCP)) / palm
            let awayMid = j[3].distance(to: m(.middlePIP)) / palm
            ext[0] = 0.4 * ramp(straight, 0.75, 0.95) + 0.3 * ramp(away, 0.35, 0.75) + 0.3 * ramp(awayMid, 0.4, 0.8)
        }

        let thumbTip = m(.thumbTip), indexTip = m(.indexTip), middleTip = m(.middleTip)

        let palmCenterRaw = HandRepair.knuckleCenter(p)
        let pinchJoints: [Joint] = [.thumbTip, .indexTip, .thumbIP, .indexDIP]
        let rightPinchJoints: [Joint] = [.thumbTip, .middleTip, .thumbIP, .middleDIP]

        return HandFeatures(
            palmCenter: palmCenterRaw,
            palmScale: palm,
            extensionScore: ext,
            fingerConfidence: Finger.allCases.map { finger in
                finger.joints.dropFirst().map { confidence[$0.rawValue] }.min() ?? 0
            },
            pinchIndex: thumbTip.distance(to: indexTip) / palm,
            pinchMiddle: thumbTip.distance(to: middleTip) / palm,
            indexReach: indexTip.distance(to: wrist) / palm,
            middleReach: middleTip.distance(to: wrist) / palm,
            pinchPoint: (p[Joint.thumbTip.rawValue] + p[Joint.indexTip.rawValue]) / 2,
            pinchConfidence: pinchJoints.map { confidence[$0.rawValue] }.min() ?? 0,
            rightPinchConfidence: rightPinchJoints.map { confidence[$0.rawValue] }.min() ?? 0
        )
    }
}

/// Canonical landmark vector for custom pose matching: wrist-centred, palm-scaled,
/// rotated so wrist→middle MCP points up, left hands mirrored onto right.
public func canonicalLandmarks(points p: [Vec2], aspect: Double, chirality: Chirality) -> [Double] {
    let pts = p.map { Vec2($0.x * aspect, $0.y) }
    let wrist = pts[Joint.wrist.rawValue]
    let axis = pts[Joint.middleMCP.rawValue] - wrist
    let scale = max(axis.length, 1e-6)
    // Rotate so `axis` maps to (0,-1) (up in y-down space).
    let angle = atan2(-1.0, 0.0) - atan2(axis.y, axis.x)
    let flip = chirality == .left ? -1.0 : 1.0
    var out: [Double] = []
    out.reserveCapacity(40)
    for i in 1..<Joint.count {
        let v = ((pts[i] - wrist) / scale).rotated(by: angle)
        out.append(v.x * flip); out.append(v.y)
    }
    return out
}
