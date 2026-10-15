extends Node3D
## Ordinary local consumer. Only the authority owns or changes material.
const Authority = preload("res://precision/authority.gd")
const Circuit = preload("res://precision/controller.gd")
signal observed(kind: String, event: Dictionary, state: Dictionary)
signal replaced(owner_id: int, state: Dictionary)
var model
var auto_advance := false
var _elapsed := 0.0
var _camera: Camera3D
var _yaw := 0.55
var _pitch := 0.85
var _radius := 15.5
var _status: Label
var _message: Label
var _clock: CheckButton
var _power: Button
var _rows: Dictionary = {}
var _pools: Dictionary = {}
var _labels: Dictionary = {}
var _deadline := 0
const COLORS = {"A": Color("59becb"), "B": Color("ecc568"), "X": Color("d97ac1"), "C": Color("85c994")}

func _ready() -> void:
	var seconds := 900
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--precision-seconds="):
			seconds = clampi(int(argument.trim_prefix("--precision-seconds=")), 1, 900)
	_deadline = Time.get_ticks_msec() + seconds * 1000
	_build_world()
	_build_ui()
	reset_fixture()

func reset_fixture() -> void:
	auto_advance = false
	_elapsed = 0.0
	if model != null:
		model.command_completed.disconnect(_on_command)
		model.step_completed.disconnect(_on_step)
	model = Authority.new()
	model.command_completed.connect(_on_command)
	model.step_completed.connect(_on_step)
	_message.text = "Fresh finite fixture: 8 A, 4 B, 1 X. Reset is a new experiment, not recovery."
	var state: Dictionary = model.snapshot()
	_refresh(state)
	replaced.emit(model.get_instance_id(), state)

func _on_command(outcome: Dictionary, state: Dictionary) -> void:
	_message.text = ("Circuit: " if outcome.origin == "circuit" else "Operator: ") + outcome.reason
	_refresh(state)
	observed.emit("command", outcome, state)

func _on_step(event: Dictionary, state: Dictionary) -> void:
	_refresh(state)
	observed.emit("step", event, state)

func insert(kind: String) -> void:
	model.command({"action": "insert", "kind": kind})

func recover(kind: String) -> void:
	model.command({"action": "recover", "kind": kind})

func collect() -> void:
	model.command({"action": "collect"})

func step_once() -> void:
	model.advance()

func toggle_power() -> void:
	model.command({"action": "power", "active": not model.snapshot().powered})

func _wire(active: bool, row: String) -> void:
	model.command({"action": "wire", "row": row, "active": active})

func _toggle_group(rows: Array) -> void:
	var state: Dictionary = model.snapshot()
	var active := false
	for row in rows:
		if not state.wiring[row]: active = true
	for row in rows: _wire(active, row)

func toggle_meter() -> void:
	_toggle_group(Circuit.METER)

func toggle_recovery() -> void:
	_toggle_group(Circuit.RECOVERY)

func set_clock(active: bool) -> void:
	auto_advance = active
	_elapsed = 0.0
	_clock.set_pressed_no_signal(active)

func _process(delta: float) -> void:
	if _deadline > 0 and Time.get_ticks_msec() >= _deadline:
		get_tree().quit(0)
		return
	if model == null or not auto_advance: return
	_elapsed += delta
	while _elapsed >= 0.12:
		_elapsed -= 0.12
		model.advance() # Fixture clock cadence, not a game-performance target.

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_A: insert("A")
		KEY_B: insert("B")
		KEY_X: insert("X")
		KEY_1: recover("A")
		KEY_2: recover("B")
		KEY_3: recover("X")
		KEY_C: collect()
		KEY_N: step_once()
		KEY_SPACE: toggle_power()
		KEY_M: toggle_meter()
		KEY_R: toggle_recovery()
		KEY_T: set_clock(not auto_advance)
		KEY_BACKSPACE: reset_fixture()
		_: return
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= event.relative.x * 0.007
		_pitch = clampf(_pitch + event.relative.y * 0.007, 0.35, 1.35)
		_camera_pose()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: _radius = maxf(10, _radius - 0.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _radius = minf(23, _radius + 0.6)
		else: return
		_camera_pose()

func _refresh(state: Dictionary) -> void:
	_status.text = "EXACT BILL: 2 A + 1 B → C\nNo X; no extra A or B\n\nCondition: %s\nJob: %d   remaining: %d\nOutput: %d C   collected: %d C\n\nCaptured input stays held when paused\nor when the output is full." % [state.condition, state.current_job, state.remaining, state.output, state.finished]
	_power.text = "Pause power [Space]" if state.powered else "Resume power [Space]"
	_clock.set_pressed_no_signal(auto_advance)
	for row in _rows: _rows[row].set_pressed_no_signal(state.wiring[row])
	for location in ["source", "input", "held", "returns", "reject"]:
		var stock: Dictionary = state.locations[location]
		_labels[location].text = "%s\nA %d   B %d   X %d" % [location.to_upper(), stock.A, stock.B, stock.X]
		for kind in ["A", "B", "X"]:
			var pool: Array = _pools[location][kind]
			for index in pool.size(): pool[index].visible = index < stock[kind]
	for location in ["output", "finished"]:
		var quantity: int = state[location]
		_labels[location].text = "%s\n%d C" % [location.to_upper(), quantity]
		for index in _pools[location].size(): _pools[location][index].visible = index < quantity

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

func _box(parent: Node3D, size: Vector3, position_value: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	mesh.position = position_value
	parent.add_child(mesh)
	return mesh

func _label3d(position_value: Vector3) -> Label3D:
	var label := Label3D.new()
	label.position = position_value
	label.font_size = 28
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	add_child(label)
	return label

func _build_world() -> void:
	_box(self, Vector3(13, 0.12, 11), Vector3(0.5, -0.2, 1), Color("32474a"))
	var positions := {"source": Vector3(-3.5, 0, -2), "input": Vector3(-0.5, 0, -2),
		"held": Vector3(2.5, 0, -2), "returns": Vector3(-3.5, 0, 2),
		"reject": Vector3(-0.5, 0, 2), "output": Vector3(2.5, 0, 2), "finished": Vector3(2.5, 0, 5)}
	for location in positions:
		var position_value: Vector3 = positions[location]
		_box(self, Vector3(2.2, 0.16, 1.7), position_value, Color("526365"))
		_labels[location] = _label3d(position_value + Vector3(0, 1.0, 0))
		if location in ["output", "finished"]:
			_pools[location] = []
			for index in (1 if location == "output" else 4):
				_pools[location].append(_box(self, Vector3(0.34, 0.30, 0.34),
					position_value + Vector3((index % 4 - 1.5) * 0.4, 0.26, 0), COLORS.C))
		else:
			_pools[location] = {"A": [], "B": [], "X": []}
			var offset := 0
			for kind in ["A", "B", "X"]:
				for _index in Authority.INITIAL[kind]:
					_pools[location][kind].append(_box(self, Vector3(0.27, 0.25, 0.27),
						position_value + Vector3((offset % 4 - 1.5) * 0.38, 0.23, (floori(float(offset) / 4.0) - 1) * 0.38), COLORS[kind]))
					offset += 1
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.4
	add_child(light)
	var ambient := WorldEnvironment.new()
	ambient.environment = Environment.new()
	ambient.environment.background_mode = Environment.BG_COLOR
	ambient.environment.background_color = Color("15282c")
	ambient.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambient.environment.ambient_light_color = Color("c9ded9")
	ambient.environment.ambient_light_energy = 0.6
	add_child(ambient)
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_camera_pose()

func _camera_pose() -> void:
	var target := Vector3(0, 0.2, 1.1)
	_camera.position = target + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _radius
	_camera.look_at(target)

func _text(parent: Control, text_value: String, size := 16) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _button(parent: Control, text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _panel(layer: CanvasLayer, position_value: Vector2, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = position_value
	panel.custom_minimum_size.x = width
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	return column

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var left := _panel(layer, Vector2(16, 16), 292)
	_text(left, "PRECISION BENCH", 23)
	_text(left, "Later-control technical fixture", 15)
	_text(left, "Stationary ports; symbolic item display", 13)
	_button(left, "Insert A [A]", insert.bind("A"))
	_button(left, "Insert B [B]", insert.bind("B"))
	_button(left, "Insert wrong X [X]", insert.bind("X"))
	_button(left, "Return one A [1]", recover.bind("A"))
	_button(left, "Return one B [2]", recover.bind("B"))
	_button(left, "Route X to reject bin [3]", recover.bind("X"))
	_button(left, "Collect output C [C]", collect)
	_power = _button(left, "", toggle_power)
	_button(left, "One authority step [N]", step_once)
	_clock = CheckButton.new()
	_clock.text = "Run clock [T]"
	_clock.focus_mode = Control.FOCUS_NONE
	_clock.toggled.connect(set_clock)
	left.add_child(_clock)
	_button(left, "Fresh fixture [Backspace]", reset_fixture)
	var right := _panel(layer, Vector2(928, 16), 336)
	_status = _text(right, "", 16)
	_text(right, "SENSOR → ACTUATOR ROWS", 16)
	for row in Circuit.ROWS:
		var toggle := CheckButton.new()
		toggle.text = Circuit.LABELS[row]
		toggle.add_theme_font_size_override("font_size", 12)
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.toggled.connect(_wire.bind(row))
		right.add_child(toggle)
		_rows[row] = toggle
	_button(right, "Toggle meter/output rows [M]", toggle_meter)
	_button(right, "Toggle recovery rows [R]", toggle_recovery)
	var bottom := _panel(layer, Vector2(16, 704), 1248)
	_message = _text(bottom, "", 15)
	_text(bottom, "Only an exact whole chamber starts. Recovery routes actual stock; it never resets it.  Right-drag orbit · Wheel zoom", 13)
