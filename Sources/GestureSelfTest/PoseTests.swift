import Foundation
import GestureCore

/// Pose classification and custom poses.
func poseTests() {
    test("Pose classifier: all built-in poses") {
        for pose in Pose.allCases where pose != .unknown {
            var cls = PoseClassifier()
            let raw = SyntheticHand.pose(pose).raw()
            let f = HandFeatures.compute(points: raw.points, confidence: raw.confidence, aspect: 16 / 9)
            var got = Pose.unknown
            for _ in 0..<3 { got = cls.classify(f, config: EngineConfig()) }
            check(got == pose, "\(pose) classified as \(got) ext=\(f.extensionScore.map { String(format: "%.2f", $0) })")
        }
    }

    test("Pose classifier: scale and rotation invariance") {
        for (scale, rot) in [(0.05, 0.0), (0.25, 0.0), (0.12, 0.5), (0.12, -0.6)] {
            for pose in [Pose.point, .twoFinger] {
                var h = SyntheticHand.pose(pose); h.scale = scale; h.rotation = rot
                var cls = PoseClassifier()
                let raw = h.raw()
                let f = HandFeatures.compute(points: raw.points, confidence: raw.confidence, aspect: 16 / 9)
                let got = cls.classify(f, config: EngineConfig())
                check(got == pose, "\(pose) at scale \(scale) rot \(rot) → \(got)")
            }
        }
    }

    test("Shapes outside the vocabulary fire nothing") {
        var thumbsUp = SyntheticHand(); thumbsUp.extended = [true, false, false, false, false]
        thumbsUp.rotation = .pi / 2; thumbsUp.thumbDirection = Vec2(-1, 0)
        var three = SyntheticHand(); three.extended = [false, true, true, true, false]
        for shape in [thumbsUp, three, horns()] {
            let d = Driver()
            d.run([shape], seconds: 1.5)
            check(d.commands.isEmpty && d.downs.isEmpty, "no commands or clicks (\(d.commands))")
        }
    }

    test("Half-bent fingers are ambiguous: no pose command fires") {
        var cls = PoseClassifier()
        let raw = horns().raw()
        var f = HandFeatures.compute(points: raw.points, confidence: raw.confidence, aspect: 16 / 9)
        f.extensionScore = [0.2, 0.62, 0.5, 0.52, 0.6]                // a recorded indecisive hand
        check(cls.classify(f, config: EngineConfig()) == .unknown, "unknown")
    }

    test("Comfortably bent ring/little fingers still allow scrolling") {
        let h = SyntheticHand.pose(.twoFinger).raw()
        var f = HandFeatures.compute(points: h.points, confidence: h.confidence, aspect: 16 / 9)
        f.extensionScore[3] = 0.50; f.extensionScore[4] = 0.48
        var cls = PoseClassifier()
        check(cls.classify(f, config: EngineConfig()) == .twoFinger, "relaxed scroll pose accepted")
        f.fingerConfidence[1] = 0.05
        check(cls.classify(f, config: EngineConfig()) == .unknown, "unseen index cannot assert scroll pose")
    }

    test("Custom pose k-NN") {
        var lib = CustomPoseLibrary()
        let rock = horns().raw(), point = SyntheticHand.pose(.point).raw()
        lib.samples.append(CustomPoseSample(name: "horns", vector: canonicalLandmarks(points: rock.points, aspect: 16 / 9, chirality: .right)))
        var r2 = horns(); r2.rotation = 0.4; r2.scale = 0.2
        let q = r2.raw()
        check(lib.classify(canonicalLandmarks(points: q.points, aspect: 16 / 9, chirality: .right), threshold: 0.5)?.name == "horns",
              "rotated/scaled match")
        check(lib.classify(canonicalLandmarks(points: point.points, aspect: 16 / 9, chirality: .right), threshold: 0.5) == nil,
              "different pose rejected")
    }

    test("Custom poses reject ambiguous votes and malformed vectors") {
        let lib = CustomPoseLibrary(samples: [CustomPoseSample(name: "a", vector: [0, 0]),
                                              CustomPoseSample(name: "b", vector: [0, 0])])
        check(lib.classify([0, 0], threshold: 0.5) == nil, "tied classes are rejected")
        check(lib.classify([0], threshold: 0.5) == nil, "odd vector rejected")
        check(lib.classify([.nan, 0], threshold: 0.5) == nil, "NaN vector rejected")
        check(lib.classify([0, 0], k: 0, threshold: 0.5) == nil, "zero neighbours rejected")
    }
}
