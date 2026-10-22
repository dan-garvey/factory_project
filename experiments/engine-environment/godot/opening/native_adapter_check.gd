extends SceneTree
## Automated headless consumer of the ordinary scene, not a desktop playtest.
const NativeModel = preload("res://opening/native_model.gd")
const OpeningGeometry = preload("res://opening/site_geometry.gd")
var opening
var destination := ""
var mode := ""
var checks := 0
var deadline := 0
var facts: Dictionary = {"steps": [], "evidence": "native_offline_scene_consumer"}
var written := false

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--native-check-output="):
			destination = argument.trim_prefix("--native-check-output=")
		if argument.begins_with("--native-check-mode="):
			mode = argument.trim_prefix("--native-check-mode=")
	deadline = Time.get_ticks_msec() + (45000 if mode == "foundations" else 60000)
	call_deferred("_run")

func _same(expected: Variant, actual: Variant, depth: int = 0) -> bool:
	if depth > 32 or typeof(expected) != typeof(actual):
		return false
	if expected is Dictionary:
		if expected.size() != actual.size():
			return false
		for key in expected:
			if not actual.has(key) or not _same(expected[key], actual[key], depth + 1):
				return false
		return true
	if expected is Array:
		if expected.size() != actual.size():
			return false
		for index in range(expected.size()):
			if not _same(expected[index], actual[index], depth + 1):
				return false
		return true
	return expected == actual

func _record(status: String, reason: String = "") -> void:
	if written:
		return
	written = true
	facts.merge({"status": status, "reason": reason, "mode": mode, "checks": checks,
		"process_id": OS.get_process_id(), "physics_frames": Engine.get_physics_frames()})
	if opening != null and opening.model != null:
		facts["final_projection"] = opening.model.projection()
		facts["final_checkpoint"] = opening.model.checkpoint()
		if opening.actor_world != null:
			facts["producer"] = opening.actor_world.diagnostics()
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		push_error("Cannot retain the native adapter consumer result")
		quit(1)
		return
	# The binary retains integer/float distinctions. JSON is only a short log.
	file.store_buffer(var_to_bytes(facts))
	file.close()
	if opening != null:
		opening.free()
		opening = null
	print(JSON.stringify({"status": status, "evidence": facts.evidence, "mode": mode, "checks": checks, "reason": reason,
		"failure_step": facts.steps[-1] if status == "fail" and not facts.steps.is_empty() else {}}))
	quit(0 if status == "pass" else 1)

func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		_record("fail", message)
		push_error(message)
	return condition

func _issue(action: Dictionary) -> Dictionary:
	var reply: Dictionary = opening.issue(action)
	var cut: Dictionary = {}
	if reply.get("reach") is Dictionary:
		cut = opening.actor_world.diagnostics("P", reply.reach.native_epoch)
	facts.steps.append({"action": action.duplicate(true), "reply": reply.duplicate(true), "native_cut": cut})
	return reply

func _construct(action: Dictionary) -> Dictionary:
	var reply := _issue(action)
	return reply if _expect(reply.get("accepted", false), "The current immersed route admits " + str(action)) else {}

func _approach(target: Vector2) -> bool:
	if not await _walk_to(target):
		return false
	for _frame in range(4):
		await physics_frame
		await process_frame
	var sample: Dictionary = opening.actor_world.diagnostics("P").sample
	return _expect(sample.ready and sample.registered and sample.on_floor and sample.control == [0.0, 0.0],
		"The real approach finishes with a released, registered actor on the floor")

func _collector_route() -> Dictionary:
	# Two large corner cogs turn the horizontal wheel's X axle onto Z. The
	# actual shaft between the output cog and collector is removable stock.
	var wheel := _construct({"action": "place", "kind": "wheel", "cell": [-2, 2], "axis": "x", "level": 4})
	if wheel.is_empty() or not await _approach(Vector2(0.7, 3.3)):
		return {}
	if _construct({"action": "place_foundation", "cell": [0, 1], "level": 4}).is_empty():
		return {}
	var collector := _construct({"action": "place", "kind": "collector", "cell": [0, 1], "axis": "z", "level": 4})
	if collector.is_empty():
		return {}
	var source_cog := _construct({"action": "place_gear", "center": [-4, 4, 8], "axis": "x", "teeth": 4})
	var output_cog := {} if written else _construct({"action": "place_gear", "center": [0, 4, 12], "axis": "z", "teeth": 4})
	var shaft := {} if written else _construct({"action": "place_shaft", "center": [0, 4, 8], "axis": "z", "half_span": 2})
	if written or source_cog.is_empty() or output_cog.is_empty() or shaft.is_empty():
		return {}
	# Keep the character clear of the stand and within genuine source reach.
	if not await _approach(Vector2(0.7, 2.9)) or not await _approach(Vector2(0.0, 2.9)):
		return {}
	return {"wheel": wheel.entity, "collector": collector.entity,
		"source_cog": source_cog.entity, "output_cog": output_cog.entity, "shaft": shaft.entity}

func _run() -> void:
	if mode in ["arrival-press", "arrival-resume"]:
		await _arrival_run()
		return
	if destination.is_empty() or mode not in ["produce", "resume", "foundations"]:
		push_error("The native adapter check requires an output and a declared mode")
		quit(1)
		return
	if FileAccess.file_exists(destination):
		push_error("The native adapter check refuses an existing result")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	opening.auto_advance = false
	root.add_child(opening)
	if not _expect(opening.model is NativeModel and opening.model.native.get_class() == "FactoryNativeWorld", "The ordinary scene must own the native model"):
		return
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		await process_frame
		if opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending:
			break
	if not _expect(opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending, "A real registered actor must reach the floor before commands"):
		return
	facts["initial_projection"] = opening.model.projection()
	facts["initial_native"] = opening.actor_world.diagnostics("P")
	if mode == "foundations":
		await _foundations()
		return
	if mode == "resume":
		_resume()
		return
	var route: Dictionary = await _collector_route()
	if route.is_empty():
		return
	opening.auto_advance = true
	while Time.get_ticks_msec() < deadline and opening.model.projection().stock.collector != 1:
		await process_frame
	var before: Dictionary = opening.model.projection()
	if not _expect(before.initial_feed == 4096 and before.stock.source == 4095 and before.stock.collector == 1 and before.powered,
		"The ordinary scene's default clock extracts one unit from the current finite reserve"):
		return
	if not _expect(_issue({"action": "recover", "entity": route.collector}).accepted, "Recovery moves the original raw unit into cargo"):
		return
	var recovery_wire: Dictionary = opening.model.checkpoint().world.history.records[-1].intent.wire
	if not _expect(_issue({"action": "remove", "entity": route.collector}).accepted and opening.model.projection().power_enabled,
		"An emptied collector can be removed with the source still enabled"):
		return
	var rebuilt: Dictionary = _issue({"action": "place", "kind": "collector", "cell": [0, 1], "axis": "z", "level": 4})
	if not _expect(rebuilt.accepted and rebuilt.entity != route.collector, "Rebuilding issues a new entity identity"):
		return
	var retry: Dictionary = opening.model.command(recovery_wire)
	facts["historical_retry"] = retry
	if not _expect(retry.accepted and retry.duplicate and retry.entity == route.collector, "An exact retry retains the removed target's original recovery"):
		return
	if not _expect(_issue({"action": "insert_raw", "entity": rebuilt.entity, "amount": 1}).accepted, "The carried unit returns without refill or conversion"):
		return
	var final: Dictionary = opening.model.projection()
	if not _expect(final.stock.source == 4095 and final.stock.collector == 1 and final.cargo.P.raw == 0 and final.order == 10 and final.power_enabled,
		"Running recovery and rebuilding preserve the original extracted unit and current reserve"):
		return
	# Removing the wheel interrupts the drive while retaining collector custody.
	if not _expect(_issue({"action": "remove", "entity": route.wheel}).accepted, "Removing the wheel interrupts the continuation checkpoint"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts["save_result"] = saved
	facts["save_slot"] = opening.save_slot
	if not _expect(saved.accepted and saved.native_preflight.accepted and FileAccess.file_exists(opening.save_slot), "Store publishes the native-validated checkpoint after a real body preflight"):
		return
	_record("pass")

func _walk_to(target: Vector2, jump: bool = false) -> bool:
	var jumped := false
	var highest_foot := -INF
	while Time.get_ticks_msec() < deadline:
		var body = opening.actor_world.bodies.P
		var at: Vector3 = body.global_position
		highest_foot = maxf(highest_foot, at.y - OpeningGeometry.CAPSULE_HEIGHT / 2.0)
		var gap := target - Vector2(at.x, at.z)
		if gap.length() < 0.08:
			opening.actor_world.release_control("P")
			if jump:
				facts["foundation_jump"] = {"edge_sent": jumped, "highest_foot": highest_foot}
			return true
		var jump_edge: bool = jump and not jumped and gap.length() < 1.2 and body.is_on_floor()
		if not _expect(opening.actor_world.set_control("P", gap.normalized(), jump_edge).accepted,
				"The fixture walks through the real character motor without setting a pose"):
			return false
		jumped = jumped or jump_edge
		await physics_frame
		await process_frame
	opening.actor_world.release_control("P")
	return _expect(false, "The bounded native walk must reach its declared target")

func _foundations() -> void:
	# A new automated construction case, not a replay of produce/resume, a
	# desktop-input test or evidence that a human understood the interaction.
	opening.auto_advance = false
	opening.set_process(false)
	if not await _walk_to(Vector2(9.0, 6.0)):
		return
	var before: Dictionary = opening.model.projection()
	var first: Dictionary = _issue({"action": "place_foundation", "cell": [5, 2], "level": 2})
	if not _expect(first.accepted, "The real nearby actor can build beyond the removed local rectangle"):
		return
	var second: Dictionary = _issue({"action": "place_foundation", "cell": [6, 2], "level": 2})
	if not _expect(second.accepted, "An independently placed foundation shares the absolute height grid"):
		return
	for _frame in range(3):
		await physics_frame
		await process_frame
	opening._select_tool("foundation")
	opening.foundation_steps_toggle.button_pressed = true
	opening._adjust_foundation_level(-2)
	if not _expect(opening.foundation_level == 2 and opening.foundation_level_label.text.begins_with("Access step"),
			"The actual controls distinguish a traversable intermediate step from a machine floor"):
		return
	if not _expect(opening.actor_world._geometry_registered(), "Displayed foundation levels match registered native box bodies"):
		return
	if not await _walk_to(Vector2(8.25, 3.3), true):
		return
	if not _expect(facts.foundation_jump.edge_sent and facts.foundation_jump.highest_foot > 2.0 * OpeningGeometry.HEIGHT_STEP + 0.05,
			"The actual jump lifts the capsule feet above one full foundation before landing"):
		return
	for _frame in range(40):
		await physics_frame
		await process_frame
	var body = opening.actor_world.bodies.P
	facts["standing_on_foundation"] = opening.actor_world.diagnostics("P")
	if not _expect(body.is_on_floor() and absf(body.global_position.y - OpeningGeometry.CAPSULE_HEIGHT / 2.0 - 2.0 * OpeningGeometry.HEIGHT_STEP) < 0.02,
			"The real capsule walks and lands on the constructed surface at the common height"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts["foundation_save"] = saved
	if not _expect(saved.accepted and saved.native_preflight.accepted,
			"Store accepts the real registered pose and foundation custody: " + str(saved)):
		return
	if not await _walk_to(Vector2(9.0, 6.0)):
		return
	opening.foundation_steps_toggle.button_pressed = false
	if not _expect(opening.foundation_level == 4 and opening.foundation_level_label.text.begins_with("Factory floor"),
			"Leaving step mode selects the common whole-tile machine floor"):
		return
	opening._world_click(Vector2i(5, 2))
	if not _expect(opening.model.projection().foundations.size() == 3,
			"The first ordinary foundation click adds the aligned floor above the access step"):
		return
	opening._world_click(Vector2i(6, 2))
	if not _expect(opening.model.projection().foundations.size() == 4,
			"An independent ordinary foundation click joins the adjacent floor at the same world height"):
		return
	opening._select_tool("processor")
	opening.transmission_controls.selected_axis = "x"
	opening._world_click(Vector2i(5, 2))
	if not _expect(opening.model.projection().entities.size() == 1, "The ordinary press placement succeeds before dependent probing"):
		return
	opening._select_tool("drive")
	opening.transmission_controls.selected_axis = "x"
	opening.transmission_controls.gear_height = 4
	opening._world_click(Vector2i(6, 2))
	for _frame in range(3):
		await physics_frame
		await process_frame
	var current: Dictionary = opening.model.projection()
	if not _expect(current.entities.size() == 1 and current.transmission_parts.size() == 1
			and current.part_kits.P.foundation == 20 and current.part_kits.P.shaft == before.part_kits.P.shaft - 1,
			"The ordinary scene places a press and shaft on separately built floors without an obsolete conveyor shortcut"):
		return
	var press_id: String = current.entities.keys()[0]
	var shaft_id: String = current.transmission_parts.keys()[0]
	var connected := false
	for edge: Dictionary in current.engagements:
		connected = connected or (edge.a == press_id and edge.b == shaft_id) or (edge.a == shaft_id and edge.b == press_id)
	if not _expect(connected, "The adjacent press and shaft share an actual native mechanical engagement"):
		return
	for id in current.entities:
		var entity: Dictionary = current.entities[id]
		var physical: StaticBody3D = opening.actor_world.machines[id]
		if not _expect(entity.level == 4 and absf(physical.position.y - OpeningGeometry.MACHINE_CENTER_HEIGHT - 4.0 * OpeningGeometry.HEIGHT_STEP) < 0.00001,
				"Machine projection, mesh and native contact share the foundation height"):
			return
	var shaft: Dictionary = current.transmission_parts[shaft_id]
	var shaft_body = opening.actor_world.mechanical_bodies.get(shaft_id)
	# A machine collision box has its own centre offset. The native profile
	# and actual engagement define the common mechanical axis instead.
	var mechanical_height: float = 4.0 * current.adapter_profile.height_step + current.adapter_profile.anchor_height
	facts["foundation_alignment"] = {"press_collision_y": opening.actor_world.machines[press_id].position.y,
		"shaft_collision_y": shaft_body.position.y if shaft_body != null else null, "native_mechanical_y": mechanical_height}
	if not _expect(shaft.kind == "shaft" and shaft.center[1] == 4 and shaft_body != null
			and absf(shaft_body.position.y - mechanical_height) < 0.00001
			and opening.actor_world._geometry_registered(),
			"The shaft uses the engaged press's native mechanical height and both collision bodies remain registered"):
		return
	if not _expect(current.stock.source == before.stock.source and current.remaining == 0,
			"Construction changes no mineral quantity or material clock"):
		return
	var upper := ""
	for id: String in current.foundations:
		if current.foundations[id].cell == [5, 2] and current.foundations[id].level == 4:
			upper = id
	if not _expect(not upper.is_empty() and _issue({"action": "remove", "entity": upper}).reason == "foundation_in_use",
			"A supporting foundation cannot disappear beneath a machine"):
		return
	_record("pass")

func _resume() -> void:
	var input := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="):
			input = argument.trim_prefix("--resume-input=")
	if not _expect(not input.is_empty() and opening.last_load_result.get("accepted", false), "The ordinary scene must load the retained Store binary"):
		return
	var bytes := FileAccess.get_file_as_bytes(input)
	var expected = bytes_to_var(bytes.slice("FACTORY-SAVE-1\n".length() + 65))
	facts["loaded_before_native"] = opening.startup_resume_checkpoint.duplicate(true)
	if not _expect(expected is Dictionary and _same(expected, opening.startup_resume_checkpoint), "Store-loaded native state and original history must match every saved type and value"):
		return
	var initial: Dictionary = opening.model.projection()
	if not _expect(opening.request_sequence == 0 and initial.order == 11 and initial.stock.source == 4095 and initial.stock.collector == 1 and initial.cargo.P.raw == 0 and not initial.powered,
		"Fresh startup publishes no material command and preserves custody with the wheel removed"):
		return
	if not _expect(_same(opening.actor_world.seeds, expected.actors), "The fresh producer uses the exact saved actor seeds"):
		return
	if not _expect(_same(opening.model.checkpoint().world, expected.world), "The paused source preserves every restored history and material value"):
		return
	var collector := ""
	for id in initial.entities:
		if initial.entities[id].kind == "collector":
			collector = id
	if not _expect(not collector.is_empty() and _issue({"action": "recover", "entity": collector}).accepted, "The fresh process can recover the retained actual unit"):
		return
	var final: Dictionary = opening.model.projection()
	if not _expect(final.stock.source == 4095 and final.stock.collector == 0 and final.cargo.P.raw == 1 and final.order == 12,
		"Fresh native admission moves custody once without creating or losing material"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts["save_result"] = saved
	facts["save_slot"] = opening.save_slot
	if not _expect(saved.accepted, "The fresh process publishes its separate continuation save"):
		return
	_record("pass")

## Fresh arrival panel consumer with actor motor, finite sources and Store.
func _arrival_run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var capture_prefix := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arrival-capture-prefix="):
			capture_prefix = argument.trim_prefix("--arrival-capture-prefix=")
	if destination.is_empty() or mode not in ["arrival-press", "arrival-resume"] or FileAccess.file_exists(destination):
		push_error("Arrival press check requires an unused output and a declared mode")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	opening.auto_advance = false
	root.add_child(opening)
	if not _expect(opening.model is NativeModel and opening.model.projection().has("fabrication_hub"),
			"The ordinary arrival scene exposes its native pod hub"):
		return
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		await process_frame
		if opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() \
				and not opening.startup_save_pending:
			break
	if not _expect(opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor(),
			"The physical actor reaches the scene floor"):
		return
	if DisplayServer.get_name() != "headless":
		while opening.get_node_or_null("MachinePreviewWarmup") != null and Time.get_ticks_msec() < deadline:
			await process_frame
		var prepared := opening.get_node_or_null("MachinePreviewWarmup") == null
		for kind in ["collector", "belt", "processor", "wheel"]:
			prepared = prepared and opening.packed_preview_templates.get(kind) is PackedScene
		if not _expect(prepared and opening.packed_preview_nodes.has("foundation")
				and not opening.packed_preview_nodes.foundation.visible,
				"The graphical preview warmup releases its cover before the arrival is sampled"):
			return
	var panel = opening.arrival_assembly_controls
	if not capture_prefix.is_empty() and mode == "arrival-press":
		await process_frame
		var landfall: Image = root.get_texture().get_image()
		if not _expect(landfall != null and landfall.save_png(capture_prefix + "-landfall.png") == OK,
				"The passive landfall viewport is retained"):
			return
	if DisplayServer.get_name() != "headless":
		opening.building_hotbar.select_slot(1)
		if not _expect(opening.mode == "foundation" and opening.placement_options_panel.visible,
				"The carried foundation shortcut opens ordinary placement after preview warmup"):
			return
		opening._select_tool("inspect")
	if mode == "arrival-resume":
		var restored: Dictionary = opening.model.projection()
		if not _expect(opening.last_load_result.get("accepted", false)
				and restored.cargo.P.products == 2 and restored.placed_components.size() == 7
				and restored.press_assemblies.size() == 1 and restored.press_assemblies[0].status == "ready"
				and restored.hand_crank.holder == "P" and panel.visible,
				"A fresh process reopens the exact modular press, cargo and one held crank"):
			return
		panel.crank_button.pressed.emit()
		if not _expect(opening.model.projection().hand_crank.holder == "pod",
				"The resumed ordinary panel can make a new native command"):
			return
		_record("pass")
		return
	if not _expect(panel != null and panel.visible and panel.craft_button.disabled,
			"The ordinary workshop panel appears at landfall"):
		return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	for index in range(8):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	if not await _approach(Vector2(0.0, 1.65)):
		return
	for index in range(6):
		if _construct({"action": "harvest_source", "target": "opening-softmetal"}).is_empty():
			return
	if not await _approach(Vector2(1.65, 6.6)):
		return
	var initial: Dictionary = opening.model.projection()
	if not _expect(initial.cargo.P.timber == 8 and initial.cargo.P.raw == 6 and initial.placed_components.is_empty(),
			"Local finite sources supply the first press bill without a gifted machine"):
		return
	var part_list := ["wooden_frame", "anvil", "ram_face", "sliding_guide",
		"tool_mount", "wooden_shaft", "wooden_cog"]
	for kind: String in part_list:
		var index := -1
		for choice in range(panel.COMPONENTS.size()):
			if panel.COMPONENTS[choice][0] == kind:
				index = choice
		if not _expect(index >= 0, "Every first-press part is available in the ordinary picker"):
			return
		panel.component_choice.select(index)
		panel._component_selected(index)
		if not _expect(not panel.craft_button.disabled, "The harvested bill enables its actual hub recipe"):
			return
		var before: int = opening.model.projection().order
		panel.craft_button.pressed.emit()
		if not _expect(opening.model.projection().order == before + 1
				and opening.model.projection().cargo.P.components.get(kind, 0) == 1,
				"The panel crafts one native component with exact finite cargo"):
			return
	if not _expect(opening.model.projection().cargo.P.timber == 0
			and opening.model.projection().cargo.P.raw == 2,
			"The complete press consumes eight timber and four ore blanks"):
		return
	if not await _approach(Vector2(3.3, 6.6)):
		return
	opening._select_tool("component")
	var expected_status := ["missing_anvil", "missing_ram", "missing_guide",
		"missing_mount", "missing_shaft", "missing_cog", "ready"]
	for index in range(part_list.size()):
		var kind: String = part_list[index]
		if not panel.craft_section.visible:
			panel.craft_tab.pressed.emit()
		var choice := -1
		for item in range(panel.COMPONENTS.size()):
			if panel.COMPONENTS[item][0] == kind:
				choice = item
		panel.component_choice.select(choice)
		panel._component_selected(choice)
		panel.place_button.pressed.emit()
		var level: int = mini(index, 4)
		var offset: int = maxi(index - 4, 0)
		opening._adjust_component_level(level - opening.component_level)
		opening._adjust_component_offset("x", offset - opening.component_offset.x)
		var before: int = opening.model.projection().order
		opening._world_click(Vector2i(3, 4))
		var projection: Dictionary = opening.model.projection()
		if not _expect(projection.order == before + 1 and projection.placed_components.size() == index + 1,
				"An ordinary placement control fits %s at %s: %s" % [kind,
					str(opening._component_place_center(Vector2i(3, 4), "")), opening.status_label.text]):
			return
		if not _expect(projection.press_assemblies.size() == 1
				and projection.press_assemblies[0].status == expected_status[index],
				"The native recognizer reports the current fitted press stage"):
			return
	var ready: Dictionary = opening.model.projection().press_assemblies[0]
	panel.press_tab.pressed.emit()
	if not _expect(panel.press_section.visible and panel.press_status.text.begins_with("Press ready")
			and panel.route_choice.get_item_count() > 0,
			"The selected press exposes its live feed routes in the ordinary panel"):
		return
	panel.crank_button.pressed.emit()
	if not _expect(opening.model.projection().hand_crank.holder == "P", "The player takes the one conserved pod crank"):
		return
	panel.feed_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.raw == 1
			and opening.model.projection().dropped_material.size() == 1,
			"The panel moves one carried blank into retained press work"):
		return
	for turn in range(3):
		if not _expect(not panel.turn_button.disabled, "A retained workpiece enables the selected drive"):
			return
		panel.turn_button.pressed.emit()
	var after: Dictionary = opening.model.projection()
	if not _expect(after.dropped_material.size() == 1 and after.dropped_material[0].products == 1,
			"Repeated hand turns form one plate at the selected lower exit"):
		return
	if not _expect(not panel.pickup_button.disabled, "The formed plate is offered for physical pickup"):
		return
	panel.feed_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.raw == 0
			and opening.model.projection().dropped_material.size() == 2,
			"A second local blank can enter while the prior plate occupies the exit"):
		return
	for turn in range(3):
		panel.turn_button.pressed.emit()
	var held: Dictionary = opening.model.projection()
	if not _expect(held.dropped_material.size() == 2
			and panel.press_status.text.contains("Exit holds a plate"),
			"A full exit retains the second workpiece and identifies the recovery action"):
		return
	if not _expect(not panel.pickup_button.disabled and not panel.recover_work_button.disabled,
			"The player can choose either exit pickup or retained work recovery"):
		return
	panel.pickup_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.products == 1
			and opening.model.projection().dropped_material.size() == 1,
			"Exit pickup leaves the second workpiece in place"):
		return
	panel.turn_button.pressed.emit()
	if not _expect(opening.model.projection().dropped_material.size() == 1
			and opening.model.projection().dropped_material[0].products == 1,
			"Clearing the exit lets the retained ready work form its second product"):
		return
	panel.pickup_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.products == 2
			and opening.model.projection().dropped_material.is_empty(),
			"Both formed plates enter finite carried custody through ordinary controls"):
		return
	facts["press_frame"] = ready.frame
	facts["final_parts"] = opening.model.projection().placed_components
	facts["panel_status"] = panel.press_status.text
	var save: Dictionary = opening._save_worksite()
	facts["save"] = save
	if not _expect(save.get("accepted", false) and save.get("native_preflight", {}).get("accepted", false)
			and FileAccess.file_exists(opening.save_slot),
			"The ordinary Store retains a typed modular press and original physical actor"):
		return
	if not capture_prefix.is_empty():
		await process_frame
		var formed: Image = root.get_texture().get_image()
		if not _expect(formed != null and formed.save_png(capture_prefix + "-press.png") == OK,
				"The passive completed press viewport is retained"):
			return
	_record("pass")
