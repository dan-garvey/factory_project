# Mechanical workshop

An optional local experiment after the basic opening. You place the tool mounts,
output gear, optional idler and training stop on the board, then operate the rig.
It starts empty. There is no successful-layout selector or supplied built machine.

The complete heads move through actual native physics bodies. The unchanged
[mechanics authority](../mechanics/README.md) owns source/branch phase, ideal
gearing, native linear obstruction, connected stall, coupling and coherent
completion. The workshop subclass supplies only bounded construction/configuration,
mount/stop positions and completed-layout publication. Its two uninstalled native
bodies are explicitly parked outside the board and hidden; they cannot run until
the required parts are installed. Their identities survive normal operation and
recovery. The opening Model, Store, shared session and project startup stay separate.

**Work encounters are non-consuming contacts, not produced items.** The blue
region counts a real tool/Area3D encounter. No material, inventory, recipe,
harvest, unlock, lasting supply or workshop save is simulated.

## Build and explore

Choose a piece, then click a square. Coordinates are printed on the board; one
unit is a fixture construction choice, not the game's selected voxel size.

| Key | Piece / allowed construction positions |
| --- | --- |
| 1 | B head: `(-1,0)` or `(0,0)` |
| 2 | U head: `(0,3)` or `(0,4)` |
| 3 / 4 | 20 / 40 tooth output on peg `(-3,-2)` |
| 5 | Optional idler on peg `(-4,-2)` |
| 6 | Stop: `(1,0)`, `(2,0)`, `(1,3)` or `(2,3)` |
| X | Pick up the piece on a square |

Clicking another valid mount moves that existing head; choosing another output
swaps the gear. Configuration pieces are workshop tools, not debits from the
opening's stock. The gear tiles are explicitly schematic ideal transmission
inputs, not a general editable gear network or native tooth-contact simulation.
They determine the inherited signed ratio and therefore actual tool travel.

Space starts/pauses the source. N advances one step. **Repeat fixed cycle** runs
steps at the existing visual fixture cadence. K opens/engages the B coupling;
U remains directly driven. O retracts/deploys an already mounted stop while
paused. R starts a visibly fresh empty workshop. Right-drag orbits, wheel zooms,
WASD pans and Home recenters.

Construction is allowed only before the source has advanced and while stopped.
Stopping later or returning to the initial position does not enable rebuilding.
Use R for another arrangement. This is a declared setup-only limit, not a final
stopped/docked construction policy. Retracting the mounted stop is its ordinary
lever control, not editing a machine in motion.

Some useful experiments:

- B on the left mount cannot reach the blue region; the center mount can. Its
  actual native center travel changes with placement.
- With a 40-tooth output, compare the first eight steps with and without an
  idler. Reversed drive goes left in that matched window. It can still reach the
  same region later in a full reciprocating cycle; reverse is not a permanent
  no-work rule. A 20-tooth output changes when contact happens.
- A stop at x=1 blocks B before the work zone; x=2 allows an encounter before a
  later actual stall. The source and both connected branches retain their prior
  phases instead of partially moving through the stop.
- Put the stop on lane z=3. U on z=3 collides; U on z=4 has genuine native
  clearance. Opening only B's coupling cannot isolate a blockage in U.
- With B blocked, open K. U/source can continue while B stays retained. Pause
  when the input and B phases align modulo a revolution, retract the stop, engage
  K and resume. For positive 20:40 gearing, 32 isolated steps restore alignment
  and complete a U cycle. No body identity or phase is reset during recovery.

The **K shaft marks** show the schematic geared input and retained B phase in
degrees modulo a revolution, plus their shortest signed offset. Opening K lets
the input mark continue while B stays retained. Use the marks to choose when to
pause and try engaging K. They wait for completed native state and show no
numbers while an update is pending. The existing coupling command still decides
engagement; a rounded zero is a display, not an additional admission rule.

These outcomes use the fixed rig's actual geometry: sliders `0.55×0.8×0.8` at
height 0.75, stop `0.35×1.5×1.1`, work Area3D `0.6×1.2×1.2` centered at
`(1.6,0.75,0)`. Its minimum x=1.3 exceeds the left mount's maximum body edge 1.275.
U/stop halfwidths sum 0.95, so moving U one lane gives 0.05 clearance. Eight
positive 20:40 steps give B phase pi/2; 32 give one complete B cycle without
rounding operating poses onto the grid. This is linear/static clearance only.

## Run and verify

Use the existing verified binary and exact SHA256 pin. The runner creates a
fresh external copied project/profile and preserves bounded evidence:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/run_workshop.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 VERIFIED_LOWERCASE_SHA256 --artifacts /absolute/owned/workshop
```

The normal entry is the actual positional `res://workshop/main.tscn`, not a test
controller. It ends when its window closes or its bounded session allowance
expires; the default is 900 seconds, with an explicit 1–1700 second selection. Do not
leave an ordinary session unattended. No engine is installed or downloaded.

Add `--check --render` for automated real key/grid/K-button/camera input plus native
RID observations and actual viewport capture. The independent Python oracle
checks phase deltas, exact box/stop geometry, early versus full-cycle direction,
contact timing, clear/blocked native outcomes and retained recovery identities.
Headless and rendered actual-input consumers must agree, excluding process-local
instance IDs. This is capability coverage, not proof of a historical defect.

`--smoke` instead observes the actual normal scene with a disclosed read-only
copied-project autoload and then exits. Original, post-import and instrumented
config/observer hashes are recorded separately. It cannot combine with `--check`;
`--render` requires `--check`. There is no default project or offline save change.

All modes use one existing engine at a time through the unchanged bounded helper,
30 minutes total, 256 MiB aggregate retained artifact allowance and 8 MiB per log.
Source/staged compilation is separate from these runtime/input results. Failure
receipts/logs remain; retrying an unexpected failure is not acceptance.

This is not arbitrary assemblies, angular/moving-moving collision, passengers,
injury, independent pushing, moving harvest/transfer, workshop networking/save,
game-scale/performance, a production engine decision or actual human-play evidence.
