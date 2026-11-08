import Foundation

public enum CursorMode: String, Codable, Sendable { case absolute, relative }
public enum HandPreference: String, Codable, Sendable { case auto, left, right }

/// Every tunable in the recognition pipeline. Times are in seconds. Distances in "palms" are
/// normalised by the hand's palm scale, so they don't depend on how far the hand is from the
/// camera; "camera heights" are fractions of the frame height.
public struct EngineConfig: Codable, Equatable, Sendable {
    /// 1€ smoothing of the landmarks used for features and poses (camera heights).
    public var landmarkMinCutoff = 3.0
    public var landmarkBeta = 4.0

    public var cursorMode: CursorMode = .absolute
    /// 1€ smoothing of the pointer. Higher beta follows fast motion with less lag but more jerk.
    public var cursorMinCutoff = 0.9
    public var cursorBeta = 9.0
    /// Absolute mode: width of the camera region (fraction of frame width) that maps to the
    /// whole screen. Height is derived from camera/screen aspect so motion is isotropic.
    public var activeRegionWidth = 0.5
    /// Centre of that region in user-view camera coordinates.
    public var activeRegionCenterX = 0.5
    public var activeRegionCenterY = 0.55
    /// Relative mode: screen-heights of travel per camera-height of hand travel, slow → fast.
    public var relativeGainMin = 0.9
    public var relativeGainMax = 4.0
    /// Hand speed (camera-heights/s) at which relative gain saturates.
    public var relativeGainSpeed = 0.6
    /// Relative mode measures motion against the hand's own size, scaled to this palm (camera
    /// heights), so the pointer moves the same whether the hand is near or far. Recorded palms
    /// span 0.22–0.6 within one session; 0.3 is their median.
    public var relativeReferencePalm = 0.3

    /// Thumb-tip to finger-tip distance (palms) below which a pinch clicks.
    public var pinchEnter = 0.30
    /// Wide hysteresis: held pinches drift open slowly (recorded p95 0.45 while pressed), so a
    /// slow opening must pass `pinchExit` to release…
    public var pinchExit = 0.50
    /// …while a fast, deliberate opening (quick re-taps open only to ~0.5) releases sooner.
    public var pinchFastExit = 0.40
    /// Opening speed (palms/s) that counts as deliberate. Recorded drift is ~0.2 palms/s,
    /// releases 2+ palms/s.
    public var pinchReleaseSpeed = 1.0
    /// As the thumb–finger gap closes from here to `pinchEnter`, the pointer is progressively
    /// damped (quadratically), so the click lands where you aimed (Heisenberg effect).
    public var pinchDampStart = 0.42
    /// Closing speed (palms/s) that counts as a pinch approach and starts damping. Slow drift
    /// of a relaxed hand must not make the pointer sticky.
    public var pinchApproachSpeed = 1.2
    /// How long a pinch must be seen before it clicks, and how long the fingers must be open
    /// before the next one can.
    public var pinchConfirmTime = 0.025
    public var pinchRearmTime = 0.035
    /// Freeze only a short closing motion, never an indefinitely half-closed hand.
    public var pinchIntentTime = 0.14
    /// Continuous reliable opening that ends a pinch.
    public var pinchReleaseTime = 0.04
    /// The pinching finger's tip must be at least this far from the wrist (palms);
    /// rejects fists where the thumb rests on curled fingers.
    public var pinchMinReach = 0.95
    /// Finger reach shrinking faster than this (palms/s) = curling into a fist, not pinching.
    public var pinchMaxCurlSpeed = 2.5
    /// Thumb–middle must beat thumb–index by this factor for a right click.
    public var rightClickMargin = 0.75
    public var enableRightClick = true
    /// Hand travel while pinched (palms), held for `dragConfirmTime`, that turns a click into a drag.
    public var dragStartPalms = 0.15
    public var dragConfirmTime = 0.035
    /// Relative dragging uses predictable constant gain rather than pointer acceleration.
    public var dragGain = 1.6
    /// The pointer stays still this long after a click, unless the hand moves more than
    /// `postClickMovePalms`, so a double-click lands on the same spot.
    public var postClickHold = 0.06
    public var postClickMovePalms = 0.08
    /// Second click within this time and distance (points) counts as a double-click.
    public var doubleClickInterval = 0.45
    public var doubleClickRadius = 10.0
    /// Time constant for blending back to the live position after a freeze.
    public var catchUpTau = 0.10

    /// How long the two-finger pose must be seen before scrolling starts.
    public var scrollEnterTime = 0.08
    /// A decisive different pose (open, point, fist) must last this long to end a scroll.
    public var scrollExitTime = 0.15
    /// An ambiguous reading keeps the scroll going (it is usually one wobbling finger), but
    /// not indefinitely.
    public var scrollAmbiguousTimeout = 0.6
    /// Ring/little fingers may be comfortably bent rather than tightly curled for scrolling.
    public var scrollFingerCurledBelow = 0.55
    /// Joystick: hand offset from where the pose formed, in palms. Inside the dead zone nothing
    /// scrolls; speed rises along `scrollCurve` to `scrollMaxSpeed` (points/s) at full deflection.
    /// The dead zone covers the hand's tremor while holding the pose (recorded p90 0.065 palms).
    public var scrollDeadzone = 0.08
    public var scrollFullDeflection = 1.0
    public var scrollCurve = 1.5
    public var scrollMaxSpeed = 2600.0
    /// Time constants for speeding up and for coasting to a stop, in seconds.
    public var scrollResponseTime = 0.08
    public var scrollStopTime = 0.12
    public var invertScroll = false

    /// Open-palm swipe: at least `swipeMinDistance` palms within `swipeWindow`, peaking above
    /// `swipeMinSpeed` palms/s, mostly along one axis.
    public var swipeWindow = 0.30
    public var swipeMinDistance = 2.2
    public var swipeMinSpeed = 7.0
    public var swipeAxisRatio = 1.8
    public var swipeMinOpenFraction = 0.6
    public var swipeCooldown = 0.45
    /// The return stroke after a swipe is ignored for this long.
    public var swipeOppositeSuppress = 0.9

    /// Finger extension score (0 curled … 1 straight) above which a finger reads as extended,
    /// below which it reads as curled; in between it is ambiguous. Hysteresis keeps a decisive
    /// reading until the score moves this far back past its threshold.
    public var fingerExtendedAbove = 0.70
    public var fingerCurledBelow = 0.35
    public var fingerHysteresis = 0.08
    /// A pose must be seen continuously this long before it is "committed".
    public var poseCommitTime = 0.08
    /// Committed custom pose held this long → its command fires.
    public var poseHoldTime = 0.45
    /// Max per-joint distance (palms) for a custom pose match.
    public var customPoseThreshold = 0.5

    /// Change in the distance between two pinching hands that makes one zoom step.
    public var zoomStep = 1.15

    /// Hands whose palm centre is below this (user-view y, 0 = top) are ignored (keyboard zone).
    public var activeZoneBottom = 0.92
    /// A fist held this long pauses or resumes.
    public var pauseHoldTime = 1.0
    public var pointerHand: HandPreference = .auto
    /// A hand unseen for this long is dropped, releasing anything it held.
    public var handLostTimeout = 0.25

    /// Max distance (camera heights) between a hand's predicted and detected knuckle centre
    /// for the detection to continue the track. Real pointing moves ~0.03 per frame at 30 fps.
    public var trackingGate = 0.1
    /// Frames a gate-failing detection is treated as a detector outlier before the track is
    /// re-acquired at the new position.
    public var trackingOutlierFrames = 2
    /// A new detection must persist before it may move the pointer or trigger actions.
    public var handAcquireTime = 0.10

    public init() {}
}
