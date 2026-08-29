# Architecture

TypeNative UI is a small, explicit runtime whose data model is designed for a
language with move semantics and native ownership. There is no JavaScript
object model behind the public API.

## Runtime layers

| Layer                          | Responsibility                                                                                        |
| ------------------------------ | ----------------------------------------------------------------------------------------------------- |
| `src/jsx-runtime.tn`           | Element records, JSX construction, component slots, host children, text, styles, refs, and disposal   |
| `src/components.tn`            | Typed `View`, `Text`, `Button`, and `Window` constructors plus direct tree helpers                    |
| `src/hooks/hooks.tn`           | State, reducers, effects, memoization, callbacks, refs, context, IDs, batching, and hook-shape checks |
| `src/reconciler/reconciler.tn` | Component resolution, keyed child matching, mutation recording, and root ownership                    |
| `src/renderer/headless.tn`     | Deterministic renderer for tests, accessibility queries, focus, and input dispatch                    |
| `src/layout/layout.tn`         | Yoga node ownership, style application, measurement, and frames                                       |
| `src/platform/macos.tn`        | Direct Objective-C/AppKit calls, native object ownership, Yoga frames, and button targets             |
| `src/scheduler/scheduler.tn`   | Owner-thread priority queue and cross-thread bounded UI handoff                                       |

## Element ownership

An `Element` is a small handle around an owned `ElementRecord`. A record owns
its text storage, style snapshot, child links, render/action slots, and any
host reference binding. `takeRawForRuntime` transfers the record pointer to a
renderer or reconciler; `dispose` recursively releases the record and its
children.

The record stores a stable `typeId`, a hashed key, and a source identity. JSX
component identity is derived from the callable's code pointer, while
unkeyed siblings receive a slot-specific source identity. A keyed component
therefore keeps its hook slots when it moves, and a same-key component with a
different callable is replaced rather than merged.

Styles are copied into `StyleSnapshot` records. A later mutation of the caller's
`Style` object cannot change an already-created element. The snapshot revision
is part of the reconciliation update test.

## Reconciliation

`renderTree` resolves functional components recursively. Each component enters
the hook store with its `(source, key)` identity and a zero-based hook cursor.
`finishHookPass` removes slots that were not seen and validates both hook count
and hook kind stability.

`Reconciler` retains the resolved root. On update it compares node kind, type,
key, text hash/length, and style revision. Keyed children are indexed with an
open-addressed table; the diff emits `create`, `insert`, `move`, `update`,
`remove`, and `replace` records. The headless backend exposes these records so
tests can assert that an unchanged tree emits zero work and that a reversal
emits moves rather than replacements.

The mutation recorder is independent from native host commitment. The current
AppKit renderer uses the same resolved ownership model but rebuilds the native
subtree for an update while retaining the `NSWindow` identity. This deliberate
boundary keeps the deterministic reconciler testable and the native ownership
rules auditable.

## Hooks and events

Hooks are process-lifetime storage keyed by component source, key, hook index,
and hook kind. `useState` and reducers expose a pointer-backed state handle;
state changes mark an update pending. `batch` coalesces multiple changes into a
single update notification. `useLayoutEffect` flushes before passive effects,
and replacement/unmount runs the prior cleanup before releasing the slot.

`Context<T>` is created once and passed to a component as `&Context<T>`. Calling
`provide` changes the context value and marks an update. `ElementRef` is a
non-owning host record reference; use `bindElementRef(element, &reference)` to
bind it, and the record detaches it during disposal.

## Scheduler and threading

`Scheduler` is owner-thread-only and orders work by priority and insertion
sequence. `UiScheduler` captures its creating thread, accepts owned jobs into
bounded non-blocking channels, and permits draining and disposal only on that
thread. A rejected post returns the owned job to the caller, so a full queue
cannot leak its callback environment.

The UI scheduler is a handoff primitive: producers may enqueue work, while the
UI thread decides when to drain it. UI objects and element handles must remain
on the UI thread.

## External boundaries

Yoga is fetched from the official React Yoga archive and verified against its
tag, commit, and SHA-256 digest before CMake builds `libyogacore.a`. Its source
is never copied into this repository. AppKit is called directly through
TypeNative `extern` declarations; there is no generated C, C++, or Objective-C
bridge in this repository.

The framework is pinned to a public compiler commit so CI can reproduce the
same lowering behavior. `scripts/verify-compiler-boundary.sh` also checks that
the compiler's frozen self-hosting paths are byte-for-byte unchanged and that
the protected compiler benchmark result remains untouched.
