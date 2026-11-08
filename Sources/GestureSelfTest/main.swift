import Foundation

// Self-test runner (XCTest / swift-testing are unavailable with Command Line Tools only).
// Each area's tests live in <Area>Tests.swift; the harness is in Harness.swift.

print("GestureCore self-test\n")
filterTests()
poseTests()
clickTests()
scrollTests()
commandTests()
robustnessTests()
configTests()

print("\n\(passes) checks passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
