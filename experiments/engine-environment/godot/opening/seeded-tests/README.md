# Bounded opening command sequences

Test-only native consumer of the existing `res://model.gd` opening rules and
`res://save-tests/checkpoint_file.gd` file boundary. No game, UI, model, codec,
network, helper or resource configuration is changed. This adds bounded
correctness coverage, not a new gameplay rule or exhaustive validation.

Run explicitly from the repository root with the existing verified binary:

```bash
python3 -B scripts/run_local.py heavy -- python3 -B scripts/check_opening_sequences.py \
  --godot /absolute/verified/Godot_v4.7.2-stable_linux.x86_64 \
  --sha256 verified-executable-sha256 \
  --artifacts /absolute/owned/seeded-opening-evidence
```

The runner downloads nothing. It copies eight named inputs to a new external
project, verifies the explicit executable hash and supported official version,
uses private profile/cache/tmp directories, and invokes only the headless probe.
It reuses the existing bounded supervisor: ten minute overall allowance,
128 MiB retained artifact-root allowance, 8 MiB logs and one engine at a time.
Resource admission/floors are unchanged. Source, runner and binary hashes,
commands, logs, progress, reports and good save files are retained on refusal.
Missing structured evidence fails even after a zero-exit pass marker.

Seeds are exactly `7, 29, 101, 2027`, with a test-only Park–Miller generator
(multiplier 48271, modulus 2147483647). Each trace declares its own fresh 16
blanks, one of each machine part and three shafts. There is no refill/reset
within a trace. Only canonical wheel/collector/belt/press cells `-1/0/1/2, z=0`
and deliberate invalid placements are generated; this is not arbitrary geometry.

Each seed first builds through real commands, captures two-tick held work,
stops power, refuses occupied dismantling, removes/rebuilds the empty wheel,
replays its retired placement and collides a request identity. It writes paused
partial work, resumes to an occupied outlet with retained held work, saves that,
and probes actual retrieval/replay plus foreign-context refusal. Then 64 fixed
seeded steps mix clock ticks, power, placement/removal, material/drive edits,
retrieval, repeats, request collisions and plain invalid intents. Four periodic
save points follow. Legal commands repair the finite kit/path and drain the
remaining material, bounded by 96 ticks, followed by a final save. There are at
most 256 recorded operations and 128 fresh caller IDs per seed; history remains
below the existing 1 MiB save cap. Generation never changes simulation randomness.

Independent observations check strictly typed nonnegative quantities, conserved
16 one-to-one items, actual inventory owners, one-item buffers, one-of-each
part/three-shaft ledgers, live unique identities/edges, and command outcome
relationships. Ordinary fresh refusals can append request/order metadata while
preserving physical facts. Duplicate/reused/foreign identities preserve the full
checkpoint. Successful retrieval must transfer actual output to its caller;
construction/power/link commands cannot move material or reset work.

Every Store operation writes a **new owned slot** and reads it into a fresh,
unrelated Model through the real decoder. Full checkpoint equality and one
common next tick are explicitly **same-implementation roundtrip/deterministic
continuation evidence**, not independent proof of the recipe or validator.
The trace continues on the restored Model; the original good file hashes must
remain unchanged. The probe never recreates a serializer or injects snapshots
into live state. Existing negative-codec/schema tests remain separate.

`sequences.json` retains complete command/outcome/state traces, save hashes and
per-seed totals. `evidence/progress.json` is written before and after operations;
the first failure stops with seed/RNG, exact prefix and before/after checkpoints.
No retry is a fix: preserve the first packet and report an implementation issue
to its owner rather than patching Model/Store here. The Python runner separately
audits every reported quantity/part/topology state, generated-step coverage,
actual good-file hashes and directed paused/blocked controls. Synthetic tooling
tests cover the report boundary without installing/running Godot.

These probes do not establish UI usability, human play, multiplayer correction,
hostile-decoder security, crash durability, cross-version saves, scale or
performance. The 16-item fixture does not prove lasting supply or automation
beyond its finite stock. [DESIGN](../../../../../DESIGN.md) remains the requirement
owner; ordinary opening/reopen/render evidence is unchanged.
