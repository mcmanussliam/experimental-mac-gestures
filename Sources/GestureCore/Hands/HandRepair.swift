import Foundation

/// Cleans a raw detection before anything else sees it.
///
/// Laptop cameras often cut the wrist off at the bottom of the frame. Vision then still returns
/// a wrist, but with ~0 confidence and sometimes in an absurd place (e.g. the top of the image).
/// Recorded sessions showed the wrist unreliable ~50% of the time and the thumb CMC ~40%, while
/// the four knuckles (MCPs) were reliable ~90%. So:
///  * observations with fewer than 3 reliable knuckles are dropped (the tracker coasts),
///  * unreliable knuckles are re-estimated from a line fit through the others,
///  * an unreliable wrist / thumb CMC is reconstructed from the knuckle line.
public enum HandRepair {
    public static let reliable = 0.3
    /// Palm length (wrist → middle MCP) as a multiple of knuckle width (index → little MCP).
    static let palmLengthPerWidth = 1.4
    static let estimatedConfidence = 0.3

    private static let mcps: [Joint] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]

    public static func repair(_ hand: RawHand, aspect: Double) -> RawHand? {
        // Codable bypasses RawHand's initializer precondition. Validate before indexing;
        // reject non-finite detector/replay artifacts before they poison filters and events.
        guard aspect.isFinite, aspect > 0,
              hand.points.count == Joint.count, hand.confidence.count == Joint.count,
              hand.score.isFinite, hand.score >= reliable,
              hand.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              hand.confidence.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        var repair = Repair(hand: hand, aspect: aspect)
        guard repair.refitKnuckles(), let knuckleLine = repair.knuckleLine(), !repair.isScattered(knuckleWidth: knuckleLine.length)
        else { return nil }
        if !repair.isReliable(.wrist) { repair.rebuildWrist(knuckleLine: knuckleLine) }
        if !repair.isReliable(.thumbCMC) { repair.rebuildThumbBase(knuckleLine: knuckleLine) }
        return repair.hand
    }

    /// Joint positions are read and written in aspect-corrected space, so distances are isotropic.
    private struct Repair {
        var hand: RawHand
        let aspect: Double

        func position(_ joint: Joint) -> Vec2 {
            let point = hand.points[joint.rawValue]
            return Vec2(point.x * aspect, point.y)
        }

        func isReliable(_ joint: Joint) -> Bool { hand.confidence[joint.rawValue] >= HandRepair.reliable }

        mutating func estimate(_ joint: Joint, at point: Vec2) {
            hand.points[joint.rawValue] = Vec2(point.x / aspect, point.y)
            hand.confidence[joint.rawValue] = HandRepair.estimatedConfidence
        }

        /// Knuckles are roughly collinear and evenly spaced: fit p(k) = a + b·k through the reliable
        /// ones and place the missing one on that line. Fails with fewer than three.
        mutating func refitKnuckles() -> Bool {
            let reliable = mcps.indices.filter { isReliable(mcps[$0]) }
            guard reliable.count >= 3 else { return false }
            guard reliable.count < 4 else { return true }
            let ks = reliable.map(Double.init), points = reliable.map { position(mcps[$0]) }
            let kMean = ks.reduce(0, +) / Double(ks.count)
            let pointMean = points.reduce(Vec2.zero, +) / Double(points.count)
            var numerator = Vec2.zero, denominator = 0.0
            for (k, point) in zip(ks, points) {
                numerator += (point - pointMean) * (k - kMean)
                denominator += (k - kMean) * (k - kMean)
            }
            let slope = denominator > 0 ? numerator / denominator : .zero
            for index in mcps.indices where !reliable.contains(index) {
                estimate(mcps[index], at: pointMean + slope * (Double(index) - kMean))
            }
            return true
        }

        /// Index knuckle to little knuckle, or nil if they coincide.
        func knuckleLine() -> Vec2? {
            let line = position(.littleMCP) - position(.indexMCP)
            return line.length > 1e-4 ? line : nil
        }

        /// Broad relative bounds reject scattered landmark artifacts without assuming a hand size
        /// or orientation. Only observed joints are tested; hidden ones are rebuilt afterwards.
        func isScattered(knuckleWidth: Double) -> Bool {
            Finger.allCases.contains { finger in
                zip(finger.joints, finger.joints.dropFirst()).contains { a, b in
                    isReliable(a) && isReliable(b) && position(a).distance(to: position(b)) > knuckleWidth * 3
                }
            }
        }

        /// Perpendicular to the knuckle line, on the side away from the fingers.
        mutating func rebuildWrist(knuckleLine: Vec2) {
            let width = knuckleLine.length
            var normal = Vec2(-knuckleLine.y, knuckleLine.x) / width
            var fingers = Vec2.zero
            for (mcp, pip) in [(Joint.indexMCP, Joint.indexPIP), (.middleMCP, .middlePIP), (.ringMCP, .ringPIP), (.littleMCP, .littlePIP)]
            where isReliable(pip) {
                fingers += position(pip) - position(mcp)
            }
            if fingers.length < 1e-6 { fingers = Vec2(0, -1) }
            if normal.dot(fingers) > 0 { normal = normal * -1 }
            estimate(.wrist, at: position(.middleMCP) + normal * width * palmLengthPerWidth)
        }

        mutating func rebuildThumbBase(knuckleLine: Vec2) {
            let width = knuckleLine.length
            let wrist = position(.wrist)
            let towardThumb = (position(.indexMCP) - position(.littleMCP)) / width
            estimate(.thumbCMC, at: wrist + (position(.indexMCP) - wrist) * 0.4 + towardThumb * width * 0.25)
        }
    }

    /// Mean of the four knuckles: the most reliable, pinch-invariant point on the hand.
    public static func knuckleCenter(_ points: [Vec2]) -> Vec2 {
        mcps.reduce(Vec2.zero) { $0 + points[$1.rawValue] } / 4
    }
}
