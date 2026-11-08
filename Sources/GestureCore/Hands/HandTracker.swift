import Foundation

/// Associates detections with persistent hand identities (≤ a few hands, so brute force).
///
/// Association is gated by motion: each track predicts where its knuckle centre should be
/// (constant velocity) and only detections within `trackingGate` of that prediction match.
/// A detection that fails the gate while a track is unmatched is first treated as a detector
/// outlier (the track coasts); if it persists for more than `trackingOutlierFrames`, the hand
/// really moved, so the track is re-acquired there, keeping its identity and never spawning a
/// phantom second hand.
public struct HandTracker {
    public private(set) var hands: [TrackedHand] = []
    private var nextID = 1

    public init() {}

    /// Returns the hands that were dropped this frame.
    public mutating func update(frame: HandFrame, config: EngineConfig) -> [TrackedHand] {
        let time = frame.timestamp
        let previouslyFresh = Set(hands.filter(\.fresh).map(\.id))
        for hand in hands { hand.fresh = false }
        let detections = frame.hands.compactMap { HandRepair.repair($0, aspect: frame.aspect) }
        let centers = detections.map { detection -> Vec2 in
            let center = HandRepair.knuckleCenter(detection.points)
            return Vec2(center.x * frame.aspect, center.y)
        }
        var matchedTracks = Set<Int>(), matchedDetections = Set<Int>()
        for (track, detection) in gatedMatches(detections, centers: centers, at: time, config: config) {
            matchedTracks.insert(track); matchedDetections.insert(detection)
            hands[track].fresh = previouslyFresh.contains(hands[track].id)
            hands[track].update(with: detections[detection], time: time, aspect: frame.aspect)
        }
        for detection in detections.indices where !matchedDetections.contains(detection) {
            placeUnmatched(detections[detection], center: centers[detection], excluding: &matchedTracks,
                           at: time, aspect: frame.aspect, config: config)
        }
        let dropped = hands.filter { time - $0.lastSeen > config.handLostTimeout }
        hands.removeAll { time - $0.lastSeen > config.handLostTimeout }
        return dropped
    }

    /// Greedy nearest-neighbour matching of tracks to detections within the motion gate; with two
    /// or three hands, brute force is cheapest. Disagreeing chirality costs half a gate.
    private func gatedMatches(_ detections: [RawHand], centers: [Vec2], at time: Double,
                              config: EngineConfig) -> [(track: Int, detection: Int)] {
        var pairs: [(cost: Double, track: Int, detection: Int)] = []
        for (trackIndex, track) in hands.enumerated() {
            let predicted = track.predictedCenter(at: time)
            for detectionIndex in detections.indices {
                var cost = centers[detectionIndex].distance(to: predicted)
                let chirality = detections[detectionIndex].chirality
                if chirality != .unknown && track.chirality != .unknown && chirality != track.chirality {
                    cost += config.trackingGate / 2
                }
                if cost <= config.trackingGate { pairs.append((cost, trackIndex, detectionIndex)) }
            }
        }
        var usedTracks = Set<Int>(), usedDetections = Set<Int>()
        var matches: [(track: Int, detection: Int)] = []
        for pair in pairs.sorted(by: { $0.cost < $1.cost })
        where !usedTracks.contains(pair.track) && !usedDetections.contains(pair.detection) {
            usedTracks.insert(pair.track); usedDetections.insert(pair.detection)
            matches.append((pair.track, pair.detection))
        }
        return matches
    }

    /// A detection outside every gate is an outlier of the nearest unmatched track, which is
    /// re-acquired if it persists; with no unmatched track it is a new hand.
    private mutating func placeUnmatched(_ detection: RawHand, center: Vec2, excluding matchedTracks: inout Set<Int>,
                                         at time: Double, aspect: Double, config: EngineConfig) {
        let nearest = hands.indices
            .filter { !matchedTracks.contains($0) }
            .min { center.distance(to: hands[$0].predictedCenter(at: time)) < center.distance(to: hands[$1].predictedCenter(at: time)) }
        guard let index = nearest else {
            hands.append(TrackedHand(id: nextID, hand: detection, time: time, aspect: aspect, config: config))
            nextID += 1
            return
        }
        matchedTracks.insert(index)
        let track = hands[index]
        track.outlierStreak += 1
        if track.outlierStreak > config.trackingOutlierFrames {
            track.reacquire(with: detection, time: time, aspect: aspect)
        }
    }

    public mutating func reset() { hands.removeAll() }
}
