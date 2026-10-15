extends PanelContainer
## A separate finite teaching instance of the existing rules, never player state.
## Only lesson setup, explicit example ticks and example retrieval mutate it.

const Model = preload("res://model.gd")
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
var inspected := ""
var transitions: Array = []

func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var heading := Label.new()
	heading.text = "SEPARATE EXAMPLE · 16 blanks · resets on lesson change\nYour worksite keeps running. Right-drag orbit · Wheel zoom · WASD pan · Home reset"
	heading.add_theme_font_size_override("font_size", 13)
	column.add_child(heading)
	surface = SubViewportContainer.new()
	surface.custom_minimum_size = Vector2(650, 310)
	surface.stretch = true
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(surface)
	viewport = SubViewport.new()
	viewport.size = Vector2i(650, 310)
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	surface.add_child(viewport)
	world = World.new()
	world.model = Model.new(16, "opening-example-1", 1, {"opening": true})
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

func _command(action: Dictionary) -> void:
	sequence += 1
	var intent := action.duplicate(true)
	intent.merge({"context": model.context, "client": "EXAMPLE", "request": "example-" + str(sequence)})
	var outcome: Dictionary = model.command(intent)
	assert(outcome.accepted, "Example setup must use valid shared-rule transitions")

func _advance(count: int = 1) -> void:
	model.advance(count)
	ticks += count
	transitions.append({"kind": "advance", "ticks": count, "state": model.projection()})

func set_lesson(index: int) -> void:
	lesson = index
	sequence = 0
	ticks = 0
	inspected = ""
	transitions.clear()
	model = Model.new(16, "opening-example-1", 1, {"opening": true})
	world.model = model
	# Exactly the carried starter kit: no scene/stock/checkpoint injection.
	for entry in [["wheel", -1], ["collector", 0], ["belt", 1], ["processor", 2]]:
		_command({"action": "place", "kind": entry[0], "cell": [entry[1], 0]})
	for pair in [["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
		_command({"action": "connect", "from": pair[0], "to": pair[1]})
	if lesson >= 1:
		for pair in [["wheel-1", "collector-1"], ["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
			_command({"action": "connect_drive", "from": pair[0], "to": pair[1]})
	if lesson == 2:
		_advance(4)
	elif lesson == 3:
		_advance(8)
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
	_command({"action": "retrieve", "entity": "processor-1", "amount": 1})
	transitions.append({"kind": "retrieve", "state": model.projection()})
	_advance()
	_refresh()

func _refresh() -> void:
	world._refresh()
	var state: Dictionary = model.projection()
	var stock: Dictionary = state.stock
	readout.text = "EXAMPLE tick %d · %s · cycle %d\nSeam %d → collector %d → belt %d → input %d → held %d → outlet %d · collected %d" % [
		ticks, "powered" if state.powered else "unconnected", state.remaining,
		stock.source, stock.collector, stock.belt, stock.input, stock.held, stock.output, stock.player]
	inspect_label.text = "Click a machine in the example to inspect its material and drive connections."
	if state.entities.has(inspected):
		var kind: String = state.entities[inspected].kind
		inspect_label.text = "EXAMPLE %s · square %s" % [world.NAMES[kind], str(state.entities[inspected].cell)]
		if kind == "processor":
			inspect_label.text += " · %d input / %d held / %d ready · %d ticks left" % [stock.input, stock.held, stock.output, state.remaining]
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
