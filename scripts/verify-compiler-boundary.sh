#!/bin/sh
set -eu

compiler_root=${1:?compiler repository path is required}
expected_commit=3ef10d4579e1c0765ad56fe787db37b9bdcb4c1a
protected_file="$compiler_root/benchmarks/json-parser/results.json"
protected_worktree_sha=634c57f2f3b53be3bd51912b3321026a80f0099043b50f6dc0b53587d485634d

test "$(git -C "$compiler_root" rev-parse HEAD)" = "$expected_commit"
protected_sha=$(shasum -a 256 "$protected_file" | awk '{print $1}')
committed_sha=$(git -C "$compiler_root" show "$expected_commit:benchmarks/json-parser/results.json" | shasum -a 256 | awk '{print $1}')
test "$protected_sha" = "$protected_worktree_sha" || test "$protected_sha" = "$committed_sha"
git -C "$compiler_root" diff --quiet "$expected_commit" -- compiler-tn scripts/bootstrap-self-host.sh
