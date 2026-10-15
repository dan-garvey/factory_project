# Reversible 3D environment sandbox

Godot 4.7.2 standard editor, GDScript, Compatibility renderer. This is the
engine-coupled baseline authorized for environment research, not a production
stack decision or completed opening demo. [Comparison/evidence](../../docs/engineering/engine-environment.md).
No downloaded engine, cache, screenshot, account state or private Beads is stored
in this source directory. No external assets/plugins are required.

Use an explicitly installed official binary and an external owned artifact path:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/check.py \
  --godot /absolute/path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --prototype-artifacts /absolute/external/trial/runs --prototype-render
```

This runs ordinary tooling checks, then actual editor import, headless checks,
and real rendered scene checks/capture. Add `--staged` to validate the exact
candidate index with those same requested runtime stages. Without
`--prototype-render`, rendering is explicitly `not_run`. Without `--godot`, the
canonical command checks tooling only. Missing requested runtime, script errors,
missing reports/markers, failed assertions or mismatched scene quantities fail;
the runner never downloads an engine or silently skips requested tests.

The standalone command is `scripts/check_engine_environment.py --godot …
--artifacts … [--render]`, also under one outer `heavy` wrapper. Do not nest it
inside another resource wrapper. A new timestamped run directory retains copies
of the six sandbox source files, source hashes, isolated XDG/temp/cache state,
logs, assertions, stage durations and `result.json`; rendered runs add
`scene.json` and `scene.png`. Failures retain their evidence. The run requires
22 GiB free and the outer wrapper's memory floor; no engine-scale claim follows.
Each stage retains at most 8 MiB of combined output, including unterminated
lines. Its deadline also covers descendants holding the output pipe open. The
runner terminates its own process group on completion or failure, even after
the group leader exits. It checks the 384 MiB run artifact allowance during
execution; periodic checks can overshoot and are not a filesystem quota.
Processes that deliberately escape their group are outside this local probe's
contract. Synthetic tooling tests cover these limits without running Godot.

## Try the sandbox

After a successful run, use the reported directory as `factory_run` and the
installed executable as `factory_godot`:

```bash
python3 -B scripts/run_local.py heavy -- env \
  XDG_DATA_HOME="$factory_run/data" XDG_CONFIG_HOME="$factory_run/config" \
  XDG_CACHE_HOME="$factory_run/cache" TMPDIR="$factory_run/tmp" \
  "$factory_godot" --path "$factory_run/project" \
  --rendering-method gl_compatibility --audio-driver Dummy
```

Close the window to release admission before another heavy job. Select Collector,
Belt or Processor and click adjacent grid cells in +X order, then Connect ports;
Build example sends the same placement/connection commands for a known layout.
Run/pause and Step advance authoritative logical ticks; Take product retrieves
one existing output. Right-drag orbits; wheel zooms. Reset fixture is an explicit
between-run reset, **not recovery evidence**.

The neutral fixture has eight finite feed units, a two-feed/one-product recipe,
two logical processing ticks, one output slot and one carried part per machine.
Those are experiment values. The constructor also tests one-feed/one-product
without a second rule path; accepted opening content is tracked separately.
Fixed +X ports, top-down camera, temporary universal fixture drive and direct
local retrieval buttons are trial restrictions, not adopted game rules.

## Rule/consumer seam

`godot/model.gd` is a `RefCounted` with no scene nodes. Construct with
`new(initial_feed, world_context, recipe_input)`; call `command(intent)`,
`advance(ticks)` and `projection()`. Intents declare context/client/request and
place/connect/retrieve actions. Outcomes expose acceptance/reason/revision/order;
exact duplicates retain their outcome, and changed-payload reuse is refused.
Projections copy entities, links, physical stock locations, held/remaining work,
inventories and construction parts. Per-client product custody is not quest or
team progression credit. The scene submits commands and displays projections;
only the model advances material quantities or completes a recipe.

`scenario.gd` is a shared input schedule, not an oracle. `tests.gd` checks
independently stated outcomes/accounting. `view.gd` supplies real scene controls
and a smoke path through their signal handlers. Headless and scene receipts must
agree at first output, blocked output and final retrieval. A PNG is visual
evidence, not a substitute for these assertions or an actual user play session.

Wheel/shaft power, stopped editing/dismantling/refunds, opening capacity choices,
goals/teaching, network transport/client correction, checkpoints/restoration and
actual player collision are **not implemented here**. Chapter and platform
consumers extend/import this same owner under their tasks; no second model or
duplicated scene recipe implementation is intended. No native-core portability,
moving-world correctness, production scale or fun is established by this spike.
