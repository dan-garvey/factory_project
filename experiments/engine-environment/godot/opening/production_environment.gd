extends RefCounted
## Render resources only; no scene controller or simulation authority.
const Geometry = preload("res://opening/site_geometry.gd")
const MachineBatcher = preload("res://opening/machine_batches.gd")
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
	static var ore_stone_finish: ShaderMaterial
	static var live_lod_cache := {}
	static var live_mat_cache := {}
	static var live_play_cached: int = -1
	const ORE_FIELD_STONES = preload("res://opening/assets/mineral-outcrop/field-rock-moss-set-02.glb")
	const ORE_FIELD_BOULDER_SHADER = preload("res://opening/ore_field_scan.gdshader")

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
		var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
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

	static func merge_static_meshes(parent: Node3D, batch_name: String, parts: Array[MeshInstance3D], poses: Array[Transform3D]) -> MeshInstance3D:
		if parts.is_empty() or parts.size() != poses.size():
			return null
		var by_mat := {}
		var mat_order: Array[Material] = []
		for idx in parts.size():
			var part := parts[idx]
			if part == null or part.mesh == null or part.mesh.get_surface_count() == 0:
				continue
			var mat: Material = part.material_override
			if mat == null:
				mat = part.mesh.surface_get_material(0)
			if mat == null:
				continue
			var mid := mat.get_instance_id()
			if not by_mat.has(mid):
				by_mat[mid] = []
				mat_order.append(mat)
			by_mat[mid].append({"part": part, "pose": poses[idx]})
		if mat_order.is_empty():
			return null
		var merged_mesh := ArrayMesh.new()
		for mat in mat_order:
			var entries: Array = by_mat[mat.get_instance_id()]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for entry in entries:
				var p: MeshInstance3D = entry.part
				st.append_from(p.mesh, 0, entry.pose)
				p.visible = false
			var surf_idx := merged_mesh.get_surface_count()
			st.commit(merged_mesh)
			merged_mesh.surface_set_material(surf_idx, _live_botanical_material(mat))
		if is_live_play():
			merged_mesh = MachineBatcher.finish_mesh(merged_mesh, true)
		var batch := MeshInstance3D.new()
		batch.name = batch_name
		batch.mesh = merged_mesh
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(batch)
		return batch

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
		var finishes := {"stone": _live_botanical_material(stone_material()), "dark_stone": ProductionVisuals.material(Color("38403e"), 0.0, 0.92),
			"foam": foam_material()}
		var live_batch := is_live_play()
		var arch_parts: Array[MeshInstance3D] = []
		var arch_poses: Array[Transform3D] = []
		for spec in Surface.architecture_boxes():
			var part := _scenery_box(groups[spec.group], spec.label,
				spec.center - Surface.group_origin(spec.group), spec.size, finishes[spec.finish])
			part.basis = spec.basis
			if live_batch:
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if spec.solid:
				part.set_meta("site_solid_id", spec.id)
			arch_parts.append(part)
			arch_poses.append(Transform3D(spec.basis, spec.center))
		if live_batch:
			merge_static_meshes(arch, "MillraceArchitectureBatch", arch_parts, arch_poses)
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
		instances.mesh = _live_lod_mesh(foliage_cluster_mesh, [-12])
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
		foliage.material_override = _live_botanical_material(finish)
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
			instances.mesh = _live_lod_mesh(foliage_cluster_mesh, [-12])
			instances.instance_count = count
			instances.buffer = buffer
			instances.custom_aabb = bounds
			var patch := MultiMeshInstance3D.new()
			patch.name = "GrassPatch%02d" % patch_index
			patch.position = center
			patch.multimesh = instances
			patch.material_override = _live_botanical_material(foliage_finish)
			patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		instances.mesh = _live_lod_mesh(foliage_cluster_mesh, [-12])
		instances.instance_count = count
		instances.buffer = buffer
		instances.custom_aabb = bounds
		patch.multimesh = instances
		patch.material_override = _live_botanical_material(foliage_finish)
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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

	static func is_live_play(state: Dictionary = {}) -> bool:
		if live_play_cached == -1:
			var args := OS.get_cmdline_args()
			live_play_cached = 1 if (not ("--script" in args) or ("res://opening/perf_benchmark.gd" in args)) else 0
		return live_play_cached == 1 or state.get("placed_components", {}).size() >= 12

	static func _live_botanical_material(mat: Material) -> Material:
		if not is_live_play() or not mat is StandardMaterial3D:
			return mat
		var mid := mat.get_instance_id()
		if live_mat_cache.has(mid):
			return live_mat_cache[mid]
		var dup := (mat as StandardMaterial3D).duplicate(false) as StandardMaterial3D
		if dup.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			dup.alpha_scissor_threshold = 0.35
		else:
			dup.cull_mode = BaseMaterial3D.CULL_BACK
		dup.normal_enabled = false
		dup.normal_texture = null
		dup.ao_enabled = false
		dup.ao_texture = null
		dup.roughness_texture = null
		dup.metallic_texture = null
		dup.roughness = 0.85
		live_mat_cache[mid] = dup
		return dup

	static func _live_lod_mesh(mesh: ArrayMesh, max_tris: Array, generate: bool = true) -> ArrayMesh:
		if mesh == null or not is_live_play():
			return mesh
		var key := "%d:%s:%d" % [mesh.get_instance_id(), str(max_tris), 1 if generate else 0]
		if live_lod_cache.has(key):
			return live_lod_cache[key]
		var out := ArrayMesh.new()
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var base_idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var orig_pts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var pts: PackedVector3Array = orig_pts.duplicate()
			var target_tris: int = int(max_tris[s]) if s < max_tris.size() else (base_idx.size() / 3)
			var chosen_idx: PackedInt32Array = base_idx
			if target_tris < 0:
				var stride := absi(target_tris)
				var card_scale := clampf(pow(float(stride), 0.34), 1.0, 2.75)
				var quad_count := base_idx.size() / 6
				if quad_count > 0:
					var sampled := PackedInt32Array()
					sampled.resize(((quad_count + stride - 1) / stride) * 6)
					var w := 0
					var scaled_verts := {}
					for q in range(0, quad_count, stride):
						var base_off := q * 6
						var i0 := base_idx[base_off]
						var i1 := base_idx[base_off + 1]
						var i2 := base_idx[base_off + 2]
						var i3 := base_idx[base_off + 3]
						var i4 := base_idx[base_off + 4]
						var i5 := base_idx[base_off + 5]
						sampled[w] = i0
						sampled[w + 1] = i1
						sampled[w + 2] = i2
						sampled[w + 3] = i3
						sampled[w + 4] = i4
						sampled[w + 5] = i5
						w += 6
						if card_scale > 1.01:
							if (orig_pts[i0] - orig_pts[i3]).length_squared() < 0.16:
								var center := (orig_pts[i0] + orig_pts[i1] + orig_pts[i2] + orig_pts[i3] + orig_pts[i4] + orig_pts[i5]) / 6.0
								for vi in [i0, i1, i2, i3, i4, i5]:
									if not scaled_verts.has(vi):
										scaled_verts[vi] = true
										pts[vi] = center + (orig_pts[vi] - center) * card_scale
							else:
								var c_a := (orig_pts[i0] + orig_pts[i1] + orig_pts[i2]) / 3.0
								for vi in [i0, i1, i2]:
									if not scaled_verts.has(vi):
										scaled_verts[vi] = true
										pts[vi] = c_a + (orig_pts[vi] - c_a) * card_scale
								var c_b := (orig_pts[i3] + orig_pts[i4] + orig_pts[i5]) / 3.0
								for vi in [i3, i4, i5]:
									if not scaled_verts.has(vi):
										scaled_verts[vi] = true
										pts[vi] = c_b + (orig_pts[vi] - c_b) * card_scale
					sampled.resize(w)
					chosen_idx = sampled
			elif target_tris < (base_idx.size() / 3):
				if generate:
					var single := ArrayMesh.new()
					single.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
					var imp := ImporterMesh.from_mesh(single)
					if imp.get_surface_lod_count(0) == 0:
						imp.generate_lods(60.0, 60.0, [])
					var lod_count := imp.get_surface_lod_count(0)
					for l in lod_count:
						var lod_idx: PackedInt32Array = imp.get_surface_lod_indices(0, l)
						var tris := lod_idx.size() / 3
						if tris > 0:
							chosen_idx = lod_idx
							if tris <= target_tris:
								break
				var cur_tris := chosen_idx.size() / 3
				if cur_tris > target_tris and target_tris > 0:
					var areas := PackedFloat32Array()
					areas.resize(cur_tris)
					for t in cur_tris:
						var off := t * 3
						var p0 := orig_pts[chosen_idx[off]]
						var p1 := orig_pts[chosen_idx[off + 1]]
						var p2 := orig_pts[chosen_idx[off + 2]]
						areas[t] = (p1 - p0).cross(p2 - p0).length_squared()
					var sorted_areas := areas.duplicate()
					sorted_areas.sort()
					var min_area2: float = sorted_areas[cur_tris - target_tris]
					var filtered := PackedInt32Array()
					filtered.resize(target_tris * 3)
					var fw := 0
					for t in cur_tris:
						if areas[t] >= min_area2 and fw < target_tris * 3:
							var off := t * 3
							filtered[fw] = chosen_idx[off]
							filtered[fw + 1] = chosen_idx[off + 1]
							filtered[fw + 2] = chosen_idx[off + 2]
							fw += 3
					if fw > 0:
						filtered.resize(fw)
						chosen_idx = filtered
			arrays[Mesh.ARRAY_VERTEX] = pts
			if chosen_idx.size() < base_idx.size() and arrays[Mesh.ARRAY_BONES] == null:
				var remap := PackedInt32Array()
				remap.resize(pts.size())
				remap.fill(-1)
				var new_idx := PackedInt32Array()
				new_idx.resize(chosen_idx.size())
				var order := PackedInt32Array()
				for i in chosen_idx.size():
					var old_v := chosen_idx[i]
					var new_v := remap[old_v]
					if new_v < 0:
						new_v = order.size()
						remap[old_v] = new_v
						order.append(old_v)
					new_idx[i] = new_v
				var new_pts := PackedVector3Array()
				new_pts.resize(order.size())
				for i in order.size():
					new_pts[i] = pts[order[i]]
				arrays[Mesh.ARRAY_VERTEX] = new_pts
				if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array and (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == pts.size():
					var old_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					var new_n := PackedVector3Array()
					new_n.resize(order.size())
					for i in order.size():
						new_n[i] = old_n[order[i]]
					arrays[Mesh.ARRAY_NORMAL] = new_n
				if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array and (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() == pts.size() * 4:
					var old_t: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
					var new_t := PackedFloat32Array()
					new_t.resize(order.size() * 4)
					for i in order.size():
						var src := order[i] * 4
						var dst := i * 4
						new_t[dst] = old_t[src]
						new_t[dst + 1] = old_t[src + 1]
						new_t[dst + 2] = old_t[src + 2]
						new_t[dst + 3] = old_t[src + 3]
					arrays[Mesh.ARRAY_TANGENT] = new_t
				if arrays[Mesh.ARRAY_COLOR] is PackedColorArray and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() == pts.size():
					var old_c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
					var new_c := PackedColorArray()
					new_c.resize(order.size())
					for i in order.size():
						new_c[i] = old_c[order[i]]
					arrays[Mesh.ARRAY_COLOR] = new_c
				if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array and (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == pts.size():
					var old_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					var new_uv := PackedVector2Array()
					new_uv.resize(order.size())
					for i in order.size():
						new_uv[i] = old_uv[order[i]]
					arrays[Mesh.ARRAY_TEX_UV] = new_uv
				if arrays[Mesh.ARRAY_TEX_UV2] is PackedVector2Array and (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size() == pts.size():
					var old_uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
					var new_uv2 := PackedVector2Array()
					new_uv2.resize(order.size())
					for i in order.size():
						new_uv2[i] = old_uv2[order[i]]
					arrays[Mesh.ARRAY_TEX_UV2] = new_uv2
				arrays[Mesh.ARRAY_INDEX] = new_idx
			else:
				arrays[Mesh.ARRAY_INDEX] = chosen_idx
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(s, _live_botanical_material(mesh.surface_get_material(s)))
		live_lod_cache[key] = out
		return out

	static func refresh_vegetation(scenery: Node3D, state: Dictionary) -> void:
		# Only soft, unsaved decoration is hidden. Natural collision geometry
		# and the confirmed construction facts remain untouched.
		var live_batch := is_live_play(state)
		var volumes := _construction_volumes(state)
		for spec in Surface.fir_specs() + Surface.broadleaf_specs():
			var source: Dictionary = state.get("hand_sources", {}).get(spec.id, {})
			if source.get("remaining", 1) == 0:
				var radius := 0.5 if str(spec.id).begins_with("fir_") else 0.8
				volumes.append(AABB(spec.center - Vector3(radius, 0.1, radius),
					Vector3(radius * 2.0, 0.8, radius * 2.0)))
		for name in ["GroundFoliage", "ForegroundBank", "PineUnderstory"]:
			var patch := scenery.get_node_or_null(name) as MultiMeshInstance3D
			if patch != null and live_batch:
				patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_refresh_plant_patch(patch, volumes)
			if patch != null and name in ["GroundFoliage", "ForegroundBank"]:
				patch.visible = not live_batch
		var shrubs := scenery.get_node_or_null("ShrubUnderstory")
		if shrubs != null:
			for patch: MultiMeshInstance3D in shrubs.get_children():
				_refresh_plant_patch(patch, volumes)
		var meadow := scenery.get_node_or_null("MeadowPatches")
		if meadow != null:
			var batch_meadow: bool = live_batch
			var q_bufs: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
			var q_bounds: Array[AABB] = [AABB(), AABB(), AABB(), AABB()]
			var q_counts: Array[int] = [0, 0, 0, 0]
			var first_patch: MultiMeshInstance3D = null
			if batch_meadow:
				for extra_name in ["GroundFoliage", "ForegroundBank"]:
					var extra := scenery.get_node_or_null(extra_name) as MultiMeshInstance3D
					if extra != null and extra.multimesh != null and extra.multimesh.instance_count > 0:
						if first_patch == null:
							first_patch = extra
						var ebuf: PackedFloat32Array = extra.multimesh.buffer
						var emesh_aabb: AABB = extra.multimesh.mesh.get_aabb()
						for offset in range(0, ebuf.size(), 16):
							var s := ebuf.slice(offset, offset + 16)
							var qi: int = (1 if s[3] >= 0.0 else 0) + (2 if s[11] >= 0.0 else 0)
							q_bufs[qi].append_array(s)
							var basis := Basis(Vector3(s[0], s[4], s[8]), Vector3(s[1], s[5], s[9]), Vector3(s[2], s[6], s[10]))
							var env: AABB = Transform3D(basis, Vector3(s[3], s[7], s[11])) * emesh_aabb
							q_bounds[qi] = env if q_counts[qi] == 0 else q_bounds[qi].merge(env)
							q_counts[qi] += 1
			for child in meadow.get_children():
				if not child is MultiMeshInstance3D or child.name.begins_with("MeadowPatchesBatch"):
					continue
				var patch := child as MultiMeshInstance3D
				_refresh_plant_patch(patch, volumes)
				patch.visible = not batch_meadow
				if batch_meadow and patch.multimesh != null and patch.multimesh.instance_count > 0:
					if first_patch == null:
						first_patch = patch
					var patch_buf: PackedFloat32Array = patch.multimesh.buffer
					var pos: Vector3 = patch.position
					var mesh_aabb: AABB = patch.multimesh.mesh.get_aabb()
					for offset in range(0, patch_buf.size(), 16):
						var s := patch_buf.slice(offset, offset + 16)
						s[3] += pos.x
						s[7] += pos.y
						s[11] += pos.z
						var qi: int = (1 if s[3] >= 0.0 else 0) + (2 if s[11] >= 0.0 else 0)
						q_bufs[qi].append_array(s)
						var basis := Basis(Vector3(s[0], s[4], s[8]), Vector3(s[1], s[5], s[9]), Vector3(s[2], s[6], s[10]))
						var env: AABB = Transform3D(basis, Vector3(s[3], s[7], s[11])) * mesh_aabb
						q_bounds[qi] = env if q_counts[qi] == 0 else q_bounds[qi].merge(env)
						q_counts[qi] += 1
			for qi in 4:
				var bname := "MeadowPatchesBatch%d" % qi
				var batch_node := meadow.get_node_or_null(bname) as MultiMeshInstance3D
				if batch_meadow and q_counts[qi] > 0 and first_patch != null:
					if batch_node == null:
						batch_node = MultiMeshInstance3D.new()
						batch_node.name = bname
						var mm := MultiMesh.new()
						mm.transform_format = MultiMesh.TRANSFORM_3D
						mm.use_colors = true
						mm.mesh = first_patch.multimesh.mesh
						batch_node.multimesh = mm
						batch_node.material_override = first_patch.material_override
						batch_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						batch_node.visibility_range_end = 42.0
						meadow.add_child(batch_node)
					batch_node.multimesh.instance_count = q_counts[qi]
					batch_node.multimesh.buffer = q_bufs[qi]
					batch_node.multimesh.custom_aabb = q_bounds[qi]
					batch_node.visible = true
				elif batch_node != null:
					batch_node.visible = false

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
		instances.mesh = _live_lod_mesh(pine_cluster_mesh, [800, -24], false)
		instances.instance_count = count
		instances.buffer = buffer
		instances.custom_aabb = bounds
		patch.multimesh = instances
		patch.visibility_range_end = 32.0
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.set_meta("candidate_buffer", buffer)
		return patch

	static func _bank_firs() -> Node3D:
		var group := Node3D.new()
		group.name = "BankFirs"
		var specs: Array[Dictionary] = Surface.fir_specs()
		if specs.is_empty():
			return group
		var mesh: ArrayMesh = _live_lod_mesh(Surface.fir_mesh(), [1500, -32, 800], false)
		for spec in specs:
			var tree := MeshInstance3D.new()
			tree.name = spec.id
			tree.mesh = mesh
			tree.position = spec.center
			tree.basis = spec.basis.scaled_local(Vector3.ONE * spec.scale)
			tree.visibility_range_end = 65.0
			tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			group.add_child(tree)
		return group

	static func _bank_broadleaf() -> Node3D:
		var group := Node3D.new()
		group.name = "BankBroadleaf"
		var mesh: ArrayMesh = _live_lod_mesh(Surface.broadleaf_mesh(), [1200, -24, 1800], false)
		if mesh == null:
			return group
		for spec in Surface.broadleaf_specs():
			var tree := MeshInstance3D.new()
			tree.name = spec.id
			tree.mesh = mesh
			tree.position = spec.center
			tree.basis = spec.basis.scaled_local(Vector3.ONE * spec.scale)
			tree.visibility_range_end = 70.0
			tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
			instances.mesh = _live_lod_mesh(mesh, [-16, -16, 200], false)
			instances.instance_count = count
			instances.buffer = buffer
			instances.custom_aabb = bounds
			var patch := MultiMeshInstance3D.new()
			patch.name = "TallShrubs" if variant == 0 else "LowShrubs"
			patch.multimesh = instances
			patch.visibility_range_end = 34.0
			patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		instances.mesh = _live_lod_mesh(fern_cluster_mesh, [-4])
		instances.instance_count = count
		instances.buffer = buffer
		instances.custom_aabb = bounds
		var ferns := MultiMeshInstance3D.new()
		ferns.name = "FernClumps"
		ferns.multimesh = instances
		ferns.material_override = _live_botanical_material(fern_finish)
		ferns.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ferns.visibility_range_end = 62.0
		group.add_child(ferns)
		return group

	static func _rock_outcrops() -> MultiMeshInstance3D:
		if rock_boulder_mesh == null:
			rock_boulder_mesh = Surface.SOURCE_OUTCROP_MESH
		var finish := _live_botanical_material(stone_material()) as StandardMaterial3D
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
		instances.mesh = _live_lod_mesh(rock_boulder_mesh, [250])
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
		outcrops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return outcrops

	static func _ore_ground_material() -> StandardMaterial3D:
		if ore_ground_finish == null:
			var image := ProductionVisuals.read_image("res://opening/assets/mineral-outcrop/field-gravel.jpg")
			if image == null or image.generate_mipmaps() != OK:
				push_error("The broad ore field requires its prepared gravel surface.")
				return null
			ore_ground_finish = StandardMaterial3D.new()
			ore_ground_finish.albedo_texture = ImageTexture.create_from_image(image)
			ore_ground_finish.albedo_color = Color("ddd4ca")
			ore_ground_finish.vertex_color_use_as_albedo = true
			ore_ground_finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ore_ground_finish.cull_mode = BaseMaterial3D.CULL_DISABLED
			ore_ground_finish.roughness = 1.0
			ore_ground_finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return ore_ground_finish

	static func _ore_stone_material() -> ShaderMaterial:
		if ore_stone_finish != null:
			return ore_stone_finish
		var source := ORE_FIELD_STONES.instantiate() as Node3D
		var meshes := source.find_children("*", "MeshInstance3D", true, false)
		var scan := meshes[0] as MeshInstance3D if not meshes.is_empty() else null
		var material: StandardMaterial3D = null
		if scan != null:
			material = scan.mesh.surface_get_material(0) as StandardMaterial3D
		if material == null or material.albedo_texture == null or material.normal_texture == null:
			push_error("The broad ore field requires its separate stone textures.")
			source.free()
			return null
		ore_stone_finish = ShaderMaterial.new()
		ore_stone_finish.shader = ORE_FIELD_BOULDER_SHADER
		ore_stone_finish.set_shader_parameter("albedo_map", material.albedo_texture)
		ore_stone_finish.set_shader_parameter("normal_map", material.normal_texture)
		ore_stone_finish.set_shader_parameter("copper_cover", 0.45)
		ore_stone_finish.set_shader_parameter("copper_strength", 0.78)
		ore_stone_finish.set_shader_parameter("mineral_base_height", 0.08)
		ore_stone_finish.set_shader_parameter("mineral_top_height", 0.42)
		source.free()
		return ore_stone_finish

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
							var span := Vector2((point.x - float(center[0])) / 3.7,
									(point.y - float(center[2])) / 3.2).length()
							var weight: float = 1.0 - smoothstep(0.23, 0.93, span + roughness * 0.19)
							local_patch = maxf(local_patch, weight * sqrt(float(balances.get(
								str(region.get("id", "")), 0.0))))
						var grain: float = smoothstep(-0.45, 0.50, fleck + roughness * 0.25)
						var bank: float = Surface.river_center_x(point.y) + Surface.channel_half_width(point.y)
						var opacity: float = smoothstep(0.0, 1.2, edge + roughness * 0.6) \
							* smoothstep(0.12, 0.85, point.x - bank) \
							* (0.12 + 0.20 * fraction + 0.52 * local_patch) * (0.16 + 0.84 * grain)
						surface.set_normal(Surface.normal(point.x, point.y))
						surface.set_uv(point * 0.55)
						surface.set_color(Color(1.0, 1.0, 1.0, opacity))
						surface.add_vertex(Vector3(point.x,
							Surface.height_at(point.x, point.y) + 0.028, point.y))
		surface.generate_tangents()
		var soil := MeshInstance3D.new()
		soil.name = "CopperBearingGround"
		soil.mesh = surface.commit()
		soil.material_override = _ore_ground_material()
		soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(soil)
		var stone_finish := _ore_stone_material()
		if stone_finish == null:
			return root
		var principal_scales := [
			Vector3(0.94, 0.82, 0.93), Vector3(0.78, 0.70, 0.82),
			Vector3(0.91, 0.79, 0.90), Vector3(0.75, 0.69, 0.78),
			Vector3.ZERO, Vector3(0.96, 0.83, 0.94)]
		var rock_layout := [
			[Vector2(-0.88, -0.45), 0.88, 0.18],
			[Vector2(0.35, 0.08), 1.08, -0.36],
			[Vector2(1.05, -0.56), 0.75, 0.72],
			[Vector2(-0.28, 0.78), 0.78, -0.62],
			[Vector2(0.92, 0.85), 0.67, 0.38],
			[Vector2(-1.08, 0.65), 0.76, 1.08],
			[Vector2(0.05, -0.88), 0.71, -0.94]]
		var batch_stones: bool = is_live_play(state)
		var stone_vertices := PackedVector3Array()
		var stone_normals := PackedVector3Array()
		var stone_tangents := PackedFloat32Array()
		var stone_uv := PackedVector2Array()
		var stone_uv2 := PackedVector2Array()
		var stone_colors := PackedColorArray()
		var stone_indices := PackedInt32Array()
		for region: Dictionary in regions:
			if int(region.get("remaining", 0)) <= 0:
				continue
			var center: Array = region.get("position", [])
			if center.size() != 3:
				continue
			var region_index: int = int(str(region.get("id", "")).get_slice("-region-", 1))
			# Region 4 retains the preexisting physical bank rock as its principal exposure.
			var x: float = float(center[0])
			var z: float = float(center[2])
			var bank: float = Surface.river_center_x(z) + Surface.channel_half_width(z)
			x = maxf(x, bank + 2.4)
			var facing: float = [-0.28, 0.45, 0.22, -0.38, 0.15, 0.5][region_index]
			if region_index != 4:
				var patch: Node3D = ORE_FIELD_STONES.instantiate()
				patch.name = "StoneAndGravelRegion%d" % region_index
				patch.position = Vector3(x, Surface.height_at(x, z), z)
				patch.rotation.y = facing
				patch.scale = principal_scales[region_index]
				var patch_meshes := patch.find_children("*", "MeshInstance3D", true, false)
				if patch_meshes.size() != rock_layout.size():
					push_error("The broad ore field requires its seven separate stone meshes.")
					return root
				for number in range(patch_meshes.size()):
					var scan := patch_meshes[number] as MeshInstance3D
					var rock: Array = rock_layout[number]
					var local: Vector2 = rock[0].rotated(float(region_index) * 0.23)
					var world_offset: Vector2 = local.rotated(facing)
					scan.name = "Mesh" if number == 0 else "Stone%d" % number
					scan.position = Vector3(local.x,
							Surface.height_at(x + world_offset.x, z + world_offset.y) -
							Surface.height_at(x, z) - 0.10, local.y)
					scan.rotation.y = float(rock[2]) + float(region_index) * 0.16
					var size: float = float(rock[1])
					scan.scale = Vector3(size, size * 0.74, size)
					scan.material_override = stone_finish
					scan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					if batch_stones and scan.mesh != null:
						scan.visible = false
						var pose: Transform3D = patch.transform * scan.transform
						var normal_basis: Basis = pose.basis.inverse().transposed()
						var lod_mesh := _live_lod_mesh(scan.mesh as ArrayMesh, [200])
						var arrays := lod_mesh.surface_get_arrays(0)
						var pts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
						var nrms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
						var tgts: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
						var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
						var idxs: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
						var start := stone_vertices.size()
						for i in pts.size():
							var pt := pts[i]
							stone_vertices.append(pose * pt)
							stone_normals.append((normal_basis * nrms[i]).normalized())
							var t_dir := (pose.basis * Vector3(tgts[i * 4], tgts[i * 4 + 1], tgts[i * 4 + 2])).normalized()
							stone_tangents.append(t_dir.x)
							stone_tangents.append(t_dir.y)
							stone_tangents.append(t_dir.z)
							stone_tangents.append(tgts[i * 4 + 3])
							stone_uv.append(uvs[i])
							stone_uv2.append(Vector2(pt.y, 0.0))
							stone_colors.append(Color(1.0, 1.0, 1.0, 0.0))
						for idx in idxs:
							stone_indices.append(start + idx)
				root.add_child(patch)
		if batch_stones and not stone_vertices.is_empty():
			var stone_arrays := []
			stone_arrays.resize(Mesh.ARRAY_MAX)
			stone_arrays[Mesh.ARRAY_VERTEX] = stone_vertices
			stone_arrays[Mesh.ARRAY_NORMAL] = stone_normals
			stone_arrays[Mesh.ARRAY_TANGENT] = stone_tangents
			stone_arrays[Mesh.ARRAY_TEX_UV] = stone_uv
			stone_arrays[Mesh.ARRAY_TEX_UV2] = stone_uv2
			stone_arrays[Mesh.ARRAY_COLOR] = stone_colors
			stone_arrays[Mesh.ARRAY_INDEX] = stone_indices
			var stone_batch_mesh := ArrayMesh.new()
			stone_batch_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, stone_arrays)
			var stone_batch_node := MeshInstance3D.new()
			stone_batch_node.name = "OreFieldStonesBatch"
			stone_batch_node.mesh = stone_batch_mesh
			stone_batch_node.material_override = stone_finish
			stone_batch_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(stone_batch_node)
		return root

	static func build(parent: Node3D) -> Node3D:
		if is_live_play():
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
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
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
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
		terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
