extends "res://opening/native_adapter_check.gd"
## Native scene callback integration without desktop input.
const Geometry = preload("res://opening/site_geometry.gd")

func _point3(value: Variant) -> bool:
	return value is Array and value.size() == 3 and value.all(
		func(coordinate: Variant) -> bool: return typeof(coordinate) == TYPE_FLOAT and is_finite(coordinate))

func _anchor(center: Array) -> Array:
	return [float(center[0]) * Geometry.PITCH / 4.0,
		Geometry.ANCHOR_HEIGHT + float(center[1]) * Geometry.PITCH / 4.0,
		float(center[2]) * Geometry.PITCH / 4.0]

func _screen_click(center: Array) -> void:
	var at := _anchor(center)
	for offset in [Vector2.ZERO, Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
		var pixel: Vector2 = opening.camera.unproject_position(Vector3(at[0] + offset.x, at[1], at[2] + offset.y))
		if opening._transmission_center(pixel) != center:
			continue
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = pixel
		opening._unhandled_input(event)
		return
	_expect(false, "No exposed pointer ray resolves to the declared tile.")

func _invoke(label: String, expected: Dictionary, targets: Array, callback: Callable) -> Dictionary:
	var before: Dictionary = opening.model.checkpoint()
	var sequence: int = opening.request_sequence
	callback.call()
	if written:
		return {}
	var after: Dictionary = opening.model.checkpoint()
	var row := {"label": label, "expected": expected.duplicate(true), "before": before,
		"after": after, "sequence_before": sequence, "sequence_after": opening.request_sequence}
	facts.steps.append(row)
	if not _expect(opening.request_sequence == sequence + 1 and after.world.history.order == before.world.history.order + 1,
		"One ordinary request advances history once."):
		return {}
	var wire: Dictionary = after.world.history.records[-1].intent.wire
	row["wire"] = wire.duplicate(true)
	var payload := wire.duplicate(true)
	for key in ["context", "client", "request"]:
		payload.erase(key)
	if not _expect(_same(expected, payload), "The literal UI payload matches exactly."):
		return {}
	var outcome: Dictionary = opening.model.command(wire)
	row["outcome"] = outcome.duplicate(true)
	if not _expect(outcome.get("accepted", false) and outcome.get("duplicate", false)
		and _same(after, opening.model.checkpoint()), "The cached result preserves the typed checkpoint."):
		return {}
	var reach: Dictionary = outcome.get("reach", {})
	var cut: Dictionary = opening.actor_world.diagnostics("P", outcome.get("native_epoch", 0))
	row["native_cut"] = cut.duplicate(true)
	var sample: Dictionary = cut.get("sample", {})
	if not _expect(cut.get("available", false) and sample.get("ready", false) and sample.get("registered", false)
		and sample.get("native_epoch", 0) > 0 and sample.native_epoch == outcome.get("native_epoch")
		and sample.native_epoch == reach.get("native_epoch"), "The receipt binds its original native cut."):
		return {}
	if not _expect(_point3(sample.get("position")) and _point3(sample.get("node_position"))
		and _point3(reach.get("position")) and _point3(outcome.get("actor_position"))
		and _same(sample.position, sample.node_position) and _same(sample.position, reach.position)
		and _same(sample.position, outcome.actor_position), "All native admission positions agree exactly."):
		return {}
	var distances: Array = []
	for target: Variant in targets:
		if not _expect(_point3(target), "Each target has three finite coordinates."):
			return {}
		var squared := 0.0
		for axis in range(3):
			var delta: float = sample.position[axis] - target[axis]
			squared += delta * delta
		distances.append(squared)
		if not _expect(squared <= 16.0, "Each target is within four metres."):
			return {}
	if not _expect(reach.get("actor") == "P" and reach.get("build_reach") == 4.0
		and reach.get("reachable") == true and _same(reach.get("targets"), targets)
		and _same(reach.get("distances_squared"), distances), "Literal reach endpoints and distances agree."):
		return {}
	return outcome

func _part_node(id: String) -> Node3D:
	for child: Node in opening.transmission_presenter.get_children():
		if child.get_meta("entity", "") == id:
			return child
	return null

func _direction(id: String, expected: int) -> bool:
	var node := _part_node(id)
	if not _expect(node != null, "The native part has a visible node."):
		return false
	var arrow: Node = node.get_node_or_null("ConfirmedDirection")
	return _expect(arrow != null and arrow.get_meta("sign", 0) == expected,
		"Arrow signs match the expected signed rate.")

func _gear_tool() -> void:
	opening.transmission_controls.get_popup().id_pressed.emit(1)

func _cog(center: Array, axis: String, teeth: int) -> Dictionary:
	opening.transmission_controls._axes.id_pressed.emit(["x", "y", "z"].find(axis))
	opening.transmission_controls._sizes.id_pressed.emit(1 if teeth == 4 else 0)
	_gear_tool()
	return _invoke("screen-picked cog", {"action": "place_gear", "center": center, "axis": axis, "teeth": teeth},
		[_anchor(center)], _screen_click.bind(center))

func _pick_cog(id: String, center: Array) -> bool:
	await physics_frame
	await process_frame
	var at := _anchor(center)
	return _expect(opening._screen_entity(opening.camera.unproject_position(Vector3(at[0], at[1], at[2]))) == id,
		"The exposed cog is picked by identity.")

func _layouts() -> bool:
	var old_size: Vector2i = root.size
	var old_confirmation: bool = opening.goal_confirmed
	var old_details: bool = opening.show_details
	var old_advance: bool = opening.auto_advance
	# This UI-only fixture does not establish production.
	opening.goal_confirmed = true
	opening.show_details = true
	opening.auto_advance = false
	facts["layouts"] = []
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(1600, 900)]:
		root.size = size
		opening._refresh_ui()
		opening.goal_label.text = "Make 4 plates\nBuild a belt beside the collector.\n0 / 4 collected"
		opening.inspector.text = "Cogwheel · Z axis\nGrid [0, 4, 12]\nRate -1 / 21"
		await process_frame
		await process_frame
		var build: Rect2 = opening.build_column.get_parent().get_global_rect()
		var worksite: Rect2 = opening.remove_button.get_parent().get_parent().get_global_rect()
		var footer: Rect2 = opening.status_label.get_parent().get_parent().get_global_rect()
		var hotbar: Rect2 = opening.building_hotbar.get_global_rect()
		var row := {"viewport": [size.x, size.y], "fixture_confirmation": true, "fixture_labels": true}
		var named := {"build": build, "worksite": worksite, "footer": footer, "hotbar": hotbar}
		for name: String in named:
			var rect: Rect2 = named[name]
			row[name] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		facts.layouts.append(row)
		var panels := [build, worksite, footer, hotbar]
		for index in range(panels.size()):
			if not _expect(Rect2(Vector2(18, 18), Vector2(size) - Vector2(36, 36)).encloses(panels[index]),
				"Each visible panel fits inside the viewport margins."):
				return false
			for prior in range(index):
				if not _expect(not panels[index].intersects(panels[prior]), "Visible panels do not overlap."):
					return false
		if not _expect(build.encloses(opening.transmission_controls.get_global_rect())
			and worksite.encloses(opening.inspector.get_global_rect()), "Expanded native controls fit their panels."):
			return false
	root.size = old_size
	opening.goal_confirmed = old_confirmation
	opening.show_details = old_details
	opening.auto_advance = old_advance
	opening._refresh_ui()
	return true

func _run() -> void:
	facts.evidence = "native_transmission_scene_consumer"
	if destination.is_empty() or mode != "controls" or FileAccess.file_exists(destination):
		push_error("Use controls mode and a fresh output.")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	root.add_child(opening)
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		await process_frame
		if opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending:
			break
	if not _expect(opening.model is NativeModel and opening.model.native.get_class() == "FactoryNativeWorld"
		and opening.actor_world.bodies.P.is_on_floor() and opening.state.actors.P.ready,
		"The scene owns one native World and a settled actor."):
		return
	if not _expect(opening.transmission_controls != null and opening.transmission_presenter != null
		and not opening.transmission_controls.visible, "Fresh guidance keeps extra tools folded."):
		return
	opening._select_tool("gear")
	if not _expect(opening.transmission_controls.visible, "The gear tool exposes its settings."):
		return
	opening.character_presenter.set_physics_process(false)
	opening.transmission_controls._axes.id_pressed.emit(0)
	opening.transmission_controls.auto_height = false
	opening.transmission_controls.gear_height = 0
	opening.transmission_controls._heights.id_pressed.emit(1)
	if not _expect(opening.transmission_controls.gear_height == 4, "Height rises one shared tile."): return
	opening._select_tool("wheel")
	var wheel := _invoke("immersed X wheel", {"action": "place", "kind": "wheel", "cell": [-2, 2], "axis": "x", "level": 4, "tiles": 3},
		[_anchor([-8, 4, 8])], func(): opening._world_click(Vector2i(-2, 2)))
	if wheel.is_empty(): return
	var key := InputEventKey.new()
	key.keycode = KEY_G
	key.pressed = true
	opening._unhandled_input(key)
	if not _expect(opening.transmission_controls.active_tool == "place_shaft", "G selects finite shaft placement."): return
	if _invoke("west X shaft", {"action": "place_shaft", "center": [-12, 4, 8], "axis": "x", "half_span": 2},
		[_anchor([-12, 4, 8])], func(): opening._transmission_click([-12, 4, 8], "")).is_empty(): return
	if not await _approach(Vector2(0.7, 3.3)): return
	opening._select_tool("foundation")
	if _invoke("collector floor", {"action": "place_foundation", "cell": [0, 1], "level": 4},
		[_anchor([0, 4, 4])], func(): opening._world_click(Vector2i(0, 1))).is_empty(): return
	opening._select_tool("collector")
	opening.transmission_controls._axes.id_pressed.emit(2)
	var collector := _invoke("Z collector", {"action": "place", "kind": "collector", "cell": [0, 1], "axis": "z", "level": 4, "rotation": 0},
		[_anchor([0, 4, 4])], func(): opening._world_click(Vector2i(0, 1)))
	if collector.is_empty(): return
	_gear_tool()
	var original: Dictionary = opening.model.checkpoint()
	var sequence: int = opening.request_sequence
	if not _expect(opening._transmission_click([0.25, 4, 4], "") and opening.request_sequence == sequence
		and _same(original, opening.model.checkpoint()), "Invalid active clicks submit no request."): return
	var a := _cog([-4, 4, 8], "x", 4)
	if a.is_empty() or not await _pick_cog(a.entity, [-4, 4, 8]): return
	var b := _cog([0, 4, 12], "z", 4)
	if b.is_empty() or not await _pick_cog(b.entity, [0, 4, 12]): return
	opening._select_tool("drive")
	if _invoke("collector Z shaft", {"action": "place_shaft", "center": [0, 4, 8], "axis": "z", "half_span": 2},
		[_anchor([0, 4, 8])], func(): opening._transmission_click([0, 4, 8], "")).is_empty(): return
	var c := _cog([0, 4, 16], "z", 2)
	if c.is_empty(): return
	var d := _cog([4, 4, 16], "z", 2)
	if d.is_empty(): return
	if not await _approach(Vector2(0.7, 2.9)) or not await _approach(Vector2(0.0, 2.9)): return
	if not _expect(not opening.state.power_enabled, "The fresh source starts switched off."): return
	if _invoke("Start drive button", {"action": "set_power", "active": true}, [_anchor([-8, 4, 8])],
		func(): opening.power_button.pressed.emit()).is_empty(): return
	if not _direction(a.entity, -1) or not _direction(b.entity, -1) or not _direction(d.entity, 1): return
	if not _expect(opening.state.powered, "Confirmed geometry powers the collector."): return
	var anchor := _part_node(a.entity)
	var pick: Node = anchor.get_node("Pick")
	opening._refresh()
	opening._refresh()
	if not _expect(is_instance_valid(anchor) and is_instance_valid(pick) and _part_node(a.entity) == anchor,
		"Unchanged refresh preserves mesh and pick identities."): return
	opening._select_tool("inspect")
	opening._world_click(Vector2i(0, 3), b.entity)
	if not _expect(opening.selected == b.entity and not opening.remove_button.disabled
		and "Cogwheel" in opening.inspector.text, "The inspector selects and offers removal for the real cog."): return
	if _invoke("powered inspector removal", {"action": "remove", "entity": b.entity}, [_anchor([0, 4, 12])],
		func(): opening.remove_button.pressed.emit()).is_empty(): return
	if not _expect(opening.state.power_enabled and not opening.state.powered, "Running removal breaks collector transmission."): return
	var misplaced := _cog([4, 4, 12], "z", 4)
	if misplaced.is_empty() or not _expect(not opening.state.powered, "A legal one-tile displacement stays disconnected."): return
	opening.transmission_controls.get_popup().id_pressed.emit(4)
	if _invoke("menu removal", {"action": "remove", "entity": misplaced.entity}, [_anchor([4, 4, 12])],
		func(): opening._world_click(Vector2i(1, 3), misplaced.entity)).is_empty(): return
	var rebuilt := _cog([0, 4, 12], "z", 4)
	if rebuilt.is_empty() or not _expect(rebuilt.entity != b.entity and opening.state.powered,
		"Correct rebuilding restores power with a new identity.") or not _direction(rebuilt.entity, -1): return
	if not _expect(opening.state.order == 14 and _same(opening.state.part_kits.P,
		{"collector": 0, "belt": 2, "processor": 1, "wheel": 0, "gear": 6, "shaft": 6, "foundation": 23}),
		"Fourteen requests conserve the kit."): return
	var units := 0
	for amount: Variant in opening.state.stock.values():
		if not _expect(typeof(amount) == TYPE_INT and amount >= 0, "Material counts remain nonnegative integers."): return
		units += amount
	if not _expect(units == 4096 and opening.state.line_belt_raw == 0 and opening.state.cargo.P.raw == 0,
		"Native custody conserves all material."): return
	if not await _layouts():
		return
	var saved: Dictionary = opening._save_worksite()
	if not _expect(saved.accepted and saved.native_preflight.accepted, "Guarded Store publication accepts the worksite."): return
	facts["save_slot"] = opening.save_slot
	_record("pass")
