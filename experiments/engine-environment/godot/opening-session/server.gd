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

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--session-port="): port = int(argument.trim_prefix("--session-port="))
		elif argument == "--frozen-clock": frozen = true
		elif argument.begins_with("--ready-file="): ready_path = argument.trim_prefix("--ready-file=")
		elif argument.begins_with("--stop-file="): stop_path = argument.trim_prefix("--stop-file=")
		elif argument.begins_with("--report-file="): report_path = argument.trim_prefix("--report-file=")
		elif argument.begins_with("--status-file="): status_path = argument.trim_prefix("--status-file=")
		elif argument.begins_with("--admission-hold-file="): admission_hold = argument.trim_prefix("--admission-hold-file=")
		elif argument.begins_with("--outcome-hold-file="): outcome_hold = argument.trim_prefix("--outcome-hold-file=")
		elif argument.begins_with("--observe-request="): observe_request = argument.trim_prefix("--observe-request=")
		elif argument.begins_with("--observe-response="): observe_response = argument.trim_prefix("--observe-response=")
	call_deferred("_boot")
	process_frame.connect(_poll)

func write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path + ".writing", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
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
	var container := Node.new()
	container.name = "OpeningShared"
	session = Session.new()
	session.name = "Session"
	session.admission_hold_path = admission_hold
	session.outcome_hold_path = outcome_hold
	container.add_child(session)
	root.add_child(container)
	var error: Error = session.serve_loopback(port, frozen)
	if error != OK:
		push_error("Loopback bind refused: " + str(error))
		quit(1)
		return
	started = Time.get_ticks_msec()
	session.server_joined.connect(func(_actor): _status())
	session.server_lost.connect(func(_actor): _status())
	session.server_event.connect(_status)
	if not write_json(ready_path, {"schema": 1, "port": port, "pid": OS.get_process_id(), "context": session.context, "clock_frozen": frozen}):
		push_error("Cannot write server readiness diagnostic")
		quit(1)
		return
	_status()
	print("OPENING_SESSION_SERVER_READY")

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
		var evidence: Dictionary = session.server_evidence()
		evidence["status"] = "fail" if expired else "pass"
		evidence["schema"] = 1
		evidence["pid"] = OS.get_process_id()
		if not write_json(report_path, evidence):
			push_error("Cannot retain server authority diagnostic")
			quit(1)
		else:
			print("OPENING_SESSION_SERVER_FINISHED")
			session.close()
			quit(1 if expired else 0)
