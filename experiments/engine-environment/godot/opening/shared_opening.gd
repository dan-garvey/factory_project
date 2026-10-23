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
		if argument == "--legacy-fixture":
			legacy_fixture = true
		elif argument.begins_with("--session-port="):
			var value := argument.trim_prefix("--session-port=")
			session_port = value.to_int() if value.is_valid_int() else 0
		elif argument.begins_with("--session-role="):
			session_role = argument.trim_prefix("--session-role=")
		elif argument.begins_with("--save-slot") or argument.begins_with("--resume"):
			offline_argument = true
	_build_world()
	_install_shared_ore_picker()
	_build_interface()
	var column := power_label.get_parent()
	connection_label = _label(column, "NOT CONNECTED", 14)
	column.move_child(connection_label, 1)
	reconnect_button = _button(column, "Reconnect  [Ctrl+J]", _reconnect)
	disconnect_button = _button(column, "Disconnect  [Ctrl+Shift+J]", _disconnect)
	session.welcomed.connect(_welcomed)
	session.changed.connect(_changed)
	session.outcome.connect(_outcome_received)
	session.disconnected.connect(_disconnected)
	if not legacy_fixture:
		_start_character_presenter()
	_refresh_ui()
	_message("Connect to the shared worksite to begin.")
	if offline_argument:
		_message("Local save and resume arguments are unavailable in a shared session.", true)
		push_error("Shared opening refuses offline save/resume arguments")
		get_tree().quit(1)
		return
	if connect_on_ready:
		_reconnect()

func _install_shared_ore_picker() -> void:
	if legacy_fixture or ProductionEnvironment.Surface == null:
		return
	var spec: Dictionary = ProductionEnvironment.Surface.source_outcrop()
	var body := StaticBody3D.new()
	body.name = "SharedOreSourcePicker"
	body.collision_layer = Geometry.PICK_LAYER
	body.collision_mask = 0
	body.position = spec.center
	body.basis = spec.basis
	var collider := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = spec.points
	shape.margin = 0.0
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode == KEY_J:
		var button := disconnect_button if event.shift_pressed else reconnect_button
		if not explanation_open and _activate_button(button):
			get_viewport().set_input_as_handled()
		return
	super._input(event)

func _usable_snapshot() -> bool:
	return state.has("entities") and state.has("stock") and state.has("inventories") and state.has("parts") and (legacy_fixture or (state.get("options", {}).get("physical", false) and state.has("actors")))

func _can_control_character() -> bool:
	# Build acknowledgements do not stop movement. Only the current connected
	# binding supplies input; the server alone owns the body's pose.
	return session != null and session.is_ready() and _usable_snapshot() and super._can_control_character()

func _can_choose_tool() -> bool:
	return _can_mutate() and super._can_choose_tool()

func _send_character_input(direction: Vector2, jump: bool) -> void:
	if session != null and session.is_ready():
		session.set_control(direction, jump)

func _release_character_input() -> void:
	if session != null:
		session.release_control()

func _can_mutate() -> bool:
	return session != null and session.is_ready() and _usable_snapshot() and not explanation_open and pending_actions.is_empty()

func _parts_are_shared() -> bool:
	return not state.get("options", {}).get("native", false)

func _can_present_confirmed_motion() -> bool:
	return session != null and session.is_ready() and _usable_snapshot() and super._can_present_confirmed_motion()

func _placement_ready() -> bool:
	return _can_mutate() and super._placement_ready()

func _reconnect() -> void:
	if session.is_ready() or connecting:
		return
	if session_port < 1 or session_port > 65535 or not session_role in ["P", "Q"]:
		_message("Session unavailable. Supply a loopback port and participant P or Q.", true)
		return
	# Prepare reusable presentation data before receiving live snapshots. Cold
	# waveform synthesis must not block the first running drive's network poll.
	if not legacy_fixture:
		for kind: String in ["collector", "belt", "processor", "wheel"]:
			MechanicalAmbience.make_loop(kind)
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
	_release_character_controls()
	session.close()
	_disconnected("Closed locally")

func _welcomed(actor: String, namespace_value: String, _snapshot: Dictionary) -> void:
	_release_character_controls()
	if _snapshot.get("options", {}).get("physical", false) == legacy_fixture or (not legacy_fixture and not _snapshot.get("actors", {}).has(actor)):
		push_error("Shared opening profile must match its declared authority and actor; no unrestricted fallback")
		session.close()
		get_tree().quit(1)
		return
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
	_message("Connected as %s." % client)
	if _has_unknown_actions():
		_message("Reconnected as %s. Earlier action is uncertain; inspect the current worksite." % client)

func _changed(confirmed: Dictionary) -> void:
	var removed_first: bool = (session.is_ready() and not pending_link.is_empty()
		and not _contains_target(confirmed, pending_link))
	var show_removed: bool = removed_first and pending_actions.is_empty()
	if removed_first:
		if selected == pending_link:
			selected = ""
		pending_link = ""
	_refresh()
	if show_removed:
		_message("The first machine was removed. Choose the first connection point again.", true)

func _has_unknown_actions() -> bool:
	for entry in uncertain_actions:
		if entry.disposition == "unknown":
			return true
	return false

func _disconnected(reason: String) -> void:
	_release_character_controls()
	if transmission_controls != null:
		transmission_controls.clear_belt_selection()
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
	var cause: String = {"closed": "Disconnected locally.", "Closed locally": "Disconnected locally.",
		"server_disconnected": "The server closed the connection.",
		"connection_failed": "Could not connect to the worksite.",
		"connection_timeout": "The worksite did not respond in time.",
		"role_unavailable": "That participant is already connected.",
		"already_joined": "This connection has already joined.",
		"not_joined": "The server has not admitted this connection.",
		"invalid_welcome": "The server did not send a usable worksite."}.get(reason, "Connection ended.")
	if _has_unknown_actions():
		cause += " An earlier action's outcome is unknown; it will not retry automatically."
	_message(cause + " Last confirmed worksite is read-only.", true)
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
			var feedback: Dictionary = item.action.duplicate(true)
			feedback.merge({"context": result.context, "client": client, "request": request}, true)
			_construction_feedback(feedback, result)
			if item.action.action in ["place", "place_gear", "place_shaft", "place_foundation", "place_foundations"] and _contains_target(state, result.entity):
				selected = result.entity
			elif item.action.action in ["remove", "remove_belt_span"] and selected == result.entity:
				selected = ""
			_message(_harvest_result_text(result) if item.action.action == "harvest_source" else {"place": "Placed.", "place_foundation": "Foundation placed on the world grid.", "place_foundations": "Foundation area placed on the world grid.", "connect": "Material path connected.", "connect_drive": "Drive shaft connected.",
				"craft_component": "Component crafted from carried material.", "field_craft": "Wooden component shaped with your multitool.",
				"craft_part": "Transmission kit made from carried timber and softmetal.",
				"place_component": "Component placed on the shared grid.", "reclaim_component": "Component returned to your carried cargo.",
				"turn_hand_crank": "Collector cut one ore blank into its receiver tray.",
				"retrieve": "Plate collected into your inventory.", "pickup_material": "Loose material collected into your inventory.", "load_belt_slot": "Material placed on the belt.",
				"remove": "Part returned."}.get(item.action.action, "Action accepted."))
		else:
			var refusal: String = _material_refusal_message(result, "Not applied: " + {"occupied": "that square is occupied.", "no_part": "that part is already placed.",
				"not_at_seam": "place the collector over the ore deposit beside the rock.",
				"not_at_stream": "place the waterwheel beside the stream bank.",
				"unavailable_output": "there is no finished plate to collect.", "not_stopped": "stop the drive before editing.",
				"out_of_reach": "move closer to the target before building or interacting.",
				"actor_unready": "your character is not ready yet; wait a moment.",
				"actor_occupied": "a character is in that square; move clear before placing the machine.",
				"powered": "stop the drive before editing.", "held_stock": "material remains in that machine.",
				"ports_not_adjacent": "choose neighboring ports in the arrow's direction.",
				"no_shaft": "all shared shafts are in use."}.get(result.reason, str(result.reason)))
			if item.action.action == "craft_component":
				refusal = {"unavailable_input": "Gather the timber or softmetal shown for this component.",
					"inventory_full": "Your component bag is full. Place a carried part to make room.",
					"out_of_reach": "Move beside the selected workshop to craft this component."}.get(result.get("reason", ""), refusal)
			elif item.action.action == "field_craft":
				refusal = {"unavailable_input": "Gather the timber shown for this component.",
					"inventory_full": "Your component bag is full. Place a carried part to make room.",
					"unavailable_recipe": "Metal components need a workshop."}.get(result.get("reason", ""), refusal)
			elif item.action.action == "craft_part":
				refusal = {"unavailable_input": "Gather the timber or softmetal shown for this transmission kit.",
					"out_of_reach": "Move beside the selected workshop to make a transmission kit.",
					"quantity_overflow": "Too many of this kit are already carried."}.get(result.get("reason", ""), refusal)
			elif item.action.action == "turn_hand_crank":
				refusal = {"not_crank_holder": "Take the pod crank before turning this collector.",
					"incomplete_assembly": "Fit the collector's missing component before cutting ore.",
					"receiver_full": "Pick up the ore blank in the collector receiver before cutting again.",
					"source_depleted": "This ore deposit is depleted.",
					"output_full": "Clear a loose material drop before cutting more ore.",
					"out_of_reach": "Move beside the collector's fitted shaft to turn it."}.get(result.get("reason", ""), refusal)
			elif item.action.action == "reclaim_component" and result.get("reason", "") == "inventory_full":
				refusal = "Your component bag is full. Place another carried part before reclaiming."
			_message(refusal, true)
		if item.action.action == "select_belt_shaft" and transmission_controls != null:
			transmission_controls.settle_belt_selection(request, result.accepted)
		elif item.action.action == "place_selected_belt_span" and transmission_controls != null:
			transmission_controls.settle_belt_placement(request, result.accepted, result.get("reason", ""))
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
	if not session.is_ready() and tool != "inspect":
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

func _load_worksite(_path: String = "", _startup_resume: bool = false) -> Dictionary:
	last_load_result = {"accepted": false, "reason": "network_load_unavailable"}
	_message("Loading is unavailable in this shared-session prototype.", true)
	return last_load_result.duplicate(true)

func _inspection_hint() -> String:
	if not session.is_ready():
		return "Last confirmed state only.\nReconnect before interacting."
	if not pending_actions.is_empty():
		return "Action awaiting the server.\nWait for its decision."
	return super._inspection_hint()

func _refresh_ui() -> void:
	if stock_label == null:
		return
	if _usable_snapshot():
		super._refresh_ui()
		if not session.is_ready():
			inspector.text = "Last confirmed state only.\nReconnect before interacting."
			if not legacy_fixture:
				goal_label.text = "Reconnect to continue."
		elif not pending_actions.is_empty() and not state.entities.has(selected):
			inspector.text = "Action awaiting the server.\nWait for its decision."
		if not legacy_fixture and session.is_ready() and not pending_actions.is_empty():
			goal_label.text = "Waiting for the server decision."
	else:
		goal_label.text = "FIRST SHIFT\nWaiting for the shared worksite"
		stock_label.text = "No server state received"
		power_label.text = "NOT CONNECTED"
		inspector.text = "Connect before interacting."
		selection_ring.visible = false
		_refresh_guided_tools(false)
	var enabled := _can_mutate()
	for button in [confirm_button, retrieve_button, remove_button]:
		button.disabled = button.disabled or not enabled
	for tool in tool_buttons:
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
	if recovery_actions != null:
		recovery_actions.refresh()
	if loose_material_controls != null:
		loose_material_controls.refresh()
	_refresh_transmission()
	# Shared pending/reconnect notices replace the base goal after its refresh.
	# Keep the personal log's current cue on that final confirmed view.
	_refresh_manager_log()

func _update_cursor() -> void:
	super._update_cursor()
	hover.visible = hover.visible and _can_mutate()
