import Foundation

public enum MouseButton: String, Codable, Sendable { case left, right }

public enum PointerEvent: Equatable, Sendable {
    case move(Vec2)
    case down(MouseButton, Vec2, clickCount: Int)
    case up(MouseButton, Vec2, clickCount: Int)
    case drag(MouseButton, Vec2)
    /// Content displacement in points (positive y = content moves down, like dragging it).
    case scroll(dx: Double, dy: Double, momentum: Bool)
}

public enum GestureCommand: Equatable, Sendable {
    case swipe(SwipeDirection)
    case pose(String)
    case zoomIn, zoomOut
    case paused(Bool)

    /// Key used for action bindings in the config file.
    public var bindingKey: String {
        switch self {
        case .swipe(let d): return "swipe.\(d.rawValue)"
        case .pose(let p): return "pose.\(p)"
        case .zoomIn: return "zoom.in"
        case .zoomOut: return "zoom.out"
        case .paused(let p): return p ? "paused" : "resumed"
        }
    }
}

public enum EngineMode: String, Sendable {
    case noHand, pointing, pressed, dragging, scrolling, zooming, paused
}

public struct HandSnapshot: Sendable {
    public var id: Int
    public var points: [Vec2]
    public var pose: String
    public var isPointer: Bool
    public var inZone: Bool
    public var chirality: Chirality
    public var pinchIndex: Double
}

public struct HUDState: Sendable {
    public var cursor: Vec2?
    public var mode: EngineMode = .noHand
    /// 0 = fingers apart … 1 = pinch registered.
    public var pinchProgress: Double = 0
    public var activeButton: MouseButton = .left
    /// Hand offset from the scroll joystick's neutral point, −1 … 1 per axis.
    public var scrollDeflection: Vec2 = .zero
    /// 1 = hand well inside the camera's view … 0 = at its edge or not currently seen.
    public var trackingQuality: Double = 1
    public init() {}
}

public struct EngineOutput: Sendable {
    public var cursor: Vec2?
    public var events: [PointerEvent] = []
    public var commands: [GestureCommand] = []
    public var hud = HUDState()
    public var hands: [HandSnapshot] = []
    public init() {}
}
