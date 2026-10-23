extends SceneTree
## Test-only local file controls exercise normal transport, not public admin RPC.
const Session = preload("res://opening-session/session.gd")
var session
var role := ""
var port := 0
var directory := ""
var sequence := 0
var busy := false
var waiting_request := ""
var decisions: Dictionary = {}
var saved_intent: Dictionary = {}
var records: Array = []
var checks := 0
var failures: Array[String] = []
var lost_reason := ""

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--pose-only"):
		call_deferred("check_pose_protocol")
		return
	if OS.get_cmdline_user_args().has("--state-coalescing-only"):
		call_deferred("check_state_coalescing")
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--session-port="): port = int(argument.trim_prefix("--session-port="))
		elif argument.begins_with("--session-role="): role = argument.trim_prefix("--session-role=")
		elif argument.begins_with("--control-dir="): directory = argument.trim_prefix("--control-dir=")
	call_deferred("_boot")
	process_frame.connect(_poll)

func state_frame(serial: int, revision := 0, order := 0) -> Dictionary:
	return {"context": "state-burst", "serial": serial,
		"snapshot": {"context": "state-burst", "revision": revision, "order": order,
			"actors": {"P": {"position": [serial, 0, 0]}}}}

func check_state_coalescing() -> void:
	# Invented authenticated receive data only. No socket, World or body.
	var container := Node.new()
	container.name = "OpeningShared"
	session = Session.new()
	session.name = "Session"
	container.add_child(session)
	root.add_child(container)
	session.context = "state-burst"
	session._ready_for_commands = true
	var observations: Array = []
	session.changed.connect(func(view: Dictionary): observations.append({"serial": session.last_serial, "view": view.duplicate(true)}))
	for serial in [1, 2, 3]:
		session._apply_frame(state_frame(serial))
	check(observations.is_empty(), "An incoming state burst must not rebuild the view per packet.")
	await process_frame
	check(observations.size() == 1 and observations.back().serial == 3
		and session.projection().actors.P.position == [3, 0, 0], "The deferred view receives exactly the newest complete state.")
	if not failures.is_empty():
		finish_state_checks(container)
		return
	session._apply_frame(state_frame(4))
	session._apply_frame(state_frame(5, 1, 1), true)
	check(observations.size() == 2 and observations.back().serial == 5 and session.projection().order == 1,
		"A reliable outcome installs and publishes its snapshot immediately.")
	await process_frame
	check(observations.size() == 2, "An older queued state cannot follow the immediate outcome.")
	session._apply_frame(state_frame(7, 2, 2))
	session._apply_frame(state_frame(6, 1, 1), true)
	check(observations.back().serial == 6, "An outcome remains visible even when a newer ordinary state is pending.")
	await process_frame
	check(observations.back().serial == 7 and session.projection().order == 2, "The newer complete state follows the outcome monotonically.")
	var before: Dictionary = session.projection()
	var count := observations.size()
	session._apply_frame(state_frame(6, 1, 1))
	var wrong := state_frame(8, 2, 2)
	wrong.context = "another-context"
	session._apply_frame(wrong)
	await process_frame
	check(session.projection() == before and observations.size() == count, "Stale and wrong-context states preserve the confirmed view.")
	session._apply_frame(state_frame(8, 2, 2))
	session.close()
	await process_frame
	check(session.projection() == before and observations.size() == count and session.world == null,
		"Closing clears pending state while preserving the read-only view and absence of a World.")
	finish_state_checks(container)

func finish_state_checks(container: Node) -> void:
	container.free()
	print("SHARED_STATE_COALESCING_", "PASS" if failures.is_empty() else "FAIL", " ", checks)
	quit(0 if failures.is_empty() else 1)

func check_pose_protocol() -> void:
	# Invented authenticated receive data checks ordering and packet size. The
	# separate native P/Q run supplies actual ENet and World observations.
	var container := Node.new()
	container.name = "OpeningShared"
	session = Session.new()
	session.name = "Session"
	container.add_child(session)
	root.add_child(container)
	session.context = "pose-check"
	session._ready_for_commands = true
	session.last_serial = 10
	session._cache = {"context": session.context, "revision": 2, "order": 3,
		"actors": {"P": {"ready": true, "position": [0.0, 1.0, 0.0],
			"native_epoch": 1, "capabilities": {"build_reach": 4.0}},
			"Q": {"ready": true, "position": [1.0, 1.0, 0.0],
				"native_epoch": 1, "capabilities": {"build_reach": 4.0}}},
		"stock": {"source": 16}}
	var pose := {"context": session.context, "serial": 11, "revision": 2, "order": 3,
		"actors": {"P": {"ready": true, "position": [2.0, 1.0, 0.0], "native_epoch": 2},
			"Q": {"ready": true, "position": [3.0, 1.0, 0.0], "native_epoch": 2}}}
	check(var_to_bytes(pose).size() < 1100, "Both actor samples fit below the pinned 1392-byte MTU with RPC headroom")
	session._apply_pose(pose)
	await process_frame
	await process_frame
	var observed: Dictionary = session.projection()
	check(session.last_serial == 11 and observed.actors.P.position == [2.0, 1.0, 0.0]
		and observed.actors.Q.position == [3.0, 1.0, 0.0]
		and observed.actors.P.capabilities.build_reach == 4.0 and observed.stock.source == 16,
		"One compact packet updates both actors without replacing material or capabilities")
	var stale: Dictionary = pose.duplicate(true)
	stale.actors.P.position = [99.0, 1.0, 0.0]
	session._apply_pose(stale)
	stale.serial = 12
	stale.revision = 1
	session._apply_pose(stale)
	check(session.last_serial == 11 and session.projection() == observed,
		"Old serials and World revisions cannot roll actor state back")
	var incomplete: Dictionary = pose.duplicate(true)
	incomplete.serial = 12
	incomplete.actors.erase("Q")
	session._apply_pose(incomplete)
	var malformed: Dictionary = pose.duplicate(true)
	malformed.serial = 12
	malformed.actors.P.position = [NAN, 1.0, 0.0]
	session._apply_pose(malformed)
	check(session.last_serial == 11 and session.projection() == observed,
		"Missing or non-finite actor samples cannot contaminate the client view")
	var newer: Dictionary = observed.duplicate(true)
	newer.revision = 3
	newer.order = 4
	newer.stock.source = 15
	session._apply_frame({"context": session.context, "serial": 13, "snapshot": newer}, true)
	var wrong_base: Dictionary = pose.duplicate(true)
	wrong_base.serial = 14
	session._apply_pose(wrong_base)
	check(session.projection().stock.source == 15 and session.projection().actors.P.position == [2.0, 1.0, 0.0]
		and session.last_serial == 13,
		"An actor packet based on old material cannot overtake a newer full state")
	var current: Dictionary = pose.duplicate(true)
	current.serial = 15
	current.revision = 3
	current.order = 4
	current.actors.P.position = [4.0, 1.0, 0.0]
	session._apply_pose(current)
	await process_frame
	await process_frame
	check(session.last_serial == 15 and session.projection().actors.P.position == [4.0, 1.0, 0.0]
		and session.projection().stock.source == 15,
		"A current actor packet follows the material state without replacing its stock")
	var earlier: Dictionary = current.duplicate(true)
	earlier.serial = 16
	earlier.actors.P.position = [5.0, 1.0, 0.0]
	var latest: Dictionary = earlier.duplicate(true)
	latest.serial = 17
	latest.actors.P.position = [6.0, 1.0, 0.0]
	session._apply_pose(earlier)
	session._apply_pose(latest)
	await process_frame
	await process_frame
	check(session.last_serial == 17 and session.projection().actors.P.position == [6.0, 1.0, 0.0]
		and session.projection().stock.source == 15,
		"A burst keeps its newest actor packet without replaying older poses")
	container.free()
	print("POSE_PROTOCOL_", "PASS" if failures.is_empty() else "FAIL", " ", checks)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path + ".writing", FileAccess.WRITE)
	check(file != null, "Owned client diagnostic opens")
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(value))
	file.close()
	check(DirAccess.rename_absolute(path + ".writing", path) == OK, "Atomic diagnostic publication")

func metadata() -> Dictionary:
	return {"actor": session.actor, "namespace": session.request_namespace, "pid": OS.get_process_id(),
		"server_relay": (session.multiplayer as SceneMultiplayer).server_relay,
		"request_sequence": session.request_sequence, "context": session.context,
		"serial": session.last_serial, "ready": session.is_ready(),
		"live_model": session.world != null, "snapshot": session.projection()}

func _boot() -> void:
	if not directory.is_absolute_path() or not DirAccess.dir_exists_absolute(directory):
		push_error("Test client requires its owned control directory")
		quit(1)
		return
	var container := Node.new()
	container.name = "OpeningShared"
	session = Session.new()
	session.name = "Session"
	container.add_child(session)
	root.add_child(container)
	session.welcomed.connect(func(_actor, _namespace, _snapshot): write_json(directory.path_join("ready.json"), metadata()))
	session.outcome.connect(func(value: Dictionary): decisions[str(value.get("request", ""))] = value)
	session.disconnected.connect(func(reason: String): lost_reason = reason)
	check(session.world == null and session.projection().is_empty(), "No initial client worksite Model or fake snapshot")
	check(not session.submit({"action": "remove", "entity": "missing"}).queued, "Not-ready action refuses without a world")
	check(session.join_loopback(port, role) == OK, "Actual loopback connection starts")

func _poll() -> void:
	if session == null or busy:
		return
	var path := directory.path_join("control.json")
	if not FileAccess.file_exists(path):
		return
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or int(value.get("sequence", 0)) <= sequence:
		return
	sequence = int(value.sequence)
	busy = true
	_run_operation(value)

func _run_operation(control: Dictionary) -> void:
	var operation: String = control.get("operation", "")
	var data: Dictionary = {}
	match operation:
		"submit", "retry", "wrong_actor", "wrong_context", "reuse", "old_namespace":
			var queued: Dictionary
			if operation == "submit":
				var action: Dictionary = control.get("payload", {}).duplicate(true)
				# JSON control numbers are floats. Reify declared integer cell
				# input here; the actual transport/core never coerces wire values.
				if action.get("cell") is Array:
					var cell: Array = []
					for value in action.cell:
						check((value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value)), "Private test cell input is integral")
						cell.append(int(value))
					action.cell = cell
				if action.has("level"):
					var level: Variant = action.level
					check((level is int or level is float) and is_finite(float(level)) and float(level) == float(int(level)), "Private test height input is integral")
					action.level = int(level)
				queued = session.submit(action)
				if queued.queued:
					saved_intent = session._sent[queued.request].duplicate(true)
			elif operation == "retry":
				queued = session.retry(str(saved_intent.get("request", "")))
			else:
				var intent := saved_intent.duplicate(true)
				if operation == "wrong_actor":
					intent["client"] = "Q" if role == "P" else "P"
					intent["request"] = session.request_namespace + "99991"
				elif operation == "wrong_context":
					intent["context"] = "another-worksite"
					intent["request"] = session.request_namespace + "99992"
				elif operation == "reuse":
					intent["action"] = "remove"
				queued = {"accepted": false, "queued": true, "request": intent.request}
				session._wire_command.rpc_id(1, intent)
			check(queued.accepted == false, "Enqueuing is never accepted authority work")
			data["queued"] = queued
			if queued.queued:
				waiting_request = queued.request
				# A retry uses the same request: wait for a NEW actual reply.
				while not decisions.has(waiting_request):
					await process_frame
				var result: Dictionary = decisions[waiting_request]
				decisions.erase(waiting_request)
				while session.projection().get("revision", -1) < result.revision or session.projection().get("order", -1) < result.order:
					await process_frame
				data["outcome"] = result
		"snapshot":
			var minimum: int = control.get("payload", {}).get("minimum_order", 0)
			while session.projection().get("order", -1) < minimum:
				await process_frame
		"disconnect":
			var before: Dictionary = session.projection()
			session.close()
			check(not session.is_ready() and session.projection() == before, "Disconnect retains read-only server snapshot")
			check(not session.submit({"action": "remove", "entity": "collector-1"}).queued, "Disconnected client refuses mutation")
		"role_occupied", "unjoined":
			check(not session.is_ready() and session._transport == null, "Adversarial connection starts from disconnected client")
			lost_reason = ""
			if operation == "unjoined":
				# Probe-only omission of the normal join handshake. The shared
				# adapter has no alternate client/admin path for this negative.
				session.multiplayer.connected_to_server.disconnect(session._connected)
			var requested: String = ("P" if role == "Q" else "Q") if operation == "role_occupied" else role
			check(session.join_loopback(port, requested) == OK, "Actual adversarial connection starts")
			if operation == "unjoined":
				while session._transport.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
					await process_frame
				session._wire_command.rpc_id(1, {"action": "retrieve", "entity": "processor-1", "client": role,
					"context": session.context, "request": session.request_namespace + "99993"})
			while lost_reason.is_empty():
				await process_frame
			if operation == "unjoined":
				session.multiplayer.connected_to_server.connect(session._connected)
			check(lost_reason == ("role_unavailable" if operation == "role_occupied" else "not_joined"), "Real authority refuses inadmissible connection")
			data["refusal"] = lost_reason
		"join":
			var old_namespace: String = session.request_namespace
			check(session.join_loopback(port, role) == OK, "Actual client rejoin starts")
			while not session.is_ready():
				await process_frame
			check(session.request_namespace != old_namespace and session.request_sequence == 0, "Rejoin gets fresh caller namespace")
		"finish":
			pass
		_:
			check(false, "Unsupported private test operation")
	check(session.world == null, "Client never owns a live worksite Model")
	data.merge(metadata())
	var record := {"schema": 1, "sequence": sequence, "operation": operation,
		"status": "pass" if failures.is_empty() else "fail", "checks": checks,
		"failures": failures.duplicate(), "data": data}
	records.append(record.duplicate(true))
	write_json(directory.path_join("ack-%d.json" % sequence), record)
	busy = false
	if operation == "finish":
		write_json(directory.path_join("final.json"), {"schema": 1, "status": record.status,
			"checks": checks, "failures": failures, "records": records, "data": metadata()})
		print("OPENING_SESSION_CLIENT_PASS" if failures.is_empty() else "OPENING_SESSION_CLIENT_FAIL")
		quit(0 if failures.is_empty() else 1)
