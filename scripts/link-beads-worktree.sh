#!/usr/bin/env bash
set -euo pipefail

if (( $# > 1 )); then
    printf 'Usage: %s [worktree-path]\n' "$0" >&2
    exit 2
fi

worktree_root=$(git -C "${1:-.}" rev-parse --show-toplevel)
common_git_dir=$(git -C "$worktree_root" rev-parse --path-format=absolute --git-common-dir)
common_git_dir=$(realpath -e -- "$common_git_dir")

if [[ ${common_git_dir##*/} != .git ]]; then
    printf 'Expected a main checkout with a .git directory; refusing to guess the Beads owner.\n' >&2
    exit 1
fi

main_root=$(dirname -- "$common_git_dir")
shared_beads=$(realpath -e -- "$main_root/.beads")
entry="$worktree_root/.beads"

if [[ ! -f "$shared_beads/beads.db" ]]; then
    printf 'The main checkout has no initialized Rust Beads database.\n' >&2
    exit 1
fi

if [[ "$worktree_root" == "$main_root" ]]; then
    printf 'Main checkout owns the canonical Beads directory: %s\n' "$shared_beads"
    exit 0
fi

if [[ -L "$entry" ]]; then
    if [[ $(readlink -f -- "$entry") != "$shared_beads" ]]; then
        printf 'Refusing to replace an existing .beads symlink pointing elsewhere: %s\n' "$entry" >&2
        exit 1
    fi
    printf 'Already sharing Beads: %s -> %s\n' "$entry" "$shared_beads"
    exit 0
fi

if [[ -e "$entry" ]]; then
    if [[ ! -d "$entry" ]]; then
        printf 'Refusing to replace a non-directory: %s\n' "$entry" >&2
        exit 1
    fi
    if [[ -e "$entry/beads.db" || -e "$entry/dolt" || -e "$entry/embeddeddolt" || -e "$entry/redirect" ]]; then
        printf 'Refusing an existing worktree database or redirect; reconcile its issues first: %s\n' "$entry" >&2
        exit 1
    fi
    if ! git -C "$worktree_root" diff --quiet -- .beads ||
       ! git -C "$worktree_root" diff --cached --quiet -- .beads ||
       [[ -n $(git -C "$worktree_root" ls-files --others -- .beads) ]]; then
        printf 'Refusing locally modified or untracked Beads files: %s\n' "$entry" >&2
        exit 1
    fi
    snapshot_backup=$(mktemp -d "$common_git_dir/beads-worktree-backup.XXXXXX")
    mv -- "$entry" "$snapshot_backup/.beads"
    printf 'Archived the clean worktree snapshot: %s\n' "$snapshot_backup/.beads"
fi

ln -s -- "$shared_beads" "$entry"
printf 'Sharing Beads: %s -> %s\n' "$entry" "$shared_beads"
