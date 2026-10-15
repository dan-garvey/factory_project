# Factory

An experimental 3D opening for a mechanically focused factory game. Place a
collector, belt, press and waterwheel; connect material and drive paths; turn
finite blanks into plates and explicitly confirm four collected products.
Placeholder geometry and a small fixed worksite keep this first feedback loop
bounded. This is not the complete chapter or a selected production stack.

## Try the opening

On Linux with a graphical display, use the separately provisioned, verified
Godot 4.7.2 stable executable. The launcher does not download an engine.
From the repository root:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/run_opening.py \
  --godot /absolute/path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --artifacts /absolute/owned/opening-sessions
```

The artifact root must be outside Git checkouts. Each launch creates a fresh
project copy, private profile and save slot there. Close the window to finish;
experimental sessions are capped at 30 minutes. Save with F5 and load with F9
within that run. To reopen a compatible saved worksite, add
`--resume /absolute/path/to/previous/session/worksite.factory` to the command.
The original is read only; the reopened world gets a new session and save slot.
See the [controls and construction example](experiments/engine-environment/godot/opening/README.md).

The gameplay UI is local. Controlled two-client fixtures exercise the same
authoritative model, not a multiplayer lobby or networked gameplay UI. Motion,
larger factories, durable cross-version saves and native-core portability remain
future work. Automated checks do not establish player understanding or enjoyment.

## Verify

The source-only tooling suite needs no engine or private tracker:

```bash
python3 -B scripts/run_local.py check -- python3 -B scripts/check.py
```

Add `--check --render` to the opening launch command for actual model/input and
save/load consumer checks with viewport captures. Use `--smoke` instead for
explicit scene startup only. These are distinct from the source-only suite and
from a real user session. Further bounded witnesses cover
[two stationary clients](experiments/engine-environment/godot/stationary-tests/README.md)
and [fresh-process save continuation](experiments/engine-environment/godot/save-tests/README.md).

## Project direction

[DESIGN.md](DESIGN.md) owns requirements and open decisions;
[ROADMAP.md](ROADMAP.md) records staged work. Contributors should read
[AGENTS.md](AGENTS.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
The [proposed delivery stages](docs/proposals/release-stage-map.md) compare two
release envelopes while retaining later requirements and unresolved choices.
