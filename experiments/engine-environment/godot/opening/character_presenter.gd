extends Node3D
## Input and confirmed actor presentation only. The native producer/server owns
## every physical pose; these meshes never grant construction permission.
const Geometry = preload("res://opening/site_geometry.gd")
static var mesh_cache: Dictionary = {}
static var material_cache: Dictionary = {}
static var cloth_normal: NoiseTexture2D

var host
var views: Dictionary = {}
var held_keys: Dictionary = {}
var jump_requested := false
var last_direction := Vector2.ZERO
var motion: Dictionary = {}
var visual_context := ""

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

func _process(delta: float) -> void:
	refresh(delta)

func _worker_box(size: Vector3) -> BoxMesh:
	var key := ["box", size]
	if not mesh_cache.has(key):
		var shape := BoxMesh.new()
		shape.size = size
		mesh_cache[key] = shape
	return mesh_cache[key]

func _worker_sphere(radius: float) -> SphereMesh:
	var key := ["sphere", radius]
	if not mesh_cache.has(key):
		var shape := SphereMesh.new()
		shape.radius = radius
		shape.height = radius * 2.0
		shape.radial_segments = 32
		shape.rings = 16
		mesh_cache[key] = shape
	return mesh_cache[key]

func _worker_capsule(radius: float, height: float) -> CapsuleMesh:
	var key := ["capsule", radius, height]
	if not mesh_cache.has(key):
		var shape := CapsuleMesh.new()
		shape.radius = radius
		shape.height = height
		shape.radial_segments = 24
		shape.rings = 8
		mesh_cache[key] = shape
	return mesh_cache[key]

func _worker_cylinder(top: float, bottom: float, height: float, segments: int = 24) -> CylinderMesh:
	var key := ["cylinder", top, bottom, height, segments]
	if not mesh_cache.has(key):
		var shape := CylinderMesh.new()
		shape.top_radius = top
		shape.bottom_radius = bottom
		shape.height = height
		shape.radial_segments = segments
		mesh_cache[key] = shape
	return mesh_cache[key]

func _worker_torso() -> ArrayMesh:
	if mesh_cache.has("torso"):
		return mesh_cache["torso"]
	var source := SphereMesh.new()
	source.radius = 1.0
	source.height = 2.0
	source.radial_segments = 32
	source.rings = 16
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var size := Vector3(0.22, 0.32, 0.1408)
	for n in range(vertices.size()):
		vertices[n] = vertices[n] * size
		normals[n] = (normals[n] / size).normalized()
		var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2]) * size
		tangent = (tangent - normals[n] * tangent.dot(normals[n])).normalized()
		tangents[n * 4] = tangent.x
		tangents[n * 4 + 1] = tangent.y
		tangents[n * 4 + 2] = tangent.z
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_cache["torso"] = mesh
	return mesh

func _worker_material(color: Color, roughness: float, metal: float, textile: bool = false) -> StandardMaterial3D:
	var key := [color, roughness, metal, textile]
	if not material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		material.metallic = metal
		if textile:
			if cloth_normal == null:
				var noise := FastNoiseLite.new()
				noise.seed = 1619
				noise.frequency = 0.3
				var texture := NoiseTexture2D.new()
				texture.width = 256
				texture.height = 256
				texture.seamless = true
				texture.as_normal_map = true
				texture.bump_strength = 0.4
				texture.noise = noise
				cloth_normal = texture
			material.normal_enabled = true
			material.normal_texture = cloth_normal
			material.normal_scale = 0.08
			material.uv1_scale = Vector3(5, 5, 1)
		material_cache[key] = material
	return material_cache[key]

func _worker_part(parent: Node3D, part_name: String, shape: Mesh, at: Vector3,
		color: Color, roughness: float = 0.8, metal: float = 0.0, textile: bool = false) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = shape
	part.position = at
	part.material_override = _worker_material(color, roughness, metal, textile)
	parent.add_child(part)
	return part

func _worker_joint(parent: Node3D, joint_name: String, at: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.name = joint_name
	joint.position = at
	parent.add_child(joint)
	return joint

func _worker_patch(parent: Node3D, part_name: String, bounds: Rect2, color: Color,
		steps_x: int = 8, steps_y: int = 4) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(steps_y):
		for x in range(steps_x):
			for corner in [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]:
				var uv := Vector2((x + corner.x) / steps_x, (y + corner.y) / steps_y)
				var at := bounds.position + bounds.size * uv
				var z := 0.1408 * sqrt(maxf(0.001, 1.0 - pow(at.x / 0.22, 2) - pow(at.y / 0.32, 2)))
				var normal := Vector3(at.x / (0.22 * 0.22), at.y / (0.32 * 0.32), z / (0.1408 * 0.1408)).normalized()
				surface.set_normal(normal)
				surface.set_uv(uv)
				surface.add_vertex(Vector3(at.x, at.y, z) + normal * 0.003)
	var patch := MeshInstance3D.new()
	patch.name = part_name
	patch.mesh = surface.commit()
	patch.material_override = _worker_material(color, 0.45, 0.05)
	parent.add_child(patch)

func _make_worker_visual() -> MeshInstance3D:
	# Every playable resource is constructed in this already captured script.
	var body := MeshInstance3D.new()
	body.name = "BodyView"
	body.mesh = _worker_torso()
	var cloth := Color("345d66")
	var rubber := Color("243039")
	var steel := Color("9caeac")
	var skin := Color(0.63, 0.43, 0.29)
	var helmet := Color("e79a39")
	var reflective := Color("d7ddbc")
	_worker_part(body, "Pelvis", _worker_box(Vector3(0.35, 0.16, 0.25)), Vector3(0, -0.31, 0), cloth, 0.88, 0, true)
	for side in [-1.0, 1.0]:
		var prefix := "Left" if side < 0.0 else "Right"
		var hip := _worker_joint(body, prefix + "Hip", Vector3(side * 0.105, -0.31, 0))
		_worker_part(hip, "Thigh", _worker_capsule(0.075, 0.28), Vector3(0, -0.13, 0), cloth, 0.88, 0, true)
		var knee := _worker_joint(hip, "Knee", Vector3(0, -0.26, 0))
		_worker_part(knee, "Shin", _worker_capsule(0.07, 0.265), Vector3(0, -0.12, 0), cloth, 0.88, 0, true)
		_worker_part(knee, "Kneepad", _worker_box(Vector3(0.13, 0.12, 0.025)), Vector3(0, -0.025, 0.075), rubber, 0.92)
		var ankle := _worker_joint(knee, "Ankle", Vector3(0, -0.245, 0))
		_worker_part(ankle, "BootUpper", _worker_box(Vector3(0.16, 0.1, 0.22)), Vector3(0, -0.02, 0.035), rubber, 0.92)
		_worker_part(ankle, "BootSole", _worker_box(Vector3(0.18, 0.04, 0.29)), Vector3(0, -0.06, 0.045), rubber, 0.98)
		var shoulder := _worker_joint(body, prefix + "Shoulder", Vector3(side * 0.24, 0.16, 0))
		_worker_part(shoulder, "UpperSleeve", _worker_capsule(0.06, 0.26), Vector3(0, -0.13, 0), cloth, 0.86, 0, true)
		var elbow := _worker_joint(shoulder, "Elbow", Vector3(0, -0.24, 0))
		_worker_part(elbow, "Forearm", _worker_capsule(0.052, 0.25), Vector3(0, -0.115, 0), cloth, 0.86, 0, true)
		_worker_part(elbow, "Glove", _worker_sphere(0.055), Vector3(0, -0.25, 0), rubber, 0.92)
		_worker_part(body, prefix + "Earmuff", _worker_sphere(0.045), Vector3(side * 0.18, 0.56, 0), rubber, 0.78)
		_worker_patch(body, prefix + "Harness", Rect2(side * 0.145 - 0.014, -0.18, 0.028, 0.35), Color("263e46"), 2, 12)
	_worker_part(body, "Neck", _worker_cylinder(0.065, 0.075, 0.12), Vector3(0, 0.36, 0), skin, 0.86)
	_worker_part(body, "Head", _worker_sphere(0.15), Vector3(0, 0.55, 0), skin, 0.86)
	var dome := _worker_part(body, "Helmet", _worker_sphere(0.205), Vector3(0, 0.73, 0), helmet, 0.43, 0.05)
	dome.scale.y = 0.82
	_worker_part(body, "HelmetBrim", _worker_cylinder(0.235, 0.235, 0.025, 32), Vector3(0, 0.69, 0.01), helmet, 0.43, 0.05)
	_worker_part(body, "HelmetRidge", _worker_box(Vector3(0.035, 0.045, 0.27)), Vector3(0, 0.85, 0), helmet, 0.43, 0.05)
	_worker_part(body, "VisorFrame", _worker_box(Vector3(0.265, 0.115, 0.035)), Vector3(0, 0.555, 0.147), rubber, 0.7)
	_worker_part(body, "SafetyVisor", _worker_box(Vector3(0.235, 0.085, 0.012)), Vector3(0, 0.555, 0.172), Color("1d414a"), 0.18, 0.1)
	_worker_part(body, "Belt", _worker_box(Vector3(0.37, 0.045, 0.27)), Vector3(0, -0.255, 0), Color("725438"), 0.75)
	_worker_part(body, "Buckle", _worker_box(Vector3(0.065, 0.05, 0.018)), Vector3(0, -0.255, 0.145), steel, 0.4, 0.8)
	_worker_patch(body, "UpperReflectiveBand", Rect2(-0.185, 0.12, 0.37, 0.035), reflective)
	_worker_patch(body, "LowerReflectiveBand", Rect2(-0.185, -0.12, 0.37, 0.035), reflective)
	_worker_part(body, "ToolPouch", _worker_box(Vector3(0.105, 0.145, 0.06)), Vector3(0.135, -0.3, 0.17), rubber, 0.92)
	_worker_part(body, "ToolPack", _worker_box(Vector3(0.28, 0.29, 0.1)), Vector3(0, -0.04, -0.17), cloth, 0.9, 0, true)
	return body

func _set_gait(body: Node3D, phase: float, weight: float) -> void:
	for pair in [["Left", 0.0], ["Right", PI]]:
		var prefix: String = pair[0]
		var swing := sin(phase + float(pair[1]))
		var hip: Node3D = body.get_node(prefix + "Hip")
		var knee: Node3D = hip.get_node("Knee")
		var ankle: Node3D = knee.get_node("Ankle")
		hip.rotation.x = -swing * 0.38 * weight
		knee.rotation.x = maxf(0.0, swing) * 0.5 * weight
		ankle.rotation.x = -(hip.rotation.x + knee.rotation.x)
		body.get_node(prefix + "Shoulder").rotation.x = swing * 0.28 * weight
		body.get_node(prefix + "Shoulder/Elbow").rotation.x = -0.12 * weight

func _animate_actor(actor: String, view: Node3D, at: Vector3, delta: float) -> void:
	var body: Node3D = view.get_node("BodyView")
	var previous: Dictionary = motion.get(actor, {"position": at, "phase": 0.0, "weight": 0.0, "age": 1.0})
	var displacement: Vector3 = at - previous.position
	var horizontal := Vector2(displacement.x, displacement.z)
	if displacement.length() > 1.0:
		previous = {"position": at, "phase": 0.0, "weight": 0.0, "age": 1.0}
		body.rotation.y = 0
	else:
		previous.phase += horizontal.length() * TAU / 0.9
		previous.age = 0.0 if horizontal.length() > 0.00001 else previous.age + delta
		previous.weight = move_toward(float(previous.weight), 1.0 if previous.age < 0.12 else 0.0, delta * 6.0)
		if horizontal.length() > 0.00001:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(horizontal.x, horizontal.y), minf(1.0, delta * 12.0))
		previous.position = at
	motion[actor] = previous
	_set_gait(body, float(previous.phase), float(previous.weight))

func _new_view(actor: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Character" + actor
	root.set_meta("actor", actor)
	var mesh := _make_worker_visual()
	mesh.material_override = _worker_material(Color("c87847") if actor == host.client else Color("50899a"), 0.85, 0, true)
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

func refresh(delta: float = 0.0) -> void:
	if host == null:
		return
	var context: String = str(host.state.get("context", ""))
	if context != visual_context:
		visual_context = context
		motion.clear()
	var actors: Dictionary = host.state.get("actors", {})
	for actor in views.keys():
		if not actors.has(actor):
			var old: Node3D = views[actor]
			remove_child(old)
			old.queue_free()
			views.erase(actor)
			motion.erase(actor)
	for actor in actors:
		if not views.has(actor):
			views[actor] = _new_view(actor)
		var data: Dictionary = actors[actor]
		var view: Node3D = views[actor]
		view.visible = data.get("ready", false) and Geometry.valid_position(data.get("position"))
		if view.visible:
			var at: Array = data.position
			view.position = Vector3(at[0], at[1], at[2])
			if not motion.has(actor):
				var body: Node3D = view.get_node("BodyView")
				body.rotation.y = 0
				_set_gait(body, 0, 0)
			if delta > 0.0:
				_animate_actor(actor, view, view.position, delta)
		else:
			motion.erase(actor)
	if not host.explanation_open and actors.has(host.client) and Geometry.valid_position(actors[host.client].get("position")):
		var at: Array = actors[host.client].position
		host.focus = Vector3(at[0], at[1] + 0.3, at[2])
		host._update_camera()
