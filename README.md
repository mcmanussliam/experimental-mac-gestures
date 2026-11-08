# Experimental Mac Gestures

Control your Mac with your hands through the built-in camera: point, pinch to click, pinch and move
to drag, raise two fingers to scroll, and swipe between Spaces. Native Swift with no dependencies,
using Apple Vision for hand tracking. Video never leaves your Mac.

This is an experiment. Expect rough edges.

## Gestures

| Gesture | Does |
|---|---|
| Move an open or pointing hand | Move the pointer |
| Tap thumb and index together | Click (twice to double-click) |
| Pinch and move | Drag |
| Tap thumb and middle together | Right click |
| Raise index and middle fingers, move off-centre | Scroll (further is faster) |
| Quick open-palm swipe | Switch Space, Mission Control |
| Pinch with both hands, spread or squeeze | Zoom |
| Hold a fist, or ⌃⌥⌘G | Pause / resume |

## Run it

Requires macOS 14 or later and the Xcode Command Line Tools.

```sh
make run      # build Gesture.app and open it
make check    # tests and benchmarks
```

Gesture asks for Camera and Accessibility access on first launch. To keep those permissions across
rebuilds, run `./scripts/make-signing-identity.sh` once to create a local signing certificate.
