extends SceneTree
## Offline asset preparation. No game, authority, scene or desktop starts.
const PINE_PINS := {
	"textures/pine_sapling_small_twig_diff_1k.jpg": "54af7d6fb664b5a38bcb118b557bc50e01e86ec54d6f1a573c3e32c649a53362",
	"textures/pine_sapling_small_bark_nor_gl_1k.jpg": "05c46455531781b6cf18cae0648cf627f60ee942adaa8bcbfd1592fc2506a9e0",
	"textures/pine_sapling_small_twig_arm_1k.jpg": "2eb0aa44124b5a4ae9401e00b23b3c916f4c3f421616ce1bb932f248fc061288",
	"textures/pine_sapling_small_bark_arm_1k.jpg": "336a4680cd571b6076b67afee2310b290b8900d9d126eb39ec1ae92e95be2ea9",
	"textures/pine_sapling_small_bark_diff_1k.jpg": "5c76836b01c3536fa0e24207b67bf4f3315b53ebe2b4ecc6f08dfcf3f8d74929",
	"textures/pine_sapling_small_twig_nor_gl_1k.jpg": "76af87821d7ff00e25768d5d97a449394fe64a21ae55d099da7f5ed46d9098c8",
	"pine_sapling_small.bin": "b4d2fc73d53f1d8717eb5ef9a2c66957d2a53152787e543aace88fcd6fca94ef",
	"pine_sapling_small_1k.gltf": "f358c01926861dd082f32dba60f7c9fba232b585a985cf38c0d2229eecf4bc48"
}
const SHRUB_PINS := {
	"searsia_lucida_1k.gltf": "ebdc8d776c058b9a6f9a04c57ca0540368531febd3bfa007d2e2d8af8d368f67",
	"searsia_lucida.bin": "e0be13cac215725de1f8438d96e1010049d655512a0608c36eabe2ba5abff851",
	"textures/searsia_lucida_diff_1k.jpg": "5d99ed106c6629d91cf5d29f067c1fd10ff4894df40634abb6c4694c59d3c764",
	"textures/searsia_lucida_alpha_1k.png": "2306c054f7188aa34fdbfd1be725899159c82730c1a5c14fcc56ef7353107006",
	"textures/searsia_lucida_nor_gl_1k.jpg": "d28556973d1cbf96c5327341be7a71da66ac63ed97b31f22162376a9f95b0041",
	"textures/searsia_lucida_arm_1k.jpg": "f7bf2359e932d3633ac99a5f9e6a507eda439b64937eb6774585da3d0fb6d3d7"
}

func prepare_rgb_map(path: String, role: String, target_size: int = 0) -> Image:
	var image := Image.load_from_file(path)
	if image == null or image.get_size() != Vector2i(1024, 1024):
		fail("Unexpected source image: " + path)
		return null
	image.convert(Image.FORMAT_RGBF)
	if role == "albedo":
		# Resample photographed color in linear light, then encode sRGB bytes.
		for y in range(1024):
			for x in range(1024):
				image.set_pixel(x, y, image.get_pixel(x, y).srgb_to_linear())
	var dimension := target_size if target_size > 0 else (384 if role == "albedo" else 256)
	image.resize(dimension, dimension, Image.INTERPOLATE_LANCZOS)
	var bytes := PackedByteArray()
	bytes.resize(image.get_width() * image.get_height() * 3)
	var maximum_normal_error := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if role == "albedo":
				color = color.linear_to_srgb()
			elif role == "normal":
				var normal := Vector3(color.r, color.g, color.b) * 2.0 - Vector3.ONE
				if not normal.is_finite() or normal.length_squared() < 0.000001:
					fail("Invalid source normal.")
					return null
				normal = normal.normalized()
				color = Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5)
			var at := (y * image.get_width() + x) * 3
			bytes[at] = nearest_byte(color.r)
			bytes[at + 1] = nearest_byte(color.g)
			bytes[at + 2] = nearest_byte(color.b)
			if role == "normal":
				var returned := Vector3(bytes[at], bytes[at + 1], bytes[at + 2]) / 255.0 * 2.0 - Vector3.ONE
				maximum_normal_error = maxf(maximum_normal_error, absf(returned.length() - 1.0))
	if maximum_normal_error > 0.01:
		fail("Prepared normals exceed the encoding bound.")
		return null
	var prepared := Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8, bytes)
	if prepared.generate_mipmaps(role == "normal") != OK:
		fail("Cannot generate source mipmaps.")
		return null
	return prepared

func prepare_pine(family: String, output: String) -> void:
	if not output.is_absolute_path() or output.begins_with(ProjectSettings.globalize_path("res://")) or DirAccess.dir_exists_absolute(output):
		fail("Use a fresh external pine output directory.")
		return
	for file in PINE_PINS:
		if FileAccess.get_sha256(family.path_join("source").path_join(file)) != PINE_PINS[file]:
			fail("Refuse an unpinned pine source: " + file)
			return
	var source_path := family.path_join("source/pine_sapling_small_1k.gltf")
	var source_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	if source_json.meshes[0].name != "pine_sapling_small_b":
		fail("The declared pine mesh changed.")
		return
	var document := GLTFDocument.new()
	var imported := GLTFState.new()
	imported.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(source_path, imported) != OK:
		fail("Cannot import the pinned pine catalogue.")
		return
	var mesh: ArrayMesh = imported.get_meshes()[0].mesh.get_mesh()
	if mesh == null or mesh.get_surface_count() != 2 or mesh.get_blend_shape_count() != 0:
		fail("Expected two static pine surfaces.")
		return
	if DirAccess.make_dir_absolute(output) != OK:
		fail("Cannot create pine output.")
		return
	var report := {"status": "pass", "selected_mesh": "pine_sapling_small_b", "scale": 1.0,
		"catalogue_translation_omitted": [1, 0, 0], "surfaces": []}
	for surface in range(2):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_INDEX].size() != (1458 if surface == 0 else 365247) or (mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0:
			fail("Pine import changed the complete selected native buffers.")
			return
		var finish := mesh.surface_get_material(surface).duplicate(true) as StandardMaterial3D
		if finish == null:
			fail("Expected the pinned pine standard material.")
			return
		var role := "bark" if surface == 0 else "twig"
		var images: Dictionary = {}
		for map_role in ["albedo", "normal", "arm"]:
			var suffix: String = {"albedo": "diff", "normal": "nor_gl", "arm": "arm"}[map_role]
			var image := prepare_rgb_map(family.path_join("source/textures").path_join("pine_sapling_small_" + role + "_" + suffix + "_1k.jpg"), map_role)
			if image == null:
				return
			images[map_role] = image
			if image.save_png(output.path_join(role + "_" + map_role + ".png")) != OK:
				fail("Cannot retain prepared pine pixels.")
				return
		# Keep importer-compressed vertex buffers. Rebuilding decoded arrays
		# needlessly expands storage and adds another normal/tangent packing.
		var packed := ImageTexture.create_from_image(images.arm)
		finish.albedo_texture = ImageTexture.create_from_image(images.albedo)
		finish.normal_texture = ImageTexture.create_from_image(images.normal)
		finish.roughness_texture = packed
		finish.metallic_texture = packed
		finish.ao_texture = packed if finish.ao_enabled else null
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mesh.surface_set_material(surface, finish)
		report.surfaces.append({"format": mesh.surface_get_format(surface),
			"vertices": arrays[Mesh.ARRAY_VERTEX].size(), "indices": arrays[Mesh.ARRAY_INDEX].size(),
			"metallic": finish.metallic, "roughness": finish.roughness,
			"specular": finish.metallic_specular, "ao": finish.ao_enabled})
	var path := output.path_join("pine_sapling.res")
	if ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES) != OK:
		fail("Cannot serialize the pine resource.")
		return
	var loaded := ResourceLoader.load(path, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if loaded == null or not ResourceLoader.get_dependencies(path).is_empty():
		fail("Pine package has an invalid mesh or external dependency.")
		return
	for surface in range(2):
		if mesh.surface_get_arrays(surface) != loaded.surface_get_arrays(surface):
			fail("Native compressed pine arrays changed during resource roundtrip.")
			return
		var a := mesh.surface_get_material(surface) as StandardMaterial3D
		var b := loaded.surface_get_material(surface) as StandardMaterial3D
		for field in ["albedo_texture", "normal_texture", "roughness_texture"]:
			var before: Image = a.get(field).get_image()
			var after: Image = b.get(field).get_image()
			if before.get_data() != after.get_data() or before.get_format() != after.get_format() or before.get_size() != after.get_size():
				fail("Embedded pine pixels changed during resource roundtrip.")
				return
	var size := FileAccess.get_file_as_bytes(path).size()
	report["resource_bytes"] = size
	report["resource_sha256"] = FileAccess.get_sha256(path)
	report["exact_native_array_roundtrip"] = true
	report["exact_prepared_pixel_roundtrip"] = true
	report["external_dependencies"] = 0
	if size > 4194304:
		report.status = "fail"
		report["finding"] = "The complete native resource exceeds its four-MiB component bound."
	var result := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	result.store_string(JSON.stringify(report, "  ") + "\n")
	result.close()
	print(JSON.stringify(report))
	quit(0 if report.status == "pass" else 1)

func prepare_forest_ground(family: String) -> void:
	var output := family.path_join("prepared-ground")
	if not family.is_absolute_path() or output.begins_with(ProjectSettings.globalize_path("res://")) or DirAccess.dir_exists_absolute(output):
		fail("Use the declared external family and preserve earlier ground outputs.")
		return
	var pins := {"grass_color.jpg": "b9b6d61bc3b6137b868a3447eef18737896acd26d58fe2f4b83ce8c0e9d3f8ad",
		"grass_normal_gl.jpg": "eef0b56db5f00a6fcb3d0e0f8463e4e141e88aa85b26527a04d617b75a4ab5d2",
		"grass_ao.jpg": "a5e6e6a1c4329562e99f009313f09e44dd179dedbfb5dd679feeaf17ca122ab9",
		"grass_roughness.jpg": "8810effd44756341170d551501b7d0c645dc2395dbce46a8c7f1e61045258a06"}
	for file in pins:
		if FileAccess.get_sha256(family.path_join(file)) != pins[file]:
			fail("Refuse changed qualified ground input: " + file)
			return
	if DirAccess.make_dir_absolute(output) != OK:
		fail("Cannot create the fresh ground output.")
		return
	var report := {"status": "pass", "asset": "ambientCG Grass001", "maps": {},
		"source_extent_metres": 1.4, "source_scene_imported": false, "limits": "No scene, collision, renderer or graphical-quality result."}
	var total := 0
	for role in ["albedo", "normal", "arm"]:
		var source_name: String = {"albedo": "grass_color.jpg", "normal": "grass_normal_gl.jpg", "arm": "grass_ao.jpg"}[role]
		var image := Image.load_from_file(family.path_join(source_name))
		if image == null or image.get_size() != Vector2i(1024, 1024):
			fail("Unexpected ground source image: " + role)
			return
		var roughness: Image
		if role == "arm":
			roughness = Image.load_from_file(family.path_join("grass_roughness.jpg"))
			if roughness == null or roughness.get_size() != Vector2i(1024, 1024):
				fail("Unexpected ground roughness source image.")
				return
			roughness.convert(Image.FORMAT_RGBF)
			roughness.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		var source_format := image.get_format()
		var bytes := PackedByteArray()
		var maximum_normal_error := 0.0
		if role == "albedo":
			# Preserve decoded source color: no resize, gamma operation or lossy re-encoding.
			image.convert(Image.FORMAT_RGB8)
			bytes = image.get_data()
		else:
			image.convert(Image.FORMAT_RGBF)
			image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
			bytes.resize(512 * 512 * 3)
			for y in range(512):
				for x in range(512):
					var color := image.get_pixel(x, y)
					if role == "arm":
						color = Color(color.r, roughness.get_pixel(x, y).r, 0.0)
					if role == "normal":
						var normal := Vector3(color.r, color.g, color.b) * 2.0 - Vector3.ONE
						if not normal.is_finite() or normal.length_squared() < 0.000001:
							fail("Invalid source ground normal.")
							return
						normal = normal.normalized()
						color = Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5)
					var at := (y * 512 + x) * 3
					bytes[at] = nearest_byte(color.r)
					bytes[at + 1] = nearest_byte(color.g)
					bytes[at + 2] = nearest_byte(color.b)
					if role == "normal":
						var returned := Vector3(bytes[at], bytes[at + 1], bytes[at + 2]) / 255.0 * 2.0 - Vector3.ONE
						maximum_normal_error = maxf(maximum_normal_error, absf(returned.length() - 1.0))
			image = Image.create_from_data(512, 512, false, Image.FORMAT_RGB8, bytes)
		if maximum_normal_error >= 0.01:
			fail("Prepared ground normals exceed the encoding bound.")
			return
		var filename: String = {"albedo": "ground_albedo.webp", "normal": "ground_normal_gl.webp", "arm": "ground_arm.webp"}[role]
		var path := output.path_join(filename)
		if image.save_webp(path, false, 1.0) != OK:
			fail("Cannot save lossless ground image: " + role)
			return
		var decoded := Image.load_from_file(path)
		if decoded == null:
			fail("Cannot decode prepared ground image.")
			return
		decoded.convert(Image.FORMAT_RGB8)
		if decoded.get_size() != image.get_size() or decoded.get_data() != bytes:
			fail("Ground WebP changed the declared prepared RGB bytes.")
			return
		var size := FileAccess.get_file_as_bytes(path).size()
		total += size
		report.maps[role] = {"file": filename, "bytes": size, "sha256": FileAccess.get_sha256(path),
			"source_decoded_format": source_format, "extent": decoded.get_width(), "decoded_rgb_exact": true,
			"maximum_normal_length_error": maximum_normal_error}
	report["prepared_bytes"] = total
	if total > 4194304:
		report.status = "fail"
		report["finding"] = "The prepared surface exceeds its four-MiB component allocation."
	var result := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	result.store_string(JSON.stringify(report, "  ") + "\n")
	result.close()
	print(JSON.stringify(report))
	quit(0 if report.status == "pass" else 1)

func prepare_fir(family: String, output: String) -> void:
	if not output.is_absolute_path() or output.begins_with(ProjectSettings.globalize_path("res://")) or DirAccess.dir_exists_absolute(output):
		fail("Use a fresh external fir output directory.")
		return
	var pins := {"fir_sapling_medium_1k.gltf": "2e80cd49d716c99bdead5a42aa6441e89443044d9a0edc31b56b5dbf87fc41de",
		"fir_sapling_medium.bin": "e3f3fabcaa1bacfc8b1feca5e6500b13c63a0e45cd812e663d01d31b042d73b1",
		"textures/fir_sapling_medium_branches_nor_gl_1k.jpg": "6a570ab53ab2249ecdfa93e7d3b9a8a2cb1a8ad391400e5a64c708914779b2c3",
		"textures/fir_sapling_medium_branches_diff_1k.jpg": "a5d25150ba1bee10008c039f98aa3c73b4477a404d6715c511ca9b5b0f4a9077",
		"textures/fir_sapling_medium_branches_arm_1k.jpg": "95d4e9e62cd309fbc38a175e2306379c76c062425b09c0fb72c5b7356a719123",
		"textures/fir_sapling_medium_twigs_nor_gl_1k.jpg": "d470dc39b1d02bbeba06feb0ad818680ef3c24623b4db597270301a5fb8c9369",
		"textures/fir_sapling_medium_twigs_diff_1k.jpg": "db1113d37d68d960b84eb14ce67a4022d02bf10d6f0c078d689063f6296eaa1d",
		"textures/fir_sapling_medium_twigs_arm_1k.jpg": "d66c81fc073ee7ea97a76b6da2399769f16944e50ef0e007f09c95619f597c79"}
	for file in pins:
		if FileAccess.get_sha256(family.path_join("source").path_join(file)) != pins[file]:
			fail("Refuse changed fir source: " + file)
			return
	var source_path := family.path_join("source/fir_sapling_medium_1k.gltf")
	var descriptor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	if descriptor.nodes[1].name != "fir_sapling_medium_b_LOD0" or descriptor.nodes[1].mesh != 1:
		fail("The selected complete local fir changed.")
		return
	var document := GLTFDocument.new()
	var imported := GLTFState.new()
	imported.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(source_path, imported) != OK:
		fail("Cannot import the pinned fir catalogue.")
		return
	var source_mesh: ImporterMesh = imported.get_meshes()[1].mesh
	if source_mesh == null or source_mesh.get_surface_count() != 3:
		fail("Fir requires its three original source surfaces.")
		return
	# A fresh importer guarantees that get_mesh() has not cached a base
	# before distance levels exist. The native has_mesh() is not script API.
	var original := ImporterMesh.new()
	for surface in range(3):
		original.add_surface(source_mesh.get_surface_primitive_type(surface), source_mesh.get_surface_arrays(surface),
			[], {}, source_mesh.get_surface_material(surface), source_mesh.get_surface_name(surface), source_mesh.get_surface_format(surface))
	var base: Array = []
	for surface in range(3):
		base.append(original.get_surface_arrays(surface).duplicate(true))
	# Pinned 4.7.2 uses attribute-aware simplification and original vertex
	# indices. Stored size is cumulative error times source mesh scale.
	# Keep the complete base; generated levels may prune fine twigs.
	original.generate_lods(60.0, 0.0, [])
	var mesh := original.get_mesh()
	if mesh == null or DirAccess.make_dir_absolute(output) != OK:
		fail("Cannot create the fir resource output.")
		return
	var textures: Dictionary = {}
	var report := {"status": "pass", "source_node": "fir_sapling_medium_b_LOD0", "source_scale": 1.0,
		"catalogue_translation_omitted": descriptor.nodes[1].get("translation", [0, 0, 0]), "base_triangles": 0, "surfaces": [],
		"lods": "Generated by pinned ImporterMesh; not authored provider LODs or rendered-error proof."}
	for role in ["branches", "twigs"]:
		var maps: Dictionary = {}
		for map_role in ["albedo", "normal", "arm"]:
			var suffix: String = {"albedo": "diff", "normal": "nor_gl", "arm": "arm"}[map_role]
			var image := prepare_rgb_map(family.path_join("source/textures/fir_sapling_medium_" + role + "_" + suffix + "_1k.jpg"), map_role)
			if image == null or image.save_png(output.path_join(role + "_" + map_role + ".png")) != OK:
				fail("Cannot retain a prepared fir image.")
				return
			maps[map_role] = ImageTexture.create_from_image(image)
		textures[role] = maps
	for surface in range(3):
		var arrays := mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_positions: PackedVector3Array = base[surface][Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if positions.size() != source_positions.size() or indices != base[surface][Mesh.ARRAY_INDEX]:
			fail("The complete source base indices or vertex count changed.")
			return
		var maximum_position_error := 0.0
		for vertex in range(positions.size()):
			maximum_position_error = maxf(maximum_position_error, positions[vertex].distance_to(source_positions[vertex]))
		if maximum_position_error > 0.0005:
			fail("Fir native vertex packing exceeds half a millimetre.")
			return
		var levels: Array = []
		var previous_count := indices.size()
		var previous_error := 0.0
		for level in range(original.get_surface_lod_count(surface)):
			var lod_indices := original.get_surface_lod_indices(surface, level)
			var error := original.get_surface_lod_size(surface, level)
			if lod_indices.size() >= previous_count or lod_indices.is_empty() or lod_indices.size() % 3 != 0 or error <= previous_error:
				fail("Fir distance levels lack decreasing triangles and increasing error.")
				return
			for index in lod_indices:
				if index < 0 or index >= positions.size():
					fail("Fir distance level references an invalid original vertex.")
					return
			levels.append({"triangles": lod_indices.size() / 3, "nominal_error_metres": error})
			previous_count = lod_indices.size()
			previous_error = error
		if levels.size() < 2:
			fail("Fir requires real generated distance levels on every surface.")
			return
		var finish := mesh.surface_get_material(surface).duplicate(false) as StandardMaterial3D
		var maps: Dictionary = textures["twigs" if surface == 1 else "branches"]
		finish.albedo_texture = maps.albedo
		finish.normal_texture = maps.normal
		finish.roughness_texture = maps.arm
		finish.metallic_texture = maps.arm
		finish.ao_texture = maps.arm if finish.ao_enabled else null
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var source_material: Dictionary = descriptor.materials[surface]
		var extensions: Dictionary = source_material.get("extensions", {})
		var ior: float = extensions.get("KHR_materials_ior", {}).get("ior", 1.5)
		var factor: float = extensions.get("KHR_materials_specular", {}).get("specularFactor", 1.0)
		var f0 := pow((ior - 1.0) / (ior + 1.0), 2.0) * factor
		finish.metallic_specular = sqrt(f0 / 0.16)
		mesh.surface_set_material(surface, finish)
		report.base_triangles += indices.size() / 3
		report.surfaces.append({"vertices": positions.size(), "indices": indices.size(), "levels": levels,
			"maximum_native_position_error_metres": maximum_position_error, "specular": finish.metallic_specular,
			"source_f0": f0, "uv_scale": str(finish.uv1_scale), "uv_offset": str(finish.uv1_offset),
			"transparency": finish.transparency, "cull": finish.cull_mode})
	var path := output.path_join("fir_tree.res")
	if ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES) != OK:
		fail("Cannot serialize the fir resource.")
		return
	var loaded := ResourceLoader.load(path, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if loaded == null or not ResourceLoader.get_dependencies(path).is_empty():
		fail("Fir resource has missing or external dependencies.")
		return
	var restored_levels := ImporterMesh.from_mesh(loaded)
	for surface in range(3):
		if mesh.surface_get_arrays(surface) != loaded.surface_get_arrays(surface) or original.get_surface_lod_count(surface) != restored_levels.get_surface_lod_count(surface):
			fail("Fir base or distance count changed during roundtrip.")
			return
		for level in range(original.get_surface_lod_count(surface)):
			if original.get_surface_lod_size(surface, level) != restored_levels.get_surface_lod_size(surface, level) or original.get_surface_lod_indices(surface, level) != restored_levels.get_surface_lod_indices(surface, level):
				fail("Fir distance indices changed during roundtrip.")
				return
		var before := mesh.surface_get_material(surface) as StandardMaterial3D
		var after := loaded.surface_get_material(surface) as StandardMaterial3D
		for field in ["albedo_texture", "normal_texture", "roughness_texture"]:
			if before.get(field).get_image().get_data() != after.get(field).get_image().get_data():
				fail("Embedded fir pixels changed during roundtrip.")
				return
	report.resource_bytes = FileAccess.get_file_as_bytes(path).size()
	report.resource_sha256 = FileAccess.get_sha256(path)
	report.exact_native_array_and_pixel_roundtrip = true
	if report.resource_bytes > 12582912:
		report.status = "fail"
		report.finding = "The complete fir exceeds its twelve-MiB component allocation."
	var result := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	result.store_string(JSON.stringify(report, "  ") + "\n")
	result.close()
	print(JSON.stringify(report))
	quit(0 if report.status == "pass" else 1)

func _botanical_maps(family: String, prefix: String, cutout: bool = false, color_size: int = 192, data_size: int = 128) -> Dictionary:
	var maps := {}
	for role in ["albedo", "normal", "arm"]:
		var suffix: String = {"albedo": "diff", "normal": "nor_gl", "arm": "arm"}[role]
		var image := prepare_rgb_map(family.path_join("textures/" + prefix + "_" + suffix + "_1k.jpg"), role,
			color_size if role == "albedo" else data_size)
		if image == null:
			return {}
		if role == "albedo" and cutout:
			var mask := Image.load_from_file(family.path_join("textures/" + prefix + "_alpha_1k.png"))
			if mask == null or mask.get_size() != Vector2i(1024, 1024):
				fail("Unexpected botanical cutout mask: " + prefix)
				return {}
			mask.convert(Image.FORMAT_L8)
			mask.resize(color_size, color_size, Image.INTERPOLATE_LANCZOS)
			var rgb := image.get_data()
			var alpha := mask.get_data()
			var rgba := PackedByteArray()
			rgba.resize(color_size * color_size * 4)
			for pixel in range(color_size * color_size):
				for channel in range(3):
					rgba[pixel * 4 + channel] = rgb[pixel * 3 + channel]
				rgba[pixel * 4 + 3] = alpha[pixel]
			image = Image.create_from_data(color_size, color_size, false, Image.FORMAT_RGBA8, rgba)
			if image.generate_mipmaps() != OK:
				fail("Cannot prepare botanical cutout mipmaps: " + prefix)
				return {}
		maps[role] = ImageTexture.create_from_image(image)
	return maps

func _botanical_finish(source: Material, maps: Dictionary, cutout: bool = false) -> StandardMaterial3D:
	var finish := source.duplicate(false) as StandardMaterial3D
	if finish == null:
		return null
	finish.albedo_texture = maps.albedo
	finish.normal_texture = maps.normal
	finish.roughness_texture = maps.arm
	finish.metallic_texture = maps.arm
	finish.ao_texture = maps.arm if finish.ao_enabled else null
	finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if cutout else BaseMaterial3D.TRANSPARENCY_DISABLED
	if cutout:
		finish.alpha_scissor_threshold = 0.5
	return finish

func _compact_botanical_surface(source: Array, selected: PackedInt32Array) -> Array:
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
	var secondary: PackedVector2Array = source[Mesh.ARRAY_TEX_UV2] if source[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var tangents: PackedFloat32Array = source[Mesh.ARRAY_TANGENT] if source[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var compact := []
	compact.resize(Mesh.ARRAY_MAX)
	var positions_out := PackedVector3Array()
	var normals_out := PackedVector3Array()
	var uv_out := PackedVector2Array()
	var secondary_out := PackedVector2Array()
	var tangents_out := PackedFloat32Array()
	var indices_out := PackedInt32Array()
	var remap := {}
	for original: int in selected:
		if original < 0 or original >= vertices.size():
			return []
		if not remap.has(original):
			remap[original] = positions_out.size()
			positions_out.append(vertices[original])
			normals_out.append(normals[original])
			uv_out.append(uvs[original])
			if not secondary.is_empty():
				secondary_out.append(secondary[original])
			if not tangents.is_empty():
				for channel in range(4):
					tangents_out.append(tangents[original * 4 + channel])
		indices_out.append(remap[original])
	compact[Mesh.ARRAY_VERTEX] = positions_out
	compact[Mesh.ARRAY_NORMAL] = normals_out
	compact[Mesh.ARRAY_TEX_UV] = uv_out
	if not secondary_out.is_empty():
		compact[Mesh.ARRAY_TEX_UV2] = secondary_out
	if not tangents_out.is_empty():
		compact[Mesh.ARRAY_TANGENT] = tangents_out
	compact[Mesh.ARRAY_INDEX] = indices_out
	return compact

func prepare_broadleaf(family: String, output: String) -> void:
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):
		fail("Use a fresh external broadleaf output directory.")
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://opening/assets/broadleaf/source.json"))
	if manifest.get("asset") != "island_tree_02" or not manifest.get("source_pins") is Array \
			or manifest.source_pins.size() != 11:
		fail("The declared Island Tree 02 source manifest is invalid.")
		return
	for pin: Dictionary in manifest.source_pins:
		var source_file: String = family.path_join(pin.file)
		if not FileAccess.file_exists(source_file) or FileAccess.get_sha256(source_file) != pin.sha256 \
				or FileAccess.get_md5(source_file) != pin.api_md5 \
				or FileAccess.get_file_as_bytes(source_file).size() != pin.bytes:
			fail("Broadleaf source identity changed: " + pin.file)
			return
	var state := GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if GLTFDocument.new().append_from_file(family.path_join("island_tree_02_1k.gltf"), state) != OK or state.get_meshes().size() != 1:
		fail("Cannot import the qualified broadleaf source.")
		return
	var original: ImporterMesh = state.get_meshes()[0].mesh
	if original.get_surface_count() != 3:
		fail("Broadleaf source must have trunk, leaf and branch surfaces.")
		return
	var mesh := ArrayMesh.new()
	var report := {"status": "pass", "source_leaf_triangles": 714744,
		"selected_leaf_triangles": 275674, "surfaces": []}
	for surface in range(3):
		var source_surface: int = [2, 1, 0][surface]
		var derived := ImporterMesh.new()
		derived.add_surface(Mesh.PRIMITIVE_TRIANGLES, original.get_surface_arrays(source_surface), [], {},
			original.get_surface_material(source_surface), ["Branches", "Leaves", "Trunk"][surface],
			original.get_surface_format(source_surface))
		derived.generate_lods(60.0, 0.0, [])
		var level: int = [2, 0, 1][surface]
		var expected: int = [39400, 275674, 6824][surface]
		if derived.get_surface_lod_count(0) <= level or derived.get_surface_lod_indices(0, level).size() != expected * 3:
			fail("Pinned broadleaf distance detail changed at surface " + str(surface))
			return
		var arrays: Array = _compact_botanical_surface(original.get_surface_arrays(source_surface),
			derived.get_surface_lod_indices(0, level))
		if arrays.is_empty():
			fail("Broadleaf compaction produced an invalid surface.")
			return
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		var prefix: String = "island_tree_02" + ["_branches", "_leaves", ""][surface]
		var maps := {}
		for role in ["albedo", "normal", "arm"]:
			var suffix: String = {"albedo": "diff", "normal": "nor_gl", "arm": "arm"}[role]
			var prepared: Image = prepare_rgb_map(family.path_join("textures/" + prefix + "_" + suffix + "_1k.jpg"),
				role, 192 if role == "albedo" else 96)
			if prepared == null:
				return
			maps[role] = ImageTexture.create_from_image(prepared)
		var finish := original.get_surface_material(source_surface).duplicate(true) as StandardMaterial3D
		if finish == null:
			fail("Broadleaf source material is not a standard material.")
			return
		finish.albedo_texture = maps.albedo
		finish.normal_texture = maps.normal
		finish.roughness_texture = maps.arm
		finish.metallic_texture = maps.arm
		finish.ao_texture = maps.arm if finish.ao_enabled else null
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mesh.surface_set_material(surface, finish)
		report.surfaces.append({"vertices": mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size(),
			"triangles": mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size() / 3})
	if DirAccess.make_dir_absolute(output) != OK:
		fail("Cannot create broadleaf output directory.")
		return
	var path := output.path_join("broadleaf_tree.res")
	if ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES) != OK:
		fail("Cannot save broadleaf resource.")
		return
	var loaded := ResourceLoader.load(path, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if loaded == null or loaded.get_surface_count() != 3 or not ResourceLoader.get_dependencies(path).is_empty():
		fail("Broadleaf resource lost a surface or has external dependencies.")
		return
	for surface in range(3):
		if loaded.surface_get_arrays(surface) != mesh.surface_get_arrays(surface):
			fail("Broadleaf resource changed geometry during roundtrip.")
			return
	report["resource_bytes"] = FileAccess.get_file_as_bytes(path).size()
	report["resource_sha256"] = FileAccess.get_sha256(path)
	report["bounds"] = str(mesh.get_aabb())
	report["status"] = "pass" if report.resource_bytes <= 16777216 else "fail"
	var receipt := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	receipt.store_string(JSON.stringify(report, "  ") + "\n")
	receipt.close()
	print(JSON.stringify(report))
	quit(0 if report.status == "pass" else 1)

func prepare_shrub(family: String, output: String) -> void:
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):
		fail("Use a fresh external shrub output directory.")
		return
	for relative in SHRUB_PINS:
		if FileAccess.get_sha256(family.path_join(relative)) != SHRUB_PINS[relative]:
			fail("Shrub source identity changed: " + relative)
			return
	var state := GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if GLTFDocument.new().append_from_file(family.path_join("searsia_lucida_1k.gltf"), state) != OK or state.get_meshes().size() != 7:
		fail("Cannot import the qualified shrub variants.")
		return
	var maps := _botanical_maps(family, "searsia_lucida", true, 128, 64)
	if maps.is_empty() or DirAccess.make_dir_absolute(output) != OK:
		fail("Cannot create shrub output directory or prepared maps.")
		return
	var report := {"status": "pass", "variants": []}
	for variant in range(2):
		var source_index := 4 if variant == 0 else 5
		var original: ImporterMesh = state.get_meshes()[source_index].mesh
		if original.get_surface_count() != 3:
			fail("Selected shrub variant has an unexpected surface count.")
			return
		var mesh := original.get_mesh()
		if mesh == null:
			fail("Cannot prepare the selected shrub variant.")
			return
		var counts := []
		for surface in range(3):
			var finish := _botanical_finish(original.get_surface_material(surface), maps, surface > 0)
			if finish == null:
				fail("Cannot prepare the selected shrub material.")
				return
			# The donor's dry leaves need a restrained green tint in this river biome.
			# Bark and narrow twigs keep their photographed source color.
			if surface == 1:
				finish.albedo_color = Color(0.55, 0.75, 0.58)
			mesh.surface_set_material(surface, finish)
			counts.append(mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size() / 3)
		var path := output.path_join("shrub_%s.res" % ["tall", "low"][variant])
		if ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES) != OK:
			fail("Cannot save shrub variant.")
			return
		var loaded := ResourceLoader.load(path, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		if loaded == null or not ResourceLoader.get_dependencies(path).is_empty():
			fail("Shrub resource changed or has external dependencies.")
			return
		for surface in range(3):
			if loaded.surface_get_arrays(surface) != mesh.surface_get_arrays(surface):
				fail("Shrub geometry changed during roundtrip.")
				return
		report.variants.append({"name": ["tall", "low"][variant], "source_mesh": source_index,
			"triangles_by_surface": counts,
			"bounds": str(mesh.get_aabb()), "bytes": FileAccess.get_file_as_bytes(path).size(), "sha256": FileAccess.get_sha256(path)})
	var receipt := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	receipt.store_string(JSON.stringify(report, "  ") + "\n")
	receipt.close()
	print(JSON.stringify(report))
	quit()

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func nearest_byte(value: float) -> int:
	return clampi(roundi(value * 255.0), 0, 255)

func prepare_stone(family: String) -> void:
	var output := family.path_join("prepared-stone")
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_absolute(output) != OK:
		fail("Use a fresh stone preparation directory; preserve earlier results.")
		return
	var files := {"albedo": "source_albedo.jpg", "normal": "source_normal.png", "arm": "source_arm.png"}
	var images := {}
	for role in files:
		var image := Image.load_from_file(family.path_join(files[role]))
		if image == null or image.is_empty() or image.get_size() != Vector2i(1024, 1024):
			fail("Unexpected stone source decode or dimensions: " + role)
			return
		image.convert(Image.FORMAT_RGB8 if role == "albedo" else Image.FORMAT_RGBF)
		images[role] = image
	images.normal.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	images.arm.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var records := {}
	var passed := true
	var total := 0
	for role in ["albedo", "normal", "arm"]:
		var image: Image = images[role]
		var maximum_normal_error := 0.0
		if role != "albedo":
			var bytes := PackedByteArray()
			bytes.resize(image.get_width() * image.get_height() * 3)
			for y in range(image.get_height()):
				for x in range(image.get_width()):
					var color := image.get_pixel(x, y)
					if role == "normal":
						var normal := Vector3(color.r * 2 - 1, color.g * 2 - 1, color.b * 2 - 1)
						if not normal.is_finite() or normal.length_squared() < 0.000001:
							fail("Invalid resized stone normal.")
							return
						normal = normal.normalized()
						color = Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5)
					var at := (y * image.get_width() + x) * 3
					bytes[at] = nearest_byte(color.r)
					bytes[at + 1] = nearest_byte(color.g)
					bytes[at + 2] = nearest_byte(color.b)
					if role == "normal":
						var vector := Vector3(bytes[at], bytes[at + 1], bytes[at + 2]) / 255.0 * 2 - Vector3.ONE
						maximum_normal_error = maxf(maximum_normal_error, absf(vector.length() - 1.0))
			image = Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8, bytes)
		var name_value: String = "stone_normal_gl.webp" if role == "normal" else "stone_" + role + ".webp"
		var destination := output.path_join(name_value)
		if image.save_webp(destination, role == "albedo", 0.80 if role == "albedo" else 1.0) != OK:
			fail("Cannot publish prepared stone map: " + role)
			return
		var decoded := Image.load_from_file(destination)
		if decoded == null or decoded.is_empty() or decoded.get_size() != image.get_size():
			fail("Prepared stone map failed to decode: " + role)
			return
		decoded.convert(Image.FORMAT_RGB8)
		var exact := decoded.get_data() == image.get_data()
		var size := FileAccess.get_file_as_bytes(destination).size()
		total += size
		var record := {"file": name_value, "width": image.get_width(), "height": image.get_height(), "bytes": size,
			"sha256": FileAccess.get_sha256(destination), "decoded_rgb8_exact": exact}
		if role == "albedo":
			var sum_error := 0.0
			for y in range(1024):
				for x in range(1024):
					var a := image.get_pixel(x, y)
					var b := decoded.get_pixel(x, y)
					sum_error += pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2)
			var rmse := sqrt(sum_error / (1024.0 * 1024.0 * 3.0))
			record.albedo_rmse_srgb = rmse
			passed = passed and rmse < 0.025
		else:
			passed = passed and exact and maximum_normal_error < 0.01
			if role == "normal":
				record.maximum_unit_length_error = maximum_normal_error
		records[role] = record
	passed = passed and total <= 1000000
	var result := {"status": "pass" if passed else "fail", "maps": records, "total_bytes": total,
		"processing": "Original 1024px sRGB color uses WebP quality 0.80. Linear ARM is Lanczos resized to 256 and explicitly nearest-rounded RGB8. OpenGL normal is resized to 512, vector-normalized and nearest-rounded RGB8. Data maps use lossless WebP, no gamma transform or green flip.",
		"limits": "Source-map preparation only; numerical bounds do not establish rendered quality, physical detail or human preference."}
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot retain the stone preparation result.")
		return
	file.store_string(JSON.stringify(result, "  ") + "\n")
	file.close()
	print(JSON.stringify(result))
	quit(0 if passed else 1)

func prepare_outcrop(family: String, output: String, scale: Vector3 = Vector3.ONE) -> void:
	# One immutable presentation mesh and its collision hull; no world authority.
	if not scale.is_finite() or scale.x <= 0.0 or scale.y <= 0.0 or scale.z <= 0.0 \
			or scale.x > 1.0 or scale.y > 1.0 or scale.z > 1.3:
		fail("The provisional outcrop fit needs finite positive dimensions and at most 1.3 times the donor length.")
		return
	var pins := {
		"boulder_01_1k.gltf": "51487934db898b4c24072780a451e34eca5c02e3ada24a62bbc600bbc4019e92",
		"boulder_01.bin": "7f5b06503d62bd95bfe9c6b8a354a5cc8ff04a4d271a8cf87a3e3125db4232d7",
		"textures/boulder_01_diff_1k.jpg": "c38f0e918f6dc16b8d386ba3cdd89805c78320c119a1ceec85856f82b09a65b8",
		"textures/boulder_01_nor_gl_1k.jpg": "0810cf6e89d89bb6eb065b4d2e2855288f5dcbd2c15c6e40ab90d462021b50aa",
		"textures/boulder_01_arm_1k.jpg": "c57187c5746b6be913fa53846cb44ff78743e7ca5000f131c9627b99563c2b87"}
	for name_value in pins:
		if FileAccess.get_sha256(family.path_join("raw-source").path_join(name_value)) != pins[name_value]:
			fail("The outcrop preparation requires the qualified donor bytes: " + name_value)
			return
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output) \
		or DirAccess.make_dir_absolute(output) != OK:
		fail("Use a fresh absolute outcrop output directory; preserve earlier results.")
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(family.path_join("raw-source/boulder_01_1k.gltf"), state) != OK \
		or state.get_meshes().size() != 1:
		fail("Cannot import the qualified outcrop.")
		return
	var original: ImporterMesh = state.get_meshes()[0].mesh
	var input := ArrayMesh.new()
	input.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, original.get_surface_arrays(0))
	var tangent_builder := SurfaceTool.new()
	tangent_builder.create_from(input, 0)
	tangent_builder.generate_tangents()
	var source := tangent_builder.commit_to_arrays()
	var lods := ImporterMesh.new()
	lods.add_surface(Mesh.PRIMITIVE_TRIANGLES, source, [], {}, null, "Boulder")
	lods.generate_lods(60.0, 0.0, [])
	if lods.get_surface_lod_count(0) <= 2:
		fail("The pinned engine did not produce the selected outcrop level.")
		return
	var indices := lods.get_surface_lod_indices(0, 2)
	var remap := {}
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var compact := PackedInt32Array()
	for index in indices:
		if not remap.has(index):
			remap[index] = vertices.size()
			vertices.append(source[Mesh.ARRAY_VERTEX][index])
			normals.append(source[Mesh.ARRAY_NORMAL][index])
			uvs.append(source[Mesh.ARRAY_TEX_UV][index])
			for component in range(4):
				tangents.append(source[Mesh.ARRAY_TANGENT][index * 4 + component])
		compact.append(remap[index])
	if vertices.size() != 5748 or compact.size() != 8264 * 3:
		fail("The pinned outcrop simplification changed; inspect it before adoption.")
		return
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for point in vertices:
		bounds = bounds.expand(point)
	var center := bounds.get_center()
	for index in range(vertices.size()):
		vertices[index] = (vertices[index] - center) * scale
		if scale != Vector3.ONE:
			var normal: Vector3 = (normals[index] / scale).normalized()
			var tangent := Vector3(tangents[index * 4], tangents[index * 4 + 1],
				tangents[index * 4 + 2]) * scale
			tangent = (tangent - normal * tangent.dot(normal)).normalized()
			if not normal.is_finite() or not tangent.is_finite() or tangent.length() < 0.99:
				fail("The fitted outcrop changed its normal or tangent basis invalidly.")
				return
			normals[index] = normal
			for component in range(3):
				tangents[index * 4 + component] = [tangent.x, tangent.y, tangent.z][component]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = compact
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shape := mesh.create_convex_shape(true, false)
	var debug := shape.get_debug_mesh()
	var hull: Array = []
	for surface in range(debug.get_surface_count()):
		if debug.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
			hull = debug.surface_get_arrays(surface)
	if hull.is_empty() or hull[Mesh.ARRAY_VERTEX].size() < 4 or hull[Mesh.ARRAY_VERTEX].size() > 512:
		fail("The full native outcrop hull is missing or exceeds the bounded convex-body allocation.")
		return
	mesh.set_meta("native_hull_points", hull[Mesh.ARRAY_VERTEX])
	mesh.set_meta("native_hull_indices", hull[Mesh.ARRAY_INDEX])
	# Reuse the original input when creating a body. Recooking the cooked
	# debug vertices removes redundant points and accumulates quantization.
	mesh.set_meta("native_hull_input_points", shape.points)
	mesh.set_meta("source_center", center)
	mesh.set_meta("source_lod_error", lods.get_surface_lod_size(0, 2))
	if ResourceSaver.save(mesh, output.path_join("boulder.res"), ResourceSaver.FLAG_COMPRESS) != OK:
		fail("Cannot save the prepared outcrop mesh.")
		return
	var report := {"status": "pass", "engine": Engine.get_version_info().string,
		"triangles": compact.size() / 3, "vertices": vertices.size(),
		"hull_points": hull[Mesh.ARRAY_VERTEX].size(), "input_hull_points": shape.points.size(),
		"selected_lod": 2, "source_lod_error": lods.get_surface_lod_size(0, 2),
		"fitted_scale": [scale.x, scale.y, scale.z], "files": {}}
	for role in ["albedo", "normal", "arm"]:
		var suffix: String = {"albedo": "diff", "normal": "nor_gl", "arm": "arm"}[role]
		var image := Image.load_from_file(family.path_join("raw-source/textures/boulder_01_" + suffix + "_1k.jpg"))
		if image == null or image.get_size() != Vector2i(1024, 1024):
			fail("Cannot decode the qualified outcrop map: " + role)
			return
		image.convert(Image.FORMAT_RGBF)
		var extent := 512 if role == "albedo" else 256
		image.resize(extent, extent, Image.INTERPOLATE_LANCZOS)
		if role == "normal":
			for y in range(extent):
				for x in range(extent):
					var pixel := image.get_pixel(x, y)
					var vector := Vector3(pixel.r, pixel.g, pixel.b) * 2.0 - Vector3.ONE
					if vector.length() <= 0.001:
						fail("A resized outcrop normal is degenerate.")
						return
					vector = vector.normalized() * 0.5 + Vector3.ONE * 0.5
					image.set_pixel(x, y, Color(vector.x, vector.y, vector.z))
		image.convert(Image.FORMAT_RGB8)
		var path := output.path_join(role + ".webp")
		if image.save_webp(path, role == "albedo", 0.84) != OK:
			fail("Cannot write the prepared outcrop map: " + role)
			return
		var decoded := Image.load_from_file(path)
		if decoded == null or decoded.get_size() != image.get_size() \
			or (role != "albedo" and decoded.get_data() != image.get_data()):
			fail("Outcrop data-map delivery changed the prepared pixels: " + role)
			return
	var total := 0
	for file_name in ["boulder.res", "albedo.webp", "normal.webp", "arm.webp"]:
		var path := output.path_join(file_name)
		var bytes := FileAccess.get_file_as_bytes(path).size()
		report.files[file_name] = {"bytes": bytes, "sha256": FileAccess.get_sha256(path)}
		total += bytes
	report["package_bytes"] = total
	var result := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	result.store_string(JSON.stringify(report, "  ") + "\n")
	result.close()
	print(JSON.stringify(report))
	quit(0)

func _initialize() -> void:
	var family := ""
	var material := "foliage"
	var pine_output := ""
	var outcrop_scale := Vector3.ONE
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--family="):
			family = argument.trim_prefix("--family=")
		elif argument.begins_with("--material="):
			material = argument.trim_prefix("--material=")
		elif argument.begins_with("--output="):
			pine_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--outcrop-scale="):
			var components := argument.trim_prefix("--outcrop-scale=").split(",")
			var valid := components.size() == 3
			for value in components:
				valid = valid and value.is_valid_float()
			if not valid:
				fail("The outcrop scale must contain three finite decimal components.")
				return
			outcrop_scale = Vector3(float(components[0]), float(components[1]), float(components[2]))
	if not family.is_absolute_path():
		fail("Use an absolute owned source family.")
		return
	if material == "pine":
		prepare_pine(family, pine_output if not pine_output.is_empty() else family.path_join("prepared-pine"))
		return
	if material == "fir":
		prepare_fir(family, pine_output if not pine_output.is_empty() else family.path_join("prepared-fir"))
		return
	if material == "broadleaf":
		prepare_broadleaf(family, pine_output if not pine_output.is_empty() else family.path_join("prepared-broadleaf"))
		return
	if material == "shrub":
		prepare_shrub(family, pine_output if not pine_output.is_empty() else family.path_join("prepared-shrub"))
		return
	if material == "forest-ground":
		prepare_forest_ground(family)
		return
	if material == "stone":
		prepare_stone(family)
		return
	if material == "outcrop":
		prepare_outcrop(family, pine_output if not pine_output.is_empty() else family.path_join("prepared-outcrop"), outcrop_scale)
		return
	if material != "foliage":
		fail("Choose a declared asset or material preparation.")
		return
	var output := family.path_join("prepared-maps")
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_absolute(output) != OK:
		fail("Use a fresh output directory; preserve earlier results.")
		return
	var files := {"albedo": "source_albedo.jpg", "alpha": "source_alpha.png", "normal": "source_normal.png", "arm": "source_arm.png"}
	var images := {}
	for role in files:
		var image := Image.load_from_file(family.path_join(files[role]))
		if image == null or image.is_empty() or image.get_size() != Vector2i(1024, 1024):
			fail("Unexpected source image dimensions or decode: " + role)
			return
		image.convert(Image.FORMAT_RGBF)
		images[role] = image
	var source_coverage := 0
	for y in range(1024):
		for x in range(1024):
			if images.alpha.get_pixel(x, y).r >= 0.5:
				source_coverage += 1
	images.albedo.resize(384, 384, Image.INTERPOLATE_LANCZOS)
	images.alpha.resize(384, 384, Image.INTERPOLATE_LANCZOS)
	images.normal.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	images.arm.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var records := {}
	var passed := true
	for role in ["albedo", "normal", "arm"]:
		var extent := 384 if role == "albedo" else 256
		var channels := 4 if role == "albedo" else 3
		var bytes := PackedByteArray()
		bytes.resize(extent * extent * channels)
		var coverage := 0
		var maximum_normal_error := 0.0
		for y in range(extent):
			for x in range(extent):
				var color: Color = images[role].get_pixel(x, y)
				if role == "normal":
					var normal := Vector3(color.r * 2 - 1, color.g * 2 - 1, color.b * 2 - 1)
					if not normal.is_finite() or normal.length_squared() < 0.000001:
						fail("Invalid source normal after resize.")
						return
					normal = normal.normalized()
					color = Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5)
				var at := (y * extent + x) * channels
				bytes[at] = nearest_byte(color.r)
				bytes[at + 1] = nearest_byte(color.g)
				bytes[at + 2] = nearest_byte(color.b)
				if role == "albedo":
					bytes[at + 3] = nearest_byte(images.alpha.get_pixel(x, y).r)
					if bytes[at + 3] >= 128:
						coverage += 1
				elif role == "normal":
					var decoded := Vector3(bytes[at], bytes[at + 1], bytes[at + 2]) / 255.0 * 2.0 - Vector3.ONE
					maximum_normal_error = maxf(maximum_normal_error, absf(decoded.length() - 1.0))
		var packed := Image.create_from_data(extent, extent, false, Image.FORMAT_RGBA8 if role == "albedo" else Image.FORMAT_RGB8, bytes)
		var destination := output.path_join(role + ".png")
		if packed.save_png(destination) != OK:
			fail("Cannot publish prepared texture: " + role)
			return
		var decoded := Image.load_from_file(destination)
		var exact := decoded != null and decoded.get_size() == packed.get_size() and decoded.get_data() == bytes
		passed = passed and exact and maximum_normal_error < 0.01
		var record := {"extent": extent, "bytes": FileAccess.get_file_as_bytes(destination).size(), "sha256": FileAccess.get_sha256(destination), "decoded_bytes_exact": exact}
		if role == "albedo":
			var original := float(source_coverage) / (1024 * 1024)
			var resized := float(coverage) / (384 * 384)
			record.source_cutout_coverage = original
			record.prepared_cutout_coverage = resized
			passed = passed and original > 0.02 and original < 0.98 and absf(original - resized) < 0.025
		elif role == "normal":
			record.maximum_unit_length_error = maximum_normal_error
		records[role] = record
	var result := {"status": "pass" if passed else "fail", "maps": records,
		"processing": "Lanczos resize; photographed sRGB color plus separate linear opacity; normalized OpenGL normal with nearest RGB8 encoding; packed linear ARM unchanged in channel meaning. Lossless PNG delivery, no normal green flip.",
		"limits": "Asset preparation and decode evidence only; no rendered quality or game authority."}
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		fail("Cannot retain preparation result.")
		return
	file.store_string(JSON.stringify(result, "  ") + "\n")
	file.close()
	print(JSON.stringify(result))
	quit(0 if passed else 1)
