extends Node
## Reversible loopback experiment adapter. The shared model alone owns rules.

signal joined(actor)
signal lost(actor)
signal queued(actor, request)
signal acknowledged(actor, label, data)
signal connected_ready
signal control(operation, payload)
signal observed(state)

const Model = preload("res://model.gd")
var world
var actor := ""
var context := ""
var state: Dictionary = {}
var outcomes: Dictionary = {}
var stale_views := 0
var peers: Dictionary = {}
var pending: Dictionary = {}
var trace: Array = []
var transport_events: Array = []
var port := 0

func listen(listen_port: int, opening := false) -> Error:
	port = listen_port
	context = "stationary-fixture-1"
	world = Model.new(16, context, 1, {"opening": true}) if opening else Model.new(16, context, 1)
	var transport := ENetMultiplayerPeer.new()
	transport.set_bind_ip("127.0.0.1")
	var error := transport.create_server(port, 2)
	if error == OK:
		multiplayer.multiplayer_peer = transport
		multiplayer.peer_disconnected.connect(_disconnected)
	return error

func connect_client(connect_port: int, name_value: String) -> Error:
	actor = name_value
	var transport := ENetMultiplayerPeer.new()
	var error := transport.create_client("127.0.0.1", connect_port)
	if error == OK:
		multiplayer.multiplayer_peer = transport
		multiplayer.connected_to_server.connect(_connected)
	return error

func _connected():
	register_client.rpc_id(1, actor)

@rpc("any_peer", "call_remote", "reliable")
func register_client(name_value: String):
	if world == null or not ["P", "Q"].has(name_value) or peers.has(name_value):
		return
	var sender := multiplayer.get_remote_sender_id()
	peers[name_value] = sender
	welcome.rpc_id(sender, name_value, world.projection())
	joined.emit(name_value)

@rpc("authority", "call_remote", "reliable")
func welcome(name_value: String, view: Dictionary):
	actor = name_value
	context = view.context
	state = view.duplicate(true)
	observed.emit(state)
	connected_ready.emit()

func send(intent: Dictionary):
	var request := intent.duplicate(true)
	request["context"] = context
	request["client"] = actor
	submit.rpc_id(1, request)

@rpc("any_peer", "call_remote", "reliable")
func submit(intent: Dictionary):
	if world == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	for name_value in peers:
		if peers[name_value] == sender:
			var actual := intent.duplicate(true)
			# The fixture identity follows its connection, not a claimed client field.
			actual["client"] = name_value
			pending[name_value + ":" + str(actual.get("request", ""))] = actual
			transport_events.append({"event": "received", "client": name_value,
				"request": actual.get("request", ""), "pending": pending.keys().duplicate()})
			queued.emit(name_value, str(actual.get("request", "")))
			return

func admit(name_value: String, request: String, withhold_outcome := false,
		excluded_views: Array = []) -> Dictionary:
	var key := name_value + ":" + request
	var intent: Dictionary = pending[key]
	transport_events.append({"event": "admitted", "client": name_value,
		"request": request, "pending_before": pending.keys().duplicate()})
	pending.erase(key)
	var result: Dictionary = world.command(intent)
	trace.append({"command": intent.duplicate(true), "result": result.duplicate(true)})
	if not withhold_outcome:
		var envelope: Dictionary = result.duplicate(true)
		envelope["client"] = name_value
		envelope["request"] = request
		decision.rpc_id(peers[name_value], envelope)
	publish(excluded_views)
	return result

func advance(ticks: int):
	world.advance(ticks)
	trace.append({"advance": ticks})

func publish(excluded: Array = []):
	for name_value in peers:
		if not excluded.has(name_value):
			view_state.rpc_id(peers[name_value], world.projection())

@rpc("authority", "call_remote", "reliable")
func decision(result: Dictionary):
	outcomes[str(result.get("request", ""))] = result.duplicate(true)

@rpc("authority", "call_remote", "reliable")
func view_state(view: Dictionary):
	if view.get("context") != context:
		return
	if (view.revision < state.get("revision", -1)
			or (view.revision == state.get("revision", -1)
				and view.order < state.get("order", -1))):
		stale_views += 1
		return
	state = view.duplicate(true)
	observed.emit(state)

func tell(name_value: String, operation: String, payload = null):
	directive.rpc_id(peers[name_value], operation, payload)

@rpc("authority", "call_remote", "reliable")
func directive(operation: String, payload):
	control.emit(operation, payload)

func report(label: String, extra: Dictionary):
	var data := {"state": state.duplicate(true), "outcomes": outcomes.duplicate(true),
		"stale_views": stale_views, "view": extra}
	client_report.rpc_id(1, label, data)

@rpc("any_peer", "call_remote", "reliable")
func client_report(label: String, data: Dictionary):
	var sender := multiplayer.get_remote_sender_id()
	for name_value in peers:
		if peers[name_value] == sender:
			acknowledged.emit(name_value, label, data)
			return

func close():
	multiplayer.multiplayer_peer.close()

func _disconnected(peer_id: int):
	for name_value in peers.keys():
		if peers[name_value] == peer_id:
			peers.erase(name_value)
			lost.emit(name_value)
