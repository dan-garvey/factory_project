extends "res://opening-session/server.gd"
## Read-only typed records around the unchanged ordinary server lifecycle.
var cog_directory := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cog-directory="):
			cog_directory = argument.trim_prefix("--cog-directory=")
	super._initialize()

func write_json(path: String, value: Dictionary) -> bool:
	if path in [ready_path, report_path]:
		if not cog_directory.is_absolute_path() or not DirAccess.dir_exists_absolute(cog_directory):
			return false
		var name := "server-ready.bin" if path == ready_path else "server-final.bin"
		var destination := cog_directory.path_join(name)
		if FileAccess.file_exists(destination) or FileAccess.file_exists(destination + ".writing"):
			return false
		var observed := value.duplicate(true)
		if session != null and session.world != null:
			observed["observer_projection"] = session.world.projection()
			observed["observer_checkpoint"] = session.world.checkpoint()
			observed["observer_native_actors"] = session.actor_world.diagnostics() if session.actor_world != null else {}
		var bytes := var_to_bytes(observed)
		if bytes.size() > 8388608:
			return false
		var record := FileAccess.open(destination + ".writing", FileAccess.WRITE)
		if record == null:
			return false
		record.store_buffer(bytes)
		record.close()
		if DirAccess.rename_absolute(destination + ".writing", destination) != OK:
			return false
	return super.write_json(path, value)
