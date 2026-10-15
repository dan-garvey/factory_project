extends "res://opening/opening_check.gd"
## Actual selected-inspector input and retained-work/save/Help consumer.
var observations: Dictionary = {}
var evidence := ""

func observe(label: String) -> void:
	scene._refresh()
	observations[label] = {"projection": scene.model.projection(), "inspector": scene.inspector.text,
		"power_label": scene.power_label.text, "selected": scene.selected,
		"inspector_rect": [scene.inspector.position.x, scene.inspector.position.y, scene.inspector.size.x, scene.inspector.size.y]}
	_check(scene.inspector.get_global_rect().end.x <= 1262, "Inspector stays within its worksite panel")
	_check(scene.load_button.get_global_rect().end.y < 694, "Inspector leaves bottom controls readable")

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(evidence.path_join(label + ".png")) == OK, "Actual inspector capture saved")

func inspect(x: int) -> void:
	var before: Dictionary = scene.model.checkpoint()
	await _key(KEY_I)
	await _click_cell(x)
	_check(scene.model.checkpoint() == before, "Inspection does not issue a command or change authority")

func _run() -> void:
	root.size = Vector2i(1280, 800)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):
			evidence = argument.trim_prefix("--evidence=")
	_check(evidence.is_absolute_path() and DirAccess.dir_exists_absolute(evidence), "Owned external evidence directory required")
	scene = load("res://opening/opening.tscn").instantiate()
	scene.auto_advance = false
	scene.configure_save_slot(evidence.path_join("worksite.factory"))
	root.add_child(scene)
	await process_frame
	await physics_frame
	for entry in [[KEY_4, -1], [KEY_1, 0], [KEY_2, 1], [KEY_3, 2]]:
		await _key(entry[0])
		await _click_cell(entry[1])
	await inspect(2)
	observe("missing_material")
	_check("No material inlet linked." in scene.inspector.text and "[F] link Belt → Press." in scene.inspector.text, "Press names missing material link")
	await capture("missing-material")
	await inspect(0)
	_check("[F] link Collector → Belt." in scene.inspector.text, "Collector names its actual outlet path")
	await _connect(KEY_F, 0, 1)
	await inspect(1)
	_check("No material outlet linked." in scene.inspector.text and "[F] link Belt → Press." in scene.inspector.text, "Belt distinguishes outlet from connected inlet")
	await _connect(KEY_F, 1, 2)
	await inspect(2)
	observe("missing_drive")
	_check("Drive needs connections." in scene.inspector.text and "[G]" in scene.inspector.text and not "[Space]" in scene.inspector.text, "Missing drive never claims Space repairs it")
	_check(scene.power_label.text == "DRIVE NEEDS CONNECTIONS", "Power label distinguishes unconnected drive")
	await capture("missing-drive")
	await _key(KEY_SPACE)
	observe("switched_off_unconnected")
	_check(scene.power_label.text == "DRIVE SWITCHED OFF" and "[Space] enables" in scene.inspector.text, "Switch-off differs from missing connections")
	await _key(KEY_SPACE)
	_check("[G]" in scene.inspector.text, "Enabling alone still calls for real drive connections")
	for pair in [[-1, 0], [0, 1], [1, 2]]:
		await _connect(KEY_G, pair[0], pair[1])
	scene.model.advance(4)
	await inspect(2)
	observe("working")
	_check(scene.state.stock.held == 1 and scene.state.remaining == 2 and "Working: 2 ticks" in scene.inspector.text, "Held work is shown as processing, not missing input")
	await _key(KEY_SPACE)
	var paused: Dictionary = scene.model.checkpoint()
	scene.model.advance(3)
	observe("paused")
	_check(scene.state.stock == paused.stock.merged({"player": 0}) and scene.state.remaining == 2 and "Drive switched off." in scene.inspector.text, "Stopped advice preserves exact unfinished phase")
	await _key(KEY_F5)
	var saved: Dictionary = scene.model.checkpoint()
	_check(scene.last_save_result.accepted, "Actual F5 still saves held work")
	await _key(KEY_H)
	await _key(KEY_RIGHT)
	await _key(KEY_H)
	_check(scene.model.checkpoint() == saved, "Read-only Help does not change live checkpoint")
	await _key(KEY_SPACE)
	scene.model.advance(12)
	scene._refresh()
	observe("blocked")
	_check(scene.state.stock.output == 1 and scene.state.stock.held == 1 and scene.state.remaining == 0, "Ordinary construction reaches real blocked held work")
	_check("Outlet full; plate ready." in scene.inspector.text and "[R] collect" in scene.inspector.text, "Full outlet names recovery action")
	await capture("blocked")
	await _key(KEY_R)
	observe("retrieved")
	_check(scene.state.inventories.get("P", 0) == 1 and scene.state.stock.output == 0, "Actual R transfers one existing plate")
	_check("Work done; blank retained." in scene.inspector.text, "Completed held work awaits next real tick after retrieval")
	scene.model.advance()
	scene._refresh()
	observe("recovered")
	_check(scene.state.stock.output == 1 and scene.state.stock.held == 1 and scene.state.remaining == 2, "Freeing outlet resumes retained work")
	await _key(KEY_F9)
	_check(scene.model.checkpoint() == saved and scene.selected.is_empty(), "Actual F9 preserves exact saved work and clears stale selection")
	await inspect(2)
	observe("restored")
	_check("Drive switched off." in scene.inspector.text and scene.state.remaining == 2 and scene.state.stock.held == 1, "Restored inspector derives from actual restored paused state")
	_check(_conserved(), "Finite quantities remain conserved")
	# A separate declared fresh worksite builds drive FIRST. Missing material
	# advice must respect the existing stop-before-edit authority contract.
	scene.free()
	scene = load("res://opening/opening.tscn").instantiate()
	scene.auto_advance = false
	root.add_child(scene)
	await process_frame
	await physics_frame
	for entry in [[KEY_4, -1], [KEY_1, 0], [KEY_2, 1], [KEY_3, 2]]:
		await _key(entry[0])
		await _click_cell(entry[1])
	for pair in [[-1, 0], [0, 1], [1, 2]]:
		await _connect(KEY_G, pair[0], pair[1])
	await inspect(2)
	observe("drive_first")
	_check(scene.state.powered and "Inlet missing. Stop [Space]." in scene.inspector.text, "Running drive requires stopping before a missing material link edit")
	await _connect(KEY_F, 1, 2)
	_check(scene.state.links.is_empty() and "Stop the drive" in scene.status_label.text, "Actual authority still refuses editing powered machinery")
	await _key(KEY_SPACE)
	await _connect(KEY_F, 0, 1)
	await _connect(KEY_F, 1, 2)
	await _key(KEY_SPACE)
	scene.model.advance(3)
	await inspect(2)
	observe("input_ready")
	_check(scene.state.stock.input == 1 and scene.state.stock.held == 0 and "Blank ready to press." in scene.inspector.text, "Present input is distinct from waiting for a blank")
	var file := FileAccess.open(evidence.path_join("inspection.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"observations": observations, "failures": failures}))
	file.close()
	if failures.is_empty():
		print("OPENING_INSPECTION_PASS")
		quit(0)
	else:
		print("OPENING_INSPECTION_FAIL " + JSON.stringify(failures))
		quit(1)
