extends Node3D
## Presentation and controls; the shared authority alone moves native bodies.

const Authority = preload("res://mechanics/authority.gd")
var authority
var auto_advance := true
var elapsed := 0.0
var camera: Camera3D
var yaw := 0.55
var distance := 17.5
var stats: Label
var message: Label
var running_button: Button
var coupling_button: Button
var sliders: Dictionary = {}
var gears: Dictionary = {}
var obstacle_mesh: MeshInstance3D

func _ready() -> void:
	authority = Authority.new()
	add_child(authority)
	authority.advanced.connect(func(_outcome: Dictionary): _refresh())
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("17232a")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c6dad8")
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 46
	add_child(camera)
	_box(Vector3(0, -0.2, 2), Vector3(12, 0.3, 10), Color("354840"))
	for branch in ["B", "U"]:
		sliders[branch] = _box(Vector3.ZERO, Authority.BODY_SIZE,
			Color("db9e5b") if branch == "B" else Color("75b8ac"))
		gears[branch] = _gear(Vector3(-3.1, 1.0, 0 if branch == "B" else 3),
			0.55, Color("d0ad67") if branch == "B" else Color("71a89e"))
		_label_3d(branch + " / SLIDER", Vector3(0, 1.65, 0 if branch == "B" else 3))
	gears.S = _gear(Vector3(-4.35, 1.0, 1.5), 0.75, Color("c6c8aa"))
	gears.I = _gear(Vector3(-3.8, 1.0, 0.5), 0.3, Color("c5b184"))
	for z in [0, 3, 4]:
		for side in [-0.48, 0.48]:
			_box(Vector3(0, 0.25, z + side), Vector3(4.8, 0.12, 0.12), Color("536b66"))
		for x in [-2, 0, 2]:
			_box(Vector3(x, 0.06, z), Vector3(0.04, 0.025, 1.0), Color("b3ab83"))
	obstacle_mesh = _box(Vector3.ZERO, Vector3(0.35, 1.5, 1.1), Color("b95e4b"))
	_box(Vector3(1.6, 0.08, 0), Vector3(0.6, 0.04, 1.2), Color("5d9eb6"))
	_label_3d("WORK ENCOUNTER", Vector3(2.1, 0.25, -1.1))
	_label_3d("SOURCE / JUNCTION", Vector3(-4.1, 2.1, 1.5))
	_interface()
	_refresh()

func issue(intent: Dictionary) -> Dictionary:
	var outcome: Dictionary = authority.command(intent)
	message.text = {"applied": "Control applied.", "queued_for_physics": "One drive step requested.",
		"geometry_pending": "Geometry update requested.",
		"source_stopped": "Start the source before stepping.", "stop_before_engage": "Stop the source before engaging K.",
		"coupling_misaligned": "Align the input shaft before engaging K.",
		"initial_stationary_setup_only": "Change construction or gearing only at initial setup."}.get(outcome.reason, outcome.reason)
	_refresh()
	return outcome

func _physics_process(delta: float) -> void:
	if auto_advance and authority != null and authority.running:
		elapsed += delta
		if elapsed >= 0.18 and not authority.pending:
			elapsed = 0.0
			issue({"action": "step"})

func _process(_delta: float) -> void:
	if authority != null:
		_refresh()
	camera.position = Vector3(0, 0.4, 1.7) + Vector3(sin(yaw) * 0.8, 0.65, cos(yaw) * 0.8) * distance
	camera.look_at(Vector3(0, 0.4, 1.7))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode in [KEY_SPACE, KEY_N, KEY_K, KEY_O]:
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_SPACE: issue({"action": "run", "active": not authority.running})
				KEY_N: issue({"action": "step"})
				KEY_K: issue({"action": "coupling", "active": not authority.coupled})
				KEY_O: issue({"action": "fixture_obstacle", "active": not authority.obstacle_active})
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.006
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(11, distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(25, distance + 1)

func _refresh() -> void:
	if stats == null:
		return
	var state: Dictionary = authority.projection()
	var physical: Dictionary = state.completed
	for branch in sliders:
		sliders[branch].visible = not physical.is_empty()
		if not physical.is_empty():
			var at: Array = physical.positions[branch]
			sliders[branch].position = Vector3(at[0], at[1], at[2])
			gears[branch].rotation.z = physical.phases[branch]
	gears.S.rotation.z = physical.get("source_phase", 0.0)
	gears.I.rotation.z = -physical.get("source_phase", 0.0)
	gears.I.visible = state.idler
	var obstacle_at: Array = physical.get("obstacle_position", state.obstacle_position)
	obstacle_mesh.visible = not physical.is_empty()
	obstacle_mesh.position = Vector3(obstacle_at[0], obstacle_at[1], obstacle_at[2])
	running_button.text = "Pause source [Space]" if state.running else "Start source [Space]"
	coupling_button.text = "Isolate B [K]" if state.coupled else "Engage K [K]"
	var visible_phases: Dictionary = physical.get("phases", {"B": 0.0, "U": 0.0})
	stats.text = "%s\nK %s  ·  B ratio %s20:%d\nSource %.3f\nB %.3f  ·  U %.3f\n%d completed steps / %d attempts\nWork encounters %d" % [
		"NATIVE UPDATE PENDING" if state.native_pending else "CONNECTED DRIVE STALLED" if state.blocked else "SOURCE RUNNING" if state.running else "SOURCE PAUSED",
		"ENGAGED" if state.coupled else "OPEN / B RETAINED", "+" if state.idler else "−", state.teeth,
		physical.get("source_phase", 0.0), visible_phases.B, visible_phases.U,
		physical.get("committed", 0), state.attempts, physical.get("contact_entries", 0)]
	if not state.last_collision.is_empty():
		stats.text += "\nLast solid: %s → %s" % [state.last_collision.branch, state.last_collision.collider]

func _box(at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material_override = material
	mesh.position = at
	add_child(mesh)
	return mesh

func _gear(at: Vector3, radius: float, color: Color) -> Node3D:
	var wheel := Node3D.new()
	wheel.position = at
	add_child(wheel)
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.18
	mesh.mesh = cylinder
	mesh.rotation.x = PI / 2
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	wheel.add_child(mesh)
	for angle in [0.0, PI / 2]:
		var spoke := _box(Vector3.ZERO, Vector3(radius * 1.8, 0.08, 0.24), Color("334a4d"))
		spoke.reparent(wheel, false)
		spoke.rotation.z = angle
	return wheel

func _label_3d(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 32
	label.pixel_size = 0.007
	label.modulate = Color("ede4c9")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(235, 38)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 18)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	var title := Label.new()
	title.text = "MECHANICS / TWO BRANCH RIG\nTrace signed drive, motion and branch isolation."
	column.add_child(title)
	running_button = _button(column, "Start source [Space]", func(): issue({"action": "run", "active": not authority.running}))
	_button(column, "Advance one step [N]", func(): issue({"action": "step"}))
	coupling_button = _button(column, "Isolate B [K]", func(): issue({"action": "coupling", "active": not authority.coupled}))
	_button(column, "Move obstacle [O]", func(): issue({"action": "fixture_obstacle", "active": not authority.obstacle_active}))
	stats = Label.new()
	column.add_child(stats)
	message = Label.new()
	message.text = "Drive the two sliders; place an obstacle in B's path."
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 295
	column.add_child(message)
	var help := Label.new()
	help.position = Vector2(25, 735)
	help.text = "Right-drag orbit · Wheel zoom\nK opens immediately; stop and align input phase before engaging. Work zone is a non-consuming fixture."
	layer.add_child(help)
