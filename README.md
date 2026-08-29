# TypeNative UI

TypeNative UI is a native, JSX-shaped UI framework written in TypeNative. It
keeps the framework runtime in TypeNative, uses persistent element records,
reconciles keyed trees deterministically, and provides both a headless backend
and a direct AppKit backend for macOS.

The public entrypoint is [`src/index.tn`](src/index.tn). The implementation is
split into the JSX runtime, hooks, reconciler, scheduler, Yoga layout adapter,
accessibility helpers, animation helpers, and platform renderers.
Layout-specific types and the Yoga adapter are also available directly from
`src/layout/layout.tn` and `src/layout/yoga.tn`.

## Build the Workbench

The repository targets Apple arm64 and uses the pinned TypeNative compiler
revision `3ef10d4579e1c0765ad56fe787db37b9bdcb4c1a`.

```sh
git clone https://github.com/Ohanronnie/typenative-ui.git
cd typenative-ui
cargo build --release -p tn-cli --manifest-path /path/to/typenative/Cargo.toml
PATH="/opt/homebrew/bin:$PATH" sh scripts/check-yoga.sh
/path/to/typenative/target/release/tn build typenative.json \
  --profile optimized --emit executable --out build/workbench
build/workbench
```

The Workbench exercises functional components, JSX children, keyed moves,
state, reducer state, context, refs, IDs, memoization, callbacks, layout and
passive effects, batched button input, the UI scheduler, headless mutation
recording, Yoga, and a real AppKit window.

## A small component

TypeNative state handles are explicit values with `current`, `set`, and
`update` operations. Effects use a `u64` dependency token because TypeNative
does not use JavaScript dependency arrays.

```tn
import { Button, Text, View, Window, useState, runApp, Element } from "./src/index";
import { String } from "std/string";

struct CounterProps {}

function Counter(props: CounterProps): Element {
  const count = useState<i32>(0i32);
  const increment = move(): void => {
    count.update(move(value: i32): i32 => value + 1i32);
  };
  let label: &str = "Count: 0";
  if (count.current() !== 0i32) {
    label = "Count: 1";
  }
  return <View>
    <Text>{String(label)}</Text>
    <Button onPress={increment}>Increment</Button>
  </View>;
}

function main(): i32 {
  return runApp(<Window title="Counter"><Counter /></Window>);
}
```

For deterministic tests, mount the same tree in `HeadlessRenderer`, dispatch an
event, render the next tree, and inspect the recorded mutations.

## Verification

The complete local verification matrix is reproducible with:

```sh
TYPE_NATIVE_COMPILER_ROOT=/path/to/typenative \
  scripts/run-tests.sh /path/to/typenative/target/release/tn
```

It checks formatting and linting, verifies the frozen compiler boundary,
rebuilds Yoga from [`deps/yoga.lock.json`](deps/yoga.lock.json), runs the
headless and native fixtures in debug and optimized builds, and records
AddressSanitizer, UndefinedBehaviorSanitizer, and ThreadSanitizer results.
The benchmark report is written to `build/verification/benchmark-results.json`.

See [`docs/architecture.md`](docs/architecture.md),
[`docs/native.md`](docs/native.md), and [`docs/testing.md`](docs/testing.md)
for the ownership model, renderer contract, compiler boundary, and measured
verification details.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
