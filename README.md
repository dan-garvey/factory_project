# Factory

An experimental 3D opening for a mechanically focused factory game. Place a
collector, press and waterwheel; build a belt between shaft tiles and use
shafts, cogwheels, gearboxes and encased chain drives to transmit rotation;
turn finite blanks into plates and
explicitly confirm four collected products.
Placeholder geometry and a small fixed worksite keep this first feedback loop
bounded. This is not the complete chapter or a selected production stack.

The default opening controls a physical character and limits construction to
nearby targets. Walk with WASD, jump with Space, and use P to operate the nearby
waterwheel. Choose a building with the hotbar, use its ghost options to rotate or
adjust placement, press E to open a pointed machine, or press F and click a part
to deconstruct it. Right-drag orbits the following camera; its position grants no build
reach. The four-world-unit reach and movement tuning are provisional demo values.

The opening HUD keeps the current objective at the upper left, contextual
actions at the right, and the assignable build bar at the bottom. Every visible
button also has a keyboard route:

| Task | Keys |
| --- | --- |
| Build and inspect | `B` opens the catalog; `1`–`8` select a hotbar slot; `E` opens the pointed machine; `F` dismantles; `C` connects material; `Esc` cancels. |
| Assign a hotbar slot | In the catalog, `1`–`8` choose the destination, the displayed letter assigns a part, `Delete` clears, and `Esc` closes. Arrow keys, `Tab` and `Enter` also navigate the controls. |
| Mechanical options | `Alt+1`–`Alt+6` select the six transmission tools. During placement, `T` opens mechanical options, `X` cycles the axle, `Shift+X` cycles chain direction, `K` changes cog size, `Shift+PageUp`/`Shift+PageDown` adjust transmission height, and `Ctrl+Home` follows the pointed surface again. |
| Foundations and waterwheels | `PageUp`/`PageDown` change foundation or drive height; `Z` toggles access steps; `V` toggles two-corner area placement; `Shift+PageUp`/`Shift+PageDown` change waterwheel diameter when its size controls are shown; `R` rotates a building. |
| Worksite actions | `P` operates the nearby drive; `Ctrl+R` collects a selected plate; `Delete` dismantles the selection; `Ctrl+M` opens the selected material menu; `Ctrl+L` opens loose-material pickup; `Ctrl+Enter` confirms four plates; `Ctrl+D` toggles details; `F5` saves and `F9` shows how to reopen the save. |
| Help and shared sessions | `H` opens or closes Help. `Left`/`Right` change lesson, `Space` advances the example, `Enter` collects its plate, `Backspace` replays, and `Home` recenters. In a shared session, `Ctrl+J` reconnects and `Ctrl+Shift+J` disconnects. Menu choices use arrow keys and `Enter`; `Esc` closes the menu. |

Early development prioritizes fixed/stationary contraptions and subfactories.
Godot use is accepted with explicit [framework constraints](docs/engineering/godot-constraints.md),
not engine defaults treated as game rules. A [continuing research catalogue](docs/research/README.md)
tracks factory-builder and engineering-puzzle inspiration separately from adopted mechanics.

## Try the opening

The current offline scene uses one C++ World through a thin Godot bridge. Follow
the [native build, resource capture and human-entry instructions](native/factory-godot-world/README.md#build-and-consume).
Missing native resources fail startup. The shared server can explicitly select
the same owner with `--native-world`; the historical Python shared launcher keeps
its scripted profile. Neither format automatically migrates the other's saves.

The Python offline command below is retained documentation of the earlier
scripted profile. Its fixed roster does not deliver the new bridge or library,
so it is not the current native offline entry. The associated scripted tests
retain their original revision and evidence scope.

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
experimental sessions are capped at 30 minutes. F5 saves the current worksite;
F9 explains reopening rather than replacing the live physical world. Close the
session, then add
`--resume /absolute/path/to/previous/session/worksite.factory` to the command.
The original is read only; the reopened world gets a new session and save slot.
Native bodies must be realized at the saved positions before building is
available; failed restoration never falls back to a fresh world or safe spawn.
Old unrestricted saves require the explicit `--legacy-fixture` regression
profile, not the normal physical opening. No automatic migration is supplied.
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
offline launcher above retains its own F5 save and restart-based reopen controls.
Physical saves require the same declared roster: reopen a P-only shared save
with `--clients 1`, or a P/Q save with the default two clients. Offline P and
shared P or P/Q are fixture profiles, not an account or roster-migration system.
Without `--resume`, each command starts a fresh 16-blank worksite.
Closing either window ends the whole shared session; Ctrl-C
also stops it. The default session lasts at most 15 minutes. See the
[shared launch controls and limits](experiments/engine-environment/godot/opening-session/README.md#normal-shared-play).

The shared UI is a trusted same-host prototype without a lobby, accounts or
remote hosting. Host checkpoints cover orderly stops, rather than crashes or
power loss; clients cannot roll back the live server. Larger factories,
durable cross-version saves and native-core portability remain future work.
Construction is still a single ground grid with fixed machine boxes; this does
not implement the intended stacked 3D factory. Actor-actor collision, pushing
and live physical-world replacement are unsupported adapter cases, not chosen
game rules. The shared finite starter kit is a fixture, not proof of a final
personal-carried-parts or construction-delivery policy. Automated checks do not
establish player understanding or enjoyment.

## Verify

The C++ material core uses the pinned [Bazel build and local
caches](docs/engineering/native-builds.md). The offline native bridge uses that
authority; the shared Session and installed commit hook have separate migrations.
Its automated headless consumer covers actual body admission, running recovery,
rebuilding, original request replay and typed save/reopen. It does not establish
desktop input, shared adoption or human play.

The source-only tooling suite needs no engine or private tracker:

```bash
python3 -B scripts/run_local.py check -- python3 -B scripts/check.py
```

For the historical scripted revisions, `--check --render` on the offline launcher provided bounded physical
movement/reach and fresh-process save/reopen checks with viewport captures.
They do not prove P/Q host-file reopening; same-server disconnect/rejoin is also
different from starting a new host. The separate normal-launcher consumer is
`scripts/check_physical_shared_resume.py`; its evidence must be reviewed for
that specific claim. Use `--smoke` instead for
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
