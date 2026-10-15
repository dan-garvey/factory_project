extends "res://opening/opening_check.gd"
## Actual resumed scene startup and ordinary keys; no independent rule owner.
const Store = preload("res://save-tests/checkpoint_file.gd")
var checks := 0

func _check(condition: bool, message: String) -> void:
	checks += 1
	super._check(condition, message)

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var slot := ""
	var source := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save-slot="): slot = argument.trim_prefix("--save-slot=")
		elif argument.begins_with("--resume-input="): source = argument.trim_prefix("--resume-input=")
	var expected = load("res://model.gd").new()
	_check(Store.read_into(expected, source).accepted, "resume input uses actual Store/Model")
	var before: Dictionary = expected.checkpoint()
	scene = load("res://opening/opening.tscn").instantiate()
	scene.auto_advance = false
	scene.configure_save_slot(slot)
	root.add_child(scene)
	await process_frame
	await physics_frame
	await process_frame
	_check(scene.model._same_plain(scene.model.checkpoint(), before), "fresh process starts at exact saved checkpoint")
	_check(scene.save_slot_owned and not scene.save_button.disabled and not scene.load_button.disabled,
		"resumed session owns a distinct writable output slot")
	_check(scene.selected.is_empty() and scene.pending_link.is_empty() and scene.request_sequence == 0,
		"resumed selection, half-link and caller sequence are fresh")
	_check(not scene.goal_confirmed and scene.confirm_button.disabled == (before.inventories.get("P", 0) < 4),
		"goal eligibility derives from restored inventory without automatic credit")
	var own_saved = load("res://model.gd").new()
	_check(Store.read_into(own_saved, slot).accepted and own_saved._same_plain(own_saved.checkpoint(), before),
		"new session slot is an actual valid save, not incoming diagnostics")
	var processor := ""
	for entity_id in scene.state.entities:
		if scene.state.entities[entity_id].kind == "processor": processor = entity_id
	_check(not processor.is_empty() and scene.state.stock.held == 1,
		"resume input check uses a declared partially working opening")
	if processor.is_empty():
		quit(1)
		return
	await _key(KEY_F)
	var collector := ""
	for entity_id in scene.state.entities:
		if scene.state.entities[entity_id].kind == "collector": collector = entity_id
	var start_cell: Array = scene.state.entities[collector].cell
	await _click_cell(start_cell[0], start_cell[1])
	var selected: String = scene.selected
	var pending: String = scene.pending_link
	var namespace_before: String = scene.request_namespace
	var sequence_before: int = scene.request_sequence
	var save_before := FileAccess.get_file_as_bytes(slot)
	var save_facts := [scene.save_slot, scene.save_slot_ready, scene.save_slot_owned,
		scene.save_button.disabled, scene.load_button.disabled,
		scene.last_save_result.duplicate(true), scene.last_load_result.duplicate(true), scene.goal_confirmed]
	var camera_before: Transform3D = scene.camera.transform
	await _key(KEY_H)
	_check(scene.explanation_open and scene.example_presenter != null, "actual H opens worked example on resumed nonempty factory")
	await _click_screen(scene.lesson_next.get_global_rect().get_center())
	await _click_screen(scene.lesson_return.get_global_rect().get_center())
	_check(not scene.explanation_open and scene.model._same_plain(scene.model.checkpoint(), before)
		and scene.selected == selected and scene.pending_link == pending and scene.camera.transform == camera_before
		and scene.request_namespace == namespace_before and scene.request_sequence == sequence_before
		and FileAccess.get_file_as_bytes(slot) == save_before
		and save_facts == [scene.save_slot, scene.save_slot_ready, scene.save_slot_owned,
			scene.save_button.disabled, scene.load_button.disabled, scene.last_save_result, scene.last_load_result, scene.goal_confirmed],
		"worked example returns without changing resumed stock, requests, selection, camera or save")
	if not scene.state.power_enabled: await _key(KEY_SPACE)
	_check(scene.state.powered, "ordinary Space resumes the actual connected drive")
	var initial_output: int = scene.state.stock.output
	var work: int = scene.state.remaining
	if initial_output == 0:
		for tick in range(work):
			scene.model.advance()
			scene._refresh()
			if tick + 1 < work:
				_check(scene.state.stock.output == 0, "retained partial work cannot produce early")
	_check(scene.state.stock.output == 1, "retained work reaches one real plate")
	var prior_inventory: int = scene.state.inventories.get("P", 0)
	await _key(KEY_I)
	var cell: Array = scene.state.entities[processor].cell
	await _click_cell(cell[0], cell[1])
	await _key(KEY_R)
	_check(scene.state.inventories.get("P", 0) == prior_inventory + 1 and _conserved(),
		"first eligible ordinary retrieval succeeds after cross-process reopening")
	_check(scene.state.entities == before.entities and scene.state.parts == before.parts
		and scene.state.links == before.links and scene.state.drive_links == before.drive_links,
		"identities, carried parts and topology survive resumed input")
	for key in before.requests:
		_check(scene.model._same_plain(scene.model.checkpoint().requests[key], before.requests[key]),
			"existing request disposition survives fresh caller input")
		_check(not before.requests[key].intent.request.begins_with(scene.request_namespace),
			"fresh namespace cannot restart into retained requests")
	await _key(KEY_F5)
	_check(scene.last_save_result.accepted and Store.read_into(own_saved, slot).accepted
		and own_saved._same_plain(own_saved.checkpoint(), scene.model.checkpoint()),
		"ordinary F5 updates only the new owned slot")
	print("OPENING_RESUME_STATE " + JSON.stringify({"loaded": before,
		"final": scene.model.projection(), "checks": checks, "failures": failures}))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "actual resumed viewport")
	print("OPENING_RESUME_INPUT_PASS" if failures.is_empty() else "OPENING_RESUME_INPUT_FAIL")
	quit(0 if failures.is_empty() else 1)
