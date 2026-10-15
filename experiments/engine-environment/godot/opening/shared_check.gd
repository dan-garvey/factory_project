extends SceneTree
## Test-only local input controller for the real OpeningShared scene.
## The normal scene never reads these files. There is no test/admin game RPC.
const KEYS := {"1": KEY_1, "2": KEY_2, "3": KEY_3, "4": KEY_4,
	"F": KEY_F, "G": KEY_G, "I": KEY_I, "R": KEY_R, "H": KEY_H,
	"SPACE": KEY_SPACE, "F5": KEY_F5, "F9": KEY_F9, "ESCAPE": KEY_ESCAPE,
	"RIGHT": KEY_RIGHT, "LEFT": KEY_LEFT, "HOME": KEY_HOME}
const BUTTONS := ["confirm_button", "retrieve_button", "power_button", "remove_button",
	"save_button", "load_button", "reconnect_button", "disconnect_button",
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
	print("OPENING_UI_READY " + JSON.stringify(facts()))

func _poll() -> void:
	if scene == null or fatal:
		return
	if Time.get_ticks_msec() - started > 240000:
		fail("Automated UI controller reached its four-minute allowance")
		return
	if busy:
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
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
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
			_:
				fail("Unknown UI observation barrier")
				return false
		if matched:
			return true
		await process_frame
	fail("UI observation barrier was not reached: " + str(command))
	return false

func execute(command: Dictionary) -> void:
	match command.get("action", ""):
		"observe": pass
		"key":
			if not KEYS.has(command.get("key")):
				fail("Unknown UI key")
				return
			await key(KEYS[command.key])
		"cell":
			var point: Vector2 = scene.camera.unproject_position(Vector3(int(command.get("x", 0)) * scene.PITCH, 0.08, int(command.get("z", 0)) * scene.PITCH))
			await click(point)
		"button":
			if not command.get("button", "") in BUTTONS:
				fail("Unknown UI button")
				return
			var button: Button = scene.get(command.button)
			if button == null or not button.is_visible_in_tree():
				fail("UI button is not visible")
				return
			await click(button.get_global_rect().get_center())
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
	file.store_string(JSON.stringify(value))
	file.close()
	print("OPENING_UI_RESPONSE " + JSON.stringify({"id": last_id, "status": "pass"}))
	busy = false
	if command.action == "quit":
		quit(0)

func facts() -> Dictionary:
	var result := {"state": scene.state.duplicate(true), "projection": scene.session.projection(),
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
			file.store_string(JSON.stringify({"status": "fail", "id": last_id, "error": reason}))
	print("OPENING_UI_FAIL " + reason)
	quit(1)
