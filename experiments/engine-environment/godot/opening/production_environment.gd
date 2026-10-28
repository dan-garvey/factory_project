extends RefCounted
## Render resources only; no scene controller or simulation authority.
const Geometry = preload("res://opening/site_geometry.gd")
const ProductionSteelFloor = preload("res://opening/production_surfaces.gd").ProductionSteelFloor
const ProductionVisuals = preload("res://opening/production_surfaces.gd").ProductionVisuals

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
	static var ore_ground_finish: StandardMaterial3D
	static var ore_exposure_finish: StandardMaterial3D

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
		push_error("Missing or invalid sourced daylight panorama: " + str(loaded.get("reason", loaded.status)))
		return null

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

	static func _ore_ground_material() -> StandardMaterial3D:
		if ore_ground_finish == null:
			var image := ProductionVisuals.read_image("res://opening/assets/mineral-outcrop/ore-soil.webp")
			if image == null or image.generate_mipmaps() != OK:
				push_error("The broad ore field requires its prepared mineral soil.")
				return null
			ore_ground_finish = StandardMaterial3D.new()
			ore_ground_finish.albedo_texture = ImageTexture.create_from_image(image)
			ore_ground_finish.vertex_color_use_as_albedo = true
			ore_ground_finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ore_ground_finish.cull_mode = BaseMaterial3D.CULL_DISABLED
			ore_ground_finish.roughness = 1.0
			ore_ground_finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return ore_ground_finish

	static func _ore_exposure_material() -> StandardMaterial3D:
		if ore_exposure_finish == null:
			var albedo := ProductionVisuals.read_image("res://opening/assets/mineral-outcrop/albedo.webp")
			var normal := ProductionVisuals.read_image("res://opening/assets/mineral-outcrop/normal.webp")
			if albedo == null or normal == null or albedo.generate_mipmaps() != OK \
					or normal.generate_mipmaps(true) != OK:
				push_error("The broad ore field requires its prepared mineral rock.")
				return null
			ore_exposure_finish = StandardMaterial3D.new()
			ore_exposure_finish.albedo_texture = ImageTexture.create_from_image(albedo)
			ore_exposure_finish.albedo_color = Color("d7a06e")
			ore_exposure_finish.roughness = 0.91
			ore_exposure_finish.normal_enabled = true
			ore_exposure_finish.normal_texture = ImageTexture.create_from_image(normal)
			ore_exposure_finish.cull_mode = BaseMaterial3D.CULL_DISABLED
			ore_exposure_finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return ore_exposure_finish

	static func ore_field(state: Dictionary) -> Node3D:
		# This surface is read from the native deposit cells and region balances.
		# It adds no body collision, stock, or admission rule to the renderer.
		var deposit: Dictionary = state.get("source_deposit", {})
		var cells: Array = deposit.get("cells", [])
		if Surface == null or cells.size() < 100:
			return null
		var cell_regions: Array = deposit.get("cell_regions", [])
		if cell_regions.size() != cells.size():
			return null
		var low := Vector2i(1000000, 1000000)
		var high := Vector2i(-1000000, -1000000)
		for cell: Array in cells:
			if cell.size() != 2:
				return null
			low = low.min(Vector2i(int(cell[0]), int(cell[1])))
			high = high.max(Vector2i(int(cell[0]), int(cell[1])))
		var left: float = (float(low.x) - 0.5) * Geometry.PITCH
		var right: float = (float(high.x) + 0.5) * Geometry.PITCH
		var back: float = (float(low.y) - 0.5) * Geometry.PITCH
		var front: float = (float(high.y) + 0.5) * Geometry.PITCH
		var regions: Array[Dictionary] = []
		var balances := {}
		for id: String in state.get("hand_sources", {}):
			if id.begins_with(str(deposit.get("id", "")) + "-region-"):
				var region: Dictionary = state.hand_sources[id].duplicate()
				region["id"] = id
				regions.append(region)
				balances[id] = clampf(float(region.remaining) / maxf(1.0, float(region.initial)), 0.0, 1.0)
		var root := Node3D.new()
		root.name = "OreField"
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var stones: Array[Transform3D] = []
		var stone_colors: Array[Color] = []
		for index in range(cells.size()):
			var cell: Array = cells[index]
			var cx: float = float(cell[0]) * Geometry.PITCH
			var cz: float = float(cell[1]) * Geometry.PITCH
			var fraction: float = float(balances.get(str(cell_regions[index]), 0.0))
			for z_step in range(4):
				for x_step in range(4):
					var x0: float = cx - Geometry.PITCH * 0.5 + float(x_step) * Geometry.PITCH / 4.0
					var z0: float = cz - Geometry.PITCH * 0.5 + float(z_step) * Geometry.PITCH / 4.0
					var x1: float = x0 + Geometry.PITCH / 4.0
					var z1: float = z0 + Geometry.PITCH / 4.0
					for point: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1),
							Vector2(x0, z0), Vector2(x1, z1), Vector2(x0, z1)]:
						var edge: float = minf(minf(point.x - left, right - point.x),
							minf(point.y - back, front - point.y))
						var roughness: float = sin(point.x * 0.71 + sin(point.y * 0.44)) * 0.58 \
							+ cos(point.y * 0.83 - point.x * 0.39) * 0.36
						var fleck: float = sin(point.x * 1.37 + sin(point.y * 0.63)) * 0.53 \
							+ cos(point.y * 1.19 - point.x * 0.72) * 0.47
						var local_patch: float = 0.0
						for region: Dictionary in regions:
							var center: Array = region.get("position", [])
							if center.size() != 3:
								continue
							var span := Vector2((point.x - float(center[0])) / 5.0,
								(point.y - float(center[2])) / 3.9).length()
							var weight: float = 1.0 - smoothstep(0.48, 1.13, span + roughness * 0.10)
							local_patch = maxf(local_patch, weight * sqrt(float(balances.get(
								str(region.get("id", "")), 0.0))))
						var opacity: float = smoothstep(0.0, 1.2, edge + roughness * 0.6) \
							* local_patch * (0.48 + 0.40 * smoothstep(-0.38, 0.36, fleck))
						surface.set_normal(Surface.normal(point.x, point.y))
						surface.set_uv(point * 0.62)
						surface.set_color(Color(1.0, 1.0, 1.0, opacity))
						surface.add_vertex(Vector3(point.x,
							Surface.height_at(point.x, point.y) + 0.028, point.y))
			if fraction <= 0.01:
				continue
			for n in range(4):
				var seed: int = absi(int(cell[0]) * 73856093 ^ int(cell[1]) * 19349663 ^ n * 83492791)
				var dx: float = (float(seed % 101) / 100.0 - 0.5) * 1.12
				var dz: float = (float((seed / 101) % 101) / 100.0 - 0.5) * 1.12
				var x: float = cx + dx
				var z: float = cz + dz
				var size: float = 0.10 + float(seed % 9) * 0.022
				var height: float = 0.035 + float((seed / 7) % 5) * 0.012
				var basis := Basis(Vector3.UP, float(seed % 360) * PI / 180.0)
				basis = basis.scaled_local(Vector3(size, height, size * 0.72))
				stones.append(Transform3D(basis,
					Vector3(x, Surface.height_at(x, z) + height * 0.45, z)))
				stone_colors.append(Color("a77855").lerp(Color("77695c"), float(seed % 5) / 5.0))
		var soil := MeshInstance3D.new()
		soil.name = "CopperBearingGround"
		soil.mesh = surface.commit()
		soil.material_override = _ore_ground_material()
		soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(soil)
		if not stones.is_empty():
			var pebble := SphereMesh.new()
			pebble.radius = 0.5
			pebble.height = 1.0
			pebble.radial_segments = 8
			pebble.rings = 4
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = true
			multimesh.mesh = pebble
			multimesh.instance_count = stones.size()
			for index in range(stones.size()):
				multimesh.set_instance_transform(index, stones[index])
				multimesh.set_instance_color(index, stone_colors[index])
			var gravel := MultiMeshInstance3D.new()
			gravel.name = "CopperGravel"
			gravel.multimesh = multimesh
			var stone_finish := StandardMaterial3D.new()
			stone_finish.vertex_color_use_as_albedo = true
			stone_finish.roughness = 0.94
			stone_finish.metallic = 0.06
			gravel.material_override = stone_finish
			root.add_child(gravel)
		var seam_mesh: Mesh = Surface.SOURCE_OUTCROP_MESH
		var seam_scale: Vector3 = Vector3(0.54, 0.20, 0.40) / seam_mesh.get_aabb().size
		var seam_finish := _ore_exposure_material()
		var original: Dictionary = state.get("hand_sources", {}).get(deposit.get("id", ""), {})
		var original_position: Array = original.get("position", [])
		for region: Dictionary in regions:
			if int(region.get("remaining", 0)) <= 0:
				continue
			var center: Array = region.get("position", [])
			if center.size() != 3:
				continue
			var x: float = float(center[0])
			var z: float = float(center[2])
			if original_position.size() == 3 and Vector2(x - float(original_position[0]),
					z - float(original_position[2])).length() < 1.8:
				continue
			for offset: Vector2 in [Vector2(-0.16, -0.12), Vector2(0.17, 0.10), Vector2(0.12, -0.17)]:
				var seam := MeshInstance3D.new()
				seam.name = "LowCopperExposure"
				seam.mesh = seam_mesh
				seam.material_override = seam_finish
				seam.scale = seam_scale
				seam.rotation.y = atan2(offset.y, offset.x)
				seam.position = Vector3(x + offset.x,
					Surface.height_at(x + offset.x, z + offset.y) + 0.055, z + offset.y)
				seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(seam)
		return root

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
