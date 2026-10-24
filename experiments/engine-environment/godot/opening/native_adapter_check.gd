extends SceneTree
## Automated headless consumer of the ordinary scene, not a desktop playtest.
const NativeModel = preload("res://opening/native_model.gd")
const OpeningGeometry = preload("res://opening/site_geometry.gd")
const OpeningScene = preload("res://opening/opening.gd")
const TransmissionPresenter = preload("res://opening/native_transmission_presenter.gd")
const ARRIVAL_INITIAL_MASS := 4096 * 4
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
	var audio_refs: Array[WeakRef] = []
	for kind in OpeningScene.MechanicalAmbience.loops:
		audio_refs.append(weakref(OpeningScene.MechanicalAmbience.loops[kind]))
	for cue in OpeningScene.ConstructionAudio.streams:
		audio_refs.append(weakref(OpeningScene.ConstructionAudio.streams[cue]))
	if opening != null:
		if opening.mechanical_ambience != null:
			opening.mechanical_ambience.silence()
		if opening.construction_audio != null:
			var playback: AudioStreamPlayback
			if opening.construction_audio.playing:
				playback = opening.construction_audio.get_stream_playback()
			if playback != null:
				audio_refs.append(weakref(playback))
			playback = null
			opening.construction_audio.stop()
			opening.construction_audio.stream = null
		opening.free()
		opening = null
	OpeningScene.ConstructionAudio.streams.clear()
	OpeningScene.ConstructionAudio.source_status = "uninitialized"
	OpeningScene.MechanicalAmbience.loops.clear()
	# The dummy audio driver can release a stopped playback after scene removal.
	# Observe the actual resources before ending this short lived consumer.
	var audio_deadline := Time.get_ticks_msec() + 2000
	while not audio_refs.is_empty():
		var remaining := 0
		for reference in audio_refs:
			if reference.get_ref() != null:
				remaining += 1
		if remaining == 0:
			break
		if Time.get_ticks_msec() >= audio_deadline:
			push_error("Native scene teardown retains %d audio objects" % remaining)
			quit(1)
			return
		await process_frame
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
	if not _expect(reply.get("accepted", false), "The current immersed route admits " + str(action)):
		return {}
	if action.get("action") == "harvest_source":
		var source_id: String = str(action.get("target", ""))
		var before: int = int(opening.model.projection().get("hand_sources", {}).get(source_id, {}).get("remaining", -1))
		var cut: Dictionary = opening.model.projection().get("manual_cuts", {}).get("P", {})
		for tick in range(int(cut.get("duration_ticks", 0))):
			opening.model.advance()
		opening._refresh()
		if not _expect(not opening.state.get("manual_cuts", {}).has("P") and
			int(opening.state.get("hand_sources", {}).get(source_id, {}).get("remaining", -1)) == before - 1,
			"Trusted native ticks finish exactly one held source cut"):
			return {}
	return reply

func _guided_die_y(ram_id: String) -> float:
	for anchor: Node in opening.transmission_presenter.get_children():
		if anchor.get_meta("component_entity", "") == ram_id:
			var die: Node3D = anchor.get_node_or_null("MovingDie")
			return die.position.y if die != null else NAN
	return NAN

func _capture_guided_close(ram_id: String, path: String) -> bool:
	var ram_anchor: Node3D
	for anchor: Node in opening.transmission_presenter.get_children():
		if anchor.get_meta("component_entity", "") == ram_id:
			ram_anchor = anchor
	if ram_anchor == null:
		return false
	var close := SubViewport.new()
	close.size = Vector2i(1280, 800)
	close.world_3d = root.world_3d
	close.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(close)
	var camera := Camera3D.new()
	close.add_child(camera)
	camera.fov = 38.0
	camera.position = ram_anchor.global_position + Vector3(1.05, 0.72, 1.15)
	camera.look_at(ram_anchor.global_position + Vector3.DOWN * 0.10)
	camera.make_current()
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var captured: bool = close.get_texture().get_image().save_png(path) == OK
	close.queue_free()
	return captured

func _approach(target: Vector2, actor: String = "P") -> bool:
	if not await _walk_to(target, false, actor):
		return false
	for _frame in range(4):
		await physics_frame
		await process_frame
	var sample: Dictionary = opening.actor_world.diagnostics(actor).sample
	return _expect(sample.ready and sample.registered and sample.on_floor and sample.control == [0.0, 0.0],
		"The real approach finishes with a released, registered actor on the floor")

func _approach_points(points: Array[Vector2], actor: String = "P") -> bool:
	for point in points:
		if not await _approach(point, actor):
			return false
	return true

func _arrival_field_craft_run(panel, capture_prefix: String) -> void:
	var inventory = opening.building_hotbar
	inventory.open_catalog()
	if not _expect(inventory.catalog.visible
			and inventory.recipe_buttons.has("component:wooden_frame")
			and "3 timber" in inventory.recipe_buttons["component:wooden_frame"].tooltip_text
			and "Carry the ingredients" in inventory.recipe_buttons["component:wooden_frame"].tooltip_text,
			"Fresh arrival exposes the wooden recipe and its missing carried ingredients"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-empty.png") == OK,
				"Retain the ordinary zero-stock inventory view"):
			return
		var original_size: Vector2i = root.size
		root.size = Vector2i(640, 480)
		await process_frame
		inventory._place_catalog()
		await RenderingServer.frame_post_draw
		if not _expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
				Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size)))
				and root.get_texture().get_image().save_png(capture_prefix + "-empty-narrow.png") == OK,
				"The ordinary zero-stock inventory remains usable at a narrow viewport"):
			return
		root.size = original_size
		await process_frame
		inventory._place_catalog()
	inventory.catalog.hide()
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
	inventory.open_catalog()
	if not _expect(inventory.material_counts.timber.text == "3"
			and inventory.material_buttons.timber.visible
			and "Craft here" in inventory.recipe_buttons["component:wooden_frame"].tooltip_text,
			"Finite cuts refresh the carried stack and available recipe in one inventory"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-timber.png") == OK,
				"Retain the ordinary finite-timber inventory view"):
			return
		var original_size: Vector2i = root.size
		root.size = Vector2i(640, 480)
		await process_frame
		inventory._place_catalog()
		await RenderingServer.frame_post_draw
		if not _expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
				Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size)))
				and root.get_texture().get_image().save_png(capture_prefix + "-timber-narrow.png") == OK,
				"The ordinary carried-timber inventory remains usable at a narrow viewport"):
			return
		root.size = original_size
		await process_frame
		inventory._place_catalog()
	inventory.recipe_buttons["component:wooden_frame"].pressed.emit()
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
	inventory.catalog.hide()
	if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
		return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	var bench_ready: Dictionary = opening.model.projection()
	opening._open_object_menu_for(str(opening.model.projection().fabrication_hub.id))
	await process_frame
	if not _expect(inventory.catalog.visible and inventory.context_bench == "pod-fabrication-hub"
			and not opening.object_menu.visible
			and "Craft here" in inventory.recipe_buttons["component:wooden_shaft"].tooltip_text,
			"E on the installed pod opens the same recipe grid with bench crafting available"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-bench.png") == OK,
				"Retain the ordinary E-opened bench inventory view"):
			return
	inventory.recipe_buttons["component:wooden_shaft"].pressed.emit()
	var bench_shaped: Dictionary = opening.model.projection()
	if not _expect(bench_shaped.order == bench_ready.order + 1
			and bench_shaped.cargo.P.timber == 0
			and bench_shaped.cargo.P.components.get("wooden_shaft", 0) == 1
			and bench_shaped.cargo.P.components.get("wooden_frame", 0) == 1,
			"The E-opened recipe icon sends a reachable native bench craft with finite custody: " +
			str({"order": bench_shaped.order, "expected": bench_ready.order + 1,
				"cargo": bench_shaped.cargo.P, "status": opening.status_label.text})):
		return
	inventory.catalog.hide()
	var saved: Dictionary = opening._save_worksite()
	facts["save_result"] = saved
	facts["save_slot"] = opening.save_slot
	if not _expect(saved.accepted and saved.native_preflight.accepted
			and FileAccess.file_exists(opening.save_slot),
			"Store saves field and bench components with finite source depletion: " + str(saved)):
		return
	_record("pass")

func _arrival_foundation_craft_run(panel, capture_prefix: String) -> void:
	var inventory = opening.building_hotbar
	if not await _approach(Vector2(6.0, 3.45)):
		return
	for index in range(2):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	var before: Dictionary = opening.model.projection()
	opening._open_object_menu_for(before.fabrication_hub.id)
	if not _expect(inventory.catalog.visible and inventory.context_bench == before.fabrication_hub.id
			and before.cargo.P.timber == 2 and before.foundation_recipe.timber == 2
			and "2 timber" in inventory.recipe_buttons.foundation.tooltip_text
			and "Craft here" in inventory.recipe_buttons.foundation.tooltip_text,
			"The E-opened inventory exposes its native floor recipe beside gathered timber"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-foundation-craft.png") == OK,
				"The ordinary workshop floor control is retained in a rendered frame"):
			return
	inventory.recipe_buttons.foundation.pressed.emit()
	var crafted: Dictionary = opening.model.projection()
	if not _expect(crafted.order == before.order + 1 and crafted.cargo.P.timber == 0
			and crafted.part_kits.P.foundation == before.part_kits.P.foundation + 1
			and crafted.hand_sources["tree-east-south"].remaining == 6
			and "Carry the ingredients" in inventory.recipe_buttons.foundation.tooltip_text,
			"The recipe icon converts two finite timber into one native foundation and updates availability"):
		return
	inventory.catalog.hide()
	if not await _approach(Vector2(9.0, 6.0)):
		return
	var placed: Dictionary = _construct({"action": "place_foundation", "cell": [5, 2], "level": 2})
	if placed.is_empty():
		return
	var built: Dictionary = opening.model.projection()
	var floor_id := ""
	for id: String in built.foundations:
		if built.foundations[id].cell == [5, 2] and built.foundations[id].level == 2:
			floor_id = id
	if not _expect(not floor_id.is_empty() and built.part_kits.P.foundation == before.part_kits.P.foundation,
			"The crafted floor can enter the ordinary native construction inventory"):
		return
	if _construct({"action": "remove", "entity": floor_id}).is_empty():
		return
	var reclaimed: Dictionary = opening.model.projection()
	if not _expect(reclaimed.part_kits.P.foundation == crafted.part_kits.P.foundation
			and reclaimed.cargo.P.timber == 0 and not reclaimed.foundations.has(floor_id)
			and reclaimed.foundations.size() == crafted.foundations.size(),
			"Reclaiming restores exactly the crafted floor without refunding its timber"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts["save_result"] = saved
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false)
			and opening.model.validate_checkpoint(opening.model.checkpoint()).accepted,
			"Store preserves the spent source and reclaimed floor in a valid native checkpoint: " + str(saved)):
		return
	_record("pass")

func _arrival_foundation_craft_resume_run(panel) -> void:
	var state: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and state.cargo.P.timber == 0 and state.hand_sources["tree-east-south"].remaining == 6
			and state.part_kits.P.foundation == 16 and state.foundations.size() == 9
			and "Carry the ingredients" in opening.building_hotbar.recipe_buttons.foundation.tooltip_text
			and opening.model.validate_checkpoint(opening.model.checkpoint()).accepted,
			"Fresh process restores the spent timber, reclaimed crafted floor and unavailable workshop control: "
			+ str({"load": opening.last_load_result, "timber": state.cargo.P.timber,
				"remaining": state.hand_sources["tree-east-south"].remaining,
				"floors": state.part_kits.P.foundation, "placed": state.foundations.size(),
				"recipe": opening.building_hotbar.recipe_buttons.foundation.tooltip_text})):
		return
	_record("pass")

func _arrival_portable_workbench_run(panel, capture_prefix: String) -> void:
	var inventory = opening.building_hotbar
	inventory.open_catalog()
	if not _expect(inventory.recipe_buttons.has("component:wooden_workbench")
			and "4 timber" in inventory.recipe_buttons["component:wooden_workbench"].tooltip_text,
			"The ordinary inventory lists a finite wooden-workbench recipe"):
		return
	inventory.catalog.hide()
	if not await _approach(Vector2(6.0, 3.45)):
		return
	for index in range(4):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	var cut: Dictionary = opening.model.projection()
	inventory.open_catalog()
	inventory.recipe_buttons["component:wooden_workbench"].pressed.emit()
	var shaped: Dictionary = opening.model.projection()
	if not _expect(shaped.order == cut.order + 1 and shaped.cargo.P.timber == 0
			and shaped.cargo.P.components.get("wooden_workbench", 0) == 1
			and shaped.hand_sources["tree-east-south"].remaining == 4,
			"Four real timber cuts become one carried workbench through the field tool"):
		return
	inventory.material_buttons.timber.grab_focus()
	if not _expect(inventory.component_buttons.wooden_workbench.visible
			and inventory.component_counts.wooden_workbench.text == "1",
			"The newly shaped bench appears as one carried component tile"):
		return
	inventory.component_buttons.wooden_workbench.pressed.emit()
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
	if not await _approach_points([Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	if _construct({"action": "harvest_source", "target": "opening-softmetal"}).is_empty():
		return
	opening._open_object_menu_for(id)
	var remote: Dictionary = opening.model.projection()
	inventory.recipe_buttons["component:cutting_edge"].pressed.emit()
	var refused: Dictionary = opening.model.projection()
	if not _expect(refused.order == remote.order + 1 and refused.cargo == remote.cargo
			and inventory.context_bench == id and "selected workshop" in opening.status_label.text,
			"E on a distant placed bench does not spend ore or craft remotely"):
		return
	inventory.catalog.hide()
	if not await _approach(Vector2(6.0, 4.95)):
		return
	opening._open_object_menu_for(id)
	inventory.recipe_buttons["component:cutting_edge"].pressed.emit()
	inventory.catalog.hide()
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
	opening._open_object_menu_for(id)
	if not _expect(inventory.catalog.visible and inventory.context_action.visible
			and not inventory.context_action.disabled
			and "Reclaim wooden workbench" in inventory.context_action.tooltip_text,
			"The placed bench offers a reclaim icon beside its recipes in the E-opened inventory"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-reclaim-menu.png") == OK,
				"The selected bench reclaim icon is retained in the ordinary E menu"):
			return
	var reclaim_key := InputEventKey.new()
	reclaim_key.keycode = KEY_R
	reclaim_key.pressed = true
	inventory._input(reclaim_key)
	inventory.catalog.hide()
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
	var inventory = opening.building_hotbar
	var pod_anchor: Vector3 = opening.landing_pod_visual.position
	if not _expect(panel.pod_workshop_button.visible and not panel.pod_workshop_button.disabled
			and panel.pod_workshop_button.text.is_empty() and panel.pod_workshop_button.icon != null
			and "Stow pod workshop" in panel.pod_workshop_button.tooltip_text
			and "shortcut S" in panel.pod_workshop_button.accessibility_name
			and opening.landing_hub_pick.collision_layer == OpeningGeometry.PICK_LAYER,
			"The ordinary panel and pick body expose the installed issued workshop"):
		return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	opening._open_object_menu_for(id)
	await process_frame
	if not _expect(inventory.catalog.visible and inventory.context_bench == id
			and inventory.context_action.visible and not inventory.context_action.disabled
			and "Stow pod workshop" in inventory.context_action.tooltip_text
			and not opening.object_menu.visible,
			"E exposes the bench recipes and pod custody icon in one inventory window"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-pod-workshop-menu.png") == OK,
				"The ordinary pod workshop icon is retained in a rendered menu frame"):
			return
	var before_close: Dictionary = opening.model.projection()
	inventory.catalog.hide()
	await process_frame
	var after_close: Dictionary = opening.model.projection()
	if not _expect(not inventory.catalog.visible and after_close.order == before_close.order
			and after_close.fabrication_hub == before_close.fabrication_hub
			and after_close.cargo == before_close.cargo,
			"The focused close control leaves native custody untouched"):
		return
	opening._open_object_menu_for(id)
	var stow_key := InputEventKey.new()
	stow_key.keycode = KEY_S
	stow_key.pressed = true
	inventory._input(stow_key)
	inventory.catalog.hide()
	await process_frame
	var carried: Dictionary = opening.model.projection()
	if not _expect(not carried.fabrication_hub.installed and carried.fabrication_hub.holder == "P"
			and carried.fabrication_hub.id == id and carried.fabrication_hub.generation == 1
			and opening.landing_pod_visual.position == pod_anchor
			and not opening.landing_hub_visual.visible and opening.landing_hub_pick.collision_layer == 0
			and opening.landing_crank_visual.visible and panel.bench_choice.item_count == 0
			and "Place carried pod workshop" in panel.pod_workshop_button.tooltip_text
			and "shortcut S" in panel.pod_workshop_button.accessibility_name,
			"Stowing moves only the one issued hub into actor custody while pod and crank stay landed"):
		return
	var invalid: Dictionary = _issue({"action": "deploy_fabrication_hub", "entity": id,
		"center": [17, 0, 12]})
	if not _expect(not invalid.accepted and invalid.reason == "unsupported_bench"
			and opening.model.projection().fabrication_hub.holder == "P"
			and not opening.landing_hub_visual.visible,
			"An off-grid redeploy refusal preserves held identity and keeps the world body absent"):
		return
	inventory.open_catalog()
	if not _expect(inventory.material_buttons.fabrication_hub.visible
			and inventory.material_counts.fabrication_hub.text == "1"
			and "select placement" in inventory.material_buttons.fabrication_hub.tooltip_text,
			"A stowed pod appears as one directly placeable carried inventory item"):
		return
	inventory.material_buttons.fabrication_hub.pressed.emit()
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
	if not _expect(opening.selected == id and inventory.catalog.visible
			and inventory.context_bench == id and inventory.parts_label.text == "BENCH / INVENTORY"
			and "Grid center" in opening.inspector.text,
			"E opens the relocated hub's shared bench inventory and current grid center"):
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
	inventory.catalog.hide()
	await process_frame
	if not await _approach_points([Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	if _construct({"action": "harvest_source", "target": "opening-softmetal"}).is_empty():
		return
	if not await _approach(Vector2(5.4, 4.95)):
		return
	opening._open_object_menu_for(id)
	if not _expect(inventory.catalog.visible and inventory.context_bench == id
			and "Craft here" in inventory.recipe_buttons["component:cutting_edge"].tooltip_text,
			"The relocated pod exposes its metal recipe in the same E-opened grid"):
		return
	inventory.recipe_buttons["component:cutting_edge"].pressed.emit()
	inventory.catalog.hide()
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
	if mode == "supplied-hardware":
		await _arrival_run()
		return
	if mode in ["arrival-press", "arrival-press-site", "arrival-belt-fed-press", "arrival-belt-fed-press-resume", "arrival-broad-pad", "arrival-broad-drive", "arrival-raised-press", "arrival-raised-press-resume", "arrival-resume", "arrival-delivery", "arrival-delivery-resume", "arrival-repeat-delivery", "arrival-repeat-delivery-resume", "arrival-repeat-delivery-q-resume", "arrival-craft-capacity", "arrival-craft-capacity-resume", "arrival-field-craft", "arrival-foundation-craft", "arrival-foundation-craft-resume", "arrival-portable-workbench", "arrival-pod-workshop", "arrival-pod-workshop-resume", "arrival-belt", "arrival-belt-controls", "arrival-belt-resume", "arrival-reveal", "arrival-reveal-skip"]:
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

func _walk_to(target: Vector2, jump: bool = false, actor: String = "P") -> bool:
	var jumped := false
	var highest_foot := -INF
	var leg_deadline := mini(deadline, Time.get_ticks_msec() + 45000)
	while Time.get_ticks_msec() < leg_deadline:
		var body = opening.actor_world.bodies[actor]
		var at: Vector3 = body.global_position
		highest_foot = maxf(highest_foot, at.y - OpeningGeometry.CAPSULE_HEIGHT / 2.0)
		var gap := target - Vector2(at.x, at.z)
		if gap.length() < 0.08:
			opening.actor_world.release_control(actor)
			if jump:
				facts["foundation_jump"] = {"edge_sent": jumped, "highest_foot": highest_foot}
			return true
		var jump_edge: bool = jump and not jumped and gap.length() < 1.2 and body.is_on_floor()
		if not _expect(opening.actor_world.set_control(actor, gap.normalized(), jump_edge).accepted,
				"The fixture walks through the real character motor without setting a pose"):
			return false
		jumped = jumped or jump_edge
		await physics_frame
		await process_frame
	opening.actor_world.release_control(actor)
	var stopped_at: Vector3 = opening.actor_world.bodies[actor].global_position
	facts["failed_walk"] = {"actor": actor, "target": target, "stopped_at": stopped_at}
	return _expect(false, "The bounded native walk must reach %s; stopped at %s" % [target, stopped_at])

func _deliver_first_arrival_plate(held_work: Dictionary, _capture_prefix: String) -> bool:
	# Keep the native shipment custody regression as an internal fixture. The
	# playable first-workshop objective now completes at local inventory pickup.
	var beacon: Dictionary = opening.model.projection().freight_beacon
	var distant: Dictionary = _issue({"action": "deliver_first_plate", "entity": beacon.id})
	if not _expect(not distant.get("accepted", false) and distant.get("reason") == "out_of_reach"
			and opening.model.projection().cargo.P.products == 1,
			"The archived native delivery path still refuses a remote cargo debit"):
		return false
	if not await _approach_points([Vector2(4.95, 4.95), Vector2(6.6, 4.95),
			Vector2(6.6, 8.25), Vector2(9.9, 8.25)]):
		return false
	var first_request: String = str(opening.request_namespace) + str(opening.request_sequence + 1)
	var before: Dictionary = opening.model.projection()
	var receipt: Dictionary = _issue({"action": "deliver_first_plate", "entity": beacon.id})
	var shipped: Dictionary = opening.model.projection()
	if not _expect(receipt.get("accepted", false) and shipped.order == before.order + 1
			and shipped.cargo.P.products == 0 and shipped.freight_beacon.shipped_products == 1
			and shipped.dropped_material == held_work.dropped_material
			and shipped.guided_press_assemblies == held_work.guided_press_assemblies
			and "FORM A PLATE · KEEP IT" in opening.goal_label.text
			and not opening.manager_log_completion_entry.visible,
			"Internal delivery debits one plate without satisfying the inventory goal"):
		return false
	var before_retry: Dictionary = opening.model.checkpoint()
	var retry: Dictionary = opening.model.command({"context": shipped.context, "client": "P",
		"request": first_request, "action": "deliver_first_plate", "entity": beacon.id})
	if not _expect(retry.get("accepted", false) and retry.get("duplicate", false)
			and opening.model.checkpoint() == before_retry,
			"Retrying the archived request cannot debit a second plate"):
		return false
	facts["delivery"] = {"request": first_request, "receipt": retry, "beacon": shipped.freight_beacon}
	return await _approach_points([Vector2(6.6, 8.25), Vector2(6.6, 4.95), Vector2(4.95, 4.95)])

func _deliver_repeat_arrival_plates(panel, capture_prefix: String) -> bool:
	var beacon: Dictionary = opening.model.projection().freight_beacon
	if not _expect(beacon.order_complete and beacon.repeat_order_shipped == 0
			and opening.model.projection().cargo.P.products == 1,
			"The first saved receipt exposes an open repeat order and one real carried plate"):
		return false
	if not await _approach_points([Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return false
	for index in range(2):
		if _construct({"action": "harvest_source", "target": "opening-softmetal"}).is_empty():
			return false
	# The deployed pod workshop now has a real collider at (3.3, 6.6).
	# Work from its clear front aisle, still within native press reach.
	if not await _approach(Vector2(4.95, 4.95)):
		return false
	for index in range(2):
		if not _expect(not panel.feed_button.disabled, "The ordinary press can accept another finite blank"):
			return false
		panel.feed_button.pressed.emit()
		for turn in range(3):
			if not _expect(not panel.turn_button.disabled, "The player can advance the retained work with the crank"):
				return false
			panel.turn_button.pressed.emit()
		if not _expect(not panel.pickup_button.disabled, "The next formed plate can be picked up physically"):
			return false
		panel.pickup_button.pressed.emit()
		if not _expect(not panel.recover_work_button.disabled
				and panel.recover_work_button.tooltip_text.contains("offcut"),
				"The next press stroke retains a separate recoverable copper trimming"):
			return false
		panel.recover_work_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.products == 3
			and opening.model.projection().cargo.P.offcuts == 4
			and opening.model.projection().cargo.P.raw == 0
			and opening.model.projection().dropped_material.is_empty()
			and opening.model.projection().material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"Two more local blanks become plates beside the retained second plate without gifted stock"):
		return false
	var press_anvil: String = str(opening.model.projection().guided_press_assemblies[0].anvil)
	if opening._object_menu_open() and opening.object_menu_target != press_anvil:
		opening.object_menu.hide()
		await process_frame
	if not opening._object_menu_open():
		opening._open_object_menu_for(press_anvil)
	if not _expect(opening._object_menu_open() and opening.object_menu_target == press_anvil
			and opening.object_menu_operations.visible
			and panel.compact_button.is_visible_in_tree() and not panel.compact_button.disabled
			and panel.compact_button.icon != null
			and panel.compact_button.focus_mode == Control.FOCUS_ALL
			and panel.compact_button.accessibility_name.contains("offcuts")
			and panel.compact_button.tooltip_text.contains("[4/4]"),
			"Four recovered offcuts expose a visible, focusable press compaction control"):
		return false
	if not capture_prefix.is_empty():
		await process_frame
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-recycle-control.png") == OK,
				"The selected press and its offcut control are retained as passive scene pixels"):
			return false
	panel.compact_button.pressed.emit()
	var recycled: Dictionary = opening.model.projection()
	if not _expect(recycled.cargo.P.offcuts == 0 and recycled.cargo.P.products == 3
			and recycled.dropped_material.size() == 1
			and recycled.dropped_material[0].raw == 1
			and recycled.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
			and panel.compact_button.disabled,
			"The ordinary press compacts four carried offcuts into one recoverable full-mass blank"):
		return false
	opening.object_menu_close.pressed.emit()
	if not _expect(not opening._object_menu_open(),
			"Closing the inspected press returns ordinary E control for the repeat shipment"):
		return false
	if not capture_prefix.is_empty():
		var prior_focus: Vector3 = opening.focus
		var prior_distance: float = opening.distance
		var prior_pitch: float = opening.orbit_pitch
		opening.focus = TransmissionPresenter.world_center(recycled.dropped_material[0].center) + Vector3.UP * 0.45
		opening.distance = 3.5
		opening.orbit_pitch = 0.45
		opening._update_camera()
		await process_frame
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-recycled-blank.png") == OK,
				"The recycled blank and press controls are retained as passive scene pixels"):
			return false
		opening.focus = prior_focus
		opening.distance = prior_distance
		opening.orbit_pitch = prior_pitch
		opening._update_camera()
	if not await _approach_points([Vector2(6.6, 4.95), Vector2(6.6, 8.25), Vector2(9.9, 8.25)]):
		return false
	for index in range(3):
		var before: Dictionary = opening.model.projection()
		var receipt: Dictionary = _issue({"action": "deliver_repeat_plate", "entity": beacon.id})
		var after: Dictionary = opening.model.projection()
		if not _expect(receipt.get("accepted", false) and after.order == before.order + 1
				and after.cargo.P.products == 2 - index
				and after.freight_beacon.shipped_products == 2 + index
				and after.freight_beacon.repeat_order_shipped == 1 + index
				and after.freight_beacon.repeat_order_target == 3
				and after.freight_beacon.repeat_order_complete == (index == 2),
			"The internal regression action debits one carried plate at a time"):
			return false
	var full: Dictionary = _issue({"action": "deliver_repeat_plate", "entity": beacon.id})
	if not _expect(not full.get("accepted", false) and full.get("reason") == "order_filled"
			and opening.model.projection().cargo.P.products == 0
			and opening.model.projection().freight_beacon.shipped_products == 4
			and "FORM A PLATE · KEEP IT" in opening.goal_label.text,
			"A fifth shipment refuses after the repeat order closes without changing material custody"):
		return false
	if not capture_prefix.is_empty():
		await process_frame
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-inventory-goal-after-internal-transfer.png") == OK,
				"The ordinary viewport has no shipment cue after the internal transfer"):
			return false
	facts["repeat_delivery"] = {"beacon": opening.model.projection().freight_beacon,
		"actor": opening.actor_world.diagnostics("P").sample}
	return true

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

func _arrival_capacity_run(panel, capture_prefix: String) -> void:
	var recipes: Dictionary = opening.model.projection().component_recipes
	opening._open_object_menu_for(str(opening.model.projection().fabrication_hub.id))
	if not _expect(opening._object_menu_open() and panel.is_visible_in_tree(),
			"The pod workshop exposes the native component choices in its centered panel"):
		return
	if not _expect(recipes.wooden_shaft.load_rating == 8
			and recipes.wooden_cog.load_rating == 8
			and recipes.softmetal_shaft.load_rating == 24
			and recipes.softmetal_cog.load_rating == 24,
			"The ordinary workshop receives its drive ratings from the native projection"):
		return
	panel.component_choice.select(9)
	panel._component_selected(9)
	if not _expect("Drive limits: wood 8 · softmetal 24" in panel.recipe_label.text
			and "Rated for 24 load" in panel.component_choice.tooltip_text
			and "Need 0 timber + 2 softmetal" in panel.recipe_label.text,
			"The selected softmetal upgrade shows stronger load and its actual local bill"):
		return
	if not capture_prefix.is_empty():
		await process_frame
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-drive-ratings.png") == OK,
				"The native-backed workshop rating is retained in a normal viewport frame"):
			return
	var original_choice: String = panel.component_choice.get_item_text(9)
	var original_place: String = panel.place_button.text
	var original_route: String = panel.part_place_button.text
	panel.component_choice.set_item_text(9, "Softmetal shaft  ×999")
	panel.place_button.text = "Place softmetal shaft"
	panel.part_place_button.text = "Connect shafts"
	await process_frame
	await process_frame
	var menu_left: float = opening.object_menu.position.x
	var menu_right: float = menu_left + opening.object_menu.size.x
	var scroll_rect: Rect2 = opening.arrival_assembly_scroll.get_global_rect()
	var place_rect: Rect2 = panel.place_button.get_global_rect()
	# Embedded popup child rects are local to the popup window, while the popup
	# position is in the root viewport. Compare them in the same space.
	var scroll_left: float = menu_left + scroll_rect.position.x
	var scroll_right: float = menu_left + scroll_rect.end.x
	var place_right: float = menu_left + place_rect.end.x
	facts["workshop_layout"] = {"menu_left": menu_left, "menu_right": menu_right,
		"scroll_left": scroll_left, "scroll_right": scroll_right,
		"place_right": place_right, "viewport_width": root.size.x,
		"horizontal_scroll": opening.arrival_assembly_scroll.get_h_scroll_bar().visible}
	if not capture_prefix.is_empty():
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-long-choice.png") == OK,
				"The long component choice is retained in the centered workshop"):
			return
	if not _expect(menu_left >= 0 and menu_right <= root.size.x
			and scroll_left >= menu_left and scroll_right <= menu_right
			and place_right <= scroll_right
			and not opening.arrival_assembly_scroll.get_h_scroll_bar().visible,
			"Long component actions remain horizontally reachable inside the centered workshop: "
			+ str(facts.workshop_layout)):
		return
	panel.component_choice.set_item_text(9, original_choice)
	panel.place_button.text = original_place
	panel.part_place_button.text = original_route
	opening.object_menu.hide()
	await process_frame
	panel.component_choice.select(0)
	panel._component_selected(0)
	# Zero-cut entries are explicit clear-aisle waypoints, not resource actions.
	for source in [
		{"point": Vector2(6.0, 3.45), "id": "tree-east-south", "cuts": 8},
		{"point": Vector2(4.95, 4.95), "cuts": 0},
		{"point": Vector2(4.95, 9.9), "cuts": 0},
		{"point": Vector2(6.0, 11.55), "id": "tree-east-north", "cuts": 8},
		{"point": Vector2(0.6, 11.55), "id": "tree-north", "cuts": 5},
	]:
		if not await _approach(source.point):
			return
		for index in range(source.cuts):
			if _construct({"action": "harvest_source", "target": source.id}).is_empty():
				return
	if not await _approach_points([Vector2(4.95, 9.9), Vector2(4.95, 4.95), Vector2(3.3, 4.95)]):
		return
	var gathered: Dictionary = opening.model.projection()
	if not _expect(gathered.cargo.P.timber == 21
			and gathered.hand_sources["tree-east-south"].remaining == 0
			and gathered.hand_sources["tree-east-north"].remaining == 0
			and gathered.hand_sources["tree-north"].remaining == 3,
			"Three finite trees supply twenty-one real component inputs"):
		return
	panel.component_choice.select(1)
	panel._component_selected(1)
	for count in range(21):
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
	var crafted: Dictionary = opening.model.projection()
	if not _expect(crafted.cargo.P.timber == 0
			and crafted.cargo.P.components.get("wooden_shaft", 0) == 21
			and crafted.hand_sources == gathered.hand_sources
			and crafted.placed_components.is_empty()
			and crafted.order == gathered.order + 21,
			"Twenty-one carried shafts consume exactly twenty-one finite timber without a placement detour"):
		return
	opening.building_hotbar.open_catalog()
	await process_frame
	var tile: Button = opening.building_hotbar.component_buttons.wooden_shaft
	if not _expect(opening.building_hotbar.catalog.visible and tile.icon != null
			and opening.building_hotbar.component_counts.wooden_shaft.text == "21"
			and "21 carried" in tile.tooltip_text
			and "21 carried" in tile.accessibility_name,
			"The shared build and inventory window shows twenty-one shafts as an icon, count, and hover description"):
		return
	var inventory_scroll: ScrollContainer = opening.building_hotbar.component_grid.get_parent().get_parent()
	inventory_scroll.ensure_control_visible(tile)
	await process_frame
	if not _expect(inventory_scroll.get_global_rect().encloses(tile.get_global_rect()),
			"The twenty-one shaft icon and count can be brought fully into the visible inventory scroll area"):
		return
	if not capture_prefix.is_empty():
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-carried-shafts.png") == OK,
				"The normal build and inventory window is retained after crafting"):
			return
	opening.building_hotbar.catalog.hide()
	var saved: Dictionary = opening._save_worksite()
	facts["save_result"] = saved
	facts["save_slot"] = opening.save_slot
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false)
			and FileAccess.file_exists(opening.save_slot)
			and opening.model.validate_checkpoint(opening.model.checkpoint()).accepted,
			"Store retains the twenty-one carried components and depleted tree stocks in a valid checkpoint"):
		return
	_record("pass")

func _arrival_capacity_resume_run() -> void:
	var state: Dictionary = opening.model.projection()
	while not opening.preview_prefetch_complete and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _expect(opening.preview_prefetch_complete,
			"The reopened scene finishes its normal preview requests before fixture teardown"):
		return
	opening.building_hotbar.open_catalog()
	await process_frame
	var tile: Button = opening.building_hotbar.component_buttons.wooden_shaft
	if not _expect(opening.last_load_result.get("accepted", false)
			and state.cargo.P.timber == 0
			and state.cargo.P.components.get("wooden_shaft", 0) == 21
			and state.hand_sources["tree-east-south"].remaining == 0
			and state.hand_sources["tree-east-north"].remaining == 0
			and state.hand_sources["tree-north"].remaining == 3
			and state.placed_components.is_empty()
			and opening.building_hotbar.catalog.visible and tile.icon != null
			and opening.building_hotbar.component_counts.wooden_shaft.text == "21"
			and "21 carried" in tile.tooltip_text
			and opening.model.validate_checkpoint(opening.model.checkpoint()).accepted,
			"A fresh ordinary scene restores every finite source and all twenty-one carried shaft icons"):
		return
	_record("pass")

func _arrival_belt_run(panel, capture_prefix: String, finish: bool = true) -> void:
	# This uses the ordinary arrival scene, its physical actor, workshop buttons
	# and the native terrain. Commands still pass through the one scene Model.
	var ore_for_press := 0 if finish else 8
	for source in [
		{"point": Vector2(6.0, 3.45), "id": "tree-east-south", "cuts": 8},
		{"point": Vector2(4.95, 4.95), "cuts": 0},
		{"point": Vector2(4.95, 9.9), "cuts": 0},
		{"point": Vector2(6.0, 11.55), "id": "tree-east-north", "cuts": 6},
		{"point": Vector2(4.95, 9.9), "cuts": 0},
		{"point": Vector2(4.95, 3.3), "cuts": 0},
		{"point": Vector2(-0.5, 0.0), "id": "opening-softmetal", "cuts": 3 + ore_for_press},
	]:
		if not await _approach(source.point):
			return
		for index in range(source.cuts):
			if _construct({"action": "harvest_source", "target": source.id}).is_empty():
				return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	if not _expect(opening.model.projection().cargo.P.timber == 14
			and opening.model.projection().cargo.P.raw == 3 + ore_for_press,
			"Two finite trees and the outcrop supply the collector route and later press stock"):
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
			and opening.model.projection().cargo.P.raw == ore_for_press,
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
	if finish:
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
	if not _expect(opening.selected == span and opening.request_sequence == selected_sequence
			and opening.inspector.text.begins_with("Mechanical belt\n"),
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
	# The initial native projection may refresh the installed hub between
	# starting the reveal and the first presentation tick. Inspect its rendered
	# phase after that tick, when the reveal pose owns visibility.
	if mode == "arrival-reveal" and opening.landing_hub_visual.visible:
		await process_frame
		await process_frame
	if mode == "arrival-reveal" and opening.arrival_reveal_active and opening.arrival_reveal_elapsed < 1.45 \
			and not _expect(not opening.landing_hub_visual.visible,
				"The hub remains folded away during the descent presentation"):
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
		while opening.arrival_reveal_active and opening.arrival_reveal_elapsed < 1.7 \
				and Time.get_ticks_msec() < deadline:
			await process_frame
		var touchdown_elapsed: float = opening.arrival_reveal_elapsed
		if not _expect(touchdown_elapsed >= 1.7
				and opening.landing_pod_visual.position.distance_to(opening.arrival_reveal_pod_anchor) < 0.01
				and (touchdown_elapsed > 1.8 or not opening.landing_hub_visual.visible),
				"The pod reaches its anchor before the later bench reveal; elapsed %.2f, hub visible %s" %
				[touchdown_elapsed, opening.landing_hub_visual.visible]):
			return
		# Slow renderers may advance beyond the fold before the next drawable
		# frame. Keep the natural clock and identify the missing sample explicitly.
		facts["touchdown_sample"] = "not_requested" if capture_prefix.is_empty() else "skipped_after_fold"
		if not capture_prefix.is_empty() and opening.arrival_reveal_active and touchdown_elapsed < 2.0:
			await RenderingServer.frame_post_draw
			if opening.arrival_reveal_active and opening.arrival_reveal_elapsed < 2.0:
				var touchdown: Image = root.get_texture().get_image()
				if not _expect(touchdown != null and touchdown.save_png(capture_prefix + "-touchdown.png") == OK,
					"The passive touchdown viewport is retained"):
					return
				facts["touchdown_sample"] = "captured"
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

func _supplied_hardware_hits(at: Vector3) -> Array:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = opening.actor_world.bodies.P.capsule
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = OpeningGeometry.MACHINE_LAYER
	return opening.get_world_3d().direct_space_state.intersect_shape(query, 64)

func _supplied_hardware_run() -> void:
	# Only this bounded automated case supplies trusted motor directions.
	# Disable the ordinary idle input producer, never set an actor pose.
	opening.set_process(false)
	opening.character_presenter.set_physics_process(false)
	var bridge = opening.actor_world
	var body = bridge.bodies.P
	var initial: Dictionary = opening.model.projection()
	var material: Dictionary = opening.model.checkpoint().world.state.material
	var solids: Dictionary = initial.supplied_hardware_boxes
	if not _expect(solids.size() == 20 and bridge.component_bodies.size() == 20
			and bridge._geometry_registered(), "The actual native scene registers every emitted supplied solid"):
		return
	var identities := {}
	for id in bridge.component_bodies:
		identities[id] = bridge.component_bodies[id].get_instance_id()
	for repeat in 3:
		if not _expect(bridge.sync_topology().accepted, "An unchanged topology remains valid"):
			return
	for id in identities:
		if not _expect(bridge.component_bodies[id].get_instance_id() == identities[id],
				"Unchanged supplied bodies keep their cached native identities"):
			return
	var missing: Dictionary = initial.duplicate(true)
	missing.erase("supplied_hardware_boxes")
	if not _expect(not OpeningGeometry.component_boxes(missing).accepted,
			"A native pod without its occupied projection cannot silently lose collision"):
		return
	if not _expect(not _supplied_hardware_hits(Vector3(1.65, 0.9, 6.6)).is_empty()
			and not _supplied_hardware_hits(Vector3(3.3, 0.9, 6.6)).is_empty()
			and _supplied_hardware_hits(body.global_position).is_empty(),
			"The real capsule query sees pod and workshop solids while the front aisle stays clear"):
		return
	var start: Vector3 = body.global_position
	if not _expect(bridge.set_control("P", Vector2(0, 1), false).accepted,
			"The trusted motor can approach the pod"):
		return
	var trace := []
	for frame in 90:
		await physics_frame
		await process_frame
		if frame % 15 == 0:
			trace.append({"frame": frame, "position": body.global_position})
	bridge.release_control("P")
	facts["supplied_wall_trace"] = trace
	if not _expect(body.global_position.z > start.z + 0.3 and body.global_position.z < 5.50
			and body.is_on_floor() and opening.model.projection().actors.P.ready,
			"The real native motor reaches the pod wall and cannot walk through it"):
		return
	var stopped: Vector3 = body.global_position
	if not _expect(bridge.set_control("P", Vector2(1, 0), false).accepted,
			"The same motor can choose the clear east aisle"):
		return
	for frame in 32:
		await physics_frame
		await process_frame
	bridge.release_control("P")
	if not _expect(body.global_position.x > stopped.x + 1.2 and body.is_on_floor(),
			"The supplied hardware does not close the clear front and east access"):
		return
	if not await _approach_points([Vector2(4.95, 4.95), Vector2(4.95, 9.9),
			Vector2(3.3, 9.9), Vector2(1.65, 11.55), Vector2(4.95, 9.9),
			Vector2(4.95, 3.3), Vector2(0.0, 1.65), Vector2(3.3, 4.95)]):
		return
	if not _expect(_issue({"action": "stow_fabrication_hub", "entity": "pod-fabrication-hub"}).accepted,
			"The physically nearby actor can stow the same issued workshop"):
		return
	bridge.sync_topology()
	for frame in 4:
		await physics_frame
		await process_frame
	if not _expect(bridge.component_bodies.size() == 10 and bridge._geometry_registered()
			and _supplied_hardware_hits(Vector3(3.3, 0.9, 6.6)).is_empty(),
			"Stowing removes its real collision bodies and clears the former worksite"):
		return
	if not _expect(_issue({"action": "deploy_fabrication_hub", "entity": "pod-fabrication-hub",
			"center": [0, 0, 16]}).accepted, "The issued workshop redeploys at an independent common-grid anchor"):
		return
	bridge.sync_topology()
	for frame in 4:
		await physics_frame
		await process_frame
	if not _expect(bridge.component_bodies.size() == 20 and bridge._geometry_registered()
			and not _supplied_hardware_hits(Vector3(0, 0.9, 6.6)).is_empty()
			and _supplied_hardware_hits(Vector3(3.3, 0.9, 6.6)).is_empty(),
			"The native collision follows the relocated workshop, without a ghost at its old site"):
		return
	for id in identities:
		if id.begins_with("landing-pod/") and not _expect(
				bridge.component_bodies[id].get_instance_id() == identities[id], "Workshop changes retain the fixed pod bodies"):
			return
	var shape: BoxShape3D = bridge.component_bodies["landing-pod/lower-hull"].get_child(0).shape
	var original_size := shape.size
	shape.size *= 1.1
	var rejected: bool = not bridge._geometry_registered()
	shape.size = original_size
	if not _expect(rejected and bridge._geometry_registered(), "Native registration detects a changed supplied collider"):
		return
	var preflight: Dictionary = bridge.checkpoint_status()
	if not _expect(preflight.accepted and opening.model.validate_checkpoint(opening.model.checkpoint()).accepted
			and _same(material, opening.model.checkpoint().world.state.material),
			"The settled clear actor and relocated workshop validate without changing material"):
		return
	facts["supplied_hardware"] = {"initial_count": 20, "stowed_count": 10, "final_count": 20,
		"wall_trace": trace, "stopped": stopped, "final_actor": body.global_position,
		"preflight": preflight, "material_unchanged": true, "desktop_operations": 0,
		"evidence": "Actual native scene, capsule queries and trusted motor controls; no actor pose, harvesting or production replay."}
	print("SUPPLIED_HARDWARE_PHYSICS " + JSON.stringify(facts.supplied_hardware))
	_record("pass")

func _arrival_press_site_run(panel, finish: bool = true) -> void:
	# Compose the ordinary collector route and the frame-free press in one
	# finite scene. The separate powered discharge remains a later consumer.
	await _arrival_belt_run(panel, "", false)
	if written:
		return
	if not _expect(opening.model.projection().line_belt_raw == 1,
			"The actor-built collector and powered belt deliver one finite blank"):
		return
	facts["collector_route"] = opening.model.projection()
	for source in [
		{"point": Vector2(4.95, 4.95), "cuts": 0},
		{"point": Vector2(4.95, 9.9), "cuts": 0},
		{"point": Vector2(6.0, 11.55), "id": "tree-east-north", "cuts": 2},
		{"point": Vector2(0.6, 11.55), "id": "tree-north", "cuts": 8},
		{"point": Vector2(4.95, 9.9), "cuts": 0},
		{"point": Vector2(4.95, 4.95), "cuts": 0},
	]:
		if not await _approach(source.point):
			return
		for cut in range(source.cuts):
			if _construct({"action": "harvest_source", "target": source.id}).is_empty():
				return
	if not _expect(opening.model.projection().cargo.P.timber == 10
			and opening.model.projection().cargo.P.raw == 8,
			"The remaining finite trees and ore supply the guided press and output route"):
		return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	for kind in ["anvil", "ram_face", "sliding_guide", "wooden_shaft", "softmetal_cog", "receiver_tray"]:
		var selected := -1
		for choice in range(panel.COMPONENTS.size()):
			if panel.COMPONENTS[choice][0] == kind:
				selected = choice
		if not _expect(selected >= 0, "The ordinary workshop lists the finite guided press component"):
			return
		panel.component_choice.select(selected)
		panel._component_selected(selected)
		var before: Dictionary = opening.model.projection()
		panel.craft_button.pressed.emit()
		var after: Dictionary = opening.model.projection()
		if not _expect(after.order == before.order + 1
				and int(after.cargo.P.components.get(kind, 0)) == int(before.cargo.P.components.get(kind, 0)) + 1,
				"The ordinary workshop crafts one finite guided press component"):
			return
	if not _expect(opening.model.projection().cargo.P.timber == 6
			and opening.model.projection().cargo.P.raw == 2,
			"The metal cog preserves the exact timber bill for an output route"):
		return
	if not await _approach_points([Vector2(4.95, 4.95), Vector2(4.95, 3.3),
			Vector2(4.95, 0.0), Vector2(1.65, 0.0), Vector2(1.65, -0.55),
			Vector2(1.1, -1.2)]):
		return
	if _construct({"action": "place_foundation", "cell": [0, -2], "level": 4}).is_empty():
		return
	for part in [
		{"kind": "anvil", "center": [0, 4, -8]},
		{"kind": "ram_face", "center": [0, 5, -8]},
		{"kind": "sliding_guide", "center": [0, 7, -8]},
		{"kind": "wooden_shaft", "center": [0, 8, -7]},
		{"kind": "softmetal_cog", "center": [0, 8, -6]},
		{"kind": "receiver_tray", "center": [1, 4, -8]},
	]:
		if _construct({"action": "place_component", "component": part.kind,
				"center": part.center}).is_empty():
			return
	var press: Dictionary = opening.model.projection()
	if not _expect(press.guided_press_assemblies.size() == 1
			and press.guided_press_assemblies[0].status == "ready"
			and press.guided_press_assemblies[0].offcut_receiver == [1, 4, -8],
			"The actor fits one elevated guided press and a side tray beside the real belt"):
		return
	facts["press_stage"] = press
	var saved: Dictionary = opening._save_worksite()
	facts["press_save"] = saved
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store accepts the same finite collector, elevated guided press and physical side tray"):
		return
	if finish:
		_record("pass")

func _arrival_belt_fed_press_run(panel) -> void:
	# The collector and belt replace hand carrying the blank. The guided press
	# still needs hand turns until its own separate drive is connected.
	facts["route"] = "collector_belt_hand_press"
	await _arrival_press_site_run(panel, false)
	if written:
		return
	var first_work := false
	for tick in range(32):
		var advanced: Dictionary = opening.model.advance()
		opening._refresh()
		if advanced.dropped_material.any(func(drop: Variant) -> bool:
			return drop is Dictionary and drop.get("center") == [0, 4, -8] and (drop.get("raw", 0) == 1 or not drop.get("work_lots", []).is_empty())):
			first_work = true
			facts["belt_feed"] = advanced
			break
	if not _expect(first_work,
			"The player-built belt feeds its original finite blank into the guided press"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts["partial_save"] = saved
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false)
			and opening.model.validate_checkpoint(opening.model.checkpoint()).get("accepted", false),
			"The physical belt-fed press work saves before forming"):
		return
	await _finish_belt_fed_press_run(panel)

func _arrival_belt_fed_press_resume_run(panel) -> void:
	facts["route"] = "collector_belt_hand_press_resume"
	var restored: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and restored.guided_press_assemblies.size() == 1
			and restored.guided_press_assemblies[0].status == "ready"
			and restored.dropped_material.any(func(drop: Variant) -> bool:
				return drop is Dictionary and drop.get("center") == [0, 4, -8] and drop.get("raw", 0) == 1)
			and restored.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
			and restored.hand_crank.holder == "P"
			and restored.actors.P.ready and restored.actors.Q.ready
			and opening.actor_world.bodies.P.is_on_floor()
			and opening.actor_world.bodies.Q.is_on_floor(),
			"A fresh scene restores the exact belt-fed press work and both physical actors"):
		return
	facts["restored_partial"] = restored
	await _finish_belt_fed_press_run(panel)

func _finish_belt_fed_press_run(panel) -> void:
	var press: Dictionary = opening.model.projection().guided_press_assemblies[0]
	var anvil: String = str(press.anvil)
	var shaft: String = str(press.parts.shaft)
	if not _expect(opening.model.projection().motion[shaft].state == "unpowered"
			and not opening.model.projection().dropped_material.any(func(drop: Variant) -> bool:
				return drop is Dictionary and drop.get("products", 0) > 0),
			"The finite belt supplies the press while its separate drive remains unpowered"):
		return
	opening._open_object_menu_for(anvil)
	if not _expect(opening.object_menu.visible and panel.press_section.visible
			and not panel.turn_button.disabled,
			"The ordinary inspection menu exposes the crank for belt-fed work"):
		return
	for turn in range(3):
		panel.turn_button.pressed.emit()
	var formed: Dictionary = opening.model.projection()
	if not _expect(formed.dropped_material.any(func(drop: Variant) -> bool:
			return drop is Dictionary and drop.get("products", 0) == 1)
			and formed.dropped_material.any(func(drop: Variant) -> bool:
				return drop is Dictionary and drop.get("offcuts", 0) == 1 and drop.get("center") == [0, 4, -8])
			and formed.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The belt-fed blank forms one plate and retains its separate offcut through three ordinary turns"):
		return
	if not _expect(not panel.recover_work_button.disabled,
			"The ordinary press exposes recovery for the retained copper offcut"):
		return
	panel.recover_work_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.offcuts == 1,
			"Offcut recovery clears the actual workface without inventing stock"):
		return
	if not _expect(not panel.pickup_button.disabled,
			"The first belt-fed plate is available for an ordinary physical pickup"):
		return
	panel.pickup_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.products == 1,
			"The actor carries the belt-fed plate from its exact output point"):
		return
	facts["first_plate"] = opening.model.projection()
	_record("pass")

## Fresh arrival panel consumer with actor motor, finite sources and Store.
func _arrival_raised_press_resume_run(panel) -> void:
	var restored: Dictionary = opening.model.projection()
	var raised_floor: bool = restored.foundations.values().any(func(floor: Variant) -> bool:
		return floor.cell == [3, 4] and floor.level == OpeningGeometry.HEIGHT_DENOMINATOR)
	if not _expect(opening.last_load_result.get("accepted", false) and raised_floor
			and restored.guided_press_assemblies.size() == 1
			and restored.guided_press_assemblies[0].status == "ready"
			and restored.guided_press_assemblies[0].center == [12, 4, 16]
			and restored.dropped_material.size() == 2
			and restored.dropped_material.any(func(drop: Variant) -> bool:
				return drop.products == 1 and restored.guided_press_assemblies[0].open_feeds.any(
					func(feed: Variant) -> bool: return drop.center == feed.exit))
			and restored.dropped_material.any(func(drop: Variant) -> bool:
				return drop.offcuts == 1 and drop.center == [12, 4, 16])
			and restored.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
			and opening.actor_world.bodies.P.is_on_floor(),
			"A fresh process restores raised geometry, separate outputs and the physical worker"):
		return
	opening._open_object_menu_for(str(restored.guided_press_assemblies[0].anvil))
	if not _expect(opening.object_menu.visible and panel.press_section.visible
			and not panel.recover_work_button.disabled,
			"The restored anvil exposes ordinary held-work recovery in its E menu"):
		return
	panel.recover_work_button.pressed.emit()
	var recovered: Dictionary = opening.model.projection()
	if not _expect(recovered.cargo.P.offcuts == 1
			and recovered.dropped_material.size() == 1
			and recovered.dropped_material[0].products == 1
			and recovered.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The resumed worker recovers only the exact raised-press offcut"):
		return
	var saved: Dictionary = opening._save_worksite()
	if not _expect(saved.get("accepted", false)
			and saved.get("native_preflight", {}).get("accepted", false)
			and FileAccess.file_exists(opening.save_slot),
			"Fresh-process Store preserves the post-recovery raised worksite"):
		return
	_record("pass")

func _arrival_run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if mode == "arrival-repeat-delivery":
		deadline = Time.get_ticks_msec() + 240000
	elif mode in ["arrival-belt", "arrival-belt-controls", "arrival-press-site", "arrival-belt-fed-press", "arrival-belt-fed-press-resume", "arrival-broad-pad", "arrival-broad-drive", "arrival-delivery", "arrival-craft-capacity"]:
		deadline = Time.get_ticks_msec() + 180000
	var capture_prefix := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arrival-capture-prefix="):
			capture_prefix = argument.trim_prefix("--arrival-capture-prefix=")
	if destination.is_empty() or mode not in ["supplied-hardware", "arrival-press", "arrival-press-site", "arrival-belt-fed-press", "arrival-belt-fed-press-resume", "arrival-broad-pad", "arrival-broad-drive", "arrival-raised-press", "arrival-raised-press-resume", "arrival-resume", "arrival-delivery", "arrival-delivery-resume", "arrival-repeat-delivery", "arrival-repeat-delivery-resume", "arrival-repeat-delivery-q-resume", "arrival-craft-capacity", "arrival-craft-capacity-resume", "arrival-field-craft", "arrival-foundation-craft", "arrival-foundation-craft-resume", "arrival-portable-workbench", "arrival-pod-workshop", "arrival-pod-workshop-resume", "arrival-belt", "arrival-belt-controls", "arrival-belt-resume", "arrival-reveal", "arrival-reveal-skip"] or FileAccess.file_exists(destination):
		push_error("Arrival press check requires an unused output and a declared mode")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	if mode in ["arrival-press-site", "arrival-belt-fed-press", "arrival-belt-fed-press-resume", "arrival-broad-pad", "arrival-broad-drive", "arrival-delivery", "arrival-delivery-resume", "arrival-repeat-delivery", "arrival-repeat-delivery-resume", "arrival-repeat-delivery-q-resume"]:
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
	if not _expect(opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor()
			and (mode != "arrival-reveal-skip" or (opening.model.projection().stock.source == 4096
				and opening.model.projection().source_deposit.initial_units == 4096)),
			"The physical actor reaches the scene floor"):
		return
	if mode == "supplied-hardware":
		await _supplied_hardware_run()
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
	if mode == "arrival-broad-pad":
		await _arrival_broad_pad_run(panel)
		return
	if mode == "arrival-broad-drive":
		await _arrival_broad_drive_run(panel)
		return
	if mode == "arrival-press-site":
		await _arrival_press_site_run(panel)
		return
	if mode == "arrival-belt-fed-press":
		await _arrival_belt_fed_press_run(panel)
		return
	if mode == "arrival-belt-fed-press-resume":
		await _arrival_belt_fed_press_resume_run(panel)
		return
	if mode == "arrival-raised-press-resume":
		await _arrival_raised_press_resume_run(panel)
		return
	if mode == "arrival-foundation-craft-resume":
		await _arrival_foundation_craft_resume_run(panel)
		return
	if mode == "arrival-craft-capacity-resume":
		await _arrival_capacity_resume_run()
		return
	if mode == "arrival-repeat-delivery-q-resume":
		while Time.get_ticks_msec() < deadline and not opening.model.projection().actors.Q.ready:
			await physics_frame
			await process_frame
		var q_saved: Dictionary = opening.model.projection()
		if not _expect(opening.last_load_result.get("accepted", false)
				and q_saved.actors.Q.ready and opening.actor_world.bodies.Q.is_on_floor()
				and q_saved.cargo.Q.raw == 1 and q_saved.cargo.P.raw == 0
				and q_saved.cargo.P.offcuts == 0 and q_saved.dropped_material.is_empty()
				and q_saved.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
				and q_saved.freight_beacon.repeat_order_complete
				and q_saved.hand_crank.holder == "pod" and opening.landing_crank_visual.visible
				and opening.model.validate_checkpoint(opening.model.checkpoint()).get("accepted", false),
				"A third process restores Q's physically recovered blank and P's next command without mass drift"):
			return
		_record("pass")
		return
	if mode == "arrival-repeat-delivery":
		if not _expect(not opening.manager_log_completion_entry.visible
				and opening.get_node_or_null("ShipmentMarker") == null,
			"The ordinary opening waits for local inventory and has no shipment marker"):
			return
		if not capture_prefix.is_empty():
			opening.manager_log_button.pressed.emit()
			await process_frame
			if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-first-log.png") == OK,
				"The first-order Work log is retained in the normal viewport"):
				return
			opening._toggle_manager_log()
	if mode == "arrival-field-craft":
		await _arrival_field_craft_run(panel, capture_prefix)
		return
	if mode == "arrival-foundation-craft":
		await _arrival_foundation_craft_run(panel, capture_prefix)
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
		await _arrival_capacity_run(panel, capture_prefix)
		return
	if not capture_prefix.is_empty() and mode in ["arrival-press", "arrival-delivery", "arrival-repeat-delivery"]:
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
	if mode in ["arrival-resume", "arrival-delivery-resume", "arrival-repeat-delivery-resume"]:
		var restored: Dictionary = opening.model.projection()
		var repeat_complete: bool = mode == "arrival-repeat-delivery-resume"
		var first_delivered: bool = mode in ["arrival-delivery-resume", "arrival-repeat-delivery-resume"]
		if not _expect(opening.last_load_result.get("accepted", false)
				and opening.arrival_reveal_audio == null
				and restored.cargo.P.products == (0 if repeat_complete else 1 if first_delivered else 2)
				and restored.cargo.P.offcuts == (0 if repeat_complete else 2)
				and (restored.dropped_material.size() == 1 and restored.dropped_material[0].raw == 1
					if repeat_complete else true)
				and restored.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
				and restored.freight_beacon.order_complete == first_delivered
				and restored.freight_beacon.shipped_products == (4 if repeat_complete else 1 if first_delivered else 0)
				and restored.freight_beacon.repeat_order_shipped == (3 if repeat_complete else 0)
				and restored.freight_beacon.repeat_order_complete == repeat_complete
				and restored.placed_components.size() == 5
				and restored.cargo.P.components.get("wooden_frame", 0) == 1
				and restored.cargo.P.components.get("receiver_tray", 0) == 1
				and restored.cargo.P.components.get("cutting_edge", 0) == 1
				and restored.cargo.P.components.get("tool_mount", 0) == 1
				and restored.cargo.P.components.get("wooden_shaft", 0) == 1
				and restored.guided_press_assemblies.size() == 1 and restored.guided_press_assemblies[0].status == "ready"
				and restored.hand_crank.holder == "P" and panel.visible
				and opening.landing_pod_visual != null and not opening.landing_crank_visual.visible
				and not opening.arrival_reveal_active,
				"A fresh process reopens the press, finite cargo and one held crank"):
			return
		if first_delivered and not _expect(restored.actors.has("Q")
				and opening.actor_world.bodies.has("Q")
				and opening.manager_log_completion_entry.visible == (restored.cargo.P.products > 0)
				and opening.get_node_or_null("ShipmentMarker") == null,
			"The saved inventory goal reflects only P's actual carried plate"):
			return
		opening.manager_log_button.pressed.emit()
		if not _expect(opening.manager_log_open and opening.manager_log_layer.visible
				and not opening.manager_log_current.text.is_empty()
				and opening.model.projection() == restored,
				"The saved site reopens with the same replayable briefing and a current native-backed cue"):
			return
		if repeat_complete and not capture_prefix.is_empty():
			await process_frame
			if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-resume-log.png") == OK,
				"The Store-restored Work log is retained in the normal viewport"):
				return
		var before_log_close: Dictionary = opening.model.projection()
		opening._toggle_manager_log()
		if not _expect(not opening.manager_log_open and opening._can_control_character()
				and opening.model.projection() == before_log_close,
				"A resumed worker can return from the log without replaying arrival or changing stock"):
			return
		if repeat_complete:
			if not await _approach_points([Vector2(1.65, 3.3), Vector2(4.95, 3.3),
					Vector2(4.95, 4.95)], "Q"):
				return
			var before_q: Dictionary = opening.model.projection()
			var recycled_drop: Dictionary = before_q.dropped_material[0]
			var expected_drop: Dictionary = recycled_drop.duplicate(true)
			expected_drop.erase("center")
			var q_reply: Dictionary = opening.model.command_as("Q", {"action": "pickup_material",
				"context": before_q.context, "client": "Q", "request": "saved-recycled-blank-q",
				"center": recycled_drop.center, "expected": expected_drop})
			opening.actor_world.sync_topology()
			opening._refresh_from_projection(opening.model.projection())
			var after_q: Dictionary = opening.model.projection()
			if not _expect(q_reply.get("accepted", false) and after_q.cargo.Q.raw == 1
					and after_q.cargo.P == before_q.cargo.P and after_q.dropped_material.is_empty()
					and after_q.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
					"Physical Q recovers the Store-restored blank without changing P's cargo or copper mass"):
				return
			if not await _approach_points([Vector2(6.6, 8.25), Vector2(6.6, 4.95),
					Vector2(1.65, 4.95)]):
				return
		panel.crank_button.pressed.emit()
		if not _expect(opening.model.projection().hand_crank.holder == "pod"
				and opening.landing_crank_visual.visible,
				"The resumed ordinary panel can make a new native command"):
			return
		if repeat_complete:
			var saved_after_q: Dictionary = opening._save_worksite()
			if not _expect(saved_after_q.get("accepted", false)
					and saved_after_q.get("native_preflight", {}).get("accepted", false)
					and FileAccess.file_exists(opening.save_slot),
					"Store validates and saves the second actor's physical recovery and P's next command"):
				return
		_record("pass")
		return
	if not _expect(panel != null and not opening._object_menu_open(),
			"The workshop waits for its centered E interaction at landfall"):
		return
	var raised: bool = mode == "arrival-raised-press"
	opening._open_object_menu_for(str(pod_state.fabrication_hub.id))
	if not _expect(opening._object_menu_open() and panel.is_visible_in_tree()
			and not panel.craft_button.disabled and "3 timber" in panel.recipe_label.text,
			"Opening the pod workshop exposes the current carried recipe and craft action"):
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
	opening.object_menu.hide()
	await process_frame
	if not await _approach(Vector2(6.0, 3.45)):
		return
	for index in range(8):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 4.95), Vector2(4.95, 9.9), Vector2(6.0, 11.55)]):
		return
	for index in range(7):
		if _construct({"action": "harvest_source", "target": "tree-east-north"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 9.9), Vector2(4.95, 3.3),
			Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
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
	if not await _approach(Vector2(3.3, 4.95)):
		return
	var initial: Dictionary = opening.model.projection()
	if not _expect(initial.cargo.P.timber == 15 and initial.cargo.P.raw == 7
			and initial.placed_components.is_empty() and initial.component_recipes.size() == 12,
			"Two finite trees and the ore deposit supply both chapter bills without gifted machines"):
		return
	var part_list := ["anvil", "ram_face", "sliding_guide", "wooden_shaft", "wooden_cog"]
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
		var bill_text := "%d timber" % bill.timber
		if int(bill.softmetal) > 0:
			bill_text += " + %d softmetal" % bill.softmetal
		if not _expect(not panel.craft_button.disabled
				and ("Need " + bill_text) in panel.recipe_label.text,
				"The ordinary picker shows the selected native hub recipe"):
			return
		var before: int = opening.model.projection().order
		var owned_before: int = opening.model.projection().cargo.P.components.get(kind, 0)
		panel.craft_button.pressed.emit()
		if not _expect(opening.model.projection().order == before + 1
				and opening.model.projection().cargo.P.components.get(kind, 0) == owned_before + 1,
				"The panel crafts one native component with exact finite cargo"):
			return
	if not _expect(opening.model.projection().cargo.P.timber == 4
			and opening.model.projection().cargo.P.raw == 2
			and opening.model.projection().cargo.P.components.values().reduce(func(total, amount): return total + amount, 0) == 10,
			"The frame-free press and collector bills use eleven timber and five ore blanks, retaining two press inputs"):
		return
	if raised:
		var before_floor: Dictionary = opening.model.projection()
		panel.foundation_craft_button.pressed.emit()
		var floor_kit: Dictionary = opening.model.projection()
		if not _expect(floor_kit.order == before_floor.order + 1
				and floor_kit.cargo.P.timber == 2
				and floor_kit.part_kits.P.foundation == before_floor.part_kits.P.foundation + 1,
				"Two remaining local timber make one raised press floor through the ordinary workshop"):
			return
		opening._select_tool("foundation")
		opening._world_click(Vector2i(3, 4))
		var floored: Dictionary = opening.model.projection()
		if not _expect(floored.order == floor_kit.order + 1
				and floored.part_kits.P.foundation == before_floor.part_kits.P.foundation
				and floored.foundations.values().any(func(floor: Variant) -> bool:
					return floor.cell == [3, 4] and floor.level == OpeningGeometry.HEIGHT_DENOMINATOR),
				"The ordinary foundation tool installs a shared-grid floor under the press"):
			return
		if not await _approach(Vector2(4.95, 4.95)):
			return
	opening._select_tool("component")
	var expected_status := ["missing_ram", "missing_guide", "missing_shaft",
		"missing_cog", "ready"]
	var press_parts: Dictionary = {}
	var original_camera_distance: float = opening.distance
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
		var requested_center := [3 * OpeningGeometry.HEIGHT_DENOMINATOR + maxi(index - 2, 0),
			[0, 1, 3, 4, 4][index] + (OpeningGeometry.HEIGHT_DENOMINATOR if raised else 0),
			4 * OpeningGeometry.HEIGHT_DENOMINATOR]
		var before: int = opening.model.projection().order
		var before_parts: Dictionary = opening.model.projection().placed_components
		if mode == "arrival-press":
			if index == 3 and not await _approach(Vector2(6.6, 6.6)):
				return
			await physics_frame
			await process_frame
			opening.distance = 0.0
			opening._update_camera()
			var target := Vector3(4.95, 0.0, 6.6)
			var expected_face := Vector3.UP
			var target_id := ""
			if index > 0:
				target_id = str(press_parts["ram_face" if index == 2 else "anvil"])
				var occupied: Dictionary = opening.model.projection().placed_components[target_id].occupied
				var center: Array = occupied.center
				var half: Array = occupied.half
				target = Vector3(float(center[0]), float(center[1]), float(center[2]))
				if index < 3:
					target.y += float(half[1])
				else:
					target.x += float(half[0])
					expected_face = Vector3.RIGHT
			var direction: Vector3 = (target - opening.camera.global_position).normalized()
			opening.orbit_yaw = atan2(-direction.x, -direction.z)
			opening.orbit_pitch = asin(clampf(-direction.y, -1.0, 1.0))
			opening._update_camera()
			var screen: Vector2 = opening._pointed_screen_position()
			var hit: Dictionary = opening._screen_pick(screen)
			var pointed: String = opening._screen_entity(screen)
			var tile: Vector2i = opening._screen_cell(screen)
			if not _expect(not opening.component_nudge_active
					and (not target_id.is_empty() or tile == Vector2i(3, 4))
					and (target_id.is_empty() or (pointed == target_id
					and not hit.is_empty() and hit.normal.dot(expected_face) > 0.8)),
					"The physical actor can point at the fitted %s face for %s: %s" % [
						target_id if not target_id.is_empty() else "floor", kind,
						str({"camera": opening.camera.global_position, "target": target,
							"pointed": pointed, "normal": hit.get("normal"), "tile": tile})]):
				return
			opening._refresh_component_preview()
			var ghost_center: Array = opening._component_place_center(tile, pointed)
			if not _expect(ghost_center == requested_center and opening.component_preview.visible
					and not opening.component_preview_blocked
					and opening.component_preview.position.distance_to(
						opening._component_candidate_box(kind, ghost_center).center) < 0.001,
					"The native-ready %s ghost shows the same reachable press socket the click will send" % kind):
				return
			if index == 2 and not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-guide-snap.png") == OK,
						"Retain the anvil-targeted raised guide ghost in the ordinary scene"):
					return
				pointed = opening._screen_entity(screen)
				tile = opening._screen_cell(screen)
				if not _expect(pointed == target_id and opening._component_place_center(tile, pointed) == ghost_center,
						"The persistent actor-eye aim keeps the guide click on the visible ghost after its rendered frame"):
					return
			opening._world_click(tile, pointed)
		else:
			opening.component_nudge_active = true
			opening.component_nudge_center = requested_center.duplicate()
			opening._world_click(Vector2i(3, 4))
			opening.component_nudge_active = false
			opening.component_nudge_center.clear()
		var projection: Dictionary = opening.model.projection()
		if not _expect(projection.order == before + 1 and projection.placed_components.size() == index + 1
				and projection.placed_components.values().any(func(part: Variant) -> bool:
					return part.component == kind and part.center == requested_center),
				"The ordinary click submits the %s point at %s: %s" % [kind,
					str(requested_center), opening.status_label.text]):
			return
		for id: String in projection.placed_components:
			if not before_parts.has(id):
				press_parts[kind] = id
		if not _expect(projection.guided_press_assemblies.size() == 1
				and projection.guided_press_assemblies[0].status == expected_status[index],
				"The native recognizer reports the current fitted press stage"):
			return
	if mode == "arrival-press":
		if not await _approach_points([Vector2(6.6, 3.3), Vector2(4.95, 3.3)]):
			return
	var ready: Dictionary = opening.model.projection().guided_press_assemblies[0]
	if mode == "arrival-press" and not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		opening._select_tool("inspect")
		opening.distance = 0.0
		opening._update_camera()
		var press_target := Vector3(4.95, 1.35, 6.6)
		var press_direction: Vector3 = (press_target - opening.camera.global_position).normalized()
		opening.orbit_yaw = atan2(-press_direction.x, -press_direction.z)
		opening.orbit_pitch = asin(clampf(-press_direction.y, -1.0, 1.0))
		opening._update_camera()
		await RenderingServer.frame_post_draw
		var ordinary_captured: bool = root.get_texture().get_image().save_png(capture_prefix + "-ready-press.png") == OK
		opening.distance = 1.5
		opening.orbit_yaw += 0.25
		opening._update_camera()
		await RenderingServer.frame_post_draw
		var third_person_captured: bool = root.get_texture().get_image().save_png(capture_prefix + "-ready-third-person.png") == OK
		if not _expect(ordinary_captured and third_person_captured,
				"Retain the fitted press in first-person and third-person actor views"):
			return
	if mode == "arrival-press":
		opening.distance = original_camera_distance
		opening._update_camera()
		if not await _approach(Vector2(4.95, 4.95)):
			return
	if raised and not _expect(ready.center == [12, 4, 16] and ready.work_center == [12, 4, 16],
			"The raised native press keeps the anvil workface on the same foundation height grid"):
		return
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
	var ready_die_y: float = _guided_die_y(str(ready.parts.ram)) if raised else NAN
	if mode == "arrival-press":
		opening._open_object_menu_for(str(ready.anvil))
		if not _expect(opening.object_menu.visible and panel.turn_button.is_visible_in_tree()
				and not panel.turn_button.disabled,
				"The physical worker can hold the crank in the ordinary press E menu"):
			return
		var before_hold_order: int = opening.model.projection().order
		panel.turn_button.button_down.emit()
		panel.turn_button.pressed.emit()
		var first_turn: Dictionary = opening.model.projection()
		if not _expect(first_turn.order == before_hold_order + 1
				and not first_turn.dropped_material.any(func(drop: Variant) -> bool: return drop.products == 1)
				and first_turn.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
				"The first held input advances one authoritative turn and retains partial copper work"):
			return
		if not _expect("0 / 2 steps" in panel.press_status.text,
				"The press panel shows projected held-turn progress: %s" % panel.press_status.text):
			return
		var progress_deadline: int = Time.get_ticks_msec() + 1500
		while Time.get_ticks_msec() < progress_deadline and opening.model.projection().order < before_hold_order + 2:
			await process_frame
		if not _expect(opening.model.projection().order == before_hold_order + 2
				and "1 / 2 steps" in panel.press_status.text,
				"The held action exposes the next native stroke step before completion: %s" % panel.press_status.text):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-held-work.png") == OK,
					"The in-progress held crank and retained work are visible in passive scene pixels"):
				return
		var hold_deadline: int = Time.get_ticks_msec() + 2500
		while Time.get_ticks_msec() < hold_deadline and not opening.model.projection().dropped_material.any(
				func(drop: Variant) -> bool: return drop.products == 1):
			await process_frame
		panel.turn_button.button_up.emit()
		var after_hold_order: int = opening.model.projection().order
		await create_timer(0.40).timeout
		if not _expect(after_hold_order == before_hold_order + 3
				and opening.model.projection().order == after_hold_order
				and panel.turn_hold_source.is_empty(),
				"One held pointer gesture advances exactly three native turns and stops on release"):
			return
	else:
		for turn in range(3):
			if not _expect(not panel.turn_button.disabled, "A retained workpiece enables the selected drive"):
				return
			var before_cues: int = opening.construction_audio.heard.size()
			panel.turn_button.pressed.emit()
			if not _expect(opening.construction_audio.heard.size() == before_cues + 1
					and opening.construction_audio.stream == OpeningScene.ConstructionAudio.make_stream("assembly"),
					"Only the confirmed hand turn emits one restrained work impact"):
				return
			if raised:
				var die_y: float = _guided_die_y(str(ready.parts.ram))
				if not _expect(is_finite(ready_die_y) and is_finite(die_y)
						and (die_y < ready_die_y - 0.01 if turn == 1 else absf(die_y - ready_die_y) < 0.001),
						"The raised die follows confirmed hand-turn work and returns after forming: %s" %
						str({"turn": turn, "rest": ready_die_y, "current": die_y,
							"work": opening.model.projection().dropped_material})):
					return
				if turn == 0 and not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
					for frame in range(3):
						await process_frame
						await RenderingServer.frame_post_draw
					if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-raised-held.png") == OK,
							"The retained billet is captured at the actor-built raised press"):
						return
				if turn == 1 and not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
					if not _expect(await _capture_guided_close(str(ready.parts.ram),
							capture_prefix + "-forming-close.png"),
							"The native in-stroke guided press is retained in a close passive frame"):
						return
	var after: Dictionary = opening.model.projection()
	if not _expect(after.dropped_material.size() == 2
			and after.dropped_material.any(func(drop: Variant) -> bool:
				return drop.products == 1 and (not raised or ready.open_feeds.any(
					func(feed: Variant) -> bool: return drop.center == feed.exit)))
			and after.dropped_material.any(func(drop: Variant) -> bool:
				return drop.offcuts == 1 and (not raised or drop.center == ready.work_center))
			and after.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"Repeated hand turns form one plate and retain one copper offcut at the work point"):
		return
	if raised:
		facts["raised_press"] = {"assembly": ready, "drops": after.dropped_material,
			"foundation": after.foundations}
		var raised_save: Dictionary = opening._save_worksite()
		if not _expect(raised_save.get("accepted", false)
				and raised_save.get("native_preflight", {}).get("accepted", false)
				and FileAccess.file_exists(opening.save_slot),
				"Store retains the raised press, formed plate, offcut and physical worker"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-raised-press.png") == OK,
					"The formed raised press is retained as passive pixels"):
				return
		_record("pass")
		return
	if not capture_prefix.is_empty():
		await process_frame
		var copper_output: Image = root.get_texture().get_image()
		if not _expect(copper_output != null and copper_output.save_png(capture_prefix + "-plate-offcut.png") == OK,
				"The separate formed plate and copper offcut are retained as passive pixels"):
			return
	if not _expect(not panel.pickup_button.disabled, "The formed plate is offered for physical pickup"):
		return
	if not _expect(not panel.recover_work_button.disabled
			and panel.recover_work_button.tooltip_text.contains("offcut")
			and panel.feed_button.disabled,
			"The next feed waits for the visible copper offcut to be recovered"):
		return
	panel.recover_work_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.offcuts == 1
			and opening.model.projection().dropped_material.size() == 1,
			"Ordinary press recovery moves only the copper offcut into actor custody"):
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
			and panel.press_status.text.contains("Exit holds a plate")
			and not opening.manager_log_completion_entry.visible,
		"A plate at the exit has not yet completed the inventory objective"):
		return
	if not _expect(not panel.pickup_button.disabled and not panel.recover_work_button.disabled,
			"The player can choose either exit pickup or retained work recovery"):
		return
	panel.pickup_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.products == 1
			and opening.model.projection().dropped_material.size() == 1
			and "FIRST WORKSHOP  /  COMPLETE" in opening.objective_heading.text
			and opening.manager_log_completion_entry.visible,
		"Physical pickup completes the workshop while the second workpiece stays in place"):
		return
	if mode in ["arrival-delivery", "arrival-repeat-delivery"]:
		var held_work: Dictionary = opening.model.projection()
		if not await _deliver_first_arrival_plate(held_work, capture_prefix):
			return
		opening.distance = 0.0
		opening.orbit_yaw = PI
		opening.orbit_pitch = 0.18
		opening._update_camera()
		opening._open_pointed_machine()
		if not _expect(not opening.selected.is_empty() and panel.press_section.visible,
				"Returning from freight opens the press again through the ordinary E ray"):
			return
	panel.turn_button.pressed.emit()
	if not _expect(opening.model.projection().dropped_material.size() == 2
			and opening.model.projection().dropped_material.any(func(drop: Variant) -> bool: return drop.products == 1)
			and opening.model.projection().dropped_material.any(func(drop: Variant) -> bool: return drop.offcuts == 1),
			"Clearing the exit lets the retained ready work form its second product"):
		return
	panel.pickup_button.pressed.emit()
	if not _expect(not panel.recover_work_button.disabled
			and opening.model.projection().dropped_material.size() == 1,
			"The second plate pickup leaves its separate copper offcut beneath the ram"):
		return
	panel.recover_work_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.products == (1 if mode in ["arrival-delivery", "arrival-repeat-delivery"] else 2)
			and opening.model.projection().cargo.P.offcuts == 2
			and opening.model.projection().dropped_material.is_empty()
			and opening.model.projection().material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"Both plates and both copper offcuts enter finite carried custody through ordinary controls"):
		return
	if mode == "arrival-repeat-delivery" and not await _deliver_repeat_arrival_plates(panel, capture_prefix):
		return
	facts["press_anvil"] = ready.anvil
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


## Finite actor-built broad-pad ground and raised layouts.
func _arrival_broad_pad_run(panel) -> void:
	deadline = Time.get_ticks_msec() + 240000
	facts.evidence = "ordinary_finite_broad_pad_assembly"
	var base_level := 4 if "--broad-raised" in OS.get_cmdline_user_args() else 0
	facts.layout_level = base_level
	if not _expect(opening.save_slot_ready and not opening.save_slot.is_empty(),
			"The isolated ordinary scene has a fresh owned save destination"):
		return
	var start: Dictionary = opening.model.projection()
	var initial_source: int = int(start.stock.source)
	if not _expect(initial_source >= 16 and start.placed_components.is_empty(),
			"The original finite arrival has no gifted broad-press components"):
		return
	for source in [
		{"path": [Vector2(3.3, 4.95)], "id": "tree-east-south"},
		{"path": [Vector2(4.95, 4.95), Vector2(4.95, 9.9), Vector2(3.3, 9.9)],
			"id": "tree-east-north"},
	]:
		var waypoints: Array[Vector2] = []
		for point in source.path:
			waypoints.append(point)
		if not await _approach_points(waypoints):
			return
		for cut in range(8):
			if _construct({"action": "harvest_source", "target": source.id}).is_empty():
				return
	if not await _approach_points([Vector2(4.95, 9.9), Vector2(4.95, 4.95),
			Vector2(3.3, 3.3), Vector2(0.0, 1.65)]):
		return
	for cut in range(16):
		if _construct({"action": "harvest_source", "target": "opening-softmetal"}).is_empty():
			return
	var gathered: Dictionary = opening.model.projection()
	if not _expect(gathered.cargo.P.timber == 16 and gathered.cargo.P.raw == 16
			and gathered.stock.source == initial_source - 16,
			"Two trees and the one finite ore reserve supply all twenty broad-pad pieces"):
		return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(3.3, 4.95)]):
		return
	for kind in ["anvil", "ram_face", "sliding_guide", "wooden_shaft", "wooden_cog"]:
		var choice := -1
		for index in range(panel.COMPONENTS.size()):
			if panel.COMPONENTS[index][0] == kind:
				choice = index
		if not _expect(choice >= 0, "The ordinary workshop lists the placed broad-pad part"):
			return
		panel.component_choice.select(choice)
		panel._component_selected(choice)
		for copy in range(4):
			var before: Dictionary = opening.model.projection()
			panel.craft_button.pressed.emit()
			var after: Dictionary = opening.model.projection()
			if not _expect(after.order == before.order + 1
					and int(after.cargo.P.components.get(kind, 0)) ==
					int(before.cargo.P.components.get(kind, 0)) + 1,
					"The pod shapes one native component from carried finite stock"):
				return
	var crafted: Dictionary = opening.model.projection()
	if not _expect(crafted.cargo.P.timber == 0 and crafted.cargo.P.raw == 0
			and crafted.placed_components.is_empty(),
			"Twenty carried pieces cost exactly sixteen timber and sixteen ore"):
		return
	if not await _approach_points([Vector2(4.95, 4.95), Vector2(6.6, 4.95),
			Vector2(6.6, 2.5), Vector2(5.8, -1.2)]):
		return
	for index in range(4):
		if base_level > 0 and index == 2 and not await _approach(Vector2(5.8, 1.65)):
			return
		var x: int = 12 + (index % 2) * 4
		var z: int = (index / 2) * 4
		if _construct({"action": "place_component", "component": "anvil",
				"center": [x, base_level, z]}).is_empty():
			return
	var supported: Dictionary = opening.model.projection()
	if not _expect(supported.broad_press_assemblies.size() == 1
			and supported.broad_press_assemblies[0].geometry_status == "missing_ram",
			"Four placed anvils define one incomplete area, not four presses"):
		return
	for index in range(4):
		var x: int = 12 + (index % 2) * 4
		var z: int = (index / 2) * 4
		for part in [
			{"kind": "ram_face", "center": [x, base_level + 1, z]},
			{"kind": "sliding_guide", "center": [x, base_level + 3, z]},
			{"kind": "wooden_shaft", "center": [x + (-1 if index % 2 == 0 else 1), base_level + 4, z]},
			{"kind": "wooden_cog", "center": [x + (-2 if index % 2 == 0 else 2), base_level + 4, z]},
		]:
			if _construct({"action": "place_component", "component": part.kind,
					"center": part.center}).is_empty():
				return
	var built: Dictionary = opening.model.projection()
	facts.broad_assembly = built.broad_press_assemblies
	if not _expect(built.placed_components.size() == 20
			and built.broad_press_assemblies.size() == 1
			and built.broad_press_assemblies[0].origin == [12, base_level, 0]
			and built.broad_press_assemblies[0].geometry_status == "ready"
			and built.broad_press_assemblies[0].status == "unpowered"
			and built.broad_press_assemblies[0].work_centers.size() == 4,
			"The real actor places one complete broad work area, which truthfully awaits drive"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts.save = saved
	facts.save_slot = opening.save_slot
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store retains the same twenty finite, independently placed pads"):
		return
	_record("pass")


## Fresh-process waterwheel continuation of the same saved ground layout.
func _arrival_broad_drive_run(panel) -> void:
	deadline = Time.get_ticks_msec() + 240000
	facts.evidence = "ordinary_broad_pad_drive_continuation"
	if not _expect(opening.save_slot_ready and opening.last_load_result.get("accepted", false),
			"A fresh scene loads the exact actor-built four-pad checkpoint"):
		return
	var start: Dictionary = opening.model.projection()
	if not _expect(start.broad_press_assemblies.size() == 1
			and start.broad_press_assemblies[0].geometry_status == "ready"
			and start.broad_press_assemblies[0].status == "unpowered"
			and start.placed_components.size() == 20
			and start.material_mass.accounted_mass == start.material_mass.initial_mass,
			"The fresh native World retains the exact finite broad work area"):
		return
	for cut in range(6):
		if _construct({"action": "harvest_source", "target": "tree-east-upstream"}).is_empty():
			return
	if not _expect(opening.model.projection().cargo.P.timber == 6,
			"The actual upstream tree supplies one wheel and four connecting shafts"):
		return
	if not await _approach_points([Vector2(3.3, -1.2), Vector2(3.3, 3.3),
			Vector2(0.0, 1.65)]):
		return
	if _construct({"action": "harvest_source", "target": "opening-softmetal"}).is_empty():
		return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(3.3, 4.95)]):
		return
	for kind in ["wheel", "shaft", "shaft", "shaft", "shaft"]:
		var choice := -1
		var recipes: Array = opening.model.projection().part_recipes
		for index in range(recipes.size()):
			if recipes[index].kind == kind:
				choice = index
		if not _expect(choice >= 0, "The workshop exposes the exact finite drive kit"):
			return
		panel.part_choice.select(choice)
		panel.part_choice.item_selected.emit(choice)
		var before: Dictionary = opening.model.projection()
		panel.part_craft_button.pressed.emit()
		var after: Dictionary = opening.model.projection()
		if not _expect(after.order == before.order + 1
				and int(after.part_kits.P.get(kind, 0)) == int(before.part_kits.P.get(kind, 0)) + 1,
				"One real workshop craft makes one carried drive part"):
			return
	if not _expect(opening.model.projection().cargo.P.timber == 0
			and opening.model.projection().cargo.P.raw == 0,
			"The route consumes only its six new finite timber units"):
		return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(0.0, 1.3)]):
		return
	if _construct({"action": "place", "kind": "wheel", "cell": [-2, 0],
			"axis": "x", "level": 4}).is_empty():
		return
	for center in [[-4, 4, 0], [0, 4, 0], [4, 4, 0]]:
		if _construct({"action": "place_shaft", "center": center, "axis": "x",
				"half_span": 2}).is_empty():
			return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(3.3, -1.2),
			Vector2(5.8, -1.2)]):
		return
	for center in [[8, 4, 0]]:
		if _construct({"action": "place_shaft", "center": center, "axis": "x",
				"half_span": 2}).is_empty():
			return
	var connected: Dictionary = opening.model.projection()
	facts.connected_assembly = connected.broad_press_assemblies
	if not _expect(connected.broad_press_assemblies.size() == 1
			and connected.broad_press_assemblies[0].geometry_status == "ready"
			and connected.broad_press_assemblies[0].status == "ready"
			and connected.broad_press_assemblies[0].stroke_rate[0] != 0,
			"One physically connected wheel drives all four actor-built pad heads"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts.save = saved
	facts.save_slot = opening.save_slot
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"The powered four-pad route survives Store without losing copper or wood"):
		return
	_record("pass")
