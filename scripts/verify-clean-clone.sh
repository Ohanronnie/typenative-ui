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
remote=$(git -C "$root" remote get-url origin)
clone_dir=$(mktemp -d "${TMPDIR:-/tmp}/typenative-ui-clean.XXXXXX")

cleanup() {
  rm -rf -- "$clone_dir"
}
trap cleanup EXIT HUP INT TERM

git clone --quiet --depth 1 --branch main "$remote" "$clone_dir"
test -z "$(git -C "$clone_dir" status --porcelain --untracked-files=all)"

(cd "$clone_dir" && "$compiler" fmt --check src examples testing benchmarks)
(cd "$clone_dir" && "$compiler" check typenative.json --timings)
(cd "$clone_dir" && "$compiler" lint . --json)
test -z "$(git -C "$clone_dir" status --porcelain --untracked-files=all)"

printf '%s\n' "clean-clone=pass"
