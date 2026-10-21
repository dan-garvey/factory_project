extends "res://opening/opening_check.gd"
## Actual help/navigation/camera/build/save consumers from an EMPTY player site.
## Frozen observation clock proves isolation; a separate check retains live time.

var report: Dictionary = {"lessons": [], "captures": [], "user_play": "not_assessed"}

func facts() -> Dictionary:
	return {"checkpoint": scene.model.checkpoint(), "selected": scene.selected,
		"pending": scene.pending_link, "mode": scene.mode, "confirmed": scene.goal_confirmed,
		"namespace": scene.request_namespace, "sequence": scene.request_sequence,
		"slot": scene.save_slot, "ready": scene.save_slot_ready, "owned": scene.save_slot_owned,
		"save_result": scene.last_save_result.duplicate(true), "load_result": scene.last_load_result.duplicate(true),
		"focus": scene.focus, "yaw": scene.orbit_yaw, "pitch": scene.orbit_pitch, "distance": scene.distance}

func mouse_button(button: MouseButton, at: Vector2, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func capture(suffix: String) -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var path := argument.trim_prefix("--capture=")
			if suffix != "":
				path = path.get_basename() + "-" + suffix + ".png"
			_check(root.get_texture().get_image().save_png(path) == OK, "Actual explanation capture saved.")
			report.captures.append(path)

func ledger(expected: Array, powered: bool, remaining: int) -> void:
	var state: Dictionary = scene.example_presenter.model.projection()
	var stock: Dictionary = state.stock
	_check([stock.source, stock.collector, stock.belt, stock.input, stock.held, stock.output, stock.player] == expected,
		"Independent finite example ledger matches every actual owner.")
	_check(state.powered == powered and state.remaining == remaining, "Actual example power and phase match independent stage.")
	_check(state.initial_feed == 16 and state.recipe_input == 1 and state.entities.size() == 4,
		"Teaching example uses same finite rule set and actual complete path.")
	_check(state.parts == {"collector": 0, "belt": 0, "processor": 0, "wheel": 0, "shaft": 0 if powered else 3},
		"Example placement/drive consumes its own finite starter kit.")

func _run() -> void:
	root.size = Vector2i(1280, 800)
	scene = load("res://opening/opening.tscn").instantiate()
	scene.auto_advance = false
	root.add_child(scene)
	await process_frame
	await physics_frame
	var before := facts()
	_check(scene.state.entities.is_empty() and scene.request_sequence == 0 and scene.state.stock.source == 16,
		"Help test starts on an empty player factory, not a supplied demo line.")
	await _key(KEY_H)
	_check(scene.explanation_open and scene.example_presenter.visible, "Actual H displays populated example.")
	var presenter = scene.example_presenter
	await physics_frame
	_check(presenter.model != scene.model and presenter.world.get_world_3d() != scene.get_world_3d(),
		"Example owns a separate same-rule model AND physics world.")
	_check(presenter.world.machine_root.get_child_count() == 6 and presenter.world.item_root.get_child_count() == 16,
		"Empty player worksite still displays four machines, material connections and finite example seam.")
	_check(scene._screen_entity(scene.camera.unproject_position(Vector3(0, 0.8, 0))).is_empty(),
		"Example colliders never appear in the empty player physics query.")
	ledger([16, 0, 0, 0, 0, 0, 0], false, 0)
	report.lessons.append(presenter.model.projection())
	await _click_screen(scene.lesson_next.get_global_rect().get_center())
	_check(scene.lesson_index == 1, "Actual Next button switches to connected drive lesson.")
	ledger([16, 0, 0, 0, 0, 0, 0], true, 0)
	report.lessons.append(presenter.model.projection())
	await _click_screen(presenter.step_button.get_global_rect().get_center())
	ledger([15, 1, 0, 0, 0, 0, 0], true, 0)
	report.step = presenter.model.projection()
	await _click_screen(scene.lesson_next.get_global_rect().get_center())
	ledger([12, 1, 1, 1, 1, 0, 0], true, 2)
	report.lessons.append(presenter.model.projection())
	await physics_frame
	# Inspect the real example collider through the actual viewport mouse path.
	var local: Vector2 = presenter.world.camera.unproject_position(Vector3(0, 0.8, 0))
	var point: Vector2 = presenter.surface.global_position + local * presenter.surface.size / Vector2(presenter.viewport.size)
	await _click_screen(point)
	_check(presenter.inspected == "collector-1" and presenter.inspect_label.text.contains("Collector"),
		"Actual example viewport click inspects its own machine.")
	var center: Vector2 = presenter.surface.get_global_rect().get_center()
	var old_yaw: float = presenter.world.orbit_yaw
	await mouse_button(MOUSE_BUTTON_RIGHT, center)
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	motion.relative = Vector2(25, 12)
	Input.parse_input_event(motion)
	await process_frame
	await mouse_button(MOUSE_BUTTON_RIGHT, center, false)
	_check(presenter.world.orbit_yaw != old_yaw, "Actual right drag rotates the example camera.")
	var old_distance: float = presenter.world.distance
	await mouse_button(MOUSE_BUTTON_WHEEL_UP, center)
	await mouse_button(MOUSE_BUTTON_WHEEL_UP, center, false)
	_check(presenter.world.distance == old_distance - 1, "Actual wheel zoom affects the example camera.")
	var old_focus: Vector3 = presenter.world.focus
	var pan_event := InputEventKey.new()
	pan_event.keycode = KEY_D
	pan_event.physical_keycode = KEY_D
	pan_event.pressed = true
	Input.parse_input_event(pan_event)
	await process_frame
	scene._process(0.1)
	pan_event = pan_event.duplicate()
	pan_event.pressed = false
	Input.parse_input_event(pan_event)
	await process_frame
	_check(presenter.world.focus.x > old_focus.x, "Actual held camera key pans only the example.")
	var example_before: Dictionary = presenter.model.checkpoint()
	for code in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_B, KEY_F, KEY_G, KEY_I, KEY_R, KEY_SPACE, KEY_F5, KEY_F9]:
		await _key(code)
	await _click_screen(center)
	_check(presenter.model.checkpoint() == example_before, "Build/retrieve/save shortcuts and viewport clicks cannot edit the example.")
	_check(facts() == before, "Full player checkpoint, parts, requests, goal, selection, camera and save facts remain unchanged.")
	_check(not scene._path_exists(scene.save_slot) and not scene._path_exists(scene.save_slot + ".pending"),
		"Read-only explanation never publishes a player save.")
	report.isolation = true
	await _key(KEY_HOME)
	await capture("working")
	await _click_screen(scene.lesson_next.get_global_rect().get_center())
	ledger([11, 1, 1, 1, 1, 1, 0], true, 0)
	report.lessons.append(presenter.model.projection())
	local = presenter.world.camera.unproject_position(Vector3(2 * scene.PITCH, 0.8, 0))
	point = presenter.surface.global_position + local * presenter.surface.size / Vector2(presenter.viewport.size)
	await _click_screen(point)
	_check(presenter.inspected == "processor-1" and presenter.inspect_label.text.contains("1 held / 1 ready"),
		"Actual blocked press inspection displays retained work and occupied outlet.")
	await capture("blocked")
	# A real tick cannot discard unfinished work while the one-slot outlet is full.
	await _click_screen(presenter.step_button.get_global_rect().get_center())
	ledger([11, 1, 1, 1, 1, 1, 0], true, 0)
	report.blocked_retained = presenter.model.projection()
	await _click_screen(presenter.recover_button.get_global_rect().get_center())
	ledger([10, 1, 1, 1, 1, 1, 1], true, 2)
	report.recovery = presenter.model.projection()
	report.transitions = presenter.transitions.duplicate(true)
	await capture("")
	_check(facts() == before, "Example collection/recovery transfers nothing to the player or its save.")
	await _click_screen(scene.lesson_previous.get_global_rect().get_center())
	_check(scene.lesson_index == 2, "Actual Previous button returns to material-path lesson.")
	await _click_screen(scene.lesson_return.get_global_rect().get_center())
	_check(not scene.explanation_open and not presenter.visible and facts() == before,
		"Actual Return button restores the ordinary empty worksite without side effects.")
	# Return must leave ordinary building usable. Build through actual input,
	# then separately prove the existing live clock moves PLAYER stock in Help.
	for entry in [[KEY_5, -1], [KEY_1, 0], [KEY_3, 1], [KEY_4, 2]]:
		await _key(entry[0])
		await _click_cell(entry[1])
	await _connect(KEY_F, 0, 1)
	await _connect(KEY_F, 1, 2)
	for pair in [[-1, 0], [0, 1], [1, 2]]:
		await _connect(KEY_G, pair[0], pair[1])
	_check(scene.state.entities.size() == 4 and scene.state.parts.collector == 0 and scene.state.powered,
		"Returning leaves actual ordinary player placement/connections usable.")
	report.player_after_return = scene.model.projection()
	await _key(KEY_H)
	var revision: int = scene.model.projection().revision
	scene.auto_advance = true
	scene.elapsed = 0.0
	scene._process(scene.STEP_SECONDS)
	scene.auto_advance = false
	_check(scene.model.projection().revision == revision + 1 and scene.state.stock.source == 15 and scene.state.stock.collector == 1,
		"Existing live worksite clock still moves actual player material while Help is open.")
	report.live_clock = true
	report.live_clock_state = scene.model.projection()
	await _key(KEY_ESCAPE)
	_check(not scene.explanation_open, "Actual Escape returns from example.")
	if failures.is_empty():
		print("OPENING_EXPLANATION_STATE " + JSON.stringify(report))
		print("OPENING_EXPLANATION_PASS: actual help/navigation/inspection/orbit/zoom/isolation/blockage/recovery/return")
		quit(0)
	else:
		print("OPENING_EXPLANATION_FAIL " + JSON.stringify(failures))
		quit(1)
