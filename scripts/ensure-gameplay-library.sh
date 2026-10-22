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

# Match the production closure in native/gameplay-build/build.cpp. Build and
# package changes can change the library even when no World .cpp file changes.
production_paths=(
    .bazelrc MODULE.bazel MODULE.bazel.lock
    native/factory-godot-world/src native/factory-godot-world/include native/factory-godot-world/BUILD.bazel
    native/opening-engineering/src native/opening-engineering/include native/opening-engineering/BUILD.bazel
    native/factory-godot-values/src native/factory-godot-values/include native/factory-godot-values/vendor native/factory-godot-values/BUILD.bazel
    native/factory-value/src native/factory-value/include native/factory-value/BUILD.bazel
    native/factory-world/src native/factory-world/include native/factory-world/BUILD.bazel
    native/factory-assembly/src native/factory-assembly/include native/factory-assembly/BUILD.bazel
    native/mineral-site/src native/mineral-site/include native/mineral-site/BUILD.bazel
    native/waterwheel/src native/waterwheel/include native/waterwheel/BUILD.bazel
    native/waterflow/src native/waterflow/include native/waterflow/BUILD.bazel
    native/factory-core/src native/factory-core/include native/factory-core/BUILD.bazel
    native/factory-stationary/src native/factory-stationary/include native/factory-stationary/BUILD.bazel
    native/factory-authority/src native/factory-authority/include native/factory-authority/BUILD.bazel
    native/factory-mechanics/src native/factory-mechanics/include native/factory-mechanics/BUILD.bazel
)

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
