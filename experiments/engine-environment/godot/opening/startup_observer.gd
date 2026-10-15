extends Node
## Test-only read-only observer, attached by --smoke to its external copy only.

func _ready():
	if Engine.is_editor_hint():
		return
	await get_tree().process_frame
	var scene = get_tree().current_scene
	var report := {"schema": 1, "scene": "", "script": ""}
	if scene != null:
		report.scene = scene.scene_file_path
		var script = scene.get_script()
		if script != null:
			report.script = script.resource_path
		if report.script == "res://opening/opening.gd":
			report["state"] = scene.model.projection()
			report["view"] = {"save_slot": scene.save_slot,
				"save_ready": scene.save_slot_ready, "save_owned": scene.save_slot_owned,
				"save_disabled": scene.save_button.disabled, "load_disabled": scene.load_button.disabled,
				"confirmed": scene.goal_confirmed, "request_sequence": scene.request_sequence,
				"namespace_nonempty": not scene.request_namespace.is_empty(),
				"machines": scene.machine_root.get_child_count(), "items": scene.item_root.get_child_count()}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--startup-report="):
			var file := FileAccess.open(argument.trim_prefix("--startup-report="), FileAccess.WRITE)
			if file == null:
				push_error("Cannot write owned startup observer report")
				return
			file.store_string(JSON.stringify(report))
			file.close()
			print("OPENING_STARTUP_OBSERVED")
			return
