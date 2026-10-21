extends "res://opening/native_adapter_check.gd"
## Headless callback integration of the real scene, not desktop or human play.
const Geometry = preload("res://opening/site_geometry.gd")

func _point3(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate: Variant in value:
		if typeof(coordinate) != TYPE_FLOAT or not is_finite(coordinate):
			return false
	return true

func _anchor(center: Array) -> Array:
	return [float(center[0]) * Geometry.PITCH / 4.0,
		Geometry.ANCHOR_HEIGHT + float(center[1]) * Geometry.PITCH / 4.0,
		float(center[2]) * Geometry.PITCH / 4.0]

func _screen_click(center: Array) -> void:
	var at := _anchor(center)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = opening.camera.unproject_position(Vector3(at[0], at[1], at[2]))
	opening._unhandled_input(event)

func _invoke(label: String, expected: Dictionary, targets: Array, callback: Callable) -> Dictionary:
	var before: Dictionary = opening.model.checkpoint()
	var sequence: int = opening.request_sequence
	callback.call()
	var after: Dictionary = opening.model.checkpoint()
	var row := {"label": label, "expected": expected.duplicate(true), "before": before,
		"after": after, "sequence_before": sequence, "sequence_after": opening.request_sequence}
	facts.steps.append(row)
	if not _expect(opening.request_sequence == sequence + 1 and after.world.history.order == before.world.history.order + 1,
		label + " must submit exactly one ordinary request"):
		return {}
	var wire: Dictionary = after.world.history.records[-1].intent.wire
	row["wire"] = wire.duplicate(true)
	var payload := wire.duplicate(true)
	for key in ["context", "client", "request"]:
		payload.erase(key)
	if not _expect(_same(expected, payload), label + " must submit the literal UI payload"):
		return {}
	# Read the original receipt by its exact identity. This retry cannot issue
	# another action, change custody or retarget an old receipt to a current pose.
	var outcome: Dictionary = opening.model.command(wire)
	row["outcome"] = outcome.duplicate(true)
	if not _expect(outcome.get("accepted", false) and outcome.get("duplicate", false)
		and _same(after, opening.model.checkpoint()), label + " must have one accepted, unchanged original result"):
		return {}
	var reach: Dictionary = outcome.get("reach", {})
	var cut: Dictionary = opening.actor_world.diagnostics("P", outcome.get("native_epoch", 0))
	row["native_cut"] = cut.duplicate(true)
	var sample: Dictionary = cut.get("sample", {})
	if not _expect(cut.get("available", false) and sample.get("ready", false) and sample.get("registered", false)
		and sample.get("native_epoch", 0) > 0 and sample.native_epoch == outcome.get("native_epoch")
		and sample.native_epoch == reach.get("native_epoch"), label + " must bind the original registered native cut"):
		return {}
	if not _expect(_point3(sample.get("position")) and _point3(sample.get("node_position"))
		and _point3(reach.get("position")) and _point3(outcome.get("actor_position"))
		and _same(sample.position, sample.node_position) and _same(sample.position, reach.position)
		and _same(sample.position, outcome.actor_position), label + " must retain exact three-dimensional body agreement"):
		return {}
	var distances: Array = []
	for target: Variant in targets:
		if not _expect(_point3(target), label + " has a literal finite target"):
			return {}
		var squared := 0.0
		for axis in range(3):
			var delta: float = sample.position[axis] - target[axis]
			squared += delta * delta
		distances.append(squared)
		if not _expect(squared <= 16.0, label + " must be within the real character's four-unit reach"):
			return {}
	if not _expect(reach.get("actor") == "P" and reach.get("build_reach") == 4.0
		and reach.get("reachable") == true and _same(reach.get("targets"), targets)
		and _same(reach.get("distances_squared"), distances), label + " must use the literal geometric endpoints"):
		return {}
	return outcome

func _part_node(id: String) -> Node3D:
	for child: Node in opening.transmission_presenter.get_children():
		if child.get_meta("entity", "") == id:
			return child
	return null

func _direction(id: String, expected: int) -> bool:
	var node := _part_node(id)
	if not _expect(node != null, "The confirmed native part must be rendered"):
		return false
	var arrow: Node = node.get_node_or_null("ConfirmedDirection")
	return _expect(arrow != null and arrow.get_meta("sign", 0) == expected,
		"The visible arrow must match the independently expected signed rate")

func _gear_tool() -> void:
	opening.transmission_controls.get_popup().id_pressed.emit(1)

func _layouts() -> bool:
	var old_size: Vector2i = root.size
	var old_confirmation: bool = opening.goal_confirmed
	var old_details: bool = opening.show_details
	var old_advance: bool = opening.auto_advance
	# This is a disclosed layout fixture, not a claim that this cog-only case
	# produced four plates. The first-shift consumer covers the actual objective.
	opening.goal_confirmed = true
	opening.show_details = true
	opening.auto_advance = false
	facts["layouts"] = []
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(1600, 900)]:
		root.size = size
		opening._refresh_ui()
		# Disclosed long-text fixtures cover the expanded rows without changing
		# inventory, topology, the native projection or the confirmation rules.
		opening.goal_label.text = "Make 4 plates\nBuild a belt beside the collector.\n0 / 4 collected"
		opening.inspector.text = "Cogwheel · Y axis\nGrid [0, 4, 4]\nRate -1 / 1"
		await process_frame
		await process_frame
		var build: Rect2 = opening.tool_buttons.drive.get_parent().get_parent().get_global_rect()
		var worksite: Rect2 = opening.remove_button.get_parent().get_parent().get_global_rect()
		var footer: Rect2 = opening.status_label.get_parent().get_parent().get_global_rect()
		facts.layouts.append({"viewport": [size.x, size.y],
			"build": [build.position.x, build.position.y, build.size.x, build.size.y],
			"worksite": [worksite.position.x, worksite.position.y, worksite.size.x, worksite.size.y],
			"footer": [footer.position.x, footer.position.y, footer.size.x, footer.size.y],
			"fixture_confirmation": true, "fixture_labels": true})
		if not _expect(build.position.x >= 18.0 and build.end.y <= float(size.y - 18)
			and build.end.x <= worksite.position.x and worksite.end.y <= footer.position.y
			and worksite.end.x <= float(size.x - 18) and footer.end.y <= float(size.y - 18),
			"Expanded native tools and confirmed-goal layout must fit the headless viewport"):
			return false
	root.size = old_size
	opening.goal_confirmed = old_confirmation
	opening.show_details = old_details
	opening.auto_advance = old_advance
	opening._refresh_ui()
	return true

func _run() -> void:
	facts.evidence = "ordinary_native_transmission_callback_consumer"
	if destination.is_empty() or mode not in ["controls", "layout"] or FileAccess.file_exists(destination):
		push_error("The transmission scene check needs a fresh output and declared mode")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	root.add_child(opening)
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		await process_frame
		if opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending:
			break
	if mode == "layout":
		facts.evidence = "headless_native_transmission_layout_fixture"
		opening.show_all_tools = true
		if await _layouts():
			_record("pass")
		return
	if not _expect(opening.model is NativeModel and opening.model.native.get_class() == "FactoryNativeWorld"
		and opening.actor_world.bodies.P.is_on_floor() and opening.state.actors.P.ready,
		"The ordinary opening must use one native World and a real settled actor"):
		return
	if not _expect(opening.transmission_controls != null and opening.transmission_presenter != null
		and not opening.transmission_controls.visible, "The fresh guided opening must mount but not dump extra tools"):
		return
	opening._toggle_all_tools()
	if not _expect(opening.transmission_controls.visible, "All tools must expose the native transmission menu"):
		return
	opening.transmission_controls._axes.id_pressed.emit(1)
	if not _expect(opening.transmission_controls.selected_axis == "y", "The ordinary axis menu must select Y"):
		return
	opening._select_tool("wheel")
	var wheel := _invoke("oriented wheel", {"action": "place", "kind": "wheel", "cell": [-1, 1], "axis": "y"},
		[_anchor([-4, 0, 4])], func(): opening._world_click(Vector2i(-1, 1)))
	if wheel.is_empty():
		return
	opening._select_tool("collector")
	var collector := _invoke("oriented collector", {"action": "place", "kind": "collector", "cell": [0, 1], "axis": "y"},
		[_anchor([0, 0, 4])], func(): opening._world_click(Vector2i(0, 1)))
	if collector.is_empty():
		return
	_gear_tool()
	var original: Dictionary = opening.model.checkpoint()
	var original_sequence: int = opening.request_sequence
	if not _expect(opening._transmission_click([0.25, 4, 4], "") and opening.request_sequence == original_sequence
		and _same(original, opening.model.checkpoint()), "An invalid active gear click must be consumed without an old machine placement"):
		return
	var a := _invoke("first screen-picked cog", {"action": "place_gear", "center": [-4, 4, 4], "axis": "y", "teeth": 2},
		[_anchor([-4, 4, 4])], func(): _screen_click([-4, 4, 4]))
	if a.is_empty():
		return
	var b := _invoke("second screen-picked cog", {"action": "place_gear", "center": [0, 4, 4], "axis": "y", "teeth": 2},
		[_anchor([0, 4, 4])], func(): _screen_click([0, 4, 4]))
	if b.is_empty():
		return
	await physics_frame
	await process_frame
	for pair in [[a.entity, [-4, 4, 4]], [b.entity, [0, 4, 4]]]:
		var at := _anchor(pair[1])
		var screen: Vector2 = opening.camera.unproject_position(Vector3(at[0], at[1], at[2]))
		if not _expect(opening._screen_entity(screen) == pair[0], "A rendered individual cog must be selectable through its real pick body"):
			return
	opening._select_tool("drive")
	if not _expect(opening.transmission_controls.active_tool == "shaft", "G's existing entry must select the finite native shaft tool"):
		return
	opening._world_click(Vector2i(-1, 1), wheel.entity)
	if _invoke("vertical source shaft", {"action": "connect_drive", "from": wheel.entity, "to": a.entity},
		[_anchor([-4, 0, 4]), _anchor([-4, 4, 4])], func(): opening._world_click(Vector2i(-1, 1), a.entity)).is_empty():
		return
	opening._world_click(Vector2i(0, 1), b.entity)
	if _invoke("vertical output shaft", {"action": "connect_drive", "from": b.entity, "to": collector.entity},
		[_anchor([0, 4, 4]), _anchor([0, 0, 4])], func(): opening._world_click(Vector2i(0, 1), collector.entity)).is_empty():
		return
	if not _expect(not opening.state.power_enabled, "The native worksite starts with its drive switched off"):
		return
	if _invoke("ordinary Start drive button", {"action": "set_power", "active": true}, [_anchor([-4, 0, 4])],
		func(): opening.power_button.pressed.emit()).is_empty():
		return
	if not _direction(a.entity, 1) or not _direction(b.entity, -1):
		return
	if not _expect(opening.state.powered and opening.state.power_enabled and opening.state.part_kits.P.shaft == 2
		and opening.state.part_kits.P.gear == 3, "Confirmed geometry must power the collector with the exact finite remainder"):
		return
	var anchor := _part_node(a.entity)
	var pick: Node = anchor.get_node("Pick")
	opening._refresh()
	opening._refresh()
	if not _expect(is_instance_valid(anchor) and is_instance_valid(pick) and _part_node(a.entity) == anchor,
		"Unchanged ordinary refresh must preserve mesh and pick-body identities"):
		return
	opening._select_tool("inspect")
	opening._world_click(Vector2i(0, 1), b.entity)
	if not _expect(opening.selected == b.entity and not opening.remove_button.disabled
		and "Cogwheel" in opening.inspector.text, "The ordinary inspector must select and offer removal for a real cog"):
		return
	if _invoke("powered inspector removal", {"action": "remove", "entity": b.entity}, [_anchor([0, 4, 4])],
		func(): opening.remove_button.pressed.emit()).is_empty():
		return
	if not _expect(opening.state.power_enabled and not opening.state.powered,
		"Removing the cog while running must break actual transmission without stopping the drive"):
		return
	_gear_tool()
	var misplaced := _invoke("screen-picked misalignment", {"action": "place_gear", "center": [1, 4, 4], "axis": "y", "teeth": 2},
		[_anchor([1, 4, 4])], func(): _screen_click([1, 4, 4]))
	if misplaced.is_empty() or not _expect(not opening.state.powered, "One quarter-step misalignment must remain visibly disconnected"):
		return
	opening.transmission_controls.get_popup().id_pressed.emit(4)
	if _invoke("menu transmission removal", {"action": "remove", "entity": misplaced.entity}, [_anchor([1, 4, 4])],
		func(): opening._world_click(Vector2i(0, 1), misplaced.entity)).is_empty():
		return
	_gear_tool()
	var rebuilt := _invoke("correct screen-picked rebuild", {"action": "place_gear", "center": [0, 4, 4], "axis": "y", "teeth": 2},
		[_anchor([0, 4, 4])], func(): _screen_click([0, 4, 4]))
	if rebuilt.is_empty() or not _expect(rebuilt.entity != b.entity and opening.state.powered,
		"Correct ordinary rebuilding must restore geometric power with a new identity") or not _direction(rebuilt.entity, -1):
		return
	var test_parent := Node3D.new()
	test_parent.rotation = Vector3(0.3, 0.6, 0.2)
	root.add_child(test_parent)
	for end in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, Vector3(1, 1, 1)]:
		opening._bar(test_parent, Vector3.ZERO, end, 0.09, Color.WHITE)
		var bar: Node3D = test_parent.get_children()[-1]
		if not _expect(bar.basis.is_finite() and absf(bar.basis.determinant() - 1.0) < 0.00001
			and (-bar.basis.z).is_equal_approx(end.normalized()), "Every local shaft axis must have a finite noncollinear basis"):
			return
	test_parent.queue_free()
	if not _expect(opening.state.order == 11 and opening.state.part_kits.P.gear == 3 and opening.state.part_kits.P.shaft == 2,
		"The eleven real UI requests must preserve all five cogs and four shafts"):
		return
	if not await _layouts():
		return
	_record("pass")
