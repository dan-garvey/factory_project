extends SceneTree
## Standalone headless consumer of the actual precision authority.
const Authority = preload("res://precision/authority.gd")
const Oracle = preload("res://precision/oracles.gd")
const METER = ["take_output", "feed_A", "feed_B"]
const RECOVERY = ["reject_X", "return_extra_A", "return_extra_B"]
var audit = Oracle.new()
var report := {"schema": 1, "mode": "headless_authority", "cases": {}, "events": []}
var output := ""
var current := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--precision-report="): output = argument.trim_prefix("--precision-report=")
	call_deferred("_run")

func _record(kind: String, event: Dictionary, state: Dictionary) -> void:
	audit.inspect(event.before, current + "/before_" + kind)
	audit.inspect(state, current + "/" + kind)
	if kind == "step" and not event.started.is_empty():
		audit.expect(event.started == {"A": 2, "B": 1, "X": 0}, current + ": exact full bill at capture")
	report.events.append({"case": current, "kind": kind, "event": event.duplicate(true), "state": state.duplicate(true)})

func _fresh(name: String):
	current = name
	var owner = Authority.new()
	owner.command_completed.connect(_on_command)
	owner.step_completed.connect(_on_step)
	return owner

func _on_command(event: Dictionary, state: Dictionary) -> void:
	_record("command", event, state)

func _on_step(event: Dictionary, state: Dictionary) -> void:
	_record("step", event, state)

func _prepare(owner, name: String) -> void:
	for kind in ["A", "B", "X"]:
		for _index in Oracle.CASES[name].input[kind]:
			audit.expect(owner.command({"action": "insert", "kind": kind}).accepted, name + ": actual source insertion")
	audit.blocked(owner.snapshot(), name)

func _manual(name: String) -> bool:
	var owner = _fresh("manual_" + name)
	_prepare(owner, name)
	var first: Dictionary = owner.snapshot()
	if name != "exact":
		for _index in 5: owner.advance()
		audit.expect(Oracle.physical(owner.snapshot()) == Oracle.physical(first), name + ": invalid state stalls without consumption")
		audit.blocked(owner.snapshot(), name)
	for intent in Oracle.CASES[name].fix:
		audit.expect(owner.command(intent).accepted, name + ": normal manual correction admitted")
	audit.corrected(owner.snapshot(), name)
	var corrected: Dictionary = owner.snapshot()
	for _index in 3: owner.advance()
	audit.one_product(owner.snapshot(), name)
	audit.expect(owner.command({"action": "collect"}).accepted, name + ": collect actual job1")
	audit.expect(not owner.command({"action": "collect"}).accepted and owner.snapshot().finished_jobs == [1], name + ": empty collection cannot duplicate product")
	report.cases[current] = {"before": first, "corrected": corrected, "final": owner.snapshot(), "same_owner": first.owner == owner.get_instance_id()}
	return audit.failures.is_empty()

func _automatic(name: String) -> bool:
	var owner = _fresh("automatic_" + name)
	_prepare(owner, name)
	var first: Dictionary = owner.snapshot()
	if name != "exact":
		for _index in 5: owner.advance()
		audit.blocked(owner.snapshot(), name)
	for row in METER: owner.command({"action": "wire", "row": row, "active": true})
	var meter_only: Dictionary = {}
	if name in ["surplus", "unlisted", "substitution"]:
		for _index in 8: owner.advance()
		meter_only = owner.snapshot()
		audit.expect(meter_only.output == 0 and meter_only.finished == 0 and meter_only.current_job == 0,
			name + ": metering alone cannot cure wrong/surplus stock")
	for row in RECOVERY: owner.command({"action": "wire", "row": row, "active": true})
	var pulses := 0
	while owner.snapshot().finished < 4 and pulses < 100 and audit.failures.is_empty():
		owner.advance()
		pulses += 1
	audit.all_products(owner.snapshot(), name)
	audit.expect(owner.get_instance_id() == first.owner, name + ": no reset/replacement during designed recovery")
	report.cases[current] = {"before": first, "meter_only": meter_only, "pulses": pulses, "final": owner.snapshot(), "same_owner": true}
	return audit.failures.is_empty()

func _phase() -> bool:
	var owner = _fresh("phase_backpressure")
	var original: Dictionary = owner.snapshot()
	var projection: Dictionary = owner.snapshot()
	projection.locations.source.A = 999
	projection.wiring.feed_A = true
	projection.finished_jobs.append(99)
	audit.expect(owner.snapshot() == original, "mutating a projection cannot change its owner")
	for invalid in [{"action": "insert", "kind": true}, {"action": "power", "active": 1},
		{"action": "wire", "row": "missing", "active": true}, {"action": "collect", "amount": 1}]:
		var before: Dictionary = owner.snapshot()
		audit.expect(not owner.command(invalid).accepted and Oracle.physical(owner.snapshot()) == Oracle.physical(before)
			and owner.snapshot().powered == before.powered, "malformed command refuses without moving material/changing power")
	for _batch in 2:
		for intent in [{"action": "insert", "kind": "A"}, {"action": "insert", "kind": "A"}, {"action": "insert", "kind": "B"}]: owner.command(intent)
		owner.advance()
		var captured: Dictionary = owner.snapshot()
		audit.expect(not owner.command({"action": "insert", "kind": "X"}).accepted
			and Oracle.physical(owner.snapshot()) == Oracle.physical(captured), "busy input refuses without taking X")
		owner.advance()
		owner.advance()
	var blocked: Dictionary = owner.snapshot()
	audit.expect(blocked.current_job == 2 and blocked.output_job == 1 and blocked.remaining == 0
		and blocked.condition == "output_full", "second captured job waits at full output")
	for _index in 5: owner.advance()
	audit.expect(Oracle.physical(owner.snapshot()) == Oracle.physical(blocked), "backpressure preserves actual held job and phase")
	owner.command({"action": "power", "active": false})
	for _index in 3: audit.expect(not owner.advance().advanced, "paused step cannot advance circuit/process")
	audit.expect(Oracle.physical(owner.snapshot()) == Oracle.physical(blocked), "paused phase unchanged")
	owner.command({"action": "collect"})
	owner.command({"action": "power", "active": true})
	owner.advance()
	audit.expect(owner.snapshot().output_job == 2 and owner.snapshot().finished_jobs == [1], "retained job publishes once after physical output removal")
	report.cases[current] = {"blocked": blocked, "final": owner.snapshot()}
	return audit.failures.is_empty()

func _run() -> void:
	for name in Oracle.CASES:
		if not _manual(name): _finish(); return
		if not _automatic(name): _finish(); return
	_phase()
	_finish()

func _finish() -> void:
	report.merge({"status": "pass" if audit.failures.is_empty() else "fail", "pid": OS.get_process_id(),
		"checks": audit.checks, "failures": audit.failures, "user_play": "not_assessed"})
	if not Oracle.publish(output, report):
		push_error("Cannot publish fresh owned precision report")
		quit(1)
		return
	print("PRECISION_CHECK_PASS" if audit.failures.is_empty() else "PRECISION_CHECK_FAIL")
	quit(0 if audit.failures.is_empty() else 1)
