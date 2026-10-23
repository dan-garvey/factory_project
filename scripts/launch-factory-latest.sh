#!/usr/bin/env bash
# Stable Windows-shortcut target; the configured helper owns mutable build pins.
set -euo pipefail
project=/home/dan/factory_project
[[ $(git -C "$project" branch --show-current) == main ]] || {
    printf 'Factory (Latest) requires the canonical main checkout.\n' >&2
    exit 1
}
launcher=$(git -C "$project" config --local --get factory.humanLauncher)
[[ $launcher == /* && -f $launcher && ! -L $launcher && -x $launcher ]] || {
    printf 'The configured Factory launch helper is unavailable.\n' >&2
    exit 1
}
exec "$launcher" "$@"
