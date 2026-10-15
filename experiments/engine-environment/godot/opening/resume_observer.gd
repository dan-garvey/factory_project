extends Node
## Test-only observer for restored startup; fresh smoke retains its own oracle.
const Model = preload("res://model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")

func _ready():
	if Engine.is_editor_hint(): return
	await get_tree().process_frame
	var source := ""
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="): source = argument.trim_prefix("--resume-input=")
		elif argument.begins_with("--startup-report="): output = argument.trim_prefix("--startup-report=")
	var scene = get_tree().current_scene
	var report := {"schema": 1, "scene": "", "script": "", "continued_from_source": false, "slot_matches_loaded": false}
	if scene != null:
		report.scene = scene.scene_file_path
		var script = scene.get_script()
		if script != null: report.script = script.resource_path
		if report.script == "res://opening/opening.gd":
			var reference = Model.new()
			var restored: Dictionary = Store.read_into(reference, source)
			report["loaded"] = scene.startup_resume_checkpoint
			if restored.accepted and reference._same_plain(reference.checkpoint(), scene.startup_resume_checkpoint):
				var ticks: int = scene.model.revision - reference.revision
				if ticks >= 0 and ticks <= 256:
					reference.advance(ticks)
					report.continued_from_source = reference._same_plain(reference.checkpoint(), scene.model.checkpoint())
			report["state"] = scene.model.projection()
			var saved = Model.new()
			var slot_result: Dictionary = Store.read_into(saved, scene.save_slot)
			report.slot_matches_loaded = slot_result.accepted and saved._same_plain(saved.checkpoint(), scene.startup_resume_checkpoint)
			var ids: Array = []
			for anchor in scene.machine_root.get_children():
				for child in anchor.get_children():
					if child is StaticBody3D and child.has_meta("entity"): ids.append(child.get_meta("entity"))
			report["view"] = {"save_slot": scene.save_slot, "save_ready": scene.save_slot_ready,
				"save_owned": scene.save_slot_owned, "save_disabled": scene.save_button.disabled,
				"load_disabled": scene.load_button.disabled, "confirmed": scene.goal_confirmed,
				"confirm_disabled": scene.confirm_button.disabled, "selected": scene.selected,
				"pending": scene.pending_link, "entity_ids": ids, "request_sequence": scene.request_sequence,
				"namespace_nonempty": not scene.request_namespace.is_empty()}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot retain actual resumed-scene observation")
		return
	file.store_string(JSON.stringify(report))
	file.close()
	print("OPENING_RESUME_OBSERVED")
