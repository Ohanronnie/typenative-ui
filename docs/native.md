# macOS renderer

`src/platform/macos.tn` is the native backend. It calls AppKit and the
Objective-C runtime directly through `extern "C"` declarations and links the
framework target with AppKit, Foundation, CoreGraphics, Objective-C runtime,
and libc++.

## Lifecycle

`NativeRenderer.start` loads AppKit and creates the shared `NSApplication`.
`mount` creates one `NSWindow`, builds the native subtree from the resolved
element records, applies Yoga frames, attaches button action targets, and
shows the window. `update` retains that same window pointer while rebuilding
the native subtree from the new tree. `closeWindow` closes the window,
`stop` terminates the application object, and `dispose` releases target objects
and native object references.

The Workbench asserts that the window remains the same across an update and
that a simulated native button press changes the next rendered tree.

## Ownership rules

Native objects returned from `alloc/init` are owned by the renderer until the
corresponding release. Text fields receive an owned `NSString` value through
`setStringValue:`. Button target objects are retained in explicit slots and
released when the tree is rebuilt or the renderer stops.

Yoga owns the native layout nodes during a mount. Teardown uses
`YGNodeFreeRecursive` so every child and sibling is released exactly once.
The framework keeps only the record-level style snapshot and the resulting
frames; it does not retain Yoga nodes after renderer disposal.

## Event path

AppKit invokes `nativeButtonCallback` on the UI thread. The callback resolves
the action slot stored on the button record and runs it inside `batch`, so
multiple state changes from one press produce one pending-update notification.
The host can then render the next tree and call `update`.

`runApp` owns this loop for a standalone application. Tests and the Workbench
use explicit start, mount, event, render, update, close, and stop calls so the
process remains deterministic and exits without an interactive event loop.

## Limitations that are part of the contract

The native backend currently supports Window, View, Text, and Button records.
The reconciler records minimal mutations, while native update commitment
rebuilds the native subtree. Accessibility helpers are present in the public
surface and the headless backend exposes role, label-length, focus, and press
operations for deterministic verification.
