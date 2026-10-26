#!/usr/bin/env bash
# Exercise the launch preparation boundary without Bazel, Godot or a desktop.
set -euo pipefail

root=$(mktemp -d "${TMPDIR:-/tmp}/factory-library-refresh-XXXXXX")
trap 'rm -rf -- "$root"' EXIT
project="$root/project"
mkdir -p "$project/native/factory-world/src" "$project/native/gameplay-build" "$project/scripts"
git -C "$root" init -q project
git -C "$project" config user.name 'Factory test'
git -C "$project" config user.email 'factory-test@example.invalid'
printf 'world one\n' > "$project/native/factory-world/src/world.cpp"
cat > "$project/native/gameplay-build/production-paths.txt" <<'PATHS'
startup native/factory-launch/src
gameplay native/factory-world/src
gameplay native/mineral-site/include
gameplay native/waterwheel/include
PATHS
printf 'notes one\n' > "$project/README.md"
git -C "$project" add README.md native/factory-world/src/world.cpp native/gameplay-build/production-paths.txt
git -C "$project" -c core.hooksPath=/dev/null commit -qm first
first=$(git -C "$project" rev-parse HEAD)

printf 'library one\n' > "$root/library.so"
digest=$(sha256sum "$root/library.so")
digest=${digest%% *}
counter="$root/build-count"
cat > "$project/scripts/build-gameplay.sh" <<'BUILDER'
#!/usr/bin/env bash
printf 'build\n' >> "$FACTORY_TEST_COUNTER"
exit "${FACTORY_TEST_BUILD_EXIT:-0}"
BUILDER
chmod +x "$project/scripts/build-gameplay.sh"
refresh=${BASH_SOURCE[0]%/tests/*}/ensure-gameplay-library.sh
[[ -f $refresh ]] || { printf 'Missing launch preparation script.\n' >&2; exit 1; }

FACTORY_TEST_COUNTER=$counter "$refresh" check "$project" "$first" "$first" "$root/library.so" "$digest"
FACTORY_TEST_COUNTER=$counter "$refresh" prepare "$project" "$first" "$first" "$root/library.so" "$digest"
[[ ! -e $counter ]] || { printf 'An unchanged library caused a build.\n' >&2; exit 1; }

printf 'notes two\n' >> "$project/README.md"
git -C "$project" add README.md
git -C "$project" -c core.hooksPath=/dev/null commit -qm docs
docs=$(git -C "$project" rev-parse HEAD)
FACTORY_TEST_COUNTER=$counter "$refresh" prepare "$project" "$first" "$docs" "$root/library.so" "$digest"
[[ ! -e $counter ]] || { printf 'An unrelated documentation change caused a build.\n' >&2; exit 1; }

for dependency in mineral-site waterwheel; do
    dependency_base=$(git -C "$project" rev-parse HEAD)
    mkdir -p "$project/native/$dependency/include"
    printf 'changed native dependency\n' > "$project/native/$dependency/include/profile.hpp"
    git -C "$project" add "native/$dependency/include/profile.hpp"
    git -C "$project" -c core.hooksPath=/dev/null commit -qm dependency
    dependency_revision=$(git -C "$project" rev-parse HEAD)
    if FACTORY_TEST_COUNTER=$counter "$refresh" check "$project" "$dependency_base" "$dependency_revision" "$root/library.so" "$digest" > /dev/null 2>&1; then
        printf 'Validation-only mode accepted a changed %s dependency.\n' "$dependency" >&2
        exit 1
    fi
    [[ ! -e $counter ]] || { printf 'Dependency validation launched a build.\n' >&2; exit 1; }
done

printf 'world two\n' >> "$project/native/factory-world/src/world.cpp"
git -C "$project" add native/factory-world/src/world.cpp
git -C "$project" -c core.hooksPath=/dev/null commit -qm world
world=$(git -C "$project" rev-parse HEAD)
if FACTORY_TEST_COUNTER=$counter "$refresh" check "$project" "$first" "$world" "$root/library.so" "$digest" > /dev/null 2>&1; then
    printf 'Validation-only mode accepted stale production.\n' >&2
    exit 1
fi
[[ ! -e $counter ]] || { printf 'Validation-only mode caused a build.\n' >&2; exit 1; }

result=0
FACTORY_TEST_COUNTER=$counter "$refresh" prepare "$project" "$first" "$world" "$root/library.so" "$digest" > /dev/null || result=$?
[[ $result == 10 && $(wc -l < "$counter") == 1 ]] || {
    printf 'A stale production source did not request exactly one refresh.\n' >&2
    exit 1
}
if FACTORY_GAMEPLAY_REFRESHED=1 FACTORY_TEST_COUNTER=$counter "$refresh" prepare "$project" "$first" "$world" "$root/library.so" "$digest" > /dev/null 2>&1; then
    printf 'A second refresh was allowed in the same launch.\n' >&2
    exit 1
fi
[[ $(wc -l < "$counter") == 1 ]] || { printf 'A second build was launched.\n' >&2; exit 1; }

rm "$root/library.so"
result=0
FACTORY_TEST_BUILD_EXIT=23 FACTORY_TEST_COUNTER=$counter "$refresh" prepare "$project" "$world" "$world" "$root/library.so" "$digest" > /dev/null || result=$?
[[ $result == 23 && $(wc -l < "$counter") == 2 ]] || {
    printf 'A failed build did not propagate its original exit.\n' >&2
    exit 1
}
printf 'Launch preparation controls passed.\n'
