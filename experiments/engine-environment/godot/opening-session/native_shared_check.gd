extends SceneTree
## Headless ordinary client consumer. Session carries all actual RPC traffic.
var view
var session
var role := ""
var phase := ""
var directory := ""
var previous := ""
var deadline := 0
var checks := 0
var finished := false
var outcomes: Dictionary = {}
var facts: Dictionary = {"steps": []}

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--session-role="):
			role = argument.trim_prefix("--session-role=")
		elif argument.begins_with("--native-check-phase="):
			phase = argument.trim_prefix("--native-check-phase=")
		elif argument.begins_with("--native-check-directory="):
			directory = argument.trim_prefix("--native-check-directory=")
		elif argument.begins_with("--native-check-previous="):
			previous = argument.trim_prefix("--native-check-previous=")
	deadline = Time.get_ticks_msec() + 20000
	call_deferred("_run")

func _write(name: String, value: Dictionary) -> bool:
	var path := directory.path_join(name)
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".writing"):
		return false
	var file := FileAccess.open(path + ".writing", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.close()
	return DirAccess.rename_absolute(path + ".writing", path) == OK

func _finish(status: String, reason: String = "") -> void:
	if finished:
		return
	finished = true
	facts.merge({"status": status, "reason": reason, "actor": role, "phase": phase,
		"checks": checks, "pid": OS.get_process_id(), "evidence": "native_shared_scene_consumer"})
	if session != null:
		facts.merge({"snapshot": session.projection(), "namespace": session.request_namespace,
			"request_sequence": session.request_sequence, "client_world_is_null": session.world == null})
	if not _write(role + "-result.json", facts):
		push_error("Cannot retain the native shared client result")
		quit(1)
		return
	print(JSON.stringify({"status": status, "actor": role, "phase": phase, "checks": checks, "reason": reason}))
	quit(0 if status == "pass" else 1)

func _ok(condition: bool, reason: String) -> bool:
	checks += 1
	if not condition:
		_finish("fail", reason)
		push_error(reason)
	return condition

func _barrier(name: String) -> bool:
	var path := directory.path_join(name)
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(path):
		await process_frame
	if not _ok(FileAccess.file_exists(path), "The other client must publish its validated barrier"):
		return false
	var record = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _ok(record is Dictionary and record.get("status") == "pass", "A failed or incomplete record cannot release the other client")

func _order(minimum: int) -> bool:
	while Time.get_ticks_msec() < deadline and session.projection().get("order", -1) < minimum:
		await process_frame
	return _ok(session.projection().get("order", -1) >= minimum, "The confirmed projection must reach the required material order")

func _submit(action: Dictionary) -> Dictionary:
	var queued: Dictionary = session.submit(action)
	if not _ok(queued.get("queued", false) and not queued.accepted, "Local queueing is not an accepted authority result"):
		return {}
	while Time.get_ticks_msec() < deadline and not outcomes.has(queued.request):
		await process_frame
	if not _ok(outcomes.has(queued.request), "The server must deliver the original request outcome"):
		return {}
	var reply: Dictionary = outcomes[queued.request]
	outcomes.erase(queued.request)
	facts.steps.append({"action": action.duplicate(true), "queued": queued, "outcome": reply.duplicate(true)})
	if reply.get("accepted", false):
		if not _ok(reply.get("reach", {}).get("actor") == role and reply.reach.native_epoch is int and reply.reach.native_epoch > 0,
			"The actual receipt must bind this client to a native actor observation"):
			return {}
	return reply

func _run() -> void:
	if role not in ["P", "Q"] or phase not in ["produce", "resume"] or not directory.is_absolute_path():
		push_error("The native shared check requires a role, phase and owned directory")
		quit(1)
		return
	view = load("res://opening/shared_opening.tscn").instantiate()
	root.add_child(view)
	session = view.session
	session.outcome.connect(func(reply: Dictionary): outcomes[str(reply.get("request", ""))] = reply)
	while Time.get_ticks_msec() < deadline and not session.is_ready():
		await process_frame
	if not _ok(session.is_ready() and session.world == null and view.actor_world == null, "An ordinary client must remain a read-only Session facade"):
		return
	var initial: Dictionary = session.projection()
	if not _ok(initial.options.get("native", false) and initial.actors.P.ready and initial.actors.Q.ready and initial.stock.source is int,
		"Both actual server actors and integer native quantities must reach the client"):
		return
	if not _ok(session.request_sequence == 0 and view.request_sequence == 0, "Initial readback precedes every material request"):
		return
	facts["initial_snapshot"] = initial.duplicate(true)
	if phase == "resume":
		var old = JSON.parse_string(FileAccess.get_file_as_string(previous.path_join(role + "-result.json")))
		if not _ok(old is Dictionary and old.status == "pass" and old.namespace != session.request_namespace,
			"A fresh host must allocate a new request namespace"):
			return
		if not _ok(initial.order == 6 and initial.stock.source == 15 and initial.stock.collector == 0 and initial.cargo.P.raw == 0 and initial.cargo.Q.raw == 1,
			"Fresh client custody must match the retained actual host save"):
			return
	if not _ok(_write(role + "-initial.json", {"status": "pass", "namespace": session.request_namespace, "snapshot": initial, "request_sequence": session.request_sequence}),
		"The initial facts must be retained before releasing peer input"):
		return
	if not await _barrier(("Q" if role == "P" else "P") + "-initial.json"):
		return
	if phase == "produce" and role == "P":
		var collector: Dictionary = await _submit({"action": "place", "kind": "collector", "cell": [0, 1]})
		if not _ok(collector.get("accepted", false), "P places the nearby finite collector"):
			return
		var wheel: Dictionary = await _submit({"action": "place", "kind": "wheel", "cell": [-1, 1]})
		if not _ok(wheel.get("accepted", false), "P places the nearby finite source"):
			return
		var shaft: Dictionary = await _submit({"action": "connect_drive", "from": wheel.entity, "to": collector.entity})
		if not _ok(shaft.get("accepted", false), "The actual drive action consumes a shaft"):
			return
		var power: Dictionary = await _submit({"action": "set_power", "active": true})
		if not _ok(power.get("accepted", false), "P starts the native source"):
			return
		while Time.get_ticks_msec() < deadline and session.projection().stock.collector != 1:
			await process_frame
		if not _ok(session.projection().stock.source == 15 and session.projection().stock.collector == 1, "A natural server tick moves exactly one retained raw unit"):
			return
		var stopped: Dictionary = await _submit({"action": "set_power", "active": false})
		if not _ok(stopped.get("accepted", false) and _write("line-ready.json", {"status": "pass"}), "Stop the source before the other client empties its buffer"):
			return
		if not await _barrier("Q-done.json") or not await _order(6):
			return
	elif phase == "produce":
		if not await _barrier("line-ready.json") or not await _order(5):
			return
		if not await _recover():
			return
		if not _ok(_write("Q-done.json", {"status": "pass"}), "Q publishes only after accepted recovery"):
			return
	elif role == "Q":
		var insert: Dictionary = await _submit({"action": "insert_raw", "entity": _collector(), "amount": 1})
		if not _ok(insert.get("accepted", false) and _write("Q-inserted.json", {"status": "pass"}), "Q reinserts its original carried unit after both initial barriers"):
			return
		if not await _barrier("P-done.json") or not await _order(8):
			return
	else:
		if not await _barrier("Q-inserted.json") or not await _order(7):
			return
		if not await _recover():
			return
		if not _ok(_write("P-done.json", {"status": "pass"}), "P publishes only after fresh native recovery"):
			return
	var final: Dictionary = session.projection()
	if not _ok(final.stock.source == 15 and final.stock.collector == 0 and final.cargo.P.raw == (1 if phase == "resume" else 0) and final.cargo.Q.raw == (0 if phase == "resume" else 1),
		"The sixteen-unit total and individual custody must remain exact"):
		return
	_finish("pass")

func _collector() -> String:
	for id in session.projection().entities:
		if session.projection().entities[id].kind == "collector":
			return id
	return ""

func _recover() -> bool:
	var reply: Dictionary = await _submit({"action": "recover", "entity": _collector()})
	return _ok(reply.get("accepted", false) and reply.get("moved_raw") == 1 and reply.get("moved_products") == 0,
		"The authenticated actor recovers one raw unit without converting it")
