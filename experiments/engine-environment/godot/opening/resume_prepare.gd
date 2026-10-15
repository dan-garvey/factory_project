extends SceneTree
## Headless local-input preflight. Store and Model alone interpret the save.
const Model = preload("res://model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")

func _initialize():
	var source := ""
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="): source = argument.trim_prefix("--resume-input=")
		elif argument.begins_with("--resume-report="): output = argument.trim_prefix("--resume-report=")
	var model = Model.new()
	var result: Dictionary = Store.read_into(model, source)
	if result.accepted and not model.projection().options.get("opening", false):
		result = {"accepted": false, "reason": "not_an_opening_worksite"}
	var report: Dictionary = result.duplicate(true)
	if result.accepted:
		report["checkpoint"] = model.checkpoint()
		report["state"] = model.projection()
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot retain resume preflight result")
		quit(1)
		return
	file.store_string(JSON.stringify(report))
	file.close()
	print("OPENING_RESUME_VALID" if result.accepted else "OPENING_RESUME_REFUSED " + result.reason)
	quit(0 if result.accepted else 1)
