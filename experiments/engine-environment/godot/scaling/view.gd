extends Node3D
## Presentation reads only the spatial authority's completed native observations.
const Authority = preload("res://scaling/authority.gd")
var case_name := "gantry_grown"
var authority
var auto_advance := true
var elapsed := 0.0
var yaw := 0.45
var distance := 15.0
var camera: Camera3D
var stats: Label
var meshes: Array = []
var coupon_meshes := {}
var beam_meshes: Array = []

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_name = argument.trim_prefix("--case=")
	authority = Authority.new()
	assert(authority.configure(case_name))
	add_child(authority)
	authority.advanced.connect(func(_value: Dictionary): _refresh())
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("17272e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d0ddd7")
	environment.ambient_light_energy = 0.8
	world.environment = environment
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.shadow_enabled = true
	add_child(light)
	camera = Camera3D.new()
	camera.fov = 48
	add_child(camera)
	_box(Vector3(0, -0.25, 1.1), Vector3(11, 0.2, 10), Color("3d514a"))
	for x in range(-5, 6):
		_box(Vector3(x, -0.13, 1.1), Vector3(0.025, 0.02, 10), Color("61716a"))
	for z in range(-4, 7):
		_box(Vector3(0, -0.13, z), Vector3(11, 0.02, 0.025), Color("61716a"))
	for coupon in authority.coupons:
		coupon_meshes[str(coupon.name)] = _box(coupon.position, Vector3(0.5, 0.2, 0.5), Color("d4a96c"))
	for head in authority.heads:
		meshes.append(_box(Vector3.ZERO, Authority.HEAD_SIZE, Color("79c6bd")))
		beam_meshes.append(_box(Vector3.ZERO, Vector3(0.035, Authority.REACH, 0.035), Color("e0d18a")))
	if authority.variant == "shielded":
		_box(authority.shield.position, Vector3(5, 0.1, 4), Color("ba735d"))
	# Supports are presentation, never hidden colliders or inferred part costs.
	if authority.layout == "gantry":
		for z in [0, 3] if authority.grown else [0]:
			_box(Vector3(0, 1.7, z), Vector3(4.8, 0.12, 0.12), Color("b9a581"))
	else:
		for z in [0, 3] if authority.layout == "duplicate" else [0]:
			_box(Vector3(0, 0.8, z), Vector3(0.25, 1.6, 0.25), Color("b9a581"))
	_interface()
	_refresh()

func issue(intent: Dictionary) -> Dictionary:
	var result: Dictionary = authority.command(intent)
	_refresh()
	return result

func _process(delta: float) -> void:
	if auto_advance and authority.running and not authority.pending:
		elapsed += delta
		if elapsed >= 0.15:
			elapsed = 0.0
			issue({"action": "step"})
	camera.position = Vector3(0, 0.5, 1.0) + Vector3(sin(yaw), 0.85, cos(yaw)) * distance
	camera.look_at(Vector3(0, 0.5, 1.0))
	_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			issue({"action": "run", "active": not authority.running})
		elif event.keycode == KEY_N:
			issue({"action": "step"})
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.006
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(10, distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(24, distance + 1)

func _refresh() -> void:
	if stats == null:
		return
	var state: Dictionary = authority.projection()
	var physical: Dictionary = state.completed
	for index in range(meshes.size()):
		meshes[index].visible = not physical.is_empty()
		beam_meshes[index].visible = not physical.is_empty()
		if not physical.is_empty():
			var pose: Dictionary = physical.heads[index]
			var at := Vector3(pose.position[0], pose.position[1], pose.position[2])
			var direction := Vector3(pose.down[0], pose.down[1], pose.down[2])
			meshes[index].position = at
			beam_meshes[index].position = at + direction * (0.2 + Authority.REACH / 2.0)
	for name in coupon_meshes:
		coupon_meshes[name].material_override.albedo_color = Color("82c689") if name in physical.get("visited", []) else Color("d4a96c")
	stats.text = "%s\n%s\n%d source requests completed\n%d / %d top faces inspected\n%d heads · %d drive rigs" % [
		case_name.replace("_", " ").to_upper(), "NATIVE UPDATE PENDING" if state.pending else "RUNNING" if state.running else "PAUSED",
		physical.get("steps", 0), physical.get("visited", []).size(), state.coupon_count, state.head_count, state.drive_count]
	if not physical.is_empty():
		stats.text += "\nHead bounds x %.2f … %.2f\nHead bounds z %.2f … %.2f" % [physical.bounds.min[0], physical.bounds.max[0], physical.bounds.min[2], physical.bounds.max[2]]

func _box(at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	node.material_override = material
	node.position = at
	add_child(node)
	return node

func _interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "SPATIAL MECHANICS\nDownward inspection / immutable coupons"
	column.add_child(title)
	for label in ["Start / pause [Space]", "One drive request [N]"]:
		var button := Button.new()
		button.text = label
		button.custom_minimum_size = Vector2(280, 38)
		if label.begins_with("Start"):
			button.pressed.connect(func(): issue({"action": "run", "active": not authority.running}))
		else:
			button.pressed.connect(func(): issue({"action": "step"}))
		column.add_child(button)
	stats = Label.new()
	column.add_child(stats)
	var note := Label.new()
	note.text = "Space then N, or let the drive run.\nRight-drag orbit · Wheel zoom\n\nYellow: untouched top face\nGreen: native eligible encounter\n\nNon-consuming geometric probe.\nNo items, production or gravity dynamics."
	column.add_child(note)
