import CoreVideo
import Foundation
import GestureCore
import Vision

/// Apple Vision hand-pose backend. Compute placement is managed by Vision.
///
/// Every frame is analysed full-frame. Cropping to the previous hand box (MediaPipe-style ROI
/// tracking) was tried and removed: Vision's landmarks from a crop and from the full frame
/// differ systematically, so mixing the two passes made the pointer jitter.
final class HandPoseDetector {
    private let request = VNDetectHumanHandPoseRequest()
    private let sequence = VNSequenceRequestHandler()
    var minObservationConfidence: Float = 0.3

    private(set) var lastInferenceMs = 0.0
    var revision: Int { request.revision }

    init(maxHands: Int) {
        request.maximumHandCount = maxHands
    }

    func detect(_ pixelBuffer: CVPixelBuffer, timestamp: Double) -> HandFrame {
        let aspect = Double(CVPixelBufferGetWidth(pixelBuffer)) / Double(CVPixelBufferGetHeight(pixelBuffer))
        let start = CFAbsoluteTimeGetCurrent()
        defer { lastInferenceMs = (CFAbsoluteTimeGetCurrent() - start) * 1000 }
        do { try sequence.perform([request], on: pixelBuffer, orientation: .up) } catch {
            return HandFrame(timestamp: timestamp, aspect: aspect, hands: [])
        }
        let hands = (request.results ?? []).compactMap { obs -> RawHand? in
            guard obs.confidence >= minObservationConfidence,
                  let pts = try? obs.recognizedPoints(.all) else { return nil }
            var points = [Vec2](repeating: Vec2(0.5, 0.5), count: GestureCore.Joint.count)
            var conf = [Double](repeating: 0, count: GestureCore.Joint.count)
            for (name, joint) in Self.jointMap {
                guard let p = pts[name] else { continue }
                // Vision: origin bottom-left. User view: mirrored (selfie), y down.
                points[joint.rawValue] = Vec2(1 - p.location.x, 1 - p.location.y)
                conf[joint.rawValue] = Double(p.confidence)
            }
            let chir: GestureCore.Chirality = obs.chirality == .left ? .left : obs.chirality == .right ? .right : .unknown
            return RawHand(points: points, confidence: conf, chirality: chir, score: Double(obs.confidence))
        }
        return HandFrame(timestamp: timestamp, aspect: aspect, hands: hands)
    }

    private static let jointMap: [(VNHumanHandPoseObservation.JointName, GestureCore.Joint)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
        (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
        (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
        (.littleMCP, .littleMCP), (.littlePIP, .littlePIP), (.littleDIP, .littleDIP), (.littleTip, .littleTip),
    ]
}
