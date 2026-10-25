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
