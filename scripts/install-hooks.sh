#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
existing=$(git config --get core.hooksPath || true)
if [[ -n "$existing" && "$existing" != .githooks ]]; then
    printf 'Refusing to replace existing core.hooksPath: %s\n' "$existing" >&2
    exit 1
fi
if [[ -z "$existing" ]]; then
    hooks_dir=$(git rev-parse --path-format=absolute --git-path hooks)
    for hook in "$hooks_dir"/*; do
        if [[ -f "$hook" && -x "$hook" && "$hook" != *.sample ]]; then
            printf 'Refusing to disable an existing executable default hook: %s\n' "$hook" >&2
            exit 1
        fi
    done
fi
if [[ ! -x "$root/.githooks/pre-commit" ]]; then
    printf 'Missing executable .githooks/pre-commit; restore its executable bit first.\n' >&2
    exit 1
fi
git config --local core.hooksPath .githooks
printf 'Installed repository hooks (also used by linked worktrees).\n'
