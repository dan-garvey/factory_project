extends Node
## Copied-only check autoload: actual ordinary scene, real input, no second owner.
const Oracle = preload("res://precision/oracles.gd")
var audit = Oracle.new()
var report := {"schema": 1, "mode": "ordinary_scene_input", "cases": {}, "events": [], "captures": []}
var output := ""
var captures := ""
var current := ""
var scene

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--precision-report="): output = argument.trim_prefix("--precision-report=")
		elif argument.begins_with("--precision-captures="): captures = argument.trim_prefix("--precision-captures=")
	call_deferred("_run")

func _record(kind: String, event: Dictionary, state: Dictionary) -> void:
	audit.inspect(event.before, current + "/before_" + kind)
	audit.inspect(state, current + "/" + kind)
	audit.expect(state.owner == scene.model.get_instance_id(), "ordinary view observes its sole actual authority")
	if kind == "step" and not event.started.is_empty():
		audit.expect(event.started == {"A": 2, "B": 1, "X": 0}, "actual scene captured only the whole exact bill")
	report.events.append({"case": current, "kind": kind, "event": event.duplicate(true), "state": state.duplicate(true)})

func _key(code: Key) -> bool:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	Input.parse_input_event(release)
	await get_tree().process_frame
	return audit.failures.is_empty()

func _input_command(intent: Dictionary) -> bool:
	var code: Key
	if intent.action == "insert":
		code = {"A": KEY_A, "B": KEY_B, "X": KEY_X}[intent.kind]
	elif intent.action == "recover":
		code = {"A": KEY_1, "B": KEY_2, "X": KEY_3}[intent.kind]
	else:
		audit.expect(false, "unsupported check input; never substitute direct model mutation")
		return false
	return await _key(code)

func _checkbox_case() -> bool:
	current = "circuit_checkbox"
	var first: Dictionary = scene.model.snapshot()
	var control: CheckButton = scene._rows["reject_X"]
	var position_value: Vector2 = control.get_global_rect().get_center()
	for active in [true, false]:
		var motion := InputEventMouseMotion.new()
		motion.position = position_value
		motion.global_position = position_value
		Input.parse_input_event(motion)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = position_value
			event.global_position = position_value
			event.button_index = MOUSE_BUTTON_LEFT
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			event.pressed = pressed
			Input.parse_input_event(event)
			await get_tree().process_frame
		audit.expect(scene.model.snapshot().wiring.reject_X == active, "actual individual sensor row toggles through GUI input")
		audit.expect(Oracle.physical(scene.model.snapshot()) == Oracle.physical(first), "wiring transfers no phantom material")
	report.cases[current] = {"before": first, "final": scene.model.snapshot()}
	return audit.failures.is_empty()

func _prepare(name: String, mode: String) -> Dictionary:
	current = mode + "_" + name
	if not await _key(KEY_BACKSPACE): return {}
	for kind in ["A", "B", "X"]:
		for _index in Oracle.CASES[name].input[kind]:
			if not await _input_command({"action": "insert", "kind": kind}): return {}
	var state: Dictionary = scene.model.snapshot()
	audit.blocked(state, name)
	return state

func _manual(name: String) -> bool:
	var first: Dictionary = await _prepare(name, "manual")
	if first.is_empty() or not audit.failures.is_empty(): return false
	if name != "exact":
		for _index in 5:
			if not await _key(KEY_N): return false
		audit.expect(Oracle.physical(scene.model.snapshot()) == Oracle.physical(first), name + ": real-input invalid batch stays retained")
		audit.blocked(scene.model.snapshot(), name)
		if name == "substitution": await _capture("wrong-retained")
	for intent in Oracle.CASES[name].fix:
		if not await _input_command(intent): return false
	audit.corrected(scene.model.snapshot(), name)
	var corrected: Dictionary = scene.model.snapshot()
	for _index in 3:
		if not await _key(KEY_N): return false
	audit.one_product(scene.model.snapshot(), name)
	if not await _key(KEY_C): return false
	if not await _key(KEY_C): return false
	audit.expect(scene.model.snapshot().finished_jobs == [1], name + ": repeated empty collect cannot duplicate")
	audit.expect(scene.model.get_instance_id() == first.owner, name + ": manual repair did not reset/replace owner")
	report.cases[current] = {"before": first, "corrected": corrected, "final": scene.model.snapshot(), "same_owner": true}
	return audit.failures.is_empty()

func _automatic(name: String) -> bool:
	var first: Dictionary = await _prepare(name, "automatic")
	if first.is_empty() or not audit.failures.is_empty(): return false
	if name != "exact":
		for _index in 5:
			if not await _key(KEY_N): return false
		audit.blocked(scene.model.snapshot(), name)
	if not await _key(KEY_M): return false
	var meter_only: Dictionary = {}
	if name in ["surplus", "unlisted", "substitution"]:
		for _index in 8:
			if not await _key(KEY_N): return false
		meter_only = scene.model.snapshot()
		audit.expect(meter_only.output == 0 and meter_only.finished == 0 and meter_only.current_job == 0,
			name + ": actual meter rows alone cannot repair wrong/surplus input")
	if not await _key(KEY_R): return false
	if not await _key(KEY_T): return false
	var deadline := Time.get_ticks_msec() + 10000
	while scene.model.snapshot().finished < 4 and audit.failures.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not await _key(KEY_T): return false
	audit.all_products(scene.model.snapshot(), name)
	audit.expect(scene.model.get_instance_id() == first.owner, name + ": designed recovery kept same real owner")
	report.cases[current] = {"before": first, "meter_only": meter_only, "final": scene.model.snapshot(), "same_owner": true}
	if name == "substitution": await _capture("automatic-four-products")
	return audit.failures.is_empty()

func _phase() -> bool:
	current = "phase_backpressure"
	if not await _key(KEY_BACKSPACE): return false
	for _batch in 2:
		for code in [KEY_A, KEY_A, KEY_B, KEY_N]:
			if not await _key(code): return false
		var before: Dictionary = scene.model.snapshot()
		if not await _key(KEY_X): return false
		audit.expect(Oracle.physical(scene.model.snapshot()) == Oracle.physical(before), "real busy insertion retains source X")
		for _index in 2:
			if not await _key(KEY_N): return false
	var blocked: Dictionary = scene.model.snapshot()
	audit.expect(blocked.current_job == 2 and blocked.output_job == 1 and blocked.remaining == 0
		and blocked.condition == "output_full", "actual view retains second job behind output1")
	for _index in 5:
		if not await _key(KEY_N): return false
	audit.expect(Oracle.physical(scene.model.snapshot()) == Oracle.physical(blocked), "real output blockage retains phase/quantities")
	if not await _key(KEY_SPACE): return false
	for _index in 3:
		if not await _key(KEY_N): return false
	audit.expect(Oracle.physical(scene.model.snapshot()) == Oracle.physical(blocked), "real pause retains blocked job")
	await _capture("paused-held-output")
	for code in [KEY_C, KEY_SPACE, KEY_N]:
		if not await _key(code): return false
	audit.expect(scene.model.snapshot().output_job == 2 and scene.model.snapshot().finished_jobs == [1], "same held job publishes after actual output removal")
	report.cases[current] = {"blocked": blocked, "final": scene.model.snapshot()}
	return audit.failures.is_empty()

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := captures.path_join(name + ".png")
	audit.expect(get_viewport().get_texture().get_image().save_png(path) == OK, "actual viewport capture")
	var state: Dictionary = scene.model.snapshot()
	var visible: Dictionary = {}
	for location in ["source", "input", "held", "returns", "reject"]:
		visible[location] = {}
		for kind in ["A", "B", "X"]:
			var count := 0
			for item in scene._pools[location][kind]:
				if item.is_visible_in_tree(): count += 1
			visible[location][kind] = count
			audit.expect(count == state.locations[location][kind], "actual visible token count equals real owner " + location + "/" + kind)
	for location in ["output", "finished"]:
		var count := 0
		for item in scene._pools[location]:
			if item.is_visible_in_tree(): count += 1
		visible[location] = count
		audit.expect(count == state[location], "actual visible C count equals real owner " + location)
	report.captures.append({"name": name, "path": path, "state": state,
		"visible": visible, "phase_text": scene._status.text})

func _run() -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var candidate = get_tree().current_scene
		if candidate != null and candidate.is_node_ready() and candidate.get("model") != null: break
	scene = get_tree().current_scene
	if not audit.expect(scene != null and scene.scene_file_path == "res://precision/main.tscn", "ordinary positional scene entry"):
		_finish(); return
	audit.expect(scene.get_script().resource_path == "res://precision/view.gd"
		and scene.model.get_script().resource_path == "res://precision/authority.gd", "actual view and real shared authority")
	report.merge({"scene": scene.scene_file_path, "view_script": scene.get_script().resource_path,
		"authority_script": scene.model.get_script().resource_path})
	scene.observed.connect(_record)
	if not await _checkbox_case(): _finish(); return
	for name in Oracle.CASES:
		if not await _manual(name): _finish(); return
		if not await _automatic(name): _finish(); return
	await _phase()
	_finish()

func _finish() -> void:
	report.merge({"status": "pass" if audit.failures.is_empty() else "fail", "pid": OS.get_process_id(),
		"checks": audit.checks, "failures": audit.failures, "user_play": "not_assessed"})
	if not Oracle.publish(output, report):
		push_error("Cannot publish fresh owned ordinary precision report")
		get_tree().quit(1)
		return
	print("PRECISION_CHECK_PASS" if audit.failures.is_empty() else "PRECISION_CHECK_FAIL")
	get_tree().quit(0 if audit.failures.is_empty() else 1)
