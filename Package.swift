// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Gesture",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Gesture", targets: ["Gesture"]),
        .executable(name: "gesture-lab", targets: ["GestureLab"]),
        .executable(name: "gesture-bench", targets: ["GestureBench"]),
        .library(name: "GestureCore", targets: ["GestureCore"]),
    ],
    targets: [
        // Pure, deterministic gesture logic. No AppKit / AVFoundation / Vision.
        .target(name: "GestureCore"),
        // Menu bar app: capture, Vision inference, event injection, HUD.
        .executableTarget(name: "Gesture", dependencies: ["GestureCore"]),
        // Offline analysis of recorded sessions.
        .executableTarget(name: "GestureLab", dependencies: ["GestureCore"]),
        .executableTarget(name: "GestureBench", dependencies: ["GestureCore"]),
        // Self-test runner (XCTest / swift-testing are unavailable with Command Line Tools only).
        .executableTarget(name: "GestureSelfTest", dependencies: ["GestureCore"]),
    ],
    swiftLanguageModes: [.v5]
)
