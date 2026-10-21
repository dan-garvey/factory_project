extends Node3D
## Input and presentation only. Every material/build mutation goes to model.gd.

const Model = preload("res://model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
const ActorWorld = preload("res://opening/actor_world.gd")
const CharacterPresenter = preload("res://opening/character_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const BuildingHotbar = preload("res://opening/building_hotbar.gd")
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
	const FILES := ["rotor.gltf", "rotor.bin", "wood_albedo.jpg", "wood_normal.webp", "wood_arm.webp"]
	static var mesh: ArrayMesh
	static var finish: StandardMaterial3D
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
		var document := GLTFDocument.new()
		var imported := GLTFState.new()
		if document.append_from_file(ROOT.path_join("rotor.gltf"), imported) != OK:
			push_error("Cannot load the prepared waterwheel component.")
			return
		var sources := imported.get_meshes()
		if sources.size() != 1 or sources[0].mesh == null or sources[0].mesh.get_surface_count() != 1:
			push_error("The waterwheel must contain one prepared visual mesh.")
			return
		var prepared: ArrayMesh = sources[0].mesh.get_mesh()
		var arrays := prepared.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_TANGENT] == null or arrays[Mesh.ARRAY_TANGENT].is_empty():
			var surface := SurfaceTool.new()
			surface.create_from(prepared, 0)
			surface.generate_tangents()
			prepared = surface.commit()
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
		mesh = prepared
		finish = material
		source_status = "ready"

	static func mount(parent: Node3D) -> bool:
		if source_status == "uninitialized":
			_prepare()
		if source_status != "ready":
			return false
		var rotor := MeshInstance3D.new()
		rotor.name = "SourcedTimberRotor"
		rotor.mesh = mesh
		rotor.material_override = finish
		rotor.set_meta("detail_role", "SourcedTimberRotor")
		rotor.set_meta("source_asset", "Poly Haven spinning_wheel_01")
		parent.add_child(rotor)
		return true

class ProductionPaddleArt:
	extends RefCounted
	## Original blade joinery and qualified timber. No power or work authority.
	const ROOT := "res://opening/assets/wheel-paddles"
	const FILES := {"albedo": "timber_albedo.jpg", "normal": "timber_normal_gl.webp", "roughness": "timber_roughness.webp"}
	const TILE_METRES := 0.6
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
		var iron := ProductionTransmissionFinish.material("worked", Color("46504e"), 0.85, 0.48)
		if iron == null:
			blade.free()
			return false
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
			var outline := PackedVector2Array([Vector2(-0.19, 0.24), Vector2(0.19, 0.24),
				Vector2(0.19, 0.32), Vector2(0.18, 0.36), Vector2(0.075, 0.36),
				Vector2(0.065, 0.58), Vector2(0.065, 0.62), Vector2(-0.065, 0.62),
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
			if drive_axis == 2:
				# Keep a real opening around the existing Z-axis drive stub.
				for end in [-1.0, 1.0]:
					_part(parent, "GuardHalf", suffix + ("N" if end < 0 else "P"),
						ProductionVisuals.box_mesh(Vector3(0.57, 0.08, 0.05)), Vector3(end * 0.405, 0.57, side * 0.36), Basis.IDENTITY, paint)
			else:
				_part(parent, "GuardRail", suffix, ProductionVisuals.box_mesh(Vector3(1.38, 0.08, 0.05)),
					Vector3(0, 0.57, side * 0.36), Basis.IDENTITY, paint)
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
		var paint := ProductionCollectorArt.coating(color)
		var steel := ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)
		var guide_finish := ProductionTransmissionFinish.material("worked", Color("b87945"), 0.85, 0.4)
		if paint == null or steel == null or guide_finish == null:
			return false
		var crown := Node3D.new()
		crown.name = "PressCrown"
		parent.add_child(crown)
		var shoulder := PackedVector2Array([Vector2(-0.60, -0.07), Vector2(-0.56, -0.10),
			Vector2(-0.34, -0.10), Vector2(-0.24, -0.04), Vector2(-0.12, -0.04),
			Vector2(-0.12, 0.10), Vector2(-0.56, 0.10), Vector2(-0.60, 0.06)])
		for right in [false, true]:
			var profile := shoulder.duplicate()
			if right:
				for n in range(profile.size()):
					profile[n].x = -profile[n].x
			_part(crown, "CastShoulderRight" if right else "CastShoulderLeft",
				ProductionVisuals.prism_mesh(profile, 0.36, 0.007), Vector3(0, 1.5, -0.3), paint)
		# The rear tie joins the shoulders without filling the ram's bore.
		_part(crown, "RearTie", ProductionVisuals.box_mesh(Vector3(0.32, 0.14, 0.265)),
			Vector3(0, 1.53, -0.3475), paint)
		var housing := PackedVector2Array([Vector2(0.083, -0.135), Vector2(0.115, -0.135),
			Vector2(0.14, -0.115), Vector2(0.14, 0.11), Vector2(0.12, 0.135),
			Vector2(0.083, 0.135), Vector2(0.083, -0.135)])
		_part(crown, "RamHousing", ProductionVisuals.turned_mesh(housing), Vector3(0, 1.465, -0.08), paint)
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

	static func _hardware(target: ArrayMesh, poses: Array[Transform3D]) -> void:
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
		for pose in poses:
			pieces.append([washer, pose])
			pieces.append([ProductionVisuals.fastener_head_mesh(), pose * Transform3D(Basis.IDENTITY, Vector3(0, 0.018, 0))])
		_surface(target, "MountingHardware", pieces)

	static func tool_mesh() -> ArrayMesh:
		if meshes.has("tool"):
			return meshes.tool
		var mesh := ArrayMesh.new()
		var holder := PackedVector2Array([
			Vector2(-0.28, -0.025), Vector2(-0.27, -0.045), Vector2(-0.25, -0.045),
			Vector2(-0.25, -0.035), Vector2(0.25, -0.035), Vector2(0.25, -0.045),
			Vector2(0.27, -0.045), Vector2(0.28, -0.025), Vector2(0.28, 0.060),
			Vector2(0.255, 0.085), Vector2(-0.255, 0.085), Vector2(-0.28, 0.060)])
		_surface(mesh, "ToolHolder", [[ProductionVisuals.prism_mesh(holder, 0.48, 0.004), Transform3D.IDENTITY]])
		# This separate working insert retains the old lower plane and full
		# front/back extent. The holder and hardware fit inside the same envelope.
		_surface(mesh, "WorkingFace", [[ProductionVisuals.box_mesh(Vector3(0.50, 0.05, 0.55)),
			Transform3D(Basis.IDENTITY, Vector3(0, -0.06, 0))]])
		var poses: Array[Transform3D] = []
		for side in [-1.0, 1.0]:
			for x in [-0.205, 0.205]:
				poses.append(Transform3D(Basis(Quaternion(Vector3.UP, Vector3.BACK * side)), Vector3(x, 0.025, side * 0.24)))
		_hardware(mesh, poses)
		meshes.tool = mesh
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
	static var rock_boulder_mesh: ArrayMesh

	static func ground_material() -> ShaderMaterial:
		if ground_source_status != "uninitialized":
			return ground_finish
		var loaded := ProductionSteelFloor.read_images(GROUND_ROOT, GROUND_FILES, Vector2i(512, 512))
		ground_source_status = loaded.status
		if loaded.status != "ready":
			push_error("Ground shading requires its complete qualified surface set.")
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
		# The stochastic mapping retains each source sample's physical scale.
		ground_finish.set_shader_parameter("source_extent", 1.4)
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
			# The mesh already carries the river/rapid palette. Do not multiply
			# it by a second dark teal tint. Transmission is an art approximation,
			# not depth-dependent absorption or a second water simulation.
			water_finish.albedo_color = Color(1.0, 1.0, 1.0, 0.68)
			water_finish.vertex_color_use_as_albedo = true
			water_finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water_finish.metallic = 0.0
			water_finish.metallic_specular = 0.255
			water_finish.roughness = 0.20
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
				var rapid := smoothstep(-5.6, -4.4, z_world) * (1.0 - smoothstep(-4.4, -2.8, z_world))
				rapid = maxf(rapid, smoothstep(8.2, 9.2, z_world) * (1.0 - smoothstep(9.2, 11.2, z_world)))
				var color := Color("235361").lerp(Color("8ec2c7"), rapid * 0.65)
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
		# Runtime GLB buffer import preserves images but does not create their
		# mip chains. Build them once with vector renormalization for normals.
		if color.generate_mipmaps() != OK or normal.generate_mipmaps(true) != OK or scalars.generate_mipmaps() != OK:
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
		if absf(position.x - 1.65) <= 7.7 and absf(position.z - 1.65) <= 7.7:
			return false
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
		for patch_index in range(24):
			var heading := float(patch_index) * 2.399963
			var radius := 9.8 + float(posmod(patch_index * 11, 31)) * 0.61
			var center := Vector3(1.65 + cos(heading) * radius, 0.0, 1.65 + sin(heading) * radius)
			center.y = Surface.height_at(center.x, center.z)
			var buffer := PackedFloat32Array()
			var bounds := AABB()
			var count := 0
			for candidate in range(32):
				var angle := random.randf_range(0.0, TAU)
				var spread := sqrt(random.randf()) * 2.2
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
		for name in ["GroundFoliage", "ForegroundBank", "PineUnderstory"]:
			_refresh_plant_patch(scenery.get_node_or_null(name) as MultiMeshInstance3D, volumes)
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
		# Young, soft-stemmed understory, not solid mature trees. Keep the
		# working bank open and retain the complete source mesh at each root.
		for n in range(24):
			var z := -5.0 + float((n * 7) % 24) * 0.65
			var x := river_center_x(z) - channel_half_width(z) - 2.2 - float(n % 3) * 0.75
			if _terrain_facet_normal(x, z).y < 0.86:
				continue
			var at := Vector3(x, Surface.height_at(x, z) - 0.015, z)
			var basis := Basis(Vector3.UP, float(n) * 2.399963).scaled_local(Vector3.ONE * (0.85 + 0.1 * float(n % 5)))
			var envelope: AABB = Transform3D(basis, at) * pine_cluster_mesh.get_aabb()
			var clear := envelope.position.z >= -8.0 and envelope.end.z <= 12.0
			var margin := 0.3 + 0.6 * envelope.size.z / 16.0
			for row in range(9):
				var edge_z := lerpf(envelope.position.z, envelope.end.z, float(row) / 8.0)
				if envelope.end.x >= river_center_x(edge_z) - channel_half_width(edge_z) - margin:
					clear = false
			for solid in Surface.support_boxes():
				var half: Vector3 = solid.size * 0.5
				var solid_bounds: AABB = Transform3D(solid.basis, solid.center) * AABB(-half, solid.size)
				if envelope.intersects(solid_bounds.grow(0.2)):
					clear = false
			if not clear:
				continue
			# Do not stack one expensive source mesh over another.
			for offset in range(0, buffer.size(), 12):
				if Vector2(at.x - buffer[offset + 3], at.z - buffer[offset + 11]).length() < 1.2:
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
			var faces: PackedVector3Array = Surface.rock_faces()
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for first in range(0, faces.size(), 3):
				var normal := (faces[first + 2] - faces[first]).cross(faces[first + 1] - faces[first]).normalized()
				for offset in range(3):
					var point := faces[first + offset]
					var uv := Vector2(point.x, point.z)
					if absf(normal.y) < 0.5:
						uv = Vector2(point.z, point.y) if absf(normal.x) > absf(normal.z) else Vector2(point.x, point.y)
					surface.set_normal(normal)
					surface.set_uv(uv)
					surface.set_color(Color.WHITE)
					surface.add_vertex(point)
			surface.generate_tangents()
			rock_boulder_mesh = surface.commit()
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
			var basis: Basis = spec.basis * Basis.from_scale(spec.scale)
			var color: Color = spec.color
			if stone_source_status == "ready":
				color = Color.WHITE.lerp(color, 0.2)
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
		return scenery

class FlatFixtureEnvironment:
	extends RefCounted
	## Visual scenery only. ActorWorld retains the flat floor and all collision.
	static var ground_finish: StandardMaterial3D
	static var water_finish: StandardMaterial3D
	static var sky_finish: PanoramaSkyMaterial

	static func _noise_texture(seed_value: int, normal_map: bool) -> NoiseTexture2D:
		var noise := FastNoiseLite.new()
		noise.seed = seed_value
		noise.frequency = 0.025 if not normal_map else 0.12
		noise.fractal_octaves = 4 if not normal_map else 3
		var texture := NoiseTexture2D.new()
		texture.width = 256
		texture.height = 256
		texture.seamless = true
		texture.generate_mipmaps = true
		texture.noise = noise
		texture.as_normal_map = normal_map
		texture.bump_strength = 0.8
		if not normal_map:
			var ramp := Gradient.new()
			ramp.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
			ramp.colors = PackedColorArray([Color("383e32"), Color("656852"), Color("9a9278")])
			texture.color_ramp = ramp
		return texture

	static func ground_material() -> StandardMaterial3D:
		if ground_finish == null:
			ground_finish = StandardMaterial3D.new()
			ground_finish.albedo_texture = _noise_texture(3471, false)
			ground_finish.roughness = 0.96
			ground_finish.normal_enabled = true
			ground_finish.normal_texture = _noise_texture(3471, true)
			ground_finish.normal_scale = 0.22
			ground_finish.uv1_scale = Vector3(48, 48, 1)
			ground_finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return ground_finish

	static func water_material() -> StandardMaterial3D:
		if water_finish == null:
			var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
			for y in range(128):
				for x in range(128):
					var u := float(x) / 128.0 * TAU
					var v := float(y) / 128.0 * TAU
					# Periodic analytic ripples; shading only, no displaced floor.
					var normal := Vector3(-0.16 * cos(u + v * 2.0), -0.28 * cos(v * 4.0) - 0.12 * cos(u + v * 2.0), 1).normalized()
					image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5))
			image.generate_mipmaps()
			water_finish = StandardMaterial3D.new()
			water_finish.albedo_color = Color("285763")
			water_finish.metallic = 0.28
			water_finish.roughness = 0.2
			water_finish.normal_enabled = true
			water_finish.normal_texture = ImageTexture.create_from_image(image)
			water_finish.normal_scale = 0.35
			water_finish.uv1_scale = Vector3(2, 8, 1)
			water_finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return water_finish

	static func panorama_material() -> PanoramaSkyMaterial:
		if sky_finish != null:
			return sky_finish
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

	static func _foliage() -> MultiMeshInstance3D:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for angle in [0.0, PI / 3.0, PI * 2.0 / 3.0]:
			var right := Vector3(cos(angle), 0, sin(angle)) * 0.025
			var tip := Vector3(0.04 * cos(angle), 0.18, 0.04 * sin(angle))
			surface.set_normal(Vector3(-sin(angle), 0, cos(angle)))
			for vertex in [-right, tip, right]:
				surface.add_vertex(vertex)
		var finish := StandardMaterial3D.new()
		finish.albedo_color = Color.WHITE
		finish.vertex_color_use_as_albedo = true
		finish.cull_mode = BaseMaterial3D.CULL_DISABLED
		finish.roughness = 1.0
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = surface.commit()
		instances.instance_count = 96
		var buffer := PackedFloat32Array()
		for n in range(96):
			var angle := float(n) * 2.399963
			var radius := 11.0 + float(posmod(n * 13, 29)) * 0.28
			var position := Vector3(1.65 + cos(angle) * radius, Geometry.GROUND_HEIGHT, 1.65 + sin(angle) * radius)
			var scale := 0.65 + float(posmod(n * 7, 13)) * 0.05
			var basis := Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale)
			var color := Color("5e714e").lerp(Color("9b9570"), float(n % 5) / 4.0)
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
		foliage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return foliage

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
		# Restrained ambient contact shading; direct sun and geometry stay exact.
		environment.ssao_enabled = true
		environment.ssao_radius = 0.55
		environment.ssao_intensity = 0.85
		environment.ssao_power = 1.2
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
		var plane := PlaneMesh.new()
		plane.size = Vector2(Geometry.DISPLAY_TERRAIN_SIZE, Geometry.DISPLAY_TERRAIN_SIZE)
		terrain.mesh = plane
		terrain.position.y = Geometry.GROUND_HEIGHT - 0.01
		terrain.material_override = ground_material()
		scenery.add_child(terrain)
		var stream := MeshInstance3D.new()
		stream.name = "StreamSurface"
		var water := PlaneMesh.new()
		water.size = Vector2(1.2, 13.4)
		stream.mesh = water
		stream.position = Vector3(-2.7, 0.03, 1.65)
		stream.material_override = water_material()
		stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scenery.add_child(stream)
		scenery.add_child(_foliage())
		return scenery

class ConstructionAudio:
	extends AudioStreamPlayer
	## Local acknowledgement only. No command, stock or simulation authority.
	signal cue_emitted(cue: String, identity: Array)
	const ROOT := "res://opening/assets/construction-audio"
	const FILES := {"belt_snap": "belt_snap.wav", "assembly": "assembly.wav",
		"coupling": "coupling.wav", "release": "release.wav"}
	static var streams: Dictionary = {}
	static var source_status := "uninitialized"
	var current_context := ""
	var heard: Dictionary = {}

	func _init() -> void:
		volume_db = -13.0
		max_polyphony = 3

	static func cue_for(action: Dictionary) -> String:
		match action.get("action", ""):
			"place":
				if action.get("kind") == "belt":
					return "belt_snap"
				if action.get("kind") in ["collector", "processor", "wheel"]:
					return "assembly"
			"place_gear", "place_shaft", "connect_drive", "connect":
				return "coupling"
			"remove", "disconnect_drive", "disconnect":
				return "release"
		return ""

	static func read_samples(directory: String = ROOT) -> Dictionary:
		var present := 0
		for file in FILES.values():
			if FileAccess.file_exists(directory.path_join(file)):
				present += 1
		if present == 0:
			return {"status": "missing", "streams": {}}
		if present != FILES.size():
			return {"status": "invalid", "reason": "incomplete_cues", "streams": {}}
		var loaded: Dictionary = {}
		for cue in FILES:
			var path := directory.path_join(FILES[cue])
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				return {"status": "invalid", "reason": "unreadable_" + cue, "streams": {}}
			var size := file.get_length()
			file.close()
			# Fixed local PCM clips, not arbitrary or unbounded user audio.
			if size < 44 or size > 65536:
				return {"status": "invalid", "reason": "cue_size_" + cue, "streams": {}}
			var sample := AudioStreamWAV.load_from_file(path)
			if sample == null or sample.stereo or sample.mix_rate != 44100 or sample.format != AudioStreamWAV.FORMAT_16_BITS \
					or sample.loop_mode != AudioStreamWAV.LOOP_DISABLED or sample.get_length() < 0.1 or sample.get_length() > 0.5:
				return {"status": "invalid", "reason": "cue_format_" + cue, "streams": {}}
			loaded[cue] = sample
		return {"status": "ready", "streams": loaded}

	static func make_stream(cue: String) -> AudioStreamWAV:
		if not FILES.has(cue):
			return null
		if streams.has(cue):
			return streams[cue]
		if source_status == "uninitialized":
			var loaded := read_samples()
			source_status = loaded.status
			if source_status == "ready":
				streams = loaded.streams
			elif source_status == "invalid":
				push_error("Invalid construction samples: " + str(loaded.reason))
		if source_status == "ready":
			return streams[cue]
		if source_status != "missing":
			return null
		# Historical fixed-roster captures retain their original generated cue.
		var rate := 44100
		var duration: float = {"belt_snap": 0.24, "assembly": 0.42, "coupling": 0.18, "release": 0.16}[cue]
		var count := roundi(duration * rate)
		var bytes := PackedByteArray()
		bytes.resize(count * 2)
		var random := RandomNumberGenerator.new()
		random.seed = {"belt_snap": 1627, "assembly": 3471, "coupling": 619, "release": 937}[cue]
		var low_noise := 0.0
		for n in range(count):
			var t := float(n) / float(rate)
			var noise := random.randf_range(-1, 1)
			low_noise = lerpf(low_noise, noise, 0.18)
			var sample := 0.0
			match cue:
				"belt_snap":
					sample = 0.22 * sin(TAU * 155.0 * t) * exp(-22.0 * t)
					sample += 0.19 * sin(TAU * (720.0 - 500.0 * t) * t) * exp(-46.0 * t)
					sample += 0.25 * (noise - low_noise) * exp(-110.0 * t)
					if t > 0.045:
						var latch := t - 0.045
						sample += 0.19 * sin(TAU * 1850.0 * latch) * exp(-65.0 * latch)
				"assembly":
					for mode in [[140.0, 0.22, 14.0], [480.0, 0.18, 23.0], [913.0, 0.1, 27.0], [1810.0, 0.06, 36.0]]:
						sample += mode[1] * sin(TAU * mode[0] * t) * exp(-mode[2] * t)
					sample += 0.18 * low_noise * exp(-30.0 * t)
				"coupling":
					sample = 0.23 * sin(TAU * 950.0 * t) * exp(-52.0 * t)
					sample += 0.13 * sin(TAU * 2410.0 * t) * exp(-65.0 * t)
					sample += 0.2 * (noise - low_noise) * exp(-95.0 * t)
				"release":
					sample = 0.2 * sin(TAU * (1500.0 - 2400.0 * t) * t) * exp(-48.0 * t)
					sample += 0.22 * low_noise * exp(-35.0 * t)
			var envelope := minf(1.0, t / 0.002) * clampf((duration - t) / 0.03, 0.0, 1.0)
			sample = 0.85 * sample * envelope if n > 0 and n < count - 1 else 0.0
			bytes.encode_s16(n * 2, clampi(roundi(sample * 32767.0), -32767, 32767))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = rate
		stream.stereo = false
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		stream.data = bytes
		streams[cue] = stream
		return stream

	func confirmed(action: Dictionary, outcome: Dictionary, live_context: String) -> bool:
		var cue := cue_for(action)
		if cue.is_empty() or typeof(outcome.get("accepted")) != TYPE_BOOL or not outcome.accepted:
			return false
		for flag in ["queued", "duplicate"]:
			if typeof(outcome.get(flag, false)) != TYPE_BOOL or outcome.get(flag, false):
				return false
		var identity: Array[String] = []
		for field in ["context", "client", "request"]:
			if typeof(action.get(field)) != TYPE_STRING or action[field].is_empty() or outcome.get(field) != action[field]:
				return false
			identity.append(action[field])
		if live_context.is_empty() or identity[0] != live_context:
			return false
		if current_context != live_context:
			current_context = live_context
			heard.clear()
		var key := JSON.stringify(identity)
		if heard.has(key):
			return false
		var next_stream := make_stream(cue)
		if next_stream == null:
			return false
		heard[key] = true
		stream = next_stream
		play()
		cue_emitted.emit(cue, identity)
		return true

class MechanicalAmbience:
	extends Node3D
	## Disposable audio from confirmed motion, never a simulation clock.
	static var loops: Dictionary = {}
	var emitters: Dictionary = {}
	var listener: AudioListener3D
	var context := ""

	func _init() -> void:
		listener = AudioListener3D.new()
		listener.name = "WorkerAudioListener"
		add_child(listener)

	static func make_loop(kind: String) -> AudioStreamWAV:
		if kind not in ["collector", "belt", "processor", "wheel"]:
			return null
		if loops.has(kind):
			return loops[kind]
		var cycles: int = {"collector": 190, "belt": 124, "processor": 98, "wheel": 76}[kind]
		var random := RandomNumberGenerator.new()
		random.seed = {"collector": 3461, "belt": 6127, "processor": 1987, "wheel": 4231}[kind]
		var partials: Array = []
		for n in range(24):
			partials.append([random.randi_range(180, 5200), random.randf_range(0, TAU)])
		var count := 88200
		var bytes := PackedByteArray()
		bytes.resize(count * 2)
		for n in range(count):
			var phase := float(n) / count
			# Every component has an integer number of cycles in this two-second
			# loop. Its seam is continuous; it does not claim a physical phase.
			var tone := 0.11 * sin(TAU * cycles * phase) + 0.035 * sin(TAU * cycles * 2 * phase)
			var grain := 0.0
			for partial in partials:
				grain += sin(TAU * int(partial[0]) * phase + float(partial[1])) * 0.0025
			var envelope := 0.78 + 0.22 * cos(TAU * phase * 3.0)
			var sample := clampf((tone + grain) * envelope, -0.25, 0.25)
			bytes.encode_s16(n * 2, roundi(sample * 32767.0))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 44100
		stream.stereo = false
		stream.data = bytes
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
		loops[kind] = stream
		return stream

	static func _numeric(value: Variant) -> bool:
		return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

	static func _pose(value: Variant) -> bool:
		return value is Array and value.size() == 3 and _numeric(value[0]) and _numeric(value[1]) and _numeric(value[2])

	static func _rotating(value: Variant) -> bool:
		return value is Dictionary and value.get("state") == "rotating" and typeof(value.get("numerator")) == TYPE_INT \
			and typeof(value.get("denominator")) == TYPE_INT and value.denominator > 0 and value.numerator != 0

	func silence() -> void:
		for emitter in emitters.values():
			emitter.stop()
			emitter.free()
		emitters.clear()
		if is_inside_tree() and listener.is_current():
			listener.clear_current()
		context = ""

	func sync(snapshot: Dictionary, actor: String, ready: bool, camera_basis: Basis) -> void:
		var options: Variant = snapshot.get("options")
		var actors: Variant = snapshot.get("actors")
		var body: Variant = actors.get(actor) if actors is Dictionary else null
		var entities: Variant = snapshot.get("entities")
		var motions: Variant = snapshot.get("motion")
		var world: Variant = snapshot.get("context")
		if not ready or not is_inside_tree() or not options is Dictionary or typeof(options.get("native")) != TYPE_BOOL \
			or not options.native or not body is Dictionary or typeof(body.get("ready")) != TYPE_BOOL or not body.ready \
			or not _pose(body.get("position")) or not entities is Dictionary or not motions is Dictionary \
			or typeof(world) != TYPE_STRING or world.is_empty() or not camera_basis.is_finite() or absf(camera_basis.determinant()) < 0.5:
			silence()
			return
		if world != context:
			silence()
			context = world
		# Body origin plus a presentation-only ear offset. Camera distance cannot
		# move the listener away from the worker or grant construction reach.
		listener.position = Vector3(body.position[0], body.position[1], body.position[2]) + Vector3.UP * 0.55
		listener.basis = camera_basis.orthonormalized()
		if not listener.is_current():
			listener.make_current()
		var audible: Dictionary = {}
		for id: Variant in entities:
			var entity: Variant = entities[id]
			var motion: Variant = motions.get(id)
			if typeof(id) != TYPE_STRING or not entity is Dictionary or not _rotating(motion):
				continue
			var kind: Variant = entity.get("kind")
			var cell: Variant = entity.get("cell")
			if typeof(kind) != TYPE_STRING or kind not in ["collector", "belt", "processor", "wheel"] \
				or not cell is Array or cell.size() != 2 or typeof(cell[0]) != TYPE_INT or typeof(cell[1]) != TYPE_INT:
				continue
			audible[id] = true
			if emitters.has(id) and emitters[id].get_meta("kind") != kind:
				emitters[id].stop()
				emitters[id].free()
				emitters.erase(id)
			if not emitters.has(id):
				var emitter := AudioStreamPlayer3D.new()
				emitter.set_meta("entity", id)
				emitter.set_meta("kind", kind)
				emitter.stream = make_loop(kind)
				emitter.volume_db = -23.0
				emitter.max_db = -14.0
				emitter.unit_size = 2.5
				emitter.max_distance = 16.0
				emitter.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
				emitter.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
				add_child(emitter)
				emitters[id] = emitter
			# A bounded timbre change, not a rate clamp in the native mechanics.
			emitters[id].pitch_scale = clampf(absf(float(motion.numerator) / float(motion.denominator)), 0.6, 1.8)
			emitters[id].position = Vector3(cell[0] * Geometry.PITCH, 0.7, cell[1] * Geometry.PITCH)
			if not emitters[id].playing:
				emitters[id].play()
		for id in emitters.keys():
			if not audible.has(id):
				emitters[id].stop()
				emitters[id].free()
				emitters.erase(id)

class ProductionInterface:
	extends RefCounted
	## Draw styles only. Effective content metrics remain the engine defaults.
	static var shared_theme: Theme

	static func _style(source: StyleBox, fill: Color, line: Color, focus: bool = false) -> StyleBoxFlat:
		var style := source.duplicate() as StyleBoxFlat
		if style == null:
			style = StyleBoxFlat.new()
		for side in range(4):
			# get_margin resolves a negative raw content margin through the old
			# border. Freeze that effective metric before drawing new borders.
			style.set_content_margin(side, source.get_margin(side))
		style.bg_color = fill
		style.border_color = line
		style.set_border_width_all(2 if focus else 1)
		style.set_corner_radius_all(4)
		style.corner_detail = 4
		style.draw_center = not focus
		return style

	static func make_theme() -> Theme:
		if shared_theme != null:
			return shared_theme
		var theme := Theme.new()
		theme.default_font_size = 15
		var original := ThemeDB.get_default_theme()
		var fills := {"normal": Color("1c2a30"), "hover": Color("2d4149"),
			"pressed": Color("5a472d"), "hover_pressed": Color("685337"), "disabled": Color("172126")}
		var borders := {"normal": Color("41565e"), "hover": Color("8ca7a8"),
			"pressed": Color("d6ab64"), "hover_pressed": Color("edcc8d"), "disabled": Color("2c3b41")}
		for control_type in ["Button", "MenuButton"]:
			# Resolve the actual inherited defaults. MenuButton has its own
			# zero-padding styles; borrowing Button metrics would widen it.
			var probe: Button = MenuButton.new() if control_type == "MenuButton" else Button.new()
			for name_value in fills:
				theme.set_stylebox(name_value, control_type, _style(probe.get_theme_stylebox(name_value), fills[name_value], borders[name_value]))
			theme.set_stylebox("focus", control_type, _style(probe.get_theme_stylebox("focus"), Color.TRANSPARENT, Color("efc78a"), true))
			for name_value in ["font_color", "font_hover_color", "font_focus_color"]:
				theme.set_color(name_value, control_type, Color("e4ebe4"))
			for name_value in ["font_pressed_color", "font_hover_pressed_color"]:
				theme.set_color(name_value, control_type, Color("fff2d6"))
			theme.set_color("font_disabled_color", control_type, Color("879895"))
			probe.free()
		var separator := original.get_stylebox("separator", "HSeparator").duplicate() as StyleBox
		if separator is StyleBoxLine:
			separator.color = Color("41565e")
		theme.set_stylebox("separator", "HSeparator", separator)
		shared_theme = theme
		return theme

const STEP_SECONDS := 0.45
const PITCH := Geometry.PITCH
const NAMES := {"collector": "Collector", "belt": "Belt", "processor": "Press", "wheel": "Waterwheel", "foundation": "Foundation"}
const COLORS := {"collector": Color("96805c"), "belt": Color("538e88"), "processor": Color("bd7054"), "wheel": Color("8b9caa")}
const LESSONS := [
	["01  /  BUILD THE PATH", "Place a collector, a belt and a press in a row. Material ports face along the brass arrow. Each placed machine uses a part from your carried kit."],
	["02  /  CONNECT THE DRIVE", "Place the waterwheel beside your line. Choose Drive link, then click two neighboring machines. Carry its rotation through the whole line; the stream supplies motion without fuel."],
	["03  /  FOLLOW ONE BLANK", "The collector removes a blank from the finite seam. The belt carries it to the press. Advance the example one tick at a time. The held blank stays in the press until its plate can leave."],
	["04  /  MAKE ROOM", "A full press outlet holds up the line. Collect the example plate below: the held blank finishes without being lost. Stopping the drive keeps the parts and unfinished work where they are."]
]

var model
var legacy_fixture := false
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
var mode := "collector"
var pending_link := ""
var selected := ""
var goal_confirmed := false
var explanation_open := false
var lesson_index := 0
var example_presenter
var lesson_next: Button
var lesson_previous: Button
var lesson_return: Button
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
var camera: Camera3D
var machine_root: Node3D
var item_root: Node3D
var workpiece_item_assets
var hover: MeshInstance3D
var selection_ring: MeshInstance3D
var placement_hint: Node3D
var placement_target_label: Label3D
var machine_preview: Node3D
var machine_preview_key := ""
var machine_preview_material: StandardMaterial3D
var wheel_rotor: Node3D
var machine_body_context := ""
var machine_press_poses: Dictionary = {}
var status_label: Label
var status_footer: Control
var status_refused := false
var footer_snapshot_ready := false
var footer_fit_pending := false
var stock_label: Label
var parts_label: Label
var goal_label: Label
var power_label: Label
var inspector: Label
var recovery_actions
var loose_material_controls
var transmission_controls
var transmission_presenter
var construction_audio
var engineering_presenter
var mechanical_ambience
var confirm_button: Button
var retrieve_button: Button
var power_button: Button
var remove_button: Button
var save_button: Button
var load_button: Button
var lesson_panel: PanelContainer
var lesson_title: Label
var lesson_body: Label
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
var show_details := false
var catalog_button: Button
var details_button: Button
var controls_label: Label

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--legacy-fixture":
			legacy_fixture = true
	if model == null:
		model = Model.new(16, "opening-local-1", 1, {"opening": true} if legacy_fixture else {"opening": true, "physical": true})
	if save_slot.is_empty():
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--save-slot="):
				configure_save_slot(argument.trim_prefix("--save-slot="))
	_build_world()
	_build_interface()
	_refresh()
	if _native_transmission():
		_message("WASD walks. Approach the mineral seam to place your collector.")
	else:
		_message("Build a small line. Choose a part, then click a grid square." if legacy_fixture else "WASD walks. Build nearby; approach the wheel to operate the drive [P].")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="):
			var result: Dictionary = _load_worksite(argument.trim_prefix("--resume-input="), true)
			if not result.accepted or not model.projection().options.get("opening", false):
				push_error("Opening resume refused; no fresh-world fallback")
				get_tree().quit(1)
				return
			startup_resume_checkpoint = model.checkpoint()
			if legacy_fixture and not _save_worksite().accepted:
				push_error("Resumed worksite could not publish its new session slot")
				get_tree().quit(1)
				return
			startup_save_pending = not legacy_fixture
			_message("Worksite reopened in this session. Your original save is kept.")
	if not legacy_fixture:
		if not _start_character_world():
			return
		_start_character_presenter()

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
	return not legacy_fixture and not _catalog_open() and not explanation_open and not startup_save_pending and state.get("actors", {}).get(client, {}).get("ready", false)

func _can_choose_tool() -> bool:
	# The catalog holds movement while keeping its own choices available.
	return not explanation_open and not startup_save_pending and (legacy_fixture or state.get("actors", {}).get(client, {}).get("ready", false))

func _native_transmission() -> bool:
	return not legacy_fixture and state.get("options", {}).get("native", false)

func _can_present_confirmed_motion() -> bool:
	return _native_transmission() and not explanation_open and not startup_save_pending and state.get("actors", {}).get(client, {}).get("ready", false)

func _contains_target(snapshot: Dictionary, id: String) -> bool:
	return snapshot.get("entities", {}).has(id) or snapshot.get("foundations", {}).has(id) or (snapshot.get("options", {}).get("native", false)
		and (snapshot.get("transmission_parts", {}).has(id) or snapshot.get("belt_spans", {}).has(id)))

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
		build_column.add_child(transmission_controls)
		transmission_controls.configure(self)
		transmission_presenter = load(presenter_path).new()
		add_child(transmission_presenter)
		transmission_presenter.configure(self)
	transmission_controls.refresh()
	transmission_presenter.refresh()
	var active: bool = not transmission_controls.active_tool.is_empty()
	transmission_controls.visible = active or _catalog_open() or goal_confirmed or int(state.get("inventories", {}).get(client, 0)) > 0 or not state.get("transmission_parts", {}).is_empty()
	if not active and mode in ["gear", "drive", "belt"]:
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
	if transmission_controls.active_tool in ["place_shaft", "gear"]:
		var part: Variant = state.get("transmission_parts", {}).get(entity_id)
		if part is Dictionary and part.get("kind") in ["shaft", "gear"]:
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

func _power_key() -> String:
	return "Space" if legacy_fixture else "P"

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
		var physical := {"accepted": true}
		if not legacy_fixture:
			physical = actor_world.checkpoint_status() if actor_world != null else {"accepted": false, "reason": "actor_unready"}
		last_save_result = Store.write(model, save_slot) if physical.accepted else {"accepted": false, "reason": physical.reason}
		if not legacy_fixture:
			last_save_result["native_preflight"] = physical.duplicate(true)
	if last_save_result.accepted:
		save_slot_owned = true
		_message("Worksite saved. Load returns to this moment." if legacy_fixture else "Worksite saved. Reopen this save through the launcher in a new session.")
	else:
		_message("Save unavailable. Your current worksite and previous save are kept.", true)
	_refresh_ui()
	return last_save_result

func _load_worksite(path: String = "", startup_resume := false) -> Dictionary:
	if not legacy_fixture and not startup_resume:
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
	construction_audio.confirmed(intent, outcome, str(model.projection().get("context", "")))

func issue(action: Dictionary) -> Dictionary:
	if explanation_open:
		return {"accepted": false, "reason": "explanation_open"}
	if startup_save_pending:
		_message("Finishing the saved worksite's opening. Wait a moment.")
		return {"accepted": false, "reason": "worksite_starting"}
	if not legacy_fixture and actor_world != null:
		for actor in model.projection().actors:
			actor_world.ensure_actor(actor)
	request_sequence += 1
	var intent: Dictionary = action.duplicate(true)
	intent.merge({"context": model.projection().context, "client": client,
		"request": request_namespace + str(request_sequence)}, true)
	var outcome: Dictionary = model.command(intent)
	if not legacy_fixture and actor_world != null:
		actor_world.sync_topology()
	if outcome.accepted:
		if action.action in ["place_gear", "place_shaft"]:
			selected = str(outcome.get("entity", ""))
		elif action.action in ["remove", "remove_belt_span"] and selected == action.get("entity", ""):
			selected = ""
		_construction_feedback(intent, outcome)
		_message({"place": "Placed. Parts stay with this worksite.",
			"place_foundation": "Foundation placed. Its surface shares the machine grid.",
			"place_foundations": "Foundation area placed on the world grid.",
			"connect": "Material path connected.", "connect_drive": "Drive shaft connected.",
			"retrieve": "Plate collected.", "pickup_material": "Loose material collected.", "set_power": "Drive updated.",
			"remove": "Part returned to your carried kit.",
			"disconnect": "Material connection removed.",
			"disconnect_drive": "Drive shaft returned."}.get(action.action, "Done."))
	else:
		_message(_material_refusal_message(outcome, {"occupied": "That square is occupied.", "no_part": "That part is already placed.",
			"ports_not_adjacent": "Connect neighboring ports, following the arrow.",
			"invalid_belt_axis": "The belt's drive shaft runs across the belt, perpendicular to material travel.",
			"missing_entity": "Choose a placed machine at each end.",
			"already_connected": "Those ports are already connected.",
			"unavailable_output": "There is no finished plate to collect yet.",
			"out_of_reach": "Move closer to the target before building or interacting.",
			"actor_unready": "Your character is not ready yet. Wait a moment.",
			"actor_occupied": "A character is in that square. Move clear before placing the machine.",
			"powered": "Stop the drive before changing the machinery.",
			"not_stopped": "Stop the drive before changing the machinery.",
			"held_stock": "Retrieve the material before removing this machine.",
			"contains_stock": "Retrieve the material before removing this machine.",
			"not_at_stream": "Set the wheel in the water with its lower rim immersed and clear of the bed.",
			"not_at_seam": "Place the collector at the exposed mineral seam.",
			"no_shaft": "All carried shafts are in use."}.get(outcome.reason, "That action is unavailable here.")), true)
	_refresh()
	return outcome

func _material_refusal_message(outcome: Dictionary, fallback: String) -> String:
	var foundation_advice: String = {
		"unaligned_elevation": "Machines and wheels need a whole-tile height. Build a factory floor with Access steps off, or adjust the wheel's drive height.",
		"axles_already_touch": "These axle ends already touch; no shaft is needed.",
		"overlapping_shafts": "A shaft already occupies that length. Place the new segment end to end.",
		"foundation_required": "Build a foundation here first so the machine has a level surface.",
		"invalid_area": "Choose a rectangle of at most 256 foundation tiles.",
		"foundation_in_use": "Remove the machinery on this foundation before reclaiming it.",
		"site_occupied": "Rock or vegetation occupies this space. Choose a clear location.",
		"terrain_unavailable": "There is no confirmed building surface here."}.get(outcome.get("reason", ""), "")
	if not foundation_advice.is_empty():
		return foundation_advice
	# Fixed-roster historical payloads may omit the helper or carry its older
	# API. Formatting must never add a resource requirement or change admission.
	if recovery_actions != null and recovery_actions.has_method("refusal_text"):
		var text: Variant = recovery_actions.call("refusal_text", outcome)
		if typeof(text) == TYPE_STRING and not text.is_empty():
			return text
	if _native_transmission() and outcome.get("reason") == "not_at_seam":
		return "Place the collector at the exposed mineral seam."
	return fallback

func _process(delta: float) -> void:
	if actor_world != null:
		actor_world.set_belt_step_seconds(STEP_SECONDS if auto_advance else 0.0)
	if auto_advance:
		elapsed += delta
		while elapsed >= STEP_SECONDS:
			elapsed -= STEP_SECONDS
			model.advance()
		_refresh()
	_refresh_machine_preview()
	_refresh_water()
	_refresh_mechanical_audio()
	_animate_wheel(delta)
	if explanation_open:
		example_presenter.pan(delta)
		return
	_update_camera()
	if not legacy_fixture:
		return
	var pan := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		focus += Vector3(pan.x, 0, pan.y) * delta * 4.0
		focus.x = clampf(focus.x, -4, 6)
		focus.z = clampf(focus.z, -4, 6)

func _water_time_seconds() -> float:
	return float(Time.get_ticks_msec()) * 0.001

func _refresh_water() -> void:
	if not legacy_fixture and ProductionEnvironment.Surface != null:
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
	mechanical_ambience.sync(state, client, true, camera.global_basis)

func _animate_wheel(delta: float) -> void:
	if _native_transmission():
		if transmission_presenter == null:
			return
		transmission_presenter.advance_visual_motion(delta)
		if wheel_rotor != null:
			for id: String in state.get("entities", {}):
				if state.entities[id].kind != "wheel":
					continue
				if not wheel_rotor.has_meta("visual_base_basis"):
					wheel_rotor.set_meta("visual_base_basis", wheel_rotor.basis)
				var base: Basis = wheel_rotor.get_meta("visual_base_basis")
				wheel_rotor.basis = base * Basis(Vector3.BACK, transmission_presenter.visual_angle(id))
		_animate_machine_bodies(delta)
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
	for anchor in machine_root.get_children():
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
	var loop := anchor.find_child("ConveyorLoop", true, false) as MeshInstance3D
	if loop == null or not loop.material_override is StandardMaterial3D:
		return
	var length_value := 4.0 * ProductionConveyorArt.HALF_SPAN + TAU * ProductionConveyorArt.RADIUS
	var repeats := maxi(1, roundi(length_value / ProductionConveyorArt.SOURCE_METRES))
	# The top profile runs toward +X as UV increases. Positive +Z shaft
	# rotation carries the top toward -X, so the texture offset increases.
	var direction := -1.0 if anchor.get_meta("material_rotated", false) else 1.0
	var offset := fposmod(direction * rotation * ProductionConveyorArt.RADIUS * repeats / length_value, 1.0)
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
	var pivot := Vector3(-0.22, 1.1, -0.19)
	var axle := Vector3.BACK
	if anchor.get_meta("material_rotated", false):
		var turn := Basis(Vector3.UP, -PI / 2.0)
		pivot = turn * pivot
		axle = turn * axle
	var spin := Transform3D(Basis(axle, angle), Vector3.ZERO)
	spin.origin = pivot - spin.basis * pivot
	for row in rows:
		if is_instance_valid(row.node) and row.role == "cutter":
			row.node.transform = row.parent_inverse * spin * row.rest
	anchor.set_meta("cutter_angle", angle)

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

func _input(event: InputEvent) -> void:
	if explanation_open:
		if event is InputEventKey:
			if event.pressed and not event.echo:
				match event.keycode:
					KEY_H, KEY_ESCAPE: _toggle_explanation()
					KEY_RIGHT: _set_lesson(lesson_index + 1)
					KEY_LEFT: _set_lesson(lesson_index - 1)
					KEY_HOME: example_presenter.recenter()
			get_viewport().set_input_as_handled()
		elif example_presenter.handle_pointer(event):
			get_viewport().set_input_as_handled()
		return
	# Consume both edges of global shortcuts so a
	# previously focused GUI button cannot also activate on the release.
	if event is InputEventKey and (event.keycode in [KEY_F5, KEY_F9] or event.keycode == (KEY_SPACE if legacy_fixture else KEY_P)):
		if event.pressed and not event.echo and not explanation_open:
			match event.keycode:
				KEY_SPACE, KEY_P: _toggle_power()
				KEY_F5:
					if not startup_save_pending:
						_save_worksite()
				KEY_F9: _load_worksite()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if explanation_open:
		return
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			orbit_yaw -= event.relative.x * 0.007
			orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.005,
				-1.25 if not legacy_fixture and distance == 0.0 else 0.35, 1.25)
		else:
			hover_cell = _screen_cell(event.position)
			_update_cursor()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(10 if legacy_fixture else 0, distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(28 if legacy_fixture else 24, distance + 1)
			if not legacy_fixture and distance > 0.0:
				orbit_pitch = maxf(orbit_pitch, 0.35)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var entity_id := _screen_entity(event.position)
			if not _transmission_click(_transmission_center(event.position), entity_id):
				_world_click(_screen_cell(event.position), entity_id)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_8:
			building_hotbar.select_slot(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_B: building_hotbar.open_catalog()
			KEY_PAGEUP: _adjust_foundation_level(1)
			KEY_PAGEDOWN: _adjust_foundation_level(-1)
			KEY_F: _select_tool("flow")
			KEY_G: _select_tool("drive")
			KEY_I, KEY_ESCAPE: _select_tool("inspect")
			KEY_R: _retrieve()
			KEY_H: _toggle_explanation()
			KEY_HOME:
				if legacy_fixture:
					focus = Vector3(1.3, 0, 1.1)
				distance = 18.5 if legacy_fixture else 14.0
	_update_camera()

func _select_tool(tool: String) -> void:
	if explanation_open:
		return
	if transmission_controls != null:
		transmission_controls.cancel()
	mode = tool
	foundation_area_started = false
	pending_link = ""
	if _native_transmission() and transmission_controls != null and tool in ["gear", "drive", "belt"]:
		transmission_controls.choose_tool({"gear": "gear", "drive": "place_shaft", "belt": "belt_span"}[tool])
	_update_cursor()
	_refresh_ui()
	var instructions := {"flow": "Click the upstream machine, then its neighbor toward the brass arrow.",
		"drive": "Click two neighboring machines to connect a drive shaft.",
		"inspect": "Click a machine to inspect it or collect its finished work.",
		"collector": "Place the collector on the brass seam strip.",
		"wheel": "Place the waterwheel in the flowing stream. Set its height to align its axle with your shafts."}
	if _native_transmission():
		instructions["collector"] = "Place the collector at the exposed mineral seam."
		instructions["belt"] = "Choose two parallel shafts within reach. The belt runs across their axle, not along it."
		instructions["flow"] = "Choose the upstream machine, then its neighbor at the material outlet."
		instructions["drive"] = "Point at a floor to match its height, a part face to snap beside it, or a belt to add a pulley. Set the shaft axis in its menu."
		instructions["gear"] = "Point at a floor to match its height or a part face to snap beside it. Set the cogwheel axis in its menu."
		instructions["foundation"] = "Place a foundation at the displayed world height. Page Up / Page Down move one foundation thickness so stacked blocks touch; Access steps enables smaller walking steps. Machines need whole-tile factory floors. Area chooses two corners; Esc cancels."
	_message(instructions.get(tool,
		"Place %s on an empty grid square." % NAMES.get(tool, tool)))

func _world_click(cell: Vector2i, entity_id: String = "") -> void:
	if explanation_open:
		return
	if _native_transmission():
		var height: int = transmission_controls.gear_height if transmission_controls != null else 0
		if _transmission_click([cell.x * 4, height, cell.y * 4], entity_id):
			return
		if mode == "belt":
			_message("Select the Belt tool and choose two parallel shafts.", true)
			return
		if mode == "inspect" and (state.get("transmission_parts", {}).has(entity_id) or state.get("belt_spans", {}).has(entity_id)):
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
				action["axis"] = transmission_controls.selected_axis
		var outcome := issue(action)
		if outcome.accepted:
			selected = outcome.entity
	_refresh_ui()
	_update_cursor()

func _retrieve() -> void:
	var target := selected
	if target.is_empty() or not state.entities.has(target) or state.entities[target].kind != "processor":
		_message("Select the press to collect its finished plate.", true)
		return
	issue({"action": "retrieve", "amount": 1, "entity": target})

func _toggle_power() -> void:
	issue({"action": "set_power", "active": not state.get("power_enabled", true)})

func _remove_selected() -> void:
	if not selected.is_empty():
		var removal := "remove_belt_span" if _native_transmission() and state.get("belt_spans", {}).has(selected) else "remove"
		var outcome := issue({"action": removal, "entity": selected})
		if outcome.accepted:
			selected = ""
			_refresh_ui()

func _confirm_goal() -> void:
	if explanation_open:
		return
	if int(model.projection().inventories.get(client, 0)) >= 4:
		goal_confirmed = true
		_message("Four plates ready. Your first production line is working.")
		_refresh_ui()

func _toggle_explanation() -> void:
	explanation_open = not explanation_open
	lesson_panel.visible = explanation_open
	if explanation_open:
		_release_character_controls()
		if example_presenter == null:
			# Lazy loading avoids a static cycle with the geometry-only subclass.
			example_presenter = load("res://opening/example_presenter.gd").new()
			lesson_panel.get_parent().add_child(example_presenter)
			# Set the far anchor first so the near anchor is not clamped.
			example_presenter.set_anchor_and_offset(SIDE_RIGHT, 0.5, 340)
			example_presenter.set_anchor_and_offset(SIDE_LEFT, 0.5, -330)
			example_presenter.set_anchor_and_offset(SIDE_TOP, 0.0, 226)
			example_presenter.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -128)
		example_presenter.show()
		example_presenter.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		example_presenter.world.set_process(true)
		_set_lesson(0)
	else:
		example_presenter.hide()
		example_presenter.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		example_presenter.world.set_process(false)
	_update_cursor()
	_refresh_ui()

func _set_lesson(index: int) -> void:
	lesson_index = posmod(index, LESSONS.size())
	lesson_title.text = LESSONS[lesson_index][0]
	lesson_body.text = LESSONS[lesson_index][1]
	if lesson_index == 0 and _native_transmission():
		lesson_body.text = "Place a collector and a press. Place one-tile shafts at the ends of the route, with their parallel axles across the belt's path. Connect the shafts with a belt. It carries blanks when its top moves toward the press."
	if lesson_index == 1 and _native_transmission():
		lesson_body.text = "Place the waterwheel in the stream with its lower rim wet and clear of the bed. Set its diameter, height and axle. Place one-tile shafts to carry rotation. Small cogs with matching axes mesh side by side in one plane; a small and a large cog mesh diagonally in that plane. These meshes reverse rotation, and different sizes change speed. Two large cogs on perpendicular axes turn a corner when offset one tile along each axle."
	if example_presenter != null:
		example_presenter.set_lesson(lesson_index)

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
	return str(hit.collider.get_meta("entity", "")) if not hit.is_empty() else ""

func _screen_pick(screen: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 80)
	query.collision_mask = Geometry.PICK_LAYER
	return get_world_3d().direct_space_state.intersect_ray(query)

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
	_refresh_placement_hint(true)

func _assemble_foundation(parent: Node3D, neighbor_mask: int = 0) -> void:
	# Only confirmed player-built surfaces or an explicit placement preview
	# call this; the unbuilt site receives no manufactured structures.
	if not ProductionFoundationArt.mount(parent, neighbor_mask):
		push_error("The foundation needs its complete concrete and steel art kit.")
		if is_inside_tree():
			get_tree().quit(1)

func _update_camera() -> void:
	var back := Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch))
	var eye_offset := 0.0 if legacy_fixture else FIRST_PERSON_EYE_OFFSET * (1.0 - clampf(distance / FIRST_PERSON_BLEND_DISTANCE, 0.0, 1.0))
	camera.position = focus + Vector3.UP * eye_offset + back * distance
	# At zero distance look along the same orbit ray instead of looking at the
	# camera's own position. The local mesh remains real but cannot fill the view.
	camera.look_at(camera.position - back)
	if character_presenter != null and character_presenter.views.has(client):
		var local_view: Node3D = character_presenter.views[client]
		var local_actor: Dictionary = state.get("actors", {}).get(client, {})
		local_view.visible = distance > 1.0 and local_actor.get("ready", false) \
			and Geometry.valid_position(local_actor.get("position"))

func _build_world() -> void:
	if not legacy_fixture and ProductionEnvironment.Surface != null:
		ProductionEnvironment.build(self)
	elif not legacy_fixture:
		FlatFixtureEnvironment.build(self)
	else:
		var environment := WorldEnvironment.new()
		var settings := Environment.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color("536f86")
		sky_material.sky_horizon_color = Color("d8cbb2")
		sky_material.ground_bottom_color = Color("394641")
		sky_material.ground_horizon_color = Color("b5b8a1")
		var sky := Sky.new()
		sky.sky_material = sky_material
		settings.background_mode = Environment.BG_SKY
		settings.sky = sky
		settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		settings.ambient_light_energy = 0.5
		settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		environment.environment = settings
		add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-48, -30, 0)
		sun.light_color = Color("fff1d6")
		sun.light_energy = 1.35
		sun.shadow_enabled = true
		add_child(sun)
		# Keep the back of machinery readable without adding a second shadow map.
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-32, 135, 0)
		fill.light_color = Color("b9d2ea")
		fill.light_energy = 0.35
		fill.shadow_enabled = false
		add_child(fill)
	if legacy_fixture or ProductionEnvironment.Surface == null:
		_box(self, Vector3(1.65, -0.55, 1.65), Vector3(13.4, 0.8, 13.4), Color("394641"))
		var foundation_finish: StandardMaterial3D = ProductionSteelFloor.material() if not legacy_fixture else null
		set_meta("foundation_surface", "legacy")
		for x in range(-2, 5):
			for z in range(-2, 5):
				# Subtle panel variation replaces the debug checkerboard. Existing
				# seams, grid dimensions and physical ground stay unchanged.
				var tint := Color("74766b").darkened(float(posmod(x * 17 + z * 31, 5)) * 0.018)
				var panel := _machine_box(self, "FoundationPanel", Vector3(x * PITCH, -0.08, z * PITCH),
					Vector3(PITCH - 0.035, 0.12, PITCH - 0.035), tint, 0.0, 0.95)
				panel.set_meta("surface_role", "foundation")
				if foundation_finish != null:
					panel.material_override = foundation_finish
		_box(self, Vector3(-2.7, 0.0, 1.65), Vector3(1.2, 0.06, 13.4), Color("396c76"))
		for z in range(-3, 6):
			_box(self, Vector3(-2.7, 0.04, z * 1.3), Vector3(0.85, 0.018, 0.035), Color("72a5a7"))
		_box(self, Vector3(0, 0.005, 1.65), Vector3(0.12, 0.035, 13.4), Color("a58c59"))
		for z in [-1.8, -1.4, -1.0]:
			_box(self, Vector3(-3.75, 0.02, z), Vector3(0.12, 0.08, 0.22), Color("be9957"))
		var arrow := _text(self, "MATERIAL  →", Vector3(1.6, 0.08, -4.15), Color("e4bc70"), 0.005)
		arrow.rotation_degrees.x = -90
	else:
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
	machine_root = Node3D.new()
	add_child(machine_root)
	item_root = Node3D.new()
	add_child(item_root)
	hover = _box(self, Vector3.ZERO, Vector3(1.5, 0.035, 1.5), Color(0.85, 0.75, 0.45, 0.45))
	hover.visible = false
	selection_ring = _selection_outline()
	selection_ring.visible = false
	_build_placement_hint()
	camera = Camera3D.new()
	camera.fov = 45
	camera.near = 0.1
	camera.far = 100
	add_child(camera)
	camera.make_current()
	_update_camera()

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
	var part := _cylinder(parent, at, radius, height, color)
	part.name = part_name
	part.rotation = orientation
	(part.mesh as CylinderMesh).radial_segments = 48
	part.material_override = ProductionVisuals.material(color, 0.85, 0.4)
	return part

func _machine_axis(entity: Dictionary) -> Vector3:
	# Native projections use the Host's X/Y/Z enumeration. Older projections
	# without an axis retain the original X default.
	return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][int(entity.get("axis", 0))]

func _spindle_rotation(axis: Vector3) -> Vector3:
	if axis == Vector3.UP:
		return Vector3.ZERO
	return Vector3(0, 0, PI / 2) if axis == Vector3.RIGHT else Vector3(PI / 2, 0, 0)

func _machine_drive_stub(anchor: Node3D, entity: Dictionary, press_input: bool = false) -> void:
	if state.get("options", {}).get("native", false):
		var axis := _machine_axis(entity)
		# The vertical stub stays above the base inside the same pick envelope.
		var height := 0.9 if axis == Vector3.UP else 1.35
		var journal := MeshInstance3D.new()
		journal.name = "DriveStub"
		journal.position = Vector3(0, Geometry.ANCHOR_HEIGHT, 0)
		journal.rotation = _spindle_rotation(axis)
		var horizontal_press := press_input and axis != Vector3.UP
		journal.mesh = ProductionDriveJournalArt.press_mesh() if horizontal_press else ProductionDriveJournalArt.mesh(height)
		journal.material_override = ProductionDriveJournalArt.material()
		anchor.add_child(journal)
		if horizontal_press:
			ProductionDriveJournalArt.mount_press_bearings(anchor, axis)
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
	if not (_native_transmission() and ProductionCollectorFeedArt.mount(anchor, frame)):
		for z in [-0.37, 0.37]:
			_machine_box(anchor, "StockGuide", Vector3(0.05, 0.6, z), Vector3(1.15, 0.08, 0.06), frame)
	_machine_drive_stub(anchor, entity)

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
	if not (sourced and _native_transmission() and ProductionPressCrownArt.mount(anchor, frame)):
		_machine_box(anchor, "PressBridge", Vector3(0, 1.5, -0.3), Vector3(1.2, 0.2, 0.36), frame, 0.05 if sourced else 0.08)
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
	var sourced := ProductionWheelArt.mount(wheel_rotor)
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

func _material_rotated(entity_id: String, entity: Dictionary) -> bool:
	if not _native_transmission():
		return false
	if entity.get("kind") == "belt":
		return int(entity.get("axis", 2)) == 0
	for pair in state.get("links", []):
		if pair.size() != 2 or entity_id not in pair:
			continue
		var other: Dictionary = state.get("entities", {}).get(pair[1] if pair[0] == entity_id else pair[0], {})
		if other.get("kind") == "belt":
			return int(other.get("axis", 2)) == 0
	return false

func _assemble_machine(anchor: Node3D, entity: Dictionary, rotated := false) -> void:
	anchor.set_meta("material_rotated", rotated)
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
		"collector": _collector_visual(anchor, entity)
		"belt": _belt_visual(anchor, entity)
		"processor": _press_visual(anchor, entity)
		"wheel": _wheel_visual(anchor, entity)
	if not water_wheel:
		_machine_surface_detail(anchor, entity.kind)

func _rebuild_machines() -> void:
	_sync_machine_body_context()
	var foundation_masks := ProductionFoundationArt.neighbor_masks(state.get("foundations", {}))
	var scenery := get_node_or_null("ProductionScenery")
	if scenery != null and not legacy_fixture and ProductionEnvironment.Surface != null:
		ProductionEnvironment.refresh_vegetation(scenery, state)
	for child in machine_root.get_children():
		child.free()
	wheel_rotor = null
	for id in state.get("foundations", {}):
		var surface: Dictionary = state.foundations[id]
		var anchor := Node3D.new()
		anchor.position = _entity_position(surface)
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
		anchor.set_meta("machine_entity", entity_id)
		anchor.set_meta("machine_kind", kind)
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
		anchor.add_child(body)
		var caption := _text(anchor, NAMES.get(kind, kind).to_upper(), Vector3(0, 1.9, 0), Color("f2e5c5"))
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

func _redraw_items() -> void:
	# The asset helper uses this script's shared surfaces, so load it after
	# the opening class is available instead of creating a preload cycle.
	if workpiece_item_assets == null:
		workpiece_item_assets = load("res://opening/workpiece_item_assets.gd")
	workpiece_item_assets.populate_items(item_root, state, PITCH)

func _refresh() -> void:
	state = model.projection()
	# Shared profiles arrive after presenter creation. Choose this revisable
	# default once, preserving any pitch already adjusted while connecting.
	if not native_camera_initialized and _native_transmission():
		native_camera_initialized = true
		if orbit_pitch == 0.82:
			orbit_pitch = 0.60
	if actor_world != null:
		actor_world.sync_topology()
	var next_key := JSON.stringify([state.entities, state.links, state.get("drive_links", []), state.get("foundations", {})])
	if next_key != geometry_key:
		geometry_key = next_key
		_rebuild_machines()
	if int(state.revision) != visual_revision:
		visual_revision = int(state.revision)
		_redraw_items()
	if character_presenter != null:
		character_presenter.refresh()
	_refresh_ui()

func _display_parts() -> Dictionary:
	if state.get("options", {}).get("native", false):
		return state.get("part_kits", {}).get(client, {})
	return state.get("parts", {})

func _parts_are_shared() -> bool:
	return false

func _transmission_inspection(part: Dictionary, motion: Dictionary) -> String:
	var name := "Shaft"
	if part.kind == "gear":
		name = {2: "Small Cogwheel", 4: "Large Cogwheel"}.get(part.get("teeth"), "Cogwheel")
	var description := "%s · %s axis\nGrid %s" % [name, ["X", "Y", "Z"][part.axis], str(part.center)]
	if motion.get("state") == "rotating":
		description += "\nRate %d / %d" % [motion.numerator, motion.denominator]
	else:
		description += "\n" + str(motion.get("state", "disconnected")).capitalize()
	return description

func _refresh_ui() -> void:
	if stock_label == null:
		return
	_refresh_transmission()
	var inventory := int(state.inventories.get(client, 0))
	parts_label.text = "BUILD FROM SHARED KIT" if _parts_are_shared() else "BUILD FROM CARRIED PARTS"
	goal_label.text = "FIRST SHIFT\nBring back 4 plates\n%d / 4 collected" % inventory
	confirm_button.disabled = inventory < 4 or goal_confirmed or explanation_open
	confirm_button.text = "Objective confirmed" if goal_confirmed else "Confirm four plates"
	stock_label.text = "SEAM  %d blanks\nIN THE LINE  %d blanks\nPRESS OUTLET  %d plate" % [state.stock.source,
		state.stock.collector + state.stock.belt + state.stock.input + state.stock.held, state.stock.output]
	power_label.text = "DRIVE RUNNING" if state.get("powered", false) else "DRIVE SWITCHED OFF" if not state.get("power_enabled", true) else "DRIVE NEEDS CONNECTIONS"
	power_button.text = ("Stop drive  [%s]" if state.get("power_enabled", true) else "Start drive  [%s]") % _power_key()
	power_button.tooltip_text = "" if legacy_fixture else "Approach the waterwheel to operate the drive."
	power_button.disabled = explanation_open
	save_button.disabled = explanation_open or not save_slot_ready or startup_save_pending or (not legacy_fixture and not state.get("actors", {}).get(client, {}).get("ready", false))
	load_button.disabled = explanation_open or not save_slot_ready or (legacy_fixture and not save_slot_owned)
	load_button.text = "Load worksite  [F9]" if legacy_fixture else "How to reopen save  [F9]"
	for button in [save_button, load_button]:
		button.tooltip_text = "" if save_slot_ready else "Launch a fresh worksite session to enable saving."
	if actor_label != null:
		actor_label.visible = not legacy_fixture
		actor_label.text = "CHARACTER READY · BUILD NEARBY" if state.get("actors", {}).get(client, {}).get("ready", false) else "CHARACTER STARTING…"
	for tool in ["flow", "inspect"]:
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
		inspector.text = "%s\nSquare %s" % [NAMES.get(state.entities[selected].kind, selected), str(state.entities[selected].cell)]
		if state.entities[selected].kind == "processor":
			inspector.text += "\n%d in · %d held · %d ready" % [state.stock.input, state.stock.held, state.stock.output]
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
		var slots: Array = state.belt_spans[selected].get("slots", [])
		var occupied := 0
		for slot: Variant in slots:
			if slot is Dictionary:
				occupied += 1
		inspector.text = "Mechanical belt\n%d occupied positions\nRecover contents before dismantling." % occupied
	else:
		inspector.text = "Select a machine to inspect\nor collect its finished work."
	_refresh_guided_tools()
	if recovery_actions != null:
		recovery_actions.refresh()
	if loose_material_controls != null:
		loose_material_controls.refresh()

func _catalog_open() -> bool:
	return building_hotbar != null and building_hotbar.catalog.visible

func _toggle_details() -> void:
	if not explanation_open:
		show_details = not show_details
		_refresh_ui()

func _refresh_guided_tools(snapshot_ready: bool = true) -> void:
	if foundation_level_controls != null:
		foundation_level_controls.visible = _native_transmission() and mode in ["foundation", "wheel"] and not explanation_open and snapshot_ready
		foundation_area_toggle.visible = foundation_level_controls.visible and mode == "foundation"
		foundation_steps_toggle.visible = foundation_area_toggle.visible
		foundation_level_label.text = _construction_height_text()
		wheel_size_controls.visible = foundation_level_controls.visible and mode == "wheel"
	_refresh_placement_hint(snapshot_ready)
	footer_snapshot_ready = snapshot_ready
	_queue_footer_fit()
	if building_hotbar != null:
		building_hotbar.refresh(snapshot_ready)
	if legacy_fixture:
		return
	# This is a view of confirmed facts, not persistent progression or admission.
	var kinds: Dictionary = {}
	for entity in state.get("entities", {}).values():
		kinds[String(entity.kind)] = true
	var offered := {"collector": true}
	if not kinds.is_empty():
		offered.inspect = true
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
	var step := _guided_step(kinds)
	if state.get("options", {}).get("foundations", false):
		offered.foundation = true
	for tool in tool_buttons:
		var button: Button = tool_buttons[tool]
		# Keyboard selection stays visible even when it precedes the suggestion.
		button.visible = NAMES.has(tool) or tool in ["drive", "gear"] or offered.has(tool) or mode == tool
		if tool == "foundation" and not state.get("options", {}).get("foundations", false):
			button.visible = false
		if tool == "gear" and not _native_transmission():
			button.visible = false
		for color_name in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			if tool == step.tool:
				button.add_theme_color_override(color_name, Color("edcc8d"))
			else:
				button.remove_theme_color_override(color_name)
	var inventory := int(state.get("inventories", {}).get(client, 0))
	goal_label.text = "Make 4 plates\n%s\n%d / 4 collected" % [step.text, inventory] if snapshot_ready else "Connect to the worksite."
	confirm_button.visible = snapshot_ready and (inventory >= 4 or goal_confirmed)
	details_button.text = "Less detail" if show_details else "Details"
	details_button.disabled = explanation_open
	for control in [stock_label, power_label, save_button, load_button]:
		control.visible = show_details
	actor_label.visible = show_details or not state.get("actors", {}).get(client, {}).get("ready", false)
	power_button.visible = kinds.has("wheel")
	controls_label.text = "WASD walk · Space jump · Right-drag view · Wheel zoom · H help"
	_refresh_engineering(snapshot_ready)
	# Introduce inspection when it can help. Keep waiting notices and explicit
	# disclosure available even before the first machine has been built.
	# Foundations alone do not need the machine panel while building.
	var unused_inspector: bool = _native_transmission() and snapshot_ready and _can_choose_tool() \
		and kinds.is_empty() and state.get("transmission_parts", {}).is_empty() \
		and not show_details and mode != "inspect"
	var inspector_panel: Control = inspector.get_parent().get_parent()
	inspector_panel.visible = not unused_inspector

func _build_placement_hint() -> void:
	placement_hint = Node3D.new()
	placement_hint.name = "GuidedPlacementHint"
	placement_hint.visible = false
	add_child(placement_hint)
	for side in [-0.7, 0.7]:
		_box(placement_hint, Vector3(0, 0, side), Vector3(1.45, 0.035, 0.055), Color("edcc8d"))
		_box(placement_hint, Vector3(side, 0, 0), Vector3(0.055, 0.035, 1.45), Color("edcc8d"))
	placement_target_label = _text(placement_hint, "MINERAL SEAM", Vector3(0, 0.65, 0), Color("ffdb94"), 0.006)
	placement_target_label.name = "MineralSeamTarget"
	placement_target_label.visible = false

func _placement_hint_ready() -> bool:
	return _can_control_character()

func _guided_placement_cell() -> Array:
	if legacy_fixture or _catalog_open() or explanation_open or not _placement_hint_ready():
		return []
	if not mode in ["collector", "belt", "processor"] or int(_display_parts().get(mode, 0)) < 1:
		return []
	# A suggestion for this starter path only, never a placement/reach decision.
	if mode == "collector":
		if not _native_transmission() or not state.get("entities", {}).is_empty() \
				or not state.get("transmission_parts", {}).is_empty() or int(state.get("stock", {}).get("source", 0)) < 1 \
				or _guided_step({}).tool != "collector":
			return []
		return [0, 1]
	var upstream_kind := "collector" if mode == "belt" else "belt"
	var upstream: Array = []
	var kinds: Dictionary = {}
	for entity in state.get("entities", {}).values():
		kinds[String(entity.kind)] = true
		if entity.kind == upstream_kind:
			if not upstream.is_empty():
				return []
			upstream = entity.cell
	if upstream.is_empty() or _guided_step(kinds).tool != mode:
		return []
	var cell := [int(upstream[0]) + 1, int(upstream[1])]
	if not _build_cell_allowed(Vector2i(cell[0], cell[1])):
		return []
	if not _entity_at_cell(Vector2i(cell[0], cell[1])).is_empty():
		return []
	return cell

func _refresh_placement_hint(snapshot_ready: bool = true) -> void:
	if placement_hint == null:
		return
	placement_target_label.visible = false
	if transmission_controls != null and not transmission_controls.active_tool.is_empty():
		placement_hint.visible = false
		return
	var cell: Array = _guided_placement_cell() if snapshot_ready else []
	placement_hint.visible = not cell.is_empty()
	if placement_hint.visible:
		placement_hint.position = _cell_position(cell) + Vector3(0, 0.055, 0)
		if mode == "collector":
			var ground: float = ProductionEnvironment.Surface.height_at(placement_hint.position.x, placement_hint.position.z)
			if not is_finite(ground):
				placement_hint.visible = false
				return
			placement_hint.position.y += ground
			placement_target_label.visible = true

func _preview_pointer_clear() -> bool:
	# This query does not consume input or move the pointer. The live preview
	# follows the current camera ray, including when the view moves under it.
	return is_inside_tree() and get_viewport().gui_get_hovered_control() == null

func _machine_preview_cell() -> Vector2i:
	return _screen_cell(get_viewport().get_mouse_position())

func _preview_axis() -> int:
	if not _native_transmission() or transmission_controls == null:
		return 0
	return ["x", "y", "z"].find(transmission_controls.selected_axis)

func _refresh_machine_preview() -> void:
	if machine_preview != null:
		machine_preview.visible = false
	if legacy_fixture or explanation_open or not _placement_hint_ready() or not _preview_pointer_clear():
		return
	if not NAMES.has(mode) or int(_display_parts().get(mode, 0)) < 1:
		return
	if transmission_controls != null and not transmission_controls.active_tool.is_empty():
		return
	var cell := _machine_preview_cell()
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
	var key := "%s:%d:%s:%d" % [mode, axis, str(_native_transmission()), wheel_tiles if mode == "wheel" else 0]
	if machine_preview == null:
		machine_preview = Node3D.new()
		machine_preview.name = "MachinePlacementPreview"
		add_child(machine_preview)
	if key != machine_preview_key:
		for child in machine_preview.get_children():
			child.free()
		# The placed wheel's observed animation target must not be replaced by
		# the visual-only assembly. Preview construction changes no projection.
		var placed_rotor := wheel_rotor
		if mode == "foundation":
			_assemble_foundation(machine_preview)
		else:
			_assemble_machine(machine_preview, {"kind": mode, "axis": axis, "tiles": wheel_tiles}, mode == "belt" and axis == 0)
		wheel_rotor = placed_rotor
		if machine_preview_material == null:
			machine_preview_material = StandardMaterial3D.new()
			machine_preview_material.albedo_color = Color(0.88, 0.75, 0.49, 0.32)
			machine_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			machine_preview_material.roughness = 0.75
			machine_preview_material.metallic = 0.0
		_style_machine_preview(machine_preview)
		machine_preview_key = key
	machine_preview.position = _cell_position([cell.x, cell.y]) + Vector3.UP * _construction_level(cell) * Geometry.HEIGHT_STEP
	machine_preview.scale = Vector3.ONE
	if mode == "foundation":
		machine_preview.scale = Vector3(area_size.x, 1, area_size.y)
		machine_preview.position.x = (area_origin.x + (area_size.x - 1) / 2.0) * PITCH
		machine_preview.position.z = (area_origin.y + (area_size.y - 1) / 2.0) * PITCH
	machine_preview.visible = true

func _style_machine_preview(node: Node) -> void:
	# Per-instance overrides leave shared placed materials and meshes intact.
	# Neutral amber is a form/footprint preview, never an admission verdict.
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
		return {"text": "Plate ready. Select the press, then collect [R].", "tool": "inspect"}
	if not kinds.has("collector"):
		return {"text": "Place a collector at the exposed mineral seam." if _native_transmission() else "Place a collector on the brass strip near you.", "tool": "collector"}
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
	if not state.get("power_enabled", true):
		return {"text": "Switch on the drive near the wheel [P].", "tool": "inspect"}
	if _native_transmission():
		var motion: Dictionary = state.get("motion", {})
		for id in state.get("entities", {}):
			var part: Dictionary = state.entities[id]
			if part.get("kind", "") in ["collector", "belt", "processor"] and motion.get(id, {}).get("state", "") != "rotating":
				return {"text": "Use cogs and shafts to bring rotation to each machine. The belt shaft crosses its direction of travel.", "tool": "drive"}
			if part.get("kind", "") == "belt" and motion.get(id, {}).get("state", "") == "rotating" and int(motion.get(id, {}).get("numerator", 0)) > 0:
				return {"text": "The belt is carrying blanks away from the press. Change the cog route to reverse its rotation; pick up loose blanks from the worksite menu.", "tool": "drive"}
		if span_route.physical and not span_route.powered and not legacy_route:
			return {"text": "Power the belt shafts, check their direction toward the press, and check branches for diverted blanks.", "tool": "drive"}
	elif not state.get("powered", false):
		return {"text": "Bring power to the line. Help [H] shows the current setup.", "tool": "drive"}
	var stock: Dictionary = state.get("stock", {})
	if _native_transmission() and not span_route.cargo and state.get("dropped_material", []).any(func(drop: Variant): return drop is Dictionary and int(drop.get("raw", 0)) > 0) and int(stock.get("source", 0)) + int(stock.get("collector", 0)) + int(stock.get("belt", 0)) + int(stock.get("input", 0)) + int(stock.get("held", 0)) == 0:
		return {"text": "Pick up loose blanks from the worksite menu, then insert them into the press.", "tool": "inspect"}
	if not span_route.cargo and int(stock.get("source", 0)) + int(stock.get("collector", 0)) + int(stock.get("belt", 0)) + int(stock.get("input", 0)) + int(stock.get("held", 0)) == 0:
		if _native_transmission():
			var cargo: Dictionary = state.get("cargo", {}).get(client, {})
			if not cargo.get("work_lots", []).is_empty():
				return {"text": "Select the press to insert a carried workpiece.", "tool": "inspect"}
			if int(cargo.get("raw", 0)) > 0:
				return {"text": "Select the press to insert a carried blank.", "tool": "inspect"}
		return {"text": "No blanks remain here. Open Build to try another layout.", "tool": "inspect"}
	return {"text": "Follow a blank to the press. Select a machine to inspect it.", "tool": "inspect"}

func _inspection_hint() -> String:
	# Describe confirmed projection facts only. This is advice, never admission
	# or a second power solver; the authority still decides every command.
	var kind: String = state.entities[selected].kind
	var stop_before_link: bool = state.get("powered", false) and not state.get("options", {}).get("native", false)
	var rotating: bool = state.get("powered", false)
	if _native_transmission():
		rotating = state.get("motion", {}).get(selected, {}).get("state", "") == "rotating"
	if kind == "processor" and state.stock.output > 0:
		return "Outlet full; plate ready.\n[R] collect to make room."
	if not state.get("power_enabled", true):
		return "Drive switched off.\n[%s] enables the drive%s." % [_power_key(), "" if legacy_fixture else " near wheel"]
	if kind == "processor" and state.stock.held > 0 and rotating:
		if state.remaining == 0:
			return "Work done; blank retained.\nNext drive tick releases plate."
		return "Working: %d ticks remaining.\nHeld blank stays in the press." % state.remaining
	if kind in ["belt", "processor"] and not _has_material_connection(true):
		return (("Inlet missing. Stop [%s].\n" % _power_key()) if stop_before_link else "No material inlet linked.\n") + "[F] link " + ("Collector → Belt." if kind == "belt" else "Belt → Press.")
	if kind in ["collector", "belt"] and not _has_material_connection(false):
		return (("Outlet missing. Stop [%s].\n" % _power_key()) if stop_before_link else "No material outlet linked.\n") + "[F] link " + ("Collector → Belt." if kind == "collector" else "Belt → Press.")
	if not rotating:
		if _native_transmission():
			if kind == "wheel":
				return "Wheel is not rotating. Check its axle and the stream."
			return "Bring rotation to the line.\n[G] shafts; mesh cogwheels."
		return "Drive needs connections.\n[G] link wheel + all machines."
	if kind == "processor":
		if state.stock.input > 0:
			return "Blank ready to press.\nNext drive tick starts work."
		return "Waiting for a blank.\nInspect the Belt upstream."
	if kind == "collector":
		if state.stock.source == 0:
			return "Seam depleted.\nNo blanks remain to collect."
		if state.stock.collector > 0:
			return "Collector outlet occupied.\nInspect the Belt downstream."
		return "Collecting finite seam blanks.\nBelt takes the next blank."
	if kind == "belt":
		return "Belt carrying a blank.\nInspect the Press downstream." if state.stock.belt > 0 else "Waiting for a blank.\nInspect the Collector upstream."
	return "Wheel rotates.\n[%s] stops it%s." % [_power_key(), " for editing" if legacy_fixture else " from nearby"]

func _has_material_connection(incoming: bool) -> bool:
	for pair in state.links:
		if pair[1 if incoming else 0] == selected:
			return true
	return false

func _refresh_machine_captions() -> void:
	if not _native_transmission() or machine_root == null:
		return
	var pointed := ""
	if not explanation_open and not show_details and _preview_pointer_clear():
		pointed = _screen_entity(get_viewport().get_mouse_position())
	for anchor in machine_root.get_children():
		var caption := anchor.get_node_or_null("MachineCaption") as Label3D
		if caption == null:
			continue
		var entity_id: String = anchor.get_meta("machine_entity", "")
		caption.visible = not explanation_open and (show_details or entity_id == selected \
			or entity_id == pending_link or entity_id == pointed)

func _update_cursor() -> void:
	_refresh_machine_preview()
	_refresh_machine_captions()
	if _native_transmission() and transmission_controls != null and not transmission_controls.active_tool.is_empty():
		hover.visible = false
		if transmission_controls.active_tool in ["gear", "place_shaft"] and not explanation_open and _can_control_character():
			_set_transmission_hover(_transmission_center(get_viewport().get_mouse_position()))
		return
	hover.basis = Basis.IDENTITY
	hover.visible = NAMES.has(mode) and _build_cell_allowed(hover_cell) and _machine_floor_aligned(hover_cell) \
		and (mode == "foundation" or _entity_at_cell(hover_cell).is_empty()) and not explanation_open
	if hover.visible:
		hover.position = _cell_position([hover_cell.x, hover_cell.y]) + Vector3(0, 0.03 + _construction_level(hover_cell) * Geometry.HEIGHT_STEP, 0)

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

func _fit_guided_footer() -> void:
	footer_fit_pending = false
	# Wrapped text settles after its container width. Fit again at that
	# boundary, rather than retaining an early oversized minimum height.
	for column in [build_column, inspector.get_parent() if inspector != null else null]:
		if column != null:
			var panel: Control = column.get_parent()
			var height: float = panel.get_combined_minimum_size().y
			if not is_equal_approx(panel.size.y, height):
				panel.size.y = height
	# Only the ordinary fresh introduction duplicates the visible goal and
	# source annotation. Explicit outcomes and unavailable-state advice stay.
	var redundant_intro: bool = _native_transmission() and footer_snapshot_ready and _placement_hint_ready() and not status_refused \
		and not show_details and not _catalog_open() and mode == "collector" \
		and state.get("entities", {}).is_empty() and state.get("transmission_parts", {}).is_empty() \
		and _guided_step({}).tool == "collector" \
		and status_label.text == "WASD walks. Approach the mineral seam to place your collector."
	status_label.visible = not redundant_intro
	var right: float = -308.0 if inspector.get_parent().get_parent().visible else -18.0
	if not is_equal_approx(status_footer.offset_right, right):
		status_footer.set_anchor_and_offset(SIDE_RIGHT, 1.0, right)
	var left_anchor := 1.0 if redundant_intro else 0.0
	var left_offset: float = right - status_footer.get_combined_minimum_size().x if redundant_intro else 310.0
	if not is_equal_approx(status_footer.anchor_left, left_anchor) or not is_equal_approx(status_footer.offset_left, left_offset):
		status_footer.set_anchor_and_offset(SIDE_LEFT, left_anchor, left_offset)
	var bottom: float = -30.0 - building_hotbar.size.y
	if not is_equal_approx(status_footer.offset_bottom, bottom):
		status_footer.set_anchor_and_offset(SIDE_BOTTOM, 1.0, bottom)
	var top: float = bottom - status_footer.get_combined_minimum_size().y
	if not is_equal_approx(status_footer.offset_top, top):
		status_footer.set_anchor_and_offset(SIDE_TOP, 1.0, top)
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

func _panel(parent: Node, at: Vector2, dimensions: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = at
	panel.size = dimensions
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.078, 0.129, 0.157, 0.96)
	style.border_color = Color("41565e")
	style.set_corner_radius_all(5)
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

func _build_interface() -> void:
	# A revisable opening adapter limit, not a fixed window or a game-world rule.
	get_window().min_size = Vector2i(1280, 800)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = ProductionInterface.make_theme()
	var build := _panel(root, Vector2(18, 18), Vector2(275, 620 if legacy_fixture else 0))
	build_column = build
	if not legacy_fixture:
		build.add_theme_constant_override("separation", 6)
	_label(build, "FACTORY / FIRST SHIFT", 20, Color("edcc8d"))
	var tagline := _label(build, "A small line. Real materials.", 14, Color("9eb4b2"))
	tagline.visible = legacy_fixture
	build.add_child(HSeparator.new())
	goal_label = _label(build, "", 18)
	if not legacy_fixture:
		goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_button = _button(build, "Confirm four plates", _confirm_goal)
	build.add_child(HSeparator.new())
	building_hotbar = BuildingHotbar.new()
	building_hotbar.configure(self, root)
	tool_buttons.merge(building_hotbar.catalog_buttons)
	parts_label = building_hotbar.parts_label
	catalog_button = building_hotbar.catalog_button
	foundation_level_controls = HBoxContainer.new()
	build.add_child(foundation_level_controls)
	_button(foundation_level_controls, "−", _adjust_foundation_level.bind(-1))
	foundation_level_label = _label(foundation_level_controls, _construction_height_text(), 14)
	_button(foundation_level_controls, "+", _adjust_foundation_level.bind(1))
	foundation_level_controls.visible = false
	foundation_steps_toggle = CheckButton.new()
	foundation_steps_toggle.text = "Access steps"
	foundation_steps_toggle.tooltip_text = "Use one height unit for walking steps. Normal height changes move one foundation thickness. Machines need whole-tile factory floors; turning this off snaps the selected height to one."
	foundation_steps_toggle.toggled.connect(_set_foundation_steps)
	build.add_child(foundation_steps_toggle)
	foundation_steps_toggle.visible = false
	wheel_size_controls = HBoxContainer.new()
	build.add_child(wheel_size_controls)
	_button(wheel_size_controls, "−", _adjust_wheel_size.bind(-1))
	wheel_size_label = _label(wheel_size_controls, "Wheel diameter: 3 squares", 14)
	_button(wheel_size_controls, "+", _adjust_wheel_size.bind(1))
	wheel_size_controls.visible = false
	foundation_area_toggle = CheckButton.new()
	foundation_area_toggle.text = "Area (two corners)"
	foundation_area_toggle.toggled.connect(func(enabled: bool) -> void:
		foundation_area_mode = enabled
		foundation_area_started = false)
	build.add_child(foundation_area_toggle)
	foundation_area_toggle.visible = false
	var selection_tools := HBoxContainer.new()
	build.add_child(selection_tools)
	tool_buttons.flow = _button(selection_tools, "Link [F]", _select_tool.bind("flow"))
	tool_buttons.inspect = _button(selection_tools, "Inspect [I]", _select_tool.bind("inspect"))
	for tool in ["flow", "inspect"]:
		tool_buttons[tool].toggle_mode = true
	var view_options := HBoxContainer.new()
	build.add_child(view_options)
	view_options.visible = not legacy_fixture
	details_button = _button(view_options, "Details", _toggle_details)
	details_button.tooltip_text = "Show worksite counters and save options."
	_button(build, "How this line works  [H]", _toggle_explanation)
	var right := _panel(root, Vector2(990, 18), Vector2(272, 490 if legacy_fixture else 0))
	var right_panel: Control = right.get_parent()
	# Set the far anchor first so the near anchor is not clamped.
	right_panel.set_anchor_and_offset(SIDE_RIGHT, 1.0, -18)
	right_panel.set_anchor_and_offset(SIDE_LEFT, 1.0, -290)
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if legacy_fixture:
		_label(right, "WORKSITE", 13, Color("a3b8b4"))
	else:
		# The actor/connection rows identify the physical worksite. Leave room
		# for a selected press and pending-server advice above the status panel.
		right.add_theme_constant_override("separation", 6)
	actor_label = _label(right, "", 11, Color("a3b8b4"))
	actor_label.visible = not legacy_fixture
	power_label = _label(right, "", 14, Color("dfbc76"))
	stock_label = _label(right, "", 16)
	inspector = _label(right, "", 15)
	inspector.custom_minimum_size.x = 238
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	retrieve_button = _button(right, "Collect plate  [R]", _retrieve)
	power_button = _button(right, "Stop drive  [Space]", _toggle_power)
	remove_button = _button(right, "Dismantle selected", _remove_selected)
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
	right.add_child(HSeparator.new())
	save_button = _button(right, "Save worksite  [F5]", _save_worksite)
	load_button = _button(right, "Load worksite  [F9]", _load_worksite)
	var bottom := _panel(root, Vector2(310, 694), Vector2(952, 88))
	var bottom_panel: Control = bottom.get_parent()
	status_footer = bottom_panel
	bottom_panel.set_anchor_and_offset(SIDE_RIGHT, 1.0, -18)
	bottom_panel.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -128)
	bottom_panel.set_anchor_and_offset(SIDE_TOP, 1.0, -216)
	bottom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status_label = _label(bottom, "", 16)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label = _label(bottom, "1–8 hotbar · B build · F material · G shaft · I inspect · H help", 12, Color("9eb4b2"))
	bottom_panel.minimum_size_changed.connect(_queue_footer_fit)
	bottom_panel.resized.connect(_queue_footer_fit)
	for column: Control in [build, right]:
		column.minimum_size_changed.connect(_queue_footer_fit)
	var lesson_column := _panel(root, Vector2(346, 18), Vector2(600, 192))
	lesson_panel = lesson_column.get_parent()
	lesson_panel.set_anchor_and_offset(SIDE_RIGHT, 0.5, 306)
	lesson_panel.set_anchor_and_offset(SIDE_LEFT, 0.5, -294)
	lesson_title = _label(lesson_column, "", 17, Color("edcc8d"))
	lesson_body = _label(lesson_column, "", 16)
	lesson_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	lesson_column.add_child(row)
	lesson_previous = _button(row, "Previous", func(): _set_lesson(lesson_index - 1))
	lesson_next = _button(row, "Next", func(): _set_lesson(lesson_index + 1))
	lesson_return = _button(row, "Return to building  [H]", _toggle_explanation)
	lesson_panel.visible = false
