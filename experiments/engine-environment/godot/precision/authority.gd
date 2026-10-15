extends RefCounted
## Isolated later-control fixture: one real owner, used headlessly and by its UI.
const Circuit = preload("res://precision/controller.gd")
const INITIAL = {"A": 8, "B": 4, "X": 1}
const BILL = {"A": 2, "B": 1, "X": 0}
signal command_completed(outcome: Dictionary, state: Dictionary)
signal step_completed(event: Dictionary, state: Dictionary)
var _source: Dictionary = INITIAL.duplicate(true)
var _input: Dictionary = zero()
var _returns: Dictionary = zero()
var _reject: Dictionary = zero()
var _held: Dictionary = zero()
var _circuit = Circuit.new()
var _current_job := 0
var _next_job := 1
var _remaining := 0
var _output_job := 0
var _finished_jobs: Array[int] = []
var _powered := true
var _order := 0
var _revision := 0
var _ticks := 0

static func zero() -> Dictionary:
	return {"A": 0, "B": 0, "X": 0}

func condition() -> String:
	if not _powered: return "paused"
	if _current_job > 0:
		if _remaining > 0: return "processing"
		return "output_full" if _output_job > 0 else "ready_to_publish"
	if _input.X > 0: return "wrong_material"
	if _input.A > 2 or _input.B > 1: return "surplus"
	if _input == BILL: return "ready"
	if _input.A == 0 or _input.B == 0: return "missing"
	return "insufficient"

func snapshot() -> Dictionary:
	return {"schema": 1, "owner": get_instance_id(), "initial": INITIAL.duplicate(true),
		"locations": {"source": _source.duplicate(true), "input": _input.duplicate(true),
			"returns": _returns.duplicate(true), "reject": _reject.duplicate(true), "held": _held.duplicate(true)},
		"output": 1 if _output_job > 0 else 0, "output_job": _output_job,
		"finished": _finished_jobs.size(), "finished_jobs": _finished_jobs.duplicate(),
		"current_job": _current_job, "next_job": _next_job, "remaining": _remaining,
		"powered": _powered, "wiring": _circuit.wiring(), "condition": condition(),
		"order": _order, "revision": _revision, "ticks": _ticks}

func command(intent) -> Dictionary:
	return _admit(intent, "manual")

func _fields(intent: Dictionary, allowed: Array) -> bool:
	for field in intent:
		if not field is String or not field in allowed: return false
	return true

func _reply(intent, accepted: bool, reason: String, origin: String, before: Dictionary, move: Dictionary = {}) -> Dictionary:
	# Retain flat primitive command evidence; arbitrary objects are not a protocol.
	var recorded: Dictionary = {}
	if intent is Dictionary:
		for field in ["action", "kind", "row", "active"]:
			if intent.has(field):
				recorded[field] = intent[field] if typeof(intent[field]) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING] else "<invalid>"
	var result := {"accepted": accepted, "reason": reason, "origin": origin,
		"intent": recorded, "before": before, "move": move.duplicate(true), "order": _order, "revision": _revision}
	command_completed.emit(result.duplicate(true), snapshot())
	return result

func _admit(intent, origin: String) -> Dictionary:
	var before: Dictionary = snapshot()
	_order += 1
	if not intent is Dictionary or not intent.get("action") is String:
		return _reply(intent, false, "invalid_command", origin, before)
	var action: String = intent.action
	if action == "power":
		if not _fields(intent, ["action", "active"]) or not intent.get("active") is bool:
			return _reply(intent, false, "invalid_power", origin, before)
		if _powered != intent.active:
			_powered = intent.active
			_revision += 1
		return _reply(intent, true, "power_set", origin, before)
	if action == "wire":
		if not _fields(intent, ["action", "row", "active"]) or not intent.get("row") is String or not intent.row in Circuit.ROWS or not intent.get("active") is bool:
			return _reply(intent, false, "invalid_wire", origin, before)
		if _circuit.configure(intent.row, intent.active): _revision += 1
		return _reply(intent, true, "wire_set", origin, before)
	if action == "collect":
		if not _fields(intent, ["action"]): return _reply(intent, false, "invalid_collect", origin, before)
		if _output_job == 0: return _reply(intent, false, "empty_output", origin, before)
		var completed := _output_job
		_finished_jobs.append(completed)
		_output_job = 0
		_revision += 1
		return _reply(intent, true, "collected", origin, before,
			{"from": "output", "to": "finished", "kind": "C", "amount": 1, "job": completed})
	if not action in ["insert", "feed_return", "recover"]:
		return _reply(intent, false, "unknown_action", origin, before)
	if not _fields(intent, ["action", "kind"]) or not intent.get("kind") is String or not intent.kind in ["A", "B", "X"]:
		return _reply(intent, false, "invalid_kind", origin, before)
	if _current_job > 0:
		return _reply(intent, false, "chamber_busy", origin, before)
	var kind: String = intent.kind
	var source: Dictionary
	var target: Dictionary
	var source_name: String
	var target_name: String
	if action == "insert":
		source = _source
		target = _input
		source_name = "source"
		target_name = "input"
	elif action == "feed_return":
		if kind == "X": return _reply(intent, false, "invalid_return_kind", origin, before)
		source = _returns
		target = _input
		source_name = "returns"
		target_name = "input"
	else:
		source = _input
		target = _reject if kind == "X" else _returns
		source_name = "input"
		target_name = "reject" if kind == "X" else "returns"
	if source[kind] == 0:
		return _reply(intent, false, "empty_source", origin, before)
	source[kind] -= 1
	target[kind] += 1
	_revision += 1
	return _reply(intent, true, "transferred", origin, before,
		{"from": source_name, "to": target_name, "kind": kind, "amount": 1})

func advance() -> Dictionary:
	var before: Dictionary = snapshot()
	if not _powered:
		var paused := {"advanced": false, "reason": "paused", "tick": _ticks,
			"before": before, "transfer": {}, "started": {}, "completed_job": 0}
		step_completed.emit(paused.duplicate(true), snapshot())
		return paused
	_ticks += 1
	var proposal: Dictionary = _circuit.propose(snapshot())
	var transfer: Dictionary = {}
	if not proposal.is_empty(): transfer = _admit(proposal, "circuit")
	var started: Dictionary = {}
	var completed := 0
	if _current_job > 0:
		if _remaining > 0: _remaining -= 1
		if _remaining == 0 and _output_job == 0:
			completed = _current_job
			_output_job = _current_job
			_current_job = 0
			_held = zero()
	elif _input == BILL:
		# Capture the WHOLE exact chamber, never a subset of surplus/wrong stock.
		started = _input.duplicate(true)
		_held = _input.duplicate(true)
		_input = zero()
		_current_job = _next_job
		_next_job += 1
		_remaining = 2
	_revision += 1
	var result := {"advanced": true, "reason": condition(), "tick": _ticks,
		"before": before, "transfer": transfer, "started": started, "completed_job": completed}
	step_completed.emit(result.duplicate(true), snapshot())
	return result
