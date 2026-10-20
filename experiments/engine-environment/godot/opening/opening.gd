extends Node3D
## Input and presentation only. Every material/build mutation goes to model.gd.

const Model = preload("res://model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
const ActorWorld = preload("res://opening/actor_world.gd")
const CharacterPresenter = preload("res://opening/character_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")
class ProductionVisuals:
	extends RefCounted
	## Presentation is self-contained in this already captured opening script.

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

	static func fastener_head_mesh() -> CylinderMesh:
		if not meshes.has("fastener/hex"):
			var head := CylinderMesh.new()
			head.top_radius = 0.035
			head.bottom_radius = 0.035
			head.height = 0.024
			head.radial_segments = 6
			meshes["fastener/hex"] = head
		return meshes["fastener/hex"]

class ProductionSteelFloor:
	extends RefCounted
	## Image/material presentation only. No geometry or physical displacement.
	const ROOT := "res://opening/assets/steel"
	const FILES := {"albedo": "steel_albedo.webp", "arm": "steel_arm.webp", "normal": "steel_normal_gl.webp"}
	static var finish: StandardMaterial3D
	static var source_status := "uninitialized"

	static func read_images(directory: String = ROOT) -> Dictionary:
		var present := 0
		for name_value in FILES.values():
			if FileAccess.file_exists(directory.path_join(name_value)):
				present += 1
		if present == 0:
			return {"status": "missing", "images": {}}
		if present != FILES.size():
			return {"status": "invalid", "reason": "incomplete_material_set", "images": {}}
		var images: Dictionary = {}
		for role in FILES:
			var image := Image.load_from_file(directory.path_join(FILES[role]))
			var expected := Vector2i(512, 512) if role == "arm" else Vector2i(1024, 1024)
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

class ProductionEnvironment:
	extends RefCounted
	## Visual scenery only. ActorWorld owns collision from the same immutable site geometry.
	static var Surface = load("res://opening/site_surface.gd") if ResourceLoader.exists("res://opening/site_surface.gd", "Script") else null
	static var ground_finish: StandardMaterial3D
	static var water_finish: StandardMaterial3D
	static var foam_finish: StandardMaterial3D
	static var stone_finish: StandardMaterial3D
	static var timber_finish: StandardMaterial3D
	static var iron_finish: StandardMaterial3D
	static var sky_finish: PanoramaSkyMaterial
	static var terrain_surface_mesh: ArrayMesh
	static var stream_volume_mesh: ArrayMesh
	static var foliage_cluster_mesh: ArrayMesh
	static var rock_boulder_mesh: ArrayMesh

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
			ramp.colors = PackedColorArray([Color("4c5344"), Color("787b64"), Color("b2aa90")])
			texture.color_ramp = ramp
		return texture

	static func ground_material() -> StandardMaterial3D:
		if ground_finish == null:
			ground_finish = StandardMaterial3D.new()
			ground_finish.albedo_texture = _noise_texture(3471, false)
			ground_finish.vertex_color_use_as_albedo = true
			ground_finish.roughness = 0.94
			ground_finish.normal_enabled = true
			ground_finish.normal_texture = _noise_texture(3471, true)
			ground_finish.normal_scale = 0.32
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
			water_finish.albedo_color = Color("245866")
			water_finish.vertex_color_use_as_albedo = true
			water_finish.metallic = 0.0
			water_finish.roughness = 0.16
			water_finish.normal_enabled = true
			water_finish.normal_texture = ImageTexture.create_from_image(image)
			water_finish.normal_scale = 0.42
			water_finish.uv1_scale = Vector3(2, 8, 1)
			water_finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return water_finish

	static func animate_water(seconds: float) -> bool:
		# The existing mesh UV grows downstream. A negative texture offset
		# moves the repeated ripple pattern downstream at a cosmetic 0.4 m/s.
		# Absolute time makes shared material updates idempotent across views.
		# It is never a production clock or an estimate of waterwheel speed.
		if water_finish == null or not is_finite(seconds) or seconds < 0.0:
			return false
		water_finish.uv1_offset = Vector3(0.0, -fposmod(seconds * 0.256, 1.0), 0.0)
		return true

	static func foam_material() -> StandardMaterial3D:
		if foam_finish == null:
			foam_finish = ProductionVisuals.material(Color("bdd6d8"), 0.04, 0.55)
		return foam_finish

	static func stone_material() -> StandardMaterial3D:
		if stone_finish == null:
			stone_finish = ProductionVisuals.material(Color("5c635c"), 0.05, 0.88)
		return stone_finish

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
		return base.lerp(Color("2c3638"), gorge)

	static func terrain_mesh() -> ArrayMesh:
		if terrain_surface_mesh != null:
			return terrain_surface_mesh
		var subdivisions: int = Surface.SUBDIVISIONS
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
		var rc := river_center_x(z_world)
		var across := x_world - rc
		var upstream_slope := maxf(0.0, (-5.55 - z_world) * 0.0022)
		var sluice_drop := 0.25 * smoothstep(-5.65, -4.25, z_world)
		var race_grade := 0.045 * smoothstep(-4.25, 8.35, z_world)
		var weir_step_a := 0.24 * smoothstep(8.35, 9.05, z_world)
		var weir_step_b := 0.24 * smoothstep(9.15, 9.85, z_world)
		var tail_grade := 0.16 * smoothstep(9.85, 61.0, z_world)
		var base := 0.13 + upstream_slope - sluice_drop - race_grade - weir_step_a - weir_step_b - tail_grade
		var wave := 0.018 * sin(z_world * 2.6 + across * 4.2) + 0.011 * cos(z_world * 4.8 - across * 3.4)
		var crown := -0.016 * clampf(across * across, 0.0, 1.5)
		return base + wave + crown

	static func stream_mesh() -> ArrayMesh:
		if stream_volume_mesh != null:
			return stream_volume_mesh
		var rows := 88
		var cols := 8
		var z_start := -58.0
		var z_end := 61.0
		var stride := cols + 1
		var positions: Array[Vector3] = []
		var normals: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		var colors: Array[Color] = []
		for r in range(rows + 1):
			var tz := float(r) / float(rows)
			var z_world := lerpf(z_start, z_end, tz)
			var z_local := z_world - 1.65
			var rc_local := river_center_x(z_world) - (-2.7)
			var half_w := lerpf(0.56, 1.62, smoothstep(5.5, 22.0, absf(z_world - 1.65)))
			for c in range(stride):
				var x_local := rc_local
				var y := 0.0
				var normal := Vector3.UP
				var color := Color.WHITE
				if c == 0:
					x_local = rc_local - half_w - 0.06
					y = stream_surface_height(-2.7 + rc_local - half_w, z_world) - 0.34
					normal = Vector3(-0.86, 0.51, 0.0).normalized()
					color = Color("183842")
				elif c == cols:
					x_local = rc_local + half_w + 0.06
					y = stream_surface_height(-2.7 + rc_local + half_w, z_world) - 0.34
					normal = Vector3(0.86, 0.51, 0.0).normalized()
					color = Color("183842")
				else:
					var tc := float(c - 1) / float(cols - 2) * 2.0 - 1.0
					x_local = rc_local + tc * half_w
					var x_world := -2.7 + x_local
					y = stream_surface_height(x_world, z_world)
					var dz := 0.25
					var dy_dz := stream_surface_height(x_world, z_world + dz) - stream_surface_height(x_world, z_world - dz)
					var dy_dx := stream_surface_height(x_world + 0.12, z_world) - stream_surface_height(x_world - 0.12, z_world)
					normal = Vector3(-dy_dx / 0.24, 1.0, -dy_dz / (2.0 * dz)).normalized()
					var rapid := smoothstep(-5.6, -4.4, z_world) * (1.0 - smoothstep(-4.4, -2.8, z_world))
					rapid = maxf(rapid, smoothstep(8.2, 9.2, z_world) * (1.0 - smoothstep(9.2, 11.2, z_world)))
					var edge_foam := smoothstep(0.65, 1.0, absf(tc)) * 0.28
					color = Color("235361").lerp(Color("8ec2c7"), clampf(rapid * 0.65 + edge_foam, 0.0, 1.0))
				var x_world_uv := -2.7 + x_local
				positions.append(Vector3(x_local, y, z_local))
				normals.append(normal)
				uvs.append(Vector2((x_world_uv + 16.0) * 0.22, (z_world - z_start) * 0.08))
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
						surface.set_color(colors[idx])
						surface.add_vertex(positions[idx])
		surface.generate_tangents()
		stream_volume_mesh = surface.commit()
		return stream_volume_mesh

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
		for group in ["HeadraceSluice", "TailraceWeir"]:
			var node := Node3D.new()
			node.name = group
			node.position = Surface.group_origin(group)
			arch.add_child(node)
			groups[group] = node
		var finishes := {"stone": stone_material(), "dark_stone": ProductionVisuals.material(Color("38403e"), 0.06, 0.92),
			"timber": timber_material(), "iron": iron_material(), "foam": foam_material()}
		for spec in Surface.architecture_boxes():
			var part := _scenery_box(groups[spec.group], spec.label,
				spec.center - Surface.group_origin(spec.group), spec.size, finishes[spec.finish])
			part.basis = spec.basis
			if spec.solid:
				part.set_meta("site_solid_id", spec.id)
		var headrace: Node3D = groups.HeadraceSluice
		var iron := iron_material()
		var brass := ProductionVisuals.material(Color("b69252"), 0.72, 0.38)
		var stem_profile := PackedVector2Array([
			Vector2(0.0, -0.58), Vector2(0.038, -0.58), Vector2(0.038, 0.58), Vector2(0.0, 0.58)])
		_scenery_turned(headrace, "SluiceLiftStem", Vector3(0.0, 1.32, 0.0), stem_profile, brass)
		var wheel_profile := PackedVector2Array([
			Vector2(0.0, -0.03), Vector2(0.24, -0.03), Vector2(0.26, -0.015),
			Vector2(0.26, 0.015), Vector2(0.24, 0.03), Vector2(0.0, 0.03)])
		_scenery_turned(headrace, "SluiceHandwheel", Vector3(0.0, 1.72, 0.0), wheel_profile, iron)
		return arch

	static func _foliage() -> MultiMeshInstance3D:
		if foliage_cluster_mesh == null:
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
		var finish := StandardMaterial3D.new()
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
			if absf(px - river_center_x(pz)) < channel_half_width(pz) + 1.1:
				px += 2.4 if px >= river_center_x(pz) else -2.4
			var py: float = Surface.height_at(px, pz)
			var position := Vector3(px, py, pz)
			var scale := 0.85 + float(posmod(n * 7, 13)) * 0.08
			var basis := Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale)
			var color := Color("4b643e").lerp(Color("8f8b62"), float(n % 5) / 4.0)
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

	static func _rock_outcrops() -> MultiMeshInstance3D:
		if rock_boulder_mesh == null:
			rock_boulder_mesh = ProductionVisuals.box_mesh(Vector3(1.35, 0.88, 1.12))
		var finish := StandardMaterial3D.new()
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
			var basis: Basis = spec.basis.scaled(spec.scale)
			var color: Color = spec.color
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
	static var streams: Dictionary = {}
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
			"place_gear", "connect_drive", "connect":
				return "coupling"
			"remove", "disconnect_drive", "disconnect":
				return "release"
		return ""

	static func make_stream(cue: String) -> AudioStreamWAV:
		if streams.has(cue):
			return streams[cue]
		if cue not in ["belt_snap", "assembly", "coupling", "release"]:
			return null
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
		heard[key] = true
		stream = make_stream(cue)
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
const NAMES := {"collector": "Collector", "belt": "Belt", "processor": "Press", "wheel": "Waterwheel"}
const COLORS := {"collector": Color("d6a34d"), "belt": Color("538e88"), "processor": Color("bd7054"), "wheel": Color("8b9caa")}
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
var distance := 18.5
var focus := Vector3(1.3, 0.0, 1.1)
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
var machine_preview: Node3D
var machine_preview_key := ""
var machine_preview_material: StandardMaterial3D
var wheel_rotor: Node3D
var machine_body_context := ""
var machine_press_poses: Dictionary = {}
var status_label: Label
var stock_label: Label
var parts_label: Label
var goal_label: Label
var power_label: Label
var inspector: Label
var recovery_actions
var transmission_controls
var transmission_presenter
var transmission_endpoint_cue
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
var state: Dictionary = {}
var show_all_tools := false
var show_details := false
var all_tools_button: Button
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
	return not legacy_fixture and not explanation_open and not startup_save_pending and state.get("actors", {}).get(client, {}).get("ready", false)

func _native_transmission() -> bool:
	return not legacy_fixture and state.get("options", {}).get("native", false)

func _can_present_confirmed_motion() -> bool:
	return _native_transmission() and not explanation_open and not startup_save_pending and state.get("actors", {}).get(client, {}).get("ready", false)

func _contains_target(snapshot: Dictionary, id: String) -> bool:
	return snapshot.get("entities", {}).has(id) or (snapshot.get("options", {}).get("native", false)
		and snapshot.get("transmission_parts", {}).has(id))

func _refresh_transmission() -> void:
	if not _native_transmission():
		if transmission_controls != null:
			if not transmission_controls.active_tool.is_empty():
				transmission_controls.cancel()
				mode = "inspect"
			transmission_controls.refresh()
		if transmission_presenter != null:
			transmission_presenter.refresh()
		_refresh_endpoint_cue()
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
		var column: Node = tool_buttons.drive.get_parent()
		column.add_child(transmission_controls)
		column.move_child(transmission_controls, tool_buttons.inspect.get_index() + 1)
		transmission_controls.configure(self)
		transmission_presenter = load(presenter_path).new()
		add_child(transmission_presenter)
		transmission_presenter.configure(self)
	transmission_controls.refresh()
	transmission_presenter.refresh()
	_refresh_endpoint_cue()
	var active: bool = not transmission_controls.active_tool.is_empty()
	transmission_controls.visible = active or show_all_tools or goal_confirmed or int(state.get("inventories", {}).get(client, 0)) > 0 or not state.get("transmission_parts", {}).is_empty()
	if not active and mode in ["gear", "drive"]:
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
	var height: int = transmission_controls.gear_height
	var plane := Plane(Vector3.UP, Geometry.ANCHOR_HEIGHT + height * PITCH / 4.0)
	var point: Variant = plane.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null:
		return []
	return [roundi(point.x * 4.0 / PITCH), height, roundi(point.z * 4.0 / PITCH)]

func _refresh_endpoint_cue() -> void:
	var endpoint: Dictionary = transmission_controls.pending_endpoint() if _native_transmission() and transmission_controls != null else {}
	if endpoint.is_empty():
		if transmission_endpoint_cue != null:
			transmission_endpoint_cue.refresh({})
		return
	if transmission_endpoint_cue == null:
		# Native captures include this helper; historical fixed rosters need none.
		var path := "res://opening/native_transmission_endpoint_cue.gd"
		if not ResourceLoader.exists(path, "Script"):
			push_error("Native endpoint cue requires the complete captured project")
			get_tree().quit(1)
			return
		transmission_endpoint_cue = load(path).new()
		transmission_endpoint_cue.name = "TransmissionEndpointCue"
		add_child(transmission_endpoint_cue)
	transmission_endpoint_cue.refresh(endpoint)

func _transmission_click(center: Array, entity_id: String) -> bool:
	var consumed: bool = _native_transmission() and transmission_controls != null and transmission_controls.handle_world_click(center, entity_id)
	if consumed:
		_refresh_endpoint_cue()
	return consumed

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
		if action.action == "place_gear":
			selected = str(outcome.get("entity", ""))
		elif action.action == "remove" and selected == action.get("entity", ""):
			selected = ""
		_construction_feedback(intent, outcome)
		_message({"place": "Placed. Parts stay with this worksite.",
			"connect": "Material path connected.", "connect_drive": "Drive shaft connected.",
			"retrieve": "Plate collected.", "set_power": "Drive updated.",
			"remove": "Part returned to your carried kit.",
			"disconnect": "Material connection removed.",
			"disconnect_drive": "Drive shaft returned."}.get(action.action, "Done."))
	else:
		_message(_material_refusal_message(outcome, {"occupied": "That square is occupied.", "no_part": "That part is already placed.",
			"ports_not_adjacent": "Connect neighboring ports, following the arrow.",
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
			"not_at_stream": "Place the waterwheel beside the stream bank.",
			"not_at_seam": "Place the collector on the brass seam strip.",
			"no_shaft": "All carried shafts are in use."}.get(outcome.reason, "That action is unavailable here.")), true)
	_refresh()
	return outcome

func _material_refusal_message(outcome: Dictionary, fallback: String) -> String:
	# Fixed-roster historical payloads may omit the helper or carry its older
	# API. Formatting must never add a resource requirement or change admission.
	if recovery_actions != null and recovery_actions.has_method("refusal_text"):
		var text: Variant = recovery_actions.call("refusal_text", outcome)
		if typeof(text) == TYPE_STRING and not text.is_empty():
			return text
	return fallback

func _process(delta: float) -> void:
	if auto_advance:
		elapsed += delta
		while elapsed >= STEP_SECONDS:
			elapsed -= STEP_SECONDS
			model.advance()
		_refresh()
	_refresh_machine_preview()
	_refresh_endpoint_cue()
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
	var spin := Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO)
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
			orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.005, 0.35, 1.25)
		else:
			hover_cell = _screen_cell(event.position)
			_update_cursor()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(10 if legacy_fixture else 8, distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(28 if legacy_fixture else 24, distance + 1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var entity_id := _screen_entity(event.position)
			if not _transmission_click(_transmission_center(event.position), entity_id):
				_world_click(_screen_cell(event.position), entity_id)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _select_tool("collector")
			KEY_2: _select_tool("belt")
			KEY_3: _select_tool("processor")
			KEY_4: _select_tool("wheel")
			KEY_5:
				if _native_transmission():
					_select_tool("gear")
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
	pending_link = ""
	if _native_transmission() and transmission_controls != null and tool in ["gear", "drive"]:
		transmission_controls.choose_tool("gear" if tool == "gear" else "shaft")
	_update_cursor()
	_refresh_ui()
	var instructions := {"flow": "Click the upstream machine, then its neighbor toward the brass arrow.",
		"drive": "Click two neighboring machines to connect a drive shaft.",
		"inspect": "Click a machine to inspect it or collect its finished work.",
		"collector": "Place the collector on the brass seam strip.",
		"wheel": "Place the waterwheel on the stream bank beside the seam."}
	if _native_transmission():
		instructions["drive"] = "Choose a machine or cogwheel, then its partner. The amber ring marks the first endpoint."
		instructions["gear"] = "Place a cogwheel at the highlighted point. Set axis and height in the cogwheel menu."
	_message(instructions.get(tool,
		"Place %s on an empty grid square." % NAMES.get(tool, tool)))

func _world_click(cell: Vector2i, entity_id: String = "") -> void:
	if explanation_open:
		return
	if _native_transmission():
		var height: int = transmission_controls.gear_height if transmission_controls != null else 0
		if _transmission_click([cell.x * 4, height, cell.y * 4], entity_id):
			return
		if mode == "inspect" and state.get("transmission_parts", {}).has(entity_id):
			selected = entity_id
			_refresh_ui()
			return
	if state.entities.has(entity_id):
		var actual: Array = state.entities[entity_id].cell
		cell = Vector2i(actual[0], actual[1])
	if cell.x < -2 or cell.x > 4 or cell.y < -2 or cell.y > 4:
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
		var action := {"action": "place", "kind": mode, "cell": [cell.x, cell.y]}
		if _native_transmission() and transmission_controls != null:
			# Dot assignment creates a StringName key; the native wire deliberately
			# accepts only exact String dictionary keys, without coercion.
			action["axis"] = transmission_controls.selected_axis
		var outcome := issue(action)
		if outcome.accepted:
			selected = outcome.entity
	_refresh_ui()

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
		var outcome := issue({"action": "remove", "entity": selected})
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
	if example_presenter != null:
		example_presenter.set_lesson(lesson_index)

func _screen_cell(screen: Vector2) -> Vector2i:
	var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null:
		return Vector2i(99, 99)
	return Vector2i(roundi(point.x / PITCH), roundi(point.z / PITCH))

func _screen_entity(screen: Vector2) -> String:
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 80)
	query.collision_mask = Geometry.PICK_LAYER
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return str(hit.collider.get_meta("entity", "")) if not hit.is_empty() else ""

func _entity_at_cell(cell: Vector2i) -> String:
	for entity_id in state.get("entities", {}):
		if state.entities[entity_id].cell == [cell.x, cell.y]:
			return entity_id
	return ""

func _cell_position(cell: Array) -> Vector3:
	return Vector3(cell[0] * PITCH, 0, cell[1] * PITCH)

func _update_camera() -> void:
	camera.position = focus + Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch)) * distance
	camera.look_at(focus)

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
	else:
		var surface = ProductionEnvironment.Surface
		var foundation_finish: StandardMaterial3D = ProductionSteelFloor.material()
		set_meta("foundation_surface", ProductionSteelFloor.source_status)
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
		for spec in surface.pad_panels():
			var tint := Color("74766b").darkened(float(posmod(spec.cell.x * 17 + spec.cell.y * 31, 5)) * 0.018)
			var panel := _machine_box(self, "FoundationPanel", spec.center, spec.size, tint, 0.04, 0.92)
			panel.set_meta("surface_role", "foundation")
			panel.set_meta("site_solid_id", spec.id)
			if foundation_finish != null:
				panel.material_override = foundation_finish
	var arrow := _text(self, "MATERIAL  →", Vector3(1.6, 0.08, -4.15), Color("e4bc70"), 0.005)
	arrow.rotation_degrees.x = -90
	machine_root = Node3D.new()
	add_child(machine_root)
	item_root = Node3D.new()
	add_child(item_root)
	hover = _box(self, Vector3.ZERO, Vector3(1.5, 0.035, 1.5), Color(0.85, 0.75, 0.45, 0.45))
	hover.visible = false
	selection_ring = _box(self, Vector3.ZERO, Vector3(1.54, 0.035, 1.54), Color("c9bb86"))
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

func _machine_drive_stub(anchor: Node3D, entity: Dictionary) -> void:
	if state.get("options", {}).get("native", false):
		var axis := _machine_axis(entity)
		# The vertical stub stays above the base inside the same pick envelope.
		var height := 0.9 if axis == Vector3.UP else 1.35
		_machine_cylinder(anchor, "DriveStub", Vector3(0, Geometry.ANCHOR_HEIGHT, 0),
			0.085, height, Color("b87945"), _spindle_rotation(axis))
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
		"belt":
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
			for x in [-0.48, 0.48]:
				_machine_box(anchor, "FrameJoint", Vector3(x, 0.46, -0.215), Vector3(0.23, 0.17, 0.035), COLORS.processor.darkened(0.14))
				for y in [0.41, 0.51]:
					_machine_fastener(anchor, "FrameFastener", Vector3(x, y, -0.19), Vector3.BACK)

func _collector_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame: Color = COLORS.collector
	var steel := Color("a6b4af")
	_machine_box(anchor, "StockBed", Vector3(0, 0.51, 0), Vector3(1.25, 0.1, 0.67), steel, 0.85, 0.45)
	_machine_box(anchor, "BackHousing", Vector3(-0.22, 0.66, -0.44), Vector3(0.84, 0.78, 0.14), frame)
	for x in [-0.57, 0.18]:
		_machine_box(anchor, "HeadSupport", Vector3(x, 0.87, -0.38), Vector3(0.12, 1.1, 0.14), frame)
	_machine_box(anchor, "HeadCover", Vector3(-0.22, 1.42, -0.25), Vector3(0.86, 0.12, 0.64), frame)
	_machine_cylinder(anchor, "CutterDrum", Vector3(-0.22, 1.1, -0.19), 0.24, 0.34,
		Color("465a60"), Vector3(PI / 2, 0, 0))
	_machine_cylinder(anchor, "CutterHub", Vector3(-0.22, 1.1, 0.01), 0.085, 0.08,
		steel, Vector3(PI / 2, 0, 0))
	for z in [-0.37, 0.37]:
		_machine_box(anchor, "StockGuide", Vector3(0.05, 0.6, z), Vector3(1.15, 0.08, 0.06), frame)
	_machine_drive_stub(anchor, entity)

func _belt_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame: Color = COLORS.belt
	for x in [-0.52, 0.52]:
		for z in [-0.26, 0.26]:
			_machine_box(anchor, "ConveyorLeg", Vector3(x, 0.315, z), Vector3(0.09, 0.21, 0.09), frame)
	_machine_box(anchor, "ConveyorBand", Vector3(0, 0.465, 0), Vector3(1.38, 0.12, 0.64), Color("28383d"), 0.05, 0.9)
	for n in range(-3, 4):
		_machine_box(anchor, "ConveyorCleat", Vector3(n * 0.18, 0.54, 0), Vector3(0.06, 0.03, 0.62), Color("b2c5b7"), 0.3)
	for z in [-0.36, 0.36]:
		_machine_box(anchor, "ConveyorRail", Vector3(0, 0.57, z), Vector3(1.38, 0.08, 0.05), frame)
	for x in [-0.57, 0.57]:
		_machine_cylinder(anchor, "ConveyorRoller", Vector3(x, 0.465, 0), 0.1, 0.7,
			Color("5b7275"), Vector3(PI / 2, 0, 0))
	_machine_drive_stub(anchor, entity)

func _press_visual(anchor: Node3D, entity: Dictionary = {}) -> void:
	var frame: Color = COLORS.processor
	var steel := Color("a6b4af")
	var dark := Color("29393f")
	for x in [-0.48, 0.48]:
		_machine_box(anchor, "PressUpright", Vector3(x, 0.82, -0.38), Vector3(0.15, 1.24, 0.28), frame)
	_machine_box(anchor, "PressBridge", Vector3(0, 1.5, -0.3), Vector3(1.2, 0.2, 0.36), frame)
	_machine_box(anchor, "Anvil", Vector3(0, 0.46, 0.05), Vector3(0.7, 0.16, 0.63), dark)
	_machine_box(anchor, "ToolHead", Vector3(0, 0.84, 0), Vector3(0.56, 0.17, 0.55), steel, 0.85, 0.32)
	_machine_cylinder(anchor, "Piston", Vector3(0, 1.14, -0.08), 0.075, 0.45, steel)
	for x in [-0.34, 0.34]:
		_machine_cylinder(anchor, "ToolGuide", Vector3(x, 1.06, -0.19), 0.04, 0.6, Color("b87945"))
	_machine_box(anchor, "OutputTray", Vector3(0.46, 0.33, 0.15), Vector3(0.48, 0.05, 0.58), Color("aaa993"), 0.85, 0.5)
	_machine_drive_stub(anchor, entity)
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
	if native_profile and axis == Vector3.UP:
		# A vertical axle rests on a pedestal below the horizontal rotor.
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
	wheel_rotor.position = Vector3.UP * 0.78 * scale_factor
	wheel_rotor.scale = Vector3.ONE * scale_factor
	if native_profile and axis == Vector3.RIGHT:
		wheel_rotor.rotation.y = PI / 2
	elif native_profile and axis == Vector3.UP:
		wheel_rotor.rotation.x = -PI / 2
	anchor.add_child(wheel_rotor)
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
		var radial := Vector3(cos(angle), sin(angle), 0)
		var paddle := _machine_box(wheel_rotor, "WheelPaddle", radial * 0.62,
			Vector3(0.14, 0.16, 0.28), wood, 0.05, 0.88)
		paddle.rotation.z = angle
	for n in range(3):
		var spoke := _machine_box(wheel_rotor, "WheelSpoke", Vector3.ZERO,
			Vector3(0.065, 1.0, 0.085), wood, 0.05, 0.88)
		spoke.rotation.z = n * PI / 3.0
	_machine_cylinder(wheel_rotor, "WheelHub", Vector3.ZERO, 0.13, 0.45,
		Color("b87945"), Vector3(PI / 2, 0, 0))

func _assemble_machine(anchor: Node3D, entity: Dictionary) -> void:
	_machine_box(anchor, "Plinth", Vector3(0, 0.12, 0), Vector3(1.35, 0.24, 1.35), Color("273c41"))
	match entity.kind:
		"collector": _collector_visual(anchor, entity)
		"belt": _belt_visual(anchor, entity)
		"processor": _press_visual(anchor, entity)
		"wheel": _wheel_visual(anchor, entity)
	_machine_surface_detail(anchor, entity.kind)

func _rebuild_machines() -> void:
	_sync_machine_body_context()
	for child in machine_root.get_children():
		child.free()
	wheel_rotor = null
	for entity_id in state.entities:
		var entity: Dictionary = state.entities[entity_id]
		var kind: String = entity.kind
		var anchor := Node3D.new()
		anchor.position = _cell_position(entity.cell)
		machine_root.add_child(anchor)
		_assemble_machine(anchor, entity)
		anchor.set_meta("machine_entity", entity_id)
		anchor.set_meta("machine_kind", kind)
		var motion_meshes: Array[Dictionary] = []
		_remember_machine_motion(anchor, kind, Transform3D.IDENTITY, motion_meshes)
		anchor.set_meta("motion_meshes", motion_meshes)
		if kind == "collector" and transmission_presenter != null:
			_apply_cutter_pose(anchor, motion_meshes, transmission_presenter.visual_angle(entity_id))
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
		shape.size = Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])
		collider.shape = shape
		collider.position.y = Geometry.MACHINE_CENTER_HEIGHT
		body.add_child(collider)
		anchor.add_child(body)
		_text(anchor, NAMES.get(kind, kind).to_upper(), Vector3(0, 1.9, 0), Color("f2e5c5"))
	for pair in state.links:
		if state.entities.has(pair[0]) and state.entities.has(pair[1]):
			_material_route(machine_root, _cell_position(state.entities[pair[0]].cell),
				_cell_position(state.entities[pair[1]].cell))
	for pair in state.get("drive_links", []):
		if not _native_transmission() and state.entities.has(pair[0]) and state.entities.has(pair[1]):
			_bar(machine_root, _cell_position(state.entities[pair[0]].cell) + Vector3(0, 0.35, 0.55),
				_cell_position(state.entities[pair[1]].cell) + Vector3(0, 0.35, 0.55), 0.09, Color("d1b56e"))

func _redraw_items() -> void:
	# The asset helper uses this script's shared surfaces, so load it after
	# the opening class is available instead of creating a preload cycle.
	var path := "res://opening/workpiece_item_assets.gd"
	if ResourceLoader.exists(path, "Script"):
		if workpiece_item_assets == null:
			workpiece_item_assets = load(path)
		workpiece_item_assets.populate_items(item_root, state, PITCH)
		return
	if state.get("options", {}).get("native", false):
		push_error("Native item presentation requires the complete captured project.")
		return
	# Historical scripted payloads have fixed file rosters. Preserve their
	# existing presentation until those entry points are replaced.
	for child in item_root.get_children():
		child.free()
	for entity_id in state.entities:
		var entity: Dictionary = state.entities[entity_id]
		var pos := _cell_position(entity.cell)
		var amount := 0
		if entity.kind in ["collector", "belt"]:
			amount = int(state.stock.get(entity.kind, 0))
		elif entity.kind == "processor":
			amount = int(state.stock.held) + int(state.stock.input)
		for n in range(amount):
			_box(item_root, pos + Vector3(-0.17 + n * 0.32, 0.65, 0), Vector3(0.27, 0.18, 0.36), Color("e2c48b"))
		if entity.kind == "processor" and state.stock.output > 0:
			_box(item_root, pos + Vector3(0.46, 0.39, 0.15), Vector3(0.44, 0.07, 0.53), Color("e4d8b3"))
	# The finite seam stays in its marked column when machinery is rebuilt.
	for n in range(mini(16, int(state.stock.source))):
		_box(item_root, Vector3(-0.16 + (n % 2) * 0.32, 0.11, -2.9 + int(n / 2.0) * 1.15),
			Vector3(0.2, 0.18, 0.28), Color("a58c59"))

func _refresh() -> void:
	state = model.projection()
	if actor_world != null:
		actor_world.sync_topology()
	var next_key := JSON.stringify([state.entities, state.links, state.get("drive_links", [])])
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

func _refresh_ui() -> void:
	if stock_label == null:
		return
	_refresh_transmission()
	var inventory := int(state.inventories.get(client, 0))
	var parts := _display_parts()
	var part_scope := "shared" if _parts_are_shared() else "carried"
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
	for tool in tool_buttons:
		var button: Button = tool_buttons[tool]
		var unavailable := NAMES.has(tool) and not parts.has(tool)
		if _native_transmission() and (NAMES.has(tool) or tool == "drive"):
			unavailable = int(parts.get("shaft" if tool == "drive" else tool, 0)) < 1
		button.disabled = explanation_open or unavailable
		button.button_pressed = mode == tool
		if transmission_controls != null and not transmission_controls.active_tool.is_empty():
			button.button_pressed = tool == "drive" and transmission_controls.active_tool == "shaft"
		if NAMES.has(tool):
			button.text = "%s    ·    %d %s" % [NAMES[tool], int(parts.get(tool, 0)), part_scope]
	tool_buttons.drive.text = "Drive link  [G]    ·    %d shafts" % int(parts.get("shaft", 0))
	if _native_transmission():
		tool_buttons.drive.text = "Shaft  [G]    ·    %d carried" % int(parts.get("shaft", 0))
	retrieve_button.disabled = explanation_open or state.stock.output < 1 or not state.entities.has(selected) or state.entities[selected].kind != "processor"
	remove_button.disabled = explanation_open or not _contains_target(state, selected)
	selection_ring.visible = state.entities.has(selected)
	if selection_ring.visible:
		selection_ring.position = _cell_position(state.entities[selected].cell) + Vector3(0, 0.02, 0)
		inspector.text = "%s\nSquare %s" % [NAMES.get(state.entities[selected].kind, selected), str(state.entities[selected].cell)]
		if state.entities[selected].kind == "processor":
			inspector.text += "\n%d in · %d held · %d ready" % [state.stock.input, state.stock.held, state.stock.output]
		inspector.text += "\n" + _inspection_hint()
	elif _native_transmission() and state.get("transmission_parts", {}).has(selected):
		var part: Dictionary = state.transmission_parts[selected]
		var motion: Dictionary = state.get("motion", {}).get(selected, {})
		inspector.text = "%s · %s axis\nGrid %s" % ["Cogwheel" if part.kind == "gear" else "Shaft", ["X", "Y", "Z"][part.axis], str(part.center)]
		if motion.get("state") == "rotating":
			inspector.text += "\nRate %d / %d" % [motion.numerator, motion.denominator]
		else:
			inspector.text += "\n" + str(motion.get("state", "disconnected")).capitalize()
	else:
		inspector.text = "Select a machine to inspect\nor collect its finished work."
	_refresh_guided_tools()
	if recovery_actions != null:
		recovery_actions.refresh()

func _toggle_all_tools() -> void:
	if not explanation_open:
		show_all_tools = not show_all_tools
		_refresh_ui()

func _toggle_details() -> void:
	if not explanation_open:
		show_details = not show_details
		_refresh_ui()

func _refresh_guided_tools(snapshot_ready: bool = true) -> void:
	_refresh_placement_hint(snapshot_ready)
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
	if kinds.has("belt"):
		offered.processor = true
	if kinds.has("processor"):
		offered.wheel = true
	if (kinds.has("collector") and kinds.has("belt")) or (kinds.has("belt") and kinds.has("processor")):
		offered.flow = true
	if kinds.has("wheel") and kinds.size() > 1:
		offered.drive = true
	var step := _guided_step(kinds)
	for tool in tool_buttons:
		var button: Button = tool_buttons[tool]
		# Keyboard selection stays visible even when it precedes the suggestion.
		button.visible = show_all_tools or offered.has(tool) or mode == tool
		for color_name in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			if tool == step.tool:
				button.add_theme_color_override(color_name, Color("edcc8d"))
			else:
				button.remove_theme_color_override(color_name)
	var inventory := int(state.get("inventories", {}).get(client, 0))
	goal_label.text = "Make 4 plates\n%s\n%d / 4 collected" % [step.text, inventory] if snapshot_ready else "Connect to the worksite."
	confirm_button.visible = snapshot_ready and (inventory >= 4 or goal_confirmed)
	all_tools_button.text = "Guided tools" if show_all_tools else "All tools"
	all_tools_button.disabled = explanation_open or not snapshot_ready
	details_button.text = "Less detail" if show_details else "Details"
	details_button.disabled = explanation_open
	for control in [stock_label, power_label, save_button, load_button]:
		control.visible = show_details
	actor_label.visible = show_details or not state.get("actors", {}).get(client, {}).get("ready", false)
	power_button.visible = show_all_tools or kinds.has("wheel")
	controls_label.text = "WASD walk · Space jump · Right-drag view · Wheel zoom · H help"
	if show_all_tools:
		controls_label.text = "WASD walk · Space jump · P wheel · 1–4 build · F / G links · I inspect · H help"
	_refresh_engineering(snapshot_ready)

func _build_placement_hint() -> void:
	placement_hint = Node3D.new()
	placement_hint.name = "GuidedPlacementHint"
	placement_hint.visible = false
	add_child(placement_hint)
	for side in [-0.7, 0.7]:
		_box(placement_hint, Vector3(0, 0, side), Vector3(1.45, 0.035, 0.055), Color("edcc8d"))
		_box(placement_hint, Vector3(side, 0, 0), Vector3(0.055, 0.035, 1.45), Color("edcc8d"))

func _placement_hint_ready() -> bool:
	return _can_control_character()

func _guided_placement_cell() -> Array:
	if legacy_fixture or show_all_tools or explanation_open or not _placement_hint_ready():
		return []
	if not mode in ["belt", "processor"] or int(_display_parts().get(mode, 0)) < 1:
		return []
	# A suggestion for this starter path only, never a placement/reach decision.
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
	if cell[0] < -2 or cell[0] > 4 or cell[1] < -2 or cell[1] > 4:
		return []
	if not _entity_at_cell(Vector2i(cell[0], cell[1])).is_empty():
		return []
	return cell

func _refresh_placement_hint(snapshot_ready: bool = true) -> void:
	if placement_hint == null:
		return
	if transmission_controls != null and not transmission_controls.active_tool.is_empty():
		placement_hint.visible = false
		return
	var cell: Array = _guided_placement_cell() if snapshot_ready else []
	placement_hint.visible = not cell.is_empty()
	if placement_hint.visible:
		placement_hint.position = _cell_position(cell) + Vector3(0, 0.055, 0)

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
	if cell.x < -2 or cell.x > 4 or cell.y < -2 or cell.y > 4 or not _entity_at_cell(cell).is_empty():
		return
	var axis := _preview_axis()
	if axis < 0:
		return
	var key := "%s:%d:%s" % [mode, axis, str(_native_transmission())]
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
		_assemble_machine(machine_preview, {"kind": mode, "axis": axis})
		wheel_rotor = placed_rotor
		if machine_preview_material == null:
			machine_preview_material = StandardMaterial3D.new()
			machine_preview_material.albedo_color = Color(0.88, 0.75, 0.49, 0.32)
			machine_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			machine_preview_material.roughness = 0.75
			machine_preview_material.metallic = 0.0
		_style_machine_preview(machine_preview)
		machine_preview_key = key
	machine_preview.position = _cell_position([cell.x, cell.y])
	machine_preview.visible = true

func _style_machine_preview(node: Node) -> void:
	# Per-instance overrides leave shared placed materials and meshes intact.
	# Neutral amber is a form/footprint preview, never an admission verdict.
	if node is MeshInstance3D:
		node.material_override = machine_preview_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_style_machine_preview(child)

func _guided_step(kinds: Dictionary) -> Dictionary:
	if goal_confirmed:
		return {"text": "Four plates confirmed. Keep building or try another layout.", "tool": "inspect"}
	if int(state.get("inventories", {}).get(client, 0)) >= 4:
		return {"text": "Four plates ready. Confirm when you are ready.", "tool": "inspect"}
	if int(state.get("stock", {}).get("output", 0)) > 0:
		return {"text": "Plate ready. Select the press, then collect [R].", "tool": "inspect"}
	if not kinds.has("collector"):
		return {"text": "Place a collector on the brass strip near you.", "tool": "collector"}
	if not kinds.has("belt"):
		return {"text": "Add a belt beside the collector.", "tool": "belt"}
	if not kinds.has("processor"):
		return {"text": "Add a press at the belt outlet.", "tool": "processor"}
	var material_pairs: Dictionary = {}
	for pair in state.get("links", []):
		var entities: Dictionary = state.get("entities", {})
		if entities.has(pair[0]) and entities.has(pair[1]):
			material_pairs["%s:%s" % [entities[pair[0]].kind, entities[pair[1]].kind]] = true
	if not material_pairs.has("collector:belt") or not material_pairs.has("belt:processor"):
		return {"text": "Connect the material path. Help [H] shows an example.", "tool": "flow"}
	if not kinds.has("wheel"):
		return {"text": "Add a waterwheel by the stream.", "tool": "wheel"}
	if not state.get("power_enabled", true):
		return {"text": "Switch on the drive near the wheel [P].", "tool": "inspect"}
	if not state.get("powered", false):
		return {"text": "Bring power to the line. Help [H] shows the current setup.", "tool": "drive"}
	var stock: Dictionary = state.get("stock", {})
	if int(stock.get("source", 0)) + int(stock.get("collector", 0)) + int(stock.get("belt", 0)) + int(stock.get("input", 0)) + int(stock.get("held", 0)) == 0:
		return {"text": "No blanks remain here. All tools stays available for experimenting.", "tool": "inspect"}
	return {"text": "Follow a blank to the press. Select a machine to inspect it.", "tool": "inspect"}

func _inspection_hint() -> String:
	# Describe confirmed projection facts only. This is advice, never admission
	# or a second power solver; the authority still decides every command.
	var kind: String = state.entities[selected].kind
	var stop_before_link: bool = state.get("powered", false) and not state.get("options", {}).get("native", false)
	if kind == "processor" and state.stock.output > 0:
		return "Outlet full; plate ready.\n[R] collect to make room."
	if not state.get("power_enabled", true):
		return "Drive switched off.\n[%s] enables the drive%s." % [_power_key(), "" if legacy_fixture else " near wheel"]
	if kind == "processor" and state.stock.held > 0 and state.get("powered", false):
		if state.remaining == 0:
			return "Work done; blank retained.\nNext drive tick releases plate."
		return "Working: %d ticks remaining.\nHeld blank stays in the press." % state.remaining
	if kind in ["belt", "processor"] and not _has_material_connection(true):
		return (("Inlet missing. Stop [%s].\n" % _power_key()) if stop_before_link else "No material inlet linked.\n") + "[F] link " + ("Collector → Belt." if kind == "belt" else "Belt → Press.")
	if kind in ["collector", "belt"] and not _has_material_connection(false):
		return (("Outlet missing. Stop [%s].\n" % _power_key()) if stop_before_link else "No material outlet linked.\n") + "[F] link " + ("Collector → Belt." if kind == "collector" else "Belt → Press.")
	if not state.get("powered", false):
		if _native_transmission():
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
	return "Wheel powers the whole line.\n[%s] stops it%s." % [_power_key(), " for editing" if legacy_fixture else " from nearby"]

func _has_material_connection(incoming: bool) -> bool:
	for pair in state.links:
		if pair[1 if incoming else 0] == selected:
			return true
	return false

func _update_cursor() -> void:
	_refresh_machine_preview()
	if _native_transmission() and transmission_controls != null and not transmission_controls.active_tool.is_empty():
		hover.visible = false
		if transmission_controls.active_tool == "gear" and not explanation_open and _can_control_character():
			var center := _transmission_center(get_viewport().get_mouse_position())
			if center.size() == 3 and center[0] >= -8 and center[0] <= 16 and center[2] >= -8 and center[2] <= 16:
				hover.visible = true
				hover.position = Vector3(center[0] * PITCH / 4.0, Geometry.ANCHOR_HEIGHT + center[1] * PITCH / 4.0, center[2] * PITCH / 4.0)
				hover.basis = transmission_presenter.axis_basis(["x", "y", "z"].find(transmission_controls.selected_axis))
		return
	hover.basis = Basis.IDENTITY
	hover.visible = hover_cell.x >= -2 and hover_cell.x <= 4 and hover_cell.y >= -2 and hover_cell.y <= 4 and not explanation_open
	if hover.visible:
		hover.position = _cell_position([hover_cell.x, hover_cell.y]) + Vector3(0, 0.03, 0)

func _message(words: String, refused: bool = false) -> void:
	status_label.text = words
	status_label.modulate = Color("e0a880") if refused else Color("d6dfd6")

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
	var build := _panel(root, Vector2(18, 18), Vector2(275, 620))
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
	parts_label = _label(build, "BUILD FROM SHARED KIT" if _parts_are_shared() else "BUILD FROM CARRIED PARTS", 12, Color("9eb4b2"))
	for kind in ["collector", "belt", "processor", "wheel"]:
		var button := _button(build, NAMES[kind], _select_tool.bind(kind))
		button.toggle_mode = true
		tool_buttons[kind] = button
	tool_buttons.flow = _button(build, "Material link  [F]", _select_tool.bind("flow"))
	tool_buttons.drive = _button(build, "Drive link  [G]", _select_tool.bind("drive"))
	tool_buttons.inspect = _button(build, "Inspect  [I]", _select_tool.bind("inspect"))
	for tool in ["flow", "drive", "inspect"]:
		tool_buttons[tool].toggle_mode = true
	var view_options := HBoxContainer.new()
	build.add_child(view_options)
	view_options.visible = not legacy_fixture
	all_tools_button = _button(view_options, "All tools", _toggle_all_tools)
	all_tools_button.tooltip_text = "Choose any available part."
	details_button = _button(view_options, "Details", _toggle_details)
	details_button.tooltip_text = "Show worksite counters and save options."
	_button(build, "How this line works  [H]", _toggle_explanation)
	var right := _panel(root, Vector2(990, 18), Vector2(272, 490))
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
	right.add_child(HSeparator.new())
	save_button = _button(right, "Save worksite  [F5]", _save_worksite)
	load_button = _button(right, "Load worksite  [F9]", _load_worksite)
	var bottom := _panel(root, Vector2(310, 694), Vector2(952, 88))
	var bottom_panel: Control = bottom.get_parent()
	bottom_panel.set_anchor_and_offset(SIDE_RIGHT, 1.0, -18)
	bottom_panel.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -18)
	bottom_panel.set_anchor_and_offset(SIDE_TOP, 1.0, -106)
	bottom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status_label = _label(bottom, "", 16)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label = _label(bottom, "1–4 build  ·  F material / G drive  ·  Right-drag orbit  ·  Wheel zoom  ·  WASD pan  ·  Home recenter" if legacy_fixture else "WASD walk · Space jump · P wheel · 1–4 build · F / G links · Right-drag orbit · Wheel zoom · H help", 12, Color("9eb4b2"))
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
