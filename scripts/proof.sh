#!/usr/bin/env bash
# One-shot native proof command. Submission does not start a watcher.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tool=$(git -C "$root" config --get factory.proofExecutable)
expected=$(git -C "$root" config --get factory.proofSHA256)
[[ $tool == /* && -x $tool && ! -L $tool && $expected =~ ^[0-9a-f]{64}$ ]] || exit 1
actual=$(sha256sum < "$tool")
[[ ${actual%% *} == "$expected" ]] || { printf 'The proof bridge differs from its installed pin.\n' >&2; exit 1; }
(( $# > 0 )) || { "$tool" --help; exit 2; }
command=$1
shift
exec "$tool" "$command" --root "$root" "$@"
