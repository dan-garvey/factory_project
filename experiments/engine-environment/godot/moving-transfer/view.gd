extends Node3D
## Read-only native pose/material display; inputs call the one authority.
const Authority = preload("res://moving-transfer/authority.gd")
var authority
var repeat_source := false
var _requests := {"P": 0, "Q": 0}
var _last_p: Dictionary = {}
var _deck: MeshInstance3D
var _dock: MeshInstance3D
var _outlet: MeshInstance3D
var _inlet: MeshInstance3D
var _tokens := {"carrier": [], "receiver": []}
var _status: Label
var _message: Label
var _repeat: CheckButton
var _sensor: CheckButton
var _presented: Dictionary = {}
var _deadline := 0

func _ready() -> void:
	var seconds := 900
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--transfer-seconds="): seconds = clampi(int(argument.trim_prefix("--transfer-seconds=")), 1, 900)
	_deadline = Time.get_ticks_msec() + seconds * 1000
	_build_world()
	_build_ui()
	authority = Authority.new()
	authority.name = "TransferAuthority"
	add_child(authority)
	authority.transfer_completed.connect(_on_transfer)

func _on_transfer(event: Dictionary) -> void:
	_message.text = "%s: %s%s" % [event.intent.get("actor", "?"), event.disposition.reason, " (original receipt; retry moved nothing)" if event.duplicate else ""]

func request_unit(actor: String) -> void:
	_requests[actor] += 1
	var intent := {"action": "transfer", "actor": actor, "request": actor + "-" + str(_requests[actor]), "kind": "A", "amount": 1}
	if actor == "P": _last_p = intent.duplicate(true)
	var response: Dictionary = authority.command(intent)
	if response.status == "queued": _message.text = actor + ": queued for the next native cut; no stock moved yet"

func compete() -> void:
	request_unit("P")
	request_unit("Q") # Two fresh requests in this same input/native cut.

func retry_p() -> void:
	if not _last_p.is_empty(): authority.command(_last_p)

func toggle_source() -> void:
	var result: Dictionary = authority.command({"action": "run", "active": not authority.running})
	_message.text = result.reason

func step_once() -> void:
	var result: Dictionary = authority.command({"action": "step"})
	_message.text = result.reason

func set_repeat(active: bool) -> void:
	repeat_source = active
	_repeat.set_pressed_no_signal(active)

func set_sensor(active: bool) -> void:
	authority.command({"action": "automatic", "active": active})
	_sensor.set_pressed_no_signal(active)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F: toggle_source()
		KEY_N: step_once()
		KEY_R: set_repeat(not repeat_source)
		KEY_T: set_sensor(not authority.projection().automatic)
		KEY_P: request_unit("P")
		KEY_Q: request_unit("Q")
		KEY_C: compete()
		KEY_D: retry_p()
		_: return
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _deadline > 0 and Time.get_ticks_msec() >= _deadline:
		get_tree().quit(0)
		return
	if authority == null: return
	if repeat_source and authority.running and not authority.pending: authority.command({"action": "step"})
	_refresh(authority.projection())

func _transform(value: Dictionary) -> Transform3D:
	var axes: Array = value.basis
	return Transform3D(Basis(Vector3(axes[0][0], axes[0][1], axes[0][2]), Vector3(axes[1][0], axes[1][1], axes[1][2]),
		Vector3(axes[2][0], axes[2][1], axes[2][2])), Vector3(value.position[0], value.position[1], value.position[2]))

func _refresh(state: Dictionary) -> void:
	var observation: Dictionary = state.observation
	if observation.is_empty(): return
	var native: Dictionary = observation.native
	_deck.global_transform = _transform(native.carrier)
	_dock.global_transform = _transform(native.receiver)
	_outlet.position = Vector3(native.outlet[0], native.outlet[1], native.outlet[2])
	_inlet.position = Vector3(native.inlet[0], native.inlet[1], native.inlet[2])
	for holder in _tokens:
		for index in _tokens[holder].size(): _tokens[holder][index].visible = index < state.stock[holder]
	_presented = {"cut": observation.cut, "stock": state.stock.duplicate(true)}
	_status.text = "FINITE CARGO A\nCarrier: %d      Receiver: %d      Total: 3\n\nDistance %.4f m  (limit .08)\nFacing %.4f  (minimum .995)\nVisit %d: %s%s\nNative cut %d   ready: %s\nGoal %d   source %s   turn %s" % [
		state.stock.carrier, state.stock.receiver, native.distance, native.facing, observation.window.id,
		"aligned" if observation.eligible else "away", "; used" if observation.window.spent else "",
		observation.cut, str(observation.registered), state.committed, "on" if state.running else "off", "pending" if state.pending else "complete"]
	_repeat.set_pressed_no_signal(repeat_source)
	_sensor.set_pressed_no_signal(state.automatic)

func visible_facts() -> Dictionary:
	var counts := {"carrier": 0, "receiver": 0}
	for holder in _tokens:
		for token in _tokens[holder]:
			if token.visible: counts[holder] += 1
	return {"counts": counts, "presented": _presented.duplicate(true), "deck": authority._pose(_deck.global_transform),
		"dock": authority._pose(_dock.global_transform), "outlet": authority._array(_outlet.position), "inlet": authority._array(_inlet.position)}

func _box(parent: Node3D, size: Vector3, location: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	node.material_override = material
	node.position = location
	parent.add_child(node)
	return node

func _build_world() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(5.5, 6.5, 7.5)
	add_child(camera)
	camera.look_at(Vector3(0.7, 0.5, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.5
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.6
	add_child(light)
	_box(self, Vector3(9, 0.1, 7), Vector3(0, -0.1, 0), Color("24333c"))
	_deck = _box(self, Vector3(3, 0.35, 3), Vector3.ZERO, Color("456879"))
	_dock = _box(self, Vector3(0.55, 0.1, 0.55), Vector3.ZERO, Color("cfad62"))
	# Visible stub to the inlet, .275 m beyond the dock's left face. No collider.
	_box(_dock, Vector3(0.55, 0.04, 0.04), Vector3(-0.275, 0, 0), Color("ffe09b"))
	_outlet = _box(self, Vector3(0.09, 0.09, 0.09), Vector3.ZERO, Color("64e1e5"))
	_inlet = _box(self, Vector3(0.04, 0.16, 0.16), Vector3.ZERO, Color("ffe09b"))
	for holder in ["carrier", "receiver"]:
		var parent: Node3D = _deck if holder == "carrier" else _dock
		for index in 3:
			var location := Vector3(-0.75 + 0.55 * index, 0.35, -0.4) if holder == "carrier" else Vector3(0, 0.16 + 0.14 * index, 0)
			_tokens[holder].append(_box(parent, Vector3(0.12, 0.12, 0.12), location, Color("67d4cd")))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(400, 0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	var title := Label.new()
	title.text = "MOVING PORT → FIXED RECEIVER"
	title.add_theme_font_size_override("font_size", 21)
	column.add_child(title)
	_status = Label.new()
	column.add_child(_status)
	for item in [["Source on/off [F]", toggle_source], ["One 20:40 goal [N]", step_once],
		["P requests 1 A [P]", request_unit.bind("P")], ["Q requests 1 A [Q]", request_unit.bind("Q")],
		["P + Q compete in one cut [C]", compete], ["Retry last P request [D]", retry_p]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		column.add_child(button)
	_repeat = CheckButton.new()
	_repeat.text = "Repeat source goals [R]"
	_repeat.toggled.connect(set_repeat)
	column.add_child(_repeat)
	_sensor = CheckButton.new()
	_sensor.text = "Contact sensor requests 1 A [T]"
	_sensor.toggled.connect(set_sensor)
	column.add_child(_sensor)
	_message = Label.new()
	_message.text = "Three finite units; one per contact visit."
	column.add_child(_message)
	var limits := Label.new()
	limits.text = "Cyan squares show symbolic cargo.\nCyan outlet and gold inlet use native poses.\nDiscrete ports; no physical item or docking force.\nA used visit reopens only after leaving."
	column.add_child(limits)
