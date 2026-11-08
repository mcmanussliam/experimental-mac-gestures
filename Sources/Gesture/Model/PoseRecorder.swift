import Foundation
import GestureCore

/// Records samples of a custom pose for the k-NN library.
@MainActor
final class PoseRecorder: ObservableObject {
    /// Nil = not recording.
    @Published private(set) var progress: Double?
    @Published private(set) var message: String?

    private unowned let model: AppModel
    private var samples: [[Double]] = []
    private var frames = 0
    /// Frames (~3 s at 30 fps).
    private let duration = 90

    init(model: AppModel) { self.model = model }

    func record(name: String, action: String) {
        samples = []; frames = 0; message = nil
        let wasPaused = model.paused
        model.pipeline.setPaused(true)
        progress = 0
        model.pipeline.observe { [weak self] engine in
            let v = engine.currentCanonicalPose()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.progress != nil else { return }
                    self.frames += 1
                    if let v, self.frames % 3 == 0 { self.samples.append(v) }
                    self.progress = Double(self.frames) / Double(self.duration)
                    if self.frames >= self.duration { self.finish(name: name, action: action, wasPaused: wasPaused) }
                }
            }
        }
    }

    private func finish(name: String, action: String, wasPaused: Bool) {
        model.pipeline.observe(nil)
        model.pipeline.setPaused(wasPaused)
        progress = nil
        if samples.count >= 10 {
            model.saveCustomPose(name: name, samples: samples, action: action)
            message = "Saved “\(name)”."
        } else {
            message = "Your hand wasn't visible enough. Try again."
        }
    }
}
