#!/usr/bin/env bash
# Factory (Latest): discover this checkout and dispatch the sealed native launcher.
set -Eeuo pipefail
umask 077
on_exit() {
    result=$?
    if (( result != 0 )); then
        printf '\nFactory could not finish launching (exit %s). The error is above.\n' "$result" >&2
        if [[ -t 0 ]]; then read -r -p 'Press Enter to close this window. ' || true; fi
    fi
}
trap on_exit EXIT

mode=prepare
resume=()
session_only=()
agent=()
agent_window=()
usage() {
    printf 'Usage: %s [--check|--prepare-only|--prepare-session-only] [--resume ABSOLUTE_SAVE]\n' "$0" >&2
    printf '       %s --agent --test-purpose=TEXT [--resume ABSOLUTE_SAVE]\n' "$0" >&2
    printf '       %s --agent-window --test-purpose=TEXT --scene|--script res://PATH [-- USER_ARGUMENTS...]\n' "$0" >&2
    exit 2
}
if [[ ${1:-} == --agent || ${1:-} == --agent-window ]]; then
    agent_mode=$1
    shift
    (( $# > 0 )) || usage
    case $1 in
        --test-purpose=*) purpose=${1#--test-purpose=}; shift ;;
        --test-purpose) (( $# >= 2 )) || usage; purpose=$2; shift 2 ;;
        *) usage ;;
    esac
    if [[ $agent_mode == --agent ]]; then
        agent=(--agent --test-purpose "$purpose")
        if (( $# > 0 )); then
            (( $# == 2 )) && [[ $1 == --resume && $2 == /* ]] || usage
            resume=(--resume "$2")
        fi
    else
        (( $# >= 2 )) && [[ $1 == --scene || $1 == --script ]] || usage
        selector=$1 target=$2
        shift 2
        agent_window=(--test-purpose "$purpose" "$selector" "$target")
        if (( $# > 0 )); then
            [[ $1 == -- ]] || usage
            shift
            agent_window+=(-- "$@")
        fi
        mode=agent-window
    fi
else
case $# in
    0) ;;
    1) case $1 in
        --check) mode=check ;;
        --prepare-only) mode=prepare-only ;;
        --prepare-session-only) session_only=(--prepare-session-only) ;;
        *) usage ;;
       esac ;;
    2) [[ $1 == --resume && $2 == /* ]] && resume=(--resume "$2") || {
           usage;
       } ;;
    3) [[ $1 == --prepare-session-only && $2 == --resume && $3 == /* ]] &&
           { session_only=(--prepare-session-only); resume=(--resume "$3"); } || {
           usage;
       } ;;
    *) usage ;;
esac
fi

project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
[[ $(git -C "$project" rev-parse --show-toplevel) == "$project" &&
   $(git -C "$project" symbolic-ref --quiet --short HEAD) == main ]] || {
    printf 'Factory (Latest) requires a main checkout.\n' >&2; exit 1;
}
[[ -z $(git -C "$project" status --porcelain --untracked-files=normal) ]] || {
    printf 'Factory (Latest) requires a clean committed main checkout.\n' >&2; exit 1;
}
revision=$(git -C "$project" rev-parse --verify HEAD)
common_git=$(git -C "$project" rev-parse --path-format=absolute --git-common-dir)
admission="$common_git/factory-local-resources/factory-local"
pins=$(git -C "$project" config --local --get factory.humanPins) || {
    printf 'Configure factory.humanPins; see native/gameplay-build/README.md.\n' >&2; exit 1;
}
[[ $pins == /* && -f $pins && ! -L $pins && -O $pins && -x $admission ]] || {
    printf 'The local pins or resource helper are unavailable.\n' >&2; exit 1;
}

# Interpret assignments as data. Never execute the local pin file.
read_pin() {
    local name=$1 value
    local -a lines
    mapfile -t lines < <(sed -n "/^${name}=/p" "$pins")
    (( ${#lines[@]} == 1 )) || { printf 'Expected one %s pin.\n' "$name" >&2; exit 1; }
    value=${lines[0]#*=}
    if [[ $value == \'*\' ]]; then
        value=${value:1:${#value}-2}
        value=${value//\'\"\'\"\'/\'}
    fi
    [[ -n $value && $value != *$'\r'* ]] || { printf 'Invalid %s pin.\n' "$name" >&2; exit 1; }
    printf '%s' "$value"
}
verify_file() {
    [[ $1 == /* && -f $1 && ! -L $1 && $2 =~ ^[0-9a-f]{64}$ ]] &&
        printf '%s  %s\n' "$2" "$1" | /usr/bin/sha256sum --check --status || {
            printf 'Missing or changed native launch resource: %s\n' "$1" >&2; exit 1;
        }
}

engine=$(read_pin engine)
engine_sha256=$(read_pin engine_sha256)
startup=$(read_pin startup)
startup_sha256=$(read_pin startup_sha256)
startup_source=$(read_pin startup_source)
library=$(read_pin library)
library_sha256=$(read_pin library_sha256)
library_source=$(read_pin library_source)
sessions=$(read_pin sessions)
verify_file "$engine" "$engine_sha256"
[[ -x $engine ]] || { printf 'The pinned engine is not executable.\n' >&2; exit 1; }

guard_component() {
    local component=$1 source=$2 binary=$3 digest=$4 script status
    script="$project/scripts/ensure-${component}.sh"
    if "$script" "$([[ $mode == check ]] && printf check || printf prepare)" "$project" \
        "$source" "$revision" "$binary" "$digest"; then
        return 0
    else
        status=$?
    fi
    [[ $status == 10 ]] || return "$status"
    [[ $(git -C "$project" rev-parse --verify HEAD) == "$revision" ]] || {
        printf 'Main changed during native preparation; try again.\n' >&2; return 1;
    }
    if [[ $component == startup-launcher ]]; then
        source=$(read_pin startup_source); binary=$(read_pin startup); digest=$(read_pin startup_sha256)
    else
        source=$(read_pin library_source); binary=$(read_pin library); digest=$(read_pin library_sha256)
    fi
    "$script" check "$project" "$source" "$revision" "$binary" "$digest"
}
guard_component startup-launcher "$startup_source" "$startup" "$startup_sha256"
guard_component gameplay-library "$library_source" "$library" "$library_sha256"
startup=$(read_pin startup); startup_sha256=$(read_pin startup_sha256)
library=$(read_pin library); library_sha256=$(read_pin library_sha256)
verify_file "$startup" "$startup_sha256"
verify_file "$library" "$library_sha256"
[[ -x $startup && $sessions == /* ]] || { printf 'The startup executable or session root is invalid.\n' >&2; exit 1; }

printf 'Factory (Latest): '
git -C "$project" show -s --format='%h %s' "$revision"
if [[ $mode == check ]]; then
    printf 'Native startup, gameplay library and engine hashes match current main. No game was started.\n'
    exit 0
fi
if [[ $mode == prepare-only ]]; then
    printf 'Native launch resources are ready. No game was started.\n'
    exit 0
fi
if [[ $mode == agent-window ]]; then
    exec "$startup" --agent-window --repo "$project" --tree "$revision" \
        --engine "$engine" --engine-sha256 "$engine_sha256" \
        --admission "$admission" "${agent_window[@]}"
fi
exec "$startup" --human-launch --repo "$project" --tree "$revision" \
    --engine "$engine" --engine-sha256 "$engine_sha256" \
    --library "$library" --library-sha256 "$library_sha256" \
    --sessions "$sessions" --admission "$admission" "${session_only[@]}" "${agent[@]}" "${resume[@]}"
