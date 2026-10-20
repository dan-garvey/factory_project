extends Node3D
## Input and confirmed actor presentation only. The native producer/server owns
## every physical pose; these meshes never grant construction permission.
const Geometry = preload("res://opening/site_geometry.gd")

var host
var views: Dictionary = {}
var held_keys: Dictionary = {}
var jump_requested := false
var last_direction := Vector2.ZERO

func configure(view) -> void:
	host = view

func _ready() -> void:
	get_window().focus_exited.connect(release)
	refresh()

func release() -> void:
	held_keys.clear()
	jump_requested = false
	last_direction = Vector2.ZERO
	if host != null:
		host._release_character_input()

func _input(event: InputEvent) -> void:
	if host == null or host.explanation_open or not event is InputEventKey:
		return
	if event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
		if event.pressed and not event.echo:
			held_keys[event.keycode] = true
		elif not event.pressed:
			held_keys.erase(event.keycode)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE:
		if event.pressed and not event.echo:
			jump_requested = true
		# Consume both edges so a focused GUI button cannot also activate.
		get_viewport().set_input_as_handled()

func _physics_process(_delta: float) -> void:
	if host == null or not host._can_control_character():
		return
	var screen := Vector2(float(held_keys.has(KEY_D)) - float(held_keys.has(KEY_A)),
		float(held_keys.has(KEY_S)) - float(held_keys.has(KEY_W)))
	var right := Vector3(cos(host.orbit_yaw), 0, -sin(host.orbit_yaw))
	var back := Vector3(sin(host.orbit_yaw), 0, cos(host.orbit_yaw))
	var desired := right * screen.x + back * screen.y
	last_direction = Vector2(desired.x, desired.z).limit_length(1.0)
	host._send_character_input(last_direction, jump_requested)
	jump_requested = false

func _process(_delta: float) -> void:
	refresh()

func _worker_box(size: Vector3) -> BoxMesh:
	var shape := BoxMesh.new()
	shape.size = size
	return shape

func _worker_sphere(radius: float) -> SphereMesh:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 16
	shape.rings = 8
	return shape

func _worker_cylinder(top: float, bottom: float, height: float, segments: int = 16) -> CylinderMesh:
	var shape := CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = bottom
	shape.height = height
	shape.radial_segments = segments
	return shape

func _worker_part(parent: Node3D, part_name: String, shape: Mesh, at: Vector3,
		color: Color, roughness: float = 0.8, metal: float = 0.0) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = shape
	part.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metal
	part.material_override = material
	parent.add_child(part)

func _make_worker_visual() -> MeshInstance3D:
	# Keep the playable visual in this already-captured script. The optional
	# preview scenes are not dependencies of either public launcher.
	var body := MeshInstance3D.new()
	body.name = "BodyView"
	body.mesh = _worker_box(Vector3(0.44, 0.64, 0.28))
	var cloth := Color(0.16, 0.32, 0.35)
	var rubber := Color(0.075, 0.095, 0.11)
	var skin := Color(0.63, 0.43, 0.29)
	var helmet := Color(0.92, 0.56, 0.18)
	var reflective := Color(0.84, 0.86, 0.7)
	_worker_part(body, "Pelvis", _worker_box(Vector3(0.37, 0.16, 0.26)), Vector3(0, -0.33, 0), rubber, 0.92)
	for direction in [-1.0, 1.0]:
		var side: float = direction
		var prefix := "Left" if side < 0.0 else "Right"
		_worker_part(body, prefix + "Leg", _worker_box(Vector3(0.16, 0.44, 0.18)), Vector3(side * 0.105, -0.56, 0), cloth, 0.88)
		_worker_part(body, prefix + "Boot", _worker_box(Vector3(0.2, 0.1, 0.29)), Vector3(side * 0.105, -0.825, 0.035), rubber, 0.92)
		_worker_part(body, prefix + "Arm", _worker_box(Vector3(0.11, 0.46, 0.14)), Vector3(side * 0.24, 0.02, 0), cloth, 0.88)
		_worker_part(body, prefix + "Glove", _worker_sphere(0.055), Vector3(side * 0.24, -0.25, 0.015), rubber, 0.92)
	_worker_part(body, "Neck", _worker_cylinder(0.075, 0.085, 0.12, 12), Vector3(0, 0.37, 0), skin, 0.86)
	_worker_part(body, "Head", _worker_sphere(0.16), Vector3(0, 0.56, 0), skin, 0.86)
	_worker_part(body, "Helmet", _worker_cylinder(0.16, 0.21, 0.16), Vector3(0, 0.76, 0), helmet, 0.43, 0.12)
	_worker_part(body, "HelmetBrim", _worker_cylinder(0.24, 0.24, 0.035, 20), Vector3(0, 0.69, 0.01), helmet, 0.43, 0.12)
	_worker_part(body, "SafetyVisor", _worker_box(Vector3(0.235, 0.085, 0.035)), Vector3(0, 0.575, 0.151), Color(0.08, 0.16, 0.18), 0.18, 0.2)
	_worker_part(body, "Belt", _worker_box(Vector3(0.45, 0.055, 0.295)), Vector3(0, -0.255, 0), Color(0.52, 0.36, 0.17), 0.42, 0.7)
	_worker_part(body, "UpperReflectiveBand", _worker_box(Vector3(0.425, 0.045, 0.012)), Vector3(0, 0.135, 0.146), reflective, 0.48)
	_worker_part(body, "LowerReflectiveBand", _worker_box(Vector3(0.425, 0.045, 0.012)), Vector3(0, -0.1, 0.146), reflective, 0.48)
	_worker_part(body, "ToolPouch", _worker_box(Vector3(0.11, 0.16, 0.065)), Vector3(0.145, -0.3, 0.18), rubber, 0.92)
	return body

func _new_view(actor: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Character" + actor
	root.set_meta("actor", actor)
	var mesh := _make_worker_visual()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c87847") if actor == host.client else Color("50899a")
	material.roughness = 0.8
	mesh.material_override = material
	root.add_child(mesh)
	var label := Label3D.new()
	label.text = actor + (" · YOU" if actor == host.client else "")
	label.position = Vector3(0, Geometry.CAPSULE_HEIGHT / 2 + 0.3, 0)
	label.font_size = 30
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
	add_child(root)
	return root

func refresh() -> void:
	if host == null:
		return
	var actors: Dictionary = host.state.get("actors", {})
	for actor in views.keys():
		if not actors.has(actor):
			var old: Node3D = views[actor]
			remove_child(old)
			old.queue_free()
			views.erase(actor)
	for actor in actors:
		if not views.has(actor):
			views[actor] = _new_view(actor)
		var data: Dictionary = actors[actor]
		var view: Node3D = views[actor]
		view.visible = data.get("ready", false) and Geometry.valid_position(data.get("position"))
		if view.visible:
			var at: Array = data.position
			view.position = Vector3(at[0], at[1], at[2])
	if not host.explanation_open and actors.has(host.client) and Geometry.valid_position(actors[host.client].get("position")):
		var at: Array = actors[host.client].position
		host.focus = Vector3(at[0], at[1] + 0.3, at[2])
		host._update_camera()
