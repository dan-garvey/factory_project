#!/usr/bin/env bash
# Called only at a main-ref update or publication boundary, never a model poll.
set -euo pipefail
(( $# == 2 )) || exit 2
required=$(git config --get factory.proofRequired || true)
[[ $required == true ]] || exit 0
root=$(git rev-parse --show-toplevel)
tool=$(git config --get factory.proofExecutable)
expected=$(git config --get factory.proofSHA256)
[[ $tool == /* && -x $tool && ! -L $tool && $expected =~ ^[0-9a-f]{64}$ ]] || {
    printf 'Human visual review is enabled but the pinned proof bridge is unavailable.\n' >&2; exit 1;
}
actual=$(sha256sum < "$tool")
[[ ${actual%% *} == "$expected" ]] || { printf 'The proof bridge differs from its installed pin.\n' >&2; exit 1; }
before=$1 after=$2
[[ $after != 0000000000000000000000000000000000000000 ]] || {
    printf 'The visual review gate does not authorize deleting main.\n' >&2; exit 1;
}
if [[ $before == 0000000000000000000000000000000000000000 ]]; then
    before=$(git hash-object -t tree /dev/null)
fi
exec "$tool" gate --root "$root" --before "$before" --after "$after"
