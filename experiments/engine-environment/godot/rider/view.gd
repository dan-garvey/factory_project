extends Node3D
## A local actual player and one inherited linear drive, not a passenger dummy.
signal answered(intent: Dictionary, outcome: Dictionary)
const Drive = preload("res://rider/authority.gd")
const Player = preload("res://rider/player.gd")
var authority
var player
var ground: StaticBody3D
var wall: StaticBody3D
var deck_mesh: MeshInstance3D
var camera: Camera3D
var stats: Label
var message: Label
var run_button: Button
var step_button: Button
var repeat_button: CheckBox
var elapsed := 0.0
var last_result := {}
var yaw := 0.38
var pitch := 0.55
var distance := 13.0

func _make_authority() -> Node3D:
	return Drive.new()

func _fixture_text() -> Dictionary:
	return {"title": "LINEAR RIDER", "deck": "LINEAR DECK · ±2", "summary": "Local linear passenger experiment"}

func _display_deck(state: Dictionary) -> void:
	if not state.completed.is_empty():
		var at: Array = state.completed.positions.B
		deck_mesh.position = Vector3(at[0], at[1], at[2])

func _support_text() -> String:
	return "deck" if player.floor_id == authority.bodies.B.get_instance_id() else "ground" if player.floor_id == ground.get_instance_id() else "air"

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("182a32")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("cfdbd7")
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.shadow_enabled = true
	add_child(light)
	ground = _solid("Ground", Vector3(0, -0.2, 0), Vector3(24, 0.4, 12), Color("3c514a"))
	wall = _solid("Wall", Vector3(5, 1, 0), Vector3(0.25, 2, 6), Color("7d5e53"))
	for x in range(-4, 5):
		_box(self, Vector3(x, 0.003, -2), Vector3(0.025, 0.01, 0.25), Color("b4b595"))
		_label3d(str(x), Vector3(x, 0.1, -2.35))
	_box(self, Vector3(0, 0.12, 0), Vector3(7.1, 0.12, 0.14), Color("82958f"))
	_label3d(_fixture_text().deck, Vector3(0, 0.3, -2.8))
	_label3d("FIXED BOUNDARY", Vector3(5, 2.4, 0))
	deck_mesh = _box(self, Vector3.ZERO, Drive.DECK_SIZE, Color("b09b64"))
	_box(deck_mesh, Vector3(0, 0.18, 0), Vector3(2.8, 0.02, 0.04), Color("eddfb6"))
	camera = Camera3D.new()
	camera.fov = 50
	add_child(camera)
	_build_interface()
	fresh()

func fresh() -> void:
	if authority != null:
		remove_child(authority)
		authority.queue_free()
		remove_child(player)
		player.queue_free()
	authority = _make_authority()
	authority.name = "Drive"
	add_child(authority)
	player = Player.new()
	player.name = "Player"
	player.position = Vector3(-2, 0.905, 0)
	add_child(player)
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	mesh.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("e1c276")
	mesh.material_override = material
	player.add_child(mesh)
	repeat_button.button_pressed = false
	elapsed = 0.0
	message.text = "Walk toward the deck with D and jump with Space to board. F starts its source."
	authority.advanced.connect(func(_outcome): _refresh())
	_refresh()

func issue(intent: Dictionary) -> void:
	last_result = authority.command(intent)
	message.text = {"applied": "Source control applied.", "queued_for_physics": "Drive step requested.",
		"source_stopped": "Start the source with F before stepping.", "step_pending": "Wait for the drive step to finish."}.get(last_result.reason, str(last_result.reason))
	_refresh()
	answered.emit(intent.duplicate(true), last_result.duplicate(true))

func _toggle_source() -> void:
	issue({"action": "run", "active": not authority.running})

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_toggle_source()
		elif event.keycode == KEY_N:
			issue({"action": "step"})
		elif event.keycode == KEY_R:
			call_deferred("fresh")
		else:
			return
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.007
		pitch = clampf(pitch + event.relative.y * 0.005, 0.25, 1.15)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(9, distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(20, distance + 1)

func _process(delta: float) -> void:
	if repeat_button.button_pressed and authority.running and not authority.pending:
		elapsed += delta
		if elapsed >= 0.18:
			elapsed = 0.0
			issue({"action": "step"})
	var focus := Vector3(0.8, 0.6, 0)
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(focus)
	_refresh()

func _refresh() -> void:
	var state: Dictionary = authority.projection()
	_display_deck(state)
	run_button.text = "Pause source [F]" if state.running else "Start source [F]"
	step_button.disabled = not state.running or state.pending
	var support := _support_text()
	stats.text = "%s · %d completed steps\nFeet: %s\nPlayer x %.3f · y %.3f\nWASD walk · Space jump\nF source · N step · R fresh start\nRight-drag orbit · Wheel zoom\n\n%s\nNo items, network or damage rules" % [
		"Updating drive" if state.native_pending else "Source running" if state.running else "Source paused", state.completed.get("committed", 0), support, player.position.x, player.position.y, _fixture_text().summary]

func _box(parent: Node, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	parent.add_child(node)
	return node

func _solid(label: String, at: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 16 | 4
	add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	_box(body, Vector3.ZERO, size, color)
	return body

func _label3d(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 27
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _build_interface() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title := Label.new()
	title.text = _fixture_text().title
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	run_button = Button.new()
	run_button.pressed.connect(_toggle_source)
	column.add_child(run_button)
	step_button = Button.new()
	step_button.text = "Advance one step [N]"
	step_button.pressed.connect(func(): issue({"action": "step"}))
	column.add_child(step_button)
	repeat_button = CheckBox.new()
	repeat_button.text = "Repeat fixed cycle"
	repeat_button.toggled.connect(func(_active): elapsed = 0.0)
	column.add_child(repeat_button)
	var reset := Button.new()
	reset.text = "Fresh start [R]"
	reset.pressed.connect(func(): call_deferred("fresh"))
	column.add_child(reset)
	stats = Label.new()
	stats.add_theme_font_size_override("font_size", 15)
	column.add_child(stats)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(280, 70)
	column.add_child(message)
