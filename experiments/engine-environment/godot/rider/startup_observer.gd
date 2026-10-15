extends Node
## Disclosed copied-project normal-entry observer; no game commands or carry.
var started := 0
var captured := false

func _scene_path() -> String:
	return "res://rider/main.tscn"

func _ready() -> void:
	started = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if captured:
		return
	if Time.get_ticks_msec() - started > 10000:
		captured = true
		push_error("Normal rider startup did not settle")
		get_tree().quit(1)
		return
	var scene = get_tree().current_scene
	if scene == null or scene.scene_file_path != _scene_path() or scene.player == null:
		return
	if scene.authority.projection().native_pending or not scene.player.is_on_floor():
		return
	captured = true
	var report := {"scene": scene.scene_file_path, "status": "pass" if scene.player.floor_id == scene.ground.get_instance_id()
		and not scene.authority.running and scene.authority.committed == 0 else "fail", "state": scene.authority.projection(),
		"player_id": scene.player.get_instance_id(), "ground_id": scene.ground.get_instance_id(), "floor_id": scene.player.floor_id}
	_finish.call_deferred(report)

func _finish(report: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--observer-report="):
			var file := FileAccess.open(argument.trim_prefix("--observer-report="), FileAccess.WRITE)
			if file == null:
				get_tree().quit(1)
				return
			file.store_string(JSON.stringify(report))
			file.close()
		elif argument.begins_with("--observer-capture="):
			if get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--observer-capture=")) != OK:
				get_tree().quit(1)
				return
	print("RIDER_STARTUP_PASS" if report.status == "pass" else "RIDER_STARTUP_FAIL")
	get_tree().quit(0 if report.status == "pass" else 1)
