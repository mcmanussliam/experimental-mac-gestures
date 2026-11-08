import AppKit
import AVFoundation
import GestureCore

struct PipelineStats: Equatable {
    var fps = 0.0
    var inferenceMs = 0.0
    /// Capture timestamp → engine output.
    var latencyMs = 0.0
}

/// camera → Vision → engine. Everything after capture runs on the camera's serial queue;
/// results are delivered to the main thread, where the pointer animator posts pointer events.
final class Pipeline {
    let camera = CameraCapture()
    let engine = GestureEngine()
    let executor: ActionExecutor
    private let animator: PointerAnimator
    private var detector: HandPoseDetector
    private var config: AppConfig

    /// Main thread, every processed frame.
    var onOutput: ((EngineOutput, PipelineStats) -> Void)?
    /// Main thread, each recognised command, with whether a bound action ran.
    var onCommand: ((GestureCommand, Bool) -> Void)?

    /// Pipeline-queue state.
    private var stats = PipelineStats()
    private var lastFrameTime: Double?
    private var lastHandTime = 0.0
    private var frameIndex = 0
    private var screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private var recorder: SessionRecorder?
    private var observer: ((GestureEngine) -> Void)?
    /// Bumped on the main thread whenever queued deliveries must be discarded (stop, pause); the
    /// capture queue stamps each delivery with its own copy.
    private var deliveryGeneration = 0
    private var captureGeneration = 0

    init(config: AppConfig, executor: ActionExecutor, animator: PointerAnimator) {
        self.config = config
        self.executor = executor
        self.animator = animator
        detector = HandPoseDetector(maxHands: config.maxHands)
        camera.onFrame = { [weak self] sb in self?.process(sb) }
        apply(config)
    }

    func apply(_ newConfig: AppConfig) {
        camera.queue.async {
            let cameraChanged = newConfig.cameraID != self.config.cameraID || newConfig.preferredFPS != self.config.preferredFPS
            if newConfig.maxHands != self.config.maxHands { self.detector = HandPoseDetector(maxHands: newConfig.maxHands) }
            self.config = newConfig
            self.engine.config = newConfig.engine
            DispatchQueue.main.async { self.executor.setBindings(newConfig.bindings) }
            if cameraChanged { DispatchQueue.main.async { try? self.restartCamera() } }
        }
    }

    func start() throws {
        try camera.configure(deviceID: config.cameraID, preferredFPS: config.preferredFPS)
        camera.start()
    }

    private func restartCamera() throws {
        suspend()
        try start()
    }

    /// Stops the camera and releases anything held. Safe to call repeatedly.
    func suspend() {
        camera.stop()
        deliveryGeneration += 1
        let generation = deliveryGeneration
        let events = camera.queue.sync {
            captureGeneration = generation
            return engine.suspend()
        }
        animator.reset()
        executor.apply(events)
    }

    func setCustomPoses(_ library: CustomPoseLibrary) { camera.queue.async { self.engine.customPoses = library } }

    func setPaused(_ isPaused: Bool) {
        deliveryGeneration += 1
        let generation = deliveryGeneration
        let events = camera.queue.sync { () -> [PointerEvent] in
            captureGeneration = generation
            let released = isPaused ? engine.suspend() : []
            engine.setPaused(isPaused)
            return released
        }
        animator.reset()
        executor.apply(events)
    }

    func setScreen(_ bounds: CGRect) {
        executor.displayOrigin = bounds.origin
        camera.queue.async { self.screen = bounds }
    }

    /// Runs `handler` with the engine after every frame (pipeline queue), e.g. for custom pose recording.
    func observe(_ handler: ((GestureEngine) -> Void)?) { camera.queue.async { self.observer = handler } }

    func setRecorder(_ recorder: SessionRecorder?) { camera.queue.async { self.recorder = recorder } }

    private func process(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        frameIndex += 1

        // Power saving: thin out frames when nobody is there, or control is paused (unless
        // something such as pose recording is observing).
        let idle = time - lastHandTime > config.idleAfter
        if (idle || (engine.paused && observer == nil)) && frameIndex % max(1, config.idleFrameStride) != 0 { return }

        if let last = lastFrameTime { stats.fps = stats.fps * 0.9 + 0.1 / max(time - last, 1e-3) }
        lastFrameTime = time

        let frame = detector.detect(pixelBuffer, timestamp: time)
        if !frame.hands.isEmpty { lastHandTime = time }

        let output = engine.process(frame, screen: Vec2(screen.width, screen.height), externalMouse: externalMouse())
        recorder?.write(frame, output: output, inferenceMs: detector.lastInferenceMs, detectorRevision: detector.revision)
        observer?(engine)

        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        stats.inferenceMs = stats.inferenceMs * 0.9 + 0.1 * detector.lastInferenceMs
        stats.latencyMs = stats.latencyMs * 0.9 + 0.1 * (now - time) * 1000
        let latest = stats
        let generation = captureGeneration
        DispatchQueue.main.async {
            guard generation == self.deliveryGeneration else { return }
            self.animator.push(output)
            self.onOutput?(output, latest)
            for command in output.commands {
                self.onCommand?(command, self.executor.run(command))
            }
        }
    }

    /// The real mouse position, but only when something other than us moved it (trackpad use),
    /// so the animator's between-frame easing isn't mistaken for external input.
    private func externalMouse() -> Vec2? {
        guard let mouse = CGEvent(source: nil)?.location else { return nil }
        if let posted = animator.postedGlobal, hypot(mouse.x - posted.x, mouse.y - posted.y) <= 3 { return nil }
        return Vec2(mouse.x - screen.minX, mouse.y - screen.minY)
    }
}
