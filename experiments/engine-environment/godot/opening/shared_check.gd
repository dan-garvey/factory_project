extends SceneTree
## Test-only local input controller for the real OpeningShared scene.
## The normal scene never reads these files. There is no test/admin game RPC.
const KEYS := {"1": KEY_1, "2": KEY_2, "3": KEY_3, "4": KEY_4,
	"5": KEY_5, "6": KEY_6, "7": KEY_7, "8": KEY_8, "B": KEY_B,
	"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D, "P": KEY_P,
	"F": KEY_F, "G": KEY_G, "R": KEY_R, "H": KEY_H,
	"SPACE": KEY_SPACE, "F5": KEY_F5, "F9": KEY_F9, "ESCAPE": KEY_ESCAPE,
	"RIGHT": KEY_RIGHT, "LEFT": KEY_LEFT, "HOME": KEY_HOME}
const BUTTONS := ["confirm_button", "retrieve_button", "remove_button",
	"save_button", "load_button", "reconnect_button", "disconnect_button",
	"catalog_button",
	"lesson_next", "lesson_previous", "lesson_return"]
var scene
var control_root := ""
var last_id := 0
var busy := false
var started := 0
var checks := 0
var defer_connect := false
var fatal := false
var transport_disconnect_reason := ""
var wire_control_probe: Dictionary = {}
var ui_readiness: Dictionary = {}
var button_probe: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")
	process_frame.connect(_poll)

func _run() -> void:
	started = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-control-root="):
			control_root = argument.trim_prefix("--ui-control-root=")
		elif argument == "--ui-defer-connect":
			defer_connect = true
	if not control_root.is_absolute_path() or not DirAccess.dir_exists_absolute(control_root):
		fail("Owned absolute --ui-control-root directory is required")
		return
	root.size = Vector2i(1280, 800)
	scene = load("res://opening/shared_opening.tscn").instantiate()
	scene.connect_on_ready = not defer_connect
	root.add_child(scene)
	scene.session.disconnected.connect(func(reason: String): transport_disconnect_reason = reason)
	current_scene = scene
	await process_frame
	await physics_frame
	await RenderingServer.frame_post_draw
	ui_readiness = {"process_frame": Engine.get_process_frames(),
		"window_size": [root.size.x, root.size.y], "window_focused": root.has_focus()}
	print("OPENING_UI_READY " + JSON.stringify(facts()))

func _poll() -> void:
	if scene == null or fatal:
		return
	if Time.get_ticks_msec() - started > 240000:
		fail("Automated UI controller reached its four-minute allowance")
		return
	if busy or ui_readiness.is_empty():
		return
	var path := control_root.path_join("control.json")
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 65536:
		fail("Invalid or oversized owned UI control")
		return
	var command = JSON.parse_string(file.get_as_text())
	if not command is Dictionary or not command.has("id"):
		fail("Invalid UI control dictionary")
		return
	var sequence := int(command.id)
	if sequence <= last_id:
		return
	if sequence != last_id + 1 or sequence > 512:
		fail("UI control sequence must advance once")
		return
	last_id = sequence
	busy = true
	call_deferred("execute", command)
	return

func key(code: Key) -> void:
	await key_edge(code, true)
	await key_edge(code, false)

func key_edge(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func click(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await physics_frame
	await process_frame

func button_state(button: Button) -> Dictionary:
	var rectangle := button.get_global_rect()
	return {"rect": [rectangle.position.x, rectangle.position.y, rectangle.size.x, rectangle.size.y],
		"visible": button.is_visible_in_tree(), "disabled": button.disabled,
		"window_focused": root.has_focus(), "process_frame": Engine.get_process_frames()}

func click_button(name: String) -> bool:
	# Sample rendered geometry and observe the real signal from one ordinary click.
	# These observations do not identify the cause of a historical missed click.
	await RenderingServer.frame_post_draw
	button_probe = {"id": last_id, "button": name, "pressed_count": 0}
	var button: Button = scene.get(name)
	if button == null:
		fail("UI button does not exist: " + name)
		return false
	button_probe["before"] = button_state(button)
	var rectangle := button.get_global_rect()
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	if not button.is_visible_in_tree() or rectangle.size.x <= 0 or rectangle.size.y <= 0 or not viewport.encloses(rectangle):
		fail("UI button has no usable rendered bounds: " + name)
		return false
	var at := rectangle.get_center()
	button_probe["point"] = [at.x, at.y]
	var observed_pressed: Callable = func() -> void:
		button_probe.pressed_count += 1
	button.pressed.connect(observed_pressed)
	await click(at)
	button.pressed.disconnect(observed_pressed)
	button_probe["after"] = button_state(button)
	var expected := 0 if button_probe.before.disabled else 1
	if button_probe.pressed_count != expected:
		fail("UI button activation count differs from its rendered enabled state: " + name)
		return false
	return true

func _barrier(command: Dictionary) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		var ready: bool = scene.session.is_ready()
		var snapshot: Dictionary = scene.session.projection()
		var matched := false
		match command.get("condition", ""):
			"ready": matched = ready
			"settled": matched = ready and scene.pending_actions.is_empty()
			"disconnected": matched = not ready and not scene.connecting
			"output": matched = ready and snapshot.get("stock", {}).get("output", 0) >= int(command.get("minimum", 1))
			"inventory": matched = ready and snapshot.get("inventories", {}).get(scene.client, 0) >= int(command.get("minimum", 1))
			"revision": matched = ready and snapshot.get("revision", -1) >= int(command.get("minimum", 0))
			"actor_epoch":
				var actor: Dictionary = snapshot.get("actors", {}).get(scene.client, {})
				matched = ready and actor.get("ready", false) and actor.get("native_epoch", 0) >= int(command.get("minimum", 1))
			"actor_coordinate":
				var axis := int(command.get("axis", -1))
				var actor: Dictionary = snapshot.get("actors", {}).get(scene.client, {})
				if not axis in [0, 1, 2] or not command.get("comparison") in ["at_least", "at_most"] or not command.get("value") is float:
					fail("Invalid actor coordinate barrier")
					return false
				if ready and actor.get("ready", false):
					matched = actor.position[axis] >= command.value if command.comparison == "at_least" else actor.position[axis] <= command.value
			_:
				fail("Unknown UI observation barrier")
				return false
		if matched:
			return true
		await process_frame
	fail("UI observation barrier was not reached: " + str(command))
	return false

func _wire_value_type(value) -> String:
	match typeof(value):
		TYPE_NIL: return "null"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "string"
		TYPE_ARRAY: return "array"
		TYPE_DICTIONARY: return "dictionary"
	return "unsupported"

func _wire_nonfinite(value) -> String:
	if not (value is int or value is float):
		return "not_number"
	if is_nan(float(value)):
		return "nan"
	if is_inf(float(value)):
		return "positive_infinity" if float(value) > 0 else "negative_infinity"
	return "finite"

func _probe_wire_control(command: Dictionary) -> bool:
	# This controller exists only in the sealed local test consumer. It sends
	# the existing client RPC; it adds no server endpoint or movement producer.
	wire_control_probe = {}
	if command.get("ordinary_jump_release", false) == true:
		if command.has("packets"):
			fail("Choose raw packets or the existing jump/release API pair")
			return false
		wire_control_probe = {"kind": "ordinary_jump_release", "results": [
			scene.session.set_control(Vector2.ZERO, true), scene.session.release_control()]}
		return true
	var entries = command.get("packets")
	if not entries is Array or entries.is_empty() or entries.size() > 64:
		fail("Wire probe requires between1 and64 private packet descriptors")
		return false
	wire_control_probe = {"kind": "raw_rpc", "packets": []}
	for entry in entries:
		if not entry is Dictionary or not entry.get("payload") is Dictionary:
			fail("Wire probe payload must be a dictionary")
			return false
		var payload: Dictionary = entry.payload.duplicate(true)
		var sequence_kind: String = entry.get("sequence_kind", "preserve")
		if sequence_kind == "int":
			var value = payload.get("sequence")
			if not (value is int or value is float) or not is_finite(float(value)) or floorf(float(value)) != float(value) or absf(float(value)) > 1000000000.0:
				fail("Integer probe descriptor needs a bounded integral JSON sequence")
				return false
			# JSON control numbers parse as floats. This explicit test descriptor
			# selects the actual Variant int; preserve leaves negative types alone.
			payload.sequence = int(value)
		elif sequence_kind != "preserve":
			fail("Unknown wire sequence descriptor")
			return false
		var nonfinite: String = entry.get("nonfinite_direction", "")
		if not nonfinite.is_empty():
			if not nonfinite in ["nan", "positive_infinity", "negative_infinity"] or not payload.get("direction") is Array or payload.direction.size() != 2:
				fail("Invalid nonfinite direction descriptor")
				return false
			payload.direction[0] = NAN if nonfinite == "nan" else INF if nonfinite == "positive_infinity" else -INF
		var field_types: Dictionary = {}
		for field in payload:
			field_types[field] = _wire_value_type(payload[field])
		var direction_types: Array = []
		var direction_nonfinite: Array = []
		if payload.get("direction") is Array:
			for value in payload.direction:
				direction_types.append(_wire_value_type(value))
				direction_nonfinite.append(_wire_nonfinite(value))
		var emitted := {"payload": payload.duplicate(true), "field_types": field_types,
			"sequence_type": _wire_value_type(payload.get("sequence")),
			"direction_types": direction_types, "direction_nonfinite": direction_nonfinite}
		var error: Error = scene.session.rpc_id(1, "_wire_control", payload)
		emitted["rpc_error"] = int(error)
		wire_control_probe.packets.append(emitted)
	return true

func execute(command: Dictionary) -> void:
	match command.get("action", ""):
		"observe": pass
		"wire_control":
			if not _probe_wire_control(command):
				return
		"key":
			if not KEYS.has(command.get("key")):
				fail("Unknown UI key")
				return
			await key(KEYS[command.key])
		"key_down", "key_up":
			if not command.get("key") in ["W", "A", "S", "D", "SPACE"]:
				fail("Unknown held character key")
				return
			await key_edge(KEYS[command.key], command.action == "key_down")
		"physics_frames":
			# Godot JSON numbers are floats. Reify only finite integral counts;
			# do not silently truncate a fractional control-file request.
			var count = command.get("frames")
			if not (count is int or count is float) or not is_finite(float(count)) or float(count) != floorf(float(count)) or float(count) < 1 or float(count) > 240:
				fail("Natural physics wait must be between1 and240 frames")
				return
			for _frame in range(int(count)):
				await physics_frame
			await process_frame
		"orbit":
			if not command.get("dx") is float or not command.get("dy") is float or absf(command.dx) > 1000 or absf(command.dy) > 1000:
				fail("Invalid ordinary orbit drag")
				return
			var edge := InputEventMouseButton.new()
			edge.button_index = MOUSE_BUTTON_RIGHT
			edge.pressed = true
			Input.parse_input_event(edge)
			await process_frame
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(command.dx, command.dy)
			motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
			Input.parse_input_event(motion)
			await process_frame
			edge = edge.duplicate()
			edge.pressed = false
			Input.parse_input_event(edge)
			await process_frame
		"focus_release":
			# Explicit local Window signal injection, not proof of OS focus loss.
			root.focus_exited.emit()
			await process_frame
		"cell":
			var point: Vector2 = scene.camera.unproject_position(Vector3(int(command.get("x", 0)) * scene.PITCH, 0.08, int(command.get("z", 0)) * scene.PITCH))
			await click(point)
		"button":
			if not command.get("button", "") in BUTTONS:
				fail("Unknown UI button")
				return
			if not await click_button(command.button):
				return
		"barrier":
			var reached: bool = await _barrier(command)
			if not reached:
				return
		"view_delta":
			var seconds := float(command.get("seconds", -1))
			if seconds < 0 or seconds > 600:
				fail("Invalid local view delta")
				return
			scene._process(seconds)
		"capture":
			if DisplayServer.get_name() == "headless":
				fail("Capture requires a real rendered consumer")
				return
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_png(control_root.path_join("capture-%d.png" % last_id)) != OK:
				fail("Actual UI capture failed")
				return
		"quit": pass
		_:
			fail("Unknown UI control action")
			return
	checks += 1
	var value := {"status": "pass", "id": last_id, "input": command, "checks": checks, "facts": facts()}
	var file := FileAccess.open(control_root.path_join("response-%d.json" % last_id), FileAccess.WRITE)
	if file == null:
		fail("Cannot retain UI response")
		return
	file.store_string(JSON.stringify(value, "", true, true))
	file.close()
	print("OPENING_UI_RESPONSE " + JSON.stringify({"id": last_id, "status": "pass"}))
	busy = false
	if command.action == "quit":
		quit(0)

func facts() -> Dictionary:
	var result := {"state": scene.state.duplicate(true), "projection": scene.session.projection(),
		"wire_control_probe": wire_control_probe.duplicate(true),
		"ui_readiness": ui_readiness.duplicate(true), "button_probe": button_probe.duplicate(true),
		"ready": scene.session.is_ready(), "connecting": scene.connecting, "actor": scene.client,
		"namespace": scene.request_namespace, "sequence": scene.request_sequence,
		"session_namespace": scene.session.request_namespace, "session_sequence": scene.session.request_sequence,
		"session_serial": scene.session.last_serial, "selected": scene.selected, "pending_link": scene.pending_link,
		"pending_actions": scene.pending_actions.duplicate(true), "uncertain": scene.uncertain_actions.duplicate(true),
		"last_submission": scene.last_submission.duplicate(true), "last_outcome": scene.last_outcome.duplicate(true),
		"last_local_result": scene.last_local_result.duplicate(true), "confirmed": scene.goal_confirmed,
		"goal": scene.goal_label.text, "confirm_disabled": scene.confirm_button.disabled,
		"connection_label": scene.connection_label.text, "message": scene.status_label.text,
		"transport_disconnect_reason": transport_disconnect_reason,
		"inspector": scene.inspector.text, "power_label": scene.power_label.text,
		"inspector_rect": [scene.inspector.get_global_rect().position.x, scene.inspector.get_global_rect().position.y,
			scene.inspector.size.x, scene.inspector.size.y],
		"worksite_bottom": scene.disconnect_button.get_global_rect().end.y,
		"save_slot": scene.save_slot, "save_ready": scene.save_slot_ready, "save_owned": scene.save_slot_owned,
		"save_disabled": scene.save_button.disabled, "load_disabled": scene.load_button.disabled,
		"save_result": scene.last_save_result.duplicate(true), "load_result": scene.last_load_result.duplicate(true),
		"auto_advance": scene.auto_advance, "elapsed": scene.elapsed,
		"model_is_session": scene.model == scene.session, "client_world_is_null": scene.session.get("world") == null,
		"model_script": scene.model.get_script().resource_path,
		"scene_path": str(scene.get_path()), "session_path": str(scene.session.get_path()),
		"explanation_open": scene.explanation_open, "lesson": scene.lesson_index}
	result["physical_view"] = {"legacy_fixture": scene.legacy_fixture,
		"has_local_actor_world": scene.actor_world != null,
		"has_presenter": scene.character_presenter != null,
		"actor_label": scene.actor_label.text,
		"camera": {"position": [scene.camera.position.x, scene.camera.position.y, scene.camera.position.z],
			"focus": [scene.focus.x, scene.focus.y, scene.focus.z], "yaw": scene.orbit_yaw, "distance": scene.distance}}
	if scene.character_presenter != null:
		var proxies: Dictionary = {}
		for actor in scene.character_presenter.views:
			var proxy: Node3D = scene.character_presenter.views[actor]
			proxies[actor] = {"visible": proxy.visible, "position": [proxy.position.x, proxy.position.y, proxy.position.z],
				"is_physics_body": proxy is PhysicsBody3D}
		result.physical_view["proxies"] = proxies
		result.physical_view["held_keys"] = scene.character_presenter.held_keys.keys()
	if scene.example_presenter != null:
		result["example"] = {"projection": scene.example_presenter.model.projection(),
			"separate_model": scene.example_presenter.model != scene.model,
			"separate_world": scene.example_presenter.world.get_world_3d() != scene.get_world_3d()}
	return result

func fail(reason: String) -> void:
	fatal = true
	push_error(reason)
	if not control_root.is_empty() and DirAccess.dir_exists_absolute(control_root):
		var file := FileAccess.open(control_root.path_join("failure.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"status": "fail", "id": last_id, "error": reason,
				"ui_readiness": ui_readiness.duplicate(true), "button_probe": button_probe.duplicate(true)}))
	print("OPENING_UI_FAIL " + reason)
	quit(1)
