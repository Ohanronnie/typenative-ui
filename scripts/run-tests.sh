#!/bin/sh
set -eu

compiler_input=${1:?path to the TypeNative compiler is required}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

case "$compiler_input" in
  */*)
    compiler_dir=$(CDPATH= cd -- "$(dirname -- "$compiler_input")" && pwd)
    compiler="$compiler_dir/$(basename -- "$compiler_input")"
    ;;
  *)
    compiler=$(command -v "$compiler_input")
    ;;
esac

test -x "$compiler"
verification="$root/build/verification"
bin_dir="$verification/bin"
timings="$verification/timings.log"
mkdir -p "$bin_dir"
: > "$timings"

run_timed() {
  label=$1
  shift
  output="$verification/$label.log"
  if /usr/bin/time -p "$@" > "$output" 2>&1; then
    result=0
  else
    result=$?
  fi
  printf '== %s ==\n' "$label"
  cat "$output"
  printf '== %s ==\n' "$label" >> "$timings"
  cat "$output" >> "$timings"
  if [ "$result" -ne 0 ]; then
    return "$result"
  fi
}

build_and_run() {
  name=$1
  config=$2
  profile=$3
  sanitizer=$4
  binary="$bin_dir/$name-$profile-$sanitizer"

  if [ "$sanitizer" = "none" ]; then
    run_timed "build-$name-$profile" \
      "$compiler" build "$config" --profile "$profile" --emit executable --out "$binary"
  else
    run_timed "build-$name-$profile-$sanitizer" \
      "$compiler" build "$config" --profile "$profile" --emit executable \
      --sanitize "$sanitizer" --out "$binary"
  fi

  case "$sanitizer" in
    address)
      run_timed "run-$name-$profile-address" \
        env ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 "$binary"
      ;;
    undefined)
      run_timed "run-$name-$profile-undefined" \
        env UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 "$binary"
      ;;
    thread)
      run_timed "run-$name-$profile-thread" \
        env TSAN_OPTIONS=halt_on_error=1 "$binary"
      ;;
    none)
      run_timed "run-$name-$profile" "$binary"
      ;;
    *)
      printf 'unknown sanitizer: %s\n' "$sanitizer" >&2
      return 2
      ;;
  esac
}

cd "$root"
run_timed format "$compiler" fmt --check src examples testing benchmarks
run_timed check "$compiler" check typenative.json --timings
run_timed lint "$compiler" lint . --json
run_timed yoga sh scripts/check-yoga.sh
run_timed compiler-boundary sh scripts/verify-compiler-boundary.sh "${TYPE_NATIVE_COMPILER_ROOT:-.compiler}"

build_and_run root testing/typenative.json debug address
build_and_run button testing/button/typenative.json debug address
build_and_run headless-events testing/headless-events/typenative.json debug address
build_and_run hooks-integration testing/hooks-integration/typenative.json debug address
build_and_run refs testing/refs/typenative.json debug address
build_and_run component-identity testing/component-identity/typenative.json debug address
build_and_run lifecycle testing/lifecycle/typenative.json debug address
build_and_run scheduler testing/scheduler/typenative.json debug address
build_and_run style testing/style/typenative.json debug address
build_and_run layout testing/layout/typenative.json debug address
build_and_run reconciler testing/reconciler/typenative.json debug address
build_and_run multi testing/multi/typenative.json debug address
build_and_run async testing/async/typenative.json debug address
build_and_run public-api testing/public-api/typenative.json debug address
build_and_run workbench typenative.json debug address

build_and_run root testing/typenative.json optimized none
build_and_run button testing/button/typenative.json optimized none
build_and_run headless-events testing/headless-events/typenative.json optimized none
build_and_run hooks-integration testing/hooks-integration/typenative.json optimized none
build_and_run refs testing/refs/typenative.json optimized none
build_and_run component-identity testing/component-identity/typenative.json optimized none
build_and_run lifecycle testing/lifecycle/typenative.json optimized none
build_and_run scheduler testing/scheduler/typenative.json optimized none
build_and_run style testing/style/typenative.json optimized none
build_and_run layout testing/layout/typenative.json optimized none
build_and_run reconciler testing/reconciler/typenative.json optimized none
build_and_run multi testing/multi/typenative.json optimized none
build_and_run async testing/async/typenative.json optimized none
build_and_run public-api testing/public-api/typenative.json optimized none
build_and_run benchmark benchmarks/typenative.json optimized address
build_and_run workbench typenative.json optimized none

build_and_run headless-undefined testing/headless-events/typenative.json debug undefined
build_and_run scheduler-undefined testing/scheduler/typenative.json debug undefined
build_and_run scheduler-thread testing/scheduler/typenative.json debug thread

benchmark_binary="$bin_dir/benchmark-optimized-address"
benchmark_output="$verification/benchmark-peak-output.log"
benchmark_peak="$verification/benchmark-peak-time.log"
if /usr/bin/time -l env ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 \
  "$benchmark_binary" > "$benchmark_output" 2> "$benchmark_peak"; then
  benchmark_result=0
else
  benchmark_result=$?
fi
cat "$benchmark_output"
cat "$benchmark_peak"
cat "$benchmark_output" >> "$timings"
cat "$benchmark_peak" >> "$timings"
if [ "$benchmark_result" -ne 0 ]; then
  exit "$benchmark_result"
fi

allocations=$(sed -n 's/^allocations=//p' "$benchmark_output" | tail -n 1)
wall_seconds=$(awk '/ real / { print $1 }' "$benchmark_peak" | tail -n 1)
peak_bytes=$(awk '/maximum resident set size/ { print $1 }' "$benchmark_peak" | tail -n 1)
test -n "$allocations"
test -n "$wall_seconds"
test -n "$peak_bytes"
compiler_commit=$(git -C "${TYPE_NATIVE_COMPILER_ROOT:-.compiler}" rev-parse HEAD 2>/dev/null || printf 'local')
cat > "$verification/benchmark-results.json" <<EOF
{
  "compilerCommit": "$compiler_commit",
  "fixture": "benchmarks/reconciler-10k.tn",
  "profile": "optimized",
  "sanitizer": "address",
  "allocationCount": $allocations,
  "wallSeconds": $wall_seconds,
  "maximumResidentBytes": $peak_bytes,
  "nodeCount": 10001,
  "mutationGates": {
    "mount": 10001,
    "unchanged": 0,
    "reverse": 10000,
    "singleTextUpdate": 1,
    "repeatChanged": 0
  }
}
EOF

printf 'verification=pass\nbenchmark-results=%s\n' "$verification/benchmark-results.json"
