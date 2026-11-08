import Foundation
import GestureCore

/// Display size used for every replay, so results are comparable between machines.
let replayScreen = Vec2(1710, 1112)

/// Runs the engine over a recording, capturing the pointer hand's state at every frame.
func replay(_ frames: [HandFrame], config: EngineConfig, customPoses: CustomPoseLibrary) -> [Sample] {
    let engine = GestureEngine(config: config)
    engine.customPoses = customPoses
    let start = frames.first?.timestamp ?? 0
    return frames.map { frame in
        let output = engine.process(frame, screen: replayScreen)
        let pointerID = output.hands.first { $0.isPointer }?.id
        let pointer = engine.tracker.hands.first { $0.id == pointerID }
        return Sample(time: frame.timestamp - start, output: output, pointerID: pointer?.id,
                      continuity: pointer?.continuity ?? 0, poseName: pointer?.poseName, features: pointer?.features,
                      fresh: pointer?.fresh ?? false, knuckles: pointer.map { HandRepair.knuckleCenter($0.raw.points) })
    }
}

private func format(_ value: Double, _ digits: Int = 3) -> String { String(format: "%.\(digits)f", value) }

func printEvents(_ samples: [Sample]) {
    var counts: [String: Int] = [:]
    for sample in samples {
        let time = format(sample.time)
        for event in sample.output.events {
            switch event {
            case .down(let button, let position, let count):
                print("\(time)  down \(button) ×\(count) at (\(Int(position.x)), \(Int(position.y)))")
                counts["press.\(button)", default: 0] += 1
            case .up(let button, let position, _):
                print("\(time)  up   \(button) at (\(Int(position.x)), \(Int(position.y)))")
            default: break
            }
        }
        for command in sample.output.commands {
            print("\(time)  \(command.bindingKey)")
            counts[command.bindingKey, default: 0] += 1
        }
    }
    print("\n\(samples.count) frames, \(format(samples.last?.time ?? 0, 1)) s")
    for (key, count) in counts.sorted(by: { $0.key < $1.key }) { print("  \(key): \(count)") }
}

func printTrace(_ samples: [Sample]) {
    print("t,x,y,mode")
    for sample in samples {
        guard let cursor = sample.output.cursor else { continue }
        print("\(format(sample.time, 4)),\(format(cursor.x, 2)),\(format(cursor.y, 2)),\(sample.output.hud.mode.rawValue)")
    }
}

func printFeatures(_ samples: [Sample]) {
    print("t,mode,pose,pinchIndex,pinchMiddle,indexReach,middleReach,palmScale,ext0,ext1,ext2,ext3,ext4,fresh")
    for sample in samples {
        guard let features = sample.features, let pose = sample.poseName else { continue }
        let columns = [format(sample.time, 4), sample.output.hud.mode.rawValue, pose, format(features.pinchIndex),
                       format(features.pinchMiddle), format(features.indexReach), format(features.middleReach),
                       format(features.palmScale, 4)]
            + features.extensionScore.map { format($0, 2) } + [sample.fresh ? "1" : "0"]
        print(columns.joined(separator: ","))
    }
}
