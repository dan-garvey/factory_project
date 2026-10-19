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
	if scene != null and not scene.legacy_fixture:
		await _physical(scene, source, output)
		return
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
	get_tree().quit(0)

func _physical(scene, source: String, output: String) -> void:
	for _frame in range(120):
		await get_tree().physics_frame
		if scene.model.projection().get("actors", {}).get("P", {}).get("ready", false) and not scene.startup_save_pending:
			break
	await get_tree().process_frame
	var reference = Model.new(16, "resume-observer", 1, {"opening": true, "physical": true})
	var restored: Dictionary = Store.read_into(reference, source)
	var report := {"schema": 1, "profile": "physical", "pid": OS.get_process_id(),
		"scene": scene.scene_file_path, "script": scene.get_script().resource_path,
		"loaded": scene.startup_resume_checkpoint, "continued_from_source": false,
		"slot_matches_loaded": false, "native": scene.actor_world.diagnostics(), "initial_native": {}}
	if restored.accepted and reference._same_plain(reference.checkpoint(), scene.startup_resume_checkpoint):
		var ticks: int = scene.model.revision - reference.revision
		if ticks >= 0 and ticks <= 256:
			reference.advance(ticks)
			var expected: Dictionary = reference.checkpoint()
			var actual: Dictionary = scene.model.checkpoint()
			expected.erase("actors")
			actual.erase("actors")
			report.continued_from_source = reference._same_plain(expected, actual)
	var saved = Model.new(16, "saved-observer", 1, {"opening": true, "physical": true})
	var slot_result: Dictionary = Store.read_into(saved, scene.save_slot)
	var expected_slot: Dictionary = scene.startup_resume_checkpoint.duplicate(true)
	var actual_slot: Dictionary = saved.checkpoint()
	var source_actors: Dictionary = expected_slot.get("actors", {}).duplicate(true)
	var saved_actors: Dictionary = actual_slot.get("actors", {}).duplicate(true)
	expected_slot.erase("actors")
	actual_slot.erase("actors")
	var native_ready: Dictionary = scene.last_save_result.get("native_preflight", {})
	var poses_match: bool = native_ready.get("accepted", false) and source_actors.keys() == saved_actors.keys()
	for actor in saved_actors:
		poses_match = poses_match and native_ready.get("actors", {}).get(actor, {}).get("position") == saved_actors[actor].position
		poses_match = poses_match and saved_actors[actor].capabilities == source_actors.get(actor, {}).get("capabilities")
	report.slot_matches_loaded = slot_result.accepted and reference._same_plain(expected_slot, actual_slot) and poses_match
	for epoch in range(1, mini(121, report.native.native_epoch + 1)):
		var retained: Dictionary = scene.actor_world.diagnostics("P", epoch)
		if retained.get("available", false) and retained.sample.cut == "initial_physics_boundary":
			report.initial_native = retained.sample
			break
	report["state"] = scene.model.projection()
	report["view"] = {"save_slot": scene.save_slot, "save_ready": scene.save_slot_ready,
		"save_owned": scene.save_slot_owned, "save_disabled": scene.save_button.disabled,
		"load_disabled": scene.load_button.disabled, "confirmed": scene.goal_confirmed,
		"confirm_disabled": scene.confirm_button.disabled, "selected": scene.selected,
		"pending": scene.pending_link, "entity_ids": scene.state.entities.keys(), "request_sequence": scene.request_sequence,
		"namespace_nonempty": not scene.request_namespace.is_empty()}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot retain physical resume observation")
		return
	file.store_string(JSON.stringify(report, "", true, true))
	file.close()
	print("OPENING_RESUME_OBSERVED")
	get_tree().quit(0)
