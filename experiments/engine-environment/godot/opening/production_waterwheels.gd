extends RefCounted
## Render resources only; no scene controller or simulation authority.
const Geometry = preload("res://opening/site_geometry.gd")
const ProductionEnvironment = preload("res://opening/production_environment.gd").ProductionEnvironment
const ProductionTransmissionFinish = preload("res://opening/production_surfaces.gd").ProductionTransmissionFinish
const ProductionVisuals = preload("res://opening/production_surfaces.gd").ProductionVisuals

class ProductionWheelArt:
	extends RefCounted
	## A reusable visual component. Native geometry and motion never read this mesh.
	const ROOT := "res://opening/assets/waterwheel"
	const CENTRE_COLOR := "wood_center_albedo.webp"
	const FILES := ["rim.gltf", "rim.bin", "hub_spokes.gltf", "hub_spokes.bin",
		"wood_albedo.jpg", "wood_normal.webp", "wood_arm.webp", CENTRE_COLOR]
	const RIM_OUTER_RADIUS := 0.57
	const RIM_INNER_RADIUS := 0.506
	const HUB_OUTER_RADIUS := 0.06631
	const SPOKE_OUTER_RADIUS := 0.5241
	static var rim_mesh: ArrayMesh
	static var hub_spokes_mesh: ArrayMesh
	static var sized_rims: Dictionary = {}
	static var sized_centres: Dictionary = {}
	static var finish: StandardMaterial3D
	static var centre_finish: StandardMaterial3D
	static var source_status := "uninitialized"

	static func resource_status(directory: String = ROOT) -> String:
		var present := 0
		for name_value in FILES:
			var path := directory.path_join(name_value)
			var exists := ProductionVisuals.image_exists(path) if name_value.get_extension() in ["jpg", "webp"] else FileAccess.file_exists(path)
			if exists:
				present += 1
		if present == 0:
			return "missing"
		return "complete" if present == FILES.size() else "incomplete"

	static func _read_mesh(file_name: String) -> ArrayMesh:
		var document := GLTFDocument.new()
		var imported := GLTFState.new()
		if document.append_from_file(ROOT.path_join(file_name), imported) != OK:
			return null
		var sources := imported.get_meshes()
		if sources.size() != 1 or sources[0].mesh == null or sources[0].mesh.get_surface_count() != 1:
			return null
		var prepared: ArrayMesh = sources[0].mesh.get_mesh()
		var arrays := prepared.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_TANGENT] == null or arrays[Mesh.ARRAY_TANGENT].is_empty():
			var surface := SurfaceTool.new()
			surface.create_from(prepared, 0)
			surface.generate_tangents()
			prepared = surface.commit()
		return prepared

	static func _prepare() -> void:
		source_status = resource_status()
		if source_status == "missing":
			# Old fixed source rosters have no art resources. Their earlier
			# procedural rotor remains explicit rather than claiming sourced art.
			return
		if source_status != "complete":
			push_error("The sourced waterwheel resource set is incomplete.")
			return
		source_status = "invalid"
		# Read only mesh data. This creates no asset scene, requires no editor
		# import cache, and cannot mount a source controller or collision body.
		var split_rim := _read_mesh("rim.gltf")
		var split_inner := _read_mesh("hub_spokes.gltf")
		if split_rim == null or split_inner == null:
			push_error("The separated waterwheel components cannot be loaded.")
			return
		var images: Dictionary = {}
		for role: String in ["albedo", "normal", "arm"]:
			var name_value: String = "wood_albedo.jpg" if role == "albedo" else "wood_" + role + ".webp"
			var image := ProductionVisuals.read_image(ROOT.path_join(name_value))
			var expected := Vector2i(1024, 1024) if role == "albedo" else Vector2i(512, 512)
			if image == null or image.get_size() != expected or image.generate_mipmaps(role == "normal") != OK:
				push_error("Cannot prepare the waterwheel material: " + role)
				return
			images[role] = image
		var material := StandardMaterial3D.new()
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color.WHITE
		material.albedo_texture = ImageTexture.create_from_image(images.albedo)
		var arm := ImageTexture.create_from_image(images.arm)
		material.metallic = 1.0
		material.metallic_texture = arm
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		material.roughness = 1.0
		material.roughness_texture = arm
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		material.ao_enabled = true
		material.ao_texture = arm
		material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.ao_light_affect = 0.0
		material.normal_enabled = true
		material.normal_texture = ImageTexture.create_from_image(images.normal)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var centre_color := ProductionVisuals.read_image(ROOT.path_join(CENTRE_COLOR))
		if centre_color == null or centre_color.get_size() != Vector2i(1024, 1024) \
			or centre_color.generate_mipmaps(false) != OK:
			push_error("Cannot prepare the wheel center color grade.")
			return
		var centre_material := material.duplicate() as StandardMaterial3D
		centre_material.albedo_texture = ImageTexture.create_from_image(centre_color)
		rim_mesh = split_rim
		hub_spokes_mesh = split_inner
		sized_rims.clear()
		sized_centres.clear()
		finish = material
		centre_finish = centre_material
		source_status = "ready"

	static func support_timber_finish() -> StandardMaterial3D:
		if source_status == "uninitialized":
			_prepare()
		return centre_finish if source_status == "ready" else null

	static func _sized_mesh(source: ArrayMesh, tiles: int, outer: bool) -> ArrayMesh:
		if tiles <= 3:
			return source
		var arrays := source.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var ratio := sqrt(3.0 / float(tiles))
		var rim_inner := RIM_OUTER_RADIUS - (RIM_OUTER_RADIUS - RIM_INNER_RADIUS) * ratio
		var spoke_outer := rim_inner + (SPOKE_OUTER_RADIUS - RIM_INNER_RADIUS)
		for n in range(vertices.size()):
			var point := vertices[n]
			var radius := Vector2(point.x, point.y).length()
			if radius < 0.000001:
				continue
			var slope := ratio
			var target_radius := RIM_OUTER_RADIUS - (RIM_OUTER_RADIUS - radius) * ratio
			if not outer:
				if radius <= HUB_OUTER_RADIUS:
					target_radius = radius * ratio
				else:
					slope = (spoke_outer - HUB_OUTER_RADIUS * ratio) / (SPOKE_OUTER_RADIUS - HUB_OUTER_RADIUS)
					target_radius = HUB_OUTER_RADIUS * ratio + (radius - HUB_OUTER_RADIUS) * slope
			var radial := Vector2(point.x, point.y) / radius
			var angular := Vector2(-radial.y, radial.x)
			var original_normal := normals[n]
			var in_plane := Vector2(original_normal.x, original_normal.y)
			var transformed := radial * (in_plane.dot(radial) / slope) \
				+ angular * (in_plane.dot(angular) * radius / target_radius)
			vertices[n] = Vector3(radial.x * target_radius, radial.y * target_radius, point.z)
			var new_normal := Vector3(transformed.x, transformed.y, original_normal.z).normalized()
			normals[n] = new_normal
			var original_tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
			var tangent_plane := Vector2(original_tangent.x, original_tangent.y)
			var mapped := radial * (tangent_plane.dot(radial) * slope) \
				+ angular * (tangent_plane.dot(angular) * target_radius / radius)
			var new_tangent := Vector3(mapped.x, mapped.y, original_tangent.z)
			new_tangent = (new_tangent - new_normal * new_tangent.dot(new_normal)).normalized()
			tangents[n * 4] = new_tangent.x
			tangents[n * 4 + 1] = new_tangent.y
			tangents[n * 4 + 2] = new_tangent.z
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		var prepared := ArrayMesh.new()
		prepared.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return prepared

	static func rim_for_tiles(tiles: int) -> ArrayMesh:
		if tiles <= 3 or rim_mesh == null:
			return rim_mesh
		if not sized_rims.has(tiles):
			sized_rims[tiles] = _sized_mesh(rim_mesh, tiles, true)
		return sized_rims[tiles]

	static func centre_for_tiles(tiles: int) -> ArrayMesh:
		if tiles <= 3 or hub_spokes_mesh == null:
			return hub_spokes_mesh
		if not sized_centres.has(tiles):
			sized_centres[tiles] = _sized_mesh(hub_spokes_mesh, tiles, false)
		return sized_centres[tiles]

	static func mount(parent: Node3D, tiles: int = 3) -> bool:
		if source_status == "uninitialized":
			_prepare()
		if source_status != "ready":
			return false
		var pieces := [["SourcedTimberRotor", centre_for_tiles(tiles), 0.0],
			["SourcedTimberRimN", rim_for_tiles(tiles), -0.08], ["SourcedTimberRimP", rim_for_tiles(tiles), 0.08]]
		for piece in pieces:
			var rotor := MeshInstance3D.new()
			rotor.name = piece[0]
			rotor.mesh = piece[1]
			rotor.position.z = piece[2]
			rotor.material_override = centre_finish if piece[2] == 0.0 else finish
			rotor.set_meta("detail_role", "SourcedTimberRotor" if piece[2] == 0.0 else "SourcedTimberRim")
			rotor.set_meta("source_asset", "Poly Haven spinning_wheel_01")
			parent.add_child(rotor)
		return true

class ProductionPaddleArt:
	extends RefCounted
	## Original blade joinery and qualified timber. No power or work authority.
	const ROOT := "res://opening/assets/wheel-paddles"
	const FILES := {"albedo": "timber_albedo.jpg", "normal": "timber_normal_gl.webp", "roughness": "timber_roughness.webp"}
	const TILE_METRES := 0.6
	# Only small joinery is distance-cullable. The blade, spoke and rim
	# silhouette stays present at every distance.
	const DETAIL_END_METRES := {"PaddleBolt": 18.0, "PaddleIronStrap": 26.0, "PaddleRootCleat": 32.0}
	static var finish: StandardMaterial3D
	static var source_status := "uninitialized"
	static var meshes: Dictionary = {}

	static func read_images(directory: String = ROOT) -> Dictionary:
		var loaded := ProductionVisuals.read_image_set(directory, FILES,
			{"albedo": Vector2i(1024, 1024), "normal": Vector2i(512, 512), "roughness": Vector2i(512, 512)},
			"incomplete_timber_set")
		if loaded.status == "ready":
			for role in loaded.images:
				loaded.images[role].convert(Image.FORMAT_L8 if role == "roughness" else Image.FORMAT_RGB8)
		return loaded

	static func _prepare() -> void:
		var loaded := read_images()
		source_status = loaded.status
		if source_status == "missing":
			return
		if source_status != "ready":
			push_error("Invalid paddle timber: " + str(loaded.get("reason", "unknown")))
			return
		for role in loaded.images:
			var image: Image = loaded.images[role]
			if image.generate_mipmaps(role == "normal") != OK:
				source_status = "invalid"
				push_error("Cannot generate paddle timber mipmaps.")
				return
		finish = StandardMaterial3D.new()
		finish.albedo_color = Color.WHITE
		finish.albedo_texture = ImageTexture.create_from_image(loaded.images.albedo)
		finish.metallic = 0.0
		finish.roughness = 1.0
		finish.roughness_texture = ImageTexture.create_from_image(loaded.images.roughness)
		finish.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		finish.normal_enabled = true
		finish.normal_texture = ImageTexture.create_from_image(loaded.images.normal)
		# The source's current page and older scale metadata disagree. This is
		# an explicit visual mapping, never a measured native dimension. Broad
		# blade faces use UV=(radial X, axial Z), so grain V runs along the span.
		finish.uv1_scale = Vector3.ONE / TILE_METRES
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role
		part.mesh = mesh
		part.position = at
		part.material_override = material
		part.set_meta("detail_role", role)
		if DETAIL_END_METRES.has(role):
			part.visibility_range_end = DETAIL_END_METRES[role]
			part.visibility_range_end_margin = 2.0
		parent.add_child(part)
		return part

	static func timber_mesh(size: Vector3, physical_scale: Vector3 = Vector3.ONE) -> ArrayMesh:
		var original := ProductionVisuals.box_mesh(size)
		if physical_scale == Vector3.ONE:
			return original
		var key := [size, physical_scale]
		if meshes.has(key):
			return meshes[key]
		var arrays := original.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for n in range(coordinates.size()):
			# Keep the original face projection and board-local grain phase.
			# The rotor scales its two radial axes equally, so paddle rotation
			# does not change these physical lengths or make the grain swim.
			var direction := normals[n].abs()
			var repeat_scale := Vector2(physical_scale.x, physical_scale.y)
			if direction.x >= direction.y and direction.x >= direction.z:
				repeat_scale = Vector2(physical_scale.y, physical_scale.z)
			elif direction.y >= direction.z:
				repeat_scale = Vector2(physical_scale.x, physical_scale.z)
			coordinates[n] *= repeat_scale
		arrays[Mesh.ARRAY_TEX_UV] = coordinates
		# Positive per-face UV scaling preserves the original tangent directions,
		# vertex geometry, normals and clockwise winding.
		var prepared := ArrayMesh.new()
		prepared.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		meshes[key] = prepared
		return prepared

	static func mount(parent: Node3D, angle: float, index: int, physical_scale: Vector3 = Vector3.ONE) -> bool:
		if source_status == "uninitialized":
			_prepare()
		if source_status != "ready":
			return false
		var blade := _part(parent, "WheelPaddle", timber_mesh(Vector3(0.14, 0.018, 0.28), physical_scale),
			Vector3(cos(angle), sin(angle), 0) * 0.62, finish)
		blade.rotation.z = angle
		blade.set_meta("paddle_index", index)
		_part(blade, "PaddleRootCleat", timber_mesh(Vector3(0.04, 0.06, 0.10), physical_scale),
			Vector3(-0.05, 0, 0), finish)
		# Two continuous edge ribs stiffen the board without increasing its
		# confirmed radial or axial envelope. Their grain uses the same local
		# physical repeat as the broad paddle, even on a larger wheel.
		for side in [-1.0, 1.0]:
			_part(blade, "PaddleEdgeRib", timber_mesh(Vector3(0.12, 0.038, 0.018), physical_scale),
				Vector3(-0.005, 0.022, side * 0.129), finish)
		var iron := ProductionTransmissionFinish.material("worked", Color("46504e"), 0.85, 0.48)
		if iron == null:
			blade.free()
			return false
		# A folded outer wear strip stays physically thin as the native-selected
		# wheel diameter changes. It is passive protection, not a new water rule.
		if not meshes.has("wear_strip"):
			meshes["wear_strip"] = ProductionVisuals.prism_mesh(PackedVector2Array([
				Vector2(-0.026, -0.004), Vector2(0, -0.004), Vector2(0, 0.003),
				Vector2(-0.006, 0.048), Vector2(-0.018, 0.048), Vector2(-0.026, 0.038)]), 0.28, 0.001)
		var wear := _part(blade, "PaddleWearStrip", meshes["wear_strip"],
			Vector3(0.07, 0.009 + 0.004 / physical_scale.y, 0), iron)
		wear.scale = Vector3(1.0 / physical_scale.x, 1.0 / physical_scale.y, 1.0)
		if not meshes.has("bolt"):
			var bolt := CylinderMesh.new()
			bolt.top_radius = 0.013
			bolt.bottom_radius = 0.013
			bolt.height = 0.01
			bolt.radial_segments = 6
			meshes["bolt"] = bolt
		for z in [-0.04, 0.04]:
			_part(blade, "PaddleIronStrap", ProductionVisuals.box_mesh(Vector3(0.07, 0.006, 0.025)),
				Vector3(-0.035, -0.033, z), iron)
			# The rotor grows radially but a machined head keeps its actual size.
			# Its upper face meets the existing strap's flat underside.
			var bolt := _part(blade, "PaddleBolt", meshes.bolt,
				Vector3(-0.05, -0.036 - 0.005 / physical_scale.y, z), iron)
			bolt.scale = Vector3.ONE / physical_scale
		return true

class ProductionWheelSupportArt:
	extends RefCounted
	## Original fixed castings. The existing rotor and native journal stay exact.
	static var fasteners: Dictionary = {}

	static func _scaled(profile: PackedVector2Array, scale_factor: float) -> PackedVector2Array:
		var result := profile.duplicate()
		for n in range(result.size()):
			result[n] *= scale_factor
		return result

	static func _part(parent: Node3D, role: String, suffix: String, mesh: Mesh, at: Vector3,
			orientation: Basis, finish: Material) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role + suffix
		part.set_meta("wheel_support_role", role)
		part.mesh = mesh
		part.position = at
		part.basis = orientation
		part.material_override = finish
		parent.add_child(part)
		return part

	static func mount(parent: Node3D, axis: Vector3, scale_factor: float, height_factor: float) -> void:
		var cast := ProductionTransmissionFinish.material("cast", Color("465a60"), 0.85, 0.55)
		var worked := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)
		# Bake scale into the mesh coordinates so the shared local material's
		# quarter-metre repeat is not shrunk by a node transform.
		var housing := PackedVector2Array([Vector2(0.15, -0.09), Vector2(0.17, -0.09),
			Vector2(0.185, -0.075), Vector2(0.185, -0.055), Vector2(0.17, -0.04),
			Vector2(0.17, 0.04), Vector2(0.185, 0.055), Vector2(0.185, 0.075),
			Vector2(0.17, 0.09), Vector2(0.15, 0.09), Vector2(0.15, -0.09)])
		var liner := PackedVector2Array([Vector2(0.135, -0.10), Vector2(0.156, -0.10),
			Vector2(0.16, -0.096), Vector2(0.16, -0.091), Vector2(0.1495, -0.085),
			Vector2(0.1495, 0.085), Vector2(0.16, 0.091), Vector2(0.16, 0.096),
			Vector2(0.156, 0.10), Vector2(0.135, 0.10), Vector2(0.135, -0.10)])
		var housing_mesh := ProductionVisuals.turned_mesh(_scaled(housing, scale_factor))
		var liner_mesh := ProductionVisuals.turned_mesh(_scaled(liner, scale_factor))
		if not fasteners.has(scale_factor):
			var bolt := CylinderMesh.new()
			bolt.top_radius = 0.022 * scale_factor
			bolt.bottom_radius = bolt.top_radius
			bolt.height = 0.018 * scale_factor
			bolt.radial_segments = 6
			fasteners[scale_factor] = bolt
		var bearing_frame := Basis(Quaternion(Vector3.UP, axis))
		if axis == Vector3.UP:
			var pedestal := PackedVector2Array([Vector2(0, 0.24), Vector2(0.18, 0.24),
				Vector2(0.195, 0.25), Vector2(0.195, 0.32), Vector2(0.19, 0.34),
				Vector2(0.14, 0.34), Vector2(0.14, 0.44), Vector2(0.14, 0.46), Vector2(0, 0.46)])
			_part(parent, "WheelStand", "Vertical", ProductionVisuals.turned_mesh(_scaled(pedestal, scale_factor)),
				Vector3.ZERO, Basis.IDENTITY, cast)
			var center := Vector3.UP * 0.53 * scale_factor
			_part(parent, "AxleBearing", "Vertical", housing_mesh, center, bearing_frame, cast)
			_part(parent, "BearingLiner", "Vertical", liner_mesh, center, bearing_frame, worked)
			# The entire hexagonal lower face rests on the annular flat flange.
			for x in [-0.117, 0.117]:
				for z in [-0.117, 0.117]:
					_part(parent, "WheelFootBolt", ("N" if x < 0 else "P") + ("N" if z < 0 else "P"), fasteners[scale_factor],
						Vector3(x, 0.349, z) * scale_factor, Basis.IDENTITY, worked)
		else:
			# The shaped upright must enter the underside of the fixed bearing.
			# Its former 0.62-height top left a visible gap below the housing.
			var seat_height := 0.78 - 0.17 * scale_factor / height_factor
			var outline := PackedVector2Array([Vector2(-0.19, 0.24), Vector2(0.19, 0.24),
				Vector2(0.19, 0.32), Vector2(0.18, 0.36), Vector2(0.075, 0.36),
				Vector2(0.065, 0.58), Vector2(0.065, seat_height), Vector2(-0.065, seat_height),
				Vector2(-0.065, 0.58), Vector2(-0.075, 0.36), Vector2(-0.18, 0.36), Vector2(-0.19, 0.32)])
			for n in range(outline.size()):
				outline[n] = Vector2(outline[n].x * scale_factor, outline[n].y * height_factor)
			var stand_mesh := ProductionVisuals.prism_mesh(outline,
				0.18 * scale_factor, 0.008 * scale_factor)
			var stand_frame := Basis(Vector3.UP, PI / 2) if axis == Vector3.RIGHT else Basis.IDENTITY
			for side in [-1.0, 1.0]:
				var suffix := "N" if side < 0 else "P"
				var offset: Vector3 = axis * side * 0.24 * scale_factor
				_part(parent, "WheelStand", suffix, stand_mesh, offset, stand_frame, cast)
				var center: Vector3 = offset + Vector3.UP * 0.78 * height_factor
				_part(parent, "AxleBearing", suffix, housing_mesh, center, bearing_frame, cast)
				_part(parent, "BearingLiner", suffix, liner_mesh, center, bearing_frame, worked)
				for x in [-0.13, 0.13]:
					_part(parent, "WheelFootBolt", suffix + ("L" if x < 0 else "R"), fasteners[scale_factor],
						offset + stand_frame * Vector3(x * scale_factor, 0.36 * height_factor + 0.009 * scale_factor, 0), Basis.IDENTITY, worked)

class ProductionWheelPierArt:
	extends RefCounted
	## Meshes consume the native Host's two terrain-seated support envelopes.
	## They introduce no independently chosen footprint or mechanical state.
	static func _beam(parent: Node3D, name_value: String, start: Vector3, finish_at: Vector3,
			width: float, surface: Material) -> void:
		var direction := finish_at - start
		var part := MeshInstance3D.new()
		part.name = name_value
		# The beveled mesh uses world-sized UVs, so the sourced grain keeps its
		# scale along riverbed-height braces instead of stretching one image.
		part.mesh = ProductionVisuals.box_mesh(Vector3(width, direction.length(), width))
		part.material_override = surface
		part.position = (start + finish_at) * 0.5
		part.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
		part.set_meta("wheel_support_role", "RiverPier")
		parent.add_child(part)

	static func mount(parent: Node3D, entity: Dictionary) -> bool:
		var projected: Dictionary = Geometry.wheel_support_boxes(entity)
		if not projected.get("accepted", false):
			return false
		var axis: int = int(entity.get("axis", -1))
		if axis not in [0, 2]:
			return false
		var radial := Vector3.BACK if axis == 0 else Vector3.RIGHT
		var worked := ProductionTransmissionFinish.material("cast", Color("465a60"), 0.85, 0.55)
		var timber: Material = ProductionWheelArt.support_timber_finish()
		if timber == null:
			timber = worked
		var stone := ProductionEnvironment.stone_material()
		for original: Dictionary in projected.boxes:
			var middle: Vector3 = original.center - parent.position
			var size: Vector3 = original.size
			var low: float = middle.y - size.y * 0.5
			var high: float = middle.y + size.y * 0.5
			for side in [-1.0, 1.0]:
				_beam(parent, "RiverPierBrace", middle + radial * side * 0.32 + Vector3.UP * (low - middle.y + 0.12),
					middle + Vector3.UP * (high - middle.y - 0.11), 0.22, timber)
			var cap := MeshInstance3D.new()
			cap.name = "RiverPierCap"
			cap.mesh = ProductionVisuals.box_mesh(Vector3(size.x, 0.12, size.z))
			cap.position = Vector3(middle.x, high - 0.06, middle.z)
			cap.material_override = worked
			cap.set_meta("wheel_support_role", "RiverPierCap")
			parent.add_child(cap)
			var foot := MeshInstance3D.new()
			foot.name = "RiverPierFoot"
			foot.mesh = ProductionVisuals.box_mesh(Vector3(size.x, 0.18, size.z))
			foot.position = Vector3(middle.x, low + 0.09, middle.z)
			foot.material_override = stone
			foot.set_meta("wheel_support_role", "RiverPierFoot")
			parent.add_child(foot)
		return true
