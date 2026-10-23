#!/usr/bin/env bash
# factory-opening-startup runs an admitted child import; pass its permit files through.
set -euo pipefail
if (( $# < 4 )); then
    printf 'Usage: %s PROJECT ADMISSION STARTUP STARTUP_ARGUMENTS...\n' "$0" >&2
    exit 2
fi
project=$1
admission=$2
startup=$3
shift 3
[[ $project == /* && $admission == /* && $startup == /* &&
   -d $project && -x $admission && -x $startup ]] || {
    printf 'The native startup or its admission helper is unavailable.\n' >&2
    exit 1
}
exec "$admission" --root "$project" heavy --inherit-permits -- "$startup" "$@"
