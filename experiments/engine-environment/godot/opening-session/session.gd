extends Node
## One loopback worksite authority, or a read-only client projection facade.
## Attach at /root/OpeningShared/Session on every peer. No fixture admin RPC.
signal welcomed(actor, request_namespace, snapshot)
signal changed(snapshot)
signal outcome(envelope)
signal disconnected(reason)
signal server_joined(actor)
signal server_lost(actor)
signal server_event

const Model = preload("res://model.gd")
const CONNECT_TIMEOUT_MSEC := 10000 # Bounded loopback fixture attempt, not game latency policy.
var world
var actor := ""
var context := ""
var request_namespace := ""
var request_sequence := 0
var last_serial := -1
var tick_count := 0
var stale_views := 0
var trace: Array = []
var lifecycle: Array = []
var _authoritative := false
var _ready_for_commands := false
var _requested_role := ""
var _transport: ENetMultiplayerPeer
var _cache: Dictionary = {}
var _sent: Dictionary = {}
var _bindings: Dictionary = {}
var _roles: Dictionary = {}
var _tick_seconds := 0.45
var _elapsed := 0.0
# Optional test-only SERVER-local barriers. No client-facing RPC controls them.
var admission_hold_path := ""
var outcome_hold_path := ""
var _incoming: Array = []
var _held: Array = []
var _received := 0
var _connect_started_msec := -1

func _ready() -> void:
	assert(str(get_path()) == "/root/OpeningShared/Session")
	# This adapter has only server/client RPCs. Do not relay peer lifecycle
	# messages to other clients, including peers closing in the same poll.
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _lost("connection_failed"))
	multiplayer.server_disconnected.connect(func(): _lost("server_disconnected"))
	multiplayer.peer_disconnected.connect(_peer_lost)

func serve_loopback(port: int, frozen_clock := false) -> Error:
	if _transport != null or world != null:
		return ERR_ALREADY_IN_USE
	if port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	var error := peer.create_server(port, 2)
	if error != OK:
		peer.close()
		return error
	_transport = peer
	multiplayer.multiplayer_peer = peer
	_authoritative = true
	_ready_for_commands = true
	context = "opening-shared-" + Crypto.new().generate_random_bytes(16).hex_encode()
	world = Model.new(16, context, 1, {"opening": true})
	_tick_seconds = 0.0 if frozen_clock else 0.45
	last_serial = 0
	return OK

func join_loopback(port: int, requested_role: String) -> Error:
	if _authoritative or port < 1 or port > 65535 or not requested_role in ["P", "Q"]:
		return ERR_INVALID_PARAMETER
	if _transport != null:
		return ERR_ALREADY_IN_USE
	_requested_role = requested_role
	_ready_for_commands = false
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client("127.0.0.1", port)
	if error != OK:
		peer.close()
		return error
	_transport = peer
	_connect_started_msec = Time.get_ticks_msec()
	multiplayer.multiplayer_peer = peer
	return OK

func is_ready() -> bool:
	return _ready_for_commands and _transport != null and _transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func projection() -> Dictionary:
	return world.projection() if _authoritative else _cache.duplicate(true)

func submit(action: Dictionary) -> Dictionary:
	if _authoritative or not is_ready():
		return {"accepted": false, "queued": false, "request": "", "reason": "not_ready"}
	request_sequence += 1
	var request := request_namespace + str(request_sequence)
	var intent := action.duplicate(true)
	intent.merge({"context": context, "client": actor, "request": request}, true)
	_sent[request] = intent.duplicate(true)
	return _send(intent)

func retry(request: String) -> Dictionary:
	if _authoritative or not is_ready():
		return {"accepted": false, "queued": false, "request": request, "reason": "not_ready"}
	if not _sent.has(request):
		return {"accepted": false, "queued": false, "request": request, "reason": "unknown_request"}
	var intent: Dictionary = _sent[request]
	if intent.context != context or not request.begins_with(request_namespace):
		return {"accepted": false, "queued": false, "request": request, "reason": "stale_request"}
	return _send(intent)

func _send(intent: Dictionary) -> Dictionary:
	var error: Error = rpc_id(1, "_wire_command", intent)
	if error != OK:
		return {"accepted": false, "queued": false, "request": intent.request, "reason": "send_failed"}
	return {"accepted": false, "queued": true, "request": intent.request, "reason": "awaiting_authority"}

func _connected() -> void:
	if not _authoritative:
		_wire_join.rpc_id(1, _requested_role)

func _process(delta: float) -> void:
	if not _authoritative:
		if (_transport != null and not _ready_for_commands and _connect_started_msec >= 0
			and Time.get_ticks_msec() - _connect_started_msec >= CONNECT_TIMEOUT_MSEC):
			_lost("connection_timeout")
		return
	if world == null:
		return
	_flush_local_barriers()
	if _tick_seconds <= 0.0:
		return
	_elapsed += delta
	while _elapsed >= _tick_seconds:
		_elapsed -= _tick_seconds
		world.advance()
		tick_count += 1
		_broadcast(_frame())

func _frame() -> Dictionary:
	last_serial += 1
	return {"context": context, "serial": last_serial, "snapshot": world.projection()}

func _broadcast(frame: Dictionary) -> void:
	for peer in _bindings:
		_wire_state.rpc_id(peer, frame)

@rpc("any_peer", "call_remote", "reliable")
func _wire_join(requested_role: String) -> void:
	if not _authoritative:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1:
		return
	if _bindings.has(sender):
		_wire_refused.rpc_id(sender, "already_joined")
		return
	if not requested_role in ["P", "Q"] or _roles.has(requested_role):
		lifecycle.append({"event": "join_refused", "peer": sender, "role": requested_role, "reason": "role_unavailable"})
		_wire_refused.rpc_id(sender, "role_unavailable")
		server_event.emit()
		return
	var namespace_value := "session-" + Crypto.new().generate_random_bytes(16).hex_encode() + "-"
	_bindings[sender] = {"actor": requested_role, "namespace": namespace_value}
	_roles[requested_role] = sender
	var frame := _frame()
	frame["actor"] = requested_role
	frame["namespace"] = namespace_value
	_wire_welcome.rpc_id(sender, frame)
	lifecycle.append({"event": "joined", "actor": requested_role, "peer": sender, "namespace": namespace_value})
	server_joined.emit(requested_role)

@rpc("any_peer", "call_remote", "reliable")
func _wire_command(intent: Dictionary) -> void:
	if not _authoritative:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _bindings.has(sender):
		lifecycle.append({"event": "command_refused", "peer": sender, "reason": "not_joined"})
		_wire_refused.rpc_id(sender, "not_joined")
		server_event.emit()
		return
	_received += 1
	var item := {"peer": sender, "intent": intent.duplicate(true), "received": _received,
		"actor": _bindings[sender].actor, "namespace": _bindings[sender].namespace}
	if _locally_held(admission_hold_path, _bindings[sender].actor):
		_incoming.append(item)
		server_event.emit()
	else:
		_admit(item)

func _admit(item: Dictionary) -> void:
	var sender: int = item.peer
	var intent: Dictionary = item.intent
	if not _bindings.has(sender) or _bindings[sender].namespace != item.namespace:
		return
	var binding: Dictionary = _bindings[sender]
	var request = intent.get("request", "")
	var refusal := ""
	if intent.get("client") != binding.actor:
		refusal = "wrong_actor"
	elif intent.get("context") != context:
		refusal = "wrong_context"
	elif not request is String or request.length() > 128 or not request.begins_with(binding.namespace):
		refusal = "stale_namespace"
	else:
		var suffix: String = request.trim_prefix(binding.namespace)
		if not suffix.is_valid_int() or int(suffix) < 1 or str(int(suffix)) != suffix:
			refusal = "invalid_request"
	var result: Dictionary
	var before: Dictionary = world.projection()
	if refusal.is_empty():
		result = world.command(intent)
	else:
		var state: Dictionary = world.projection()
		result = {"accepted": false, "reason": refusal, "entity": "", "context": context,
			"revision": state.revision, "order": state.order, "duplicate": false}
	result["client"] = binding.actor
	result["request"] = request if request is String and request.length() <= 128 else ""
	var frame := _frame()
	var envelope := result.duplicate(true)
	envelope["snapshot"] = frame.snapshot
	envelope["serial"] = frame.serial
	var held: bool = _locally_held(outcome_hold_path, binding.actor)
	trace.append({"peer": sender, "received": item.received, "intent": intent.duplicate(true), "before": before,
		"tick_count": tick_count, "outcome_held": held, "outcome": envelope.duplicate(true)})
	if held:
		_held.append({"peer": sender, "namespace": binding.namespace, "actor": binding.actor, "envelope": envelope})
	else:
		_wire_outcome.rpc_id(sender, envelope)
	_broadcast(frame)
	server_event.emit()

func _locally_held(path: String, role: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 64:
		push_error("Invalid owned local transport barrier")
		get_tree().quit(1)
		return true
	return role in file.get_as_text().strip_edges().split(",")

func _flush_local_barriers() -> void:
	var pending: Array = []
	var modified := false
	for item in _incoming:
		if not _bindings.has(item.peer) or _bindings[item.peer].namespace != item.namespace:
			modified = true
		elif _locally_held(admission_hold_path, _bindings[item.peer].actor):
			pending.append(item)
		else:
			_admit(item)
			modified = true
	_incoming = pending
	var held: Array = []
	for item in _held:
		if not _bindings.has(item.peer) or _bindings[item.peer].namespace != item.namespace:
			modified = true
		elif _locally_held(outcome_hold_path, item.actor):
			held.append(item)
		else:
			# This original acknowledgement can now be older than the latest
			# published state. Client watermarks must never apply it backwards.
			_wire_outcome.rpc_id(item.peer, item.envelope)
			modified = true
	_held = held
	if modified:
		server_event.emit()

@rpc("authority", "call_remote", "reliable")
func _wire_welcome(frame: Dictionary) -> void:
	if _authoritative or multiplayer.get_remote_sender_id() != 1:
		return
	if frame.get("actor") != _requested_role or not frame.get("namespace") is String or frame.namespace.is_empty():
		_lost("invalid_welcome")
		return
	if not _valid_frame(frame):
		_lost("invalid_welcome")
		return
	actor = frame.actor
	context = frame.context
	request_namespace = frame.namespace
	request_sequence = 0
	_sent.clear()
	_cache = frame.snapshot.duplicate(true)
	last_serial = frame.serial
	_ready_for_commands = true
	_connect_started_msec = -1
	welcomed.emit(actor, request_namespace, _cache.duplicate(true))
	changed.emit(_cache.duplicate(true))

func _valid_frame(frame: Dictionary) -> bool:
	return (frame.get("context") is String and not frame.context.is_empty()
		and frame.get("serial") is int and frame.serial >= 0 and frame.get("snapshot") is Dictionary
		and frame.snapshot.get("context") == frame.context and frame.snapshot.get("revision") is int
		and frame.snapshot.get("order") is int)

func _apply_frame(frame: Dictionary) -> void:
	if not _ready_for_commands or not _valid_frame(frame) or frame.context != context:
		return
	var view: Dictionary = frame.snapshot
	if frame.serial <= last_serial or view.revision < _cache.get("revision", -1) or view.order < _cache.get("order", -1):
		stale_views += 1
		return
	last_serial = frame.serial
	_cache = view.duplicate(true)
	changed.emit(_cache.duplicate(true))

@rpc("authority", "call_remote", "reliable")
func _wire_state(frame: Dictionary) -> void:
	if not _authoritative and multiplayer.get_remote_sender_id() == 1:
		_apply_frame(frame)

@rpc("authority", "call_remote", "reliable")
func _wire_outcome(envelope: Dictionary) -> void:
	if _authoritative or not is_ready() or multiplayer.get_remote_sender_id() != 1 or envelope.get("context") != context:
		return
	_apply_frame(envelope)
	outcome.emit(envelope.duplicate(true))

@rpc("authority", "call_remote", "reliable")
func _wire_refused(reason: String) -> void:
	if not _authoritative and multiplayer.get_remote_sender_id() == 1:
		_lost(reason)

func _peer_lost(peer: int) -> void:
	if _authoritative and _bindings.has(peer):
		var binding: Dictionary = _bindings[peer]
		_roles.erase(binding.actor)
		_bindings.erase(peer)
		lifecycle.append({"event": "lost", "actor": binding.actor, "peer": peer})
		_incoming = _incoming.filter(func(item: Dictionary): return item.peer != peer)
		_held = _held.filter(func(item: Dictionary): return item.peer != peer)
		server_lost.emit(binding.actor)
		server_event.emit()
	elif _authoritative:
		# An unadmitted connection can also close after an explicit refusal.
		server_event.emit()

func _lost(reason: String) -> void:
	var notify := _transport != null or _ready_for_commands
	_ready_for_commands = false
	_connect_started_msec = -1
	var peer := _transport
	_transport = null
	if peer != null:
		peer.close()
	if notify:
		disconnected.emit(reason)

func close() -> void:
	_authoritative = false
	_lost("closed")

func server_evidence() -> Dictionary:
	if world == null:
		return {"authoritative": false, "live_model": false}
	return {"authoritative": _authoritative, "model_instance": world.get_instance_id(),
		"server_relay": (multiplayer as SceneMultiplayer).server_relay,
		"context": context, "clock_frozen": _tick_seconds == 0.0, "tick_count": tick_count,
		"connected_peers": Array(multiplayer.get_peers()),
		"serial": last_serial, "roles": _roles.duplicate(), "bindings": _bindings.duplicate(true),
		"snapshot": world.projection(), "checkpoint": world.checkpoint(),
		"trace": trace.duplicate(true), "lifecycle": lifecycle.duplicate(true),
		"pending_transport": _incoming.duplicate(true), "held_outcomes": _held.duplicate(true)}
