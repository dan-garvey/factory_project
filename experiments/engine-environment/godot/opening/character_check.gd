extends SceneTree
## Ordinary offline input consumer. Fixed production ticks expose retained work;
## character motion always uses natural native physics, never a pose setter.
var scene
var failures: Array[String] = []
var cuts: Array = []
var admissions: Array = []
var first_native: Dictionary = {}
var checks := 0
var output := ""
var capture := ""
var resumed := false
var captured_request := ""
var wall_save := ""
var wall_checkpoint: Dictionary = {}
var negative_save := ""
var negative_fixture: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame
	await process_frame

func _edge(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _key(code: Key) -> void:
	await _edge(code, true)
	await _edge(code, false)

func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _cell(x: int, z := 0) -> void:
	await _click(scene.camera.unproject_position(Vector3(x * scene.PITCH, 0.08, z * scene.PITCH)))
	_capture_admission()

func _capture_admission() -> void:
	var key: String = JSON.stringify([scene.client, scene.request_namespace + str(scene.request_sequence)])
	if key != captured_request and scene.model.requests.has(key):
		captured_request = key
		var record: Dictionary = scene.model.requests[key].duplicate(true)
		var result: Dictionary = record.result
		if result.has("reach"):
			record["native"] = scene.actor_world.diagnostics(result.reach.actor, result.reach.native_epoch)
		if result.has("blockers"):
			record["blocker_native"] = {}
			for blocker in result.blockers:
				record.blocker_native[blocker.actor] = scene.actor_world.diagnostics(blocker.actor, blocker.native_epoch)
		admissions.append(record)

func _last() -> Dictionary:
	return admissions[-1].result if not admissions.is_empty() else {}

func _cut(label: String) -> Dictionary:
	var state: Dictionary = scene.model.projection()
	var actor: Dictionary = state.actors.P
	var native: Dictionary = scene.actor_world.diagnostics("P", actor.native_epoch)
	var value := {"label": label, "state": state, "native": native,
		"camera": [scene.camera.position.x, scene.camera.position.y, scene.camera.position.z],
		"yaw": scene.orbit_yaw, "distance": scene.distance, "message": scene.status_label.text,
		"held_keys": scene.character_presenter.held_keys.keys(), "physics_frame": Engine.get_physics_frames()}
	cuts.append(value)
	_check(native.get("available", false), label + ": exact native observation retained")
	if native.get("available", false):
		_check(native.sample.position == actor.position and native.sample.native_epoch == actor.native_epoch and native.sample.registered,
			label + ": projection matches actual registered native cut")
		_check(native.sample.space == native.sample.expected_space and native.sample.rid > 0 and native.sample.shape_rid > 0,
			label + ": actual body and shape in declared native world")
	return value

func _orbit_to_zero() -> void:
	var edge := InputEventMouseButton.new()
	edge.button_index = MOUSE_BUTTON_RIGHT
	edge.pressed = true
	Input.parse_input_event(edge)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(scene.orbit_yaw / 0.007, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(motion)
	await process_frame
	edge = edge.duplicate()
	edge.pressed = false
	Input.parse_input_event(edge)
	await process_frame
	_check(absf(scene.orbit_yaw) < 0.00001, "Ordinary orbit sets a known camera-relative walking direction")

func _zoom_out() -> void:
	# Keep target clicks in the unobscured world between the actual side panels.
	for _step in range(10):
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.position = Vector2(640, 400)
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
	_check(scene.distance == 24.0, "Ordinary zoom exposes far target without moving actor")

func _same_seed(sample: Dictionary) -> bool:
	if not sample.get("registered", false):
		return false
	for axis in range(3):
		if absf(float(sample.position[axis]) - float(sample.seed[axis])) > 0.00001:
			return false
	return true

func _walk(x: float, z: float) -> void:
	# Closed-loop ordinary key input from confirmed poses. This chooses the
	# player's route; it never changes a body or supplies position to authority.
	var held: Array = []
	var reached := false
	for _frame in range(360):
		var at: Array = scene.model.projection().actors.P.position
		var dx := x - float(at[0])
		var dz := z - float(at[2])
		if absf(dx) < 0.09 and absf(dz) < 0.09:
			reached = true
			break
		var wanted: Array = []
		if absf(dx) >= 0.09:
			wanted.append(KEY_D if dx > 0 else KEY_A)
		if absf(dz) >= 0.09:
			wanted.append(KEY_S if dz > 0 else KEY_W)
		for code in held:
			if not wanted.has(code):
				await _edge(code, false)
		for code in wanted:
			if not held.has(code):
				await _edge(code, true)
		held = wanted
		await physics_frame
	for code in held:
		await _edge(code, false)
	await _frames(3)
	_check(reached, "Ordinary walk reaches waypoint %s" % str([x, z]))

func _link(code: Key, a: int, b: int) -> void:
	await _key(code)
	await _cell(a)
	await _cell(b)
	_check(_last().get("accepted", false), "Both real connection endpoints admitted")

func _ledger() -> void:
	var state: Dictionary = scene.model.projection()
	var stock: Dictionary = state.stock
	_check(stock.source + stock.collector + stock.belt + stock.input + stock.held + stock.output + stock.player == 16,
		"Literal finite16 ledger conserved")

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character-report="): output = argument.trim_prefix("--character-report=")
		elif argument.begins_with("--capture="): capture = argument.trim_prefix("--capture=")
		elif argument.begins_with("--resume-input="): resumed = true
		elif argument.begins_with("--wall-save="): wall_save = argument.trim_prefix("--wall-save=")
		elif argument.begins_with("--negative-save="): negative_save = argument.trim_prefix("--negative-save=")
	root.size = Vector2i(1280, 800)
	scene = load("res://opening/opening.tscn").instantiate()
	scene.auto_advance = false
	root.add_child(scene)
	current_scene = scene
	scene.actor_world.pose_published.connect(func(actor: String, sample: Dictionary):
		if not first_native.has(actor): first_native[actor] = sample.duplicate(true))
	scene.actor_world.initialization_failed.connect(_initialization_failed)
	for _frame in range(120):
		await _frames(1)
		if scene.model.projection().actors.P.ready and not scene.startup_save_pending:
			break
	_check(not scene.legacy_fixture and scene._can_control_character(), "Normal opening has a ready physical character")
	_check(first_native.has("P") and _same_seed(first_native.P),
		"Initial/restored native seed agrees within declared1e-5 observation tolerance before natural movement")
	await _frames(30)
	_cut("ready_ground")
	if resumed:
		_check(scene.save_slot_owned and scene.last_save_result.get("accepted", false), "Fresh resumed session publishes its own verified native slot")
		await _orbit_to_zero()
		await _key(KEY_F9)
		_check(scene.last_load_result.get("reason") == "load_requires_restart", "Physical live Load explicitly refuses without replacement")
		await _key(KEY_F5)
		_check(scene.last_save_result.get("accepted", false), "Current resumed resting pose saves through native preflight")
		_cut("reopened_saved")
		await _finish()
		return
	await _zoom_out()
	await _key(KEY_4)
	await _cell(2)
	_check(_last().get("reason") == "out_of_reach" and scene.state.parts.processor == 1 and scene.state.entities.is_empty(), "Far click refuses without consuming carried press")
	var far_position: Array = scene.model.projection().actors.P.position.duplicate()
	await _orbit_to_zero()
	await _cell(2)
	_check(_last().get("reason") == "out_of_reach" and scene.model.projection().actors.P.position == far_position, "Camera-only orbit cannot grant reach or move body")
	await _key(KEY_3)
	await _cell(-1, 2)
	_check(_last().get("reason") == "actor_occupied" and scene.state.parts.belt == 1 and scene.state.entities.is_empty(), "Underfoot placement refuses before part/identity mutation")
	await _key(KEY_F5)
	_check(scene.last_save_result.get("accepted", false), "Immediate save after refused underfoot placement preserves valid world")
	_cut("underfoot_refused_saved")
	await _walk(-1.65, 1.65)
	for entry in [[KEY_5, -1], [KEY_1, 0], [KEY_3, 1]]:
		await _key(entry[0])
		await _cell(entry[1])
		_check(_last().get("accepted", false), "Nearby ordinary machine placement succeeds")
	await _walk(1.65, 1.65)
	await _key(KEY_4)
	await _cell(2)
	_check(_last().get("accepted", false) and scene.state.entities.size() == 4, "Fresh closer press request succeeds with all four real machines")
	await _frames(3)
	await _edge(KEY_W, true)
	await _frames(45)
	await _edge(KEY_W, false)
	await _frames(3)
	var contact := _cut("machine_wall_contact")
	var wall_z: float = contact.state.actors.P.position[2]
	_check(wall_z >= 1.02 and wall_z < 1.2, "Actual capsule stops at machine box instead of crossing its center")
	await _key(KEY_F5)
	_check(scene.last_save_result.get("accepted", false), "Actual ground/wall resting contact passes declared native save preflight")
	if not wall_save.is_empty():
		_check(not FileAccess.file_exists(wall_save) and DirAccess.copy_absolute(scene.save_slot, wall_save) == OK,
			"Retain exact owned wall-save bytes for a separate fresh-process reopen")
		wall_checkpoint = scene.model.checkpoint()
	await _walk(1.65, 1.65)
	await _link(KEY_F, 0, 1)
	await _link(KEY_F, 1, 2)
	for pair in [[-1, 0], [0, 1], [1, 2]]:
		await _link(KEY_G, pair[0], pair[1])
	_check(scene.state.powered and scene.state.parts.shaft == 0, "Actual connected wheel powers the stationary line with three finite shafts")
	# Jump and release are actual native motion; no desired pose is accepted.
	var ground_y: float = scene.state.actors.P.position[1]
	await _key(KEY_SPACE)
	await _frames(10)
	_check(scene.state.actors.P.position[1] > ground_y + 0.2, "Space jumps physical character instead of switching power")
	_check(scene.state.power_enabled, "Jump leaves automatic waterwheel drive available")
	await _frames(70)
	_cut("jump_landed")
	await _edge(KEY_D, true)
	await _frames(4)
	await _key(KEY_H)
	var help_pose: Array = scene.model.projection().actors.P.position.duplicate()
	var revision_before: int = scene.model.revision
	scene.auto_advance = true
	await _frames(90)
	scene.auto_advance = false
	_check(scene.explanation_open and scene.character_presenter.held_keys.is_empty(), "Help releases held movement")
	_check(scene.model.projection().actors.P.position == help_pose, "Released character stays horizontal while Help remains open")
	_check(scene.model.revision > revision_before, "Factory production continues during explanation")
	await _edge(KEY_D, false)
	await _key(KEY_H)
	await _walk(3.3, 1.65)
	scene.auto_advance = false
	var before_p: Dictionary = scene.model.projection()
	await _key(KEY_P)
	_check(scene.state.order == before_p.order and scene.state.power_enabled, "P at the press does not switch the drive")
	await _walk(-1.65, 1.65)
	before_p = scene.model.projection()
	await _key(KEY_P)
	_check(scene.state.order == before_p.order and scene.state.power_enabled, "P beside the wheel does not switch the drive")
	var paused: Dictionary = scene.model.projection()
	await _frames(5)
	_check(scene.model.projection().stock == paused.stock and scene.model.projection().remaining == paused.remaining, "The controlled fixture clock retains exact stock and phase")
	_cut("controlled_clock_retained_work")
	scene.auto_advance = true
	await _walk(3.3, 1.65)
	await _key(KEY_ESCAPE)
	await _cell(2)
	for _tick in range(80):
		scene._refresh()
		if scene.state.stock.output > 0:
			await _key(KEY_R)
			_capture_admission()
		if scene.state.inventories.get("P", 0) >= 4:
			break
		scene.model.advance()
	_check(scene.state.inventories.get("P", 0) == 4, "Actual nearby R retrieves four plates")
	_ledger()
	var before_goal: Dictionary = scene.model.checkpoint()
	await _click(scene.confirm_button.get_global_rect().get_center())
	_check(scene.goal_confirmed and scene.model.checkpoint() == before_goal, "Actual goal button confirms without consumption")
	await _edge(KEY_D, true)
	await _frames(3)
	root.focus_exited.emit() # Explicit signal injection, not real OS-focus evidence.
	await _frames(3)
	var released: Array = scene.state.actors.P.position.duplicate()
	await _frames(12)
	_check(scene.character_presenter.held_keys.is_empty() and scene.state.actors.P.position == released, "Window release signal clears held input without polling it back on")
	await _edge(KEY_D, false)
	await _key(KEY_F5)
	_check(scene.last_save_result.get("accepted", false), "Final current native character and factory save succeeds")
	var before_load: Dictionary = scene.model.checkpoint()
	await _key(KEY_F9)
	_check(scene.last_load_result.get("reason") == "load_requires_restart" and scene.model.checkpoint() == before_load, "Live Load refuses atomically")
	_cut("four_plate_saved")
	if not negative_save.is_empty():
		# Explicit invalid persistence fixture, not a pose setter or an accepted
		# native sample. The live Model/body and successful original stay intact.
		var candidate: Dictionary = scene.model.checkpoint()
		candidate.actors.P.position = [1.65, 0.8, 0.0]
		_check(not FileAccess.file_exists(negative_save), "Negative fixture uses its own fresh owned path")
		negative_fixture = load("res://save-tests/checkpoint_file.gd").write_snapshot(candidate, negative_save)
		_check(negative_fixture.get("accepted", false), "Schema-valid deep-overlap fixture is written separately for real native refusal")
	await _finish()

func _initialization_failed(actor: String, reason: String) -> void:
	# The product already schedules a nonzero abort. Preserve its actual native
	# failed seed/query before exit, without making readiness or a fallback pose.
	if output.is_empty():
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema": 1, "status": "refused", "profile": "physical",
			"pid": OS.get_process_id(), "actor": actor, "reason": reason,
			"first_native": first_native, "state": scene.model.projection(),
			"native": scene.actor_world.diagnostics(actor), "save_owned": scene.save_slot_owned}, "", true, true))
		file.close()

func _finish() -> void:
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(capture) == OK, "Actual rendered viewport saved")
	var report := {"schema": 1, "status": "pass" if failures.is_empty() else "fail", "checks": checks,
		"failures": failures, "profile": "physical", "resumed": resumed,
		"pid": OS.get_process_id(), "first_native": first_native, "cuts": cuts, "admissions": admissions,
		"checkpoint": scene.model.checkpoint(), "loaded": scene.startup_resume_checkpoint,
		"native": scene.actor_world.diagnostics(), "save": scene.last_save_result,
		"wall_save": wall_save, "wall_checkpoint": wall_checkpoint,
		"negative_save": negative_save, "negative_fixture": negative_fixture,
		"goal_confirmed": scene.goal_confirmed, "capture": capture,
		"clock": "native physics; production controlled except90-frame real Help interval",
		"focus_evidence": "Window.focus_exited signal injected; no OS focus claim"}
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "", true, true))
			file.close()
	print("OPENING_CHARACTER_PASS" if failures.is_empty() else "OPENING_CHARACTER_FAIL " + JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
