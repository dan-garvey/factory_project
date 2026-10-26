extends RefCounted
## Render resources only; no scene controller or simulation authority.
const Geometry = preload("res://opening/site_geometry.gd")
const ProductionCoating = preload("res://opening/production_surfaces.gd").ProductionCoating
const ProductionTransmissionFinish = preload("res://opening/production_surfaces.gd").ProductionTransmissionFinish
const ProductionVisuals = preload("res://opening/production_surfaces.gd").ProductionVisuals

class ProductionConveyorArt:
	extends RefCounted
	## Closed visual belt and source rubber. No transport clock or contact rules.
	const ROOT := "res://opening/assets/conveyor"
	const FILES := {"albedo": "rubber_albedo.webp", "normal": "rubber_normal_gl.webp", "roughness": "rubber_roughness.webp"}
	const HALF_SPAN := 0.57
	const HALF_WIDTH := 0.32
	const RADIUS := 0.09
	const THICKNESS := 0.012
	const BEVEL := 0.0015
	const HEIGHT := 0.465
	const ARC_SEGMENTS := 24
	const SOURCE_METRES := 0.75
	static var loop_meshes: Dictionary = {}
	static var finish: StandardMaterial3D
	static var batch_finish: ShaderMaterial
	static var source_status := "uninitialized"

	static func read_images(directory: String = ROOT) -> Dictionary:
		return ProductionVisuals.read_image_set(directory, FILES, {
			"albedo": Vector2i(1024, 1024), "normal": Vector2i(512, 512),
			"roughness": Vector2i(512, 512)}, "incomplete_material_set")

	static func material() -> StandardMaterial3D:
		if source_status != "uninitialized":
			return finish
		var loaded := read_images()
		source_status = loaded.status
		if source_status == "missing":
			# Historical rosters retain generated rubber on the same visual loop.
			finish = ProductionVisuals.material(Color("28383d"), 0.0, 0.9)
			return finish
		if source_status != "ready":
			push_error("Invalid conveyor rubber material: " + str(loaded.get("reason", "unknown")))
			return null
		for role in loaded.images:
			var image: Image = loaded.images[role]
			if image.generate_mipmaps(role == "normal") != OK:
				source_status = "invalid"
				push_error("Cannot generate conveyor material mipmaps.")
				return null
		finish = StandardMaterial3D.new()
		finish.albedo_color = Color.WHITE
		finish.albedo_texture = ImageTexture.create_from_image(loaded.images.albedo)
		finish.metallic = 0.0
		finish.roughness = 1.0
		finish.roughness_texture = ImageTexture.create_from_image(loaded.images.roughness)
		finish.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		finish.normal_enabled = true
		finish.normal_texture = ImageTexture.create_from_image(loaded.images.normal)
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return finish

	static func loop_mesh(half_span: float = HALF_SPAN, half_width: float = HALF_WIDTH,
			radius: float = RADIUS, thickness: float = THICKNESS, bevel: float = BEVEL) -> ArrayMesh:
		var key := [half_span, half_width, radius, thickness, bevel]
		if loop_meshes.has(key):
			return loop_meshes[key]
		var profile := PackedVector2Array([
			Vector2(radius - thickness + bevel, -half_width), Vector2(radius - bevel, -half_width),
			Vector2(radius, -half_width + bevel), Vector2(radius, half_width - bevel),
			Vector2(radius - bevel, half_width), Vector2(radius - thickness + bevel, half_width),
			Vector2(radius - thickness, half_width - bevel), Vector2(radius - thickness, -half_width + bevel)])
		var directions := PackedVector2Array()
		var centers := PackedVector2Array()
		var distances := PackedFloat32Array()
		for side in [1.0, -1.0]:
			for n in range(ARC_SEGMENTS + 1):
				var angle := (PI / 2.0 if side > 0 else -PI / 2.0) - PI * float(n) / ARC_SEGMENTS
				directions.append(Vector2(cos(angle), sin(angle)))
				centers.append(Vector2(side * half_span, 0))
				distances.append(radius * PI * float(n) / ARC_SEGMENTS + (0.0 if side > 0 else PI * radius + 2.0 * half_span))
		var length_value := 4.0 * half_span + TAU * radius
		# Whole physical-scale repeats close the longitudinal texture seam.
		var repeats := maxi(1, roundi(length_value / SOURCE_METRES))
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cross_distance := 0.0
		for section in range(profile.size()):
			var a := profile[section]
			var b := profile[(section + 1) % profile.size()]
			var across := a.distance_to(b)
			var slope := Vector2(b.y - a.y, a.x - b.x).normalized()
			for n in range(centers.size()):
				var next := (n + 1) % centers.size()
				var points: Array[Vector3] = []
				var normals: Array[Vector3] = []
				var coordinates: Array[Vector2] = []
				for corner in [[n, a, 0.0], [next, a, 0.0], [next, b, across], [n, b, across]]:
					var at: int = corner[0]
					var p: Vector2 = corner[1]
					var xy: Vector2 = centers[at] + directions[at] * p.x
					var normal := Vector3(directions[at].x * slope.x, directions[at].y * slope.x, slope.y)
					var along: float = distances[at] if not (n == centers.size() - 1 and at == 0) else length_value
					points.append(Vector3(xy.x, xy.y, p.y))
					normals.append(normal)
					coordinates.append(Vector2(along / length_value * repeats, (cross_distance + float(corner[2])) / SOURCE_METRES))
				for triangle in [[0, 1, 2], [0, 2, 3]]:
					var order: Array = triangle.duplicate()
					var cross := (points[order[1]] - points[order[0]]).cross(points[order[2]] - points[order[0]])
					if cross.dot(normals[order[0]] + normals[order[1]] + normals[order[2]]) > 0:
						order.reverse()
					for index in order:
						surface.set_normal(normals[index])
						surface.set_uv(coordinates[index])
						surface.add_vertex(points[index])
			cross_distance += across
		surface.generate_tangents()
		var result := surface.commit()
		loop_meshes[key] = result
		return result

	static func mount(parent: Node3D) -> void:
		var belt := MeshInstance3D.new()
		belt.name = "ConveyorLoop"
		belt.position.y = HEIGHT
		belt.mesh = loop_mesh()
		var source := material()
		belt.material_override = source.duplicate() if source != null else null
		belt.set_meta("detail_role", "ConveyorLoop")
		parent.add_child(belt)

	static func multimesh_material() -> ShaderMaterial:
		if batch_finish != null:
			return batch_finish
		var source := material()
		if source == null or source_status != "ready":
			return null
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
void vertex() {
	UV.x += INSTANCE_CUSTOM.r;
}
void fragment() {
	ALBEDO = texture(albedo_map, UV).rgb;
	METALLIC = 0.0;
	ROUGHNESS = texture(roughness_map, UV).r;
	NORMAL_MAP = texture(normal_map, UV).rgb;
}
"""
		batch_finish = ShaderMaterial.new()
		batch_finish.shader = shader
		batch_finish.set_shader_parameter("albedo_map", source.albedo_texture)
		batch_finish.set_shader_parameter("roughness_map", source.roughness_texture)
		batch_finish.set_shader_parameter("normal_map", source.normal_texture)
		return batch_finish

class ProductionConveyorFrameArt:
	extends RefCounted
	## Fixed original furniture around the existing loop, rollers and drive.
	static var foot_bolt: CylinderMesh
	static var cap_bolt: CylinderMesh

	static func _part(parent: Node3D, role: String, suffix: String, mesh: Mesh, at: Vector3,
			orientation: Basis, finish: StandardMaterial3D) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role + suffix
		part.set_meta("conveyor_frame_role", role)
		part.set_meta("detail_role", {"FrameCheek": "ConveyorLeg", "SideBeam": "ConveyorChannel",
			"BearingCup": "RollerBearing"}.get(role, role))
		part.mesh = mesh
		part.position = at
		part.basis = orientation
		part.material_override = finish
		parent.add_child(part)
		return part

	static func mount(parent: Node3D, color: Color, drive_axis: int) -> bool:
		var paint := ProductionCoating.material(color)
		var steel := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)
		if paint == null or steel == null:
			return false
		if foot_bolt == null:
			foot_bolt = CylinderMesh.new()
			foot_bolt.top_radius = 0.012
			foot_bolt.bottom_radius = 0.012
			foot_bolt.height = 0.012
			foot_bolt.radial_segments = 6
			cap_bolt = CylinderMesh.new()
			cap_bolt.top_radius = 0.024
			cap_bolt.bottom_radius = 0.024
			cap_bolt.height = 0.015
			cap_bolt.radial_segments = 6
		var cheek := PackedVector2Array([Vector2(-0.13, 0.24), Vector2(0.13, 0.24),
			Vector2(0.13, 0.275), Vector2(0.09, 0.275), Vector2(0.052, 0.35),
			Vector2(0.048, 0.385), Vector2(-0.048, 0.385), Vector2(-0.052, 0.35),
			Vector2(-0.09, 0.275), Vector2(-0.13, 0.275)])
		var cup := PackedVector2Array([Vector2(0.065, -0.0475), Vector2(0.09, -0.0475),
			Vector2(0.115, -0.0375), Vector2(0.115, 0.0355), Vector2(0.105, 0.0475),
			Vector2(0.065, 0.0475), Vector2(0.065, -0.0475)])
		var liner := PackedVector2Array([Vector2(0.063, -0.0465), Vector2(0.065, -0.0465),
			Vector2(0.065, 0.0465), Vector2(0.063, 0.0465), Vector2(0.063, -0.0465)])
		var cap := PackedVector2Array([Vector2(0, -0.004), Vector2(0.078, -0.004),
			Vector2(0.085, -0.002), Vector2(0.085, 0.002), Vector2(0.078, 0.004), Vector2(0, 0.004)])
		for x in [-0.57, 0.57]:
			for side in [-1.0, 1.0]:
				var suffix := ("N" if x < 0 else "P") + ("N" if side < 0 else "P")
				var bearing_frame := Basis(Quaternion(Vector3.UP, Vector3.BACK * side))
				var stand := _part(parent, "FrameCheek", suffix, ProductionVisuals.prism_mesh(cheek, 0.06, 0.003),
					Vector3(x, 0, side * 0.36), Basis.IDENTITY, paint)
				_part(parent, "BearingCup", suffix, ProductionVisuals.turned_mesh(cup),
					Vector3(x, 0.465, side * 0.3875), bearing_frame, paint)
				_part(parent, "BearingLiner", suffix, ProductionVisuals.turned_mesh(liner),
					Vector3(x, 0.465, side * 0.3875), bearing_frame, steel)
				var cover := _part(parent, "EndCap", suffix, ProductionVisuals.turned_mesh(cap),
					Vector3(x, 0.465, side * 0.438), bearing_frame, steel)
				var bolt := _part(parent, "CapBolt", suffix, cap_bolt,
					Vector3(x, 0.465, side * 0.4495), bearing_frame, steel)
				bolt.set_meta("frame_seat", cover.name)
				for offset in [-0.11, 0.11]:
					var foot := _part(parent, "FootBolt", suffix + ("N" if offset < 0 else "P"), foot_bolt,
						Vector3(x + offset, 0.281, side * 0.36), Basis.IDENTITY, steel)
					foot.set_meta("frame_seat", stand.name)
		var channel := PackedVector2Array([Vector2(-0.025, -0.03), Vector2(0.025, -0.03),
			Vector2(0.025, -0.018), Vector2(-0.013, -0.018), Vector2(-0.013, 0.018),
			Vector2(0.025, 0.018), Vector2(0.025, 0.03), Vector2(-0.025, 0.03)])
		for side in [-1.0, 1.0]:
			var suffix := "N" if side < 0 else "P"
			_part(parent, "SideBeam", suffix, ProductionVisuals.prism_mesh(channel, 1.14, 0.002),
				Vector3(0, 0.355, side * 0.36), Basis(Vector3.UP, side * PI / 2), paint)
			# A closed folded section leaves its hollow visible at the ends. Its
			# inward lips stop outside the rubber's unchanged 0.32 m half-width.
			var guard_section := PackedVector2Array([Vector2(-0.047, -0.04), Vector2(0.018, -0.04),
				Vector2(0.018, -0.015), Vector2(-0.024, -0.015), Vector2(-0.024, 0.015),
				Vector2(0.018, 0.015), Vector2(0.018, 0.04), Vector2(-0.047, 0.04)])
			var guard_basis := Basis(Vector3.UP, side * PI / 2)
			if drive_axis == 2:
				# Keep a real opening around the existing Z-axis drive stub.
				for end in [-1.0, 1.0]:
					_part(parent, "GuardHalf", suffix + ("N" if end < 0 else "P"),
						ProductionVisuals.prism_mesh(guard_section, 0.57, 0.003),
						Vector3(end * 0.405, 0.57, side * 0.36), guard_basis, paint)
			else:
				_part(parent, "GuardRail", suffix, ProductionVisuals.prism_mesh(guard_section, 1.38, 0.003),
					Vector3(0, 0.57, side * 0.36), guard_basis, paint)
			var post_profile := PackedVector2Array([Vector2(-0.035, -0.0725), Vector2(0.035, -0.0725),
				Vector2(0.035, -0.045), Vector2(0.025, 0.0725),
				Vector2(-0.025, 0.0725), Vector2(-0.035, -0.045)])
			for end in [-1.0, 1.0]:
				_part(parent, "GuardPost", suffix + ("N" if end < 0 else "P"),
					ProductionVisuals.prism_mesh(post_profile, 0.035, 0.002),
					Vector3(end * 0.30, 0.4575, side * 0.36), Basis.IDENTITY, paint)
		parent.set_meta("conveyor_frame", true)
		return true

class ProductionConveyorHubArt:
	extends RefCounted
	## A compact view of the native point hub, not a new shaft or drive route.
	static var journals: Dictionary = {}

	static func _part(parent: Node3D, role: String, suffix: String, mesh: Mesh, at: Vector3,
			finish: StandardMaterial3D, orientation: Basis = Basis.IDENTITY) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role + suffix
		part.set_meta("conveyor_hub_role", role)
		part.mesh = mesh
		part.position = at
		part.basis = orientation
		part.material_override = finish
		parent.add_child(part)
		return part

	static func mount(parent: Node3D, axis: Vector3, color: Color) -> bool:
		var paint := ProductionCoating.material(color)
		var steel := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)
		var warm := ProductionTransmissionFinish.material("worked", Color("b87945"), 0.85, 0.4)
		if paint == null or steel == null or warm == null:
			return false
		var rail := PackedVector2Array([Vector2(-0.0125, -0.0175), Vector2(0.0125, -0.0175),
			Vector2(0.0125, 0.0175), Vector2(-0.0125, 0.0175)])
		for side in [-1.0, 1.0]:
			var suffix := "N" if side < 0 else "P"
			_part(parent, "HubCarrierRail", suffix, ProductionVisuals.prism_mesh(rail, 0.74, 0.0015),
				Vector3(side * 0.0625, 0.4325, 0), paint)
			for end in [-1.0, 1.0]:
				_part(parent, "HubMountCleat", suffix + ("N" if end < 0 else "P"),
					ProductionVisuals.box_mesh(Vector3(0.025, 0.033, 0.024)), Vector3(side * 0.0625, 0.4005, end * 0.36), paint)
		var vertical := axis == Vector3.UP
		var housing: PackedVector2Array
		if vertical:
			housing = PackedVector2Array([Vector2(0.039, -0.03), Vector2(0.057, -0.03),
				Vector2(0.06, -0.027), Vector2(0.06, 0.027), Vector2(0.057, 0.03),
				Vector2(0.039, 0.03), Vector2(0.039, -0.03)])
			var fork := PackedVector2Array([Vector2(0.05, 0.447), Vector2(0.075, 0.447),
				Vector2(0.055, 0.472), Vector2(0.042, 0.472)])
			for side in [-1.0, 1.0]:
				var profile := fork.duplicate()
				for n in range(profile.size()):
					profile[n].x *= side
				_part(parent, "HubFork", "N" if side < 0 else "P", ProductionVisuals.prism_mesh(profile, 0.018, 0.001),
					Vector3.ZERO, paint)
		else:
			housing = PackedVector2Array([Vector2(0.039, -0.05), Vector2(0.0405, -0.05),
				Vector2(0.042, -0.0485), Vector2(0.042, 0.0485), Vector2(0.0405, 0.05),
				Vector2(0.039, 0.05), Vector2(0.039, -0.05)])
			_part(parent, "HubBridge", "", ProductionVisuals.box_mesh(Vector3(0.15, 0.01, 0.028)),
				Vector3(0, 0.4475, 0), paint)
			_part(parent, "HubPedestal", "", ProductionVisuals.box_mesh(Vector3(0.024, 0.01, 0.026)),
				Vector3(0, 0.455, 0), paint)
		var at := Vector3(0, Geometry.ANCHOR_HEIGHT, 0)
		var orientation := Basis(Quaternion(Vector3.UP, axis))
		_part(parent, "HubHousing", "", ProductionVisuals.turned_mesh(housing), at, paint if vertical else steel, orientation)
		if not journals.has(vertical):
			var journal := CylinderMesh.new()
			journal.top_radius = 0.028
			journal.bottom_radius = 0.028
			journal.height = 0.08 if vertical else 0.12
			journal.radial_segments = 48
			journals[vertical] = journal
		var spindle := _part(parent, "HubJournal", "", journals[vertical], at, warm, orientation)
		spindle.name = "DriveStub"
		parent.set_meta("conveyor_hub", true)
		return true
