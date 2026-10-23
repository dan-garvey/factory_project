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

func _arrival_field_craft_run(panel) -> void:
	if not _expect(panel.visible and panel.field_craft_button.visible and not panel.field_craft_button.disabled,
			"The ordinary arrival panel exposes the wooden multitool recipe"):
		return
	if not await _approach(Vector2(6.0, 3.45)):
		return
	var distant: Dictionary = opening.model.projection()
	panel.craft_button.pressed.emit()
	if not _expect(opening.model.projection().order == distant.order + 1
			and opening.model.projection().cargo == distant.cargo
			and "Move beside the selected workshop" in opening.status_label.text,
			"The physical field position is beyond bench crafting reach"):
		return
	for index in range(3):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	var gathered: Dictionary = opening.model.projection()
	if not _expect(gathered.cargo.P.timber == 3 and gathered.hand_sources["tree-east-south"].remaining == 5,
			"Three finite cuts reach the same physically present field actor"):
		return
	panel.field_craft_button.pressed.emit()
	var shaped: Dictionary = opening.model.projection()
	if not _expect(shaped.order == gathered.order + 1 and shaped.cargo.P.timber == 0
			and shaped.cargo.P.components.get("wooden_frame", 0) == 1
			and shaped.hand_sources == gathered.hand_sources
			and "multitool" in opening.status_label.text,
			"The ordinary multitool control shapes one wooden frame without the pod"):
		return
	var rejected: Dictionary = _issue({"action": "field_craft", "component": "cutting_edge"})
	if not _expect(not rejected.accepted and rejected.reason == "unavailable_recipe"
			and opening.model.projection().cargo == shaped.cargo
			and "a workshop" in opening.status_label.text,
			"The field tool refuses metal while preserving the shaped frame"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts["save_result"] = saved
	facts["save_slot"] = opening.save_slot
	if not _expect(saved.accepted and saved.native_preflight.accepted
			and FileAccess.file_exists(opening.save_slot),
			"Store saves the field-shaped component and source depletion from the real actor"):
		return
	_record("pass")

func _arrival_portable_workbench_run(panel, capture_prefix: String) -> void:
	var bench_choice: int = panel.COMPONENTS.size() - 1
	if not _expect(panel.COMPONENTS[bench_choice][0] == "wooden_workbench"
			and panel.bench_choice.item_count == 1,
			"The ordinary menu lists the finite workbench recipe and original pod workshop"):
		return
	panel.component_choice.select(bench_choice)
	panel._component_selected(bench_choice)
	if not await _approach(Vector2(6.0, 3.45)):
		return
	for index in range(4):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	var cut: Dictionary = opening.model.projection()
	panel.field_craft_button.pressed.emit()
	var shaped: Dictionary = opening.model.projection()
	if not _expect(shaped.order == cut.order + 1 and shaped.cargo.P.timber == 0
			and shaped.cargo.P.components.get("wooden_workbench", 0) == 1
			and shaped.hand_sources["tree-east-south"].remaining == 4,
			"Four real timber cuts become one carried workbench through the field tool"):
		return
	opening._select_tool("component")
	var tile := Vector2i(4, 3)
	if not _expect(opening._component_place_center(tile, "") == [16, 0, 12],
			"The workbench uses a whole tile on the common construction grid"):
		return
	opening._world_click(tile)
	var installed: Dictionary = opening.model.projection()
	if not _expect(installed.placed_components.size() == 1 and installed.fabrication_benches.size() == 1
			and installed.cargo.P.components.get("wooden_workbench", 0) == 0,
			"Ordinary placement moves the one crafted bench into confirmed world custody"):
		return
	var id: String = installed.fabrication_benches[0].id
	var visible_bench := false
	for node in opening.transmission_presenter.get_children():
		if node.get_meta("component_entity", "") == id:
			visible_bench = node.get_node_or_null("WorkbenchTop") != null
	if not _expect(opening.actor_world.component_bodies.has(id) and visible_bench,
			"The placed identity has a physical pick body and a distinct rendered work surface"):
		return
	if not await _approach(Vector2(0.0, 1.65)):
		return
	if _construct({"action": "harvest_source", "target": "opening-softmetal"}).is_empty():
		return
	panel.bench_choice.select(1)
	panel._bench_selected(1)
	var edge_index := 6
	panel.component_choice.select(edge_index)
	panel._component_selected(edge_index)
	var remote: Dictionary = opening.model.projection()
	panel.craft_button.pressed.emit()
	var refused: Dictionary = opening.model.projection()
	if not _expect(refused.order == remote.order + 1 and refused.cargo == remote.cargo
			and panel.selected_bench == id and "selected workshop" in opening.status_label.text,
			"Selecting the placed bench does not spend distant ore or craft remotely"):
		return
	if not await _approach(Vector2(6.0, 4.95)):
		return
	panel.craft_button.pressed.emit()
	var crafted: Dictionary = opening.model.projection()
	if not _expect(crafted.order == refused.order + 1 and crafted.cargo.P.raw == 0
			and crafted.cargo.P.components.get("cutting_edge", 0) == 1
			and crafted.fabrication_benches[0].id == id,
			"The ordinary crafting menu spends one carried ore at the selected built bench"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		# An isolated presentation view inspects the confirmed body. It changes
		# only the camera and never the physical actor or material transaction.
		opening._select_tool("inspect")
		opening.camera.global_position = Vector3(8.8, 2.3, 7.8)
		opening.camera.look_at(Vector3(6.6, 0.85, 4.95))
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if not _expect(image != null and image.save_png(capture_prefix + "-workbench.png") == OK,
				"The confirmed workbench presentation frame is retained"):
			return
	opening.selected = id
	opening._refresh_ui()
	panel.reclaim_button.pressed.emit()
	var reclaimed: Dictionary = opening.model.projection()
	if not _expect(reclaimed.fabrication_benches.is_empty()
			and reclaimed.cargo.P.components.get("wooden_workbench", 0) == 1
			and reclaimed.cargo.P.components.get("cutting_edge", 0) == 1,
			"Reclaiming the exact selected bench returns its component without refunding the ore"):
		return
	_record("pass")

func _arrival_pod_workshop_run(panel, capture_prefix: String) -> void:
	var original: Dictionary = opening.model.projection()
	var id: String = original.fabrication_hub.id
	var pod_anchor: Vector3 = opening.landing_pod_visual.position
	if not _expect(panel.pod_workshop_button.visible and not panel.pod_workshop_button.disabled
			and panel.pod_workshop_button.text == "Stow pod workshop"
			and opening.landing_hub_pick.collision_layer == OpeningGeometry.PICK_LAYER,
			"The ordinary panel and pick body expose the installed issued workshop"):
		return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	panel.pod_workshop_button.pressed.emit()
	var carried: Dictionary = opening.model.projection()
	if not _expect(not carried.fabrication_hub.installed and carried.fabrication_hub.holder == "P"
			and carried.fabrication_hub.id == id and carried.fabrication_hub.generation == 1
			and opening.landing_pod_visual.position == pod_anchor
			and not opening.landing_hub_visual.visible and opening.landing_hub_pick.collision_layer == 0
			and opening.landing_crank_visual.visible and panel.bench_choice.item_count == 0
			and panel.pod_workshop_button.text == "Place carried pod workshop",
			"Stowing moves only the one issued hub into actor custody while pod and crank stay landed"):
		return
	var invalid: Dictionary = _issue({"action": "deploy_fabrication_hub", "entity": id,
		"center": [17, 0, 12]})
	if not _expect(not invalid.accepted and invalid.reason == "unsupported_bench"
			and opening.model.projection().fabrication_hub.holder == "P"
			and not opening.landing_hub_visual.visible,
			"An off-grid redeploy refusal preserves held identity and keeps the world body absent"):
		return
	panel.pod_workshop_button.pressed.emit()
	if not _expect(opening.mode == "pod_workshop", "The menu opens the full-tile pod placement tool"):
		return
	var tile := Vector2i(4, 3)
	opening.distance = 0.0
	opening.hover_cell = tile
	opening._update_cursor()
	if not _expect(opening.hover.visible and opening.hover.scale == Vector3.ONE
			and absf(opening.hover.position.x - 6.6) < 0.001
			and absf(opening.hover.position.z - 4.95) < 0.001
			and opening.placement_options_panel.visible
			and "POD WORKSHOP" in opening.placement_options_title.text,
			"The carried pod workshop shows a horizontal full-tile outline and placement menu"):
		return
	opening._world_click(tile)
	var installed: Dictionary = opening.model.projection()
	if not _expect(installed.fabrication_hub.installed and installed.fabrication_hub.holder == null
			and installed.fabrication_hub.id == id and installed.fabrication_hub.center == [4, 0, 3]
			and opening.mode == "inspect" and opening.selected == id
			and opening.landing_pod_visual.position == pod_anchor
			and opening.landing_hub_visual.visible and opening.landing_hub_pick.collision_layer == OpeningGeometry.PICK_LAYER
			and opening.landing_hub_visual.position.distance_to(Vector3(6.6, 0, 4.95)) < 0.001
			and panel.bench_choice.item_count == 1 and panel.selected_bench == id,
			"Ordinary placement reinstalls the same issued hub away from its still-landed pod"):
		return
	opening.camera.global_position = Vector3(9.0, 3.7, 8.6)
	opening.camera.look_at(Vector3(6.6, 0.7, 4.95))
	await physics_frame
	opening.camera.global_position = Vector3(9.0, 3.7, 8.6)
	opening.camera.look_at(Vector3(6.6, 0.7, 4.95))
	var screen: Vector2 = root.get_visible_rect().size * 0.5
	var picked: Dictionary = opening._screen_pick(screen)
	var picked_id: String = opening._screen_entity(screen)
	if not _expect(picked_id == id and opening._contains_target(installed, id),
			"The relocated hub has the issued identity in the ordinary E pick ray: %s" % \
			str({"picked": picked_id, "collider": str(picked.get("collider", "")), "camera": opening.camera.global_position})):
		return
	opening.distance = 0.0
	opening._open_pointed_machine()
	if not _expect(opening.selected == id and "Pod workshop" in opening.inspector.text,
			"E opens the relocated hub and identifies it as a workshop"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		opening.distance = 14.0
		opening._update_camera()
		opening.set_process(false)
		opening.camera.global_position = Vector3(8.5, 4.3, 9.4)
		opening.camera.look_at(Vector3(4.4, 0.7, 5.9))
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if not _expect(image != null and image.save_png(capture_prefix + "-relocated-pod-workshop.png") == OK,
				"The moved issued workshop and stationary pod frame are retained"):
			return
		opening.set_process(true)
	if not await _approach(Vector2(0.0, 1.65)):
		return
	if _construct({"action": "harvest_source", "target": "opening-softmetal"}).is_empty():
		return
	if not await _approach(Vector2(6.0, 4.95)):
		return
	var edge_index := 6
	panel.component_choice.select(edge_index)
	panel._component_selected(edge_index)
	panel.craft_button.pressed.emit()
	var crafted: Dictionary = opening.model.projection()
	if not _expect(crafted.cargo.P.raw == 0 and crafted.cargo.P.components.get("cutting_edge", 0) == 1
			and crafted.fabrication_hub.center == [4, 0, 3] and crafted.fabrication_hub.installed,
			"The selected moved pod workshop spends one hand-mined ore on a metal edge"):
		return
	var save: Dictionary = opening._save_worksite()
	if not _expect(save.get("accepted", false) and save.get("native_preflight", {}).get("accepted", false)
			and FileAccess.file_exists(opening.save_slot),
			"Store saves the moved issued hub and physical actor for a fresh-process resume"):
		return
	_record("pass")

func _arrival_pod_workshop_resume_run(panel) -> void:
	var restored: Dictionary = opening.model.projection()
	var id: String = restored.fabrication_hub.id
	if not _expect(opening.last_load_result.get("accepted", false)
			and restored.fabrication_hub.installed and restored.fabrication_hub.center == [4, 0, 3]
			and restored.cargo.P.components.get("cutting_edge", 0) == 1
			and opening.landing_pod_visual.position.distance_to(Vector3(1.65, 0, 6.6)) < 0.001
			and opening.landing_hub_visual.position.distance_to(Vector3(6.6, 0, 4.95)) < 0.001
			and opening.landing_hub_visual.visible and opening.landing_hub_pick.collision_layer == OpeningGeometry.PICK_LAYER
			and panel.bench_choice.item_count == 1 and panel.selected_bench == id,
			"Fresh-process restore preserves one moved hub, finite cargo, pod anchor and selectable pick body"):
		return
	opening._select_tool("deconstruct")
	opening._world_click(Vector2i(4, 3), id)
	var carried: Dictionary = opening.model.projection()
	if not _expect(not carried.fabrication_hub.installed and carried.fabrication_hub.holder == "P"
			and carried.fabrication_hub.id == id and panel.bench_choice.item_count == 0
			and opening.landing_pod_visual.position.distance_to(Vector3(1.65, 0, 6.6)) < 0.001,
			"The resumed worker can deconstruct the same restored workshop without duplication"):
		return
	_record("pass")

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
	if mode in ["arrival-press", "arrival-resume", "arrival-delivery", "arrival-delivery-resume", "arrival-craft-capacity", "arrival-field-craft", "arrival-portable-workbench", "arrival-pod-workshop", "arrival-pod-workshop-resume", "arrival-belt", "arrival-belt-controls", "arrival-belt-resume", "arrival-reveal", "arrival-reveal-skip"]:
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

func _deliver_first_arrival_plate(held_work: Dictionary, capture_prefix: String) -> bool:
	var beacon: Dictionary = opening.model.projection().freight_beacon
	var distant: Dictionary = _issue({"action": "deliver_first_plate", "entity": beacon.id})
	if not _expect(not distant.get("accepted", false) and distant.get("reason") == "out_of_reach"
			and opening.model.projection().cargo.P.products == 1,
			"The carried plate cannot be shipped from the press by camera or remote command"):
		return false
	# Walk around the press with the ordinary motor; never set a native pose.
	if not await _approach(Vector2(3.3, 8.25)) or not await _approach(Vector2(9.9, 8.25)):
		return false
	var sample: Dictionary = opening.actor_world.diagnostics("P").sample
	if not _expect(sample.ready and sample.registered and sample.on_floor
			and opening.freight_beacon_visual != null,
			"A registered physical actor reaches the visible freight receiver"):
		return false
	await process_frame
	var prior_distance: float = opening.distance
	# Aim the ordinary first-person camera from the settled actor eye. The
	# camera selects a pick body; the native command still checks actor reach.
	opening.distance = 0.0
	opening.orbit_yaw = 0.0
	opening.orbit_pitch = 0.18
	opening._update_camera()
	var hit: Dictionary = opening._screen_pick(root.get_visible_rect().size / 2.0)
	if not _expect(not hit.is_empty() and hit.collider == opening.freight_beacon_visual,
			"The ordinary E ray selects the native freight receiver's visible pick body"):
		return false
	var first_request: String = str(opening.request_namespace) + str(opening.request_sequence + 1)
	var before: Dictionary = opening.model.projection()
	opening._interact_pointed()
	var shipped: Dictionary = opening.model.projection()
	if not _expect(shipped.order == before.order + 1 and shipped.cargo.P.products == 0
			and shipped.freight_beacon.order_complete and shipped.freight_beacon.shipped_products == 1
			and not opening.freight_beacon_visual.get_node("ShipmentLabel").visible
			and shipped.dropped_material == held_work.dropped_material
			and shipped.press_assemblies == held_work.press_assemblies,
			"E ships exactly the first carried plate while the second press work stays retained"):
		return false
	if not capture_prefix.is_empty():
		await process_frame
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-beacon.png") == OK,
				"The ordinary completed receiver cue is retained as passive pixels"):
			return false
	var before_retry: Dictionary = opening.model.checkpoint()
	var retry: Dictionary = opening.model.command({"context": shipped.context, "client": "P",
		"request": first_request, "action": "deliver_first_plate", "entity": beacon.id})
	if not _expect(retry.get("accepted", false) and retry.get("duplicate", false)
			and opening.model.checkpoint() == before_retry,
			"Retrying the original freight request returns its receipt without a second debit"):
		return false
	var again: Dictionary = _issue({"action": "deliver_first_plate", "entity": beacon.id})
	if not _expect(not again.get("accepted", false) and again.get("reason") == "order_filled"
			and opening.model.projection().cargo.P.products == 0
			and opening.model.projection().dropped_material == held_work.dropped_material,
			"A new request cannot spend retained work after the one-plate order is filled"):
		return false
	facts["delivery"] = {"request": first_request, "receipt": retry, "beacon": shipped.freight_beacon,
		"physical_actor": sample}
	opening.distance = prior_distance
	opening._update_camera()
	return await _approach(Vector2(3.3, 8.25)) and await _approach(Vector2(3.3, 6.6))

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

func _arrival_capacity_run(panel) -> void:
	for source in [
		{"point": Vector2(3.3, 4.95), "id": "tree-east-south", "cuts": 8},
		{"point": Vector2(3.3, 9.9), "id": "tree-east-north", "cuts": 8},
		{"point": Vector2(1.65, 11.55), "id": "tree-north", "cuts": 5},
	]:
		if not await _approach(source.point):
			return
		for index in range(source.cuts):
			if _construct({"action": "harvest_source", "target": source.id}).is_empty():
				return
	if not await _approach(Vector2(1.65, 6.6)):
		return
	if not _expect(opening.model.projection().cargo.P.timber == 21,
			"Three finite trees put twenty component inputs and one spare within the hand-carry limit"):
		return
	panel.component_choice.select(1)
	panel._component_selected(1)
	for count in range(20):
		if not _expect(not panel.craft_button.disabled,
				"The pod workshop keeps the native shaft recipe selectable while stock is available"):
			return
		var before: Dictionary = opening.model.projection()
		panel.craft_button.pressed.emit()
		var after: Dictionary = opening.model.projection()
		if not _expect(after.order == before.order + 1 and after.cargo.P.timber == before.cargo.P.timber - 1
				and after.cargo.P.components.get("wooden_shaft", 0) == count + 1,
				"Each selected recipe converts exactly one carried timber into one wooden shaft"):
			return
	var full_before: Dictionary = opening.model.projection()
	if not _expect("Parts 20 / 20" in panel.recipe_label.text and not panel.craft_button.disabled
			and full_before.cargo.P.timber == 1,
			"The ordinary panel shows a full component bag while one recipe input remains"):
		return
	panel.craft_button.pressed.emit()
	var full_after: Dictionary = opening.model.projection()
	if not _expect(full_after.order == full_before.order + 1 and full_after.cargo == full_before.cargo
			and full_after.hand_sources == full_before.hand_sources
			and "component bag is full" in opening.status_label.text,
			"The native full-output refusal keeps the last timber and offers a clear placement remedy"):
		return
	panel.place_button.pressed.emit()
	var before_placement: Dictionary = opening.model.projection()
	opening._world_click(Vector2i(3, 4))
	var placed: Dictionary = opening.model.projection()
	if not _expect(placed.order == before_placement.order + 1
			and placed.placed_components.size() == 1
			and placed.cargo.P.components.get("wooden_shaft", 0) == 19
			and placed.cargo.P.timber == 1,
			"The ordinary placement control frees one component slot without changing the held timber"):
		return
	panel.craft_button.pressed.emit()
	var recovered: Dictionary = opening.model.projection()
	if not _expect(recovered.order == placed.order + 1 and recovered.cargo.P.timber == 0
			and recovered.cargo.P.components.get("wooden_shaft", 0) == 20
			and recovered.placed_components == placed.placed_components,
			"The same hub recipe succeeds after an actual component is placed"):
		return
	var first_id: String = str(recovered.placed_components.keys()[0])
	opening.selected = first_id
	opening._refresh_ui()
	if not _expect(panel.reclaim_button.visible and not panel.reclaim_button.disabled,
			"The selected placed shaft offers an ordinary reclaim control"):
		return
	panel.reclaim_button.pressed.emit()
	var reclaim_refused: Dictionary = opening.model.projection()
	if not _expect(reclaim_refused.order == recovered.order + 1
			and reclaim_refused.cargo == recovered.cargo
			and reclaim_refused.placed_components == recovered.placed_components
			and "Place another carried part" in opening.status_label.text,
			"Reclaiming into a full component bag refuses without duplicating or losing the shaft"):
		return
	panel.place_button.pressed.emit()
	opening._world_click(Vector2i(3, 5))
	var room_made: Dictionary = opening.model.projection()
	if not _expect(room_made.order == reclaim_refused.order + 1
			and room_made.cargo.P.components.get("wooden_shaft", 0) == 19
			and room_made.placed_components.size() == 2,
			"Placing a second real shaft frees one carried slot for the selected reclaim"):
		return
	opening.selected = first_id
	opening._refresh_ui()
	panel.reclaim_button.pressed.emit()
	var reclaimed: Dictionary = opening.model.projection()
	if not _expect(reclaimed.order == room_made.order + 1
			and reclaimed.cargo.P.components.get("wooden_shaft", 0) == 20
			and reclaimed.placed_components.size() == 1 and not reclaimed.placed_components.has(first_id),
			"The same shaft returns to carried custody after room is made, leaving one placed identity"):
		return
	_record("pass")

func _arrival_belt_run(panel, capture_prefix: String) -> void:
	# This uses the ordinary arrival scene, its physical actor, workshop buttons
	# and the native terrain. Commands still pass through the one scene Model.
	for source in [
		{"point": Vector2(3.3, 4.95), "id": "tree-east-south", "cuts": 8},
		{"point": Vector2(3.3, 9.9), "id": "tree-east-north", "cuts": 6},
		{"point": Vector2(0.0, 1.65), "id": "opening-softmetal", "cuts": 3},
	]:
		if not await _approach(source.point):
			return
		for index in range(source.cuts):
			if _construct({"action": "harvest_source", "target": source.id}).is_empty():
				return
	if not await _approach(Vector2(1.65, 6.6)):
		return
	if not _expect(opening.model.projection().cargo.P.timber == 14
			and opening.model.projection().cargo.P.raw == 3,
			"Two finite trees and the outcrop supply the exact collector and powered-route bill"):
		return
	for kind in ["wooden_frame", "tool_mount", "cutting_edge", "receiver_tray", "wooden_shaft"]:
		var index := -1
		for choice in panel.COMPONENTS.size():
			if panel.COMPONENTS[choice][0] == kind:
				index = choice
		if not _expect(index >= 0, "The native collector component is listed in the ordinary workshop"):
			return
		panel.component_choice.select(index)
		panel._component_selected(index)
		panel.craft_button.pressed.emit()
		if not _expect(int(opening.model.projection().cargo.P.components.get(kind, 0)) == 1,
				"The ordinary workshop makes one finite collector component"):
			return
	for route_part in ["shaft", "shaft", "shaft", "belt", "wheel"]:
		var index := -1
		var recipes: Array = opening.model.projection().part_recipes
		for choice in recipes.size():
			if recipes[choice].kind == route_part:
				index = choice
		if not _expect(index >= 0, "The native transmission recipe is listed in the ordinary workshop"):
			return
		panel.part_choice.select(index)
		panel.part_choice.item_selected.emit(index)
		var before: Dictionary = opening.model.projection()
		panel.part_craft_button.pressed.emit()
		var after: Dictionary = opening.model.projection()
		if not _expect(after.order == before.order + 1 and after.part_kits.P[route_part] == before.part_kits.P[route_part] + 1,
				"The ordinary workshop turns carried stock into one exact native route kit"):
			return
	if not _expect(opening.model.projection().cargo.P.timber == 0
			and opening.model.projection().cargo.P.raw == 0,
			"The complete collector and three-shaft route spend fourteen timber and three ore"):
		return
	panel.crank_button.pressed.emit()
	if not _expect(opening.model.projection().hand_crank.holder == "P",
			"The physical actor takes the single pod crank before leaving the workshop"):
		return
	if not await _approach(Vector2(0.0, 1.3)):
		return
	var wheel_recipe := -1
	for choice in opening.model.projection().part_recipes.size():
		if opening.model.projection().part_recipes[choice].kind == "wheel":
			wheel_recipe = choice
	panel.part_choice.select(wheel_recipe)
	panel.part_choice.item_selected.emit(wheel_recipe)
	panel.part_place_button.pressed.emit()
	if not _expect(opening.mode == "wheel", "The ordinary workshop arms its crafted waterwheel tool"):
		return
	var wheel: Dictionary = _construct({"action": "place", "kind": "wheel", "cell": [-2, 0], "axis": "x", "level": 4})
	if wheel.is_empty():
		return
	var shaft_recipe := -1
	for choice in opening.model.projection().part_recipes.size():
		if opening.model.projection().part_recipes[choice].kind == "shaft":
			shaft_recipe = choice
	panel.part_choice.select(shaft_recipe)
	panel.part_choice.item_selected.emit(shaft_recipe)
	panel.part_place_button.pressed.emit()
	if not _expect(opening.mode == "drive", "The ordinary workshop arms its crafted shaft tool"):
		return
	var inlet := ""
	var far := ""
	var middle := ""
	for route_shaft in [
		{"center": [-4, 4, 0], "name": "middle"},
		{"center": [0, 4, 0], "name": "inlet"},
		{"center": [0, 4, -4], "name": "far"},
	]:
		var placed: Dictionary = _construct({"action": "place_shaft", "center": route_shaft.center,
			"axis": "x", "half_span": 2})
		if placed.is_empty():
			return
		if route_shaft.name == "middle": middle = placed.entity
		if route_shaft.name == "inlet": inlet = placed.entity
		if route_shaft.name == "far": far = placed.entity
	var belt_recipe := -1
	for choice in opening.model.projection().part_recipes.size():
		if opening.model.projection().part_recipes[choice].kind == "belt":
			belt_recipe = choice
	panel.part_choice.select(belt_recipe)
	panel.part_choice.item_selected.emit(belt_recipe)
	panel.part_place_button.pressed.emit()
	if not _expect(opening.mode == "belt", "The ordinary workshop arms its crafted belt tool"):
		return
	var span: Dictionary = _construct({"action": "place_belt_span", "from": inlet, "to": far})
	if span.is_empty():
		return
	if not await _approach(Vector2(0.7, 3.3)):
		return
	if _construct({"action": "place_foundation", "cell": [0, 1], "level": 4}).is_empty():
		return
	for component in [
		{"kind": "wooden_frame", "center": [0, 4, 4]},
		{"kind": "tool_mount", "center": [-1, 4, 4]},
		{"kind": "cutting_edge", "center": [-2, 4, 4]},
		{"kind": "receiver_tray", "center": [0, 4, 3]},
		{"kind": "wooden_shaft", "center": [1, 4, 4]},
	]:
		if _construct({"action": "place_component", "component": component.kind,
				"center": component.center}).is_empty():
			return
	var built: Dictionary = opening.model.projection()
	if not _expect(built.collector_assemblies.any(func(item: Variant) -> bool:
		return item is Dictionary and item.get("status") == "ready")
			and panel.route_status_label.text.contains("outward"),
			"The fitted north receiver meets a powered outward belt mouth in the ordinary panel"):
		return
	var drive := ""
	for id in built.placed_components:
		if built.placed_components[id].get("component") == "wooden_shaft":
			drive = id
	if _construct({"action": "turn_hand_crank", "entity": drive}).is_empty():
		return
	var before_tick: Dictionary = opening.model.projection()
	if not _expect(before_tick.dropped_material.any(func(drop: Variant) -> bool:
		return drop is Dictionary and drop.get("raw", 0) == 1),
		"The hand crank puts one true ore blank in the fitted receiver"):
		return
	var stepped: Dictionary = opening.model.advance()
	if not _expect(stepped.has("belt_spans") and int(stepped.get("revision", 0)) > int(before_tick.revision),
		"The ordinary scene advances the shared native drive once"):
		return
	opening._refresh()
	var after_tick: Dictionary = opening.model.projection()
	if not _expect(not after_tick.belt_spans[span.entity].slots.is_empty()
			and after_tick.belt_spans[span.entity].slots.any(func(slot: Variant) -> bool:
				return slot is Dictionary and slot.get("raw", 0) == 1),
			"The first hand-cut receiver blank enters the player-built belt"):
		return
	if not _expect(opening.transmission_presenter.get_node_or_null("CollectorReceiverChute") != null,
			"The confirmed receiver and belt render a short physical chute"):
		return
	var save: Dictionary = opening._save_worksite()
	facts["save"] = save
	if not _expect(save.get("accepted", false) and save.get("native_preflight", {}).get("accepted", false),
			"Store keeps the fabricated route and its transferred blank in one checkpoint"):
		return
	if not capture_prefix.is_empty():
		for frame in 3:
			await process_frame
		var rendered: Image = root.get_texture().get_image()
		if not _expect(rendered != null and rendered.save_png(capture_prefix + "-belt.png") == OK,
				"The passive receiver chute and moving belt viewport are retained"):
			return
		opening.arrival_assembly_scroll.scroll_vertical = 10000
		await RenderingServer.frame_post_draw
		var workshop: Image = root.get_texture().get_image()
		if not _expect(workshop != null and workshop.save_png(capture_prefix + "-workshop.png") == OK,
				"The scrollable receiver-status controls are retained in a second passive frame"):
			return
	if mode == "arrival-belt-controls":
		if not await _arrival_belt_controls(middle, span.entity):
			return
	_record("pass")

func _arrival_belt_controls(middle: String, span: String) -> bool:
	# The pod-first route has earned these parts through ordinary harvesting and
	# workshop controls. Exercise F on a real, reachable shaft after that route.
	var span_view: Node3D
	for child: Node in opening.transmission_presenter.get_children():
		if child is Node3D and child.get_meta("entity", "") == span:
			span_view = child
	if not _expect(span_view != null and span_view.get_node_or_null("Pick") != null,
			"The confirmed belt retains its own selection body"):
		return false
	var pick: Node = span_view.get_node("Pick")
	opening._refresh()
	opening._refresh()
	if not _expect(is_instance_valid(span_view) and is_instance_valid(pick)
			and span_view.get_node_or_null("Pick") == pick,
			"Unchanged projection refresh preserves the belt and pick identities"):
		return false
	opening._select_tool("inspect")
	var selected_sequence: int = opening.request_sequence
	opening._world_click(Vector2i(0, -1), span)
	if not _expect(opening.selected == span and opening.request_sequence == selected_sequence,
			"The confirmed belt opens its inspector without submitting an authority request"):
		return false
	if not await _approach(Vector2(0.4, 2.8)):
		return false
	var before: Dictionary = opening.model.checkpoint()
	var before_state: Dictionary = opening.model.projection()
	var sequence: int = opening.request_sequence
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	opening._unhandled_input(key)
	if not _expect(opening.mode == "deconstruct", "F enters dedicated deconstruction"):
		return false
	opening._world_click(Vector2i(-1, 0), middle)
	var after: Dictionary = opening.model.checkpoint()
	var after_state: Dictionary = opening.model.projection()
	if not _expect(opening.request_sequence == sequence + 1
			and after.world.history.order == before.world.history.order + 1,
			"One ordinary deconstruction click submits one native request"):
		return false
	var record: Dictionary = after.world.history.records[-1]
	var wire: Dictionary = record.intent.wire
	if not _expect(wire.get("action") == "remove" and wire.get("entity") == middle
			and record.result.get("accepted", false)
			and not after_state.transmission_parts.has(middle),
			"F removes the exact confirmed middle shaft identity"):
		return false
	if not _expect(after_state.belt_spans.has(span)
			and after_state.belt_spans[span] == before_state.belt_spans[span]
			and after_state.part_kits.P.shaft == before_state.part_kits.P.shaft + 1
			and after_state.stock == before_state.stock and after_state.cargo == before_state.cargo,
			"Dismantling refunds one shaft while preserving belt and material custody"):
		return false
	var retry: Dictionary = opening.model.command(wire)
	if not _expect(retry.get("accepted", false) and retry.get("duplicate", false)
			and after == opening.model.checkpoint(),
			"The exact original removal receipt cannot remove a second part"):
		return false
	var reach: Dictionary = retry.get("reach", {})
	var cut: Dictionary = opening.actor_world.diagnostics("P", retry.get("native_epoch", 0))
	var sample: Dictionary = cut.get("sample", {})
	var center := [-4.0 * OpeningGeometry.PITCH / 4.0,
		OpeningGeometry.ANCHOR_HEIGHT + 4.0 * OpeningGeometry.PITCH / 4.0, 0.0]
	var squared := 0.0
	if sample.get("position") is Array and sample.position.size() == 3:
		for axis in 3:
			var offset: float = sample.position[axis] - center[axis]
			squared += offset * offset
	if not _expect(cut.get("available", false) and sample.get("registered", false)
			and sample.get("ready", false) and sample.get("native_epoch") == retry.get("native_epoch")
			and sample.get("position") == reach.get("position")
			and reach.get("targets") == [center]
			and reach.get("distances_squared") == [squared]
			and squared <= 16.0,
			"The removal receipt retains its original physical four-metre reach cut"):
		return false
	var saved: Dictionary = opening._save_worksite()
	return _expect(saved.get("accepted", false)
		and saved.get("native_preflight", {}).get("accepted", false),
		"Store publishes the recovered shaft and unchanged belt custody")

func _arrival_belt_resume_run() -> void:
	var restored: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and restored.collector_assemblies.any(func(item: Variant) -> bool:
				return item is Dictionary and item.get("status") == "ready")
			and restored.belt_spans.size() == 1 and restored.line_belt_raw == 1
			and restored.part_kits.P.shaft == 0 and restored.part_kits.P.belt == 0
			and restored.part_kits.P.wheel == 0,
			"A fresh scene process restores the exact installed finite route and the original blank"):
		return
	if not _expect(opening.transmission_presenter.get_node_or_null("CollectorReceiverChute") != null,
			"The restored route re-creates its receiver chute from the native projection"):
		return
	var before: Dictionary = opening.model.checkpoint()
	var advanced: Dictionary = opening.model.advance()
	var loose_raw := 0
	for drop in advanced.get("dropped_material", []):
		loose_raw += int(drop.get("raw", 0))
	if not _expect(advanced.has("belt_spans") and advanced.line_belt_raw + loose_raw == 1
			and advanced.stock.source == restored.stock.source
			and opening.model.validate_checkpoint(opening.model.checkpoint()).get("accepted", false)
			and before.world.history.order == opening.model.checkpoint().world.history.order,
			"The rejoined route can advance without duplicating or dropping the retained blank"):
		return
	_record("pass")

func _arrival_reveal_run(capture_prefix: String) -> void:
	while not opening.arrival_reveal_active and Time.get_ticks_msec() < deadline:
		await process_frame
	var before: Dictionary = opening.model.projection()
	if not _expect(opening.arrival_reveal_active
			and opening.landing_pod_visual.position.y > 6.0
			and opening.arrival_reveal_audio != null
			and opening.arrival_reveal_audio.cue_history.size() > 0
			and opening.arrival_reveal_audio.cue_history[0] == "descent"
			and not opening.landing_hub_visual.visible
			and not opening.character_presenter.visible
			and not opening.arrival_gameplay_canvas.visible and opening.arrival_reveal_canvas.visible
			and root.get_camera_3d() == opening.camera
			and opening.camera.position.distance_to(opening.arrival_reveal_pod_anchor + Vector3(7.0, 17.0, 17.0)) < 2.0
			and not opening._can_control_character(),
			"A fresh arrival begins above the native deck with the actor held during the brief reveal: %s" %
			str([opening.arrival_reveal_active, opening.arrival_reveal_elapsed,
				opening.landing_pod_visual.position.y, opening.landing_hub_visual.visible,
				opening.character_presenter.visible, opening.camera.position,
				root.get_camera_3d() == opening.camera,
				opening._can_control_character(), opening.arrival_reveal_probe])):
		return
	if mode == "arrival-reveal-skip":
		opening._finish_arrival_reveal()
		opening.arrival_reveal_audio.advance(100.0)
		if not _expect(opening.arrival_reveal_audio.cue_history == ["descent"]
				and opening.arrival_reveal_audio.all_stopped(),
				"Skip immediately silences the score before touchdown and leaves no queued cue"):
			return
		await create_timer(0.2).timeout
	else:
		if not capture_prefix.is_empty():
			await RenderingServer.frame_post_draw
			var approach: Image = root.get_texture().get_image()
			if not _expect(approach != null and approach.save_png(capture_prefix + "-approach.png") == OK,
					"The passive approach viewport is retained"):
				return
		while opening.arrival_reveal_elapsed < 1.7 and Time.get_ticks_msec() < deadline:
			await process_frame
		if not _expect(opening.arrival_reveal_active
				and opening.landing_pod_visual.position.distance_to(opening.arrival_reveal_pod_anchor) < 0.01
				and opening.landing_hub_visual.visible,
				"The native pod touches down before the bench and deck finish unfolding"):
			return
		if not capture_prefix.is_empty():
			await RenderingServer.frame_post_draw
			var touchdown: Image = root.get_texture().get_image()
			if not _expect(touchdown != null and touchdown.save_png(capture_prefix + "-touchdown.png") == OK,
					"The passive touchdown viewport is retained"):
				return
		while opening.arrival_reveal_active and Time.get_ticks_msec() < deadline:
			await process_frame
		if not _expect(opening.arrival_reveal_audio.cue_history ==
				["descent", "touchdown", "latch_port", "latch_starboard", "hub_ready"]
				and not opening.arrival_reveal_audio.active,
				"Normal descent, impact, two latches and hub signal play once on the reveal clock"):
			return
		# Let the final chime complete before the short-lived test tree frees it.
		await create_timer(0.45).timeout
		await process_frame
		if not _expect(opening.arrival_reveal_audio.all_stopped(),
				"The naturally completed arrival score releases every playback voice"):
			return
	var after: Dictionary = opening.model.projection()
	var deck_settled := true
	for panel in opening.machine_root.get_children():
		if panel.get_meta("arrival_deck_panel", false):
			var deck_panel := panel as Node3D
			deck_settled = deck_settled and deck_panel.position.distance_to(deck_panel.get_meta("arrival_deck_anchor")) < 0.001 \
				and deck_panel.scale == Vector3.ONE and deck_panel.visible
	if not _expect(not opening.arrival_reveal_active and opening._can_control_character()
			and opening.landing_pod_visual.position.distance_to(opening.arrival_reveal_pod_anchor) < 0.001
			and opening.landing_hub_visual.visible and opening.landing_hub_visual.scale == Vector3.ONE
			and opening.character_presenter.visible and opening.arrival_gameplay_canvas.visible
			and not opening.arrival_reveal_canvas.visible and deck_settled
			and after.landing_pod == before.landing_pod and after.fabrication_hub == before.fabrication_hub
			and after.foundations == before.foundations and after.cargo == before.cargo
			and after.hand_sources == before.hand_sources and after.hand_crank == before.hand_crank,
			"Finishing or skipping restores the ordinary camera, controls and settled native pod visual"):
		return
	if not capture_prefix.is_empty():
		await RenderingServer.frame_post_draw
		var settled: Image = root.get_texture().get_image()
		if not _expect(settled != null and settled.save_png(capture_prefix + "-settled.png") == OK,
				"The passive settled viewport is retained"):
			return
	if "--arrival-close-camera" in OS.get_cmdline_user_args():
		opening.distance = 0.0
		opening._update_camera()
	opening.manager_log_button.pressed.emit()
	if not _expect(opening.manager_log_open and opening.manager_log_layer.visible
			and not opening._can_control_character()
			and "Cut timber or ore" in opening.manager_log_current.text
			and opening.model.projection() == after,
			"The replayable manager log opens after normal or skipped arrival without changing native work"):
		return
	if not capture_prefix.is_empty():
		await RenderingServer.frame_post_draw
		var log_view: Image = root.get_texture().get_image()
		if not _expect(log_view != null and log_view.save_png(capture_prefix + "-work-log.png") == OK,
				"The passive manager work log viewport is retained"):
			return
	opening._toggle_manager_log()
	var after_log: Dictionary = opening.model.projection()
	if not _expect(not opening.manager_log_open and not opening.manager_log_layer.visible
			and opening._can_control_character() and after_log.order == after.order
			and after_log.cargo == after.cargo and after_log.hand_sources == after.hand_sources
			and after_log.landing_pod == after.landing_pod and after_log.fabrication_hub == after.fabrication_hub,
			"Closing the work log restores construction and leaves native stock untouched"):
		return
	_record("pass")

## Fresh arrival panel consumer with actor motor, finite sources and Store.
func _arrival_run() -> void:
	deadline = Time.get_ticks_msec() + (180000 if mode in ["arrival-belt", "arrival-belt-controls", "arrival-delivery"] else 120000)
	var capture_prefix := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arrival-capture-prefix="):
			capture_prefix = argument.trim_prefix("--arrival-capture-prefix=")
	if destination.is_empty() or mode not in ["arrival-press", "arrival-resume", "arrival-delivery", "arrival-delivery-resume", "arrival-craft-capacity", "arrival-field-craft", "arrival-portable-workbench", "arrival-pod-workshop", "arrival-pod-workshop-resume", "arrival-belt", "arrival-belt-controls", "arrival-belt-resume", "arrival-reveal", "arrival-reveal-skip"] or FileAccess.file_exists(destination):
		push_error("Arrival press check requires an unused output and a declared mode")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	if mode in ["arrival-delivery", "arrival-delivery-resume"]:
		# Reuse the ordinary presentation and physical producer with a second
		# native actor provisioned for a later peer on this same checkpoint.
		facts["evidence"] = "native_arrival_scene_dual_actor_consumer"
		facts["actor_roster"] = ["P", "Q"]
		opening.set_script(load("res://opening/opening.gd"))
		opening.model = NativeModel.new("arrival-delivery-" + Crypto.new().generate_random_bytes(16).hex_encode(), ["P", "Q"], true)
	opening.auto_advance = mode == "arrival-reveal"
	opening.arrival_reveal_probe = mode == "arrival-reveal-skip" \
		or (mode == "arrival-resume" and "--arrival-reveal-probe" in OS.get_cmdline_user_args())
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
	if mode == "arrival-pod-workshop-resume":
		await _arrival_pod_workshop_resume_run(opening.arrival_assembly_controls)
		return
	if mode in ["arrival-reveal", "arrival-reveal-skip"]:
		await _arrival_reveal_run(capture_prefix)
		return
	var pod_state: Dictionary = opening.model.projection()
	if not _expect(opening.landing_pod_visual != null and opening.landing_hub_visual != null
			and opening.landing_pod_visual.get_meta("authority_entity", "") == pod_state.landing_pod.id
			and opening.landing_hub_visual.get_meta("authority_entity", "") == pod_state.fabrication_hub.id
			and opening.landing_pod_visual.position.distance_to(Vector3(1.65, 0, 6.6)) < 0.001
			and opening.landing_hub_visual.position.distance_to(Vector3(3.3, 0, 6.6)) < 0.001
			and opening.landing_crank_visual.visible == (pod_state.hand_crank.holder == "pod"),
			"The settled hull and bench meet the native foundation top plane with the crank in its actual custody"):
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
	if mode == "arrival-field-craft":
		await _arrival_field_craft_run(panel)
		return
	if mode == "arrival-portable-workbench":
		await _arrival_portable_workbench_run(panel, capture_prefix)
		return
	if mode == "arrival-pod-workshop":
		await _arrival_pod_workshop_run(panel, capture_prefix)
		return
	if mode in ["arrival-belt", "arrival-belt-controls"]:
		await _arrival_belt_run(panel, capture_prefix)
		return
	if mode == "arrival-belt-resume":
		await _arrival_belt_resume_run()
		return
	if mode == "arrival-craft-capacity":
		await _arrival_capacity_run(panel)
		return
	if not capture_prefix.is_empty() and mode in ["arrival-press", "arrival-delivery"]:
		await process_frame
		var landfall: Image = root.get_texture().get_image()
		if not _expect(landfall != null and landfall.save_png(capture_prefix + "-landfall.png") == OK,
				"The passive landfall viewport is retained"):
			return
	if DisplayServer.get_name() != "headless":
		opening.building_hotbar.select_slot(1)
		if not _expect(opening.mode == "foundation" and opening.machine_preview != null
				and opening.placement_options_panel.visible == opening.machine_preview.visible,
				"The foundation shortcut selects placement and shows options only with its valid ghost"):
			return
		opening._select_tool("inspect")
	if mode in ["arrival-resume", "arrival-delivery-resume"]:
		var restored: Dictionary = opening.model.projection()
		if not _expect(opening.last_load_result.get("accepted", false)
				and opening.arrival_reveal_audio == null
				and restored.cargo.P.products == (1 if mode == "arrival-delivery-resume" else 2)
				and restored.freight_beacon.order_complete == (mode == "arrival-delivery-resume")
				and restored.freight_beacon.shipped_products == (1 if mode == "arrival-delivery-resume" else 0)
				and restored.placed_components.size() == 7
				and restored.cargo.P.components.get("wooden_frame", 0) == 1
				and restored.cargo.P.components.get("receiver_tray", 0) == 1
				and restored.cargo.P.components.get("cutting_edge", 0) == 1
				and restored.cargo.P.components.get("tool_mount", 0) == 1
				and restored.cargo.P.components.get("wooden_shaft", 0) == 1
				and restored.press_assemblies.size() == 1 and restored.press_assemblies[0].status == "ready"
				and restored.hand_crank.holder == "P" and panel.visible
				and opening.landing_pod_visual != null and not opening.landing_crank_visual.visible
				and not opening.arrival_reveal_active,
				"A fresh process reopens the press, finite cargo, freight receipt and one held crank"):
			return
		if mode == "arrival-delivery-resume" and not _expect(restored.actors.has("Q")
				and opening.actor_world.bodies.has("Q")
				and "DELIVERED" in opening.goal_label.text
				and not opening.freight_beacon_visual.get_node("ShipmentLabel").visible,
				"The saved shipment and second actor remain visible on the resumed worksite"):
			return
		opening.manager_log_button.pressed.emit()
		if not _expect(opening.manager_log_open and opening.manager_log_layer.visible
				and ("east freight beacon" in opening.manager_log_current.text
					if mode == "arrival-resume" else not opening.manager_log_current.text.is_empty())
				and opening.model.projection() == restored,
				"The saved site reopens with the same replayable briefing and a current native-backed cue"):
			return
		opening._toggle_manager_log()
		if not _expect(not opening.manager_log_open and opening._can_control_character()
				and opening.model.projection() == restored,
				"A resumed worker can return from the log without replaying arrival or changing stock"):
			return
		panel.crank_button.pressed.emit()
		if not _expect(opening.model.projection().hand_crank.holder == "pod"
				and opening.landing_crank_visual.visible,
				"The resumed ordinary panel can make a new native command"):
			return
		_record("pass")
		return
	if not _expect(panel != null and panel.visible and not panel.craft_button.disabled
			and "3 timber" in panel.recipe_label.text and "Parts 0 / 20" in panel.recipe_label.text,
			"The ordinary workshop panel appears at landfall"):
		return
	var empty_before: Dictionary = opening.model.projection()
	panel.craft_button.pressed.emit()
	var empty_after: Dictionary = opening.model.projection()
	if not _expect(empty_after.order == empty_before.order + 1
			and empty_after.cargo == empty_before.cargo
			and empty_after.hand_sources == empty_before.hand_sources
			and "Gather the timber or softmetal" in opening.status_label.text,
			"The nearby hub records one missing-input refusal without changing carried or source stock"):
		return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	for index in range(8):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	if not await _approach(Vector2(3.3, 9.9)):
		return
	for index in range(7):
		if _construct({"action": "harvest_source", "target": "tree-east-north"}).is_empty():
			return
	if not await _approach(Vector2(0.0, 1.65)):
		return
	for index in range(7):
		if _construct({"action": "harvest_source", "target": "opening-softmetal"}).is_empty():
			return
	var distant_before: Dictionary = opening.model.projection()
	panel.craft_button.pressed.emit()
	var distant_after: Dictionary = opening.model.projection()
	if not _expect(distant_after.order == distant_before.order + 1
			and distant_after.cargo == distant_before.cargo
			and distant_after.hand_sources == distant_before.hand_sources
			and "Move beside the selected workshop" in opening.status_label.text,
			"A remote hub attempt records a refusal and preserves the complete carried bill"):
		return
	if not await _approach(Vector2(1.65, 6.6)):
		return
	var initial: Dictionary = opening.model.projection()
	if not _expect(initial.cargo.P.timber == 15 and initial.cargo.P.raw == 7
			and initial.placed_components.is_empty() and initial.component_recipes.size() == 12,
			"Two finite trees and the ore deposit supply both chapter bills without gifted machines"):
		return
	var part_list := ["wooden_frame", "anvil", "ram_face", "sliding_guide",
		"tool_mount", "wooden_shaft", "wooden_cog"]
	var collector_list := ["wooden_frame", "tool_mount", "cutting_edge", "receiver_tray", "wooden_shaft"]
	for kind: String in part_list + collector_list:
		var index := -1
		for choice in range(panel.COMPONENTS.size()):
			if panel.COMPONENTS[choice][0] == kind:
				index = choice
		if not _expect(index >= 0, "Every collector and press part is available in the ordinary picker"):
			return
		panel.component_choice.select(index)
		panel._component_selected(index)
		var bill: Dictionary = opening.model.projection().component_recipes[kind]
		if not _expect(not panel.craft_button.disabled
				and ("Needs %d timber + %d softmetal" % [bill.timber, bill.softmetal]) in panel.recipe_label.text,
				"The ordinary picker shows the selected native hub recipe"):
			return
		var before: int = opening.model.projection().order
		var owned_before: int = opening.model.projection().cargo.P.components.get(kind, 0)
		panel.craft_button.pressed.emit()
		if not _expect(opening.model.projection().order == before + 1
				and opening.model.projection().cargo.P.components.get(kind, 0) == owned_before + 1,
				"The panel crafts one native component with exact finite cargo"):
			return
	if not _expect(opening.model.projection().cargo.P.timber == 0
			and opening.model.projection().cargo.P.raw == 2
			and opening.model.projection().cargo.P.components.values().reduce(func(total, amount): return total + amount, 0) == 12,
			"Both chapter bills consume fifteen timber and five ore blanks, retaining two press inputs"):
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
	if not _expect(opening.model.projection().hand_crank.holder == "P"
			and not opening.landing_crank_visual.visible,
			"The player takes the one conserved pod crank and its tray visual clears"):
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
	if mode == "arrival-delivery":
		var held_work: Dictionary = opening.model.projection()
		if not await _deliver_first_arrival_plate(held_work, capture_prefix):
			return
	panel.turn_button.pressed.emit()
	if not _expect(opening.model.projection().dropped_material.size() == 1
			and opening.model.projection().dropped_material[0].products == 1,
			"Clearing the exit lets the retained ready work form its second product"):
		return
	panel.pickup_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.products == (1 if mode == "arrival-delivery" else 2)
			and opening.model.projection().dropped_material.is_empty(),
			"The second formed plate enters finite carried custody through ordinary controls"):
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
