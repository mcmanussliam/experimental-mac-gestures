import AVFoundation
import CoreMedia

/// Low-latency camera capture: the highest frame rate format near 720p, late frames dropped,
/// one serial queue shared by capture → inference → engine so nothing ever queues up.
/// Recovers from runtime errors and from the camera being unplugged or plugged back in.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "gesture.pipeline", qos: .userInteractive)
    var onFrame: ((CMSampleBuffer) -> Void)?
    /// Main thread: human-readable state changes ("FaceTime HD Camera · 1280×720 @ 30 fps", errors).
    var onStatus: ((String) -> Void)?

    private(set) var deviceName = ""
    private(set) var formatDescription = ""
    private(set) var aspect: Double = 16 / 9
    private var preferredDeviceID: String?
    private var preferredFPS = 60
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []

    enum CaptureError: LocalizedError {
        case noCamera, cannotAddInput, cannotAddOutput
        var errorDescription: String? {
            switch self {
            case .noCamera: return "No camera found"
            case .cannotAddInput, .cannotAddOutput: return "The camera is unavailable"
            }
        }
    }

    static func availableCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    override init() {
        super.init()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] n in
            let err = n.userInfo?[AVCaptureSessionErrorKey] as? Error
            Log.camera.error("Capture runtime error: \(err?.localizedDescription ?? "unknown", privacy: .public)")
            self?.onStatus?("Camera error, restarting…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.restart() }
        })
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let d = n.object as? AVCaptureDevice, d.localizedName == self.deviceName else { return }
            Log.camera.info("Camera disconnected: \(d.localizedName, privacy: .public)")
            self.onStatus?("\(d.localizedName) disconnected")
            self.restart()   // falls back to the default camera if one remains
        })
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let d = n.object as? AVCaptureDevice else { return }
            // The preferred camera came back, or we had none at all.
            if d.uniqueID == self.preferredDeviceID || self.deviceName.isEmpty { self.restart() }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func configure(deviceID: String?, preferredFPS: Int) throws {
        preferredDeviceID = deviceID
        self.preferredFPS = preferredFPS
        let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
        guard let device else { deviceName = ""; throw CaptureError.noCamera }
        deviceName = device.localizedName

        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { session.commitConfiguration(); throw CaptureError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        // The webcam's native format: no per-frame conversion.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { session.commitConfiguration(); throw CaptureError.cannotAddOutput }
        session.addOutput(output)
        session.commitConfiguration()

        // Pick a format after the input is attached so the session preset doesn't override it.
        if let (format, rate) = Self.bestFormat(device, preferredFPS: Double(preferredFPS)) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                // Fixed frame duration: stops auto-exposure halving the rate in dim light.
                let d = CMTime(value: 1000, timescale: CMTimeScale(rate * 1000))
                device.activeVideoMinFrameDuration = d
                device.activeVideoMaxFrameDuration = d
                device.unlockForConfiguration()
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                aspect = Double(dims.width) / Double(max(dims.height, 1))
                formatDescription = "\(dims.width)×\(dims.height) @ \(Int(rate)) fps"
            } catch {
                Log.camera.error("Could not configure camera format: \(error.localizedDescription, privacy: .public)")
            }
        }
        Log.camera.info("Using \(self.deviceName, privacy: .public) \(self.formatDescription, privacy: .public)")
    }

    /// Highest achievable frame rate (≤ preferred), then the resolution closest to 1280 wide.
    static func bestFormat(_ device: AVCaptureDevice, preferredFPS: Double) -> (AVCaptureDevice.Format, Double)? {
        var best: (format: AVCaptureDevice.Format, rate: Double, score: Double)?
        for f in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard dims.width >= 640 else { continue }
            let rate = min(f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0, preferredFPS)
            let score = rate * 10_000 - abs(Double(dims.width) - 1280)
            if best == nil || score > best!.score { best = (f, rate, score) }
        }
        return best.map { ($0.format, $0.rate) }
    }

    func start() {
        wantsRunning = true
        queue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func stop() {
        wantsRunning = false
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func restart() {
        guard wantsRunning else { return }
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
        do {
            try configure(deviceID: preferredDeviceID, preferredFPS: preferredFPS)
            start()
            onStatus?("\(deviceName) · \(formatDescription)")
        } catch {
            onStatus?(error.localizedDescription)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }
}
