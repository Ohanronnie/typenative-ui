# TypeNative UI

TypeNative UI is a native, JSX-shaped UI framework written in TypeNative. It
keeps the framework runtime in TypeNative, uses persistent element records,
reconciles keyed trees deterministically, and provides both a headless backend
and a direct AppKit backend for macOS.

The public entrypoint is [`src/index.tn`](src/index.tn). The implementation is
split into the JSX runtime, hooks, reconciler, scheduler, Yoga layout adapter,
accessibility helpers, animation helpers, and platform renderers. The canonical
JSX runtime exports `jsx`, `jsxs`, and `fragment`; the compiler selects it from
`typenative.json`.
Layout-specific types and the Yoga adapter are also available directly from
`src/layout/layout.tn` and `src/layout/yoga.tn`.

## Build the macOS example

The repository targets Apple arm64 and uses the pinned TypeNative compiler
revision `3ef10d4579e1c0765ad56fe787db37b9bdcb4c1a`.

```sh
git clone https://github.com/Ohanronnie/typenative-ui.git
cd typenative-ui
cargo build --release -p tn-cli --manifest-path /path/to/typenative/Cargo.toml
PATH="/opt/homebrew/bin:$PATH" sh scripts/check-yoga.sh
/path/to/typenative/target/release/tn build typenative.json \
  --profile optimized --emit executable --out build/typenative-counter
build/typenative-counter
```

The root project builds the macOS Counter example. It exercises functional
components, JSX children, state, button input, Yoga, and a real AppKit window.
The deterministic renderer smoke test covers the same native records without
entering the AppKit event loop.

## A small component

TypeNative state hooks return a typed `(value, setter)` pair. Effects use a
`u64` dependency token because TypeNative does not use JavaScript dependency
arrays.

```tnx
import { Button, Element, Text, View, Window, runApp, useState } from "./src/index";
import { String } from "std/string";

struct CounterProps {}

function Counter(props: CounterProps): Element {
  const [current, setCount] = useState<i32>(0i32);
  const increment = move(): void => {
    setCount(current + 1i32);
  };
  let label: &str = "Count: 0";
  if (current !== 0i32) {
    label = "Count: 1";
  }
  return <View>
    <Text>{String(label)}</Text>
    <Button onPress={increment}>Increment</Button>
  </View>;
}

function main(): i32 {
  return runApp(move(): Element => <Counter />);
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
