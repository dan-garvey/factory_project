extends SceneTree
## Test-only real Core/Store files valid under Core but outside host scope.
const Model = preload("res://model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
var directory := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			directory = argument.trim_prefix("--output-dir=")
	call_deferred("produce")

func produce() -> void:
	if not directory.is_absolute_path() or not DirAccess.dir_exists_absolute(directory):
		push_error("Checkpoint controls need an owned absolute output directory")
		quit(1)
		return
	var neutral = Model.new(0, "host-negative-neutral", 2)
	var actor = Model.new(16, "host-negative-actor", 1, {"opening": true})
	var placed: Dictionary = actor.command({"context": actor.context, "client": "EXAMPLE",
		"request": "control-place", "action": "place", "kind": "collector", "cell": [0, 0]})
	if not placed.accepted or not Store.write(neutral, directory.path_join("neutral.factory")).accepted or not Store.write(actor, directory.path_join("actor.factory")).accepted:
		push_error("Actual Core/Store could not create valid incompatible controls")
		quit(1)
		return
	print("CHECKPOINT_CONTROLS_READY")
	quit(0)
