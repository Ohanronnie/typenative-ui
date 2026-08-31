# Testing and benchmarks

The repository keeps executable TypeNative fixtures beside the source they
exercise. Every fixture is built with a small `typenative.json` file so the
entry path, target, JSX runtime, and external libraries are explicit.

## Fixture coverage

| Fixture                          | Contract                                                                  |
| -------------------------------- | ------------------------------------------------------------------------- |
| `testing/typenative.json`        | JSX ownership and component resolution                                    |
| `testing/button/typenative.json` | JSX button children and action dispatch                                   |
| `testing/headless-events`        | Headless mount, accessibility, focus, input, update, and unmount          |
| `testing/hooks-integration`      | State, reducer, context, ref, ID, memo, callback, effects, and batching   |
| `testing/hook-order`             | Structured diagnostics for changing hook order                          |
| `testing/component-identity`     | Callable identity, keyed state retention, replacement, and key reset      |
| `testing/refs`                   | Host reference attach/current/detach lifecycle                            |
| `testing/lifecycle`              | Deep disposal, repeated mount/unmount, and effect cleanup                 |
| `testing/reconciler`             | Keyed reverse moves, unchanged trees, text updates, and replacement       |
| `testing/layout`                 | Yoga row direction, padding, gap, and computed frames                     |
| `testing/style`                  | Style fields, edge insets, revisions, and snapshots                       |
| `testing/scheduler`              | Priority order, cancellation, owner-thread drain, dynamic UI posts, and wakeups |
| `testing/async`                  | Task-group completion, cancellation, and cleanup                          |
| `testing/multi`                  | Multiple JSX component children and fragment flattening                   |
| `testing/public-api`             | Public entrypoint aliases and renderer/scheduler factories                |
| `testing/native-renderer`        | macOS AppKit mount, state update, button/input events, refs, and teardown |

## Verification command

```sh
TYPE_NATIVE_COMPILER_ROOT=/path/to/typenative \
  scripts/run-tests.sh /path/to/typenative/target/release/tn
```

The script performs these stages:

1. TypeNative formatting, checking, linting, and compiler-boundary validation.
2. Yoga archive verification and external CMake build.
3. AddressSanitizer debug runs for every fixture and the deterministic macOS native renderer smoke test.
4. Optimized runs for every fixture and the deterministic macOS native renderer smoke test.
5. UndefinedBehaviorSanitizer and ThreadSanitizer runs for the scheduler and
   headless paths.
6. The 10,000-key reconciler benchmark with mutation-count gates, allocation
   count, wall time, and maximum resident memory.

Hook storage is owned by a renderer's `HookRoot` and is cleared on unmount.
Hook and AppKit runs therefore use AddressSanitizer's invalid-access checks;
the non-hook ownership fixtures also run leak detection where the platform has
no AppKit-owned process caches.

## Reconciler benchmark

`benchmarks/reconciler-10k.tn` creates 10,000 keyed text children and checks:

- 10,001 nodes after mount, including the fragment root;
- zero mutations for an identical update;
- 10,000 move mutations for a full reversal;
- one text update after changing one keyed child; and
- zero mutations for repeating that changed tree.

The executable prints `allocations=<count>` after unmount. The verification
script combines that counter with the measured wall time and macOS maximum
resident set size in `build/verification/benchmark-results.json`. The checked
in `benchmarks/results.json` records the latest local run and its compiler
revision.

## Compiler boundary

The framework starts from compiler commit
`a1e7324f6df9316d64dec3826d556864f4d49688` and pins the published compiler
revision `3ef10d4579e1c0765ad56fe787db37b9bdcb4c1a`. The latter contains the
small compiler/runtime fixes required by the framework: function-valued field
lowering, explicit float-width casts, safe global callable loads, and
non-blocking channel operations. The framework never changes
`compiler-tn/**` or `scripts/bootstrap-self-host.sh`.
