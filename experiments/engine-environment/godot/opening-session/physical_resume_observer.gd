extends Node
## Test-only autoload captured by the unchanged normal shared launcher.
## Injects ordinary UI events; Session/the host remain the only state owners.
var report_path := ""
var finish_path := ""
var directory := ""
var role := ""
var phase := ""
var deadline := 0
var scene
var initial_position: Array = []
var movement: Dictionary = {}
var placement: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--launch-report="): report_path = argument.trim_prefix("--launch-report=")
		elif argument.begins_with("--launch-finish-file="): finish_path = argument.trim_prefix("--launch-finish-file=")
		elif argument.begins_with("--session-role="): role = argument.trim_prefix("--session-role=")
	phase = OS.get_environment("FACTORY_PHYSICAL_RESUME_PHASE")
	if not report_path.is_absolute_path() or not finish_path.is_absolute_path() or not role in ["P", "Q"] or not phase in ["produce", "resume"]:
		fail("Observer requires owned normal-launch paths, P/Q role and explicit test phase")
		return
	directory = report_path.get_base_dir().get_base_dir()
	deadline = Time.get_ticks_msec() + 20000
	if not await wait_for(connected, "normal physical scene connection"):
		return
	var connected_revision: int = scene.session.projection().revision
	initial_position = pose()
	if phase == "produce":
		if not await produce():
			return
	else:
		if not need(scene.session.request_sequence == 0 and scene.pending_actions.is_empty(), "Read-only fresh client must issue no material command"):
			return
	if not await wait_for(func() -> bool:
		var snapshot: Dictionary = scene.session.projection()
		return snapshot.order == 2 and snapshot.revision >= connected_revision + 2 and scene.pending_actions.is_empty(), "two actual historical requests and new live clock"):
		return
	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	if not need(get_tree().root.get_texture().get_image().save_png(report_path + ".png") == OK, "Rendered normal client capture"):
		return
	var value := {"schema": 1, "status": "pass", "actor": scene.client, "pid": OS.get_process_id(),
		"phase": phase, "scene": scene.scene_file_path, "script": scene.get_script().resource_path,
		"session_path": str(scene.session.get_path()), "projection": scene.session.projection(),
		"connected_revision": connected_revision, "initial_position": initial_position,
		"movement": movement, "placement": placement,
		"limits": ["Injected ordinary input, not human play or OS focus evidence.", "No direct Model, pose, capability or native-world mutation."],
		"view": {"ready": scene.session.is_ready(), "connecting": scene.connecting,
			"model_is_session": scene.model == scene.session, "client_world_is_null": scene.session.world == null,
			"auto_advance": scene.auto_advance, "model_script": scene.model.get_script().resource_path,
			"namespace": scene.request_namespace, "sequence": scene.request_sequence,
			"selected": scene.selected, "pending_link": scene.pending_link,
			"goal": scene.goal_text,
			"session_namespace": scene.session.request_namespace, "session_sequence": scene.session.request_sequence,
			"save_slot": scene.save_slot, "save_ready": scene.save_slot_ready, "save_owned": scene.save_slot_owned,
			"save_disabled": scene.save_button.disabled, "load_disabled": scene.load_button.disabled}}
	if not publish(report_path, value):
		return
	print("SHARED_OPENING_OBSERVED " + JSON.stringify({"actor": role, "pid": OS.get_process_id()}))
	if not await wait_for(func() -> bool: return FileAccess.file_exists(finish_path), "normal launcher finish marker"):
		return
	get_tree().quit(0)

func connected() -> bool:
	scene = get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://opening/shared_opening.tscn" or scene.get("session") == null or not scene.session.is_ready():
		return false
	var snapshot: Dictionary = scene.session.projection()
	return snapshot.get("options", {}).get("physical", false) and snapshot.get("actors", {}).has(role) and snapshot.actors[role].get("ready", false)

func pose() -> Array:
	var snapshot: Dictionary = scene.session.projection()
	return snapshot.actors[role].position.duplicate()

func wait_for(predicate: Callable, label: String) -> bool:
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	fail("Observation deadline: " + label)
	return false

func key_edge(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame

func place_collector() -> bool:
	await key_edge(KEY_1, true)
	await key_edge(KEY_1, false)
	var point: Vector2 = scene.camera.unproject_position(Vector3(0, 0.08, 0))
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	if not await wait_for(func() -> bool:
		return scene.session.request_sequence == 1 and scene.pending_actions.is_empty() and not scene.last_outcome.is_empty(), "actual ordinary placement disposition"):
		return false
	placement = {"submission": scene.last_submission.duplicate(true), "outcome": scene.last_outcome.duplicate(true)}
	var expected := "placed" if role == "P" else "out_of_reach"
	return need(placement.outcome.reason == expected and placement.outcome.accepted == (role == "P") and not placement.outcome.duplicate, "P nearby placement/Q far refusal")

func walk() -> bool:
	var before: Array = pose()
	var code: Key = KEY_D if role == "P" else KEY_S
	await key_edge(code, true)
	var moved: bool = await wait_for(func() -> bool:
		var current: Array = pose()
		var dx: float = current[0] - before[0]
		var dz: float = current[2] - before[2]
		return dx * dx + dz * dz >= 0.04, "server-confirmed horizontal walking")
	await key_edge(code, false)
	if not moved:
		return false
	var previous: Array = pose()
	var snapshot: Dictionary = scene.session.projection()
	var epoch: int = snapshot.actors[role].native_epoch
	var stable := 0
	while Time.get_ticks_msec() < deadline and stable < 3:
		await get_tree().physics_frame
		await get_tree().process_frame
		snapshot = scene.session.projection()
		if snapshot.actors[role].native_epoch <= epoch:
			continue
		epoch = snapshot.actors[role].native_epoch
		var current: Array = pose()
		stable = stable + 1 if current[0] == previous[0] and current[2] == previous[2] else 0
		previous = current
	if not need(stable == 3 and scene.character_presenter.held_keys.is_empty(), "Released keys and three fresh stationary horizontal observations"):
		return false
	movement = {"before": before, "after": pose(), "final_epoch": epoch, "stable_observations": stable,
		"held_keys": scene.character_presenter.held_keys.keys()}
	return true

func produce() -> bool:
	var other := directory.path_join("physical-checkpoint-Q-done.json")
	var complete := directory.path_join("physical-checkpoint-P-done.json")
	if role == "P":
		if not await wait_for(func() -> bool: return FileAccess.file_exists(other), "Q actual refusal and movement before P builds"):
			return false
	if not await place_collector() or not await walk():
		return false
	if not publish(complete if role == "P" else other, {"actor": role, "pid": OS.get_process_id(), "movement": movement, "placement": placement}):
		return false
	if role == "Q" and not await wait_for(func() -> bool: return FileAccess.file_exists(complete), "P actual placement and movement"):
		return false
	return true

func publish(path: String, value: Dictionary) -> bool:
	if not need(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".writing"), "Fresh owned observer output"):
		return false
	var file := FileAccess.open(path + ".writing", FileAccess.WRITE)
	if file == null:
		fail("Cannot open owned observer output")
		return false
	file.store_string(JSON.stringify(value, "", true, true))
	file.close()
	return need(DirAccess.rename_absolute(path + ".writing", path) == OK, "Atomic owned observer publication")

func need(condition: bool, label: String) -> bool:
	if not condition:
		fail(label)
	return condition

func fail(reason: String) -> void:
	push_error(reason)
	print("SHARED_OPENING_OBSERVER_FAIL " + reason)
	get_tree().quit(1)
