extends "res://opening/opening_check.gd"
## Native Help interactions in a private headless process; no desktop control.
## The player material clock is frozen for isolation; native actor frames remain live.

const NativeModel = preload("res://opening/native_model.gd")
const Opening = preload("res://opening/opening.gd")
const Geometry = preload("res://opening/site_geometry.gd")
var checks := 0
var report := {"ledgers": [], "user_play": "not_assessed", "desktop_operations": 0}

func _check(condition: bool, message: String) -> void:
	checks += 1
	super._check(condition, message)

func finish() -> void:
	report["checks"] = checks
	report["failures"] = failures.duplicate()
	print("OPENING_EXPLANATION_STATE " + JSON.stringify(report))
	print("OPENING_EXPLANATION_%s %d" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func facts() -> Dictionary:
	return {"world": scene.model.checkpoint().world, "selected": scene.selected,
		"pending": scene.pending_link, "mode": scene.mode, "confirmed": scene.goal_confirmed,
		"namespace": scene.request_namespace, "sequence": scene.request_sequence,
		"slot": scene.save_slot, "ready": scene.save_slot_ready, "owned": scene.save_slot_owned,
		"save_result": scene.last_save_result.duplicate(true), "load_result": scene.last_load_result.duplicate(true),
		"focus": scene.focus, "yaw": scene.orbit_yaw, "pitch": scene.orbit_pitch, "distance": scene.distance}

func cargo_units(cargo: Dictionary, recipe: int) -> int:
	var count := int(cargo.get("raw", 0)) + int(cargo.get("products", 0)) * recipe
	for lot: Dictionary in cargo.get("work_lots", []):
		count += int(lot.recipe_input)
	return count

func conserved(state: Dictionary) -> bool:
	var stock: Dictionary = state.stock
	var total: int = stock.source + stock.collector + stock.belt + stock.input + stock.held
	total += int(state.recipe_input) * int(stock.output + stock.player)
	# Stock.player already aggregates carried products; cargo repeats that
	# projection for each actor. Only carried raw and work lots are additional.
	for cargo: Dictionary in state.get("cargo", {}).values():
		total += int(cargo.get("raw", 0))
		for lot: Dictionary in cargo.get("work_lots", []):
			total += int(lot.recipe_input)
	for cargo: Dictionary in state.get("dropped_material", []):
		total += cargo_units(cargo, state.recipe_input)
	for span: Dictionary in state.get("belt_spans", {}).values():
		for slot: Variant in span.slots:
			if slot is Dictionary:
				total += cargo_units(slot, state.recipe_input)
	return total == int(state.initial_feed)

func ledger(label: String, powered: bool) -> Dictionary:
	var state: Dictionary = scene.example_presenter.model.projection()
	_check(state.options.native and state.initial_feed == 4096 and state.recipe_input == 1,
		"The lesson uses the real native reserve and recipe.")
	_check(state.entities.size() == 3 and state.belt_spans.size() == 1 and state.transmission_parts.size() == 12,
		"The native example has three machines, a shaft span, seven cogs and five shafts.")
	_check(state.part_kits.P == {"collector": 0, "belt": 1, "processor": 0, "wheel": 0,
		"shaft": 3, "gear": 3, "foundation": 20}, "The example spends its own finite construction kit.")
	_check(state.powered == powered and conserved(state), "Power and all material owners match the lesson.")
	report.ledgers.append({"stage": label, "lesson": scene.lesson_index, "ticks": scene.example_presenter.ticks,
		"stock": state.stock, "remaining": state.remaining, "belt": state.belt_spans,
		"cargo": state.cargo, "kit": state.part_kits.P, "revision": state.revision,
		"next_inside_example": scene.example_presenter.surface.get_global_rect().has_point(scene.lesson_next.get_global_rect().get_center())})
	return state

func example_target(kind: String) -> Dictionary:
	var presenter = scene.example_presenter
	for id: String in presenter.model.projection().entities:
		var entity: Dictionary = presenter.model.projection().entities[id]
		if entity.kind == kind:
			var at := Vector3(float(entity.cell[0]) * Geometry.PITCH,
				float(entity.get("level", 0)) * Geometry.HEIGHT_STEP + Geometry.MACHINE_CENTER_HEIGHT,
				float(entity.cell[1]) * Geometry.PITCH)
			var local: Vector2 = presenter.world.camera.unproject_position(at)
			return {"id": id, "world": at,
				"screen": presenter.surface.global_position + local * presenter.surface.size / Vector2(presenter.viewport.size)}
	return {}

func isolated(before: Dictionary, original_position: Vector3) -> void:
	_check(facts() == before, "Help preserves the complete native World, requests, kit, goal, selection, camera and save facts.")
	var position: Array = scene.model.projection().actors.P.position
	_check(Vector3(position[0], position[1], position[2]).distance_to(original_position) < 0.001,
		"Neutral physical frames do not move the player while the example camera is controlled.")

func _run() -> void:
	_check(DisplayServer.get_name().to_lower() == "headless", "Synthetic interaction runs only in a private headless engine.")
	if not failures.is_empty():
		finish()
		return
	root.size = Vector2i(1280, 800)
	scene = load("res://opening/opening.tscn").instantiate()
	scene.auto_advance = false
	root.add_child(scene)
	for _frame in range(20):
		await physics_frame
	var before := facts()
	var position: Array = scene.model.projection().actors.P.position
	var original_position := Vector3(position[0], position[1], position[2])
	_check(scene.state.entities.is_empty() and scene.request_sequence == 0 and scene.state.stock.source == 4096,
		"Help begins at an empty native player worksite with its real finite reserve.")
	await _key(KEY_H)
	await physics_frame
	_check(scene.explanation_open and scene.example_presenter != null and scene.example_presenter.visible,
		"H opens the actual Help interface.")
	if not failures.is_empty():
		finish()
		return
	var presenter = scene.example_presenter
	_check(presenter.model.native != scene.model.native and presenter.world.get_world_3d() != scene.get_world_3d(),
		"The example owns a different native World and physics space.")
	var example_machines := 0
	for child in presenter.world.machine_root.get_children():
		if child.has_meta("machine_entity"):
			example_machines += 1
	_check(example_machines == 3,
		"The isolated viewport draws the three confirmed native machines.")
	var off := ledger("stopped", false)
	_check(off.stock.source == 4096 and off.power_enabled and presenter.ticks == 0 and presenter.step_button.disabled,
		"The first lesson keeps its finite material at the seam before advancing time.")
	if not failures.is_empty():
		finish()
		return
	await _click_screen(scene.lesson_next.get_global_rect().get_center())
	_check(scene.lesson_index == 1, "Next opens the connected-drive lesson.")
	_check(not presenter.get_global_rect().intersects(scene.lesson_next.get_global_rect()),
		"The native drive paragraph leaves Next outside the example panel.")
	var running := ledger("drive", true)
	await _click_screen(presenter.step_button.get_global_rect().get_center())
	_check(presenter.ticks == 1 and presenter.model.projection().revision > running.revision,
		"The step button advances exactly one native example tick.")
	ledger("one_step", true)
	if not failures.is_empty():
		finish()
		return
	await _click_screen(scene.lesson_next.get_global_rect().get_center())
	_check(scene.lesson_index == 2, "Next opens the material-path lesson after stepping the example.")
	if not failures.is_empty():
		finish()
		return
	var working := ledger("working", true)
	_check(working.stock.held == 1 and working.remaining > 0 and presenter.ticks > 0,
		"The working lesson owns a real unfinished native lot.")
	var live_source_model = presenter.model
	var live_template: Dictionary = live_source_model.checkpoint()
	var collector := example_target("collector")
	_check(not collector.is_empty(), "The actual example collector has a projected screen target.")
	if not failures.is_empty():
		finish()
		return
	_check(scene._screen_entity(scene.camera.unproject_position(collector.world)).is_empty(),
		"Private example colliders never enter the empty player's pick space.")
	await _click_screen(collector.screen)
	_check(presenter.inspected == collector.id and presenter.inspect_label.text.contains("Collector"),
		"A viewport click inspects the native collector without a fixed legacy ID.")
	var center: Vector2 = presenter.surface.get_global_rect().get_center()
	var old_yaw: float = presenter.world.orbit_yaw
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = center
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.relative = Vector2(25, 12)
	Input.parse_input_event(motion)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	_check(presenter.world.orbit_yaw != old_yaw, "Right drag changes only the example camera orbit.")
	var old_distance: float = presenter.world.distance
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.position = center
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	_check(presenter.world.distance == old_distance - 1, "Wheel zoom changes the example camera distance.")
	var old_focus: Vector3 = presenter.world.focus
	var pan := InputEventKey.new()
	pan.keycode = KEY_D
	pan.physical_keycode = KEY_D
	pan.pressed = true
	Input.parse_input_event(pan)
	await process_frame
	scene._process(0.1)
	pan.pressed = false
	Input.parse_input_event(pan)
	await process_frame
	_check(presenter.world.focus.x > old_focus.x, "Held camera input pans the example.")
	var example_before: Dictionary = presenter.model.checkpoint()
	for code in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_B, KEY_F, KEY_G, KEY_I, KEY_R, KEY_SPACE, KEY_P, KEY_F5, KEY_F9]:
		await _key(code)
	await _click_screen(center)
	_check(presenter.model.checkpoint() == example_before, "Build, drive, retrieve and save shortcuts cannot edit the read-only example.")
	isolated(before, original_position)
	if not failures.is_empty():
		finish()
		return
	await _key(KEY_HOME)
	await _click_screen(scene.lesson_next.get_global_rect().get_center())
	var full := ledger("blocked", true)
	_check(full.stock.output == 1 and full.stock.held == 1 and full.remaining == 0,
		"The blocked lesson owns finished retained work behind its occupied outlet.")
	if not failures.is_empty():
		finish()
		return
	var press := example_target("processor")
	await _click_screen(press.screen)
	_check(presenter.inspected == press.id and presenter.inspect_label.text.contains("1 held / 1 ready"),
		"Press inspection reports the real retained work and occupied outlet.")
	await _click_screen(presenter.step_button.get_global_rect().get_center())
	var retained := ledger("blocked_step", true)
	_check(retained.stock.held == 1 and retained.stock.output == 1 and retained.remaining == 0,
		"A blocked native tick retains finished work and the existing plate.")
	if not failures.is_empty():
		finish()
		return
	var recovery_tick: int = presenter.ticks
	await _click_screen(presenter.recover_button.get_global_rect().get_center())
	var recovered := ledger("recovered", true)
	_check(recovered.inventories.P == 1 and recovered.stock.player == 1 and presenter.ticks == recovery_tick + 1,
		"Collection credits exactly one example plate and resumes its native clock.")
	if not failures.is_empty():
		finish()
		return
	isolated(before, original_position)
	_check(not scene._path_exists(scene.save_slot) and not scene._path_exists(scene.save_slot + ".pending"),
		"Help neither publishes a player save nor leaves pending save data.")
	await _click_screen(scene.lesson_previous.get_global_rect().get_center())
	_check(scene.lesson_index == 2, "Previous returns to the material-path lesson.")
	await _click_screen(scene.lesson_return.get_global_rect().get_center())
	_check(not scene.explanation_open and not presenter.visible, "Return restores the ordinary worksite interface.")
	isolated(before, original_position)
	await _key(KEY_1)
	await _click_cell(0, 1)
	_check(scene.state.entities.size() == 1 and scene.state.part_kits.P.collector == 0 and scene.request_sequence == 1,
		"Return leaves real proximity-checked native Collector placement usable.")
	report["player_after_return"] = {"stock": scene.state.stock, "kit": scene.state.part_kits.P,
		"entities": scene.state.entities, "game_requests": scene.request_sequence}
	if not failures.is_empty():
		finish()
		return
	# A separate owned native World reopens the real working lesson checkpoint.
	# It isolates the existing live-player clock from the frozen empty-site case.
	scene.queue_free()
	await process_frame
	var live_model = NativeModel.new("help-clock-player", ["P"])
	_check(live_model.restore_checkpoint(live_template).get("accepted", false), "An independent native World restores the actual working checkpoint.")
	scene = Opening.new()
	scene.model = live_model
	scene.auto_advance = false
	root.add_child(scene)
	for _frame in range(8):
		await physics_frame
	await _key(KEY_H)
	var live_before: Dictionary = scene.model.checkpoint().world
	var live_revision: int = scene.model.projection().revision
	scene.elapsed = 0.0
	scene.auto_advance = true
	scene._process(scene.STEP_SECONDS)
	scene.auto_advance = false
	_check(scene.explanation_open and scene.model.projection().revision > live_revision and scene.model.checkpoint().world != live_before,
		"The existing player clock advances actual native work while Help is open.")
	_check(live_source_model.checkpoint() == live_template and conserved(scene.model.projection()),
		"The independent live clock preserves material and cannot advance its source example World.")
	report["live_clock"] = {"before_revision": live_revision, "after_revision": scene.model.projection().revision,
		"stock": scene.model.projection().stock, "native_worlds_distinct": live_model.native != live_source_model.native}
	await _key(KEY_ESCAPE)
	_check(not scene.explanation_open, "Escape closes the native Help interface.")
	finish()
