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
var actor_world
var actor_error := ""
var control_trace: Array = []
var control_trace_dropped := 0
var _control_sequence := 0
var _control_direction := Vector2.ZERO
var _control_initialized := false
var _control_received: Dictionary = {}

func _ready() -> void:
	assert(str(get_path()) == "/root/OpeningShared/Session")
	# This adapter has only server/client RPCs. Do not relay peer lifecycle
	# messages to other clients, including peers closing in the same poll.
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _lost("connection_failed"))
	multiplayer.server_disconnected.connect(func(): _lost("server_disconnected"))
	multiplayer.peer_disconnected.connect(_peer_lost)

func serve_loopback(port: int, frozen_clock := false, physical_profile := false, actor_ids: Array = ["P", "Q"], native_authority := false) -> Error:
	if _transport != null or world != null:
		return ERR_ALREADY_IN_USE
	if port < 1 or port > 65535 or (native_authority and not physical_profile):
		return ERR_INVALID_PARAMETER
	var next_context := "opening-shared-" + Crypto.new().generate_random_bytes(16).hex_encode()
	var candidate
	if native_authority:
		var adapter = load("res://opening/native_model.gd")
		if adapter == null:
			return ERR_UNAVAILABLE
		candidate = adapter.new(next_context, actor_ids, true)
		if not candidate.boot_result.get("accepted", false):
			return ERR_UNAVAILABLE
	else:
		candidate = Model.new(16, next_context, 1, {"opening": true, "physical": true} if physical_profile else {"opening": true}, actor_ids)
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
	context = next_context
	world = candidate
	_tick_seconds = 0.0 if frozen_clock else 0.45
	last_serial = 0
	return OK

func start_physical_world() -> Error:
	# The host invokes this AFTER validating/restoring Model. Creating spawn
	# bodies before restore would silently retain the wrong native positions.
	if not _authoritative or world == null or not world.projection().options.get("physical", false):
		return ERR_UNAVAILABLE
	if actor_world != null:
		return ERR_ALREADY_IN_USE
	var adapter = load("res://opening/actor_world.gd")
	if adapter == null:
		return ERR_UNAVAILABLE
	actor_world = adapter.new()
	actor_world.name = "ActorWorld"
	actor_world.set_belt_step_seconds(_tick_seconds)
	var configured: Dictionary = actor_world.configure(world)
	if not configured.accepted:
		actor_error = "actor_configure_refused:" + str(configured.get("reason", "invalid_result"))
		actor_world.free()
		actor_world = null
		return ERR_INVALID_DATA
	actor_world.pose_published.connect(_actor_pose)
	actor_world.initialization_failed.connect(_actor_initialization_failed)
	add_child(actor_world)
	var topology: Dictionary = actor_world.sync_topology()
	if not topology.accepted:
		actor_error = "actor_topology_refused:" + str(topology.get("reason", "invalid_result"))
		return ERR_INVALID_DATA
	for actor_id in world.projection().actors:
		var created: Dictionary = actor_world.ensure_actor(actor_id)
		if not created.accepted:
			actor_error = actor_id + ":" + str(created.get("reason", "actor_creation_failed"))
			return ERR_CANT_CREATE
	return OK

func physical_ready() -> bool:
	if world == null or not world.projection().options.get("physical", false):
		return false
	var states: Dictionary = world.projection().actors
	if states.is_empty():
		return false
	for actor_id in states:
		if not states.get(actor_id, {}).get("ready", false):
			return false
	return actor_error.is_empty()

func _actor_pose(actor_id: String, sample: Dictionary) -> void:
	if not _authoritative or world == null:
		return
	if not sample.get("ready", false):
		world.invalidate_actor(actor_id)
		_broadcast(_frame())
		return
	var result: Dictionary = world.publish_actor(actor_id, sample.get("position", []), sample.get("native_epoch", 0))
	if not result.accepted:
		actor_error = result.reason
		world.invalidate_actor(actor_id)
	_broadcast(_frame())

func _actor_initialization_failed(actor_id: String, reason: String) -> void:
	actor_error = actor_id + ":" + reason
	world.invalidate_actor(actor_id)
	_broadcast(_frame())

func set_control(world_xz: Vector2, jump: bool) -> Dictionary:
	return _send_control(world_xz, jump, false)

func _send_control(world_xz: Vector2, jump: bool, release: bool) -> Dictionary:
	# A separate bounded input stream. Pending construction acknowledgements do
	# not freeze walking, and inputs never enter material command history.
	if _authoritative or not is_ready() or not _cache.get("options", {}).get("physical", false):
		return {"accepted": false, "reason": "physical_control_unavailable"}
	if not world_xz.is_finite():
		return {"accepted": false, "reason": "invalid_control"}
	var direction := world_xz.limit_length(1.0)
	if _control_initialized and direction == _control_direction and not jump and not release:
		return {"accepted": true, "reason": "unchanged_control"}
	_control_sequence += 1
	var payload := {"namespace": request_namespace, "sequence": _control_sequence,
		"direction": [direction.x, direction.y], "jump": jump, "release": release}
	var error: Error = rpc_id(1, "_wire_control", payload)
	if error != OK:
		return {"accepted": false, "reason": "control_send_failed"}
	_control_direction = direction
	_control_initialized = true
	return {"accepted": true, "reason": "control_sent"}

func release_control() -> Dictionary:
	# A release must clear a queued jump as well as horizontal input; merely
	# sending jump=false would leave ActorBody's one-shot edge latched.
	return _send_control(Vector2.ZERO, false, true)

func _record_control(entry: Dictionary) -> void:
	if control_trace.size() >= 4096:
		control_trace.pop_front()
		control_trace_dropped += 1
	control_trace.append(entry)

@rpc("any_peer", "call_remote", "reliable")
func _wire_control(payload: Dictionary) -> void:
	if not _authoritative:
		return
	# Capture sender identity in this RPC, never after a deferred callback.
	var sender := multiplayer.get_remote_sender_id()
	var refusal := ""
	if not _bindings.has(sender) or actor_world == null:
		refusal = "not_joined"
	elif payload.size() != 5 or not payload.get("namespace") is String or payload.namespace != _bindings[sender].namespace:
		refusal = "invalid_control_binding"
	elif not payload.get("sequence") is int or payload.sequence <= _control_received.get(sender, 0):
		refusal = "stale_control"
	elif not payload.get("jump") is bool or not payload.get("release") is bool or not payload.get("direction") is Array or payload.direction.size() != 2:
		refusal = "invalid_control"
	else:
		for value in payload.direction:
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 1.0:
				refusal = "invalid_control"
		if payload.release and (payload.jump or payload.direction != [0.0, 0.0]):
			refusal = "invalid_control_release"
	if not refusal.is_empty():
		_record_control({"peer": sender, "accepted": false, "reason": refusal})
		return
	var actor_id: String = _bindings[sender].actor
	var direction := Vector2(float(payload.direction[0]), float(payload.direction[1])).limit_length(1.0)
	_control_received[sender] = payload.sequence
	if payload.release:
		actor_world.release_control(actor_id)
	else:
		actor_world.set_control(actor_id, direction, payload.jump)
	_record_control({"peer": sender, "actor": actor_id, "namespace": _bindings[sender].namespace,
		"sequence": payload.sequence, "direction": [direction.x, direction.y], "jump": payload.jump, "release": payload.release,
		"accepted": true, "physics_frame": Engine.get_physics_frames()})

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
	if world.projection().options.get("physical", false) and not world.projection().actors.has(requested_role):
		_wire_refused.rpc_id(sender, "actor_not_provisioned")
		return
	if world.projection().options.get("physical", false) and not physical_ready():
		_wire_refused.rpc_id(sender, "actor_unready")
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
	if refusal.is_empty() and actor_world != null:
		# Fresh native observation only; ensure_actor cannot re-establish initial
		# readiness outside its natural registration boundary or force a flush.
		for actor_id in actor_world.bodies:
			actor_world.ensure_actor(actor_id)
	var before: Dictionary = world.projection()
	var admission_native: Dictionary = {}
	if actor_world != null:
		for actor_id in before.actors:
			admission_native[actor_id] = actor_world.diagnostics(actor_id, before.actors[actor_id].native_epoch)
	if refusal.is_empty():
		result = world.command_as(binding.actor, intent) if world.has_method("command_as") else world.command(intent)
	else:
		var state: Dictionary = world.projection()
		result = {"accepted": false, "reason": refusal, "entity": "", "context": context,
			"revision": state.revision, "order": state.order, "duplicate": false}
	if result.accepted and not result.duplicate and actor_world != null and intent.get("action") in ["place", "remove"]:
		actor_world.sync_topology()
	result["client"] = binding.actor
	result["request"] = request if request is String and request.length() <= 128 else ""
	var frame := _frame()
	var envelope := result.duplicate(true)
	envelope["snapshot"] = frame.snapshot
	envelope["serial"] = frame.serial
	var held: bool = _locally_held(outcome_hold_path, binding.actor)
	trace.append({"peer": sender, "received": item.received, "intent": intent.duplicate(true), "before": before,
		"tick_count": tick_count, "outcome_held": held, "outcome": envelope.duplicate(true), "admission_native": admission_native})
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
	_control_sequence = 0
	_control_direction = Vector2.ZERO
	_control_initialized = false
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
		if actor_world != null:
			actor_world.release_control(binding.actor)
			_record_control({"peer": peer, "actor": binding.actor, "accepted": true, "reason": "disconnect_release", "physics_frame": Engine.get_physics_frames()})
		_control_received.erase(peer)
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
	if actor_world != null:
		for actor_id in actor_world.bodies:
			actor_world.release_control(actor_id)
	_authoritative = false
	_lost("closed")

func prepare_checkpoint() -> Dictionary:
	if world == null or not _authoritative:
		return {"accepted": false, "reason": "not_authority"}
	if not world.projection().options.get("physical", false):
		return {"accepted": true, "reason": "legacy_fixture"}
	if actor_world == null or not actor_error.is_empty():
		return {"accepted": false, "reason": "actor_unready"}
	# The producer reads and publishes a CURRENT native observation for every
	# declared body before the caller captures Model. Last-frame poses can lag
	# a real move or a pending collider registration; neither can be silently saved.
	return actor_world.checkpoint_status()

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
		"control_trace": control_trace.duplicate(true), "control_trace_dropped": control_trace_dropped,
		"physical_ready": physical_ready(), "actor_error": actor_error,
		"native_actors": actor_world.diagnostics() if actor_world != null else {},
		"pending_transport": _incoming.duplicate(true), "held_outcomes": _held.duplicate(true)}
