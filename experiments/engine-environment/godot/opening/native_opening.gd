extends "res://opening/opening.gd"
## Normal offline entry over one native World and the existing physical producer.
const NativeModel = preload("res://opening/native_model.gd")
var transmission_key := ""

func _ready() -> void:
	if "--legacy-fixture" in OS.get_cmdline_user_args():
		# Explicit historical entry only. Missing native resources never select it.
		super._ready()
		return
	model = NativeModel.new("opening-native-" + Crypto.new().generate_random_bytes(16).hex_encode())
	if not model.boot_result.get("accepted", false):
		push_error("Native opening refused: " + str(model.boot_result.get("reason", "invalid_boot")))
		get_tree().quit(1)
		return
	super._ready()

func _refresh() -> void:
	if not legacy_fixture and model != null:
		var next: Dictionary = model.projection()
		var next_key := JSON.stringify(next.get("transmission_parts", {}))
		if next_key != transmission_key:
			geometry_key = ""
			transmission_key = next_key
	super._refresh()

func _rebuild_machines() -> void:
	if legacy_fixture:
		super._rebuild_machines()
		return
	# Suppress the old edge decoration. Draw the actual independent shaft
	# geometry from the native projection instead, including orphaned shafts.
	var old_links: Array = state.get("drive_links", [])
	state["drive_links"] = []
	super._rebuild_machines()
	state["drive_links"] = old_links
	for part in state.get("transmission_parts", {}).values():
		if part.kind != "shaft":
			continue
		var at := Vector3(part.center[0], part.center[1], part.center[2]) * (PITCH / 4.0) + Vector3(0, Geometry.ANCHOR_HEIGHT, 0)
		var axis: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][part.axis]
		var half: float = float(part.half_span) * PITCH / 4.0
		_bar(machine_root, at - axis * half, at + axis * half, 0.09, Color("d1b56e"))
