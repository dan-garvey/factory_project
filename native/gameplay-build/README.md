# Build and refresh the human gameplay library

`factory-gameplay-build` builds the canonical native World target, or the
`factory-opening-startup` executable with `--component startup`, and refreshes
only that component's three human-launcher pins after success. It never launches
Godot or controls a desktop. The Windows shortcut uses the tracked startup and
gameplay freshness guards. A changed source or missing installed binary triggers
one bounded build for that component; the helper then reloads its pins and
continues. A failed build leaves the shortcut closed and retains the old
installation. `--prepare-only` exercises both preparations without starting the
game; `--check` only validates existing installations.

A pre-merge Bazel test or build checks an agent's branch, which may never reach
main. It does not update the human shortcut. A plain `bazel build` remains an
artifact-only operation. The shortcut prepares its own current-main library
when the human opens it.

After one-time repository-local configuration, the normal entry point is
`./scripts/build-gameplay.sh`. Add `--startup` to select the startup executable.
Each invocation takes one native heavy admission, builds, then installs on
verified success; the shortcut calls it when needed. Configure the
absolute owned paths and the retained tool's verified hash:

```bash
git config --local factory.gameplayBuildExecutable /absolute/retained/factory-gameplay-build
git config --local factory.gameplayBuildSHA256 verified-lowercase-sha256
git config --local factory.gameplayArtifacts /absolute/owned/gameplay-build-family
git config --local factory.bazelExecutable /absolute/verified/bazel-8.4.2
git config --local factory.humanLauncher /absolute/human-launch-helper.sh
git config --local factory.gameplayInstallRoot /absolute/owned/installed-libraries
```

The small Bash entry point only validates local pins and dispatches the native
command. Each attempt gets a fresh log directory in the same cumulative family;
it does not reset the family or retry a failure. Run after publishing the relevant
native change, from a clean owned checkout whose production inputs match main.

Each build runs once through the existing bounded runner inside one ordinary
`factory-local heavy` admission. Use the pinned Bazel 8.4.2 executable, an owned
external family with verified dependency cache entries, and a clean committed
build checkout. The main checkout must have the same production inputs. Build
outside the shared Git landing lock. The command uses eight jobs, a five-minute
bound, an 8 MiB log and the existing 2 GiB family ceiling. No network dependency
download, resource-floor override or passing-test replay is introduced.

```bash
"$FACTORY_LOCAL" --root "$BUILD_CHECKOUT" heavy --inherit-permits -- \
  "$FACTORY_GAMEPLAY_BUILD" \
  --checkout "$BUILD_CHECKOUT" --main /home/dan/factory_project \
  --bazel "$FACTORY_BAZEL" --artifacts "$OWNED_BUILD_FAMILY" \
  --log "$OWNED_BUILD_FAMILY/fresh-build.log" \
  --admission-directory /home/dan/factory_project/.git/factory-local-resources \
  --launcher "$HUMAN_LAUNCH_HELPER" \
  --install-root /home/dan/.local/state/factory-prototypes/human-opening/native
```

Build the tool with `//native/gameplay-build:factory-gameplay-build`. Its focused
publication controls are `//native/gameplay-build:install_test`; this explicit
host test uses isolated temporary Git repositories and invented ELF headers,
never a game, the real launcher or a real library loader.

The tool snapshots the selected component's committed source closure and launcher before building.
It refuses if the build checkout changes, production on main advances, launcher
pins change concurrently, output is missing or malformed, or the destination is
invalid. An unrelated documentation commit may advance main without invalidating
the library. The existing startup/engine pins and all other launcher bytes remain
unchanged. The successful binary is copied into an immutable source-and-content-
addressed directory before only its three pins are replaced in one atomic launcher
update. Old binaries and failed-build logs are preserved. Interrupted filesystem
publication can leave an unused version directory; it cannot silently point the
launcher at a partially copied binary. Both source guards remain active because
another production commit can land after any installation completes.

This is a cooperative same-user workflow, not an adversarial package-signing or
filesystem-isolation boundary. Toolchain/header provenance remains the existing
[native build contract](../../docs/engineering/native-builds.md). Successful
compilation and installation do not establish gameplay, human usability or a
new native test result. A build failure returns its original exit and leaves the
previous launcher and installed library untouched.
