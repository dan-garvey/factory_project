extends RefCounted
## Prototype file boundary; the shared model is the sole state/schema validator.

const Model = preload("res://model.gd")
const MAGIC = "FACTORY-SAVE-1\n"
const MAX_BYTES = 1024 * 1024

static func _result(accepted: bool, reason: String) -> Dictionary:
	return {"accepted": accepted, "reason": reason}

static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().to_ascii_buffer()

static func encode(snapshot: Dictionary) -> PackedByteArray:
	var payload := var_to_bytes(snapshot) # Plain values; object encoding disabled.
	return MAGIC.to_ascii_buffer() + _digest(payload) + PackedByteArray([10]) + payload

static func write(model, path: String) -> Dictionary:
	return write_snapshot(model.checkpoint(), path)

static func write_snapshot(snapshot: Dictionary, path: String) -> Dictionary:
	var validator = Model.new()
	var validation: Dictionary = validator.restore_checkpoint(snapshot)
	if not validation.accepted:
		return _result(false, "invalid_capture:" + validation.reason)
	var bytes := encode(snapshot)
	if bytes.size() > MAX_BYTES:
		return _result(false, "capture_too_large")
	var absolute := ProjectSettings.globalize_path(path)
	if path.begins_with("res://") or not absolute.is_absolute_path() or not DirAccess.dir_exists_absolute(absolute.get_base_dir()):
		return _result(false, "missing_destination_directory")
	var temporary := absolute + ".pending"
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary):
		return _result(false, "pending_file_exists")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _result(false, "open_failed")
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(temporary) != bytes:
		return _result(false, "write_not_verified")
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		return _result(false, "publish_failed")
	return _result(true, "saved")

static func read_into(model, path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _result(false, "open_failed")
	var length := file.get_length()
	if length > MAX_BYTES:
		file.close()
		return _result(false, "capture_too_large")
	var bytes := file.get_buffer(length)
	file.close()
	var magic := MAGIC.to_ascii_buffer()
	var prefix := magic.size() + 65
	if bytes.size() < prefix + 4 or bytes.slice(0, magic.size()) != magic or bytes[magic.size() + 64] != 10:
		return _result(false, "invalid_envelope")
	var payload := bytes.slice(prefix)
	if bytes.slice(magic.size(), magic.size() + 64) != _digest(payload):
		return _result(false, "integrity_mismatch")
	var candidate = bytes_to_var(payload) # Never bytes_to_var_with_objects.
	if not candidate is Dictionary:
		return _result(false, "invalid_value")
	return model.restore_checkpoint(candidate)
