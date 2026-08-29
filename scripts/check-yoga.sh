#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
lock="$root/deps/yoga.lock.json"
cache="$root/.cache/yoga"
archive="$cache/yoga-v3.2.1.tar.gz"
source="$cache/yoga-3.2.1"
build="$cache/build-core"

test -f "$lock"
grep -F '"tag": "v3.2.1"' "$lock" >/dev/null
grep -F '"commit": "042f5013152eb81c1552dec945b88f7b95ca350f"' "$lock" >/dev/null
grep -F '"sha256": "86b399ac31fd820d8ffa823c3fae31bb690b6fc45301b2a8a966c09b5a088b55"' "$lock" >/dev/null

mkdir -p "$cache"
if [ ! -f "$archive" ]; then
  curl --fail --location --silent --show-error \
    "https://github.com/react/yoga/archive/refs/tags/v3.2.1.tar.gz" \
    --output "$archive"
fi
test "$(shasum -a 256 "$archive" | awk '{print $1}')" = \
  "86b399ac31fd820d8ffa823c3fae31bb690b6fc45301b2a8a966c09b5a088b55"
if [ ! -d "$source" ]; then
  mkdir -p "$source"
  tar -xzf "$archive" --strip-components=1 -C "$source"
fi
cmake -S "$source/yoga" -B "$build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build" --config Release --target yogacore
printf '%s\n' "$build"
