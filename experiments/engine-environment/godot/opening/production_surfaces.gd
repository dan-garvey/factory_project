extends RefCounted
## Render resources only; no scene controller or simulation authority.

class ProductionVisuals:
	extends RefCounted
	## Shared mesh and image primitives for the production presenters.

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
		if image == null:
			return null
		# Some imported textures return their cached Image. Preparation must not
		# resize or decompress the resource that later consumers will read.
		image = image.duplicate() as Image
		if image.is_compressed() and image.decompress() != OK:
			return null
		return image

	static func read_image_set(directory: String, files: Dictionary, sizes: Dictionary,
			incomplete_reason: String) -> Dictionary:
		var present := 0
		for file_name in files.values():
			if image_exists(directory.path_join(file_name)):
				present += 1
		if present == 0:
			return {"status": "missing", "images": {}}
		if present != files.size():
			return {"status": "invalid", "reason": incomplete_reason, "images": {}}
		var images: Dictionary = {}
		for role in files:
			var image := read_image(directory.path_join(files[role]))
			if image == null or image.is_empty() or image.get_size() != sizes[role]:
				return {"status": "invalid", "reason": "invalid_" + role, "images": {}}
			images[role] = image
		return {"status": "ready", "images": images}

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
		var sizes := {}
		for role in FILES:
			var extent := 512 if role.begins_with("cast") else 256
			sizes[role] = Vector2i(extent, extent)
		return ProductionVisuals.read_image_set(directory, FILES, sizes, "incomplete_surface_set")

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

class ProductionSteelFloor:
	extends RefCounted
	## Image/material presentation only. No geometry or physical displacement.
	const ROOT := "res://opening/assets/steel"
	const FILES := {"albedo": "steel_albedo.webp", "arm": "steel_arm.webp", "normal": "steel_normal_gl.webp"}
	static var finish: StandardMaterial3D
	static var source_status := "uninitialized"

	static func read_images(directory: String = ROOT, files: Dictionary = FILES, normal_size: Vector2i = Vector2i(1024, 1024), arm_size: Vector2i = Vector2i(512, 512)) -> Dictionary:
		var sizes := {}
		for role in files:
			sizes[role] = arm_size if role == "arm" else (normal_size if role == "normal" else Vector2i(1024, 1024))
		return ProductionVisuals.read_image_set(directory, files, sizes, "incomplete_material_set")

	static func material() -> StandardMaterial3D:
		if source_status != "uninitialized":
			return finish
		var loaded := read_images()
		source_status = loaded.status
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

class ProductionCoating:
	extends RefCounted
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

	static func material(color: Color) -> StandardMaterial3D:
		if coatings.has(color):
			return coatings[color]
		var source := ProductionTransmissionFinish.material("cast", color, 0.0, 0.72)
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

class ProductionMeshAssembly:
	extends RefCounted
	static func append_surface(target: ArrayMesh, role: String, pieces: Array) -> void:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for piece: Array in pieces:
			surface.append_from(piece[0], 0, piece[1])
		surface.commit(target)
		target.surface_set_name(target.get_surface_count() - 1, role)

	static func append_hardware(target: ArrayMesh, poses: Array[Transform3D],
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
		append_surface(target, "MountingHardware", pieces)
