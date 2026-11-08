import AppKit
import AVFoundation
import GestureCore

/// Debug window: mirrored camera feed, tracked skeletons, poses and live stats.
final class PreviewWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let skeleton = CAShapeLayer()
    private let pointerSkeleton = CAShapeLayer()
    private let joints = CAShapeLayer()
    private let info = CATextLayer()
    private let labels = CALayer()
    private let zoneLine = CAShapeLayer()
    var activeZoneBottom = 0.92
    var onClose: (() -> Void)?

    init(session: AVCaptureSession, aspect: CGFloat) {
        let w: CGFloat = 720
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: w / aspect),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Gesture Camera"
        window.contentAspectRatio = NSSize(width: aspect, height: 1)
        window.isReleasedWhenClosed = false
        window.level = .floating
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init()
        window.delegate = self

        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = view

        previewLayer.videoGravity = .resize
        if let conn = previewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        previewLayer.frame = view.bounds
        view.layer?.addSublayer(previewLayer)

        for l in [skeleton, pointerSkeleton, joints, zoneLine] {
            l.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            l.frame = view.bounds
            view.layer?.addSublayer(l)
        }
        skeleton.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        skeleton.lineWidth = 2; skeleton.fillColor = nil
        pointerSkeleton.strokeColor = NSColor.systemGreen.cgColor
        pointerSkeleton.lineWidth = 3; pointerSkeleton.fillColor = nil
        joints.fillColor = NSColor.systemYellow.cgColor
        zoneLine.strokeColor = NSColor.systemRed.withAlphaComponent(0.6).cgColor
        zoneLine.lineDashPattern = [6, 6]; zoneLine.lineWidth = 1.5

        labels.frame = view.bounds
        labels.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(labels)

        info.fontSize = 12
        info.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        info.foregroundColor = NSColor.white.cgColor
        info.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        info.contentsScale = 2
        info.frame = CGRect(x: 8, y: 8, width: 420, height: 34)
        view.layer?.addSublayer(info)
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isVisible: Bool { window.isVisible }
    func windowWillClose(_ notification: Notification) { onClose?() }

    func update(_ out: EngineOutput, stats: PipelineStats, cameraInfo: String) {
        guard window.isVisible else { return }
        let b = window.contentView!.bounds
        func pt(_ v: Vec2) -> CGPoint { CGPoint(x: v.x * b.width, y: (1 - v.y) * b.height) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let normal = CGMutablePath(), pointer = CGMutablePath(), dots = CGMutablePath()
        labels.sublayers?.forEach { $0.removeFromSuperlayer() }
        for h in out.hands {
            let path = h.isPointer ? pointer : normal
            for (a, c) in handBones {
                path.move(to: pt(h.points[a.rawValue])); path.addLine(to: pt(h.points[c.rawValue]))
            }
            for p in h.points { let q = pt(p); dots.addEllipse(in: CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)) }

            let label = CATextLayer()
            label.string = "\(h.pose)\(h.inZone ? "" : " (ignored)")  pinch \(String(format: "%.2f", h.pinchIndex))  \(h.chirality.rawValue)"
            label.fontSize = 13
            label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            label.foregroundColor = (h.isPointer ? NSColor.systemGreen : NSColor.white).cgColor
            label.contentsScale = 2
            let w = pt(h.points[GestureCore.Joint.wrist.rawValue])
            label.frame = CGRect(x: w.x - 120, y: w.y - 26, width: 260, height: 18)
            labels.addSublayer(label)
        }
        skeleton.path = normal; pointerSkeleton.path = pointer; joints.path = dots
        let z = CGMutablePath()
        let zy = (1 - activeZoneBottom) * b.height
        z.move(to: CGPoint(x: 0, y: zy)); z.addLine(to: CGPoint(x: b.width, y: zy))
        zoneLine.path = z
        info.string = String(format: " %@ · %.0f fps · vision %.1f ms · latency %.0f ms\n mode: %@",
                             cameraInfo, stats.fps, stats.inferenceMs, stats.latencyMs, out.hud.mode.rawValue)
        CATransaction.commit()
    }
}
