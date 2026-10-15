extends SceneTree
## Real workshop input; independent native observations at completed boundaries.
var scene
var checks := 0
var failures: Array[String] = []
var cases := {}
var trace: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func native_facts() -> Dictionary:
	var value := {"bodies": {}, "ids": {}, "sizes": {}}
	for branch in ["B", "U"]:
		var body: PhysicsBody3D = scene.authority.bodies[branch]
		var pose: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		var size: Vector3 = body.get_node("CollisionShape3D").shape.size
		value.bodies[branch] = [pose.origin.x, pose.origin.y, pose.origin.z]
		value.ids[branch] = body.get_instance_id()
		value.sizes[branch] = [size.x, size.y, size.z]
	var solid: Transform3D = PhysicsServer3D.body_get_state(scene.authority.obstacle.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	value["stop"] = [solid.origin.x, solid.origin.y, solid.origin.z]
	value["stop_id"] = scene.authority.obstacle.get_instance_id()
	return value

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func click_screen(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await physics_frame
	await process_frame

func cell(x: int, z: int) -> void:
	await click_screen(scene.camera.unproject_position(Vector3(x, 0.04, z)))

func settled_geometry() -> void:
	while scene.authority.projection().native_pending:
		await physics_frame
		await process_frame

func fresh() -> void:
	if scene != null:
		scene.queue_free()
	await process_frame
	scene = load("res://workshop/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame
	await process_frame
	await settled_geometry()
	# Initial geometry publishes without an advanced signal. Let the view's
	# scheduled process refresh complete before observing its actual labels.
	await process_frame
	check(not scene.authority.projection().layout.ready and scene.authority.projection().contact_entries == 0,
		"Fresh board starts empty, not a preset working arrangement")
	for branch in ["B", "U"]:
		check(not scene.body_meshes[branch].visible, "Uninstalled native bodies are not shown as built heads")
	check(scene.clutch_marks.text == "K SHAFT MARKS\nPlace both heads and output.",
		"Empty layout explains why shaft marks are unavailable; observed " + scene.clutch_marks.text)
	trace = []

func piece(selector: Key, x: int, z: int) -> void:
	await key(selector)
	await cell(x, z)
	check(scene.last_result.get("accepted", false), "Actual key and grid click configures a piece")
	await settled_geometry()

func build(bx: int = 0, uz: int = 3, gear: Key = KEY_4, with_idler := true, stop_cell: Array = []) -> void:
	await piece(KEY_1, bx, 0)
	await piece(KEY_2, 0, uz)
	await piece(gear, -3, -2)
	if with_idler:
		await piece(KEY_5, -4, -2)
	if not stop_cell.is_empty():
		await piece(KEY_6, stop_cell[0], stop_cell[1])
	check(scene.authority.projection().layout.ready, "Player-built layout, not an injected ready flag")

func step() -> Dictionary:
	var before: Dictionary = scene.authority.projection()
	var admission := {}
	var completion := {}
	var observed_ids: Dictionary = native_facts().ids
	scene.answered.connect(func(intent: Dictionary, outcome: Dictionary, at_ack: Dictionary):
		if intent.get("action") == "step" and outcome.accepted:
			admission["state"] = at_ack
			admission["native"] = native_facts()
			check(scene.clutch_marks.text == "K SHAFT MARKS\nNative update pending", "Shaft marks withhold tentative input phases during native completion")
			var refused: Dictionary = scene.authority.command({"action": "step"})
			check(not refused.accepted and refused.reason == "step_pending", "Additional pending API control cannot double-advance")
			check(scene.authority.projection() == at_ack, "Pending refusal preserves full mechanism/config state")
	, CONNECT_ONE_SHOT)
	scene.authority.advanced.connect(func(outcome: Dictionary): completion["value"] = outcome, CONNECT_ONE_SHOT)
	await key(KEY_N)
	if completion.is_empty():
		await scene.authority.advanced
	check(admission.has("state") and admission.state.pending, "Actual N input queues an owned native step")
	var after: Dictionary = scene.authority.projection()
	var native := native_facts()
	check(not after.pending and not after.native_pending, "Published step waits for actual native completion")
	check(after.attempts == before.attempts + 1, "One real N input has one attempt")
	check(native.ids == observed_ids, "Body identities survive this native operation")
	for branch in ["B", "U"]:
		for axis in range(3):
			check(near(native.bodies[branch][axis], after.completed.positions[branch][axis]), "Native RID pose matches completed publication")
		check(scene.body_meshes[branch].position.distance_to(Vector3(native.bodies[branch][0], native.bodies[branch][1], native.bodies[branch][2])) < 0.00001,
			"Actual view renders completed native positions")
	trace.append({"before": before, "admission": admission, "after": after, "native": native,
		"accepted": completion.value.accepted})
	return after

func record(name: String) -> void:
	cases[name] = {"state": scene.authority.projection(), "native": native_facts(), "steps": trace.duplicate(true)}

func _run() -> void:
	root.size = Vector2i(1280, 800)
	await fresh()
	await key(KEY_SPACE)
	check(not scene.authority.running and scene.last_result.reason == "place_heads_and_output", "Empty build cannot silently run a supplied rig")
	var empty: Dictionary = scene.authority.projection()
	await piece(KEY_1, -1, 0)
	await key(KEY_4)
	await cell(-2, -2)
	check(not scene.last_result.accepted and scene.last_result.reason == "choose_output_peg", "Wrong actual peg is refused")
	check(scene.authority.projection().layout.pieces.gear == null,
		"Invalid geometry does not install a phantom output gear")
	await key(KEY_X)
	await cell(-1, 0)
	await settled_geometry()
	check(scene.authority.projection().layout.pieces.B == null, "Actual pickup returns to empty mount")
	cases.empty = {"state": scene.authority.projection(), "initial": empty}

	await build(-1, 3)
	await key(KEY_SPACE)
	for index in range(32):
		await step()
	check(scene.authority.contact_entries == 0, "B at -1 genuinely misses the work area over the full cycle")
	record("miss")
	await key(KEY_SPACE)
	var retained: Dictionary = scene.authority.projection()
	await key(KEY_1)
	await cell(0, 0)
	check(not scene.last_result.accepted and scene.last_result.reason == "initial_setup_only"
		and scene.authority.projection() == retained, "Even returned stopped cycle cannot silently rebuild; explicit reset needed")
	var prior_id: int = scene.authority.get_instance_id()
	await key(KEY_R)
	await process_frame
	await settled_geometry()
	check(scene.authority.get_instance_id() != prior_id and not scene.authority.projection().layout.ready,
		"R starts an explicitly fresh empty workshop")

	await build(0, 3)
	await key(KEY_SPACE)
	for index in range(8):
		await step()
	record("positive8")
	check(near(scene.authority.phases.B, PI / 2) and scene.authority.contact_entries == 1,
		"Player idler/output drives actual first positive work encounter")
	check(scene.clutch_marks.text == "K SHAFT MARKS\nGeared input 090.00°\nRetained B 090.00°\nOffset +0.00°", "Positive half-rate shaft marks use completed geared input, not raw source")
	var moving: Dictionary = scene.authority.projection()
	await key(KEY_2)
	await cell(0, 4)
	check(not scene.last_result.accepted and scene.authority.projection() == moving, "Moving construction is refused without changing native layout")
	for index in range(24):
		await step()
	record("positive32")

	await fresh()
	await build(0, 3, KEY_4, false)
	await key(KEY_SPACE)
	for index in range(8):
		await step()
	record("negative8")
	check(near(scene.authority.phases.B, -PI / 2) and scene.authority.contact_entries == 0, "Reversed first matched window goes away from work")
	check(scene.clutch_marks.text == "K SHAFT MARKS\nGeared input 270.00°\nRetained B 270.00°\nOffset +0.00°", "Reversed shaft marks show signed geared phase modulo a revolution")
	for index in range(24):
		await step()
	record("negative32")
	check(scene.authority.contact_entries > 0, "Reversed reciprocation can contact later; no permanent-miss fiction")

	await fresh()
	await build(0, 3, KEY_3)
	await key(KEY_SPACE)
	for index in range(2):
		await step()
	record("ratio20two")
	check(scene.authority.contact_entries == 1 and near(scene.authority.phases.B, PI / 4), "Output gear placement changes real encounter timing")
	check(scene.clutch_marks.text == "K SHAFT MARKS\nGeared input 045.00°\nRetained B 045.00°\nOffset +0.00°", "Twenty-tooth output inspection follows its actual changed ratio")

	await fresh()
	await build(0, 3, KEY_4, true, [1, 0])
	var identity: Dictionary = native_facts()
	await key(KEY_SPACE)
	await step()
	var before_block: Dictionary = scene.authority.projection()
	await step()
	record("blocked")
	check(scene.authority.blocked and scene.authority.last_collision.branch == "B"
		and scene.authority.phases == before_block.phases and scene.authority.source_phase == before_block.source_phase,
		"Real stop stalls whole connected drive before committing any partial motion")
	await key(KEY_SPACE)
	await key(KEY_K)
	await key(KEY_SPACE)
	for index in range(32):
		await step()
		if index == 0:
			check(scene.clutch_marks.text == "K SHAFT MARKS\nGeared input 022.50°\nRetained B 011.25°\nOffset +11.25°", "Isolated input mark advances while retained B mark stays")
			await key(KEY_SPACE)
			var misaligned: Dictionary = scene.authority.projection()
			await click_screen(scene.coupling_button.get_global_rect().get_center())
			check(not scene.last_result.accepted and scene.last_result.reason == "coupling_misaligned"
				and scene.authority.projection() == misaligned, "Actual K button retains authoritative refusal at displayed nonzero offset")
			await key(KEY_SPACE)
	record("isolated32")
	check(near(scene.authority.phases.B, PI / 16) and near(scene.authority.phases.U, 33 * PI / 16),
		"U completes a real isolated cycle while B retains its blocked phase")
	await key(KEY_SPACE)
	await key(KEY_O)
	await settled_geometry()
	check(scene.clutch_marks.text == "K SHAFT MARKS\nGeared input 011.25°\nRetained B 011.25°\nOffset +0.00°", "Complete isolated cycle visibly restores modulo shaft marks without resetting phases")
	var inspected: Dictionary = scene.authority.projection()
	await process_frame
	check(scene.authority.projection() == inspected, "Paused inspection changes no authority state")
	await click_screen(scene.coupling_button.get_global_rect().get_center())
	check(scene.last_result.accepted and scene.authority.coupled, "Stopped modulo-aligned K engages without reset")
	await key(KEY_SPACE)
	await step()
	await step()
	record("recovered")
	check(native_facts().ids == identity.ids and native_facts().stop_id == identity.stop_id
		and near(scene.authority.phases.B, 3 * PI / 16) and scene.authority.contact_entries == 1,
		"Same native identities resume retained phase and reach real work after stop retraction")

	await fresh()
	await build(0, 3, KEY_4, true, [2, 0])
	await key(KEY_SPACE)
	for index in range(5):
		await step()
	record("late_stop")
	check(scene.authority.blocked and scene.authority.committed == 4 and scene.authority.contact_entries == 1,
		"Stop at x2 permits actual work before native stall, unlike stop at x1")

	await fresh()
	await build(0, 3, KEY_4, true, [1, 3])
	await key(KEY_K)
	await key(KEY_SPACE)
	await step()
	await step()
	record("U3blocked")
	check(scene.authority.blocked and scene.authority.last_collision.branch == "U", "B isolation cannot conceal obstruction in still-driven U")
	await fresh()
	await build(0, 4, KEY_4, true, [1, 3])
	await key(KEY_K)
	await key(KEY_SPACE)
	for index in range(8):
		await step()
	record("U4clear")
	check(not scene.authority.blocked and scene.authority.committed == 8, "Player U mount choice has real native clearance")
	await key(KEY_SPACE)
	var camera_authority: Dictionary = scene.authority.projection()
	var old_yaw: float = scene.yaw
	var old_distance: float = scene.distance
	var pointer := InputEventMouseButton.new()
	pointer.button_index = MOUSE_BUTTON_RIGHT
	pointer.position = Vector2(640, 400)
	pointer.pressed = true
	Input.parse_input_event(pointer)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = pointer.position
	motion.relative = Vector2(24, 10)
	Input.parse_input_event(motion)
	await process_frame
	pointer = pointer.duplicate()
	pointer.pressed = false
	Input.parse_input_event(pointer)
	await process_frame
	pointer = InputEventMouseButton.new()
	pointer.position = Vector2(640, 400)
	pointer.button_index = MOUSE_BUTTON_WHEEL_UP
	pointer.pressed = true
	Input.parse_input_event(pointer)
	await process_frame
	pointer = pointer.duplicate()
	pointer.pressed = false
	Input.parse_input_event(pointer)
	await process_frame
	check(scene.yaw != old_yaw and scene.distance == old_distance - 1, "Actual pointer input orbits and zooms workshop camera")
	check(scene.authority.projection() == camera_authority, "Camera input never changes mechanism state")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture="):
				check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "Actual workshop viewport capture")
	var report := {"status": "pass" if failures.is_empty() else "fail", "checks": checks, "failures": failures, "cases": cases}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report))
	print("WORKSHOP_PASS" if failures.is_empty() else "WORKSHOP_FAIL")
	quit(0 if failures.is_empty() else 1)
