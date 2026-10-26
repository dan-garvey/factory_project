# Focused Godot fixture runner

`factory-godot-fixture` runs one headless project script through the existing
native build-support supervisor. It requires the pinned Godot executable, an
exact complete PASS line, exit zero, and a retained log without `SCRIPT ERROR:`,
`ERROR:`, parse/compile errors, or failed script loads. A partial PASS count is
insufficient. The supervisor retains combined output in a fresh bounded log and
keeps its existing process cleanup and resource checks. This command is an
opt-in focused fixture entry point, not another commit or landing gate.

Import project resources before a normal fixture run. A missing import sidecar
is a setup failure: keep its log and import the unchanged project before trying
the intended component check. A zero Godot exit does not override a script-load
error or a partial PASS line.

`parts_view_check.gd` runs its default parts display suite with no user arguments,
or one named `--...-only` suite. An unknown or repeated selector exits 2 before
any suite starts; capture paths are accepted only with their corresponding
suite. Select the exact completion line emitted by that suite when using this
runner. The default suite emits an `OPENING_PARTS_VIEW_PASS` count, while
`--buttons-only` emits its JSON status and check count. These are
scripted view checks, not native gameplay, rendered, or human-play evidence.

`machine_detail_check.gd` likewise runs its default geometry suite only with
no user arguments. Select one direct check mode at a time; the retired
one-cell conveyor selectors deliberately fail. Asset preparation takes its
named `--prepare-...` selector first, followed by that case's required path
arguments. `--render-buildable-resources` may combine its declared
`--...-check` prerequisites; `--foot-seat-geometry` applies only to
`--wheel-foot-seats-only`. Unknown, duplicate, conflicting or orphan options
exit 2 before any case runs. Existing suite-specific completion and exit
contracts remain; resource renders are isolated passive evidence.

`guidance_cue_check.gd --mouse-look-only` emits `OPENING_MOUSE_LOOK_PASS 15`.
It checks first-person capture policy, relative camera motion, menu release and
held-key refusal in a headless view. It does not establish actual OS focus or
human mouse control.

Build `//native/godot-fixture:factory-godot-fixture` with the verified Bazel
8.4.2 toolchain described in [native builds](../../docs/engineering/native-builds.md).
Then run from a linked checkout, substituting existing absolute paths, the
verified lowercase SHA-256, an owned private artifact directory, and the full
PASS line for that exact fixture revision:

```bash
FACTORY_LOCAL="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources/factory-local"
FACTORY_ADMISSION="$(git rev-parse --path-format=absolute --git-common-dir)/factory-local-resources"
"$FACTORY_LOCAL" --root "$PWD" heavy --inherit-permits -- \
  /absolute/verified/factory-godot-fixture \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --godot-sha256 VERIFIED_LOWERCASE_SHA256 \
  --project "$PWD/experiments/engine-environment/godot" \
  --script res://opening/native_transmission_view_check.gd \
  --pass-line 'NATIVE_TRANSMISSION_VIEW_PASS EXPECTED_EXACT_COUNT' \
  --artifacts /absolute/owned/private-fixture-artifacts \
  --log /absolute/owned/private-fixture-artifacts/fresh-run.log \
  --admission "$FACTORY_ADMISSION"
```

Create the artifact directory before the command with owner-only permissions
(`install -d -m 700`). `--seconds` may set a deadline from 1 to 300 seconds;
the default is 180. Arguments after `--` reach the Godot fixture as user
arguments. The executable limits its log to 2 MiB and its owned artifact family
to 128 MiB. It never accepts or prints the log contents as a PASS receipt.

## Chapter 1 scene event selection

The following `native_adapter_check.gd` selections exercise Godot event routing
through the ordinary arrival scene and assert native outcomes. Run each with
`factory-godot-fixture` above, setting `--pass-line` to the exact line shown and
passing the listed arguments after `--`. Give every run a fresh `--log` and
`--native-check-output` inside an owner-only artifact family. The runner rejects
engine errors, nonzero exits, missing completion lines and oversized logs. The
fixture rejects a selected route if its required actions were skipped.

| Selection | Godot arguments | Exact completion line | Maximum time |
| --- | --- | --- | --- |
| First plate placement and focus guard | `--native-check-mode=arrival-first-plate --event-route-pointer --native-check-output=FRESH_RESULT` | `CHAPTER 1 SCENE EVENTS PASS: arrival-first-plate` | 180 seconds |
| Narrow channel custody and blocked gap | `--native-check-mode=arrival-channel-small --event-route-loose --resume-input=BROAD_CUT_WORKSITE --save-slot=FRESH_WORKSITE --native-check-output=FRESH_RESULT` | `CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small` | 300 seconds |
| Fresh-process recovery | `--native-check-mode=arrival-channel-small-resume --event-route-loose --resume-input=PREVIOUS_WORKSITE --save-slot=FRESH_WORKSITE --native-check-prior=PREVIOUS_RESULT --native-check-output=FRESH_RESULT` | `CHAPTER 1 SCENE EVENTS PASS: arrival-channel-small-resume` | 180 seconds |

`BROAD_CUT_WORKSITE` is the retained passing output of
`arrival-broad-cut-resume` from the same native revision. Feed the narrow
channel result and save into the fresh-process recovery case; it checks exact
placed parts, dropped items, carried cargo and conserved mass before keyboard
pickup. The first case uses pointer events for two fitted placements and checks
that a click while the Escape menu is open cannot place a part. The second
uses Ctrl+L, popup focus, arrow keys and Enter for three custody attempts,
including refusal across a missing rail. The third uses the same keyboard
path to pick up the restored plate. Scene tests still substitute scripted
actor movement and choices; they do not establish human play or desktop input.
