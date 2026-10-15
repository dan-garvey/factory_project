extends SceneTree
const Authority = preload("res://moving-transfer/authority.gd")
const Probe = preload("res://moving-transfer/probe.gd")
var output := ""
var control := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--transfer-report="): output = argument.trim_prefix("--transfer-report=")
		elif argument == "--transfer-control=wrong_facing": control = true
	call_deferred("_run")

func _run() -> void:
	var probe := Probe.new()
	root.add_child(probe)
	var authority := Authority.new()
	if control: authority.initial_fixture("wrong_facing")
	probe.attach(authority)
	root.add_child(authority)
	authority.command({"action": "transfer", "actor": "Q", "request": "bootstrap", "kind": "A", "amount": 1})
	var report: Dictionary = await probe.run(null, control)
	if not Probe.publish(output, report):
		push_error("Cannot publish fresh owned moving-transfer report")
		quit(1)
		return
	print("MOVING_TRANSFER_PASS" if report.status == "pass" else "MOVING_TRANSFER_FAIL")
	quit(0 if report.status == "pass" else 1)
