extends Node3D
## Input and confirmed actor presentation only. The native producer/server owns
## every physical pose; these meshes never grant construction permission.
const Geometry = preload("res://opening/site_geometry.gd")
const Surface = preload("res://opening/site_surface.gd")
const MULTITOOL = preload("res://opening/assets/multitool/multitool.tscn")
const ADULT_ASSETS := "res://opening/assets/worker/"
const SECOND_ADULT_ASSETS := "res://opening/assets/worker-second/"
const GAIT_CYCLE_DISTANCE := 2.30
const WALK_CYCLE_DISTANCE := 1.30
const FULL_WALK_POSE_SPEED := 1.05
const FULL_GAIT_SPEED := 2.4
const RUN_BLEND_START := 1.15
const RUN_BLEND_END := 2.35
const STOP_HOLD_SECONDS := 2.0 / 60.0
const STALE_SAMPLE_SETTLE_SECONDS := 0.15
const TAKEOFF_DELTA := 0.025
const DROP_DELTA := 0.075
const LANDING_SECONDS := 0.32
const DISCONTINUITY_HORIZONTAL := 2.0
const DISCONTINUITY_VERTICAL := 1.8
static var mesh_cache: Dictionary = {}
static var material_cache: Dictionary = {}
static var cloth_normal: NoiseTexture2D
static var adult_template: PackedScene
static var second_adult_template: PackedScene
static var adult_run_clip: Animation
static var adult_run_root_track := -1
static var adult_run_root_reference := Vector3.ZERO
static var adult_walk_clip: Animation
static var adult_walk_root_track := -1
static var adult_walk_root_reference := Vector3.ZERO
static var second_adult_run_clip: Animation
static var second_adult_run_root_track := -1
static var second_adult_run_root_reference := Vector3.ZERO
static var second_adult_walk_clip: Animation
static var second_adult_walk_root_track := -1
static var second_adult_walk_root_reference := Vector3.ZERO
static var multitool_hand_meshes: Dictionary = {}

var host
var views: Dictionary = {}
var held_keys: Dictionary = {}
var jump_requested := false
var last_direction := Vector2.ZERO
var motion: Dictionary = {}
var native_sample_frames: Dictionary = {}
var visual_context := ""
var eye_multitool: Node3D

func configure(view) -> void:
	host = view

func observe_native_sample(actor: String, sample: Dictionary) -> void:
	# This is presentation timing only; the model still owns the confirmed pose.
	native_sample_frames[actor] = {"epoch": sample.native_epoch,
		"physics_frame": sample.physics_frame,
		"on_floor": sample.get("on_floor") if typeof(sample.get("on_floor")) == TYPE_BOOL else null}

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

func _exit_tree() -> void:
	if is_instance_valid(eye_multitool):
		eye_multitool.queue_free()

func _multitool_frame(body: Node3D) -> Transform3D:
	# Rocketbox's hand X points along the fingers, Y out of the palm and Z
	# across it. Seat the grip inside the curled fingers, and keep the authored
	# tool in metres despite the actor's fit scale.
	var fitted_scale: float = body.get_node("AdultHuman").scale.x
	return Transform3D(Basis(Vector3.DOWN, Vector3.BACK, Vector3.LEFT).scaled(Vector3.ONE / fitted_scale),
		Vector3(0.085, 0.018, 0.012))

func _badge_quad(builder: SurfaceTool, center: Vector3, height: float,
		width: float, tint: Color, angle: float = 0.0) -> void:
	var rotated := Basis(Vector3.UP, angle)
	var a := center + rotated * Vector3(-height * 0.5, 0.0, -width * 0.5)
	var b := center + rotated * Vector3(-height * 0.5, 0.0, width * 0.5)
	var c := center + rotated * Vector3(height * 0.5, 0.0, width * 0.5)
	var d := center + rotated * Vector3(height * 0.5, 0.0, -width * 0.5)
	builder.set_color(tint)
	builder.set_normal(Vector3.UP)
	for point in [a, b, c, a, c, d]:
		builder.add_vertex(point)

func _attach_field_badge(body: Node3D, skeleton: Skeleton3D) -> bool:
	if skeleton.find_bone("Bip01 Spine2") < 0:
		return false
	var attachment := BoneAttachment3D.new()
	attachment.name = "FieldSuitMark"
	attachment.bone_name = "Bip01 Spine2"
	skeleton.add_child(attachment)
	attachment.owner = body
	attachment.set_meta("presentation_only", true)
	# On this sourced rig, local X rises, Y faces the jacket front and Z points
	# toward the actor's left. Keep the mark on the upper torso during gait.
	var center := Vector3(0.04, 0.132, 0.092)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	_badge_quad(builder, center, 0.050, 0.080, Color("2a211d"))
	_badge_quad(builder, center + Vector3(0.0, 0.001, 0.0),
		0.044, 0.074, Color("6f5946"))
	# The provisional field-package mark is a small angular M, not a screen
	# overlay or another material/interaction state.
	for side in [-1.0, 1.0]:
		_badge_quad(builder, center + Vector3(0.0, 0.002, side * 0.022),
			0.027, 0.004, Color("ba9d76"))
		_badge_quad(builder, center + Vector3(0.003, 0.002, side * 0.009),
			0.023, 0.004, Color("ba9d76"), side * 0.48)
	var mark := MeshInstance3D.new()
	mark.name = "WovenInsignia"
	mark.mesh = builder.commit()
	var finish := StandardMaterial3D.new()
	finish.vertex_color_use_as_albedo = true
	finish.cull_mode = BaseMaterial3D.CULL_DISABLED
	finish.roughness = 0.9
	mark.material_override = finish
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attachment.add_child(mark)
	mark.owner = body
	return true

func _attach_multitool(body: Node3D) -> BoneAttachment3D:
	var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
	if skeleton.find_bone("Bip01 R Hand") < 0:
		push_error("The qualified worker needs its right-hand tool attachment.")
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "MultitoolAttachment"
	attachment.bone_name = "Bip01 R Hand"
	skeleton.add_child(attachment)
	var tool := MULTITOOL.instantiate() as Node3D
	tool.transform = _multitool_frame(body)
	attachment.add_child(tool)
	body.set_meta("multitool_attachment", body.get_path_to(attachment))
	return attachment

func _hold_multitool(body: Node3D) -> void:
	# Only the right-hand grip changes. Arm, gait, source pose and native body
	# remain independent of the carried presentation object.
	var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
	for finger: Dictionary in body.get_meta("grounded_fingers"):
		var index: int = finger.index
		var label := skeleton.get_bone_name(index)
		if not label.begins_with("Bip01 R Finger"):
			continue
		var segment := 0 if label.length() == "Bip01 R Finger1".length() else int(label.right(1))
		var angle: float = [1.35, 1.15, 0.65][segment]
		skeleton.set_bone_pose_rotation(index, (finger.base * Quaternion(Vector3.BACK, angle)).normalized())

func _bake_multitool_hand(body: Node3D) -> ArrayMesh:
	var source: String = body.get_meta("source", "")
	if multitool_hand_meshes.has(source):
		return multitool_hand_meshes[source]
	var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
	var frames := _adult_pose_frames(skeleton)
	var to_tool := (frames[skeleton.find_bone("Bip01 R Hand")] * _multitool_frame(body)).affine_inverse()
	var mesh: MeshInstance3D
	for candidate: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if candidate.skin != null:
			mesh = candidate
			break
	if mesh == null:
		return null
	var binds: Array[Transform3D] = []
	var hand_binds: Array[bool] = []
	for bind in range(mesh.skin.get_bind_count()):
		var index: int = mesh.skin.get_bind_bone(bind)
		if index < 0:
			index = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		if index < 0 or index >= frames.size():
			return null
		var label := skeleton.get_bone_name(index)
		hand_binds.append(label == "Bip01 R Hand" or label.begins_with("Bip01 R Finger"))
		binds.append(to_tool * frames[index] * mesh.skin.get_bind_pose(bind))
	var result := ArrayMesh.new()
	for surface in range(mesh.mesh.get_surface_count()):
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var stride: int = bones.size() / vertices.size()
		var selected := PackedByteArray()
		var posed := PackedVector3Array()
		var posed_normals := PackedVector3Array()
		selected.resize(vertices.size())
		posed.resize(vertices.size())
		posed_normals.resize(vertices.size())
		for vertex in range(vertices.size()):
			var hand_weight := 0.0
			for influence in range(stride):
				var offset := vertex * stride + influence
				var weight: float = weights[offset]
				if weight <= 0.0:
					continue
				var bind: int = bones[offset]
				posed[vertex] += binds[bind] * vertices[vertex] * weight
				posed_normals[vertex] += binds[bind].basis * normals[vertex] * weight
				if hand_binds[bind]:
					hand_weight += weight
			selected[vertex] = 1 if hand_weight >= 0.35 else 0
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count := 0
		for triangle in range(0, indices.size(), 3):
			if not selected[indices[triangle]] or not selected[indices[triangle + 1]] or not selected[indices[triangle + 2]]:
				continue
			for corner in range(3):
				var vertex: int = indices[triangle + corner]
				builder.set_normal(posed_normals[vertex].normalized())
				builder.set_uv(uv[vertex])
				builder.add_vertex(posed[vertex])
				count += 1
		if count > 0:
			builder.index()
			builder.generate_tangents()
			builder.commit(result)
			result.surface_set_material(result.get_surface_count() - 1, mesh.mesh.surface_get_material(surface))
	if result.get_surface_count() == 0:
		return null
	multitool_hand_meshes[source] = result
	return result

func _refresh_multitools() -> void:
	var equipped: bool = host.state.get("options", {}).get("native", false) and host.state.has("hand_sources")
	for actor: String in views:
		var body: Node3D = views[actor].get_node("BodyView")
		if not equipped and not body.has_meta("multitool_attachment"):
			continue
		if not body.has_meta("multitool_attachment") and _attach_multitool(body) == null:
			get_tree().quit(1)
			return
		var attachment: BoneAttachment3D = body.get_node(body.get_meta("multitool_attachment"))
		attachment.visible = equipped
		if equipped:
			_hold_multitool(body)
	var local_ready: bool = host.state.get("actors", {}).get(host.client, {}).get("ready", false)
	var show_eye: bool = equipped and local_ready and host.distance <= 1.0 and views.has(host.client)
	if show_eye and eye_multitool == null:
		var body: Node3D = views[host.client].get_node("BodyView")
		var hand := _bake_multitool_hand(body)
		if hand == null:
			push_error("The qualified worker needs a valid first-person hand.")
			get_tree().quit(1)
			return
		eye_multitool = MULTITOOL.instantiate() as Node3D
		eye_multitool.name = "FirstPersonMultitool"
		var hand_view := MeshInstance3D.new()
		hand_view.name = "QualifiedRightHand"
		hand_view.mesh = hand
		eye_multitool.add_child(hand_view)
		# Keep the sourced fingers and grip in view without covering the center aim.
		eye_multitool.position = Vector3(0.19, -0.10, -0.72)
		eye_multitool.rotation_degrees = Vector3(18, 20, -8)
		for part: MeshInstance3D in eye_multitool.find_children("*", "MeshInstance3D", true, false):
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.camera.add_child(eye_multitool)
	if eye_multitool != null:
		eye_multitool.visible = show_eye

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

func _make_legacy_worker_visual() -> MeshInstance3D:
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

func _adult_image(path: String) -> Image:
	var image: Image = null
	var imported_ready := true
	var descriptor_path := path + ".import"
	if FileAccess.file_exists(descriptor_path):
		var descriptor := ConfigFile.new()
		if descriptor.load(descriptor_path) != OK:
			return null
		var cooked: Variant = descriptor.get_value("remap", "path", "")
		if typeof(cooked) != TYPE_STRING or cooked.is_empty():
			return null
		# A tracked descriptor can outlive its generated cache in a fresh
		# checkout. Avoid a failing ResourceLoader.load before decoding the
		# fixed captured source image directly.
		imported_ready = FileAccess.file_exists(cooked) or ResourceLoader.exists(cooked, "Texture2D")
	if imported_ready and ResourceLoader.exists(path, "Texture2D"):
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		image = texture.get_image() if texture != null else null
	elif FileAccess.file_exists(path):
		# The new garment also has to render in a fresh checkout before an
		# editor import. Decode only the captured image formats from file bytes;
		# exported projects use the imported Texture2D path above.
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return null
		var bytes := file.get_buffer(file.get_length())
		file.close()
		image = Image.new()
		var decoded := ERR_FILE_UNRECOGNIZED
		match path.get_extension().to_lower():
			"png": decoded = image.load_png_from_buffer(bytes)
			"webp": decoded = image.load_webp_from_buffer(bytes)
		if decoded != OK:
			return null
	if image == null or image.is_empty():
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	return image

func _adult_material(material_name: String, asset_root: String = ADULT_ASSETS) -> Material:
	var stem: String = {"f004_body": "body", "f004_head": "head", "f004_opacity": "opacity",
		"m009_body": "body", "m009_head": "head", "m009_opacity": "opacity"}.get(material_name, "")
	if stem.is_empty():
		return null
	var color := _adult_image(asset_root + stem + "_color.webp")
	if color == null or color.is_empty():
		return null
	color.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.resource_name = material_name
	material.albedo_texture = ImageTexture.create_from_image(color)
	material.roughness = 0.65 if stem == "head" else 0.8
	if stem == "opacity":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.4
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.metallic_specular = 0.0
	else:
		var normal := _adult_image(asset_root + stem + "_normal.webp")
		if normal == null or normal.is_empty():
			return null
		normal.generate_mipmaps(true)
		material.normal_enabled = true
		material.normal_texture = ImageTexture.create_from_image(normal)
	return material

func _adult_bone_delta(body: Node3D, key: String, rotation: Quaternion) -> void:
	var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
	var bone: Dictionary = body.get_meta("rig")[key]
	# Convert a presentation-space rotation into this source rig's local frame.
	# Preserve its original local pose and all bind matrices; never move a body.
	skeleton.set_bone_pose_rotation(bone.index,
		(bone.rotation * bone.space.inverse() * rotation * bone.space).normalized())

func _set_adult_air_and_landing(body: Node3D, air: float,
		vertical_speed: float, impact: float, landing_progress: float = 1.0,
		landing_stride: float = 1.0, landing_approach: float = 0.0) -> void:
	# The captured run supplies grounded motion. These poses blend from its
	# lowered-arm rest stance when confirmed height changes show a jump or fall.
	var rise := clampf((vertical_speed + 0.4) / 5.0, 0.0, 1.0)
	var fall := clampf((-vertical_speed - 0.4) / 5.2, 0.0, 1.0)
	# Confirmed horizontal travel gives the leading foot room to catch the
	# load; an in-place jump settles both boots beneath the body.
	var contact_stride := clampf(landing_stride, 0.0, 1.0)
	# A moving leading foot reaches ahead and stays low while the confirmed
	# actor descends, so contact does not invent the whole step in one sample.
	var pre_contact := clampf(landing_approach, 0.0, 1.0) * contact_stride * air
	# Start the opposite arm's counterbalance with the lead boot's final reach;
	# the other arm stays close instead of forming a two-handed brace.
	# The leading boot reaches support promptly while the torso continues to
	# absorb the load. Do not slow the established contact step with the torso.
	var foot_load := smoothstep(0.0, 0.16, landing_progress) * \
		pow(1.0 - clampf(landing_progress, 0.0, 1.0), 1.7)
	var plant := foot_load * (1.0 - smoothstep(0.12, 0.60, landing_progress)) * contact_stride
	# The lead boot must take support promptly, but the torso follows the load
	# over the next few rendered samples instead of snapping into its brace.
	var torso_brace := foot_load * smoothstep(0.0, 0.35, landing_progress) * \
		(1.0 - smoothstep(0.20, 0.70, landing_progress)) * contact_stride
	# The leading left boot takes a moving landing first. The opposite arm
	# catches that rotation; an in-place landing keeps its symmetric balance.
	var arm_balance := contact_stride * impact
	for pair in [["L", 1.0], ["R", -1.0]]:
		var side: String = pair[0]
		var sign: float = pair[1]
		var air_asymmetry := sign * air
		# The running takeoff keeps a leading knee up and a trailing leg back.
		# Both legs fold under the body near the apex and reach down on descent.
		var hip := ((-0.42 - 0.15 * rise + 0.30 * fall
			- 0.35 * sign * rise - 0.08 * sign * (1.0 - rise) * (1.0 - fall)) * air
			- (0.48 + 0.08 * sign * contact_stride) * impact
			+ (-0.24 if side == "L" else 0.32) * plant
			- (0.25 * pre_contact if side == "L" else 0.0))
		var knee := ((0.90 + 0.10 * rise - 0.55 * fall
			+ 0.35 * sign * rise + 0.08 * sign * (1.0 - rise) * (1.0 - fall)) * air
			+ (1.02 + 0.08 * sign * contact_stride) * impact
			+ (-0.54 if side == "L" else 0.32) * plant
			- (0.25 * pre_contact if side == "L" else 0.0))
		_adult_bone_delta(body, side + " Thigh", Quaternion(Vector3.RIGHT, hip))
		_adult_bone_delta(body, side + " Calf", Quaternion(Vector3.RIGHT, knee))
		_adult_bone_delta(body, side + " Foot", Quaternion(Vector3.RIGHT,
			-(hip + knee) * (1.0 - 0.25 * air)))
		# The takeoff arm drive settles into lateral balance before reaching out
		# for the landing. Avoid holding both forearms straight ahead in flight.
		var stance := Quaternion(Vector3.BACK,
			-sign * (0.72 + 0.20 * air * (1.0 - rise) * (1.0 - fall)))
		var arm_air := (0.10 - 1.0 * rise - 0.30 * fall) * air
		_adult_bone_delta(body, side + " UpperArm", Quaternion(Vector3.RIGHT,
			arm_air - 0.48 * impact + 0.60 * sign * rise * air
			+ 0.18 * air_asymmetry + 0.48 * sign * arm_balance
			- (0.18 - 0.12 * sign) * pre_contact) * stance)
		_adult_bone_delta(body, side + " Forearm", Quaternion(Vector3.RIGHT,
			(-0.30 - 0.22 * rise - 0.20 * fall) * air - 0.78 * impact
			+ 0.22 * sign * arm_balance
			- (0.12 - 0.06 * sign) * pre_contact))
	_adult_bone_delta(body, "Spine1", Quaternion(Vector3.RIGHT,
		(0.18 * rise + 0.08 * fall) * air + 0.30 * impact + 0.42 * torso_brace
		+ 0.10 * pre_contact))
	_adult_bone_delta(body, "Spine2", Quaternion(Vector3.RIGHT,
		0.12 * impact + 0.18 * torso_brace))
	_adult_bone_delta(body, "Neck", Quaternion(Vector3.RIGHT,
		(0.06 * rise - 0.08 * fall) * air - 0.22 * impact - 0.16 * torso_brace
		- 0.05 * pre_contact))
	# Compression moves only the skinned view; the Character root is unchanged.
	body.position.y = -0.065 * impact

static func _adult_clip_influence(key: String, strength: float) -> float:
	if key in ["Pelvis", "Spine", "Spine1", "Spine2"]:
		return strength * 0.55
	if key in ["Neck", "Head"]:
		return strength * 0.4
	return strength

func _adult_joint(body: Node3D, skeleton: Skeleton3D, index: int) -> Vector3:
	var to_body: Transform3D = body.global_transform.affine_inverse() * skeleton.global_transform
	return to_body * skeleton.get_bone_global_pose(index).origin

func _adult_joint_frame(body: Node3D, skeleton: Skeleton3D, index: int) -> Quaternion:
	var to_body: Transform3D = body.global_transform.affine_inverse() * skeleton.global_transform
	return (to_body.basis * skeleton.get_bone_global_pose(index).basis).orthonormalized().get_rotation_quaternion()

func _adult_turn_joint(body: Node3D, skeleton: Skeleton3D, index: int,
		rotation: Quaternion) -> void:
	var frame := _adult_joint_frame(body, skeleton, index)
	skeleton.set_bone_pose_rotation(index,
		(skeleton.get_bone_pose_rotation(index) * frame.inverse() * rotation * frame).normalized())

func _adult_correct_grounded_knees(body: Node3D, skeleton: Skeleton3D) -> void:
	# The source calf channels hyperextend after retargeting. Keep the captured
	# ankle path and foot orientation, while placing each bent knee on the
	# forward solution of its two-bone reach circle in the character's plane.
	for side in ["L", "R"]:
		skeleton.force_update_all_bone_transforms()
		var thigh := skeleton.find_bone("Bip01 " + side + " Thigh")
		var calf := skeleton.find_bone("Bip01 " + side + " Calf")
		var foot := skeleton.find_bone("Bip01 " + side + " Foot")
		var hip_at := _adult_joint(body, skeleton, thigh)
		var knee_at := _adult_joint(body, skeleton, calf)
		var ankle_at := _adult_joint(body, skeleton, foot)
		var old_foot_frame := _adult_joint_frame(body, skeleton, foot)
		var reach := ankle_at - hip_at
		var distance := reach.length()
		if distance < 0.01:
			continue
		var along := reach / distance
		var forward := (Vector3.BACK - along * along.dot(Vector3.BACK)).normalized()
		var knee_offset := (knee_at - hip_at).dot(forward)
		if knee_offset >= -0.002:
			continue
		var upper := hip_at.distance_to(knee_at)
		var lower := knee_at.distance_to(ankle_at)
		var advance := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
		var height := sqrt(maxf(0.0, upper * upper - advance * advance))
		var target_knee := hip_at + along * advance + forward * height
		var amount := smoothstep(0.0, 0.065, -knee_offset)
		var upper_turn := Quaternion((knee_at - hip_at).normalized(),
			(target_knee - hip_at).normalized())
		_adult_turn_joint(body, skeleton, thigh, Quaternion.IDENTITY.slerp(upper_turn, amount))
		skeleton.force_update_all_bone_transforms()
		var new_knee := _adult_joint(body, skeleton, calf)
		var new_ankle := _adult_joint(body, skeleton, foot)
		var lower_turn := Quaternion((new_ankle - new_knee).normalized(),
			(ankle_at - new_knee).normalized())
		_adult_turn_joint(body, skeleton, calf, lower_turn)
		skeleton.force_update_all_bone_transforms()
		var foot_turn := old_foot_frame * _adult_joint_frame(body, skeleton, foot).inverse()
		_adult_turn_joint(body, skeleton, foot, foot_turn)

func _adult_hold_contact_toe(body: Node3D, skeleton: Skeleton3D,
		anchor: Vector3, influence: float, toe_off_lift: float = 0.0,
		side: String = "L") -> void:
	# Place only the visual boot at its contact point. The hip, knee and ankle
	# retain their lengths; the native actor never moves.
	var thigh := skeleton.find_bone("Bip01 " + side + " Thigh")
	var calf := skeleton.find_bone("Bip01 " + side + " Calf")
	var foot := skeleton.find_bone("Bip01 " + side + " Foot")
	var toe := skeleton.find_bone("Bip01 " + side + " Toe0")
	skeleton.force_update_all_bone_transforms()
	var hip_at := _adult_joint(body, skeleton, thigh)
	var knee_at := _adult_joint(body, skeleton, calf)
	var ankle_at := _adult_joint(body, skeleton, foot)
	var toe_at := _adult_joint(body, skeleton, toe)
	var foot_frame := _adult_joint_frame(body, skeleton, foot)
	var upper := hip_at.distance_to(knee_at)
	var lower := knee_at.distance_to(ankle_at)
	var target_ankle := ankle_at + (body.to_local(anchor) - toe_at) * influence \
		+ Vector3.UP * toe_off_lift
	var reach := target_ankle - hip_at
	var distance := reach.length()
	if distance < 0.01:
		return
	var along := reach / distance
	distance = clampf(distance, absf(upper - lower) + 0.005, upper + lower - 0.005)
	target_ankle = hip_at + along * distance
	var forward := (Vector3.BACK - along * along.dot(Vector3.BACK)).normalized()
	var advance := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper * upper - advance * advance))
	var target_knee := hip_at + along * advance + forward * height
	_adult_turn_joint(body, skeleton, thigh,
		Quaternion((knee_at - hip_at).normalized(), (target_knee - hip_at).normalized()))
	skeleton.force_update_all_bone_transforms()
	var new_knee := _adult_joint(body, skeleton, calf)
	var new_ankle := _adult_joint(body, skeleton, foot)
	_adult_turn_joint(body, skeleton, calf,
		Quaternion((new_ankle - new_knee).normalized(), (target_ankle - new_knee).normalized()))
	skeleton.force_update_all_bone_transforms()
	_adult_turn_joint(body, skeleton, foot,
		foot_frame * _adult_joint_frame(body, skeleton, foot).inverse())

func _adult_lift_landing_swing_toe(body: Node3D, skeleton: Skeleton3D,
		progress: float, stride: float, fast_handoff: float) -> void:
	# Lift the trailing boot as the anchored leading leg takes the impact.
	var lift := 0.12 * clampf(stride, 0.0, 1.0) * smoothstep(0.0, 0.35, progress) \
		* (1.0 - smoothstep(lerpf(0.70, 0.50, fast_handoff),
			lerpf(0.95, 0.80, fast_handoff), progress))
	if lift <= 0.001:
		return
	skeleton.force_update_all_bone_transforms()
	var swing_toe := body.to_global(_adult_joint(body, skeleton,
		skeleton.find_bone("Bip01 R Toe0")))
	_adult_hold_contact_toe(body, skeleton, swing_toe, 1.0, lift, "R")

func _adult_hold_grounded_toe(body: Node3D, previous: Dictionary, delta: float,
		run_mix: float) -> void:
	# The walk and run clips share a single support boot through their blend.
	# The confirmed actor owns travel; this anchor only prevents visual skating.
	var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
	skeleton.force_update_all_bone_transforms()
	var toes := {}
	var clearance := {}
	for side in ["L", "R"]:
		var toe: Vector3 = body.to_global(_adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 " + side + " Toe0")))
		toes[side] = toe
		clearance[side] = toe.y - Surface.height_at(toe.x, toe.z)
	if not is_finite(clearance.L) or not is_finite(clearance.R):
		previous.erase("support_contact_side")
		previous.erase("support_contact_toe")
		previous.erase("support_contact_age")
		previous.erase("release_contact_side")
		previous.erase("release_contact_toe")
		previous.erase("release_contact_age")
		previous.erase("release_contact_strength")
		return
	var walking_hold := 1.0 - smoothstep(0.25, 0.75, run_mix)
	var side: String = previous.get("support_contact_side", "")
	var handoff_side := ""
	if side != "" and walking_hold > 0.99 \
			and float(previous.support_contact_age) > 0.25:
		var incoming := "R" if side == "L" else "L"
		if clearance[incoming] < 0.055 and \
				body.to_local(toes[incoming]).z > body.to_local(toes[side]).z + 0.20:
			handoff_side = incoming
	if side != "" and (clearance[side] >= lerpf(0.060, 0.09, run_mix)
			or handoff_side != ""):
		if walking_hold > 0.001:
			# Keep the outgoing walking toe at its last planted point while it
			# lifts into swing after the other boot accepts support.
			previous.release_contact_side = side
			previous.release_contact_toe = previous.support_contact_toe
			previous.release_contact_age = 0.0
			previous.release_contact_strength = walking_hold
		previous.erase("support_contact_side")
		previous.erase("support_contact_toe")
		previous.erase("support_contact_age")
		side = ""
	if side == "":
		var next_side := handoff_side if handoff_side != "" else \
			"L" if clearance.L < clearance.R else "R"
		if handoff_side != "" or (clearance[next_side] < lerpf(0.035, 0.055, run_mix) \
				and clearance["R" if next_side == "L" else "L"] > lerpf(0.045, 0.10, run_mix)):
			previous.support_contact_side = next_side
			previous.support_contact_toe = toes[next_side]
			previous.support_contact_age = 0.0
			side = next_side
	if side != "":
		previous.support_contact_age = float(previous.support_contact_age) + delta
		var age: float = float(previous.support_contact_age)
		var run_hold := (1.0 - smoothstep(0.16, 0.26, age)) \
			* (1.0 - smoothstep(0.045, 0.09, clearance[side]))
		# A walking support boot stays planted until the source clip lifts it.
		# Running releases sooner as the short stance rolls through toe-off.
		var influence := lerpf(run_hold, 1.0, walking_hold)
		if influence > 0.001:
			var anchor: Vector3 = previous.support_contact_toe
			if walking_hold > 0.99:
				anchor.y = minf(anchor.y, toes[side].y)
			anchor.y = lerpf(anchor.y, toes[side].y, run_mix)
			previous.support_contact_toe = anchor
			var toe_off_lift := 0.12 * smoothstep(0.30, 0.85, run_mix) \
				* smoothstep(0.08, 0.18, age) * (1.0 - smoothstep(0.24, 0.30, age))
			_adult_hold_contact_toe(body, skeleton, anchor, influence, toe_off_lift, side)
	if previous.has("release_contact_side"):
		previous.release_contact_age = float(previous.release_contact_age) + delta
		var progress := clampf(float(previous.release_contact_age) / 0.14, 0.0, 1.0)
		_adult_hold_contact_toe(body, skeleton, previous.release_contact_toe,
			float(previous.release_contact_strength) * (1.0 - smoothstep(0.0, 1.0, progress)),
			0.08 * float(previous.release_contact_strength) * sin(PI * progress),
			previous.release_contact_side)
		if progress >= 1.0:
			previous.erase("release_contact_side")
			previous.erase("release_contact_toe")
			previous.erase("release_contact_age")
			previous.erase("release_contact_strength")

func _adult_clip_bindings(skeleton: Skeleton3D, clip: Animation) -> Dictionary:
	var result := {"bindings": [], "root_track": -1, "root_reference": Vector3.ZERO}
	for track in range(clip.get_track_count()):
		var kind := clip.track_get_type(track)
		if kind != Animation.TYPE_ROTATION_3D and kind != Animation.TYPE_POSITION_3D:
			continue
		var path := str(clip.track_get_path(track))
		if not path.begins_with("Skeleton3D:"):
			continue
		var name := path.substr(11)
		if name == "Bip01" and kind == Animation.TYPE_POSITION_3D:
			result.root_track = track
			result.root_reference = clip.position_track_interpolate(track, 0.0)
			continue
		var index := skeleton.find_bone(name)
		if index < 0:
			continue
		result.bindings.append({"index": index, "key": name.trim_prefix("Bip01 "),
			"track": track, "kind": kind,
			"reference": clip.rotation_track_interpolate(track, 0.0) if kind == Animation.TYPE_ROTATION_3D
				else clip.position_track_interpolate(track, 0.0),
			"base": skeleton.get_bone_pose_rotation(index) if kind == Animation.TYPE_ROTATION_3D
				else skeleton.get_bone_pose_position(index)})
	return result

func _apply_adult_locomotion(body: Node3D, phase: float, weight: float,
		air: float, impact: float, run_mix: float) -> void:
	var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
	var second: bool = body.get_meta("second_adult", false)
	var run_clip: Animation = second_adult_run_clip if second else adult_run_clip
	var walk_clip: Animation = second_adult_walk_clip if second else adult_walk_clip
	var strength := weight * (1.0 - air) * (1.0 - impact * 0.7)
	var run_sample := fposmod(phase / TAU, 1.0) * run_clip.length
	var walk_sample := fposmod(phase / TAU, 1.0) * walk_clip.length
	var rig: Dictionary = body.get_meta("rig")
	var walk_channels: Dictionary = body.get_meta("walk_channels")
	for binding in body.get_meta("run_bindings"):
		var index: int = binding.index
		var influence := _adult_clip_influence(binding.key, strength)
		if binding.kind == Animation.TYPE_ROTATION_3D \
				and binding.key in ["Spine", "Spine1", "Spine2"]:
			# Preserve more of the captured counter-motion at running speed.
			# The walking torso keeps its quieter carriage.
			influence = strength * lerpf(0.55, 1.0, run_mix)
		var walk_binding: Variant = walk_channels.get("%d:%d" % [index, binding.kind])
		if binding.kind == Animation.TYPE_ROTATION_3D:
			var original: Quaternion = binding.base
			var from: Quaternion = skeleton.get_bone_pose_rotation(index) if rig.has(binding.key) else original
			var run_frame := run_clip.rotation_track_interpolate(binding.track, run_sample)
			var source_leg: bool = binding.key in ["L Thigh", "L Calf", "L Foot",
				"R Thigh", "R Calf", "R Foot"]
			var source_run_arm: bool = binding.key in ["L UpperArm", "L Forearm",
				"R UpperArm", "R Forearm"]
			# Both FBX takes begin in a stride. Preserve the run's captured arm
			# carriage and both leg stances instead of subtracting their first pose.
			var run_target: Quaternion = run_frame if source_leg or source_run_arm else \
				(original * binding.reference.inverse() * run_frame).normalized()
			if binding.key == "L Forearm" or binding.key == "R Forearm":
				# Retain the opposing swing while lowering the source's high fists.
				run_target = original.slerp(run_frame, 0.72)
			if binding.key == "Spine1" or binding.key == "Spine2":
				var forward_pitch := 0.25 if binding.key == "Spine1" else 0.08
				var frame: Quaternion = rig[binding.key].space
				run_target = (run_target * frame.inverse()
					* Quaternion(Vector3.RIGHT, forward_pitch) * frame).normalized()
			var walk_target := original
			if walk_binding is Dictionary:
				var walk_frame := walk_clip.rotation_track_interpolate(walk_binding.track, walk_sample)
				walk_target = walk_frame if source_leg else \
					(original * walk_binding.reference.inverse() * walk_frame).normalized()
				if binding.key == "L UpperArm" or binding.key == "R UpperArm":
					# Retain the clip's opposing swing without its stiff, long reach.
					walk_target = original.slerp(walk_target, 0.72)
			skeleton.set_bone_pose_rotation(index, from.slerp(walk_target.slerp(run_target, run_mix), influence))
		else:
			var original: Vector3 = binding.base
			var run_frame: Vector3 = run_clip.position_track_interpolate(binding.track, run_sample)
			var run_reference: Vector3 = binding.reference
			var run_target: Vector3 = original + run_frame - run_reference
			var walk_target: Vector3 = original
			if walk_binding is Dictionary:
				var walk_frame: Vector3 = walk_clip.position_track_interpolate(walk_binding.track, walk_sample)
				var walk_reference: Vector3 = walk_binding.reference
				walk_target = original + walk_frame - walk_reference
			skeleton.set_bone_pose_position(index, original.lerp(walk_target.lerp(run_target, run_mix), influence))
	for binding in body.get_meta("walk_only_bindings"):
		# The run take has no finger channels. Retain the walk take's small hand
		# articulation instead of reverting every running finger to its open bind.
		var finger_channel: bool = binding.kind == Animation.TYPE_ROTATION_3D \
			and "Finger" in binding.key
		var influence := _adult_clip_influence(binding.key,
			strength if finger_channel else strength * (1.0 - run_mix))
		if binding.kind == Animation.TYPE_ROTATION_3D:
			var original: Quaternion = binding.base
			var frame := walk_clip.rotation_track_interpolate(binding.track, walk_sample)
			var target: Quaternion = (original * binding.reference.inverse() * frame).normalized()
			skeleton.set_bone_pose_rotation(binding.index, original.slerp(target, influence))
		else:
			var original: Vector3 = binding.base
			var frame: Vector3 = walk_clip.position_track_interpolate(binding.track, walk_sample)
			var reference: Vector3 = binding.reference
			skeleton.set_bone_pose_position(binding.index, original + (frame - reference) * influence)
	# A relaxed hand carries the run without the asset's straight, splayed
	# bind fingers. Keep the smaller walking curl and leave flight untouched.
	var hand_curl := strength * lerpf(0.40, 1.0, run_mix)
	for finger in body.get_meta("grounded_fingers"):
		var index: int = finger.index
		# Only some finger segments have source tracks. Reset the others to
		# their bind rotations so repeated samples cannot accumulate a claw.
		var pose: Quaternion = skeleton.get_bone_pose_rotation(index) if finger.animated else finger.base
		var angle: float = float(finger.curl) * hand_curl
		skeleton.set_bone_pose_rotation(index,
			(pose * Quaternion(Vector3.BACK, angle)).normalized())
	var run_lift := 0.0
	var run_root_track: int = second_adult_run_root_track if second else adult_run_root_track
	var run_root_reference: Vector3 = second_adult_run_root_reference if second else adult_run_root_reference
	if run_root_track >= 0:
		run_lift = run_clip.position_track_interpolate(run_root_track, run_sample).y - run_root_reference.y
	var walk_lift := 0.0
	var walk_root_track: int = second_adult_walk_root_track if second else adult_walk_root_track
	var walk_root_reference: Vector3 = second_adult_walk_root_reference if second else adult_walk_root_reference
	if walk_root_track >= 0:
		walk_lift = walk_clip.position_track_interpolate(walk_root_track, walk_sample).y - walk_root_reference.y
	# The preserved running stride bends both legs more than the previous
	# first-frame-relative pose, so lower only its visual root toward support.
	# Leave three millimetres of clearance for the fuller running spine motion.
	body.position.y += (lerpf(walk_lift, run_lift, run_mix) + 0.006
		- 0.047 * run_mix) * strength
	if strength > 0.01:
		var walk_bend := strength * (1.0 - run_mix)
		if walk_bend > 0.01:
			# The relative walk tracks almost straighten both elbows at the reach
			# extremes. Bend in the sagittal plane without spreading the hands.
			for side in ["L", "R"]:
				_adult_turn_joint(body, skeleton, skeleton.find_bone("Bip01 " + side + " Forearm"),
					Quaternion(Vector3.RIGHT, -0.26 * walk_bend))
		_adult_correct_grounded_knees(body, skeleton)
		# The walk clip reaches forward with an almost locked swing knee well
		# before the boot meets the ground. Fold that airborne leg during its
		# forward arc, then release it before support so the planted path stays.
		var walk_swing := strength * (1.0 - run_mix)
		if walk_swing > 0.01:
			for side in ["L", "R"]:
				var swing_phase := fposmod(phase + (PI if side == "L" else 0.0), TAU)
				var arc := smoothstep(3.2, 3.8, swing_phase) * \
					(1.0 - smoothstep(4.4, 5.0, swing_phase))
				var bend := 0.30 * walk_swing * arc
				if bend > 0.001:
					_adult_turn_joint(body, skeleton,
						skeleton.find_bone("Bip01 " + side + " Calf"),
						Quaternion(Vector3.RIGHT, bend))
					_adult_turn_joint(body, skeleton,
						skeleton.find_bone("Bip01 " + side + " Foot"),
						Quaternion(Vector3.RIGHT, -bend))

func _adult_pose_frames(skeleton: Skeleton3D) -> Array[Transform3D]:
	# Pose setters outside the scene tree do not invalidate Godot's global-pose
	# cache. Compose the source's current local poses while preparing this cache.
	var frames: Array[Transform3D] = []
	frames.resize(skeleton.get_bone_count())
	var ready := PackedByteArray()
	ready.resize(frames.size())
	for index in range(skeleton.get_bone_count()):
		var chain: Array[int] = []
		var current: int = index
		while current >= 0:
			if current >= frames.size() or chain.has(current):
				return []
			if ready[current]:
				break
			chain.append(current)
			current = skeleton.get_bone_parent(current)
		var pose: Transform3D = frames[current] if current >= 0 else Transform3D.IDENTITY
		chain.reverse()
		for bone in chain:
			pose = pose * skeleton.get_bone_pose(bone)
			frames[bone] = pose
			ready[bone] = 1
	return frames

func _adult_node_frame(ancestor: Node3D, node: Node3D) -> Transform3D:
	var frame := Transform3D.IDENTITY
	var current: Node = node
	while current != ancestor:
		if not current is Node3D:
			return Transform3D()
		frame = current.transform * frame
		current = current.get_parent()
	return frame

func _adult_rest_bounds(skeleton: Skeleton3D, mesh: MeshInstance3D, to_model: Transform3D = Transform3D.IDENTITY) -> AABB:
	# Imported mesh vertices and skeletons can have different source axes.
	# Measure actual bind-weighted vertices once, rather than using an unskinned
	# mesh AABB to infer the standing height or foot plane.
	var frames := _adult_pose_frames(skeleton)
	if frames.is_empty():
		return AABB()
	var binds: Array[Transform3D] = []
	for bind in range(mesh.skin.get_bind_count()):
		var index: int = mesh.skin.get_bind_bone(bind)
		if index < 0:
			index = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		if index < 0 or index >= skeleton.get_bone_count():
			return AABB()
		binds.append(frames[index] * mesh.skin.get_bind_pose(bind))
	var bounds := AABB()
	var first := true
	for surface in range(mesh.mesh.get_surface_count()):
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or bones.is_empty() or weights.size() != bones.size() or bones.size() % vertices.size() != 0:
			return AABB()
		var stride: int = bones.size() / vertices.size()
		for vertex in range(vertices.size()):
			var at := Vector3.ZERO
			for influence in range(stride):
				var offset := vertex * stride + influence
				if weights[offset] > 0.0:
					if bones[offset] < 0 or bones[offset] >= binds.size():
						return AABB()
					at += binds[bones[offset]] * vertices[vertex] * weights[offset]
			at = to_model * at
			if not at.is_finite():
				return AABB()
			if first:
				bounds = AABB(at, Vector3.ZERO)
				first = false
			else:
				bounds = bounds.expand(at)
	return bounds

func _prepare_adult_template(asset_root: String = ADULT_ASSETS, second: bool = false) -> bool:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	# Direct runtime glTF reading also supports cold native captures without an
	# editor import cache. Textures are explicitly decoded from the captured maps.
	if document.append_from_file(asset_root + "adult_worker.glb", state) != OK:
		return false
	var appearance: Node = document.generate_scene(state)
	if not appearance is Node3D:
		if appearance != null:
			appearance.free()
		return false
	var skeletons := appearance.find_children("*", "Skeleton3D", true, false)
	var meshes := appearance.find_children("*", "MeshInstance3D", true, false)
	if skeletons.size() != 1 or meshes.size() != 1:
		appearance.free()
		return false
	var skeleton: Skeleton3D = skeletons[0]
	var mesh: MeshInstance3D = meshes[0]
	var to_model := _adult_node_frame(appearance, skeleton)
	if mesh.skin == null or skeleton.transform != Transform3D.IDENTITY or mesh.transform != Transform3D.IDENTITY:
		appearance.free()
		return false
	for surface in range(mesh.mesh.get_surface_count()):
		var source: Material = mesh.mesh.surface_get_material(surface)
		var material: Material = _adult_material(source.resource_name if source != null else "", asset_root)
		if material == null:
			appearance.free()
			return false
		mesh.mesh.surface_set_material(surface, material)
	var body := Node3D.new()
	body.name = "BodyView"
	body.add_child(appearance)
	appearance.name = "AdultHuman"
	appearance.owner = body
	for descendant in appearance.find_children("*", "", true, false):
		descendant.owner = body
	body.set_meta("sourced_character", true)
	body.set_meta("second_adult", second)
	body.set_meta("skeleton_path", body.get_path_to(skeleton))
	var rig := {}
	var frames := _adult_pose_frames(skeleton)
	if frames.is_empty():
		body.free()
		return false
	for key in ["Spine1", "Spine2", "Neck", "L Thigh", "L Calf", "L Foot",
			"L UpperArm", "L Forearm", "R Thigh", "R Calf", "R Foot",
			"R UpperArm", "R Forearm"]:
		var index: int = skeleton.find_bone("Bip01 " + key)
		if index < 0:
			body.free()
			return false
		rig[key] = {"index": index, "rotation": skeleton.get_bone_pose_rotation(index),
			"space": (to_model.basis * frames[index].basis).get_rotation_quaternion()}
	body.set_meta("rig", rig)
	var run_clip := load(asset_root + "run_neutral.res") as Animation
	var walk_clip := load(asset_root + "walk_neutral.res") as Animation
	if run_clip == null or run_clip.length <= 0.0 \
			or walk_clip == null or walk_clip.length <= 0.0:
		body.free()
		return false
	_set_adult_air_and_landing(body, 0.0, 0.0, 0.0)
	var run_data := _adult_clip_bindings(skeleton, run_clip)
	var walk_data := _adult_clip_bindings(skeleton, walk_clip)
	body.set_meta("run_bindings", run_data.bindings)
	var run_channels := {}
	for binding in run_data.bindings:
		run_channels["%d:%d" % [binding.index, binding.kind]] = true
	var walk_channels := {}
	var walk_only_bindings := []
	for binding in walk_data.bindings:
		var channel := "%d:%d" % [binding.index, binding.kind]
		walk_channels[channel] = binding
		if not run_channels.has(channel):
			walk_only_bindings.append(binding)
	body.set_meta("walk_channels", walk_channels)
	body.set_meta("walk_only_bindings", walk_only_bindings)
	var grounded_fingers := []
	for side in ["L", "R"]:
		for finger in range(1, 5):
			var finger_weight: float = [0.75, 0.90, 1.0, 1.10][finger - 1]
			for segment in range(3):
				var name := "Bip01 %s Finger%d%s" % [side, finger,
					"" if segment == 0 else str(segment)]
				var index := skeleton.find_bone(name)
				if index < 0:
					body.free()
					return false
				grounded_fingers.append({"index": index,
					"curl": [0.62, 0.10, 0.06][segment] * finger_weight,
					"animated": walk_channels.has("%d:%d" % [index, Animation.TYPE_ROTATION_3D]),
					"base": skeleton.get_bone_pose_rotation(index)})
	body.set_meta("grounded_fingers", grounded_fingers)
	var bounds := _adult_rest_bounds(skeleton, mesh, to_model)
	if bounds.size.y < 1.0 or bounds.size.y > 2.2:
		body.free()
		return false
	var fitted_scale: float = Geometry.CAPSULE_HEIGHT / bounds.size.y
	appearance.scale = Vector3.ONE * fitted_scale
	appearance.position.y = -Geometry.CAPSULE_HEIGHT / 2.0 - bounds.position.y * fitted_scale
	if not second and not _attach_field_badge(body, skeleton):
		body.free()
		return false
	body.set_meta("source_rest_bounds", bounds)
	body.set_meta("source", "Microsoft Rocketbox Male_Adult_05" if second
		else "Microsoft Rocketbox Female_Adult_04")
	var packed := PackedScene.new()
	var error: Error = packed.pack(body)
	body.free()
	if error != OK:
		return false
	if second:
		second_adult_template = packed
		second_adult_run_clip = run_clip
		second_adult_walk_clip = walk_clip
		second_adult_run_root_track = run_data.root_track
		second_adult_run_root_reference = run_data.root_reference
		second_adult_walk_root_track = walk_data.root_track
		second_adult_walk_root_reference = walk_data.root_reference
	else:
		adult_template = packed
		adult_run_clip = run_clip
		adult_walk_clip = walk_clip
		adult_run_root_track = run_data.root_track
		adult_run_root_reference = run_data.root_reference
		adult_walk_root_track = walk_data.root_track
		adult_walk_root_reference = walk_data.root_reference
	return true

func _make_worker_visual(actor: String) -> Node3D:
	# Fixed historical source rosters do not include the new asset. They retain
	# their explicitly documented procedural appearance, without new file reads.
	if not FileAccess.file_exists(ADULT_ASSETS + "adult_worker.glb"):
		return _make_legacy_worker_visual()
	if actor == "Q" and FileAccess.file_exists(SECOND_ADULT_ASSETS + "adult_worker.glb"):
		if second_adult_template == null and not _prepare_adult_template(SECOND_ADULT_ASSETS, true):
			push_error("The second adult character asset is incomplete or invalid.")
			var unavailable := Node3D.new()
			unavailable.name = "BodyView"
			unavailable.set_meta("appearance_unavailable", true)
			return unavailable
		return second_adult_template.instantiate()
	if adult_template == null and not _prepare_adult_template():
		push_error("The captured adult character asset is incomplete or invalid.")
		var unavailable := Node3D.new()
		unavailable.name = "BodyView"
		unavailable.set_meta("appearance_unavailable", true)
		return unavailable
	return adult_template.instantiate()

func _set_gait(body: Node3D, phase: float, weight: float,
		air: float = 0.0, vertical_speed: float = 0.0, impact: float = 0.0,
		run_mix: float = 1.0, landing_progress: float = 1.0,
		landing_stride: float = 1.0, landing_approach: float = 0.0,
		landing_toe_anchor: Variant = null) -> void:
	if body.get_meta("appearance_unavailable", false):
		return
	if body.get_meta("sourced_character", false):
		_set_adult_air_and_landing(body, air, vertical_speed, impact,
			landing_progress, landing_stride, landing_approach)
		_apply_adult_locomotion(body, phase, weight, air, impact, run_mix)
		if impact > 0.0:
			var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
			skeleton.force_update_all_bone_transforms()
			var left_toe := _adult_joint(body, skeleton, skeleton.find_bone("Bip01 L Toe0"))
			var right_toe := _adult_joint(body, skeleton, skeleton.find_bone("Bip01 R Toe0"))
			# The confirmed actor is at ground height now. Keep the leading boot
			# against it while the bent legs absorb and release the load.
			var contact_y := -Geometry.CAPSULE_HEIGHT / 2.0 + 0.01 - minf(left_toe.y, right_toe.y)
			body.position.y = lerpf(body.position.y, contact_y, clampf(impact * 8.0, 0.0, 1.0))
			if landing_toe_anchor is Vector3:
				# Every moving landing needs a support boot. Hand the hold from
				# walking to running without leaving an unsupported jog-speed gap.
				var run_hold := smoothstep(0.55, 0.90, run_mix)
				var walk_hold := 1.0 - run_hold
				var fast_handoff := smoothstep(0.75, 0.95, run_mix)
				var ordinary_hold := walk_hold * (1.0 - smoothstep(0.30, 0.75, landing_progress)) \
					+ run_hold * (1.0 - smoothstep(0.35, 0.78, landing_progress))
				var hold := lerpf(ordinary_hold,
					1.0 - smoothstep(0.68, 0.98, landing_progress), fast_handoff)
				# Lift the leading boot as its support fades so the recovery travels
				# through the air instead of sliding along the ground at jog speed.
				var toe_off_lift := lerpf(0.11, 0.07, run_hold) \
					* smoothstep(lerpf(0.32, 0.68, fast_handoff),
						lerpf(0.44, 0.88, fast_handoff), landing_progress) \
					* (1.0 - smoothstep(0.82, 1.0, landing_progress))
				if hold > 0.0 or toe_off_lift > 0.0:
					_adult_hold_contact_toe(body, skeleton, landing_toe_anchor, hold, toe_off_lift)
			if landing_toe_anchor is Vector3:
				_adult_lift_landing_swing_toe(body, skeleton,
					landing_progress, landing_stride,
					smoothstep(0.75, 0.95, run_mix))
		return
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

func _animate_actor(actor: String, view: Node3D, at: Vector3, delta: float,
		native_epoch: int = -1, native_physics_frame: int = -1,
		native_on_floor: Variant = null) -> void:
	var body: Node3D = view.get_node("BodyView")
	var previous: Dictionary = motion.get(actor, {"position": at, "phase": 0.0, "weight": 0.0,
		"age": 1.0, "mode": "grounded", "ground_y": at.y, "peak_y": at.y,
		"vertical_speed": 0.0, "air": 0.0, "impact_age": LANDING_SECONDS,
		"run_mix": 0.0, "horizontal_speed": 0.0, "gait_speed": 0.0, "landing_stride": 0.0,
		"native_epoch": -1, "sample_elapsed": 0.0, "native_physics_frame": -1})
	var displacement: Vector3 = at - previous.position
	var horizontal := Vector2(displacement.x, displacement.z)
	var repeated_sample := native_epoch >= 0 and native_epoch == int(previous.native_epoch) \
		and displacement.length_squared() < 0.000000000001
	var sample_elapsed: float = float(previous.sample_elapsed) + delta
	# Native epochs identify cuts, not elapsed time. When the local native sample
	# matches this pose, its physics frame gives the actual time between cuts.
	# Shared projections without that sample retain the render-time fallback.
	var confirmed_elapsed := -1.0
	if native_physics_frame >= 0 and int(previous.native_physics_frame) >= 0 \
			and native_physics_frame > int(previous.native_physics_frame):
		confirmed_elapsed = float(native_physics_frame - int(previous.native_physics_frame)) \
			/ float(Engine.physics_ticks_per_second)
	var pose_elapsed := confirmed_elapsed if confirmed_elapsed > 0.0 else \
		sample_elapsed if native_epoch >= 0 else delta
	var horizontal_speed := horizontal.length() / maxf(pose_elapsed, 0.0001)
	previous.sample_elapsed = sample_elapsed if repeated_sample else 0.0
	previous.native_epoch = native_epoch
	previous.native_physics_frame = native_physics_frame
	var new_landing := false
	if horizontal.length() > DISCONTINUITY_HORIZONTAL or absf(displacement.y) > DISCONTINUITY_VERTICAL:
		previous = {"position": at, "phase": 0.0, "weight": 0.0, "age": 1.0,
			"mode": "grounded", "ground_y": at.y, "peak_y": at.y,
			"vertical_speed": 0.0, "air": 0.0, "impact_age": LANDING_SECONDS,
			"run_mix": 0.0, "horizontal_speed": 0.0, "gait_speed": 0.0, "landing_stride": 0.0,
			"native_epoch": native_epoch, "sample_elapsed": 0.0,
			"native_physics_frame": native_physics_frame}
		body.rotation.y = 0
	else:
		# Native cuts may contain one, two or more physics ticks per rendered
		# frame. Use their confirmed elapsed time for the fall pose, and hold the
		# last pose when a draw repeats the same airborne sample.
		var vertical_speed: float = float(previous.vertical_speed) if repeated_sample \
			and sample_elapsed <= STALE_SAMPLE_SETTLE_SECONDS else \
			displacement.y / maxf(pose_elapsed, 0.0001)
		var mode: String = previous.mode
		if mode == "grounded" or mode == "landing":
			# Rising terrain also raises the actor root. The trusted producer's
			# floor contact distinguishes a walking climb from actual takeoff.
			if native_on_floor != true and displacement.y > TAKEOFF_DELTA and vertical_speed > 0.6:
				mode = "ascent"
				previous.ground_y = previous.position.y
				previous.peak_y = at.y
				previous.impact_age = LANDING_SECONDS
			elif native_on_floor != true and displacement.y < -DROP_DELTA and vertical_speed < -0.7:
				mode = "descent"
				previous.ground_y = previous.position.y
				previous.peak_y = previous.position.y
				previous.impact_age = LANDING_SECONDS
			else:
				previous.ground_y = at.y
		elif mode == "ascent" or mode == "descent":
			previous.peak_y = maxf(float(previous.peak_y), at.y)
			if vertical_speed < -0.4:
				mode = "descent"
			if native_on_floor == true or native_on_floor == null and mode == "descent" \
					and (at.y <= float(previous.ground_y) + 0.025
					and displacement.y < 0.0 or not repeated_sample and absf(displacement.y) < 0.002
					and float(previous.peak_y) - at.y > 0.10):
				mode = "landing"
				new_landing = true
				previous.landing_air = float(previous.air)
				previous.impact_age = 0.0
				previous.ground_y = at.y
				# The last airborne sample still carries momentum when the landing
				# sample itself stops. A jump without horizontal travel has no step.
				previous.landing_stride = smoothstep(0.35, 1.35,
					maxf(horizontal_speed, float(previous.horizontal_speed)))
				if float(previous.run_mix) > 0.85:
					# Resume the captured run with its next right support step
					# arriving as the left landing boot releases the load.
					previous.phase = float(previous.phase) + wrapf(
						4.20 - fposmod(float(previous.phase), TAU), -PI, PI)
		if mode == "landing":
			previous.impact_age += delta
			if float(previous.impact_age) >= LANDING_SECONDS:
				mode = "grounded"
		previous.mode = mode
		if mode != "landing":
			previous.erase("landing_toe_anchor")
			previous.erase("landing_arm_start")
		if mode == "landing":
			# Keep the pre-contact extension long enough for the leading leg to
			# carry the first load; shed it through the recovery, not in four frames.
			previous.air = float(previous.landing_air) * (1.0 - smoothstep(0.0, 0.85,
				float(previous.impact_age) / LANDING_SECONDS))
		else:
			previous.air = move_toward(float(previous.air),
				1.0 if mode == "ascent" or mode == "descent" else 0.0, delta * 14.0)
		previous.vertical_speed = vertical_speed if mode == "ascent" or mode == "descent" else 0.0
		var starting_from_rest := (mode == "grounded" or mode == "landing") \
			and float(previous.age) >= STOP_HOLD_SECONDS \
			and float(previous.horizontal_speed) < 0.01
		previous.age = 0.0 if horizontal.length() > 0.00001 else previous.age + delta
		# Brief gaps between native poses are still the same confirmed motion.
		# A longer gap settles the visual stride without predicting actor travel.
		var speed := float(previous.horizontal_speed) if repeated_sample \
			and sample_elapsed <= STALE_SAMPLE_SETTLE_SECONDS else horizontal_speed
		# Native physics cuts and rendered frames are not one-to-one. Average the
		# observed speed for pose strength while phase still follows exact travel.
		# A fresh start responds to its first confirmed step; a true stop clears
		# the estimate promptly instead of holding a stale moving stride.
		var gait_speed := float(previous.gait_speed)
		if speed < 0.01 or gait_speed < 0.01:
			gait_speed = speed
		else:
			gait_speed = lerpf(gait_speed, speed, 1.0 - exp(-delta / 0.16))
		previous.gait_speed = gait_speed
		if mode == "grounded" and speed < 0.01 and float(previous.horizontal_speed) > 0.5:
			previous.stop_pending = true
		if mode != "grounded" or horizontal.length() > 0.00001:
			previous.erase("stop_pending")
			previous.erase("stop_toe_anchor")
			previous.erase("stop_side")
			previous.erase("stop_step_age")
		var target_run_mix := clampf((gait_speed - RUN_BLEND_START) / (RUN_BLEND_END - RUN_BLEND_START), 0.0, 1.0)
		previous.run_mix = move_toward(float(previous.run_mix), target_run_mix, delta * 5.0)
		if mode == "grounded" or mode == "landing":
			previous.phase += horizontal.length() * TAU / lerpf(WALK_CYCLE_DISTANCE, GAIT_CYCLE_DISTANCE, float(previous.run_mix))
		var target_weight := 0.0
		if horizontal.length() > 0.00001 or repeated_sample and speed > 0.00001:
			# The captured walk completes one stride over 1.30 m. At its ordinary
			# 1.05 m/s cadence it needs the full leg travel to hold a support foot;
			# the run retains its separate full-pose speed through the blend.
			var full_pose_speed := lerpf(FULL_WALK_POSE_SPEED, FULL_GAIT_SPEED,
				float(previous.run_mix))
			target_weight = minf(1.0, gait_speed / full_pose_speed)
		elif previous.age < (STOP_HOLD_SECONDS if mode == "grounded" else 0.1):
			# Keep one grounded pose at the stop, then lower the swing foot promptly.
			# Airborne and landing poses retain their longer accepted transition.
			target_weight = float(previous.weight)
		previous.weight = move_toward(float(previous.weight), target_weight, delta * 6.0)
		if horizontal.length() > 0.00001:
			var facing := atan2(horizontal.x, horizontal.y)
			# Once the actor has stopped, the first confirmed step must face its
			# travel. Easing an idle orientation makes a fast start strafe sideways.
			# A running corner also needs a quicker pivot because confirmed travel
			# changes direction immediately; retain the gentler walking turn.
			var turn_rate := lerpf(12.0, 30.0, float(previous.run_mix))
			body.rotation.y = facing if starting_from_rest else \
				lerp_angle(body.rotation.y, facing, minf(1.0, delta * turn_rate))
		previous.horizontal_speed = speed
		previous.position = at
	motion[actor] = previous
	var impact := 0.0
	var landing_progress := 1.0
	if previous.mode == "landing":
		var elapsed: float = float(previous.impact_age) / LANDING_SECONDS
		landing_progress = elapsed
		# The feet reach support before the torso finishes absorbing the load.
		# Delay the deeper compression until the support leg can take the load.
		impact = 1.90 * smoothstep(0.04, 0.60, elapsed) \
			* (1.0 - clampf(elapsed, 0.0, 1.0))
	var presentation_stride := float(previous.landing_stride)
	var landing_approach := 0.0
	if previous.mode == "descent":
		presentation_stride = smoothstep(0.35, 1.35, float(previous.horizontal_speed))
		landing_approach = 1.0 - smoothstep(0.25, 1.0,
			maxf(0.0, at.y - float(previous.ground_y)))
	if new_landing and body.get_meta("sourced_character", false):
		var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
		var saved_arms := {}
		for key in ["L UpperArm", "L Forearm", "R UpperArm", "R Forearm"]:
			var index: int = body.get_meta("rig")[key].index
			saved_arms[key] = skeleton.get_bone_pose_rotation(index)
		previous.landing_arm_start = saved_arms
	_set_gait(body, float(previous.phase), float(previous.weight), float(previous.air),
		float(previous.vertical_speed), impact, float(previous.run_mix), landing_progress,
		presentation_stride, landing_approach,
		previous.get("landing_toe_anchor") if previous.mode == "landing" else null)
	if previous.mode == "landing" and previous.has("landing_arm_start"):
		var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
		var arm_blend := smoothstep(0.0, 0.55, landing_progress)
		for key in previous.landing_arm_start:
			var index: int = body.get_meta("rig")[key].index
			var current: Quaternion = skeleton.get_bone_pose_rotation(index)
			skeleton.set_bone_pose_rotation(index,
				previous.landing_arm_start[key].slerp(current, arm_blend))
	if previous.mode == "grounded" and float(previous.horizontal_speed) > 0.2 \
			and body.get_meta("sourced_character", false):
		_adult_hold_grounded_toe(body, previous, delta, float(previous.run_mix))
	if previous.mode != "grounded" or float(previous.horizontal_speed) <= 0.2:
		previous.erase("support_contact_side")
		previous.erase("support_contact_toe")
		previous.erase("support_contact_age")
		previous.erase("release_contact_side")
		previous.erase("release_contact_toe")
		previous.erase("release_contact_age")
		previous.erase("release_contact_strength")
	motion[actor] = previous
	if previous.mode == "grounded" and (previous.get("stop_pending", false)
			or previous.has("stop_toe_anchor")) and body.get_meta("sourced_character", false):
		var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
		skeleton.force_update_all_bone_transforms()
		if previous.get("stop_pending", false):
			var left_toe := body.to_global(_adult_joint(body, skeleton,
				skeleton.find_bone("Bip01 L Toe0")))
			var right_toe := body.to_global(_adult_joint(body, skeleton,
				skeleton.find_bone("Bip01 R Toe0")))
			var side := "L" if left_toe.y < right_toe.y else "R"
			var toe := left_toe if side == "L" else right_toe
			if toe.y - (at.y - Geometry.CAPSULE_HEIGHT / 2.0) < 0.06:
				previous.stop_toe_anchor = toe
				previous.stop_side = side
				previous.stop_step_age = 0.0
				previous.erase("stop_pending")
		if previous.has("stop_toe_anchor"):
			var side: String = previous.stop_side
			var resting_toe := body.to_global(_adult_joint(body, skeleton,
				skeleton.find_bone("Bip01 " + side + " Toe0")))
			var target: Vector3 = previous.stop_toe_anchor
			var lift := 0.0
			if float(previous.weight) <= 0.001:
				previous.stop_step_age = minf(0.20, float(previous.stop_step_age) + delta)
				var progress: float = float(previous.stop_step_age) / 0.20
				target = target.lerp(resting_toe, smoothstep(0.0, 1.0, progress))
				lift = 0.06 * sin(PI * progress)
			_adult_hold_contact_toe(body, skeleton, target, 1.0, lift, side)
			# The other boot travels forward while the planted one carries the
			# stop. Give that swing a short arc before it joins the resting stance;
			# otherwise the captured run-to-idle blend drags its toe through soil.
			var swing_progress := 1.0 - clampf(float(previous.run_mix), 0.0, 1.0)
			var swing_lift := 0.12 * sin(PI * swing_progress)
			if swing_lift > 0.001:
				var swing_side := "R" if side == "L" else "L"
				skeleton.force_update_all_bone_transforms()
				var swing_toe := body.to_global(_adult_joint(body, skeleton,
					skeleton.find_bone("Bip01 " + swing_side + " Toe0")))
				_adult_hold_contact_toe(body, skeleton, swing_toe, 1.0,
					swing_lift, swing_side)
			if float(previous.stop_step_age) >= 0.20:
				previous.erase("stop_toe_anchor")
				previous.erase("stop_side")
				previous.erase("stop_step_age")
		motion[actor] = previous
	if new_landing and presentation_stride > 0.1 and body.get_meta("sourced_character", false):
		var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
		skeleton.force_update_all_bone_transforms()
		var contact_toe := body.to_global(_adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 L Toe0")))
		contact_toe.y = at.y - Geometry.CAPSULE_HEIGHT / 2.0 + 0.01
		previous.landing_toe_anchor = contact_toe
		_adult_hold_contact_toe(body, skeleton, contact_toe,
			1.0)
		_adult_lift_landing_swing_toe(body, skeleton, landing_progress,
			presentation_stride, smoothstep(0.75, 0.95, float(previous.run_mix)))
		motion[actor] = previous

func _new_view(actor: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Character" + actor
	root.set_meta("actor", actor)
	var mesh := _make_worker_visual(actor)
	if mesh is MeshInstance3D:
		mesh.material_override = _worker_material(Color("c87847") if actor == host.client else Color("50899a"), 0.85, 0, true)
	root.add_child(mesh)
	if actor != host.client:
		var label := Label3D.new()
		label.text = actor
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
		native_sample_frames.clear()
	var actors: Dictionary = host.state.get("actors", {})
	for actor in views.keys():
		if not actors.has(actor):
			var old: Node3D = views[actor]
			remove_child(old)
			old.queue_free()
			views.erase(actor)
			motion.erase(actor)
			native_sample_frames.erase(actor)
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
				var observed_epoch: Variant = data.get("native_epoch", -1)
				var native_epoch := int(observed_epoch) if typeof(observed_epoch) == TYPE_INT else -1
				var sample: Dictionary = native_sample_frames.get(actor, {})
				var physics_frame := int(sample.get("physics_frame", -1)) \
					if sample.get("epoch", -1) == native_epoch else -1
				_animate_actor(actor, view, view.position, delta,
				native_epoch, physics_frame,
				sample.get("on_floor") if sample.get("epoch", -1) == native_epoch else null)
		else:
			motion.erase(actor)
	_refresh_multitools()
	if views.has(host.client) and host.distance <= 1.0:
		views[host.client].visible = false
	if not host.explanation_open and actors.has(host.client) and Geometry.valid_position(actors[host.client].get("position")):
		var at: Array = actors[host.client].position
		host.focus = Vector3(at[0], at[1] + 0.3, at[2])
		host._update_camera()
