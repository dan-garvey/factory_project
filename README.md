# Factory

An experimental 3D mechanical factory game. The native opening starts with a
landing pod, finite local wood/ore, a multitool and component fabrication.
Players arrange machinery to make a first carried plate. Chapter 1 remains
under development; a running prototype is not a claim of completed usability,
multiplayer or performance acceptance.

[DESIGN.md](DESIGN.md) holds game requirements. Contributors and agents follow
[AGENTS.md](AGENTS.md). Tasks, current status and evidence live in the private
Rust Beads tracker; public source can be built without it.

## Run the current opening

On the configured development machine, use **Factory (Latest)** or:

```bash
./scripts/launch-factory-latest.sh
```

The tracked shortcut locates its own clean main checkout, checks and refreshes
its pinned native startup executable and gameplay library, and opens a fresh
session. Configure local installation paths as described in the
[gameplay installation guide](native/gameplay-build/README.md). Preparation
failure stops launch.

```bash
./scripts/launch-factory-latest.sh --check
./scripts/launch-factory-latest.sh --prepare-only
./scripts/launch-factory-latest.sh --resume /absolute/path/to/player.factory
```

`--check` validates existing installations without building; `--prepare-only`
runs needed preparation without starting Godot. `--resume` copies the selected
native save into a fresh session and opens it with a new save slot. For a
headless startup record without a window, use `--prepare-session-only`, with
optional `--resume /absolute/path/to/player.factory`. These are local
development entrypoints, not a portable installer.

Agent graphical runs require a visible purpose label (at most 60 Unicode
characters). The label is a runtime argument, so changing it reuses the same
native and Godot artifacts:

```bash
./scripts/launch-factory-latest.sh --agent --test-purpose="Ore interaction reach"
./scripts/launch-factory-latest.sh --agent --test-purpose="Resume inspection" --resume /absolute/path/to/player.factory
./scripts/launch-factory-latest.sh --agent-window --test-purpose="Slide fixture" --script res://opening/parts_view_check.gd -- --slide-view-only
./scripts/launch-factory-latest.sh --agent-window --test-purpose="First plate route" --script res://opening/native_adapter_check.gd -- --native-check-mode=arrival-first-plate --event-route-pointer --native-check-output=/absolute/owned/first-plate.bin --save-slot=/absolute/owned/first-plate.factory
```

For a shared client with an already running server, use `--agent-window`
with `--scene res://opening/shared_opening.tscn`, then pass the session port
and role after `--`. Supported script fixtures are `parts_view_check.gd`,
`native_adapter_check.gd`, `native_transmission_view_check.gd`, and
`worker_wardrobe_view_check.gd` in
`res://opening/`; other targets refuse until they initialize the same title.
The normal player shortcut needs no test purpose.

For another checkout or machine, provision the verified Godot **4.7.2**
executable, follow the [native build setup](docs/engineering/native-builds.md),
and configure the local pins. The script discovers the checkout from its own
location, including paths with spaces. Missing resources refuse startup. The
old scripted launchers remain fixtures and do not deliver this entry.

## Controls

| Action | Keys |
| --- | --- |
| Move / jump | WASD / Space |
| Camera | Right-drag to orbit; wheel to zoom |
| Interact, gather, open a machine | E |
| Turn a fitted hand crank | Point at the crank and hold E; release to stop. |
| Inventory/build catalog | B; 1–8 select hotbar slots |
| Machine workbed transfer | Drag a carried input onto the workbed; drag workbed material anywhere onto the carried area to pick it up. F/R feed, P/U pick up where available. |
| Rotate a building | R during placement |
| Deconstruct | F, then select the part |
| Placement options | T; shown shortcuts depend on the selected part |
| Lock/nudge a component ghost | Alt; Alt+arrows; Alt+PageUp/PageDown |
| Foundation height / area placement | PageUp/PageDown / V |
| Cancel placement / worksite menu | Esc cancels placement; Esc again opens the menu. Tab/arrows and Enter navigate controls. |
| Save / reopen information | F5 / F9 |
| Developer conveniences | F3 |

Use local benches for fabrication. Craft a timber hand crank, select it in the
inventory and click an exposed input to fit it. Point at the fitted crank and
hold E to turn it. Release E to stop, or select Deconstruct [F] and click the
crank to detach it before switching to external power. Components and material
remain owned through stalls and recovery. Saves
use the selected native Store format;
scripted fixture saves are separate.

The isolated first slide shows its Auto workbed feed and outlet in the E menu.
Select or drag carried copper onto the workbed; clear a blocked route before
feeding or resuming its retained work.

## Build and verify

Bazel **8.4.2** is pinned in `.bazelversion`. The
[build recipe](docs/engineering/native-builds.md) covers toolchain/cache setup,
resource admission, hook configuration and publication. Select relevant native
package tests; the full non-host suite is:

```text
bazel test --build_tests_only --test_tag_filters=-host //native/...
```

Run it through the documented admitted, pinned invocation. Host-tagged tests
need their explicit fixtures. Install the repository hook with:

```bash
./scripts/install-hooks.sh
```

The hook validates the immutable staged tree and parses staged Godot changes;
it does not establish gameplay or human usability. Existing Python checks remain
active during the native tooling transition. Never wrap `git commit` in a
second admission command.

The [fixture guide](experiments/engine-environment/README.md) identifies retained
experimental scenes. Asset credits and licenses remain beside their sources.
The compact [Godot register](docs/engineering/godot-constraints.md) separates
engine constraints from adapter limitations and fixture assumptions.
