extends Node3D
## Input and presentation only. The native model owns ordinary material and build mutations.

const NativeWorldModel = preload("res://opening/native_model.gd")
const RecoveryActions = preload("res://opening/recovery_actions.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
const ActorWorld = preload("res://opening/actor_world.gd")
const CharacterPresenter = preload("res://opening/character_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const BuildingHotbar = preload("res://opening/building_hotbar.gd")
const ArrivalRevealAudio = preload("res://opening/arrival_reveal_audio.gd")
const ConstructionAudio = preload("res://opening/construction_audio.gd")
const MechanicalAmbience = preload("res://opening/mechanical_ambience.gd")
const ProductionInterface = preload("res://opening/production_interface.gd")

class ProductionVisuals:
	extends RefCounted
	## Presentation is self-contained in this already captured opening script.

	static func image_exists(path: String) -> bool:
		return ResourceLoader.exists(path, "Texture2D") if path.begins_with("res://") else FileAccess.file_exists(path)

	static func read_image(path: String) -> Image:
		# Project images are imported resources, including when raw source files
		# are absent in a package. Preparation fixtures use external files.
		if not path.begins_with("res://"):
			return Image.load_from_file(path)
		# Decode available source bytes before asking an imported texture for
		# its image. Exports may omit source files, so retain
		# the imported-resource path below.
		if FileAccess.file_exists(path):
			var bytes := FileAccess.get_file_as_bytes(path)
			if not bytes.is_empty():
				var source := Image.new()
				var decoded := ERR_FILE_UNRECOGNIZED
				match path.get_extension().to_lower():
					"webp": decoded = source.load_webp_from_buffer(bytes)
					"jpg", "jpeg": decoded = source.load_jpg_from_buffer(bytes)
					"png": decoded = source.load_png_from_buffer(bytes)
				if decoded == OK and not source.is_empty():
					return source
		if not ResourceLoader.exists(path, "Texture2D"):
			return null
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		var image := texture.get_image() if texture != null else null
		if image != null and image.is_compressed() and image.decompress() != OK:
			return null
		return image

	static func _surface_noise() -> FastNoiseLite:
		var noise := FastNoiseLite.new()
		noise.seed = 1627
		noise.frequency = 0.13
		noise.fractal_octaves = 3
		return noise

	static var SURFACE_HEIGHT := _surface_noise()

	static func _surface_texture(normal_map: bool) -> NoiseTexture2D:
		var texture := NoiseTexture2D.new()
		texture.width = 256
		texture.height = 256
		texture.seamless = true
		texture.generate_mipmaps = true
		texture.noise = SURFACE_HEIGHT
		if normal_map:
			texture.as_normal_map = true
			texture.bump_strength = 1.5
		else:
			var ramp := Gradient.new()
			ramp.colors = PackedColorArray([Color(0.72, 0.72, 0.72, 1), Color.WHITE])
			texture.color_ramp = ramp
		return texture

	static var SURFACE_GRAIN := _surface_texture(false)
	static var SURFACE_NORMAL := _surface_texture(true)

	static var meshes: Dictionary = {}
	static var finishes: Dictionary = {}

	static func material(color: Color, metal: float, roughness: float) -> StandardMaterial3D:
		var key := [color, metal, roughness]
		if finishes.has(key):
			return finishes[key]
		var finish := StandardMaterial3D.new()
		finish.albedo_color = color
		finish.metallic = metal
		finish.roughness = roughness
		finish.roughness_texture = SURFACE_GRAIN
		finish.normal_enabled = true
		finish.normal_texture = SURFACE_NORMAL
		finish.normal_scale = 0.18
		finish.uv1_scale = Vector3(3, 3, 1)
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		finishes[key] = finish
		return finish

	static func _uv(point: Vector3, normal: Vector3) -> Vector2:
		var direction := normal.abs()
		if direction.x >= direction.y and direction.x >= direction.z:
			return Vector2(point.y, point.z)
		if direction.y >= direction.z:
			return Vector2(point.x, point.z)
		return Vector2(point.x, point.y)

	static func _face(surface: SurfaceTool, points: Array[Vector3], normal: Vector3) -> void:
		# Godot uses clockwise front faces. Explicit flat normals keep machined
		# shoulders crisp; tangents are generated from the actual planar UVs.
		if (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) > 0:
			points.reverse()
		for index in range(1, points.size() - 1):
			for point in [points[0], points[index], points[index + 1]]:
				surface.set_normal(normal)
				surface.set_uv(_uv(point, normal))
				surface.add_vertex(point)

	static func box_mesh(dimensions: Vector3) -> ArrayMesh:
		if meshes.has(dimensions):
			return meshes[dimensions]
		var half := dimensions / 2.0
		var bevel := minf(0.014, minf(dimensions.x, minf(dimensions.y, dimensions.z)) * 0.12)
		var inner := half - Vector3.ONE * bevel
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Six broad faces, twelve chamfer shoulders and eight closed corners.
		for axis in range(3):
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			for side in [-1.0, 1.0]:
				var normal := Vector3.ZERO
				normal[axis] = side
				var points: Array[Vector3] = []
				for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var point := Vector3.ZERO
					point[axis] = side * half[axis]
					point[u] = corner.x * inner[u]
					point[v] = corner.y * inner[v]
					points.append(point)
				_face(surface, points, normal)
		# Each pair of face axes meets in one shoulder on either side.
		for a in range(3):
			for b in range(a + 1, 3):
				var along := 3 - a - b
				for sa in [-1.0, 1.0]:
					for sb in [-1.0, 1.0]:
						var normal := Vector3.ZERO
						normal[a] = sa
						normal[b] = sb
						var points: Array[Vector3] = []
						for end in [-1.0, 1.0]:
							var p := Vector3.ZERO
							p[a] = sa * half[a]
							p[b] = sb * inner[b]
							p[along] = end * inner[along]
							var q := p
							q[a] = sa * inner[a]
							q[b] = sb * half[b]
							if end < 0:
								points.append_array([p, q])
							else:
								points.append_array([q, p])
						_face(surface, points, normal.normalized())
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					var signs := Vector3(x, y, z)
					_face(surface, [Vector3(x * half.x, y * inner.y, z * inner.z),
						Vector3(x * inner.x, y * half.y, z * inner.z),
						Vector3(x * inner.x, y * inner.y, z * half.z)], signs.normalized())
		surface.generate_tangents()
		var mesh := surface.commit()
		meshes[dimensions] = mesh
		return mesh


	static func turned_mesh(profile: PackedVector2Array, segments: int = 48) -> ArrayMesh:
		var key := "turned/" + Marshalls.raw_to_base64(var_to_bytes([profile, segments]))
		if meshes.has(key):
			return meshes[key]
		var low := INF
		var high := -INF
		for point in profile:
			low = minf(low, point.y)
			high = maxf(high, point.y)
		var height := maxf(0.000001, high - low)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for row in range(profile.size() - 1):
			var a := profile[row]
			var b := profile[row + 1]
			var slope := Vector2(b.y - a.y, a.x - b.x).normalized()
			for n in range(segments):
				var angles := [float(n) * TAU / segments, float(n + 1) * TAU / segments]
				var points: Array[Vector3] = []
				var normals: Array[Vector3] = []
				var coordinates: Array[Vector2] = []
				for corner in [[a, 0], [a, 1], [b, 1], [b, 0]]:
					var p: Vector2 = corner[0]
					var angle: float = angles[corner[1]]
					var position := Vector3(cos(angle) * p.x, p.y, sin(angle) * p.x)
					points.append(position)
					normals.append(Vector3(cos(angle) * slope.x, slope.y, sin(angle) * slope.x))
					coordinates.append(Vector2(position.x, position.z) if absf(b.y - a.y) < 0.000001
						else Vector2(float(n + corner[1]) / segments, (p.y - low) / height))
				for triangle in [[0, 2, 3], [0, 1, 2]]:
					if (points[triangle[1]] - points[triangle[0]]).cross(points[triangle[2]] - points[triangle[0]]).length_squared() < 0.00000000000001:
						continue
					for index in triangle:
						surface.set_normal(normals[index])
						surface.set_uv(coordinates[index])
						surface.add_vertex(points[index])
		surface.generate_tangents()
		var mesh := surface.commit()
		meshes[key] = mesh
		return mesh

	static func prism_mesh(profile: PackedVector2Array, depth: float, bevel: float) -> ArrayMesh:
		var key := "prism/" + Marshalls.raw_to_base64(var_to_bytes([profile, depth, bevel]))
		if meshes.has(key):
			return meshes[key]
		var outline := profile.duplicate()
		var signed_area := 0.0
		for n in range(outline.size()):
			signed_area += outline[n].cross(outline[(n + 1) % outline.size()])
		if signed_area < 0:
			outline.reverse()
		# The fixed art profiles have generous corners. Intersect their inward
		# edge offsets rather than scaling a whole cap and distorting the bevel.
		var inset := PackedVector2Array()
		for n in range(outline.size()):
			var before := (outline[n] - outline[posmod(n - 1, outline.size())]).normalized()
			var after := (outline[(n + 1) % outline.size()] - outline[n]).normalized()
			var first := Vector2(-before.y, before.x)
			var second := Vector2(-after.y, after.x)
			inset.append(outline[n] + (first + second) * bevel / (1.0 + first.dot(second)))
		var triangles := Geometry2D.triangulate_polygon(inset)
		if triangles.size() != (inset.size() - 2) * 3:
			push_error("The authored casting cap cannot be triangulated.")
			return null
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var half := depth / 2.0
		for side in [-1.0, 1.0]:
			for n in range(0, triangles.size(), 3):
				var cap: Array[Vector3] = []
				for corner in range(3):
					var p := inset[triangles[n + corner]]
					cap.append(Vector3(p.x, p.y, side * half))
				ProductionVisuals._face(surface, cap, Vector3.BACK * side)
		for n in range(outline.size()):
			var next := (n + 1) % outline.size()
			var a := outline[n]
			var b := outline[next]
			var ia := inset[n]
			var ib := inset[next]
			var edge := (b - a).normalized()
			var normal := Vector3(edge.y, -edge.x, 0)
			ProductionVisuals._face(surface, [Vector3(a.x, a.y, -half + bevel),
				Vector3(b.x, b.y, -half + bevel), Vector3(b.x, b.y, half - bevel),
				Vector3(a.x, a.y, half - bevel)], normal)
			for side in [-1.0, 1.0]:
				ProductionVisuals._face(surface, [Vector3(a.x, a.y, side * (half - bevel)),
					Vector3(b.x, b.y, side * (half - bevel)), Vector3(ib.x, ib.y, side * half),
					Vector3(ia.x, ia.y, side * half)], (normal + Vector3.BACK * side).normalized())
		surface.generate_tangents()
		var mesh := surface.commit()
		meshes[key] = mesh
		return mesh

	static func fastener_head_mesh() -> CylinderMesh:
		if not meshes.has("fastener/hex"):
			var head := CylinderMesh.new()
			head.top_radius = 0.035
			head.bottom_radius = 0.035
			head.height = 0.024
			head.radial_segments = 6
			meshes["fastener/hex"] = head
		return meshes["fastener/hex"]

	static func cylinder_mesh(radius: float, height: float, segments: int = 48) -> CylinderMesh:
		var key := ["machine/cylinder", radius, height, segments]
		if not meshes.has(key):
			var result := CylinderMesh.new()
			result.top_radius = radius
			result.bottom_radius = radius
			result.height = height
			result.radial_segments = segments
			meshes[key] = result
		return meshes[key]

class ProductionTransmissionFinish:
	extends RefCounted
	## Shared surface presentation. Native dimensions and motion never read maps.
	const ROOT := "res://opening/assets/transmission-surfaces"
	const FILES := {"cast_normal": "cast_normal_gl.webp", "cast_roughness": "cast_roughness.webp",
		"worked_normal": "worked_normal_gl.webp", "worked_roughness": "worked_roughness.webp"}
	const CAST_METRES := 0.25
	const WORKED_METRES := 0.08
	static var source_status := "uninitialized"
	static var textures: Dictionary = {}
	static var finishes: Dictionary = {}

	static func read_images(directory: String = ROOT) -> Dictionary:
		var present := 0
		for file_name in FILES.values():
			if ProductionVisuals.image_exists(directory.path_join(file_name)):
				present += 1
		if present == 0:
			return {"status": "missing", "images": {}}
		if present != FILES.size():
			return {"status": "invalid", "reason": "incomplete_surface_set", "images": {}}
		var images: Dictionary = {}
		for role in FILES:
			var image := ProductionVisuals.read_image(directory.path_join(FILES[role]))
			var extent := 512 if role.begins_with("cast") else 256
			if image == null or image.is_empty() or image.get_size() != Vector2i(extent, extent):
				return {"status": "invalid", "reason": "invalid_" + role, "images": {}}
			images[role] = image
		return {"status": "ready", "images": images}

	static func _prepare() -> void:
		var loaded := read_images()
		source_status = loaded.status
		if source_status == "missing":
			return
		if source_status != "ready":
			push_error("Invalid transmission surface set: " + str(loaded.get("reason", "unknown")))
			return
		for role in loaded.images:
			var image: Image = loaded.images[role]
			if image.generate_mipmaps(role.ends_with("normal")) != OK:
				source_status = "invalid"
				push_error("Cannot generate transmission surface mipmaps.")
				return
			textures[role] = ImageTexture.create_from_image(image)

	static func material(role: String, color: Color, metal: float, fallback_roughness: float) -> StandardMaterial3D:
		if source_status == "uninitialized":
			_prepare()
		if source_status == "missing":
			return ProductionVisuals.material(color, metal, fallback_roughness)
		if source_status != "ready" or role not in ["cast", "worked"]:
			return null
		var key := [role, color, metal]
		if finishes.has(key):
			return finishes[key]
		var finish := StandardMaterial3D.new()
		# Keep the presenter's original motion tint. Source color is deliberately
		# omitted; these surface roles are not an alloy or operating-state ledger.
		finish.albedo_color = color
		finish.metallic = metal
		finish.roughness = 1.0
		finish.roughness_texture = textures[role + "_roughness"]
		finish.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		finish.normal_enabled = true
		finish.normal_texture = textures[role + "_normal"]
		finish.normal_scale = 0.35 if role == "cast" else 1.0
		# Local-space mapping follows the rigid part as it turns. Physical mesh
		# coordinates avoid stretching a normalized UV along a longer shaft.
		finish.uv1_triplanar = true
		finish.uv1_world_triplanar = false
		finish.uv1_triplanar_sharpness = 8.0
		finish.uv1_scale = Vector3.ONE / (CAST_METRES if role == "cast" else WORKED_METRES)
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		finishes[key] = finish
		return finish

class ProductionCollectorArt:
	extends RefCounted
	## Original rigid casting kit. These meshes never define work or collision.
	static var coatings: Dictionary = {}
	static var paint_roughness: ImageTexture

	static func _paint_roughness() -> ImageTexture:
		if paint_roughness != null:
			return paint_roughness
		var source: Image = ProductionTransmissionFinish.textures.cast_roughness.get_image()
		if source == null or source.is_empty():
			push_error("The qualified source cannot supply the authored coating response.")
			return null
		var bytes := PackedByteArray()
		bytes.resize(source.get_width() * source.get_height())
		for y in range(source.get_height()):
			for x in range(source.get_width()):
				var original := roundi(source.get_pixel(x, y).r * 255.0)
				# Preserve the source variation in a paint-only satin range. The
				# rounded L8 endpoints stay inside the provisional 0.65..0.90.
				bytes[y * source.get_width() + x] = clampi(roundi((663.0 + original) / 4.0), 166, 229)
		var image := Image.create_from_data(source.get_width(), source.get_height(), false, Image.FORMAT_L8, bytes)
		if image.generate_mipmaps() != OK:
			push_error("The authored coating response cannot retain its mip chain.")
			return null
		paint_roughness = ImageTexture.create_from_image(image)
		return paint_roughness

	static func coating(color: Color) -> StandardMaterial3D:
		if coatings.has(color):
			return coatings[color]
		var source := ProductionTransmissionFinish.material("cast", color, 0.0, 0.72)
		if ProductionTransmissionFinish.source_status == "missing":
			# Retain the exact earlier finish for historical fixed rosters.
			return ProductionVisuals.material(color, 0.08, 0.72)
		if source == null:
			return null
		var satin := _paint_roughness()
		if satin == null:
			return null
		# Share qualified image resources, never the mutable metal material.
		# This is an authored coating over cast detail, not a paint scan.
		var finish := source.duplicate(false) as StandardMaterial3D
		finish.normal_scale = 0.08
		finish.roughness_texture = satin
		coatings[color] = finish
		return finish

	static func cheek_profile(right: bool) -> PackedVector2Array:
		var points := PackedVector2Array([Vector2(-0.65, 0.24), Vector2(-0.65, 0.40),
			Vector2(-0.62, 0.47), Vector2(-0.62, 1.31), Vector2(-0.58, 1.48),
			Vector2(-0.49, 1.49), Vector2(-0.48, 1.44), Vector2(-0.50, 1.36),
			Vector2(-0.50, 0.62), Vector2(-0.40, 0.48), Vector2(-0.38, 0.38), Vector2(-0.38, 0.24)])
		if right:
			for n in range(points.size()):
				points[n].x = -0.39 - points[n].x
		return points


	static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: StandardMaterial3D) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role
		part.mesh = mesh
		part.position = at
		part.material_override = finish
		part.set_meta("collector_frame_role", role)
		parent.add_child(part)
		return part

	static func mount(parent: Node3D, color: Color) -> void:
		var frame := Node3D.new()
		frame.name = "CollectorCastFrame"
		parent.add_child(frame)
		var paint := coating(color)
		for right in [false, true]:
			_part(frame, "CastCheekRight" if right else "CastCheekLeft",
				ProductionVisuals.prism_mesh(cheek_profile(right), 0.18, 0.008), Vector3(0, 0, -0.40), paint)
		var housing := PackedVector2Array([Vector2(-0.62, 0.24), Vector2(0.23, 0.24),
			Vector2(0.23, 0.84), Vector2(0.12, 1.02), Vector2(-0.50, 1.02), Vector2(-0.62, 0.84)])
		_part(frame, "CastLowerHousing", ProductionVisuals.prism_mesh(housing, 0.14, 0.012),
			Vector3(0, 0, -0.44), coating(color.darkened(0.09)))
		# A neutral service cover has a folded lower return, angled shoulders and
		# a shallow crown. Its broad roof is a formed part, not a bright flat box.
		var hood := PackedVector2Array([Vector2(-0.65, 1.38), Vector2(0.26, 1.38),
			Vector2(0.26, 1.42), Vector2(0.22, 1.42), Vector2(0.22, 1.47),
			Vector2(0.15, 1.51), Vector2(-0.19, 1.54), Vector2(-0.53, 1.51),
			Vector2(-0.62, 1.47), Vector2(-0.62, 1.42), Vector2(-0.65, 1.42)])
		_part(frame, "CastUpperHood", ProductionVisuals.prism_mesh(hood, 0.64, 0.012),
			Vector3(0, 0, -0.25), coating(Color("394f59")))
		var hanger := PackedVector2Array([Vector2(-0.26, 1.21), Vector2(-0.18, 1.21),
			Vector2(-0.15, 1.32), Vector2(-0.13, 1.43), Vector2(-0.31, 1.43), Vector2(-0.29, 1.32)])
		_part(frame, "BearingHanger", ProductionVisuals.prism_mesh(hanger, 0.07, 0.007), Vector3(0, 0, 0.045), paint)
		var bearing := PackedVector2Array([Vector2(0.109, -0.025), Vector2(0.125, -0.025),
			Vector2(0.14, -0.015), Vector2(0.14, 0.015), Vector2(0.125, 0.025),
			Vector2(0.109, 0.025), Vector2(0.109, -0.025)])
		var housing_part := _part(frame, "FixedBearingHousing", ProductionVisuals.turned_mesh(bearing),
			Vector3(-0.22, 1.1, 0.045), paint)
		housing_part.basis = Basis(Quaternion(Vector3.UP, Vector3.BACK))
		var liner := PackedVector2Array([Vector2(0.095, -0.014), Vector2(0.109, -0.014),
			Vector2(0.109, 0.014), Vector2(0.095, 0.014), Vector2(0.095, -0.014)])
		var liner_part := _part(frame, "FixedBearingLiner", ProductionVisuals.turned_mesh(liner),
			Vector3(-0.22, 1.1, 0.045), ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38))
		liner_part.basis = housing_part.basis

class ProductionSkidArt:
	extends RefCounted
	## One original shared base resource. Empty channels are visual only.
	static var shared_mesh: ArrayMesh

	static func skid_mesh() -> ArrayMesh:
		if shared_mesh != null:
			return shared_mesh
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		# The mounting deck retains the exact old top and outer footprint.
		surface.append_from(ProductionVisuals.box_mesh(Vector3(1.35, 0.04, 1.35)), 0,
			Transform3D(Basis.IDENTITY, Vector3(0, 0.10, 0)))
		var channel := PackedVector2Array([Vector2(-0.105, -0.12), Vector2(0.105, -0.12),
			Vector2(0.105, -0.08), Vector2(-0.045, -0.08), Vector2(-0.045, 0.055),
			Vector2(0.105, 0.055), Vector2(0.105, 0.095), Vector2(-0.105, 0.095)])
		for side in [-1.0, 1.0]:
			var profile := channel.duplicate()
			for n in range(profile.size()):
				profile[n].x *= -side
			surface.append_from(ProductionVisuals.prism_mesh(profile, 1.35, 0.004), 0,
				Transform3D(Basis.IDENTITY, Vector3(side * 0.53, 0, 0)))
		for z in [-0.38, 0.38]:
			surface.append_from(ProductionVisuals.box_mesh(Vector3(1.08, 0.045, 0.06)), 0,
				Transform3D(Basis.IDENTITY, Vector3(0, 0.045, z)))
		shared_mesh = surface.commit()
		return shared_mesh

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
		var present := 0
		for name_value in FILES.values():
			if ProductionVisuals.image_exists(directory.path_join(name_value)):
				present += 1
		if present == 0:
			return {"status": "missing", "images": {}}
		if present != FILES.size():
			return {"status": "invalid", "reason": "incomplete_timber_set", "images": {}}
		var images: Dictionary = {}
		for role in FILES:
			var image := ProductionVisuals.read_image(directory.path_join(FILES[role]))
			var extent := 1024 if role == "albedo" else 512
			if image == null or image.is_empty() or image.get_size() != Vector2i(extent, extent):
				return {"status": "invalid", "reason": "invalid_" + role, "images": {}}
			image.convert(Image.FORMAT_L8 if role == "roughness" else Image.FORMAT_RGB8)
			images[role] = image
		return {"status": "ready", "images": images}

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

class ProductionFeedSleeveArt:
	extends RefCounted
	## Render the existing confirmed feed link. No stock, transfer or power rule.
	const CACHE_LENGTH_STEP := 0.00001
	const MINIMUM_RENDER_SPAN := 0.28
	const FLOOR_HEIGHT := 0.09
	static var bolt_mesh: CylinderMesh
	static var marking: StandardMaterial3D

	static func _part(parent: Node3D, role: String, suffix: String, mesh: Mesh,
			at: Vector3, orientation: Basis, finish: Material) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role + suffix
		part.set_meta("feed_sleeve_role", role)
		part.mesh = mesh
		part.position = at
		part.basis = orientation
		part.material_override = finish
		parent.add_child(part)
		return part

	static func mount(parent: Node3D, start: Vector3, finish: Vector3) -> bool:
		var offset: Vector3 = finish - start
		var span: float = offset.length()
		if not start.is_finite() or not finish.is_finite() or not offset.is_finite() \
				or not is_finite(span) or offset.y != 0 or span < MINIMUM_RENDER_SPAN:
			return false
		# Cache equivalent render lengths despite float packing at different
		# grid positions. This does not round a native pose, command or reach.
		var length: float = snappedf(span, CACHE_LENGTH_STEP)
		var direction: Vector3 = offset / span
		var across := Vector3(direction.z, 0, -direction.x)
		var channel := PackedVector2Array([Vector2(-0.292, -0.012), Vector2(0.292, -0.012),
			Vector2(0.292, 0.07), Vector2(0.28, 0.07), Vector2(0.28, 0),
			Vector2(-0.28, 0), Vector2(-0.28, 0.07), Vector2(-0.292, 0.07)])
		var cuff := PackedVector2Array([Vector2(-0.306, -0.026), Vector2(0.306, -0.026),
			Vector2(0.306, 0.07), Vector2(0.292, 0.07), Vector2(0.292, -0.012),
			Vector2(-0.292, -0.012), Vector2(-0.292, 0.07), Vector2(-0.306, 0.07)])
		var arrow := PackedVector2Array([Vector2(-0.09, -0.03), Vector2(-0.025, -0.03),
			Vector2(-0.025, -0.12), Vector2(0.025, -0.12), Vector2(0.025, -0.03),
			Vector2(0.09, -0.03), Vector2(0, 0.07)])
		var worked := ProductionTransmissionFinish.material("worked", Color("929e91"), 0.85, 0.52)
		var cast := ProductionTransmissionFinish.material("cast", Color("465a60"), 0.85, 0.55)
		var hardware := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)
		if worked == null or cast == null or hardware == null:
			return false
		if bolt_mesh == null:
			bolt_mesh = CylinderMesh.new()
			bolt_mesh.top_radius = 0.0115
			bolt_mesh.bottom_radius = 0.0115
			bolt_mesh.height = 0.014
			bolt_mesh.radial_segments = 6
		if marking == null:
			marking = StandardMaterial3D.new()
			marking.albedo_color = Color("e2c48b")
			marking.metallic = 0
			marking.roughness = 0.85
		parent.position = (start + finish) / 2.0
		parent.basis = Basis(across, Vector3.UP, direction)
		parent.set_meta("feed_sleeve", true)
		parent.set_meta("render_span", length)
		_part(parent, "FeedChannel", "", ProductionVisuals.prism_mesh(channel, length, 0.001),
			Vector3(0, FLOOR_HEIGHT, 0), Basis.IDENTITY, worked)
		for end in [-1.0, 1.0]:
			var suffix := "N" if end < 0 else "P"
			var z: float = end * (length / 2.0 - 0.0225)
			_part(parent, "FeedCuff", suffix, ProductionVisuals.prism_mesh(cuff, 0.045, 0.001),
				Vector3(0, FLOOR_HEIGHT, z), Basis.IDENTITY, cast)
			for side in [-1.0, 1.0]:
				_part(parent, "FeedBolt", suffix + ("N" if side < 0 else "P"), bolt_mesh,
					Vector3(side * 0.313, FLOOR_HEIGHT + 0.035, z),
					Basis(Quaternion(Vector3.UP, Vector3.RIGHT * side)), hardware)
		_part(parent, "FeedDirection", "", ProductionVisuals.prism_mesh(arrow, 0.002, 0.0002),
			Vector3(0, FLOOR_HEIGHT + 0.001, length * 0.2), Basis(Vector3.RIGHT, PI / 2), marking)
		return true

class ProductionSteelFloor:
	extends RefCounted
	## Image/material presentation only. No geometry or physical displacement.
	const ROOT := "res://opening/assets/steel"
	const FILES := {"albedo": "steel_albedo.webp", "arm": "steel_arm.webp", "normal": "steel_normal_gl.webp"}
	static var finish: StandardMaterial3D
	static var source_status := "uninitialized"

	static func read_images(directory: String = ROOT, files: Dictionary = FILES, normal_size: Vector2i = Vector2i(1024, 1024), arm_size: Vector2i = Vector2i(512, 512)) -> Dictionary:
		var present := 0
		for name_value in files.values():
			if ProductionVisuals.image_exists(directory.path_join(name_value)):
				present += 1
		if present == 0:
			return {"status": "missing", "images": {}}
		if present != files.size():
			return {"status": "invalid", "reason": "incomplete_material_set", "images": {}}
		var images: Dictionary = {}
		for role in files:
			var image := ProductionVisuals.read_image(directory.path_join(files[role]))
			var expected := arm_size if role == "arm" else (normal_size if role == "normal" else Vector2i(1024, 1024))
			if image == null or image.is_empty() or image.get_size() != expected:
				return {"status": "invalid", "reason": "invalid_" + role, "images": {}}
			images[role] = image
		return {"status": "ready", "images": images}

	static func material() -> StandardMaterial3D:
		if source_status != "uninitialized":
			return finish
		var loaded := read_images()
		source_status = loaded.status
		if source_status == "missing":
			# Historical fixed rosters have no bitmap assets. Keep their earlier
			# procedural floor explicit; current native capture includes all files.
			return null
		if source_status != "ready":
			push_error("Incomplete or invalid scanned foundation material: " + str(loaded.get("reason", "unknown")))
			return null
		for role in loaded.images:
			var image: Image = loaded.images[role]
			if image.generate_mipmaps(role == "normal") != OK:
				source_status = "invalid"
				push_error("Cannot generate foundation material mipmaps.")
				return null
		var arm := ImageTexture.create_from_image(loaded.images.arm)
		finish = StandardMaterial3D.new()
		finish.albedo_color = Color.WHITE
		finish.albedo_texture = ImageTexture.create_from_image(loaded.images.albedo)
		finish.metallic = 1.0
		finish.metallic_texture = arm
		finish.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		finish.roughness = 1.0
		finish.roughness_texture = arm
		finish.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		finish.ao_enabled = true
		finish.ao_texture = arm
		finish.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		finish.ao_light_affect = 0.0
		finish.normal_enabled = true
		finish.normal_texture = ImageTexture.create_from_image(loaded.images.normal)
		finish.normal_scale = 1.0
		# The source covers two metres. World-space mapping keeps its pattern
		# continuous across static panels instead of resetting at each tile.
		finish.uv1_triplanar = true
		finish.uv1_world_triplanar = true
		finish.uv1_triplanar_sharpness = 8.0
		finish.uv1_scale = Vector3.ONE * 0.5
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return finish

class ProductionFoundationArt:
	extends RefCounted
	## Passive kit below a confirmed tile's top-plane origin. No grid or state.
	const ROOT := "res://opening/assets/foundation-concrete"
	const FILES := {"albedo": "concrete_albedo.jpg", "normal": "concrete_normal_gl.webp", "arm": "concrete_arm.webp"}
	const DECK_THICKNESS := 0.024
	const WEST := 1
	const EAST := 2
	const NORTH := 4
	const SOUTH := 8
	const FOOTING_BEVEL := 0.014
	const JOIN_CORNER := 0.0002
	const COURSE_RECESS := 0.006
	const BAY_MARGIN := 0.19
	const BAY_SHOULDER := 0.018
	const BAY_RECESS := 0.018
	static var finish: StandardMaterial3D
	static var textures: Dictionary = {}
	static var source_status := "uninitialized"
	static var deck_meshes: Dictionary = {}
	static var footing_meshes: Dictionary = {}

	static func read_images(directory: String = ROOT) -> Dictionary:
		return ProductionSteelFloor.read_images(directory, FILES, Vector2i(512, 512))

	static func material() -> StandardMaterial3D:
		if source_status != "uninitialized":
			return finish
		var loaded := read_images()
		source_status = loaded.status
		if source_status != "ready":
			push_error("The player-built foundation needs its complete qualified concrete surface set.")
			return null
		for role in loaded.images:
			var image: Image = loaded.images[role]
			if image.generate_mipmaps(role == "normal") != OK:
				source_status = "invalid"
				push_error("Cannot generate foundation concrete mipmaps.")
				return null
			textures[role] = ImageTexture.create_from_image(image)
		finish = StandardMaterial3D.new()
		finish.albedo_color = Color.WHITE
		finish.albedo_texture = textures.albedo
		finish.metallic = 0.0
		finish.roughness = 1.0
		finish.roughness_texture = textures.arm
		finish.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		finish.normal_enabled = true
		finish.normal_texture = textures.normal
		finish.normal_scale = 1.0
		finish.uv1_triplanar = true
		finish.uv1_world_triplanar = true
		finish.uv1_triplanar_sharpness = 8.0
		finish.uv1_scale = Vector3.ONE * 0.5
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return finish

	static func _footing_outline(mask: int, cap: bool = false, bay_recess: float = 0.0) -> Array[Vector2]:
		var half := Geometry.PITCH / 2.0 - (FOOTING_BEVEL if cap else 0.0)
		var corner := FOOTING_BEVEL / 2.0 if cap else FOOTING_BEVEL
		var nw := corner if cap or (mask & (NORTH | WEST)) == 0 else JOIN_CORNER
		var ne := corner if cap or (mask & (NORTH | EAST)) == 0 else JOIN_CORNER
		var se := corner if cap or (mask & (SOUTH | EAST)) == 0 else JOIN_CORNER
		var sw := corner if cap or (mask & (SOUTH | WEST)) == 0 else JOIN_CORNER
		# Each exposed wall has one broad inset casting bay. The shoulders and
		# outer corner piers keep their physical scale when tiles join; hidden
		# faces stay flat. Every height ring has the same vertex correspondence.
		var north_bay := bay_recess if mask & NORTH == 0 else 0.0
		var east_bay := bay_recess if mask & EAST == 0 else 0.0
		var south_bay := bay_recess if mask & SOUTH == 0 else 0.0
		var west_bay := bay_recess if mask & WEST == 0 else 0.0
		return [Vector2(-half, -half + nw), Vector2(-half + nw, -half),
			Vector2(-half + BAY_MARGIN, -half),
			Vector2(-half + BAY_MARGIN + BAY_SHOULDER, -half + north_bay),
			Vector2(half - BAY_MARGIN - BAY_SHOULDER, -half + north_bay),
			Vector2(half - BAY_MARGIN, -half),
			Vector2(half - ne, -half), Vector2(half, -half + ne),
			Vector2(half, -half + BAY_MARGIN),
			Vector2(half - east_bay, -half + BAY_MARGIN + BAY_SHOULDER),
			Vector2(half - east_bay, half - BAY_MARGIN - BAY_SHOULDER),
			Vector2(half, half - BAY_MARGIN),
			Vector2(half, half - se), Vector2(half - se, half),
			Vector2(half - BAY_MARGIN, half),
			Vector2(half - BAY_MARGIN - BAY_SHOULDER, half - south_bay),
			Vector2(-half + BAY_MARGIN + BAY_SHOULDER, half - south_bay),
			Vector2(-half + BAY_MARGIN, half),
			Vector2(-half + sw, half), Vector2(-half, half - sw),
			Vector2(-half, half - BAY_MARGIN),
			Vector2(-half + west_bay, half - BAY_MARGIN - BAY_SHOULDER),
			Vector2(-half + west_bay, -half + BAY_MARGIN + BAY_SHOULDER),
			Vector2(-half, -half + BAY_MARGIN)]

	static func _footing_ring(outline: Array[Vector2], height: float, recess: float, mask: int) -> Array[Vector3]:
		var ring: Array[Vector3] = []
		for point in outline:
			var x := point.x
			var z := point.y
			if x < 0 and mask & WEST == 0:
				x += recess
			elif x > 0 and mask & EAST == 0:
				x -= recess
			if z < 0 and mask & NORTH == 0:
				z += recess
			elif z > 0 and mask & SOUTH == 0:
				z -= recess
			ring.append(Vector3(x, height, z))
		return ring

	static func _footing_seam(surface: SurfaceTool, upper: Array[Vector3], lower: Array[Vector3]) -> void:
		for index in range(upper.size()):
			var next := (index + 1) % upper.size()
			var first: Array[Vector3] = [upper[index], upper[next], lower[next]]
			var second: Array[Vector3] = [upper[index], lower[next], lower[index]]
			ProductionVisuals._face(surface, first,
				(first[1] - first[0]).cross(first[2] - first[0]).normalized())
			ProductionVisuals._face(surface, second,
				(second[1] - second[0]).cross(second[2] - second[0]).normalized())

	static func footing_mesh(mask: int = 0) -> ArrayMesh:
		assert(mask >= 0 and mask < 16)
		if footing_meshes.has(mask):
			return footing_meshes[mask]
		var half_depth := (Geometry.FOUNDATION_DEPTH - DECK_THICKNESS) / 2.0
		var outline := _footing_outline(mask)
		var bay := _footing_outline(mask, false, BAY_RECESS)
		var cap := _footing_outline(mask, true)
		var upper := _footing_ring(cap, half_depth, 0.0, mask)
		var lower := _footing_ring(cap, -half_depth, 0.0, mask)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(cap.size()):
			var next := (index + 1) % cap.size()
			ProductionVisuals._face(surface, [Vector3(0, half_depth, 0), upper[index], upper[next]], Vector3.UP)
			ProductionVisuals._face(surface, [Vector3(0, -half_depth, 0), lower[next], lower[index]], Vector3.DOWN)
		var rings: Array = [upper,
			_footing_ring(outline, half_depth - FOOTING_BEVEL, 0.0, mask),
			_footing_ring(outline, half_depth - 0.13, 0.0, mask),
			_footing_ring(bay, half_depth - 0.15, 0.0, mask),
			_footing_ring(bay, half_depth - 0.20, 0.0, mask),
			_footing_ring(bay, half_depth - 0.212, COURSE_RECESS, mask),
			_footing_ring(bay, half_depth - 0.232, COURSE_RECESS, mask),
			_footing_ring(bay, half_depth - 0.244, 0.0, mask),
			_footing_ring(bay, -half_depth + 0.09, 0.0, mask),
			_footing_ring(outline, -half_depth + 0.07, 0.0, mask),
			_footing_ring(outline, -half_depth + FOOTING_BEVEL, 0.0, mask), lower]
		for index in range(rings.size() - 1):
			_footing_seam(surface, rings[index], rings[index + 1])
		surface.generate_tangents()
		var mesh := surface.commit()
		footing_meshes[mask] = mesh
		return mesh

	static func neighbor_masks(foundations: Dictionary) -> Dictionary:
		# The native projection owns placement and height. This only selects art
		# for edges shared by already confirmed tiles at exactly the same level.
		var occupied: Dictionary = {}
		for id in foundations:
			var tile: Dictionary = foundations[id]
			occupied[Vector3i(int(tile.cell[0]), int(tile.level), int(tile.cell[1]))] = true
		var masks: Dictionary = {}
		for id in foundations:
			var tile: Dictionary = foundations[id]
			var cell := Vector3i(int(tile.cell[0]), int(tile.level), int(tile.cell[1]))
			var mask := 0
			if occupied.has(cell + Vector3i(-1, 0, 0)):
				mask |= WEST
			if occupied.has(cell + Vector3i(1, 0, 0)):
				mask |= EAST
			if occupied.has(cell + Vector3i(0, 0, -1)):
				mask |= NORTH
			if occupied.has(cell + Vector3i(0, 0, 1)):
				mask |= SOUTH
			masks[id] = mask
		return masks

	static func _deck_top_point(x_index: int, z_index: int, mask: int) -> Vector3:
		var half := Geometry.PITCH / 2.0
		var bevel := minf(0.014, DECK_THICKNESS * 0.12)
		var positions := [-half, -half + bevel, half - bevel, half]
		var joined := (x_index == 0 and mask & WEST != 0) or (x_index == 3 and mask & EAST != 0) \
			or (z_index == 0 and mask & NORTH != 0) or (z_index == 3 and mask & SOUTH != 0)
		var edge := x_index == 0 or x_index == 3 or z_index == 0 or z_index == 3
		return Vector3(positions[x_index], DECK_THICKNESS / 2.0 - (bevel if edge and not joined else 0.0), positions[z_index])

	static func _deck_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
		ProductionVisuals._face(surface, [a, b, c], outward)

	static func _deck_bottom_point(x_index: int, z_index: int) -> Vector3:
		var half := Geometry.PITCH / 2.0
		var bevel := minf(0.014, DECK_THICKNESS * 0.12)
		var inset := half - bevel
		var positions := [-inset, -inset + bevel, inset - bevel, inset]
		return Vector3(positions[x_index], -DECK_THICKNESS / 2.0, positions[z_index])

	static func _deck_side(surface: SurfaceTool, top: Array[Vector3], bottom: Array[Vector3], outward: Vector3) -> void:
		for index in range(3):
			_deck_triangle(surface, top[index], top[index + 1], bottom[index + 1], outward)
			_deck_triangle(surface, top[index], bottom[index + 1], bottom[index], outward)

	static func deck_mesh(mask: int = 0) -> ArrayMesh:
		assert(mask >= 0 and mask < 16)
		if deck_meshes.has(mask):
			return deck_meshes[mask]
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for x in range(3):
			for z in range(3):
				var a := _deck_top_point(x, z, mask)
				var b := _deck_top_point(x + 1, z, mask)
				var c := _deck_top_point(x, z + 1, mask)
				var d := _deck_top_point(x + 1, z + 1, mask)
				_deck_triangle(surface, a, c, b, Vector3.UP)
				_deck_triangle(surface, b, c, d, Vector3.UP)
		for x in range(3):
			for z in range(3):
				var a := _deck_bottom_point(x, z)
				var b := _deck_bottom_point(x + 1, z)
				var c := _deck_bottom_point(x, z + 1)
				var d := _deck_bottom_point(x + 1, z + 1)
				_deck_triangle(surface, a, b, c, Vector3.DOWN)
				_deck_triangle(surface, b, d, c, Vector3.DOWN)
		var north: Array[Vector3] = []
		var south: Array[Vector3] = []
		var west: Array[Vector3] = []
		var east: Array[Vector3] = []
		var north_bottom: Array[Vector3] = []
		var south_bottom: Array[Vector3] = []
		var west_bottom: Array[Vector3] = []
		var east_bottom: Array[Vector3] = []
		for index in range(4):
			north.append(_deck_top_point(index, 0, mask))
			south.append(_deck_top_point(index, 3, mask))
			west.append(_deck_top_point(0, index, mask))
			east.append(_deck_top_point(3, index, mask))
			north_bottom.append(_deck_bottom_point(index, 0))
			south_bottom.append(_deck_bottom_point(index, 3))
			west_bottom.append(_deck_bottom_point(0, index))
			east_bottom.append(_deck_bottom_point(3, index))
		_deck_side(surface, north, north_bottom, Vector3.FORWARD)
		_deck_side(surface, east, east_bottom, Vector3.RIGHT)
		_deck_side(surface, south, south_bottom, Vector3.BACK)
		_deck_side(surface, west, west_bottom, Vector3.LEFT)
		surface.generate_tangents()
		var mesh := surface.commit()
		deck_meshes[mask] = mesh
		return mesh

	static func mount(parent: Node3D, neighbor_mask: int = 0) -> bool:
		var concrete := material()
		var steel := ProductionSteelFloor.material()
		if concrete == null or steel == null:
			return false
		var footing := MeshInstance3D.new()
		footing.name = "FoundationBlock"
		footing.mesh = footing_mesh(neighbor_mask)
		footing.position.y = -(Geometry.FOUNDATION_DEPTH + DECK_THICKNESS) / 2.0
		footing.material_override = concrete
		parent.add_child(footing)
		var deck := MeshInstance3D.new()
		deck.name = "FoundationTop"
		deck.mesh = deck_mesh(neighbor_mask)
		deck.position.y = -DECK_THICKNESS / 2.0
		deck.material_override = steel
		parent.add_child(deck)
		return true

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
		var present := 0
		for file_name in FILES.values():
			if ProductionVisuals.image_exists(directory.path_join(file_name)):
				present += 1
		if present == 0:
			return {"status": "missing", "images": {}}
		if present != FILES.size():
			return {"status": "invalid", "reason": "incomplete_material_set", "images": {}}
		var images: Dictionary = {}
		for role in FILES:
			var image := ProductionVisuals.read_image(directory.path_join(FILES[role]))
			var size_value := Vector2i(1024, 1024) if role == "albedo" else Vector2i(512, 512)
			if image == null or image.is_empty() or image.get_size() != size_value:
				return {"status": "invalid", "reason": "invalid_" + role, "images": {}}
			images[role] = image
		return {"status": "ready", "images": images}

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
		var paint := ProductionCollectorArt.coating(color)
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
		var paint := ProductionCollectorArt.coating(color)
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

class ProductionPressArt:
	extends RefCounted
	## Authored support components for the existing confirmed processor.
	const ROOT := "res://opening/assets/press-support"
	const IMAGES := {"albedo": "cast_albedo.jpg", "normal": "cast_normal.webp", "arm": "cast_arm.webp"}
	static var mesh: ArrayMesh
	static var finish: StandardMaterial3D
	static var source_status := "uninitialized"

	static func resource_status(directory: String = ROOT) -> String:
		var files: Array = ["press_support.gltf", "press_support.bin"]
		files.append_array(IMAGES.values())
		var present := 0
		for name_value: String in files:
			if FileAccess.file_exists(directory.path_join(name_value)):
				present += 1
		if present == 0:
			return "missing"
		return "complete" if present == files.size() else "incomplete"

	static func _prepare() -> void:
		source_status = resource_status()
		if source_status == "missing":
			return
		if source_status != "complete":
			push_error("The sourced press support resource set is incomplete.")
			return
		source_status = "invalid"
		var images := ProductionSteelFloor.read_images(ROOT, IMAGES, Vector2i(512, 512))
		if images.status != "ready":
			push_error("Cannot decode the sourced press support material.")
			return
		var document := GLTFDocument.new()
		var imported := GLTFState.new()
		if document.append_from_file(ROOT.path_join("press_support.gltf"), imported) != OK:
			push_error("Cannot load the prepared press support component.")
			return
		var sources := imported.get_meshes()
		if sources.size() != 1 or sources[0].mesh == null or sources[0].mesh.get_surface_count() != 1:
			push_error("The press support must contain one prepared visual mesh.")
			return
		var prepared: ArrayMesh = sources[0].mesh.get_mesh()
		var arrays := prepared.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_TANGENT] == null or arrays[Mesh.ARRAY_TANGENT].is_empty():
			var surface := SurfaceTool.new()
			surface.create_from(prepared, 0)
			surface.generate_tangents()
			prepared = surface.commit()
		for role: String in images.images:
			var image: Image = images.images[role]
			if image.generate_mipmaps(role == "normal") != OK:
				push_error("Cannot generate press support mipmaps.")
				return
		var material := StandardMaterial3D.new()
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color.WHITE
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
		material.ao_light_affect = 0.0
		material.normal_enabled = true
		material.normal_texture = ImageTexture.create_from_image(images.images.normal)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mesh = prepared
		finish = material
		source_status = "ready"

	static func mount(parent: Node3D) -> bool:
		if source_status == "uninitialized":
			_prepare()
		if source_status != "ready":
			return false
		for side in [-1.0, 1.0]:
			var support := MeshInstance3D.new()
			support.name = "CastPressSupportLeft" if side < 0 else "CastPressSupportRight"
			support.mesh = mesh
			support.material_override = finish
			support.position = Vector3(side * 0.48, 0.24, -0.38)
			if side > 0:
				support.rotation.y = PI
			support.set_meta("detail_role", "CastPressSupport")
			support.set_meta("source_asset", "Poly Haven drill_press_01")
			parent.add_child(support)
		return true

class ProductionPressCrownArt:
	extends RefCounted
	## Fixed original castings around the unchanged tool and guide shafts.
	static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: StandardMaterial3D) -> void:
		var part := MeshInstance3D.new()
		part.name = role
		part.set_meta("press_crown_role", role)
		part.mesh = mesh
		part.position = at
		part.material_override = finish
		parent.add_child(part)

	static func mount(parent: Node3D, color: Color) -> bool:
		var cast_finish := ProductionTransmissionFinish.material("cast", Color("56635f"), 0.55, 0.74)
		var steel := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)
		var guide_finish := ProductionTransmissionFinish.material("worked", Color("b87945"), 0.85, 0.4)
		if cast_finish == null or steel == null or guide_finish == null:
			return false
		var crown := Node3D.new()
		crown.name = "PressCrown"
		parent.add_child(crown)
		var shoulder := PackedVector2Array([Vector2(-0.64, -0.14), Vector2(-0.55, -0.14),
			Vector2(-0.40, -0.08), Vector2(-0.25, -0.08), Vector2(-0.25, 0.12),
			Vector2(-0.64, 0.12)])
		for right in [false, true]:
			var profile := shoulder.duplicate()
			if right:
				for n in range(profile.size()):
					profile[n].x = -profile[n].x
			_part(crown, "CastShoulderRight" if right else "CastShoulderLeft",
				ProductionVisuals.prism_mesh(profile, 0.36, 0.007), Vector3(0, 1.5, -0.3), cast_finish)
		# The rear tie joins the shoulders without filling the ram's bore.
		_part(crown, "RearTie", ProductionVisuals.box_mesh(Vector3(0.54, 0.18, 0.265)),
			Vector3(0, 1.53, -0.3475), cast_finish)
		var housing := PackedVector2Array([Vector2(0.083, -0.135), Vector2(0.115, -0.135),
			Vector2(0.14, -0.115), Vector2(0.14, 0.11), Vector2(0.12, 0.135),
			Vector2(0.083, 0.135), Vector2(0.083, -0.135)])
		_part(crown, "RamHousing", ProductionVisuals.turned_mesh(housing), Vector3(0, 1.465, -0.08), cast_finish)
		var liner := PackedVector2Array([Vector2(0.079, -0.125), Vector2(0.083, -0.125),
			Vector2(0.083, 0.125), Vector2(0.079, 0.125), Vector2(0.079, -0.125)])
		_part(crown, "RamLiner", ProductionVisuals.turned_mesh(liner), Vector3(0, 1.465, -0.08), steel)
		var socket := PackedVector2Array([Vector2(0.043, -0.04), Vector2(0.058, -0.04),
			Vector2(0.068, -0.03), Vector2(0.068, 0.03), Vector2(0.058, 0.04),
			Vector2(0.043, 0.04), Vector2(0.043, -0.04)])
		for side in [-1.0, 1.0]:
			_part(crown, "GuideSocketLeft" if side < 0 else "GuideSocketRight",
				ProductionVisuals.turned_mesh(socket), Vector3(side * 0.34, 1.39, -0.19), guide_finish)
		return true

class ProductionPressRearFrameArt:
	extends RefCounted
	## A fixed, original H-frame behind the existing sourced columns. It carries
	## no separate support, collision, material or press-work authority.
	static var meshes: Dictionary = {}

	static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: StandardMaterial3D) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role
		part.set_meta("press_frame_role", role)
		part.mesh = mesh
		part.position = at
		part.material_override = finish
		parent.add_child(part)
		return part

	static func mount(parent: Node3D, color: Color) -> bool:
		var cast_finish := ProductionTransmissionFinish.material("cast", Color("56635f"), 0.55, 0.74)
		if cast_finish == null:
			return false
		if not meshes.has("tie"):
			# The lower tie remains behind the feed bed and joins both sourced
			# columns, unlike an unsupported decorative bar across the tool.
			meshes.tie = ProductionVisuals.box_mesh(Vector3(0.93, 0.14, 0.13))
			meshes.foot = ProductionVisuals.box_mesh(Vector3(0.27, 0.06, 0.22))
			for side in [-1.0, 1.0]:
				var profile := PackedVector2Array([
					Vector2(0.35, 0.29), Vector2(0.62, 0.29),
					Vector2(0.59, 0.30), Vector2(0.53, 0.52),
					Vector2(0.44, 0.52), Vector2(0.42, 0.36)])
				var upright := PackedVector2Array([
					Vector2(0.53, 0.24), Vector2(0.64, 0.24),
					Vector2(0.61, 0.36),
					Vector2(0.65, 1.34), Vector2(0.65, 1.42),
					Vector2(0.47, 1.42), Vector2(0.47, 1.34),
					Vector2(0.51, 0.36)])
				for n in range(profile.size()):
					profile[n].x *= side
				for n in range(upright.size()):
					upright[n].x *= side
				meshes["gusset_n" if side < 0 else "gusset_p"] = ProductionVisuals.prism_mesh(profile, 0.14, 0.004)
				meshes["upright_n" if side < 0 else "upright_p"] = ProductionVisuals.prism_mesh(upright, 0.12, 0.004)
		var frame := Node3D.new()
		frame.name = "PressRearFrame"
		parent.add_child(frame)
		_part(frame, "RearLowerTie", meshes.tie, Vector3(0, 0.30, -0.46), cast_finish)
		for side in [-1.0, 1.0]:
			_part(frame, "RearFootLeft" if side < 0 else "RearFootRight", meshes.foot,
				Vector3(side * 0.48, 0.27, -0.40), cast_finish)
			_part(frame, "RearGussetLeft" if side < 0 else "RearGussetRight",
				meshes["gusset_n" if side < 0 else "gusset_p"], Vector3(0, 0, -0.46), cast_finish)
			_part(frame, "FrontUprightLeft" if side < 0 else "FrontUprightRight",
				meshes["upright_n" if side < 0 else "upright_p"], Vector3(0, 0, -0.25), cast_finish)
		return true

class ProductionPressFrameJointArt:
	extends RefCounted
	## Presentation-only joins between complete rigid press bays. Native World
	## does not yet own a multi-press, so ordinary machine mounting never calls this.
	const BAY_WIDTH := 1.35
	const CROWN_WIDTH := 1.20

	static func _box(parent: Node3D, role: String, size: Vector3, at: Vector3,
			finish: Material) -> void:
		var part := MeshInstance3D.new()
		part.name = role
		part.set_meta("frame_role", role)
		part.mesh = ProductionVisuals.box_mesh(size)
		part.position = at
		part.material_override = finish
		parent.add_child(part)

	static func _bolt(parent: Node3D, at: Vector3, finish: Material) -> void:
		var part := MeshInstance3D.new()
		part.name = "JointBolt"
		part.set_meta("frame_role", "JointBolt")
		part.mesh = ProductionVisuals.fastener_head_mesh()
		part.position = at
		part.basis = Basis(Quaternion(Vector3.UP, Vector3.BACK))
		part.material_override = finish
		parent.add_child(part)

	static func _brace(parent: Node3D, from: Vector3, to: Vector3,
			finish: Material) -> void:
		var direction := to - from
		var part := MeshInstance3D.new()
		part.name = "RearKneeBrace"
		part.set_meta("frame_role", "RearKneeBrace")
		part.mesh = ProductionVisuals.box_mesh(Vector3(0.045, direction.length(), 0.055))
		part.position = (from + to) * 0.5
		part.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
		part.material_override = finish
		parent.add_child(part)

	static func mount(parent: Node3D, centers: PackedFloat32Array, cast: Material,
			worked: Material, skid: Material) -> Dictionary:
		# Refuse the complete request before mounting anything. These bounds are
		# a sample art envelope, not a new construction or support rule.
		if centers.size() < 2 or centers.size() > 8 or cast == null or worked == null or skid == null:
			return {"status": "invalid"}
		for index in range(centers.size()):
			if not is_finite(centers[index]):
				return {"status": "invalid"}
			# PackedFloat32Array rounds decimal bay positions. This one-tenth
			# millimetre tolerance keeps its stated envelope stable after packing.
			if index > 0 and (centers[index] - centers[index - 1] < BAY_WIDTH - 0.0001 or centers[index] - centers[index - 1] > 3.0001):
				return {"status": "invalid"}
		var assembly := Node3D.new()
		assembly.name = "FittedPressFrameJoints"
		parent.add_child(assembly)
		for index in range(centers.size() - 1):
			var left := centers[index]
			var right := centers[index + 1]
			var middle := (left + right) * 0.5
			var skid_gap := right - left - BAY_WIDTH
			var crown_gap := right - left - CROWN_WIDTH
			var joint := Node3D.new()
			joint.name = "BayJoint%d" % index
			joint.set_meta("frame_role", "BayJoint")
			assembly.add_child(joint)
			# Existing C-channel bays and sourced cast uprights remain rigid. Only
			# the true gap receives length-dependent steel and cast members.
			if skid_gap > 0.001:
				_box(joint, "DeckTongue", Vector3(skid_gap, 0.04, 1.22),
					Vector3(middle, 0.22, 0), skid)
				for z in [-0.53, 0.53]:
					_box(joint, "SkidChannelWeb", Vector3(skid_gap, 0.145, 0.045),
						Vector3(middle, 0.09, z), skid)
					for y in [0.02, 0.18]:
						_box(joint, "SkidChannelFlange", Vector3(skid_gap, 0.018, 0.17),
							Vector3(middle, y, z), skid)
				_box(joint, "DeckStiffener", Vector3(0.055, 0.075, 1.09),
					Vector3(middle, 0.165, 0), worked)
			for edge in [left + BAY_WIDTH * 0.5, right - BAY_WIDTH * 0.5]:
				for z in [-0.53, 0.53]:
					_box(joint, "SkidClamp", Vector3(0.16, 0.018, 0.19),
						Vector3(edge, 0.247, z), worked)
					for x_offset in [-0.045, 0.045]:
						_bolt(joint, Vector3(edge + x_offset, 0.262, z), worked)
			# An open, flanged crosshead replaces a plain solid bar. Both fixed
			# shoulder ends retain their original positions and cast profiles.
			_box(joint, "CrownWeb", Vector3(crown_gap, 0.112, 0.040),
				Vector3(middle, 1.53, -0.3475), cast)
			for y in [1.456, 1.604]:
				_box(joint, "CrownFlange", Vector3(crown_gap, 0.030, 0.275),
					Vector3(middle, y, -0.3475), cast)
			for edge in [left + CROWN_WIDTH * 0.5, right - CROWN_WIDTH * 0.5]:
				_box(joint, "CrownFishplate", Vector3(0.07, 0.19, 0.022),
					Vector3(edge, 1.53, -0.198), worked)
				for y in [1.475, 1.585]:
					_bolt(joint, Vector3(edge, y, -0.183), worked)
			# Each knee reaches an existing inner upright. A short decorative
			# strut hanging from the middle of the beam would imply false support.
			var knee_run := 0.12 + crown_gap * 0.34
			_brace(joint, Vector3(left + 0.48, 1.16, -0.39),
				Vector3(left + 0.48 + knee_run, 1.47, -0.39), worked)
			_brace(joint, Vector3(right - 0.48, 1.16, -0.39),
				Vector3(right - 0.48 - knee_run, 1.47, -0.39), worked)
			if crown_gap > 0.40:
				_box(joint, "CrownStiffener", Vector3(0.05, 0.14, 0.24),
					Vector3(middle, 1.53, -0.3475), worked)
		for edge in [centers[0] - CROWN_WIDTH * 0.5, centers[centers.size() - 1] + CROWN_WIDTH * 0.5]:
			_box(assembly, "TerminalCrownCap", Vector3(0.04, 0.19, 0.28),
				Vector3(edge, 1.53, -0.3475), worked)
		for edge in [centers[0] - BAY_WIDTH * 0.5, centers[centers.size() - 1] + BAY_WIDTH * 0.5]:
			for z in [-0.53, 0.53]:
				_box(assembly, "TerminalSkidCap", Vector3(0.035, 0.18, 0.19),
					Vector3(edge, 0.09, z), worked)
		return {"status": "ready", "joints": centers.size() - 1,
			"crown_gaps": centers[centers.size() - 1] - centers[0] - CROWN_WIDTH * (centers.size() - 1)}

class ProductionPressDieArt:
	extends RefCounted
	## Passive rigid tooling. Working planes and the existing motion anchor stay literal.
	static var meshes: Dictionary = {}

	static func _surface(target: ArrayMesh, role: String, pieces: Array) -> void:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for piece: Array in pieces:
			surface.append_from(piece[0], 0, piece[1])
		surface.commit(target)
		target.surface_set_name(target.get_surface_count() - 1, role)

	static func _hardware(target: ArrayMesh, poses: Array[Transform3D],
			extra_pieces: Array = []) -> void:
		var washer := ProductionVisuals.turned_mesh(PackedVector2Array([
			Vector2(0.014, 0), Vector2(0.038, 0), Vector2(0.043, 0.002),
			Vector2(0.043, 0.004), Vector2(0.038, 0.006), Vector2(0.014, 0.006), Vector2(0.014, 0)]), 24)
		# append_from does not supply indices for earlier unindexed pieces
		# when an indexed primitive is appended. Keep both inputs indexed.
		var indexed_washer := SurfaceTool.new()
		indexed_washer.create_from(washer, 0)
		indexed_washer.index()
		washer = indexed_washer.commit()
		var pieces: Array = []
		for piece: Array in extra_pieces:
			# SurfaceTool drops an earlier unindexed append when a later indexed
			# piece is added. Index every lock before combining it with the heads.
			var indexed_lock := SurfaceTool.new()
			indexed_lock.create_from(piece[0], 0)
			indexed_lock.index()
			pieces.append([indexed_lock.commit(), piece[1]])
		for pose in poses:
			pieces.append([washer, pose])
			pieces.append([ProductionVisuals.fastener_head_mesh(), pose * Transform3D(Basis.IDENTITY, Vector3(0, 0.018, 0))])
		_surface(target, "MountingHardware", pieces)

	static func tool_mesh(kind: String = "press") -> ArrayMesh:
		if kind not in ["press", "cut_sample"]:
			return null
		var key := "tool_" + kind
		if meshes.has(key):
			return meshes[key]
		var mesh := ArrayMesh.new()
		var holder := PackedVector2Array([
			Vector2(-0.28, -0.025), Vector2(-0.27, -0.045), Vector2(-0.25, -0.045),
			Vector2(-0.25, -0.035), Vector2(0.25, -0.035), Vector2(0.25, -0.045),
			Vector2(0.27, -0.045), Vector2(0.28, -0.025), Vector2(0.28, 0.060),
			Vector2(0.255, 0.085), Vector2(-0.255, 0.085), Vector2(-0.28, 0.060)])
		_surface(mesh, "ToolHolder", [[ProductionVisuals.prism_mesh(holder, 0.48, 0.004), Transform3D.IDENTITY]])
		# Both complete heads use the same rigid carrier and mounting sites.
		# Only the press face is installed in the native machine. The narrow
		# cutter is an isolated art comparison, not a cutting command or rule.
		if kind == "press":
			_surface(mesh, "WorkingFace", [[ProductionVisuals.box_mesh(Vector3(0.50, 0.05, 0.55)),
				Transform3D(Basis.IDENTITY, Vector3(0, -0.06, 0))]])
		else:
			# A replaceable wedge runs across the head. Its narrow lower edge is
			# perpendicular to feed, unlike the press's complete flat plate.
			var blade := PackedVector2Array([Vector2(-0.06, -0.035), Vector2(0.06, -0.035),
				Vector2(0.04, -0.055), Vector2(0.001, -0.085),
				Vector2(-0.001, -0.085), Vector2(-0.04, -0.055)])
			_surface(mesh, "WorkingFace", [[ProductionVisuals.prism_mesh(blade, 0.50, 0.0005),
				Transform3D(Basis(Quaternion(Vector3.UP, PI / 2.0)), Vector3.ZERO)]])
		var poses: Array[Transform3D] = []
		for side in [-1.0, 1.0]:
			for x in [-0.205, 0.205]:
				poses.append(Transform3D(Basis(Quaternion(Vector3.UP, Vector3.BACK * side)), Vector3(x, 0.025, side * 0.24)))
		var locks: Array = []
		for side in [-1.0, 1.0]:
			locks.append([ProductionVisuals.box_mesh(Vector3(0.02, 0.06, 0.38)),
				Transform3D(Basis.IDENTITY, Vector3(side * 0.27, 0.025, 0))])
			locks.append([ProductionVisuals.box_mesh(Vector3(0.36, 0.045, 0.025)),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.035, side * 0.255))])
		_hardware(mesh, poses, locks)
		meshes[key] = mesh
		return mesh

	static func anvil_mesh() -> ArrayMesh:
		if meshes.has("anvil"):
			return meshes.anvil
		var mesh := ArrayMesh.new()
		var saddle := PackedVector2Array([
			Vector2(-0.35, -0.08), Vector2(0.21, -0.08), Vector2(0.21, -0.02),
			Vector2(0.35, -0.02), Vector2(0.35, 0.005), Vector2(0.27, 0.005), Vector2(0.24, 0.04),
			Vector2(-0.24, 0.04), Vector2(-0.24, -0.015), Vector2(-0.27, -0.045), Vector2(-0.35, -0.045)])
		_surface(mesh, "AnvilSaddle", [[ProductionVisuals.prism_mesh(saddle, 0.63, 0.004), Transform3D.IDENTITY]])
		_surface(mesh, "WorkingFace", [[ProductionVisuals.box_mesh(Vector3(0.52, 0.04, 0.51)),
			Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0))]])
		var poses: Array[Transform3D] = []
		for x in [-0.305, 0.305]:
			for z in [-0.255, 0.255]:
				# The outlet-side foot is relieved above the existing output plate.
				poses.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.005 if x > 0 else -0.045, z)))
		_hardware(mesh, poses)
		meshes.anvil = mesh
		return mesh

	static func pedestal_mesh() -> ArrayMesh:
		if not meshes.has("pedestal"):
			var rib := PackedVector2Array([
				Vector2(-0.05, -0.07), Vector2(0.05, -0.07), Vector2(0.05, -0.045),
				Vector2(0.025, -0.045), Vector2(0.022, 0.045), Vector2(0.045, 0.045),
				Vector2(0.045, 0.07), Vector2(-0.045, 0.07), Vector2(-0.045, 0.045),
				Vector2(-0.022, 0.045), Vector2(-0.025, -0.045), Vector2(-0.05, -0.045)])
			meshes.pedestal = ProductionVisuals.prism_mesh(rib, 0.53, 0.002)
		return meshes.pedestal

	static func mount(parent: Node3D, anvil: MeshInstance3D, head: MeshInstance3D) -> void:
		var holder := ProductionCollectorArt.coating(Color("58634c"))
		var saddle := ProductionCollectorArt.coating(Color("394a44"))
		var face := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.32)
		var hardware := ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.85, 0.38)
		if holder == null or saddle == null or face == null or hardware == null:
			return
		for pair in [[head, tool_mesh(), holder], [anvil, anvil_mesh(), saddle]]:
			var part: MeshInstance3D = pair[0]
			part.mesh = pair[1]
			part.material_override = null
			part.set_surface_override_material(0, pair[2])
			part.set_surface_override_material(1, face)
			part.set_surface_override_material(2, hardware)
			part.set_meta("press_die_role", str(part.name))
		for side in [-1.0, 1.0]:
			var rib := MeshInstance3D.new()
			rib.name = "AnvilPedestalLeft" if side < 0 else "AnvilPedestalRight"
			# Keep the outlet side open without entering the vertical drive journal.
			rib.position = Vector3(side * 0.16, 0.31, 0.05)
			rib.mesh = pedestal_mesh()
			rib.material_override = saddle
			rib.set_meta("press_die_role", "AnvilPedestal")
			parent.add_child(rib)

class ProductionCutterGuardArt:
	extends RefCounted
	## Sample-only visual guard for the cutter cartridge. No native cutting rule.
	static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: Material) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = role
		part.set_meta("cutter_guard_role", role)
		part.mesh = mesh
		part.position = at
		part.material_override = finish
		parent.add_child(part)
		return part

	static func mount(head: MeshInstance3D) -> bool:
		if head == null or head.mesh != ProductionPressDieArt.tool_mesh("cut_sample") \
			or head.get_node_or_null("CutterSampleGuard") != null:
			return false
		var cast := ProductionCollectorArt.coating(Color("806a40"))
		var steel := ProductionTransmissionFinish.material("worked", Color("c4d4cd"), 0.85, 0.32)
		if cast == null or steel == null:
			return false
		var guard := Node3D.new()
		guard.name = "CutterSampleGuard"
		head.add_child(guard)
		var cheek := PackedVector2Array([Vector2(-0.28, 0.03), Vector2(-0.28, 0.20),
			Vector2(-0.25, 0.25), Vector2(-0.20, 0.25), Vector2(-0.20, 0.03)])
		for face in [-1.0, 1.0]:
			var face_name := "Rear" if face < 0 else "Front"
			for right in [false, true]:
				var profile := cheek.duplicate()
				if right:
					for n in range(profile.size()):
						profile[n].x = -profile[n].x
				_part(guard, face_name + ("RightCheek" if right else "LeftCheek"),
					ProductionVisuals.prism_mesh(profile, 0.035, 0.004), Vector3(0, 0, face * 0.27), cast)
			_part(guard, face_name + "Crossbar", ProductionVisuals.box_mesh(Vector3(0.40, 0.04, 0.038)),
				Vector3(0, 0.23, face * 0.27), cast)
			for x in [-0.22, 0.22]:
				var fastener := _part(guard, face_name + "Fastener", ProductionVisuals.fastener_head_mesh(),
					Vector3(x, 0.21, face * 0.288), steel)
				fastener.basis = Basis(Quaternion(Vector3.UP, Vector3.BACK * face))
		return true

class ProductionPressTrayArt:
	extends RefCounted
	## Fixed sheet and brackets. The receiving datum and output item never move.
	static var meshes: Dictionary = {}

	static func tray_mesh() -> ArrayMesh:
		if not meshes.has("tray"):
			# An eight-millimetre floor with folded sides and short returned lips.
			# The open ends leave the existing output accessible; all folds stay
			# outside the full declared plate footprint, not just its centre.
			var section := PackedVector2Array([
				Vector2(-0.24, 0.017), Vector2(0.24, 0.017), Vector2(0.24, 0.040),
				Vector2(0.228, 0.040), Vector2(0.228, 0.032), Vector2(0.232, 0.032),
				Vector2(0.232, 0.025), Vector2(-0.232, 0.025), Vector2(-0.232, 0.032),
				Vector2(-0.228, 0.032), Vector2(-0.228, 0.040), Vector2(-0.24, 0.040)])
			meshes.tray = ProductionVisuals.prism_mesh(section, 0.58, 0.0006)
		return meshes.tray

	static func bracket_mesh() -> ArrayMesh:
		if meshes.has("bracket"):
			return meshes.bracket
		var section := PackedVector2Array([
			Vector2(-0.030, -0.0535), Vector2(0.030, -0.0535), Vector2(0.030, -0.0435),
			Vector2(0.012, -0.0435), Vector2(0.012, 0.0375), Vector2(0.028, 0.0375),
			Vector2(0.028, 0.0535), Vector2(-0.028, 0.0535), Vector2(-0.028, 0.0375),
			Vector2(-0.012, 0.0375), Vector2(-0.012, -0.0435), Vector2(-0.030, -0.0435)])
		var mesh := ArrayMesh.new()
		ProductionPressDieArt._surface(mesh, "Bracket", [[ProductionVisuals.prism_mesh(section, 0.32, 0.0008), Transform3D.IDENTITY]])
		var fasteners: Array = []
		for x in [-0.021, 0.021]:
			for z in [-0.12, 0.12]:
				fasteners.append([ProductionVisuals.fastener_head_mesh(),
					Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.18), Vector3(x, -0.04134, z))])
		ProductionPressDieArt._surface(mesh, "FootFasteners", fasteners)
		meshes.bracket = mesh
		return mesh

	static func mount(parent: Node3D, tray: MeshInstance3D) -> void:
		var sheet := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.5)
		var bracket_finish := ProductionCollectorArt.coating(Color("394a44"))
		var hardware := ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.85, 0.38)
		if sheet == null or bracket_finish == null or hardware == null:
			return
		tray.mesh = tray_mesh()
		tray.material_override = sheet
		tray.set_meta("press_tray_role", "FormedPan")
		for index in range(2):
			var bracket := MeshInstance3D.new()
			bracket.name = "TrayBracketLeft" if index == 0 else "TrayBracketRight"
			bracket.position = Vector3(0.40 if index == 0 else 0.62, 0.2935, 0.15)
			bracket.mesh = bracket_mesh()
			bracket.set_surface_override_material(0, bracket_finish)
			bracket.set_surface_override_material(1, hardware)
			bracket.set_meta("press_tray_role", "FixedBracket")
			parent.add_child(bracket)

class ProductionDriveJournalArt:
	extends RefCounted
	## Turned presentation inside the original native journal cylinder.
	static var horizontal_press_mesh: ArrayMesh
	static var z_input_post_mesh: ArrayMesh
	static var collector_bearing_mesh: ArrayMesh
	static func mesh(height: float, radius: float = 0.085) -> ArrayMesh:
		var half := height / 2.0
		# Keep the full central bearing span. End relief and center marks are
		# visual machining details, without a new coupling or contact rule.
		var profile := PackedVector2Array([
			Vector2(0, -half + 0.020), Vector2(0.014, -half + 0.020),
			Vector2(0.028, -half), Vector2(0.071, -half),
			Vector2(0.085, -half + 0.014), Vector2(0.085, -half + 0.040),
			Vector2(0.081, -half + 0.044), Vector2(0.081, -half + 0.058),
			Vector2(0.085, -half + 0.062), Vector2(0.085, half - 0.062),
			Vector2(0.081, half - 0.058), Vector2(0.081, half - 0.044),
			Vector2(0.085, half - 0.040), Vector2(0.085, half - 0.014),
			Vector2(0.071, half), Vector2(0.028, half),
			Vector2(0.014, half - 0.020), Vector2(0, half - 0.020)])
		if radius != 0.085:
			var ratio := radius / 0.085
			for n in range(profile.size()):
				profile[n] = Vector2(profile[n].x * ratio, profile[n].y)
		return ProductionVisuals.turned_mesh(profile)

	static func material() -> StandardMaterial3D:
		return ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)

	static func press_mesh() -> ArrayMesh:
		if horizontal_press_mesh == null:
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			# The inboard shoulder clears the original stamped-plate hardware;
			# the outer cuff keeps the established attachment radius and plane.
			var end_mesh := ProductionVisuals.turned_mesh(PackedVector2Array([
				Vector2(0, -0.070), Vector2(0.014, -0.070), Vector2(0.028, -0.090),
				Vector2(0.065, -0.090), Vector2(0.077, -0.078), Vector2(0.077, 0.050),
				Vector2(0.078, 0.055), Vector2(0.085, 0.060), Vector2(0.085, 0.076),
				Vector2(0.071, 0.090), Vector2(0.028, 0.090), Vector2(0.014, 0.070),
				Vector2(0, 0.070)]))
			# Preserve the two original external ends. The working body between
			# them is not an exposed through-shaft across the anvil.
			for side in [-1.0, 1.0]:
				var basis := Basis(Vector3.RIGHT, PI) if side < 0 else Basis.IDENTITY
				surface.append_from(end_mesh, 0, Transform3D(basis, Vector3(0, side * 0.585, 0)))
			horizontal_press_mesh = surface.commit()
		return horizontal_press_mesh

	static func _press_fixed(parent: Node3D, name_value: String, role: String,
			mesh_value: ArrayMesh, at: Vector3, basis_value: Basis = Basis.IDENTITY) -> void:
		var part := MeshInstance3D.new()
		part.name = name_value
		part.position = at
		part.basis = basis_value
		part.mesh = mesh_value
		part.material_override = ProductionTransmissionFinish.material("worked", Color("878d7f"), 0.85, 0.42) \
			if role == "Bearing" else ProductionCollectorArt.coating(Color("58634c"))
		part.set_meta("press_input_role", role)
		parent.add_child(part)

	static func mount_press_bearings(parent: Node3D, axis: Vector3) -> void:
		var ring := ProductionVisuals.turned_mesh(PackedVector2Array([
			Vector2(0.087, -0.010), Vector2(0.089, -0.015), Vector2(0.096, -0.015),
			Vector2(0.100, -0.011), Vector2(0.100, 0.011), Vector2(0.096, 0.015),
			Vector2(0.089, 0.015), Vector2(0.087, 0.010), Vector2(0.087, -0.010)]))
		for side in [-1.0, 1.0]:
			var suffix := "Left" if side < 0 else "Right"
			var at: Vector3 = axis * float(side) * 0.66
			_press_fixed(parent, "PressInputBearing" + suffix, "Bearing", ring,
				at + Vector3.UP * Geometry.ANCHOR_HEIGHT, Basis(Quaternion(Vector3.UP, axis)))
			if axis == Vector3.RIGHT:
				# The raised shared axle needs a taller rear load path. Keep the
				# narrow upper ear outside the original journal radius.
				var deck_top := 0.24
				var post_top := Geometry.ANCHOR_HEIGHT - 0.105
				_press_fixed(parent, "PressInputPost" + suffix, "Post",
					ProductionVisuals.box_mesh(Vector3(0.10, post_top - deck_top, 0.12)),
					at + Vector3(0, (post_top + deck_top) * 0.5, -0.23))
				_press_fixed(parent, "PressInputBracket" + suffix, "Bracket",
					ProductionVisuals.box_mesh(Vector3(0.06, 0.13, 0.16)),
					at + Vector3(0, Geometry.ANCHOR_HEIGHT - 0.08, -0.17))
			else:
				if z_input_post_mesh == null:
					# An offset cast cheek reaches the annular housing but leaves
					# the central shaft and its original clearance unobstructed.
					var cheek := PackedVector2Array([Vector2(0.09, 0.24),
						Vector2(0.24, 0.24), Vector2(0.19, 0.33),
						Vector2(0.15, Geometry.ANCHOR_HEIGHT - 0.18),
						Vector2(0.15, Geometry.ANCHOR_HEIGHT - 0.015),
						Vector2(0.09, Geometry.ANCHOR_HEIGHT - 0.015)])
					z_input_post_mesh = ProductionVisuals.prism_mesh(cheek, 0.10, 0.004)
				_press_fixed(parent, "PressInputPost" + suffix, "Post",
					z_input_post_mesh, at)

	static func _collector_fixed(parent: Node3D, name_value: String, role: String,
			mesh_value: Mesh, at: Vector3, basis_value: Basis = Basis.IDENTITY) -> void:
		var part := MeshInstance3D.new()
		part.name = name_value
		part.position = at
		part.basis = basis_value
		part.mesh = mesh_value
		part.material_override = ProductionTransmissionFinish.material("worked", Color("878d7f"), 0.85, 0.42) \
			if role == "Bearing" else ProductionCollectorArt.coating(Color("394a44"))
		part.set_meta("collector_input_role", role)
		parent.add_child(part)

	static func mount_collector_bearings(parent: Node3D, axis: Vector3) -> void:
		if collector_bearing_mesh == null:
			collector_bearing_mesh = ProductionVisuals.turned_mesh(PackedVector2Array([
				Vector2(0.087, -0.010), Vector2(0.089, -0.015), Vector2(0.096, -0.015),
				Vector2(0.100, -0.011), Vector2(0.100, 0.011), Vector2(0.096, 0.015),
				Vector2(0.089, 0.015), Vector2(0.087, 0.010), Vector2(0.087, -0.010)]))
		var along_x := axis == Vector3.RIGHT
		for side in [-1.0, 1.0]:
			var suffix := "Left" if side < 0 else "Right"
			var at: Vector3 = axis * float(side) * 0.66
			_collector_fixed(parent, "CollectorInputBearing" + suffix, "Bearing", collector_bearing_mesh,
				at + Vector3.UP * Geometry.ANCHOR_HEIGHT, Basis(Quaternion(Vector3.UP, axis)))
			# The post and skid foot touch below the bearing. Their narrow axial
			# faces remain outboard of the stock bed at both confirmed input axes.
			_collector_fixed(parent, "CollectorInputPost" + suffix, "Post",
				ProductionVisuals.box_mesh(Vector3(0.08, 0.50, 0.16) if along_x else Vector3(0.16, 0.50, 0.08)),
				axis * float(side) * 0.675 + Vector3.UP * 0.49)
			_collector_fixed(parent, "CollectorInputFoot" + suffix, "Foot",
				ProductionVisuals.box_mesh(Vector3(0.26, 0.10, 0.20) if along_x else Vector3(0.20, 0.10, 0.26)),
				axis * float(side) * 0.58 + Vector3.UP * 0.20)

class ProductionCollectorFeedArt:
	extends RefCounted
	## Formed guides sit on the literal stock bed. They carry no material state.
	static var rail_mesh: ArrayMesh
	static var clamp_mesh: ArrayMesh

	static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: StandardMaterial3D, scale: Vector3 = Vector3.ONE) -> void:
		var part := MeshInstance3D.new()
		part.name = role
		part.set_meta("collector_feed_role", role)
		part.mesh = mesh
		part.position = at
		part.scale = scale
		part.material_override = finish
		parent.add_child(part)

	static func mount(parent: Node3D, color: Color) -> bool:
		var paint := ProductionCollectorArt.coating(color.darkened(0.13))
		var steel := ProductionTransmissionFinish.material("worked", Color("9caaa5"), 0.85, 0.42)
		if paint == null or steel == null:
			return false
		if rail_mesh == null:
			# The contact plane stays at the original bed top, y = 0.56.
			# A tapered end and folded upper edge avoid a floating box silhouette.
			var section := PackedVector2Array([Vector2(-0.525, 0.56),
				Vector2(0.625, 0.56), Vector2(0.625, 0.585),
				Vector2(0.575, 0.615), Vector2(0.50, 0.64),
				Vector2(-0.45, 0.64), Vector2(-0.525, 0.605)])
			rail_mesh = ProductionVisuals.prism_mesh(section, 0.06, 0.003)
			clamp_mesh = ProductionVisuals.box_mesh(Vector3(0.11, 0.07, 0.13))
		var assembly := Node3D.new()
		assembly.name = "CollectorFeedGuides"
		parent.add_child(assembly)
		for side in [-1.0, 1.0]:
			var z: float = side * 0.335
			_part(assembly, "FormedGuide", rail_mesh, Vector3(0, 0, z), paint)
			# Clamp feet overlap both the rail and the unchanged bed edge.
			# Neither claims a new support or collision volume.
			for x in [-0.42, 0.42]:
				_part(assembly, "GuideClamp", clamp_mesh, Vector3(x, 0.53, z), paint)
				_part(assembly, "ClampHead", ProductionVisuals.fastener_head_mesh(),
					Vector3(x, 0.6445, z), steel, Vector3.ONE * 0.38)
		return true

class ProductionCollectorOutputArt:
	extends RefCounted
	## The intake stays aimed at the fixed seam. This passive cassette follows
	## only the native material-output quarter turn inside the machine body.
	static func _part(parent: Node3D, role: String, size: Vector3, at: Vector3,
			finish: Material) -> void:
		var part := MeshInstance3D.new()
		part.name = role
		part.mesh = ProductionVisuals.box_mesh(size)
		part.position = at
		part.material_override = finish
		part.set_meta("collector_output_role", role)
		parent.add_child(part)

	static func mount(parent: Node3D, rotation: int) -> void:
		var cassette := Node3D.new()
		cassette.name = "CollectorOutputCassette"
		cassette.rotation.y = -float(posmod(rotation, 4)) * PI / 2.0
		parent.add_child(cassette)
		var steel := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.4)
		var paint := ProductionCollectorArt.coating(Color("58634c"))
		if steel == null or paint == null:
			return
		# The inner floor meets the original stock bed at y = 0.56 and ends
		# inside the confirmed 0.725 m half-width. An open end remains open
		# until the native material link supplies a real neighboring route.
		_part(cassette, "OutletFloor", Vector3(0.48, 0.035, 0.38),
			Vector3(0.45, 0.5675, 0), steel)
		for side in [-1.0, 1.0]:
			_part(cassette, "OutletSideLeft" if side < 0 else "OutletSideRight", Vector3(0.48, 0.105, 0.035),
				Vector3(0.45, 0.635, side * 0.21), paint)
		_part(cassette, "OutletLip", Vector3(0.055, 0.025, 0.46),
			Vector3(0.69, 0.60, 0), steel)

class ProductionCollectorToolingArt:
	extends RefCounted
	## Passive rigid tooling. The existing cutter rows and presenter own its pose.
	static var meshes: Dictionary = {}

	static func drum_mesh() -> ArrayMesh:
		if not meshes.has("drum"):
			var section := PackedVector2Array([
				Vector2(0.085, -0.17), Vector2(0.218, -0.17), Vector2(0.228, -0.164),
				Vector2(0.24, -0.15), Vector2(0.24, -0.13), Vector2(0.228, -0.12),
				Vector2(0.228, 0.12), Vector2(0.24, 0.13), Vector2(0.24, 0.15),
				Vector2(0.228, 0.164), Vector2(0.218, 0.17), Vector2(0.085, 0.17), Vector2(0.085, -0.17)])
			meshes.drum = ProductionVisuals.turned_mesh(section)
		return meshes.drum

	static func hub_mesh() -> ArrayMesh:
		if not meshes.has("hub"):
			var section := PackedVector2Array([
				Vector2(0, -0.04), Vector2(0.078, -0.04), Vector2(0.085, -0.036),
				Vector2(0.085, -0.020), Vector2(0.078, -0.014), Vector2(0.078, -0.006),
				Vector2(0.085, 0), Vector2(0.085, 0.039), Vector2(0.083, 0.04), Vector2(0, 0.04)])
			meshes.hub = ProductionVisuals.turned_mesh(section)
		return meshes.hub

	static func flute_mesh() -> ArrayMesh:
		if meshes.has("flute"):
			return meshes.flute
		var holder := PackedVector2Array([
			Vector2(-0.02, -0.0225), Vector2(0.02, -0.0225), Vector2(0.02, 0.0025),
			Vector2(0.012, 0.0075), Vector2(-0.012, 0.0075), Vector2(-0.02, 0.0025)])
		var insert := PackedVector2Array([
			Vector2(-0.012, 0.0075), Vector2(0.012, 0.0075), Vector2(0.02, 0.0175),
			Vector2(0.014, 0.0225), Vector2(-0.014, 0.0225), Vector2(-0.02, 0.0175)])
		var mesh := ArrayMesh.new()
		ProductionPressDieArt._surface(mesh, "InsertHolder", [[ProductionVisuals.prism_mesh(holder, 0.29, 0.001), Transform3D.IDENTITY]])
		ProductionPressDieArt._surface(mesh, "CuttingInsert", [[ProductionVisuals.prism_mesh(insert, 0.27, 0.0006), Transform3D.IDENTITY]])
		var heads: Array = []
		for z in [-0.14, 0.14]:
			heads.append([ProductionVisuals.fastener_head_mesh(),
				Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.12), Vector3(0, 0.00894, z))])
		ProductionPressDieArt._surface(mesh, "RetainingHeads", heads)
		meshes.flute = mesh
		return mesh

	static func mount_body(drum: MeshInstance3D, hub: MeshInstance3D) -> void:
		var dark := ProductionTransmissionFinish.material("worked", Color("465a60"), 0.85, 0.4)
		var steel := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.4)
		if dark == null or steel == null:
			return
		drum.mesh = drum_mesh()
		drum.material_override = dark
		drum.set_meta("collector_tooling_role", "BoredDrum")
		hub.mesh = hub_mesh()
		hub.material_override = steel
		hub.set_meta("collector_tooling_role", "SteppedHub")

	static func mount_flute(flute: MeshInstance3D) -> void:
		var holder := ProductionTransmissionFinish.material("worked", Color("465a60"), 0.85, 0.4)
		var insert := ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.9, 0.3)
		var hardware := ProductionTransmissionFinish.material("worked", Color("778b8c"), 0.85, 0.4)
		if holder == null or insert == null or hardware == null:
			return
		flute.mesh = flute_mesh()
		flute.material_override = null
		flute.set_surface_override_material(0, holder)
		flute.set_surface_override_material(1, insert)
		flute.set_surface_override_material(2, hardware)
		flute.set_meta("collector_tooling_role", "FittedInsert")

class ProductionCollectorServiceArt:
	extends RefCounted
	## Fixed rear access artwork. No service action, state or collision owner.
	static var meshes: Dictionary = {}

	static func _outline(width: float, height: float, corner: float) -> PackedVector2Array:
		var x := width / 2.0
		var y := height / 2.0
		return PackedVector2Array([Vector2(-x + corner, -y), Vector2(x - corner, -y),
			Vector2(x, -y + corner), Vector2(x, y - corner), Vector2(x - corner, y),
			Vector2(-x + corner, y), Vector2(-x, y - corner), Vector2(-x, -y + corner)])

	static func _prepare() -> void:
		if not meshes.is_empty():
			return
		meshes.gasket = ProductionVisuals.prism_mesh(_outline(0.662, 0.522, 0.032), 0.003, 0.0004)
		meshes.panel = ProductionVisuals.prism_mesh(_outline(0.64, 0.50, 0.028), 0.018, 0.002)
		var hardware := ArrayMesh.new()
		var poses: Array[Transform3D] = []
		var orientation := Basis(Quaternion(Vector3.UP, Vector3.FORWARD)).scaled(Vector3.ONE * 0.45)
		for x in [-0.255, 0.255]:
			for y in [-0.19, 0.19]:
				poses.append(Transform3D(orientation, Vector3(x, y, 0)))
		ProductionPressDieArt._hardware(hardware, poses)
		meshes.hardware = hardware
		meshes.frame_leaf = ProductionVisuals.box_mesh(Vector3(0.06, 0.07, 0.006))
		meshes.panel_leaf = ProductionVisuals.box_mesh(Vector3(0.05, 0.07, 0.006))
		var pin := CylinderMesh.new()
		pin.top_radius = 0.011
		pin.bottom_radius = 0.011
		pin.height = 0.09
		pin.radial_segments = 16
		meshes.hinge_pin = pin
		meshes.latch_back = ProductionVisuals.box_mesh(Vector3(0.10, 0.15, 0.006))
		meshes.latch_stand = ProductionVisuals.box_mesh(Vector3(0.018, 0.022, 0.036))
		meshes.latch_grip = ProductionVisuals.box_mesh(Vector3(0.025, 0.13, 0.018))
		meshes.latch_keeper = ProductionVisuals.box_mesh(Vector3(0.055, 0.08, 0.006))
		meshes.latch_tongue = ProductionVisuals.box_mesh(Vector3(0.10, 0.025, 0.026))

	static func _fixed(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
			finish: Material) -> void:
		var part := MeshInstance3D.new()
		part.name = role
		part.set_meta("collector_service_role", role)
		part.mesh = mesh
		part.position = at
		part.material_override = finish
		parent.add_child(part)

	static func mount(parent: Node3D, color: Color) -> void:
		_prepare()
		var paint := ProductionCollectorArt.coating(color.darkened(0.14))
		var steel := ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.85, 0.38)
		var gasket := ProductionVisuals.material(Color("1c2424"), 0.0, 0.95)
		for row in [["RearServiceGasket", "gasket", -0.5115, gasket],
			["RearServicePanel", "panel", -0.522, paint], ["RearServiceHardware", "hardware", -0.531, steel]]:
			var part := MeshInstance3D.new()
			part.name = row[0]
			part.set_meta("collector_service_role", row[1])
			part.mesh = meshes[row[1]]
			part.position = Vector3(-0.22, 0.67, row[2])
			part.material_override = row[3]
			parent.add_child(part)
		# Two fixed leaves visibly connect the removable panel to the casting.
		# The pin bridges their different front planes; none is a service action.
		for y in [0.52, 0.79]:
			var suffix := "Lower" if y < 0.67 else "Upper"
			_fixed(parent, "RearServiceFrameLeaf" + suffix, meshes.frame_leaf,
				Vector3(-0.575, y, -0.513), steel)
			_fixed(parent, "RearServicePanelLeaf" + suffix, meshes.panel_leaf,
				Vector3(-0.51, y, -0.534), steel)
			_fixed(parent, "RearServiceHingePin" + suffix, meshes.hinge_pin,
				Vector3(-0.545, y, -0.525), steel)
		# A visible pull and fixed keeper make the opposite edge read as closed.
		_fixed(parent, "RearServiceLatchBack", meshes.latch_back, Vector3(0.015, 0.67, -0.534), steel)
		for y in [0.615, 0.725]:
			_fixed(parent, "RearServiceLatchStand" + ("Low" if y < 0.67 else "High"),
				meshes.latch_stand, Vector3(0.015, y, -0.55), steel)
		_fixed(parent, "RearServiceLatchGrip", meshes.latch_grip, Vector3(0.015, 0.67, -0.574), steel)
		_fixed(parent, "RearServiceLatchKeeper", meshes.latch_keeper, Vector3(0.145, 0.67, -0.513), steel)
		_fixed(parent, "RearServiceLatchTongue", meshes.latch_tongue, Vector3(0.11, 0.67, -0.524), steel)

class ProductionEnvironment:
	extends RefCounted
	## Visual scenery only. ActorWorld owns collision from the same immutable site geometry.
	static var Surface = load("res://opening/site_surface.gd") if ResourceLoader.exists("res://opening/site_surface.gd", "Script") else null
	static var ground_finish: ShaderMaterial
	const GROUND_ROOT := "res://opening/assets/ground"
	const GROUND_FILES := {"albedo": "ground_albedo.webp", "arm": "ground_arm.webp", "normal": "ground_normal_gl.webp"}
	const GROUND_SHADER = preload("res://opening/terrain_surface.gdshader")
	static var ground_source_status := "uninitialized"
	static var water_finish: StandardMaterial3D
	static var foam_finish: StandardMaterial3D
	static var stone_finish: StandardMaterial3D
	const STONE_ROOT := "res://opening/assets/stone"
	const STONE_FILES := {"albedo": "stone_albedo.webp", "arm": "stone_arm.webp", "normal": "stone_normal_gl.webp"}
	static var stone_source_status := "uninitialized"
	static var timber_finish: StandardMaterial3D
	const CUT_WOOD_SHADER = preload("res://opening/mature_tree_cut.gdshader")
	static var cut_wood_finish: ShaderMaterial
	static var iron_finish: StandardMaterial3D
	static var sky_finish: PanoramaSkyMaterial
	const SKY_FILE := "res://opening/assets/sky/kloppenheim_03_puresky_1k.hdr"
	# Brightest source texel centre in the pinned panorama coordinate convention.
	# This is an initial lighting orientation, not a time-of-day or weather rule.
	const SKY_SUN_DIRECTION := Vector3(-0.3070684373, 0.8529605865, 0.4220985472)
	static var sky_source_status := "uninitialized"
	static var terrain_surface_mesh: ArrayMesh
	static var stream_surface_mesh: ArrayMesh
	static var foliage_cluster_mesh: ArrayMesh
	const FOLIAGE_FILE := "res://opening/assets/foliage/grass_tuft.glb"
	static var foliage_source_status := "uninitialized"
	static var foliage_finish: StandardMaterial3D
	const FERN_FILE := "res://opening/assets/ferns/fern_clump.glb"
	static var fern_source_status := "uninitialized"
	static var fern_cluster_mesh: ArrayMesh
	static var fern_finish: StandardMaterial3D
	const PINE_FILE := "res://opening/assets/pine/pine_sapling.res"
	const PINE_SHA256 := "42bf54f373fc5ee316cc16e59993ec1d19060b30c859441948cc192703959b8e"
	# Source gray dielectric F0 = ((ior - 1)/(ior + 1))^2 * specularColor.
	# Compatibility uses F0 = 0.16 * specular^2. This maps only the two
	# pinned opaque/cutout materials, not general glTF scattering extensions.
	const PINE_SPECULAR := [0.1, 0.07071067811865476]
	static var pine_source_status := "uninitialized"
	static var pine_cluster_mesh: ArrayMesh
	const SHRUB_FILES := ["res://opening/assets/shrub/shrub_tall.res", "res://opening/assets/shrub/shrub_low.res"]
	const SHRUB_SHA256 := ["b13e205e991152435f581e4c29a393098cc8ce0854c409846656f475b230bf25",
		"ee2b375f3f26abef349419321534ad53618a348ddfbbdd226109c3b4d88f0565"]
	static var shrub_meshes: Array[ArrayMesh] = []
	static var rock_boulder_mesh: ArrayMesh

	static func ground_material() -> ShaderMaterial:
		if ground_source_status != "uninitialized":
			return ground_finish
		var loaded := ProductionSteelFloor.read_images(GROUND_ROOT, GROUND_FILES, Vector2i(512, 512))
		ground_source_status = loaded.status
		if loaded.status != "ready":
			push_error("Ground shading requires its complete qualified surface set.")
			return null
		var rock := stone_material()
		if stone_source_status != "ready":
			ground_source_status = "invalid"
			push_error("Steep ground shading requires its complete qualified stone set.")
			return null
		for role in loaded.images:
			var image: Image = loaded.images[role]
			if image.generate_mipmaps(role == "normal") != OK:
				ground_source_status = "invalid"
				push_error("Cannot generate forest-ground mipmaps.")
				return null
		ground_finish = ShaderMaterial.new()
		ground_finish.shader = GROUND_SHADER
		for role in loaded.images:
			ground_finish.set_shader_parameter(role + "_map", ImageTexture.create_from_image(loaded.images[role]))
		ground_finish.set_shader_parameter("stone_albedo_map", rock.albedo_texture)
		ground_finish.set_shader_parameter("stone_normal_map", rock.normal_texture)
		ground_finish.set_shader_parameter("stone_arm_map", rock.roughness_texture)
		# The stochastic mapping retains each source sample's physical scale.
		ground_finish.set_shader_parameter("source_extent", 1.4)
		ground_finish.set_shader_parameter("stone_extent", 1.5)
		return ground_finish

	static func _ripple_normals(seed: int, frequency: float) -> ImageTexture:
		# A cached two-dimensional height field breaks straight wave bands.
		# Wrapped derivatives and normalized mips keep repeat edges smooth.
		var noise := FastNoiseLite.new()
		noise.seed = seed
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = frequency
		noise.fractal_octaves = 3
		noise.fractal_gain = 0.45
		var heights := noise.get_seamless_image(256, 256)
		var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in range(256):
			for x in range(256):
				var dx := heights.get_pixel((x + 1) % 256, y).r - heights.get_pixel((x + 255) % 256, y).r
				var dy := heights.get_pixel(x, (y + 1) % 256).r - heights.get_pixel(x, (y + 255) % 256).r
				var slope := (Vector2(dx, dy) * 12.0).limit_length(0.34)
				var normal := Vector3(-slope.x, -slope.y, 1).normalized()
				image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5))
		image.generate_mipmaps(true)
		return ImageTexture.create_from_image(image)

	static func water_material() -> StandardMaterial3D:
		if water_finish == null:
			water_finish = StandardMaterial3D.new()
			# The mesh already carries the river palette. Do not multiply
			# it by a second dark teal tint. Transmission is an art approximation,
			# not depth-dependent absorption or a second water simulation.
			water_finish.albedo_color = Color(1.0, 1.0, 1.0, 0.86)
			water_finish.vertex_color_use_as_albedo = true
			water_finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water_finish.metallic = 0.0
			water_finish.metallic_specular = 0.16
			water_finish.roughness = 0.27
			water_finish.normal_enabled = true
			water_finish.normal_texture = _ripple_normals(338453, 0.016)
			water_finish.normal_scale = 0.42
			water_finish.uv1_scale = Vector3(2, 8, 1)
			var blend := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			blend.set_pixel(0, 0, Color(1.0, 1.0, 1.0, 0.35))
			water_finish.detail_enabled = true
			water_finish.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			water_finish.detail_albedo = ImageTexture.create_from_image(blend)
			water_finish.detail_normal = _ripple_normals(596043, 0.025)
			water_finish.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
			water_finish.uv2_scale = Vector3(7, 48, 1)
			water_finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return water_finish

	static func animate_water(seconds: float) -> bool:
		# The mesh UV grows downstream at a density estimated from the same
		# terrain and staged water used for native current. A negative texture
		# offset moves the ripple faster through narrow reaches.
		# Absolute time makes shared material updates idempotent across views.
		# It is never a production clock or waterwheel authority.
		if water_finish == null or not is_finite(seconds) or seconds < 0.0:
			return false
		water_finish.uv1_offset = Vector3(0.0, -fposmod(seconds * 0.256, 1.0), 0.0)
		# UV2 has six times the downstream density. Both layers advect at
		# the same local estimated speed, with a small lateral drift. Reduce time
		# before the faster multiplication so every finite time remains valid.
		water_finish.uv2_offset = Vector3(-fposmod(seconds * 0.0385, 1.0),
			-fposmod(fposmod(seconds, 1.0 / 1.536) * 1.536, 1.0), 0.0)
		return true

	static func foam_material() -> StandardMaterial3D:
		if foam_finish == null:
			foam_finish = ProductionVisuals.material(Color("bdd6d8"), 0.04, 0.55)
		return foam_finish

	static func stone_material() -> StandardMaterial3D:
		if stone_finish == null:
			stone_finish = _scanned_stone_material()
			if stone_finish == null:
				stone_finish = ProductionVisuals.material(Color("5c635c"), 0.05, 0.88)
		return stone_finish

	static func _scanned_stone_material() -> StandardMaterial3D:
		var loaded := ProductionSteelFloor.read_images(STONE_ROOT, STONE_FILES, Vector2i(512, 512), Vector2i(256, 256))
		stone_source_status = loaded.status
		if loaded.status == "missing":
			return null
		if loaded.status != "ready":
			push_error("Incomplete or invalid weathered-stone material: " + str(loaded.get("reason", "unknown")))
			return null
		for role in loaded.images:
			var image: Image = loaded.images[role]
			if image.generate_mipmaps(role == "normal") != OK:
				stone_source_status = "invalid"
				push_error("Cannot generate weathered-stone mipmaps.")
				return null
		var packed := ImageTexture.create_from_image(loaded.images.arm)
		var finish := StandardMaterial3D.new()
		finish.albedo_color = Color.WHITE
		finish.albedo_texture = ImageTexture.create_from_image(loaded.images.albedo)
		finish.vertex_color_use_as_albedo = true
		finish.metallic = 0.0
		finish.metallic_texture = packed
		finish.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		finish.roughness = 1.0
		finish.roughness_texture = packed
		finish.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		finish.ao_enabled = true
		finish.ao_texture = packed
		finish.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		finish.ao_light_affect = 0.0
		finish.normal_enabled = true
		finish.normal_texture = ImageTexture.create_from_image(loaded.images.normal)
		finish.normal_scale = 1.0
		finish.uv1_triplanar = true
		finish.uv1_world_triplanar = true
		finish.uv1_triplanar_sharpness = 8.0
		finish.uv1_scale = Vector3.ONE / 1.5
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return finish

	static func timber_material() -> StandardMaterial3D:
		if timber_finish == null:
			timber_finish = ProductionVisuals.material(Color("6e5339"), 0.04, 0.84)
		return timber_finish

	static func cut_wood_material() -> ShaderMaterial:
		if cut_wood_finish == null:
			cut_wood_finish = ShaderMaterial.new()
			cut_wood_finish.shader = CUT_WOOD_SHADER
		return cut_wood_finish

	static func iron_material() -> StandardMaterial3D:
		if iron_finish == null:
			iron_finish = ProductionVisuals.material(Color("3b4b50"), 0.78, 0.42)
		return iron_finish

	static func river_center_x(z: float) -> float:
		return Surface.river_center_x(z)

	static func channel_half_width(z: float) -> float:
		return Surface.channel_half_width(z)

	static func terrain_height(x: float, z: float) -> float:
		return Surface.raw_height(x, z)

	static func terrain_normal(x: float, z: float) -> Vector3:
		return Surface.normal(x, z)

	static func _terrain_vertex_color(x: float, y: float, z: float, normal: Vector3) -> Color:
		var gorge := smoothstep(-0.25, -1.05, y)
		var slope := clampf(1.0 - normal.y, 0.0, 1.0)
		var high := smoothstep(1.2, 11.5, y)
		var base := Color("626852").lerp(Color("8a846c"), high)
		base = base.lerp(Color("555b56"), clampf(slope * 2.6 + high * 0.35, 0.0, 1.0))
		var moisture := smoothstep(4.2, 0.8, absf(x - river_center_x(z)))
		base = base.lerp(Color("3d4a3d"), moisture * 0.45)
		base = base.lerp(Color("2c3638"), gorge)
		if ground_source_status == "uninitialized":
			ground_material()
		# Preserve broad elevation/moisture variation without multiplying the
		# photographed albedo by a second dark procedural base coat.
		return base.lerp(Color.WHITE, 0.75) if ground_source_status == "ready" else base

	static func terrain_mesh() -> ArrayMesh:
		if terrain_surface_mesh != null:
			return terrain_surface_mesh
		var subdivisions: int = Surface.grid_size() - 1
		var positions: PackedVector3Array = Surface.vertices()
		var normals: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		var colors: Array[Color] = []
		var stride := subdivisions + 1
		for position in positions:
			var n := terrain_normal(position.x, position.z)
			normals.append(n)
			uvs.append(Vector2((position.x + Surface.HALF) / Surface.SIZE, (position.z + Surface.HALF) / Surface.SIZE))
			colors.append(_terrain_vertex_color(position.x, position.y, position.z, n))
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for gz in range(subdivisions):
			for gx in range(subdivisions):
				var i00 := gz * stride + gx
				var i10 := i00 + 1
				var i01 := (gz + 1) * stride + gx
				var i11 := i01 + 1
				for tri in [[i00, i10, i11], [i00, i11, i01]]:
					for idx in tri:
						surface.set_normal(normals[idx])
						surface.set_uv(uvs[idx])
						surface.set_color(colors[idx])
						surface.add_vertex(positions[idx])
		surface.generate_tangents()
		terrain_surface_mesh = surface.commit()
		return terrain_surface_mesh

	static func stream_surface_height(x_world: float, z_world: float) -> float:
		return Surface.stream_surface_height(x_world, z_world)

	static func stream_mesh() -> ArrayMesh:
		if stream_surface_mesh != null:
			return stream_surface_mesh
		var rows := 238
		var cols := 6
		var z_start := -58.0
		var z_end := 61.0
		var stride := cols + 1
		var positions: Array[Vector3] = []
		var normals: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		var colors: Array[Color] = []
		var uv_v := 0.0
		var previous_uv_density := 0.0
		for r in range(rows + 1):
			var tz := float(r) / float(rows)
			var z_world := lerpf(z_start, z_end, tz)
			# Both normal layers scroll by 0.032 UV units per second after
			# material scaling. Wider, slower reaches need denser UVs.
			var uv_density := 0.032 / maxf(Surface.display_flow_speed(z_world), 0.05)
			if r > 0:
				uv_v += (previous_uv_density + uv_density) * 0.5 * (z_end - z_start) / float(rows)
			previous_uv_density = uv_density
			var z_local := z_world - 1.65
			var rc_local := river_center_x(z_world) - (-2.7)
			var west_w: float = Surface.wet_half_width(z_world, -1.0)
			var east_w: float = Surface.wet_half_width(z_world, 1.0)
			for c in range(stride):
				var tc := float(c) / float(cols) * 2.0 - 1.0
				var x_local := rc_local + tc * (west_w if tc < 0.0 else east_w)
				var x_world := -2.7 + x_local
				var y := stream_surface_height(x_world, z_world)
				var dz := 0.25
				var dy_dz := stream_surface_height(x_world, z_world + dz) - stream_surface_height(x_world, z_world - dz)
				var dy_dx := stream_surface_height(x_world + 0.12, z_world) - stream_surface_height(x_world - 0.12, z_world)
				var normal := Vector3(-dy_dx / 0.24, 1.0, -dy_dz / (2.0 * dz)).normalized()
				var color := Color("254d51")
				# Thin shoreline water blends into the real bank. This is visual
				# opacity, not depth simulation or additional underwater geometry.
				color.a = 0.25 if c == 0 or c == cols else 1.0
				var x_world_uv := -2.7 + x_local
				positions.append(Vector3(x_local, y, z_local))
				normals.append(normal)
				uvs.append(Vector2((x_world_uv + 16.0) * 0.22, uv_v))
				colors.append(color)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for r in range(rows):
			for c in range(cols):
				var i00 := r * stride + c
				var i10 := i00 + 1
				var i01 := (r + 1) * stride + c
				var i11 := i01 + 1
				for tri in [[i00, i10, i11], [i00, i11, i01]]:
					for idx in tri:
						surface.set_normal(normals[idx])
						surface.set_uv(uvs[idx])
						surface.set_uv2(uvs[idx])
						surface.set_color(colors[idx])
						surface.add_vertex(positions[idx])
		surface.generate_tangents()
		stream_surface_mesh = surface.commit()
		return stream_surface_mesh

	static func read_sky(path: String = SKY_FILE) -> Dictionary:
		if not ProductionVisuals.image_exists(path):
			return {"status": "missing"}
		if not path.begins_with("res://"):
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() < 1000 or file.get_length() > 2 * 1024 * 1024:
				return {"status": "invalid", "reason": "source_size"}
			file.close()
		var image := ProductionVisuals.read_image(path)
		if image == null or image.is_empty() or image.get_size() != Vector2i(1024, 512) or image.get_format() != Image.FORMAT_RGBE9995:
			return {"status": "invalid", "reason": "radiance_decode"}
		# Preserve the original HDR radiance; no sRGB conversion, tone mapping,
		# resizing or disk recompression is used for the delivered environment.
		image.convert(Image.FORMAT_RGBF)
		if image.generate_mipmaps() != OK:
			return {"status": "invalid", "reason": "radiance_mipmaps"}
		return {"status": "ready", "image": image}

	static func panorama_material() -> PanoramaSkyMaterial:
		if sky_finish != null:
			return sky_finish
		var loaded := read_sky()
		sky_source_status = loaded.status
		if loaded.status == "ready":
			sky_finish = PanoramaSkyMaterial.new()
			sky_finish.panorama = ImageTexture.create_from_image(loaded.image)
			return sky_finish
		if loaded.status == "invalid":
			push_error("Invalid sourced daylight panorama: " + str(loaded.reason))
		# Fixed historical rosters retain the original generated panorama.
		var image := Image.create(512, 256, false, Image.FORMAT_RGBF)
		var sun_direction := Basis.from_euler(Vector3(deg_to_rad(-48), deg_to_rad(-30), 0)).z
		for y in range(256):
			var elevation := PI * (0.5 - float(y) / 255.0)
			var height := sin(elevation)
			for x in range(512):
				var azimuth := TAU * float(x) / 511.0
				# Match Godot's SKY_COORDS atan(direction.x, -direction.z).
				var direction := Vector3(cos(elevation) * sin(azimuth), height, -cos(elevation) * cos(azimuth))
				var haze := Color("c0c7b5")
				var color := haze.lerp(Color("3f6a88"), pow(clampf(height, 0, 1), 0.45))
				# Original distant silhouettes live in the sky, never as solid
				# scenery that an actor could walk through on the flat floor.
				for ridge in range(3):
					var horizon := 0.015 + float(ridge) * 0.018 + 0.018 * sin(azimuth * 3.0 + ridge * 2.0) + 0.012 * sin(azimuth * 7.0 + ridge)
					if height < horizon:
						color = [Color("667970"), Color("7e8c7d"), Color("9ca696")][ridge]
				if height < -0.08:
					color = Color("565f4d")
				var alignment := maxf(0.0, direction.dot(sun_direction))
				color += Color(0.55, 0.36, 0.17) * pow(alignment, 128.0)
				if alignment > 0.9998:
					color += Color(5.0, 4.6, 3.8)
				image.set_pixel(x, y, color)
		image.generate_mipmaps()
		sky_finish = PanoramaSkyMaterial.new()
		sky_finish.panorama = ImageTexture.create_from_image(image)
		return sky_finish

	static func _scenery_box(parent: Node3D, part_name: String, at: Vector3, dimensions: Vector3,
			finish: StandardMaterial3D, rotation_rad: Vector3 = Vector3.ZERO) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = part_name
		part.mesh = ProductionVisuals.box_mesh(dimensions)
		part.position = at
		part.rotation = rotation_rad
		part.material_override = finish
		parent.add_child(part)
		return part

	static func _scenery_turned(parent: Node3D, part_name: String, at: Vector3,
			profile: PackedVector2Array, finish: StandardMaterial3D, axis: Vector3 = Vector3.UP) -> MeshInstance3D:
		var part := MeshInstance3D.new()
		part.name = part_name
		part.position = at
		part.basis = Basis(Quaternion(Vector3.UP, axis))
		part.mesh = ProductionVisuals.turned_mesh(profile, 24)
		part.material_override = finish
		parent.add_child(part)
		return part

	static func _build_millrace_architecture(scenery: Node3D) -> Node3D:
		var arch := Node3D.new()
		arch.name = "MillraceArchitecture"
		scenery.add_child(arch)
		var groups := {"MillraceArchitecture": arch}
		for group in ["HeadraceGorge", "TailraceCascade"]:
			var node := Node3D.new()
			node.name = group
			node.position = Surface.group_origin(group)
			arch.add_child(node)
			groups[group] = node
		var finishes := {"stone": stone_material(), "dark_stone": ProductionVisuals.material(Color("38403e"), 0.0, 0.92),
			"foam": foam_material()}
		for spec in Surface.architecture_boxes():
			var part := _scenery_box(groups[spec.group], spec.label,
				spec.center - Surface.group_origin(spec.group), spec.size, finishes[spec.finish])
			part.basis = spec.basis
			if spec.solid:
				part.set_meta("site_solid_id", spec.id)
		return arch

	static func _cutout_mipmaps(image: Image) -> bool:
		image.convert(Image.FORMAT_RGBA8)
		image.fix_alpha_edges()
		if image.generate_mipmaps() != OK:
			return false
		var data := image.get_data()
		var covered := 0
		for pixel in range(image.get_width() * image.get_height()):
			if data[pixel * 4 + 3] >= 128:
				covered += 1
		var coverage := float(covered) / float(image.get_width() * image.get_height())
		for level in range(1, image.get_mipmap_count() + 1):
			var pixels := maxi(1, image.get_width() >> level) * maxi(1, image.get_height() >> level)
			var offset := image.get_mipmap_offset(level)
			var histogram := PackedInt32Array()
			histogram.resize(256)
			for pixel in range(pixels):
				histogram[data[offset + pixel * 4 + 3]] += 1
			# Choose the nearest achievable coverage, including an empty subpixel mip.
			var target := coverage * pixels
			var cutoff := 256
			var error := target
			var count := 0
			for alpha in range(255, 0, -1):
				count += histogram[alpha]
				if absf(count - target) < error:
					error = absf(count - target)
					cutoff = alpha
			for pixel in range(pixels):
				var at := offset + pixel * 4 + 3
				data[at] = mini(255, int(float(data[at]) * 128.0 / cutoff))
		image.set_data(image.get_width(), image.get_height(), true, Image.FORMAT_RGBA8, data)
		return true

	static func read_foliage(path: String = FOLIAGE_FILE, vertex_count: int = 1386, index_count: int = 3771) -> Dictionary:
		if not FileAccess.file_exists(path):
			return {"status": "missing"}
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() < 1000 or bytes.size() > 650000:
			return {"status": "invalid", "reason": "package_size"}
		# Runtime buffer import keeps the captured asset self-contained. It does
		# not require an editor-generated .import file or instantiate a scene.
		var document := GLTFDocument.new()
		var imported := GLTFState.new()
		imported.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
		if document.append_from_buffer(bytes, "", imported) != OK:
			return {"status": "invalid", "reason": "glb_decode"}
		var meshes := imported.get_meshes()
		if meshes.size() != 1 or meshes[0].mesh == null or meshes[0].mesh.get_surface_count() != 1:
			return {"status": "invalid", "reason": "mesh_set"}
		var mesh: ArrayMesh = meshes[0].mesh.get_mesh()
		var arrays := mesh.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_VERTEX].size() != vertex_count or arrays[Mesh.ARRAY_INDEX].size() != index_count:
			return {"status": "invalid", "reason": "geometry_count"}
		var finish := mesh.surface_get_material(0) as StandardMaterial3D
		if finish == null or finish.albedo_texture == null or finish.normal_texture == null or finish.roughness_texture == null:
			return {"status": "invalid", "reason": "material_set"}
		var color := finish.albedo_texture.get_image()
		var normal := finish.normal_texture.get_image()
		var scalars := finish.roughness_texture.get_image()
		if color == null or normal == null or scalars == null or color.get_size() != Vector2i(384, 384) or normal.get_size() != Vector2i(256, 256) or scalars.get_size() != Vector2i(256, 256):
			return {"status": "invalid", "reason": "texture_extent"}
		if path == FOLIAGE_FILE:
			# Reversible meadow palette: retain photographed detail, not black bands.
			for y in range(color.get_height()):
				for x in range(color.get_width()):
					var pixel := color.get_pixel(x, y)
					var detail := pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
					var green := Color(0.28, 0.38, 0.16).lerp(Color(0.5, 0.62, 0.30), detail)
					green.a = pixel.a
					color.set_pixel(x, y, green)
			finish.metallic_specular = 0.2
		# Runtime GLB buffer import preserves images but does not create their
		# mip chains. Build them once with vector renormalization for normals.
		if not _cutout_mipmaps(color) or normal.generate_mipmaps(true) != OK or scalars.generate_mipmaps() != OK:
			return {"status": "invalid", "reason": "texture_mipmaps"}
		finish.albedo_texture = ImageTexture.create_from_image(color)
		finish.normal_texture = ImageTexture.create_from_image(normal)
		var packed := ImageTexture.create_from_image(scalars)
		finish.metallic_texture = packed
		finish.roughness_texture = packed
		finish.ao_texture = packed
		finish.albedo_color = Color.WHITE
		finish.vertex_color_use_as_albedo = true
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return {"status": "ready", "mesh": mesh, "material": finish}

	static func _foliage() -> MultiMeshInstance3D:
		if foliage_cluster_mesh == null:
			var loaded := read_foliage()
			foliage_source_status = loaded.status
			if loaded.status == "ready":
				foliage_cluster_mesh = loaded.mesh
				foliage_finish = loaded.material
			elif loaded.status == "invalid":
				push_error("Invalid sourced foliage: " + str(loaded.reason))
		if foliage_cluster_mesh == null:
			# Historical fixed launch rosters omit new bitmap/mesh assets. Their
			# earlier generated blades remain explicit instead of claiming import.
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for ring in [[0.0, 0.24, 0.08, 0.045], [0.12, 0.42, 0.14, 0.065]]:
				var y_base: float = ring[0]
				var y_tip: float = ring[1]
				var spread: float = ring[2]
				var half_blade: float = ring[3]
				for idx in range(6):
					var angle := float(idx) * TAU / 6.0 + y_base * 1.7
					var radial := Vector3(cos(angle), 0, sin(angle))
					var tangent := Vector3(-sin(angle), 0, cos(angle)) * half_blade
					var base_center := radial * 0.03 + Vector3.UP * y_base
					var tip := radial * spread + Vector3.UP * y_tip
					var normal := (radial + Vector3.UP * 0.55).normalized()
					surface.set_normal(normal)
					for vertex in [base_center - tangent, tip, base_center + tangent]:
						surface.add_vertex(vertex)
			foliage_cluster_mesh = surface.commit()
		var finish := foliage_finish
		if finish == null:
			finish = StandardMaterial3D.new()
			finish.albedo_color = Color.WHITE
			finish.vertex_color_use_as_albedo = true
			finish.cull_mode = BaseMaterial3D.CULL_DISABLED
			finish.roughness = 0.92
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = foliage_cluster_mesh
		instances.instance_count = 96
		var buffer := PackedFloat32Array()
		for n in range(96):
			var angle := float(n) * 2.399963
			var radius := 11.2 + float(posmod(n * 13, 37)) * 0.52
			var px := 1.65 + cos(angle) * radius
			var pz := 1.65 + sin(angle) * radius
			var river_x := river_center_x(pz)
			var bank_clearance := channel_half_width(pz) + 1.1
			if absf(px - river_x) < bank_clearance:
				px = river_x + bank_clearance * (1.0 if px >= river_x else -1.0)
			var py: float = Surface.height_at(px, pz)
			var position := Vector3(px, py, pz)
			var scale := 0.85 + float(posmod(n * 7, 13)) * 0.08
			var basis := Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale)
			var color := Color("4b643e").lerp(Color("8f8b62"), float(n % 5) / 4.0)
			if foliage_source_status == "ready":
				color = Color.WHITE.lerp(Color("e3e5cf"), float(n % 5) / 4.0)
			# Upload once: three matrix rows, each with its translation, then RGBA.
			buffer.append_array(PackedFloat32Array([
				basis.x.x, basis.y.x, basis.z.x, position.x,
				basis.x.y, basis.y.y, basis.z.y, position.y,
				basis.x.z, basis.y.z, basis.z.z, position.z,
				color.r, color.g, color.b, color.a]))
		instances.buffer = buffer
		var foliage := MultiMeshInstance3D.new()
		foliage.name = "GroundFoliage"
		foliage.multimesh = instances
		foliage.material_override = finish
		foliage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED if foliage_source_status == "ready" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		foliage.set_meta("candidate_buffer", buffer)
		return foliage

	static func _terrain_facet_normal(x: float, z: float) -> Vector3:
		var cell: Vector2i = Surface.cell(x, z)
		var a: Vector3 = Surface.vertex(cell.x, cell.y)
		var b: Vector3 = Surface.vertex(cell.x + 1, cell.y)
		var c: Vector3 = Surface.vertex(cell.x + 1, cell.y + 1)
		var d: Vector3 = Surface.vertex(cell.x, cell.y + 1)
		var tx := (x - a.x) / (b.x - a.x)
		var tz := (z - a.z) / (d.z - a.z)
		return (c - a).cross(b - a).normalized() if tz <= tx else (d - a).cross(c - a).normalized()

	static func _clear_meadow_root(position: Vector3, solids: Array) -> bool:
		# Reject an expanded whole-clump envelope, not just a point hidden
		# inside an existing rock. Small plants remain noncolliding decoration.
		if absf(position.x - river_center_x(position.z)) <= channel_half_width(position.z) + 0.8:
			return false
		for spec in solids:
			var local: Vector3 = spec.basis.transposed() * (position - spec.center)
			var half: Vector3 = spec.size * 0.5 + Vector3.ONE * 0.9
			if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
				return false
		return true

	static func _meadow_patches() -> Node3D:
		var meadow := Node3D.new()
		meadow.name = "MeadowPatches"
		if foliage_source_status != "ready":
			return meadow
		var solids: Array = Surface.support_boxes()
		var random := RandomNumberGenerator.new()
		random.seed = 718093
		# Overlapping, compact patches avoid the isolated tufts left by the
		# previous wide spiral while retaining cullable local groups.
		const patch_count := 40
		for patch_index in range(patch_count):
			var heading := float(patch_index) * 2.399963 + random.randf_range(-0.7, 0.7)
			var radius := sqrt(float(patch_index) / float(patch_count)) * 27.0
			var center := Vector3(1.65 + cos(heading) * radius, 0.0, 1.65 + sin(heading) * radius)
			center.y = Surface.height_at(center.x, center.z)
			var buffer := PackedFloat32Array()
			var bounds := AABB()
			var count := 0
			for candidate in range(48):
				var angle := random.randf_range(0.0, TAU)
				var spread := sqrt(random.randf()) * 3.0
				var root_position := center + Vector3(cos(angle) * spread, 0.0, sin(angle) * spread)
				root_position.y = Surface.height_at(root_position.x, root_position.z)
				var up := _terrain_facet_normal(root_position.x, root_position.z)
				if up.y < 0.82 or not _clear_meadow_root(root_position, solids):
					continue
				var right := Vector3(up.y, -up.x, 0.0).normalized()
				var basis := Basis(right, up, right.cross(up)) * Basis(Vector3.UP, random.randf_range(0.0, TAU))
				basis = basis.scaled_local(Vector3.ONE * random.randf_range(0.8, 1.55))
				var local := root_position - center
				var tint := Color.WHITE.lerp(Color("e3e5cf"), random.randf_range(0.0, 0.8))
				buffer.append_array(PackedFloat32Array([
					basis.x.x, basis.y.x, basis.z.x, local.x,
					basis.x.y, basis.y.y, basis.z.y, local.y,
					basis.x.z, basis.y.z, basis.z.z, local.z,
					tint.r, tint.g, tint.b, tint.a]))
				var envelope: AABB = Transform3D(basis, local) * foliage_cluster_mesh.get_aabb()
				bounds = envelope if count == 0 else bounds.merge(envelope)
				count += 1
			if count == 0:
				continue
			var instances := MultiMesh.new()
			instances.transform_format = MultiMesh.TRANSFORM_3D
			instances.use_colors = true
			instances.mesh = foliage_cluster_mesh
			instances.instance_count = count
			instances.buffer = buffer
			instances.custom_aabb = bounds
			var patch := MultiMeshInstance3D.new()
			patch.name = "GrassPatch%02d" % patch_index
			patch.position = center
			patch.multimesh = instances
			patch.material_override = foliage_finish
			patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			patch.visibility_range_end = 62.0
			patch.set_meta("candidate_buffer", buffer)
			meadow.add_child(patch)
		return meadow

	static func _foreground_bank() -> MultiMeshInstance3D:
		var patch := MultiMeshInstance3D.new()
		patch.name = "ForegroundBank"
		if foliage_source_status != "ready":
			return patch
		var solids: Array = Surface.support_boxes()
		var random := RandomNumberGenerator.new()
		random.seed = 321704
		var buffer := PackedFloat32Array()
		var bounds := AABB()
		var count := 0
		# The eastern working bank stays open. These soft plants frame the
		# opposite bank, rather than filling the ordinary construction space.
		for candidate in range(96):
			var z := random.randf_range(-5.5, 9.0)
			var x := river_center_x(z) - channel_half_width(z) - random.randf_range(1.1, 2.6)
			var at := Vector3(x, Surface.height_at(x, z), z)
			var up := _terrain_facet_normal(x, z)
			if up.y < 0.86:
				continue
			var right := Vector3(up.y, -up.x, 0.0).normalized()
			var basis := Basis(right, up, right.cross(up)) * Basis(Vector3.UP, random.randf_range(0.0, TAU))
			basis = basis.scaled_local(Vector3.ONE * random.randf_range(0.85, 1.15))
			var envelope: AABB = Transform3D(basis, at) * foliage_cluster_mesh.get_aabb()
			var clear := envelope.position.z >= -8.0 and envelope.end.z <= 12.0
			# On this local reach, |d(center - half_width)/dz| < 0.6.
			# The half-sample margin bounds the unsampled intervals as well.
			var margin := 0.2 + 0.6 * envelope.size.z / 16.0
			for row in range(9):
				var edge_z := lerpf(envelope.position.z, envelope.end.z, float(row) / 8.0)
				if envelope.end.x >= river_center_x(edge_z) - channel_half_width(edge_z) - margin:
					clear = false
			for solid in solids:
				var local: Vector3 = solid.basis.transposed() * (at - solid.center)
				var half: Vector3 = solid.size * 0.5 + Vector3.ONE * 0.9
				if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
					clear = false
			if not clear:
				continue
			var tint := Color.WHITE.lerp(Color("e3e5cf"), random.randf_range(0.0, 0.45))
			buffer.append_array(PackedFloat32Array([
				basis.x.x, basis.y.x, basis.z.x, at.x,
				basis.x.y, basis.y.y, basis.z.y, at.y,
				basis.x.z, basis.y.z, basis.z.z, at.z,
				tint.r, tint.g, tint.b, tint.a]))
			bounds = envelope if count == 0 else bounds.merge(envelope)
			count += 1
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = foliage_cluster_mesh
		instances.instance_count = count
		instances.buffer = buffer
		instances.custom_aabb = bounds
		patch.multimesh = instances
		patch.material_override = foliage_finish
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		patch.visibility_range_end = 40.0
		# Candidates are derived presentation, never saved vegetation state.
		patch.set_meta("candidate_buffer", buffer)
		return patch

	static func _construction_volumes(state: Dictionary) -> Array[AABB]:
		var volumes: Array[AABB] = []
		var size := Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])
		for entity: Dictionary in state.get("entities", {}).values():
			var center := Vector3(entity.cell[0] * Geometry.PITCH,
				float(entity.get("level", 0)) * Geometry.HEIGHT_STEP + Geometry.MACHINE_CENTER_HEIGHT,
				entity.cell[1] * Geometry.PITCH)
			var half := size * 0.5
			if entity.get("kind") == "wheel" and state.get("options", {}).get("native", false):
				center.y = float(entity.get("level", 0)) * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT
				half = Geometry.wheel_half_extents(int(entity.get("axis", 0)), int(entity.get("tiles", 3)))
			volumes.append(AABB(center - half, half * 2.0).grow(0.08))
		for foundation: Dictionary in state.get("foundations", {}).values():
			var top := Vector3(foundation.cell[0] * Geometry.PITCH,
				foundation.level * Geometry.HEIGHT_STEP, foundation.cell[1] * Geometry.PITCH)
			volumes.append(AABB(top - Vector3(Geometry.PITCH * 0.5, Geometry.FOUNDATION_DEPTH, Geometry.PITCH * 0.5),
				Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH)).grow(0.08))
		if state.has("landing_pod"):
			var pod: Dictionary = state.landing_pod
			if pod.get("deployed", false):
				var pod_center: Array = pod.center
				var center := Vector3(float(pod_center[0]) * Geometry.PITCH,
					float(pod_center[1]) * Geometry.HEIGHT_STEP,
					float(pod_center[2]) * Geometry.PITCH)
				var half := Geometry.PITCH * 1.5
				# The native deck is a cleared landing, including the air above it.
				# Its nine floor volumes alone only hide plants below panel height.
				volumes.append(AABB(center - Vector3(half, 0.5, half),
					Vector3(half * 2.0, 2.7, half * 2.0)))
				var hub: Dictionary = state.get("fabrication_hub", {})
				if hub.get("installed", false) and hub.has("position"):
					var position: Array = hub.position
					var hub_floor := Vector3(float(position[0]), float(position[1]) - Geometry.ANCHOR_HEIGHT,
						float(position[2]))
					volumes.append(AABB(hub_floor - Vector3(0.7, 0.1, 0.5), Vector3(1.4, 1.5, 1.0)))
		return volumes

	static func _refresh_plant_patch(patch: MultiMeshInstance3D, volumes: Array[AABB]) -> void:
		if patch == null or patch.multimesh == null:
			return
		var original: PackedFloat32Array = patch.get_meta("candidate_buffer")
		var kept := PackedFloat32Array()
		var mesh_bounds := patch.multimesh.mesh.get_aabb()
		var stride := 16 if patch.multimesh.use_colors else 12
		for offset in range(0, original.size(), stride):
			var basis := Basis(Vector3(original[offset], original[offset + 4], original[offset + 8]),
				Vector3(original[offset + 1], original[offset + 5], original[offset + 9]),
				Vector3(original[offset + 2], original[offset + 6], original[offset + 10]))
			var at := Vector3(original[offset + 3], original[offset + 7], original[offset + 11])
			var bounds: AABB = (patch.global_transform * Transform3D(basis, at)) * mesh_bounds
			var clear := true
			for volume: AABB in volumes:
				if bounds.intersects(volume):
					clear = false
					break
			if clear:
				kept.append_array(original.slice(offset, offset + stride))
		patch.multimesh.instance_count = kept.size() / stride
		patch.multimesh.buffer = kept

	static func refresh_vegetation(scenery: Node3D, state: Dictionary) -> void:
		# Only soft, unsaved decoration is hidden. Natural collision geometry
		# and the confirmed construction facts remain untouched.
		var volumes := _construction_volumes(state)
		for spec in Surface.fir_specs() + Surface.broadleaf_specs():
			var source: Dictionary = state.get("hand_sources", {}).get(spec.id, {})
			if source.get("remaining", 1) == 0:
				var radius := 0.5 if str(spec.id).begins_with("fir_") else 0.8
				volumes.append(AABB(spec.center - Vector3(radius, 0.1, radius),
					Vector3(radius * 2.0, 0.8, radius * 2.0)))
		for name in ["GroundFoliage", "ForegroundBank", "PineUnderstory"]:
			_refresh_plant_patch(scenery.get_node_or_null(name) as MultiMeshInstance3D, volumes)
		var shrubs := scenery.get_node_or_null("ShrubUnderstory")
		if shrubs != null:
			for patch: MultiMeshInstance3D in shrubs.get_children():
				_refresh_plant_patch(patch, volumes)
		var meadow := scenery.get_node_or_null("MeadowPatches")
		if meadow != null:
			for patch: MultiMeshInstance3D in meadow.get_children():
				_refresh_plant_patch(patch, volumes)

	static func read_pine(path: String = PINE_FILE) -> Dictionary:
		if not FileAccess.file_exists(path):
			return {"status": "missing"}
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 4194304:
			return {"status": "invalid", "reason": "Pine resource exceeds its four-MiB component bound."}
		file.close()
		if FileAccess.get_sha256(path) != PINE_SHA256:
			return {"status": "invalid", "reason": "Pine resource does not match its prepared identity."}
		var mesh := ResourceLoader.load(path, "ArrayMesh") as ArrayMesh
		if mesh == null or mesh.get_surface_count() != 2 or not ResourceLoader.get_dependencies(path).is_empty():
			return {"status": "invalid", "reason": "Pine requires one self-contained two-surface mesh."}
		for surface in range(2):
			var original := mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null:
				return {"status": "invalid", "reason": "Pine requires its two qualified standard materials."}
			if not is_equal_approx(original.metallic_specular, PINE_SPECULAR[surface]):
				# Keep imported material references and every texture intact.
				# Repeated reads reuse these surface bindings across all plants.
				var adapted := original.duplicate(false) as StandardMaterial3D
				adapted.metallic_specular = PINE_SPECULAR[surface]
				mesh.surface_set_material(surface, adapted)
		return {"status": "ready", "mesh": mesh}

	static func _pine_understory() -> MultiMeshInstance3D:
		var patch := MultiMeshInstance3D.new()
		patch.name = "PineUnderstory"
		if pine_source_status == "uninitialized":
			var loaded := read_pine()
			pine_source_status = loaded.status
			if loaded.status == "ready":
				pine_cluster_mesh = loaded.mesh
			elif loaded.status == "invalid":
				push_error("Invalid sourced pine component: " + str(loaded.reason))
		if pine_cluster_mesh == null:
			return patch
		var buffer := PackedFloat32Array()
		var bounds := AABB()
		var count := 0
		# Age and bank position vary across the same sourced young-pine mesh.
		# These remain soft plants that construction can clear, not mature solids.
		for n in range(64):
			var z := -17.0 + float((n * 11) % 43) * 0.72
			var side := -1.0 if n % 2 == 0 else 1.0
			var x := river_center_x(z) + side * (channel_half_width(z) + 3.2 + float(n % 4) * 1.1)
			if _terrain_facet_normal(x, z).y < 0.86:
				continue
			var at := Vector3(x, Surface.height_at(x, z) - 0.015, z)
			var age := 1.15 + float((n * 7) % 9) * 0.23
			var breadth := 0.86 + float(n % 4) * 0.09
			var basis := Basis(Vector3.UP, float(n) * 2.399963).scaled_local(Vector3(age * breadth, age, age / breadth))
			var envelope: AABB = Transform3D(basis, at) * pine_cluster_mesh.get_aabb()
			var clear := envelope.position.z >= -22.0 and envelope.end.z <= 22.0
			var margin := 0.3 + 0.6 * envelope.size.z / 16.0
			for row in range(9):
				var edge_z := lerpf(envelope.position.z, envelope.end.z, float(row) / 8.0)
				var edge_x := river_center_x(edge_z) + side * (channel_half_width(edge_z) + margin)
				if (side < 0.0 and envelope.end.x >= edge_x) or (side > 0.0 and envelope.position.x <= edge_x):
					clear = false
			for solid in Surface.support_boxes():
				var half: Vector3 = solid.size * 0.5
				var solid_bounds: AABB = Transform3D(solid.basis, solid.center) * AABB(-half, solid.size)
				if envelope.intersects(solid_bounds.grow(0.2)):
					clear = false
			for fir in Surface.fir_specs():
				if envelope.intersects(fir.bounds.grow(0.2)):
					clear = false
			for broadleaf in Surface.broadleaf_specs():
				if envelope.intersects(broadleaf.bounds.grow(0.2)):
					clear = false
			if not clear:
				continue
			# Do not stack one expensive source mesh over another.
			for offset in range(0, buffer.size(), 12):
				if Vector2(at.x - buffer[offset + 3], at.z - buffer[offset + 11]).length() < 2.4:
					clear = false
			if not clear:
				continue
			buffer.append_array(PackedFloat32Array([
				basis.x.x, basis.y.x, basis.z.x, at.x,
				basis.x.y, basis.y.y, basis.z.y, at.y,
				basis.x.z, basis.y.z, basis.z.z, at.z]))
			bounds = envelope if count == 0 else bounds.merge(envelope)
			count += 1
			if count == 6:
				break
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = pine_cluster_mesh
		instances.instance_count = count
		instances.buffer = buffer
		instances.custom_aabb = bounds
		patch.multimesh = instances
		patch.visibility_range_end = 32.0
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		patch.set_meta("candidate_buffer", buffer)
		return patch

	static func _bank_firs() -> Node3D:
		var group := Node3D.new()
		group.name = "BankFirs"
		var specs: Array[Dictionary] = Surface.fir_specs()
		if specs.is_empty():
			return group
		var mesh: ArrayMesh = Surface.fir_mesh()
		for spec in specs:
			var tree := MeshInstance3D.new()
			tree.name = spec.id
			tree.mesh = mesh
			tree.position = spec.center
			tree.basis = spec.basis.scaled_local(Vector3.ONE * spec.scale)
			tree.visibility_range_end = 65.0
			tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			group.add_child(tree)
		return group

	static func _bank_broadleaf() -> Node3D:
		var group := Node3D.new()
		group.name = "BankBroadleaf"
		var mesh: ArrayMesh = Surface.broadleaf_mesh()
		if mesh == null:
			return group
		for spec in Surface.broadleaf_specs():
			var tree := MeshInstance3D.new()
			tree.name = spec.id
			tree.mesh = mesh
			tree.position = spec.center
			tree.basis = spec.basis.scaled_local(Vector3.ONE * spec.scale)
			tree.visibility_range_end = 70.0
			tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			group.add_child(tree)
		return group

	static func _read_shrubs() -> bool:
		if shrub_meshes.size() == 2:
			return true
		shrub_meshes.clear()
		for variant in range(2):
			var path: String = SHRUB_FILES[variant]
			if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != SHRUB_SHA256[variant]:
				push_error("Qualified shrub resource is missing or changed: " + path)
				return false
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() > 2097152:
				push_error("Qualified shrub resource exceeds its component allocation.")
				return false
			file.close()
			var mesh := ResourceLoader.load(path, "ArrayMesh") as ArrayMesh
			if mesh == null or mesh.get_surface_count() != 3 or not ResourceLoader.get_dependencies(path).is_empty():
				push_error("Qualified shrub resource has missing or external components.")
				return false
			shrub_meshes.append(mesh)
		return true

	static func _bank_shrubs() -> Node3D:
		var group := Node3D.new()
		group.name = "ShrubUnderstory"
		if not _read_shrubs():
			return group
		var solids: Array[Dictionary] = Surface.support_boxes()
		var trees: Array = Surface.fir_specs() + Surface.broadleaf_specs()
		for variant in range(2):
			var mesh: ArrayMesh = shrub_meshes[variant]
			var buffer := PackedFloat32Array()
			var bounds := AABB()
			var count := 0
			for n in range(64):
				var z := -19.0 + float((n * 13 + variant * 7) % 40)
				var side := 1.0 if (n + variant) % 2 == 0 else -1.0
				var x := river_center_x(z) + side * (channel_half_width(z) + 2.7 + float(n % 4) * 1.45)
				if _terrain_facet_normal(x, z).y < 0.84:
					continue
				var at := Vector3(x, Surface.height_at(x, z) - 0.02, z)
				var size := 0.88 + float((n * 3 + variant) % 5) * 0.085
				var basis := Basis(Vector3.UP, float(n) * 2.399963).scaled_local(Vector3.ONE * size)
				var envelope: AABB = Transform3D(basis, at) * mesh.get_aabb()
				var clear := envelope.position.z >= -23.0 and envelope.end.z <= 23.0
				var margin := 0.25 + 0.6 * envelope.size.z / 16.0
				for row in range(5):
					var edge_z := lerpf(envelope.position.z, envelope.end.z, float(row) / 4.0)
					var edge_x := river_center_x(edge_z) + side * (channel_half_width(edge_z) + margin)
					if (side < 0.0 and envelope.end.x >= edge_x) or (side > 0.0 and envelope.position.x <= edge_x):
						clear = false
				for solid in solids:
					var half: Vector3 = solid.size * 0.5
					var solid_bounds: AABB = Transform3D(solid.basis, solid.center) * AABB(-half, solid.size)
					if envelope.intersects(solid_bounds.grow(0.15)):
						clear = false
				for tree in trees:
					if envelope.intersects(tree.bounds.grow(0.15)):
						clear = false
				for offset in range(0, buffer.size(), 12):
					if Vector2(at.x - buffer[offset + 3], at.z - buffer[offset + 11]).length() < 1.6:
						clear = false
				if not clear:
					continue
				buffer.append_array(PackedFloat32Array([
					basis.x.x, basis.y.x, basis.z.x, at.x,
					basis.x.y, basis.y.y, basis.z.y, at.y,
					basis.x.z, basis.y.z, basis.z.z, at.z]))
				bounds = envelope if count == 0 else bounds.merge(envelope)
				count += 1
				if count == 12:
					break
			var instances := MultiMesh.new()
			instances.transform_format = MultiMesh.TRANSFORM_3D
			instances.mesh = mesh
			instances.instance_count = count
			instances.buffer = buffer
			instances.custom_aabb = bounds
			var patch := MultiMeshInstance3D.new()
			patch.name = "TallShrubs" if variant == 0 else "LowShrubs"
			patch.multimesh = instances
			patch.visibility_range_end = 38.0
			patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			patch.set_meta("candidate_buffer", buffer)
			group.add_child(patch)
		return group

	static func _bank_ferns() -> Node3D:
		var group := Node3D.new()
		group.name = "BankFerns"
		if fern_source_status == "uninitialized":
			var loaded := read_foliage(FERN_FILE, 544, 2352)
			fern_source_status = loaded.status
			if loaded.status == "ready":
				fern_cluster_mesh = loaded.mesh
				fern_finish = loaded.material
			elif loaded.status == "invalid":
				push_error("Invalid sourced fern component: " + str(loaded.reason))
		if fern_cluster_mesh == null:
			# Historical incomplete rosters simply omit this optional low plant.
			return group
		var solids: Array = Surface.support_boxes()
		var buffer := PackedFloat32Array()
		var bounds := AABB()
		var count := 0
		for n in range(32):
			var z := -40.0 + float(n) * 2.55
			var side := -1.0 if n % 2 == 0 else 1.0
			var x := river_center_x(z) + side * (channel_half_width(z) + 1.45 + 0.28 * sin(float(n) * 1.7))
			var at := Vector3(x, Surface.height_at(x, z), z)
			var up := _terrain_facet_normal(x, z)
			if up.y < 0.86 or not _clear_meadow_root(at, solids):
				continue
			var right := Vector3(up.y, -up.x, 0.0).normalized()
			var basis := Basis(right, up, right.cross(up)) * Basis(Vector3.UP, float(n) * 2.399963)
			basis = basis.scaled_local(Vector3.ONE * (0.82 + 0.08 * float(n % 4)))
			buffer.append_array(PackedFloat32Array([
				basis.x.x, basis.y.x, basis.z.x, at.x,
				basis.x.y, basis.y.y, basis.z.y, at.y,
				basis.x.z, basis.y.z, basis.z.z, at.z,
				1.0, 1.0, 1.0, 1.0]))
			var envelope: AABB = Transform3D(basis, at) * fern_cluster_mesh.get_aabb()
			bounds = envelope if count == 0 else bounds.merge(envelope)
			count += 1
		if count == 0:
			return group
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = fern_cluster_mesh
		instances.instance_count = count
		instances.buffer = buffer
		instances.custom_aabb = bounds
		var ferns := MultiMeshInstance3D.new()
		ferns.name = "FernClumps"
		ferns.multimesh = instances
		ferns.material_override = fern_finish
		ferns.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		ferns.visibility_range_end = 62.0
		group.add_child(ferns)
		return group

	static func _rock_outcrops() -> MultiMeshInstance3D:
		if rock_boulder_mesh == null:
			rock_boulder_mesh = Surface.SOURCE_OUTCROP_MESH
		var finish := stone_material()
		if stone_source_status != "ready":
			finish = StandardMaterial3D.new()
			finish.albedo_color = Color.WHITE
			finish.vertex_color_use_as_albedo = true
			finish.roughness = 0.9
			finish.normal_enabled = true
			finish.normal_texture = ProductionVisuals.SURFACE_NORMAL
			finish.normal_scale = 0.28
			finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = rock_boulder_mesh
		instances.instance_count = 64
		var buffer := PackedFloat32Array()
		for spec in Surface.rock_boxes():
			var position: Vector3 = spec.center
			var basis: Basis = spec.basis * Basis.from_scale(spec.mesh_scale)
			var color: Color = spec.color
			if stone_source_status == "ready":
				color = Color.WHITE.lerp(color, 0.38)
			buffer.append_array(PackedFloat32Array([
				basis.x.x, basis.y.x, basis.z.x, position.x,
				basis.x.y, basis.y.y, basis.z.y, position.y,
				basis.x.z, basis.y.z, basis.z.z, position.z,
				color.r, color.g, color.b, color.a]))
		instances.buffer = buffer
		var outcrops := MultiMeshInstance3D.new()
		outcrops.name = "RockOutcrops"
		outcrops.multimesh = instances
		outcrops.material_override = finish
		return outcrops

	static func build(parent: Node3D) -> Node3D:
		var scenery := Node3D.new()
		scenery.name = "ProductionScenery"
		parent.add_child(scenery)
		var world := WorldEnvironment.new()
		world.name = "WorksiteEnvironment"
		var environment := Environment.new()
		environment.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		sky.sky_material = panorama_material()
		environment.sky = sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_energy = 0.6
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		environment.tonemap_exposure = 1.0
		environment.fog_enabled = true
		environment.fog_mode = Environment.FOG_MODE_DEPTH
		environment.fog_depth_begin = 35.0
		environment.fog_depth_end = 95.0
		environment.fog_density = 0.85
		environment.fog_light_color = Color("bbc5b3")
		environment.fog_sky_affect = 0.0
		world.environment = environment
		scenery.add_child(world)
		var sun := DirectionalLight3D.new()
		sun.name = "WorksiteSun"
		sun.rotation_degrees = Vector3(-48, -30, 0)
		if sky_source_status == "ready":
			sun.basis = Basis.looking_at(-SKY_SUN_DIRECTION, Vector3.UP)
		sun.light_color = Color("fff0d4")
		sun.light_energy = 1.25
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 45.0
		scenery.add_child(sun)
		var fill := DirectionalLight3D.new()
		fill.name = "WorksiteFill"
		fill.rotation_degrees = Vector3(-32, 135, 0)
		fill.light_color = Color("b9d2ea")
		fill.light_energy = 0.18
		fill.shadow_enabled = false
		scenery.add_child(fill)
		var terrain := MeshInstance3D.new()
		terrain.name = "GroundSurface"
		terrain.mesh = terrain_mesh()
		terrain.position = Vector3.ZERO
		terrain.material_override = ground_material()
		scenery.add_child(terrain)
		var stream := MeshInstance3D.new()
		stream.name = "StreamSurface"
		stream.mesh = stream_mesh()
		stream.position = Vector3(-2.7, 0.0, 1.65)
		stream.material_override = water_material()
		stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scenery.add_child(stream)
		_build_millrace_architecture(scenery)
		scenery.add_child(_rock_outcrops())
		scenery.add_child(_foliage())
		scenery.add_child(_meadow_patches())
		scenery.add_child(_bank_ferns())
		scenery.add_child(_foreground_bank())
		scenery.add_child(_pine_understory())
		scenery.add_child(_bank_firs())
		scenery.add_child(_bank_broadleaf())
		scenery.add_child(_bank_shrubs())
		return scenery

const STEP_SECONDS := 0.45
const PITCH := Geometry.PITCH
const NAMES := {"collector": "Collector", "belt": "Belt", "processor": "Press", "wheel": "Waterwheel", "foundation": "Foundation", "pod_workshop": "Pod workshop"}
const COLORS := {"collector": Color("96805c"), "belt": Color("538e88"), "processor": Color("bd7054"), "wheel": Color("8b9caa")}

var model
var actor_world
var character_presenter
var actor_label: Label
var startup_save_pending := false
var startup_save_scheduled := false
var auto_advance := true
var client := "P"
var request_sequence := 0
# A fresh view must not restart request IDs into a restored authority's cache.
# This nonce identifies submitted intents; it never randomizes simulation rules.
var request_namespace := "opening-" + Crypto.new().generate_random_bytes(16).hex_encode() + "-"
var save_slot := ""
var save_slot_ready := false
var save_slot_owned := false
var last_save_result: Dictionary = {}
var last_load_result: Dictionary = {}
var startup_resume_checkpoint: Dictionary = {}
const FIRST_COLLECTOR_HINT := "Choose Collector [1] on the ore-colored ground beside the rock."
var mode := "inspect"
var pending_link := ""
var selected := ""
var goal_confirmed := false
var explanation_open := false
var help_close_button: Button
var elapsed := 0.0
var orbit_yaw := 0.68
var orbit_pitch := 0.82
var native_camera_initialized := false
var distance := 18.5
var focus := Vector3(1.3, 0.0, 1.1)
const FIRST_PERSON_EYE_OFFSET := 0.35
const FIRST_PERSON_BLEND_DISTANCE := 4.0
var hover_cell := Vector2i(99, 99)
var visual_revision := -1
var geometry_key := ""
var ui_refresh_key: Array = []
var hand_tree_nodes: Dictionary = {}
var hand_tree_assets: Dictionary = {}
var mature_tree_nodes: Dictionary = {}
var mature_tree_collision_rows: Dictionary = {}
var camera: Camera3D
var machine_root: Node3D
var item_root: Node3D
var workpiece_item_assets
var hover: MeshInstance3D
var selection_ring: MeshInstance3D
var machine_preview: Node3D
var component_preview: Node3D
var press_snap_target: MeshInstance3D
var press_snap_material: StandardMaterial3D
var press_snap_lift: Node3D
var press_snap_lift_tip: MeshInstance3D
var press_snap_lift_material: StandardMaterial3D
var component_preview_kind := ""
var component_preview_pose_key := ""
var component_preview_material: StandardMaterial3D
var component_preview_cell_materials: Dictionary = {}
var component_preview_blocked := false
var component_preview_snap := ""
var component_footprint_size := 1
var component_area_anchor: Array = []
var component_area_kind := ""
var mutable_machine_preview: Node3D
var machine_preview_key := ""
var machine_preview_material: StandardMaterial3D
var packed_preview_templates: Dictionary = {}
var packed_preview_nodes: Dictionary = {}
var preview_variant_pending := false
var preview_prefetch_paths: Array[String] = []
var preview_prefetch_complete := false
const BAKED_WHEEL_PREVIEW_MAX_TILES := 9
var machine_dynamic_batches: Array[Dictionary] = []
var machine_conveyor_batches: Array[Dictionary] = []
var machine_conveyor_batch_slots: Dictionary = {}
var machine_rotors: Array[Dictionary] = []
var machine_rotor_cells: Array[Dictionary] = []
var machine_batched_rotors: Dictionary = {}
var machine_batched_rotor_slots: Dictionary = {}
var machine_cutter_batch_slots: Dictionary = {}
var wheel_batch_poses: Dictionary = {}
var wheel_updated_rotors: Dictionary = {}
var machine_motion_anchors: Array[Node3D] = []
var machine_batch_finished_meshes: Dictionary = {}
var machine_batch_rotor_meshes: Dictionary = {}
var machine_batch_composite_meshes: Dictionary = {}
# Spatial draws help the measured native Windows renderer at large scale,
# but overwhelm the WSL Compatibility path even when they cull triangles.
var machine_static_spatial_tiles: int = 4 if OS.has_feature("windows") else 0
var machine_batch_static_machine_count := 0
var transmission_preview_point: Array = []
var wheel_rotor: Node3D
var machine_body_context := ""
var machine_press_poses: Dictionary = {}
var status_label: Label
var developer_mode_label: Label
var fps_label: Label
var fps_elapsed := 0.0
var status_footer: Control
var status_refused := false
var footer_snapshot_ready := false
var footer_fit_pending := false
var stock_label: Label
var parts_label: Label
var goal_label: Label
var objective_heading: Label
var manager_log_button: Button
var manager_log_layer: CanvasLayer
var manager_log_panel: PanelContainer
var manager_log_current: Label
var manager_log_completion_entry: Label
var manager_log_projects: VBoxContainer
var manager_log_open := false
var workshop_completion_observed: Variant = null
var workshop_completion_audio: AudioStreamPlayer
var workshop_completion_cue_count := 0
var help_button: Button
var goal_progress: ProgressBar
var power_label: Label
var inspector: Label
var inspector_title: Label
var inspection_actions: HBoxContainer
var pointed_summary: PanelContainer
var pointed_name: Label
var pointed_detail: Label
var object_menu: PopupPanel
var object_menu_scrim: ColorRect
var object_menu_title: Label
var object_menu_operations_label: Label
var object_menu_close: Button
var object_menu_operations: VBoxContainer
var object_menu_detail_panel: PanelContainer
var object_menu_desired_extent := Vector2i(500, 400)
var object_menu_viewport_size := Vector2i.ZERO
var object_menu_target := ""
var object_menu_closed_frame := -1
var mouse_capture_owned := false
var mouse_capture_skip_motion := false
var pause_menu: PanelContainer
var pause_menu_scrim: ColorRect
var pause_resume_button: Button
var pause_exit_button: Button
var pause_exit_confirmation: ConfirmationDialog
var recovery_actions
var loose_material_controls
var transmission_controls
var transmission_presenter
var construction_audio
var engineering_presenter
var mechanical_ambience
var confirm_button: Button
var retrieve_button: Button
var remove_button: Button
var save_button: Button
var load_button: Button
var help_panel: PanelContainer
var help_title: Label
var help_body: Label
var tool_buttons: Dictionary = {}
var building_hotbar
var build_column: VBoxContainer
var foundation_level := Geometry.HEIGHT_DENOMINATOR
var foundation_steps := false
var foundation_steps_toggle: CheckButton
var foundation_area_mode := false
var foundation_area_started := false
var foundation_area_start := Vector2i.ZERO
var foundation_area_toggle: CheckButton
var foundation_level_controls: HBoxContainer
var foundation_level_label: Label
var wheel_level := 4
var wheel_tiles := 3
var wheel_size_controls: HBoxContainer
var wheel_size_label: Label
var state: Dictionary = {}
var consumed_shortcut_keys: Dictionary = {}
var held_crank := ""
var held_crank_seconds := 0.0
var held_crank_context := ""
var held_crank_request := ""
var catalog_button: Button
var controls_label: Label
var building_rotation := 0
var rotation_button: Button
var placement_options_panel: PanelContainer
var placement_options_column: VBoxContainer
var placement_options_title: Label
var placement_options_hint: Label
var placement_options_axis: Button
var placement_cell_cache := Vector2i.ZERO
var arrival_assembly_controls
var arrival_assembly_scroll: ScrollContainer
var component_nudge_active := false
var component_nudge_center: Array = []
var landing_pod_visual: Node3D
var landing_hub_visual: Node3D
var landing_hub_pick: StaticBody3D
var arrival_reveal_probe := false
var arrival_reveal_active := false
var arrival_reveal_elapsed := 0.0
var arrival_reveal_pod_anchor := Vector3.ZERO
var arrival_gameplay_canvas: CanvasLayer
var arrival_reveal_canvas: CanvasLayer
var arrival_reveal_caption: Label
var arrival_reveal_audio
const ARRIVAL_REVEAL_SECONDS := 2.8

static func apply_test_window_title(tree: SceneTree) -> bool:
	var purpose := ""
	var found := false
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--test-purpose="):
			continue
		if found:
			push_error("Use exactly one test window purpose")
			tree.quit(2)
			return false
		found = true
		purpose = argument.trim_prefix("--test-purpose=")
	if not found:
		return true
	if purpose.strip_edges().is_empty() or purpose.length() > 60 or "\n" in purpose or "\r" in purpose:
		push_error("Invalid test window purpose")
		tree.quit(2)
		return false
	tree.root.title = "Factory — " + purpose
	return true

func _ready() -> void:
	if not apply_test_window_title(get_tree()):
		return
	if model == null:
		push_error("Opening requires an assigned native or shared model")
		get_tree().quit(1)
		return
	if save_slot.is_empty():
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--save-slot="):
				configure_save_slot(argument.trim_prefix("--save-slot="))
	_build_world()
	_build_interface()
	for menu: Node in [object_menu, pause_menu, pause_exit_confirmation,
			building_hotbar.catalog, manager_log_layer, help_panel]:
		if menu != null:
			menu.connect("visibility_changed", _on_mouse_menu_visibility_changed)
	_refresh()
	if _native_transmission():
		if state.has("hand_sources"):
			call_deferred("_warm_packed_machine_previews")
		else:
			_prime_machine_visuals()
	if not _native_transmission():
		_message("WASD walks. Build nearby; a wheel in the stream drives connected parts.")
	elif not state.has("hand_sources"):
		_message(FIRST_COLLECTOR_HINT)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="):
			var result: Dictionary = _load_worksite(argument.trim_prefix("--resume-input="), true)
			if not result.accepted or not model.projection().options.get("opening", false):
				push_error("Opening resume refused; no fresh-world fallback")
				get_tree().quit(1)
				return
			startup_resume_checkpoint = model.checkpoint()
			startup_save_pending = true
			_message("Worksite reopened in this session. Your original save is kept.")
	if not _start_character_world():
		return
	_start_character_presenter()
	if model is NativeWorldModel and state.has("landing_pod") and startup_resume_checkpoint.is_empty() \
			and (auto_advance or arrival_reveal_probe):
		_maybe_start_arrival_reveal.call_deferred()

func _start_character_world() -> bool:
	actor_world = ActorWorld.new()
	actor_world.name = "OpeningActors"
	actor_world.set_belt_step_seconds(STEP_SECONDS if auto_advance else 0.0)
	actor_world.pose_published.connect(_actor_pose)
	actor_world.initialization_failed.connect(_actor_failed)
	var configured: Dictionary = actor_world.configure(model)
	if not configured.accepted:
		actor_world.free()
		actor_world = null
		_actor_failed(client, configured.reason)
		return false
	add_child(actor_world)
	for actor in model.projection().actors:
		if not actor_world.ensure_actor(actor).accepted:
			return false
	return true

func _start_character_presenter() -> void:
	distance = 14.0
	character_presenter = CharacterPresenter.new()
	character_presenter.name = "Characters"
	character_presenter.configure(self)
	add_child(character_presenter)

func _actor_pose(actor: String, sample: Dictionary) -> void:
	var result: Dictionary = model.publish_actor(actor, sample.position, sample.native_epoch)
	if not result.accepted:
		_actor_failed(actor, result.reason)
		return
	if character_presenter != null:
		character_presenter.observe_native_sample(actor, sample)
	# The ordinary render-frame refresh follows this physics cut. The first
	# ready pose and paused fixtures still need their immediate snapshot.
	if not (model is NativeWorldModel and auto_advance \
			and state.get("actors", {}).get(actor, {}).get("ready", false)):
		_refresh()
	if startup_save_pending and not startup_save_scheduled:
		var all_ready := true
		for current in model.projection().actors.values():
			all_ready = all_ready and current.ready
		if all_ready:
			startup_save_scheduled = true
			call_deferred("_finish_startup_save")

func _finish_startup_save() -> void:
	var saved: Dictionary = _save_worksite()
	if not saved.accepted:
		_actor_failed(client, "resume_save_failed:" + str(saved.reason))
		return
	startup_save_pending = false
	_refresh_ui()
	_message("Worksite reopened in this session. Your original save is kept.")

func _actor_failed(actor: String, reason: String) -> void:
	if model != null and model.has_method("invalidate_actor"):
		model.invalidate_actor(actor)
	push_error("Physical character unavailable for " + actor + ": " + reason)
	get_tree().quit(1)

func _can_control_character() -> bool:
	return _actor_ready_for_actions() and not _object_menu_open() and not _pause_menu_open() \
		and DisplayServer.window_get_active_popup() == DisplayServer.INVALID_WINDOW_ID

func _actor_ready_for_actions() -> bool:
	return not arrival_reveal_active and not manager_log_open and not _catalog_open() and not explanation_open \
		and not startup_save_pending and state.get("actors", {}).get(client, {}).get("ready", false)

func _can_use_object_actions() -> bool:
	return _actor_ready_for_actions()

func _can_choose_tool() -> bool:
	# The catalog holds movement while keeping its own choices available.
	return not arrival_reveal_active and not manager_log_open and not explanation_open and not startup_save_pending and not _object_menu_open() and not _pause_menu_open() \
		and state.get("actors", {}).get(client, {}).get("ready", false)

func _native_transmission() -> bool:
	return state.get("options", {}).get("native", false)

func _can_present_confirmed_motion() -> bool:
	return _native_transmission() and not explanation_open and not startup_save_pending and state.get("actors", {}).get(client, {}).get("ready", false)

func _contains_target(snapshot: Dictionary, id: String) -> bool:
	return snapshot.get("entities", {}).has(id) or snapshot.get("foundations", {}).has(id) or (snapshot.get("options", {}).get("native", false)
		and (snapshot.get("transmission_parts", {}).has(id) or snapshot.get("belt_spans", {}).has(id)
			or snapshot.get("placed_components", {}).has(id)
			or (snapshot.get("fabrication_hub", {}).get("installed", false)
				and snapshot.fabrication_hub.get("id", "") == id)))

func _refresh_transmission() -> void:
	if not _native_transmission():
		if transmission_controls != null:
			if not transmission_controls.active_tool.is_empty():
				transmission_controls.cancel()
				mode = "inspect"
			transmission_controls.refresh()
		if transmission_presenter != null:
			transmission_presenter.refresh()
		return
	if transmission_controls == null:
		# Historical fixed-roster runtimes do not include the native helpers.
		# A native worksite requires the complete captured native project.
		var controls_path := "res://opening/native_transmission_controls.gd"
		var presenter_path := "res://opening/native_transmission_presenter.gd"
		if not ResourceLoader.exists(controls_path, "Script") or not ResourceLoader.exists(presenter_path, "Script"):
			push_error("Native transmission requires the complete captured project")
			get_tree().quit(1)
			return
		transmission_controls = load(controls_path).new()
		transmission_controls.custom_minimum_size.y = 37
		placement_options_column.add_child(transmission_controls)
		transmission_controls.configure(self)
		transmission_presenter = load(presenter_path).new()
		add_child(transmission_presenter)
		transmission_presenter.configure(self)
	transmission_controls.refresh()
	transmission_presenter.refresh()
	var active: bool = not transmission_controls.active_tool.is_empty()
	transmission_controls.visible = active
	if not active and mode in ["gear", "drive", "belt", "gearbox", "vertical_gearbox", "chain_drive"]:
		mode = "inspect"
	_update_cursor()

func _engineering_progress() -> Dictionary:
	if not _native_transmission():
		return {}
	var records: Variant = state.get("opening_engineering", {})
	if not records is Dictionary:
		return {}
	var report: Variant = records.get(client, {})
	if not report is Dictionary or report.get("schema") != 1 or report.get("format") != "factory-opening-engineering" or report.get("actor") != client or report.get("known_actor") != true:
		return {}
	var cell: Variant = report.get("wheel_cell")
	if not cell is Array or cell.size() != 2 or typeof(cell[0]) != TYPE_INT or typeof(cell[1]) != TYPE_INT:
		return {}
	if typeof(report.get("products")) != TYPE_INT or typeof(report.get("target")) != TYPE_INT or not report.get("phase", "") in ["first_shift", "move_source", "restore_drive", "deliver_more", "ready"]:
		return {}
	return report

func _refresh_engineering(snapshot_ready: bool) -> void:
	var report := _engineering_progress() if snapshot_ready else {}
	if report.is_empty():
		if engineering_presenter != null:
			engineering_presenter.visible = false
		goal_label.tooltip_text = ""
		return
	if engineering_presenter == null:
		var path := "res://opening/upstream_drive_challenge.gd"
		if not ResourceLoader.exists(path, "Script"):
			push_error("Native engineering content requires the complete captured project")
			get_tree().quit(1)
			return
		engineering_presenter = load(path).new()
		add_child(engineering_presenter)
		engineering_presenter.configure(self, Vector2i(report.wheel_cell[0], report.wheel_cell[1]))
	var cell := Vector2i(report.wheel_cell[0], report.wheel_cell[1])
	if engineering_presenter.target_wheel_cell != cell:
		engineering_presenter.set_target_wheel_cell(cell)
	engineering_presenter.refresh()
	# Confirmation only dismisses the introductory view. All challenge facts,
	# including eligibility after reopen, come from the native projection.
	var active: bool = goal_confirmed and report.phase != "first_shift"
	engineering_presenter.visible = active
	if not active:
		goal_label.tooltip_text = ""
		return
	goal_progress.max_value = maxi(1, int(report.target))
	goal_progress.value = clampi(int(report.products), 0, int(report.target))
	var step: String = {
		"move_source": "Move power upstream.",
		"restore_drive": "Restore the drive.",
		"deliver_more": "Collect four more plates.",
		"ready": "Upstream drive restored.",
	}[report.phase]
	goal_label.text = "UPSTREAM DRIVE\n%s\n%d / %d collected" % [step, report.products, report.target]
	var details: Dictionary = engineering_presenter.evaluate()
	goal_label.tooltip_text = str(details.get("diagnostic_text", "")) + "\n" + str(details.get("tradeoff_text", ""))
	confirm_button.visible = false

# A local read-only picker for the same site triangles shown by the view.
# Shared clients have no authority or character floor body of their own.
const TRANSMISSION_TERRAIN_PICK_LAYER := 32

func _install_transmission_terrain_picker() -> void:
	if ProductionEnvironment.Surface == null or has_node("TransmissionTerrainPicker"):
		return
	var terrain := StaticBody3D.new()
	terrain.name = "TransmissionTerrainPicker"
	terrain.set_meta("transmission_terrain", true)
	terrain.collision_layer = TRANSMISSION_TERRAIN_PICK_LAYER
	terrain.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(ProductionEnvironment.Surface.faces())
	var collider := CollisionShape3D.new()
	collider.shape = shape
	terrain.add_child(collider)
	add_child(terrain)

# Find the highest point of the emitted terrain triangles inside a footprint.
# Clipping the triangles also catches peaks and diagonal edges between samples.
func _transmission_terrain_high(x: float, z: float, half_x: float, half_z: float) -> float:
	var surface = ProductionEnvironment.Surface
	if not surface.contains(x - half_x, z - half_z) or not surface.contains(x + half_x, z + half_z):
		return NAN
	var first: Vector2i = surface.cell(x - half_x, z - half_z)
	var last: Vector2i = surface.cell(x + half_x, z + half_z)
	var high := -INF
	for gz in range(first.y, last.y + 1):
		for gx in range(first.x, last.x + 1):
			var a: Vector3 = surface.vertex(gx, gz)
			var b: Vector3 = surface.vertex(gx + 1, gz)
			var c: Vector3 = surface.vertex(gx + 1, gz + 1)
			var d: Vector3 = surface.vertex(gx, gz + 1)
			for triangle in [[a, b, c], [a, c, d]]:
				var polygon: Array = triangle
				for clip in [[0, x - half_x, 1.0], [0, x + half_x, -1.0], [2, z - half_z, 1.0], [2, z + half_z, -1.0]]:
					var clipped: Array = []
					for n in polygon.size():
						var p: Vector3 = polygon[n]
						var q: Vector3 = polygon[(n + 1) % polygon.size()]
						var inside: bool = (p[clip[0]] - clip[1]) * clip[2] >= 0.0
						var next_inside: bool = (q[clip[0]] - clip[1]) * clip[2] >= 0.0
						if inside:
							clipped.append(p)
						if inside != next_inside:
							clipped.append(p.lerp(q, (clip[1] - p[clip[0]]) / (q[clip[0]] - p[clip[0]])))
					polygon = clipped
				for p: Vector3 in polygon:
					high = maxf(high, p.y)
	return high

func _transmission_terrain_level(point: Vector3, x: float, z: float) -> int:
	var level := ceili(point.y / PITCH)
	if transmission_controls.active_tool not in ["place_shaft", "gear", "gearbox", "vertical_gearbox", "chain_drive"]:
		return level * Geometry.HEIGHT_DENOMINATOR
	var axis: String = transmission_controls.selected_axis
	var axle := Vector3(0.1, 0.1, 0.1)
	axle[["x", "y", "z"].find(axis)] = PITCH / 2.0
	var footprints: Array = [axle]
	if transmission_controls.active_tool == "gear":
		var disc := Vector3.ONE * PITCH / 2.0
		disc[["x", "y", "z"].find(axis)] = 0.04
		footprints.append(disc)
	elif transmission_controls.active_tool in ["gearbox", "vertical_gearbox", "chain_drive"]:
		footprints = [Vector3.ONE * PITCH / 2.0]
	for half: Vector3 in footprints:
		var high := _transmission_terrain_high(x, z, half.x, half.z)
		if is_finite(high):
			level = maxi(level, ceili((high - Geometry.ANCHOR_HEIGHT + half.y - 0.000000001) / PITCH))
	return level * Geometry.HEIGHT_DENOMINATOR

func _transmission_center(screen: Vector2) -> Array:
	if transmission_controls == null:
		return []
	var origin := camera.project_ray_origin(screen)
	var hit := _screen_pick(screen)
	if not hit.is_empty():
		if transmission_controls.active_tool == "place_shaft":
			var pulley_target := _belt_pulley_target(str(hit.collider.get_meta("entity", "")), hit.position)
			if not pulley_target.is_empty():
				return pulley_target
		var target := _transmission_snap_target(str(hit.collider.get_meta("entity", "")), hit.normal, origin)
		if not target.is_empty():
			return target
	if transmission_controls.auto_height:
		var terrain_ray := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 80.0)
		terrain_ray.collision_mask = TRANSMISSION_TERRAIN_PICK_LAYER
		var terrain_hit := get_world_3d().direct_space_state.intersect_ray(terrain_ray)
		if not terrain_hit.is_empty():
			var point: Vector3 = terrain_hit.position
			var x := roundi(point.x / PITCH)
			var z := roundi(point.z / PITCH)
			var level := _transmission_terrain_level(point, x * PITCH, z * PITCH)
			transmission_controls.snapped_height = level
			return [x * 4, level, z * 4]
	transmission_controls.snapped_height = 0
	var height: int = 0 if transmission_controls.auto_height else transmission_controls.gear_height
	var plane := Plane(Vector3.UP, Geometry.ANCHOR_HEIGHT + height * PITCH / 4.0)
	var point: Variant = plane.intersects_ray(origin, camera.project_ray_normal(screen))
	if point == null:
		return []
	return [roundi(point.x / PITCH) * 4, height, roundi(point.z / PITCH) * 4]

func _belt_pulley_target(entity_id: String, hit_position: Vector3) -> Array:
	var span: Variant = state.get("belt_spans", {}).get(entity_id)
	if not span is Dictionary or not hit_position.is_finite():
		return []
	var parts: Dictionary = state.get("transmission_parts", {})
	var first: Variant = parts.get(span.get("from", ""))
	var last: Variant = parts.get(span.get("to", ""))
	if not first is Dictionary or not last is Dictionary or first.get("kind") != "shaft" or last.get("kind") != "shaft":
		return []
	var a: Variant = first.get("center")
	var b: Variant = last.get("center")
	if not a is Array or not b is Array or a.size() != 3 or b.size() != 3:
		return []
	for axis in 3:
		if typeof(a[axis]) != TYPE_INT or typeof(b[axis]) != TYPE_INT or a[axis] % 4 != 0 or b[axis] % 4 != 0:
			return []
	var start := Vector3(a[0], a[1], a[2])
	var difference := Vector3(b[0], b[1], b[2]) - start
	var steps := roundi(maxf(absf(difference.x), maxf(absf(difference.y), absf(difference.z))) / 4.0)
	if steps < 1 or steps > 19:
		return []
	for axis in 3:
		if difference[axis] != 0.0 and absf(difference[axis]) != steps * 4.0:
			return []
	var world_start := start * Geometry.HEIGHT_STEP + Vector3.UP * Geometry.ANCHOR_HEIGHT
	var world_delta := difference * Geometry.HEIGHT_STEP
	var index := clampi(roundi((hit_position - world_start).dot(world_delta) / world_delta.length_squared() * steps), 0, steps)
	var center := start + difference * float(index) / float(steps)
	transmission_controls.snapped_height = roundi(center.y)
	return [roundi(center.x), transmission_controls.snapped_height if transmission_controls.auto_height else transmission_controls.gear_height, roundi(center.z)]

func _transmission_snap_target(entity_id: String, normal: Vector3, eye: Vector3) -> Array:
	# Pick bodies identify confirmed construction. Use their common grid height
	# when following surfaces; the menu can still choose an absolute air level.
	if transmission_controls.active_tool in ["place_shaft", "gear", "gearbox", "vertical_gearbox", "chain_drive"]:
		var part: Variant = state.get("transmission_parts", {}).get(entity_id)
		if part is Dictionary and part.get("kind") in ["shaft", "gear", "gearbox", "vertical_gearbox", "chain_drive"]:
			var center: Variant = part.get("center")
			if not center is Array or center.size() != 3 or not normal.is_finite():
				return []
			for coordinate: Variant in center:
				if typeof(coordinate) != TYPE_INT or coordinate % 4 != 0:
					return []
			var axis := 0
			for candidate in [1, 2]:
				if absf(normal[candidate]) > absf(normal[axis]):
					axis = candidate
			if absf(normal[axis]) < 0.5:
				return []
			var adjacent: Array = center.duplicate()
			adjacent[axis] += 4 if normal[axis] > 0.0 else -4
			transmission_controls.snapped_height = adjacent[1]
			adjacent[1] = adjacent[1] if transmission_controls.auto_height else transmission_controls.gear_height
			return adjacent
	var surface: Dictionary = state.get("foundations", {}).get(entity_id, {})
	if not surface.is_empty():
		var level: int = int(surface.get("level", 0))
		# Foundation slabs can end halfway between transmission tile levels.
		# Select the first shared tile at or above the top, including below zero.
		level = ceili(float(level) / Geometry.HEIGHT_DENOMINATOR) * Geometry.HEIGHT_DENOMINATOR
		transmission_controls.snapped_height = level
		return [int(surface.cell[0]) * 4, level if transmission_controls.auto_height else transmission_controls.gear_height,
			int(surface.cell[1]) * 4]
	var machine: Dictionary = state.get("entities", {}).get(entity_id, {})
	if machine.is_empty():
		return []
	var level: int = int(machine.get("level", 0))
	if level % Geometry.HEIGHT_DENOMINATOR != 0:
		return []
	var axis: int = ["x", "y", "z"].find(transmission_controls.selected_axis)
	if transmission_controls.active_tool in ["gearbox", "vertical_gearbox"] and typeof(machine.get("axis")) == TYPE_INT:
		axis = int(machine.axis)
	if axis < 0:
		return []
	var center := Vector3(machine.cell[0] * PITCH, level * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT,
		machine.cell[1] * PITCH)
	var side: float = normal[axis]
	if absf(side) < 0.5:
		side = (eye - center)[axis]
	var point := [int(machine.cell[0]) * 4, level, int(machine.cell[1]) * 4]
	point[axis] += 4 if side >= 0.0 else -4
	transmission_controls.snapped_height = point[1]
	point[1] = point[1] if transmission_controls.auto_height else transmission_controls.gear_height
	return point

func _transmission_click(center: Array, entity_id: String) -> bool:
	return _native_transmission() and transmission_controls != null and transmission_controls.handle_world_click(center, entity_id)

func _send_character_input(direction: Vector2, jump: bool) -> void:
	if actor_world != null:
		actor_world.set_control(client, direction, jump)

func _release_character_input() -> void:
	if actor_world != null:
		actor_world.release_control(client)

func _release_character_controls() -> void:
	if character_presenter != null:
		character_presenter.release()

func configure_save_slot(path: String) -> void:
	# The launcher supplies a fresh external session directory. One cooperating
	# writer owns this slot; this is not a cross-process filesystem lock.
	save_slot = path
	save_slot_owned = false
	save_slot_ready = path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://") and DirAccess.dir_exists_absolute(path.get_base_dir()) and not _path_exists(path) and not _path_exists(path + ".pending")

func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

func _save_worksite() -> Dictionary:
	if explanation_open or not save_slot_ready:
		last_save_result = {"accepted": false, "reason": "save_unavailable"}
	elif not save_slot_owned and _path_exists(save_slot):
		last_save_result = {"accepted": false, "reason": "existing_destination"}
	else:
		var physical: Dictionary = actor_world.checkpoint_status() if actor_world != null else {"accepted": false, "reason": "actor_unready"}
		last_save_result = Store.write(model, save_slot) if physical.accepted else {"accepted": false, "reason": physical.reason}
		last_save_result["native_preflight"] = physical.duplicate(true)
	if last_save_result.accepted:
		save_slot_owned = true
		_message("Worksite saved. Reopen this save through the launcher in a new session.")
	else:
		_message("Save unavailable. Your current worksite and previous save are kept.", true)
	_refresh_ui()
	return last_save_result

func _load_worksite(path: String = "", startup_resume := false) -> Dictionary:
	if not startup_resume:
		last_load_result = {"accepted": false, "reason": "load_requires_restart"}
		_message("Reopen the saved worksite through the launcher in a new session. The live worksite is kept.", true)
		return last_load_result
	if explanation_open or not save_slot_ready:
		last_load_result = {"accepted": false, "reason": "load_unavailable"}
	else:
		last_load_result = Store.read_into(model, save_slot if path.is_empty() else path)
	if last_load_result.accepted:
		# Restored revision/order may be lower or equal. Invalidate presentation
		# caches instead of altering the restored authoritative version.
		if transmission_controls != null:
			transmission_controls.clear_belt_selection()
		selected = ""
		pending_link = ""
		geometry_key = ""
		visual_revision = -1
		elapsed = 0.0
		request_sequence = 0
		request_namespace = "opening-" + Crypto.new().generate_random_bytes(16).hex_encode() + "-"
		goal_confirmed = false
		# A restored completed order is already known; reopening is not a new receipt.
		workshop_completion_observed = null
		_refresh()
		_message("Worksite loaded. Select a machine to continue.")
	else:
		_message("Load refused. Your current worksite and previous save are kept.", true)
	return last_load_result

func _construction_feedback(intent: Dictionary, outcome: Dictionary) -> void:
	if ConstructionAudio.cue_for(intent).is_empty() or not outcome.get("accepted", false):
		return
	if construction_audio == null:
		construction_audio = ConstructionAudio.new()
		construction_audio.name = "ConstructionAudio"
		add_child(construction_audio)
	construction_audio.confirmed(intent, outcome, str(outcome.get("context", state.get("context", ""))))

func _crank_turn_refusal(machine: String) -> String:
	return "Fit a crafted hand crank to this %s's input before turning it." % machine

func _confirm_hand_crank_visual(action: Dictionary, outcome: Dictionary) -> void:
	if action.get("action") == "operate_hand_crank" and outcome.get("accepted", false) \
			and transmission_presenter != null:
		transmission_presenter.confirmed_hand_crank_pulse(str(action.get("entity", "")), outcome)

func issue(action: Dictionary) -> Dictionary:
	if explanation_open:
		return {"accepted": false, "reason": "explanation_open"}
	if startup_save_pending:
		_message("Finishing the saved worksite's opening. Wait a moment.")
		return {"accepted": false, "reason": "worksite_starting"}
	if actor_world != null:
		for actor in model.projection().actors:
			actor_world.ensure_actor(actor)
	request_sequence += 1
	var intent: Dictionary = action.duplicate(true)
	intent.merge({"context": model.projection().context, "client": client,
		"request": request_namespace + str(request_sequence)}, true)
	var outcome: Dictionary = model.command(intent)
	if actor_world != null:
		actor_world.sync_topology()
	if outcome.accepted:
		if action.action in ["place_gear", "place_shaft"]:
			selected = str(outcome.get("entity", ""))
		elif action.action == "stow_fabrication_hub" and selected == action.get("entity", ""):
			selected = ""
		elif action.action in ["remove", "remove_belt_span"] and selected == action.get("entity", ""):
			selected = ""
		_construction_feedback(intent, outcome)
		if action.action != "set_developer_conveniences":
			_message(_harvest_result_text(outcome) if action.action == "harvest_source" else {"place": "Placed. Parts stay with this worksite.",
			"craft_component": "Component crafted from carried material.",
			"field_craft": "Wooden component shaped with your multitool.",
			"craft_part": "Transmission kit made from carried timber and copper.",
			"place_component": "Component placed on the shared grid.",
			"attach_hand_crank": "Hand crank fitted to the input.",
			"detach_hand_crank": "The same hand crank returned to your inventory.",
			"operate_hand_crank": "Crank turning.",
			"turn_slide_crank": "The fitted crank advanced the slide.",
			"reclaim_component": "Component returned to your carried cargo.",
			"stow_fabrication_hub": "Pod workshop unbolted. Place it on clear ground or a foundation top.",
			"deploy_fabrication_hub": "Pod workshop installed at its new worksite.",
			"turn_hand_crank": "Collector cut a piece of copper into its receiver tray.",
			"feed_press": "One carried copper piece is now under the press head.",
			"turn_press_crank": "Plate formed at outlet. Collect it [P]." if int(outcome.get("formed_products", 0)) > 0 else "Press work advanced. Turn again to finish the plate.",
			"place_foundation": "Foundation placed. Its surface shares the machine grid.",
			"place_foundations": "Foundation area placed on the world grid.",
			"connect": "Material path connected.", "connect_drive": "Drive shaft connected.",
			"retrieve": "Plate collected.", "pickup_material": "Loose material collected.", "load_belt_slot": "Material placed on the belt.",
			"push_channel_sheet": "Sheet moved one workcell along the channel.",
			"push_channel_small": "Material moved to the next channel cell.",
			"remove": "Part returned to your carried kit.",
			"disconnect": "Material connection removed.",
			"disconnect_drive": "Drive shaft returned."}.get(action.action, "Done."))
	else:
		var refusal := _material_refusal_message(outcome, {"occupied": "That square is occupied.", "no_part": "That part is already placed.",
			"ports_not_adjacent": "Connect neighboring ports, following the arrow.",
			"invalid_belt_axis": "The belt's drive shaft runs across the belt, perpendicular to material travel.",
			"missing_entity": "Choose a placed machine at each end.",
			"already_connected": "Those ports are already connected.",
			"unavailable_output": "There is no finished copper plate to collect yet.",
			"out_of_reach": "Move closer to the target before building or interacting.",
			"crank_not_attached": "Fit a crafted hand crank to the input before turning it.",
			"input_port_occupied": "That input already holds a crank or another part.",
			"wrong_input_port": "Fit the crank at an exposed rotary input.",
			"attached_crank": "Remove the fitted crank before reclaiming its input.",
			"wrong_drive_shaft": "Use this press's fitted drive shaft.",
			"incomplete_assembly": "The press still needs the indicated component.",
			"receiver_full": "Pick up the copper in the collector receiver before cutting again.",
			"blocked_feed": "Choose a clear feed face.",
			"blocked_exit": "Choose a clear lower exit.",
			"input_full": "Recover or process the existing copper first.",
			"unavailable_input": "Carry copper or feed the selected press first.",
			"site_occupied": "Rock or scenery blocks that placement or press route.",
			"unsupported_bench": "Set the workbench on clear ground or a foundation top.",
			"not_holder": "Only the worker carrying the pod workshop can place it.",
			"already_stowed": "The pod workshop is already carried.",
			"actor_unready": "Your character is not ready yet. Wait a moment.",
			"actor_occupied": "A character is in that square. Move clear before placing the machine.",
			"powered": "Stop the drive before changing the machinery.",
			"not_stopped": "Stop the drive before changing the machinery.",
			"held_stock": "Retrieve the material before removing this machine.",
			"contains_stock": "Retrieve the material before removing this machine.",
			"not_at_stream": "Set the wheel in the water with its lower rim immersed and clear of the bed.",
			"not_at_seam": "Place the collector over the ore deposit beside the rock.",
			"no_shaft": "All carried shafts are in use."}.get(outcome.reason, "That action is unavailable here."), action.action)
		if action.action == "craft_component":
			refusal = {"unavailable_input": "Gather the timber or copper shown for this component.",
				"out_of_reach": "Move beside the selected workshop to craft this component."}.get(outcome.get("reason", ""), refusal)
		elif action.action == "field_craft":
			refusal = {"unavailable_input": "Gather the timber shown for this component.",
				"unavailable_recipe": "Metal components need a workshop."}.get(outcome.get("reason", ""), refusal)
		elif action.action == "craft_part":
			refusal = {"unavailable_input": "Gather the timber or copper shown for this transmission kit.",
				"out_of_reach": "Move beside the selected workshop to make a transmission kit.",
				"quantity_overflow": "Too many of this kit are already carried."}.get(outcome.get("reason", ""), refusal)
		elif action.action == "place_component" and outcome.get("reason", "") == "no_component":
			refusal = "Carry another %s." % str(action.get("component", "component")).replace("_", " ")
		elif action.action == "turn_hand_crank":
			refusal = {"crank_not_attached": "Fit a crafted hand crank to the collector input.",
				"incomplete_assembly": "Fit the collector's missing component before cutting ore.",
				"source_depleted": "This ore deposit is depleted.",
				"output_full": "Clear a loose material drop before cutting more ore.",
				"out_of_reach": "Move beside the collector mount to turn it."}.get(outcome.get("reason", ""), refusal)
		elif action.action == "deploy_fabrication_hub" and outcome.get("reason", "") == "unsupported_bench":
			refusal = "Set the pod workshop on clear ground or a foundation top."
		_message(refusal, true)
	_refresh()
	_confirm_hand_crank_visual(action, outcome)
	return outcome

func _harvest_result_text(outcome: Dictionary) -> String:
	var timber: int = outcome.get("moved_timber", 0)
	if timber > 0:
		return "Collected %d timber." % timber
	var raw: int = outcome.get("moved_raw", 0)
	if raw == 0:
		return "Cutting…"
	return "Collected %d copper %s." % [raw, "piece" if raw == 1 else "pieces"]

func _press_contact_refusal(entity: String) -> String:
	for assembly: Variant in state.get("guided_press_assemblies", []):
		if not assembly is Dictionary or assembly.get("anvil", "") != entity:
			continue
		match assembly.get("status", ""):
			"missing_ram": return "No working face contacts this support."
			"missing_guide": return "The working face has no guided stroke."
			"missing_shaft", "missing_cog": return "No rotary input reaches this working face."
	return "No compatible working face acts on this support."

func _material_refusal_message(outcome: Dictionary, fallback: String, action_name: String = "") -> String:
	var advice: String = {
		"first_plate_required": "Carry your first copper plate to unlock that part.",
		"unavailable_source": "That source is unavailable or depleted. Choose another tree or ore deposit.",
		"source_occluded": "Move around the obstacle before harvesting.",
		"unaligned_elevation": "Machines and wheels need a whole-tile height. Build a factory floor with Access steps off, or adjust the wheel's drive height.",
		"axles_already_touch": "These axle ends already touch; no shaft is needed.",
		"overlapping_shafts": "A shaft already occupies that length. Place the new segment end to end.",
		"foundation_required": "Build a foundation here first so the machine has a level surface.",
		"invalid_area": "Choose a rectangle of at most 256 foundation tiles.",
		"foundation_in_use": "Remove the machinery on this foundation before reclaiming it.",
		"site_occupied": "Rock or vegetation occupies this space. Choose a clear location.",
		"terrain_unavailable": "There is no confirmed building surface here."}.get(outcome.get("reason", ""), "")
	if not advice.is_empty():
		return advice
	if _native_transmission() and action_name == "load_belt_slot" \
			and outcome.get("reason") == "belt_cannot_carry" and not outcome.get("uncertain", false):
		return "This belt is too narrow for broad work. Carry it to the next machine."
	if _native_transmission() and action_name == "load_belt_slot" \
			and outcome.get("reason") == "belt_path_cannot_carry" and not outcome.get("uncertain", false):
		return "This belt transmits rotation but cannot carry items along this path."
	if _native_transmission() and action_name in ["push_channel_sheet", "push_channel_small"] \
			and not outcome.get("uncertain", false):
		var small_item: bool = action_name == "push_channel_small"
		var channel_advice: String = {
			"unavailable_input": "That item is no longer at the chosen square. Inspect the loose material again.",
			"partial_shear": "A partly cut sheet must be finished or recovered before moving.",
			"missing_channel": "Build a narrow or broad channel in the direction of travel before pushing this item." if small_item else "Build a broad channel in the direction of travel before pushing this copper sheet.",
			"blocked_channel": "The item needs a supported square and a clear receiver. Clear or extend the channel." if small_item else "The full copper sheet needs two supported squares and a clear swept route. Clear or extend the channel.",
			"invalid_channel_target": "Push toward the next channel cell along X or Z at the item's current height." if small_item else "Push one whole tile along X or Z at the sheet's current height."}.get(outcome.get("reason", ""), "")
		if not channel_advice.is_empty():
			return channel_advice
	if _native_transmission() and action_name == "stroke_broad_shear" and not outcome.get("uncertain", false):
		var shear_advice: String = {"output_full": "Clear the other anvil squares before cutting the copper sheet.",
			"shear_unpowered": "Drive the cutting head forward before cutting."}.get(outcome.get("reason", ""), "")
		if not shear_advice.is_empty():
			return shear_advice
	# Fixed-roster historical payloads may omit the helper or carry its older
	# API. Formatting must never add a resource requirement or change admission.
	if recovery_actions != null and recovery_actions.has_method("refusal_text"):
		var text: Variant = recovery_actions.call("refusal_text", outcome)
		if typeof(text) == TYPE_STRING and not text.is_empty():
			return text
	if _native_transmission() and action_name in ["feed_press", "refeed_press_work", "turn_press_crank"] \
			and outcome.get("reason") == "incomplete_assembly" \
			and not outcome.get("uncertain", false):
		return _press_contact_refusal(str(outcome.get("entity", "")))
	if _native_transmission() and outcome.get("reason") == "not_at_seam":
		return "Place the collector on the ore-colored ground beside the rock. A foundation there at factory floor height can support it."
	return fallback

func _process(delta: float) -> void:
	_sync_mouse_capture()
	_update_fps_counter(delta)
	_advance_held_crank(delta)
	if actor_world != null:
		actor_world.set_belt_step_seconds(STEP_SECONDS if auto_advance else 0.0)
	if auto_advance:
		elapsed += delta
		var advanced: Dictionary = {}
		while elapsed >= STEP_SECONDS:
			elapsed -= STEP_SECONDS
			advanced = model._advance_borrowed() if model is NativeWorldModel else model.advance()
		if advanced.has("context") and advanced.has("revision") and advanced.has("entities"):
			_refresh_from_projection(advanced)
		else:
			_refresh()
	_refresh_machine_preview()
	_refresh_component_preview()
	_refresh_placement_options()
	_refresh_water()
	_refresh_mechanical_audio()
	_animate_wheel(delta)
	if explanation_open:
		return
	_update_camera()
	_advance_arrival_reveal(delta)
	if _object_menu_open() and Vector2i(get_viewport().get_visible_rect().size) != object_menu_viewport_size:
		_fit_object_menu()
	_refresh_pointed_summary()

func _update_fps_counter(delta: float) -> void:
	if fps_label == null or not is_finite(delta) or delta <= 0.0:
		return
	fps_elapsed += delta
	if fps_elapsed >= 0.25:
		fps_elapsed = fmod(fps_elapsed, 0.25)
		fps_label.text = "FPS %d" % maxi(0, roundi(Engine.get_frames_per_second()))

func _water_time_seconds() -> float:
	return float(Time.get_ticks_msec()) * 0.001

func _refresh_water() -> void:
	if ProductionEnvironment.Surface != null:
		ProductionEnvironment.animate_water(_water_time_seconds())

func _refresh_mechanical_audio() -> void:
	var ready := _can_control_character() and _native_transmission() and camera != null
	if not ready:
		if mechanical_ambience != null:
			mechanical_ambience.silence()
		return
	if mechanical_ambience == null:
		mechanical_ambience = MechanicalAmbience.new()
		mechanical_ambience.name = "MechanicalAmbience"
		add_child(mechanical_ambience)
	mechanical_ambience.sync(state, client, true, camera.global_basis, model is NativeWorldModel)

func _animate_wheel(delta: float) -> void:
	if _native_transmission():
		if transmission_presenter == null:
			return
		transmission_presenter.advance_visual_motion(delta)
		wheel_batch_poses.clear()
		wheel_updated_rotors.clear()
		var cull_far_joinery := camera != null and camera.is_inside_tree() and not machine_batched_rotors.is_empty()
		var listener_position := camera.global_position if cull_far_joinery else Vector3.ZERO
		var frustum: Array = camera.get_frustum() if camera != null and camera.is_inside_tree() else []
		for cell in machine_rotor_cells:
			var bounds: AABB = cell.bounds
			var minimum := bounds.position
			var maximum := bounds.end
			var cell_outside := false
			for plane: Plane in frustum:
				# The nearest corner has the minimum plane distance. Culling it
				# excludes only cells whose every wheel is beyond the old margin.
				var nearest := Vector3(minimum.x if plane.normal.x >= 0.0 else maximum.x,
					minimum.y if plane.normal.y >= 0.0 else maximum.y,
					minimum.z if plane.normal.z >= 0.0 else maximum.z)
				if plane.distance_to(nearest) > WHEEL_MOTION_VISIBILITY_MARGIN:
					cell_outside = true
					break
			if cell_outside:
				continue
			for wheel in cell.wheels:
				# Keep nearby offscreen wheels live for their shadows. The confirmed
				# cosmetic phase still advances when its hidden pose is held.
				var outside_view := false
				for plane: Plane in frustum:
					if plane.distance_to(wheel.center) > WHEEL_MOTION_VISIBILITY_MARGIN:
						outside_view = true
						break
				if outside_view:
					continue
				var basis: Basis = wheel.base * Basis(Vector3.BACK, transmission_presenter.visual_angle(wheel.id))
				var rotor_id: int = wheel.rotor.get_instance_id()
				wheel_updated_rotors[rotor_id] = true
				# The full core is already in a MultiMesh. Beyond the last paddle
				# detail range, advance that instance without dirtying the many
				# hidden and distance-culled source nodes under its rotor.
				if cull_far_joinery and machine_batched_rotors.has(rotor_id) \
						and listener_position.distance_squared_to(wheel.center) > WHEEL_DETAIL_UPDATE_RADIUS * WHEEL_DETAIL_UPDATE_RADIUS:
					wheel_batch_poses[rotor_id] = Transform3D(basis, wheel.rotor.position)
				else:
					wheel.rotor.basis = basis
		_animate_machine_bodies(delta)
		_update_machine_dynamic_batches(true)
		return
	# Historical scripted presentation remains separate. Native cosmetic
	# angles above are neither a simulation clock nor saved/contact phase.
	if wheel_rotor != null and state.get("powered", false) and not state.get("options", {}).get("native", false):
		wheel_rotor.rotation.z += delta * 0.8

func _remember_machine_motion(node: Node3D, kind: String, pose: Transform3D,
		rows: Array[Dictionary]) -> void:
	if node is MeshInstance3D:
		var part_name := str(node.name)
		var role := ""
		if kind == "collector" and (part_name in ["CutterDrum", "CutterHub"] or node.get_meta("detail_role", "") == "CutterFlute"):
			role = "cutter"
		elif kind == "processor" and part_name in ["ToolHead", "Piston"]:
			role = "head" if part_name == "ToolHead" else "rod"
		if not role.is_empty():
			rows.append({"node": node, "role": role, "rest": pose,
				"parent_inverse": (pose * node.transform.affine_inverse()).affine_inverse()})
	for child in node.get_children():
		if child is Node3D:
			_remember_machine_motion(child, kind, pose * child.transform, rows)

func _animate_machine_bodies(delta: float) -> void:
	if not _can_present_confirmed_motion() or not is_finite(delta) or delta <= 0 or machine_root == null or transmission_presenter == null:
		return
	_sync_machine_body_context()
	for anchor in machine_motion_anchors:
		var kind: String = anchor.get_meta("machine_kind", "")
		var id: String = anchor.get_meta("machine_entity", "")
		var rows: Array = anchor.get_meta("motion_meshes", [])
		if kind == "collector":
			var angle: float = transmission_presenter.visual_angle(id)
			if angle == float(anchor.get_meta("cutter_angle", NAN)):
				continue
			_apply_cutter_pose(anchor, rows, angle)
		elif kind == "belt":
			_apply_conveyor_motion(anchor, transmission_presenter.visual_rotation(id))
		elif kind == "processor":
			var target: Variant = _observed_press_target()
			var generation: Variant = state.get("entities", {}).get(id, {}).get("generation")
			if target == null or typeof(generation) != TYPE_INT or generation < 1:
				continue
			# A pose follows observed held work, including blocked READY. It does
			# not predict a cycle, release a plate or advance remaining ticks.
			if not machine_press_poses.has(id):
				machine_press_poses[id] = {"generation": generation, "travel": target}
				_apply_press_pose(rows, target)
				continue
			var previous: float = machine_press_poses[id].travel
			var travel: float = move_toward(previous, float(target), minf(delta, 0.1) * 0.12)
			if travel == previous:
				continue
			_apply_press_pose(rows, travel)
			machine_press_poses[id].travel = travel

func _apply_conveyor_motion(anchor: Node3D, rotation: float) -> void:
	var loop: MeshInstance3D
	if anchor.has_meta("conveyor_loop"):
		loop = anchor.get_meta("conveyor_loop") as MeshInstance3D
	if not is_instance_valid(loop):
		loop = anchor.find_child("ConveyorLoop", true, false) as MeshInstance3D
		anchor.set_meta("conveyor_loop", loop)
	if loop == null or not loop.material_override is StandardMaterial3D:
		return
	var length_value := 4.0 * ProductionConveyorArt.HALF_SPAN + TAU * ProductionConveyorArt.RADIUS
	var repeats := maxi(1, roundi(length_value / ProductionConveyorArt.SOURCE_METRES))
	# The top profile runs toward +X as UV increases. Positive +Z shaft
	# rotation carries the top toward -X, so the texture offset increases.
	var direction := -1.0 if anchor.get_meta("material_rotated", false) else 1.0
	var offset := fposmod(direction * rotation * ProductionConveyorArt.RADIUS * repeats / length_value, 1.0)
	var slot: Dictionary = machine_conveyor_batch_slots.get(loop.get_instance_id(), {})
	if not slot.is_empty():
		# The visible batch reads custom data; the source material is hidden.
		slot.mesh.set_instance_custom_data(slot.index, Color(offset, 0, 0))
		return
	loop.material_override.uv1_offset = Vector3(offset, 0, 0)

func _sync_machine_body_context() -> void:
	var context: Variant = state.get("context")
	if typeof(context) != TYPE_STRING or context != machine_body_context:
		machine_press_poses.clear()
		machine_body_context = context if typeof(context) == TYPE_STRING else ""
	for id in machine_press_poses.keys():
		var entity: Dictionary = state.get("entities", {}).get(id, {})
		if entity.get("kind") != "processor" or typeof(entity.get("generation")) != TYPE_INT or entity.get("generation") != machine_press_poses[id].generation:
			machine_press_poses.erase(id)

func _observed_press_target() -> Variant:
	var stock: Variant = state.get("stock")
	var held: Variant = stock.get("held") if stock is Dictionary else null
	var remaining: Variant = state.get("remaining")
	if typeof(held) != TYPE_INT or held < 0 or typeof(remaining) != TYPE_INT or remaining < 0:
		return null
	# The fitted billet boss reaches y = 0.732; the resting head's lower face
	# is at y = 0.755. Keep this pose clear of the unchanged workpiece.
	return 0.015 if held > 0 else 0.0

func _apply_cutter_pose(anchor: Node3D, rows: Array, angle: float) -> void:
	var spin := _cutter_spin(anchor, angle)
	var slot: Dictionary = machine_cutter_batch_slots.get(anchor.get_instance_id(), {})
	if not slot.is_empty():
		slot.mesh.set_instance_transform(slot.index, anchor.transform * spin)
		anchor.set_meta("cutter_angle", angle)
		return
	for row in rows:
		if is_instance_valid(row.node) and row.role == "cutter":
			row.node.transform = row.parent_inverse * spin * row.rest
	anchor.set_meta("cutter_angle", angle)

func _cutter_spin(anchor: Node3D, angle: float) -> Transform3D:
	var pivot := Vector3(-0.22, 1.1, -0.19)
	var axle := Vector3.BACK
	if anchor.get_meta("material_rotated", false):
		var turn := Basis(Vector3.UP, -PI / 2.0)
		pivot = turn * pivot
		axle = turn * axle
	var spin := Transform3D(Basis(axle, angle), Vector3.ZERO)
	spin.origin = pivot - spin.basis * pivot
	return spin

func _apply_press_pose(rows: Array, travel: float) -> void:
	for row in rows:
		if not is_instance_valid(row.node):
			continue
		var pose: Transform3D = row.rest
		if row.role == "head":
			pose.origin.y -= travel
		elif row.role == "rod":
			pose.origin.y -= travel / 2.0
			pose.basis = pose.basis.scaled(Vector3(1, 1 + travel / 0.45, 1))
		row.node.transform = row.parent_inverse * pose

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_stop_held_crank()
		_release_character_controls()
		_release_mouse_capture()

func _exit_tree() -> void:
	_release_mouse_capture()

func _mouse_capture_allowed(window_focused: bool, popup_open: bool) -> bool:
	return distance <= 0.0 and window_focused and not popup_open \
		and _can_control_character() and (pause_exit_confirmation == null or not pause_exit_confirmation.visible)

func _wants_mouse_capture() -> bool:
	return _mouse_capture_allowed(DisplayServer.window_is_focused(),
		DisplayServer.window_get_active_popup() != DisplayServer.INVALID_WINDOW_ID)

func _release_mouse_capture() -> void:
	if not mouse_capture_owned:
		return
	mouse_capture_owned = false
	mouse_capture_skip_motion = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_mouse_menu_visibility_changed() -> void:
	if not _can_control_character():
		_release_character_controls()
		_stop_held_crank()
	_sync_mouse_capture()

func _sync_mouse_capture() -> void:
	if not _wants_mouse_capture():
		if mouse_capture_owned and (not DisplayServer.window_is_focused() or not _can_control_character()):
			_release_character_controls()
			_stop_held_crank()
		_release_mouse_capture()
		return
	if not mouse_capture_owned or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_capture_owned = true
		# Capture can warp the pointer. Ignore that first relative event.
		mouse_capture_skip_motion = true

func _rotate_camera_from_mouse(relative: Vector2) -> void:
	orbit_yaw -= relative.x * 0.007
	orbit_pitch = clampf(orbit_pitch + relative.y * 0.005,
		-1.25 if distance == 0.0 else 0.35, 1.25)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_capture_owned and _wants_mouse_capture():
		if mouse_capture_skip_motion:
			mouse_capture_skip_motion = false
		else:
			_rotate_camera_from_mouse(event.relative)
			_update_camera()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_E and not event.pressed:
		_stop_held_crank()
	if arrival_reveal_active:
		if event is InputEventKey and event.pressed and not event.echo \
				and event.keycode in [KEY_SPACE, KEY_ESCAPE]:
			_finish_arrival_reveal(true)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_F3:
		if event.pressed and not event.echo and _can_control_character():
			issue({"action": "set_developer_conveniences", "enabled":
				not state.get("options", {}).get("developer_conveniences", false)})
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_ALT and not event.pressed \
			and component_nudge_active:
		component_nudge_active = false
		component_nudge_center.clear()
		_update_cursor()
		get_viewport().set_input_as_handled()
		return
	if _object_menu_open():
		if event is InputEventKey and event.keycode == KEY_T and not event.pressed \
				and arrival_assembly_controls != null:
			arrival_assembly_controls.stop_turn_hold("key")
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			var used := false
			if event.keycode in [KEY_ESCAPE, KEY_E]:
				object_menu.hide()
				used = true
			elif event.keycode == KEY_DELETE:
				used = _activate_button(arrival_assembly_controls.reclaim_button) \
					if arrival_assembly_controls != null and state.get("placed_components", {}).has(selected) \
					else _activate_button(remove_button)
			elif event.ctrl_pressed and event.keycode == KEY_R:
				used = _activate_button(retrieve_button)
			elif event.ctrl_pressed and event.keycode == KEY_M:
				used = _open_action_menu(recovery_actions.action_button if recovery_actions != null else null)
			elif event.ctrl_pressed and event.keycode == KEY_L:
				used = _open_action_menu(loose_material_controls)
			elif event.keycode == KEY_F5 and not startup_save_pending:
				_save_worksite()
				used = true
			elif event.keycode == KEY_F9:
				_load_worksite()
				used = true
			elif not event.ctrl_pressed and arrival_assembly_controls != null:
				var actions = arrival_assembly_controls
				match event.keycode:
					KEY_P: used = actions.inventory_shortcut(KEY_P) or _activate_button(actions.pickup_button)
					KEY_F: used = actions.inventory_shortcut(KEY_F) or _activate_button(actions.feed_button)
					KEY_N: used = _open_action_menu(actions.broad_refeed_button)
					KEY_T: used = actions.press_turn_key()
					KEY_X: used = _activate_button(actions.shear_button) or _activate_button(actions.collector_cut_button)
					KEY_R: used = actions.inventory_shortcut(KEY_R) or _activate_button(actions.refeed_work_button)
					KEY_U: used = actions.inventory_shortcut(KEY_U) or _activate_button(actions.recover_work_button)
					KEY_V: used = actions.cycle_slide_port()
					KEY_G: used = actions.cycle_feed_route()
					KEY_S: used = _open_action_menu(actions.sheet_button)
			if used:
				get_viewport().set_input_as_handled()
		return
	if pause_exit_confirmation != null and pause_exit_confirmation.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			pause_exit_confirmation.hide()
			get_viewport().set_input_as_handled()
		return
	if _pause_menu_open():
		if event is InputEventKey and event.pressed and not event.echo:
			var used := true
			match event.keycode:
				KEY_ESCAPE: pause_menu.hide()
				KEY_F5:
					if not startup_save_pending:
						_save_worksite()
				KEY_F9: _load_worksite()
				KEY_Q: pause_exit_confirmation.popup_centered()
				_: used = false
			if used:
				get_viewport().set_input_as_handled()
		return
	if manager_log_open:
		if event is InputEventKey:
			if event.pressed and not event.echo and event.keycode in [KEY_J, KEY_ESCAPE]:
				_toggle_manager_log()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J \
			and _native_transmission() and not explanation_open and not _catalog_open():
		_toggle_manager_log()
		get_viewport().set_input_as_handled()
		return
	if explanation_open:
		if event is InputEventKey:
			if event.pressed and not event.echo:
				if event.keycode in [KEY_H, KEY_ESCAPE]:
					_toggle_explanation()
			get_viewport().set_input_as_handled()
		return
	if _catalog_open():
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo:
		# PopupPanel can hide itself before this scene sees the same Escape.
		if object_menu_closed_frame == Engine.get_process_frames():
			get_viewport().set_input_as_handled()
			return
		if _cancel_active_construction():
			consumed_shortcut_keys[KEY_ESCAPE] = true
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_ALT and mode == "component":
		if event.pressed and not component_nudge_active:
			component_nudge_center = _component_pointed_center()
			component_nudge_active = true
		elif not event.pressed:
			component_nudge_active = false
			component_nudge_center.clear()
		_update_cursor()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and not event.pressed and consumed_shortcut_keys.has(event.keycode):
		consumed_shortcut_keys.erase(event.keycode)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var handled := false
		if event.alt_pressed and mode == "component" and event.keycode in [KEY_LEFT, KEY_RIGHT,
				KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN]:
			if not component_nudge_active:
				component_nudge_center = _component_pointed_center()
				component_nudge_active = true
			var axis := 1 if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN] else \
				0 if event.keycode in [KEY_LEFT, KEY_RIGHT] else 2
			var step := 1 if event.keycode in [KEY_RIGHT, KEY_UP, KEY_PAGEUP] else -1
			component_nudge_center[axis] = clampi(int(component_nudge_center[axis]) + step,
				-Geometry.GRID_COORDINATE_LIMIT, Geometry.GRID_COORDINATE_LIMIT)
			_update_cursor()
			handled = true
		elif event.ctrl_pressed:
			match event.keycode:
				KEY_ENTER, KEY_KP_ENTER: handled = _activate_button(confirm_button)
				KEY_R: handled = _activate_button(retrieve_button)
				KEY_M: handled = _open_action_menu(recovery_actions.action_button if recovery_actions != null else null)
				KEY_L: handled = _open_action_menu(loose_material_controls)
				KEY_HOME:
					if transmission_controls != null and transmission_controls.is_visible_in_tree():
						transmission_controls._height_selected(2)
						handled = true
		elif event.alt_pressed and transmission_controls != null and _native_transmission() and _can_choose_tool():
			var transmission_tools := {KEY_1: "gear", KEY_2: "drive", KEY_3: "belt",
				KEY_4: "gearbox", KEY_5: "vertical_gearbox", KEY_6: "chain_drive"}
			if transmission_tools.has(event.keycode):
				var choice: String = transmission_tools[event.keycode]
				var entry := building_hotbar.catalog_buttons.get(choice) as Button
				if entry != null and not entry.disabled:
					_select_tool(choice)
					handled = true
		elif not event.alt_pressed:
			match event.keycode:
				KEY_DELETE: handled = _activate_button(remove_button)
				KEY_T: handled = _open_action_menu(transmission_controls)
				KEY_X:
					if event.shift_pressed and transmission_controls != null and transmission_controls.is_visible_in_tree():
						var axes := ["x", "y", "z"]
						var next := (axes.find(transmission_controls.selected_link_axis) + 1) % 3
						if axes[next] == transmission_controls.selected_axis:
							next = (next + 1) % 3
						transmission_controls._link_axis_selected(next)
						handled = true
					elif placement_options_axis.is_visible_in_tree():
						handled = _activate_button(placement_options_axis)
				KEY_Z:
					if foundation_steps_toggle.is_visible_in_tree() and not foundation_steps_toggle.disabled:
						foundation_steps_toggle.button_pressed = not foundation_steps_toggle.button_pressed
						_set_foundation_steps(foundation_steps_toggle.button_pressed)
						handled = true
				KEY_V:
					if mode == "component" and arrival_assembly_controls != null \
							and arrival_assembly_controls.selected_name() in ["anvil", "ram_face"]:
						_toggle_component_footprint()
						handled = true
					elif foundation_area_toggle.is_visible_in_tree() and not foundation_area_toggle.disabled:
						foundation_area_toggle.button_pressed = not foundation_area_toggle.button_pressed
						foundation_area_mode = foundation_area_toggle.button_pressed
						foundation_area_started = false
						handled = true
				KEY_K:
					if transmission_controls != null and transmission_controls.is_visible_in_tree() and mode == "gear":
						transmission_controls._size_selected(1 if transmission_controls.gear_teeth == 2 else 0)
						handled = true
				KEY_PAGEUP, KEY_PAGEDOWN:
					if event.shift_pressed and wheel_size_controls.is_visible_in_tree():
						handled = _activate_button(wheel_size_controls.get_child(2 if event.keycode == KEY_PAGEUP else 0) as Button)
					elif event.shift_pressed and transmission_controls != null and transmission_controls.is_visible_in_tree():
						transmission_controls._height_selected(1 if event.keycode == KEY_PAGEUP else 0)
						handled = true
		if handled:
			consumed_shortcut_keys[event.keycode] = true
			get_viewport().set_input_as_handled()
			return
	# Consume both edges of global shortcuts so a
	# previously focused GUI button cannot also activate on the release.
	if event is InputEventKey and event.keycode in [KEY_F5, KEY_F9]:
		if event.pressed and not event.echo and not explanation_open:
			match event.keycode:
				KEY_F5:
					if not startup_save_pending:
						_save_worksite()
				KEY_F9: _load_worksite()
		get_viewport().set_input_as_handled()

func _activate_button(button: Button) -> bool:
	if button == null or not button.is_visible_in_tree() or button.disabled:
		return false
	button.pressed.emit()
	return true

func _open_action_menu(button: MenuButton) -> bool:
	if button == null or not button.is_visible_in_tree() or button.disabled:
		return false
	button.show_popup()
	return true

func _unhandled_input(event: InputEvent) -> void:
	if explanation_open or _object_menu_open() or _pause_menu_open():
		return
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_rotate_camera_from_mouse(event.relative)
		elif not component_nudge_active:
			hover_cell = _screen_cell(event.position)
			_update_cursor()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(0, distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(24, distance + 1)
			if distance > 0.0:
				orbit_pitch = maxf(orbit_pitch, 0.35)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var entity_id := _screen_entity(event.position)
			if mode == "deconstruct" or not _transmission_click(_transmission_center(event.position), entity_id):
				_world_click(_screen_cell(event.position), entity_id)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_8:
			building_hotbar.select_slot(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_B: building_hotbar.open_catalog()
			KEY_PAGEUP:
				if mode != "component": _adjust_foundation_level(1)
			KEY_PAGEDOWN:
				if mode != "component": _adjust_foundation_level(-1)
			KEY_F: _select_tool("deconstruct" if _native_transmission() else "flow")
			KEY_C:
				if _native_transmission():
					_select_tool("flow")
			KEY_G: _select_tool("drive")
			KEY_E:
				if _native_transmission():
					_interact_pointed()
			KEY_R:
				if _native_transmission() and mode in ["collector", "processor", "wheel"]:
					_rotate_building()
				elif _native_transmission() and mode != "inspect":
					_cycle_placement_axis()
				else:
					_retrieve()
			KEY_H: _toggle_explanation()
			KEY_HOME: distance = 14.0
	_update_camera()

func _select_tool(tool: String) -> void:
	if explanation_open:
		return
	component_nudge_active = false
	component_nudge_center.clear()
	if transmission_controls != null:
		transmission_controls.cancel()
	mode = tool
	foundation_area_started = false
	pending_link = ""
	transmission_preview_point.clear()
	if _native_transmission() and transmission_controls != null:
		if tool == "wheel" and transmission_controls.selected_axis == "y":
			transmission_controls._axis_selected(0)
		if tool in ["gear", "drive", "belt", "gearbox", "vertical_gearbox", "chain_drive"]:
			transmission_controls.choose_tool({"gear": "gear", "drive": "place_shaft", "belt": "belt_span",
				"gearbox": "gearbox", "vertical_gearbox": "vertical_gearbox", "chain_drive": "chain_drive"}[tool])
	_update_cursor()
	_refresh_ui()
	var instructions := {"flow": "Click the upstream machine, then its neighbor toward the brass arrow.",
		"component": "Point at a part face to snap. Hold Alt and use arrows or Page Up / Down to nudge one quarter-grid step; click to place.",
		"pod_workshop": "Click a clear full tile to reinstall the carried pod workshop. It can sit on ground or a foundation top.",
		"drive": "Click two neighboring machines to connect a drive shaft.",
		"inspect": "E opens a pointed machine; hold E to turn a fitted crank." if _native_transmission() else "Click a machine to inspect it or collect its finished work.",
		"deconstruct": "Point at a built part and click to dismantle it. Escape leaves dismantle mode.",
		"collector": "Place the collector on the ore deposit.",
		"wheel": "Place the waterwheel in the flowing stream. Set its height to align its axle with your shafts."}
	if _native_transmission():
		instructions["collector"] = "Place the collector on the ore-colored ground beside the rock, or on a foundation there at factory floor height."
		instructions["belt"] = "Choose two parallel shafts within reach. The belt runs across their axle, not along it."
		instructions["flow"] = "Choose the upstream machine, then its neighbor at the material outlet."
		instructions["drive"] = "Point at a floor to match its height, a part face to snap beside it, or a belt to add a pulley. Set the shaft axis in its menu."
		instructions["gear"] = "Point at a floor to match its height or a part face to snap beside it. Set the cogwheel axis in its menu."
		instructions["foundation"] = "Place a foundation at the displayed world height. Page Up / Page Down move one foundation thickness so stacked blocks touch; Access steps enables smaller walking steps. Machines need whole-tile factory floors. Area chooses two corners; Esc cancels."
		if tool == "component" and arrival_assembly_controls != null:
			var component_kind: String = arrival_assembly_controls.selected_name()
			if component_kind == "flat_head":
				instructions["component"] = "Aim at the anvil to show the head at press height. Click to fit it; the slide goes above."
			elif component_kind in ["wooden_slide", "copper_slide"]:
				instructions["component"] = "Aim at the flat head to show the slide above it. Click to fit the amber ghost; red means blocked."
	_message(instructions.get(tool,
		"Place %s on an empty grid square." % NAMES.get(tool, tool)))

func _cancel_active_construction() -> bool:
	if mode == "inspect" and pending_link.is_empty() and not foundation_area_started \
			and component_area_anchor.is_empty() and not component_nudge_active \
			and transmission_preview_point.is_empty() \
			and (transmission_controls == null or transmission_controls.active_tool.is_empty()):
		return false
	component_area_anchor.clear()
	component_area_kind = ""
	component_preview_snap = ""
	component_preview_blocked = false
	component_preview_pose_key = ""
	component_preview_kind = ""
	foundation_area_start = Vector2i.ZERO
	_select_tool("inspect")
	return true

func _world_click(cell: Vector2i, entity_id: String = "") -> void:
	if explanation_open:
		return
	if mode == "deconstruct":
		var crank_id := _pointed_crank()
		if not crank_id.is_empty():
			issue({"action": "detach_hand_crank", "entity": crank_id})
			return
		var target := entity_id if _contains_target(state, entity_id) else ""
		if target.is_empty():
			_message("Point at a built part to dismantle it.", true)
			return
		var removal := "stow_fabrication_hub" if target == state.get("fabrication_hub", {}).get("id", "") else \
			"reclaim_component" if state.get("placed_components", {}).has(target) else \
			"remove_belt_span" if state.get("belt_spans", {}).has(target) else "remove"
		var outcome := issue({"action": removal, "entity": target})
		if outcome.accepted and selected == target:
			selected = ""
		_refresh_ui()
		return
	if mode == "pod_workshop" and _native_transmission():
		var hub: Dictionary = state.get("fabrication_hub", {})
		if hub.get("holder") != client or not _build_cell_allowed(cell):
			return
		var center := [cell.x * Geometry.HEIGHT_DENOMINATOR, _construction_level(cell),
			cell.y * Geometry.HEIGHT_DENOMINATOR]
		var outcome := issue({"action": "deploy_fabrication_hub", "entity": hub.id, "center": center})
		if outcome.accepted:
			selected = str(hub.id)
			_select_tool("inspect")
		return
	if mode == "component" and _native_transmission():
		if arrival_assembly_controls == null:
			return
		var center := _component_place_center(cell, entity_id)
		var component_name: String = arrival_assembly_controls.selected_name()
		if component_name == "hand_crank":
			var input_id := _rotary_at_input_port(center)
			if input_id.is_empty():
				_message("Point at a visible rotary input to fit the crank.", true)
				return
			var carried_id := ""
			for item_id: String in state.get("crank_items", {}):
				if state.crank_items[item_id].get("holder", "") == client:
					carried_id = item_id
					break
			if carried_id.is_empty():
				_message("Craft and carry a hand crank before fitting an input.", true)
				return
			var attach_wire := {"action": "attach_hand_crank", "entity": input_id,
				"crank": carried_id, "port": center}
			var crank_face := _crank_face_for_input(input_id, center)
			if crank_face.size() == 3:
				attach_wire["face"] = crank_face
			var attached := issue(attach_wire)
			if attached.accepted:
				selected = input_id
			_refresh_ui()
			return
		var area_origin := _component_area_origin(component_name, center)
		var centers := _component_footprint_centers(component_name, area_origin)
		if not _component_center_allowed(center):
			return
		if centers.size() == 4 and not centers.has(center):
			_message("Aim at one of the four highlighted cells.", true)
			return
		if centers.size() == 4 and _component_area_has_part(component_name, center):
			_message("That part is already placed.", true)
			return
		var selected_anvil: String = arrival_assembly_controls.press_anvil_for(selected)
		var outcome := issue({"action": "place_component",
			"component": component_name, "center": center})
		if outcome.accepted or outcome.get("queued", false):
			if centers.size() == 4:
				component_area_anchor = area_origin.duplicate()
				component_area_kind = component_name
		if outcome.accepted:
			selected = selected_anvil if component_name != "anvil" and not selected_anvil.is_empty() \
				else str(outcome.get("entity", ""))
		_refresh_ui()
		return
	if _native_transmission():
		var height: int = transmission_controls.gear_height if transmission_controls != null else 0
		if _transmission_click([cell.x * 4, height, cell.y * 4], entity_id):
			return
		if mode == "belt":
			_message("Select the Belt tool and choose two parallel shafts.", true)
			return
		if mode == "inspect":
			if state.get("belt_spans", {}).has(entity_id):
				selected = entity_id
				_refresh_ui()
			return
	if mode != "foundation" and state.entities.has(entity_id):
		var actual: Array = state.entities[entity_id].cell
		cell = Vector2i(actual[0], actual[1])
	if not _build_cell_allowed(cell):
		return
	if mode == "inspect":
		selected = entity_id if not entity_id.is_empty() else _entity_at_cell(cell)
		_refresh_ui()
	elif mode in ["flow", "drive"]:
		var target := entity_id if not entity_id.is_empty() else _entity_at_cell(cell)
		if target.is_empty():
			_message("Choose a placed machine.", true)
			return
		selected = target
		if pending_link.is_empty():
			pending_link = target
			_message("Now choose the neighboring machine.")
		else:
			issue({"action": "connect" if mode == "flow" else "connect_drive", "from": pending_link, "to": target})
			pending_link = ""
	else:
		hover_cell = cell
		var action := {"action": "place", "kind": mode, "cell": [cell.x, cell.y]}
		if _native_transmission() and mode == "foundation":
			if foundation_area_mode:
				if not foundation_area_started:
					foundation_area_start = cell
					foundation_area_started = true
					_message("First corner chosen. Choose the opposite corner at this height; Esc cancels. The whole area uses carried parts.")
					return
				action = {"action": "place_foundations", "cell": [foundation_area_start.x, foundation_area_start.y], "end_cell": [cell.x, cell.y], "level": foundation_level}
				foundation_area_started = false
			else:
				action = {"action": "place_foundation", "cell": [cell.x, cell.y], "level": _construction_level(cell)}
		elif _native_transmission():
			action["level"] = _construction_level(cell)
			if mode == "wheel":
				action["tiles"] = wheel_tiles
		if _native_transmission() and transmission_controls != null:
			# Dot assignment creates a StringName key; the native wire deliberately
			# accepts only exact String dictionary keys, without coercion.
			if mode != "foundation":
				action["axis"] = ["x", "y", "z"][_preview_axis()]
		if _native_transmission() and mode in ["collector", "processor"]:
			action["rotation"] = building_rotation
		var outcome := issue(action)
		if outcome.accepted:
			selected = outcome.entity
	_refresh_ui()
	_update_cursor()

func _retrieve() -> void:
	var target := selected
	if target.is_empty() or not state.entities.has(target) or state.entities[target].kind != "processor":
		_message("Point at the press and press E, then collect its finished copper plate.", true)
		return
	issue({"action": "retrieve", "amount": 1, "entity": target})

func _pointed_screen_position() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5 if distance <= 0.0 else get_viewport().get_mouse_position()

func _pointed_crank() -> String:
	return _crank_at_screen(_pointed_screen_position())

func _crank_at_screen(screen: Vector2) -> String:
	var hit := _screen_pick(screen)
	if hit.is_empty():
		return ""
	var id: String = str(hit.collider.get_meta("crank_entity", ""))
	var item: Dictionary = state.get("crank_items", {}).get(id, {})
	return id if not item.is_empty() and not str(item.get("attached_to", "")).is_empty() else ""

func _stop_held_crank() -> void:
	held_crank = ""
	held_crank_seconds = 0.0
	held_crank_context = ""
	held_crank_request = ""

func _settle_held_crank_request(request: String, accepted: bool) -> void:
	if request != held_crank_request:
		return
	if accepted:
		held_crank_request = ""
	else:
		_stop_held_crank()

func _advance_held_crank(delta: float) -> void:
	if held_crank.is_empty():
		return
	if not _crank_hold_allowed() or str(state.get("context", "")) != held_crank_context \
			or mode != "inspect" or _pointed_crank() != held_crank:
		_stop_held_crank()
		return
	held_crank_seconds = minf(STEP_SECONDS, held_crank_seconds + delta)
	if not held_crank_request.is_empty() or held_crank_seconds < STEP_SECONDS:
		return
	held_crank_seconds = 0.0
	var outcome := issue({"action": "operate_hand_crank", "entity": held_crank})
	if outcome.get("queued", false) and not str(outcome.get("request", "")).is_empty():
		held_crank_request = str(outcome.request)
	elif not outcome.get("accepted", false):
		_stop_held_crank()

func _crank_hold_allowed() -> bool:
	return DisplayServer.window_is_focused() and _can_control_character()

func _hand_source(id: String) -> Dictionary:
	var source: Variant = state.get("hand_sources", {}).get(id)
	if not source is Dictionary or source.get("kind") not in ["tree", "ore_deposit"] \
			or not Geometry.valid_position(source.get("position")) or typeof(source.get("remaining")) != TYPE_INT \
			or source.remaining < 0:
		return {}
	if source.has("contact_bounds"):
		var bounds: Variant = source.contact_bounds
		if not bounds is Array or bounds.size() != 2 or not Geometry.valid_position(bounds[0]) \
				or not Geometry.valid_position(bounds[1]):
			return {}
		for axis in range(3):
			if float(bounds[0][axis]) >= float(bounds[1][axis]):
				return {}
	return source

func _hand_source_in_reach(source: Dictionary) -> bool:
	var actor: Dictionary = state.get("actors", {}).get(client, {})
	var position: Variant = actor.get("position")
	var radius: Variant = actor.get("capabilities", {}).get("harvest_reach")
	if not Geometry.valid_position(position) or not (radius is float or radius is int) or radius <= 0:
		return false
	var target: Array = source.position.duplicate()
	if source.has("contact_bounds"):
		var bounds: Array = source.contact_bounds
		for axis in range(3):
			target[axis] = clampf(float(position[axis]), float(bounds[0][axis]), float(bounds[1][axis]))
	var distance_squared := 0.0
	for axis in range(3):
		var difference: float = float(position[axis]) - float(target[axis])
		distance_squared += difference * difference
	return distance_squared <= float(radius) * float(radius)

func _hand_source_clear(id: String) -> bool:
	var actor: Dictionary = state.get("actors", {}).get(client, {})
	return actor.get("harvest_clear", {}).get(id, true) == true

func _prepare_hand_tree_assets() -> bool:
	if not hand_tree_assets.is_empty():
		return true
	var loaded := ProductionEnvironment.read_pine()
	if loaded.status != "ready":
		push_error("Harvestable trees require the qualified pine mesh.")
		return false
	var mesh: ArrayMesh = loaded.mesh
	var bark_surface := -1
	for surface in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			bark_surface = surface
			break
	if bark_surface < 0:
		push_error("The harvestable pine has no opaque bark surface.")
		return false
	var arrays := mesh.surface_get_arrays(bark_surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base_height := mesh.get_aabb().position.y
	var root_min := Vector3(INF, base_height, INF)
	var root_max := Vector3(-INF, base_height, -INF)
	for point in vertices:
		if point.y <= base_height + 0.025:
			root_min = root_min.min(point)
			root_max = root_max.max(point)
	if not root_min.is_finite() or not root_max.is_finite():
		push_error("The harvestable pine has no grounded bark root.")
		return false
	var root := Vector3((root_min.x + root_max.x) * 0.5, base_height, (root_min.z + root_max.z) * 0.5)
	var radius := maxf(root_max.x - root_min.x, root_max.z - root_min.z) * 0.5
	var faces := PackedVector3Array()
	for index in indices:
		faces.append(vertices[index] - root)
	var trunk := ConcavePolygonShape3D.new()
	trunk.backface_collision = true
	trunk.set_faces(faces)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("68503b")
	wood.roughness = 1.0
	wood.metallic_specular = 0.0
	wood.cull_mode = BaseMaterial3D.CULL_DISABLED
	var base := _hand_tree_stump(arrays, root, mesh.surface_get_material(bark_surface), wood)
	if base.is_empty():
		return false
	# The scar follows every actual bark face. A single tiny quad could face
	# away from the worker after the tree's deterministic rotation.
	var scar_arrays: Array = arrays.duplicate(true)
	var scar_vertices := PackedVector3Array()
	for point in vertices:
		scar_vertices.append(point - root)
	scar_arrays[Mesh.ARRAY_VERTEX] = scar_vertices
	var scar := ArrayMesh.new()
	scar.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, scar_arrays)
	var scar_shader := Shader.new()
	scar_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float cut_fraction : hint_range(0.0, 1.0) = 0.125;
varying vec3 bark;
void vertex() {
	bark = VERTEX;
	VERTEX += NORMAL * 0.0006;
}
void fragment() {
	float angle = atan(bark.z, bark.x);
	float rough_edge = sin(angle * 5.0 + 2.0) * 0.002 + sin(angle * 11.0) * 0.001;
	float half_height = mix(0.006, 0.026, cut_fraction) * (0.8 + 0.2 * sin(angle * 3.0));
	float edge = abs(bark.y - 0.18 - rough_edge) / half_height;
	if (edge > 1.0) { discard; }
	float grain = 0.9 + 0.1 * sin(bark.x * 2200.0 + bark.z * 1700.0 + sin(bark.y * 75.0));
	ALBEDO = mix(vec3(0.43, 0.30, 0.19) * grain, vec3(0.23, 0.14, 0.07), smoothstep(0.7, 1.0, edge));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
	var scar_material := ShaderMaterial.new()
	scar_material.shader = scar_shader
	scar.surface_set_material(0, scar_material)
	var stump_shape := CylinderShape3D.new()
	stump_shape.height = base.height
	stump_shape.radius = radius
	hand_tree_assets = {"mesh": mesh, "root": root, "trunk": trunk, "stump": base.mesh,
		"stump_shape": stump_shape, "stump_height": base.height, "cut": base.cap, "notch": scar}
	return true

func _hand_tree_stump(arrays: Array, root: Vector3, bark: Material, wood: Material) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = []
	# Clip the qualified trunk rather than substituting a lathed post. The
	# shallow sloping cut preserves its flare, lean, texture and irregular rim.
	for first in range(0, indices.size(), 3):
		var polygon: Array[Dictionary] = []
		for index in indices.slice(first, first + 3):
			polygon.append({"p": vertices[index] - root, "n": normals[index], "uv": uv[index]})
		var clipped: Array[Dictionary] = []
		for i in range(3):
			var a: Dictionary = polygon[i]
			var b: Dictionary = polygon[(i + 1) % 3]
			var da: float = a.p.y - 0.045 - a.p.x * 0.15 - a.p.z * 0.10
			var db: float = b.p.y - 0.045 - b.p.x * 0.15 - b.p.z * 0.10
			if da <= 0.0:
				clipped.append(a)
			if (da <= 0.0) != (db <= 0.0):
				var t := da / (da - db)
				var point: Vector3 = a.p.lerp(b.p, t)
				clipped.append({"p": point, "n": a.n.lerp(b.n, t).normalized(), "uv": a.uv.lerp(b.uv, t)})
				var unique := true
				for existing in rim:
					if existing.distance_squared_to(point) < 0.0000000001:
						unique = false
						break
				if unique:
					rim.append(point)
		for i in range(1, clipped.size() - 1):
			for point: Dictionary in [clipped[0], clipped[i], clipped[i + 1]]:
				sides.set_normal(point.n)
				sides.set_uv(point.uv)
				sides.add_vertex(point.p)
	if rim.size() < 3:
		push_error("The qualified pine has no closed stump section.")
		return {}
	var center := Vector3.ZERO
	var height := 0.0
	for point in rim:
		center += point
		height = maxf(height, point.y)
	center /= float(rim.size())
	rim.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return atan2(a.z - center.z, a.x - center.x) < atan2(b.z - center.z, b.x - center.x))
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(rim.size()):
		for point: Vector3 in [center, rim[i], rim[(i + 1) % rim.size()]]:
			top.set_normal(Vector3(-0.15, 1.0, -0.10).normalized())
			top.add_vertex(point)
	var stump := sides.commit()
	stump.surface_set_material(0, bark)
	var cap := top.commit()
	cap.surface_set_material(0, wood)
	return {"mesh": stump, "cap": cap, "height": height}

func _refresh_hand_trees() -> void:
	var sources := {}
	if _native_transmission() and ProductionEnvironment.Surface != null:
		for id: String in state.get("hand_sources", {}):
			var source := _hand_source(id)
			if source.get("kind") == "tree" and typeof(source.get("initial")) == TYPE_INT \
					and source.initial > 0 and source.remaining <= source.initial:
				sources[id] = source
	_refresh_mature_trees(sources)
	for id: String in hand_tree_nodes.keys():
		if not sources.has(id) or hand_tree_nodes[id].get_meta("source_position") != sources[id].position:
			hand_tree_nodes[id].free()
			hand_tree_nodes.erase(id)
	if sources.is_empty() or not _prepare_hand_tree_assets():
		return
	for id: String in sources:
		if id.begins_with("fir_") or id.begins_with("broadleaf_"):
			continue
		var source: Dictionary = sources[id]
		if not hand_tree_nodes.has(id):
			var body := StaticBody3D.new()
			body.collision_layer = Geometry.PICK_LAYER
			body.collision_mask = 0
			body.set_meta("hand_source", id)
			body.set_meta("source_position", source.position.duplicate())
			body.position = Vector3(source.position[0], 0.0, source.position[2])
			body.position.y = ProductionEnvironment.Surface.height_at(body.position.x, body.position.z)
			var variation := absi(id.hash())
			body.basis = Basis(Vector3.UP, deg_to_rad(float(variation % 360))).scaled_local(Vector3.ONE * (4.0 + float(variation % 3) * 0.3))
			var tree := MeshInstance3D.new()
			tree.name = "Tree"
			tree.mesh = hand_tree_assets.mesh
			tree.position = -hand_tree_assets.root
			tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			body.add_child(tree)
			var stump := MeshInstance3D.new()
			stump.name = "Stump"
			stump.mesh = hand_tree_assets.stump
			body.add_child(stump)
			var cut := MeshInstance3D.new()
			cut.name = "Cut"
			cut.mesh = hand_tree_assets.cut
			body.add_child(cut)
			var picker := CollisionShape3D.new()
			picker.name = "PickShape"
			body.add_child(picker)
			add_child(body)
			hand_tree_nodes[id] = body
		var body: StaticBody3D = hand_tree_nodes[id]
		var counts := [source.initial, source.remaining]
		if body.get_meta("presented_counts", []) == counts:
			continue
		body.set_meta("presented_counts", counts)
		var standing: bool = source.remaining > 0
		body.get_node("Tree").visible = standing
		body.get_node("Stump").visible = not standing
		var picker: CollisionShape3D = body.get_node("PickShape")
		var shape: Shape3D = hand_tree_assets.trunk if standing else hand_tree_assets.stump_shape
		if picker.shape != shape:
			picker.shape = shape
		picker.position.y = 0.0 if standing else hand_tree_assets.stump_height * 0.5
		var cut: MeshInstance3D = body.get_node("Cut")
		cut.visible = source.remaining < source.initial
		cut.mesh = hand_tree_assets.notch if standing else hand_tree_assets.cut
		cut.transform = Transform3D.IDENTITY
		var fraction := 1.0 - float(source.remaining) / float(source.initial)
		if standing and cut.visible:
			if cut.material_override == null:
				cut.material_override = hand_tree_assets.notch.surface_get_material(0).duplicate()
			cut.material_override.set_shader_parameter("cut_fraction", fraction)
		else:
			cut.material_override = null

func _mature_cut_disk(radius: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(48):
		var angle := TAU * float(segment) / 48.0
		var next_angle := TAU * float(segment + 1) / 48.0
		var edge := radius * (1.0 + 0.025 * sin(angle * 5.0) + 0.012 * sin(angle * 11.0))
		var next_edge := radius * (1.0 + 0.025 * sin(next_angle * 5.0)
			+ 0.012 * sin(next_angle * 11.0))
		var first := Vector2(cos(angle), sin(angle)) * edge
		var second := Vector2(cos(next_angle), sin(next_angle)) * next_edge
		for point in [Vector2.ZERO, first, second]:
			tool.set_normal(Vector3.UP)
			tool.set_uv(Vector2(0.5 + point.x / (2.0 * radius),
				0.5 + point.y / (2.0 * radius)))
			tool.add_vertex(Vector3(point.x, 0.0, point.y))
	return tool.commit()

func _refresh_mature_trees(sources: Dictionary) -> void:
	var scenery := get_node_or_null("ProductionScenery")
	if scenery == null or ProductionEnvironment.Surface == null:
		return
	if mature_tree_collision_rows.is_empty():
		for row in ProductionEnvironment.Surface.mature_tree_collision_rows():
			mature_tree_collision_rows[row.id] = row
	for spec in ProductionEnvironment.Surface.fir_specs() + ProductionEnvironment.Surface.broadleaf_specs():
		var id: String = spec.id
		var group := "BankFirs" if id.begins_with("fir_") else "BankBroadleaf"
		var standing_mesh := scenery.get_node_or_null("%s/%s" % [group, id]) as MeshInstance3D
		if standing_mesh == null:
			continue
		var source: Dictionary = sources.get(id, {})
		var center: Vector3 = spec.center
		var site := Vector3(float(source.get("position", [0.0, 0.0, 0.0])[0]), 0.0,
			float(source.get("position", [0.0, 0.0, 0.0])[2]))
		if source.is_empty() or Vector2(site.x - center.x, site.z - center.z).length() > 0.35:
			standing_mesh.visible = false
			push_error("Mature tree lacks a matching native timber source: " + id)
			continue
		var standing: bool = source.remaining > 0
		standing_mesh.visible = standing
		if not mature_tree_nodes.has(id):
			var body := StaticBody3D.new()
			body.name = "MatureTreePicker_" + id
			body.collision_layer = Geometry.PICK_LAYER
			body.collision_mask = 0
			body.set_meta("hand_source", id)
			var picker := CollisionShape3D.new()
			picker.name = "PickShape"
			body.add_child(picker)
			var radius := 0.28 if id.begins_with("fir_") else 0.5
			var stump := MeshInstance3D.new()
			stump.name = "Stump"
			var stump_mesh := CylinderMesh.new()
			stump_mesh.height = 0.18
			stump_mesh.bottom_radius = radius
			stump_mesh.top_radius = radius * 0.9
			stump.mesh = stump_mesh
			stump.material_override = standing_mesh.mesh.surface_get_material(2)
			stump.position = Vector3(center.x,
				ProductionEnvironment.Surface.height_at(center.x, center.z) + 0.07, center.z)
			body.add_child(stump)
			var cap := MeshInstance3D.new()
			cap.name = "CutFace"
			cap.mesh = _mature_cut_disk(radius * 0.9)
			cap.material_override = ProductionEnvironment.cut_wood_material()
			cap.position = stump.position + Vector3.UP * 0.11
			body.add_child(cap)
			add_child(body)
			mature_tree_nodes[id] = body
		var body: StaticBody3D = mature_tree_nodes[id]
		if body.has_meta("standing") and body.get_meta("standing") == standing:
			continue
		body.set_meta("standing", standing)
		body.get_node("Stump").visible = not standing
		body.get_node("CutFace").visible = not standing
		var picker: CollisionShape3D = body.get_node("PickShape")
		if standing:
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(mature_tree_collision_rows[id].faces)
			picker.position = Vector3.ZERO
			picker.shape = shape
		else:
			var shape := CylinderShape3D.new()
			shape.radius = 0.28 if id.begins_with("fir_") else 0.5
			shape.height = 0.18
			picker.position = body.get_node("Stump").position
			picker.shape = shape

func _screen_hand_source(screen: Vector2) -> String:
	if not _native_transmission() or camera == null or state.get("hand_sources", {}).is_empty():
		return ""
	var eye := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(eye, eye + camera.project_ray_normal(screen) * 80.0,
		Geometry.GROUND_LAYER | Geometry.MACHINE_LAYER | Geometry.PICK_LAYER | TRANSMISSION_TERRAIN_PICK_LAYER)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	# A resource presenter identifies the actual hit, rather than selecting a
	# nearby source from camera distance. Host retains the actor-reach check.
	var id: String = str(hit.collider.get_meta("hand_source", ""))
	if id.is_empty() and actor_world != null and hit.collider == actor_world.floor_body:
		# Standing mature trunks use the same exact triangles in the actor floor
		# and in a resource picker. Resolve the coincident hit by its pick ID,
		# but keep a nearer terrain surface as an occluder.
		var pick_query := PhysicsRayQueryParameters3D.create(eye,
			eye + camera.project_ray_normal(screen) * 80.0, Geometry.PICK_LAYER)
		var pick := get_world_3d().direct_space_state.intersect_ray(pick_query)
		if not pick.is_empty() and pick.collider.get_meta("hand_source", "") != "" \
				and pick.position.distance_to(eye) <= hit.position.distance_to(eye) + 0.03:
			id = str(pick.collider.get_meta("hand_source"))
	if id.is_empty() and hit.collider == get_node_or_null("SharedOreSourcePicker"):
		# The shared view owns only a pick shape. The server projection supplies
		# the source identity and remains the sole stock and reach authority.
		id = str(state.get("source_deposit", {}).get("id", ""))
	if id.is_empty() and actor_world != null and hit.collider == actor_world.site_bodies.get("source_outcrop"):
		var deposits: Array[String] = []
		for key: String in state.hand_sources:
			if _hand_source(key).get("kind") == "ore_deposit":
				deposits.append(key)
		if deposits.size() == 1:
			id = deposits[0]
	return id if not _hand_source(id).is_empty() else ""

func _interact_pointed() -> void:
	if not _can_control_character():
		return
	var attached_crank := _pointed_crank() if mode == "inspect" else ""
	if not attached_crank.is_empty():
		held_crank = attached_crank
		held_crank_context = str(state.get("context", ""))
		held_crank_request = ""
		held_crank_seconds = STEP_SECONDS
		_advance_held_crank(0.0)
		return
	var source_id := _screen_hand_source(_pointed_screen_position()) if mode == "inspect" else ""
	var source := _hand_source(source_id)
	if source.is_empty():
		_open_pointed_machine()
		return
	if not _placement_ready():
		return
	if source.remaining == 0:
		_message("This source is depleted. Choose another tree or ore deposit.", true)
		return
	if not _hand_source_in_reach(source):
		_message("Move closer to the source before harvesting.", true)
		return
	if not _hand_source_clear(source_id):
		_message("Move around the obstacle before harvesting.", true)
		return
	if state.get("manual_cuts", {}).has(client):
		return
	issue({"action": "harvest_source", "target": source_id})

func _open_pointed_machine() -> void:
	if _catalog_open() or not _can_control_character():
		return
	var target := _screen_entity(_pointed_screen_position())
	if not _contains_target(state, target):
		_message("Point at a machine or part and press E to open it.", true)
		return
	_open_object_menu_for(target)

func _open_object_menu_for(target: String) -> void:
	if not _contains_target(state, target):
		return
	if building_hotbar != null and building_hotbar._valid_bench(state, target):
		_select_tool("inspect")
		selected = target
		_refresh_ui()
		building_hotbar.open_at_bench(target)
		return
	_select_tool("inspect")
	selected = target
	_refresh_ui()
	if arrival_assembly_controls != null:
		arrival_assembly_controls.open_context()
	object_menu_target = target
	object_menu_title.text = _object_name(target)
	object_menu_operations_label.text = "PART ACTIONS"
	var active_press := _is_guided_press_part(target)
	if active_press:
		object_menu_operations_label.text = "PRESS WORK"
	for row: Variant in state.get("collector_assemblies", []):
		if row is Dictionary and row.get("parts", {}).get("frame", "") == target:
			object_menu_operations_label.text = "COLLECTOR"
	object_menu_operations.visible = _object_supports_operations(target) and arrival_assembly_scroll.visible
	_release_character_controls()
	object_menu_scrim.visible = true
	var compact_collector := _is_collector_frame(target)
	var compact_part: bool = state.get("placed_components", {}).has(target) and not active_press and not compact_collector
	if compact_collector:
		arrival_assembly_scroll.custom_minimum_size.y = 0
	object_menu_desired_extent = Vector2i(620 if compact_part else 760 if object_menu_operations.visible else 500,
		280 if compact_part else 400 if compact_collector else 520 if object_menu_operations.visible else 400)
	var extent := _object_menu_extent()
	object_menu.min_size = extent
	object_menu.popup_centered(extent)
	_fit_object_menu()
	object_menu_close.grab_focus()
	_refresh_ui()

func _object_menu_extent(viewport: Vector2i = Vector2i.ZERO) -> Vector2i:
	if viewport == Vector2i.ZERO:
		viewport = Vector2i(get_viewport().get_visible_rect().size)
	return Vector2i(mini(object_menu_desired_extent.x, maxi(320, viewport.x - 24)),
		mini(object_menu_desired_extent.y, maxi(280, viewport.y - 24)))

func _fit_object_menu(viewport: Vector2i = Vector2i.ZERO) -> void:
	if viewport == Vector2i.ZERO:
		viewport = Vector2i(get_viewport().get_visible_rect().size)
	var narrow := viewport.x < 800
	object_menu_detail_panel.custom_minimum_size.x = 180 if narrow else 220
	object_menu_operations.custom_minimum_size.x = 340 if narrow else 420
	arrival_assembly_controls.custom_minimum_size.x = 340 if narrow else 410
	var extent := _object_menu_extent(viewport)
	object_menu.min_size = extent
	object_menu.size = extent
	object_menu.position = (viewport - object_menu.size) / 2
	object_menu_viewport_size = viewport

func _remove_selected() -> void:
	if not selected.is_empty():
		var removal := "stow_fabrication_hub" if selected == state.get("fabrication_hub", {}).get("id", "") else \
			"reclaim_component" if state.get("placed_components", {}).has(selected) else \
			"remove_belt_span" if _native_transmission() and state.get("belt_spans", {}).has(selected) else "remove"
		var outcome := issue({"action": removal, "entity": selected})
		if outcome.accepted:
			selected = ""
			if _object_menu_open():
				object_menu.hide()
			_refresh_ui()

func _confirm_goal() -> void:
	if explanation_open or state.has("hand_sources"):
		return
	if int(model.projection().inventories.get(client, 0)) >= 4:
		goal_confirmed = true
		_message("Four plates ready. Your first production line is working.")
		_refresh_ui()

func _toggle_explanation() -> void:
	explanation_open = not explanation_open
	help_panel.visible = explanation_open
	if explanation_open:
		_release_character_controls()
		help_title.text = "CURRENT TASK"
		help_body.text = goal_label.text + "\n\n" + controls_label.text
	_update_cursor()
	_refresh_ui()

func _screen_cell(screen: Vector2) -> Vector2i:
	if _native_transmission() and mode != "foundation":
		var id := _screen_entity(screen)
		var surface: Dictionary = state.get("foundations", {}).get(id, state.get("entities", {}).get(id, {}))
		if not surface.is_empty():
			return Vector2i(surface.cell[0], surface.cell[1])
	# Select a requested construction datum, not permission or terrain contact.
	# Shared clients need no duplicate ground collider. The host decides actual
	# placement; an area request deliberately has no construction reach limit.
	var height := foundation_level * Geometry.HEIGHT_STEP if _native_transmission() and mode == "foundation" else 0.0
	var point = Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null:
		return Vector2i(999999, 999999)
	return Vector2i(roundi(point.x / PITCH), roundi(point.z / PITCH))

func _screen_entity(screen: Vector2) -> String:
	var hit := _screen_pick(screen)
	return str(hit.collider.get_meta("entity", hit.collider.get_meta("component_entity", ""))) if not hit.is_empty() else ""

func _component_pointed_center() -> Array:
	var screen := _pointed_screen_position()
	return _component_place_center(_screen_cell(screen), _screen_entity(screen), false)

func _rotary_at_input_port(port: Array) -> String:
	var found := ""
	for id: String in state.get("placed_components", {}):
		var placed: Dictionary = state.placed_components[id]
		if placed.get("input_ports", []).has(port):
			if not found.is_empty():
				return ""
			found = id
	return found

func _crank_face_for_input(input_id: String, port: Array) -> Array:
	var input: Dictionary = state.get("placed_components", {}).get(input_id, {})
	var center: Array = input.get("center", [])
	if center.size() != 3 or port.size() != 3:
		return []
	if center != port:
		return [1 if int(port[0]) > int(center[0]) else -1, 0, 0]
	var axis := int(input.get("crank_axis", -1))
	var actor: Dictionary = state.get("actors", {}).get(client, {})
	var position: Array = actor.get("position", [])
	var anchor_position: Array = input.get("position", [])
	if axis not in [0, 2] or position.size() != 3 or anchor_position.size() != 3:
		return []
	var face := [0, 0, 0]
	face[axis] = -1 if float(position[axis]) < float(anchor_position[axis]) else 1
	return face

func _guided_press_part_snap(kind: String, pointed_kind: String, center: Array,
		normal: Vector3) -> Dictionary:
	# The press's working offsets are larger than a one-step face snap. Use the
	# part the player can actually point at to expose its next fitted socket.
	if kind == "flat_head" and pointed_kind == "anvil":
		return {"center": [center[0], center[1] + 1, center[2]], "label": "Head over workbed"}
	if kind in ["wooden_slide", "copper_slide"] and pointed_kind == "flat_head":
		return {"center": [center[0], center[1] + 1, center[2]], "label": "Slide over head"}
	if kind == "ram_face" and pointed_kind == "anvil":
		return {"center": [center[0], center[1] + 1, center[2]], "label": "Ram over anvil"}
	if kind == "sliding_guide" and pointed_kind in ["anvil", "ram_face"]:
		var rise := 3 if pointed_kind == "anvil" else 2
		return {"center": [center[0], center[1] + rise, center[2]],
			"label": "Guide over %s" % ("ram" if pointed_kind == "ram_face" else "anvil")}
	if pointed_kind == "anvil" and kind in ["wooden_shaft", "copper_shaft",
			"wooden_cog", "copper_cog"]:
		var distance := 1 if kind in ["wooden_shaft", "copper_shaft"] else 2
		if absf(normal.x) > 0.5 and absf(normal.x) > absf(normal.z):
			return {"center": [center[0] + distance * (1 if normal.x > 0.0 else -1),
				center[1] + 4, center[2]], "label": "Press drive from anvil"}
		if absf(normal.z) > 0.5:
			return {"center": [center[0], center[1] + 4,
				center[2] + distance * (1 if normal.z > 0.0 else -1)],
				"label": "Press drive from anvil"}
	if kind in ["wooden_shaft", "copper_shaft"] and pointed_kind == "sliding_guide":
		if absf(normal.x) > 0.5 and absf(normal.x) > absf(normal.z):
			return {"center": [center[0] + (1 if normal.x > 0.0 else -1),
				center[1] + 1, center[2]], "label": "Drive beside guide"}
		if absf(normal.z) > 0.5:
			return {"center": [center[0], center[1] + 1,
				center[2] + (1 if normal.z > 0.0 else -1)], "label": "Drive beside guide"}
	return {}

func _component_place_center(cell: Vector2i, pointed: String, use_nudge := true) -> Array:
	# One quarter-grid step off a confirmed component face builds a stack or
	# lateral drive. Host still decides support, occupancy, custody and reach.
	if use_nudge and component_nudge_active and component_nudge_center.size() == 3:
		return component_nudge_center.duplicate()
	if arrival_assembly_controls != null and arrival_assembly_controls.selected_name() == "wooden_workbench":
		return [cell.x * Geometry.HEIGHT_DENOMINATOR, _construction_level(cell),
			cell.y * Geometry.HEIGHT_DENOMINATOR]
	var placed: Dictionary = state.get("placed_components", {})
	if placed.has(pointed):
		var hit := _screen_pick(_pointed_screen_position())
		if not hit.is_empty() and hit.collider.get_meta("component_entity", "") == pointed:
			var normal: Vector3 = hit.normal
			var center: Array = placed[pointed].center.duplicate()
			var kind: String = arrival_assembly_controls.selected_name() if arrival_assembly_controls != null else ""
			if kind == "hand_crank" and placed[pointed].get("component", "") in \
					["tool_mount", "wooden_shaft", "copper_shaft"]:
				return center
			if kind == "flat_head" and str(placed[pointed].component) in ["wooden_slide", "copper_slide"]:
				return [center[0], center[1] - 1, center[2]]
			var press_snap := _guided_press_part_snap(kind, str(placed[pointed].component), center, normal)
			if not press_snap.is_empty():
				return press_snap.center
			var axis := 0
			if absf(normal.y) > absf(normal.x) and absf(normal.y) >= absf(normal.z):
				axis = 1
			elif absf(normal.z) > absf(normal.x):
				axis = 2
			center[axis] += 1 if normal[axis] >= 0.0 else -1
			return center
	return [cell.x * Geometry.HEIGHT_DENOMINATOR,
		_construction_level(cell), cell.y * Geometry.HEIGHT_DENOMINATOR]

func _component_center_allowed(center: Array) -> bool:
	if center.size() != 3 or ProductionEnvironment.Surface == null:
		return false
	var half: float = ProductionEnvironment.Surface.HALF - Geometry.HEIGHT_STEP / 2.0
	return absf(center[0] * Geometry.HEIGHT_STEP) <= half \
		and absf(center[2] * Geometry.HEIGHT_STEP) <= half

func _component_footprint_centers(kind: String, anchor: Array) -> Array:
	if anchor.size() != 3:
		return []
	if component_footprint_size != 2 or kind not in ["anvil", "ram_face"]:
		return [anchor.duplicate()]
	var centers := []
	for z in 2:
		for x in 2:
			centers.append([int(anchor[0]) + x * Geometry.HEIGHT_DENOMINATOR,
				int(anchor[1]), int(anchor[2]) + z * Geometry.HEIGHT_DENOMINATOR])
	return centers

func _component_area_origin(kind: String, pointer_center: Array) -> Array:
	return component_area_anchor if component_area_kind == kind and component_area_anchor.size() == 3 \
		else pointer_center

func _component_area_has_part(kind: String, center: Array) -> bool:
	for part: Dictionary in state.get("placed_components", {}).values():
		if part.get("component", "") == kind and part.get("center", []) == center:
			return true
	return false

func _toggle_component_footprint() -> void:
	if mode != "component" or arrival_assembly_controls == null \
			or arrival_assembly_controls.selected_name() not in ["anvil", "ram_face"]:
		return
	component_footprint_size = 1 if component_footprint_size == 2 else 2
	component_area_anchor.clear()
	component_area_kind = ""
	component_preview_pose_key = ""
	_refresh_component_preview()
	_update_cursor()
	if building_hotbar != null:
		building_hotbar.refresh()

func _component_collector_face(kind: String, center: Array) -> Dictionary:
	if kind not in ["tool_mount", "cutting_edge"]:
		return {}
	var step := 1 if kind == "tool_mount" else 2
	for face: Dictionary in state.get("collector_assemblies", []):
		var machine: Variant = face.get("center")
		var toward: Variant = face.get("toward_ore")
		if machine is Array and machine.size() == 3 and toward is Array and toward.size() == 3 \
				and center[0] == machine[0] + step * toward[0] \
				and center[1] in [machine[1], machine[1] + 1] \
				and center[2] == machine[2] + step * toward[2]:
			return face
	return {}

func _component_candidate_box(kind: String, center: Array) -> Dictionary:
	var at := Vector3(center[0] * Geometry.HEIGHT_STEP,
		center[1] * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT,
		center[2] * Geometry.HEIGHT_STEP)
	var occupied := at
	var half := Vector3(0.14, 0.14, 0.14)
	var collector_face := _component_collector_face(kind, center)
	if not collector_face.is_empty():
		var floor_y: float = collector_face.center[1] * Geometry.HEIGHT_STEP
		var top_y: float = at.y + (0.28 if kind == "tool_mount" else 0.105)
		var along_x: bool = collector_face.toward_ore[0] != 0
		var face_half := 0.21 if kind == "tool_mount" else 0.2025
		occupied.y = (floor_y + top_y) * 0.5
		half = Vector3(face_half if along_x else (0.20 if kind == "tool_mount" else 0.21),
			(top_y - floor_y) * 0.5,
			(0.19 if kind == "tool_mount" else 0.18) if along_x else face_half)
		return {"center": occupied, "half": half, "size": half * 2.0}
	match kind:
		"wooden_frame":
			occupied.y = center[1] * Geometry.HEIGHT_STEP + 0.45
			half = Vector3(0.2025, 0.45, 0.2025)
		"wooden_workbench":
			occupied.y = center[1] * Geometry.HEIGHT_STEP + 0.45
			half = Vector3(0.34, 0.45, 0.30)
		"channel_narrow_x", "channel_narrow_z", "channel_broad_x", "channel_broad_z":
			var pitch := Geometry.HEIGHT_STEP * 4.0
			var wide := kind.begins_with("channel_broad")
			var along_x := kind.ends_with("_x")
			var width_x := pitch * (1.0 if not wide or along_x else 2.0)
			var width_z := pitch * (1.0 if not wide or not along_x else 2.0)
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP
			var high: float = at.y + 0.082 + 0.12
			occupied += Vector3((width_x - pitch) * 0.5,
				(low + high) * 0.5 - occupied.y, (width_z - pitch) * 0.5)
			half = Vector3(width_x * 0.5, (high - low) * 0.5, width_z * 0.5)
		"anvil":
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP
			var high := low + Geometry.HEIGHT_STEP
			occupied.y = (low + high) * 0.5
			half = Vector3(0.2025, (high - low) * 0.5, 0.14)
		"ram_face":
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP
			var high := at.y + Geometry.HEIGHT_STEP * 0.5
			occupied.y = (low + high) * 0.5
			half.y = (high - low) * 0.5
		"flat_head":
			var low: float = float(center[1]) * Geometry.HEIGHT_STEP
			var high := at.y + Geometry.HEIGHT_STEP * 0.5
			occupied.y = (low + high) * 0.5
			half.y = (high - low) * 0.5
		"wooden_slide", "copper_slide":
			var low: float = at.y - Geometry.HEIGHT_STEP * 1.5
			var high := at.y + Geometry.HEIGHT_STEP * 0.5
			occupied.y = (low + high) * 0.5
			half = Vector3(0.21, (high - low) * 0.5, 0.21)
		"sliding_guide":
			var low := at.y - Geometry.HEIGHT_STEP * 1.5
			var high := at.y + Geometry.HEIGHT_STEP - 0.08
			occupied.y = (low + high) * 0.5
			half.y = (high - low) * 0.5
		"tool_mount":
			occupied.y += 0.10
			half = Vector3(Geometry.HEIGHT_STEP - 0.205, 0.18, Geometry.HEIGHT_STEP - 0.205)
		"cutting_edge":
			occupied.y -= 0.015
			half = Vector3(0.21, 0.12, 0.18)
		"receiver_tray":
			occupied.y -= 0.0825
			half = Vector3(0.18, 0.15, 0.205)
		"wooden_shaft", "copper_shaft":
			half = Vector3(0.205, 0.12, 0.205)
		"wooden_cog", "copper_cog":
			half = Vector3(Geometry.HEIGHT_STEP - 0.205, 0.14, Geometry.HEIGHT_STEP - 0.205)
	return {"center": occupied, "half": half, "size": half * 2.0}

func _component_candidate_blocked(kind: String, center: Array, box: Dictionary) -> bool:
	var result: Dictionary = Geometry.component_boxes(state)
	var occupied: Array = []
	if result.get("accepted", false):
		var paired_ids: Dictionary = {}
		for id: Variant in state.get("placed_components", {}):
			var part: Dictionary = state.placed_components[id]
			var part_center: Array = part.get("center", [])
			if part_center.size() != 3 or center.size() != 3 or \
					part_center[0] != center[0] or part_center[2] != center[2]:
				continue
			if (kind == "flat_head" and part.component in ["wooden_slide", "copper_slide"]
					and part_center[1] == center[1] + 1) or \
					(kind in ["wooden_slide", "copper_slide"] and part.component == "flat_head"
					and part_center[1] == center[1] - 1) or \
				(kind == "sliding_guide" and part.component == "ram_face"
					and part_center[1] == center[1] - 1) or \
				(kind == "ram_face" and part.component == "sliding_guide"
					and part_center[1] == center[1] + 1) or \
				(kind == "anvil" and part.component == "wooden_frame"
					and part_center[1] == center[1] - 1) or \
				(kind == "wooden_frame" and part.component == "anvil"
					and part_center[1] == center[1] + 1) or \
				(kind == "ram_face" and part.component == "wooden_frame"
					and part_center[1] == center[1] - 2) or \
				(kind == "wooden_frame" and part.component == "ram_face"
					and part_center[1] == center[1] + 2):
				paired_ids[id] = true
		for id: Variant in result.boxes:
			if not paired_ids.has(id):
				occupied.append(result.boxes[id])
	var mechanical: Dictionary = Geometry.mechanical_boxes(state)
	if mechanical.get("accepted", false):
		occupied.append_array(mechanical.get("boxes", {}).values())
	for foundation: Dictionary in state.get("foundations", {}).values():
		var cell: Variant = foundation.get("cell")
		if not cell is Array or cell.size() != 2 or typeof(foundation.get("level")) != TYPE_INT:
			continue
		var top := Vector3(cell[0] * Geometry.PITCH,
			foundation.level * Geometry.HEIGHT_STEP, cell[1] * Geometry.PITCH)
		occupied.append({"center": top - Vector3.UP * Geometry.FOUNDATION_DEPTH * 0.5,
			"size": Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH)})
	for entity: Dictionary in state.get("entities", {}).values():
		if entity.get("cell") is Array and entity.cell.size() == 2:
			occupied.append({"center": _entity_position(entity) + Vector3.UP * 0.8,
				"size": Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])})
	for actor: Dictionary in state.get("actors", {}).values():
		var position: Variant = actor.get("position")
		if Geometry.valid_position(position):
			occupied.append({"center": Vector3(position[0], position[1], position[2]),
				"size": Vector3(Geometry.CAPSULE_RADIUS * 2.0, Geometry.CAPSULE_HEIGHT,
					Geometry.CAPSULE_RADIUS * 2.0)})
	var source_contact := kind == "cutting_edge" and not _component_collector_face(kind, center).is_empty()
	if ProductionEnvironment.Surface != null:
		for solid: Dictionary in ProductionEnvironment.Surface.support_boxes():
			if solid.get("id", "") == "source_outcrop" and source_contact:
				continue
			var obstacle: AABB = Transform3D(solid.basis, solid.center) * AABB(-solid.size * 0.5, solid.size)
			occupied.append({"center": obstacle.get_center(), "size": obstacle.size})
	for other: Dictionary in occupied:
		var separation: Vector3 = (box.center - other.center).abs()
		var extent: Vector3 = (box.half + other.size * 0.5) - Vector3.ONE * 0.001
		if separation.x < extent.x and separation.y < extent.y and separation.z < extent.z:
			return true
	return false

func _refresh_component_preview() -> void:
	if component_preview == null:
		return
	component_preview.visible = false
	if press_snap_target != null:
		press_snap_target.visible = false
		press_snap_lift.visible = false
	if mode != "component" or not _native_transmission() or arrival_assembly_controls == null \
			or transmission_presenter == null or explanation_open or not _placement_ready() \
			or not _preview_pointer_clear():
		return
	var kind: String = arrival_assembly_controls.selected_name()
	if int(state.get("cargo", {}).get(client, {}).get("components", {}).get(kind, 0)) < 1:
		return
	var pointed := _screen_entity(_pointed_screen_position()) if not component_nudge_active else ""
	var center := _component_place_center(_screen_cell(_pointed_screen_position()), pointed)
	if center.size() != 3:
		return
	if kind == "hand_crank":
		var input_id := _rotary_at_input_port(center)
		var input: Dictionary = state.get("placed_components", {}).get(input_id, {})
		component_preview_blocked = input_id.is_empty()
		for item: Dictionary in state.get("crank_items", {}).values():
			if item.get("port", []) == center:
				component_preview_blocked = true
		component_preview_snap = "Rotary input" if not component_preview_blocked else "Point at a rotary input"
		if component_preview_pose_key != "hand_crank":
			for child in component_preview.get_children():
				child.free()
			transmission_presenter.preview_component(component_preview, kind, Vector3(0.15, 0.2, 0.15))
			component_preview_pose_key = "hand_crank"
			component_preview_kind = kind
			component_preview_material = StandardMaterial3D.new()
			component_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_style_component_preview(component_preview)
		component_preview.position = Vector3(float(center[0]) * Geometry.HEIGHT_STEP,
			float(center[1]) * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT,
			float(center[2]) * Geometry.HEIGHT_STEP)
		var input_cell: Array = input.get("center", [])
		var face := _crank_face_for_input(input_id, center)
		if face.size() != 3:
			face = [-1, 0, 0] if input_cell.size() == 3 and center[0] < input_cell[0] \
				else [1, 0, 0]
		var outward := Vector3(float(face[0]), 0.0, float(face[2]))
		if input_cell == center:
			component_preview.position += outward * 0.22
		component_preview.rotation.y = -atan2(outward.z, outward.x)
		component_preview_material.albedo_color = Color(0.94, 0.27, 0.21, 0.64) if component_preview_blocked \
			else Color(0.91, 0.73, 0.40, 0.56)
		component_preview.visible = true
		return
	component_preview.rotation.y = 0.0
	if component_area_kind == kind and component_area_anchor.size() == 3:
		var finished := true
		for area_cell: Array in _component_footprint_centers(kind, component_area_anchor):
			finished = finished and _component_area_has_part(kind, area_cell)
		if finished:
			component_area_anchor.clear()
			component_area_kind = ""
	var area_origin := _component_area_origin(kind, center)
	var box := _component_candidate_box(kind, center)
	var area_centers := _component_footprint_centers(kind, area_origin)
	if area_centers.size() == 4:
		var area_box := _component_candidate_box(kind, area_origin)
		component_preview_blocked = not area_centers.has(center) \
			or not _component_center_allowed(center) \
			or _component_area_has_part(kind, center) \
			or _component_candidate_blocked(kind, center, box)
		component_preview_snap = "Nudged point" if component_nudge_active else \
			"Selected area" if component_area_anchor.size() == 3 else "Floor grid"
		var placed_cells := []
		for part_center: Array in area_centers:
			placed_cells.append(_component_area_has_part(kind, part_center))
		var area_key := "area:%s:%s:%s" % [kind, str(area_origin), str(placed_cells)]
		if area_key != component_preview_pose_key:
			for child in component_preview.get_children():
				child.free()
			component_preview_cell_materials.clear()
			component_preview_material = StandardMaterial3D.new()
			component_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			component_preview_material.roughness = 0.72
			for index in area_centers.size():
				if placed_cells[index]:
					continue
				var part_center: Array = area_centers[index]
				var part_box := _component_candidate_box(kind, part_center)
				var anchor := Node3D.new()
				anchor.position = part_box.center - area_box.center
				component_preview.add_child(anchor)
				transmission_presenter.preview_component(anchor, kind, part_box.size)
				var material := component_preview_material.duplicate() as StandardMaterial3D
				component_preview_cell_materials[str(part_center)] = material
				_style_component_preview(anchor, material)
			component_preview_kind = kind
			component_preview_pose_key = area_key
		for part_center: Array in area_centers:
			if _component_area_has_part(kind, part_center):
				continue
			var part_box := _component_candidate_box(kind, part_center)
			var blocked := not _component_center_allowed(part_center) \
				or _component_candidate_blocked(kind, part_center, part_box)
			var material: StandardMaterial3D = component_preview_cell_materials[str(part_center)]
			material.albedo_color = Color(0.94, 0.27, 0.21, 0.64) if blocked \
				else Color(0.91, 0.73, 0.40, 0.56)
		component_preview.position = area_box.center
		component_preview_material.albedo_color = Color(0.94, 0.27, 0.21, 0.64) if component_preview_blocked \
			else Color(0.91, 0.73, 0.40, 0.56)
		component_preview.visible = true
		return
	component_preview_blocked = not _component_center_allowed(center) or _component_candidate_blocked(kind, center, box)
	component_preview_snap = ""
	if component_nudge_active:
		component_preview_snap = "Nudged point"
	elif state.get("placed_components", {}).has(pointed):
		var pointed_kind: String = str(state.placed_components[pointed].component)
		var hit := _screen_pick(_pointed_screen_position())
		var press_snap := _guided_press_part_snap(kind, pointed_kind,
			state.placed_components[pointed].center, hit.normal) if not hit.is_empty() else {}
		component_preview_snap = str(press_snap.label) if not press_snap.is_empty() else \
			("Above %s" % pointed_kind.replace("_", " ") if not hit.is_empty() and hit.normal.y > 0.5 \
			else "Beside %s" % pointed_kind.replace("_", " "))
		if press_snap_target != null and not press_snap.is_empty() \
				and (kind == "flat_head" and pointed_kind == "anvil" \
				or kind in ["wooden_slide", "copper_slide"] and pointed_kind == "flat_head"):
			var target_box := _component_candidate_box(pointed_kind, state.placed_components[pointed].center)
			press_snap_target.position = target_box.center + Vector3.UP * (target_box.half.y + 0.015)
			press_snap_target.scale = Vector3(target_box.half.x / 0.77, 1.0, target_box.half.z / 0.77)
			press_snap_material.albedo_color = Color(0.94, 0.27, 0.21, 0.85) \
				if component_preview_blocked else Color(0.98, 0.73, 0.28, 0.9)
			press_snap_target.visible = true
			var camera_right: Vector3 = camera.global_transform.basis.x
			camera_right.y = 0.0
			var guide_bottom: float = target_box.center.y - target_box.half.y + 0.02 \
				if pointed_kind == "flat_head" else target_box.center.y + target_box.half.y + 0.025
			var guide_top: float = box.center.y + box.half.y - 0.025
			press_snap_lift.scale.y = maxf(0.35, (guide_top - guide_bottom) / 0.82)
			press_snap_lift_tip.scale.y = 0.5 / press_snap_lift.scale.y
			press_snap_lift_tip.position.y = 0.455 - 0.0375 / press_snap_lift.scale.y
			press_snap_lift.position = Vector3(target_box.center.x,
				guide_bottom + press_snap_lift.scale.y * 0.365, target_box.center.z) \
				+ camera_right.normalized() * (0.28 if pointed_kind == "flat_head" else 0.22)
			press_snap_lift_material.albedo_color = press_snap_material.albedo_color
			press_snap_lift.visible = true
	else:
		component_preview_snap = "Floor grid"
	var collector_face := _component_collector_face(kind, center)
	var collector_angle := 0.0
	var collector_support_drop := 0.0
	var visual_center: Vector3 = box.center
	if not collector_face.is_empty():
		var toward: Array = collector_face.toward_ore
		collector_angle = atan2(float(toward[2]), -float(toward[0]))
		var floor_y: float = collector_face.center[1] * Geometry.HEIGHT_STEP
		visual_center.y = center[1] * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT \
			+ (0.10 if kind == "tool_mount" else -0.015)
		collector_support_drop = visual_center.y - floor_y
	var preview_key := "%s:%s:%s" % [kind, collector_angle, collector_support_drop]
	if preview_key != component_preview_pose_key:
		for child in component_preview.get_children():
			child.free()
		transmission_presenter.preview_component(component_preview, kind, box.size,
			collector_angle, collector_support_drop)
		component_preview_kind = kind
		component_preview_pose_key = preview_key
		component_preview_material = StandardMaterial3D.new()
		component_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		component_preview_material.roughness = 0.72
		_style_component_preview(component_preview)
	component_preview.position = visual_center
	component_preview_material.albedo_color = Color(0.94, 0.27, 0.21, 0.64) if component_preview_blocked \
		else Color(0.91, 0.73, 0.40, 0.56)
	component_preview.visible = true

func _style_component_preview(node: Node, material: StandardMaterial3D = null) -> void:
	if node is MeshInstance3D:
		node.material_override = material if material != null else component_preview_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_style_component_preview(child, material)

func _component_placement_hint() -> String:
	if component_preview == null or not component_preview.visible:
		return "Point at a floor or built part"
	if arrival_assembly_controls != null and arrival_assembly_controls.selected_name() == "hand_crank":
		return "Point at a slide input shaft end · click to fit the carried crank" \
			if not component_preview_blocked else "Point at a clear slide input shaft end"
	var center := _component_place_center(_screen_cell(_pointed_screen_position()),
		_screen_entity(_pointed_screen_position()))
	var location := "%s · X %d  Y %d  Z %d" % [component_preview_snap, center[0], center[1], center[2]]
	var action := "Blocked here · move the ghost" if component_preview_blocked else "Click to place"
	var kind: String = arrival_assembly_controls.selected_name()
	if component_footprint_size == 2 and kind in ["anvil", "ram_face"]:
		action = "Aim at a free area cell" if component_preview_blocked else "Click each area cell"
	var stack_hint := "Aim at a floor or built surface" if kind == "anvil" else \
		"Aim at the anvil to place the head above" if kind == "flat_head" else \
		"Aim at the flat head to place the slide above" if kind in ["wooden_slide", "copper_slide"] else \
		"Aim at the anvil top" if kind == "ram_face" else \
		"Aim at the anvil or ram top" if kind == "sliding_guide" else \
		"Press drive: aim at anvil side or guide side" if kind in ["wooden_shaft", "copper_shaft"] else \
		"Press drive: aim at anvil side or shaft end" if kind in ["wooden_cog", "copper_cog"] else \
		"Point at a part face to snap"
	return "%s\n%s · %s\nAlt + arrows / PgUp / PgDn nudges" % [location, action, stack_hint]

func _screen_pick(screen: Vector2) -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		return {}
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 80)
	query.collision_mask = Geometry.PICK_LAYER | Geometry.MACHINE_LAYER | TRANSMISSION_TERRAIN_PICK_LAYER
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_meta("transmission_terrain"):
		return {}
	return hit

func _entity_at_cell(cell: Vector2i) -> String:
	for entity_id in state.get("entities", {}):
		if state.entities[entity_id].cell == [cell.x, cell.y]:
			return entity_id
	return ""

func _cell_position(cell: Array) -> Vector3:
	return Vector3(cell[0] * PITCH, 0, cell[1] * PITCH)

func _entity_position(entity: Dictionary) -> Vector3:
	return _cell_position(entity.cell) + Vector3.UP * float(entity.get("level", 0)) * Geometry.HEIGHT_STEP

func _build_cell_allowed(cell: Vector2i) -> bool:
	if mode != "foundation" and _native_transmission() and ProductionEnvironment.Surface != null:
		var half: float = ProductionEnvironment.Surface.HALF - PITCH / 2.0
		return absf(cell.x * PITCH) <= half and absf(cell.y * PITCH) <= half
	return absi(cell.x) <= 250000 and absi(cell.y) <= 250000

func _construction_level(cell: Vector2i) -> int:
	if mode == "foundation":
		return foundation_level
	if mode == "wheel":
		return wheel_level
	var top := -1000001
	for surface: Dictionary in state.get("foundations", {}).values():
		if surface.cell == [cell.x, cell.y]:
			top = maxi(top, int(surface.level))
	return top if top > -1000001 else 0

func _adjust_foundation_level(delta: int) -> void:
	if mode not in ["foundation", "wheel"] or not _native_transmission() or explanation_open:
		return
	if mode == "wheel":
		wheel_level = clampi(wheel_level + delta * Geometry.HEIGHT_DENOMINATOR, -1000000, 1000000)
	else:
		var step := 1 if foundation_steps else Geometry.FOUNDATION_HEIGHT_UNITS
		foundation_level = clampi(foundation_level + delta * step, -1000000, 1000000)
	foundation_area_started = false
	foundation_level_label.text = _construction_height_text()
	_message(_construction_height_text() + ". Access steps are for walking; machines need a factory floor.")

func _set_foundation_steps(enabled: bool) -> void:
	foundation_steps = enabled
	if not enabled:
		foundation_level = roundi(float(foundation_level) / Geometry.HEIGHT_DENOMINATOR) * Geometry.HEIGHT_DENOMINATOR
	foundation_area_started = false
	foundation_level_label.text = _construction_height_text()
	_message(_construction_height_text() + ". Existing foundations stay at their built heights.")

func _construction_height_text() -> String:
	var level := wheel_level if mode == "wheel" else foundation_level
	var caption := "Drive height" if mode == "wheel" else "Factory floor" if level % Geometry.HEIGHT_DENOMINATOR == 0 else "Access step"
	return "%s · %.2f m" % [caption, level * Geometry.HEIGHT_STEP]

func _machine_floor_aligned(cell: Vector2i) -> bool:
	# Only suppress a known impossible height. Host still decides support,
	# terrain, occupancy and reach; an amber preview never promises admission.
	return not _native_transmission() or mode not in ["collector", "belt", "processor", "wheel"] \
		or _construction_level(cell) % Geometry.HEIGHT_DENOMINATOR == 0

func _adjust_wheel_size(delta: int) -> void:
	if mode != "wheel" or not _native_transmission() or explanation_open:
		return
	wheel_tiles = clampi(wheel_tiles + delta, 3, 4096)
	wheel_size_label.text = "Wheel diameter: %d squares" % wheel_tiles

func _assemble_foundation(parent: Node3D, neighbor_mask: int = 0) -> void:
	# Only confirmed player-built surfaces or an explicit placement preview
	# call this; the unbuilt site receives no manufactured structures.
	if not ProductionFoundationArt.mount(parent, neighbor_mask):
		push_error("The foundation needs its complete concrete and steel art kit.")
		if is_inside_tree():
			get_tree().quit(1)

func _update_camera() -> void:
	var back := Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch))
	var eye_offset := FIRST_PERSON_EYE_OFFSET * (1.0 - clampf(distance / FIRST_PERSON_BLEND_DISTANCE, 0.0, 1.0))
	camera.position = focus + Vector3.UP * eye_offset + back * distance
	# At zero distance look along the same orbit ray instead of looking at the
	# camera's own position. The local mesh remains real but cannot fill the view.
	camera.look_at(camera.position - back)
	if character_presenter != null and character_presenter.views.has(client):
		var local_view: Node3D = character_presenter.views[client]
		var local_actor: Dictionary = state.get("actors", {}).get(client, {})
		local_view.visible = distance > 1.0 and local_actor.get("ready", false) \
			and Geometry.valid_position(local_actor.get("position"))
	if status_footer != null:
		var footer_anchor := 0.0 if _footer_above_view() else 1.0
		if not is_equal_approx(status_footer.anchor_top, footer_anchor):
			_queue_footer_fit()
	if arrival_reveal_active:
		_update_arrival_reveal_camera()

func _build_world() -> void:
	if ProductionEnvironment.Surface == null:
		push_error("Opening requires authored site geometry")
		if is_inside_tree():
			get_tree().quit(1)
		return
	ProductionEnvironment.build(self)
	var surface = ProductionEnvironment.Surface
	var natural_ground: ShaderMaterial = ProductionEnvironment.ground_material()
	if natural_ground == null:
		if is_inside_tree():
			get_tree().quit(1)
		return
	var natural_stone: StandardMaterial3D = ProductionEnvironment.stone_material()
	set_meta("foundation_surface", ProductionEnvironment.ground_source_status)
	var groups := {"": self}
	var headwall := Node3D.new()
	headwall.name = "NorthSeamOutcrop"
	headwall.position = surface.group_origin("NorthSeamOutcrop")
	add_child(headwall)
	groups.NorthSeamOutcrop = headwall
	for spec in surface.foundation_boxes():
		var part := _machine_box(groups[spec.group], spec.label,
			spec.center - surface.group_origin(spec.group), spec.size, spec.tint, spec.metallic, spec.roughness)
		part.set_meta("site_solid_id", spec.id)
		if spec.label in ["EastBedrockShelf", "WestBankBedrockShelf"] and natural_ground != null:
			part.material_override = natural_ground
		elif spec.label in ["EastBedrockRim", "WestBedrockRim", "EastShelfOutcrop", "WestShelfOutcrop", "StreamBankLedge"] and natural_stone != null:
			part.material_override = natural_stone
	for spec in surface.pad_panels():
		var tint := Color("74766b").darkened(float(posmod(spec.cell.x * 17 + spec.cell.y * 31, 5)) * 0.018)
		var panel := _machine_box(self, "BedrockTerracePanel", spec.center, spec.size, tint, 0.0, 0.94)
		panel.set_meta("surface_role", "foundation")
		panel.set_meta("site_solid_id", spec.id)
		if natural_ground != null:
			panel.material_override = natural_ground
	_install_transmission_terrain_picker()
	machine_root = Node3D.new()
	add_child(machine_root)
	component_preview = Node3D.new()
	component_preview.name = "ComponentPreview"
	component_preview.visible = false
	add_child(component_preview)
	press_snap_target = _selection_outline()
	press_snap_target.name = "PressSnapTarget"
	press_snap_material = press_snap_target.material_override.duplicate() as StandardMaterial3D
	press_snap_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	press_snap_target.material_override = press_snap_material
	press_snap_target.visible = false
	press_snap_lift = Node3D.new()
	press_snap_lift.name = "PressSnapLift"
	press_snap_lift_material = StandardMaterial3D.new()
	press_snap_lift_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	press_snap_lift_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for dash_y in [-0.30, -0.08, 0.14]:
		var dash := MeshInstance3D.new()
		var stem := CylinderMesh.new()
		stem.top_radius = 0.009
		stem.bottom_radius = 0.009
		stem.height = 0.13
		dash.mesh = stem
		dash.position.y = dash_y
		dash.material_override = press_snap_lift_material
		dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		press_snap_lift.add_child(dash)
	press_snap_lift_tip = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.045
	cone.height = 0.15
	press_snap_lift_tip.mesh = cone
	press_snap_lift_tip.position.y = 0.38
	press_snap_lift_tip.material_override = press_snap_lift_material
	press_snap_lift_tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	press_snap_lift.add_child(press_snap_lift_tip)
	press_snap_lift.visible = false
	add_child(press_snap_lift)
	item_root = Node3D.new()
	add_child(item_root)
	hover = _box(self, Vector3.ZERO, Vector3(1.5, 0.035, 1.5), Color(0.85, 0.75, 0.45, 0.45))
	hover.visible = false
	selection_ring = _selection_outline()
	selection_ring.visible = false
	camera = Camera3D.new()
	# Keep the full guided press in view while aiming from reachable actor distance.
	camera.fov = 65
	camera.near = 0.1
	camera.far = 100
	add_child(camera)
	camera.make_current()
	_update_camera()

func _pod_panel(parent: Node3D, part_name: String, profile: PackedVector2Array,
		depth: float, at: Vector3, finish: Material, bevel: float = 0.012) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = ProductionVisuals.prism_mesh(profile, depth, bevel)
	part.position = at
	part.material_override = finish
	parent.add_child(part)
	return part

func _build_landing_pod_visual(pod: Dictionary, hub: Dictionary) -> void:
	landing_pod_visual = Node3D.new()
	landing_pod_visual.name = "DeployedLandingPod"
	landing_pod_visual.set_meta("authority_entity", pod.id)
	add_child(landing_pod_visual)
	var shell := Node3D.new()
	shell.name = "OpenedPodShell"
	landing_pod_visual.add_child(shell)
	var graphite := Color("293a3c")
	var amber := Color("be8d43")
	var dark := Color("17282c")
	var hull_finish := ProductionCollectorArt.coating(Color("74766d"))
	var service_finish := ProductionCollectorArt.coating(Color("394347"))
	var worked_finish := ProductionTransmissionFinish.material("worked", Color("91938b"), 0.75, 0.48)
	# One pressure canopy closes over the pallet in flight, then hinges back.
	# The folded cover parks behind the pallet, clearing the front and east aisle.
	_pod_panel(shell, "LowerHull", PackedVector2Array([
		Vector2(-0.56, 0.12), Vector2(0.56, 0.12), Vector2(0.67, 0.17),
		Vector2(0.74, 0.26), Vector2(0.72, 0.34), Vector2(0.64, 0.43),
		Vector2(-0.64, 0.43), Vector2(-0.72, 0.34), Vector2(-0.74, 0.26),
		Vector2(-0.67, 0.17)]),
		1.76, Vector3(0, 0, 0.02), ProductionCollectorArt.coating(graphite))
	var pallet := _pod_panel(shell, "InteriorPallet", PackedVector2Array([
		Vector2(-0.535, -0.585), Vector2(-0.415, -0.705),
		Vector2(0.415, -0.705), Vector2(0.535, -0.585),
		Vector2(0.535, 0.585), Vector2(0.415, 0.705),
		Vector2(-0.415, 0.705), Vector2(-0.535, 0.585)]),
		0.055, Vector3(0, 0.43, -0.03), service_finish, 0.006)
	pallet.rotation.x = PI / 2.0
	_pod_panel(shell, "RearBulkhead", PackedVector2Array([
		Vector2(-0.56, 0.37), Vector2(0.56, 0.37), Vector2(0.56, 0.81),
		Vector2(0.42, 0.95), Vector2(-0.42, 0.95), Vector2(-0.56, 0.81)]),
		0.12, Vector3(0, 0, 0.79), service_finish)
	var canopy := Node3D.new()
	canopy.name = "CanopyPivot"
	canopy.position = Vector3(0, 0.72, 0.80)
	shell.add_child(canopy)
	var inner_arch := PackedVector2Array([
		Vector2(0.56, 0.38), Vector2(0.56, 0.84), Vector2(0.54, 1.00),
		Vector2(0.48, 1.12), Vector2(0.37, 1.22), Vector2(0.20, 1.28),
		Vector2(-0.20, 1.28), Vector2(-0.37, 1.22), Vector2(-0.48, 1.12),
		Vector2(-0.54, 1.00), Vector2(-0.56, 0.84), Vector2(-0.56, 0.38)])
	var canopy_profile := PackedVector2Array([
		Vector2(-0.68, 0.38), Vector2(-0.68, 0.48), Vector2(-0.668, 0.53),
		Vector2(-0.668, 0.88), Vector2(-0.65, 1.05), Vector2(-0.58, 1.20),
		Vector2(-0.48, 1.32), Vector2(-0.34, 1.39), Vector2(-0.16, 1.42),
		Vector2(0.16, 1.42), Vector2(0.34, 1.39), Vector2(0.48, 1.32),
		Vector2(0.58, 1.20), Vector2(0.65, 1.05), Vector2(0.668, 0.88),
		Vector2(0.668, 0.53), Vector2(0.68, 0.48), Vector2(0.68, 0.38)])
	canopy_profile.append_array(inner_arch)
	_pod_panel(canopy, "PressureCanopy", canopy_profile,
		1.70, Vector3(0, -0.72, -0.85), hull_finish, 0.008)
	var liner_profile := inner_arch.duplicate()
	var liner_return := inner_arch.duplicate()
	liner_return.reverse()
	for index in range(liner_return.size()):
		liner_return[index].x *= 0.965
		liner_return[index].y = maxf(0.38, liner_return[index].y - 0.014)
	liner_profile.append_array(liner_return)
	_pod_panel(canopy, "CanopyLiner", liner_profile,
		1.49, Vector3(0, -0.72, -0.85), service_finish, 0.002)
	_pod_panel(canopy, "ForwardHatch", inner_arch,
		0.075, Vector3(0, -0.72, -1.72), ProductionCollectorArt.coating(graphite))
	_pod_panel(canopy, "SmokedVisor", PackedVector2Array([
		Vector2(-0.36, 0.78), Vector2(0.36, 0.78), Vector2(0.33, 1.00),
		Vector2(0.22, 1.12), Vector2(0.08, 1.16), Vector2(-0.08, 1.16),
		Vector2(-0.22, 1.12), Vector2(-0.33, 1.00)]),
		0.008, Vector3(0, -0.72, -1.754), ProductionVisuals.material(Color("36585e"), 0.05, 0.22), 0.002)
	_pod_panel(canopy, "HatchLatch", PackedVector2Array([
		Vector2(-0.115, -0.02), Vector2(-0.10, -0.0325),
		Vector2(0.10, -0.0325), Vector2(0.115, -0.02),
		Vector2(0.115, 0.02), Vector2(0.10, 0.0325),
		Vector2(-0.10, 0.0325), Vector2(-0.115, 0.02)]),
		0.018, Vector3(0, -0.14, -1.75), ProductionCollectorArt.coating(amber), 0.003)
	for side in [-1.0, 1.0]:
		var suffix := "Port" if side < 0.0 else "Starboard"
		var panel := _pod_panel(canopy, suffix + "ServicePanel", PackedVector2Array([
			Vector2(-0.65, 0.56), Vector2(-0.60, 0.52), Vector2(0.60, 0.52),
			Vector2(0.65, 0.56), Vector2(0.65, 0.82), Vector2(0.60, 0.86),
			Vector2(-0.60, 0.86), Vector2(-0.65, 0.82)]),
			0.006, Vector3(side * 0.672, -0.72, -0.85), service_finish, 0.002)
		panel.rotation.y = side * PI / 2.0
		_machine_box(canopy, suffix + "CanopyStripe", Vector3(side * 0.11, 0.709, -0.85),
			Vector3(0.055, 0.018, 1.51), amber, 0.18, 0.69)
	for side in [-1.0, 1.0]:
		var suffix := "Port" if side < 0.0 else "Starboard"
		var hinge := _machine_cylinder(shell, suffix + "CanopyHinge", Vector3(side * 0.53, 0.72, 0.80),
			0.09, 0.21, graphite, Vector3(0, 0, PI / 2.0))
		hinge.material_override = worked_finish
		_machine_cylinder(shell, suffix + "CanopyStrut", Vector3.ZERO, 0.026, 1.0, Color("8d9c99"))
		for z in [-0.72, 0.72]:
			var end := "Front" if z < 0 else "Rear"
			var foot := _pod_panel(shell, suffix + "LandingFoot" + end, PackedVector2Array([
				Vector2(-0.14, -0.10), Vector2(-0.095, -0.145),
				Vector2(0.095, -0.145), Vector2(0.14, -0.10),
				Vector2(0.14, 0.10), Vector2(0.095, 0.145),
				Vector2(-0.095, 0.145), Vector2(-0.14, 0.10)]),
				0.14, Vector3(side * 0.65, 0.07, z), ProductionCollectorArt.coating(graphite), 0.008)
			foot.rotation.x = PI / 2.0
			_machine_box(shell, suffix + "PalletSkid" + end, Vector3(side * 0.58, 0.15, z),
				Vector3(0.09, 0.18, 0.13), graphite, 0.45, 0.68)
	landing_hub_visual = Node3D.new()
	landing_hub_visual.name = "PodFabricationHub"
	landing_hub_visual.set_meta("authority_entity", hub.id)
	add_child(landing_hub_visual)
	landing_hub_pick = StaticBody3D.new()
	landing_hub_pick.name = "WorkshopPickBody"
	landing_hub_pick.set_meta("component_entity", hub.id)
	landing_hub_pick.collision_layer = Geometry.PICK_LAYER
	landing_hub_pick.collision_mask = 0
	landing_hub_pick.position.y = 0.68
	var pick_shape := CollisionShape3D.new()
	pick_shape.name = "PickShape"
	var pick_box := BoxShape3D.new()
	pick_box.size = Vector3(1.16, 1.25, 0.70)
	pick_shape.shape = pick_box
	landing_hub_pick.add_child(pick_shape)
	landing_hub_visual.add_child(landing_hub_pick)
	var workspace := Node3D.new()
	workspace.name = "FoldoutBench"
	landing_hub_visual.add_child(workspace)
	var frame_finish := ProductionCollectorArt.coating(graphite)
	var work_finish := ProductionTransmissionFinish.material("worked", Color("50504b"), 0.55, 0.57)
	var steel_finish := ProductionTransmissionFinish.material("worked", Color("979a95"), 0.85, 0.42)
	var tool_finish := ProductionCollectorArt.coating(Color("99713c"))
	for x in [-0.40, 0.40]:
		var side := "West" if x < 0 else "East"
		for z in [-0.27, 0.27]:
			_pod_panel(workspace, "BenchLeg%s%s" % [side, "Front" if z < 0 else "Rear"], PackedVector2Array([
				Vector2(-0.0425, 0), Vector2(0.0425, 0),
				Vector2(0.0425, 0.68), Vector2(-0.0425, 0.68)]),
				0.085, Vector3(x, 0, z), frame_finish, 0.004)
		var brace := _pod_panel(workspace, "BenchLockBrace" + side, PackedVector2Array([
			Vector2(-0.27, 0.60), Vector2(0.27, 0.60),
			Vector2(0.27, 0.53), Vector2(-0.27, 0.32)]),
			0.035, Vector3(x, 0, 0), frame_finish, 0.004)
		brace.rotation.y = PI / 2.0
	for z in [-0.27, 0.27]:
		var rail := _machine_box(workspace, "BenchFrontApron" if z < 0 else "BenchRearApron", Vector3(0, 0.645, z),
			Vector3(0.88, 0.09, 0.06), graphite)
		rail.material_override = frame_finish
	var worktop := _pod_panel(workspace, "BenchWorktop", PackedVector2Array([
		Vector2(-0.58, -0.30), Vector2(-0.53, -0.35), Vector2(0.53, -0.35),
		Vector2(0.58, -0.30), Vector2(0.58, 0.30), Vector2(0.53, 0.35),
		Vector2(-0.53, 0.35), Vector2(-0.58, 0.30)]),
		0.115, Vector3(0, 0.74, 0), work_finish, 0.008)
	worktop.rotation.x = PI / 2.0
	var bed := _machine_box(workspace, "BenchSteelInsert", Vector3(-0.16, 0.805, -0.06),
		Vector3(0.52, 0.02, 0.38), Color("596e6d"))
	bed.material_override = steel_finish
	for spec in [[-0.35, 1.0, "Fixed"], [0.03, -1.0, "Sliding"]]:
		var x: float = spec[0]
		var jaw_name: String = spec[2]
		_pod_panel(workspace, "Vise" + jaw_name + "Jaw", PackedVector2Array([
			Vector2(-0.0375, -0.065), Vector2(0.0375, -0.065),
			Vector2(0.033, 0.035), Vector2(0.018, 0.065),
			Vector2(-0.018, 0.065), Vector2(-0.0375, 0.035)]),
			0.27, Vector3(x, 0.88, -0.06), frame_finish, 0.004)
		var face := _machine_box(workspace, "Vise" + jaw_name + "Face", Vector3(x + spec[1] * 0.032, 0.90, -0.06),
			Vector3(0.009, 0.075, 0.25), Color("78867e"))
		face.material_override = steel_finish
	var lead_screw := _machine_cylinder(workspace, "ViseLeadScrew", Vector3(-0.10, 0.847, -0.06),
		0.014, 0.50, Color("979a95"), Vector3(0, 0, PI / 2.0))
	lead_screw.material_override = steel_finish
	var handle_boss := _machine_cylinder(workspace, "ViseHandleBoss", Vector3(0.16, 0.847, -0.06),
		0.028, 0.04, Color("979a95"), Vector3(0, 0, PI / 2.0))
	handle_boss.material_override = steel_finish
	var sliding_handle := _machine_cylinder(workspace, "ViseSlidingHandle", Vector3(0.16, 0.847, -0.06),
		0.008, 0.14, Color("979a95"))
	sliding_handle.material_override = steel_finish
	_pod_panel(workspace, "ToolPost", PackedVector2Array([
		Vector2(-0.07, -0.22), Vector2(0.07, -0.22), Vector2(0.07, -0.16),
		Vector2(0.045, -0.12), Vector2(0.045, 0.18), Vector2(0.03, 0.22),
		Vector2(-0.03, 0.22), Vector2(-0.045, 0.18),
		Vector2(-0.045, -0.12), Vector2(-0.07, -0.16)]),
		0.14, Vector3(0.35, 1.01, -0.19), frame_finish, 0.005)
	_pod_panel(workspace, "ToolArm", PackedVector2Array([
		Vector2(-0.285, -0.018), Vector2(-0.265, -0.0325),
		Vector2(0.285, -0.0325), Vector2(0.285, 0.0325),
		Vector2(-0.265, 0.0325), Vector2(-0.285, 0.018)]),
		0.065, Vector3(0.065, 1.23, -0.19), frame_finish, 0.004)
	_pod_panel(workspace, "CuttingHead", PackedVector2Array([
		Vector2(-0.06, 0.085), Vector2(0.06, 0.085), Vector2(0.055, -0.02),
		Vector2(0.025, -0.07), Vector2(0.02, -0.085), Vector2(-0.02, -0.085),
		Vector2(-0.025, -0.07), Vector2(-0.055, -0.02)]),
		0.13, Vector3(-0.16, 1.16, -0.19), tool_finish, 0.004)
	var spindle := _machine_cylinder(workspace, "CuttingSpindle", Vector3(-0.16, 1.06, -0.19),
		0.012, 0.04, Color("979a95"))
	spindle.material_override = steel_finish
	var mounting_points := [Vector3(-0.39, 0.82, 0.09), Vector3(0.07, 0.82, 0.09),
		Vector3(0.30, 0.805, -0.23), Vector3(0.40, 0.805, -0.23)]
	for index in range(mounting_points.size()):
		var bolt := MeshInstance3D.new()
		bolt.name = "BenchFastener%d" % index
		bolt.mesh = ProductionVisuals.fastener_head_mesh()
		bolt.material_override = steel_finish
		bolt.position = mounting_points[index]
		bolt.scale = Vector3.ONE * 0.5
		workspace.add_child(bolt)
	_pose_pod_canopy(1.0)

func _pose_pod_canopy(amount: float) -> void:
	var shell: Node3D = landing_pod_visual.get_node("OpenedPodShell")
	var canopy: Node3D = shell.get_node("CanopyPivot")
	canopy.rotation.x = PI * amount
	for side in [-1.0, 1.0]:
		var start := Vector3(side * 0.62, 0.28, 0.10)
		var end: Vector3 = canopy.transform * Vector3(side * 0.62, 0.25, -0.90)
		var strut: MeshInstance3D = shell.get_node(("Port" if side < 0.0 else "Starboard") + "CanopyStrut")
		strut.position = (start + end) * 0.5
		strut.basis = Basis.looking_at((end - start).normalized(), Vector3.RIGHT) * Basis(Vector3.RIGHT, PI / 2.0)
		strut.scale = Vector3(1.0, start.distance_to(end), 1.0)

func _sync_landing_pod_visual() -> void:
	if not state.has("landing_pod") or not state.has("fabrication_hub"):
		if landing_pod_visual != null:
			landing_pod_visual.free()
			landing_hub_visual.free()
			landing_pod_visual = null
			landing_hub_visual = null
			landing_hub_pick = null
		return
	var pod: Dictionary = state.landing_pod
	var hub: Dictionary = state.fabrication_hub
	if not pod.get("deployed", false):
		return
	if landing_pod_visual == null:
		_build_landing_pod_visual(pod, hub)
	var pod_center: Array = pod.center
	var pod_floor := Vector3(float(pod_center[0]) * PITCH,
		float(pod_center[1]) * Geometry.HEIGHT_STEP, float(pod_center[2]) * PITCH)
	if not arrival_reveal_active:
		landing_pod_visual.position = pod_floor
	var installed: bool = hub.get("installed", false)
	landing_hub_visual.visible = installed
	landing_hub_pick.collision_layer = Geometry.PICK_LAYER if installed else 0
	if installed and hub.has("position"):
		var position: Array = hub.position
		# Host positions use the shared spindle anchor; the bench art sits on its floor.
		landing_hub_visual.position = Vector3(float(position[0]), float(position[1]), float(position[2])) \
			- Vector3.UP * Geometry.ANCHOR_HEIGHT

func _maybe_start_arrival_reveal() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while is_inside_tree() and get_node_or_null("MachinePreviewWarmup") != null \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_inside_tree() or get_node_or_null("MachinePreviewWarmup") != null \
			or landing_pod_visual == null or landing_hub_visual == null:
		return
	arrival_reveal_pod_anchor = landing_pod_visual.position
	arrival_reveal_elapsed = 0.0
	_release_character_controls()
	arrival_reveal_active = true
	if character_presenter != null:
		character_presenter.visible = false
	if arrival_gameplay_canvas != null:
		arrival_gameplay_canvas.visible = false
	if arrival_reveal_canvas != null:
		arrival_reveal_canvas.visible = true
	if arrival_reveal_audio == null:
		arrival_reveal_audio = ArrivalRevealAudio.new()
		arrival_reveal_audio.name = "ArrivalRevealAudio"
		add_child(arrival_reveal_audio)
	arrival_reveal_audio.begin()
	_refresh_ui()
	_advance_arrival_reveal(0.0)

func _arrival_fold_amount() -> float:
	var phase := clampf((arrival_reveal_elapsed - 1.45) / 1.20, 0.0, 1.0)
	return phase * phase * (3.0 - 2.0 * phase)

func _pose_arrival_reveal() -> void:
	var descent := clampf(arrival_reveal_elapsed / 1.45, 0.0, 1.0)
	descent = descent * descent * (3.0 - 2.0 * descent)
	var fold := _arrival_fold_amount()
	landing_pod_visual.position = arrival_reveal_pod_anchor + Vector3.UP * (8.0 * (1.0 - descent))
	landing_pod_visual.rotation.y = 0.18 * (1.0 - descent)
	_pose_pod_canopy(smoothstep(0.0, 0.60, fold))
	var bench_fold := smoothstep(0.35, 1.0, fold)
	var workspace: Node3D = landing_hub_visual.get_node("FoldoutBench")
	workspace.position = (arrival_reveal_pod_anchor - landing_hub_visual.position) * (1.0 - bench_fold) \
		+ Vector3.UP * (0.5 * (1.0 - bench_fold))
	workspace.rotation.z = -PI * 0.5 * (1.0 - bench_fold)
	workspace.visible = bench_fold > 0.01
	landing_hub_visual.visible = bench_fold > 0.01 and state.get("fabrication_hub", {}).get("installed", false)
	if arrival_reveal_caption != null:
		arrival_reveal_caption.text = "SITE PACKAGE UNFOLDING" if arrival_reveal_elapsed >= 1.45 else "FIELD DESCENT IN PROGRESS"
	for panel in machine_root.get_children():
		if not panel.get_meta("arrival_deck_panel", false):
			continue
		var deck_panel := panel as Node3D
		var target: Vector3 = deck_panel.get_meta("arrival_deck_anchor")
		deck_panel.position = arrival_reveal_pod_anchor.lerp(target, fold)
		deck_panel.rotation = Vector3.ZERO
		deck_panel.scale = Vector3(0.22 + 0.78 * fold, 1.0, 0.22 + 0.78 * fold)
		deck_panel.visible = fold > 0.01
	_update_arrival_reveal_camera()
	if character_presenter != null and character_presenter.views.has(client):
		character_presenter.views[client].visible = false

func _update_arrival_reveal_camera() -> void:
	var phase := clampf(arrival_reveal_elapsed / ARRIVAL_REVEAL_SECONDS, 0.0, 1.0)
	phase = phase * phase * (3.0 - 2.0 * phase)
	var back := Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch))
	var settled_eye := focus + back * distance
	var approach_eye := arrival_reveal_pod_anchor + Vector3(7.0, 17.0, 17.0)
	camera.position = approach_eye.lerp(settled_eye, phase)
	var descent := clampf(arrival_reveal_elapsed / 1.45, 0.0, 1.0)
	var tracked := arrival_reveal_pod_anchor + Vector3.UP * (8.0 * (1.0 - descent) + 0.8)
	var release := smoothstep(0.72, 1.0, arrival_reveal_elapsed / ARRIVAL_REVEAL_SECONDS)
	camera.look_at(tracked.lerp(settled_eye - back, release))

func _advance_arrival_reveal(delta: float) -> void:
	if not arrival_reveal_active:
		return
	arrival_reveal_elapsed = minf(ARRIVAL_REVEAL_SECONDS, arrival_reveal_elapsed + maxf(delta, 0.0))
	_pose_arrival_reveal()
	if arrival_reveal_audio != null:
		arrival_reveal_audio.advance(arrival_reveal_elapsed)
	if arrival_reveal_elapsed >= ARRIVAL_REVEAL_SECONDS:
		_finish_arrival_reveal(false)

func _finish_arrival_reveal(skipped: bool = true) -> void:
	if not arrival_reveal_active:
		return
	if arrival_reveal_audio != null:
		arrival_reveal_audio.finish(skipped)
	_release_character_controls()
	arrival_reveal_elapsed = ARRIVAL_REVEAL_SECONDS
	_pose_arrival_reveal()
	arrival_reveal_active = false
	if character_presenter != null:
		character_presenter.visible = true
	if arrival_gameplay_canvas != null:
		arrival_gameplay_canvas.visible = true
	if arrival_reveal_canvas != null:
		arrival_reveal_canvas.visible = false
	_update_camera()
	_refresh_ui()

func _box(parent: Node, at: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = dimensions
	mesh.mesh = shape
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if color.a < 1:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _selection_outline() -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var outer := 0.77
	var inner := 0.73
	var strips := [
		[Vector2(-outer, -outer), Vector2(outer, -inner)],
		[Vector2(-outer, inner), Vector2(outer, outer)],
		[Vector2(-outer, -inner), Vector2(-inner, inner)],
		[Vector2(inner, -inner), Vector2(outer, inner)]]
	for strip in strips:
		var low: Vector2 = strip[0]
		var high: Vector2 = strip[1]
		var first := vertices.size()
		vertices.append_array(PackedVector3Array([
			Vector3(low.x, 0, low.y), Vector3(high.x, 0, low.y),
			Vector3(high.x, 0, high.y), Vector3(low.x, 0, high.y)]))
		indices.append_array(PackedInt32Array([first, first + 2, first + 1,
			first, first + 3, first + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var outline := ArrayMesh.new()
	outline.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	marker.mesh = outline
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b98b3d")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	return marker

func _cylinder(parent: Node, at: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 16
	mesh.mesh = shape
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _text(parent: Node, words: String, at: Vector3, color: Color, pixel_size: float = 0.007) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.position = at
	label.font_size = 36
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

func _bar(parent: Node, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	if a.distance_to(b) < 0.01:
		return
	var bar := _box(parent, (a + b) / 2, Vector3(width, width, a.distance_to(b)), color)
	# Both endpoints are local to the parent. A vertical shaft needs a
	# noncollinear up vector, and its orientation must not depend on the tree.
	var direction := (b - a).normalized()
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	bar.basis = Basis.looking_at(direction, up)

func _route_segment(parent: Node3D, part_name: String, a: Vector3, b: Vector3,
		width: float, color: Color) -> MeshInstance3D:
	var offset := b - a
	var part := _box(parent, (a + b) / 2.0, Vector3(width, width, offset.length()), color)
	part.name = part_name
	# Material routes join equal-height grid anchors. Local rotation keeps this
	# mesh construction independent of a camera or an attached scene tree.
	part.rotation.y = atan2(offset.x, offset.z)
	return part

func _material_route(parent: Node3D, a: Vector3, b: Vector3) -> Node3D:
	var route := Node3D.new()
	route.name = "MaterialRoute"
	parent.add_child(route)
	if a.distance_to(b) < 0.01:
		return route
	var direction := (b - a).normalized()
	var start := a + direction * 0.55 + Vector3.UP * 0.45
	var finish := b - direction * 0.55 + Vector3.UP * 0.45
	if _native_transmission() and ProductionFeedSleeveArt.mount(route, start, finish):
		return route
	_route_segment(route, "Rail", start, finish, 0.17, Color("929e91"))
	var side := Vector3(-direction.z, 0, direction.x)
	var tip := start.lerp(finish, 0.7) + Vector3.UP * 0.115
	_route_segment(route, "ArrowLeft", tip - direction * 0.15 + side * 0.1, tip,
		0.035, Color("e2c48b"))
	_route_segment(route, "ArrowRight", tip - direction * 0.15 - side * 0.1, tip,
		0.035, Color("e2c48b"))
	return route

func _machine_box(parent: Node3D, part_name: String, at: Vector3, dimensions: Vector3,
		color: Color, metal: float = 0.08, roughness: float = 0.5) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = ProductionVisuals.box_mesh(dimensions)
	part.position = at
	part.name = part_name
	part.material_override = ProductionVisuals.material(color, metal, roughness)
	parent.add_child(part)
	return part

func _machine_cylinder(parent: Node3D, part_name: String, at: Vector3, radius: float,
		height: float, color: Color, orientation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = at
	part.rotation = orientation
	part.mesh = ProductionVisuals.cylinder_mesh(radius, height)
	part.material_override = ProductionVisuals.material(color, 0.85, 0.4)
	parent.add_child(part)
	return part

func _machine_axis(entity: Dictionary) -> Vector3:
	# Native projections use the Host's X/Y/Z enumeration. Older projections
	# without an axis retain the original X default.
	return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][int(entity.get("axis", 0))]

func _spindle_rotation(axis: Vector3) -> Vector3:
	if axis == Vector3.UP:
		return Vector3.ZERO
	return Vector3(0, 0, PI / 2) if axis == Vector3.RIGHT else Vector3(PI / 2, 0, 0)

func _machine_drive_stub(anchor: Node3D, entity: Dictionary, press_input: bool = false,
		collector_input: bool = false) -> void:
	if state.get("options", {}).get("native", false):
		var axis := _machine_axis(entity)
		# The vertical stub stays above the base inside the same pick envelope.
		var height := 0.9 if axis == Vector3.UP else 1.35
		var journal := MeshInstance3D.new()
		journal.name = "DriveStub"
		journal.position = Vector3(0, Geometry.ANCHOR_HEIGHT, 0)
		journal.rotation = _spindle_rotation(axis)
		var horizontal_press := press_input and axis != Vector3.UP
		var horizontal_collector := collector_input and axis != Vector3.UP
		journal.mesh = ProductionDriveJournalArt.press_mesh() if horizontal_press or horizontal_collector else ProductionDriveJournalArt.mesh(height)
		journal.material_override = ProductionDriveJournalArt.material()
		anchor.add_child(journal)
		if horizontal_press:
			ProductionDriveJournalArt.mount_press_bearings(anchor, axis)
		if horizontal_collector:
			ProductionDriveJournalArt.mount_collector_bearings(anchor, axis)
	else:
		_machine_cylinder(anchor, "DriveStub", Vector3(0, 0.35, 0.55), 0.085, 0.18,
			Color("b87945"), Vector3(PI / 2, 0, 0))

func _machine_turned(parent: Node3D, part_name: String, at: Vector3,
		profile: PackedVector2Array, color: Color, axis: Vector3 = Vector3.UP) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = at
	part.basis = Basis(Quaternion(Vector3.UP, axis))
	part.mesh = ProductionVisuals.turned_mesh(profile)
	part.material_override = ProductionVisuals.material(color, 0.85, 0.38)
	part.set_meta("detail_role", part_name)
	parent.add_child(part)
	return part

func _machine_fastener(parent: Node3D, part_name: String, at: Vector3, normal: Vector3 = Vector3.UP) -> void:
	var assembly := Node3D.new()
	assembly.name = part_name
	assembly.position = at
	assembly.basis = Basis(Quaternion(Vector3.UP, normal))
	assembly.set_meta("surface_detail", true)
	assembly.set_meta("detail_role", part_name)
	parent.add_child(assembly)
	_machine_turned(assembly, "Washer", Vector3.ZERO, PackedVector2Array([
		Vector2(0, 0), Vector2(0.038, 0), Vector2(0.043, 0.002),
		Vector2(0.043, 0.004), Vector2(0.038, 0.006), Vector2(0, 0.006)]), Color("778b8c"))
	var head := MeshInstance3D.new()
	head.name = "HexHead"
	head.position.y = 0.018
	head.mesh = ProductionVisuals.fastener_head_mesh()
	head.material_override = ProductionVisuals.material(Color("b8c3bb"), 0.85, 0.38)
	assembly.add_child(head)
	_machine_box(assembly, "HeadSlot", Vector3(0, 0.03, 0), Vector3(0.03, 0.002, 0.006), Color("28383d"), 0.1, 0.8)

func _machine_surface_detail(machine: Node3D, kind: String) -> void:
	var anchor := Node3D.new()
	anchor.name = "SurfaceDetail"
	machine.add_child(anchor)
	for x in [-0.55, 0.55]:
		for z in [-0.55, 0.55]:
			_machine_fastener(anchor, "FoundationFastener", Vector3(x, 0.24, z))
	match kind:
		"collector":
			var frame: Color = COLORS.collector
			if _native_transmission():
				ProductionCollectorServiceArt.mount(anchor, frame)
			_machine_box(anchor, "ServiceCover", Vector3(-0.22, 0.68, -0.35), Vector3(0.65, 0.5, 0.035), frame.darkened(0.14))
			for n in range(5):
				var vent := _machine_box(anchor, "ServiceVent", Vector3(-0.22, 0.55 + n * 0.06, -0.326), Vector3(0.42, 0.014, 0.006), Color("28383d"), 0.1, 0.8)
				vent.set_meta("detail_role", "ServiceVent")
			for x in [-0.48, 0.04]:
				for y in [0.49, 0.87]:
					_machine_fastener(anchor, "ServiceFastener", Vector3(x, y, -0.32), Vector3.BACK)
			for n in range(8):
				var angle := float(n) * TAU / 8.0
				var tooth := _machine_box(anchor, "CutterFlute",
					Vector3(-0.22 + cos(angle) * 0.235, 1.1 + sin(angle) * 0.235, -0.19),
					Vector3(0.04, 0.045, 0.29), Color("a6b4af"), 0.85, 0.32)
				tooth.rotation.z = angle - PI / 2.0
				tooth.set_meta("detail_role", "CutterFlute")
				if _native_transmission():
					ProductionCollectorToolingArt.mount_flute(tooth)
		"belt":
			if not machine.get_meta("conveyor_frame", false):
				var profile := PackedVector2Array([Vector2(0, -0.025), Vector2(0.11, -0.025),
					Vector2(0.135, -0.015), Vector2(0.135, 0.015), Vector2(0.11, 0.025), Vector2(0, 0.025)])
				for x in [-0.57, 0.57]:
					for side in [-1.0, 1.0]:
						_machine_turned(anchor, "RollerBearing", Vector3(x, 0.465, side * 0.405), profile, Color("778b8c"), Vector3.BACK)
						_machine_fastener(anchor, "BearingFastener", Vector3(x, 0.465, side * 0.435), Vector3.BACK * side)
		"processor":
			var profile := PackedVector2Array([Vector2(0, -0.02), Vector2(0.052, -0.02),
				Vector2(0.065, -0.01), Vector2(0.065, 0.01), Vector2(0.052, 0.02), Vector2(0, 0.02)])
			for x in [-0.34, 0.34]:
				for y in [0.82, 1.32]:
					_machine_turned(anchor, "GuideCollar", Vector3(x, y, -0.19), profile, Color("778b8c"))
			if ProductionPressArt.source_status != "ready":
				for x in [-0.48, 0.48]:
					_machine_box(anchor, "FrameJoint", Vector3(x, 0.46, -0.215), Vector3(0.23, 0.17, 0.035), COLORS.processor.darkened(0.14))
					for y in [0.41, 0.51]:
						_machine_fastener(anchor, "FrameFastener", Vector3(x, y, -0.19), Vector3.BACK)

func _collector_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame: Color = COLORS.collector
	var steel := Color("a6b4af")
	_machine_box(anchor, "StockBed", Vector3(0, 0.51, 0), Vector3(1.25, 0.1, 0.67), steel, 0.85, 0.45)
	ProductionCollectorArt.mount(anchor, frame)
	var drum := _machine_cylinder(anchor, "CutterDrum", Vector3(-0.22, 1.1, -0.19), 0.24, 0.34,
		Color("465a60"), Vector3(PI / 2, 0, 0))
	var hub := _machine_cylinder(anchor, "CutterHub", Vector3(-0.22, 1.1, 0.01), 0.085, 0.08,
		steel, Vector3(PI / 2, 0, 0))
	if _native_transmission():
		ProductionCollectorToolingArt.mount_body(drum, hub)
		var intake_result: Dictionary = Geometry.collector_intake_boxes(entity)
		if not intake_result.get("accepted", false):
			push_error("The confirmed collector lacks an admitted source-facing intake.")
		elif intake_result.boxes.size() == 1:
			var pickup: Dictionary = intake_result.boxes[0]
			var local_at: Vector3 = pickup.center - anchor.position
			# The open scoop uses the full confirmed pickup box. Its floor meets
			# the rock while the cheeks expose the teeth and lead into the trough.
			_machine_box(anchor, "SourcePickupHousing", local_at + Vector3(0.10, 0, 0),
				Vector3(0.08, 0.20, 0.24), Color("465a60"), 0.85, 0.35)
			_machine_box(anchor, "SourcePickupFloor", local_at + Vector3(0, -0.07, 0),
				Vector3(0.28, 0.045, 0.17), steel, 0.85, 0.42)
			for side in [-1.0, 1.0]:
				_machine_box(anchor, "SourcePickupCheekLeft" if side < 0.0 else "SourcePickupCheekRight",
					local_at + Vector3(-0.02, 0, side * 0.1025),
					Vector3(0.24, 0.20, 0.035), Color("465a60"), 0.85, 0.35)
			for tooth_index in range(3):
				_machine_box(anchor, "SourcePickupTooth%d" % tooth_index,
					local_at + Vector3(-0.105, 0, (tooth_index - 1) * 0.075),
					Vector3(0.06, 0.12, 0.028), steel, 0.85, 0.32)
			var start := Vector3(-0.74, 0.57, local_at.z)
			var finish := Vector3(-0.15, 0.57, 0)
			var delta := finish - start
			var trough := _machine_box(anchor, "SourceGatheringTrough", (start + finish) * 0.5,
				Vector3(delta.length(), 0.045, 0.10), steel, 0.85, 0.45)
			trough.rotation.y = -atan2(delta.z, delta.x)
		elif intake_result.boxes.size() == 9:
			var pickup: Dictionary = intake_result.boxes[0]
			var carrier: Dictionary = intake_result.carrier
			var head: Dictionary = intake_result.head
			var shoe_at: Vector3 = pickup.center - anchor.position
			var carrier_at: Vector3 = carrier.center - anchor.position
			var head_at: Vector3 = head.center - anchor.position
			_machine_box(anchor, "SourceLiftPickup", shoe_at + Vector3(0.04, 0, 0),
				Vector3(0.25, 0.17, 0.35), Color("465a60"), 0.85, 0.35)
			for tooth_index in range(3):
				_machine_box(anchor, "SourceLiftPickupTooth%d" % tooth_index,
					shoe_at + Vector3(-0.13, -0.01, (tooth_index - 1) * 0.12),
					Vector3(0.07, 0.11, 0.035), steel, 0.85, 0.32)
			for index in range(2):
				var guide: Dictionary = intake_result.boxes[index + 1]
				_machine_box(anchor, "SourceLiftGuideLeft" if index == 0 else "SourceLiftGuideRight",
					guide.center - anchor.position, guide.size, frame, 0.8, 0.45)
			var carrier_mesh := ProductionVisuals.prism_mesh(PackedVector2Array([
				Vector2(-0.125, 0.0), Vector2(0.125, 0.0),
				Vector2(0.125, 0.105), Vector2(0.095, 0.105),
				Vector2(0.095, 0.032), Vector2(-0.10, 0.032),
				Vector2(-0.10, 0.055), Vector2(-0.125, 0.055)]), 0.27, 0.002)
			var carrier_finish := ProductionTransmissionFinish.material("worked",
				Color("b1a184"), 0.82, 0.42)
			for index in range(5):
				var flight: Dictionary = intake_result.boxes[index + 3]
				var step := _machine_box(anchor, "SourceLiftFlight%d" % index,
					flight.center - anchor.position - Vector3.UP * Geometry.COLLECTOR_LIFT_PROFILE.flight_raise_y,
					Vector3(flight.size.x, 0.035, flight.size.z), steel, 0.78, 0.42)
				# The formed carrier is inside the same native occupied flight. It
				# stays empty; actual inventory never becomes a decorative ore prop.
				var bucket := MeshInstance3D.new()
				bucket.name = "SourceLiftBucket"
				bucket.mesh = carrier_mesh
				bucket.position.y = 0.018
				bucket.material_override = carrier_finish
				step.add_child(bucket)
				for side in [-1.0, 1.0]:
					_machine_box(step, "SourceLiftBucketCheek", Vector3(0, 0.07, side * 0.138),
						Vector3(0.25, 0.095, 0.024), frame, 0.78, 0.45)
			var start := Vector3(carrier_at.x + 0.03, head_at.y, carrier_at.z)
			var finish := Vector3(0.48, 1.28, 0.28)
			var delta := finish - start
			var discharge := _machine_box(anchor, "SourceLiftDischarge", (start + finish) * 0.5,
				Vector3(delta.length(), 0.07, 0.24), Color("b18a43"), 0.78, 0.46)
			discharge.basis = Basis(Quaternion(Vector3.RIGHT, delta.normalized()))
			var cross := Vector3(-delta.z, 0, delta.x).normalized()
			for side in [-1.0, 1.0]:
				var guard := _machine_box(anchor, "SourceLiftHeadGuardLeft" if side < 0.0 else "SourceLiftHeadGuardRight",
					(start + finish) * 0.5 +
					Vector3(0, 0.10, 0) + cross * side * 0.12,
					Vector3(delta.length(), 0.16, 0.03), frame, 0.8, 0.42)
				guard.basis = discharge.basis
			_machine_box(anchor, "SourceLiftTransferHopper", finish + Vector3(0.03, -0.10, 0),
				Vector3(0.33, 0.20, 0.36), frame, 0.78, 0.48)
			var drop_start := finish + Vector3(0.03, -0.12, 0)
			var stock_entry := Vector3(0.46, 0.65, 0.28)
			var drop_delta := stock_entry - drop_start
			var downspout := _machine_box(anchor, "SourceLiftDownspout",
				(drop_start + stock_entry) * 0.5,
				Vector3(drop_delta.length(), 0.17, 0.18), steel, 0.83, 0.40)
			downspout.basis = Basis(Quaternion(Vector3.RIGHT, drop_delta.normalized()))
	if not (_native_transmission() and ProductionCollectorFeedArt.mount(anchor, frame)):
		for z in [-0.37, 0.37]:
			_machine_box(anchor, "StockGuide", Vector3(0.05, 0.6, z), Vector3(1.15, 0.08, 0.06), frame)
	_machine_drive_stub(anchor, entity, false, true)

func _belt_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame: Color = COLORS.belt
	# The sourced cast coating is brighter than the legacy flat tint. Keep the
	# finished frame in the same restrained steel palette as nearby machines.
	var fitted_frame := Color("49666a")
	var fitted := _native_transmission() and ProductionConveyorFrameArt.mount(anchor, fitted_frame, int(entity.get("axis", 0)))
	if not fitted:
		for x in [-0.52, 0.52]:
			for z in [-0.36, 0.36]:
				var leg := _machine_box(anchor, "ConveyorLeg", Vector3(x, 0.315, z), Vector3(0.09, 0.21, 0.06), frame)
				leg.set_meta("detail_role", "ConveyorLeg")
	ProductionConveyorArt.mount(anchor)
	if not fitted:
		for z in [-0.36, 0.36]:
			_machine_box(anchor, "ConveyorRail", Vector3(0, 0.57, z), Vector3(1.38, 0.08, 0.05), frame)
			var channel := _machine_box(anchor, "ConveyorChannel", Vector3(0, 0.43, z), Vector3(1.34, 0.08, 0.05), frame)
			channel.set_meta("detail_role", "ConveyorChannel")
	var roller_profile := PackedVector2Array([Vector2(0, -0.35), Vector2(0.055, -0.35),
		Vector2(0.06, -0.345), Vector2(0.06, -0.305), Vector2(0.077, -0.3),
		Vector2(0.077, 0.3), Vector2(0.06, 0.305), Vector2(0.06, 0.345),
		Vector2(0.055, 0.35), Vector2(0, 0.35)])
	for x in [-0.57, 0.57]:
		_machine_turned(anchor, "ConveyorRoller", Vector3(x, 0.465, 0), roller_profile, Color("a6b4af"), Vector3.BACK)
	if not (fitted and ProductionConveyorHubArt.mount(anchor, _machine_axis(entity), fitted_frame)):
		_machine_drive_stub(anchor, entity)

func _press_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame: Color = COLORS.processor
	var steel := Color("a6b4af")
	var dark := Color("29393f")
	var sourced := ProductionPressArt.mount(anchor)
	if sourced:
		frame = Color("58634c")
	else:
		for x in [-0.48, 0.48]:
			_machine_box(anchor, "PressUpright", Vector3(x, 0.82, -0.38), Vector3(0.15, 1.24, 0.28), frame)
	var fitted_crown := sourced and _native_transmission() and ProductionPressCrownArt.mount(anchor, frame)
	if not fitted_crown:
		_machine_box(anchor, "PressBridge", Vector3(0, 1.5, -0.3), Vector3(1.2, 0.2, 0.36), frame, 0.05 if sourced else 0.08)
	else:
		ProductionPressRearFrameArt.mount(anchor, frame)
	var anvil := _machine_box(anchor, "Anvil", Vector3(0, 0.46, 0.05), Vector3(0.7, 0.16, 0.63), dark)
	var head := _machine_box(anchor, "ToolHead", Vector3(0, 0.84, 0), Vector3(0.56, 0.17, 0.55), steel, 0.85, 0.32)
	if _native_transmission():
		ProductionPressDieArt.mount(anchor, anvil, head)
	_machine_cylinder(anchor, "Piston", Vector3(0, 1.14, -0.08), 0.075, 0.45, steel)
	for x in [-0.34, 0.34]:
		_machine_cylinder(anchor, "ToolGuide", Vector3(x, 1.06, -0.19), 0.04, 0.6, Color("b87945"))
	var tray := _machine_box(anchor, "OutputTray", Vector3(0.46, 0.33, 0.15), Vector3(0.48, 0.05, 0.58), Color("aaa993"), 0.85, 0.5)
	if _native_transmission():
		ProductionPressTrayArt.mount(anchor, tray)
	_machine_drive_stub(anchor, entity, true)
	for x in [-0.48, 0.48]:
		_machine_cylinder(anchor, "BridgeBolt", Vector3(x, 1.5, -0.1075), 0.035, 0.025,
			steel, Vector3(PI / 2, 0, 0))

func _wheel_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame := Color("465a60")
	var wood := Color("b48c52")
	var native_profile: bool = state.get("options", {}).get("native", false)
	var scale_factor: float = Geometry.ANCHOR_HEIGHT / 0.78 if native_profile else 1.0
	var axis := _machine_axis(entity) if native_profile else Vector3.BACK
	var bearing_rotation := _spindle_rotation(axis)
	if native_profile and ProductionWheelArt.resource_status() == "complete":
		# Preserve the bearing width while raising the shared mechanical center.
		ProductionWheelSupportArt.mount(anchor, axis, 0.5 / 0.78, scale_factor)
	elif native_profile and axis == Vector3.UP:
		# Fixed historical rosters retain the support fitted to their old rim.
		_machine_box(anchor, "WheelStand", Vector3(0, 0.27, 0), Vector3(0.24, 0.3, 0.24), frame)
		_machine_cylinder(anchor, "AxleBearing", Vector3.UP * (Geometry.ANCHOR_HEIGHT - 0.25 * scale_factor),
			0.145 * scale_factor, 0.18 * scale_factor, Color("a6b4af"), bearing_rotation)
	else:
		for side in [-1.0, 1.0]:
			var offset: Vector3 = axis * float(side) * 0.42 * scale_factor
			_machine_box(anchor, "WheelStand", offset + Vector3.UP * 0.51 * scale_factor,
				Vector3(0.16, 0.54, 0.16) * scale_factor, frame)
			_machine_cylinder(anchor, "AxleBearing", offset + Vector3.UP * 0.78 * scale_factor,
				0.145 * scale_factor, 0.18 * scale_factor, Color("a6b4af"), bearing_rotation)
	if native_profile and entity.has("supports"):
		if ProductionWheelPierArt.mount(anchor, entity):
			for child in anchor.get_children():
				if child is MeshInstance3D and child.get_meta("wheel_support_role", "") == "WheelStand":
					child.visible = false
		else:
			push_error("The native wheel support projection is invalid.")
	wheel_rotor = Node3D.new()
	wheel_rotor.name = "WheelRotor"
	wheel_rotor.position = Vector3.UP * (Geometry.ANCHOR_HEIGHT if native_profile else 0.78)
	# Paddle tips use a 0.70-unit source radius. The larger rotor reaches the
	# water while its center stays at the common machine spindle height.
	var rotor_scale := Geometry.WATERWHEEL_RADIUS / 0.70 if native_profile else scale_factor
	var radial_scale := rotor_scale * int(entity.get("tiles", 3)) if native_profile else rotor_scale
	wheel_rotor.scale = Vector3(radial_scale, radial_scale, rotor_scale)
	if native_profile and axis == Vector3.RIGHT:
		wheel_rotor.rotation.y = PI / 2
	elif native_profile and axis == Vector3.UP:
		wheel_rotor.rotation.x = -PI / 2
	anchor.add_child(wheel_rotor)
	var sourced := ProductionWheelArt.mount(wheel_rotor, int(entity.get("tiles", 3)) if native_profile else 3)
	wheel_rotor.set_meta("visual_batch_key", [native_profile, int(entity.get("tiles", 3)), sourced])
	if not sourced:
		var rim_profile := PackedVector2Array([
			Vector2(0.51, -0.022), Vector2(0.518, -0.03), Vector2(0.582, -0.03),
			Vector2(0.59, -0.022), Vector2(0.59, 0.022), Vector2(0.582, 0.03),
			Vector2(0.518, 0.03), Vector2(0.51, 0.022), Vector2(0.51, -0.022)])
		for z in [-0.15, 0.15]:
			_machine_turned(wheel_rotor, "WheelRim", Vector3(0, 0, z), rim_profile, frame, Vector3.BACK)
			for n in range(12):
				var angle := float(n) * TAU / 12.0
				_machine_fastener(wheel_rotor, "RimFastener",
					Vector3(cos(angle) * 0.55, sin(angle) * 0.55, z + signf(z) * 0.03), Vector3.BACK * signf(z))
	# An open rim exposes the spokes. Meshes never supply drive relationships.
	for n in range(12):
		var angle := n * TAU / 12.0
		if not ProductionPaddleArt.mount(wheel_rotor, angle, n, wheel_rotor.scale if native_profile else Vector3.ONE):
			# Historical fixed rosters retain their exact earlier block paddles.
			var radial := Vector3(cos(angle), sin(angle), 0)
			var paddle := _machine_box(wheel_rotor, "WheelPaddle", radial * 0.62,
				Vector3(0.14, 0.16, 0.28), wood, 0.05, 0.88)
			paddle.rotation.z = angle
	if not sourced:
		for n in range(3):
			var spoke := _machine_box(wheel_rotor, "WheelSpoke", Vector3.ZERO,
				Vector3(0.065, 1.0, 0.085), wood, 0.05, 0.88)
			spoke.rotation.z = n * PI / 3.0
	var journal := _machine_cylinder(wheel_rotor, "WheelHub", Vector3.ZERO, 0.13, 0.45,
		Color("b87945"), Vector3(PI / 2, 0, 0))
	if native_profile:
		# Bake the fitted journal in metres, then cancel the rotor's scale.
		# Its local worked-metal repeat stays physical as the rim grows.
		journal.mesh = ProductionDriveJournalArt.mesh(0.45 * rotor_scale, 0.13 * 0.5 / 0.78)
		journal.material_override = ProductionDriveJournalArt.material()
		journal.scale = Vector3(1.0 / radial_scale, 1.0 / rotor_scale, 1.0 / radial_scale)

func _material_rotated(_entity_id: String, entity: Dictionary) -> bool:
	return _native_transmission() and entity.get("kind") == "belt" and int(entity.get("axis", 2)) == 0

func _assemble_machine(anchor: Node3D, entity: Dictionary, rotated := false) -> void:
	anchor.set_meta("material_rotated", rotated)
	var facing: int = int(entity.get("rotation", 0)) if _native_transmission() and entity.kind in ["collector", "processor"] else 0
	if facing != 0 and entity.kind != "collector":
		var visual := Node3D.new()
		visual.name = "RotatedMachineVisual"
		visual.rotation.y = -float(facing) * PI / 2.0
		anchor.add_child(visual)
		var local_entity := entity.duplicate()
		local_entity["rotation"] = 0
		if facing % 2 == 1 and int(entity.get("axis", 0)) != 1:
			local_entity["axis"] = 2 - int(entity.get("axis", 0))
		_assemble_machine(visual, local_entity)
		return
	if rotated:
		var visual := Node3D.new()
		visual.name = "RotatedMachineVisual"
		visual.rotation.y = -PI / 2.0
		anchor.add_child(visual)
		var local_entity := entity.duplicate()
		if int(entity.get("axis", 0)) == 0:
			local_entity["axis"] = 2
		elif int(entity.get("axis", 0)) == 2:
			local_entity["axis"] = 0
		_assemble_machine(visual, local_entity)
		return
	var water_wheel: bool = entity.kind == "wheel" and _native_transmission()
	if not water_wheel:
		var plinth := MeshInstance3D.new()
		plinth.name = "Plinth"
		plinth.position = Vector3(0, 0.12, 0)
		plinth.mesh = ProductionSkidArt.skid_mesh()
		plinth.material_override = ProductionVisuals.material(Color("273c41"), 0.08, 0.5)
		plinth.set_meta("asset_role", "MachineSupportSkid")
		anchor.add_child(plinth)
	match entity.kind:
		"collector":
			_collector_visual(anchor, entity)
			if _native_transmission():
				ProductionCollectorOutputArt.mount(anchor, facing)
		"belt": _belt_visual(anchor, entity)
		"processor": _press_visual(anchor, entity)
		"wheel": _wheel_visual(anchor, entity)
	if not water_wheel:
		_machine_surface_detail(anchor, entity.kind)

func _prime_machine_visuals() -> void:
	# Build once during opening setup so the first tool selection can reuse
	# imported textures, procedural meshes, and their Godot render resources.
	var previous_rotor := wheel_rotor
	for kind in ["collector", "belt", "processor", "wheel"]:
		var anchor := Node3D.new()
		var cell := [0, 1] if kind == "collector" else [1, 2]
		anchor.position = _cell_position(cell)
		_assemble_machine(anchor, {"kind": kind, "axis": 0, "tiles": 3,
			"rotation": 0, "cell": cell, "level": 0})
		anchor.free()
	wheel_rotor = previous_rotor

func _collector_preview_source_path(cell: Vector2i, level: int) -> String:
	return "res://opening/assets/prebuilt-preview-collector-source-%d-%d.scn" % [cell.y, level]

func _prefetch_machine_preview_variants() -> void:
	# Load during the arrival reveal, after the workshop cover is gone. Spread
	# requests over frames; no variant is built on the selection frame.
	var paths: Array[String] = []
	for site in [0, 1]:
		for level in [0, 4, 8]:
			paths.append(_collector_preview_source_path(Vector2i(0, site), level))
	for axis in [1, 2]:
		paths.append("res://opening/assets/prebuilt-preview-processor-drive-%d.scn" % axis)
		paths.append("res://opening/assets/prebuilt-preview-belt-axis-%d.scn" % axis)
	for axis in [1, 2]:
		paths.append("res://opening/assets/prebuilt-preview-wheel-support-%d.scn" % axis)
	for tiles in range(4, BAKED_WHEEL_PREVIEW_MAX_TILES + 1):
		paths.append("res://opening/assets/prebuilt-preview-wheel-rotor-%d.scn" % tiles)
	preview_prefetch_complete = false
	for index in paths.size():
		if not is_inside_tree():
			return
		var path: String = paths[index]
		if ResourceLoader.load_threaded_request(path) == OK:
			preview_prefetch_paths.append(path)
		else:
			push_error("Cannot prepare a machine preview resource: " + path)
		if index % 4 == 3:
			await get_tree().process_frame
	call_deferred("_finish_machine_preview_prefetch")

func _finish_machine_preview_prefetch() -> void:
	while is_inside_tree() and not preview_prefetch_paths.is_empty():
		var remaining: Array[String] = []
		for path in preview_prefetch_paths:
			if packed_preview_templates.has(path):
				continue
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				remaining.append(path)
			elif status == ResourceLoader.THREAD_LOAD_LOADED:
				packed_preview_templates[path] = ResourceLoader.load_threaded_get(path)
			else:
				push_error("Cannot load a machine preview resource: " + path)
		preview_prefetch_paths = remaining
		if not preview_prefetch_paths.is_empty():
			await get_tree().process_frame
	if is_inside_tree():
		# Prime the shared mesh and UV caches during the arrival reveal. Later
		# wheel sizes use the same loaded source art and stay off the cold path.
		var large_wheel := _packed_machine_preview_variant("wheel", 2, 10, 0, Vector2i(1, 2), 4)
		if large_wheel != null:
			large_wheel.free()
		else:
			push_error("Cannot prepare the large-wheel preview geometry.")
	preview_prefetch_complete = preview_prefetch_paths.is_empty()

func _packed_preview_resource(path: String) -> PackedScene:
	if packed_preview_templates.has(path):
		return packed_preview_templates[path]
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		preview_variant_pending = true
		return null
	var packed := (ResourceLoader.load_threaded_get(path) if status == ResourceLoader.THREAD_LOAD_LOADED
		else load(path)) as PackedScene
	if packed != null:
		packed_preview_templates[path] = packed
	return packed

func _clear_preview_owners(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_preview_owners(child)

func _replace_preview_parts(anchor: Node3D, replacement: PackedScene, prefixes: Array[String]) -> void:
	var first := -1
	for child in anchor.get_children():
		var replace := false
		for prefix in prefixes:
			if child.name.begins_with(prefix):
				replace = true
				break
		if replace:
			if first < 0:
				first = child.get_index()
			child.free()
	var prepared := replacement.instantiate() as Node3D
	for child in prepared.get_children():
		_clear_preview_owners(child)
		prepared.remove_child(child)
		anchor.add_child(child)
		if first >= 0:
			anchor.move_child(child, first)
			first += 1
	prepared.free()

func _rotate_packed_preview_port(anchor: Node3D, facing: int) -> void:
	if facing == 0:
		return
	var turn := Transform3D(Basis(Vector3.UP, -float(facing) * PI / 2.0), Vector3.ZERO)
	for child in anchor.get_children():
		if child.name.begins_with("PortArrow") or child.name == "MaterialPortLabel":
			child.transform = turn * child.transform
			if child.name == "MaterialPortLabel":
				child.set_meta("port_side", turn.basis * child.get_meta("port_side", Vector3.ZERO))

func _resize_packed_wheel_rotor(rotor: Node3D, tiles: int) -> void:
	# The packed three-tile wheel already owns its materials and paddle nodes.
	# Reuse them rather than preparing GLTF and textures on the click frame.
	var rim := rotor.get_node("SourcedTimberRimN") as MeshInstance3D
	var centre := rotor.get_node("SourcedTimberRotor") as MeshInstance3D
	var sized_rim := ProductionWheelArt._sized_mesh(rim.mesh as ArrayMesh, tiles, true)
	var sized_centre := ProductionWheelArt._sized_mesh(centre.mesh as ArrayMesh, tiles, false)
	var rotor_scale := Geometry.WATERWHEEL_RADIUS / 0.70
	var radial_scale := rotor_scale * tiles
	var physical_scale := Vector3(radial_scale, radial_scale, rotor_scale)
	rotor.scale = physical_scale
	centre.mesh = sized_centre
	rim.mesh = sized_rim
	(rotor.get_node("SourcedTimberRimP") as MeshInstance3D).mesh = sized_rim
	(rotor.get_node("WheelHub") as MeshInstance3D).scale = Vector3(
		1.0 / radial_scale, 1.0 / rotor_scale, 1.0 / radial_scale)
	for child in rotor.get_children():
		if not child is MeshInstance3D or child.get_meta("detail_role", "") != "WheelPaddle":
			continue
		var blade := child as MeshInstance3D
		blade.mesh = ProductionPaddleArt.timber_mesh(Vector3(0.14, 0.018, 0.28), physical_scale)
		for part in blade.get_children():
			if not part is MeshInstance3D:
				continue
			match part.get_meta("detail_role", ""):
				"PaddleRootCleat":
					part.mesh = ProductionPaddleArt.timber_mesh(Vector3(0.04, 0.06, 0.10), physical_scale)
				"PaddleEdgeRib":
					part.mesh = ProductionPaddleArt.timber_mesh(Vector3(0.12, 0.038, 0.018), physical_scale)
				"PaddleWearStrip":
					part.position.y = 0.009 + 0.004 / physical_scale.y
					part.scale = Vector3(1.0 / physical_scale.x, 1.0 / physical_scale.y, 1.0)
				"PaddleBolt":
					part.position.y = -0.036 - 0.005 / physical_scale.y
					part.scale = Vector3.ONE / physical_scale
	rotor.set_meta("visual_batch_key", [true, tiles, true])

func _packed_machine_preview_variant(kind: String, axis: int, tiles: int,
		facing: int, cell: Vector2i, level: int) -> Node3D:
	preview_variant_pending = false
	if not _native_transmission():
		return null
	if kind == "wheel":
		var default_wheel: PackedScene = packed_preview_templates.get("wheel")
		if default_wheel == null:
			default_wheel = load("res://opening/assets/prebuilt-preview-wheel.scn") as PackedScene
		if default_wheel == null:
			return null
		var support_part: PackedScene
		if axis != 0:
			support_part = _packed_preview_resource(
				"res://opening/assets/prebuilt-preview-wheel-support-%d.scn" % axis)
			if support_part == null:
				return null
		var rotor_part: PackedScene
		if tiles != 3 and tiles <= BAKED_WHEEL_PREVIEW_MAX_TILES:
			rotor_part = _packed_preview_resource(
				"res://opening/assets/prebuilt-preview-wheel-rotor-%d.scn" % tiles)
			if rotor_part == null:
				return null
		var wheel := default_wheel.instantiate() as Node3D
		if support_part != null:
			for child in wheel.get_children():
				if child.name != "WheelRotor":
					child.free()
			var prepared := support_part.instantiate() as Node3D
			for child in prepared.get_children():
				_clear_preview_owners(child)
				prepared.remove_child(child)
				wheel.add_child(child)
				wheel.move_child(child, wheel.get_node("WheelRotor").get_index())
			prepared.free()
		if rotor_part != null:
			_replace_preview_parts(wheel, rotor_part, ["WheelRotor"])
		var rotor := wheel.get_node("WheelRotor") as Node3D
		if tiles > BAKED_WHEEL_PREVIEW_MAX_TILES:
			_resize_packed_wheel_rotor(rotor, tiles)
		if axis == 1:
			rotor.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		elif axis == 2:
			rotor.rotation = Vector3.ZERO
		return wheel
	if kind == "belt":
		var belt_path := ("res://opening/assets/prebuilt-preview-belt.scn" if axis == 0
			else "res://opening/assets/prebuilt-preview-belt-axis-%d.scn" % axis)
		var belt: PackedScene = _packed_preview_resource(belt_path)
		return belt.instantiate() as Node3D if belt != null else null
	if kind not in ["collector", "processor"]:
		return null
	var default: PackedScene = packed_preview_templates.get(kind)
	if default == null:
		default = load("res://opening/assets/prebuilt-preview-" + kind + ".scn") as PackedScene
	if default == null:
		return null
	var anchor := default.instantiate() as Node3D
	if kind == "collector":
		if cell != Vector2i(0, 1) or level != 0:
			var source: PackedScene = _packed_preview_resource(_collector_preview_source_path(cell, level))
			if source == null:
				anchor.free()
				return null
			_replace_preview_parts(anchor, source, ["Source"])
		var drive := anchor.get_node("DriveStub") as MeshInstance3D
		if axis == 1:
			for child in anchor.get_children():
				if child.name.begins_with("CollectorInput"):
					child.free()
			drive.mesh = ProductionDriveJournalArt.mesh(0.9)
			drive.rotation = Vector3.ZERO
		elif axis == 2:
			var turn := Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3.ZERO)
			for child in anchor.get_children():
				if child.name == "DriveStub" or child.name.begins_with("CollectorInput"):
					child.transform = turn * child.transform
					if child.name == "DriveStub":
						child.rotation = _spindle_rotation(Vector3.BACK)
					elif child.name.begins_with("CollectorInputBearing"):
						child.basis = Basis(Quaternion(Vector3.UP, Vector3.BACK))
					elif child.name.begins_with("CollectorInputPost"):
						child.basis = Basis.IDENTITY
						child.mesh = ProductionVisuals.box_mesh(Vector3(0.16, 0.50, 0.08))
					elif child.name.begins_with("CollectorInputFoot"):
						child.basis = Basis.IDENTITY
						child.mesh = ProductionVisuals.box_mesh(Vector3(0.20, 0.10, 0.26))
		var cassette := anchor.get_node_or_null("CollectorOutputCassette") as Node3D
		if cassette != null:
			cassette.rotation.y = -float(facing) * PI / 2.0
		_rotate_packed_preview_port(anchor, facing)
		return anchor
	var local_axis := 2 - axis if facing % 2 == 1 and axis != 1 else axis
	if local_axis != 0:
		var drive_part: PackedScene = _packed_preview_resource(
			"res://opening/assets/prebuilt-preview-processor-drive-%d.scn" % local_axis)
		if drive_part == null:
			anchor.free()
			return null
		_replace_preview_parts(anchor, drive_part, ["DriveStub", "PressInput"])
		# Press bearings follow the drive stub in the source assembly.
		# The drive resource owns their complete alternative layout.
	if facing != 0:
		var holder := Node3D.new()
		holder.name = "RotatedMachineVisual"
		for child in anchor.get_children():
			if child.name.begins_with("PortArrow") or child.name == "MaterialPortLabel":
				continue
			_clear_preview_owners(child)
			anchor.remove_child(child)
			holder.add_child(child)
		holder.rotation.y = -float(facing) * PI / 2.0
		anchor.add_child(holder)
		anchor.move_child(holder, 0)
		_rotate_packed_preview_port(anchor, facing)
	return anchor

func _warm_packed_machine_previews() -> void:
	if DisplayServer.get_name() == "headless":
		for kind in ["collector", "belt", "processor", "wheel"]:
			packed_preview_templates[kind] = load("res://opening/assets/prebuilt-preview-" + kind + ".scn")
		return
	var cover := CanvasLayer.new()
	cover.name = "MachinePreviewWarmup"
	cover.layer = 100
	var color := ColorRect.new()
	color.color = Color("101e20")
	color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(color)
	var progress := Label.new()
	progress.text = "Preparing workshop..."
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(progress)
	add_child(cover)
	var view_size := get_viewport().get_visible_rect().size
	for index in 4:
		var kind: String = ["collector", "belt", "processor", "wheel"][index]
		var packed: PackedScene = load("res://opening/assets/prebuilt-preview-" + kind + ".scn")
		if packed == null:
			continue
		packed_preview_templates[kind] = packed
		var anchor := packed.instantiate() as Node3D
		add_child(anchor)
		_style_machine_preview(anchor)
		anchor.position = camera.project_position(Vector2(view_size.x * (0.2 + 0.2 * index), view_size.y * 0.5), 7.0)
		packed_preview_nodes[kind] = anchor
	var foundation := Node3D.new()
	foundation.name = "FoundationPreviewTemplate"
	add_child(foundation)
	_assemble_foundation(foundation)
	_style_machine_preview(foundation)
	foundation.position = camera.project_position(view_size * Vector2(0.5, 0.65), 7.0)
	packed_preview_nodes["foundation"] = foundation
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for anchor in packed_preview_nodes.values():
		anchor.visible = false
	await _warm_transmission_placement_previews(view_size)
	var frames_waited := 0
	while not state.get("actors", {}).get(client, {}).get("ready", false) and frames_waited < 120:
		frames_waited += 1
		await get_tree().process_frame
	if state.get("actors", {}).get(client, {}).get("ready", false):
		# Draw the real tool panels behind the loading cover. Arrival has no
		# carried kits yet, so only the temporary visual form is shown here.
		var opening_message := status_label.text
		var opening_refused := status_refused
		var resume_processing := is_processing()
		set_process(false)
		for kind in ["collector", "foundation", "processor", "wheel"]:
			var anchor: Node3D = packed_preview_nodes.get(kind)
			if anchor == null:
				continue
			_select_tool(kind)
			_choose_machine_preview(anchor)
			anchor.visible = true
			_refresh_placement_options()
			await RenderingServer.frame_post_draw
			anchor.visible = false
		_select_tool("inspect")
		set_process(resume_processing)
		_message(opening_message, opening_refused)
	cover.free()
	# The first native input window follows the arrival reveal. Begin loading
	# finite variants now, after the covered startup is complete.
	_prefetch_machine_preview_variants()

func _warm_transmission_placement_previews(view_size: Vector2) -> void:
	# Draw the two cog sizes and the shaft while the workshop cover is visible.
	# Their shared meshes and render resources then exist before a tool click.
	var assets = load("res://opening/native_transmission_assets.gd")
	var warm_nodes: Array[Node3D] = []
	for teeth in [2, 4]:
		var cog := MeshInstance3D.new()
		cog.name = "CogPreviewWarmup%d" % teeth
		cog.mesh = assets.complete_gear_mesh(PITCH / 2.0, teeth, Color("687a7b"), PITCH)
		cog.position = camera.project_position(Vector2(view_size.x * (0.2 if teeth == 2 else 0.8),
			view_size.y * 0.5), 7.0)
		add_child(cog)
		_style_machine_preview(cog)
		warm_nodes.append(cog)
	var shaft := Node3D.new()
	shaft.name = "ShaftPreviewWarmup"
	shaft.position = camera.project_position(view_size * Vector2(0.5, 0.5), 7.0)
	add_child(shaft)
	assets.shaft(shaft, PITCH, Color("687a7b"))
	_style_machine_preview(shaft)
	warm_nodes.append(shaft)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for node in warm_nodes:
		node.free()

func _choose_machine_preview(pooled: Node3D = null) -> void:
	var desired := pooled
	if desired == null:
		if mutable_machine_preview == null:
			mutable_machine_preview = Node3D.new()
			mutable_machine_preview.name = "MachinePlacementPreview"
			add_child(mutable_machine_preview)
		desired = mutable_machine_preview
	if machine_preview != desired:
		if machine_preview != null:
			machine_preview.visible = false
		machine_preview = desired
		machine_preview_key = ""

const MACHINE_BATCH_THRESHOLD := 12
const MACHINE_STATIC_SPATIAL_THRESHOLD := 256
const MACHINE_STATIC_SPATIAL_FIELD_THRESHOLD := 800
# Paddle joinery ends by 32 m with a 2 m fade margin; the extra room
# covers the largest authored rim and a camera move between render cuts.
const WHEEL_DETAIL_UPDATE_RADIUS := 48.0
const WHEEL_MOTION_VISIBILITY_MARGIN := 16.0
# Bound moving rotor batches by worksite region so distant wheels do not
# submit the complete field to the color and shadow passes.
const WHEEL_ROTOR_BATCH_CELL := 32.0

func _machine_batch_surface_mesh(part: MeshInstance3D) -> Mesh:
	var source: Mesh = part.mesh
	var finishes: Array = []
	var finish_ids: Array[int] = []
	var has_overrides := false
	for surface in source.get_surface_count():
		var finish: Material = part.get_surface_override_material(surface)
		has_overrides = has_overrides or finish != null
		if finish == null:
			finish = source.surface_get_material(surface)
		finishes.append(finish)
		finish_ids.append(finish.get_instance_id() if finish != null else 0)
	if not has_overrides:
		return source
	var key := [source.get_instance_id(), finish_ids]
	if machine_batch_finished_meshes.has(key):
		return machine_batch_finished_meshes[key]
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface),
			source.surface_get_arrays(surface))
		result.surface_set_material(surface, finishes[surface])
	machine_batch_finished_meshes[key] = result
	return result

func _collect_wheel_rotor_parts(node: Node3D, pose: Transform3D, parts: Array[Dictionary]) -> bool:
	for child in node.get_children():
		if not child is Node3D or not child.visible:
			continue
		var child_pose: Transform3D = pose * (child as Node3D).transform
		if child is MeshInstance3D:
			var part := child as MeshInstance3D
			if part.mesh == null or part.material_overlay != null:
				return false
			if part.visibility_range_end > 0.0:
				continue
			for surface in part.mesh.get_surface_count():
				var finish: Material = part.material_override
				if finish == null:
					finish = part.get_surface_override_material(surface)
				if finish == null:
					finish = part.mesh.surface_get_material(surface)
				if finish is BaseMaterial3D and finish.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					return false
				if part.mesh is ArrayMesh and part.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
					return false
				parts.append({"source": part, "mesh": part.mesh, "surface": surface, "finish": finish,
					"pose": child_pose, "shadow": part.cast_shadow, "layers": part.layers})
		if not _collect_wheel_rotor_parts(child, child_pose, parts):
			return false
	return true

func _wheel_rotor_batch_mesh(rotor: Node3D, hidden_core: Array[MeshInstance3D]) -> Mesh:
	var key: Array = rotor.get_meta("visual_batch_key", [])
	var parts: Array[Dictionary] = []
	if not _collect_wheel_rotor_parts(rotor, Transform3D.IDENTITY, parts) or parts.is_empty():
		return null
	for part in parts:
		if part.source not in hidden_core:
			hidden_core.append(part.source)
	if machine_batch_rotor_meshes.has(key):
		return machine_batch_rotor_meshes[key]
	var groups := {}
	var shadow: int = parts[0].shadow
	var layers: int = parts[0].layers
	for part in parts:
		if part.shadow != shadow or part.layers != layers:
			return null
		var finish: Material = part.finish
		var finish_id := finish.get_instance_id() if finish != null else 0
		if not groups.has(finish_id):
			groups[finish_id] = {"finish": finish, "parts": []}
		groups[finish_id].parts.append(part)
	var combined: ArrayMesh
	for group in groups.values():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in group.parts:
			surface.append_from(part.mesh, part.surface, part.pose)
		surface.set_material(group.finish)
		combined = surface.commit(combined)
	machine_batch_rotor_meshes[key] = combined
	return combined

func _collect_machine_composite_parts(node: Node3D, pose: Transform3D,
		moving: Dictionary, parts: Array[Dictionary]) -> void:
	# Keep moving, translucent, range-culled and conveyor-loop visuals on their
	# existing paths. Only identical opaque static assemblies can be instanced.
	for child in node.get_children():
		if not child is Node3D or not child.visible or child.name == "WheelRotor":
			continue
		var child_pose: Transform3D = pose * child.transform
		if child is MeshInstance3D:
			var source := child as MeshInstance3D
			if moving.has(source.get_instance_id()):
				continue
			# Hiding a scene parent would also hide its unbatched children.
			if source.mesh != null and source.get_child_count() == 0 and source.name != "ConveyorLoop" \
					and source.material_overlay == null \
					and source.visibility_range_end <= 0.0:
				var eligible_parts: Array[Dictionary] = []
				for surface in source.mesh.get_surface_count():
					var finish: Material = source.material_override
					if finish == null:
						finish = source.get_surface_override_material(surface)
					if finish == null:
						finish = source.mesh.surface_get_material(surface)
					if (finish is BaseMaterial3D and finish.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED) \
							or (source.mesh is ArrayMesh and source.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES):
						eligible_parts.clear()
						break
					eligible_parts.append({"source": source, "mesh": source.mesh, "surface": surface,
						"finish": finish, "pose": child_pose, "shadow": source.cast_shadow,
						"layers": source.layers})
				parts.append_array(eligible_parts)
		_collect_machine_composite_parts(child, child_pose, moving, parts)

func _machine_finish_mesh(source: ArrayMesh) -> ArrayMesh:
	# Opaque parts can share a surface when their finish differs only by values
	# carried on vertices. Keep the source mesh if an attribute is unsupported.
	var groups := {}
	for surface_index in source.get_surface_count():
		var finish := source.surface_get_material(surface_index) as StandardMaterial3D
		if finish == null or finish.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or finish.albedo_texture != null \
				or source.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			return source
		var varied := not finish.uv1_triplanar and finish.normal_enabled \
			and finish.normal_texture != null and finish.roughness_texture != null \
			and finish.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED \
			and finish.metallic_texture == null
		var key := [varied]
		for property in finish.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0 or property.name in [
					"resource_name", "resource_path", "resource_local_to_scene",
					"albedo_color", "vertex_color_use_as_albedo"]:
				continue
			if varied and property.name in ["metallic", "roughness"]:
				continue
			key.append([property.name, finish.get(property.name)])
		if not groups.has(key):
			groups[key] = {"finish": finish, "varied": varied, "vertices": [],
				"normals": [], "tangents": [], "uv": [], "uv2": [], "colors": [], "indices": []}
		var group: Dictionary = groups[key]
		var arrays := source.surface_get_arrays(surface_index)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents = arrays[Mesh.ARRAY_TANGENT]
		var uv = arrays[Mesh.ARRAY_TEX_UV]
		var colors = arrays[Mesh.ARRAY_COLOR]
		var indices = arrays[Mesh.ARRAY_INDEX]
		if normals.size() != points.size() or not tangents is PackedFloat32Array \
				or tangents.size() != points.size() * 4 or not uv is PackedVector2Array \
				or uv.size() != points.size():
			return source
		var start: int = group.vertices.size()
		for point_index in points.size():
			group.vertices.append(points[point_index])
			group.normals.append(normals[point_index])
			group.uv.append(uv[point_index])
			for lane in 4:
				group.tangents.append(tangents[point_index * 4 + lane])
			var color := finish.albedo_color
			if finish.vertex_color_use_as_albedo and colors is PackedColorArray \
					and colors.size() == points.size():
				color *= colors[point_index]
			if varied:
				color.a = finish.metallic
				group.uv2.append(Vector2(finish.roughness, 0))
			group.colors.append(color)
		if not indices is PackedInt32Array or indices.is_empty():
			for point_index in points.size():
				group.indices.append(start + point_index)
		else:
			for point_index in indices:
				group.indices.append(start + point_index)
	if groups.size() >= source.get_surface_count():
		return source
	var result := ArrayMesh.new()
	for group in groups.values():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(group.vertices)
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(group.normals)
		arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array(group.tangents)
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(group.uv)
		if group.varied:
			arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array(group.uv2)
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(group.colors)
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(group.indices)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material: Material
		if group.varied:
			var shader := Shader.new()
			shader.code = "shader_type spatial;\n" + \
				"uniform sampler2D finish_rough : filter_linear_mipmap_anisotropic, repeat_enable;\n" + \
				"uniform sampler2D finish_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;\n" + \
				"uniform vec2 finish_uv_scale;\n" + \
				"uniform vec2 finish_uv_offset;\n" + \
				"uniform float finish_normal_scale;\n" + \
				"void fragment() { vec2 at = UV * finish_uv_scale + finish_uv_offset; " + \
				"ALBEDO = COLOR.rgb; METALLIC = COLOR.a; " + \
				"ROUGHNESS = UV2.x * texture(finish_rough, at).r; " + \
				"NORMAL_MAP = texture(finish_normal, at).rgb; " + \
				"NORMAL_MAP_DEPTH = finish_normal_scale; }"
			var custom_finish := ShaderMaterial.new()
			custom_finish.shader = shader
			custom_finish.set_shader_parameter("finish_rough", group.finish.roughness_texture)
			custom_finish.set_shader_parameter("finish_normal", group.finish.normal_texture)
			custom_finish.set_shader_parameter("finish_uv_scale", Vector2(group.finish.uv1_scale.x, group.finish.uv1_scale.y))
			custom_finish.set_shader_parameter("finish_uv_offset", Vector2(group.finish.uv1_offset.x, group.finish.uv1_offset.y))
			custom_finish.set_shader_parameter("finish_normal_scale", group.finish.normal_scale)
			material = custom_finish
		else:
			var standard := group.finish.duplicate() as StandardMaterial3D
			standard.albedo_color = Color.WHITE
			standard.vertex_color_use_as_albedo = true
			material = standard
		result.surface_set_material(result.get_surface_count() - 1, material)
	return result

func _machine_composite_mesh(parts: Array[Dictionary], key: Array) -> ArrayMesh:
	if machine_batch_composite_meshes.has(key):
		return machine_batch_composite_meshes[key]
	var finishes := {}
	for part in parts:
		var finish: Material = part.finish
		var finish_id := finish.get_instance_id() if finish != null else 0
		if not finishes.has(finish_id):
			finishes[finish_id] = {"material": finish, "parts": []}
		finishes[finish_id].parts.append(part)
	var combined: ArrayMesh
	for group in finishes.values():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in group.parts:
			surface.append_from(part.mesh, part.surface, part.pose)
		surface.set_material(group.material)
		combined = surface.commit(combined)
	combined = _machine_finish_mesh(combined)
	# Keep the full composite and its finishes at close range. Godot selects
	# simpler indices only when their projected error fits the viewport LOD.
	var importer := ImporterMesh.from_mesh(combined)
	importer.generate_lods(60.0, 60.0, [])
	combined = importer.get_mesh()
	machine_batch_composite_meshes[key] = combined
	return combined

func _batch_machine_composites(moving: Dictionary, static_groups: Dictionary) -> Dictionary:
	var candidates := {}
	var skip_sources := {}
	for anchor in machine_root.get_children():
		# Wheel rotors already use a composite moving mesh; their supports did
		# not improve the rendered frame-time comparison.
		if not anchor is Node3D or not anchor.has_meta("machine_kind") \
				or anchor.get_meta("machine_kind") == "wheel":
			continue
		var parts: Array[Dictionary] = []
		_collect_machine_composite_parts(anchor, Transform3D.IDENTITY, moving, parts)
		if parts.size() < 2:
			continue
		var shadow: int = parts[0].shadow
		var layers: int = parts[0].layers
		var key: Array = []
		var compatible := true
		for part in parts:
			if part.shadow != shadow or part.layers != layers:
				compatible = false
				break
			var finish: Material = part.finish
			key.append_array([part.mesh.get_instance_id(), part.surface,
				finish.get_instance_id() if finish != null else 0, part.pose])
		if not compatible:
			continue
		key.append_array([shadow, layers])
		if not candidates.has(key):
			candidates[key] = {"parts": parts, "instances": []}
		candidates[key].instances.append({"anchor": anchor, "parts": parts})
	for key in candidates:
		var candidate: Dictionary = candidates[key]
		if candidate.instances.size() < 2:
			continue
		var mesh := _machine_composite_mesh(candidate.parts, key)
		var shadow: int = candidate.parts[0].shadow
		var layers: int = candidate.parts[0].layers
		var group_key := [mesh.get_instance_id(), 0, shadow, layers]
		if not static_groups.has(group_key):
			static_groups[group_key] = {"mesh": mesh, "material": null,
				"shadow": shadow, "layers": layers, "parts": [],
				"spatial_composite": true}
		for instance in candidate.instances:
			var sources: Array[MeshInstance3D] = []
			for part in instance.parts:
				if part.source not in sources:
					sources.append(part.source)
				skip_sources[part.source.get_instance_id()] = true
			static_groups[group_key].parts.append({"node": instance.anchor,
				"pose": instance.anchor.transform,
				"hide_nodes": sources})
	return skip_sources

func _batch_collector_cutters(dynamic_groups: Dictionary, skip_sources: Dictionary) -> void:
	var candidates := {}
	for anchor in machine_motion_anchors:
		if anchor.get_meta("machine_kind", "") != "collector":
			continue
		var parts: Array[Dictionary] = []
		var sources: Array[MeshInstance3D] = []
		var key: Array = ["collector_cutter"]
		var compatible := true
		for row in anchor.get_meta("motion_meshes", []):
			if row.role != "cutter":
				continue
			var source: MeshInstance3D = row.node
			if not is_instance_valid(source) or source.mesh == null or source.get_child_count() != 0 \
					or source.material_overlay != null or source.visibility_range_end > 0.0:
				compatible = false
				break
			sources.append(source)
			for surface in source.mesh.get_surface_count():
				var finish: Material = source.material_override
				if finish == null:
					finish = source.get_surface_override_material(surface)
				if finish == null:
					finish = source.mesh.surface_get_material(surface)
				if (finish is BaseMaterial3D and finish.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED) \
						or (source.mesh is ArrayMesh and source.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES):
					compatible = false
					break
				parts.append({"source": source, "mesh": source.mesh, "surface": surface,
					"finish": finish, "pose": row.rest, "shadow": source.cast_shadow,
					"layers": source.layers})
				key.append_array([source.mesh.get_instance_id(), surface,
					finish.get_instance_id() if finish != null else 0, row.rest])
			if not compatible:
				break
		if not compatible or sources.size() != 10 or parts.is_empty():
			continue
		var shadow: int = parts[0].shadow
		var layers: int = parts[0].layers
		for part in parts:
			if part.shadow != shadow or part.layers != layers:
				compatible = false
				break
		if not compatible:
			continue
		key.append_array([shadow, layers])
		if not candidates.has(key):
			candidates[key] = {"parts": parts, "instances": []}
		candidates[key].instances.append({"anchor": anchor, "sources": sources})
	for key in candidates:
		var candidate: Dictionary = candidates[key]
		if candidate.instances.size() < MACHINE_BATCH_THRESHOLD:
			continue
		var mesh := _machine_composite_mesh(candidate.parts, key)
		var group_key := [mesh.get_instance_id(), 0, candidate.parts[0].shadow,
			candidate.parts[0].layers, "collector_cutter"]
		dynamic_groups[group_key] = {"mesh": mesh, "material": null,
			"shadow": candidate.parts[0].shadow, "layers": candidate.parts[0].layers,
			"parts": []}
		for instance in candidate.instances:
			var anchor: Node3D = instance.anchor
			var angle: float = float(anchor.get_meta("cutter_angle", 0.0))
			dynamic_groups[group_key].parts.append({"node": anchor,
				"pose": anchor.transform * _cutter_spin(anchor, angle),
				"hide_nodes": instance.sources, "cutter": true})
			for source in instance.sources:
				skip_sources[source.get_instance_id()] = true

func _batch_machine_visuals_walk(node: Node3D, pose: Transform3D,
		moving: Dictionary, static_groups: Dictionary, dynamic_groups: Dictionary,
		rotating := false, skip_sources: Dictionary = {}) -> void:
	if not node.visible:
		return
	var next_pose := pose * node.transform
	var in_rotor: bool = rotating or node.name == "WheelRotor"
	if node.name == "WheelRotor":
		var hidden_core: Array[MeshInstance3D] = []
		var combined := _wheel_rotor_batch_mesh(node, hidden_core)
		if combined != null:
			var bucket := Vector2i(floori(next_pose.origin.x / WHEEL_ROTOR_BATCH_CELL),
				floori(next_pose.origin.z / WHEEL_ROTOR_BATCH_CELL))
			var key := [combined.get_instance_id(), 0, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, 1, bucket]
			if not dynamic_groups.has(key):
				dynamic_groups[key] = {"mesh": combined, "material": null,
					"shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "layers": 1, "parts": []}
			dynamic_groups[key].parts.append({"node": node, "pose": next_pose,
				"parent_pose": pose, "hide_nodes": hidden_core})
			return
	if node is MeshInstance3D and not skip_sources.has(node.get_instance_id()) and node.mesh != null and node.name != "ConveyorLoop" \
			and node.visibility_range_end <= 0.0:
		var mesh_part := node as MeshInstance3D
		var material := mesh_part.material_override
		var overrides := mesh_part.material_overlay != null
		for surface in mesh_part.mesh.get_surface_count():
			var finish := mesh_part.get_surface_override_material(surface)
			if finish is BaseMaterial3D:
				overrides = overrides or finish.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if material is BaseMaterial3D:
			overrides = overrides or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if not overrides:
			var dynamic: bool = in_rotor or moving.has(node.get_instance_id())
			var groups: Dictionary = dynamic_groups if dynamic else static_groups
			var batch_mesh: Mesh = _machine_batch_surface_mesh(mesh_part)
			var key := [batch_mesh.get_instance_id(), material.get_instance_id() if material != null else 0,
				mesh_part.cast_shadow, mesh_part.layers]
			if not groups.has(key):
				groups[key] = {"mesh": batch_mesh, "material": material,
					"shadow": mesh_part.cast_shadow, "layers": mesh_part.layers, "parts": []}
			groups[key].parts.append({"node": mesh_part, "pose": next_pose})
	for child in node.get_children():
		if child is Node3D:
			_batch_machine_visuals_walk(child, next_pose, moving, static_groups, dynamic_groups,
				in_rotor, skip_sources)

func _emit_machine_mesh_batches(groups: Dictionary, batches: Node3D, dynamic: bool) -> void:
	var batch_index := batches.get_child_count()
	for group in groups.values():
		if group.parts.size() < 2:
			continue
		var partitions: Array = [group.parts]
		# Smaller fields submit more cell batches than culling saves. Count only
		# eligible static machines so wheels and foundations cannot trigger it.
		if not dynamic and group.get("spatial_composite", false) \
				and machine_static_spatial_tiles > 0 \
				and machine_batch_static_machine_count >= MACHINE_STATIC_SPATIAL_FIELD_THRESHOLD \
				and group.parts.size() >= MACHINE_STATIC_SPATIAL_THRESHOLD:
			var cells := {}
			var cell_size := PITCH * float(machine_static_spatial_tiles)
			for part in group.parts:
				var at: Vector3 = part.pose.origin
				var cell := Vector2i(floori(at.x / cell_size), floori(at.z / cell_size))
				if not cells.has(cell):
					cells[cell] = []
				cells[cell].append(part)
			partitions = cells.values()
		for parts in partitions:
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = group.mesh
			multi.instance_count = parts.size()
			var bounds: AABB = parts[0].pose * group.mesh.get_aabb()
			var motion_margin := bounds.size.length()
			for index in parts.size():
				multi.set_instance_transform(index, parts[index].pose)
				var part_bounds: AABB = parts[index].pose * group.mesh.get_aabb()
				bounds = bounds.merge(part_bounds)
				motion_margin = maxf(motion_margin, part_bounds.size.length())
				if parts[index].has("hide_nodes"):
					for source in parts[index].hide_nodes:
						source.visible = false
				else:
					parts[index].node.visible = false
			multi.custom_aabb = bounds.grow(maxf(6.0, motion_margin)) if dynamic else bounds
			var instance := MultiMeshInstance3D.new()
			instance.name = "MachineBatch%d" % batch_index
			instance.multimesh = multi
			instance.material_override = group.material
			instance.cast_shadow = group.shadow
			instance.layers = group.layers
			instance.set_meta("spatial_composite", group.get("spatial_composite", false))
			batches.add_child(instance)
			if dynamic:
				var rotor_only := true
				var cutter_only := true
				for part in parts:
					rotor_only = rotor_only and part.node.name == "WheelRotor"
					cutter_only = cutter_only and part.get("cutter", false)
				machine_dynamic_batches.append({"mesh": multi, "parts": parts,
					"rotor_only": rotor_only, "cutter_only": cutter_only})
				for index in parts.size():
					var part: Dictionary = parts[index]
					if part.get("cutter", false):
						machine_cutter_batch_slots[part.node.get_instance_id()] = {"mesh": multi, "index": index}
					if part.node.name == "WheelRotor":
						var node_id: int = part.node.get_instance_id()
						machine_batched_rotors[node_id] = true
						machine_batched_rotor_slots[node_id] = {"mesh": multi, "index": index,
							"node": part.node, "parent_pose": part.parent_pose}
			batch_index += 1

func _update_machine_dynamic_batches(visible_rotors_only := false) -> void:
	if machine_dynamic_batches.is_empty():
		return
	var to_local := machine_root.global_transform.affine_inverse()
	if visible_rotors_only:
		for node_id in wheel_updated_rotors:
			var slot: Dictionary = machine_batched_rotor_slots.get(node_id, {})
			if slot.is_empty():
				continue
			var pose: Transform3D = slot.parent_pose * (wheel_batch_poses[node_id] \
				if wheel_batch_poses.has(node_id) else slot.node.transform)
			slot.mesh.set_instance_transform(slot.index, pose)
	for group in machine_dynamic_batches:
		if visible_rotors_only and (group.rotor_only or group.get("cutter_only", false)):
			continue
		var mesh: MultiMesh = group.mesh
		for index in group.parts.size():
			var part: Dictionary = group.parts[index]
			if visible_rotors_only and machine_batched_rotor_slots.has(part.node.get_instance_id()):
				continue
			# Wheel ancestors remain fixed until the next topology rebuild. Keep
			# their machine-root-relative pose and update only the moving rotor.
			var motion_pose: Transform3D
			if part.has("parent_pose"):
				var node_id: int = part.node.get_instance_id()
				# An offscreen rotor keeps its last instance pose until it returns.
				if visible_rotors_only and not wheel_updated_rotors.has(node_id):
					continue
				motion_pose = part.parent_pose * (wheel_batch_poses[node_id] \
					if wheel_batch_poses.has(node_id) else part.node.transform)
			else:
				motion_pose = to_local * part.node.global_transform
			mesh.set_instance_transform(index, motion_pose)
func _batch_conveyor_loops(batches: Node3D) -> void:
	var loops: Array[MeshInstance3D] = []
	for part in machine_root.find_children("ConveyorLoop", "MeshInstance3D", true, false):
		if part.is_visible_in_tree() and part.mesh != null and part.material_override is StandardMaterial3D:
			loops.append(part)
	if loops.size() < MACHINE_BATCH_THRESHOLD:
		return
	for loop in loops:
		if loop.mesh != loops[0].mesh or loop.cast_shadow != loops[0].cast_shadow or loop.layers != loops[0].layers:
			return
	var finish := ProductionConveyorArt.multimesh_material()
	if finish == null:
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = loops[0].mesh
	multi.instance_count = loops.size()
	var to_local := machine_root.global_transform.affine_inverse()
	var bounds: AABB = to_local * loops[0].global_transform * loops[0].mesh.get_aabb()
	for index in loops.size():
		var loop := loops[index]
		var pose: Transform3D = to_local * loop.global_transform
		multi.set_instance_transform(index, pose)
		multi.set_instance_custom_data(index, Color(loop.material_override.uv1_offset.x, 0, 0))
		bounds = bounds.merge(pose * loop.mesh.get_aabb())
		loop.visible = false
	multi.custom_aabb = bounds
	var instance := MultiMeshInstance3D.new()
	instance.name = "ConveyorLoopBatch"
	instance.multimesh = multi
	instance.material_override = finish
	instance.cast_shadow = loops[0].cast_shadow
	instance.layers = loops[0].layers
	batches.add_child(instance)
	machine_conveyor_batches.append({"mesh": multi, "parts": loops})
	for index in loops.size():
		machine_conveyor_batch_slots[loops[index].get_instance_id()] = {"mesh": multi, "index": index}

func _batch_machine_visuals() -> void:
	machine_dynamic_batches.clear()
	machine_conveyor_batches.clear()
	machine_conveyor_batch_slots.clear()
	machine_batch_static_machine_count = 0
	machine_batched_rotors.clear()
	machine_batched_rotor_slots.clear()
	machine_cutter_batch_slots.clear()
	wheel_batch_poses.clear()
	wheel_updated_rotors.clear()
	if not _native_transmission() or machine_root.get_child_count() < MACHINE_BATCH_THRESHOLD:
		return
	var moving := {}
	for anchor in machine_root.get_children():
		if anchor.get_meta("machine_kind", "") in ["collector", "belt", "processor"]:
			machine_batch_static_machine_count += 1
		for row in anchor.get_meta("motion_meshes", []):
			moving[row.node.get_instance_id()] = true
	var static_groups := {}
	var dynamic_groups := {}
	var skip_sources := _batch_machine_composites(moving, static_groups)
	_batch_collector_cutters(dynamic_groups, skip_sources)
	for anchor in machine_root.get_children():
		if anchor is Node3D:
			_batch_machine_visuals_walk(anchor, Transform3D.IDENTITY, moving, static_groups,
				dynamic_groups, false, skip_sources)
	var batches := Node3D.new()
	batches.name = "MachineVisualBatches"
	machine_root.add_child(batches)
	_emit_machine_mesh_batches(static_groups, batches, false)
	_emit_machine_mesh_batches(dynamic_groups, batches, true)
	_batch_conveyor_loops(batches)

func _index_machine_rotors() -> void:
	machine_rotor_cells.clear()
	var cell_indices := {}
	for wheel in machine_rotors:
		var center: Vector3 = wheel.center
		var key := Vector3i(floori(center.x / WHEEL_ROTOR_BATCH_CELL),
			floori(center.y / WHEEL_ROTOR_BATCH_CELL), floori(center.z / WHEEL_ROTOR_BATCH_CELL))
		if not cell_indices.has(key):
			cell_indices[key] = machine_rotor_cells.size()
			machine_rotor_cells.append({"bounds": AABB(center, Vector3.ZERO), "wheels": [wheel]})
		else:
			var cell: Dictionary = machine_rotor_cells[cell_indices[key]]
			cell.bounds = (cell.bounds as AABB).expand(center)
			cell.wheels.append(wheel)

func _rebuild_machines() -> void:
	_sync_machine_body_context()
	machine_rotors.clear()
	machine_motion_anchors.clear()
	machine_cutter_batch_slots.clear()
	var foundation_masks := ProductionFoundationArt.neighbor_masks(state.get("foundations", {}))
	var scenery := get_node_or_null("ProductionScenery")
	if scenery != null and ProductionEnvironment.Surface != null:
		ProductionEnvironment.refresh_vegetation(scenery, state)
	for child in machine_root.get_children():
		child.free()
	wheel_rotor = null
	for id in state.get("foundations", {}):
		var surface: Dictionary = state.foundations[id]
		var anchor := Node3D.new()
		anchor.position = _entity_position(surface)
		anchor.set_meta("arrival_deck_panel", str(id).begins_with("pod-floor-"))
		anchor.set_meta("arrival_deck_anchor", anchor.position)
		machine_root.add_child(anchor)
		_assemble_foundation(anchor, foundation_masks[id])
		var body := StaticBody3D.new()
		body.collision_layer = Geometry.PICK_LAYER
		body.collision_mask = 0
		body.set_meta("entity", id)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE * PITCH
		collider.shape = shape
		collider.position.y = -PITCH / 2.0
		body.add_child(collider)
		anchor.add_child(body)
	for entity_id in state.entities:
		var entity: Dictionary = state.entities[entity_id]
		var kind: String = entity.kind
		var anchor := Node3D.new()
		anchor.position = _entity_position(entity)
		machine_root.add_child(anchor)
		_assemble_machine(anchor, entity, _material_rotated(entity_id, entity))
		if kind == "wheel" and wheel_rotor != null:
			# A detached presentation fixture has no global transform yet.
			var rotor_center: Vector3 = wheel_rotor.global_position if wheel_rotor.is_inside_tree() \
				else machine_root.transform * anchor.transform * wheel_rotor.position
			machine_rotors.append({"id": entity_id, "rotor": wheel_rotor,
				"base": wheel_rotor.basis, "center": rotor_center})
		anchor.set_meta("machine_entity", entity_id)
		anchor.set_meta("machine_kind", kind)
		if kind in ["collector", "belt", "processor"]:
			machine_motion_anchors.append(anchor)
		var motion_meshes: Array[Dictionary] = []
		_remember_machine_motion(anchor, kind, Transform3D.IDENTITY, motion_meshes)
		anchor.set_meta("motion_meshes", motion_meshes)
		if kind == "collector" and transmission_presenter != null:
			_apply_cutter_pose(anchor, motion_meshes, transmission_presenter.visual_angle(entity_id))
		elif kind == "belt" and transmission_presenter != null:
			_apply_conveyor_motion(anchor, transmission_presenter.visual_rotation(entity_id))
		elif kind == "processor" and _native_transmission():
			var target: Variant = _observed_press_target()
			var generation: Variant = entity.get("generation")
			if target != null and typeof(generation) == TYPE_INT and generation > 0:
				if not machine_press_poses.has(entity_id):
					machine_press_poses[entity_id] = {"generation": generation, "travel": target}
				_apply_press_pose(motion_meshes, machine_press_poses[entity_id].travel)
		var body := StaticBody3D.new()
		body.collision_layer = Geometry.PICK_LAYER
		body.collision_mask = 0
		body.set_meta("entity", entity_id)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Geometry.wheel_half_extents(int(entity.get("axis", 0)), int(entity.get("tiles", 3))) * 2.0 if kind == "wheel" and _native_transmission() else Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])
		collider.shape = shape
		collider.position.y = Geometry.ANCHOR_HEIGHT if kind == "wheel" and _native_transmission() else Geometry.MACHINE_CENTER_HEIGHT
		body.add_child(collider)
		if kind == "collector" and _native_transmission():
			var intake_result: Dictionary = Geometry.collector_intake_boxes(entity)
			if not intake_result.get("accepted", false):
				push_error("The collector pick geometry lacks its native source-facing intake.")
			else:
				for intake: Dictionary in intake_result.boxes:
					var intake_pick := CollisionShape3D.new()
					var intake_box := BoxShape3D.new()
					intake_box.size = intake.size
					intake_pick.shape = intake_box
					intake_pick.position = intake.center - anchor.position
					body.add_child(intake_pick)
		if kind == "wheel" and _native_transmission() and entity.has("supports"):
			var support_result: Dictionary = Geometry.wheel_support_boxes(entity)
			if not support_result.get("accepted", false):
				push_error("The wheel pick geometry lacks its native support boxes.")
			else:
				for support: Dictionary in support_result.boxes:
					var support_pick := CollisionShape3D.new()
					var support_box := BoxShape3D.new()
					support_box.size = support.size
					support_pick.shape = support_box
					support_pick.position = support.center - anchor.position
					body.add_child(support_pick)
		anchor.add_child(body)
		var caption_height := collider.position.y + shape.size.y * 0.5 + 0.275
		var caption := _text(anchor, NAMES.get(kind, kind).to_upper(), Vector3(0, caption_height, 0), Color("f2e5c5"))
		caption.name = "MachineCaption"
		caption.visible = not _native_transmission()
	for pair in state.links:
		if state.entities.has(pair[0]) and state.entities.has(pair[1]):
			_material_route(machine_root, _entity_position(state.entities[pair[0]]),
				_entity_position(state.entities[pair[1]]))
	for pair in state.get("drive_links", []):
		if not _native_transmission() and state.entities.has(pair[0]) and state.entities.has(pair[1]):
			_bar(machine_root, _cell_position(state.entities[pair[0]].cell) + Vector3(0, 0.35, 0.55),
				_cell_position(state.entities[pair[1]].cell) + Vector3(0, 0.35, 0.55), 0.09, Color("d1b56e"))
	_index_machine_rotors()
	_batch_machine_visuals()

func _redraw_items() -> void:
	# The asset helper uses this script's shared surfaces, so load it after
	# the opening class is available instead of creating a preload cycle.
	if workpiece_item_assets == null:
		workpiece_item_assets = load("res://opening/workpiece_item_assets.gd")
	workpiece_item_assets.populate_items(item_root, state, PITCH)

func _refresh() -> void:
	_refresh_from_projection(model._view_projection_borrowed() if model.has_method("_view_projection_borrowed") \
		else model.view_projection() if model.has_method("view_projection") else model.projection())

func _refresh_from_projection(known_projection: Dictionary) -> void:
	# Both model paths return the complete projection from advance(). Reuse the
	# final accepted tick in this render cut instead of projecting every part
	# again. A failed tick or a frame without one still reads current authority.
	var prior_cut: Dictionary = state.get("manual_cuts", {}).get(client, {})
	var prior_cargo: Dictionary = state.get("cargo", {}).get(client, {})
	state = known_projection
	if not prior_cut.is_empty() and not state.get("manual_cuts", {}).has(client):
		var current_cargo: Dictionary = state.get("cargo", {}).get(client, {})
		var timber_added: int = int(current_cargo.get("timber", 0)) - int(prior_cargo.get("timber", 0))
		var raw_added: int = int(current_cargo.get("raw", 0)) - int(prior_cargo.get("raw", 0))
		_message(_harvest_result_text({"moved_timber": timber_added, "moved_raw": raw_added}) \
			if timber_added > 0 or raw_added > 0 else "Cut interrupted.")
	_sync_landing_pod_visual()
	# Shared profiles arrive after presenter creation. Choose this revisable
	# default once, preserving any pitch already adjusted while connecting.
	if not native_camera_initialized and _native_transmission():
		native_camera_initialized = true
		if orbit_pitch == 0.82:
			orbit_pitch = 0.60
	var next_key: String
	if model is NativeWorldModel and typeof(state.get("order")) == TYPE_INT and typeof(state.get("context")) == TYPE_STRING:
		# Commands can change topology; material ticks advance revision without
		# changing the built geometry. A new model or context also needs a rebuild.
		next_key = "native:" + str(model.get_instance_id()) + ":" + state.context + ":" + str(state.order)
	else:
		next_key = JSON.stringify([state.entities, state.links, state.get("drive_links", []), state.get("foundations", {})])
	if next_key != geometry_key:
		geometry_key = next_key
		if actor_world != null:
			actor_world.sync_topology()
		_rebuild_machines()
	if int(state.revision) != visual_revision:
		visual_revision = int(state.revision)
		_redraw_items()
	if character_presenter != null:
		character_presenter.refresh()
	if not model is NativeWorldModel or _native_ui_key() != ui_refresh_key:
		_refresh_ui()

func _native_ui_key() -> Array:
	return [model.get_instance_id(), state.get("context"), state.get("revision"),
		state.get("actors", {}).get(client, {}).get("ready", false),
		selected, mode, explanation_open, startup_save_pending, save_slot_ready, save_slot_owned,
		goal_confirmed, building_rotation, foundation_level, wheel_level, wheel_tiles,
		transmission_controls.active_tool if transmission_controls != null else "",
		transmission_controls.selected_axis if transmission_controls != null else ""]

func _display_parts() -> Dictionary:
	if state.get("options", {}).get("native", false):
		return state.get("part_kits", {}).get(client, {})
	return state.get("parts", {})

func _parts_are_shared() -> bool:
	return false

func _confirmed_drive_status(motion: Variant) -> String:
	if not motion is Dictionary or motion.is_empty():
		return "Power status unavailable"
	if motion.get("state") == "rotating":
		if typeof(motion.get("numerator")) != TYPE_INT or typeof(motion.get("denominator")) != TYPE_INT or motion.denominator <= 0:
			return "Power status unavailable"
		var description := "Rate %d / %d" % [motion.numerator, motion.denominator]
		if motion.has("capacity"):
			description += "\nLoad %.2f / capacity %.2f" % [motion.get("impact", 0.0), motion.capacity]
		return description
	elif motion.get("overloaded", false):
		var description := "Overloaded · load %.2f / capacity %.2f" % [motion.get("impact", 0.0), motion.get("capacity", 0.0)]
		var limiting: Variant = motion.get("limiting_part", "")
		if limiting is String and not limiting.is_empty():
			var part_kind: String = str(motion.get("limiting_kind", "drive part")).replace("_", " ").capitalize()
			description += "\nLimit: %s (%s). Replace with copper or split the load." % [part_kind, limiting]
		else:
			description += "\nAdd power or reduce load."
		return description
	return str(motion.get("state", "disconnected")).capitalize()

func _transmission_inspection(part: Dictionary, motion: Dictionary) -> String:
	var name := "Shaft"
	if part.kind == "gear":
		name = {2: "Small Cogwheel", 4: "Large Cogwheel"}.get(part.get("teeth"), "Cogwheel")
	elif part.kind == "gearbox":
		name = "Horizontal Gearbox"
	elif part.kind == "vertical_gearbox":
		name = "Vertical Gearbox"
	elif part.kind == "chain_drive":
		name = "Encased Chain Drive · link %s" % ["X", "Y", "Z"][part.get("relay_axis", 0)]
	return "%s · %s axis\nGrid %s\n%s" % [name, ["X", "Y", "Z"][part.axis], str(part.center), _confirmed_drive_status(motion)]

func _machine_inspection(entity: Dictionary, stock: Dictionary, motion: Variant, native: bool) -> String:
	var description := "%s\nSquare %s" % [NAMES.get(entity.kind, entity.kind), str(entity.cell)]
	if entity.kind == "processor":
		description += "\n%d in · %d held · %d ready" % [stock.get("input", 0), stock.get("held", 0), stock.get("output", 0)]
	if native:
		description += "\n" + _confirmed_drive_status(motion)
	return description

func _belt_inspection(span: Dictionary, motions: Dictionary) -> String:
	var occupied := 0
	for slot: Variant in span.get("slots", []):
		if slot is Dictionary:
			occupied += 1
	var drive: Variant = motions.get(span.get("from", ""))
	return "Mechanical belt\n%d occupied %s\n%s\nRecover contents before dismantling." % [occupied, "position" if occupied == 1 else "positions", _confirmed_drive_status(drive)]

func _refresh_ui() -> void:
	_refresh_hand_trees()
	if stock_label == null:
		return
	if _object_menu_open() and not _contains_target(state, object_menu_target):
		object_menu.hide()
		return
	_refresh_transmission()
	var inventory := int(state.inventories.get(client, 0))
	goal_progress.max_value = 4
	goal_progress.value = clampi(inventory, 0, 4)
	parts_label.text = "BUILD / INVENTORY"
	goal_label.text = "FIRST SHIFT\nBring back 4 plates\n%d / 4 collected" % inventory
	confirm_button.disabled = inventory < 4 or goal_confirmed or explanation_open
	confirm_button.text = "Objective confirmed" if goal_confirmed else "Confirm four plates  [Ctrl+Enter]"
	var belt_raw: int = int(state.get("line_belt_raw", 0)) if _native_transmission() else state.stock.belt
	stock_label.text = "ORE DEPOSIT  %d copper\nIN THE LINE  %d copper\nPRESS OUTLET  %d copper plate" % [state.stock.source,
		state.stock.collector + belt_raw + state.stock.input + state.stock.held, state.stock.output]
	power_label.text = "DRIVE RUNNING" if state.get("powered", false) else "DRIVE NEEDS CONNECTIONS"
	save_button.disabled = explanation_open or not save_slot_ready or startup_save_pending or not state.get("actors", {}).get(client, {}).get("ready", false)
	load_button.disabled = explanation_open or not save_slot_ready
	save_button.tooltip_text = "Save worksite  [F5]" if save_slot_ready else "Saving needs a fresh worksite session."
	load_button.tooltip_text = "How to reopen save  [F9]"
	if actor_label != null:
		actor_label.visible = true
		actor_label.text = "CHARACTER READY · BUILD NEARBY" if state.get("actors", {}).get(client, {}).get("ready", false) else "CHARACTER STARTING…"
	if developer_mode_label != null:
		var fast_enabled: bool = state.get("options", {}).get("developer_conveniences", false)
		developer_mode_label.add_theme_color_override("font_color",
			Color("edb95d") if fast_enabled else Color("64777a"))
		developer_mode_label.tooltip_text = "Developer conveniences %s. F3 toggles fast manual harvesting." % (
			"enabled" if fast_enabled else "disabled")
		developer_mode_label.accessibility_name = developer_mode_label.tooltip_text
	for tool in ["flow"]:
		var button: Button = tool_buttons[tool]
		button.disabled = explanation_open
		button.button_pressed = mode == tool
		if transmission_controls != null and not transmission_controls.active_tool.is_empty():
			button.button_pressed = false
	retrieve_button.disabled = explanation_open or state.stock.output < 1 or not state.entities.has(selected) or state.entities[selected].kind != "processor"
	remove_button.disabled = explanation_open or not _contains_target(state, selected)
	selection_ring.visible = mode in ["inspect", "flow", "drive"] and state.entities.has(selected)
	if state.entities.has(selected):
		selection_ring.position = _entity_position(state.entities[selected]) + Vector3(0, 0.02, 0)
		inspector.text = _machine_inspection(state.entities[selected], state.stock, state.get("motion", {}).get(selected), _native_transmission())
		inspector.text += "\n" + _inspection_hint()
	elif state.get("foundations", {}).has(selected):
		var surface: Dictionary = state.foundations[selected]
		selection_ring.visible = mode in ["inspect", "flow", "drive"]
		selection_ring.position = _entity_position(surface) + Vector3(0, 0.02, 0)
		var floor_type := "Factory floor" if int(surface.level) % Geometry.HEIGHT_DENOMINATOR == 0 else "Access step · machines need a factory floor"
		inspector.text = "%s\nSquare %s\nTop %.2f m\nRemove to reclaim the carried part." % [floor_type, str(surface.cell), surface.level * Geometry.HEIGHT_STEP]
	elif _native_transmission() and state.get("transmission_parts", {}).has(selected):
		var part: Dictionary = state.transmission_parts[selected]
		var motion: Dictionary = state.get("motion", {}).get(selected, {})
		inspector.text = _transmission_inspection(part, motion)
	elif _native_transmission() and state.get("belt_spans", {}).has(selected):
		inspector.text = _belt_inspection(state.belt_spans[selected], state.get("motion", {}))
	elif _native_transmission() and state.get("fabrication_hub", {}).get("installed", false) \
			and selected == state.fabrication_hub.get("id", ""):
		inspector.text = "Pod workshop\nGrid center %s\nPress E for recipes and stowage." % \
			str(state.fabrication_hub.get("center", []))
	elif _native_transmission() and state.get("placed_components", {}).has(selected):
		var component: Dictionary = state.placed_components[selected]
		inspector.text = "%s\nGrid center %s" % [
			str(component.get("component", "part")).replace("_", " ").capitalize(),
			str(component.get("center", []))]
		if component.get("component", "") == "wooden_workbench":
			inspector.text += "\nPress E for recipes when nearby."
	else:
		inspector.text = "E opens a pointed machine; hold E to turn a fitted crank."
	inspector.tooltip_text = inspector.text
	if _object_menu_open() and _contains_target(state, selected):
		var detail_lines := inspector.text.split("\n")
		inspector.text = "\n".join(detail_lines.slice(1, detail_lines.size()))
	else:
		var inspection_lines := inspector.text.split("\n")
		inspector.text = "\n".join(inspection_lines.slice(0, mini(3, inspection_lines.size())))
	_refresh_guided_tools()
	_refresh_manager_log()
	if arrival_assembly_controls != null:
		arrival_assembly_controls.refresh(state, client, selected, _can_use_object_actions())
		if _object_menu_open():
			var selected_placed: bool = state.get("placed_components", {}).has(selected)
			arrival_assembly_controls.reclaim_button.visible = selected_placed
			if selected_placed:
				remove_button.visible = false
		arrival_assembly_scroll.visible = arrival_assembly_controls.visible
		if object_menu_operations != null:
			object_menu_operations.visible = _object_menu_open() and _object_supports_operations(object_menu_target) \
				and arrival_assembly_scroll.visible
	if recovery_actions != null:
		recovery_actions.refresh()
	if loose_material_controls != null:
		loose_material_controls.refresh()
	if arrival_assembly_controls != null and arrival_assembly_controls.inventory_section.is_visible_in_tree():
		# The selected slide's workbed shows the same finite material at its actual
		# work face and outlet. Keep one transfer surface in this object panel.
		if recovery_actions != null:
			recovery_actions.visible = false
		if loose_material_controls != null:
			loose_material_controls.visible = false
	if model is NativeWorldModel:
		ui_refresh_key = _native_ui_key()

func _catalog_open() -> bool:
	return building_hotbar != null and building_hotbar.catalog.visible

func _refresh_manager_log() -> void:
	if manager_log_current == null or goal_label == null:
		return
	var complete: bool = state.get("workshop_completed_actors", []).has(client)
	manager_log_completion_entry.visible = complete
	manager_log_projects.visible = complete
	var viewport_height := get_viewport().get_visible_rect().size.y
	var half_height := minf(300.0 if complete else 215.0,
		maxf(180.0, (viewport_height - 32.0) * 0.5))
	manager_log_panel.offset_top = -half_height
	manager_log_panel.offset_bottom = half_height
	var lines := goal_label.text.split("\n")
	var current := lines[lines.size() - 1] if not lines.is_empty() else "Inspect the worksite."
	manager_log_current.text = "CURRENT FIELD CUE\n" + current

func _notice_workshop_completion(complete: bool) -> void:
	var previously_complete: Variant = workshop_completion_observed
	workshop_completion_observed = complete
	if previously_complete != false or not complete:
		return
	_message("Plate collected. Open the Work log [J].")
	if workshop_completion_audio == null:
		workshop_completion_audio = AudioStreamPlayer.new()
		workshop_completion_audio.name = "WorkshopCompletionChime"
		workshop_completion_audio.volume_db = -13.0
		workshop_completion_audio.stream = ArrivalRevealAudio.workshop_chime()
		add_child(workshop_completion_audio)
	workshop_completion_audio.play()
	workshop_completion_cue_count += 1

func _toggle_manager_log() -> void:
	if manager_log_layer == null or arrival_reveal_active or explanation_open or _catalog_open():
		return
	_release_character_controls()
	manager_log_open = not manager_log_open
	manager_log_layer.visible = manager_log_open
	_refresh_ui()

func _slide_outlet_holds_plate(press: Dictionary) -> bool:
	var exits: Array = []
	var selected_exit: Array = press.get("selected_exit", [])
	if not selected_exit.is_empty():
		exits.append(selected_exit)
	else:
		for feed: Dictionary in press.get("open_feeds", []):
			exits.append(feed.get("exit", []))
	for drop: Dictionary in state.get("dropped_material", []):
		if int(drop.get("products", 0)) > 0 and exits.has(drop.get("center", [])):
			return true
	return false

func _first_plate_material_cue(carried: Dictionary) -> String:
	var recipes: Dictionary = state.get("component_recipes", {})
	var timber_needed := 0
	var copper_needed := 1 # The blank that becomes the first plate.
	for part: String in ["anvil", "flat_head", "wooden_slide", "hand_crank"]:
		var cost: Dictionary = recipes.get(part, {})
		if cost.is_empty():
			return "Gather timber and copper with the multitool [E]."
		timber_needed += int(cost.get("timber", 0))
		copper_needed += int(cost.get("copper", 0))
	var timber_left := maxi(0, timber_needed - int(carried.get("timber", 0)))
	var copper_left := maxi(0, copper_needed - int(carried.get("raw", 0)))
	if timber_left > 0 and copper_left > 0:
		return "Gather %d timber and %d copper pieces with the multitool [E]." % [timber_left, copper_left]
	if timber_left > 0:
		return "Gather %d timber with the multitool [E] for the first plate." % timber_left
	if copper_left > 0:
		return "Gather %d copper piece%s with the multitool [E]." % [
			copper_left, "" if copper_left == 1 else "s"]
	return "Use Build [B] to craft and fit press parts from carried stock."

func _refresh_guided_tools(snapshot_ready: bool = true) -> void:
	if rotation_button != null:
		rotation_button.visible = _native_transmission() and mode in ["collector", "processor", "wheel"] and not explanation_open
		rotation_button.disabled = not snapshot_ready or not _can_choose_tool()
		rotation_button.text = "Rotate [R]" if mode == "wheel" else "Rotate [R] · %d°" % (building_rotation * 90)
		rotation_button.tooltip_text = "Turn the building by a quarter turn before placing it. Its input, output and horizontal drive axle turn together."
		if mode == "wheel" and transmission_controls != null:
			rotation_button.disabled = rotation_button.disabled or transmission_controls.selected_axis == "y"
			rotation_button.tooltip_text = "Turn the wheel axle between X and Z."
	if foundation_level_controls != null:
		foundation_level_controls.visible = _native_transmission() and mode in ["foundation", "wheel"] and not explanation_open and snapshot_ready
		foundation_area_toggle.visible = foundation_level_controls.visible and mode == "foundation"
		foundation_steps_toggle.visible = foundation_area_toggle.visible
		foundation_steps_toggle.text = "Access steps  [Z]"
		foundation_area_toggle.text = "Area: two corners  [V]"
		foundation_level_label.text = _construction_height_text()
		(foundation_level_controls.get_child(0) as Button).text = "−  [PgDn]"
		(foundation_level_controls.get_child(2) as Button).text = "+  [PgUp]"
		wheel_size_controls.visible = foundation_level_controls.visible and mode == "wheel"
		(wheel_size_controls.get_child(0) as Button).text = "−  [Shift+PgDn]"
		(wheel_size_controls.get_child(2) as Button).text = "+  [Shift+PgUp]"
	footer_snapshot_ready = snapshot_ready
	_queue_footer_fit()
	if building_hotbar != null:
		building_hotbar.refresh(snapshot_ready)
	# This is a view of confirmed facts, not persistent progression or admission.
	var kinds: Dictionary = {}
	for entity in state.get("entities", {}).values():
		kinds[String(entity.kind)] = true
	var offered := {"collector": true}
	if kinds.has("collector"):
		offered.belt = true
	if kinds.has("belt") or (_native_transmission() and not state.get("belt_spans", {}).is_empty()):
		offered.processor = true
	if kinds.has("processor"):
		offered.wheel = true
	if (kinds.has("collector") and kinds.has("belt")) or (kinds.has("belt") and kinds.has("processor")):
		offered.flow = true
	if kinds.has("wheel") and kinds.size() > 1:
		offered.drive = true
	var arrival := _native_transmission() and state.has("hand_sources")
	var step := {"tool": "inspect", "text": ""} if arrival else _guided_step(kinds)
	if state.get("options", {}).get("foundations", false):
		offered.foundation = true
	for tool in tool_buttons:
		if building_hotbar.catalog_buttons.has(tool):
			continue
		var button: Button = tool_buttons[tool]
		# Keyboard selection stays visible even when it precedes the suggestion.
		button.visible = (NAMES.has(tool) or building_hotbar.catalog_buttons.has(tool) or offered.has(tool) or mode == tool) \
			and not (arrival and tool in ["collector", "processor"])
		if tool == "foundation" and not state.get("options", {}).get("foundations", false):
			button.visible = false
		if tool in ["gear", "gearbox", "vertical_gearbox", "chain_drive"] and not _native_transmission():
			button.visible = false
		for color_name in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			if tool == step.tool:
				button.add_theme_color_override(color_name, Color("edcc8d"))
			else:
				button.remove_theme_color_override(color_name)
	var inventory := int(state.get("inventories", {}).get(client, 0))
	goal_progress.value = clampi(inventory, 0, 4)
	goal_progress.visible = not arrival
	var workshop_complete: bool = arrival and state.get("workshop_completed_actors", []).has(client)
	objective_heading.text = ("FIRST WORKSHOP  /  COMPLETE" if workshop_complete else "FIRST WORKSHOP  /  01") \
		if arrival else "FIRST SHIFT  /  01"
	if arrival:
		var carried: Dictionary = state.get("cargo", {}).get(client, {})
		var next_work := _first_plate_material_cue(carried)
		var press_ready := false
		var sliding_press_ready := false
		var sliding_plate_waiting := false
		var ready_slide_has_crank := false
		var sliding_feed_blocked := false
		var collector_ready := false
		for press: Dictionary in state.get("guided_press_assemblies", []):
			press_ready = press_ready or press.get("status") == "ready"
		for press: Dictionary in state.get("sliding_press_assemblies", []):
			sliding_press_ready = sliding_press_ready or press.get("status") == "ready"
			if press.get("status") == "ready":
				sliding_plate_waiting = sliding_plate_waiting or _slide_outlet_holds_plate(press)
			sliding_feed_blocked = sliding_feed_blocked or press.get("status") == "blocked_feed"
			press_ready = press_ready or press.get("status") == "ready"
			if press.get("status") == "ready":
				var slide_id: String = str(press.get("parts", {}).get("slide", ""))
				for crank: Dictionary in state.get("crank_items", {}).values():
					ready_slide_has_crank = ready_slide_has_crank or (
						not slide_id.is_empty() and crank.get("attached_to", "") == slide_id)
		for collector: Dictionary in state.get("collector_assemblies", []):
			collector_ready = collector_ready or collector.get("status") == "ready"
		if snapshot_ready:
			_notice_workshop_completion(workshop_complete)
		if workshop_complete:
			next_work = "Open Work log [J] for the collector project, or keep building."
		elif sliding_plate_waiting:
			next_work = "Plate at outlet. Open the press [E], then collect it [P]."
		elif sliding_press_ready and ready_slide_has_crank:
			next_work = "Open the fitted press [E]. Move copper to the workbed, then point at the crank and hold E."
		elif sliding_press_ready:
			next_work = "Fit your carried crank at a slide input [B], then open the press [E]." \
				if int(carried.get("components", {}).get("hand_crank", 0)) > 0 else \
				"Craft a hand crank [B], fit it at a slide input, then open the press [E]."
		elif state.get("first_plate_unlock", false) and sliding_feed_blocked:
			next_work = "Clear an X-side feed path [F], then open the press [E]."
		elif press_ready:
			next_work = "Open the working press [E] to feed or turn."
		elif state.get("first_plate_unlock", false) and not state.get("placed_components", {}).is_empty():
			next_work = "Inspect placed parts [E] and use Build [B] for what the press still needs."
		elif state.get("first_plate_unlock", false) and (
				not carried.get("components", {}).is_empty() or
				int(carried.get("timber", 0)) >= 3 or int(carried.get("raw", 0)) >= 4):
			next_work = "Use Build [B] to craft and fit press parts from carried stock."
		elif collector_ready and int(state.get("line_belt_raw", 0)) > 0:
			next_work = "Blank on belt. Inspect its outlet [E] or recover it."
		elif collector_ready:
			next_work = "Collector ready. Cut ore or connect a material route."
		elif not state.get("placed_components", {}).is_empty():
			next_work = "Inspect parts [E] or build [B]."
		elif not carried.get("components", {}).is_empty():
			next_work = "Place a carried part [B]."
		elif int(carried.get("timber", 0)) >= 3:
			next_work = "Craft a part in Build [B]."
		goal_label.text = (next_work if workshop_complete else "FORM A PLATE · KEEP IT\n" + next_work) \
			if snapshot_ready else "Connect to the worksite."
	else:
		goal_label.text = "Make 4 plates  ·  %d / 4\n%s" % [inventory, step.text] if snapshot_ready else "Connect to the worksite."
	confirm_button.visible = not arrival and snapshot_ready and (inventory >= 4 or goal_confirmed)
	help_button.visible = true
	actor_label.visible = true
	controls_label.text = "WASD move · E interact · B build · F remove · H help" if arrival \
		else "B catalog · 1–8 build · E open · F remove · H help"
	if explanation_open:
		help_body.text = goal_label.text + "\n\n" + controls_label.text
	_refresh_engineering(snapshot_ready)
	var target_selected: bool = _contains_target(state, selected)
	inspector_title.visible = object_menu == null and (target_selected or not snapshot_ready or not _can_choose_tool())
	inspector.visible = target_selected if object_menu != null else target_selected \
		or not snapshot_ready or not _can_choose_tool()
	retrieve_button.visible = state.get("entities", {}).get(selected, {}).get("kind") == "processor"
	remove_button.visible = target_selected
	inspection_actions.visible = target_selected
	for divider in inspector.get_parent().get_children():
		if divider is HSeparator:
			divider.visible = target_selected

func _placement_ready() -> bool:
	return _can_control_character()

func _preview_pointer_clear() -> bool:
	# This query does not consume input or move the pointer. The live preview
	# follows the current camera ray, including when the view moves under it.
	if component_nudge_active and mode == "component":
		return is_inside_tree()
	return is_inside_tree() and get_viewport().get_visible_rect().has_point(_pointed_screen_position()) \
		and (get_viewport().gui_get_hovered_control() == null or _pointer_over_placement_options())

func _pointer_over_placement_options() -> bool:
	if placement_options_panel == null or not placement_options_panel.visible or not is_inside_tree():
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	while hovered != null:
		if hovered == placement_options_panel:
			return true
		hovered = hovered.get_parent() as Control
	return false

func _machine_preview_cell() -> Vector2i:
	return placement_cell_cache if _pointer_over_placement_options() else _screen_cell(get_viewport().get_mouse_position())

func _preview_axis() -> int:
	if not _native_transmission() or transmission_controls == null:
		return 0
	var axis: int = ["x", "y", "z"].find(transmission_controls.selected_axis)
	if mode in ["collector", "processor"] and axis != 1 and building_rotation % 2 == 1:
		return 2 - axis
	return axis

func _rotate_building() -> void:
	if not _native_transmission() or not _can_choose_tool() or mode not in ["collector", "processor", "wheel"] or explanation_open:
		return
	if mode == "wheel":
		if transmission_controls == null or transmission_controls.selected_axis not in ["x", "z"]:
			return
		transmission_controls.selected_axis = "z" if transmission_controls.selected_axis == "x" else "x"
		transmission_controls.refresh()
	else:
		building_rotation = (building_rotation + 1) % 4
	_update_cursor()
	_refresh_ui()

func _cycle_placement_axis() -> void:
	if transmission_controls == null or not _can_choose_tool() or mode not in ["wheel", "gear", "drive", "vertical_gearbox", "chain_drive"]:
		return
	var axes := ["x", "y", "z"]
	var next_axis: int = (axes.find(transmission_controls.selected_axis) + 1) % axes.size()
	if mode in ["wheel", "vertical_gearbox"] and next_axis == 1:
		next_axis = 2
	transmission_controls._axis_selected(next_axis)
	transmission_controls.refresh()
	_update_cursor()
	_refresh_ui()

func _refresh_placement_options() -> void:
	if placement_options_panel == null:
		return
	var placing_machine := machine_preview != null and machine_preview.visible
	var placing_component := mode == "component" and component_preview != null and component_preview.visible
	var placing_pod := mode == "pod_workshop" and hover != null and hover.visible
	var placing_transmission: bool = _native_transmission() and transmission_controls != null \
		and transmission_controls.active_tool in ["gear", "place_shaft", "belt_span", "gearbox", "vertical_gearbox", "chain_drive"]
	var shown: bool = _native_transmission() and not explanation_open and not _catalog_open() and _can_choose_tool() \
		and (placing_machine or placing_component or placing_pod or placing_transmission)
	placement_options_panel.visible = shown
	if not shown:
		return
	var tool: String = {"place_shaft": "drive", "belt_span": "belt"}.get(transmission_controls.active_tool, mode) \
		if placing_transmission else mode
	placement_options_title.text = "CONNECT BELT" if tool == "belt" else "PLACE %s" % {
		"gearbox": "HORIZONTAL GEARBOX", "vertical_gearbox": "VERTICAL GEARBOX",
		"chain_drive": "ENCASED CHAIN DRIVE",
		"component": arrival_assembly_controls.selected_name().replace("_", " ").to_upper() if arrival_assembly_controls != null else "COMPONENT"}.get(tool, NAMES.get(tool, tool).to_upper())
	placement_options_hint.text = {
		"foundation": "Left click to build · choose height or area below · Esc cancels",
		"wheel": "Left click to build · R turns the axle · choose size or height below",
		"gear": "Left click to build · choose axle, height or size below",
		"drive": "Left click to build · choose axle or height below",
		"gearbox": "Left click to build · adjust height below",
		"vertical_gearbox": "Left click to build · choose axle or height below",
		"chain_drive": "Left click to build · choose axle and chain link direction below",
		"belt": "Click two parallel shafts · Esc cancels",
		"component": _component_placement_hint(),
		"pod_workshop": "Left click to reinstall on the full tile · Esc cancels",
	}.get(tool, "Left click to build · R rotates · Esc cancels")
	placement_options_axis.visible = tool in ["wheel", "gear", "drive", "vertical_gearbox", "chain_drive"]
	placement_options_axis.text = "Axle: %s  [X]" % (transmission_controls.selected_axis.to_upper()
		if transmission_controls != null else "X")
	_fit_placement_options()

func _fit_placement_options() -> void:
	var parent := placement_options_panel.get_parent() as Control
	var height: float = placement_options_panel.get_combined_minimum_size().y
	placement_options_panel.size = Vector2(maxf(302.0, placement_options_panel.get_combined_minimum_size().x), height)
	var hotbar_height: float = building_hotbar.size.y if building_hotbar != null else 0.0
	var footer_height: float = status_footer.size.y if status_footer != null and status_footer.visible else 0.0
	placement_options_panel.position = Vector2(maxf(18.0, parent.size.x - placement_options_panel.size.x - 18.0),
		18.0 if mode == "component" else maxf(18.0,
			parent.size.y - hotbar_height - footer_height - placement_options_panel.size.y - 48.0))

func _refresh_machine_preview() -> void:
	if machine_preview != null:
		machine_preview.visible = false
	if explanation_open or not _placement_ready() or not _preview_pointer_clear():
		return
	if _native_transmission() and transmission_controls != null \
			and transmission_controls.active_tool in ["gear", "place_shaft"]:
		_refresh_transmission_preview()
		return
	if not NAMES.has(mode) or int(_display_parts().get(mode, 0)) < 1:
		return
	if transmission_controls != null and not transmission_controls.active_tool.is_empty():
		return
	var cell := _machine_preview_cell()
	if not _pointer_over_placement_options():
		placement_cell_cache = cell
	if not _build_cell_allowed(cell) or not _machine_floor_aligned(cell) or (mode != "foundation" and not _entity_at_cell(cell).is_empty()):
		return
	var area_size := Vector2i.ONE
	var area_origin := cell
	if mode == "foundation" and foundation_area_mode and foundation_area_started:
		area_size = Vector2i(absi(cell.x - foundation_area_start.x) + 1, absi(cell.y - foundation_area_start.y) + 1)
		area_origin = Vector2i(mini(cell.x, foundation_area_start.x), mini(cell.y, foundation_area_start.y))
		if area_size.x > 256 or area_size.y > 256 or area_size.x * area_size.y > 256:
			return
	var axis := _preview_axis()
	if axis < 0:
		return
	var facing := building_rotation if mode in ["collector", "processor"] else 0
	var level := _construction_level(cell)
	if mode == "collector" and _native_transmission() and not Geometry.collector_intake_boxes(
		{"kind": "collector", "cell": [cell.x, cell.y], "level": level}).get("accepted", false):
		return
	var key := "%s:%d:%s:%d:%d:%s" % [mode, axis, str(_native_transmission()), wheel_tiles if mode == "wheel" else 0, facing,
		str([cell.x, cell.y, level]) if mode == "collector" else ""]
	var packaged: bool = mode == "foundation" or _native_transmission() and axis == 0 and facing == 0 \
		and (mode != "wheel" or wheel_tiles == 3) \
		and (mode != "collector" or cell == Vector2i(0, 1) and level == 0)
	var pooled: Node3D = packed_preview_nodes.get(mode) if packaged else null
	_choose_machine_preview(pooled)
	if pooled != null:
		machine_preview_key = key
	machine_preview.basis = Basis.IDENTITY
	machine_preview.position = _cell_position([cell.x, cell.y]) + Vector3.UP * level * Geometry.HEIGHT_STEP
	if key != machine_preview_key:
		for child in machine_preview.get_children():
			child.free()
		# The placed wheel's observed animation target must not be replaced by
		# the visual-only assembly. Preview construction changes no projection.
		var placed_rotor := wheel_rotor
		if mode == "foundation":
			_assemble_foundation(machine_preview)
		else:
			if packaged and packed_preview_templates.has(mode):
				var packed: PackedScene = packed_preview_templates.get(mode)
				var template := packed.instantiate() as Node3D
				machine_preview.set_meta("material_rotated", template.get_meta("material_rotated", false))
				for part in template.get_children():
					part.owner = null
					template.remove_child(part)
					machine_preview.add_child(part)
				template.free()
			else:
				var variant := _packed_machine_preview_variant(mode, axis, wheel_tiles, facing, cell, level)
				if preview_variant_pending:
					wheel_rotor = placed_rotor
					return
				if variant != null:
					machine_preview.set_meta("material_rotated", variant.get_meta("material_rotated", false))
					for part in variant.get_children():
						_clear_preview_owners(part)
						variant.remove_child(part)
						machine_preview.add_child(part)
					variant.free()
				else:
					_assemble_machine(machine_preview, {"kind": mode, "axis": axis, "tiles": wheel_tiles,
						"rotation": facing, "cell": [cell.x, cell.y], "level": level}, mode == "belt" and axis == 0)
					if mode in ["collector", "processor"]:
						_preview_port(machine_preview, facing, mode == "collector")
		wheel_rotor = placed_rotor
		_style_machine_preview(machine_preview)
		machine_preview_key = key
	machine_preview.scale = Vector3.ONE
	if mode == "foundation":
		machine_preview.scale = Vector3(area_size.x, 1, area_size.y)
		machine_preview.position.x = (area_origin.x + (area_size.x - 1) / 2.0) * PITCH
		machine_preview.position.z = (area_origin.y + (area_size.y - 1) / 2.0) * PITCH
	machine_preview.visible = true

func _refresh_transmission_preview() -> void:
	var context: Dictionary = transmission_controls._context()
	if context.is_empty() or not context.usable:
		return
	var gear: bool = transmission_controls.active_tool == "gear"
	var size: int = transmission_controls.gear_teeth if gear else transmission_controls.shaft_half_span
	if transmission_controls._count(context, "gear" if gear else "shaft", size if gear else 0, 0 if gear else size) < 1:
		return
	var axis := _preview_axis()
	if axis < 0:
		return
	var center: Array
	if _pointer_over_placement_options() and not transmission_preview_point.is_empty():
		center = transmission_preview_point.duplicate()
		center[1] = transmission_controls.snapped_height if transmission_controls.auto_height else transmission_controls.gear_height
	else:
		center = _transmission_center(_pointed_screen_position())
		transmission_preview_point = center.duplicate()
	if not Geometry._mechanical_point(center):
		return
	_choose_machine_preview()
	machine_preview.position = Geometry._mechanical_center(center)
	var key := "transmission:%s:%d:%d" % [transmission_controls.active_tool, axis, size]
	if key != machine_preview_key:
		for child in machine_preview.get_children():
			child.free()
		var assets = load("res://opening/native_transmission_assets.gd")
		machine_preview.basis = load("res://opening/native_transmission_presenter.gd").axis_basis(axis)
		if gear:
			var mesh := MeshInstance3D.new()
			mesh.name = "Cogwheel"
			mesh.mesh = assets.complete_gear_mesh(PITCH / 2.0, size, Color("687a7b"), PITCH)
			machine_preview.add_child(mesh)
		else:
			assets.shaft(machine_preview, size * Geometry.HEIGHT_STEP * 2.0, Color("687a7b"))
		_style_machine_preview(machine_preview)
		machine_preview_key = key
	machine_preview.scale = Vector3.ONE
	machine_preview.visible = true

func _preview_port(parent: Node3D, facing: int, output: bool) -> void:
	var forward := Vector3.RIGHT.rotated(Vector3.UP, -float(facing) * PI / 2.0)
	var side := forward if output else -forward
	var at := side * 0.9 + Vector3.UP * 0.6
	var direction := forward
	var across := Vector3(-direction.z, 0, direction.x)
	var tip := at + direction * 0.23
	_route_segment(parent, "PortArrow", at - direction * 0.23, tip, 0.055, Color("edcc8d"))
	_route_segment(parent, "PortArrowLeft", tip - direction * 0.15 + across * 0.12, tip, 0.055, Color("edcc8d"))
	_route_segment(parent, "PortArrowRight", tip - direction * 0.15 - across * 0.12, tip, 0.055, Color("edcc8d"))
	var label := Label3D.new()
	label.name = "MaterialPortLabel"
	label.text = "OUT" if output else "IN"
	label.position = side * 0.9 + Vector3.UP * 0.95
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.pixel_size = 0.01
	label.outline_size = 6
	label.set_meta("port_side", side)
	parent.add_child(label)

func _style_machine_preview(node: Node) -> void:
	# Per-instance overrides leave shared placed materials and meshes intact.
	# Neutral amber is a form/footprint preview, never an admission verdict.
	if machine_preview_material == null:
		machine_preview_material = StandardMaterial3D.new()
		machine_preview_material.albedo_color = Color(0.88, 0.75, 0.49, 0.32)
		machine_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		machine_preview_material.roughness = 0.75
		machine_preview_material.metallic = 0.0
	if node is MeshInstance3D:
		node.material_override = machine_preview_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_style_machine_preview(child)

func _guided_span_path(routes: Array, collector: Vector3i, processor: Vector3i, powered: bool) -> bool:
	# A loose item leaving a span can be picked up on any tile of another span.
	# This is advisory over confirmed projection facts, not construction authority.
	var queue: Array[int] = []
	var visited := {}
	for index in range(routes.size()):
		var route: Dictionary = routes[index]
		var entry := 0 if collector == route.before else (1 if collector == route.after else -1)
		if entry < 0 or (powered and (not route.rotating or (entry == 0) != route.forward)):
			continue
		queue.append(index)
		visited[index] = true
	while not queue.is_empty():
		var current: int = queue.pop_front()
		var route: Dictionary = routes[current]
		var exits: Array = [route.after if route.forward else route.before] if powered else [route.before, route.after]
		for outlet: Vector3i in exits:
			if outlet == processor:
				return true
			for index in range(routes.size()):
				var next: Dictionary = routes[index]
				if visited.has(index) or (powered and not next.rotating) or not next.tiles.has(outlet):
					continue
				visited[index] = true
				queue.append(index)
	return false

func _guided_span_routes() -> Dictionary:
	var result := {"physical": false, "powered": false, "cargo": false}
	var parts: Variant = state.get("transmission_parts", {})
	var spans: Variant = state.get("belt_spans", {})
	var entities: Variant = state.get("entities", {})
	var motion: Variant = state.get("motion", {})
	if not parts is Dictionary or not spans is Dictionary or not entities is Dictionary or not motion is Dictionary:
		return result
	var collector: Variant = null
	var processor: Variant = null
	for entity: Variant in entities.values():
		if not entity is Dictionary or not entity.get("center") is Array or entity.center.size() != 3:
			continue
		if entity.get("kind") == "collector":
			collector = Vector3i(entity.center[0], entity.center[1], entity.center[2])
		elif entity.get("kind") == "processor":
			processor = Vector3i(entity.center[0], entity.center[1], entity.center[2])
	var routes: Array = []
	for span: Variant in spans.values():
		if not span is Dictionary or not span.get("slots") is Array:
			continue
		for item: Variant in span.slots:
			if item is Dictionary:
				result.cargo = true
		var first: Variant = parts.get(span.get("from", ""))
		var last: Variant = parts.get(span.get("to", ""))
		if not first is Dictionary or not last is Dictionary or first.get("axis") not in [0, 2] or first.get("axis") != last.get("axis") or not first.get("center") is Array or not last.get("center") is Array or first.center.size() != 3 or last.center.size() != 3:
			continue
		var start := Vector3i(first.center[0], first.center[1], first.center[2])
		var finish := Vector3i(last.center[0], last.center[1], last.center[2])
		var delta := finish - start
		var steps := maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.z))) / 4
		if steps < 1 or steps > 19 or (delta.x == 0 and delta.z == 0) or delta[first.axis] != 0:
			continue
		var valid_path := true
		for coordinate in range(3):
			if start[coordinate] % 4 != 0 or (delta[coordinate] != 0 and absi(delta[coordinate]) != steps * 4):
				valid_path = false
		if not valid_path:
			continue
		var step := delta / steps
		var tiles: Array = []
		for index in range(steps + 1):
			tiles.append(start + step * index)
		var shaft_motion: Variant = motion.get(span.get("from", ""), {})
		var rotating: bool = shaft_motion is Dictionary and shaft_motion.get("state") == "rotating" and typeof(shaft_motion.get("numerator")) == TYPE_INT and shaft_motion.numerator != 0
		var positive: bool = rotating and ((first.axis == 0 and shaft_motion.numerator > 0) or (first.axis == 2 and shaft_motion.numerator < 0))
		var along := delta.z if first.axis == 0 else delta.x
		routes.append({"before": start - step, "after": finish + step, "tiles": tiles,
			"rotating": rotating, "forward": positive == (along > 0)})
	if collector is Vector3i and processor is Vector3i:
		result.physical = _guided_span_path(routes, collector, processor, false)
		result.powered = _guided_span_path(routes, collector, processor, true)
		# The native assessment also accounts for collector-side competition;
		# a geometric path alone can be starved by an earlier fast branch.
		var reports: Variant = state.get("opening_engineering", {})
		var report: Variant = reports.get(client, {}) if reports is Dictionary else {}
		if report is Dictionary and report.get("schema") == 1 and report.get("format") == "factory-opening-engineering" \
				and report.get("actor") == client and report.get("known_actor") == true and typeof(report.get("belt_forward")) == TYPE_BOOL:
			result.powered = result.physical and report.belt_forward
	return result

func _guided_step(kinds: Dictionary) -> Dictionary:
	if goal_confirmed:
		return {"text": "Four plates confirmed. Keep building or try another layout.", "tool": "inspect"}
	if int(state.get("inventories", {}).get(client, 0)) >= 4:
		return {"text": "Four plates ready. Confirm when you are ready.", "tool": "inspect"}
	if int(state.get("stock", {}).get("output", 0)) > 0:
		return {"text": "Plate ready. Point at the press and open [E], then collect [R].", "tool": "inspect"}
	if not kinds.has("collector"):
		if _native_transmission():
			return {"text": FIRST_COLLECTOR_HINT if mode == "inspect" else "Place a collector at the exposed ore deposit.", "tool": "collector"}
		return {"text": "Place a collector on the brass strip near you.", "tool": "collector"}
	var spans: Dictionary = state.get("belt_spans", {}) if _native_transmission() else {}
	if not kinds.has("belt") and spans.is_empty():
		return {"text": "Place two parallel shafts, then connect them with a belt.", "tool": "drive"} if _native_transmission() else {"text": "Add a belt beside the collector.", "tool": "belt"}
	if not kinds.has("processor"):
		return {"text": "Add a press at the belt outlet.", "tool": "processor"}
	var material_pairs: Dictionary = {}
	for pair in state.get("links", []):
		var entities: Dictionary = state.get("entities", {})
		if entities.has(pair[0]) and entities.has(pair[1]):
			material_pairs["%s:%s" % [entities[pair[0]].kind, entities[pair[1]].kind]] = true
	var span_route := _guided_span_routes() if _native_transmission() else {"physical": false, "powered": false, "cargo": false}
	var legacy_route := material_pairs.has("collector:belt") and material_pairs.has("belt:processor")
	if not span_route.physical and not legacy_route:
		if not spans.is_empty() and not kinds.has("belt"):
			return {"text": "Connect the collector and press with horizontal or inclined belts.", "tool": "drive"}
		return {"text": "Connect the material path. Help [H] shows an example.", "tool": "flow"}
	if not kinds.has("wheel"):
		return {"text": "Place a waterwheel in the stream.", "tool": "wheel"}
	if _native_transmission():
		var motion: Dictionary = state.get("motion", {})
		for id in state.get("entities", {}):
			var part: Dictionary = state.entities[id]
			if part.get("kind", "") in ["collector", "belt", "processor"] and motion.get(id, {}).get("state", "") != "rotating":
				return {"text": "Use cogs and shafts to bring rotation to each machine. The belt shaft crosses its direction of travel.", "tool": "drive"}
			if part.get("kind", "") == "belt" and motion.get(id, {}).get("state", "") == "rotating" and int(motion.get(id, {}).get("numerator", 0)) > 0:
				return {"text": "The belt is carrying copper away from the press. Change the cog route to reverse its rotation.", "tool": "drive"}
		if span_route.physical and not span_route.powered and not legacy_route:
			return {"text": "Power the belt shafts, check their direction toward the press, and check branches for diverted copper.", "tool": "drive"}
	elif not state.get("powered", false):
		return {"text": "Bring power to the line. Help [H] shows the current setup.", "tool": "drive"}
	var stock: Dictionary = state.get("stock", {})
	if _native_transmission() and not span_route.cargo and state.get("dropped_material", []).any(func(drop: Variant): return drop is Dictionary and int(drop.get("raw", 0)) > 0) and int(stock.get("source", 0)) + int(stock.get("collector", 0)) + int(stock.get("belt", 0)) + int(stock.get("input", 0)) + int(stock.get("held", 0)) == 0:
		return {"text": "Pick up loose copper nearby, then insert it into the press.", "tool": "inspect"}
	if not span_route.cargo and int(stock.get("source", 0)) + int(stock.get("collector", 0)) + int(stock.get("belt", 0)) + int(stock.get("input", 0)) + int(stock.get("held", 0)) == 0:
		if _native_transmission():
			var cargo: Dictionary = state.get("cargo", {}).get(client, {})
			if not cargo.get("work_lots", []).is_empty():
				return {"text": "Point at the press and open [E] to insert a carried copper workpiece.", "tool": "inspect"}
			if int(cargo.get("raw", 0)) > 0:
				return {"text": "Point at the press and open [E] to insert carried copper.", "tool": "inspect"}
		return {"text": "No copper remains here. Open Build to try another layout.", "tool": "inspect"}
	return {"text": "Follow the material toward the press. Point at a machine and open it [E].", "tool": "inspect"}

func _inspection_hint() -> String:
	# Describe confirmed projection facts only. This is advice, never admission
	# or a second power solver; the authority still decides every command.
	var kind: String = state.entities[selected].kind
	var rotating: bool = state.get("powered", false)
	if _native_transmission():
		rotating = state.get("motion", {}).get(selected, {}).get("state", "") == "rotating"
	if kind == "processor" and state.stock.output > 0:
		return "Outlet full; copper plate ready.\n[R] collect to make room."
	if kind == "processor" and state.stock.held > 0 and rotating:
		if state.remaining == 0:
			return "Work done; copper retained.\nNext drive tick releases a copper plate."
		return "Working: %d ticks remaining.\nHeld copper stays in the press." % state.remaining
	if kind in ["belt", "processor"] and not _has_material_connection(true):
		return "No material inlet linked.\n" + ("[C]" if _native_transmission() else "[F]") + " link " + ("Collector → Belt." if kind == "belt" else "Belt → Press.")
	if kind in ["collector", "belt"] and not _has_material_connection(false):
		return "No material outlet linked.\n" + ("[C]" if _native_transmission() else "[F]") + " link " + ("Collector → Belt." if kind == "collector" else "Belt → Press.")
	if not rotating:
		if _native_transmission():
			if kind == "wheel":
				return "Wheel is not rotating. Check its axle and the stream."
			return "Bring rotation to the line.\n[G] shafts; mesh cogwheels."
		return "Drive needs connections.\n[G] link wheel + all machines."
	if kind == "processor":
		if state.stock.input > 0:
			return "Copper ready to press.\nNext drive tick starts work."
		return "Waiting for copper.\nInspect the Belt upstream."
	if kind == "collector":
		if state.stock.source == 0:
			return "Ore deposit depleted.\nNo copper remains to collect."
		if state.stock.collector > 0:
			return "Collector outlet occupied.\nInspect the Belt downstream."
		return "Cutting copper from the finite deposit.\nBelt takes the next piece."
	if kind == "belt":
		return "Belt carrying copper.\nInspect the Press downstream." if state.stock.belt > 0 else "Waiting for copper.\nInspect the Collector upstream."
	return "Wheel rotates in the stream.\nConnected parts receive its motion."

func _has_material_connection(incoming: bool) -> bool:
	for pair in state.links:
		if pair[1 if incoming else 0] == selected:
			return true
	return false

func _refresh_machine_captions() -> void:
	if not _native_transmission() or machine_root == null:
		return
	for anchor in machine_root.get_children():
		var caption := anchor.get_node_or_null("MachineCaption") as Label3D
		if caption == null:
			continue
		var entity_id: String = anchor.get_meta("machine_entity", "")
		caption.visible = not explanation_open and (entity_id == selected \
			or entity_id == pending_link)

func _update_cursor() -> void:
	_refresh_machine_preview()
	_refresh_component_preview()
	_refresh_machine_captions()
	if _native_transmission() and transmission_controls != null and not transmission_controls.active_tool.is_empty():
		hover.visible = false
		if transmission_controls.active_tool in ["gearbox", "vertical_gearbox", "chain_drive"] and not explanation_open and _can_control_character():
			_set_transmission_hover(_transmission_center(get_viewport().get_mouse_position()))
		_refresh_placement_options()
		return
	hover.basis = Basis.IDENTITY
	hover.scale = Vector3.ONE
	if mode == "pod_workshop" and _native_transmission():
		var hub: Dictionary = state.get("fabrication_hub", {})
		hover.visible = hub.get("holder") == client and _preview_pointer_clear() \
			and _build_cell_allowed(hover_cell) and not explanation_open
		if hover.visible:
			hover.position = _cell_position([hover_cell.x, hover_cell.y]) + Vector3.UP * \
				(0.03 + _construction_level(hover_cell) * Geometry.HEIGHT_STEP)
		_refresh_placement_options()
		return
	if mode == "component" and _native_transmission():
		hover.visible = false
		_refresh_placement_options()
		return
	hover.visible = NAMES.has(mode) and _build_cell_allowed(hover_cell) and _machine_floor_aligned(hover_cell) \
		and (mode == "foundation" or _entity_at_cell(hover_cell).is_empty()) and not explanation_open
	if hover.visible:
		hover.position = _cell_position([hover_cell.x, hover_cell.y]) + Vector3(0, 0.03 + _construction_level(hover_cell) * Geometry.HEIGHT_STEP, 0)
	_refresh_placement_options()

func _set_transmission_hover(center: Array) -> void:
	if center.size() != 3 or absi(center[0]) > Geometry.GRID_COORDINATE_LIMIT or absi(center[1]) > Geometry.GRID_COORDINATE_LIMIT or absi(center[2]) > Geometry.GRID_COORDINATE_LIMIT:
		return
	hover.visible = true
	hover.position = Vector3(center[0] * Geometry.HEIGHT_STEP,
		0.03 + center[1] * Geometry.HEIGHT_STEP, center[2] * Geometry.HEIGHT_STEP)
	hover.basis = Basis.IDENTITY

func _message(words: String, refused: bool = false) -> void:
	status_label.text = words
	status_refused = refused
	status_label.modulate = Color("e0a880") if refused else Color("d6dfd6")
	_queue_footer_fit()

func _queue_footer_fit() -> void:
	if status_footer == null or footer_fit_pending:
		return
	footer_fit_pending = true
	_fit_guided_footer.call_deferred()

func _footer_above_view() -> bool:
	# A nearby third-person worker fills the lower centre of the view. Use the
	# free lane above the worker; Help keeps its own upper reading space.
	return distance > 1.0 and distance <= 6.0 and not explanation_open

func _fit_guided_footer() -> void:
	footer_fit_pending = false
	# Wrapped text settles after its container width. Fit again at that
	# boundary, rather than retaining an early oversized minimum height.
	var columns_to_fit := [build_column] if object_menu != null else [build_column, inspector.get_parent() if inspector != null else null]
	for column in columns_to_fit:
		if column != null:
			var panel: Control = column.get_parent()
			if column == inspector.get_parent():
				var content_visible := false
				for control in column.get_children():
					if control is Control and control.visible and not control is HSeparator:
						content_visible = true
						break
				panel.visible = content_visible
			var height: float = panel.get_combined_minimum_size().y
			if not is_equal_approx(panel.size.y, height):
				panel.size.y = height
	# Keep repeated guidance on the objective card instead of a second message panel.
	var repeated_goal: bool = not status_label.text.is_empty() and goal_label.text.contains(status_label.text)
	var can_omit_instruction: bool = footer_snapshot_ready and _placement_ready() \
		and not status_refused and not _catalog_open() and not explanation_open
	var redundant_intro: bool = can_omit_instruction and (repeated_goal or _native_transmission() \
		and mode in ["inspect", "collector"] \
		and state.get("entities", {}).is_empty() and state.get("transmission_parts", {}).is_empty() \
		and _guided_step({}).tool == "collector" \
		and status_label.text == FIRST_COLLECTOR_HINT)
	status_label.visible = not status_label.text.is_empty() and not redundant_intro
	var right := -18.0
	if object_menu == null:
		var inspector_panel: Control = inspector.get_parent().get_parent()
		right = inspector_panel.get_global_rect().position.x - get_viewport().get_visible_rect().end.x - 18.0 \
			if inspector_panel.visible else -18.0
	if not is_equal_approx(status_footer.offset_right, right):
		status_footer.set_anchor_and_offset(SIDE_RIGHT, 1.0, right)
	var left_anchor := 1.0 if redundant_intro else 0.0
	var left_offset: float = right - status_footer.get_combined_minimum_size().x if redundant_intro else 310.0
	if not is_equal_approx(status_footer.anchor_left, left_anchor) or not is_equal_approx(status_footer.offset_left, left_offset):
		status_footer.set_anchor_and_offset(SIDE_LEFT, left_anchor, left_offset)
	var edge := 0.0 if _footer_above_view() else 1.0
	var bottom: float = 18.0 + status_footer.get_combined_minimum_size().y if edge == 0.0 else -30.0 - building_hotbar.size.y
	if not is_equal_approx(status_footer.anchor_bottom, edge) or not is_equal_approx(status_footer.offset_bottom, bottom):
		status_footer.set_anchor_and_offset(SIDE_BOTTOM, edge, bottom)
	var top: float = bottom - status_footer.get_combined_minimum_size().y
	if not is_equal_approx(status_footer.anchor_top, edge) or not is_equal_approx(status_footer.offset_top, top):
		status_footer.set_anchor_and_offset(SIDE_TOP, edge, top)
	if _catalog_open():
		building_hotbar._place_catalog()

func _label(parent: Node, words: String, size: int = 16, color: Color = Color("dde5d9")) -> Label:
	var label := Label.new()
	label.text = words
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, words: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size.y = 37
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _accent_button(button: Button) -> void:
	for state_name in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := button.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
		style.bg_color = Color("614721") if state_name in ["normal", "pressed"] else Color("806036")
		style.border_color = Color("e9b873")
		button.add_theme_stylebox_override(state_name, style)
	button.add_theme_color_override("font_color", Color("fff5df"))
	button.add_theme_color_override("font_hover_color", Color("fff5df"))

func _panel(parent: Node, at: Vector2, dimensions: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = at
	panel.size = dimensions
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.092, 0.112, 0.94)
	style.border_color = Color("52676b")
	style.set_corner_radius_all(7)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	return column

func _hud_surface(column: VBoxContainer, opacity: float, padding: int = 10) -> void:
	var panel := column.get_parent() as PanelContainer
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.085, opacity)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(padding)
	panel.add_theme_stylebox_override("panel", style)
	column.add_theme_constant_override("separation", 5)

func _build_pointed_summary(root: Control) -> void:
	pointed_summary = PanelContainer.new()
	pointed_summary.name = "PointedSummary"
	pointed_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.035, 0.065, 0.075, 0.68)
	surface.set_corner_radius_all(5)
	surface.set_content_margin_all(7)
	pointed_summary.add_theme_stylebox_override("panel", surface)
	root.add_child(pointed_summary)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 1)
	pointed_summary.add_child(column)
	pointed_name = _label(column, "", 14, Color("f4f5eb"))
	pointed_detail = _label(column, "", 11, Color("b9ceca"))
	pointed_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointed_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointed_summary.visible = false

func _build_object_menu(root: Control, detail_panel: PanelContainer) -> void:
	object_menu_scrim = ColorRect.new()
	object_menu_scrim.name = "ObjectMenuShade"
	object_menu_scrim.color = Color(0.01, 0.02, 0.025, 0.58)
	object_menu_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(object_menu_scrim)
	object_menu_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	object_menu_scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			object_menu.hide())
	object_menu_scrim.visible = false
	object_menu = PopupPanel.new()
	object_menu.name = "ObjectMenu"
	object_menu.theme = root.theme.duplicate()
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.035, 0.06, 0.075, 0.97)
	surface.set_corner_radius_all(10)
	object_menu.theme.set_stylebox("panel", "PopupPanel", surface)
	root.add_child(object_menu)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	object_menu.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	margin.add_child(shell)
	var header := HBoxContainer.new()
	shell.add_child(header)
	object_menu_title = _label(header, "", 22, Color("f1d7a5"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	object_menu_close = _button(header, "", object_menu.hide)
	object_menu_close.icon = load("res://opening/assets/menu-icons/close.svg")
	object_menu_close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	object_menu_close.custom_minimum_size = Vector2(40, 32)
	object_menu_close.tooltip_text = "Close object menu · Esc"
	object_menu_close.accessibility_name = "Close object menu, shortcut Escape"
	shell.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(columns)
	detail_panel.reparent(columns)
	object_menu_detail_panel = detail_panel
	detail_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	detail_panel.custom_minimum_size = Vector2(220, 0)
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var detail_column := inspector.get_parent() as VBoxContainer
	arrival_assembly_controls.reclaim_spacer = Control.new()
	arrival_assembly_controls.reclaim_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arrival_assembly_controls.reclaim_spacer.visible = false
	detail_column.add_child(arrival_assembly_controls.reclaim_spacer)
	arrival_assembly_controls.reclaim_row.reparent(detail_column, false)
	object_menu_operations = VBoxContainer.new()
	object_menu_operations.custom_minimum_size.x = 420
	object_menu_operations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	object_menu_operations.size_flags_vertical = Control.SIZE_EXPAND_FILL
	object_menu_operations.add_theme_constant_override("separation", 8)
	columns.add_child(object_menu_operations)
	object_menu_operations_label = _label(object_menu_operations, "MACHINE ACTIONS", 12, Color("f4bf75"))
	arrival_assembly_scroll.reparent(object_menu_operations)
	arrival_assembly_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arrival_assembly_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arrival_assembly_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	arrival_assembly_controls.custom_minimum_size.x = 410
	arrival_assembly_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arrival_assembly_controls.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	object_menu_operations.visible = false
	object_menu.popup_hide.connect(_on_object_menu_closed)

func _object_menu_open() -> bool:
	return object_menu != null and object_menu.visible

func _pause_menu_open() -> bool:
	return pause_menu != null and pause_menu.visible

func _open_pause_menu() -> void:
	if pause_menu == null or _object_menu_open() or _catalog_open() or explanation_open or manager_log_open:
		return
	_release_character_controls()
	pause_menu_scrim.visible = true
	pause_menu.show()
	pause_resume_button.grab_focus()

func _build_pause_menu(root: Control) -> void:
	pause_menu_scrim = ColorRect.new()
	pause_menu_scrim.name = "PauseMenuShade"
	pause_menu_scrim.color = Color(0.01, 0.02, 0.025, 0.54)
	pause_menu_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu_scrim.z_index = 100
	root.add_child(pause_menu_scrim)
	pause_menu_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu_scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pause_menu.hide())
	pause_menu_scrim.visible = false
	var center := CenterContainer.new()
	center.name = "PauseMenuCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.z_index = 101
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu = PanelContainer.new()
	pause_menu.name = "PauseMenu"
	pause_menu.theme = root.theme.duplicate()
	pause_menu.custom_minimum_size = Vector2(380, 390)
	pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.035, 0.06, 0.075, 0.96)
	surface.set_corner_radius_all(10)
	pause_menu.theme.set_stylebox("panel", "PanelContainer", surface)
	center.add_child(pause_menu)
	pause_menu.hide()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	pause_menu.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_label(column, "WORKSITE", 18, Color("f1d7a5"))
	_label(column, "Esc resumes  ·  F5 saves", 11, Color("b9ceca"))
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 4)
	column.add_child(status)
	for control in [actor_label, power_label, stock_label]:
		control.reparent(status)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 14)
	actions.add_theme_constant_override("v_separation", 12)
	column.add_child(actions)
	pause_resume_button = _pause_action(actions, "resume", "Resume", "Esc", func(): pause_menu.hide())
	save_button.reparent(actions)
	_style_pause_action(save_button, "save", "Save worksite", "F5")
	load_button.reparent(actions)
	_style_pause_action(load_button, "reopen", "Reopen save", "F9")
	pause_exit_button = _pause_action(actions, "exit", "Exit workshop", "Q", func(): pause_exit_confirmation.popup_centered())
	pause_menu.visibility_changed.connect(func() -> void:
		if not pause_menu.visible:
			pause_menu_scrim.visible = false)
	pause_exit_confirmation = ConfirmationDialog.new()
	pause_exit_confirmation.title = "Exit workshop"
	pause_exit_confirmation.dialog_text = "Unsaved changes will be lost. Save with F5 before exiting."
	pause_exit_confirmation.ok_button_text = "Exit without saving"
	pause_exit_confirmation.confirmed.connect(func(): get_tree().quit())
	root.add_child(pause_exit_confirmation)

func _pause_action(parent: GridContainer, icon_name: String, action_name: String,
		shortcut: String, callback: Callable) -> Button:
	var button := _button(parent, "", callback)
	_style_pause_action(button, icon_name, action_name, shortcut)
	return button

func _style_pause_action(button: Button, icon_name: String, action_name: String, shortcut: String) -> void:
	button.text = ""
	button.icon = load("res://opening/assets/menu-icons/%s.svg" % icon_name)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = false
	button.custom_minimum_size = Vector2(140, 82)
	button.tooltip_text = "%s  [%s]" % [action_name, shortcut]
	button.accessibility_name = "%s, shortcut %s" % [action_name, shortcut]
	var caption := Label.new()
	caption.text = action_name
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -24
	caption.add_theme_font_size_override("font_size", 11)

func _on_object_menu_closed() -> void:
	object_menu_closed_frame = Engine.get_process_frames()
	if arrival_assembly_controls != null:
		arrival_assembly_controls.stop_turn_hold()
	object_menu_scrim.visible = false
	object_menu_target = ""
	selected = ""
	_refresh_ui()

func _object_name(target: String) -> String:
	if state.get("entities", {}).has(target):
		return NAMES.get(state.entities[target].kind, str(state.entities[target].kind).capitalize())
	if state.get("foundations", {}).has(target):
		return "Factory floor" if int(state.foundations[target].get("level", 0)) % Geometry.HEIGHT_DENOMINATOR == 0 else "Access step"
	if state.get("transmission_parts", {}).has(target):
		return str(state.transmission_parts[target].get("kind", "Drive part")).replace("_", " ").capitalize()
	if state.get("belt_spans", {}).has(target):
		return "Mechanical belt"
	if target == state.get("fabrication_hub", {}).get("id", ""):
		return "Pod workshop"
	if state.get("placed_components", {}).has(target):
		var component: String = str(state.placed_components[target].get("component", "part"))
		return "Wooden workbench" if component == "wooden_workbench" else component.replace("_", " ").capitalize()
	return ""

func _object_supports_operations(target: String) -> bool:
	if target == state.get("fabrication_hub", {}).get("id", "") and not target.is_empty():
		return true
	if state.get("entities", {}).get(target, {}).get("kind", "") in ["collector", "processor"]:
		return true
	if state.get("placed_components", {}).get(target, {}).get("component", "") == "wooden_workbench":
		return true
	if state.get("placed_components", {}).has(target):
		return true
	for row: Variant in state.get("fabrication_benches", []):
		if row is Dictionary and row.get("id", "") == target:
			return true
	return _is_guided_press_part(target) or _is_collector_frame(target)

func _is_guided_press_part(target: String) -> bool:
	if target.is_empty():
		return false
	for assemblies: Array in [state.get("sliding_press_assemblies", []),
			state.get("guided_press_assemblies", [])]:
		for row: Variant in assemblies:
			if not row is Dictionary:
				continue
			var parts: Variant = row.get("parts", {})
			if row.get("status") == "ready" and (row.get("anvil", "") == target \
					or (parts is Dictionary and parts.values().has(target))):
				return true
	return false

func _is_collector_frame(target: String) -> bool:
	if target.is_empty():
		return false
	for row: Variant in state.get("collector_assemblies", []):
		if row is Dictionary and row.get("parts", {}).get("frame", "") == target:
			return true
	return false

func _pointed_summary_data(screen: Vector2) -> Dictionary:
	if camera == null or not camera.is_inside_tree():
		return {}
	var crank_id := _crank_at_screen(screen)
	if not crank_id.is_empty():
		return {"name": "Fitted hand crank",
			"detail": "Click  Detach" if mode == "deconstruct" else "Hold E  Turn · F then click  Detach",
			"target": crank_id}
	var hit := _screen_pick(screen)
	var target: String = str(hit.collider.get_meta("entity", hit.collider.get_meta("component_entity", ""))) if not hit.is_empty() else ""
	if _contains_target(state, target):
		var detail := "E  Open"
		if state.get("entities", {}).get(target, {}).get("kind") == "processor":
			detail = "%d ready  ·  E Open" % int(state.get("stock", {}).get("output", 0))
		return {"name": _object_name(target), "detail": detail, "target": target}
	var source_id := _screen_hand_source(screen)
	var source := _hand_source(source_id)
	if not source.is_empty():
		var cut: Dictionary = state.get("manual_cuts", {}).get(client, {})
		if cut.get("target", "") == source_id:
			return {"name": "Timber tree" if source.kind == "tree" else "Ore deposit",
				"detail": "Cutting…"}
		var detail := "Depleted"
		if source.remaining > 0:
			detail = "%d left  ·  Move closer" % source.remaining
			if _hand_source_in_reach(source):
				detail = "%d left  ·  E Harvest" % source.remaining if _hand_source_clear(source_id) else \
					"%d left  ·  Move around" % source.remaining
		return {"name": "Timber tree" if source.kind == "tree" else "Ore deposit",
			"detail": detail}
	return {}

func _refresh_pointed_summary() -> void:
	if pointed_summary == null or camera == null:
		return
	if arrival_reveal_active or explanation_open or manager_log_open or _catalog_open() or _object_menu_open() or _pause_menu_open():
		pointed_summary.visible = false
		return
	var screen := _pointed_screen_position()
	if distance > 0.0 and get_viewport().gui_get_hovered_control() != null:
		pointed_summary.visible = false
		return
	var summary := _pointed_summary_data(screen)
	pointed_summary.visible = not summary.is_empty()
	if summary.is_empty():
		return
	pointed_name.text = summary.name
	pointed_detail.text = summary.detail
	pointed_summary.size = pointed_summary.get_combined_minimum_size()
	var extent := get_viewport().get_visible_rect().size
	pointed_summary.position = Vector2(
		clampf(screen.x + 20.0, 12.0, extent.x - pointed_summary.size.x - 12.0),
		clampf(screen.y + 20.0, 12.0, extent.y - pointed_summary.size.y - 12.0))

func _build_interface() -> void:
	# A revisable opening adapter limit, not a fixed window or a game-world rule.
	get_window().min_size = Vector2i(640, 480)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	arrival_gameplay_canvas = canvas
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = ProductionInterface.make_theme()
	arrival_reveal_canvas = CanvasLayer.new()
	arrival_reveal_canvas.name = "ArrivalReveal"
	arrival_reveal_canvas.layer = 50
	arrival_reveal_canvas.visible = false
	add_child(arrival_reveal_canvas)
	var reveal_root := Control.new()
	reveal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reveal_root.theme = root.theme
	arrival_reveal_canvas.add_child(reveal_root)
	reveal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var company := _label(reveal_root, "MERIDIAN COMBINE  /  FIELD PACKAGE 01", 20, Color("f1d7a5"))
	company.position = Vector2(30, 14)
	var company_style := LabelSettings.new()
	company_style.font_size = 20
	company_style.font_color = Color("f1d7a5")
	company_style.outline_size = 5
	company_style.outline_color = Color("102023")
	company.label_settings = company_style
	arrival_reveal_caption = _label(reveal_root, "FIELD DESCENT IN PROGRESS", 13, Color("d1ded9"))
	arrival_reveal_caption.position = Vector2(32, 52)
	var caption_style := LabelSettings.new()
	caption_style.font_size = 13
	caption_style.font_color = Color("d1ded9")
	caption_style.outline_size = 4
	caption_style.outline_color = Color("102023")
	arrival_reveal_caption.label_settings = caption_style
	var skip_hint := _label(reveal_root, "SPACE / ESC  Skip arrival", 13, Color("d1ded9"))
	skip_hint.label_settings = caption_style
	skip_hint.position = Vector2(32, 76)
	fps_label = _label(root, "FPS --", 13)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.set_anchor_and_offset(SIDE_LEFT, 0.0, 16.0)
	fps_label.set_anchor_and_offset(SIDE_RIGHT, 0.0, 98.0)
	fps_label.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -20.0)
	fps_label.set_anchor_and_offset(SIDE_TOP, 1.0, -44.0)
	var fps_style := LabelSettings.new()
	fps_style.font_size = 13
	fps_style.font_color = Color("e7ede5")
	fps_style.outline_size = 4
	fps_style.outline_color = Color("16242a")
	fps_label.label_settings = fps_style
	var build := _panel(root, Vector2(18, 18), Vector2(260, 0))
	_hud_surface(build, 0.58)
	build_column = build
	build.add_theme_constant_override("separation", 6)
	objective_heading = _label(build, "FIRST SHIFT  /  01", 13, Color("f4bf75"))
	goal_label = _label(build, "", 16, Color("f4f5eb"))
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	manager_log_button = _button(build, "Work log  J", _toggle_manager_log)
	manager_log_button.custom_minimum_size.y = 30
	goal_progress = ProgressBar.new()
	goal_progress.max_value = 4
	goal_progress.show_percentage = false
	goal_progress.custom_minimum_size.y = 7
	var track := StyleBoxFlat.new()
	track.bg_color = Color("293a3d")
	track.set_corner_radius_all(3)
	goal_progress.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e6ae64")
	fill.set_corner_radius_all(3)
	goal_progress.add_theme_stylebox_override("fill", fill)
	build.add_child(goal_progress)
	confirm_button = _button(build, "Confirm four plates  [Ctrl+Enter]", _confirm_goal)
	_accent_button(confirm_button)
	build.add_child(HSeparator.new())
	building_hotbar = BuildingHotbar.new()
	building_hotbar.configure(self, root)
	tool_buttons.merge(building_hotbar.catalog_buttons)
	parts_label = building_hotbar.parts_label
	catalog_button = building_hotbar.catalog_button
	placement_options_column = _panel(root, Vector2.ZERO, Vector2(302, 0))
	_hud_surface(placement_options_column, 0.66)
	placement_options_panel = placement_options_column.get_parent() as PanelContainer
	placement_options_panel.name = "PlacementOptions"
	placement_options_panel.visible = false
	placement_options_title = _label(placement_options_column, "PLACE", 17, Color("edcc8d"))
	placement_options_hint = _label(placement_options_column, "Left click to build · Esc to cancel", 13, Color("a3b8b4"))
	placement_options_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement_options_hint.custom_minimum_size.x = 260
	rotation_button = _button(placement_options_column, "Rotate [R]", _rotate_building)
	rotation_button.visible = false
	placement_options_axis = _button(placement_options_column, "Axle: X", _cycle_placement_axis)
	placement_options_axis.visible = false
	foundation_level_controls = HBoxContainer.new()
	placement_options_column.add_child(foundation_level_controls)
	_button(foundation_level_controls, "−", _adjust_foundation_level.bind(-1))
	foundation_level_label = _label(foundation_level_controls, _construction_height_text(), 14)
	_button(foundation_level_controls, "+", _adjust_foundation_level.bind(1))
	foundation_level_controls.visible = false
	foundation_steps_toggle = CheckButton.new()
	foundation_steps_toggle.text = "Access steps"
	foundation_steps_toggle.tooltip_text = "Use one height unit for walking steps. Normal height changes move one foundation thickness. Machines need whole-tile factory floors; turning this off snaps the selected height to one."
	foundation_steps_toggle.toggled.connect(_set_foundation_steps)
	placement_options_column.add_child(foundation_steps_toggle)
	foundation_steps_toggle.visible = false
	wheel_size_controls = HBoxContainer.new()
	placement_options_column.add_child(wheel_size_controls)
	_button(wheel_size_controls, "−", _adjust_wheel_size.bind(-1))
	wheel_size_label = _label(wheel_size_controls, "Wheel diameter: 3 squares", 14)
	_button(wheel_size_controls, "+", _adjust_wheel_size.bind(1))
	wheel_size_controls.visible = false
	foundation_area_toggle = CheckButton.new()
	foundation_area_toggle.text = "Area (two corners)"
	foundation_area_toggle.toggled.connect(func(enabled: bool) -> void:
		foundation_area_mode = enabled
		foundation_area_started = false)
	placement_options_column.add_child(foundation_area_toggle)
	foundation_area_toggle.visible = false
	var selection_tools := HBoxContainer.new()
	build.add_child(selection_tools)
	tool_buttons.flow = _button(selection_tools, "Link  C", _select_tool.bind("flow"))
	tool_buttons.flow.toggle_mode = true
	tool_buttons.flow.custom_minimum_size.y = 30
	help_button = _button(build, "Help  H", _toggle_explanation)
	help_button.tooltip_text = "Show the current task and controls. H opens Help; H or Escape closes it."
	help_button.custom_minimum_size.y = 30
	manager_log_button.text = "Log  J"
	var quick_actions := HBoxContainer.new()
	quick_actions.add_theme_constant_override("separation", 4)
	build.add_child(quick_actions)
	for action in [manager_log_button, help_button]:
		action.get_parent().remove_child(action)
		quick_actions.add_child(action)
	var right := _panel(root, Vector2(932, 18), Vector2(255, 0))
	_hud_surface(right, 0.58)
	var right_panel: Control = right.get_parent()
	# Set the far anchor first so the near anchor is not clamped.
	right_panel.set_anchor_and_offset(SIDE_RIGHT, 1.0, -18)
	right_panel.set_anchor_and_offset(SIDE_LEFT, 1.0, -273)
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# The actor/connection rows identify the physical worksite. Leave room
	# for a selected press and pending-server advice above the status panel.
	right.add_theme_constant_override("separation", 6)
	inspector_title = _label(right, "SELECTED", 12, Color("f4bf75"))
	actor_label = _label(right, "", 11, Color("a3b8b4"))
	power_label = _label(right, "", 14, Color("dfbc76"))
	stock_label = _label(right, "", 16)
	inspector = _label(right, "", 13)
	inspector.custom_minimum_size.x = 195
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspection_actions = HBoxContainer.new()
	inspection_actions.add_theme_constant_override("separation", 5)
	right.add_child(inspection_actions)
	retrieve_button = _button(inspection_actions, "Collect  Ctrl+R", _retrieve)
	_accent_button(retrieve_button)
	remove_button = _button(inspection_actions, "Remove  Del", _remove_selected)
	for action in [retrieve_button, remove_button]:
		action.custom_minimum_size.y = 30
		action.add_theme_font_size_override("font_size", 12)
	# Older scripted launch payloads have a fixed roster without this native UI.
	var recovery_path := "res://opening/recovery_actions.gd"
	if ResourceLoader.exists(recovery_path, "Script"):
		var recovery_script = load(recovery_path)
		recovery_actions = recovery_script.new()
		right.add_child(recovery_actions)
		recovery_actions.configure(self)
	loose_material_controls = load("res://opening/recovery_actions.gd").LooseMaterialControls.new()
	right.add_child(loose_material_controls)
	loose_material_controls.configure(self)
	arrival_assembly_scroll = ScrollContainer.new()
	arrival_assembly_scroll.name = "ArrivalWorkshopScroll"
	arrival_assembly_scroll.custom_minimum_size.y = 260
	right.add_child(arrival_assembly_scroll)
	arrival_assembly_controls = RecoveryActions.ArrivalAssemblyControls.new()
	arrival_assembly_scroll.add_child(arrival_assembly_controls)
	arrival_assembly_controls.configure(self)
	arrival_assembly_scroll.visible = false
	right.add_child(HSeparator.new())
	save_button = _button(right, "Save worksite  [F5]", _save_worksite)
	load_button = _button(right, "Load worksite  [F9]", _load_worksite)
	_build_object_menu(root, right_panel as PanelContainer)
	# Loose work belongs to the world, so its action menu must stay reachable
	# while the selected-object panel is closed.
	loose_material_controls.reparent(selection_tools)
	loose_material_controls.text = "Loose"
	loose_material_controls.icon = load("res://opening/assets/build-icons/ore.svg")
	loose_material_controls.custom_minimum_size = Vector2(82, 30)
	loose_material_controls.focus_mode = Control.FOCUS_ALL
	loose_material_controls.accessibility_name = "Handle loose material, shortcut Control L"
	_build_pause_menu(root)
	_build_pointed_summary(root)
	var bottom := _panel(root, Vector2(310, 694), Vector2(952, 88))
	_hud_surface(bottom, 0.64, 7)
	var bottom_panel: Control = bottom.get_parent()
	status_footer = bottom_panel
	bottom_panel.set_anchor_and_offset(SIDE_RIGHT, 1.0, -18)
	bottom_panel.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -128)
	bottom_panel.set_anchor_and_offset(SIDE_TOP, 1.0, -216)
	bottom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status_label = _label(bottom, "", 14)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label = _label(bottom, "B catalog · 1–8 build · E open · F dismantle · H help", 12, Color("bfd1cc"))
	developer_mode_label = _label(bottom, "F3  FAST", 11, Color("64777a"))
	developer_mode_label.focus_mode = Control.FOCUS_ALL
	bottom_panel.minimum_size_changed.connect(_queue_footer_fit)
	bottom_panel.resized.connect(_queue_footer_fit)
	for column: Control in [build, right]:
		column.minimum_size_changed.connect(_queue_footer_fit)
	var lesson_column := _panel(root, Vector2(346, 18), Vector2(600, 192))
	help_panel = lesson_column.get_parent()
	help_panel.set_anchor_and_offset(SIDE_RIGHT, 0.5, 306)
	help_panel.set_anchor_and_offset(SIDE_LEFT, 0.5, -294)
	help_title = _label(lesson_column, "", 17, Color("edcc8d"))
	help_body = _label(lesson_column, "", 16)
	help_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_close_button = _button(lesson_column, "Return to work  [H / Esc]", _toggle_explanation)
	help_close_button.tooltip_text = "Close Help and return to the worksite."
	help_panel.visible = false
	_build_manager_log()

func _build_manager_log() -> void:
	manager_log_layer = CanvasLayer.new()
	manager_log_layer.name = "MeridianWorkLog"
	manager_log_layer.layer = 20
	manager_log_layer.visible = false
	add_child(manager_log_layer)
	var log_root := Control.new()
	log_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	manager_log_layer.add_child(log_root)
	log_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	log_root.theme = ProductionInterface.make_theme()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.05, 0.58)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	log_root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := _panel(log_root, Vector2.ZERO, Vector2(550, 480))
	column.add_theme_constant_override("separation", 8)
	var panel := column.get_parent() as PanelContainer
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	column.reparent(scroll)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manager_log_panel = panel
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -275.0
	panel.offset_right = 275.0
	panel.offset_top = -240.0
	panel.offset_bottom = 240.0
	_label(column, "MERIDIAN COMBINE  /  WORK LOG", 19, Color("f1d7a5"))
	_label(column, "Field Operations Manager · Shift 01", 13, Color("a9c3bb"))
	column.add_child(HSeparator.new())
	for entry in [
		"00  LANDFALL\nLandfall confirmed. Your office is now the part of the planet under your boots.",
		"01  FIELD KIT\nThe kit makes tools. The tools make a factory. Corporate has provided the kit.",
		"02  FIRST WORKSHOP\nForm one plate from local stock and collect it in your inventory."]:
		var line := _label(column, entry, 15)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 496.0
	manager_log_completion_entry = _label(column,
		"03  FIRST WORKSHOP COMPLETE\nYou collected your first formed plate. Corporate has filed your next shift under 'voluntary.'", 15,
		Color("f1d7a5"))
	manager_log_completion_entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	manager_log_completion_entry.custom_minimum_size.x = 496.0
	manager_log_completion_entry.visible = false
	manager_log_projects = VBoxContainer.new()
	manager_log_projects.add_theme_constant_override("separation", 6)
	column.add_child(manager_log_projects)
	for project in [
		["collector", "Assemble a finite ore collector: frame, mount, edge, receiver and drive."],
		["belt", "Then route its copper by belt to a powered press."]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		manager_log_projects.add_child(row)
		var icon := TextureRect.new()
		icon.texture = load("res://opening/assets/build-icons/%s.svg" % project[0])
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var description := _label(row, project[1], 14)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manager_log_projects.visible = false
	manager_log_current = _label(column, "CURRENT FIELD CUE\nInspect the worksite.", 15, Color("f1d7a5"))
	manager_log_current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var close_log := _button(column, "Return to work  [J / Esc]", _toggle_manager_log)
	_accent_button(close_log)
