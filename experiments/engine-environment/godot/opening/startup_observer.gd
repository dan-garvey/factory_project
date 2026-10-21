extends Node
## Read-only startup observer, enabled only in an instrumented external runtime.

func _ready():
	if Engine.is_editor_hint():
		return
	var report_path := ""
	var image_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--startup-report="):
			report_path = argument.trim_prefix("--startup-report=")
		elif argument.begins_with("--startup-image="):
			image_path = argument.trim_prefix("--startup-image=")
	if not report_path.is_absolute_path() or FileAccess.file_exists(report_path):
		push_error("Startup observation requires a fresh absolute report path")
		get_tree().quit(1)
		return
	if not image_path.is_empty() and (not image_path.is_absolute_path() or FileAccess.file_exists(image_path)):
		push_error("Startup capture requires a fresh absolute image path")
		get_tree().quit(1)
		return
	if not image_path.is_empty() and image_path.simplify_path() == report_path.simplify_path():
		push_error("Startup image and report require distinct output paths")
		get_tree().quit(1)
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
	var report := {"schema": 1, "scene": "", "script": "", "display_server": DisplayServer.get_name()}
	if scene != null:
		report.scene = scene.scene_file_path
		var script = scene.get_script()
		if script != null:
			report.script = script.resource_path
		if report.script in ["res://opening/opening.gd", "res://opening/native_opening.gd"]:
			report["model_script"] = scene.model.get_script().resource_path
			report["state"] = scene.model.projection()
			report["view"] = {"save_slot": scene.save_slot,
				"save_ready": scene.save_slot_ready, "save_owned": scene.save_slot_owned,
				"save_disabled": scene.save_button.disabled, "load_disabled": scene.load_button.disabled,
				"confirmed": scene.goal_confirmed, "request_sequence": scene.request_sequence,
				"namespace_nonempty": not scene.request_namespace.is_empty(),
				"machines": report.state.get("entities", {}).size(), "foundations": report.state.get("foundations", {}).size(),
				"items": scene.item_root.get_child_count(),
				"goal_text": scene.goal_label.text, "status_text": scene.status_label.text}
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
	if not image_path.is_empty():
		if DisplayServer.get_name().to_lower() == "headless":
			push_error("A startup image requires a real rendered display")
			get_tree().quit(1)
			return
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image.is_empty() or image.save_png(image_path) != OK:
			push_error("Cannot retain the actual app viewport")
			get_tree().quit(1)
			return
		report["image"] = {"path": image_path, "width": image.get_width(), "height": image.get_height()}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write owned startup observer report")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "", true, true))
	file.close()
	print("OPENING_STARTUP_OBSERVED")
	get_tree().quit(0)
