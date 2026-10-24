extends "res://opening/opening.gd"
## Normal offline entry over one native World and the existing physical producer.
const NativeModel = preload("res://opening/native_model.gd")

func _ready() -> void:
	if "--legacy-fixture" in OS.get_cmdline_user_args():
		# Explicit historical entry only. Missing native resources never select it.
		super._ready()
		return
	model = NativeModel.new("opening-native-" + Crypto.new().generate_random_bytes(16).hex_encode(), ["P"], true)
	mode = "inspect"
	if not model.boot_result.get("accepted", false):
		push_error("Native opening refused: " + str(model.boot_result.get("reason", "invalid_boot")))
		get_tree().quit(1)
		return
	super._ready()
