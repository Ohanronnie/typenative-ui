# macOS renderer

`src/platform/macos.tn` is the native backend. It calls AppKit and the
Objective-C runtime directly through `extern "C"` declarations and links the
framework target with AppKit, Foundation, CoreGraphics, Objective-C runtime,
and libc++.

## Lifecycle

`NativeRenderer.start` loads AppKit and creates the shared `NSApplication`.
`mount` creates one `NSWindow`, builds the native subtree from the resolved
element records, applies Yoga frames, attaches control targets and text field
delegates, and shows the window. `update` retains that same window pointer and
applies the reconciler's create, insert, move, remove, replace, and update
mutations to the native records. `close` closes the window, `stop` terminates
the application object, and `dispose` releases target objects, Yoga nodes, and
native object references.

The native smoke fixture asserts that a window and native controls mount and
teardown cleanly. The interactive Counter example uses the same renderer and
keeps the AppKit event loop open through `runApp`.

## Ownership rules

Native objects returned from `alloc/init` are owned by the renderer until the
corresponding release. Text fields receive an owned `NSString` value through
`setStringValue:`. Button and text-input target objects are retained by their
native records and released when the tree is rebuilt or the renderer stops.

Yoga nodes are owned by the corresponding native records during a mount. The
renderer removes child nodes before calling `YGNodeFree`, so every node is
released exactly once. The framework keeps only the record-level style
snapshot and resulting frames after layout; it does not retain Yoga nodes after
renderer disposal.

## Event path

AppKit invokes `nativeTargetCallback` on the UI thread. The callback resolves
the mounted identity stored in the target object and routes button presses or
text changes to the reconciler inside a batch. A registered renderer callback
then renders the next tree and commits its mutations on the same UI thread.

`runApp` owns this loop for a standalone application. The smoke test uses
explicit mount, assertions, close, and stop calls so the process remains
deterministic and exits without an interactive event loop.

## Platform boundary

The native backend is intentionally macOS-only. It maps Window and Dialog to
AppKit windows or panels; View, Stack, Grid, SplitView, and Canvas to native
views; Text, Button, TextInput, Image, ScrollView, List, Switch, Slider, and
Progress to their corresponding AppKit controls; and Menu and Toolbar to
their AppKit container objects. It uses AppKit and the Objective-C runtime
directly; there is no Linux renderer, generated C backend, or project-owned
Objective-C bridge. Accessibility helpers are present in the public surface,
and the headless backend exposes role, label-length, focus, and event
operations for deterministic verification.
