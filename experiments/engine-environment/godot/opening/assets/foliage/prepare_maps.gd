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

func pine_image(path: String, role: String) -> Image:
	var image := Image.load_from_file(path)
	if image == null or image.get_size() != Vector2i(1024, 1024):
		fail("Unexpected pine source image: " + path)
		return null
	image.convert(Image.FORMAT_RGBF)
	if role == "albedo":
		# Resample photographed color in linear light, then encode sRGB bytes.
		for y in range(1024):
			for x in range(1024):
				image.set_pixel(x, y, image.get_pixel(x, y).srgb_to_linear())
	image.resize(384 if role == "albedo" else 256, 384 if role == "albedo" else 256, Image.INTERPOLATE_LANCZOS)
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
					fail("Invalid pine source normal.")
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
		fail("Prepared pine normals exceed the encoding bound.")
		return null
	var prepared := Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8, bytes)
	if prepared.generate_mipmaps(role == "normal") != OK:
		fail("Cannot generate pine mipmaps.")
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
			var image := pine_image(family.path_join("source/textures").path_join("pine_sapling_small_" + role + "_" + suffix + "_1k.jpg"), map_role)
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
	var pins := {"source.gltf": "7da88e6354aa1f67566e7aca803642641b8247ddbbfc81c5dd64067961daa194",
		"source_albedo.jpg": "c598c555f13cd5328409fd5e2a45496a26e319e52299e3959042f1449c2f1b06",
		"source_normal.png": "0c5c37348830b6a36024a114359e26aaf2f48bf2b435a5ef2d6999bcd4b530b7",
		"source_arm.png": "939f98687379b70fe2f2e1daf0965d46080d00bb4bbe9afb9e2108ce456ad9ab"}
	for file in pins:
		if FileAccess.get_sha256(family.path_join(file)) != pins[file]:
			fail("Refuse changed qualified ground input: " + file)
			return
	var descriptor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(family.path_join("source.gltf")))
	if descriptor.materials[0].pbrMetallicRoughness.metallicFactor != 0:
		fail("The ground descriptor no longer selects the qualified dielectric surface.")
		return
	if DirAccess.make_dir_absolute(output) != OK:
		fail("Cannot create the fresh ground output.")
		return
	var report := {"status": "pass", "asset": "brown_mud_leaves_01", "maps": {},
		"source_extent_metres": 1.3, "source_scene_imported": false, "limits": "No scene, collision, renderer or graphical-quality result."}
	var total := 0
	for role in ["albedo", "normal", "arm"]:
		var source_name: String = {"albedo": "source_albedo.jpg", "normal": "source_normal.png", "arm": "source_arm.png"}[role]
		var image := Image.load_from_file(family.path_join(source_name))
		if image == null or image.get_size() != Vector2i(1024, 1024):
			fail("Unexpected ground source image: " + role)
			return
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
		"catalogue_translation_omitted": [1, 0, 0], "base_triangles": 0, "surfaces": [],
		"lods": "Generated by pinned ImporterMesh; not authored provider LODs or rendered-error proof."}
	for role in ["branches", "twigs"]:
		var maps: Dictionary = {}
		for map_role in ["albedo", "normal", "arm"]:
			var suffix: String = {"albedo": "diff", "normal": "nor_gl", "arm": "arm"}[map_role]
			var image := pine_image(family.path_join("source/textures/fir_sapling_medium_" + role + "_" + suffix + "_1k.jpg"), map_role)
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

func _initialize() -> void:
	var family := ""
	var material := "foliage"
	var pine_output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--family="):
			family = argument.trim_prefix("--family=")
		elif argument.begins_with("--material="):
			material = argument.trim_prefix("--material=")
		elif argument.begins_with("--output="):
			pine_output = argument.trim_prefix("--output=")
	if not family.is_absolute_path():
		fail("Use an absolute owned source family.")
		return
	if material == "pine":
		prepare_pine(family, pine_output if not pine_output.is_empty() else family.path_join("prepared-pine"))
		return
	if material == "fir":
		prepare_fir(family, pine_output if not pine_output.is_empty() else family.path_join("prepared-fir"))
		return
	if material == "forest-ground":
		prepare_forest_ground(family)
		return
	if material == "stone":
		prepare_stone(family)
		return
	if material != "foliage":
		fail("Choose the declared foliage or stone preparation.")
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
