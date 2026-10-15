extends SceneTree
## Actual input and raw native facts. This observer never moves a player/body.
var scene
var checks := 0
var failures: Array[String] = []
var frames: Array = []
var provisional_frames: Array = []
var waiting: Array = []
var advanced_events: Array = []
var view_frames: Array = []
var observed_moves := 0
var finish_requested := false
var capturing := true
var report_written := false
var last_render_key := ""
var cases := {}
var stage := "startup"

class ViewObserver extends Node:
	var sample: Callable
	func _process(_delta: float) -> void:
		sample.call()

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func shape_data(value):
	if value is Vector3:
		return array(value)
	if value is Vector2:
		return [value.x, value.y]
	return value

func native(body: PhysicsBody3D) -> Dictionary:
	var rid := body.get_rid()
	var pose: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var shape := PhysicsServer3D.body_get_shape(rid, 0)
	return {"id": body.get_instance_id(), "rid": rid.get_id(), "position": array(pose.origin),
		"basis": [array(pose.basis.x), array(pose.basis.y), array(pose.basis.z)],
		"linear_velocity": array(PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)),
		"angular_velocity": array(PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)),
		"node_position": array(body.global_position), "shape_type": PhysicsServer3D.shape_get_type(shape),
		"shape_data": shape_data(PhysicsServer3D.shape_get_data(shape)),
		"layer": PhysicsServer3D.body_get_collision_layer(rid), "mask": PhysicsServer3D.body_get_collision_mask(rid)}

func facts() -> Dictionary:
	var player = scene.player
	var player_mesh := Vector3.ZERO
	for child in player.get_children():
		if child is MeshInstance3D:
			player_mesh = child.global_position
	var collisions: Array = []
	for index in range(player.get_slide_collision_count()):
		var collision: KinematicCollision3D = player.get_slide_collision(index)
		collisions.append({"id": collision.get_collider_id(), "normal": array(collision.get_normal()), "point": array(collision.get_position())})
	return {"stage": stage, "ticks": player.ticks, "walking_seconds": player.walking_seconds,
		"scene": scene.scene_file_path,
		"delta": player.get_physics_process_delta_time(),
		"player": native(player), "deck": native(scene.authority.bodies.B),
		"ground_id": scene.ground.get_instance_id(), "wall_id": scene.wall.get_instance_id(),
		"on_floor": player.is_on_floor(), "floor_id": player.floor_id,
		"floor_normal": array(player.get_floor_normal()), "platform_velocity": array(player.get_platform_velocity()),
		"platform_angular_velocity": array(player.get_platform_angular_velocity()),
		"velocity": array(player.velocity), "input": [player.input_direction.x, player.input_direction.y],
		"follow_layers": player.platform_floor_layers, "collisions": collisions,
		"player_mesh": array(player_mesh), "deck_mesh": array(scene.deck_mesh.position),
		"deck_visible": scene.deck_mesh.visible, "view_status": scene.stats.text,
		"deck_mesh_basis": [array(scene.deck_mesh.basis.x), array(scene.deck_mesh.basis.y), array(scene.deck_mesh.basis.z)],
		"state": scene.authority.projection()}

func observe() -> void:
	# A callback-local Node transform is still provisional: SceneTree flushes
	# transform notifications AFTER its deferred callback queue. Keep this cut.
	if not capturing:
		return
	observed_moves += 1
	if provisional_frames.size() < 2000:
		var value := facts()
		value["engine_frame"] = Engine.get_physics_frames()
		provisional_frames.append(value)
		waiting.append(value)

func observe_completed() -> void:
	# NEXT physics_frame: prior transforms naturally flushed; new controller
	# callbacks have not run. This works even with many physics ticks per draw.
	if not is_instance_valid(scene):
		return
	if not waiting.is_empty():
		check(waiting.size() == 1, "No physics observations coalesce before natural native completion")
	for requested in waiting:
		var observed := facts()
		var value: Dictionary = requested.duplicate(true)
		value["player"] = observed.player
		value["deck"] = observed.deck
		value["player_mesh"] = observed.player_mesh
		value["deck_mesh"] = observed.deck_mesh
		value["observer_state"] = observed.state
		value["observer_tick"] = observed.ticks
		value["observed_engine_frame"] = Engine.get_physics_frames()
		value["state_cut"] = "requested_player_move_before_its_natural_transform_flush"
		value["requested_tick"] = requested.ticks
		value["requested_id"] = requested.player.id
		value["requested_position"] = requested.player.node_position
		value["stage"] = requested.stage
		check(observed.ticks == requested.ticks and value.player.id == requested.player.id
			and value.observed_engine_frame == requested.engine_frame + 1,
			"Natural native completion belongs to the exact requested player and physics tick")
		frames.append(value)
	waiting.clear()
	if finish_requested:
		_finish()

func observe_view() -> void:
	# Presentation consumes the latest native input epoch at its own cadence.
	# Fewer rendered frames never remove a physics completion from the stream.
	if not capturing or not is_instance_valid(scene) or scene.player.ticks == 0:
		return
	var key := str(scene.player.get_instance_id()) + ":" + str(scene.player.ticks)
	if key == last_render_key:
		return
	last_render_key = key
	view_frames.append(facts())

func hold(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func key(code: Key) -> void:
	await hold(code, true)
	await hold(code, false)

func click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func ticks(count: int) -> void:
	var end: int = scene.player.ticks + count
	while scene.player.ticks < end:
		await physics_frame
		await process_frame

func _scene_path() -> String:
	return "res://rider/main.tscn"

func fresh() -> void:
	if scene != null:
		# Close this finite observation epoch and drain its last target before
		# the explicit fresh scene frees that native body.
		capturing = false
		await physics_frame
		check(waiting.is_empty(), "Fresh scene preserves the prior epoch's last native completion")
		scene.queue_free()
	await process_frame
	stage = "startup"
	scene = load(_scene_path()).instantiate()
	root.add_child(scene)
	current_scene = scene
	capturing = true
	scene.player.moved.connect(observe)
	scene.authority.advanced.connect(record_advance)
	await ticks(8)
	check(scene.player.get_parent() == scene and scene.player.get_parent() != scene.authority.bodies.B,
		"Actual player is a separate collision body, never parented to the deck")
	check(scene.player.is_on_floor() and scene.player.floor_id == scene.ground.get_instance_id(), "Fresh player stands on native fixed ground")
	check(not scene.authority.running and scene.authority.committed == 0, "Fresh source starts paused")

func board() -> void:
	stage = "board"
	await hold(KEY_D, true)
	await key(KEY_SPACE)
	await ticks(25)
	await hold(KEY_D, false)
	for index in range(100):
		if scene.player.is_on_floor() and scene.player.floor_id == scene.authority.bodies.B.get_instance_id():
			break
		await ticks(1)
	check(scene.player.is_on_floor() and scene.player.floor_id == scene.authority.bodies.B.get_instance_id(),
		"Real walk/jump input boards the stopped native deck")
	await hold(KEY_D, true)
	for index in range(60):
		if scene.player.position.x >= -0.4:
			break
		await ticks(1)
	await hold(KEY_D, false)
	await ticks(4)
	check(scene.player.is_on_floor() and scene.player.floor_id == scene.authority.bodies.B.get_instance_id()
		and scene.player.position.x >= -0.41 and scene.player.position.x < -0.25,
		"Ordinary walk input places rider near deck center without scripted boarding")

func check_deck_pose(value: Dictionary, at_advance: bool) -> void:
	var expected := 2 * sin(float(value.state.phases.B))
	check(absf(value.deck.position[0] - expected) < 0.00002, "Native deck pose matches inherited source phase")
	if at_advance:
		check(absf(value.state.completed.positions.B[0] - expected) < 0.00002
			and absf(value.deck_mesh[0] - expected) < 0.00002,
			"Exact Drive advanced boundary has matching completed and view deck poses")

func record_advance(_outcome: Dictionary) -> void:
	var at_advance := facts()
	at_advance["cut"] = "drive_only_advanced_before_player_callback"
	advanced_events.append(at_advance)
	check_deck_pose(at_advance, true)

func step(button := false) -> void:
	var outcome := {}
	scene.authority.advanced.connect(func(value: Dictionary): outcome["value"] = value, CONNECT_ONE_SHOT)
	if button:
		await click(scene.step_button)
	else:
		await key(KEY_N)
	for index in range(30):
		if not outcome.is_empty():
			break
		await ticks(1)
	check(not outcome.is_empty() and outcome.value.accepted, "Actual source input completes one native drive operation")
	await ticks(4)
	var value := facts()
	check(not value.state.native_pending, "Completed source publication is settled in actual native world")
	check_deck_pose(value, false)
	check(value.player.position == value.player.node_position, "Player view transform and raw native RID pose agree")

func start_observers() -> void:
	root.size = Vector2i(1280, 800)
	physics_frame.connect(observe_completed)
	var observer := ViewObserver.new()
	observer.sample = observe_view
	observer.process_priority = 1000
	root.add_child(observer)

func _run() -> void:
	start_observers()
	await fresh()
	cases.initial = facts()
	await key(KEY_N)
	check(not scene.last_result.accepted and scene.last_result.reason == "source_stopped", "Paused drive refuses a real N input")
	await board()
	cases.boarded = facts()
	var relative: float = scene.player.position.x - scene.authority.bodies.B.position.x
	stage = "standing"
	await click(scene.run_button)
	for index in range(8):
		await step(index == 0)
		var value := facts()
		check(value.on_floor and value.floor_id == value.deck.id, "Standing rider remains on the real moving deck")
		check(absf(value.player.position[0] - value.deck.position[0] - relative) <= 0.015,
			"Native platform following carries standing rider within declared drift bound")
	cases.carried = facts()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture="):
				check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "Actual standing native passenger viewport capture")
	stage = "walk_reversal"
	var before_walk := facts()
	await hold(KEY_D, true)
	await step()
	await ticks(8)
	await hold(KEY_D, false)
	await ticks(4)
	var after_walk := facts()
	var actual_walk: float = after_walk.player.position[0] - after_walk.deck.position[0] - before_walk.player.position[0] + before_walk.deck.position[0]
	var expected_walk: float = 2 * (after_walk.walking_seconds - before_walk.walking_seconds)
	check(after_walk.deck.position[0] < before_walk.deck.position[0] and actual_walk > 0.2
		and absf(actual_walk - expected_walk) < 0.02, "Actual walking remains independent while native deck reverses")
	cases.walk = {"before": before_walk, "after": after_walk}
	await click(scene.run_button)
	await ticks(8)
	stage = "paused"
	var paused := facts()
	await ticks(12)
	check(scene.authority.projection() == paused.state and scene.player.position.distance_to(Vector3(paused.player.position[0], paused.player.position[1], paused.player.position[2])) < 0.00002,
		"Pausing drive retains deck phase and settled rider pose")
	cases.paused = facts()
	stage = "jump"
	await key(KEY_SPACE)
	await ticks(12)
	check(not scene.player.is_on_floor() and scene.player.position.y > 2.5, "Space jumps the actual colliding player off the paused deck")
	cases.air = facts()
	for index in range(100):
		if scene.player.is_on_floor():
			break
		await ticks(1)
	check(scene.player.floor_id == scene.authority.bodies.B.get_instance_id(), "Native gravity lands player back on same deck")
	cases.landed = facts()
	stage = "step_off"
	await hold(KEY_D, true)
	for index in range(160):
		if scene.player.is_on_floor() and scene.player.floor_id == scene.ground.get_instance_id():
			break
		await ticks(1)
	await hold(KEY_D, false)
	await ticks(4)
	check(scene.player.is_on_floor() and scene.player.floor_id == scene.ground.get_instance_id(), "Ordinary walk input leaves deck and lands on fixed ground")
	cases.off = facts()
	stage = "wall"
	await hold(KEY_D, true)
	await ticks(90)
	await hold(KEY_D, false)
	await ticks(4)
	check(absf(scene.player.position.x - 4.575) < 0.015 and scene.player.is_on_floor(), "Real character collision stops ground walking at fixed solid boundary")
	cases.wall = facts()
	for name in ["carried", "paused", "air", "landed", "off", "wall"]:
		check(cases[name].player.id == cases.boarded.player.id and cases[name].player.rid == cases.boarded.player.rid
			and cases[name].deck.id == cases.boarded.deck.id and cases[name].deck.rid == cases.boarded.deck.rid,
			"Same native player/deck identities survive all carry and leave operations")
	stage = "follow_disabled"
	await fresh()
	await board()
	stage = "follow_disabled"
	# Additional native API control, explicitly not normal product input.
	scene.player.platform_floor_layers = 0
	await ticks(3)
	var excluded_before := facts()
	await key(KEY_F)
	await step()
	await step()
	var excluded_after := facts()
	check(absf(excluded_after.player.position[0] - excluded_before.player.position[0]) < 0.015
		and excluded_after.deck.position[0] - excluded_before.deck.position[0] > 0.7,
		"Disabling native platform following distinguishes carry from parenting/manual offsets")
	cases.follow_disabled = {"before": excluded_before, "after": excluded_after}
	capturing = false
	finish_requested = true

func _finish() -> void:
	if report_written:
		return
	report_written = true
	check(observed_moves < 2000 and frames.size() == observed_moves and provisional_frames.size() == observed_moves
		and waiting.is_empty(), "Every provisional physics tick has one natural native completion; no loss or truncation")
	var report := {"status": "pass" if failures.is_empty() else "fail", "checks": checks, "failures": failures,
		"cases": cases, "frames": frames, "provisional_frames": provisional_frames,
		"advanced_events": advanced_events, "observed_moves": observed_moves}
	report["view_frames"] = view_frames
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report))
	print("RIDER_PASS" if failures.is_empty() else "RIDER_FAIL")
	quit(0 if failures.is_empty() else 1)
