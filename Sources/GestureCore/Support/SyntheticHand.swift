import Foundation

/// Procedural 2D hand generator for tests, demos and replay sanity checks.
/// Local frame: palm-facing view, y down, fingers pointing up (−y), thumb on the −x side,
/// all lengths in palms. `rotation` rotates the whole hand (radians, +90° = fingers right).
public struct SyntheticHand {
    /// Palm centre, user-view normalised.
    public var center = Vec2(0.5, 0.45)
    /// Palm size, camera-height units.
    public var scale = 0.12
    public var rotation = 0.0
    /// Thumb … little.
    public var extended: [Bool] = [true, true, true, true, true]
    /// Direction of an extended thumb in local coordinates.
    public var thumbDirection = Vec2(-0.7, -0.7)
    /// Thumb–index tip gap in palms (nil = no pinch shaping).
    public var pinchIndexGap: Double?
    public var pinchMiddleGap: Double?
    /// Extra angle (radians) between index and middle when both are extended ("V").
    public var spread = 0.0
    public var chirality: Chirality = .right
    public var confidence = 0.9

    public init() {}

    public static func pose(_ p: Pose) -> SyntheticHand {
        var h = SyntheticHand()
        switch p {
        case .open, .unknown: break
        case .point: h.extended = [false, true, false, false, false]
        case .twoFinger: h.extended = [false, true, true, false, false]
        case .fist: h.extended = [false, false, false, false, false]
        }
        return h
    }

    private static let mcp: [Vec2] = [Vec2(-0.25, -0.25), Vec2(-0.30, -0.95), Vec2(-0.05, -1.0), Vec2(0.18, -0.95), Vec2(0.38, -0.85)]
    private static let segs: [[Double]] = [[0.35, 0.30, 0.25], [0.45, 0.27, 0.22], [0.50, 0.30, 0.24], [0.46, 0.28, 0.22], [0.36, 0.22, 0.20]]
    private static let palmCenterLocal = (Vec2(0, 0) + mcp[1] + mcp[2] + mcp[3]) / 4

    /// Joint positions in local palm units.
    public func localPoints() -> [Vec2] {
        var pts = [Vec2](repeating: .zero, count: Joint.count)
        pts[Joint.wrist.rawValue] = .zero

        func setFinger(_ f: Finger, _ js: [Vec2]) { for (k, j) in f.joints.enumerated() { pts[j.rawValue] = js[k] } }

        func straight(_ f: Finger, dir: Vec2) -> [Vec2] {
            let b = Self.mcp[f.rawValue], s = Self.segs[f.rawValue]
            let p1 = b + dir * s[0], p2 = p1 + dir * s[1]
            return [b, p1, p2, p2 + dir * s[2]]
        }
        func curled(_ f: Finger) -> [Vec2] {
            let b = Self.mcp[f.rawValue], dir = b.normalized
            let pip = b + dir * 0.25, dip = b + dir * 0.17
            return [b, pip, dip, b - dir * 0.15]
        }
        /// Finger hooked toward the thumb so its tip can meet the thumb.
        func hooked(_ f: Finger) -> [Vec2] {
            let b = Self.mcp[f.rawValue], s = Self.segs[f.rawValue], dir = b.normalized
            let p1 = b + dir * s[0]
            let p2 = p1 + dir.rotated(by: -0.7) * s[1]
            return [b, p1, p2, p2 + dir.rotated(by: -1.4) * s[2]]
        }

        for f in [Finger.index, .middle, .ring, .little] {
            // Fingers of a relaxed hand are nearly parallel (only a slight fan).
            let b = Self.mcp[f.rawValue]
            var dir = Vec2(b.x * 0.3, b.y).normalized
            if f == .index { dir = dir.rotated(by: -spread / 2) }
            if f == .middle { dir = dir.rotated(by: spread / 2) }
            if f == .index && pinchIndexGap != nil { setFinger(f, hooked(f)); continue }
            if f == .middle && pinchMiddleGap != nil { setFinger(f, hooked(f)); continue }
            setFinger(f, extended[f.rawValue] ? straight(f, dir: dir) : curled(f))
        }

        let cmc = Self.mcp[0]
        let openThumb = straight(.thumb, dir: thumbDirection.normalized)
        if let gap = pinchMiddleGap ?? pinchIndexGap {
            let target = pts[(pinchMiddleGap != nil ? Joint.middleTip : Joint.indexTip).rawValue]
            let tip = target.lerp(to: openThumb[3], clamp01(gap))
            let mid = cmc.lerp(to: tip, 0.5) + Vec2(-0.12, 0)
            setFinger(.thumb, [cmc, cmc.lerp(to: mid, 0.7), mid.lerp(to: tip, 0.5), tip])
        } else if extended[0] {
            setFinger(.thumb, openThumb)
        } else {
            setFinger(.thumb, [cmc, Vec2(-0.30, -0.55), Vec2(-0.15, -0.75), Vec2(0.0, -0.72)])
        }
        return pts
    }

    public func raw(aspect: Double = 16.0 / 9.0) -> RawHand {
        let local = localPoints()
        let pcRot = Self.palmCenterLocal.rotated(by: rotation) * scale
        let centerMetric = Vec2(center.x * aspect, center.y)
        var pts: [Vec2] = []
        for p in local {
            let m = centerMetric + p.rotated(by: rotation) * scale - pcRot
            var v = Vec2(m.x / aspect, m.y)
            // Chirality only mirrors the hand; geometry stays plausible either way.
            if chirality == .left { v.x = center.x - (v.x - center.x) }
            pts.append(v)
        }
        return RawHand(points: pts, confidence: [Double](repeating: confidence, count: Joint.count),
                       chirality: chirality, score: confidence)
    }
}
