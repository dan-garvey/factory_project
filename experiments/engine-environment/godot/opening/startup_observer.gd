extends Node
## Test-only read-only observer, attached by --smoke to its external copy only.

func _ready():
	if Engine.is_editor_hint():
		return
	await get_tree().process_frame
	var scene = get_tree().current_scene
	if scene != null and not scene.legacy_fixture:
		for _frame in range(120):
			await get_tree().physics_frame
			if scene.model.projection().get("actors", {}).get("P", {}).get("ready", false):
				break
		for _frame in range(30):
			await get_tree().physics_frame
		await get_tree().process_frame
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
			if not scene.legacy_fixture:
				report["profile"] = "physical"
				report["pid"] = OS.get_process_id()
				report["native"] = scene.actor_world.diagnostics()
				report["initial_native"] = {}
				for epoch in range(1, mini(121, report.native.native_epoch + 1)):
					var retained: Dictionary = scene.actor_world.diagnostics("P", epoch)
					if retained.get("available", false) and retained.sample.cut == "initial_physics_boundary":
						report.initial_native = retained.sample
						break
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--startup-report="):
			var file := FileAccess.open(argument.trim_prefix("--startup-report="), FileAccess.WRITE)
			if file == null:
				push_error("Cannot write owned startup observer report")
				return
			file.store_string(JSON.stringify(report, "", true, true))
			file.close()
			print("OPENING_STARTUP_OBSERVED")
			get_tree().quit(0)
			return
