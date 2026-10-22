extends "res://opening/native_first_shift_check.gd"
## Native continuation from four actual plates; in-process callbacks and motor.

func _anchor(part: Dictionary) -> Array:
	return [float(part.center[0]) * 0.4125, 0.825 + float(part.center[1]) * 0.4125,
		float(part.center[2]) * 0.4125]

func _targets(before: Dictionary, action: Dictionary) -> Array:
	if action.action == "remove":
		return [_anchor(before.entities.get(action.entity, before.transmission_parts.get(action.entity, {})))]
	return super._targets(before, action)

func _cell(id: String) -> Vector2i:
	var part: Dictionary = opening.state.entities.get(id, opening.state.transmission_parts.get(id, {}))
	return Vector2i(roundi(float(part.center[0]) / 4.0), roundi(float(part.center[2]) / 4.0))

func _screen_place(center: Array) -> void:
	var point := _anchor({"center": center})
	for offset in [Vector2.ZERO, Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
		var pixel: Vector2 = opening.camera.unproject_position(Vector3(point[0] + offset.x, point[1], point[2] + offset.y))
		if opening._transmission_center(pixel) != center:
			continue
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = pixel
		opening._unhandled_input(event)
		return
	_expect(false, "An exposed pointer ray must resolve to the declared tile.")

func _gear(center: Array, axis: String, teeth: int) -> String:
	opening.transmission_controls._axes.id_pressed.emit(0 if axis == "x" else 2)
	opening.transmission_controls._sizes.id_pressed.emit(1 if teeth == 4 else 0)
	opening.transmission_controls.get_popup().id_pressed.emit(1)
	var reply := _action("screen-place cog", {"action": "place_gear", "center": center, "axis": axis, "teeth": teeth},
		_screen_place.bind(center))
	return str(reply.get("entity", ""))

func _remove_part(id: String) -> void:
	opening._select_tool("inspect")
	opening._world_click(_cell(id), id)
	_action("remove confirmed part", {"action": "remove", "entity": id}, opening._remove_selected)

func _kind(kind: String) -> String:
	for id: String in opening.state.entities:
		if opening.state.entities[id].kind == kind: return id
	return ""

func _run() -> void:
	facts.evidence = "native_upstream_drive_continuation"
	if mode != "challenge" or not destination.is_absolute_path() or FileAccess.file_exists(destination) or not FileAccess.file_exists(prior_path):
		push_error("Use challenge mode, the original four-plate packet and a fresh output.")
		quit(1)
		return
	var file := FileAccess.open(prior_path, FileAccess.READ)
	if not _expect(file != null and file.get_length() <= 8388608, "The original packet is bounded."): return
	var prior: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	if not _expect(prior is Dictionary and prior.get("status") == "pass" and prior.get("mode") == "resume",
		"The original first-shift continuation passed."): return
	var original_slot := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="): original_slot = argument.trim_prefix("--resume-input=")
	if not _expect(original_slot.is_absolute_path() and FileAccess.file_exists(original_slot), "The original Store input exists."): return
	facts["original_save_sha256"] = FileAccess.get_sha256(original_slot)
	opening = load("res://opening/opening.tscn").instantiate()
	root.add_child(opening)
	if not (await _until(func(): return opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending,
		"The reopened worksite has a fresh settled character.")): return
	var start: Dictionary = opening.model.projection()
	facts["initial_projection"] = start
	if not _expect(opening.model is NativeModel and opening.auto_advance and opening.save_slot != original_slot
		and _same(opening.startup_resume_checkpoint.world, prior.final_checkpoint.world)
		and opening.request_sequence == 0 and start.inventories.P == 4 and start.opening_engineering.P.phase == "move_source"
		and _same(start.opening_engineering.P.wheel_cell, [-2, 0]), "The actual four-plate World resumes toward the current native target."): return
	var before_confirmation: Dictionary = opening.model.checkpoint()
	opening._confirm_goal()
	facts["confirmation"] = {"goal": opening.goal_label.text, "visible": opening.engineering_presenter.visible,
		"children": opening.engineering_presenter.get_child_count()}
	if not _expect(opening.goal_confirmed and _same(before_confirmation, opening.model.checkpoint())
		and opening.engineering_presenter.visible and "Move power upstream." in opening.goal_label.text
		and opening.engineering_presenter.get_child_count() == 0, "Confirmation reveals UI guidance without consuming product or adding world props."): return
	var collector := _kind("collector")
	var press := _kind("processor")
	var wheel := _kind("wheel")
	opening.character_presenter.set_physics_process(false)
	# Go around the stocked line using the motor, without passing through it.
	if not await _approach_axis(0, 6.6) or not await _approach_axis(2, -3.3) \
		or not await _approach_axis(0, -1.9) or not await _approach_axis(2, -1.2): return
	if not _power(false): return
	var frozen: Dictionary = opening.model.projection()
	var material: Dictionary = opening.model.checkpoint().world.state.material.duplicate(true)
	facts["frozen_material"] = material
	_remove_part(wheel)
	if written: return
	var wheel_action := {"action": "place", "kind": "wheel", "cell": [-2, 0], "axis": "x", "level": 8, "tiles": 5}
	var placed := _action("larger upstream wheel", wheel_action, func():
		opening._select_tool("wheel")
		opening.transmission_controls._axes.id_pressed.emit(0)
		opening.wheel_level = 8
		opening.wheel_tiles = 5
		opening._world_click(Vector2i(-2, 0)))
	wheel = str(placed.get("entity", ""))
	if written or wheel.is_empty(): return
	if not _expect(opening.state.opening_engineering.P.phase == "restore_drive", "Moving the immersed wheel alone leaves the line disconnected."): return
	# Raise the corner above the outcrop on the shared grid. The larger wheel
	# remains immersed; a diagonal mesh drives the existing lower relay.
	for id: String in frozen.transmission_parts:
		var part: Dictionary = frozen.transmission_parts[id]
		if part.kind == "gear" and part.teeth == 4:
			_remove_part(id)
			if written: return
	if _setup({"action": "place_foundation", "cell": [-1, 0], "level": 8}).is_empty(): return
	if _setup({"action": "place_shaft", "center": [0, 4, 0], "axis": "z", "half_span": 2}).is_empty(): return
	opening.transmission_controls.auto_height = false
	opening.transmission_controls.gear_height = 8
	if _gear([-4, 8, 0], "x", 4).is_empty(): return
	if not await _approach_axis(2, -4.95) or not await _approach_axis(0, 0.0): return
	var wrong := _gear([0, 8, -8], "z", 4)
	if written or wrong.is_empty(): return
	if not await _approach_axis(0, -1.9) or not await _approach_axis(2, -1.2) or not _power(true): return
	if not _expect(opening.state.opening_engineering.P.phase == "restore_drive"
		and opening.engineering_presenter.evaluate().diagnostic_code == "missing_drive_shaft",
		"The legal disconnected bridge has current confirmed-state advice."): return
	if not _power(false) or not await _approach_axis(2, -4.95) or not await _approach_axis(0, 0.0): return
	_remove_part(wrong)
	if written: return
	if not await _approach_axis(0, -0.7) or not await _approach_axis(2, -3.3): return
	var repaired := _gear([0, 8, -4], "z", 4)
	if written or repaired.is_empty(): return
	if not _expect(_same(material, opening.model.checkpoint().world.state.material), "The stopped correction preserves the complete typed material cut."): return
	if not await _approach_axis(0, -1.9) or not await _approach_axis(2, -1.2) or not _power(true): return
	var corrected: Dictionary = opening.model.projection()
	var source_rate: Dictionary = corrected.motion[wheel]
	var collector_rate: Dictionary = corrected.motion[collector]
	if not _expect(corrected.opening_engineering.P.phase == "deliver_more" and repaired != wrong
		and collector_rate.numerator * source_rate.denominator == -2 * source_rate.numerator * collector_rate.denominator
		and corrected.transmission_parts.size() == frozen.transmission_parts.size() + 1
		and corrected.part_kits.P.gear == frozen.part_kits.P.gear and corrected.part_kits.P.shaft == frozen.part_kits.P.shaft - 1
		and corrected.part_kits.P.foundation == frozen.part_kits.P.foundation - 1
		and corrected.entities.has(collector) and corrected.entities.has(press)
		and _same(corrected.belt_spans, frozen.belt_spans)
		and _same(material, opening.model.checkpoint().world.state.material),
		"The raised corner restores the stocked line at the expected signed ratio without losing material."): return
	for id: String in frozen.foundations:
		if not _expect(_same(corrected.foundations.get(id), frozen.foundations[id]), "Original floors retain their identities."): return
	facts["corrected_projection"] = corrected
	if not await _approach_axis(2, -3.3) or not await _approach_axis(0, 6.6) \
		or not await _approach_axis(2, 3.3) or not await _approach_axis(0, 4.95): return
	for _plate: int in range(4):
		if not (await _until(func(): return opening.model.projection().stock.output == 1, "The restored native line produces another plate.")): return
		if not _retrieve(press): return
	var final: Dictionary = opening.model.projection()
	if not _expect(final.opening_engineering.P.ready and final.opening_engineering.P.products == 8
		and "Upstream drive restored." in opening.goal_label.text and not opening.confirm_button.visible
		and opening.engineering_presenter.get_child_count() == 0,
		"Eight individually collected plates and live native power complete the UI goal without world props."): return
	if not _expect(opening._save_worksite().accepted and FileAccess.get_sha256(original_slot) == facts.original_save_sha256,
		"The fresh output leaves the original Store bytes unchanged."): return
	facts["save_slot"] = opening.save_slot
	_finish("pass")
