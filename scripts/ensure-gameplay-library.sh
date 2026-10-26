#!/usr/bin/env bash
# Return 10 after a successful refresh so the caller reloads the launcher's new pins.
set -euo pipefail

if [[ $# != 6 || ( $1 != check && $1 != prepare ) ]]; then
    printf 'Usage: %s check|prepare PROJECT LIBRARY_SOURCE REVISION LIBRARY SHA256\n' "$0" >&2
    exit 2
fi
mode=$1
project=$2
source_revision=$3
revision=$4
library=$5
digest=$6

[[ $source_revision =~ ^[0-9a-f]{40}$ && $revision =~ ^[0-9a-f]{40}$ &&
   $digest =~ ^[0-9a-f]{64}$ && -d $project ]] || {
    printf 'The gameplay library has invalid source or hash pins.\n' >&2
    exit 1
}

manifest_path=native/gameplay-build/production-paths.txt
manifest=$(git -C "$project" show "$revision:$manifest_path") || {
    printf 'Cannot read the committed gameplay dependency manifest.\n' >&2
    exit 1
}
production_paths=("$manifest_path")
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
    if [[ $component == gameplay ]]; then production_paths+=("$path"); fi
done <<< "$manifest"
(( ${#production_paths[@]} > 1 )) || { printf 'The gameplay dependency manifest is empty.\n' >&2; exit 1; }

source_current=false
if git -C "$project" diff --quiet "$source_revision" "$revision" -- "${production_paths[@]}"; then
    source_current=true
else
    result=$?
    [[ $result == 1 ]] || {
        printf 'Could not compare the installed and current gameplay sources.\n' >&2
        exit "$result"
    }
fi

library_current=false
if [[ -f $library && ! -L $library ]] &&
   printf '%s  %s\n' "$digest" "$library" | /usr/bin/sha256sum --check --status; then
    library_current=true
fi

if "$source_current" && "$library_current"; then
    exit 0
fi
if [[ $mode == check ]]; then
    printf 'The installed gameplay library needs a successful build for current main.\n' >&2
    exit 1
fi
if [[ ${FACTORY_GAMEPLAY_REFRESHED:-0} == 1 ]]; then
    printf 'Main changed during gameplay preparation, or the rebuilt library did not validate. Try the shortcut again.\n' >&2
    exit 1
fi

printf 'Building the current gameplay library before launch.\n'
"$project/scripts/build-gameplay.sh"
exit 10
