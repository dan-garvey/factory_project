extends Node
## Copied-only autoload: attaches before authority ready, preserves startup cuts.
const Authority = preload("res://moving-transfer/authority.gd")
const Probe = preload("res://moving-transfer/probe.gd")
var probe
var output := ""

func _ready() -> void:
	probe = Probe.new()
	add_child(probe)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--transfer-report="): output = argument.trim_prefix("--transfer-report=")
		elif argument.begins_with("--transfer-captures="): probe.capture_directory = argument.trim_prefix("--transfer-captures=")
	get_tree().node_added.connect(_added)
	call_deferred("_run")

func _added(node: Node) -> void:
	if node.get_script() == Authority:
		probe.attach(node)
		node.ready.connect(_pre_physics_control.bind(node), CONNECT_ONE_SHOT)

func _pre_physics_control(authority) -> void:
	# Disclosed check harness only. Normal play has no synthetic request/cache
	# entry or startup refusal message. ready fires before the parent view adds
	# its ordinary transfer message handler, and before the first physics cut.
	authority.command({"action": "transfer", "actor": "Q", "request": "bootstrap", "kind": "A", "amount": 1})

func _run() -> void:
	await get_tree().process_frame
	var scene = get_tree().current_scene
	if scene == null or probe.subject != scene.authority:
		push_error("Observer did not attach to the actual ordinary authority before ready")
		get_tree().quit(1)
		return
	var report: Dictionary = await probe.run(scene)
	report.merge({"scene": scene.scene_file_path, "view_script": scene.get_script().resource_path,
		"authority_script": scene.authority.get_script().resource_path})
	if not Probe.publish(output, report):
		push_error("Cannot publish fresh ordinary moving-transfer report")
		get_tree().quit(1)
		return
	print("MOVING_TRANSFER_PASS" if report.status == "pass" else "MOVING_TRANSFER_FAIL")
	get_tree().quit(0 if report.status == "pass" else 1)
