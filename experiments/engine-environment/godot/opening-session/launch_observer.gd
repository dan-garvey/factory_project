extends Node
## Test-only autoload in an owned copy. The normal scene remains the entrypoint.
var report_path := ""
var finish_path := ""
var role := ""

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--launch-report="): report_path = argument.trim_prefix("--launch-report=")
		elif argument.begins_with("--launch-finish-file="): finish_path = argument.trim_prefix("--launch-finish-file=")
		elif argument.begins_with("--session-role="): role = argument.trim_prefix("--session-role=")
	if not report_path.is_absolute_path() or not finish_path.is_absolute_path():
		fail("Observer needs owned absolute report/finish paths")
		return
	var deadline := Time.get_ticks_msec() + 15000
	var scene
	var connected_revision := -1
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		scene = get_tree().current_scene
		if scene != null and scene.scene_file_path == "res://opening/shared_opening.tscn":
			var session = scene.get("session")
			if session != null and session.is_ready():
				var revision: int = session.projection().get("revision", -1)
				if connected_revision < 0:
					connected_revision = revision
				# A restored revision can already be large. Observe two NEW
				# revisions after connection; this observer sends no commands.
				if revision >= connected_revision + 2:
					break
	if scene == null or scene.get("session") == null or not scene.session.is_ready():
		fail("Normal shared scene did not auto-connect")
		return
	if connected_revision < 0 or scene.session.projection().get("revision", -1) < connected_revision + 2:
		fail("Actual server clock did not advance")
		return
	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	if get_tree().root.get_texture().get_image().save_png(report_path + ".png") != OK:
		fail("Cannot capture actual normal window")
		return
	var value := {"schema": 1, "status": "pass", "actor": scene.client, "pid": OS.get_process_id(),
		"scene": scene.scene_file_path, "script": scene.get_script().resource_path,
		"session_path": str(scene.session.get_path()), "projection": scene.session.projection(),
		"connected_revision": connected_revision,
		"view": {"ready": scene.session.is_ready(), "connecting": scene.connecting,
			"model_is_session": scene.model == scene.session, "client_world_is_null": scene.session.world == null,
			"auto_advance": scene.auto_advance, "model_script": scene.model.get_script().resource_path,
			"namespace": scene.request_namespace, "sequence": scene.request_sequence,
			"selected": scene.selected, "pending_link": scene.pending_link, "confirmed": scene.goal_confirmed,
			"goal": scene.goal_label.text, "confirm_disabled": scene.confirm_button.disabled,
			"session_namespace": scene.session.request_namespace, "session_sequence": scene.session.request_sequence,
			"save_slot": scene.save_slot, "save_ready": scene.save_slot_ready, "save_owned": scene.save_slot_owned,
			"save_disabled": scene.save_button.disabled, "load_disabled": scene.load_button.disabled}}
	var file := FileAccess.open(report_path + ".writing", FileAccess.WRITE)
	if file == null:
		fail("Cannot open owned normal-entry report")
		return
	file.store_string(JSON.stringify(value))
	file.close()
	if DirAccess.rename_absolute(report_path + ".writing", report_path) != OK:
		fail("Cannot publish normal-entry report")
		return
	print("SHARED_OPENING_OBSERVED " + JSON.stringify({"actor": role, "pid": OS.get_process_id()}))
	while not FileAccess.file_exists(finish_path):
		if Time.get_ticks_msec() >= deadline:
			fail("Observer finish deadline expired")
			return
		await get_tree().process_frame
	get_tree().quit(0)

func fail(reason: String) -> void:
	push_error(reason)
	print("SHARED_OPENING_OBSERVER_FAIL " + reason)
	get_tree().quit(1)
