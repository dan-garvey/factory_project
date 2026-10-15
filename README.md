# Factory

An experimental 3D opening for a mechanically focused factory game. Place a
collector, belt, press and waterwheel; connect material and drive paths; turn
finite blanks into plates and explicitly confirm four collected products.
Placeholder geometry and a small fixed worksite keep this first feedback loop
bounded. This is not the complete chapter or a selected production stack.

The next required increment is a controlled physical character with nearby
construction; the current free-camera opening does **not** implement that yet.
Early development prioritizes fixed/stationary contraptions and subfactories.
Godot use is accepted with explicit [framework constraints](docs/engineering/godot-constraints.md),
not engine defaults treated as game rules. A [continuing research catalogue](docs/research/README.md)
tracks factory-builder and engineering-puzzle inspiration separately from adopted mechanics.

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

To play the shared opening on this computer, use the same verified executable
and its SHA256:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/run_shared_opening.py \
  --godot /absolute/path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 verified-lowercase-executable-sha256 \
  --artifacts /absolute/owned/shared-opening-sessions
```

This opens ordinary P and Q game windows connected to one live loopback server.
Add `--clients 1` for a single window. Both participants use the same finite
starter kit, while collected plates and the four-plate confirmation belong to
the individual participant. Client Save/Load is unavailable. Add
`--save-on-close` to save the whole host worksite when the session ends; the
console prints its new `worksite.factory` path. To reopen it, add
`--resume /absolute/path/to/prior/shared-run/worksite.factory`. The original
stays read only, and the resumed host saves to a fresh output on close. The
offline launcher above retains its individual F5/F9 controls.
Without `--resume`, each command starts a fresh 16-blank worksite.
Closing either window ends the whole shared session; Ctrl-C
also stops it. The default session lasts at most 15 minutes. See the
[shared launch controls and limits](experiments/engine-environment/godot/opening-session/README.md#normal-shared-play).

The shared UI is a trusted same-host prototype without a lobby, accounts or
remote hosting. Host checkpoints cover orderly stops, rather than crashes or
power loss; clients cannot roll back the live server. Larger factories,
durable cross-version saves and native-core
portability remain future work. Automated checks do not establish player
understanding or enjoyment.

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
