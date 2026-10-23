#!/usr/bin/env bash
# Build and install the current native World; never launch the game.
set -euo pipefail
component=gameplay
if (( $# > 1 )); then
    printf 'Usage: %s [--startup]\n' "$0" >&2
    exit 2
fi
if (( $# == 1 )); then
    [[ $1 == --startup ]] || { printf 'Usage: %s [--startup]\n' "$0" >&2; exit 2; }
    component=startup
fi
root=$(git rev-parse --show-toplevel)
common=$(git rev-parse --path-format=absolute --git-common-dir)
[[ $(basename "$common") == .git ]] || { printf 'Configure an ordinary canonical main checkout for gameplay delivery.\n' >&2; exit 1; }
main=$(dirname "$common")
setting() {
    local value
    value=$(git -C "$root" config --local --get "$1") && [[ -n "$value" ]] ||
        { printf 'Missing repository-local %s; see native/gameplay-build/README.md.\n' "$1" >&2; exit 1; }
    printf '%s' "$value"
}
tool=$(setting factory.gameplayBuildExecutable)
digest=$(setting factory.gameplayBuildSHA256)
artifacts=$(setting factory.gameplayArtifacts)
bazel=$(setting factory.bazelExecutable)
launcher=$(setting factory.humanLauncher)
installed=$(setting factory.gameplayInstallRoot)
[[ "$tool" == /* && -f "$tool" && ! -L "$tool" && -x "$tool" && "$digest" =~ ^[0-9a-f]{64}$ ]] &&
    printf '%s  %s\n' "$digest" "$tool" | sha256sum --check --status ||
    { printf 'The configured native gameplay build tool is missing or changed.\n' >&2; exit 1; }
[[ "$artifacts" == /* && -d "$artifacts" && ! -L "$artifacts" ]] ||
    { printf 'Use an existing owned absolute gameplay artifact family.\n' >&2; exit 1; }
umask 077
session=$(mktemp -d "$artifacts/build-$component-$(date -u +%Y%m%d-%H%M%S)-XXXXXX")
extra=()
[[ $component == startup ]] && extra=(--component startup)
exec "$common/factory-local-resources/factory-local" --root "$root" heavy --inherit-permits -- "$tool" \
    --checkout "$root" --main "$main" --bazel "$bazel" --artifacts "$artifacts" \
    --log "$session/build.log" --admission-directory "$common/factory-local-resources" \
    --launcher "$launcher" --install-root "$installed" "${extra[@]}"
