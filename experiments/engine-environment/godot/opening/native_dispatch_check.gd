extends SceneTree
## Metadata guard and real typed-VM call. This has no physical producer.
func _init() -> void:
	var names := ["initialize", "command", "publish_actor", "invalidate_actor", "advance", "projection", "checkpoint", "restore_checkpoint", "validate_checkpoint"]
	var methods: Dictionary = {}
	for method in ClassDB.class_get_method_list("FactoryNativeWorld", true):
		methods[str(method.name)] = method
	for name in names:
		if not methods.has(name) or int(methods[name].flags) & METHOD_FLAG_VARARG == 0:
			# The old library is rejected before the known unsafe dispatch path.
			print(JSON.stringify({"status": "rejected", "reason": "missing_vararg_flag", "method": name, "typed_calls": 0}))
			quit(41)
			return
	var script := GDScript.new()
	# The exact registered native receiver forces the VM path that a generic
	# Object.callv facade does not exercise. It is compiled only when the real
	# extension is loaded, not by the source-only staged project import.
	script.source_code = """
extends RefCounted
func run() -> bool:
	var host: FactoryNativeWorld = FactoryNativeWorld.new()
	var boot: Dictionary = host.initialize("typed-dispatch", ["P"])
	if not boot.get("accepted", false):
		return false
	var state: Dictionary = host.projection()
	var saved: Dictionary = host.checkpoint()
	var validation: Dictionary = host.validate_checkpoint(saved)
	return state.stock.source is int and state.stock.source == 16 and state.order == 0 and validation.get("accepted", false)
"""
	if script.reload() != OK:
		quit(1)
		return
	var fixture = script.new()
	if fixture == null or fixture.run() != true:
		quit(1)
		return
	print(JSON.stringify({"status": "pass", "evidence": "native_typed_vm_dispatch", "metadata_guards": names.size(), "typed_calls": 4, "physical_producers": 0}))
	quit(0)
