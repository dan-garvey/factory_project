extends SceneTree
## Automated headless consumer of the ordinary scene, not a desktop playtest.
const NativeModel = preload("res://opening/native_model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
const OpeningGeometry = preload("res://opening/site_geometry.gd")
const OpeningScene = preload("res://opening/opening.gd")
const ConstructionAudio = preload("res://opening/construction_audio.gd")
const MechanicalAmbience = preload("res://opening/mechanical_ambience.gd")
const TransmissionPresenter = preload("res://opening/native_transmission_presenter.gd")
const ARRIVAL_INITIAL_MASS := 4096 * 4
const VALUE_OPTIONS := ["--native-check-output=", "--native-check-mode=",
	"--arrival-capture-prefix=", "--resume-input=", "--save-slot=", "--test-purpose="]
const FLAG_OPTIONS := ["--event-route-pointer"]
var opening
var destination := ""
var event_route_pointer := false
var event_route_pointer_placements := 0
var event_route_pointer_suppressed := 0
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
			"--native-check-mode=": mode = value
			"--event-route-pointer": event_route_pointer = true
	if mode.is_empty() or destination.is_empty():
		push_error("Select one native adapter fixture mode and a fresh output")
		quit(2)
		return
	var resumes_worksite := mode.ends_with("-resume") or mode in ["resume",
		"arrival-nonhorizontal-incline"]
	if seen.has("--resume-input=") != resumes_worksite:
		push_error("The selected native adapter fixture mode requires exactly its declared worksite input")
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
	if status == "pass" and event_route_pointer and (event_route_pointer_placements !=
			(3 if mode == "arrival-raised-starter-snap" else 2)
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
	if status == "pass" and mode == "arrival-nonhorizontal-incline":
		print("CHAPTER 1 PLAYER-BUILT INCLINE PASS")
	if status == "pass" and mode in ["arrival-nonhorizontal-vertical-resume", "arrival-nonhorizontal-sideways-resume"]:
		print("CHAPTER 1 PLAYER-BUILT POWER BELT PASS: " + mode)
	if status == "pass" and mode == "arrival-nonhorizontal-power-reopen-resume":
		print("CHAPTER 1 POWER BELT REOPEN PASS")
	if status == "pass" and mode == "arrival-nonhorizontal-actor-block-resume":
		print("CHAPTER 1 BELT ACTOR OBSTRUCTION PASS")
	if status == "pass" and mode == "arrival-foundation-craft":
		print("CHAPTER 1 FOUNDATION CRAFT PASS")
	if status == "pass" and mode == "arrival-joined-broad":
		print("CHAPTER 1 JOINED BROAD PRESS PASS")
	if status == "pass" and mode == "arrival-joined-broad-slab":
		print("CHAPTER 1 JOINED BROAD PRESS SLAB PASS")
	if status == "pass" and event_route_pointer:
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
	var part_kind := ""
	if key.begins_with("part:"):
		var part_index := int(key.trim_prefix("part:"))
		var parts: Array = opening.model.projection().get("part_recipes", [])
		if part_index >= 0 and part_index < parts.size():
			part_kind = str(parts[part_index].get("kind", ""))
	var category: String = inventory._recipe_category(key, part_kind)
	if inventory.recipe_tabs.has(category):
		inventory.recipe_tabs[category].pressed.emit()
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

func _capture_component_close(component_id: String, path: String) -> bool:
	var component_anchor: Node3D
	for anchor: Node in opening.transmission_presenter.get_children():
		if anchor.get_meta("component_entity", "") == component_id:
			component_anchor = anchor
	if component_anchor == null:
		return false
	var close := SubViewport.new()
	close.size = Vector2i(1280, 800)
	close.world_3d = root.world_3d
	close.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(close)
	var camera := Camera3D.new()
	close.add_child(camera)
	camera.fov = 38.0
	camera.position = component_anchor.global_position + Vector3(1.05, 0.72, 1.15)
	camera.look_at(component_anchor.global_position + Vector3.DOWN * 0.10)
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

func _capture_press_context_side(path: String, target: Vector3, opposite := false) -> bool:
	var context := SubViewport.new()
	context.size = Vector2i(1280, 800)
	context.world_3d = root.world_3d
	context.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(context)
	var camera := Camera3D.new()
	context.add_child(camera)
	camera.fov = 52.0
	camera.position = target + Vector3(-2.1 if opposite else 2.1, 0.55, 2.25)
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
	for lower: float in [0.0, 0.2, 0.4, 0.6]:
		opening._update_camera()
		var direction: Vector3 = (target - Vector3.UP * lower - opening.camera.global_position).normalized()
		opening.orbit_yaw = atan2(-direction.x, -direction.z)
		opening.orbit_pitch = asin(clampf(-direction.y, -1.0, 1.0))
		opening._update_camera()
		await physics_frame
		var screen: Vector2 = opening._pointed_screen_position()
		var hit: Dictionary = opening._screen_pick(screen)
		if opening._screen_entity(screen) == id and absf(hit.get("normal", Vector3.UP).y) < 0.5:
			return hit
	return opening._screen_pick(opening._pointed_screen_position())

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
	# Scene waypoints establish physical reach, not exact foot coordinates.
	# Keep the stricter 8 cm bound for direct motor and jump checks.
	if not await _walk_to(target, false, actor, OpeningGeometry.CAPSULE_RADIUS):
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

func _arrival_joined_broad_run(capture_prefix: String, on_slab := false) -> void:
	deadline = Time.get_ticks_msec() + 240000
	facts.evidence = "native_joined_broad_press_slab_scripted_actor_route" if on_slab \
		else "native_joined_broad_press_scripted_actor_route"
	var start: Dictionary = opening.model.projection()
	if not _expect(start.placed_components.is_empty() and start.broad_press_assemblies.is_empty(),
			"The joined broad proof begins without installed press parts"):
		return
	if on_slab and not _expect(start.foundations.values().any(func(floor: Variant) -> bool:
		return floor is Dictionary and floor.cell == [2, 2] and floor.level == 0),
			"The joined broad slab proof starts with one real pod-deck foundation at cell (2, 2)"):
		return
	if not await _approach_points([Vector2(6.0, 3.45)]):
		return
	for cut in range(2):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 4.95), Vector2(3.3, 3.3),
			Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	for cut in range(31):
		if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
			return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(3.3, 4.95)]):
		return
	var bench_id: String = str(opening.model.projection().fabrication_hub.id)
	for recipe in [{"kind": "anvil", "count": 4}, {"kind": "flat_head", "count": 4},
			{"kind": "copper_slide", "count": 4}, {"kind": "hand_crank", "count": 1}]:
		for copy in range(recipe.count):
			if _construct({"action": "craft_component", "entity": bench_id,
					"component": recipe.kind}).is_empty():
				return
	var crafted: Dictionary = opening.model.projection()
	var carried_crank := ""
	for crank_id: String in crafted.crank_items:
		if crafted.crank_items[crank_id].holder == "P":
			carried_crank = crank_id
	if not _expect(crafted.cargo.P.raw == 3 and crafted.cargo.P.timber == 0
			and not carried_crank.is_empty() and crafted.placed_components.is_empty(),
			"Finite ore and timber leave twelve carried press parts, one crank and three feed blanks"):
		return
	var installation_path: Array[Vector2] = [Vector2(4.95, 4.95), Vector2(3.3, 3.3),
		Vector2(3.3, 1.65)]
	if on_slab:
		installation_path = [Vector2(3.3, 4.95)]
	if not await _approach_points(installation_path):
		return
	var installed: Dictionary = {}
	var origin: Array = [24, 0, 24] if on_slab else [12, 0, 0]
	for part in [{"kind": "broad_anvil", "center": origin},
			{"kind": "broad_flat_head", "center": [origin[0], origin[1] + 1, origin[2]]},
			{"kind": "broad_copper_slide", "center": [origin[0], origin[1] + 4, origin[2]]}]:
		installed[part.kind] = _construct({"action": "place_component",
			"component": part.kind, "center": part.center})
		if installed[part.kind].is_empty():
			return
	opening._refresh()
	var assembled: Dictionary = opening.model.projection()
	if not _expect(assembled.placed_components.size() == 3
			and assembled.broad_press_assemblies.size() == 1
			and assembled.broad_press_assemblies[0].geometry_status == "ready"
			and assembled.broad_press_assemblies[0].status == "unpowered"
			and assembled.broad_press_assemblies[0].work_centers.size() == 4,
			"One native broad anvil, matching face and slide cover exactly four workcells"):
		return
	if on_slab and not _expect(assembled.broad_press_assemblies[0].work_centers == [
			[24, 0, 24], [28, 0, 24], [24, 0, 28], [28, 0, 28]],
			"All four native broad workcells fit inside the same 3U-square pod-deck slab"):
		return
	facts.broad_assembly = assembled.broad_press_assemblies[0]
	if on_slab and not await _approach(Vector2(3.3, 5.775)):
		return
	var workface := Vector3(26.0 * OpeningGeometry.HEIGHT_STEP, 0.48,
		26.0 * OpeningGeometry.HEIGHT_STEP) if on_slab else Vector3(
		3.0 * OpeningGeometry.PITCH, 0.48, 0.5 * OpeningGeometry.PITCH)
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		opening._select_tool("inspect")
		if not _expect(await _capture_press_context_side(capture_prefix + "-joined-rest-side.png", workface, not on_slab)
				and await _capture_actor_area(capture_prefix + "-joined-rest-actor.png", workface),
				"Retain the actual three-piece broad press in its surrounding worksite at rest"):
			return
	var bed_id: String = str(installed.broad_anvil.entity)
	var slide_id: String = str(installed.broad_copper_slide.entity)
	if _construct({"action": "feed_broad_press", "entity": bed_id}).is_empty():
		return
	var fed: Dictionary = opening.model.projection()
	if not _expect(fed.cargo.P.raw == 0 and fed.dropped_material.any(func(drop: Variant) -> bool:
		return drop is Dictionary and not drop.get("work_lots", []).is_empty()),
		"Three finite blanks enter one retained broad work lot"):
		return
	var crank_port: Array = [22, 4, 24] if on_slab else [18, 4, 0]
	var crank_face: Array = [-1, 0, 0] if on_slab else [1, 0, 0]
	if _construct({"action": "attach_hand_crank", "entity": slide_id,
			"crank": carried_crank, "port": crank_port, "face": crank_face}).is_empty():
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		opening._select_tool("inspect")
		if not _expect(await _capture_press_context_side(capture_prefix + "-joined-fed-side.png", workface, not on_slab),
				"Retain the broad workpiece and fitted external crank in context"):
			return
	var rest_phase: int = int(opening.model.projection().slide_phases[slide_id].subticks)
	for pulse in range(6):
		if _construct({"action": "operate_hand_crank", "entity": carried_crank}).is_empty():
			return
		opening._refresh()
		if pulse == 0:
			var moving: Dictionary = opening.model.projection()
			if not _expect(int(moving.slide_phases[slide_id].subticks) > rest_phase,
					"The actual broad slide advances from its native rest phase"):
				return
			if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
				if not _expect(await _capture_press_context_side(capture_prefix + "-joined-stroke-side.png", workface, not on_slab),
						"Retain the broad slide during its native stroke in context"):
					return
	var formed: Dictionary = opening.model.projection()
	if not _expect(formed.dropped_material.any(func(drop: Variant) -> bool:
		return drop is Dictionary and int(drop.get("sheets", 0)) == 1)
			and formed.placed_components.size() == 3,
			"The powered joined press forms one native sheet without replacing its installed parts"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_press_context_side(capture_prefix + "-joined-sheet-side.png", workface, not on_slab),
				"Retain the formed sheet and the same joined press in context"):
			return
	_record("pass")

func _arrival_field_craft_run(panel, capture_prefix: String) -> void:
	var inventory = opening.building_hotbar
	inventory.open_catalog()
	inventory.recipe_tabs.machine.pressed.emit()
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
		inventory.recipe_tabs.machine.pressed.emit()
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
	if not await _approach(Vector2(7.0, 3.45)):
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
	if not await _approach(Vector2(6.0, 3.45)):
		return
	for index in range(3):
		if _construct({"action": "harvest_source", "target": "tree-east-south"}).is_empty():
			return
	var gathered: Dictionary = opening.model.projection()
	if not _expect(gathered.cargo.P.timber == 3 and gathered.hand_sources["tree-east-south"].remaining == 5,
			"Three finite cuts reach the same physically present field actor"):
		return
	inventory.open_catalog()
	inventory.recipe_tabs.machine.pressed.emit()
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
		inventory.recipe_tabs.machine.pressed.emit()
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
	inventory.recipe_tabs.machine.pressed.emit()
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
	inventory.recipe_tabs.other.pressed.emit()
	if not _expect(inventory.recipe_buttons.foundation.visible,
			"The Other tab exposes the foundation recipe before it is pressed"):
		return
	inventory.recipe_buttons.foundation.pressed.emit()
	var crafted: Dictionary = opening.model.projection()
	if not _expect(crafted.order == before.order + 1 and crafted.cargo.P.timber == 0
			and crafted.part_kits.P.foundation == before.part_kits.P.foundation + 1
			and crafted.hand_sources["tree-east-south"].remaining == 6
			and "Carry the ingredients" in inventory.recipe_buttons.foundation.tooltip_text,
			"The recipe icon converts two finite timber into one native foundation and updates availability: "
			+ str({"order": crafted.order, "before": before.order,
				"timber": crafted.cargo.P.timber,
				"foundations": crafted.part_kits.P.foundation,
				"before_foundations": before.part_kits.P.foundation,
				"source_remaining": crafted.hand_sources["tree-east-south"].remaining,
				"tooltip": inventory.recipe_buttons.foundation.tooltip_text})):
		return
	inventory.catalog.hide()
	if not await _approach(Vector2(3.3, 4.95)):
		return
	var placed: Dictionary = _construct({"action": "place_foundation", "cell": [2, 1], "level": 4})
	if placed.is_empty():
		return
	var built: Dictionary = opening.model.projection()
	var floor_id := ""
	for id: String in built.foundations:
		if built.foundations[id].cell == [2, 1] and built.foundations[id].level == 4:
			floor_id = id
	if not _expect(not floor_id.is_empty() and built.part_kits.P.foundation == before.part_kits.P.foundation,
			"The crafted floor can enter the ordinary native construction inventory"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		opening._select_tool("inspect")
		if not _expect(await _capture_actor_area(capture_prefix + "-one-foundation-built.png",
				Vector3(2.0 * OpeningGeometry.FOUNDATION_PITCH,
					4.0 * OpeningGeometry.HEIGHT_STEP, OpeningGeometry.FOUNDATION_PITCH)),
				"Retain the actor-eye one-slab footprint beside the unchanged worksite"):
			return
		var context := SubViewport.new()
		context.size = Vector2i(1280, 800)
		context.world_3d = root.world_3d
		context.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(context)
		var camera := Camera3D.new()
		context.add_child(camera)
		camera.fov = 60.0
		camera.position = Vector3(7.5, 4.1, 9.2)
		camera.look_at(Vector3(3.3, 0.7, 4.6))
		camera.make_current()
		for frame in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var context_captured: bool = context.get_texture().get_image().save_png(
			capture_prefix + "-foundation-pod-worker-context.png") == OK
		context.queue_free()
		if not _expect(context_captured,
				"Retain the single new slab beside the unchanged pod and worker"):
			return
	if _construct({"action": "remove", "entity": floor_id}).is_empty():
		return
	var reclaimed: Dictionary = opening.model.projection()
	if not _expect(reclaimed.part_kits.P.foundation == crafted.part_kits.P.foundation
			and reclaimed.cargo.P.timber == 0 and not reclaimed.foundations.has(floor_id)
			and reclaimed.foundations.size() == crafted.foundations.size(),
			"Reclaiming restores exactly the crafted floor without refunding its timber"):
		return
	opening.configure_save_slot(destination + ".worksite")
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
	if event_route_pointer and mode not in ["arrival-first-plate", "arrival-first-plate-press", "arrival-raised-starter-snap"]:
		push_error("The selected event route does not apply to this fixture mode")
		quit(1)
		return
	if mode == "supplied-hardware":
		await _arrival_run()
		return
	if mode == "arrival-nonhorizontal-incline":
		await _arrival_run()
		return
	if mode in ["arrival-mature-trees", "arrival-mature-trees-resume", "arrival-starter-assembly", "arrival-first-plate", "arrival-first-plate-press", "arrival-raised-starter-snap", "arrival-raised-starter-belt", "arrival-blocked-feed-cue", "arrival-first-plate-resume", "arrival-nonhorizontal-incline", "arrival-nonhorizontal-vertical-resume", "arrival-nonhorizontal-sideways-resume", "arrival-nonhorizontal-power-reopen-resume", "arrival-nonhorizontal-actor-block-resume", "arrival-slide", "arrival-joined-broad", "arrival-joined-broad-slab", "arrival-craft-capacity", "arrival-craft-capacity-resume", "arrival-field-craft", "arrival-foundation-craft", "arrival-foundation-craft-resume", "arrival-portable-workbench", "arrival-pod-workshop", "arrival-pod-workshop-resume", "arrival-belt", "arrival-belt-controls", "arrival-belt-resume", "arrival-cancel-placement", "arrival-reveal", "arrival-reveal-skip"]:
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

func _walk_to(target: Vector2, jump: bool = false, actor: String = "P",
		arrival_radius: float = 0.08) -> bool:
	# This fixture drives the trusted motor directly. The ordinary keyboard
	# presenter otherwise sends its idle direction in the same physics frame,
	# making the walk depend on the render and physics callback order.
	var presenter_was_processing: bool = opening.character_presenter.is_physics_processing()
	opening.character_presenter.set_physics_process(false)
	var jumped := false
	var highest_foot := -INF
	var leg_deadline := mini(deadline, Time.get_ticks_msec() + 45000)
	while Time.get_ticks_msec() < leg_deadline:
		var body = opening.actor_world.bodies[actor]
		var at: Vector3 = body.global_position
		highest_foot = maxf(highest_foot, at.y - OpeningGeometry.CAPSULE_HEIGHT / 2.0)
		var gap := target - Vector2(at.x, at.z)
		if gap.length() < arrival_radius:
			opening.actor_world.release_control(actor)
			opening.character_presenter.set_physics_process(presenter_was_processing)
			if jump:
				facts["foundation_jump"] = {"edge_sent": jumped, "highest_foot": highest_foot}
			return true
		var jump_edge: bool = jump and not jumped and gap.length() < 1.2 and body.is_on_floor()
		if not _expect(opening.actor_world.set_control(actor, gap.normalized(), jump_edge).accepted,
				"The fixture walks through the real character motor without setting a pose"):
			opening.character_presenter.set_physics_process(presenter_was_processing)
			return false
		jumped = jumped or jump_edge
		await physics_frame
		await process_frame
	opening.actor_world.release_control(actor)
	opening.character_presenter.set_physics_process(presenter_was_processing)
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
	if not await _walk_to(Vector2(12.0, 6.9)):
		return
	var before: Dictionary = opening.model.projection()
	var first: Dictionary = _issue({"action": "place_foundation", "cell": [5, 2], "level": 4})
	if not _expect(first.accepted, "The real nearby actor can build beyond the removed local rectangle"):
		return
	var second: Dictionary = _issue({"action": "place_foundation", "cell": [6, 2], "level": 4})
	if not _expect(second.accepted, "An independently placed foundation shares the absolute height grid"):
		return
	for _frame in range(3):
		await physics_frame
		await process_frame
	opening._select_tool("foundation")
	if not _expect(opening.foundation_level == 4 and opening.foundation_level_label.text.begins_with("Factory floor"),
			"The actual controls present every full-U foundation top as a machine floor"):
		return
	if not _expect(opening.actor_world._geometry_registered(), "Displayed foundation levels match registered native box bodies"):
		return
	if not await _walk_to(Vector2(12.375, 4.95), true):
		return
	if not _expect(facts.foundation_jump.edge_sent and facts.foundation_jump.highest_foot > 4.0 * OpeningGeometry.HEIGHT_STEP + 0.05,
			"The actual jump lifts the capsule feet above one full foundation before landing"):
		return
	for _frame in range(40):
		await physics_frame
		await process_frame
	var body = opening.actor_world.bodies.P
	facts["standing_on_foundation"] = opening.actor_world.diagnostics("P")
	if not _expect(body.is_on_floor() and absf(body.global_position.y - OpeningGeometry.CAPSULE_HEIGHT / 2.0 - 4.0 * OpeningGeometry.HEIGHT_STEP) < 0.02,
			"The real capsule walks and lands on the constructed surface at the common height"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts["foundation_save"] = saved
	if not _expect(saved.accepted and saved.native_preflight.accepted,
			"Store accepts the real registered pose and foundation custody: " + str(saved)):
		return
	if not await _walk_to(Vector2(12.0, 6.9)):
		return
	opening._adjust_foundation_level(1)
	if not _expect(opening.foundation_level == 8 and opening.foundation_level_label.text.begins_with("Factory floor"),
			"The next foundation height selects the next complete machine floor"):
		return
	opening._world_click(Vector2i(5, 2))
	if not _expect(opening.model.projection().foundations.size() == 3,
			"The first ordinary foundation click adds a second full-U floor above its base"):
		return
	opening._world_click(Vector2i(6, 2))
	if not _expect(opening.model.projection().foundations.size() == 4,
			"An independent ordinary foundation click joins the adjacent floor at the same world height"):
		return
	opening._select_tool("processor")
	opening.transmission_controls.selected_axis = "x"
	opening._world_click(Vector2i(16, 6))
	if not _expect(opening.model.projection().entities.size() == 1, "The ordinary press placement succeeds before dependent probing"):
		return
	opening._select_tool("drive")
	opening.transmission_controls.selected_axis = "x"
	opening.transmission_controls.gear_height = 8
	opening._world_click(Vector2i(17, 6))
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
		if not _expect(entity.level == 8 and absf(physical.position.y - OpeningGeometry.MACHINE_CENTER_HEIGHT - 8.0 * OpeningGeometry.HEIGHT_STEP) < 0.00001,
				"Machine projection, mesh and native contact share the foundation height"):
			return
	var shaft: Dictionary = current.transmission_parts[shaft_id]
	var shaft_body = opening.actor_world.mechanical_bodies.get(shaft_id)
	# A machine collision box has its own centre offset. The native profile
	# and actual engagement define the common mechanical axis instead.
	var mechanical_height: float = 8.0 * current.adapter_profile.height_step + current.adapter_profile.anchor_height
	facts["foundation_alignment"] = {"press_collision_y": opening.actor_world.machines[press_id].position.y,
		"shaft_collision_y": shaft_body.position.y if shaft_body != null else null, "native_mechanical_y": mechanical_height}
	if not _expect(shaft.kind == "shaft" and shaft.center[1] == 8 and shaft_body != null
			and absf(shaft_body.position.y - mechanical_height) < 0.00001
			and opening.actor_world._geometry_registered(),
			"The shaft uses the engaged press's native mechanical height and both collision bodies remain registered"):
		return
	if not _expect(current.stock.source == before.stock.source and current.remaining == 0,
			"Construction changes no mineral quantity or material clock"):
		return
	var upper := ""
	for id: String in current.foundations:
		if current.foundations[id].cell == [5, 2] and current.foundations[id].level == 8:
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
	if not await _approach(Vector2(-0.6, 1.3)):
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
			and panel._receiver_route_status(built).contains("outward"),
			"The fitted north receiver meets a powered outward belt mouth in native inspection"):
		return
	var drive := ""
	for collector: Dictionary in built.collector_assemblies:
		if collector.get("status") == "ready":
			drive = str(collector.parts.mount)
			break
	# Walk around the east side of the fitted collector. Its frame closes the
	# direct path from the receiver aisle to the wheel, while both inputs stay
	# within the same physical actor's build reach from the south approach.
	if not await _approach_points([Vector2(1.1, 3.3), Vector2(1.1, 0.2), Vector2(-0.3, 0.55)]):
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

func _expect_nonhorizontal_belt_preview(first_id: String, last_id: String,
		capture_path: String) -> bool:
	# Point the actual standing actor camera at the second confirmed shaft. The
	# pick ray and amber loop are player cues; native Host keeps construction
	# authority and the fixture checks that looking spends nothing.
	var before: Dictionary = opening.model.projection()
	var last: Dictionary = before.get("transmission_parts", {}).get(last_id, {})
	if not _expect(not last.is_empty() and before.part_kits.P.belt == 1
			and opening.transmission_controls._belt_start.get("id", "") == first_id,
			"The first confirmed shaft and one paid belt kit precede the visual preview"):
		return false
	opening.distance = 0.0
	opening._update_camera()
	var target: Vector3 = opening.transmission_presenter.world_center(last.center)
	var direction: Vector3 = (target - opening.camera.global_position).normalized()
	opening.orbit_yaw = atan2(-direction.x, -direction.z)
	opening.orbit_pitch = asin(clampf(-direction.y, -1.0, 1.0))
	opening._update_camera()
	for frame in 5:
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	opening._refresh_machine_preview()
	var screen: Vector2 = opening._pointed_screen_position()
	var loop: MeshInstance3D = opening.machine_preview.get_node_or_null("BeltLoop")
	if not _expect(opening._screen_entity(screen) == last_id
			and opening._pointed_summary_data(screen).get("detail", "") == "Click  Connect belt"
			and opening.machine_preview.visible
			and opening.machine_preview.get_meta("belt_preview_from", "") == first_id
			and opening.machine_preview.get_meta("belt_preview_to", "") == last_id
			and loop != null and loop.mesh != null
			and loop.material_override == opening.belt_preview_material
			and opening.machine_preview.find_children("*", "CollisionObject3D", true, false).is_empty()
			and opening.model.projection().revision == before.revision
			and opening.model.projection().part_kits.P.belt == 1,
			"The standing worker sees the proposed amber belt on the pointed shaft without spending a kit"):
		return false
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		return _expect(root.get_texture().get_image().save_png(capture_path) == OK,
			"Retain the standing worker view of the proposed belt")
	return true

func _arrival_nonhorizontal_incline_run(capture_prefix: String) -> void:
	# Begin with the physically saved, normal first plate. The motor, finite
	# sources, workshop inventory and belt endpoint clicks are the player path;
	# this remains scripted scene evidence, not a human play session.
	var start: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and start.first_plate_unlock and start.cargo.P.products == 1
			and start.actors.Q.ready and opening.actor_world.bodies.P.is_on_floor()
			and opening.actor_world.bodies.Q.is_on_floor()
			and start.belt_spans.is_empty() and start.part_kits.P.belt == 0,
			"The ordinary two-worker first-plate save reopens before the new belt is earned"):
		return
	for point in [Vector2(4.95, 9.9), Vector2(6.0, 11.55)]:
		if not await _approach(point):
			return
	for cut in 6:
		if _construct({"action": "harvest_source", "target": "tree-east-north"}).is_empty():
			return
	if not await _approach_points([Vector2(4.95, 9.9), Vector2(7.5, 9.9),
			Vector2(7.5, 3.3), Vector2(-0.5, 0.0)]):
		return
	for cut in 2:
		if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
			return
	if not _expect(opening.model.projection().cargo.P.timber == 6
			and opening.model.projection().cargo.P.raw == 2,
			"Six finite timber and two copper units reach the worker without extra stock"):
		return
	if not await _approach(Vector2(3.3, 4.95)):
		return
	var hub: String = str(opening.model.projection().fabrication_hub.id)
	for part in [{"kind": "wheel", "half_span": 0}, {"kind": "shaft", "half_span": 2},
			{"kind": "shaft", "half_span": 2}, {"kind": "belt", "half_span": 0}]:
		var recipe := -1
		for index in opening.model.projection().part_recipes.size():
			var offer: Dictionary = opening.model.projection().part_recipes[index]
			if offer.kind == part.kind and offer.half_span == part.half_span:
				recipe = index
				break
		if not _expect(recipe >= 0, "The native workshop offers the needed finite transmission part"):
			return
		opening.building_hotbar.open_at_bench(hub)
		var key := "part:%d" % recipe
		if opening.building_hotbar.recipe_buttons.has(key) \
				and not opening.building_hotbar.recipe_buttons[key].visible:
			opening.building_hotbar.recipe_tabs[
				opening.building_hotbar._recipe_category(key, part.kind)].pressed.emit()
		if not _expect(opening.building_hotbar.recipe_buttons.has(key)
				and opening.building_hotbar.recipe_buttons[key].visible,
			"The selected type tab exposes the needed workshop recipe"):
			return
		var before: Dictionary = opening.model.projection()
		opening.building_hotbar.recipe_buttons[key].pressed.emit()
		opening.building_hotbar.catalog.hide()
		var after: Dictionary = opening.model.projection()
		if not _expect(after.order == before.order + 1
				and after.part_kits.P[part.kind] == before.part_kits.P[part.kind] + 1,
				"The workshop spends carried material for one native route part"):
			return
	if not await _approach_points([Vector2(1.1, 3.3), Vector2(0.0, 2.15)]):
		return
	if not _select_inventory_item("wheel"):
		return
	var wheel: Dictionary = _construct({"action": "place", "kind": "wheel", "cell": [-2, 1],
		"axis": "x", "level": 4})
	if wheel.is_empty() or not _select_inventory_item("drive"):
		return
	var first: Dictionary = _construct({"action": "place_shaft", "center": [-4, 4, 4],
		"axis": "x", "half_span": 2})
	var last: Dictionary = _construct({"action": "place_shaft", "center": [-4, 8, 8],
		"axis": "x", "half_span": 2})
	if first.is_empty() or last.is_empty() or not _select_inventory_item("belt"):
		return
	var before_order: int = int(opening.model.projection().order)
	opening._world_click(Vector2i.ZERO, str(first.entity))
	if not _expect(opening.transmission_controls._belt_start.get("id", "") == first.entity
			and opening.model.projection().part_kits.P.belt == 1
			and opening.model.projection().belt_spans.is_empty(),
			"The first ordinary belt click selects one shaft without spending a kit: "
			+ str(opening.transmission_controls._belt_start)):
		return
	if not await _expect_nonhorizontal_belt_preview(str(first.entity), str(last.entity),
			capture_prefix + "-incline-preview-eye.png" if not capture_prefix.is_empty() else ""):
		return
	opening._world_click(Vector2i.ZERO, str(last.entity))
	var built: Dictionary = opening.model.projection()
	if not _expect(built.order > before_order and built.belt_spans.size() == 1
			and built.part_kits.P.belt == 0 and built.part_kits.P.shaft == 0
			and built.part_kits.P.wheel == 0,
			"The second ordinary click pays for one inclined belt between the exact shafts"):
		return
	var span_id: String = str(built.belt_spans.keys()[0])
	var span: Dictionary = built.belt_spans[span_id]
	if not _expect(span.from == first.entity and span.to == last.entity
			and built.motion[first.entity].state == "rotating"
			and built.motion[last.entity].state == "rotating",
			"The waterwheel powers both ends of the native inclined route"):
		return
	var span_view: Node3D
	for child: Node in opening.transmission_presenter.get_children():
		if child is Node3D and child.get_meta("entity", "") == span_id:
			span_view = child
	if not _expect(span_view != null and span_view.get_node_or_null("Pick") != null,
			"The player-built inclined loop has a selectable rendered body"):
		return
	opening._select_tool("inspect")
	opening._world_click(Vector2i.ZERO, span_id)
	if not _expect(opening.selected == span_id
			and opening.inspector.text.begins_with("Mechanical belt\n"),
			"The ordinary inspect click identifies the native belt"):
		return
	if not await _approach(Vector2(1.1, 3.3)):
		return
	var save: Dictionary = opening._save_worksite()
	if not _expect(save.get("accepted", false) and save.get("native_preflight", {}).get("accepted", false),
			"The physical actor and exact paid incline pass native save preflight"):
		return
	facts["belt"] = {"span": span_id, "from": first.entity, "to": last.entity,
		"revision": built.revision, "save_slot": opening.save_slot}
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-incline-eye.png",
				Vector3(-1.65, 2.5, 2.5))
				and await _capture_nonhorizontal_incline_close(capture_prefix + "-incline-close.png"),
				"Retain passive actor-eye and close views of the paid incline"):
			return
	_record("pass")

func _arrival_nonhorizontal_power_reopen_run() -> void:
	var input := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="):
			input = argument.trim_prefix("--resume-input=")
	var saved: Variant = bytes_to_var(FileAccess.get_file_as_bytes(input).slice(
		"FACTORY-SAVE-1\n".length() + 65))
	var reopened: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and saved is Dictionary and saved.has("world")
			and _same(saved.world, opening.model.checkpoint().world)
			and _same(saved.actors, opening.actor_world.seeds)
			and reopened.actors.Q.ready and reopened.belt_spans.size() == 1,
			"A fresh scene restores the exact saved native world and physical worker seeds"):
		return
	var span_id: String = str(reopened.belt_spans.keys()[0])
	var span: Dictionary = reopened.belt_spans[span_id]
	var first: Dictionary = reopened.transmission_parts.get(span.from, {})
	var last: Dictionary = reopened.transmission_parts.get(span.to, {})
	var vertical: bool = (first.get("axis", -1) == 0 and last.get("axis", -1) == 0
		and first.get("center", []).size() == 3 and last.get("center", []).size() == 3
		and first.center[1] != last.center[1])
	var sideways: bool = (first.get("axis", -1) == 1 and last.get("axis", -1) == 1
		and first.get("center", []).size() == 3 and last.get("center", []).size() == 3
		and first.center[0] != last.center[0])
	if not _expect((vertical or sideways) and span.slots == [null, null]
			and reopened.part_kits.P.belt == 0,
			"The fresh projection retains one paid vertical or sideways power-only belt"):
		return
	var view: Node3D
	for child: Node in opening.transmission_presenter.get_children():
		if child is Node3D and child.get_meta("entity", "") == span_id:
			view = child
	if not _expect(view != null and view.get_node_or_null("Pick") != null,
			"The reopened power belt still has a selectable rendered body"):
		return
	opening._select_tool("inspect")
	opening._world_click(Vector2i.ZERO, span_id)
	if not _expect(opening.selected == span_id
			and opening.inspector.text.begins_with("Mechanical belt\n"),
			"The fresh inspector binds to the saved native belt identity"):
		return
	facts["belt"] = {"span": span_id, "vertical": vertical, "sideways": sideways,
		"revision": reopened.revision}
	_record("pass")

func _arrival_nonhorizontal_actor_block_run(capture_prefix: String) -> void:
	# A physically saved sideways route supplies its already paid belt and
	# shafts. Jumping the real worker into the corridor tests Host clearance;
	# the later step away proves a refusal does not spend or strand the kit.
	var start: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and start.first_plate_unlock and start.actors.Q.ready
			and opening.actor_world.bodies.P.is_on_floor()
			and opening.actor_world.bodies.Q.is_on_floor()
			and start.belt_spans.size() == 1 and start.part_kits.P.belt == 0,
			"The physically saved paid sideways belt reopens before the clearance check"):
		return
	var old_id: String = str(start.belt_spans.keys()[0])
	var old: Dictionary = start.belt_spans[old_id]
	var first: Dictionary = start.transmission_parts.get(old.from, {})
	var last: Dictionary = start.transmission_parts.get(old.to, {})
	if not _expect(first.get("axis", -1) == 1 and last.get("axis", -1) == 1
			and first.get("center", []) == [0, 4, 0]
			and last.get("center", []) == [4, 4, 0],
			"The saved route uses the two expected parallel upright shafts"):
		return
	var removed: Dictionary = _construct({"action": "remove_belt_span", "entity": old_id})
	if removed.is_empty():
		return
	if not _expect(opening.model.projection().part_kits.P.belt == 1
			and opening.model.projection().belt_spans.is_empty(),
			"Dismantling the route returns its one paid belt kit"):
		return
	if not await _approach(Vector2(0.825, -0.2)) or not _select_inventory_item("belt"):
		return
	opening._world_click(Vector2i.ZERO, str(old.from))
	var selection: String = opening.transmission_controls._belt_start.get("request", "")
	if not _expect(not selection.is_empty()
			and opening.model.projection().part_kits.P.belt == 1,
			"The first ordinary shaft click selects the saved endpoint without spending a kit"):
		return
	if not await _approach(Vector2(0.825, 1.2)):
		return
	if not await _expect_nonhorizontal_belt_preview(str(old.from), str(old.to),
			capture_prefix + "-preview-eye.png" if not capture_prefix.is_empty() else ""):
		return
	if not await _approach(Vector2(0.825, -0.2)):
		return
	# Keep the fixture motor authoritative while a passive graphical window
	# cannot supply keyboard focus to CharacterPresenter.
	var presenter_was_processing: bool = opening.character_presenter.is_physics_processing()
	opening.character_presenter.set_physics_process(false)
	var jumped := false
	for frame in range(30):
		var pulse: Dictionary = opening.actor_world.set_control("P", Vector2.ZERO, true)
		if not _expect(pulse.get("accepted", false), "The physical worker receives a real jump control"):
			return
		await physics_frame
		await process_frame
		if not opening.actor_world.bodies.P.is_on_floor():
			jumped = true
			break
	if not _expect(jumped, "The physical worker leaves the ground after the jump control"):
		return
	opening.actor_world.set_control("P", Vector2.ZERO, false)
	for frame in range(40):
		await physics_frame
		await process_frame
		if opening.actor_world.bodies.P.global_position.y > 2.0:
			break
	var body: Vector3 = opening.actor_world.bodies.P.global_position
	if not _expect(absf(body.x - 0.825) < 0.35 and absf(body.z) < 0.35
			and body.y > 2.0 and not opening.actor_world.bodies.P.is_on_floor(),
			"The native actor is physically airborne in the belt path before the second click: %s" %
			str([body, opening.actor_world.diagnostics("P")])):
		return
	var before: Dictionary = opening.model.projection()
	var refused: Dictionary = _issue({"action": "place_selected_belt_span",
		"from": str(old.from), "to": str(old.to), "selection": selection})
	if not _expect(not refused.get("accepted", false) and refused.get("reason", "") == "actor_occupied"
			and opening.model.projection().belt_spans.is_empty()
			and opening.model.projection().part_kits.P.belt == 1
			and opening.model.projection().revision == before.revision
			and opening.model.projection().cargo.P == before.cargo.P,
			"Native clearance refuses the body in the route without consuming the paid belt"):
		return
	opening._world_click(Vector2i.ZERO, str(old.to))
	if not _expect(opening.model.projection().belt_spans.is_empty()
			and opening.model.projection().part_kits.P.belt == 1
			and opening.transmission_controls._belt_start.get("id", "") == old.from
			and opening.status_refused
			and opening.status_label.text == "Move clear of the belt's path before connecting these shafts.",
			"The ordinary second click keeps its selection and explains the obstructed belt"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		if not _expect(await _capture_actor_area(capture_prefix + "-blocked-eye.png", Vector3(0.825, 2.5, 0.0)),
				"Retain the passive actor-eye obstruction cue"):
			return
	opening.actor_world.release_control("P")
	for frame in range(75):
		await physics_frame
		await process_frame
		if frame >= 45 and opening.actor_world.bodies.P.is_on_floor():
			break
	opening.character_presenter.set_physics_process(presenter_was_processing)
	if not await _approach(Vector2(0.825, 1.2)):
		return
	opening._world_click(Vector2i.ZERO, str(old.to))
	var clear: Dictionary = opening.model.projection()
	opening._refresh_machine_preview()
	if not _expect(clear.belt_spans.size() == 1 and clear.part_kits.P.belt == 0
			and clear.belt_spans.values()[0].from == old.from
			and clear.belt_spans.values()[0].to == old.to
			and not opening.machine_preview.visible,
			"Stepping out of the corridor lets the same selected shafts spend one kit"):
		return
	if not await _approach(Vector2(1.1, 3.3)):
		return
	var save: Dictionary = opening._save_worksite()
	if not _expect(save.get("accepted", false) and save.get("native_preflight", {}).get("accepted", false),
			"The recovered route and physical actor pass native save preflight"):
		return
	facts["actor_obstruction"] = {"refusal": refused.reason, "belt": str(clear.belt_spans.keys()[0]),
		"revision": clear.revision, "save_slot": opening.save_slot}
	_record("pass")

func _capture_nonhorizontal_incline_close(path: String, camera_position := Vector3(1.4, 4.0, 5.2),
		target := Vector3(-1.65, 2.5, 2.5)) -> bool:
	var view := SubViewport.new()
	view.size = Vector2i(1280, 800)
	view.world_3d = root.world_3d
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.fov = 64.0
	camera.position = camera_position
	camera.look_at(target)
	camera.make_current()
	for frame in 6:
		await process_frame
		await RenderingServer.frame_post_draw
	var captured: bool = view.get_texture().get_image().save_png(path) == OK
	view.queue_free()
	return captured

func _arrival_nonhorizontal_power_belt_run(capture_prefix: String) -> void:
	# A normal, paid incline is the input. Recover its parts through the same
	# native commands available to a player, then change the shaft arrangement.
	var sideways := mode == "arrival-nonhorizontal-sideways-resume"
	var start: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and start.first_plate_unlock and start.actors.Q.ready
			and opening.actor_world.bodies.P.is_on_floor()
			and opening.actor_world.bodies.Q.is_on_floor()
			and start.belt_spans.size() == 1 and start.part_kits.P.belt == 0,
			"The paid incline and both physical workers reopen before changing the route"):
		return
	var old_id: String = str(start.belt_spans.keys()[0])
	var old: Dictionary = start.belt_spans[old_id]
	if not _expect(old.slots == [null, null] and old.from != old.to,
			"The input route has two distinct shafts and no cargo to duplicate"):
		return
	if not await _approach(Vector2(0.0, 2.15)):
		return
	if _construct({"action": "remove_belt_span", "entity": old_id}).is_empty():
		return
	if _construct({"action": "remove", "entity": str(old.to)}).is_empty():
		return
	if sideways and _construct({"action": "remove", "entity": str(old.from)}).is_empty():
		return
	var recovered: Dictionary = opening.model.projection()
	if not _expect(recovered.belt_spans.is_empty() and recovered.part_kits.P.belt == 1
			and recovered.part_kits.P.shaft == (2 if sideways else 1),
			"Removing a paid belt refunds exactly its kit and the removed shaft kits"):
		return
	if not _select_inventory_item("drive"):
		return
	var first: Dictionary = {"entity": old.from}
	if sideways:
		first = _construct({"action": "place_shaft", "center": [0, 4, 0],
			"axis": "y", "half_span": 2})
	var last: Dictionary = _construct({"action": "place_shaft",
		"center": [4, 4, 0] if sideways else [-4, 8, 4],
		"axis": "y" if sideways else "x", "half_span": 2})
	if first.is_empty() or last.is_empty() or not _select_inventory_item("belt"):
		return
	var before_order: int = int(opening.model.projection().order)
	opening._world_click(Vector2i.ZERO, str(first.entity))
	if not _expect(opening.transmission_controls._belt_start.get("id", "") == first.entity
			and opening.model.projection().part_kits.P.belt == 1
			and opening.model.projection().belt_spans.is_empty(),
			"Selecting the first power shaft retains the belt kit until the route is confirmed"):
		return
	if sideways and not await _approach(Vector2(0.825, 1.2)):
		return
	if not await _expect_nonhorizontal_belt_preview(str(first.entity), str(last.entity),
			capture_prefix + ("-sideways-preview-eye.png" if sideways else "-vertical-preview-eye.png")
			if not capture_prefix.is_empty() else ""):
		return
	opening._world_click(Vector2i.ZERO, str(last.entity))
	var built: Dictionary = opening.model.projection()
	if not _expect(built.order > before_order and built.belt_spans.size() == 1
			and built.part_kits.P.belt == 0 and built.part_kits.P.shaft == 0,
			"Two ordinary shaft clicks spend one belt kit for the requested power route"):
		return
	var span_id: String = str(built.belt_spans.keys()[0])
	var span: Dictionary = built.belt_spans[span_id]
	if not _expect(span.from == first.entity and span.to == last.entity
			and span.slots == [null, null]
			and built.transmission_parts[first.entity].axis == (1 if sideways else 0)
			and built.transmission_parts[last.entity].axis == (1 if sideways else 0),
			"The native route joins the exact parallel shafts and carries no items"):
		return
	var refused: Dictionary = _issue({"action": "load_belt_slot", "entity": span_id,
		"slot": 1, "item": "product", "work_id": 0})
	if not _expect(not refused.get("accepted", false)
			and refused.get("reason", "") == "belt_path_cannot_carry"
			and opening.model.projection().cargo.P == built.cargo.P
			and opening.model.projection().belt_spans[span_id].slots == [null, null],
			"A power-only route refuses a carried plate without changing native custody"):
		return
	var span_view: Node3D
	for child: Node in opening.transmission_presenter.get_children():
		if child is Node3D and child.get_meta("entity", "") == span_id:
			span_view = child
	if not _expect(span_view != null and span_view.get_node_or_null("Pick") != null,
			"The player-built power loop has a selectable rendered body"):
		return
	opening._select_tool("inspect")
	opening._world_click(Vector2i.ZERO, span_id)
	if not _expect(opening.selected == span_id
			and opening.inspector.text.begins_with("Mechanical belt\n"),
			"Inspect identifies the exact native power belt"):
		return
	if not await _approach(Vector2(1.1, 3.3)):
		return
	var save: Dictionary = opening._save_worksite()
	if not _expect(save.get("accepted", false) and save.get("native_preflight", {}).get("accepted", false),
			"The physical worker and paid power route pass native save preflight"):
		return
	facts["belt"] = {"span": span_id, "from": first.entity, "to": last.entity,
		"revision": built.revision, "save_slot": opening.save_slot, "sideways": sideways}
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		var label := "sideways" if sideways else "vertical"
		if not _expect(await _capture_nonhorizontal_incline_close(capture_prefix + "-" + label + "-close.png",
				Vector3(4.0, 4.5, 7.0) if sideways else Vector3(1.4, 4.0, 5.2),
				Vector3(1.7, 2.5, 0.0) if sideways else Vector3(-1.65, 2.5, 2.5))
				and await _capture_actor_area(capture_prefix + "-" + label + "-eye.png",
					Vector3(2.0, 2.0, 0.0) if sideways else Vector3(-1.65, 3.2, 2.0)),
				"Retain passive close and actor-eye frames of the power route"):
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
		if not _expect(await _capture_component_close(id, capture_prefix + "-slide.png"),
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
	var first_plate_route := mode in ["arrival-first-plate", "arrival-first-plate-press"]
	var inventory = opening.building_hotbar
	var start: Dictionary = opening.model.projection()
	if not _expect((raised_snap or start.first_plate_unlock) and start.workshop_completed_actors.is_empty()
			and inventory.slots.all(func(slot: String) -> bool: return slot.is_empty()),
			"The native arrival starts with an empty hotbar and its expected plate gate"):
		return
	inventory.open_catalog()
	if raised_snap:
		inventory.recipe_tabs.machine.pressed.emit()
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
		{"kind": "anvil", "name": "Anvil", "card": "Anvil"},
		{"kind": "flat_head", "name": "Flat pressing head", "card": "Flat head"},
		{"kind": "wooden_slide", "name": "Wooden slide", "card": "Wooden slide"},
		{"kind": "hand_crank", "name": "Hand crank", "card": "Hand crank"}]:
		var key: String = "component:" + recipe.kind
		var tile: Button = inventory.recipe_buttons[key]
		var name_label: Label = inventory.recipe_names[key]
		var native_cost: Dictionary = start.component_recipes[recipe.kind]
		var ingredients := "%d timber + %d copper" % [native_cost.timber, native_cost.copper]
		var station := "Bench" if native_cost.copper > 0 else "Field or bench"
		if not _expect(tile.icon != null and tile.focus_mode == Control.FOCUS_ALL
				and tile.custom_minimum_size == inventory.material_buttons.timber.custom_minimum_size
				and name_label.is_visible_in_tree() and name_label.text == recipe.card
				and Rect2(Vector2.ZERO, tile.custom_minimum_size).encloses(name_label.get_rect())
				and tile.tooltip_text.begins_with(recipe.name + " · ")
				and tile.tooltip_text.contains(ingredients) and tile.tooltip_text.contains(station)
				and tile.accessibility_name.contains(ingredients)
				and tile.accessibility_name.contains(station),
			"The %s compact icon keeps its full native cost and crafting place in tooltip and focus text." % recipe.kind):
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
		if not await _approach(Vector2(5.7, 5.8)):
			return
		opening._select_tool("foundation")
		opening._world_click(Vector2i(3, 3))
		var placed_floor: bool = opening.model.projection().foundations.values().any(
			func(floor: Variant) -> bool:
				return floor.cell == [3, 3] and floor.level == OpeningGeometry.HEIGHT_DENOMINATOR)
		if not _expect(placed_floor,
			"The starter route places a raised foundation through its ordinary build tool: "
			+ opening.status_label.text):
			return
	if not await _approach(Vector2(5.6, 5.6) if raised_snap else Vector2(3.3, 3.3)):
		return
	var fitted: Dictionary = {}
	var rise := OpeningGeometry.HEIGHT_DENOMINATOR if raised_snap else 0
	var press_x := 32 if raised_snap else 8
	var press_z := 32 if raised_snap else 12
	var press_cell := Vector2i(8, 8) if raised_snap else Vector2i(2, 3)
	for part in [{"kind": "anvil", "center": [press_x, rise, press_z]},
			{"kind": "flat_head", "center": [press_x, rise + 1, press_z]},
			{"kind": "wooden_slide", "center": [press_x, rise + 2, press_z]}]:
		if not _select_inventory_item("component:" + part.kind):
			return
		var prior: Dictionary = opening.model.projection().placed_components
		if part.kind == "anvil" and raised_snap:
			opening.distance = 0.0
			opening._update_camera()
			var floor_target := Vector3(6.6, 0.75, 6.6)
			var floor_direction: Vector3 = (floor_target - opening.camera.global_position).normalized()
			opening.orbit_yaw = atan2(-floor_direction.x, -floor_direction.z)
			opening.orbit_pitch = asin(clampf(-floor_direction.y, -1.0, 1.0))
			opening._update_camera()
			await physics_frame
			var floor_screen: Vector2 = opening._pointed_screen_position()
			var floor_pointed: String = opening._screen_entity(floor_screen)
			var floor_cell: Vector2i = opening._screen_cell(floor_screen)
			opening._refresh_component_preview()
			if not _expect(floor_cell == press_cell
					and opening._component_place_center(floor_cell, floor_pointed) == part.center
					and opening.component_preview.visible and not opening.component_preview_blocked,
				"The actor-eye foundation pick shows a clear, floor-seated anvil ghost: "
				+ str({"cell": floor_cell, "expected": press_cell, "pointed": floor_pointed,
					"center": opening._component_place_center(floor_cell, floor_pointed),
					"preview": opening.component_preview.visible,
					"blocked": opening.component_preview_blocked})):
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
			"The physical worker places the %s on its shared-grid socket: %s" %
			[part.kind, str({"status": opening.status_label.text,
				"actor": opening.model.projection().actors.P.position,
				"center": part.center, "placed": after})]):
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
	if not await _approach_points([Vector2(4.95, 3.3), Vector2(1.65, 3.3),
			Vector2(1.65, 4.95)]):
		return
	if not _select_inventory_item("component:hand_crank"):
		return
	var west_port := [press_x - 4, rise + 4, press_z]
	var east_port := [press_x + 4, rise + 4, press_z]
	if not _expect(assembled.placed_components[fitted.wooden_slide].get("input_ports", [])
			== [west_port, east_port],
			"The fitted slide exposes two native full-U external crank ports"):
		return
	opening.component_nudge_active = true
	opening.component_nudge_center = east_port.duplicate()
	opening._refresh_component_preview()
	if not _expect(opening.component_preview.visible and not opening.component_preview_blocked
			and absf(opening.component_preview.rotation.y) < 0.001,
			"The east slide input exposes an outward fitted-crank preview"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		var preview_position: Array = assembled.placed_components[fitted.wooden_slide].position
		if not _expect(await _capture_actor_area(capture_prefix + "-crank-preview-east.png",
				Vector3(float(preview_position[0]) + OpeningGeometry.PITCH,
					float(preview_position[1]), float(preview_position[2]))),
				"Retain the east input preview in the ordinary scene"):
			return
	opening.component_nudge_center = west_port.duplicate()
	opening._refresh_component_preview()
	if not _expect(opening.component_preview.visible and not opening.component_preview_blocked
			and absf(absf(opening.component_preview.rotation.y) - PI) < 0.001,
			"The west slide input visibly reverses the crank fitting"):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		var preview_position: Array = assembled.placed_components[fitted.wooden_slide].position
		if not _expect(await _capture_actor_area(capture_prefix + "-crank-preview-west.png",
				Vector3(float(preview_position[0]) - OpeningGeometry.PITCH,
					float(preview_position[1]), float(preview_position[2]))),
				"Retain the west input preview in the ordinary scene"):
			return
	opening.component_nudge_center = west_port.duplicate()
	opening._world_click(press_cell, fitted.wooden_slide)
	opening.component_nudge_active = false
	opening.component_nudge_center.clear()
	var attached: Dictionary = opening.model.projection()
	if not _expect(attached.crank_items.values().any(func(item: Variant) -> bool:
			return item.attached_to == fitted.wooden_slide and item.port == west_port),
			"The ordinary component tool fits the finite crank at the west input for an east outlet: "
			+ str({"port": west_port, "status": opening.status_label.text,
				"cranks": attached.crank_items})):
		return
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		var slide_position: Array = attached.placed_components[fitted.wooden_slide].position
		if not _expect(await _capture_actor_area(capture_prefix + "-crank-fitted.png",
				Vector3(float(slide_position[0]) - OpeningGeometry.PITCH,
					float(slide_position[1]), float(slide_position[2]))),
				"Retain the fitted exterior crank in the ordinary scene view"):
			return
		if "--shaft-clip-probe" in OS.get_cmdline_user_args() and not _expect(
				await _capture_slide_shaft(str(fitted.wooden_slide), capture_prefix + "-shaft-close.png"),
				"Retain the fitted slide shaft at a fixed close view"):
			return
	if first_plate_route:
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
	if first_plate_route:
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
					return item.attached_to == fitted.wooden_slide and item.port == west_port)
				and cycled.workshop_completed_actors.is_empty(),
			"The worker turns the fitted crafted crank through the slide's integral input"):
			return
	var route: Dictionary = presses[0].auto_feed
	var feed: Dictionary = {}
	if first_plate_route:
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
	if not _expect((first_plate_route or feed.get("accepted", false))
			and loaded.cargo.P.raw == 0
			and loaded.sliding_press_assemblies[0].selected_exit == route.exit
			and loaded.workshop_completed_actors.is_empty(),
			"The worker feeds the last finite blank and retains its chosen outlet without unlocking parts"):
		return
	if first_plate_route:
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
		var pickup_cue := "Plate on the workbed. Aim at the offcuts and press [E]."
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
		if not await _approach(work_point + Vector2(1.65, 0.0)):
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
			"The standing worker points at the visible offcut without opening a press menu: "
			+ str({"pointed": pointed_drop, "formed": formed,
				"entity": opening._screen_entity(opening._pointed_screen_position()),
				"screen": opening._pointed_screen_position(),
				"actor": opening.model.projection().actors.P.position,
				"menu": opening.object_menu.visible})):
			return
		var pick_screen: Vector2 = opening._pointed_screen_position()
		var unrelated_machine := StaticBody3D.new()
		unrelated_machine.collision_layer = OpeningGeometry.MACHINE_LAYER
		unrelated_machine.collision_mask = 0
		var pick_blocker := CollisionShape3D.new()
		var blocker_box := BoxShape3D.new()
		blocker_box.size = Vector3.ONE * 0.25
		pick_blocker.shape = blocker_box
		unrelated_machine.add_child(pick_blocker)
		unrelated_machine.position = opening.camera.project_ray_origin(pick_screen) \
			+ opening.camera.project_ray_normal(pick_screen) * 0.6
		opening.add_child(unrelated_machine)
		await physics_frame
		if not _expect(opening._screen_loose_material(pick_screen).is_empty(),
			"An unrelated opaque machine still blocks pickup through the fitted press"):
			unrelated_machine.free()
			return
		unrelated_machine.free()
		await physics_frame
		if not _expect(opening._screen_loose_material(pick_screen) == formed,
			"Removing that unrelated blocker restores the visible workbed pickup"):
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
		if not _expect(inventory.recipe_category == "power"
				and inventory.recipe_tabs.power.button_pressed
				and inventory.recipe_buttons["component:wooden_cog"].visible
				and not inventory.recipe_buttons["component:wooden_frame"].visible
				and opening.goal_text.contains("Power"),
			"The native first-plate milestone opens the Power recipes first"):
			return
		inventory.recipe_tabs.power.grab_focus()
		await process_frame
		if not _expect(inventory.focus_description.text.contains("Power recipes")
				and inventory.recipe_tabs.power.accessibility_name == "Power recipe tab",
			"Keyboard focus names the current recipe category"):
			return
		inventory.recipe_tabs.machine.pressed.emit()
		inventory._focus_catalog_button(inventory.recipe_tabs.machine)
		await process_frame
		if not _expect(inventory.recipe_buttons["component:anvil"].visible
				and inventory.recipe_buttons["component:wooden_frame"].visible
				and not inventory.recipe_buttons["foundation"].visible
				and inventory.focus_description.text.contains("Machine parts recipes"),
			"Machine parts keeps the first press and collector recipes reachable"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-unlocked-machine.png") == OK,
					"Retain the Machine parts tab after native plate pickup"):
				return
		inventory.recipe_tabs.other.pressed.emit()
		inventory._focus_catalog_button(inventory.recipe_tabs.other)
		await process_frame
		if not _expect(inventory.recipe_buttons["foundation"].visible
				and inventory.material_buttons.products.visible
				and inventory.focus_description.text.contains("Other recipes"),
			"Other recipes remain reachable without filtering the carried plate"):
			return
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-unlocked-other.png") == OK,
					"Retain the Other tab and unfiltered carried stock after native plate pickup"):
				return
		inventory.recipe_tabs.power.pressed.emit()
		inventory.recipe_tabs.power.grab_focus()
		if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(
					capture_prefix + "-unlocked-catalog.png") == OK,
					"Retain the Power tab after native plate pickup"):
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
			var narrow_visible: bool = inventory.catalog.visible
			if not _expect(narrow_visible
					and inventory.recipe_category == "power"
					and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(narrow_rect)
					and narrow_capture == OK,
					"The ordinary Power recipes fit the narrow actor viewport: " +
				str({"popup": narrow_rect, "viewport": root.size,
					"visible": narrow_visible, "recipe_category": inventory.recipe_category})):
				return
			root.size = original_size
			await process_frame
			inventory._place_catalog()
		inventory.catalog.hide()
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		var frame_name := "-first-plate.png" if first_plate_route else "-starter-press.png"
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
	if mode == "arrival-first-plate-press":
		_record("pass")
		return
	if mode == "arrival-first-plate" and not await _postplate_belt_project_run(capture_prefix):
		return
	_record("pass")

func _postplate_belt_project_run(capture_prefix: String) -> bool:
	# The earlier save remains the first-plate continuation. Build a collector
	# afterward so the suggested next project reads an actual native assembly.
	var before_project: Dictionary = opening.model.projection()
	for harvest in [
		{"point": Vector2(6.0, 3.45), "source": "tree-east-south", "cuts": 3},
		{"point": Vector2(6.0, 11.55), "source": "tree-east-north", "cuts": 7},
		{"point": Vector2(-0.5, 0.0), "source": "opening-copper", "cuts": 1},
	]:
		var reached := false
		if harvest.source == "opening-copper":
			reached = await _approach_points([Vector2(4.95, 9.9), Vector2(4.95, 3.3),
				Vector2(4.95, 0.0), Vector2(0.0, 0.0), Vector2(0.0, 1.65), harvest.point])
		else:
			reached = await _approach(harvest.point)
		if not reached:
			return false
		for index in range(harvest.cuts):
			if _construct({"action": "harvest_source", "target": harvest.source}).is_empty():
				return false
	if not await _approach_points([Vector2(0.0, 1.65), Vector2(0.0, 0.0),
			Vector2(4.95, 0.0), Vector2(4.95, 3.3), Vector2(4.95, 6.6)]):
		return false
	if not _expect(opening._can_choose_tool(),
			"The plate owner's Build controls are available after the saved first workshop: " +
			str({"pause": opening.pause_menu.visible, "log": opening.manager_log_open,
				"explanation": opening.explanation_open, "catalog": opening.building_hotbar.catalog.visible,
				"actor": opening.state.get("actors", {}).get("P", {})})):
		return false
	var hub: String = str(opening.model.projection().fabrication_hub.id)
	for recipe in ["foundation", "component:wooden_frame", "component:tool_mount",
			"component:cutting_edge", "component:receiver_tray", "component:wooden_shaft"]:
		var before_craft: Dictionary = opening.model.projection()
		if not _press_inventory_recipe(recipe, hub):
			return false
		var after_craft: Dictionary = opening.model.projection()
		if not _expect(after_craft.order == before_craft.order + 1 and not opening.status_refused,
				"The ordinary bench crafts one native " + recipe + ": " + str({
					"before": before_craft.order, "after": after_craft.order,
					"context": opening.building_hotbar.context_bench,
					"focus": opening.building_hotbar.focus_description.text,
					"status": opening.status_label.text})):
			return false
	var prepared: Dictionary = opening.model.projection()
	if not _expect(prepared.part_kits.P.foundation == before_project.part_kits.P.foundation + 1
			and ["wooden_frame", "tool_mount", "cutting_edge", "receiver_tray", "wooden_shaft"].all(
				func(kind: String) -> bool: return int(prepared.cargo.P.components.get(kind, 0)) == \
					int(before_project.cargo.P.components.get(kind, 0)) + 1),
			"Finite local stock becomes exactly one foundation and the five collector components: " +
			str({"before_foundation": before_project.part_kits.P.foundation,
				"after_foundation": prepared.part_kits.P.foundation,
				"before_components": before_project.cargo.P.components,
				"after_components": prepared.cargo.P.components})):
		return false
	if not await _approach_points([Vector2(4.95, 3.3), Vector2(4.95, 0.0),
			Vector2(0.0, 0.0), Vector2(0.0, 1.65), Vector2(-2.25, 2.475)]):
		return false
	if _construct({"action": "place_foundation", "cell": [0, 1], "level": 4}).is_empty():
		return false
	for component in [
		{"kind": "wooden_frame", "center": [0, 4, 4]},
		{"kind": "tool_mount", "center": [-1, 4, 4]},
		{"kind": "cutting_edge", "center": [-2, 4, 4]},
		{"kind": "receiver_tray", "center": [0, 4, 3]},
		{"kind": "wooden_shaft", "center": [1, 4, 4]},
	]:
		if _construct({"action": "place_component", "component": component.kind,
				"center": component.center}).is_empty():
			return false
	var built: Dictionary = opening.model.projection()
	if not _expect(built.collector_assemblies.any(func(item: Variant) -> bool:
			return item is Dictionary and item.get("status") == "ready")
			and built.workshop_completed_actors.has("P") and built.cargo.P.products == 1,
			"The original plate owner has a native ready collector without consuming the first plate"):
		return false
	var inventory = opening.building_hotbar
	inventory.open_catalog()
	if not _expect(inventory.recipe_category == "logistics"
			and inventory.recipe_tabs.logistics.button_pressed
			and not inventory.recipe_buttons.foundation.visible
			and not inventory.recipe_buttons["component:wooden_cog"].visible
			and not inventory.recipe_buttons["component:wooden_frame"].visible
			and inventory.material_buttons.products.visible
			and opening.goal_text.contains("Logistics"),
			"A physical first-plate worker sees Logistics after building the collector"):
		return false
	var belt_recipe := -1
	for index in built.part_recipes.size():
		if built.part_recipes[index].kind == "belt":
			belt_recipe = index
			break
	if not _expect(belt_recipe >= 0 and inventory.recipe_buttons["part:%d" % belt_recipe].visible,
			"The next suggested group includes the native belt-span recipe"):
		return false
	inventory.recipe_tabs.logistics.grab_focus()
	await process_frame
	if not _expect(inventory.focus_description.text.contains("Logistics recipes")
			and inventory.recipe_tabs.logistics.accessibility_name == "Logistics recipe tab",
			"The real post-collector tab gives keyboard focus a readable recipe category"):
		return false
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(
				capture_prefix + "-postcollector-build.png") == OK,
				"Retain the native post-collector Build window at normal actor size"):
			return false
	inventory.recipe_tabs.machine.pressed.emit()
	inventory._focus_catalog_button(inventory.recipe_tabs.machine)
	await process_frame
	if not _expect(inventory.recipe_buttons["component:anvil"].visible
			and inventory.recipe_buttons["component:wooden_frame"].visible
			and inventory.material_buttons.products.visible
			and inventory.focus_description.text.contains("Machine parts recipes"),
			"Machine parts still exposes the old press and another collector without filtering Carried"):
		return false
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(
				capture_prefix + "-postcollector-machine.png") == OK,
				"Retain the native post-collector Machine parts window"):
			return false
	inventory.recipe_tabs.logistics.pressed.emit()
	inventory._focus_catalog_button(inventory.recipe_tabs.logistics)
	await process_frame
	if not _expect(inventory.recipe_category == "logistics"
			and inventory.focus_description.text.contains("Logistics recipes"),
			"The selected Logistics tab returns before the narrow Build capture"):
		return false
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		var original_size: Vector2i = root.size
		root.size = Vector2i(900, 600)
		for frame in range(3):
			await process_frame
		inventory._place_catalog()
		await RenderingServer.frame_post_draw
		if not _expect(inventory.catalog.visible and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
				Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size)))
				and root.get_texture().get_image().save_png(
					capture_prefix + "-postcollector-build-narrow.png") == OK,
				"Retain the native belt-route Build group inside the narrow actor viewport"):
			return false
		root.size = original_size
		await process_frame
	inventory._close_catalog()
	# A resize while the popup was visible can leave its deferred layout
	# coroutine waiting for one more frame; let it finish before scene teardown.
	await process_frame
	await process_frame
	opening.configure_save_slot(destination + ".postcollector.worksite")
	var saved: Dictionary = opening._save_worksite()
	if not _expect(saved.get("accepted", false) and saved.get("native_preflight", {}).get("accepted", false),
			"The built collector and first plate retain native custody in a separate save"):
		return false
	var reopened := NativeModel.new(opening.model.context, ["P"], true)
	var readback: Dictionary = Store.read_into(reopened, opening.save_slot)
	var restored: Dictionary = reopened.projection()
	return _expect(readback.get("accepted", false) and restored.cargo == built.cargo
		and restored.placed_components == built.placed_components
		and restored.workshop_completed_actors.has("P")
		and restored.collector_assemblies.any(func(item: Variant) -> bool:
			return item is Dictionary and item.get("status") == "ready"),
		"A fresh native model reads the saved plate owner and ready collector without changing custody")

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
	if mode in ["arrival-nonhorizontal-incline", "arrival-nonhorizontal-vertical-resume", "arrival-nonhorizontal-sideways-resume", "arrival-nonhorizontal-power-reopen-resume", "arrival-nonhorizontal-actor-block-resume"]:
		deadline = Time.get_ticks_msec() + 300000
	if mode == "arrival-raised-starter-belt":
		deadline = Time.get_ticks_msec() + 180000
	if mode in ["arrival-belt", "arrival-belt-controls", "arrival-craft-capacity"]:
		deadline = Time.get_ticks_msec() + 180000
	var capture_prefix := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arrival-capture-prefix="):
			capture_prefix = argument.trim_prefix("--arrival-capture-prefix=")
	if destination.is_empty() or mode not in ["arrival-mature-trees", "arrival-mature-trees-resume", "arrival-starter-assembly", "arrival-first-plate", "arrival-first-plate-press", "arrival-raised-starter-snap", "arrival-raised-starter-belt", "arrival-blocked-feed-cue", "arrival-first-plate-resume", "arrival-nonhorizontal-incline", "arrival-nonhorizontal-vertical-resume", "arrival-nonhorizontal-sideways-resume", "arrival-nonhorizontal-power-reopen-resume", "arrival-nonhorizontal-actor-block-resume", "arrival-slide", "arrival-joined-broad", "arrival-joined-broad-slab", "supplied-hardware", "arrival-craft-capacity", "arrival-craft-capacity-resume", "arrival-field-craft", "arrival-foundation-craft", "arrival-foundation-craft-resume", "arrival-portable-workbench", "arrival-pod-workshop", "arrival-pod-workshop-resume", "arrival-belt", "arrival-belt-controls", "arrival-belt-resume", "arrival-cancel-placement", "arrival-reveal", "arrival-reveal-skip"] or FileAccess.file_exists(destination):
		push_error("Arrival press check requires an unused output and a declared mode")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	var advanced_fixture := mode not in ["arrival-mature-trees", "arrival-mature-trees-resume", "arrival-starter-assembly", "arrival-first-plate", "arrival-first-plate-press", "arrival-blocked-feed-cue", "arrival-first-plate-resume", "arrival-nonhorizontal-incline", "arrival-nonhorizontal-vertical-resume", "arrival-nonhorizontal-sideways-resume", "arrival-nonhorizontal-power-reopen-resume", "arrival-nonhorizontal-actor-block-resume", "arrival-reveal", "arrival-reveal-skip"]
	# Channel command fixtures deliberately exercise developer diagnostics.
	# Ordinary players pick up pointed material with E and never issue pushes.
	opening.developer_material_tools = false
	if mode in ["arrival-nonhorizontal-incline", "arrival-nonhorizontal-vertical-resume", "arrival-nonhorizontal-sideways-resume", "arrival-nonhorizontal-power-reopen-resume", "arrival-nonhorizontal-actor-block-resume"]:
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
	opening.arrival_reveal_probe = mode == "arrival-reveal-skip"

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
			and opening.landing_hub_visual.position.distance_to(Vector3(4.125, 0, 6.6)) < 0.001,
			"The unchanged pod and east bench meet the native foundation top plane"):
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
	if mode in ["arrival-starter-assembly", "arrival-first-plate", "arrival-first-plate-press", "arrival-raised-starter-snap", "arrival-raised-starter-belt", "arrival-blocked-feed-cue"]:
		await _arrival_starter_assembly_run(capture_prefix)
		return
	if mode == "arrival-first-plate-resume":
		await _arrival_first_plate_resume_run(capture_prefix)
		return
	if mode == "arrival-nonhorizontal-incline":
		await _arrival_nonhorizontal_incline_run(capture_prefix)
		return
	if mode in ["arrival-nonhorizontal-vertical-resume", "arrival-nonhorizontal-sideways-resume"]:
		await _arrival_nonhorizontal_power_belt_run(capture_prefix)
		return
	if mode == "arrival-nonhorizontal-power-reopen-resume":
		await _arrival_nonhorizontal_power_reopen_run()
		return
	if mode == "arrival-nonhorizontal-actor-block-resume":
		await _arrival_nonhorizontal_actor_block_run(capture_prefix)
		return
	if mode == "arrival-slide":
		await _arrival_slide_run(panel, capture_prefix)
		return
	if mode in ["arrival-joined-broad", "arrival-joined-broad-slab"]:
		await _arrival_joined_broad_run(capture_prefix, mode == "arrival-joined-broad-slab")
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
	push_error("The selected arrival fixture is unavailable")
	quit(1)
