#!/usr/bin/env bash
# Return 10 after a successful build so the caller reloads the new startup pins.
set -euo pipefail

if [[ $# != 6 || ( $1 != check && $1 != prepare ) ]]; then
    printf 'Usage: %s check|prepare PROJECT STARTUP_SOURCE REVISION STARTUP SHA256\n' "$0" >&2
    exit 2
fi
mode=$1
project=$2
source_revision=$3
revision=$4
startup=$5
digest=$6

[[ $source_revision =~ ^[0-9a-f]{40}$ && $revision =~ ^[0-9a-f]{40}$ &&
   $digest =~ ^[0-9a-f]{64}$ && -d $project ]] || {
    printf 'The native startup has invalid source or hash pins.\n' >&2
    exit 1
}

manifest_path=native/gameplay-build/production-paths.txt
manifest=$(git -C "$project" show "$revision:$manifest_path") || {
    printf 'Cannot read the committed startup dependency manifest.\n' >&2
    exit 1
}
startup_paths=("$manifest_path")
declare -A seen_paths=()
while IFS= read -r line; do
    [[ $line =~ ^(startup|gameplay)\ ([a-zA-Z0-9._/-]+)$ ]] || {
        printf 'Invalid production dependency manifest.\n' >&2; exit 1;
    }
    component=${BASH_REMATCH[1]}
    path=${BASH_REMATCH[2]}
    [[ $path != /* && $path != *..* && $path != *//* && ! -v seen_paths[$line] ]] || {
        printf 'Unsafe or duplicate production dependency path.\n' >&2; exit 1;
    }
    seen_paths[$line]=1
    if [[ $component == startup ]]; then startup_paths+=("$path"); fi
done <<< "$manifest"
(( ${#startup_paths[@]} > 1 )) || { printf 'The startup dependency manifest is empty.\n' >&2; exit 1; }
source_current=false
if git -C "$project" diff --quiet "$source_revision" "$revision" -- "${startup_paths[@]}"; then
    source_current=true
else
    result=$?
    [[ $result == 1 ]] || {
        printf 'Could not compare the installed and current startup sources.\n' >&2
        exit "$result"
    }
fi

binary_current=false
if [[ -f $startup && ! -L $startup && -x $startup ]] &&
   printf '%s  %s\n' "$digest" "$startup" | /usr/bin/sha256sum --check --status; then
    binary_current=true
fi
if "$source_current" && "$binary_current"; then
    exit 0
fi
if [[ $mode == check ]]; then
    printf 'The native startup needs a successful current-main build.\n' >&2
    exit 1
fi
if [[ ${FACTORY_STARTUP_REFRESHED:-0} == 1 ]]; then
    printf 'Main changed during startup preparation, or the rebuilt startup did not validate. Try the shortcut again.\n' >&2
    exit 1
fi

printf 'Building the current native startup before launch.\n'
"$project/scripts/build-gameplay.sh" --startup
exit 10
