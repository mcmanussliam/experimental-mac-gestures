import os

/// Unified logging (view with Console.app, or `log stream --predicate 'subsystem == "local.gesture.app"'`).
enum Log {
    static let app = Logger(subsystem: "local.gesture.app", category: "app")
    static let camera = Logger(subsystem: "local.gesture.app", category: "camera")
}
