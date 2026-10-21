extends SceneTree
## Dedicated loopback process. Control files are local lifecycle diagnostics only.
const Session = preload("res://opening-session/session.gd")
var session
var port := 0
var frozen := false
var ready_path := ""
var stop_path := ""
var report_path := ""
var status_path := ""
var started := 0
var admission_hold := ""
var outcome_hold := ""
var observe_request := ""
var observe_response := ""
var observed := 0
var save_path := ""
var resume_path := ""
var checkpoint_store
var resume_result: Dictionary = {}
var incoming_sha256 := ""
var loaded_checkpoint: Dictionary = {}
var legacy_fixture := false
var native_authority := false
var actor_roster: Array = ["P", "Q"]

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--session-port="): port = int(argument.trim_prefix("--session-port="))
		elif argument == "--frozen-clock": frozen = true
		elif argument == "--legacy-fixture": legacy_fixture = true
		elif argument == "--native-world": native_authority = true
		elif argument.begins_with("--actor-roster="): actor_roster = Array(argument.trim_prefix("--actor-roster=").split(","))
		elif argument.begins_with("--ready-file="): ready_path = argument.trim_prefix("--ready-file=")
		elif argument.begins_with("--stop-file="): stop_path = argument.trim_prefix("--stop-file=")
		elif argument.begins_with("--report-file="): report_path = argument.trim_prefix("--report-file=")
		elif argument.begins_with("--status-file="): status_path = argument.trim_prefix("--status-file=")
		elif argument.begins_with("--admission-hold-file="): admission_hold = argument.trim_prefix("--admission-hold-file=")
		elif argument.begins_with("--outcome-hold-file="): outcome_hold = argument.trim_prefix("--outcome-hold-file=")
		elif argument.begins_with("--observe-request="): observe_request = argument.trim_prefix("--observe-request=")
		elif argument.begins_with("--observe-response="): observe_response = argument.trim_prefix("--observe-response=")
		elif argument.begins_with("--save-file="): save_path = argument.trim_prefix("--save-file=")
		elif argument.begins_with("--resume-input="): resume_path = argument.trim_prefix("--resume-input=")
	call_deferred("_boot")
	process_frame.connect(_poll)

func write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path + ".writing", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "", true, true))
	file.close()
	return DirAccess.rename_absolute(path + ".writing", path) == OK

func _boot() -> void:
	for path in [ready_path, stop_path, report_path, status_path]:
		if not path.is_absolute_path() or not DirAccess.dir_exists_absolute(path.get_base_dir()) or FileAccess.file_exists(path):
			push_error("Server needs fresh owned absolute lifecycle paths")
			quit(1)
			return
	for path in [admission_hold, outcome_hold, observe_request, observe_response]:
		if not path.is_empty() and (not path.is_absolute_path() or not DirAccess.dir_exists_absolute(path.get_base_dir())):
			push_error("Local observation/barrier paths must be owned absolute paths")
			quit(1)
			return
	if not actor_roster in [["P"], ["P", "Q"]]:
		checkpoint_failure("invalid_actor_roster")
		return
	if native_authority and legacy_fixture:
		checkpoint_failure("native_world_requires_physical_profile")
		return
	if checkpoint_enabled():
		var option_error := checkpoint_options_error()
		if not option_error.is_empty():
			checkpoint_failure(option_error)
			return
		# The accepted minimal nine-file transport consumer has no Store.
		# Keep its no-option path independent of this optional host boundary.
		checkpoint_store = load("res://save-tests/checkpoint_file.gd")
		if checkpoint_store == null:
			checkpoint_failure("store_unavailable")
			return
	var container := Node.new()
	container.name = "OpeningShared"
	session = Session.new()
	session.name = "Session"
	session.admission_hold_path = admission_hold
	session.outcome_hold_path = outcome_hold
	container.add_child(session)
	root.add_child(container)
	var error: Error = session.serve_loopback(port, frozen, not legacy_fixture, actor_roster, native_authority)
	if error != OK:
		push_error("Loopback bind refused: " + str(error))
		quit(1)
		return
	if not resume_path.is_empty():
		incoming_sha256 = FileAccess.get_sha256(resume_path)
		var restored = checkpoint_store.read_into(session.world, resume_path)
		if not restored is Dictionary or not restored.get("accepted") is bool or not restored.accepted:
			checkpoint_failure("resume_refused:" + str(restored.get("reason", "invalid_result") if restored is Dictionary else "invalid_result"))
			return
		if FileAccess.get_sha256(resume_path) != incoming_sha256:
			checkpoint_failure("resume_input_changed")
			return
		loaded_checkpoint = session.world.checkpoint()
		if not compatible_opening(loaded_checkpoint):
			checkpoint_failure("incompatible_opening")
			return
		# Logical world/request identity belongs to the restored Core, while
		# transport serial, socket bindings and join namespaces start fresh.
		session.context = session.world.context
		resume_result = {"accepted": true, "reason": "restored", "source_sha256": incoming_sha256}
	if not legacy_fixture:
		if session.start_physical_world() != OK:
			checkpoint_failure("physical_adapter_unavailable:" + session.actor_error)
			return
		# Initial/restored bodies must really register at the declared poses.
		# No client or ready marker is admitted while that native proof is pending.
		for _tick in range(120):
			if not session.actor_error.is_empty() or session.physical_ready():
				break
			await physics_frame
		if not session.actor_error.is_empty() or not session.physical_ready():
			checkpoint_failure("physical_initialization_refused:" + session.actor_error)
			return
	started = Time.get_ticks_msec()
	session.server_joined.connect(func(_actor): _status())
	session.server_lost.connect(func(_actor): _status())
	session.server_event.connect(_status)
	var ready := {"schema": 1, "port": port, "pid": OS.get_process_id(), "context": session.context, "clock_frozen": frozen,
		"physical_profile": not legacy_fixture, "physical_ready": session.physical_ready()}
	if checkpoint_enabled():
		ready["persistence"] = {"resume": resume_result, "loaded_checkpoint": loaded_checkpoint,
			"save_file": save_path, "resume_input": resume_path}
	if not write_json(ready_path, ready):
		push_error("Cannot write server readiness diagnostic")
		quit(1)
		return
	_status()
	print("OPENING_SESSION_SERVER_READY")

func checkpoint_enabled() -> bool:
	return not save_path.is_empty() or not resume_path.is_empty()

func fresh_destination() -> bool:
	for path in [save_path, save_path + ".pending"]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			return false
	return true

func checkpoint_paths() -> Array[String]:
	var paths: Array[String] = []
	if not resume_path.is_empty(): paths.append(resume_path)
	if not save_path.is_empty(): paths.append_array([save_path, save_path + ".pending"])
	return paths

func checkpoint_options_error() -> String:
	var owned := ready_path.get_base_dir().simplify_path()
	for path in [save_path, resume_path]:
		if not path.is_empty() and (not path.is_absolute_path() or path != path.simplify_path()
			or path.get_base_dir() != owned):
			return "checkpoint_path_outside_owned_run"
	for checkpoint in checkpoint_paths():
		for reserved in [ready_path, stop_path, report_path, status_path, admission_hold, outcome_hold, observe_request, observe_response]:
			if not reserved.is_empty() and checkpoint in [reserved.simplify_path(), (reserved + ".writing").simplify_path()]:
				return "checkpoint_path_conflicts_with_lifecycle"
	if not save_path.is_empty() and not fresh_destination():
		return "save_destination_or_pending_exists"
	if not resume_path.is_empty() and not FileAccess.file_exists(resume_path):
		return "resume_input_missing"
	return ""

func compatible_opening(capture: Dictionary) -> bool:
	if native_authority:
		var validated: Dictionary = session.world.validate_checkpoint(capture)
		var snapshot: Dictionary = session.world.projection()
		# The native validator binds the complete current profile, including its
		# finite reserve. Do not impose a second, obsolete sixteen-unit profile.
		return validated.get("accepted", false) and snapshot.recipe_input == 1 and snapshot.options.get("native", false) and Array(capture.get("actors", {}).keys()) == actor_roster
	if capture.initial_feed != 16 or capture.recipe_input != 1 or capture.options.get("opening") != true:
		return false
	if not legacy_fixture and (capture.schema != 2 or capture.options.get("physical") != true):
		return false
	if legacy_fixture and capture.schema != 1:
		return false
	for actor in capture.inventories:
		if not actor in ["P", "Q"]:
			return false
	for entry in capture.requests.values():
		if not entry.intent.client in ["P", "Q"]:
			return false
	return true

func checkpoint_failure(reason: String) -> void:
	# Refusing an alias must not use the aliased diagnostic buffer itself.
	var report_safe := true
	for checkpoint in checkpoint_paths():
		if checkpoint.simplify_path() in [report_path.simplify_path(), (report_path + ".writing").simplify_path()]:
			report_safe = false
	if report_safe:
		write_json(report_path, {"schema": 1, "status": "fail", "pid": OS.get_process_id(),
			"ready": false, "persistence": {"accepted": false, "reason": reason}})
	else:
		print("HOST_CHECKPOINT_REPORT_SUPPRESSED")
	if session != null:
		session.close()
	push_error("Host checkpoint refused: " + reason)
	quit(1)

func checkpoint_finish(capture: Dictionary, expired: bool, native_preflight: Dictionary) -> Dictionary:
	var preserved := resume_path.is_empty() or FileAccess.get_sha256(resume_path) == incoming_sha256
	var result := {"accepted": preserved and not expired, "resume": resume_result,
		"resume_input": resume_path, "input_preserved": preserved, "input_sha256": incoming_sha256,
		"save_file": save_path, "save": {"accepted": false, "reason": "not_requested"}}
	result["native_preflight"] = native_preflight
	if not save_path.is_empty():
		if expired:
			result.save = {"accepted": false, "reason": "lifetime_expired"}
		elif not preserved:
			result.save = {"accepted": false, "reason": "resume_input_changed"}
		elif not native_preflight.get("accepted", false):
			result.save = {"accepted": false, "reason": "native_save_refused:" + str(native_preflight.get("reason", "invalid_preflight"))}
		elif not fresh_destination():
			result.save = {"accepted": false, "reason": "save_destination_or_pending_exists"}
		else:
			var saved = checkpoint_store.write(session.world, save_path) if native_authority else checkpoint_store.write_snapshot(capture, save_path)
			result.save = saved if saved is Dictionary else {"accepted": false, "reason": "invalid_result"}
		result.accepted = result.save.get("accepted") is bool and result.save.accepted and preserved and not expired
		if result.accepted:
			result["saved_sha256"] = FileAccess.get_sha256(save_path)
	return result

func _status() -> void:
	var evidence: Dictionary = session.server_evidence()
	var queued: Array = []
	for item in evidence.pending_transport:
		if evidence.bindings.has(item.peer): queued.append(evidence.bindings[item.peer].actor)
	var held: Array = []
	for item in evidence.held_outcomes: held.append(item.actor)
	write_json(status_path, {"roles": evidence.roles, "context": session.context,
		"pending_roles": queued, "held_roles": held, "order": evidence.snapshot.order,
		"peer_count": evidence.connected_peers.size()})

func _poll() -> void:
	if session == null or started == 0:
		return
	if not observe_request.is_empty() and FileAccess.file_exists(observe_request):
		var request = JSON.parse_string(FileAccess.get_file_as_string(observe_request))
		if request is Dictionary and int(request.get("id", 0)) > observed:
			observed = int(request.id)
			var observation: Dictionary = session.server_evidence()
			observation["id"] = observed
			if not write_json(observe_response, observation):
				push_error("Cannot publish read-only server observation")
				quit(1)
	var expired := Time.get_ticks_msec() - started >= 1200000
	if expired or FileAccess.file_exists(stop_path):
		var native_preflight: Dictionary = session.prepare_checkpoint() if checkpoint_enabled() else {"accepted": true, "reason": "not_requested"}
		var evidence: Dictionary = session.server_evidence()
		var failed: bool = expired or not session.actor_error.is_empty()
		if checkpoint_enabled():
			var persisted := checkpoint_finish(evidence.checkpoint, expired, native_preflight)
			evidence["persistence"] = persisted
			failed = failed or not persisted.accepted
		evidence["status"] = "fail" if failed else "pass"
		evidence["schema"] = 1
		evidence["pid"] = OS.get_process_id()
		if not write_json(report_path, evidence):
			push_error("Cannot retain server authority diagnostic")
			quit(1)
		else:
			print("OPENING_SESSION_SERVER_FINISHED")
			session.close()
			quit(1 if failed else 0)
