extends "res://opening/opening.gd"
## The existing view over a read-only session projection, never a live Model.
## Session owns identity, transport, retry dispositions and snapshot freshness.

var session
var session_port := 0
var session_role := ""
var connect_on_ready := true
var connecting := false
var pending_actions: Dictionary = {}
var uncertain_actions: Array = []
var last_outcome: Dictionary = {}
var last_submission: Dictionary = {}
var last_local_result: Dictionary = {}
var connection_label: Label
var reconnect_button: Button
var disconnect_button: Button

func _ready() -> void:
	# Do not call the offline _ready: that path legitimately creates its Model
	# and accepts a local save slot. This scene does neither.
	auto_advance = false
	client = ""
	request_namespace = ""
	request_sequence = 0
	session = get_node("Session")
	model = session # projection() only; there is no client advance/restore.
	var offline_argument := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--session-port="):
			var value := argument.trim_prefix("--session-port=")
			session_port = value.to_int() if value.is_valid_int() else 0
		elif argument.begins_with("--session-role="):
			session_role = argument.trim_prefix("--session-role=")
		elif argument.begins_with("--save-slot") or argument.begins_with("--resume"):
			offline_argument = true
	_build_world()
	_build_interface()
	for child in tool_buttons.collector.get_parent().get_children():
		if child is Label and child.text == "BUILD FROM CARRIED PARTS":
			child.text = "BUILD FROM SHARED KIT"
	var column := power_button.get_parent()
	connection_label = _label(column, "NOT CONNECTED", 14)
	column.move_child(connection_label, 1)
	reconnect_button = _button(column, "Reconnect to session", _reconnect)
	disconnect_button = _button(column, "Disconnect", _disconnect)
	session.welcomed.connect(_welcomed)
	session.changed.connect(_changed)
	session.outcome.connect(_outcome_received)
	session.disconnected.connect(_disconnected)
	_refresh_ui()
	_message("Connect to the shared worksite to begin.")
	if offline_argument:
		_message("Local save and resume arguments are unavailable in a shared session.", true)
		push_error("Shared opening refuses offline save/resume arguments")
		get_tree().quit(1)
		return
	if connect_on_ready:
		_reconnect()

func _usable_snapshot() -> bool:
	return state.has("entities") and state.has("stock") and state.has("inventories") and state.has("parts")

func _can_mutate() -> bool:
	return session != null and session.is_ready() and _usable_snapshot() and not explanation_open and pending_actions.is_empty()

func _reconnect() -> void:
	if session.is_ready() or connecting:
		return
	if session_port < 1 or session_port > 65535 or not session_role in ["P", "Q"]:
		_message("Session unavailable. Supply a loopback port and participant P or Q.", true)
		return
	connecting = true
	var error: Error = session.join_loopback(session_port, session_role)
	if error != OK:
		connecting = false
		_message("Could not connect to the shared worksite.", true)
	else:
		connecting = true
		_message("Connecting to the shared worksite…")
	_refresh_ui()

func _disconnect() -> void:
	session.close()
	_disconnected("Closed locally")

func _welcomed(actor: String, namespace_value: String, _snapshot: Dictionary) -> void:
	connecting = false
	client = actor
	request_namespace = namespace_value
	request_sequence = session.request_sequence
	selected = ""
	pending_link = ""
	pending_actions.clear()
	last_outcome = {}
	last_submission = {}
	last_local_result = {}
	goal_confirmed = false
	geometry_key = ""
	visual_revision = -1
	elapsed = 0.0
	_refresh()
	_message("Connected as %s. The shared worksite is ready." % client)
	if _has_unknown_actions():
		_message("Reconnected as %s. Earlier action is uncertain; inspect the current worksite." % client)

func _changed(_snapshot: Dictionary) -> void:
	_refresh()

func _has_unknown_actions() -> bool:
	for entry in uncertain_actions:
		if entry.disposition == "unknown":
			return true
	return false

func _disconnected(reason: String) -> void:
	connecting = false
	for request in pending_actions:
		uncertain_actions.append({"request": request, "action": pending_actions[request].action.duplicate(true),
			"context": state.get("context", ""),
			"disposition": "unknown" if pending_actions[request].outcome.is_empty() else "server_decided",
			"known_result": pending_actions[request].outcome.duplicate(true)})
	while uncertain_actions.size() > 32:
		uncertain_actions.pop_front()
	pending_actions.clear()
	selected = ""
	pending_link = ""
	_message("Disconnected. Last confirmed worksite is read-only. %s" % reason, true)
	if _has_unknown_actions():
		_message("Disconnected. The last action's outcome is unknown; it will not retry automatically.", true)
	_refresh_ui()
	_update_cursor()

func issue(action: Dictionary) -> Dictionary:
	if explanation_open:
		last_local_result = {"accepted": false, "queued": false, "reason": "explanation_open"}
	elif not session.is_ready() or not _usable_snapshot():
		last_local_result = {"accepted": false, "queued": false, "reason": "session_not_ready"}
		_message("Connect to the shared worksite before changing it.", true)
	elif not pending_actions.is_empty():
		last_local_result = {"accepted": false, "queued": false, "reason": "request_pending"}
		_message("Waiting for the server's decision on your current action.")
	else:
		var receipt: Dictionary = session.submit(action)
		last_submission = receipt.duplicate(true)
		request_sequence = session.request_sequence
		request_namespace = session.request_namespace
		if receipt.get("queued", false):
			assert(not receipt.accepted)
			pending_actions[receipt.request] = {"action": action.duplicate(true), "outcome": {}}
			_message("Action sent. Waiting for the server's decision…")
		else:
			_message("Action could not be sent: %s." % str(receipt.get("reason", "session unavailable")), true)
		_refresh_ui()
		return receipt
	_refresh_ui()
	return last_local_result.duplicate(true)

func _outcome_received(envelope: Dictionary) -> void:
	var request: String = envelope.get("request", "")
	if not pending_actions.has(request) or envelope.get("client") != client or envelope.get("context") != state.get("context"):
		return
	last_outcome = envelope.duplicate(true)
	pending_actions[request].outcome = envelope.duplicate(true)
	_refresh()

func _settle_pending() -> void:
	if not session.is_ready() or not _usable_snapshot():
		return
	for request in pending_actions.keys():
		var item: Dictionary = pending_actions[request]
		var result: Dictionary = item.outcome
		if result.is_empty():
			continue
		if state.context != result.context or state.revision < result.revision or state.order < result.order:
			_message("Server decision received. Waiting for the current worksite…")
			continue
		pending_actions.erase(request)
		if result.accepted:
			if item.action.action == "place" and state.entities.has(result.entity):
				selected = result.entity
			elif item.action.action == "remove" and selected == result.entity:
				selected = ""
			_message({"place": "Placed.", "connect": "Material path connected.", "connect_drive": "Drive shaft connected.",
				"retrieve": "Plate collected into your inventory.", "set_power": "Drive updated.",
				"remove": "Part returned to the shared kit."}.get(item.action.action, "Action accepted."))
		else:
			_message("Not applied: " + {"occupied": "that square is occupied.", "no_part": "that part is already placed.",
				"unavailable_output": "there is no finished plate to collect.", "not_stopped": "stop the drive before editing.",
				"powered": "stop the drive before editing.", "held_stock": "material remains in that machine.",
				"ports_not_adjacent": "choose neighboring ports in the arrow's direction.",
				"no_shaft": "all shared shafts are in use."}.get(result.reason, str(result.reason)), true)
	_refresh_ui()

func _refresh() -> void:
	var snapshot: Dictionary = session.projection()
	if snapshot.is_empty():
		_refresh_ui()
		return
	super._refresh()
	_settle_pending()

func _process(delta: float) -> void:
	# Render/camera motion is local. The server alone advances the worksite.
	auto_advance = false
	super._process(delta)

func _select_tool(tool: String) -> void:
	if explanation_open:
		return
	if not session.is_ready():
		_message("Connect before selecting a construction tool.", true)
		return
	if not pending_actions.is_empty() and tool != "inspect":
		_message("Waiting for the server's decision.")
		return
	super._select_tool(tool)

func _world_click(cell: Vector2i, entity_id: String = "") -> void:
	if not session.is_ready() or not _usable_snapshot():
		_message("Connect to the shared worksite before interacting.", true)
		return
	if not pending_actions.is_empty() and mode != "inspect":
		_message("Waiting for the server's decision.")
		return
	super._world_click(cell, entity_id)

func _retrieve() -> void:
	if not _can_mutate():
		issue({"action": "retrieve"}) # local guard refuses before any transport send.
		return
	super._retrieve()

func _toggle_power() -> void:
	if not _can_mutate():
		issue({"action": "set_power"})
		return
	super._toggle_power()

func _remove_selected() -> void:
	if not _can_mutate():
		issue({"action": "remove"})
		return
	super._remove_selected()

func _confirm_goal() -> void:
	if _can_mutate():
		super._confirm_goal()

func configure_save_slot(_path: String) -> void:
	save_slot = ""
	save_slot_ready = false
	save_slot_owned = false

func _save_worksite() -> Dictionary:
	last_save_result = {"accepted": false, "reason": "network_save_unavailable"}
	_message("Saving is unavailable in this shared-session prototype.", true)
	return last_save_result.duplicate(true)

func _load_worksite(_path: String = "") -> Dictionary:
	last_load_result = {"accepted": false, "reason": "network_load_unavailable"}
	_message("Loading is unavailable in this shared-session prototype.", true)
	return last_load_result.duplicate(true)

func _refresh_ui() -> void:
	if stock_label == null:
		return
	if _usable_snapshot():
		super._refresh_ui()
	else:
		goal_label.text = "FIRST SHIFT\nWaiting for the shared worksite"
		stock_label.text = "No server state received"
		power_label.text = "NOT CONNECTED"
		inspector.text = "Connect before interacting."
		selection_ring.visible = false
	var enabled := _can_mutate()
	for button in [confirm_button, retrieve_button, remove_button, power_button]:
		button.disabled = button.disabled or not enabled
	for tool in tool_buttons:
		if _usable_snapshot() and NAMES.has(tool):
			tool_buttons[tool].text = "%s    ·    %d shared" % [NAMES[tool], int(state.parts.get(tool, 0))]
		tool_buttons[tool].disabled = tool_buttons[tool].disabled or not enabled
	save_button.disabled = true
	load_button.disabled = true
	for button in [save_button, load_button]:
		button.tooltip_text = "Shared-session saving and loading are unavailable."
	if connection_label != null:
		connection_label.text = "CONNECTED AS %s" % client if session.is_ready() else "CONNECTING…" if connecting else "DISCONNECTED / READ-ONLY"
		if not pending_actions.is_empty():
			connection_label.text += "\nWAITING FOR SERVER DECISION"
		reconnect_button.disabled = connecting or session.is_ready() or explanation_open
		disconnect_button.disabled = not session.is_ready() or explanation_open

func _update_cursor() -> void:
	super._update_cursor()
	hover.visible = hover.visible and _can_mutate()
