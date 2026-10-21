extends PanelContainer
## A separate finite teaching instance of the existing rules, never player state.
## Only lesson setup, explicit example ticks and example retrieval mutate it.

const Model = preload("res://opening/native_model.gd")
const World = preload("res://opening/example_world.gd")
var world
var viewport: SubViewport
var surface: SubViewportContainer
var readout: Label
var inspect_label: Label
var step_button: Button
var recover_button: Button
var model
var lesson := 0
var sequence := 0
var ticks := 0
var epoch := 0
var press_id := ""
var inspected := ""
var transitions: Array = []

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111f26")
	style.border_color = Color("536565")
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var heading := Label.new()
	heading.text = "SEPARATE EXAMPLE · resets on lesson change\nYour worksite keeps running. Right-drag orbit · Wheel zoom · WASD pan · Home reset"
	heading.add_theme_font_size_override("font_size", 13)
	column.add_child(heading)
	surface = SubViewportContainer.new()
	surface.custom_minimum_size = Vector2(650, 250)
	surface.stretch = true
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(surface)
	viewport = SubViewport.new()
	viewport.size = Vector2i(650, 250)
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	surface.add_child(viewport)
	world = World.new()
	world.model = Model.new("opening-example-1", ["P"])
	viewport.add_child(world)
	recenter()
	readout = Label.new()
	readout.add_theme_font_size_override("font_size", 14)
	column.add_child(readout)
	inspect_label = Label.new()
	inspect_label.add_theme_font_size_override("font_size", 13)
	column.add_child(inspect_label)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	step_button = Button.new()
	step_button.text = "Advance example one tick"
	step_button.pressed.connect(_step)
	buttons.add_child(step_button)
	recover_button = Button.new()
	recover_button.text = "Collect example plate → resume"
	recover_button.pressed.connect(_recover)
	buttons.add_child(recover_button)
	set_lesson(0)

func _command(action: Dictionary) -> Dictionary:
	sequence += 1
	var intent := action.duplicate(true)
	intent.merge({"context": model.context, "client": "P", "request": "example-" + str(sequence)})
	var outcome: Dictionary = model.command(intent)
	assert(outcome.accepted, "Example setup must use valid shared-rule transitions")
	return outcome

func _observe(x: float, z: float) -> void:
	epoch += 1
	var observed: Dictionary = model.publish_actor("P", [x, 1.0, z], epoch)
	assert(observed.get("accepted", false), "Example construction must remain in reach")

func _advance(count: int = 1) -> void:
	for i in range(count):
		model.advance()
		ticks += 1
	transitions.append({"kind": "advance", "ticks": count, "state": model.projection()})

func set_lesson(index: int) -> void:
	lesson = index
	sequence = 0
	ticks = 0
	epoch = 0
	press_id = ""
	inspected = ""
	transitions.clear()
	model = Model.new("opening-example-1", ["P"])
	world.model = model
	if not model.boot_result.get("accepted", false):
		readout.text = "The native teaching example is unavailable."
		step_button.disabled = true
		recover_button.disabled = true
		return
	# The isolated Host uses the same finite kit, site, rules and placement
	# commands as a worksite. Observations only supply this example's reach.
	_observe(0.0, 0.0)
	_command({"action": "place_foundation", "cell": [0, 1], "level": 4})
	_observe(4.95, 0.0)
	_command({"action": "place_foundation", "cell": [3, 1], "level": 4})
	for entry in [["wheel", -2, "x"], ["collector", 0, "z"], ["processor", 3, "z"]]:
		_observe(-1.65 if entry[0] == "wheel" else float(entry[1]) * 1.65, 3.3 if entry[0] == "wheel" else 0.0)
		var placed: Dictionary = _command({"action": "place", "kind": entry[0], "cell": [entry[1], 1], "axis": entry[2], "level": 4})
		if entry[0] == "processor":
			press_id = placed.entity
	_observe(-3.3, 0.0)
	_command({"action": "place_gear", "center": [-4, 4, 4], "axis": "x", "teeth": 4})
	_observe(-3.3, -1.65)
	_command({"action": "place_gear", "center": [0, 4, 0], "axis": "z", "teeth": 4})
	for x in [0, 4]:
		_observe(float(x) * 1.65 / 4.0, -3.3)
		_command({"action": "place_gear", "center": [x, 4, -4], "axis": "z", "teeth": 2})
	for x in [4, 8, 12]:
		_observe(float(x) * 1.65 / 4.0, -4.95)
		_command({"action": "place_gear", "center": [x, 4, -8], "axis": "z", "teeth": 2})
	for center in [[4, 0], [12, -4], [12, 0]]:
		_observe(float(center[0]) * 1.65 / 4.0, float(center[1]) * 1.65 / 4.0 - 1.65)
		_command({"action": "place_shaft", "center": [center[0], 4, center[1]], "axis": "z", "half_span": 2})
	var endpoints: Array[String] = []
	for x in [4, 8]:
		_observe(float(x) * 1.65 / 4.0, 0.0)
		endpoints.append(_command({"action": "place_shaft", "center": [x, 4, 4], "axis": "z", "half_span": 2}).entity)
	_observe(2.475, 0.0)
	_command({"action": "place_belt_span", "from": endpoints[0], "to": endpoints[1]})
	_observe(-1.65, 0.0)
	_command({"action": "set_power", "active": lesson >= 1})
	if lesson >= 2:
		for turn in range(512):
			var stock: Dictionary = model.projection().stock
			if stock.held > 0 and (lesson == 2 or stock.output > 0):
				break
			_advance()
	transitions.append({"kind": "lesson", "state": model.projection()})
	# Revisions can repeat across the deliberately reset teaching instances.
	world.geometry_key = ""
	world.visual_revision = -1
	_refresh()

func _step() -> void:
	_advance()
	_refresh()

func _recover() -> void:
	if lesson != 3 or model.projection().stock.output != 1:
		return
	_observe(4.95, 0.0)
	_command({"action": "retrieve", "entity": press_id, "amount": 1})
	transitions.append({"kind": "retrieve", "state": model.projection()})
	_advance()
	_refresh()

func _refresh() -> void:
	world._refresh()
	var state: Dictionary = model.projection()
	var stock: Dictionary = state.stock
	var belt_raw := 0
	for span: Dictionary in state.get("belt_spans", {}).values():
		for slot: Variant in span.slots:
			if slot is Dictionary:
				belt_raw += int(slot.get("raw", 0))
	readout.text = "EXAMPLE tick %d · %s · cycle %d\nSeam %d → collector %d → belt %d → input %d → held %d → outlet %d · collected %d" % [
		ticks, "powered" if state.powered else ("stopped" if not state.power_enabled else "unpowered"), state.remaining,
		stock.source, stock.collector, belt_raw, stock.input, stock.held, stock.output, stock.player]
	inspect_label.text = "Click a machine in the example to inspect its material and drive connections."
	if state.entities.has(inspected):
		var kind: String = state.entities[inspected].kind
		var motion: Dictionary = state.get("motion", {}).get(inspected, {})
		inspect_label.text = "EXAMPLE %s · %s" % [world.NAMES[kind], motion.get("state", "unpowered")]
		if kind == "processor":
			inspect_label.text += " · %d input / %d held / %d ready · %d ticks left" % [stock.input, stock.held, stock.output, state.remaining]
	elif state.get("transmission_parts", {}).has(inspected):
		var part: Dictionary = state.transmission_parts[inspected]
		inspect_label.text = "EXAMPLE %s · %s" % [part.kind.capitalize(), state.get("motion", {}).get(inspected, {}).get("state", "unpowered")]
	step_button.disabled = lesson < 1
	recover_button.visible = lesson == 3
	recover_button.disabled = stock.output != 1

func pan(delta: float) -> void:
	var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		world.focus += Vector3(direction.x, 0, direction.y) * delta * 4.0
		world.focus.x = clampf(world.focus.x, -4, 6)
		world.focus.z = clampf(world.focus.z, -4, 6)

func recenter() -> void:
	world.focus = Vector3(0.8, 0, 0)
	world.distance = 11.5
	world.orbit_yaw = 0.68
	world.orbit_pitch = 0.82
	world._update_camera()

func handle_pointer(event: InputEvent) -> bool:
	if not (event is InputEventMouse) or not surface.get_global_rect().has_point(event.position):
		return false
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		world.orbit_yaw -= event.relative.x * 0.007
		world.orbit_pitch = clampf(world.orbit_pitch + event.relative.y * 0.005, 0.35, 1.25)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: world.distance = maxf(10, world.distance - 1)
			MOUSE_BUTTON_WHEEL_DOWN: world.distance = minf(28, world.distance + 1)
			MOUSE_BUTTON_LEFT:
				var point: Vector2 = (event.position - surface.global_position) * Vector2(viewport.size) / surface.size
				inspected = world._screen_entity(point)
				_refresh()
	world._update_camera()
	return true
