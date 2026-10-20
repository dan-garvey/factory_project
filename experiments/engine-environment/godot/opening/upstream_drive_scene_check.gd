extends "res://opening/native_first_shift_check.gd"
## New post-shift integration over the retained, actually produced four-plate
## Store file. Headless callbacks and real ActorWorld movement, not desktop play.

func _anchor(part: Dictionary) -> Array:
	var center: Array = part.center
	return [float(center[0]) * 1.65 / 4.0, 0.5 + float(center[1]) * 1.65 / 4.0, float(center[2]) * 1.65 / 4.0]

func _targets(before: Dictionary, action: Dictionary) -> Array:
	if action.action == "place":
		return [[float(action.cell[0]) * 1.65, 0.5, float(action.cell[1]) * 1.65]]
	if action.action == "place_gear":
		return [_anchor({"center": action.center})]
	var ids: Array = [action.from, action.to] if action.action in ["connect", "connect_drive", "disconnect_drive"] else [action.entity]
	var targets: Array = []
	for id: String in ids:
		var part: Dictionary = before.entities.get(id, before.transmission_parts.get(id, {}))
		targets.append(_anchor(part))
	return targets

func _cell(id: String) -> Vector2i:
	var part: Dictionary = opening.state.entities.get(id, opening.state.transmission_parts.get(id, {}))
	return Vector2i(roundi(float(part.center[0]) / 4.0), roundi(float(part.center[2]) / 4.0))

func _pair(menu_id: int, from: String, to: String) -> void:
	opening.transmission_controls.get_popup().id_pressed.emit(menu_id)
	for id: String in [from, to]:
		opening._world_click(_cell(id), id)

func _gear(center: Array) -> String:
	opening.transmission_controls.get_popup().id_pressed.emit(1)
	var wire := {"action": "place_gear", "center": center, "axis": "x", "teeth": 2}
	var reply := _action("screen-place cog", wire, func():
		var point := _anchor({"center": center})
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = opening.camera.unproject_position(Vector3(point[0], point[1], point[2]))
		opening._unhandled_input(event))
	return str(reply.get("entity", ""))

func _remove_part(id: String) -> void:
	opening._select_tool("inspect")
	opening._world_click(_cell(id), id)
	_action("remove confirmed part", {"action": "remove", "entity": id}, opening._remove_selected)

func _kind(kind: String) -> String:
	for id: String in opening.state.entities:
		if opening.state.entities[id].kind == kind:
			return id
	return ""

func _run() -> void:
	facts.evidence = "ordinary_native_upstream_drive_continuation"
	if mode != "challenge" or not destination.is_absolute_path() or FileAccess.file_exists(destination) or not FileAccess.file_exists(prior_path):
		push_error("Use challenge mode, a retained first-shift Store file and a fresh output")
		quit(1)
		return
	facts["original_save_sha256"] = FileAccess.get_sha256(prior_path)
	opening = load("res://opening/opening.tscn").instantiate()
	root.add_child(opening)
	if not (await _until(func(): return opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending,
		"The retained worksite has a fresh registered, settled character")): return
	var start: Dictionary = opening.model.projection()
	facts["initial_projection"] = start
	if not _expect(opening.model is NativeModel and start.inventories.P == 4 and start.opening_engineering.P.phase == "move_source"
		and _same(start.opening_engineering.P.wheel_cell, [-1, 0]), "The actual row-1 first shift continues with a different native upstream target"): return
	var before_confirmation: Dictionary = opening.model.checkpoint()
	opening._confirm_goal()
	if not _expect(opening.goal_confirmed and _same(before_confirmation, opening.model.checkpoint())
		and opening.engineering_presenter.visible and "Move power upstream." in opening.goal_label.text,
		"The existing confirmation reveals the new goal without consuming product or recording progress"): return
	var marker: Node3D = opening.engineering_presenter.get_node("UpstreamRaceMarker")
	if not _expect(marker.position == Vector3(-1.65, 0.04, 0.0) and _same(marker.get_meta("target_wheel_cell"), [-1, 0]),
		"The ordinary marker uses the same native target as eligibility"): return
	var collector := _kind("collector")
	var belt := _kind("belt")
	var press := _kind("processor")
	var wheel := _kind("wheel")
	var material: Dictionary = opening.model.checkpoint().world.state.material.duplicate(true)
	_action("disconnect original source", {"action": "disconnect_drive", "from": wheel, "to": collector}, _pair.bind(3, wheel, collector))
	if written: return
	_remove_part(wheel)
	if written: return
	# Walk toward the stream through the ordinary input/motor. The machine box
	# may stop this approach; the test never writes the body's position.
	_key(KEY_W, true)
	if not (await _until(func(): return opening.model.projection().actors.P.position[2] <= 2.84, "Actual walking approaches the new source site")): return
	_key(KEY_W, false)
	opening.character_presenter.release()
	for _frame: int in range(4):
		await physics_frame
		await process_frame
	opening._select_tool("wheel")
	var placed: Dictionary = _action("place upstream wheel", {"action": "place", "kind": "wheel", "cell": [-1, 0], "axis": "x"}, func(): opening._world_click(Vector2i(-1, 0)))
	if written: return
	wheel = placed.entity
	if not _expect(opening.model.projection().opening_engineering.P.phase == "restore_drive", "Moving the wheel alone cannot satisfy the native challenge"): return
	for _step: int in range(4):
		opening.transmission_controls._heights.id_pressed.emit(0)
	var a := _gear([0, 0, 0])
	if written: return
	var wrong := _gear([1, 0, 4])
	if written: return
	_action("connect upstream shaft", {"action": "connect_drive", "from": wheel, "to": a}, _pair.bind(2, wheel, a))
	if written or not _expect(opening.model.projection().opening_engineering.P.phase == "restore_drive"
		and opening.engineering_presenter.evaluate().diagnostic_code == "gear_plane_mismatch",
		"The failed physical arrangement has an actionable confirmed-state diagnosis"): return
	_remove_part(wrong)
	if written: return
	var b := _gear([0, 0, 4])
	if written: return
	var corrected: Dictionary = opening.model.projection()
	if not _expect(corrected.opening_engineering.P.phase == "deliver_more" and corrected.motion[collector].numerator == -1
		and corrected.opening_engineering.P.placed_gears == 2 and corrected.part_kits.P.gear == 0
		and corrected.entities.has(collector) and corrected.entities.has(belt) and corrected.entities.has(press)
		and _same(material, opening.model.checkpoint().world.state.material),
		"The corrected two-cog route preserves all stocked machines and the exact material cut"): return
	facts["corrected_projection"] = corrected
	for _plate: int in range(4):
		if not (await _until(func(): return opening.model.projection().stock.output == 1, "The repaired native line produces another plate")): return
		if not _retrieve(press): return
	var final: Dictionary = opening.model.projection()
	if not _expect(final.opening_engineering.P.ready and final.opening_engineering.P.products == 8
		and "Upstream drive restored." in opening.goal_label.text and not opening.confirm_button.visible,
		"Eight actual individually collected plates and current native power finish the visible challenge"): return
	if not _expect(opening._save_worksite().accepted and FileAccess.get_sha256(prior_path) == facts.original_save_sha256,
		"The ordinary save preserves the completed worksite without touching its original input"): return
	_finish("pass")
