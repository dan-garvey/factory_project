#!/usr/bin/env bash
# Agent launches of the Windows review app always identify their purpose.
set -euo pipefail
if [[ ${1:-} != --test-purpose=* || -z ${1#--test-purpose=} ]]; then
    printf 'Usage: %s --test-purpose=TEXT [VIEWER_ARGUMENTS...]\n' "$0" >&2
    exit 2
fi
purpose=${1#--test-purpose=}
shift
[[ ${#purpose} -le 80 && $purpose != *$'\n'* && $purpose != *$'\r'* ]] || exit 2
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
viewer=$(git -C "$root" config --get factory.proofViewer)
expected=$(git -C "$root" config --get factory.proofViewerSHA256)
[[ $viewer == /* && -f $viewer && $expected =~ ^[0-9a-f]{64}$ ]] || exit 1
actual=$(sha256sum < "$viewer")
[[ ${actual%% *} == "$expected" ]] || { printf 'Proof viewer changed from its installed pin.\n' >&2; exit 1; }
exec "$viewer" --test-purpose "$purpose" "$@"
