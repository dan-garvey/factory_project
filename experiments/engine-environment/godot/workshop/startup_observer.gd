extends Node
## Disclosed copied-project autoload. Reads normal scene/native startup, then exits.
var started := 0
var captured := false

func _ready() -> void:
	started = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if captured:
		return
	if Time.get_ticks_msec() - started > 10000:
		captured = true
		push_error("Normal workshop startup did not reach coherent native state")
		get_tree().quit(1)
		return
	var scene = get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://workshop/main.tscn" or scene.authority == null:
		return
	var state: Dictionary = scene.authority.projection()
	if state.native_pending or state.completed.is_empty():
		return
	captured = true
	var native := {}
	for branch in ["B", "U"]:
		var body: PhysicsBody3D = scene.authority.bodies[branch]
		var pose: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		native[branch] = [pose.origin.x, pose.origin.y, pose.origin.z]
	var report := {"scene": scene.scene_file_path, "view_script": scene.get_script().resource_path,
		"state": state, "native": native, "auto_advance": scene.auto_advance,
		"B_visible": scene.body_meshes.B.visible, "U_visible": scene.body_meshes.U.visible,
		"status": "pass" if not state.running and not state.layout.ready and state.committed == 0
			and state.contact_entries == 0 and not scene.auto_advance else "fail"}
	_finish.call_deferred(report)

func _finish(report: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--observer-report="):
			var file := FileAccess.open(argument.trim_prefix("--observer-report="), FileAccess.WRITE)
			if file == null:
				push_error("Cannot retain normal startup observation")
				get_tree().quit(1)
				return
			file.store_string(JSON.stringify(report))
			file.close()
		elif argument.begins_with("--observer-capture="):
			if get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--observer-capture=")) != OK:
				push_error("Cannot retain actual normal workshop viewport")
				get_tree().quit(1)
				return
	print("WORKSHOP_STARTUP_PASS" if report.status == "pass" else "WORKSHOP_STARTUP_FAIL")
	get_tree().quit(0 if report.status == "pass" else 1)
