#!/bin/sh
set -eu

compiler_root=${1:?compiler repository path is required}
protected_file="$compiler_root/benchmarks/json-parser/results.json"
protected_worktree_sha=634c57f2f3b53be3bd51912b3321026a80f0099043b50f6dc0b53587d485634d

protected_sha=$(shasum -a 256 "$protected_file" | awk '{print $1}')
test "$protected_sha" = "$protected_worktree_sha"
git -C "$compiler_root" diff --quiet HEAD -- compiler-tn scripts/bootstrap-self-host.sh
