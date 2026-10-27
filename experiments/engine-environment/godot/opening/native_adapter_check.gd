extends SceneTree
## Automated headless consumer of the ordinary scene, not a desktop playtest.
const NativeModel = preload("res://opening/native_model.gd")
const OpeningGeometry = preload("res://opening/site_geometry.gd")
const OpeningScene = preload("res://opening/opening.gd")
const ConstructionAudio = preload("res://opening/construction_audio.gd")
const MechanicalAmbience = preload("res://opening/mechanical_ambience.gd")
const TransmissionPresenter = preload("res://opening/native_transmission_presenter.gd")
const ARRIVAL_INITIAL_MASS := 4096 * 4
const VALUE_OPTIONS := ["--native-check-output=", "--native-check-prior=", "--native-check-mode=",
	"--arrival-capture-prefix=", "--resume-input=", "--save-slot=", "--test-purpose="]
const FLAG_OPTIONS := ["--event-route-loose", "--event-route-pointer", "--anvil-seat-only",
	"--anvil-deck-only", "--anvil-ready-only", "--arrival-reveal-probe"]
var opening
var destination := ""
var prior_result_path := ""
var event_route_loose := false
var event_route_pointer := false
var event_route_loose_activations := 0
var event_route_pointer_placements := 0
var event_route_pointer_suppressed := 0
var anvil_seat_only := false
var anvil_deck_only := false
var anvil_ready_only := false
var mode := ""
var checks := 0
var deadline := 0
var facts: Dictionary = {"steps": [], "evidence": "native_offline_scene_consumer"}
var written := false

func _init() -> void:
	var seen: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		var option := ""
		var value := ""
		for prefix: String in VALUE_OPTIONS:
			if argument.begins_with(prefix):
				option = prefix
				value = argument.trim_prefix(prefix)
				break
		if option.is_empty() and FLAG_OPTIONS.has(argument):
			option = argument
		if option.is_empty() or seen.has(option) or (VALUE_OPTIONS.has(option) and value.is_empty()):
			push_error("Unknown, duplicate or empty native adapter fixture argument: " + argument)
			quit(2)
			return
		seen[option] = true
		match option:
			"--native-check-output=": destination = value
			"--native-check-prior=": prior_result_path = value
			"--native-check-mode=": mode = value
			"--event-route-loose": event_route_loose = true
			"--event-route-pointer": event_route_pointer = true
			"--anvil-seat-only": anvil_seat_only = true
			"--anvil-deck-only": anvil_deck_only = true
			"--anvil-ready-only": anvil_ready_only = true
	if mode.is_empty() or destination.is_empty():
		push_error("Select one native adapter fixture mode and a fresh output")
		quit(2)
		return
	var resumes_worksite := mode.ends_with("-resume") or mode in ["resume",
		"arrival-broad-drive", "arrival-broad-form", "arrival-channel-broad",
		"arrival-channel-small"]
	if seen.has("--resume-input=") != resumes_worksite:
		push_error("The selected native adapter fixture mode requires exactly its declared worksite input")
		quit(2)
		return
	var anvil_options := int(anvil_seat_only) + int(anvil_deck_only) + int(anvil_ready_only)
	if anvil_options > 1 or (anvil_options > 0 and mode not in ["arrival-press", "arrival-guide-geometry", "arrival-raised-press"]):
		push_error("Select at most one anvil stage for an arrival press fixture")
		quit(2)
		return
	if (not prior_result_path.is_empty() and mode != "arrival-channel-small-resume") \
			or (seen.has("--arrival-reveal-probe") and mode != "arrival-resume"):
		push_error("The selected native adapter fixture mode does not use this companion argument")
		quit(2)
		return
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
	if status == "pass" and event_route_loose and event_route_loose_activations != (
			1 if mode == "arrival-channel-small-resume" else 3):
		status = "fail"
		reason = "The selected keyboard popup route did not execute every custody transfer"
	if status == "pass" and event_route_pointer and (event_route_pointer_placements !=
			(5 if mode == "arrival-raised-press" else 3 if mode == "arrival-raised-starter-snap" else 2)
			or event_route_pointer_suppressed != 1):
		status = "fail"
		reason = "The selected pointer route did not execute every placement and its pause-menu refusal"
	written = true
	var prefetch_wait_frames := 0
	if opening != null and not opening.preview_prefetch_complete \
			and not opening.preview_prefetch_paths.is_empty():
		var prefetch_deadline := Time.get_ticks_msec() + 5000
		while not opening.preview_prefetch_complete and Time.get_ticks_msec() < prefetch_deadline:
			await process_frame
			prefetch_wait_frames += 1
		if not opening.preview_prefetch_complete:
			push_error("Machine preview prefetch did not finish before fixture teardown")
			if status == "pass":
				status = "fail"
				reason = "Machine preview prefetch did not finish before fixture teardown"
	facts["preview_prefetch_wait_frames"] = prefetch_wait_frames
	facts.merge({"status": status, "reason": reason, "mode": mode, "checks": checks,
		"process_id": OS.get_process_id(), "physics_frames": Engine.get_physics_frames(),
		"event_route_loose_activations": event_route_loose_activations,
		"event_route_pointer_placements": event_route_pointer_placements,
		"event_route_pointer_suppressed": event_route_pointer_suppressed})
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
	for kind in MechanicalAmbience.loops:
		audio_refs.append(weakref(MechanicalAmbience.loops[kind]))
	for cue in ConstructionAudio.streams:
		audio_refs.append(weakref(ConstructionAudio.streams[cue]))
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
		if opening.workshop_completion_audio != null:
			var completion_playback: AudioStreamPlayback
			if opening.workshop_completion_audio.playing:
				completion_playback = opening.workshop_completion_audio.get_stream_playback()
			if completion_playback != null:
				audio_refs.append(weakref(completion_playback))
			completion_playback = null
			var completion_stream: AudioStream = opening.workshop_completion_audio.stream
			if completion_stream != null:
				audio_refs.append(weakref(completion_stream))
			completion_stream = null
			opening.workshop_completion_audio.stop()
			opening.workshop_completion_audio.stream = null
		opening.free()
		opening = null
	ConstructionAudio.streams.clear()
	ConstructionAudio.source_status = "uninitialized"
	MechanicalAmbience.loops.clear()
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
	if status == "pass" and (event_route_loose or event_route_pointer):
		print("CHAPTER 1 SCENE EVENTS PASS: " + mode)
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

func _press_inventory_recipe(key: String, bench_id: String = "") -> bool:
	var inventory = opening.building_hotbar
	if opening.object_menu.visible:
		opening.object_menu.hide()
	if inventory.catalog.visible:
		inventory.catalog.hide()
	if bench_id.is_empty():
		inventory.open_catalog()
	else:
		inventory.open_at_bench(bench_id)
	if not _expect(inventory.catalog.visible and inventory.recipe_buttons.has(key)
			and inventory.recipe_buttons[key].visible,
			"The ordinary inventory exposes recipe " + key):
		return false
	inventory.recipe_buttons[key].pressed.emit()
	inventory.catalog.hide()
	return true

func _select_inventory_item(tool: String) -> bool:
	var inventory = opening.building_hotbar
	if opening.object_menu.visible:
		opening.object_menu.hide()
	if inventory.catalog.visible:
		inventory.catalog.hide()
	inventory.open_catalog()
	var button: Button
	if tool.begins_with("component:"):
		button = inventory.component_buttons.get(tool.trim_prefix("component:"))
	else:
		button = inventory.catalog_buttons.get(tool)
	if not _expect(button != null and button.visible and not button.disabled,
			"The ordinary inventory has a carried item for " + tool):
		return false
	button.pressed.emit()
	return true

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

func _capture_slide_shaft(slide_id: String, path: String) -> bool:
	var shaft: MeshInstance3D
	var spindle: MeshInstance3D
	for child: Node in opening.transmission_presenter.get_children():
		if child.get_meta("component_entity", "") == slide_id:
			shaft = child.get_node_or_null("IntegralInputShaft") as MeshInstance3D
		elif child.name == "AttachedHandCrank":
			spindle = child.get_node_or_null("CrankSpindle") as MeshInstance3D
	if shaft == null or spindle == null:
		return false
	var axis: Vector3 = shaft.global_basis.y.normalized()
	var offset: Vector3 = spindle.global_position - shaft.global_position
	var along: float = offset.dot(axis)
	var transverse: float = (offset - axis * along).length()
	var shaft_half: float = (shaft.mesh as CylinderMesh).height * 0.5
	var spindle_half: float = (spindle.mesh as CylinderMesh).height * 0.5
	var overlap: float = minf(shaft_half, along + spindle_half) - maxf(-shaft_half, along - spindle_half)
	facts["shaft_probe"] = {"axial_overlap_m": overlap, "axis_offset_m": along,
		"center_offset_m": transverse,
		"shaft_radius_m": (shaft.mesh as CylinderMesh).top_radius,
		"spindle_radius_m": (spindle.mesh as CylinderMesh).top_radius,
		"parallel": absf(axis.dot(spindle.global_basis.y.normalized()))}
	if overlap < 0.07 or transverse > 0.0001 or \
			absf(axis.dot(spindle.global_basis.y.normalized())) < 0.999 or \
			(spindle.mesh as CylinderMesh).top_radius - (shaft.mesh as CylinderMesh).top_radius < 0.002:
		return false
	var close := SubViewport.new()
	close.size = Vector2i(1280, 800)
	close.world_3d = root.world_3d
	close.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(close)
	var camera := Camera3D.new()
	close.add_child(camera)
	camera.fov = 28.0
	camera.position = spindle.global_position + Vector3(0.0, 0.06, 0.62)
	camera.look_at(spindle.global_position)
	camera.make_current()
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var captured: bool = close.get_texture().get_image().save_png(path) == OK
	close.queue_free()
	return captured

func _capture_anvil_side(path: String, target: Vector3, support_y: float) -> bool:
	var close := SubViewport.new()
	close.size = Vector2i(1280, 800)
	close.world_3d = root.world_3d
	close.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(close)
	var camera := Camera3D.new()
	close.add_child(camera)
	camera.fov = 38.0
	camera.position = Vector3(target.x + 0.95, support_y + 0.70, target.z + 1.05)
	camera.look_at(target)
	camera.make_current()
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var captured: bool = close.get_texture().get_image().save_png(path) == OK
	close.queue_free()
	return captured

func _capture_press_context_side(path: String, target: Vector3) -> bool:
	var context := SubViewport.new()
	context.size = Vector2i(1280, 800)
	context.world_3d = root.world_3d
	context.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(context)
	var camera := Camera3D.new()
	context.add_child(camera)
	camera.fov = 52.0
	camera.position = target + Vector3(2.1, 0.55, 2.25)
	camera.look_at(target)
	camera.make_current()
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var captured: bool = context.get_texture().get_image().save_png(path) == OK
	context.queue_free()
	return captured

func _capture_press_standing_approach(path: String, workface: Vector3) -> bool:
	var context := SubViewport.new()
	context.size = Vector2i(1280, 800)
	context.world_3d = root.world_3d
	context.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(context)
	var camera := Camera3D.new()
	context.add_child(camera)
	# The neighboring raised foundation supports this eye-height viewpoint.
	# It reveals the working surface, head, slide feet and separate belt fitting.
	camera.fov = 64.0
	camera.position = workface + Vector3(-0.75, 0.60, 0.60)
	camera.look_at(workface + Vector3(0.45, 0.15, 0))
	camera.make_current()
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var captured: bool = context.get_texture().get_image().save_png(path) == OK
	context.queue_free()
	return captured

func _capture_actor_area(path: String, target: Vector3) -> bool:
	var prior_distance: float = opening.distance
	var prior_yaw: float = opening.orbit_yaw
	var prior_pitch: float = opening.orbit_pitch
	opening.distance = 0.0
	opening._update_camera()
	var direction: Vector3 = (target - opening.camera.global_position).normalized()
	opening.orbit_yaw = atan2(-direction.x, -direction.z)
	opening.orbit_pitch = asin(clampf(-direction.y, -1.0, 1.0))
	opening._update_camera()
	if opening.mode == "component":
		opening._refresh_component_preview()
	await process_frame
	await RenderingServer.frame_post_draw
	var captured: bool = root.get_texture().get_image().save_png(path) == OK
	opening.distance = prior_distance
	opening.orbit_yaw = prior_yaw
	opening.orbit_pitch = prior_pitch
	opening._update_camera()
	return captured

func _aim_actor_at_component(id: String) -> Dictionary:
	var occupied: Array = opening.model.projection().placed_components[id].occupied.center
	var target := Vector3(float(occupied[0]), float(occupied[1]), float(occupied[2]))
	opening.distance = 0.0
	opening._update_camera()
	var direction: Vector3 = (target - opening.camera.global_position).normalized()
	opening.orbit_yaw = atan2(-direction.x, -direction.z)
	opening.orbit_pitch = asin(clampf(-direction.y, -1.0, 1.0))
	opening._update_camera()
	await physics_frame
	var screen: Vector2 = opening._pointed_screen_position()
	return opening._screen_pick(screen)

func _aim_actor_at_crank(id: String) -> Dictionary:
	var pick: StaticBody3D = null
	for node: Node in opening.transmission_presenter.get_children():
		if node.get_meta("crank_entity", "") == id:
			pick = node.get_node_or_null("AttachedCrankPick") as StaticBody3D
			break
	if pick == null:
		return {}
	var target: Vector3 = pick.global_position + Vector3(0, 0.07, 0)
	opening.distance = 0.0
	opening._update_camera()
	var direction: Vector3 = (target - opening.camera.global_position).normalized()
	opening.orbit_yaw = atan2(-direction.x, -direction.z)
	opening.orbit_pitch = asin(clampf(-direction.y, -1.0, 1.0))
	opening._update_camera()
	await physics_frame
	return opening._screen_pick(opening._pointed_screen_position())

func _pulse_fitted_world_crank(id: String) -> bool:
	if opening.object_menu.visible:
		opening.object_menu.hide()
		await process_frame
	opening._select_tool("inspect")
	var hit := await _aim_actor_at_crank(id)
	if opening._pointed_crank() != id:
		var item: Dictionary = opening.model.projection().crank_items[id]
		var port: Array = item.port
		var face: Array = item.get("face", [])
		var standing_points: Array[Vector2] = [Vector2(float(port[0]) * OpeningGeometry.HEIGHT_STEP - 0.22,
			float(port[2]) * OpeningGeometry.HEIGHT_STEP - 1.25)]
		if face == [0, 0, 1]:
			standing_points = [Vector2(float(port[0]) * OpeningGeometry.HEIGHT_STEP + 1.25,
					float(port[2]) * OpeningGeometry.HEIGHT_STEP + 1.25)]
		for standing_point in standing_points:
			if not await _approach(standing_point):
				return false
			hit = await _aim_actor_at_crank(id)
			if opening._pointed_crank() == id:
				break
	if not _expect(hit.get("collider") != null and opening._pointed_crank() == id
			and not opening.object_menu.visible,
			"The physical worker points at the fitted crank outside the press menu: %s" %
			str({"expected": id, "pointed": opening._pointed_crank(),
				"hit": str(hit.get("collider", null)), "actor": opening.actor_world.bodies.P.global_position,
				"camera": opening.camera.global_position,
				"hit_name": hit.get("collider", null).name if hit.get("collider") != null else "",
				"hit_layer": hit.get("collider", null).collision_layer if hit.get("collider") != null else 0,
				"hit_terrain": hit.get("collider", null).get_meta("transmission_terrain", false) if hit.get("collider") != null else false,
				"hit_position": hit.get("position"),
				"hit_component": hit.get("collider", null).get_meta("component_entity", "") if hit.get("collider") != null else "",
				"hit_crank": hit.get("collider", null).get_meta("crank_entity", "") if hit.get("collider") != null else "",
				"port": opening.model.projection().crank_items[id].port,
				"face": opening.model.projection().crank_items[id].get("face")})):
		return false
	var before: Dictionary = opening.model.projection()
	var press := InputEventKey.new()
	press.keycode = KEY_E
	press.physical_keycode = KEY_E
	press.pressed = true
	opening._unhandled_input(press)
	var after: Dictionary = opening.model.projection()
	var focused_input: bool = int(after.order) == int(before.order) + 1
	if not focused_input:
		if not _expect(not DisplayServer.window_is_focused() and after.order == before.order
				and opening.held_crank.is_empty(),
				"An unfocused passive window cannot claim an accepted E crank pulse"):
			return false
		var fallback: Dictionary = opening.issue({"action": "operate_hand_crank", "entity": id})
		if not _expect(fallback.get("accepted", false),
				"Native crank authority supplies the passive unfocused scene check"):
			return false
		facts["crank_input"] = "native_after_unfocused_e"
	else:
		facts["crank_input"] = "focused_world_e"
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	opening._input(release)
	return _expect(opening.model.projection().order == before.order + 1
			and opening.held_crank.is_empty()
			and not opening.object_menu.visible,
			"One fitted world-crank interaction commits exactly one native pulse")

func _approach(target: Vector2, actor: String = "P") -> bool:
	if not await _walk_to(target, false, actor):
		return false
	for frame in range(30):
		await physics_frame
		await process_frame
		if frame >= 3 and opening.actor_world.diagnostics(actor).sample.on_floor:
			break
	var sample: Dictionary = opening.actor_world.diagnostics(actor).sample
	return _expect(sample.ready and sample.registered and sample.on_floor and sample.control == [0.0, 0.0],
		"The real approach to %s finishes with a released, registered actor on the floor: %s" % [target, sample])

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
		if inventory.catalog.visible:
			inventory.catalog.hide()
		await process_frame
		inventory.open_catalog()
		await process_frame
		inventory._place_catalog()
		await RenderingServer.frame_post_draw
		var empty_capture: Error = root.get_texture().get_image().save_png(capture_prefix + "-empty-narrow.png")
		var empty_rect := Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size))
		if not _expect(inventory.catalog.visible and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
				empty_rect) and empty_capture == OK,
				"The ordinary zero-stock inventory remains usable at a narrow viewport: " +
				str({"visible": inventory.catalog.visible, "popup": empty_rect, "viewport": root.size,
					"parent": inventory.get_parent().size, "minimum": inventory.catalog.min_size})):
			return
		root.size = original_size
		await process_frame
		inventory._place_catalog()
	inventory.catalog.hide()
	if not await _approach(Vector2(6.0, 3.45)):
		return
	var distant: Dictionary = opening.model.projection()
	if not _press_inventory_recipe("component:wooden_frame", str(distant.fabrication_hub.id)):
		return
	if not _expect(opening.model.projection().order == distant.order
			and opening.model.projection().cargo == distant.cargo
			and "Carry the ingredients" in opening.building_hotbar.focus_description.text,
			"The remote inventory recipe preserves cargo while its inputs are missing"):
		return
	var remote_refusal: Dictionary = _issue({"action": "craft_component",
		"entity": distant.fabrication_hub.id, "component": "wooden_frame"})
	if not _expect(not remote_refusal.accepted and remote_refusal.reason == "out_of_reach",
			"Native bench crafting still refuses a physically distant actor"):
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
			and "Shape with multitool" in inventory.recipe_buttons["component:wooden_frame"].tooltip_text,
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
		if inventory.catalog.visible:
			inventory.catalog.hide()
		await process_frame
		inventory.open_catalog()
		await process_frame
		inventory._place_catalog()
		await RenderingServer.frame_post_draw
		var narrow_capture: Error = root.get_texture().get_image().save_png(capture_prefix + "-timber-narrow.png")
		var narrow_rect := Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size))
		if not _expect(inventory.catalog.visible and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(narrow_rect)
				and narrow_capture == OK,
				"The ordinary carried-timber inventory remains usable at a narrow viewport: " +
				str({"popup": narrow_rect, "viewport": root.size, "minimum": inventory.catalog.min_size})):
			return
		root.size = original_size
		await process_frame
		inventory._place_catalog()
	if not inventory.catalog.visible:
		inventory.open_catalog()
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
	await process_frame
	if not _expect(opening.goal_text == "FORM A PLATE · KEEP IT\nPlace a carried part [B].",
			"The ordinary finite crafted part receives a component action cue without a fixed press bill"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-carried-component-hud.png") == OK,
				"Retain the ordinary crafted-component HUD without an anvil recipe"):
			return
	if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
		return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	var bench_ready: Dictionary = opening.model.projection()
	opening._open_object_menu_for(str(opening.model.projection().fabrication_hub.id))
	await process_frame
	if not _expect(inventory.catalog.visible and inventory.context_bench == "pod-fabrication-hub"
			and not opening.object_menu.visible
			and "Craft at selected bench; stand nearby" in inventory.recipe_buttons["component:wooden_shaft"].tooltip_text,
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
			and "Craft at selected bench; stand nearby" in inventory.recipe_buttons.foundation.tooltip_text,
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
	if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
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
	if not _expect(opening.landing_hub_pick.collision_layer == OpeningGeometry.PICK_LAYER
			and original.fabrication_hub.installed,
			"The ordinary pick body exposes the installed issued workshop"):
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
			and not inventory._valid_bench(carried, id),
		"Stowing moves only the one issued hub into actor custody while the pod stays landed"):
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
			and inventory._valid_bench(installed, id),
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
	if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
		return
	if not await _approach(Vector2(5.4, 4.95)):
		return
	opening._open_object_menu_for(id)
	if not _expect(inventory.catalog.visible and inventory.context_bench == id
			and "Craft at selected bench; stand nearby" in inventory.recipe_buttons["component:cutting_edge"].tooltip_text,
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
			"Store saves the moved issued hub and physical actor for a fresh-process resume: " + str(save)):
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
			and opening.building_hotbar._valid_bench(restored, id),
			"Fresh-process restore preserves one moved hub, finite cargo, pod anchor and selectable pick body"):
		return
	opening._select_tool("deconstruct")
	opening._world_click(Vector2i(4, 3), id)
	var carried: Dictionary = opening.model.projection()
	if not _expect(not carried.fabrication_hub.installed and carried.fabrication_hub.holder == "P"
			and carried.fabrication_hub.id == id
			and not opening.building_hotbar._valid_bench(carried, id)
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
	if not OpeningScene.apply_test_window_title(self):
		return
	if event_route_loose and mode not in ["arrival-channel-small", "arrival-channel-small-resume"] \
			or event_route_pointer and mode not in ["arrival-first-plate", "arrival-raised-starter-snap", "arrival-raised-press"]:
		push_error("The selected event route does not apply to this fixture mode")
		quit(1)
		return
	if mode == "supplied-hardware":
		await _arrival_run()
		return
	if mode in ["arrival-mature-trees", "arrival-mature-trees-resume", "arrival-starter-assembly", "arrival-first-plate", "arrival-raised-starter-snap", "arrival-raised-starter-belt", "arrival-blocked-feed-cue", "arrival-first-plate-resume", "arrival-slide", "arrival-press", "arrival-guide-geometry", "arrival-press-site", "arrival-belt-fed-press", "arrival-belt-fed-press-resume", "arrival-powered-press-site", "arrival-powered-press-resume", "arrival-powered-press-blocked-resume", "arrival-powered-press-release-resume", "arrival-broad-pad", "arrival-broad-drive", "arrival-broad-form", "arrival-broad-cut-resume", "arrival-channel-broad", "arrival-channel-small", "arrival-channel-broad-resume", "arrival-channel-small-resume", "arrival-raised-press", "arrival-raised-press-resume", "arrival-resume", "arrival-craft-capacity", "arrival-craft-capacity-resume", "arrival-field-craft", "arrival-foundation-craft", "arrival-foundation-craft-resume", "arrival-portable-workbench", "arrival-pod-workshop", "arrival-pod-workshop-resume", "arrival-belt", "arrival-belt-controls", "arrival-belt-resume", "arrival-cancel-placement", "arrival-reveal", "arrival-reveal-skip"]:
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
	var contacts: Array[String] = []
	for index in opening.actor_world.bodies[actor].get_slide_collision_count():
		var collision: KinematicCollision3D = opening.actor_world.bodies[actor].get_slide_collision(index)
		var collider: Object = collision.get_collider()
		contacts.append("%s %s" % [collider.name if collider is Node else str(collider), collision.get_normal()])
	facts["failed_walk"] = {"actor": actor, "target": target, "stopped_at": stopped_at,
		"contacts": contacts}
	return _expect(false, "The bounded native walk must reach %s; stopped at %s; contacts %s" %
		[target, stopped_at, contacts])

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
	var inventory = opening.building_hotbar
	var tile: Button = inventory.recipe_buttons["component:copper_shaft"]
	if not _expect(inventory.catalog.visible and inventory.context_bench == opening.model.projection().fabrication_hub.id
			and tile.visible and tile.icon != null,
			"The pod workshop exposes the native component recipes in its shared inventory"):
		return
	if not _expect(recipes.wooden_shaft.load_rating == 8
			and recipes.wooden_cog.load_rating == 8
			and recipes.copper_shaft.load_rating == 24
			and recipes.copper_cog.load_rating == 24,
			"The ordinary workshop receives its drive ratings from the native projection"):
		return
	tile.grab_focus()
	if not _expect("rated for 24 load" in tile.tooltip_text
			and "0 timber + 2 ore" in tile.tooltip_text
			and "needs 0 timber and 2 ore" in tile.accessibility_name,
			"The copper upgrade recipe shows its native rating and actual bill"):
		return
	if not capture_prefix.is_empty():
		await process_frame
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-drive-ratings.png") == OK,
				"The native-backed workshop rating is retained in a normal viewport frame"):
			return
	await process_frame
	await process_frame
	var popup_rect := Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size))
	var recipe_scroll: ScrollContainer = inventory.recipe_scroll
	facts["workshop_layout"] = {"popup": popup_rect, "viewport": root.size,
		"horizontal_scroll": recipe_scroll.get_h_scroll_bar().visible}
	if not capture_prefix.is_empty():
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-long-choice.png") == OK,
				"The native recipe grid is retained in the centered workshop"):
			return
	if not _expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(popup_rect)
			and not recipe_scroll.get_h_scroll_bar().visible,
			"The native recipe grid remains horizontally reachable inside the centered inventory: "
			+ str(facts.workshop_layout)):
		return
	inventory.catalog.hide()
	await process_frame
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
	for count in range(21):
		if not _expect(opening.building_hotbar.recipe_buttons["component:wooden_shaft"].visible,
				"The pod workshop keeps the native shaft recipe discoverable while stock is available"):
			return
		var before: Dictionary = opening.model.projection()
		if not _press_inventory_recipe("component:wooden_shaft", str(before.fabrication_hub.id)):
			return
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
	await process_frame
	if opening.building_hotbar.catalog.visible:
		opening.building_hotbar.catalog.hide()
	opening.building_hotbar.open_catalog()
	await process_frame
	tile = opening.building_hotbar.component_buttons.wooden_shaft
	if not _expect(opening.building_hotbar.catalog.visible and tile.icon != null
			and opening.building_hotbar.component_counts.wooden_shaft.text == "21"
			and "21 carried" in tile.tooltip_text
			and "21 carried" in tile.accessibility_name,
			"The shared build and inventory window shows twenty-one shafts as an icon, count, and hover description: " +
			str({"open": opening.building_hotbar.catalog.visible, "icon": tile.icon != null,
				"count": opening.building_hotbar.component_counts.wooden_shaft.text,
				"tooltip": tile.tooltip_text, "focus": tile.accessibility_name})):
		return
	var inventory_scroll: ScrollContainer = opening.building_hotbar.inventory_scroll
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
	var ore_for_press := 0 if finish else (11 if mode == "arrival-powered-press-site" else 8)
	for source in [
		{"point": Vector2(6.0, 3.45), "id": "tree-east-south", "cuts": 8},
		{"point": Vector2(4.95, 4.95), "cuts": 0},
		{"point": Vector2(4.95, 9.9), "cuts": 0},
		{"point": Vector2(6.0, 11.55), "id": "tree-east-north", "cuts": 7},
		{"point": Vector2(0.6, 11.55), "id": "tree-north", "cuts": 2},
		{"point": Vector2(4.95, 9.9), "cuts": 0},
		{"point": Vector2(4.95, 3.3), "cuts": 0},
		{"point": Vector2(-0.5, 0.0), "id": "opening-copper", "cuts": 3 + ore_for_press},
	]:
		if not await _approach(source.point):
			return
		for index in range(source.cuts):
			if _construct({"action": "harvest_source", "target": source.id}).is_empty():
				return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	if not _expect(opening.model.projection().cargo.P.timber == 17
			and opening.model.projection().cargo.P.raw == 3 + ore_for_press,
			"Three finite trees and the outcrop supply the collector route, crank and later press stock"):
		return
	for kind in ["wooden_frame", "tool_mount", "cutting_edge", "receiver_tray", "wooden_shaft"]:
		if not _expect(opening.building_hotbar.recipe_buttons.has("component:" + kind),
				"The native collector component is listed in the ordinary inventory recipes"):
			return
		if not _press_inventory_recipe("component:" + kind, str(opening.model.projection().fabrication_hub.id)):
			return
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
		var before: Dictionary = opening.model.projection()
		if not _press_inventory_recipe("part:%d" % index, str(before.fabrication_hub.id)):
			return
		var after: Dictionary = opening.model.projection()
		if not _expect(after.order == before.order + 1 and after.part_kits.P[route_part] == before.part_kits.P[route_part] + 1,
				"The ordinary workshop turns carried stock into one exact native route kit"):
			return
	if not _press_inventory_recipe("component:hand_crank", str(opening.model.projection().fabrication_hub.id)):
		return
	if not _expect(opening.model.projection().cargo.P.timber == 0
			and opening.model.projection().cargo.P.raw == ore_for_press,
			"The collector, hand crank and three-shaft route spend seventeen timber and three ore"):
		return
	var carried_crank := ""
	for crank_id: String in opening.model.projection().crank_items:
		if opening.model.projection().crank_items[crank_id].holder == "P":
			carried_crank = crank_id
	if not _expect(not carried_crank.is_empty(),
			"The physical actor carries the finite crafted crank away from the workshop"):
		return
	if not await _approach(Vector2(0.0, 1.3)):
		return
	if not _select_inventory_item("wheel"):
		return
	if not _expect(opening.mode == "wheel", "The ordinary workshop arms its crafted waterwheel tool"):
		return
	var wheel: Dictionary = _construct({"action": "place", "kind": "wheel", "cell": [-2, 0], "axis": "x", "level": 4})
	if wheel.is_empty():
		return
	var shaft_recipe := -1
	for choice in opening.model.projection().part_recipes.size():
		if opening.model.projection().part_recipes[choice].kind == "shaft":
			shaft_recipe = choice
	if not _select_inventory_item("drive"):
		return
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
	if not _select_inventory_item("belt"):
		return
	if not _expect(opening.mode == "belt", "The ordinary workshop arms its crafted belt tool"):
		return
	var span: Dictionary = _construct({"action": "place_belt_span", "from": inlet, "to": far})
	if span.is_empty():
		return
	# Follow the open southward aisle before turning east to the collector
	# foundation; a diagonal from the belt cuts across scene collision.
	if not await _approach_points([Vector2(0.0, 3.3), Vector2(0.7, 3.3)]):
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
			and panel._receiver_route_status(built).contains("outward"),
			"The fitted north receiver meets a powered outward belt mouth in native inspection"):
		return
	var drive := ""
	for collector: Dictionary in built.collector_assemblies:
		if collector.get("status") == "ready":
			drive = str(collector.parts.mount)
			break
	# Walk around the east side of the fitted collector. The direct first east
	# step meets installed collision; the open southern detour keeps the actor
	# on real floor and both inputs within build reach at the wheel.
	if not await _approach_points([Vector2(0.7, 4.95), Vector2(1.65, 4.95),
			Vector2(1.65, 0.2), Vector2(0.2, 0.55)]):
		return
	if _construct({"action": "remove", "entity": wheel.entity}).is_empty():
		return
	if not _expect(panel._receiver_route_status(opening.model.projection()).contains("linked"),
			"Removing the wheel leaves the physical belt linked for a manual collector cut"):
		return
	if _construct({"action": "attach_hand_crank", "entity": drive,
			"crank": carried_crank, "port": [-1, 4, 4]}).is_empty():
		return
	if _construct({"action": "turn_hand_crank", "entity": drive}).is_empty():
		return
	var before_tick: Dictionary = opening.model.projection()
	if not _expect(before_tick.dropped_material.any(func(drop: Variant) -> bool:
		return drop is Dictionary and drop.get("raw", 0) == 1),
		"The hand crank puts one true ore blank in the fitted receiver"):
		return
	if _construct({"action": "detach_hand_crank", "entity": carried_crank}).is_empty():
		return
	if not _select_inventory_item("wheel"):
		return
	if not _expect(opening.mode == "wheel", "The ordinary workshop arms its crafted waterwheel tool"):
		return
	if _construct({"action": "place", "kind": "wheel", "cell": [-2, 0], "axis": "x", "level": 4}).is_empty():
		return
	if not _expect(panel._receiver_route_status(opening.model.projection()).contains("outward"),
			"The installed waterwheel turns the linked receiver belt outward"):
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
	if not await _approach_points([Vector2(1.1, 0.2), Vector2(1.1, 3.3), Vector2(0.4, 2.8)]):
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
			and after.hand_sources == before.hand_sources and after.crank_items == before.crank_items,
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
	opening._toggle_manager_log()
	if not _expect(opening.manager_log_open and opening.manager_log_layer.visible
			and not opening._can_control_character()
			and "Gather 5 timber and 4 copper pieces" in opening.manager_log_current.text
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
	var inventory = opening.building_hotbar
	inventory.open_catalog()
	if not _expect(after_log.first_plate_unlock and after_log.workshop_completed_actors.is_empty()
			and inventory.slots.all(func(slot: String) -> bool: return slot.is_empty())
			and inventory.recipe_buttons.has("component:anvil")
			and inventory.recipe_buttons.has("component:flat_head")
			and inventory.recipe_buttons.has("component:wooden_slide")
			and not inventory.recipe_buttons.has("component:wooden_cog")
			and not inventory.recipe_buttons.has("component:receiver_tray")
			and not inventory.recipe_buttons.has("foundation")
			and inventory.context_label.text.contains("press with a hand crank")
			and not inventory.context_label.text.contains("anvil, flat head"),
			"Fresh native arrival offers starter recipes and a first-plate goal without an assembly checklist"):
		return
	if not capture_prefix.is_empty():
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-starter-catalog.png") == OK,
				"Retain the ordinary starter inventory and empty hotbar in one passive frame"):
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
		{"point": Vector2(6.0, 11.55), "id": "tree-east-north", "cuts": 1},
		{"point": Vector2(0.6, 11.55), "id": "tree-north", "cuts": 6},
		{"point": Vector2(4.95, 9.9), "cuts": 0},
		{"point": Vector2(4.95, 4.95), "cuts": 0},
	]:
		if not await _approach(source.point):
			return
		for cut in range(source.cuts):
			if _construct({"action": "harvest_source", "target": source.id}).is_empty():
				return
	if not await _approach_points([Vector2(4.95, 3.3), Vector2(6.0, -1.65)]):
		return
	for cut in range(8 if mode == "arrival-powered-press-site" else 3):
		if _construct({"action": "harvest_source", "target": "tree-east-upstream"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 3.3), Vector2(4.95, 4.95)]):
		return
	if not _expect(opening.model.projection().cargo.P.timber ==
			(15 if mode == "arrival-powered-press-site" else 10)
			and opening.model.projection().cargo.P.raw ==
				(11 if mode == "arrival-powered-press-site" else 8),
			"The remaining finite trees and ore supply the guided press and output route"):
		return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	for kind in ["anvil", "ram_face", "sliding_guide", "wooden_shaft", "copper_cog", "receiver_tray"]:
		if not _expect(opening.building_hotbar.recipe_buttons.has("component:" + kind),
				"The ordinary inventory lists the finite guided press component"):
			return
		var before: Dictionary = opening.model.projection()
		if not _press_inventory_recipe("component:" + kind, str(before.fabrication_hub.id)):
			return
		var after: Dictionary = opening.model.projection()
		if not _expect(after.order == before.order + 1
				and int(after.cargo.P.components.get(kind, 0)) == int(before.cargo.P.components.get(kind, 0)) + 1,
				"The ordinary workshop crafts one finite guided press component"):
			return
	if not _expect(opening.model.projection().cargo.P.timber ==
			(11 if mode == "arrival-powered-press-site" else 6)
			and opening.model.projection().cargo.P.raw ==
				(5 if mode == "arrival-powered-press-site" else 2),
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
		{"kind": "copper_cog", "center": [0, 8, -6]},
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

func _arrival_powered_press_site_run(panel) -> void:
	facts.route = "collector_belt_powered_press_site"
	await _arrival_press_site_run(panel, false)
	if written:
		return
	var fed := false
	for tick in range(32):
		opening.model.advance()
		opening._refresh()
		if opening.model.projection().dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.get("center") == [0, 4, -8]
				and drop.get("raw", 0) == 1)):
			fed = true
			break
	if not _expect(fed and opening.model.projection().cargo.P.raw == 5,
			"The real belt stages one blank while the worker retains three relay inputs"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts.powered_site_save = saved
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store preserves the pre-power belt work and the worker’s finite relay stock"):
		return
	_record("pass")

func _arrival_belt_fed_press_resume_run(panel) -> void:
	facts["route"] = "collector_belt_hand_press_resume"
	var restored: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and restored.guided_press_assemblies.size() == 1
			and restored.guided_press_assemblies[0].status == "ready"
			and restored.dropped_material.any(func(drop: Variant) -> bool:
				return drop is Dictionary and drop.get("center") == [0, 4, -8] and drop.get("raw", 0) == 1)
			and restored.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
			and restored.crank_items.values().any(func(item: Variant) -> bool:
				return item.holder == "P")
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
	var carried_crank := ""
	for crank_id: String in opening.model.projection().crank_items:
		if opening.model.projection().crank_items[crank_id].holder == "P":
			carried_crank = crank_id
	if not _expect(not carried_crank.is_empty(), "The same crafted hand crank remains in P's custody"):
		return
	if not await _approach_points([Vector2(2.0, -1.2), Vector2(2.0, -3.4)]):
		return
	if _construct({"action": "attach_hand_crank", "entity": shaft,
			"crank": carried_crank, "port": press.shaft_center}).is_empty():
		return
	opening._open_object_menu_for(anvil)
	if not _expect(opening.object_menu.visible and panel.press_section.visible,
			"The belt-fed workbed remains inspectable before exterior crank operation"):
		return
	for turn in range(3):
		if not await _pulse_fitted_world_crank(carried_crank):
			return
		opening.model.advance()
		opening._refresh()
	opening._open_object_menu_for(anvil)
	var formed: Dictionary = opening.model.projection()
	if not _expect(formed.dropped_material.any(func(drop: Variant) -> bool:
			return drop is Dictionary and drop.get("products", 0) == 1)
			and formed.dropped_material.any(func(drop: Variant) -> bool:
				return drop is Dictionary and drop.get("offcuts", 0) == 1 and drop.get("center") == press.offcut_receiver)
			and formed.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The belt-fed blank forms one plate and routes its offcut into the side receiver through three world crank pulses"):
		return
	var receiver_drop: Dictionary = formed.dropped_material.filter(func(drop: Variant) -> bool:
		return drop is Dictionary and drop.get("center") == press.offcut_receiver)[0].duplicate(true)
	receiver_drop.erase("center")
	if _construct({"action": "pickup_material", "center": press.offcut_receiver,
			"expected": receiver_drop}).is_empty():
		return
	if not _expect(opening.model.projection().cargo.P.offcuts == 1,
			"The worker collects the routed offcut from its physical side receiver"):
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

func _arrival_powered_press_resume_run(panel) -> void:
	deadline = Time.get_ticks_msec() + 240000
	facts.evidence = "ordinary_collector_belt_powered_press_continuation"
	var start: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and start.guided_press_assemblies.size() == 1
			and start.guided_press_assemblies[0].status == "ready"
			and start.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [0, 4, -8]
					and drop.get("raw", 0) == 1))
			and start.actors.P.ready and start.actors.Q.ready,
			"A fresh native worksite retains the real belt blank before powering its press"):
		return
	var press_shaft: String = str(start.guided_press_assemblies[0].parts.shaft)
	if not _expect(start.motion[press_shaft].state == "unpowered"
			and start.cargo.P.timber == 11 and start.cargo.P.raw == 5,
			"The press has no gifted power relays or extra metal after its first setup"):
		return
	if not await _approach_points([Vector2(4.95, -1.2), Vector2(4.95, 3.3),
			Vector2(3.3, 4.95)]):
		return
	for kind in ["vertical_gearbox", "vertical_gearbox", "gearbox",
			"shaft", "shaft", "shaft", "shaft", "shaft", "shaft", "belt"]:
		var choice := -1
		var recipes: Array = opening.model.projection().part_recipes
		for index in range(recipes.size()):
			if recipes[index].kind == kind:
				choice = index
		if not _expect(choice >= 0, "The ordinary workshop lists a finite height-transfer part"):
			return
		if not _press_inventory_recipe("part:%d" % choice,
				str(opening.model.projection().fabrication_hub.id)):
			return
	if not _expect(opening.model.projection().part_kits.P.vertical_gearbox == 2
			and opening.model.projection().part_kits.P.gearbox == 1
			and opening.model.projection().part_kits.P.shaft == 6
			and opening.model.projection().part_kits.P.belt == 1
			and opening.model.projection().cargo.P.raw == 1,
			"The press and collector branch spend only harvested, carried workshop stock"):
		return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(3.3, 0.0),
			Vector2(1.65, -1.2)]):
		return
	if _construct({"action": "place_relay", "kind": "vertical_gearbox",
			"center": [4, 4, 0], "axis": "z"}).is_empty():
		return
	for relay in [
		{"kind": "vertical_gearbox", "center": [4, 8, 0], "axis": "z"},
		{"kind": "gearbox", "center": [0, 8, 0], "axis": "y"},
	]:
		if _construct({"action": "place_relay", "kind": relay.kind,
				"center": relay.center, "axis": relay.axis}).is_empty():
			return
	if _construct({"action": "place_shaft", "center": [0, 8, -4],
			"axis": "z", "half_span": 2}).is_empty():
		return
	if not await _approach_points([Vector2(3.3, -1.2)]):
		return
	var branch_ids: Array[String] = []
	for center in [[8, 4, 0], [12, 4, 0], [12, 4, 4], [8, 4, 4], [4, 4, 4]]:
		var placed: Dictionary = _construct({"action": "place_shaft", "center": center,
			"axis": "x", "half_span": 2})
		if placed.is_empty():
			return
		branch_ids.append(str(placed.entity))
	if _construct({"action": "place_belt_span", "from": branch_ids[1],
			"to": branch_ids[2]}).is_empty():
		return
	var powered: Dictionary = opening.model.projection()
	facts.powered_motion = powered.motion.get(press_shaft, {})
	var collector_shaft: String = str(powered.collector_assemblies[4].parts.shaft)
	if not _expect(powered.motion.has(press_shaft)
			and powered.motion[press_shaft].state == "rotating"
			and not powered.motion[press_shaft].overloaded
			and powered.motion.has(collector_shaft)
			and powered.motion[collector_shaft].state == "rotating"
			and powered.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The finite river drive powers the press and collector through actual supported branches"):
		return
	var formed := false
	for tick in range(128):
		opening.model.advance()
		var current: Dictionary = opening.model.projection()
		if current.dropped_material.any(func(drop: Variant) -> bool:
			return drop is Dictionary and drop.get("products", 0) == 1):
			formed = true
			facts.powered_ticks = tick + 1
			break
	opening._refresh()
	var final: Dictionary = opening.model.projection()
	if not _expect(formed and final.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
			and final.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("offcuts", 0) == 1
					and drop.get("center") == [1, 4, -8])),
			"Native ticks form the original belt-fed plate and discharge its offcut without hand turns"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts.powered_save = saved
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store retains the powered press and its first automatic copper output"):
		return
	_record("pass")

func _arrival_powered_press_blocked_resume_run() -> void:
	deadline = Time.get_ticks_msec() + 240000
	facts.evidence = "ordinary_powered_press_blocked_output"
	var start: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and start.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [0, 4, -9]
					and drop.get("products", 0) == 1))
			and start.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [1, 4, -8]
					and drop.get("offcuts", 0) == 1))
			and start.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"A fresh scene restores one automatic plate, its offcut and conserved finite stock"):
		return
	var press_shaft: String = str(start.guided_press_assemblies[0].parts.shaft)
	if not _expect(start.motion[press_shaft].state == "rotating"
			and not start.motion[press_shaft].overloaded,
			"The original waterwheel still powers the loaded press after fresh restore"):
		return
	var blocked := false
	var trace: Array = []
	for tick in range(256):
		var current: Dictionary = opening.model.advance()
		if tick % 16 == 15:
			trace.append({"tick": tick + 1, "drops": current.dropped_material.duplicate(true),
				"stock": current.material_mass.duplicate(true)})
		blocked = current.dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.get("center") == [0, 4, -8]
				and drop.get("work_lots", []).size() == 1
				and drop.work_lots[0].get("remaining", -1) == 0))
		if blocked:
			facts.blocked_ticks = tick + 1
			break
	opening._refresh()
	facts.blocked_trace = trace
	if blocked:
		for extra in range(8):
			opening.model.advance()
	var retained: Dictionary = opening.model.projection()
	if not _expect(blocked and retained.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
			and retained.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [0, 4, -8]
					and drop.get("work_lots", []).size() == 1
					and drop.work_lots[0].get("remaining", -1) == 0))
			and retained.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [0, 4, -9]
					and drop.get("products", 0) == 1))
			and retained.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [1, 4, -8]
					and drop.get("offcuts", 0) == 1)),
			"The next native work lot waits ready behind the occupied exit without duplicating output"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts.blocked_save = saved
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store preserves the blocked ready work, first plate and first offcut"):
		return
	_record("pass")

func _arrival_powered_press_release_resume_run(panel) -> void:
	deadline = Time.get_ticks_msec() + 240000
	facts.evidence = "ordinary_powered_press_output_recovery"
	var start: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and start.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [0, 4, -8]
					and drop.get("work_lots", []).size() == 1
					and drop.work_lots[0].get("remaining", -1) == 0))
			and start.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [0, 4, -9]
					and drop.get("products", 0) == 1))
			and start.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [1, 4, -8]
					and drop.get("offcuts", 0) == 1))
			and start.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The original ready work, occupied plate exit and offcut tray survive another fresh load"):
		return
	if not await _approach_points([Vector2(3.3, -1.2), Vector2(1.65, -1.2)]):
		return
	var anvil: String = str(start.guided_press_assemblies[0].anvil)
	opening._open_object_menu_for(anvil)
	if not _expect(opening.object_menu.visible and panel.press_section.visible
			and not panel.pickup_button.disabled,
			"The ordinary selected press offers the first plate at its actual exit"):
		return
	panel.pickup_button.pressed.emit()
	var cleared: Dictionary = opening.model.projection()
	if not _expect(cleared.cargo.P.products == 1
			and not cleared.dropped_material.any(func(drop: Variant) -> bool:
				return drop is Dictionary and drop.get("center") == [0, 4, -9])
			and cleared.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The worker removes only the original plate and clears its blocked exit"):
		return
	var released := false
	for tick in range(32):
		var current: Dictionary = opening.model.advance()
		released = current.dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.get("center") == [0, 4, -9]
				and drop.get("products", 0) == 1))
		if released:
			facts.release_ticks = tick + 1
			break
	opening._refresh()
	var second: Dictionary = opening.model.projection()
	if not _expect(released and second.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
			and second.cargo.P.products == 1
			and second.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [1, 4, -8]
					and drop.get("offcuts", 0) == 2))
			and not second.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.get("center") == [0, 4, -8]
					and drop.get("work_lots", []).size() > 0)),
			"Native ticks release the retained second plate and preserve both copper offcuts"):
		return
	opening._open_object_menu_for(anvil)
	if not _expect(not panel.pickup_button.disabled,
			"The ordinary press offers the released second plate for collection"):
		return
	panel.pickup_button.pressed.emit()
	var final: Dictionary = opening.model.projection()
	if not _expect(final.cargo.P.products == 2
		and final.dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.get("center") == [1, 4, -8]
				and drop.get("offcuts", 0) == 2))
			and final.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
			and final.material_mass.plates == 2 and final.material_mass.offcut_units == 2,
			"The worker collects two distinct automatic plates while both copper offcuts remain conserved in the tray"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts.final_save = saved
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store validates both finished plates and retained offcuts after the blocked-output recovery"):
		return
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

func _arrival_slide_run(panel, capture_prefix: String) -> void:
	if not await _approach(Vector2(6.0, 3.45)):
		return
	for index in range(6):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 3.3), Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
		return
	if not await _approach_points([Vector2(0.0, 1.65), Vector2(3.3, 4.95)]):
		return
	var inventory = opening.building_hotbar
	if not _expect(inventory.recipe_buttons.has("component:wooden_slide"),
			"The ordinary inventory exposes the native wooden slide recipe"):
		return
	if not _press_inventory_recipe("component:wooden_slide", str(opening.model.projection().fabrication_hub.id)):
		return
	for kind in ["wheel", "shaft"]:
		var recipe := -1
		for index in opening.model.projection().part_recipes.size():
			if opening.model.projection().part_recipes[index].kind == kind:
				recipe = index
		if not _expect(recipe >= 0, "The workshop offers a finite external drive part"):
			return
		if not _press_inventory_recipe("part:%d" % recipe,
				str(opening.model.projection().fabrication_hub.id)):
			return
	if not _expect(opening.model.projection().cargo.P.timber == 0
			and opening.model.projection().cargo.P.raw == 0
			and opening.model.projection().cargo.P.components.get("wooden_slide", 0) == 1
			and opening.model.projection().part_kits.P.wheel == 1
			and opening.model.projection().part_kits.P.shaft == 1,
			"Six finite timber units and one ore blank become one slide, wheel and shaft"):
		return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(0.0, 1.3)]):
		return
	if not _select_inventory_item("wheel"):
		return
	if _construct({"action": "place", "kind": "wheel", "cell": [-2, 1],
			"axis": "x", "level": 4}).is_empty():
		return
	if not _select_inventory_item("drive"):
		return
	if _construct({"action": "place_shaft", "center": [-4, 4, 4],
			"axis": "x", "half_span": 2}).is_empty():
		return
	if not _select_inventory_item("component:wooden_slide"):
		return
	if not _expect(opening.mode == "component" and panel.selected_name() == "wooden_slide",
			"The slide icon selects the actual component placement mode"):
		return
	var placed := _construct({"action": "place_component", "component": "wooden_slide",
		"center": [-1, 4, 4]})
	if placed.is_empty():
		return
	var id: String = placed.entity
	var idle: Dictionary = opening.model.projection()
	if not _expect(idle.placed_components[id].component == "wooden_slide"
			and idle.cargo.P.components.get("wooden_slide", 0) == 0
			and idle.slide_phases[id].subticks == 0
			and idle.motion[id].state == "rotating",
			"One fixed native slide consumes its carried body and joins the external drive"):
		return
	var anchor: Node3D
	for child: Node in opening.transmission_presenter.get_children():
		if child.get_meta("component_entity", "") == id:
			anchor = child as Node3D
	if not _expect(anchor != null and anchor.has_node("IntegralInputShaft")
			and anchor.has_node("SlideCarriage") and
			anchor.get_node("SlideCarriage").position.y < anchor.get_node("SlideCrown").position.y,
			"The ordinary presenter shows the native port and resting carriage below its crown"):
		return
	var rest_carriage_y: float = anchor.get_node("SlideCarriage").position.y
	opening.model.advance()
	opening._refresh()
	var powered: Dictionary = opening.model.projection()
	if not _expect(powered.slide_phases[id].subticks > 0
			and powered.slide_phases[id].subticks < powered.slide_phases[id].cycle_subticks,
			"The external waterwheel advances the unloaded slide's exact native phase"):
		return
	anchor = null
	for child: Node in opening.transmission_presenter.get_children():
		if child.get_meta("component_entity", "") == id:
			anchor = child as Node3D
	if not _expect(anchor != null and anchor.get_node("SlideCarriage").position.y < rest_carriage_y,
			"The installed carriage follows the projected native phase"):
		return
	# Auto-advance consumes the native tick delta after its first complete view.
	# The presenter must receive each later carriage phase, not retain the first.
	opening.model._view_projection_borrowed()
	var first_delta: Dictionary = opening.model._advance_borrowed()
	opening._refresh_from_projection(first_delta)
	var second_delta: Dictionary = opening.model._advance_borrowed()
	opening._refresh_from_projection(second_delta)
	var exact_phase: Dictionary = opening.model.projection().slide_phases[id]
	if not _expect(first_delta.slide_phases[id].subticks != powered.slide_phases[id].subticks
			and second_delta.slide_phases[id].subticks != first_delta.slide_phases[id].subticks
			and second_delta.slide_phases[id] == exact_phase
			and opening.state.slide_phases[id] == exact_phase,
			"Successive native tick deltas keep the powered carriage current in the ordinary scene"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_guided_close(id, capture_prefix + "-slide.png"),
				"A passive ordinary scene capture retains the driven slide"):
			return
	opening.configure_save_slot(destination + ".worksite")
	var saved: Dictionary = opening._save_worksite()
	if not _expect(saved.accepted and saved.native_preflight.accepted
			and FileAccess.file_exists(opening.save_slot),
			"The native checkpoint retains a physically crafted and externally driven slide: " + str(saved)):
		return
	_record("pass")

func _arrival_first_plate_resume_run(capture_prefix: String) -> void:
	var restored: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and restored.first_plate_unlock and restored.cargo.P.products == 1
			and restored.workshop_completed_actors.has("P")
			and restored.placed_components.size() == 3
			and restored.crank_items.values().any(func(item: Variant) -> bool:
				return item.attached_to == restored.sliding_press_assemblies[0].parts.slide)
			and restored.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
			and opening.objective_title.contains("COMPLETE"),
			"A separate Godot process reopens the first carried plate and completed native milestone"):
		return
	var inventory = opening.building_hotbar
	inventory.open_catalog()
	if not _expect(inventory.recipe_buttons.has("component:wooden_cog")
			and inventory.recipe_buttons.has("component:receiver_tray")
			and inventory.recipe_buttons.has("foundation"),
			"The restored actor keeps the advanced recipe unlock without default hotbar assignments"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(
				capture_prefix + "-restored-catalog.png") == OK,
				"Retain a passive frame of the restored advanced catalog"):
			return
	_record("pass")

func _arrival_raised_starter_belt_context(capture_prefix: String, fitted: Dictionary) -> bool:
	# Build a belt beside the actor-built workbed, using finite workshop stock.
	# The two additional foundations keep its shaft supports at the same deck.
	if not await _approach_points([Vector2(6.6, 4.95), Vector2(6.6, 9.9), Vector2(6.0, 10.05)]):
		return false
	for _cut in range(4):
		if _construct({"action": "harvest_source", "target": "tree-east-north"}).is_empty():
			return false
	if not await _approach_points([Vector2(6.6, 4.95), Vector2(3.3, 4.95)]):
		return false
	var hub: String = str(opening.model.projection().fabrication_hub.id)
	for kind in ["shaft", "shaft", "belt"]:
		var choice := -1
		var recipes: Array = opening.model.projection().part_recipes
		for index in range(recipes.size()):
			if recipes[index].kind == kind:
				choice = index
		if not _expect(choice >= 0 and _press_inventory_recipe("part:%d" % choice, hub),
				"The finite workshop crafts the selected belt and both shaft ends"):
			return false
	if not await _approach(Vector2(6.6, 4.95)):
		return false
	for cell in [[4, 4], [5, 4]]:
		if _construct({"action": "place_foundation", "cell": cell, "level": 4}).is_empty():
			return false
	var ends: Array[String] = []
	for center in [[16, 4, 16], [20, 4, 16]]:
		var shaft: Dictionary = _construct({"action": "place_shaft", "center": center,
			"axis": "z", "half_span": 2})
		if shaft.is_empty():
			return false
		ends.append(str(shaft.entity))
	var belt: Dictionary = _construct({"action": "place_belt_span", "from": ends[0], "to": ends[1]})
	if belt.is_empty():
		return false
	opening._refresh()
	var state: Dictionary = opening.model.projection()
	var press: Dictionary = state.sliding_press_assemblies[0] if not state.sliding_press_assemblies.is_empty() else {}
	var connector: Node3D = opening.transmission_presenter.get_node_or_null("PressBeltConnector")
	if not _expect(press.get("status") == "ready" and press.get("parts", {}).get("anvil") == fitted.anvil
			and state.belt_spans.has(belt.entity) and connector != null
			and connector.get_meta("belt_span", "") == belt.entity,
		"The native ready press and placed belt endpoint show one connected feed fitting"):
		return false
	facts.raised_starter_belt = {"press": press, "span": belt.entity,
		"foundations": state.foundations.size()}
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		opening._select_tool("inspect")
		if not _expect(await _capture_actor_area(capture_prefix + "-raised-belt-actor.png",
				Vector3(5.9, 2.55, 6.6))
			and await _capture_press_context_side(capture_prefix + "-raised-belt-side.png",
				Vector3(6.0, 2.2, 6.6))
			and await _capture_press_standing_approach(capture_prefix + "-raised-belt-standing.png",
				Vector3(4.95, 2.6175, 6.6)),
			"Retain the raised workbed and belt from the side and standing-height approach"):
			return false
	return true

func _arrival_starter_assembly_run(capture_prefix: String) -> void:
	var raised_snap := mode in ["arrival-raised-starter-snap", "arrival-raised-starter-belt"]
	var inventory = opening.building_hotbar
	var start: Dictionary = opening.model.projection()
	if not _expect((raised_snap or start.first_plate_unlock) and start.workshop_completed_actors.is_empty()
			and inventory.slots.all(func(slot: String) -> bool: return slot.is_empty()),
			"The native arrival starts with an empty hotbar and its expected plate gate"):
		return
	inventory.open_catalog()
	if not _expect(inventory.recipe_buttons.has("component:anvil")
			and inventory.recipe_buttons.has("component:flat_head")
			and inventory.recipe_buttons.has("component:wooden_slide")
			and inventory.recipe_buttons.has("component:hand_crank")
			and (raised_snap or (not inventory.recipe_buttons.has("component:wooden_cog")
				and not inventory.recipe_buttons.has("component:receiver_tray")
				and inventory.context_label.text.contains("press with a hand crank")
				and not inventory.context_label.text.contains("anvil, flat head"))),
			"The ordinary inventory offers press recipes for this route"):
		return
	for recipe: Dictionary in [
		{"kind": "anvil", "name": "Anvil"},
		{"kind": "flat_head", "name": "Flat pressing head"},
		{"kind": "wooden_slide", "name": "Wooden slide"},
		{"kind": "hand_crank", "name": "Hand crank"}]:
		var key: String = "component:" + recipe.kind
		var tile: Button = inventory.recipe_buttons[key]
		var name_label: Label = inventory.recipe_names[key]
		var cost_label: Label = inventory.recipe_costs[key]
		var native_cost: Dictionary = start.component_recipes[recipe.kind]
		if not _expect(tile.icon != null and tile.focus_mode == Control.FOCUS_ALL
				and name_label.is_visible_in_tree() and name_label.text == recipe.name
				and Rect2(Vector2.ZERO, tile.custom_minimum_size).encloses(name_label.get_rect())
				and cost_label.text == "%dT · %dCu" % [native_cost.timber, native_cost.copper]
				and Rect2(Vector2.ZERO, tile.custom_minimum_size).encloses(cost_label.get_rect()),
				"The %s icon shows a readable name and its native projected cost." % recipe.kind):
			return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(
				capture_prefix + "-starter-catalog.png") == OK,
				"Retain the first-plate starter catalog at 1280x800"):
			return
		root.size = Vector2i(900, 600)
		inventory._place_catalog()
		await process_frame
		await RenderingServer.frame_post_draw
		if not _expect(Rect2i(Vector2i.ZERO, root.size).encloses(
				Rect2i(inventory.catalog.position, inventory.catalog.size))
				and root.get_texture().get_image().save_png(
					capture_prefix + "-starter-catalog-narrow.png") == OK,
				"Retain the first-plate starter catalog inside a 900x600 window"):
			return
		root.size = Vector2i(1280, 800)
	inventory.catalog.hide()
	if not raised_snap:
		var early: Dictionary = _issue({"action": "craft_component",
			"entity": str(start.fabrication_hub.id), "component": "wooden_cog"})
		if not _expect(not early.get("accepted", false) and early.get("reason") == "first_plate_required"
				and opening.model.projection().cargo == start.cargo,
				"A direct cog recipe remains locked without spending the initial finite stock"):
			return
	if not await _approach(Vector2(6.0, 3.45)):
		return
	for index in range(7 if raised_snap else 5):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 3.3), Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	for index in range(6 if mode == "arrival-blocked-feed-cue" else 4):
		if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
			return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	for kind in ["anvil", "flat_head", "wooden_slide", "hand_crank"]:
		if not _press_inventory_recipe("component:" + kind, str(start.fabrication_hub.id)):
			return
	if mode == "arrival-blocked-feed-cue" and not _press_inventory_recipe(
			"component:anvil", str(start.fabrication_hub.id)):
		return
	if not _expect(opening.model.projection().cargo.P.raw == 1
			and opening.model.projection().cargo.P.timber == (2 if raised_snap else 0),
			"Finite shaping spends two copper for the anvil, one for its head, and five timber for the slide and crank"):
		return
	if raised_snap:
		if not _press_inventory_recipe("foundation", str(start.fabrication_hub.id)):
			return
		opening._select_tool("foundation")
		opening._world_click(Vector2i(3, 4))
		if not _expect(opening.model.projection().foundations.values().any(func(floor: Variant) -> bool:
			return floor.cell == [3, 4] and floor.level == OpeningGeometry.HEIGHT_DENOMINATOR),
			"The starter route places a raised foundation through its ordinary build tool"):
			return
	if not await _approach(Vector2(4.95, 4.95)):
		return
	var fitted: Dictionary = {}
	var rise := OpeningGeometry.HEIGHT_DENOMINATOR if raised_snap else 0
	var press_x := 12 if raised_snap else 8
	var press_z := 16 if raised_snap else 12
	var press_cell := Vector2i(3, 4) if raised_snap else Vector2i(2, 3)
	for part in [{"kind": "anvil", "center": [press_x, rise, press_z]},
			{"kind": "flat_head", "center": [press_x, rise + 1, press_z]},
			{"kind": "wooden_slide", "center": [press_x, rise + 2, press_z]}]:
		if not _select_inventory_item("component:" + part.kind):
			return
		var prior: Dictionary = opening.model.projection().placed_components
		if part.kind == "anvil" and raised_snap:
			opening.distance = 0.0
			opening._update_camera()
			var floor_target := Vector3(4.95, 1.55, 6.6)
			var floor_direction: Vector3 = (floor_target - opening.camera.global_position).normalized()
			opening.orbit_yaw = atan2(-floor_direction.x, -floor_direction.z)
			opening.orbit_pitch = asin(clampf(-floor_direction.y, -1.0, 1.0))
			opening._update_camera()
			await physics_frame
			var floor_screen: Vector2 = opening._pointed_screen_position()
			var floor_pointed: String = opening._screen_entity(floor_screen)
			var floor_cell: Vector2i = opening._screen_cell(floor_screen)
			opening._refresh_component_preview()
			if not _expect(floor_cell == Vector2i(3, 4)
					and opening._component_place_center(floor_cell, floor_pointed) == part.center
					and opening.component_preview.visible and not opening.component_preview_blocked,
					"The actor-eye foundation pick shows a clear, floor-seated anvil ghost"):
				return
			if event_route_pointer:
				await _ordinary_left_click(floor_screen)
				event_route_pointer_placements += 1
			else:
				opening._world_click(floor_cell, floor_pointed)
		elif part.kind == "anvil":
			opening.component_nudge_active = true
			opening.component_nudge_center = part.center.duplicate()
			opening._world_click(press_cell)
			opening.component_nudge_active = false
			opening.component_nudge_center.clear()
		else:
			var lower_id: String = fitted.anvil if part.kind == "flat_head" else fitted.flat_head
			var hit := await _aim_actor_at_component(lower_id)
			var screen: Vector2 = opening._pointed_screen_position()
			var pointed: String = opening._screen_entity(screen)
			opening._refresh_component_preview()
			opening._refresh_placement_options()
			if not _expect((pointed == lower_id or part.kind == "wooden_slide"
					and pointed == fitted.anvil) and hit.get("collider") != null
					and absf(hit.get("normal", Vector3.UP).y) < 0.5
					and opening._component_place_center(opening._screen_cell(screen), pointed) == part.center
					and opening.component_preview.visible and not opening.component_preview_blocked
					and opening.placement_options_panel.position.y <= 18.0
					and opening.status_label.text.contains(
						"Aim at the anvil" if part.kind == "flat_head" else "flat head")
					and opening.placement_options_hint.text.contains(
						"Aim at the anvil" if part.kind == "flat_head" else "flat head"),
					"The standing worker points at the lower part side and sees a reachable fitted %s ghost: %s" %
					[part.kind, str({"pointed": pointed, "lower": lower_id,
						"normal": hit.get("normal", Vector3.UP),
						"center": opening._component_place_center(opening._screen_cell(screen), pointed),
						"preview": opening.component_preview.visible,
						"blocked": opening.component_preview_blocked,
						"hint": opening.status_label.text})]):
				return
			if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
				await process_frame
				await RenderingServer.frame_post_draw
				if not _expect(root.get_texture().get_image().save_png(
						capture_prefix + "-" + part.kind + "-side-ghost.png") == OK,
						"Retain the actor-eye fitted %s ghost while aiming at its lower part" % part.kind):
					return
				if part.kind == "flat_head":
					root.size = Vector2i(900, 600)
					await process_frame
					opening._refresh_component_preview()
					opening._refresh_placement_options()
					if not _expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
							opening.placement_options_panel.get_global_rect())
							and opening.component_preview.visible,
							"The elevated component cue and ghost remain visible in a narrow window"):
						return
					await RenderingServer.frame_post_draw
					if not _expect(root.get_texture().get_image().save_png(
							capture_prefix + "-flat_head-narrow-ghost.png") == OK,
							"Retain the narrow actor-eye head ghost and elevated cue"):
						return
					root.size = Vector2i(1280, 800)
					await process_frame
					opening._refresh_component_preview()
					opening._refresh_placement_options()
			if part.kind == "flat_head":
				var before_refusal: Dictionary = opening.model.projection()
				var refused := _issue({"action": "place_component", "component": part.kind,
					"center": [press_x, rise, press_z]})
				var after_refusal: Dictionary = opening.model.projection()
				if not _expect(not refused.get("accepted", false) and refused.get("reason") == "occupied"
						and after_refusal.cargo == before_refusal.cargo
						and after_refusal.placed_components == before_refusal.placed_components
						and opening.component_preview.visible and not opening.component_preview_blocked,
						"Native refuses a head at the occupied anvil center without spending it; the fitted ghost stays clear: " + str(refused)):
					return
			if event_route_pointer:
				if part.kind == "flat_head":
					var blocked_before: Dictionary = _construction_custody()
					opening._open_pause_menu()
					if not _expect(opening.pause_menu.visible,
							"Pause menu opens over the aimed head placement"):
						return
					await _ordinary_left_click(screen)
					if not _expect(_construction_custody() == blocked_before,
							"A left click over the pause menu cannot place the held head"):
						return
					event_route_pointer_suppressed += 1
					await _ordinary_key(KEY_ESCAPE)
					if not _expect(not opening.pause_menu.visible,
							"Escape closes the pause menu before placement"):
						return
				await _ordinary_left_click(screen)
				event_route_pointer_placements += 1
			else:
				opening._world_click(opening._screen_cell(screen), pointed)
		var after: Dictionary = opening.model.projection().placed_components
		if not _expect(after.size() == prior.size() + 1 and after.values().any(
				func(placed: Variant) -> bool: return placed.component == part.kind and placed.center == part.center),
				"The physical worker places the %s on its shared-grid socket" % part.kind):
			return
		for id: String in after:
			if not prior.has(id):
				fitted[part.kind] = id
	var assembled: Dictionary = opening.model.projection()
	var presses: Array = assembled.get("sliding_press_assemblies", [])
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless" \
			and presses.size() == 1 and presses[0].status == "ready":
		opening._select_tool("inspect")
		var workbed: Dictionary = assembled.placed_components[fitted.anvil].occupied
		var workbed_center: Array = workbed.center
		var workbed_half: Array = workbed.half
		var context_frame := "-raised-assembled-context.png" if raised_snap else "-assembled-context.png"
		if not _expect(await _capture_actor_area(capture_prefix + context_frame,
					Vector3(float(workbed_center[0]), float(workbed_center[1])
						+ float(workbed_half[1]) + 0.35, float(workbed_center[2]))),
			"Retain the complete player-built press and neighboring worksite at actor eye"):
			return
		var slide_body: Dictionary = assembled.placed_components[fitted.wooden_slide].occupied
		var bottom_y: float = float(workbed_center[1]) - float(workbed_half[1])
		var top_y: float = float(slide_body.center[1]) + float(slide_body.half[1])
		var side_frame := "-raised-assembled-side.png" if raised_snap else "-assembled-side.png"
		if not _expect(await _capture_press_context_side(capture_prefix + side_frame,
					Vector3(float(workbed_center[0]), (bottom_y + top_y) * 0.5,
						float(workbed_center[2]))),
			"Retain the foundation, whole press and neighboring worksite in one passive side view"):
			return
	if raised_snap:
		if not _expect(presses.size() == 1 and presses[0].status == "ready"
				and presses[0].parts.anvil == fitted.anvil
				and presses[0].parts.head == fitted.flat_head
				and presses[0].parts.slide == fitted.wooden_slide,
				"The actor-eye raised starter snaps form one native-ready sliding press"):
			return
		facts.raised_starter_parts = fitted
		if mode == "arrival-raised-starter-belt":
			if not await _arrival_raised_starter_belt_context(capture_prefix, fitted):
				return
		_record("pass")
		return
	if not _expect(presses.size() == 1 and presses[0].status == "ready"
			and presses[0].get("auto_route", false)
			and presses[0].get("auto_feed", {}).get("entry", []) == [press_x - 1, 0, press_z]
			and presses[0].get("auto_feed", {}).get("exit", []) == [press_x + 1, 0, press_z]
			and assembled.foundations.values().any(func(floor: Variant) -> bool:
				return floor.cell == [press_cell.x, press_cell.y] and floor.level == 0)
			and presses[0].parts.anvil == fitted.anvil
			and presses[0].parts.head == fitted.flat_head
			and presses[0].parts.slide == fitted.wooden_slide
			and assembled.workshop_completed_actors.is_empty()
			and assembled.cargo.P.raw == 1,
			"An actor-built anvil, separate head and integral slide form one ready native geometry while the plate gate stays locked"):
		return
	if mode == "arrival-blocked-feed-cue":
		if not _select_inventory_item("component:anvil"):
			return
		var prior_blocker: Dictionary = opening.model.projection().placed_components
		opening.component_nudge_active = true
		opening.component_nudge_center = [press_x - 1, 0, press_z]
		opening._world_click(press_cell)
		opening.component_nudge_active = false
		opening.component_nudge_center.clear()
		var obstructed: Dictionary = opening.model.projection()
		var blocker_id := ""
		for id: String in obstructed.placed_components:
			if not prior_blocker.has(id):
				blocker_id = id
		var blocked_press := false
		for press: Dictionary in obstructed.sliding_press_assemblies:
			blocked_press = blocked_press or (press.get("anvil") == fitted.anvil
				and press.get("status") == "blocked_feed")
		if not _expect(not blocker_id.is_empty()
				and blocked_press
				and opening.goal_text.contains("Clear an X-side feed path [F]")
				and not opening.goal_text.contains("Craft and place"),
				"A physically placed side obstruction produces the native blocked-feed status and recovery cue"):
			return
		opening._open_object_menu_for(str(fitted.anvil))
		if not _expect(opening.object_menu.visible
				and opening.arrival_assembly_controls.press_status.text ==
				"No clear through-feed route. Close [Esc], press F, then click the blocking part.",
			"The native blocked route gives the E menu a removal cue that names its keyboard context"):
			return
		var before_feed_key: int = int(opening.model.projection().order)
		var feed_key := InputEventKey.new()
		feed_key.keycode = KEY_F
		feed_key.pressed = true
		opening._input(feed_key)
		if not _expect(opening.object_menu.visible
				and int(opening.model.projection().order) == before_feed_key,
			"F in the blocked E menu cannot remove the blocker or feed a closed route"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-blocked-menu.png") == OK,
				"Retain the blocked native press menu in a passive frame"):
				return
		var close_key := InputEventKey.new()
		close_key.keycode = KEY_ESCAPE
		close_key.pressed = true
		opening._input(close_key)
		await process_frame
		opening._unhandled_input(feed_key)
		if not _expect(not opening.object_menu.visible and opening.mode == "deconstruct",
			"Escape then F selects the ordinary removal tool outside the E menu"):
			return
		if not _expect(_issue({"action": "reclaim_component", "entity": blocker_id}).get("accepted", false)
				and opening.model.projection().sliding_press_assemblies[0].status == "ready"
				and opening.goal_text.contains("Open the fitted press [E]"),
				"Reclaiming the obstruction restores the native ready feed route and first-plate cue"):
			return
		opening._open_object_menu_for(str(fitted.anvil))
		if not _expect(opening.arrival_assembly_controls.press_status.text.contains("ready"),
			"Reopening E after removing the blocker shows the restored clear feed route"):
			return
		_record("pass")
		return
	if not _select_inventory_item("component:hand_crank"):
		return
	opening.component_nudge_active = true
	opening.component_nudge_center = [press_x + 1, rise + 2, press_z]
	opening._refresh_component_preview()
	if not _expect(opening.component_preview.visible and not opening.component_preview_blocked
			and absf(opening.component_preview.rotation.y) < 0.001,
			"The east slide input exposes an outward fitted-crank preview"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		var preview_position: Array = assembled.placed_components[fitted.wooden_slide].position
		if not _expect(await _capture_actor_area(capture_prefix + "-crank-preview-east.png",
				Vector3(float(preview_position[0]) + OpeningGeometry.HEIGHT_STEP,
					float(preview_position[1]), float(preview_position[2]))),
				"Retain the east input preview in the ordinary scene"):
			return
	opening.component_nudge_center = [press_x - 1, rise + 2, press_z]
	opening._refresh_component_preview()
	if not _expect(opening.component_preview.visible and not opening.component_preview_blocked
			and absf(absf(opening.component_preview.rotation.y) - PI) < 0.001,
			"The west slide input visibly reverses the crank fitting"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		var preview_position: Array = assembled.placed_components[fitted.wooden_slide].position
		if not _expect(await _capture_actor_area(capture_prefix + "-crank-preview-west.png",
				Vector3(float(preview_position[0]) - OpeningGeometry.HEIGHT_STEP,
					float(preview_position[1]), float(preview_position[2]))),
				"Retain the west input preview in the ordinary scene"):
			return
	opening.component_nudge_center = [press_x - 1, rise + 2, press_z]
	opening._world_click(press_cell, fitted.wooden_slide)
	opening.component_nudge_active = false
	opening.component_nudge_center.clear()
	var attached: Dictionary = opening.model.projection()
	if not _expect(attached.crank_items.values().any(func(item: Variant) -> bool:
			return item.attached_to == fitted.wooden_slide and item.port == [press_x - 1, rise + 2, press_z]),
			"The ordinary component tool fits the finite crank at the west input for an east outlet"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		var slide_position: Array = attached.placed_components[fitted.wooden_slide].position
		if not _expect(await _capture_actor_area(capture_prefix + "-crank-fitted.png",
				Vector3(float(slide_position[0]) - OpeningGeometry.HEIGHT_STEP,
					float(slide_position[1]), float(slide_position[2]))),
				"Retain the fitted exterior crank in the ordinary scene view"):
			return
		if "--shaft-clip-probe" in OS.get_cmdline_user_args() and not _expect(
				await _capture_slide_shaft(str(fitted.wooden_slide), capture_prefix + "-shaft-close.png"),
				"Retain the fitted slide shaft at a fixed close view"):
			return
	if mode == "arrival-first-plate":
		var crank_id := ""
		for id: String in attached.crank_items:
			if attached.crank_items[id].get("attached_to") == fitted.wooden_slide:
				crank_id = id
		if not _expect(not crank_id.is_empty(), "The fitted slide keeps its finite crank identity"):
			return
		opening._select_tool("inspect")
		if not await _approach_points([Vector2(4.95, 3.3), Vector2(1.65, 3.3),
				Vector2(1.65, 4.95)]):
			return
		var crank_hit := await _aim_actor_at_crank(crank_id)
		opening._refresh_pointed_summary()
		if not _expect(crank_hit.get("collider") != null and opening._pointed_crank() == crank_id
				and opening.pointed_summary.visible
				and opening.pointed_detail.text.contains("Hold E"),
			"A standing worker can point at the fitted exterior crank and read its direct hold cue"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-crank-world-cue.png") == OK,
				"Retain the actor-eye direct crank cue before operating it"):
				return
		var before_direct: Dictionary = opening.model.projection()
		var press_key := InputEventKey.new()
		press_key.keycode = KEY_E
		press_key.pressed = true
		opening._unhandled_input(press_key)
		var after_direct: Dictionary = opening.model.projection()
		var focused_world_input: bool = int(after_direct.order) == int(before_direct.order) + 1
		if not focused_world_input:
			if not _expect(not DisplayServer.window_is_focused()
					and after_direct.order == before_direct.order
					and opening.held_crank.is_empty() and not opening.object_menu.visible,
				"An unfocused passive window refuses E without leaving a held source"):
				return
			var visual_pulse: Dictionary = opening.issue({"action": "operate_hand_crank", "entity": crank_id})
			after_direct = opening.model.projection()
			if not _expect(visual_pulse.get("accepted", false),
				"A confirmed native pulse can still supply the passive motion capture"):
				return
		facts["crank_visual_input"] = "focused_world_e" if focused_world_input else "native_after_unfocused_e"
		if not _expect(after_direct.order == before_direct.order + 1
				and after_direct.slide_phases[fitted.wooden_slide].subticks >
					before_direct.slide_phases[fitted.wooden_slide].subticks
				and (opening.held_crank == crank_id if focused_world_input else opening.held_crank.is_empty())
				and not opening.object_menu.visible,
			"The direct native crank pulse drives the unloaded slide once without opening a machine menu"):
			return
		var rotor: Node3D = opening.transmission_presenter._crank_rotors.get(crank_id)
		var initial_angle: float = rotor.rotation.x if rotor != null else NAN
		await create_timer(0.15).timeout
		if not _expect(rotor != null and absf(wrapf(rotor.rotation.x - initial_angle, -PI, PI)) > 0.1,
			"The accepted native pulse visibly turns the fitted arm around its spindle"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-crank-world-turn.png") == OK,
				"Retain a mid-pulse actor-eye crank motion pose"):
				return
		var release_key := InputEventKey.new()
		release_key.keycode = KEY_E
		release_key.pressed = false
		opening._input(release_key)
		if not _expect(opening.held_crank.is_empty(), "Releasing E ends the direct crank hold"):
			return
	var panel = opening.arrival_assembly_controls
	if mode == "arrival-first-plate":
		opening._open_object_menu_for(fitted.anvil)
		if not _expect(opening.object_menu.visible and panel.press_section.is_visible_in_tree()
				and panel.get_node_or_null("SlideCrankPort") == null
				and panel.inventory_section.visible and not panel.feed_button.visible,
			"The physical actor opens a ready three-part sliding press with workbed inventory"):
			return
	else:
		var prior_phase: Dictionary = opening.model.projection().slide_phases[fitted.wooden_slide]
		var slide_crank_id := ""
		for id: String in opening.model.projection().crank_items:
			if opening.model.projection().crank_items[id].get("attached_to") == fitted.wooden_slide:
				slide_crank_id = id
		if not _expect(not slide_crank_id.is_empty(),
				"The slide retains the fitted exterior crank before an unloaded turn"):
			return
		if not await _pulse_fitted_world_crank(slide_crank_id):
			return
		var cycled: Dictionary = opening.model.projection()
		if not _expect(cycled.slide_phases[fitted.wooden_slide].subticks > prior_phase.subticks
				and cycled.crank_items.values().any(func(item: Variant) -> bool:
					return item.attached_to == fitted.wooden_slide and item.port == [press_x - 1, rise + 2, press_z])
				and cycled.workshop_completed_actors.is_empty(),
			"The worker turns the fitted crafted crank through the slide's integral input"):
			return
	var route: Dictionary = presses[0].auto_feed
	var feed: Dictionary = {}
	if mode == "arrival-first-plate":
		opening._open_object_menu_for(fitted.wooden_slide)
		if not _expect(panel.press_section.is_visible_in_tree()
				and opening.object_menu_target == fitted.wooden_slide
				and panel.reclaim_button.is_visible_in_tree()
				and not panel.inventory_drag("player_raw").is_empty()
				and not panel.route_choice.visible
				and panel.auto_route_cue.visible
				and panel.auto_route_cue.text.contains("WEST → EAST")
				and not panel.press_status.text.contains("clear feed routes")
				and not panel.cycle_feed_route(),
			"The slide's E panel offers a native Auto route and carried blank transfer without a side choice"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-auto-route-normal.png") == OK,
					"Retain the actual first-plate Auto route menu at 1280x800"):
				return
			root.size = Vector2i(900, 600)
			opening._fit_object_menu()
			await process_frame
			await RenderingServer.frame_post_draw
			if not _expect(Rect2i(Vector2i.ZERO, root.size).encloses(
					Rect2i(opening.object_menu.position, opening.object_menu.size))
					and panel.auto_route_cue.is_visible_in_tree()
					and root.get_texture().get_image().save_png(
						capture_prefix + "-auto-route-narrow.png") == OK,
					"Retain the actual first-plate Auto route menu inside 900x600"):
				return
			root.size = Vector2i(1280, 800)
			opening._fit_object_menu()
		panel.inventory_slots.player_raw.pressed.emit()
	else:
		feed = _issue({"action": "feed_press", "entity": fitted.anvil, "entry": route.entry})
	var loaded: Dictionary = opening.model.projection()
	if not _expect((mode == "arrival-first-plate" or feed.get("accepted", false))
			and loaded.cargo.P.raw == 0
			and loaded.sliding_press_assemblies[0].selected_exit == route.exit
			and loaded.workshop_completed_actors.is_empty(),
			"The worker feeds the last finite blank and retains its chosen outlet without unlocking parts"):
		return
	if mode == "arrival-first-plate":
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-press-controls.png") == OK,
					"Retain the loaded slide workbed and native Auto route"):
				return
		await _ordinary_key(KEY_ESCAPE)
		var loaded_crank_id := ""
		for id: String in opening.model.projection().crank_items:
			if opening.model.projection().crank_items[id].get("attached_to") == fitted.wooden_slide:
				loaded_crank_id = id
		facts["loaded_workbed_close"] = {"object_menu_visible": opening.object_menu.visible,
			"pause_menu_visible": opening.pause_menu.visible,
			"window_focused": DisplayServer.window_is_focused()}
		if not _expect(not opening.object_menu.visible and not opening.pause_menu.visible
				and not loaded_crank_id.is_empty(),
			"One Escape closes the loaded workbed without opening Worksite pause"):
			return
		var loaded_hit := await _aim_actor_at_crank(loaded_crank_id)
		opening._refresh_pointed_summary()
		if not _expect(loaded_hit.get("collider") != null
				and opening._pointed_crank() == loaded_crank_id
				and opening.pointed_detail.text.contains("Hold E"),
			"The loaded slide still offers the same actor-eye direct crank hold"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-loaded-crank-cue.png") == OK,
				"Retain the loaded workpiece and direct exterior crank cue"):
				return
		var direct_world_hold: bool = DisplayServer.get_name() != "headless" \
			and DisplayServer.window_is_focused()
		facts["plate_drive_input"] = "viewport_world_e_hold" if direct_world_hold else "native_unfocused_passive"
		var hold_key := InputEventKey.new()
		hold_key.keycode = KEY_E
		hold_key.physical_keycode = KEY_E
		hold_key.pressed = true
		var prior_held_order: int = int(opening.model.projection().order)
		var focus_owner: Control = root.gui_get_focus_owner()
		facts["plate_drive_before_hold"] = {"window_focused": DisplayServer.window_is_focused(),
			"can_control": opening._can_control_character(), "mode": opening.mode,
			"pointed_crank": opening._pointed_crank(), "held_crank": opening.held_crank,
			"object_menu_visible": opening.object_menu.visible,
			"pause_menu_visible": opening.pause_menu.visible,
			"focus_owner": str(focus_owner.get_path()) if focus_owner != null else ""}
		if direct_world_hold:
			root.push_input(hold_key)
			await process_frame
			facts["plate_drive_after_press"] = {"order_delta":
				int(opening.model.projection().order) - prior_held_order,
				"held_crank": opening.held_crank,
				"object_menu_visible": opening.object_menu.visible,
				"pause_menu_visible": opening.pause_menu.visible}
		var formed: Dictionary = {}
		var hold_progressed := true
		var held_pulses := 0
		for turn_index in range(64):
			if direct_world_hold and turn_index > 0:
				await create_timer(OpeningScene.STEP_SECONDS + 0.03).timeout
			elif not direct_world_hold:
				var passive_pulse: Dictionary = opening.issue({
					"action": "operate_hand_crank", "entity": loaded_crank_id})
				if not passive_pulse.get("accepted", false):
					hold_progressed = false
					break
			var current_order: int = int(opening.model.projection().order)
			if current_order <= prior_held_order or (direct_world_hold
					and opening.held_crank != loaded_crank_id):
				hold_progressed = false
				break
			held_pulses += current_order - prior_held_order
			prior_held_order = current_order
			for drop: Dictionary in opening.model.projection().dropped_material:
				if drop.center == presses[0].work_center and int(drop.get("products", 0)) == 1:
					formed = drop
					break
			if not formed.is_empty():
				break
		if direct_world_hold:
			var release_hold: InputEventKey = hold_key.duplicate()
			release_hold.pressed = false
			root.push_input(release_hold)
			await process_frame
		facts["plate_drive_pulses"] = held_pulses
		var before_pickup: Dictionary = opening.model.projection()
		if not _expect(hold_progressed and held_pulses > 0 and opening.held_crank.is_empty()
				and not formed.is_empty()
				and before_pickup.cargo.P.products == 0
				and before_pickup.workshop_completed_actors.is_empty()
				and before_pickup.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The held exterior crank conserves mass and forms one plate on the native workbed"):
			return
		var pickup_cue := "Plate and offcut on the workbed. Aim at the offcuts and press E to collect both."
		if not _expect(opening.goal_text.contains(pickup_cue)
				and opening.manager_log_current.text.ends_with(pickup_cue),
				"The first-shift cue and replayable log name the supported workbed pickup"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			opening._toggle_manager_log()
			await process_frame
			await RenderingServer.frame_post_draw
			if not _expect(opening.manager_log_layer.visible
					and root.get_texture().get_image().save_png(
						capture_prefix + "-workbed-log-cue.png") == OK,
				"Retain the supported workbed pickup instruction in the surrounding worksite"):
				return
			opening._toggle_manager_log()
		var work_point := Vector2(float(press_x) * OpeningGeometry.HEIGHT_STEP,
			float(press_z) * OpeningGeometry.HEIGHT_STEP)
		if not await _approach(work_point + Vector2(1.1, 1.05)):
			return
		opening._select_tool("inspect")
		var plate_visual: Node3D = opening.transmission_presenter.get_node_or_null("LoosePlateStack")
		var offcut_visual: Node3D = plate_visual.get_node_or_null("CopperOffcuts") if plate_visual != null else null
		if not _expect(offcut_visual != null,
			"The native plate and offcut have a visible workbed pickup target"):
			return
		opening.distance = 0.0
		opening._update_camera()
		var target_direction: Vector3 = (offcut_visual.global_position - opening.camera.global_position).normalized()
		opening.orbit_yaw = atan2(-target_direction.x, -target_direction.z)
		opening.orbit_pitch = asin(clampf(-target_direction.y, -1.0, 1.0))
		opening._update_camera()
		await physics_frame
		var pointed_drop: Dictionary = opening._screen_loose_material(opening._pointed_screen_position())
		if not _expect(pointed_drop == formed and not opening.object_menu.visible,
			"The standing worker points at the visible offcut without opening a press menu"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-workbed-pickup-cue.png") == OK,
				"Retain the supported plate, visible offcut and pickup cue in the worksite"):
				return
		await _ordinary_key(KEY_E)
		var completed: Dictionary = opening.model.projection()
		if not _expect(completed.cargo.P.products == 1 and completed.cargo.P.offcuts == 1
				and completed.dropped_material.is_empty()
				and completed.workshop_completed_actors.has("P")
				and completed.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
				and opening.objective_title.contains("COMPLETE"),
			"Pointed E pickup carries the plate and offcut and completes the inventory milestone"):
			return
		inventory.open_catalog()
		if not _expect(inventory.recipe_buttons.has("component:wooden_cog")
				and inventory.recipe_buttons.has("component:receiver_tray")
				and inventory.recipe_buttons.has("foundation")
				and inventory.material_buttons.products.visible
				and inventory.material_counts.products.text == "1",
				"The exact formed plate enters the full carried inventory and reveals advanced recipes"):
			return
		if not _expect(inventory.recipe_focus == "collector"
				and inventory.collector_focus_button.visible
				and inventory.recipe_buttons["component:wooden_frame"].visible
				and inventory.recipe_buttons["component:receiver_tray"].visible
				and not inventory.recipe_buttons["component:anvil"].visible,
			"The native first-plate milestone opens a focused collector project"):
			return
		inventory.all_focus_button.grab_focus()
		await process_frame
		if not _expect(inventory.focus_description.text.contains("All parts")
				and inventory.all_focus_button.accessibility_name == "All unlocked recipes",
			"Keyboard focus describes the route to every earned recipe"):
			return
		inventory.all_focus_button.pressed.emit()
		if not _expect(inventory.recipe_buttons["component:anvil"].visible
				and inventory.recipe_buttons["foundation"].visible,
			"All parts reveals the complete native-unlocked recipe list"):
			return
		inventory.collector_focus_button.pressed.emit()
		inventory.collector_focus_button.grab_focus()
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-unlocked-catalog.png") == OK,
					"Retain the focused collector group after native plate pickup"):
				return
			var original_size: Vector2i = root.size
			root.size = Vector2i(900, 600)
			for _frame in range(3):
				await process_frame
			inventory._place_catalog()
			await RenderingServer.frame_post_draw
			var narrow_rect := Rect2(Vector2(inventory.catalog.position),
				Vector2(inventory.catalog.size))
			var narrow_capture: Error = root.get_texture().get_image().save_png(
				capture_prefix + "-unlocked-catalog-narrow.png")
			var narrow_visible: bool = inventory.catalog.is_visible_in_tree()
			if not _expect(narrow_visible
					and inventory.recipe_focus == "collector"
					and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(narrow_rect)
					and narrow_capture == OK,
					"The ordinary collector recipes fit the narrow actor viewport: " +
				str({"popup": narrow_rect, "viewport": root.size,
					"visible": narrow_visible, "recipe_focus": inventory.recipe_focus})):
				return
			root.size = original_size
			await process_frame
			inventory._place_catalog()
		inventory.catalog.hide()
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		var frame_name := "-first-plate.png" if mode == "arrival-first-plate" else "-starter-press.png"
		if not _expect(await _capture_actor_area(capture_prefix + frame_name,
				Vector3(float(press_x) * OpeningGeometry.HEIGHT_STEP, 1.1,
					float(press_z) * OpeningGeometry.HEIGHT_STEP)),
				"Retain the actor-built sliding press in an ordinary passive view"):
			return
	opening.configure_save_slot(destination + ".worksite")
	var saved: Dictionary = opening._save_worksite()
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"The three-part unfinished worksite retains exact finite custody and a valid native checkpoint"):
		return
	_record("pass")

func _arrival_mature_tree_run(capture_prefix: String) -> void:
	var surface = load("res://opening/site_surface.gd")
	var initial: Dictionary = opening.model.projection()
	var specs: Array[Dictionary] = surface.fir_specs() + surface.broadleaf_specs()
	if not _expect(specs.size() == 8 and opening.mature_tree_nodes.size() == 8,
			"Every mature bank tree has one native-backed pick identity"):
		return
	for spec in specs:
		var source: Dictionary = initial.hand_sources.get(spec.id, {})
		var body: StaticBody3D = opening.mature_tree_nodes[spec.id]
		var anchor := Vector3(float(source.get("position", [0, 0, 0])[0]), 0.0,
			float(source.get("position", [0, 0, 0])[2]))
		if not _expect(source.get("kind") == "tree" and source.get("remaining") == 8
				and Vector2(anchor.x - spec.center.x, anchor.z - spec.center.z).length() <= 0.35
				and body.get_meta("hand_source") == spec.id
				and body.get_node("PickShape").shape is ConcavePolygonShape3D,
				"The visible root, native finite source and physical picker agree for " + spec.id):
			return
	var broadleaf: Dictionary = surface.broadleaf_specs()[0]
	if not await _approach_points([Vector2(6.0, 3.0), Vector2(6.0, 0.0),
			Vector2(6.0, -4.0), Vector2(6.0, -8.0), Vector2(9.2, -8.0),
			Vector2(9.2, -12.0), Vector2(9.2, -15.0), Vector2(8.5, -17.0),
			Vector2(broadleaf.center.x + 1.65, broadleaf.center.z + 0.6)]):
		return
	var target: Vector3 = broadleaf.center + Vector3.UP * 1.2
	opening.distance = 0.0
	opening._update_camera()
	var direction: Vector3 = (target - opening.camera.global_position).normalized()
	opening.orbit_yaw = atan2(-direction.x, -direction.z)
	opening.orbit_pitch = asin(clampf(-direction.y, -1.0, 1.0))
	opening._update_camera()
	await physics_frame
	await process_frame
	var aim: Vector2 = root.get_visible_rect().size * 0.5
	var aimed_source: String = opening._screen_hand_source(aim)
	var aimed_summary: Dictionary = opening._pointed_summary_data(aim)
	if not _expect(aimed_source == "broadleaf_00"
			and aimed_summary.get("detail", "").contains("E Harvest"),
			"The ordinary actor-eye ray and E cue identify the reported broadleaf in native reach: %s" %
			{"source": aimed_source, "summary": aimed_summary,
				"actor": opening.actor_world.bodies.P.global_position, "tree": broadleaf.center}):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-broadleaf-standing.png", target),
				"Retain the actor-eye standing broadleaf and harvest cue"):
			return
	opening._interact_pointed()
	var started: Dictionary = opening.model.projection()
	if not _expect(started.manual_cuts.has("P") and started.manual_cuts.P.target == "broadleaf_00",
			"Ordinary E interaction starts a real timed cut on the aimed broadleaf"):
		return
	for tick in range(int(started.manual_cuts.P.duration_ticks)):
		opening.model.advance()
	opening._refresh()
	var first: Dictionary = opening.model.projection()
	if not _expect(first.hand_sources.broadleaf_00.remaining == 7 and first.cargo.P.timber == 1
			and opening.actor_world.active_woody_ids.has("broadleaf_00"),
			"The first contact transfers exactly one timber and retains standing trunk collision"):
		return
	if not _expect(_issue({"action": "set_developer_conveniences", "enabled": true}).accepted,
			"The fixture can shorten only its seven remaining finite cuts"):
		return
	for cut in range(7):
		var before: Dictionary = opening.model.projection()
		var result := _issue({"action": "harvest_source", "target": "broadleaf_00"})
		var after: Dictionary = opening.model.projection()
		if not _expect(result.get("accepted", false) and after.manual_cuts.is_empty()
				and after.hand_sources.broadleaf_00.remaining == before.hand_sources.broadleaf_00.remaining - 1
				and after.cargo.P.timber == before.cargo.P.timber + 1,
				"Fast fixture contact spends one finite broadleaf unit without a duplicate payout"):
			return
	await physics_frame
	await process_frame
	var depleted: Dictionary = opening.model.projection()
	var stump: StaticBody3D = opening.mature_tree_nodes["broadleaf_00"]
	var standing: MeshInstance3D = opening.get_node("ProductionScenery/BankBroadleaf/broadleaf_00")
	if not _expect(depleted.hand_sources.broadleaf_00.remaining == 0 and depleted.cargo.P.timber == 8
			and not standing.visible and stump.get_node("Stump").visible
			and stump.get_node("PickShape").shape is CylinderShape3D
			and not opening.actor_world.active_woody_ids.has("broadleaf_00")
			and opening.actor_world.active_woody_ids.has("broadleaf_01")
			and opening.actor_world._geometry_registered(),
			"Native depletion leaves a selectable stump, removes trunk collision and preserves its neighbor"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-broadleaf-depleted.png",
				stump.get_node("Stump").global_position),
				"Retain the actor-eye depleted broadleaf and low stump"):
			return
	if not await _approach_points([Vector2(9.2, -15.0), Vector2(9.2, -12.0),
		Vector2(10.5, -9.7)]):
		return
	var fir: Dictionary = surface.fir_specs()[3]
	var fir_target: Vector3 = fir.center + Vector3.UP * 1.0
	opening._update_camera()
	var fir_direction: Vector3 = (fir_target - opening.camera.global_position).normalized()
	opening.orbit_yaw = atan2(-fir_direction.x, -fir_direction.z)
	opening.orbit_pitch = asin(clampf(-fir_direction.y, -1.0, 1.0))
	opening._update_camera()
	await physics_frame
	await process_frame
	if not _expect(opening._screen_hand_source(aim) == "fir_03"
			and opening._pointed_summary_data(aim).get("detail", "").contains("E Harvest"),
			"The same actor-eye resource cue selects a separate mature fir"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-fir-standing.png", fir_target),
				"Retain the standing fir and its E cue"):
			return
	opening._interact_pointed()
	var fir_first: Dictionary = opening.model.projection()
	if not _expect(fir_first.hand_sources.fir_03.remaining == 7 and fir_first.cargo.P.timber == 9,
			"Aiming and pressing E on the fir transfers only its own finite timber"):
		return
	for cut in range(7):
		var before: Dictionary = opening.model.projection()
		var result := _issue({"action": "harvest_source", "target": "fir_03"})
		var after: Dictionary = opening.model.projection()
		if not _expect(result.get("accepted", false) and after.hand_sources.fir_03.remaining ==
				before.hand_sources.fir_03.remaining - 1 and after.cargo.P.timber == before.cargo.P.timber + 1,
				"Each further fir cut debits that distinct native tree once"):
			return
	await physics_frame
	await process_frame
	var fir_stump: StaticBody3D = opening.mature_tree_nodes["fir_03"]
	var fir_mesh: MeshInstance3D = opening.get_node("ProductionScenery/BankFirs/fir_03")
	if not _expect(opening.model.projection().cargo.P.timber == 16 and not fir_mesh.visible
			and fir_stump.get_node("Stump").visible
			and not opening.actor_world.active_woody_ids.has("fir_03")
			and opening.actor_world.active_woody_ids.has("fir_04")
			and opening.actor_world._geometry_registered(),
			"The mature fir also becomes a low stump with no invisible trunk collision"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-fir-depleted.png",
				fir_stump.get_node("Stump").global_position),
				"Retain the depleted fir beside its intact neighboring trees"):
			return
	opening.configure_save_slot(destination + ".worksite")
	var saved: Dictionary = opening._save_worksite()
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"The ordinary depleted tree and actor state save through native preflight"):
		return
	_record("pass")

func _arrival_mature_tree_resume_run(capture_prefix: String) -> void:
	var input := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="):
			input = argument.trim_prefix("--resume-input=")
	if not _expect(not input.is_empty() and opening.last_load_result.get("accepted", false),
			"A fresh ordinary scene reopens the saved mature-tree worksite"):
		return
	var restored: Dictionary = opening.model.projection()
	var standing: MeshInstance3D = opening.get_node("ProductionScenery/BankBroadleaf/broadleaf_00")
	var stump: StaticBody3D = opening.mature_tree_nodes["broadleaf_00"]
	if not _expect(restored.hand_sources.broadleaf_00.remaining == 0
			and restored.hand_sources.fir_03.remaining == 0 and restored.cargo.P.timber == 16
			and not standing.visible and stump.get_node("Stump").visible
			and not opening.actor_world.active_woody_ids.has("broadleaf_00")
			and not opening.actor_world.active_woody_ids.has("fir_03")
			and opening.actor_world._geometry_registered()
			and _same(opening.startup_resume_checkpoint.world, opening.model.checkpoint().world),
			"Rejoin keeps native timber custody, depleted presentation and absent trunk collision"):
		return
	var surface = load("res://opening/site_surface.gd")
	var broadleaf: Dictionary = surface.broadleaf_specs()[0]
	if not await _approach_points([Vector2(9.2, -12.0), Vector2(9.2, -15.0),
		Vector2(8.5, -17.0), Vector2(broadleaf.center.x, broadleaf.center.z)]):
		return
	if not _expect(opening.actor_world._geometry_registered(),
			"The restored actor can walk across the former trunk without an invisible collision"):
		return
	var refused: Dictionary = _issue({"action": "harvest_source", "target": "broadleaf_00"})
	if not _expect(not refused.get("accepted", true) and refused.get("reason", "") == "unavailable_source"
			and opening.model.projection().cargo.P.timber == 16,
			"A reopened depleted broadleaf cannot issue another timber unit"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-broadleaf-rejoined.png",
				stump.get_node("Stump").global_position),
				"Retain a passive view of the restored depleted broadleaf"):
			return
	_record("pass")

func _ordinary_key(code: Key, repeat: bool = false, ctrl: bool = false) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.ctrl_pressed = ctrl
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	if repeat:
		var echo_key: InputEventKey = key.duplicate()
		echo_key.echo = true
		Input.parse_input_event(echo_key)
		await process_frame
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame

func _ordinary_left_click(screen: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.position = screen
	click.global_position = screen
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await process_frame
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await process_frame

func _activate_popup_choice_with_keys(popup: PopupMenu, choice: int) -> bool:
	if not _expect(popup.visible and choice >= 0 and choice < popup.get_item_count(),
			"Keyboard activation has a visible popup and valid native offer"):
		return false
	await _ordinary_key(KEY_HOME)
	if popup.get_focused_item() < 0:
		await _ordinary_key(KEY_DOWN)
	if not _expect(popup.get_focused_item() == 0,
			"Popup keyboard navigation starts at its first native offer"):
		return false
	for step in range(choice):
		await _ordinary_key(KEY_DOWN)
	if not _expect(popup.get_focused_item() == choice,
			"Popup keyboard navigation reaches the selected native offer: %s" % str({
			"focused": popup.get_focused_item(), "choice": choice,
			"items": popup.get_item_count()})):
		return false
	await _ordinary_key(KEY_ENTER)
	event_route_loose_activations += 1
	return true

func _push_loose_from_menu(source: Array, target: Array, item_name: String) -> bool:
	if opening.object_menu.visible:
		opening.object_menu.hide()
	if opening.building_hotbar.catalog.visible:
		opening.building_hotbar.catalog.hide()
	if opening.mode == "component":
		await _ordinary_key(KEY_ESCAPE)
		if not _expect(opening.mode == "inspect" and not opening.pause_menu.visible,
				"Escape leaves channel construction before the loose-material shortcut"):
			return false
	await _ordinary_key(KEY_L, false, true)
	var controls: MenuButton = opening.loose_material_controls
	var popup: PopupMenu = controls.get_popup()
	var choice := -1
	for index in range(popup.get_item_count()):
		var offer: Dictionary = controls._offers[index]
		if offer.wire.get("from", []) == source and offer.wire.get("to", []) == target \
				and popup.get_item_text(index).contains(item_name):
			choice = index
			break
	if not _expect(choice >= 0 and controls.visible and not controls.disabled,
			"Ctrl+L offers the confirmed %s at %s for a one-cell push to %s: %s" % [
				item_name, str(source), str(target), str({"visible": controls.visible,
					"disabled": controls.disabled, "in_tree": controls.is_visible_in_tree(),
					"popup": popup.visible,
					"offers": controls._offers.size(), "items": popup.get_item_count(),
					"mode": opening.mode, "drops": opening.model.projection().dropped_material.size()})]):
		return false
	if event_route_loose:
		if not await _activate_popup_choice_with_keys(popup, choice):
			return false
	else:
		popup.id_pressed.emit(choice)
	popup.hide()
	return true

func _pickup_loose_from_menu(center: Array, item_name: String) -> bool:
	if opening.object_menu.visible:
		opening.object_menu.hide()
	if opening.building_hotbar.catalog.visible:
		opening.building_hotbar.catalog.hide()
	await _ordinary_key(KEY_L, false, true)
	var controls: MenuButton = opening.loose_material_controls
	var popup: PopupMenu = controls.get_popup()
	var choice := -1
	for index in range(popup.get_item_count()):
		var offer: Dictionary = controls._offers[index]
		if offer.wire.get("action", "") == "pickup_material" \
				and offer.wire.get("center", []) == center \
				and popup.get_item_text(index).contains(item_name):
			choice = index
			break
	if not _expect(choice >= 0 and controls.is_visible_in_tree() and not controls.disabled,
			"Ctrl+L offers recovery of the actual %s at %s" % [item_name, str(center)]):
		return false
	if event_route_loose:
		if not await _activate_popup_choice_with_keys(popup, choice):
			return false
	else:
		popup.id_pressed.emit(choice)
	popup.hide()
	return true

func _placement_ghosts_hidden() -> bool:
	return (opening.machine_preview == null or not opening.machine_preview.visible) \
		and (opening.component_preview == null or not opening.component_preview.visible) \
		and not opening.placement_options_panel.visible

func _construction_custody() -> Dictionary:
	var projection: Dictionary = opening.model.projection()
	var result := {}
	for field in ["cargo", "part_kits", "foundation_kits", "placed_components",
			"transmission_parts", "belt_spans", "foundations", "entities",
			"hand_sources", "stock", "material_mass"]:
		result[field] = projection.get(field)
	return result.duplicate(true)

func _arrival_cancel_placement_run(capture_prefix: String) -> void:
	var inventory = opening.building_hotbar
	var before: Dictionary = _construction_custody()
	if not _expect(opening.mode == "inspect" and not opening.pause_menu.visible,
			"The ordinary actor starts with no construction or pause overlay"):
		return
	inventory.open_catalog()
	if not _expect(inventory.catalog.visible and not inventory.catalog_buttons.foundation.disabled,
			"The carried foundation is available through the ordinary inventory"):
		return
	var foundation_drag: Dictionary = inventory._drag_payload("foundation")
	if not _expect(inventory.catalog_slots[0]._can_drop_data(Vector2.ZERO, foundation_drag),
			"The carried foundation can be dragged onto hotbar key 1"):
		return
	inventory.catalog_slots[0]._drop_data(Vector2.ZERO, foundation_drag)
	inventory._close_catalog()
	inventory.select_slot(0)
	await process_frame
	if not _expect(opening.mode == "foundation" and inventory.slots[0] == "foundation"
			and inventory.selected_slot == 0 and inventory.buttons[0].button_pressed,
			"Dragging and selecting the carried foundation arms its real hotbar slot"):
		return
	for tool in ["foundation", "collector", "processor", "wheel", "gear", "drive",
			"belt", "gearbox", "vertical_gearbox", "chain_drive", "component",
			"flow", "deconstruct", "pod_workshop"]:
		if tool == "deconstruct":
			await _ordinary_key(KEY_F)
		elif tool != "foundation":
			opening._select_tool(tool)
		if tool == "belt":
			opening.transmission_controls._belt_start = {"id": "pending-shaft", "pending": false}
		elif tool == "component":
			opening.component_nudge_active = true
			opening.component_nudge_center = [0, 4, 0]
		elif tool == "flow":
			opening.pending_link = "pending-machine"
		elif tool == "foundation":
			opening.foundation_area_mode = true
			var corner := Vector2i(5, 5)
			if not _expect(opening._build_cell_allowed(corner),
					"The ordinary first area corner lies on a constructable cell"):
				return
			opening._world_click(corner)
			if not _expect(opening.foundation_area_started,
					"The first foundation-area click starts one pending placement stage"):
				return
		if not _expect(opening.mode == tool and not opening.pause_menu.visible,
				"The selected %s construction operation is active before Escape" % tool):
			return
		if tool == "foundation" and not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-placement.png") == OK,
					"Retain the actual foundation placement view before Escape"):
				return
		await _ordinary_key(KEY_ESCAPE, tool == "foundation")
		if not _expect(opening.mode == "inspect" and not opening.pause_menu.visible
				and opening.transmission_controls.active_tool.is_empty()
				and opening.transmission_controls._belt_start.is_empty()
				and not opening.foundation_area_started and opening.foundation_area_start == Vector2i.ZERO
				and not opening.component_nudge_active
				and opening.component_nudge_center.is_empty() and opening.pending_link.is_empty()
				and opening.transmission_preview_point.is_empty()
				and _placement_ghosts_hidden()
				and _construction_custody() == before
				and inventory.selected_slot == -1 and not inventory.buttons[0].button_pressed
				and inventory.slots[0] == "foundation",
				"One Escape cancels %s without opening pause, reviving a ghost or changing native custody: %s" %
				[tool, {"mode": opening.mode, "pause": opening.pause_menu.visible,
					"active_tool": opening.transmission_controls.active_tool,
					"belt_start": opening.transmission_controls._belt_start,
					"area_started": opening.foundation_area_started,
					"area_start": opening.foundation_area_start,
					"nudge": opening.component_nudge_active,
					"nudge_center": opening.component_nudge_center,
					"pending_link": opening.pending_link,
					"preview_point": opening.transmission_preview_point,
					"ghosts_hidden": _placement_ghosts_hidden(),
					"custody_same": _construction_custody() == before,
					"selected_slot": inventory.selected_slot,
					"slot_pressed": inventory.buttons[0].button_pressed}]):
			return
		await process_frame
		if not _expect(_placement_ghosts_hidden()
				and _construction_custody() == before,
				"Canceled %s construction stays neutral on the next frame" % tool):
			return
		if tool == "foundation" and not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-neutral.png") == OK,
					"Retain the same scene after the foundation ghost and prompt clear"):
				return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(opening.pause_menu.visible and opening.mode == "inspect"
			and _construction_custody() == before,
			"The next Escape from neutral interaction opens the worksite menu"):
		return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(not opening.pause_menu.visible and _construction_custody() == before,
			"Escape closes the worksite menu without entering construction"):
		return
	opening._select_tool("foundation")
	inventory.open_catalog()
	if not _expect(inventory.catalog.visible and opening.mode == "foundation",
			"The catalog can open over a pending foundation operation"):
		return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(not inventory.catalog.visible and opening.mode == "foundation"
			and not opening.pause_menu.visible and _construction_custody() == before,
			"Escape closes the focused catalog while preserving the underlying construction selection"):
		return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(opening.mode == "inspect" and not opening.pause_menu.visible
			and _construction_custody() == before,
			"The next Escape cancels construction after the catalog closes"):
		return
	inventory.open_catalog()
	if not _expect(inventory.catalog.visible, "The inventory catalog opens independently of construction"):
		return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(not inventory.catalog.visible and not opening.pause_menu.visible
			and _construction_custody() == before,
			"Escape closes the focused catalog before any worksite menu"):
		return
	var floor_id := ""
	for id: String in opening.model.projection().foundations:
		if id.begins_with("pod-floor-"):
			floor_id = id
			break
	if not _expect(not floor_id.is_empty(), "The native arrival retains a pod floor for machine-menu input"):
		return
	opening._open_object_menu_for(floor_id)
	if not _expect(opening.object_menu.visible and not opening.pause_menu.visible,
			"An ordinary built floor opens the machine popup before Escape"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-machine-popup.png") == OK,
				"Retain the ordinary open machine popup"):
			return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(not opening.object_menu.visible and not opening.pause_menu.visible
			and _construction_custody() == before,
			"One ordinary Escape closes the machine popup without opening Worksite"):
		return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(opening.pause_menu.visible and _construction_custody() == before,
			"A later Escape from the closed machine popup opens Worksite"):
		return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(not opening.pause_menu.visible, "Escape resumes after the machine-popup pause route"):
		return
	opening._open_object_menu_for(floor_id)
	if not _expect(opening.object_menu.visible, "The same native floor can reopen its popup"):
		return
	# Reproduce the alternate Godot ordering: the PopupPanel hides before
	# opening.gd receives the Escape that caused the hide.
	opening.object_menu.hide()
	opening._on_object_menu_closed()
	if not _expect(opening.object_menu_target.is_empty(),
			"The popup hide callback finishes before scene input"):
		return
	var close_key := InputEventKey.new()
	close_key.keycode = KEY_ESCAPE
	close_key.pressed = true
	opening._input(close_key)
	if not _expect(not opening.object_menu.visible and not opening.pause_menu.visible
			and _construction_custody() == before,
			"The same Escape cannot open Worksite after PopupPanel hid first"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-machine-closed.png") == OK,
				"Retain the popup-closed view without Worksite"):
			return
	await process_frame
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(opening.pause_menu.visible and _construction_custody() == before,
			"A separate next-frame Escape still opens Worksite after an early popup hide"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-worksite.png") == OK,
				"Retain the distinct later-Escape Worksite view"):
			return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(not opening.pause_menu.visible and _construction_custody() == before,
			"Machine-popup Escape precedence leaves native construction custody unchanged"):
		return
	_record("pass")

func _arrival_run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if mode == "arrival-raised-starter-belt":
		deadline = Time.get_ticks_msec() + 180000
	if mode in ["arrival-belt", "arrival-belt-controls", "arrival-press-site", "arrival-belt-fed-press", "arrival-belt-fed-press-resume", "arrival-powered-press-site", "arrival-powered-press-resume", "arrival-powered-press-blocked-resume", "arrival-powered-press-release-resume", "arrival-broad-pad", "arrival-broad-drive", "arrival-broad-form", "arrival-broad-cut-resume", "arrival-channel-broad", "arrival-channel-small", "arrival-channel-broad-resume", "arrival-channel-small-resume", "arrival-craft-capacity"]:
		deadline = Time.get_ticks_msec() + 180000
	var capture_prefix := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arrival-capture-prefix="):
			capture_prefix = argument.trim_prefix("--arrival-capture-prefix=")
	if destination.is_empty() or mode not in ["arrival-mature-trees", "arrival-mature-trees-resume", "arrival-starter-assembly", "arrival-first-plate", "arrival-raised-starter-snap", "arrival-raised-starter-belt", "arrival-blocked-feed-cue", "arrival-first-plate-resume", "arrival-slide", "supplied-hardware", "arrival-press", "arrival-guide-geometry", "arrival-press-site", "arrival-belt-fed-press", "arrival-belt-fed-press-resume", "arrival-powered-press-site", "arrival-powered-press-resume", "arrival-powered-press-blocked-resume", "arrival-powered-press-release-resume", "arrival-broad-pad", "arrival-broad-drive", "arrival-broad-form", "arrival-broad-cut-resume", "arrival-channel-broad", "arrival-channel-small", "arrival-channel-broad-resume", "arrival-channel-small-resume", "arrival-raised-press", "arrival-raised-press-resume", "arrival-resume", "arrival-craft-capacity", "arrival-craft-capacity-resume", "arrival-field-craft", "arrival-foundation-craft", "arrival-foundation-craft-resume", "arrival-portable-workbench", "arrival-pod-workshop", "arrival-pod-workshop-resume", "arrival-belt", "arrival-belt-controls", "arrival-belt-resume", "arrival-cancel-placement", "arrival-reveal", "arrival-reveal-skip"] or FileAccess.file_exists(destination):
		push_error("Arrival press check requires an unused output and a declared mode")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	var advanced_fixture := mode not in ["arrival-mature-trees", "arrival-mature-trees-resume", "arrival-starter-assembly", "arrival-first-plate", "arrival-blocked-feed-cue", "arrival-first-plate-resume", "arrival-reveal", "arrival-reveal-skip"]
	# Channel command fixtures deliberately exercise developer diagnostics.
	# Ordinary players pick up pointed material with E and never issue pushes.
	opening.developer_material_tools = mode.begins_with("arrival-channel-")
	if mode in ["arrival-press-site", "arrival-belt-fed-press", "arrival-belt-fed-press-resume", "arrival-powered-press-site", "arrival-powered-press-resume", "arrival-powered-press-blocked-resume", "arrival-powered-press-release-resume", "arrival-broad-pad", "arrival-broad-drive", "arrival-broad-form", "arrival-broad-cut-resume", "arrival-channel-broad", "arrival-channel-small", "arrival-channel-broad-resume", "arrival-channel-small-resume"]:
		# Reuse the ordinary presentation and physical producer with a second
		# native actor provisioned for a later peer on this same checkpoint.
		facts["evidence"] = "native_arrival_scene_dual_actor_consumer"
		facts["actor_roster"] = ["P", "Q"]
		opening.set_script(load("res://opening/opening.gd"))
		opening.model = NativeModel.new("arrival-dual-actor-" + Crypto.new().generate_random_bytes(16).hex_encode(), ["P", "Q"], true, advanced_fixture)
	elif advanced_fixture:
		# Legacy subsystem fixtures use finite site stock but begin with the
		# advanced catalog available. The separate first-plate mode checks the
		# actual playable arrival and its native milestone gate.
		facts["evidence"] = "native_advanced_fixture_scene_consumer"
		opening.set_script(load("res://opening/opening.gd"))
		opening.model = NativeModel.new("opening-native", ["P"], true, true)
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
	if mode in ["arrival-press", "arrival-raised-press"]:
		opening.configure_save_slot(destination + ".worksite")
		if not _expect(opening.save_slot_ready,
				"The guided press consumer has a fresh owned Store destination"):
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
	if mode == "arrival-mature-trees":
		await _arrival_mature_tree_run(capture_prefix)
		return
	if mode == "arrival-mature-trees-resume":
		await _arrival_mature_tree_resume_run(capture_prefix)
		return
	var pod_state: Dictionary = opening.model.projection()
	if not _expect(opening.landing_pod_visual != null and opening.landing_hub_visual != null
			and opening.landing_pod_visual.get_meta("authority_entity", "") == pod_state.landing_pod.id
			and opening.landing_hub_visual.get_meta("authority_entity", "") == pod_state.fabrication_hub.id
			and opening.landing_pod_visual.position.distance_to(Vector3(1.65, 0, 6.6)) < 0.001
			and opening.landing_hub_visual.position.distance_to(Vector3(3.3, 0, 6.6)) < 0.001,
			"The settled hull and bench meet the native foundation top plane without a pod crank display"):
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
	if mode == "arrival-cancel-placement":
		await _arrival_cancel_placement_run(capture_prefix)
		return
	if mode in ["arrival-starter-assembly", "arrival-first-plate", "arrival-raised-starter-snap", "arrival-raised-starter-belt", "arrival-blocked-feed-cue"]:
		await _arrival_starter_assembly_run(capture_prefix)
		return
	if mode == "arrival-first-plate-resume":
		await _arrival_first_plate_resume_run(capture_prefix)
		return
	if mode == "arrival-slide":
		await _arrival_slide_run(panel, capture_prefix)
		return
	if mode == "arrival-broad-pad":
		await _arrival_broad_pad_run(panel, capture_prefix)
		return
	if mode == "arrival-broad-drive":
		await _arrival_broad_drive_run(panel)
		return
	if mode == "arrival-broad-form":
		await _arrival_broad_form_run()
		return
	if mode == "arrival-broad-cut-resume":
		await _arrival_broad_cut_resume_run(panel)
		return
	if mode == "arrival-channel-broad":
		await _arrival_channel_broad_run(capture_prefix)
		return
	if mode == "arrival-channel-small":
		await _arrival_channel_small_run(capture_prefix)
		return
	if mode in ["arrival-channel-broad-resume", "arrival-channel-small-resume"]:
		await _arrival_channel_resume_run(mode == "arrival-channel-broad-resume")
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
	if mode == "arrival-powered-press-site":
		await _arrival_powered_press_site_run(panel)
		return
	if mode == "arrival-powered-press-resume":
		await _arrival_powered_press_resume_run(panel)
		return
	if mode == "arrival-powered-press-blocked-resume":
		await _arrival_powered_press_blocked_resume_run()
		return
	if mode == "arrival-powered-press-release-resume":
		await _arrival_powered_press_release_resume_run(panel)
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
	if not capture_prefix.is_empty() and mode in ["arrival-press", "arrival-guide-geometry"]:
		await process_frame
		var landfall: Image = root.get_texture().get_image()
		if not _expect(landfall != null and landfall.save_png(capture_prefix + "-landfall.png") == OK,
				"The passive landfall viewport is retained"):
			return
	if DisplayServer.get_name() != "headless":
		opening.building_hotbar.select_slot(1)
		if not _expect(not opening.building_hotbar.catalog.visible
				and opening.building_hotbar.slots[1].is_empty(),
				"An empty hotbar key leaves the inventory closed until B opens it"):
			return
		opening.building_hotbar.open_catalog()
		if not _expect(opening.building_hotbar.catalog.visible
				and opening.building_hotbar.catalog_buttons.foundation.visible
				and not opening.building_hotbar.catalog_buttons.foundation.disabled,
				"The inventory exposes the carried foundation for binding"):
			return
		opening.building_hotbar.catalog_buttons.foundation.grab_focus()
		var bind_key := InputEventKey.new()
		bind_key.keycode = KEY_2
		bind_key.pressed = true
		opening.building_hotbar._input(bind_key)
		opening.building_hotbar._close_catalog()
		opening.building_hotbar.select_slot(1)
		if not _expect(opening.building_hotbar.slots[1] == "foundation"
				and not opening.building_hotbar.catalog.visible
				and opening.mode == "foundation" and opening.machine_preview != null
				and opening.placement_options_panel.visible == opening.machine_preview.visible,
				"Focused inventory item plus number key binds a foundation and shows its valid ghost"):
			return
		opening._select_tool("inspect")
	if mode == "arrival-resume":
		var restored: Dictionary = opening.model.projection()
		var restored_press: Dictionary = restored.guided_press_assemblies[0] if restored.guided_press_assemblies.size() == 1 else {}
		var fitted_crank := ""
		for crank_id: String in restored.crank_items:
			var item: Dictionary = restored.crank_items[crank_id]
			if item.attached_to == restored_press.get("parts", {}).get("shaft", "") \
					and item.port == restored_press.get("shaft_center", []):
				fitted_crank = crank_id
		if not _expect(opening.last_load_result.get("accepted", false)
				and opening.arrival_reveal_audio == null
				and restored.cargo.P.products == 2 and restored.cargo.P.offcuts == 2
				and restored.workshop_completed_actors.has("P")
				and not restored.has("freight_beacon")
				and restored.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
				and restored.placed_components.size() == 5
				and restored.cargo.P.components.get("wooden_frame", 0) == 1
				and restored.cargo.P.components.get("receiver_tray", 0) == 1
				and restored.cargo.P.components.get("cutting_edge", 0) == 1
				and restored.cargo.P.components.get("tool_mount", 0) == 1
				and restored.cargo.P.components.get("wooden_shaft", 0) == 1
				and restored_press.get("status") == "ready"
				and not fitted_crank.is_empty() and panel.visible
				and opening.landing_pod_visual != null
				and not opening.arrival_reveal_active
				and opening.manager_log_completion_entry.visible,
				"A fresh process reopens the finite press, attached crank and P's saved inventory milestone"):
			return
		opening._toggle_manager_log()
		if not _expect(opening.manager_log_open and opening.manager_log_layer.visible
				and not opening.manager_log_current.text.is_empty()
				and opening.model.projection() == restored,
				"The saved site reopens with a native-backed completed work cue"):
			return
		if not capture_prefix.is_empty():
			await process_frame
			if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-resume-log.png") == OK,
					"The Store-restored Work log is retained in the normal viewport"):
				return
		var before_log_close: Dictionary = opening.model.projection()
		opening._toggle_manager_log()
		if not _expect(not opening.manager_log_open and opening._can_control_character()
				and opening.model.projection() == before_log_close,
				"A resumed worker returns from the log without changing stock"):
			return
		if not await _approach_points([Vector2(6.6, 4.95), Vector2(6.6, 8.0), Vector2(5.7, 8.0)]):
			return
		opening.distance = 0.0
		opening._update_camera()
		var port: Array = restored.crank_items[fitted_crank].port
		var crank_target := Vector3(float(port[0]) * OpeningGeometry.HEIGHT_STEP,
			float(port[1]) * OpeningGeometry.HEIGHT_STEP + OpeningGeometry.ANCHOR_HEIGHT + 0.19,
			float(port[2]) * OpeningGeometry.HEIGHT_STEP + 0.22)
		var direction: Vector3 = (crank_target - opening.camera.global_position).normalized()
		opening.orbit_yaw = atan2(-direction.x, -direction.z)
		opening.orbit_pitch = asin(clampf(-direction.y, -1.0, 1.0))
		opening._update_camera()
		await physics_frame
		var hit: Dictionary = opening._screen_pick(opening._pointed_screen_position())
		if not _expect(not hit.is_empty() and hit.collider.get_meta("crank_entity", "") == fitted_crank,
				"The resumed actor-eye E ray resolves the same fitted crank: %s" %
				{"hit": str(hit.get("collider")),
					"crank": str(hit.get("collider", null).get_meta("crank_entity", "")) if not hit.is_empty() else "",
					"camera": opening.camera.global_position, "target": crank_target,
					"actor": opening.actor_world.bodies.P.global_position}):
			return
		opening._interact_pointed()
		if not _expect(opening.model.projection().crank_items[fitted_crank].holder == "P"
				and opening.model.projection().cargo.P.components.get("hand_crank", 0) == 1
				and opening.model.projection().material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
				"E detaches the same finite crank into the resumed actor's inventory"):
			return
		_record("pass")
		return
	if not _expect(panel != null and not opening._object_menu_open(),
			"The workshop waits for its centered E interaction at landfall"):
		return
	var raised: bool = mode == "arrival-raised-press"
	opening._open_object_menu_for(str(pod_state.fabrication_hub.id))
	var inventory = opening.building_hotbar
	if not _expect(inventory.catalog.visible and inventory.context_bench == pod_state.fabrication_hub.id
			and inventory.recipe_buttons.has("component:wooden_frame")
			and inventory.recipe_buttons["component:wooden_frame"].visible
			and "3 timber" in inventory.recipe_buttons["component:wooden_frame"].tooltip_text,
			"Opening the pod workshop exposes the finite advanced-fixture recipes"):
		return
	var empty_before: Dictionary = opening.model.projection()
	inventory.recipe_buttons["component:wooden_frame"].pressed.emit()
	var empty_after: Dictionary = opening.model.projection()
	if not _expect(empty_after.order == empty_before.order
			and empty_after.cargo == empty_before.cargo
			and empty_after.hand_sources == empty_before.hand_sources
			and "Carry the ingredients" in inventory.focus_description.text,
			"The nearby recipe explains missing ingredients without changing custody"):
		return
	var empty_refusal: Dictionary = _issue({"action": "craft_component",
		"entity": pod_state.fabrication_hub.id, "component": "wooden_frame"})
	if not _expect(not empty_refusal.accepted and opening.model.projection().cargo == empty_before.cargo,
			"Native admission independently refuses missing component inputs"):
		return
	inventory.catalog.hide()
	await process_frame
	if not await _approach(Vector2(6.0, 3.45)):
		return
	for index in range(8):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 4.95), Vector2(4.95, 9.9), Vector2(6.0, 11.55)]):
		return
	for index in range(8 if raised else 7):
		if _construct({"action": "harvest_source", "target": "tree-east-north"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 9.9), Vector2(4.95, 3.3),
			Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	for index in range(7):
		if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
			return
	var distant_before: Dictionary = opening.model.projection()
	if not _press_inventory_recipe("component:wooden_frame", str(distant_before.fabrication_hub.id)):
		return
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
	if not _expect(initial.cargo.P.timber == (16 if raised else 15) and initial.cargo.P.raw == 7
			and initial.placed_components.is_empty()
			and initial.component_recipes.flat_head.copper == 1
			and initial.component_recipes.wooden_slide.timber == 3
			and initial.component_recipes.copper_slide.copper == 4,
			"Two finite trees and the ore deposit supply the original route while native slides remain finite options"):
		return
	var part_list := ["anvil", "ram_face", "sliding_guide", "wooden_shaft", "wooden_cog"]
	var collector_list := ["wooden_frame", "tool_mount", "cutting_edge", "receiver_tray", "wooden_shaft"]
	for kind: String in part_list + collector_list:
		if not _expect(inventory.recipe_buttons.has("component:" + kind),
				"Every collector and press part is available in the inventory recipes"):
			return
		var bill: Dictionary = opening.model.projection().component_recipes[kind]
		var bill_text := "%d timber + %d copper" % [bill.timber, bill.copper]
		if not _expect(bill_text in inventory.recipe_buttons["component:" + kind].tooltip_text,
				"The ordinary inventory shows the native hub recipe bill"):
			return
		var before: int = opening.model.projection().order
		var owned_before: int = opening.model.projection().cargo.P.components.get(kind, 0)
		if not _press_inventory_recipe("component:" + kind, str(opening.model.projection().fabrication_hub.id)):
			return
		if not _expect(opening.model.projection().order == before + 1
				and opening.model.projection().cargo.P.components.get(kind, 0) == owned_before + 1,
				"The panel crafts one native component with exact finite cargo"):
			return
	if mode != "arrival-guide-geometry":
		if not _press_inventory_recipe("component:hand_crank", str(opening.model.projection().fabrication_hub.id)):
			return
	if not _expect(opening.model.projection().cargo.P.timber == (3 if mode == "arrival-guide-geometry" else 2 if raised else 1)
			and opening.model.projection().cargo.P.raw == 2
			and opening.model.projection().cargo.P.components.values().reduce(func(total, amount): return total + amount, 0) == (10 if mode == "arrival-guide-geometry" else 11),
			"The finite press, collector and optional crafted crank retain two copper inputs"):
		return
	if anvil_deck_only:
		if not await _approach(Vector2(1.65, 4.95)):
			return
		opening._select_tool("component")
		if not _select_inventory_item("component:anvil"):
			return
		var deck_center := [0, 0, 12]
		var before_deck: Dictionary = opening.model.projection()
		opening.component_nudge_active = true
		opening.component_nudge_center = deck_center.duplicate()
		opening._world_click(Vector2i(0, 3))
		opening.component_nudge_active = false
		opening.component_nudge_center.clear()
		var on_deck: Dictionary = opening.model.projection()
		var deck_anvil: Dictionary = {}
		for id: String in on_deck.placed_components:
			if not before_deck.placed_components.has(id):
				deck_anvil = on_deck.placed_components[id]
				deck_anvil["id"] = id
		if not _expect(on_deck.order == before_deck.order + 1
				and deck_anvil.get("component") == "anvil" and deck_anvil.get("center") == deck_center
				and on_deck.foundations.values().any(func(floor: Variant) -> bool:
					return floor.cell == [0, 3] and floor.level == 0),
				"The ordinary component tool places one anvil on the pod's existing forward deck"):
			return
		var deck_box: Dictionary = deck_anvil.occupied
		var deck_body: StaticBody3D = opening.actor_world.component_bodies.get(deck_anvil.id)
		var deck_casting: Node3D = null
		for node: Node in opening.transmission_presenter.get_children():
			if node.get_meta("component_entity", "") == deck_anvil.id:
				deck_casting = node as Node3D
				break
		var deck_foot: MeshInstance3D = deck_casting.get_node_or_null("CastPedestalFoot") as MeshInstance3D if deck_casting != null else null
		var deck_foot_bottom: float = (deck_foot.global_transform * deck_foot.mesh.get_aabb()).position.y if deck_foot != null else INF
		var deck_collision_bottom: float = deck_body.position.y - ((deck_body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size.y * 0.5 if deck_body != null else INF
		var deck_preview: Dictionary = opening._component_candidate_box("anvil", deck_center)
		if not _expect(absf(float(deck_box.center[1]) - float(deck_box.half[1])) < 0.0002
				and absf(deck_collision_bottom) < 0.0002 and absf(deck_foot_bottom) < 0.0002
				and deck_preview.center.distance_to(Vector3(deck_box.center[0], deck_box.center[1], deck_box.center[2])) < 0.0002
				and deck_preview.half.distance_to(Vector3(deck_box.half[0], deck_box.half[1], deck_box.half[2])) < 0.0002,
				"The pod-deck anvil's native box, casting, actor collision and preview meet its floor"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			opening._select_tool("inspect")
			opening.distance = 0.0
			opening._update_camera()
			var deck_target := Vector3(0.0, 0.18, 4.95)
			var deck_direction: Vector3 = (deck_target - opening.camera.global_position).normalized()
			opening.orbit_yaw = atan2(-deck_direction.x, -deck_direction.z)
			opening.orbit_pitch = asin(clampf(-deck_direction.y, -1.0, 1.0))
			opening._update_camera()
			await RenderingServer.frame_post_draw
			var first_deck: bool = root.get_texture().get_image().save_png(capture_prefix + "-anvil-deck-first.png") == OK
			opening.distance = 2.0
			opening.orbit_yaw += 0.35
			opening._update_camera()
			await RenderingServer.frame_post_draw
			var third_deck: bool = root.get_texture().get_image().save_png(
				capture_prefix + "-anvil-deck-third.png") == OK
			var side_deck: bool = await _capture_anvil_side(
				capture_prefix + "-anvil-deck-side.png", Vector3(0, 0.22, 4.95), 0.0)
			if not _expect(first_deck and third_deck and side_deck,
					"Retain the native-placed pod-deck anvil in first and third person"):
				return
		facts.anvil_support_height = 0.0
		facts.anvil_occupied = deck_box
		_record("pass")
		return
	if raised:
		var before_floor: Dictionary = opening.model.projection()
		if not _press_inventory_recipe("foundation", str(before_floor.fabrication_hub.id)):
			return
		var floor_kit: Dictionary = opening.model.projection()
		if not _expect(floor_kit.order == before_floor.order + 1
				and floor_kit.cargo.P.timber == 0
				and floor_kit.part_kits.P.foundation == before_floor.part_kits.P.foundation + 1,
				"Two local timber make one raised press floor through the ordinary workshop"):
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
	var guide_view_position := Vector2.ZERO
	var guide_view_yaw := 0.0
	var guide_view_pitch := 0.0
	for index in range(part_list.size()):
		var kind: String = part_list[index]
		if not _select_inventory_item("component:" + kind):
			return
		var requested_center := [3 * OpeningGeometry.HEIGHT_DENOMINATOR + maxi(index - 2, 0),
			[0, 1, 3, 4, 4][index] + (OpeningGeometry.HEIGHT_DENOMINATOR if raised else 0),
			4 * OpeningGeometry.HEIGHT_DENOMINATOR]
		var before: int = opening.model.projection().order
		var before_parts: Dictionary = opening.model.projection().placed_components
		if mode in ["arrival-press", "arrival-guide-geometry", "arrival-raised-press"]:
			if index == 3 and not await _approach(Vector2(6.6, 6.6)):
				return
			await physics_frame
			await process_frame
			opening.distance = 0.0
			opening._update_camera()
			var target := Vector3(4.95, 1.65 if raised else 0.0, 6.6)
			var expected_face := Vector3.UP
			var target_id := ""
			if index > 0:
				target_id = str(press_parts["ram_face" if index == 2 else "anvil"])
				var occupied: Dictionary = opening.model.projection().placed_components[target_id].occupied
				var center: Array = occupied.center
				var half: Array = occupied.half
				target = Vector3(float(center[0]), float(center[1]), float(center[2]))
				if index < 3 and not raised:
					target.y += float(half[1])
				elif index < 3:
					target.z -= float(half[2])
					expected_face = Vector3.FORWARD
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
			if raised:
				if index == 2:
					var paused_before: Dictionary = _construction_custody()
					opening._open_pause_menu()
					if not _expect(opening.pause_menu.visible,
							"Pause opens over the aimed raised guide placement"):
						return
					await _ordinary_left_click(screen)
					if not _expect(_construction_custody() == paused_before,
							"A viewport click while paused cannot place the raised guide"):
						return
					event_route_pointer_suppressed += 1
					await _ordinary_key(KEY_ESCAPE)
					if not _expect(not opening.pause_menu.visible,
							"Escape closes pause before the raised guide is fitted"):
						return
				await _ordinary_left_click(screen)
				event_route_pointer_placements += 1
			else:
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
		if index == 0 and not capture_prefix.is_empty() \
				and mode in ["arrival-press", "arrival-raised-press"] \
				and DisplayServer.get_name() != "headless":
			var prior_distance: float = opening.distance
			var prior_yaw: float = opening.orbit_yaw
			var prior_pitch: float = opening.orbit_pitch
			opening._select_tool("inspect")
			opening.distance = 0.0
			opening._update_camera()
			var foot_target := Vector3(4.95, 1.83 if raised else 0.18, 6.6)
			var foot_direction: Vector3 = (foot_target - opening.camera.global_position).normalized()
			opening.orbit_yaw = atan2(-foot_direction.x, -foot_direction.z)
			opening.orbit_pitch = asin(clampf(-foot_direction.y, -1.0, 1.0))
			opening._update_camera()
			await RenderingServer.frame_post_draw
			var seat_name := "raised" if raised else "ground"
			var first_seat: bool = root.get_texture().get_image().save_png(
				capture_prefix + "-anvil-" + seat_name + "-first.png") == OK
			opening.distance = 2.0
			opening.orbit_yaw += 0.35
			if raised:
				opening.orbit_pitch = 0.25
			opening._update_camera()
			await RenderingServer.frame_post_draw
			var third_seat: bool = root.get_texture().get_image().save_png(
				capture_prefix + "-anvil-" + seat_name + "-third.png") == OK
			var side_support: float = 1.65 if raised else 0.0
			var side_seat: bool = await _capture_anvil_side(
				capture_prefix + "-anvil-" + seat_name + "-side.png",
				Vector3(4.95, side_support + 0.22, 6.6), side_support)
			if not _expect(first_seat and third_seat and side_seat,
					"Retain the native-placed anvil and its support in first and third person"):
				return
			opening.distance = prior_distance
			opening.orbit_yaw = prior_yaw
			opening.orbit_pitch = prior_pitch
			opening._update_camera()
			opening._select_tool("component")
		if index == 0 and anvil_seat_only:
			var placed_anvil: Dictionary = projection.placed_components[press_parts.anvil]
			var occupied: Dictionary = placed_anvil.occupied
			var support_y: float = 1.65 if raised else 0.0
			var anvil_top: float = float(occupied.center[1]) + float(occupied.half[1])
			var ram_snap: Dictionary = opening._guided_press_part_snap(
				"ram_face", "anvil", requested_center, Vector3.RIGHT)
			var guide_snap: Dictionary = opening._guided_press_part_snap(
				"sliding_guide", "anvil", requested_center, Vector3.RIGHT)
			var head_snap: Dictionary = opening._guided_press_part_snap(
				"flat_head", "anvil", requested_center, Vector3.UP)
			var slide_snap: Dictionary = opening._guided_press_part_snap(
				"wooden_slide", "flat_head", head_snap.get("center", []), Vector3.UP)
			var shaft_snap: Dictionary = opening._guided_press_part_snap(
				"wooden_shaft", "anvil", requested_center, Vector3.RIGHT)
			var cog_snap: Dictionary = opening._guided_press_part_snap(
				"wooden_cog", "anvil", requested_center, Vector3.RIGHT)
			var expected_column := [requested_center[0], requested_center[1] + 1, requested_center[2]]
			var head_box: Dictionary = opening._component_candidate_box("flat_head", expected_column)
			var slide_box: Dictionary = opening._component_candidate_box("wooden_slide",
				[requested_center[0], requested_center[1] + 2, requested_center[2]])
			if not _expect(ram_snap.get("center") == expected_column
					and head_snap.get("center") == expected_column
					and guide_snap.get("center") == [requested_center[0], requested_center[1] + 3, requested_center[2]]
					and slide_snap.get("center") == [requested_center[0], requested_center[1] + 2, requested_center[2]]
					and shaft_snap.get("center") == [requested_center[0] + 1, requested_center[1] + 4, requested_center[2]]
					and cog_snap.get("center") == [requested_center[0] + 2, requested_center[1] + 4, requested_center[2]]
					and absf(head_box.center.y - head_box.half.y - anvil_top) < 0.0002
					and absf(slide_box.center.y - slide_box.half.y - anvil_top) < 0.0002,
				"Ground and raised snap targets seat the slide feet on the belt-height workbed"):
				return
			var body: StaticBody3D = opening.actor_world.component_bodies.get(press_parts.anvil)
			if raised:
				await physics_frame
				var side_ray := PhysicsRayQueryParameters3D.create(
					Vector3(4.95, 1.55, 4.95), Vector3(4.95, 1.95, 7.4))
				side_ray.collision_mask = OpeningGeometry.MACHINE_LAYER
				var side_hit: Dictionary = opening.get_world_3d().direct_space_state.intersect_ray(side_ray)
				if not _expect(side_hit.get("collider") == body
						and absf(side_hit.get("normal", Vector3.UP).y) < 0.5,
						"A standing ground-level ray reaches the raised anvil side for fitted snaps"):
					return
			var casting: Node3D = null
			for node: Node in opening.transmission_presenter.get_children():
				if node.get_meta("component_entity", "") == press_parts.anvil:
					casting = node as Node3D
					break
			var foot: MeshInstance3D = casting.find_child("WorkbedSkid*", false, false) as MeshInstance3D if casting != null else null
			var foot_bottom: float = (foot.global_transform * foot.mesh.get_aabb()).position.y if foot != null else INF
			var native_bottom: float = float(occupied.center[1]) - float(occupied.half[1])
			var collision_bottom: float = body.position.y - ((body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size.y * 0.5 if body != null else INF
			var preview_box: Dictionary = opening._component_candidate_box("anvil", requested_center)
			if not _expect(absf(native_bottom - support_y) < 0.0002
					and absf(collision_bottom - support_y) < 0.0002
					and absf(foot_bottom - support_y) < 0.0002
					and preview_box.center.distance_to(Vector3(occupied.center[0], occupied.center[1], occupied.center[2])) < 0.0002
					and preview_box.half.distance_to(Vector3(occupied.half[0], occupied.half[1], occupied.half[2])) < 0.0002,
					"The native anvil, physical body, casting foot and placement preview meet the selected floor"):
				return
			facts.anvil_support_height = support_y
			facts.anvil_occupied = occupied
			_record("pass")
			return
		if mode == "arrival-guide-geometry" and index == 2:
			guide_view_position = Vector2(opening.actor_world.bodies.P.position.x,
				opening.actor_world.bodies.P.position.z)
			guide_view_yaw = opening.orbit_yaw
			guide_view_pitch = opening.orbit_pitch
			if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
				opening._select_tool("inspect")
				await RenderingServer.frame_post_draw
				if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-partial-guide.png") == OK,
						"Retain the placed guide before a shaft or cog completes the press"):
					return
	if mode == "arrival-guide-geometry":
		if not await _approach(guide_view_position):
			return
		opening.orbit_yaw = guide_view_yaw
		opening.orbit_pitch = guide_view_pitch
		opening.distance = 0.0
		opening._update_camera()
		for _frame in range(12):
			await process_frame
	elif mode == "arrival-press":
		if not await _approach_points([Vector2(6.6, 3.3), Vector2(4.95, 3.3)]):
			return
	var ready: Dictionary = opening.model.projection().guided_press_assemblies[0]
	if mode in ["arrival-press", "arrival-guide-geometry", "arrival-raised-press"] and not capture_prefix.is_empty() \
			and DisplayServer.get_name() != "headless":
		opening._select_tool("inspect")
		opening.distance = 0.0
		opening._update_camera()
		var press_target := Vector3(4.95, 3.0 if raised else 1.35, 6.6)
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
	if anvil_ready_only:
		if not _expect(ready.status == "ready" and ready.anvil == press_parts.anvil,
				"The native recognizer keeps the floor-seated anvil in the ready press"):
			return
		facts.ready_press = ready
		_record("pass")
		return
	if mode == "arrival-guide-geometry":
		var guide_id: String = str(press_parts.sliding_guide)
		var guide_before: Dictionary = opening.model.projection().placed_components[guide_id]
		for kind: String in ["wooden_cog", "wooden_shaft", "ram_face", "anvil"]:
			if not _expect(_issue({"action": "reclaim_component", "entity": str(press_parts[kind])}).get("accepted", false),
					"The actor can remove the neighboring %s without reclaiming the guide" % kind):
				return
		var standalone: Dictionary = opening.model.projection()
		if not _expect(standalone.placed_components.size() == 1
				and standalone.placed_components[guide_id] == guide_before,
				"The same guide keeps its native component geometry after the press is removed"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			opening.distance = 0.0
			opening.orbit_yaw = guide_view_yaw
			opening.orbit_pitch = guide_view_pitch
			opening._update_camera()
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(capture_prefix + "-standalone-guide.png") == OK,
					"Retain the unchanged guide after its neighboring press parts are reclaimed"):
				return
		_record("pass")
		return
	if mode == "arrival-press":
		opening.distance = original_camera_distance
		opening._update_camera()
		if not await _approach(Vector2(4.95, 4.95)):
			return
	elif raised:
		if not await _approach_points([Vector2(6.6, 4.95), Vector2(4.95, 4.95)]):
			return
	if raised and not _expect(ready.center == [12, 4, 16] and ready.work_center == [12, 4, 16],
			"The raised native press keeps the anvil workface on the same foundation height grid"):
		return
	opening._open_object_menu_for(str(ready.anvil))
	if not _expect(opening.object_menu.visible and panel.press_section.is_visible_in_tree()
			and panel.press_status.text.begins_with("Press ready")
			and panel.route_choice.get_item_count() > 0,
			"The selected press exposes its live feed routes in the ordinary panel"):
		return
	if not _select_inventory_item("component:hand_crank"):
		return
	opening.component_nudge_active = true
	opening.component_nudge_center = ready.shaft_center.duplicate()
	opening._refresh_component_preview()
	if not _expect(opening.component_preview.visible and not opening.component_preview_blocked,
			"The crafted crank has a clear ordinary preview on the guided press shaft input"):
		return
	opening._world_click(Vector2i(3, 4), str(ready.parts.shaft))
	opening.component_nudge_active = false
	opening.component_nudge_center.clear()
	var fitted_crank := ""
	for crank_id: String in opening.model.projection().crank_items:
		var item: Dictionary = opening.model.projection().crank_items[crank_id]
		if item.attached_to == ready.parts.shaft and item.port == ready.shaft_center:
			fitted_crank = crank_id
	if not _expect(not fitted_crank.is_empty(),
			"The actor fits one conserved crafted crank at the projected native shaft input"):
		return
	opening._open_object_menu_for(str(ready.anvil))
	panel.feed_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.raw == 1
			and opening.model.projection().dropped_material.size() == 1,
			"The panel moves one carried blank into retained press work"):
		return
	var ready_die_y: float = _guided_die_y(str(ready.parts.ram)) if raised else NAN
	var work_target := Vector3(float(ready.work_center[0]) * OpeningGeometry.HEIGHT_STEP,
		OpeningGeometry.ANCHOR_HEIGHT + float(ready.work_center[1]) * OpeningGeometry.HEIGHT_STEP + 0.18,
		float(ready.work_center[2]) * OpeningGeometry.HEIGHT_STEP)
	for turn in range(3):
		if not opening.object_menu.visible:
			opening._open_object_menu_for(str(ready.anvil))
		if not _expect(opening.object_menu.visible and panel.press_section.is_visible_in_tree(),
				"The retained workpiece remains visible in the workbed menu before exterior crank operation"):
			return
		var before_turn: int = int(opening.model.projection().order)
		if not await _pulse_fitted_world_crank(fitted_crank):
			return
		opening._open_object_menu_for(str(ready.anvil))
		if not _expect(opening.model.projection().order == before_turn + 1
				and opening.model.projection().material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
				"One exterior crank pulse advances native press work without changing total copper mass"):
			return
		if mode == "arrival-press" and turn < 2:
			if not _expect("%d / 2 steps" % turn in panel.press_status.text
					and not opening.model.projection().dropped_material.any(
						func(drop: Variant) -> bool: return drop.products == 1),
					"The E menu exposes the native partial-work step before plate formation"):
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
			opening.object_menu.hide()
			var frame_name := "-raised-held.png" if raised else "-partial-work.png"
			if not _expect(await _capture_actor_area(capture_prefix + frame_name, work_target),
				"The native partial work is retained in an ordinary actor-eye press view"):
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
			opening.object_menu.hide()
			if not _expect(await _capture_actor_area(capture_prefix + "-raised-press.png", work_target),
				"The formed raised press is retained in an ordinary actor-eye view"):
				return
		_record("pass")
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		opening.object_menu.hide()
		if not _expect(await _capture_actor_area(capture_prefix + "-plate-offcut.png", work_target),
				"The separate formed plate and copper offcut are retained in an actor-eye press view"):
			return
		opening._open_object_menu_for(str(ready.anvil))
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
		if not await _pulse_fitted_world_crank(fitted_crank):
			return
	opening._open_object_menu_for(str(ready.anvil))
	var held: Dictionary = opening.model.projection()
	if not _expect(held.dropped_material.size() == 2
			and panel.press_status.text.contains("Exit holds a copper plate")
			and not opening.manager_log_completion_entry.visible,
		"A plate at the exit has not yet completed the inventory objective: %s" %
		str({"drops": held.dropped_material, "press_status": panel.press_status.text,
			"completion": opening.manager_log_completion_entry.visible})):
		return
	if not _expect(not panel.pickup_button.disabled and not panel.recover_work_button.disabled,
			"The player can choose either exit pickup or retained work recovery"):
		return
	panel.pickup_button.pressed.emit()
	if not _expect(opening.model.projection().cargo.P.products == 1
			and opening.model.projection().dropped_material.size() == 1
			and "FIRST WORKSHOP  /  COMPLETE" in opening.objective_title
			and opening.manager_log_completion_entry.visible,
		"Physical pickup completes the workshop while the second workpiece stays in place"):
		return
	if not await _pulse_fitted_world_crank(fitted_crank):
		return
	opening._open_object_menu_for(str(ready.anvil))
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
	if not _expect(opening.model.projection().cargo.P.products == 2
			and opening.model.projection().cargo.P.offcuts == 2
			and opening.model.projection().dropped_material.is_empty()
			and opening.model.projection().material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"Both plates and both copper offcuts enter finite carried custody through ordinary controls"):
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
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		opening.object_menu.hide()
		if not _expect(await _capture_actor_area(capture_prefix + "-press.png", work_target),
				"The completed press remains visible in an ordinary actor-eye view"):
			return
	_record("pass")


## Finite actor-built broad-pad ground and raised layouts.
func _arrival_broad_pad_run(panel, capture_prefix: String) -> void:
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
		{"path": [Vector2(6.0, 3.45)], "id": "tree-east-south"},
		{"path": [Vector2(4.95, 4.95), Vector2(4.95, 9.9), Vector2(6.0, 11.55)],
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
			Vector2(3.3, 3.3), Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	for cut in range(16):
		if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
			return
	var gathered: Dictionary = opening.model.projection()
	if not _expect(gathered.cargo.P.timber == 16 and gathered.cargo.P.raw == 16
			and gathered.stock.source == initial_source - 16,
			"Two trees and the one finite ore reserve supply all twenty broad-pad pieces"):
		return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(3.3, 4.95)]):
		return
	for kind in ["anvil", "ram_face", "sliding_guide", "wooden_shaft", "wooden_cog"]:
		if not _expect(opening.building_hotbar.recipe_buttons.has("component:" + kind),
				"The ordinary inventory lists the placed broad-pad part"):
			return
		for copy in range(4):
			var before: Dictionary = opening.model.projection()
			if not _press_inventory_recipe("component:" + kind, str(before.fabrication_hub.id)):
				return
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
	if not _select_inventory_item("component:anvil"):
		return
	opening.component_nudge_active = true
	opening.component_nudge_center = [12, base_level, 0]
	opening._refresh_component_preview()
	if not _expect(opening.component_preview.visible and opening.component_preview.get_child_count() > 0,
			"The original single-cell anvil ghost remains visible before size selection"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-one-anvil.png",
				Vector3(4.95, 0.7 + base_level * OpeningGeometry.HEIGHT_STEP, 0.0)),
				"Retain the actor-eye single-anvil ghost before choosing the larger footprint"):
			return
	opening._toggle_component_footprint()
	if not _expect(opening.arrival_assembly_controls.selected_name() == "broad_anvil"
			and opening.building_hotbar.footprint_button.visible,
			"The ordinary build bar selects one joined four-part workbed"):
		return
	var edge := floori((OpeningGeometry.DISPLAY_TERRAIN_SIZE * 0.5 -
		OpeningGeometry.HEIGHT_STEP * 0.5) / OpeningGeometry.HEIGHT_STEP)
	opening.component_nudge_center = [edge, base_level, 0]
	opening._refresh_component_preview()
	if not _expect(opening.component_preview.visible and opening.component_preview_blocked
			and not opening._component_area_bounds_allowed("broad_anvil", [edge, base_level, 0]),
			"The joined workbed ghost refuses its whole out-of-terrain footprint"):
		return
	var edge_before: Dictionary = opening.model.projection()
	var edge_reply: Dictionary = opening.issue({"action": "place_component", "component": "broad_anvil",
		"center": [edge, base_level, 0]})
	var edge_after: Dictionary = opening.model.projection()
	if not _expect(not edge_reply.accepted and edge_after.cargo.P.components == edge_before.cargo.P.components
			and edge_after.placed_components == edge_before.placed_components,
			"Native authority refuses the red broad footprint without spending four anvils"):
		return
	var obstructed_center := [16, base_level, 0]
	var obstacle_before: Dictionary = opening.model.projection()
	var obstacle_reply: Dictionary = opening.issue({"action": "place_component",
		"component": "ram_face", "center": obstructed_center})
	if not _expect(obstacle_reply.accepted
			and int(opening.model.projection().cargo.P.components.get("ram_face", 0)) ==
			int(obstacle_before.cargo.P.components.get("ram_face", 0)) - 1,
			"A real carried ram face can temporarily occupy one neighboring anvil cell"):
		return
	opening.component_nudge_center = [12, base_level, 0]
	opening._refresh_component_preview()
	if not _expect(opening.component_preview.visible and opening.component_preview_blocked,
			"An obstruction turns the entire joined workbed ghost red"):
		return
	var blocked_before: Dictionary = opening.model.projection()
	var blocked_reply: Dictionary = opening.issue({"action": "place_component",
		"component": "broad_anvil", "center": [12, base_level, 0]})
	if not _expect(not blocked_reply.accepted
			and opening.model.projection().cargo.P.components == blocked_before.cargo.P.components
			and opening.model.projection().placed_components == blocked_before.placed_components,
			"A blocked joined workbed placement keeps all four carried anvils"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-blocked-workbed-ghost.png",
				Vector3(5.775, 1.0 + base_level * OpeningGeometry.HEIGHT_STEP, 0.825)),
				"Retain the actor-eye blocked joined workbed ghost beside a real placed part"):
			return
	var reclaimed: Dictionary = opening.issue({"action": "reclaim_component",
		"entity": str(obstacle_reply.entity)})
	if not _expect(reclaimed.accepted
			and opening.model.projection().cargo.P.components == obstacle_before.cargo.P.components
			and opening.model.projection().placed_components == obstacle_before.placed_components,
			"Removing the temporary obstruction restores the four available anvils"):
		return
	opening._toggle_component_footprint()
	if not _expect(opening.arrival_assembly_controls.selected_name() == "anvil",
			"The legacy pad scenario explicitly returns to one small anvil per click"):
		return
	for index in range(4):
		if base_level > 0 and index == 2 and not await _approach(Vector2(5.8, 1.65)):
			return
		var x: int = 12 + (index % 2) * 4
		var z: int = (index / 2) * 4
		opening.component_nudge_active = true
		opening.component_nudge_center = [x, base_level, z]
		opening._refresh_component_preview()
		if index == 0 and not _expect(opening.component_preview.visible
				and opening.component_preview_kind == "anvil",
			"The legacy pad route previews one small anvil per click"):
			return
		if index == 0 and not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			if not _expect(await _capture_actor_area(capture_prefix + "-small-anvil-ghost.png",
					Vector3(5.775, 1.0 + base_level * OpeningGeometry.HEIGHT_STEP, 0.825)),
					"Retain the actor-eye small anvil ghost for the legacy pad route"):
				return
		var before_anvil: Dictionary = opening.model.projection()
		opening._world_click(Vector2i.ZERO)
		var after_anvil: Dictionary = opening.model.projection()
		if not _expect(after_anvil.order == before_anvil.order + 1
				and int(after_anvil.cargo.P.components.get("anvil", 0)) == int(before_anvil.cargo.P.components.get("anvil", 0)) - 1
				and after_anvil.placed_components.size() == before_anvil.placed_components.size() + 1,
				"Each separate legacy click charges one reachable small anvil"):
			return
	var supported: Dictionary = opening.model.projection()
	if not _expect(supported.broad_press_assemblies.size() == 1
			and supported.broad_press_assemblies[0].geometry_status == "missing_ram",
			"Four placed anvils define one incomplete area, not four presses"):
		return
	opening.component_nudge_center = [12, base_level, 0]
	var occupied_before: Dictionary = opening.model.projection()
	opening._world_click(Vector2i.ZERO)
	if not _expect(opening.model.projection().placed_components == occupied_before.placed_components
			and opening.model.projection().cargo.P.components == occupied_before.cargo.P.components,
			"A fifth small anvil refuses the occupied legacy pad without losing parts"):
		return
	opening.component_nudge_center = [20, base_level, 0]
	var empty_before: Dictionary = opening.model.projection()
	opening._world_click(Vector2i.ZERO)
	if not _expect(opening.model.projection().placed_components.size() == empty_before.placed_components.size()
			and opening.model.projection().cargo.P.components == empty_before.cargo.P.components
			and opening.status_label.text == "Carry another anvil.",
			"An exhausted carried stack refuses another small anvil without hidden partial placement"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		opening._select_tool("inspect")
		if not _expect(await _capture_actor_area(capture_prefix + "-four-anvil-built.png",
				Vector3(5.775, 1.0 + base_level * OpeningGeometry.HEIGHT_STEP, 0.825)),
				"Retain the actor-eye installed four-anvil work area"):
			return
	if not _select_inventory_item("component:ram_face"):
		return
	for index in range(4):
		var x: int = 12 + (index % 2) * 4
		var z: int = (index / 2) * 4
		opening.component_nudge_active = true
		opening.component_nudge_center = [x, base_level + 1, z]
		opening._refresh_component_preview()
		if index == 0 and not _expect(opening.component_preview.visible
				and opening.component_preview_kind == "ram_face"
				and not opening.building_hotbar.footprint_button.visible,
			"The legacy ram face has one small ghost and no misleading size control"):
			return
		if index == 0 and not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			if not _expect(await _capture_actor_area(capture_prefix + "-four-ram-ghost.png",
					Vector3(5.775, 1.45 + base_level * OpeningGeometry.HEIGHT_STEP, 0.825)),
					"Retain the actor-eye matching ram footprint before placement"):
				return
		var before_ram: Dictionary = opening.model.projection()
		opening._world_click(Vector2i.ZERO)
		var after_ram: Dictionary = opening.model.projection()
		if not _expect(after_ram.order == before_ram.order + 1
				and after_ram.placed_components.size() == before_ram.placed_components.size() + 1,
				"Each ram-face click charges one independent part on the broad work area"):
			return
		for part in [
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
	if not await _approach(Vector2(6.0, -1.2)):
		return
	for cut in range(6):
		if _construct({"action": "harvest_source", "target": "tree-east-upstream"}).is_empty():
			return
	if not _expect(opening.model.projection().cargo.P.timber == 6,
			"The actual upstream tree supplies one wheel and four connecting shafts"):
		return
	if not await _approach_points([Vector2(3.3, -1.2), Vector2(3.3, 3.3),
			Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
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
		var before: Dictionary = opening.model.projection()
		if not _press_inventory_recipe("part:%d" % choice, str(before.fabrication_hub.id)):
			return
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
	if _construct({"action": "place", "kind": "wheel", "cell": [-2, 1],
			"axis": "x", "level": 4}).is_empty():
		return
	for center in [[-4, 4, 4], [0, 4, 4], [4, 4, 4]]:
		if _construct({"action": "place_shaft", "center": center, "axis": "x",
				"half_span": 2}).is_empty():
			return
	if not await _approach_points([Vector2(0.0, -1.2), Vector2(3.3, -1.2)]):
		return
	for center in [[8, 4, 4]]:
		if _construct({"action": "place_shaft", "center": center, "axis": "x",
				"half_span": 2}).is_empty():
			return
	var connected: Dictionary = opening.model.projection()
	facts.connected_assembly = connected.broad_press_assemblies
	if not _expect(connected.broad_press_assemblies.size() == 1
			and connected.broad_press_assemblies[0].geometry_status == "ready"
			and connected.broad_press_assemblies[0].status == "ready"
			and connected.broad_press_assemblies[0].stroke_rate[0] > 0,
			"The back-row wheel route drives all four pad heads in their working direction"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts.save = saved
	facts.save_slot = opening.save_slot
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"The powered four-pad route survives Store without losing copper or wood"):
		return
	_record("pass")

func _broad_part(state: Dictionary, kind: String, center: Array) -> Dictionary:
	for id: String in state.placed_components:
		var part: Dictionary = state.placed_components[id]
		if part.component == kind and part.center == center:
			return {"id": id, "generation": part.generation}
	return {}

func _place_carried_channel(kind: String, center: Array,
		capture_path: String = "", capture_target: Vector3 = Vector3.ZERO) -> String:
	if not _select_inventory_item("component:" + kind):
		return ""
	opening.component_nudge_active = true
	opening.component_nudge_center = center.duplicate()
	opening._refresh_component_preview()
	if not _expect(opening.component_preview.visible and not opening.component_preview_blocked,
			"The carried %s shows a supported placement preview at %s" % [kind, str(center)]):
		return ""
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_path, capture_target),
				"Retain the actor-eye %s placement ghost before its ordinary world click" % kind):
			return ""
	var before: Dictionary = opening.model.projection().placed_components
	opening._world_click(Vector2i(int(center[0] / 4), int(center[2] / 4)))
	opening.component_nudge_active = false
	opening.component_nudge_center.clear()
	var after: Dictionary = opening.model.projection().placed_components
	if not _expect(after.size() == before.size() + 1,
			"The ordinary component click builds one finite %s channel" % kind):
		return ""
	for id: String in after:
		if not before.has(id) and after[id].component == kind and after[id].center == center:
			return id
	_expect(false, "The new channel identity retains its selected kind and grid center")
	return ""

func _arrival_channel_broad_run(capture_prefix: String) -> void:
	deadline = Time.get_ticks_msec() + 240000
	facts.evidence = "ordinary_actor_broad_channel_transfer"
	var restored: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and restored.broad_press_assemblies.size() == 1
			and restored.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.center == [12, 0, 0]
					and drop.work_lots.size() == 1 and drop.work_lots[0].remaining == 1))
			and restored.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"A fresh native scene resumes the finite partially formed broad workpiece"):
		return
	var formed: Dictionary = {}
	for tick in range(128):
		opening.model.advance()
		var state: Dictionary = opening.model.projection()
		for drop: Dictionary in state.dropped_material:
			if drop.center == [12, 0, 0] and drop.get("sheets", 0) == 1:
				formed = drop
				break
		if not formed.is_empty():
			break
	opening._refresh()
	if not _expect(formed.get("sheet_items", []).size() == 1
			and opening.model.projection().material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The restored native drive finishes one identity-bearing twelve-mass copper sheet"):
		return
	var sheet_id: int = formed.sheet_items[0].id
	if not await _approach_points([Vector2(5.8, -1.2), Vector2(5.8, 0.8)]):
		return
	var placed: Dictionary = opening.model.projection().placed_components.duplicate(true)
	for id: String in placed:
		if placed[id].component in ["ram_face", "sliding_guide"]:
			if _construct({"action": "reclaim_component", "entity": id}).is_empty():
				return
	if not _expect(opening.model.projection().dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.center == [12, 0, 0]
				and drop.sheet_items.size() == 1 and drop.sheet_items[0].id == sheet_id)),
			"Removing only the upper heads leaves the same sheet on its four native supports"):
		return
	if not await _approach(Vector2(6.0, -1.2)):
		return
	for cut in range(2):
		if _construct({"action": "harvest_source", "target": "tree-east-upstream"}).is_empty():
			return
	if not await _approach_points([Vector2(3.3, -1.2), Vector2(3.3, 3.3),
			Vector2(4.95, 9.9), Vector2(0.6, 11.55)]):
		return
	for cut in range(8):
		if _construct({"action": "harvest_source", "target": "tree-north"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 9.9), Vector2(4.95, 4.95),
			Vector2(3.3, 4.95)]):
		return
	for kind in ["channel_narrow_x", "channel_broad_x", "channel_broad_x"]:
		if not _press_inventory_recipe("component:" + kind,
				str(opening.model.projection().fabrication_hub.id)):
			return
	if not _expect(opening.model.projection().cargo.P.timber == 0
			and opening.model.projection().cargo.P.components.get("channel_narrow_x", 0) == 1
			and opening.model.projection().cargo.P.components.get("channel_broad_x", 0) == 2,
			"Ten finite tree cuts become one narrow and two broad channel kits"):
		return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(3.3, -1.2),
			Vector2(5.8, -1.2), Vector2(6.6, -1.2)]):
		return
	var narrow_id: String = await _place_carried_channel("channel_narrow_x", [20, 0, 0])
	if narrow_id.is_empty():
		return
	var before_refusal: Dictionary = opening.model.projection()
	if not await _push_loose_from_menu([12, 0, 0], [16, 0, 0], "copper sheet"):
		return
	var after_refusal: Dictionary = opening.model.projection()
	if not _expect(after_refusal.order == before_refusal.order + 1
			and after_refusal.cargo == before_refusal.cargo
			and after_refusal.dropped_material == before_refusal.dropped_material
			and after_refusal.material_mass == before_refusal.material_mass
			and opening.status_label.text.contains("Build a broad channel"),
			"The one-wide channel refuses a two-wide sheet without losing its owner: %s" % str({
				"orders": [before_refusal.order, after_refusal.order],
				"drops_equal": after_refusal.dropped_material == before_refusal.dropped_material,
				"message": opening.status_label.text})):
		return
	if _construct({"action": "reclaim_component", "entity": narrow_id}).is_empty():
		return
	var first_id: String = await _place_carried_channel("channel_broad_x", [20, 0, 0],
			capture_prefix + "-broad-placement-ghost.png" if not capture_prefix.is_empty() else "",
			Vector3(6.6, 0.7, 0.825))
	if first_id.is_empty():
		return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(opening.mode == "inspect" and not opening.component_preview.visible,
			"Escape clears the broad build ghost before inspecting the installed route"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-first-broad-channel.png",
				Vector3(6.6, 0.7, 0.825)),
				"Retain the installed broad rail beside the sheet at actor-eye height"):
			return
	if not await _push_loose_from_menu([12, 0, 0], [16, 0, 0], "copper sheet"):
		return
	var moved: Dictionary = opening.model.projection()
	if not _expect(moved.dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.center == [16, 0, 0]
				and drop.sheet_items.size() == 1 and drop.sheet_items[0].id == sheet_id))
			and not moved.dropped_material.any(func(drop: Variant) -> bool:
				return drop is Dictionary and drop.center == [12, 0, 0]),
			"Ctrl+L moves the same whole sheet one supported workcell along the broad rail"):
		return
	var before_gap: Dictionary = moved.duplicate(true)
	if not await _push_loose_from_menu([16, 0, 0], [20, 0, 0], "copper sheet"):
		return
	if not _expect(opening.model.projection().dropped_material == before_gap.dropped_material
			and opening.status_label.text.contains("supported squares"),
			"A missing receiving segment retains the sheet at its last real owner"):
		return
	if not await _approach(Vector2(7.18, -1.2)):
		return
	if (await _place_carried_channel("channel_broad_x", [24, 0, 0])).is_empty():
		return
	if not await _push_loose_from_menu([16, 0, 0], [20, 0, 0], "copper sheet"):
		return
	var final: Dictionary = opening.model.projection()
	if not _expect(final.dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.center == [20, 0, 0]
				and drop.sheet_items.size() == 1 and drop.sheet_items[0].id == sheet_id))
			and final.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The repaired broad route keeps one sheet identity and all finite material: %s" % str({
				"drops": final.dropped_material, "message": opening.status_label.text,
				"actor": final.actors.P.position})):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-sheet-second-cell.png",
				Vector3(8.25, 0.7, 0.825)),
				"Retain the moved sheet and clear receiving rail in an ordinary actor-eye frame"):
			return
	var saved: Dictionary = opening._save_worksite()
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store keeps the channel-built actor, repaired route and moved sheet in one native checkpoint"):
		return
	facts.sheet_id = sheet_id
	facts.channel_ids = [first_id]
	_record("pass")

func _arrival_channel_small_run(capture_prefix: String) -> void:
	deadline = Time.get_ticks_msec() + 240000
	facts.evidence = "ordinary_actor_small_channel_transfer"
	var restored: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and restored.cargo.P.products == 1
			and restored.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.center == [16, 0, 0]
					and drop.products == 1))
			and restored.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"A fresh native scene resumes a carried broad-route plate and separate retained plates"):
		return
	if not await _approach_points([Vector2(5.8, -1.2), Vector2(5.8, 0.8)]):
		return
	var placed: Dictionary = restored.placed_components.duplicate(true)
	for id: String in placed:
		if placed[id].component == "sliding_guide":
			if _construct({"action": "reclaim_component", "entity": id}).is_empty():
				return
	if not await _approach_points([Vector2(5.8, -1.2), Vector2(3.3, -1.2),
			Vector2(3.3, 3.3), Vector2(4.95, 9.9), Vector2(0.6, 11.55)]):
		return
	for cut in range(4):
		if _construct({"action": "harvest_source", "target": "tree-north"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 9.9), Vector2(4.95, 4.95),
			Vector2(3.3, 4.95)]):
		return
	for index in range(2):
		if not _press_inventory_recipe("component:channel_narrow_x",
				str(opening.model.projection().fabrication_hub.id)):
			return
	if not _expect(opening.model.projection().cargo.P.timber == 0
			and opening.model.projection().cargo.P.components.get("channel_narrow_x", 0) == 2,
			"Four finite timber cuts become two distinct narrow channel kits"):
		return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(3.3, -1.2),
			Vector2(5.8, -1.2), Vector2(6.6, -1.2)]):
		return
	if (await _place_carried_channel("channel_narrow_x", [20, 0, 0],
			capture_prefix + "-narrow-placement-ghost.png" if not capture_prefix.is_empty() else "",
			Vector3(7.425, 0.7, 0.825))).is_empty():
		return
	await _ordinary_key(KEY_ESCAPE)
	if not _expect(opening.mode == "inspect" and not opening.component_preview.visible,
			"Escape clears the narrow build ghost before inspecting the supported plate"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-narrow-channel.png",
				Vector3(7.425, 0.7, 0.825)),
				"Retain the actor-eye narrow rail and its supported plate at normal scale"):
			return
		root.size = Vector2i(900, 600)
		await process_frame
		if not _expect(await _capture_actor_area(capture_prefix + "-narrow-window.png",
				Vector3(7.425, 0.7, 0.825)),
				"Retain the same narrow rail and contextual loose-material control at 900x600"):
			return
		root.size = Vector2i(1280, 800)
		await process_frame
	if not await _push_loose_from_menu([16, 0, 0], [20, 0, 0], "copper plate"):
		return
	var moved: Dictionary = opening.model.projection()
	if not _expect(moved.dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.center == [20, 0, 0]
				and drop.products == 1))
			and not moved.dropped_material.any(func(drop: Variant) -> bool:
				return drop is Dictionary and drop.center == [16, 0, 0]),
			"Ctrl+L moves only the selected plate one workcell along the narrow rail"):
		return
	var before_gap: Dictionary = moved.duplicate(true)
	if not await _push_loose_from_menu([20, 0, 0], [24, 0, 0], "copper plate"):
		return
	if not _expect(opening.model.projection().dropped_material == before_gap.dropped_material
			and opening.status_label.text.contains("supported square"),
			"A missing receiving rail retains the plate at the occupied channel cell"):
		return
	if (await _place_carried_channel("channel_narrow_x", [24, 0, 0])).is_empty():
		return
	if not await _push_loose_from_menu([20, 0, 0], [24, 0, 0], "copper plate"):
		return
	var final: Dictionary = opening.model.projection()
	if not _expect(final.dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.center == [24, 0, 0]
				and drop.products == 1))
			and final.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The repaired narrow route retains the same finite plate and all material"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-plate-second-cell.png",
				Vector3(9.075, 0.7, 0.825)),
				"Retain the moved plate on its second narrow rail in the ordinary actor view"):
			return
	var saved: Dictionary = opening._save_worksite()
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store retains the two narrow rails, carried plate and moved plate in native custody"):
		return
	_record("pass")

func _arrival_channel_resume_run(sheet: bool) -> void:
	facts.evidence = "fresh_process_channel_custody_and_recovery"
	if not _expect(not prior_result_path.is_empty() and FileAccess.file_exists(prior_result_path),
			"The fresh channel continuation names its retained producer result"):
		return
	var previous_value: Variant = bytes_to_var(FileAccess.get_file_as_bytes(prior_result_path))
	if not _expect(previous_value is Dictionary and previous_value.get("status") == "pass"
			and previous_value.get("final_projection") is Dictionary,
			"The source result contains one passing producer projection"):
		return
	var previous: Dictionary = previous_value.final_projection
	var restored: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and restored.placed_components == previous.placed_components
			and restored.dropped_material == previous.dropped_material
			and restored.cargo == previous.cargo
			and restored.material_mass == previous.material_mass
			and restored.actors.P.ready and restored.actors.Q.ready
			and opening.actor_world.bodies.P.is_on_floor(),
			"The fresh native World reopens exact channel parts, item identities, cargo and conserved mass: %s" % str({
				"load": opening.last_load_result.get("accepted", false),
				"placed": restored.placed_components == previous.placed_components,
				"drops": restored.dropped_material == previous.dropped_material,
				"cargo": restored.cargo == previous.cargo,
				"mass": restored.material_mass == previous.material_mass,
				"ready": [restored.actors.P.ready, restored.actors.Q.ready],
				"floor": opening.actor_world.bodies.P.is_on_floor()})):
		return
	var point := [20, 0, 0] if sheet else [24, 0, 0]
	var item_name := "copper sheet" if sheet else "copper plate"
	var owned := false
	for drop: Dictionary in restored.dropped_material:
		if drop.center == point:
			owned = drop.get("sheets", 0) == 1 if sheet else drop.get("products", 0) == 1
	if not _expect(owned and restored.placed_components.values().any(func(part: Variant) -> bool:
			return part is Dictionary and part.component == (
				"channel_broad_x" if sheet else "channel_narrow_x")),
			"The restored %s still sits on its selected real channel" % item_name):
		return
	if not await _pickup_loose_from_menu(point, item_name):
		return
	var recovered: Dictionary = opening.model.projection()
	if not _expect(not recovered.dropped_material.any(func(drop: Variant) -> bool:
			return drop is Dictionary and drop.center == point)
			and (recovered.cargo.P.sheets == previous.cargo.P.sheets + 1 if sheet else
				recovered.cargo.P.products == previous.cargo.P.products + 1)
			and recovered.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The ordinary loose-material menu transfers the same restored %s into carried custody" % item_name):
		return
	var saved: Dictionary = opening._save_worksite()
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store retains the post-recovery channel worksite without material loss"):
		return
	_record("pass")

func _arrival_broad_form_run() -> void:
	deadline = Time.get_ticks_msec() + 240000
	facts.evidence = "ordinary_finite_broad_sheet_forming"
	var start: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and start.broad_press_assemblies.size() == 1
			and start.broad_press_assemblies[0].status == "ready"
			and start.cargo.P.raw == 0 and start.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The saved four-pad head has its original real drive and no gifted sheet stock"):
		return
	if not await _approach_points([Vector2(3.3, -1.2), Vector2(3.3, 3.3),
			Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	for cut in range(3):
		if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
			return
	if not _expect(opening.model.projection().cargo.P.raw == 3,
			"Three finite ore chunks provide one twelve-mass broad sheet"):
		return
	if not await _approach_points([Vector2(0.0, 1.65), Vector2(3.3, 3.3),
			Vector2(3.3, -1.2), Vector2(5.8, -1.2), Vector2(5.8, 0.8)]):
		return
	var press: Dictionary = opening.model.projection().broad_press_assemblies[0]
	var anvil: String = str(press.parts.anvils[0])
	if _construct({"action": "feed_broad_press", "entity": anvil}).is_empty():
		return
	var fed: Dictionary = opening.model.projection()
	if not _expect(fed.cargo.P.raw == 0
			and fed.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.center == [12, 0, 0]
					and drop.work_lots.size() == 1
					and drop.work_lots[0].recipe_input == 3
					and drop.work_lots[0].output_form == "sheet"))
			and fed.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The powered broad head accepts one identity-bearing lot from exactly three chunks"):
		return
	var partial_ticks := 0
	var partial: Dictionary = {}
	for tick in range(128):
		opening.model.advance()
		partial_ticks += 1
		partial = opening.model.projection()
		if partial.dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.center == [12, 0, 0]
				and drop.work_lots.size() == 1 and drop.work_lots[0].remaining == 1)):
			break
	opening._refresh()
	facts.partial_ticks = partial_ticks
	facts.partial_work = partial.dropped_material
	if not _expect(partial.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.center == [12, 0, 0]
					and drop.work_lots.size() == 1 and drop.work_lots[0].remaining == 1))
			and partial.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"Positive native drive advances the original lot to recoverable partial work"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts.partial_save = saved
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store publishes the partial broad work and its exact native identity"):
		return
	_record("pass")

func _arrival_broad_cut_resume_run(panel) -> void:
	deadline = Time.get_ticks_msec() + 240000
	facts.evidence = "ordinary_finite_broad_sheet_shear_continuation"
	var restored: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and restored.broad_press_assemblies.size() == 1
			and restored.broad_press_assemblies[0].status == "ready"
			and restored.dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.center == [12, 0, 0]
					and drop.work_lots.size() == 1 and drop.work_lots[0].remaining == 1))
			and restored.actors.P.ready and restored.actors.Q.ready
			and opening.actor_world.bodies.P.is_on_floor()
			and opening.actor_world.bodies.Q.is_on_floor(),
			"A fresh scene restores the same partial broad lot and both native actors"):
		return
	facts.restored_partial = restored.dropped_material
	var finishing_ticks := 0
	var formed: Dictionary = {}
	for tick in range(128):
		opening.model.advance()
		finishing_ticks += 1
		formed = opening.model.projection()
		if formed.dropped_material.any(func(drop: Variant) -> bool:
			return (drop is Dictionary and drop.center == [12, 0, 0]
				and drop.sheets == 1 and drop.sheet_items.size() == 1)):
			break
	opening._refresh()
	facts.finishing_ticks = finishing_ticks
	var sheet_drop: Dictionary = {}
	for drop: Dictionary in formed.dropped_material:
		if drop.center == [12, 0, 0]:
			sheet_drop = drop
	if not _expect(sheet_drop.get("sheets", 0) == 1
			and sheet_drop.get("sheet_items", []).size() == 1
			and formed.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The original three-chunk lot forms one twelve-mass sheet on four supports"):
		return
	var sheet_id: int = int(sheet_drop.sheet_items[0].id)
	var expected_sheet: Dictionary = sheet_drop.duplicate(true)
	expected_sheet.erase("center")
	if _construct({"action": "pickup_material", "center": [12, 0, 0],
			"expected": expected_sheet}).is_empty():
		return
	if not _expect(opening.model.projection().cargo.P.sheets == 1
			and opening.model.projection().cargo.P.sheet_items[0].id == sheet_id,
			"The physical worker carries the original whole sheet identity"):
		return
	if not await _approach_points([Vector2(5.8, -1.2), Vector2(3.3, -1.2),
			Vector2(3.3, 3.3), Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	for cut in range(8):
		if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
			return
	if not await _approach_points([Vector2(0.0, 1.65), Vector2(3.3, 3.3),
			Vector2(3.3, 4.95)]):
		return
	if not _expect(opening.building_hotbar.recipe_buttons.has("component:cutting_edge"),
			"The ordinary inventory lists the interchangeable cutting face"):
		return
	for edge in range(4):
		if not _press_inventory_recipe("component:cutting_edge", str(opening.model.projection().fabrication_hub.id)):
			return
	if not _expect(opening.model.projection().cargo.P.components.get("cutting_edge", 0) == 4
			and opening.model.projection().cargo.P.sheets == 1,
			"Four separately crafted blades accompany the same carried sheet"):
		return
	if not await _approach_points([Vector2(4.95, 4.95), Vector2(3.3, 3.3),
			Vector2(3.3, -1.2), Vector2(5.8, -1.2), Vector2(5.8, 0.8)]):
		return
	var anvil: String = str(opening.model.projection().broad_press_assemblies[0].parts.anvils[0])
	var blade_at: Array = []
	for index in range(4):
		var point: Array = [12 + (index % 2) * 4, 1, (index / 2) * 4]
		var ram: Dictionary = _broad_part(opening.model.projection(), "ram_face", point)
		if not _expect(not ram.is_empty(), "The broad press retains each separate removable face"):
			return
		if _construct({"action": "reclaim_component", "entity": ram.id}).is_empty():
			return
		blade_at.append(point)
	for point: Array in blade_at:
		if _construct({"action": "place_component", "component": "cutting_edge",
				"center": point}).is_empty():
			return
	var cutting: Dictionary = opening.model.projection()
	if not _expect(cutting.broad_shear_assemblies.any(func(head: Variant) -> bool:
			return head is Dictionary and head.origin == [12, 0, 0] and head.status == "ready")
			and cutting.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The same supported work area now has a complete driven cutting head"):
		return
	if _construct({"action": "place_sheet", "center": [12, 0, 0],
			"sheet_id": sheet_id}).is_empty():
		return
	for stroke in range(2):
		if _construct({"action": "stroke_broad_shear", "entity": anvil,
				"sheet_id": sheet_id}).is_empty():
			return
	var interrupted: Dictionary = opening.model.projection()
	var missing: Dictionary = _broad_part(interrupted, "cutting_edge", blade_at[3])
	if not _expect(not missing.is_empty(), "The fourth blade has a reclaimable placed identity"):
		return
	if _construct({"action": "reclaim_component", "entity": missing.id}).is_empty():
		return
	var refused: Dictionary = _issue({"action": "stroke_broad_shear", "entity": anvil,
		"sheet_id": sheet_id})
	if not _expect(not refused.get("accepted", false)
			and refused.get("reason", "") == "incomplete_shear"
			and opening.model.projection().dropped_material.any(func(drop: Variant) -> bool:
				return (drop is Dictionary and drop.center == [12, 0, 0]
					and drop.sheet_items[0].id == sheet_id)),
			"A missing blade refuses the next stroke while retaining the partial sheet"):
		return
	if _construct({"action": "place_component", "component": "cutting_edge",
			"center": blade_at[3]}).is_empty():
		return
	for stroke in range(2):
		if _construct({"action": "stroke_broad_shear", "entity": anvil,
				"sheet_id": sheet_id}).is_empty():
			return
	var products: Dictionary = opening.model.projection()
	var four := 0
	for drop: Dictionary in products.dropped_material:
		if drop.products == 1 and drop.center in [[12, 0, 0], [16, 0, 0],
				[12, 0, 4], [16, 0, 4]]:
			four += 1
	if not _expect(four == 4 and products.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS
			and products.material_mass.sheets == 0 and products.material_mass.offcut_units == 0,
			"Four separated three-mass plates replace the one sheet without an offcut"):
		return
	var plate_drop: Dictionary = {}
	for drop: Dictionary in products.dropped_material:
		if drop.center == [12, 0, 0]:
			plate_drop = drop
	var expected_plate: Dictionary = plate_drop.duplicate(true)
	expected_plate.erase("center")
	if _construct({"action": "pickup_material", "center": [12, 0, 0],
			"expected": expected_plate}).is_empty():
		return
	var carried: Dictionary = opening.model.projection()
	var remaining_plates := 0
	for drop: Dictionary in carried.dropped_material:
		if drop.products == 1:
			remaining_plates += 1
	facts.final_plate = carried.cargo.P
	if not _expect(carried.cargo.P.products == 1
			and remaining_plates == 3
			and carried.material_mass.accounted_mass == ARRIVAL_INITIAL_MASS,
			"The worker carries one broad-route plate and leaves three accessible plates"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts.final_save = saved
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"Store preserves the repaired cutting head and all four plate identities"):
		return
	_record("pass")
