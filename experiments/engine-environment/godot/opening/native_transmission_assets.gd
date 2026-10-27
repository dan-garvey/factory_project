extends RefCounted
## Pure render assemblies. The presenter retains axes, picks and native facts.
const Visuals = preload("res://opening/production_surfaces.gd").ProductionVisuals
const Finish = preload("res://opening/production_surfaces.gd").ProductionTransmissionFinish
const ConveyorArt = preload("res://opening/production_conveyors.gd").ProductionConveyorArt
const UNIT := preload("res://opening/site_geometry.gd").PITCH / 4.0
const SHAFT_CORE_RADIUS := 0.03
const SPAN_HALF_WIDTH := preload("res://opening/site_geometry.gd").BELT_HALF_WIDTH
const SPAN_OUTER_RADIUS := preload("res://opening/site_geometry.gd").BELT_OUTER_RADIUS
const SPAN_THICKNESS := 0.045
const PULLEY_RADIUS := 0.095
const PULLEY_BORE := 0.039
static var meshes: Dictionary = {}
static var batches: Dictionary = {}
static var complete_gears: Dictionary = {}
const COUPLING_ROOT := "res://opening/assets"
# The prepared pipe kit already tracks the identical original Group 01 JPEG.
# Use canonical resource paths: imported textures do not resolve parent segments.
const COUPLING_IMAGES := {"albedo": "pipe-fit/textures/modular_industrial_pipes_01_group01_diff_1k.jpg",
	"normal": "shaft-coupling/coupling_normal.webp", "arm": "shaft-coupling/coupling_arm.webp"}
const COUPLING_HALF_LENGTH := (0.42954 - 0.39) * 0.72
static var coupling_mesh: ArrayMesh
static var coupling_finish: StandardMaterial3D
static var coupling_status := "uninitialized"

static func _prepare_coupling() -> void:
	var files: Array = ["shaft-coupling/coupling.gltf", "shaft-coupling/coupling.bin"]
	files.append_array(COUPLING_IMAGES.values())
	var present := 0
	for file_name: String in files:
		if FileAccess.file_exists(COUPLING_ROOT.path_join(file_name)):
			present += 1
	coupling_status = "missing" if present == 0 else "invalid"
	if present == 0:
		return
	if present != files.size():
		push_error("The sourced shaft coupling resource set is incomplete.")
		return
	var images := preload("res://opening/production_surfaces.gd").ProductionSteelFloor.read_images(COUPLING_ROOT, COUPLING_IMAGES, Vector2i(512, 512))
	if images.status != "ready":
		push_error("Cannot decode the sourced shaft coupling material.")
		return
	var document := GLTFDocument.new()
	var imported := GLTFState.new()
	if document.append_from_file(COUPLING_ROOT.path_join("shaft-coupling/coupling.gltf"), imported) != OK:
		push_error("Cannot load the prepared shaft coupling.")
		return
	var sources := imported.get_meshes()
	if sources.size() != 1 or sources[0].mesh == null or sources[0].mesh.get_surface_count() != 2:
		push_error("The shaft coupling needs retained source and authored cut surfaces.")
		return
	var prepared: ArrayMesh = sources[0].mesh.get_mesh()
	var complete := ArrayMesh.new()
	for index in range(2):
		var surface := SurfaceTool.new()
		surface.create_from(prepared, index)
		surface.generate_tangents()
		surface.commit(complete)
	for role: String in images.images:
		if images.images[role].generate_mipmaps(role == "normal") != OK:
			push_error("Cannot generate shaft coupling mipmaps.")
			return
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = ImageTexture.create_from_image(images.images.albedo)
	var arm := ImageTexture.create_from_image(images.images.arm)
	material.metallic = 1.0
	material.metallic_texture = arm
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	material.roughness = 1.0
	material.roughness_texture = arm
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.ao_enabled = true
	material.ao_texture = arm
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.normal_enabled = true
	material.normal_texture = ImageTexture.create_from_image(images.images.normal)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	coupling_mesh = complete
	coupling_finish = material
	coupling_status = "ready"

static func coupling(parent: Node3D) -> bool:
	if coupling_status == "uninitialized":
		_prepare_coupling()
	if coupling_status != "ready":
		return false
	for side in [0, 1]:
		var half := MeshInstance3D.new()
		half.name = "SourcedFlange%d" % side
		half.mesh = coupling_mesh
		half.set_surface_override_material(0, coupling_finish)
		half.set_surface_override_material(1, Finish.material("worked", Color("a6b4af"), 0.85, 0.38))
		if side == 1:
			half.rotation.x = PI
		half.set_meta("source_asset", "Poly Haven modular_industrial_pipes_01")
		parent.add_child(half)
	return true

static func _finish(instance: GeometryInstance3D, name_value: String, color: Color,
		metal: float, roughness: float) -> void:
	instance.name = name_value
	instance.set_meta("asset_role", name_value)
	if name_value == "ShaftKey":
		instance.material_override = Visuals.material(color, metal, roughness)
		instance.set_meta("surface_role", "copper")
	else:
		var surface_role := "cast" if name_value in ["Gear", "GearSpoke"] else "worked"
		instance.material_override = Finish.material(surface_role, color, metal, roughness)
		instance.set_meta("surface_role", surface_role)

static func _part(parent: Node3D, name_value: String, mesh: Mesh, at: Vector3,
		color: Color, metal: float = 0.85, roughness: float = 0.38) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	_finish(instance, name_value, color, metal, roughness)
	parent.add_child(instance)
	return instance

static func append_triangles(surface: SurfaceTool, mesh: Mesh, face: int, pose: Transform3D) -> void:
	# SurfaceTool.append_from copies indexed source vertices without their face
	# order into a new unindexed stream. Expand source triangles explicitly.
	var arrays := mesh.surface_get_arrays(face)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array else PackedVector2Array()
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array else PackedFloat32Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for corner in count:
		var index: int = indices[corner] if not indices.is_empty() else corner
		if not normals.is_empty():
			surface.set_normal((pose.basis * normals[index]).normalized())
		if not uvs.is_empty():
			surface.set_uv(uvs[index])
		if tangents.size() >= index * 4 + 4:
			var direction := Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])
			surface.set_tangent(Plane((pose.basis * direction).normalized(), tangents[index * 4 + 3]))
		surface.add_vertex(pose * vertices[index])

static func _batch(parent: Node3D, role: String, key_value: Array, mesh: Mesh,
		poses: Array[Transform3D], color: Color) -> void:
	if not batches.has(key_value):
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = mesh
		batch.instance_count = poses.size()
		var bounds: AABB = poses[0] * mesh.get_aabb()
		var buffer := PackedFloat32Array()
		for pose in poses:
			var basis := pose.basis
			var at := pose.origin
			buffer.append_array(PackedFloat32Array([
				basis.x.x, basis.y.x, basis.z.x, at.x,
				basis.x.y, basis.y.y, basis.z.y, at.y,
				basis.x.z, basis.y.z, basis.z.z, at.z]))
			bounds = bounds.merge(pose * mesh.get_aabb())
		batch.buffer = buffer
		# One rigid cog owns each culling group. Avoid a world-sized batch and
		# repeated bounds rebuilding when only the parent angle changes.
		batch.custom_aabb = bounds
		batches[key_value] = batch
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = batches[key_value]
	_finish(instance, role, color, 0.85, 0.38)
	parent.add_child(instance)

static func _cylinder(radius: float, height: float, segments: int = 48) -> CylinderMesh:
	var key := [radius, height, segments]
	if not meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = segments
		meshes[key] = mesh
	return meshes[key]

static func _face(surface: SurfaceTool, points: Array[Vector3], center: Vector3) -> void:
	var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var middle := Vector3.ZERO
	for point in points:
		middle += point / float(points.size())
	if normal.dot(middle - center) < 0:
		normal = -normal
	# The common face builder reverses its input to select clockwise winding.
	# Preserve ring order for the side faces that still need these vertices.
	Visuals._face(surface, points.duplicate(), normal)

static func tooth_mesh(radius: float, teeth: int) -> ArrayMesh:
	var key := ["tooth", radius, teeth]
	if meshes.has(key):
		return meshes[key]
	var pitch := TAU * radius / float(teeth)
	var root := radius - 0.1
	var tip_width := pitch * 0.17
	# Outer corners stay inside the unchanged native radius, rather than
	# enlarging the occupied/pick envelope to accommodate decorative detail.
	var tip_x := sqrt(radius * radius - tip_width * tip_width)
	var outline := PackedVector2Array([Vector2(root - 0.015, -pitch * 0.34),
		Vector2(tip_x, -tip_width), Vector2(tip_x, tip_width), Vector2(root - 0.015, pitch * 0.34)])
	var center := Vector3((root - 0.015 + tip_x) / 2.0, 0, 0)
	var rings: Array = []
	for row in [[-0.07, 0.92], [-0.06, 1.0], [0.06, 1.0], [0.07, 0.92]]:
		var points: Array[Vector3] = []
		for point in outline:
			points.append(Vector3(lerpf(center.x, point.x, row[1]), row[0], point.y * row[1]))
		rings.append(points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_face(surface, rings[0], center)
	_face(surface, rings[3], center)
	for row in range(3):
		for side in range(4):
			var next := (side + 1) % 4
			_face(surface, [rings[row][side], rings[row][next], rings[row + 1][next], rings[row + 1][side]], center)
	surface.generate_tangents()
	var mesh := surface.commit()
	meshes[key] = mesh
	return mesh

static func gear(parent: Node3D, radius: float, ratio_units: int, color: Color,
		detail_segments: int = 0) -> void:
	# Eight render teeth per native ratio/radius unit. This tessellation stays
	# proportional; it does not change the wire parameter or model tooth contact.
	var count := ratio_units * 8
	var inner := radius * 0.56
	var outer := radius - 0.1
	var band := outer - inner
	var relief := minf(0.008, band * 0.075)
	# Recess one annular track on each face of the wide cast rim. Its shoulders
	# keep the original 70 mm face plane and its roots stay inside the native
	# radius, so size variants share the same manufactured reading.
	var rim := PackedVector2Array([Vector2(inner + 0.006, -0.07),
		Vector2(inner + band * 0.33, -0.07), Vector2(inner + band * 0.37, -0.07 + relief),
		Vector2(inner + band * 0.63, -0.07 + relief), Vector2(inner + band * 0.67, -0.07),
		Vector2(outer - 0.006, -0.07),
		Vector2(outer, -0.06), Vector2(outer, 0.06), Vector2(outer - 0.006, 0.07),
		Vector2(inner + band * 0.67, 0.07), Vector2(inner + band * 0.63, 0.07 - relief),
		Vector2(inner + band * 0.37, 0.07 - relief), Vector2(inner + band * 0.33, 0.07),
		Vector2(inner + 0.006, 0.07), Vector2(inner, 0.06), Vector2(inner, -0.06),
		Vector2(inner + 0.006, -0.07)])
	_part(parent, "Gear", Visuals.turned_mesh(rim, maxi(48, count * 2) if detail_segments == 0
		else maxi(detail_segments, count)), Vector3.ZERO, color)
	var tooth := tooth_mesh(radius, count)
	var teeth: Array[Transform3D] = []
	for n in range(count):
		teeth.append(Transform3D(Basis.from_euler(Vector3(0, float(n) * TAU / count, 0)), Vector3.ZERO))
	_batch(parent, "GearTooth", ["GearTooth", radius, ratio_units], tooth, teeth, color)
	var hub_radius := minf(0.16, radius * 0.34)
	# Open both machined faces around the existing shaft/collar/key envelope.
	# This is render clearance, not a new mechanical connection or phase rule.
	var hub := PackedVector2Array([Vector2(0.044, -0.11), Vector2(hub_radius - 0.008, -0.11),
		Vector2(hub_radius, -0.102), Vector2(hub_radius, 0.102),
		Vector2(hub_radius - 0.008, 0.11), Vector2(0.044, 0.11),
		Vector2(0.039, 0.105), Vector2(0.039, -0.105), Vector2(0.044, -0.11)])
	_part(parent, "Hub", Visuals.turned_mesh(hub, detail_segments if detail_segments > 0 else 48),
		Vector3.ZERO, Color("a6b4af"))
	var spoke_length := inner - hub_radius + 0.04
	var spokes: Array[Transform3D] = []
	var fasteners: Array[Transform3D] = []
	for n in range(4):
		var angle := float(n) * PI / 2.0
		spokes.append(Transform3D(Basis.from_euler(Vector3(0, -angle, 0)),
			Vector3(cos(angle), 0, sin(angle)) * (hub_radius + inner) / 2.0))
		for side in [-1.0, 1.0]:
			fasteners.append(Transform3D(Basis.from_euler(Vector3(PI if side < 0 else 0.0, 0, 0)),
				Vector3(cos(angle) * hub_radius * 0.65, side * 0.108, sin(angle) * hub_radius * 0.65)))
	_batch(parent, "GearSpoke", ["GearSpoke", radius], Visuals.box_mesh(Vector3(spoke_length, 0.08, 0.09)), spokes, color)
	_batch(parent, "HubFastener", ["HubFastener", hub_radius], _cylinder(0.022, 0.012, 6), fasteners, Color("b8c3bb"))

static func complete_gear_mesh(radius: float, ratio_units: int, color: Color, length: float) -> ArrayMesh:
	# Bake the existing fitted assembly once per specification. Each finish keeps
	# its own surface, while a whole cog becomes one rigid MultiMesh instance.
	var key := [radius, ratio_units, color, length]
	if complete_gears.has(key):
		return complete_gears[key]
	var assembly := Node3D.new()
	gear(assembly, radius, ratio_units, color, 24)
	shaft(assembly, length, color, 24)
	var materials: Array[Material] = []
	var surfaces: Array[SurfaceTool] = []
	for child: Node in assembly.get_children():
		var source: Mesh
		var poses: Array[Transform3D] = []
		var finish: Material
		if child is MeshInstance3D:
			source = child.mesh
			poses.append(child.transform)
			finish = child.material_override
		elif child is MultiMeshInstance3D:
			source = child.multimesh.mesh
			for index in child.multimesh.instance_count:
				poses.append(child.transform * child.multimesh.get_instance_transform(index))
			finish = child.material_override
		else:
			continue
		if source == null or finish == null:
			continue
		var group := materials.find(finish)
		if group < 0:
			group = materials.size()
			materials.append(finish)
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces.append(surface)
		for pose in poses:
			for face in source.get_surface_count():
				append_triangles(surfaces[group], source, face, pose)
	var result := ArrayMesh.new()
	for index in surfaces.size():
		surfaces[index].commit(result)
		result.surface_set_material(index, materials[index])
	assembly.free()
	complete_gears[key] = result
	return result

static func shaft(parent: Node3D, length: float, color: Color, detail_segments: int = 0) -> void:
	# Keep this public node's CylinderMesh and exact length for the established
	# endpoint consumer. Fitted collars do not alter the pick cylinder.
	_part(parent, "Shaft", _cylinder(SHAFT_CORE_RADIUS, length, detail_segments if detail_segments > 0 else 48),
		Vector3.ZERO, color)
	var collar := PackedVector2Array([Vector2(0.03, -0.055), Vector2(0.0345, -0.055),
		Vector2(0.036, -0.0535), Vector2(0.036, 0.0535), Vector2(0.0345, 0.055),
		Vector2(0.03, 0.055), Vector2(0.03, -0.055)])
	for sign_value in [-1.0, 1.0]:
		var center: float = sign_value * (length / 2.0 - 0.06)
		_part(parent, "ShaftCollar", Visuals.turned_mesh(collar, detail_segments if detail_segments > 0 else 48),
			Vector3(0, center, 0), Color("a6b4af"))
		_part(parent, "ShaftKey", Visuals.box_mesh(Vector3(0.012, 0.08, 0.012)),
			Vector3(0.031, center, 0), Color("b87945"))

static func _belt_frame(loop: MeshInstance3D, distance: float) -> void:
	# The admitted span includes this fixed frame. Its seats surround the
	# confirmed shafts outside the pulley faces; only the plain middle scales.
	var rail_finish := Finish.material("cast", Color("41565b"), 0.55, 0.48)
	var seat_finish := Finish.material("worked", Color("a6b4af"), 0.85, 0.38)
	var ring_key := "span_frame_seat"
	if not meshes.has(ring_key):
		meshes[ring_key] = Visuals.turned_mesh(PackedVector2Array([
			Vector2(0.034, -0.020), Vector2(0.037, -0.020),
			Vector2(0.072, -0.020), Vector2(0.078, -0.014),
			Vector2(0.078, 0.014), Vector2(0.072, 0.020),
			Vector2(0.037, 0.020), Vector2(0.034, 0.017),
			Vector2(0.034, -0.020)]))
	# A closed formed channel exposes two narrow flanges and a recessed web.
	# The open side faces away from the cargo lane; the profile stays rigid as
	# only its undecorated length changes between confirmed shaft centres.
	var section := PackedVector2Array([
		Vector2(-0.026, -0.055), Vector2(0.026, -0.055),
		Vector2(0.026, -0.043), Vector2(-0.014, -0.043),
		Vector2(-0.014, 0.043), Vector2(0.026, 0.043),
		Vector2(0.026, 0.055), Vector2(-0.026, 0.055)])
	for side in [-1.0, 1.0]:
		var profile := section.duplicate()
		for index in range(profile.size()):
			profile[index].x *= -side
		var rail := MeshInstance3D.new()
		rail.name = "SpanFrameRailN" if side < 0 else "SpanFrameRailP"
		rail.mesh = Visuals.prism_mesh(profile, distance, 0.002)
		rail.basis = Basis(Vector3.UP, PI / 2.0)
		rail.position = Vector3(0, 0, side * 0.515)
		rail.material_override = rail_finish
		rail.set_meta("span_frame_role", "Rail")
		loop.add_child(rail)
		for end in [-1.0, 1.0]:
			var seat := MeshInstance3D.new()
			seat.name = "SpanFrameSeat" + ("N" if end < 0 else "P") + ("N" if side < 0 else "P")
			seat.mesh = meshes[ring_key]
			seat.position = Vector3(end * distance / 2.0, 0, side * 0.515)
			seat.basis = Basis(Quaternion(Vector3.UP, Vector3.BACK))
			seat.material_override = seat_finish
			seat.set_meta("span_frame_role", "Seat")
			loop.add_child(seat)

static func belt_loop(parent: Node3D, distance: float, travel_axis: int) -> MeshInstance3D:
	# Keep the confirmed strips' width and four flat surface heights. Only
	# their missing curved returns and material treatment are replaced.
	if not is_finite(distance) or distance < UNIT * 4.0 or distance > UNIT * 80.0 * sqrt(2.0) or travel_axis not in [0, 2]:
		return null
	var source := ConveyorArt.material()
	if source == null:
		return null
	var loop := MeshInstance3D.new()
	loop.name = "BeltLoop"
	loop.mesh = ConveyorArt.loop_mesh(distance / 2.0, SPAN_HALF_WIDTH,
		SPAN_OUTER_RADIUS, SPAN_THICKNESS, 0.003)
	loop.material_override = source
	if travel_axis == 2:
		loop.rotation.y = -PI / 2.0
	loop.set_meta("asset_role", "BeltLoop")
	parent.add_child(loop)
	_belt_frame(loop, distance)
	return loop

static func belt_pulley(parent: Node3D) -> MeshInstance3D:
	# One fitted drum per shaft even when several confirmed spans meet it.
	# The presenter supplies the existing shaft basis and cosmetic rotation.
	var existing := parent.get_node_or_null("BeltPulley")
	if existing is MeshInstance3D:
		return existing
	var key := ["belt_pulley"]
	if not meshes.has(key):
		var face := SPAN_HALF_WIDTH - 0.006
		var profile := PackedVector2Array([
			Vector2(0.044, -0.49), Vector2(0.059, -0.49), Vector2(0.065, -0.484),
			Vector2(0.065, -0.43), Vector2(0.085, -0.43), Vector2(0.090, -face),
			Vector2(0.093, -face), Vector2(PULLEY_RADIUS, -face + 0.002),
			Vector2(PULLEY_RADIUS, face - 0.002), Vector2(0.093, face),
			Vector2(0.090, face), Vector2(0.085, 0.43), Vector2(0.065, 0.43),
			Vector2(0.065, 0.484), Vector2(0.059, 0.49), Vector2(0.044, 0.49),
			Vector2(PULLEY_BORE, 0.485), Vector2(PULLEY_BORE, -0.485), Vector2(0.044, -0.49)])
		meshes[key] = Visuals.turned_mesh(profile)
	return _part(parent, "BeltPulley", meshes[key], Vector3.ZERO, Color("a6b4af"))
