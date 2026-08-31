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

real_seconds() {
  real_label=$1
  awk '$1 == "real" { print $2 }' "$verification/$real_label.log" | tail -n 1
}

assert_less() {
  less_label=$1
  less_value=$2
  less_limit=$3
  awk -v label="$less_label" -v value="$less_value" -v limit="$less_limit" '
    BEGIN {
      if (value == "" || (value + 0) >= (limit + 0)) {
        printf "%s=%s exceeds %s\n", label, value, limit > "/dev/stderr"
        exit 1
      }
    }
  '
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
      if [ "$name" = "native-renderer" ] || [ "$name" = "native-components" ] || [ "$name" = "native-window" ]; then
        run_timed "run-$name-$profile-address" \
          env ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
          LSAN_OPTIONS=suppressions="$root/scripts/macos-framework.lsan.supp" "$binary"
      else
        run_timed "run-$name-$profile-address" \
          env ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 "$binary"
      fi
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

run_timed check-cache-cold "$compiler" check testing/renderer-smoke/typenative.json --timings
run_timed check-cache-warm "$compiler" check testing/renderer-smoke/typenative.json --timings
cached_check_seconds=$(real_seconds check-cache-warm)
test -n "$cached_check_seconds"
assert_less cached-check-seconds "$cached_check_seconds" 1.0

performance_binary="$bin_dir/performance-debug"
run_timed build-performance-debug-initial "$compiler" build testing/renderer-smoke/typenative.json \
  --profile debug --emit executable --out "$performance_binary" --timings
run_timed build-performance-debug-incremental "$compiler" build testing/renderer-smoke/typenative.json \
  --profile debug --emit executable --out "$performance_binary" --timings
initial_build_seconds=$(real_seconds build-performance-debug-initial)
incremental_build_seconds=$(real_seconds build-performance-debug-incremental)
test -n "$initial_build_seconds"
test -n "$incremental_build_seconds"
assert_less compiler-invocation-seconds "$initial_build_seconds" 180.0
assert_less incremental-debug-build-seconds "$incremental_build_seconds" 2.0

performance_samples="$verification/performance-samples.tsv"
: > "$performance_samples"
record_performance_sample() {
  sample_kind=$1
  sample_label=$2
  sample_seconds=$(real_seconds "$sample_label")
  test -n "$sample_seconds"
  printf '%s\t%s\n' "$sample_kind" "$sample_seconds" >> "$performance_samples"
}
for sample in 3 8 1 6 9 2 7 4 5; do
  case "$sample" in
    1|4|7)
      run_timed "performance-build-$sample" "$compiler" build testing/renderer-smoke/typenative.json \
        --profile debug --emit executable --out "$performance_binary" --timings
      record_performance_sample build "performance-build-$sample"
      run_timed "performance-check-$sample" "$compiler" check testing/renderer-smoke/typenative.json --timings
      record_performance_sample check "performance-check-$sample"
      ;;
    *)
      run_timed "performance-check-$sample" "$compiler" check testing/renderer-smoke/typenative.json --timings
      record_performance_sample check "performance-check-$sample"
      run_timed "performance-build-$sample" "$compiler" build testing/renderer-smoke/typenative.json \
        --profile debug --emit executable --out "$performance_binary" --timings
      record_performance_sample build "performance-build-$sample"
      ;;
  esac
done

check_values="$verification/performance-check-values.txt"
build_values="$verification/performance-build-values.txt"
awk -F '\t' '$1 == "check" { print $2 }' "$performance_samples" | sort -n > "$check_values"
awk -F '\t' '$1 == "build" { print $2 }' "$performance_samples" | sort -n > "$build_values"

summarize_samples() {
  stats_file=$1
  awk '
    {
      values[NR] = $1
      sum += $1
      sumSquares += $1 * $1
    }
    END {
      count = NR
      if (count == 0) {
        exit 1
      }
      if (count % 2 == 1) {
        median = values[(count + 1) / 2]
      } else {
        median = (values[count / 2] + values[count / 2 + 1]) / 2
      }
      p95Index = int((count * 95 + 99) / 100)
      if (p95Index < 1) {
        p95Index = 1
      }
      mean = sum / count
      variance = (sumSquares / count) - (mean * mean)
      if (variance < 0) {
        variance = 0
      }
      standardDeviation = sqrt(variance)
      confidence95 = 1.96 * standardDeviation / sqrt(count)
      printf "%d\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\n", count, median, values[p95Index], mean, standardDeviation, confidence95
    }
  ' "$stats_file"
}

check_stats=$(summarize_samples "$check_values")
build_stats=$(summarize_samples "$build_values")
stat_field() {
  stat_line=$1
  stat_number=$2
  printf '%s\n' "$stat_line" | awk -F '\t' -v field="$stat_number" '{ print $field }'
}
check_count=$(stat_field "$check_stats" 1)
check_median=$(stat_field "$check_stats" 2)
check_p95=$(stat_field "$check_stats" 3)
check_mean=$(stat_field "$check_stats" 4)
check_stddev=$(stat_field "$check_stats" 5)
check_ci95=$(stat_field "$check_stats" 6)
build_count=$(stat_field "$build_stats" 1)
build_median=$(stat_field "$build_stats" 2)
build_p95=$(stat_field "$build_stats" 3)
build_mean=$(stat_field "$build_stats" 4)
build_stddev=$(stat_field "$build_stats" 5)
build_ci95=$(stat_field "$build_stats" 6)
assert_less cached-check-p95-seconds "$check_p95" 1.0
assert_less incremental-debug-build-p95-seconds "$build_p95" 2.0

build_and_run root testing/typenative.json debug address
build_and_run renderer-smoke testing/renderer-smoke/typenative.json debug address
build_and_run button testing/button/typenative.json debug address
build_and_run headless-events testing/headless-events/typenative.json debug address
build_and_run hooks-integration testing/hooks-integration/typenative.json debug address
build_and_run hook-order testing/hook-order/typenative.json debug address
build_and_run refs testing/refs/typenative.json debug address
build_and_run memory testing/memory/typenative.json debug address
build_and_run component-identity testing/component-identity/typenative.json debug address
build_and_run lifecycle testing/lifecycle/typenative.json debug address
build_and_run scheduler testing/scheduler/typenative.json debug address
build_and_run animation testing/animation/typenative.json debug address
build_and_run frame-budget testing/frame-budget/typenative.json debug address
build_and_run accessibility testing/accessibility/typenative.json debug address
build_and_run style testing/style/typenative.json debug address
build_and_run layout testing/layout/typenative.json debug address
build_and_run reconciler testing/reconciler/typenative.json debug address
build_and_run multi testing/multi/typenative.json debug address
build_and_run async testing/async/typenative.json debug address
build_and_run public-api testing/public-api/typenative.json debug address
build_and_run list testing/list/typenative.json debug address
build_and_run native-renderer testing/native-renderer/typenative.json debug address
build_and_run native-components testing/native-components/typenative.json debug address
build_and_run native-window testing/native-window/typenative.json debug address

build_and_run root testing/typenative.json optimized none
build_and_run renderer-smoke testing/renderer-smoke/typenative.json optimized none
build_and_run button testing/button/typenative.json optimized none
build_and_run headless-events testing/headless-events/typenative.json optimized none
build_and_run hooks-integration testing/hooks-integration/typenative.json optimized none
build_and_run hook-order testing/hook-order/typenative.json optimized none
build_and_run refs testing/refs/typenative.json optimized none
build_and_run memory testing/memory/typenative.json optimized none
build_and_run component-identity testing/component-identity/typenative.json optimized none
build_and_run lifecycle testing/lifecycle/typenative.json optimized none
build_and_run scheduler testing/scheduler/typenative.json optimized none
build_and_run animation testing/animation/typenative.json optimized none
build_and_run frame-budget testing/frame-budget/typenative.json optimized address
build_and_run frame-budget testing/frame-budget/typenative.json optimized none
build_and_run accessibility testing/accessibility/typenative.json optimized none
build_and_run style testing/style/typenative.json optimized none
build_and_run layout testing/layout/typenative.json optimized none
build_and_run reconciler testing/reconciler/typenative.json optimized none
build_and_run multi testing/multi/typenative.json optimized none
build_and_run async testing/async/typenative.json optimized none
build_and_run public-api testing/public-api/typenative.json optimized none
build_and_run list testing/list/typenative.json optimized none
build_and_run benchmark benchmarks/typenative.json optimized address
build_and_run native-renderer testing/native-renderer/typenative.json optimized none
build_and_run native-components testing/native-components/typenative.json optimized none
build_and_run native-window testing/native-window/typenative.json optimized none

build_and_run headless-undefined testing/headless-events/typenative.json debug undefined
build_and_run scheduler-undefined testing/scheduler/typenative.json debug undefined
build_and_run scheduler-thread testing/scheduler/typenative.json debug thread

metric_from() {
  metric_key=$1
  metric_file=$2
  awk -F= -v expected_key="$metric_key" '$1 == expected_key { value = $2 } END { if (value != "") print value }' "$metric_file" | tail -n 1
}

frame_budget_output="$verification/run-frame-budget-optimized.log"
frame_60_p95=$(metric_from frameBudget60P95Nanoseconds "$frame_budget_output")
frame_120_p95=$(metric_from frameBudget120P95Nanoseconds "$frame_budget_output")
test -n "$frame_60_p95"
test -n "$frame_120_p95"
assert_less frame-60hz-p95-nanoseconds "$frame_60_p95" 16670000
assert_less frame-120hz-p95-nanoseconds "$frame_120_p95" 8330000

benchmark_binary="$bin_dir/benchmark-optimized-address"
benchmark_output="$verification/benchmark-peak-output.log"
benchmark_peak="$verification/benchmark-peak-time.log"
if /usr/bin/time -l env ASAN_OPTIONS=detect_leaks=1:halt_on_error=1 \
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

metric() {
  key=$1
  awk -F= -v expected_key="$key" '$1 == expected_key { value = $2 } END { if (value != "") print value }' "$benchmark_output" | tail -n 1
}

node_count=$(metric nodeCount)
allocations=$(metric allocations)
mount_mutations=$(metric mutation.mount)
unchanged_mutations=$(metric mutation.unchanged)
reverse_mutations=$(metric mutation.reverse)
single_text_mutations=$(metric mutation.singleTextUpdate)
repeat_changed_mutations=$(metric mutation.repeatChanged)
wall_seconds=$(awk '/ real / { print $1 }' "$benchmark_peak" | tail -n 1)
peak_bytes=$(awk '/maximum resident set size/ { print $1 }' "$benchmark_peak" | tail -n 1)
test -n "$node_count"
test -n "$allocations"
test -n "$mount_mutations"
test -n "$unchanged_mutations"
test -n "$reverse_mutations"
test -n "$single_text_mutations"
test -n "$repeat_changed_mutations"
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
  "nodeCount": $node_count,
  "mutationGates": {
    "mount": $mount_mutations,
    "unchanged": $unchanged_mutations,
    "reverse": $reverse_mutations,
    "singleTextUpdate": $single_text_mutations,
    "repeatChanged": $repeat_changed_mutations
  }
}
EOF

cat > "$verification/performance-results.json" <<EOF
{
  "cachedCheckSeconds": $cached_check_seconds,
  "initialDebugBuildSeconds": $initial_build_seconds,
  "incrementalDebugBuildSeconds": $incremental_build_seconds,
  "frameBudgetNanoseconds": {
    "60HzP95": $frame_60_p95,
    "120HzP95": $frame_120_p95
  },
  "sampleOrder": [3, 8, 1, 6, 9, 2, 7, 4, 5],
  "samples": {
    "check": {
      "count": $check_count,
      "medianSeconds": $check_median,
      "p95Seconds": $check_p95,
      "meanSeconds": $check_mean,
      "standardDeviationSeconds": $check_stddev,
      "confidence95Seconds": $check_ci95
    },
    "debugBuild": {
      "count": $build_count,
      "medianSeconds": $build_median,
      "p95Seconds": $build_p95,
      "meanSeconds": $build_mean,
      "standardDeviationSeconds": $build_stddev,
      "confidence95Seconds": $build_ci95
    }
  },
  "thresholds": {
    "cachedCheckSeconds": 1.0,
    "incrementalDebugBuildSeconds": 2.0,
    "compilerInvocationSeconds": 180.0,
    "frame60HzP95Nanoseconds": 16670000,
    "frame120HzP95Nanoseconds": 8330000
  }
}
EOF

printf 'verification=pass\nbenchmark-results=%s\n' "$verification/benchmark-results.json"
