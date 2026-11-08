import Foundation
import GestureCore

// gesture-lab: offline analysis of recorded sessions. Everything runs the real engine, so
// results match the app exactly.

guard let options = Options(Array(CommandLine.arguments.dropFirst())) else {
    print(Options.usage)
    exit(CommandLine.arguments.dropFirst().first == "--help" ? 0 : 1)
}
let config = try options.engineConfig()
let frames = try Recording.load(options.session)
guard !frames.isEmpty else { print("empty session"); exit(1) }

switch options.command {
case "replay": printEvents(replay(frames, config: config, customPoses: options.customPoses))
case "trace": printTrace(replay(frames, config: config, customPoses: options.customPoses))
case "features": printFeatures(replay(frames, config: config, customPoses: options.customPoses))
case "score": Score(samples: replay(frames, config: config, customPoses: options.customPoses), config: config).report()
case "display":
    let result = Display.run(frames, config: config, screen: replayScreen, smoothing: options.displaySmoothing)
    Display.report(result, smoothing: options.displaySmoothing)
default:
    print(Options.usage)
    exit(1)
}
