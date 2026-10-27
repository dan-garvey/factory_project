extends SceneTree
const ProductionConveyorArt = preload("res://opening/production_conveyors.gd").ProductionConveyorArt
const ProductionEnvironment = preload("res://opening/production_environment.gd").ProductionEnvironment
const ProductionFoundationArt = preload("res://opening/production_foundations.gd").ProductionFoundationArt
const ProductionSteelFloor = preload("res://opening/production_surfaces.gd").ProductionSteelFloor
const ProductionTransmissionFinish = preload("res://opening/production_surfaces.gd").ProductionTransmissionFinish
const ProductionVisuals = preload("res://opening/production_surfaces.gd").ProductionVisuals
const ProductionPaddleArt = preload("res://opening/production_waterwheels.gd").ProductionPaddleArt
const ProductionWheelArt = preload("res://opening/production_waterwheels.gd").ProductionWheelArt
## Fitted transmission geometry only. No World, input, network or desktop.
const Assets = preload("res://opening/native_transmission_assets.gd")
const Presenter = preload("res://opening/native_transmission_presenter.gd")
const Finish = Assets.Finish
const WORKED_SIZE := 256
const WORKED_RELIEF_METRES := 0.00001
# The presenter fits every gear in one 1.65 m tile; native ratio units change
# tooth count, not world radius. Its signed half-rate phase is measured over
# 0.1 s around the fitted span roller with the established visual phase scale.
const PRESENTED_GEAR_RADIUS := 0.825
const PRESENTED_HALF_RATE_STEP := -0.1 * 0.5 * 1.65 / (0.1425 * 0.45)
var checks := 0
var failed := false
var checked_meshes: Dictionary = {}
var max_tangent_dot := 0.0
var visual_instances := 0
var mode := "default"
var image_family := ""
var image_report := ""
var image_paths: Array[String] = []
var packed_images := false
var map_source := ""
var map_output := ""

const SIMPLE_MODES := {
	"--tooth-only": "tooth-only",
	"--shaft-coupling-only": "shaft-coupling-only",
	"--gear-batch-only": "gear-batch-only",
	"--gear-bore-only": "gear-bore-only",
	"--material-only": "material-only",
	"--historical-material-only": "historical-material-only"}

func refuse_option(message: String) -> bool:
	push_error(message)
	quit(2)
	return false

func external_path(path: String) -> bool:
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	if path.is_empty() or not path.is_absolute_path() or path.simplify_path() != path \
			or path == project_root or path.begins_with(project_root + "/"):
		return false
	var root_directory := DirAccess.open("/")
	var ancestor := "/"
	for segment in path.split("/", false):
		ancestor = ancestor.path_join(segment)
		if root_directory.is_link(ancestor):
			return false
	return true

func parse_options() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return true
	if args[0] == "--resource-images":
		if (args.size() != 3 and args.size() != 4) or (args.size() == 4 and args[3] != "--packed-images"):
			return refuse_option("Use --resource-images FAMILY REPORT [--packed-images].")
		mode = "resource-images"
		image_family = args[1]
		image_report = args[2]
		packed_images = args.size() == 4
		if not external_path(image_family) or not DirAccess.dir_exists_absolute(image_family) \
				or not external_path(image_family.path_join("reference")) \
				or not DirAccess.dir_exists_absolute(image_family.path_join("reference")) \
				or not external_path(image_family.path_join("image-paths.json")) \
				or not FileAccess.file_exists(image_family.path_join("image-paths.json")):
			return refuse_option("Imported image controls need an existing external family and reference set.")
		if not external_path(image_report) or not DirAccess.dir_exists_absolute(image_report.get_base_dir()) \
				or DirAccess.dir_exists_absolute(image_report) or FileAccess.file_exists(image_report):
			return refuse_option("Use a fresh external imported-image report path.")
		var listed = JSON.parse_string(FileAccess.get_file_as_string(image_family.path_join("image-paths.json")))
		if not listed is Array or listed.is_empty() or listed.size() > 64:
			return refuse_option("Imported image controls need 1..64 listed source images.")
		for relative in listed:
			if typeof(relative) != TYPE_STRING or not relative.begins_with("opening/assets/") \
					or relative.simplify_path() != relative or image_paths.has(relative) \
					or not external_path(image_family.path_join("reference").path_join(relative)) \
					or not FileAccess.file_exists(image_family.path_join("reference").path_join(relative)):
				return refuse_option("Imported image controls contain an unsafe or missing reference.")
			image_paths.append(relative)
		return true
	if args[0] == "--prepare-transmission-maps":
		if args.size() != 3:
			return refuse_option("Use --prepare-transmission-maps SOURCE OUTPUT.")
		mode = "prepare-transmission-maps"
		map_source = args[1]
		map_output = args[2]
		if not external_path(map_source) or not DirAccess.dir_exists_absolute(map_source) \
				or not external_path(map_output) or not DirAccess.dir_exists_absolute(map_output) \
				or map_output == map_source or map_output.begins_with(map_source + "/"):
			return refuse_option("Prepared maps need separate existing external source and output directories.")
		for file_name in Finish.FILES.values():
			var target := map_output.path_join(file_name)
			if not external_path(target) or FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
				return refuse_option("Refuse an existing or linked prepared transmission output.")
		return true
	if args.size() != 1 or not SIMPLE_MODES.has(args[0]):
		return refuse_option("Select one known transmission asset fixture mode.")
	mode = SIMPLE_MODES[args[0]]
	return true

func preserves_opaque_and_alpha(imported: Image, source: Image) -> bool:
	var actual := imported.duplicate() as Image
	var expected := source.duplicate() as Image
	actual.convert(Image.FORMAT_RGBA8)
	expected.convert(Image.FORMAT_RGBA8)
	if actual.get_size() != expected.get_size():
		return false
	for y in range(expected.get_height()):
		for x in range(expected.get_width()):
			var pixel := actual.get_pixel(x, y)
			var original := expected.get_pixel(x, y)
			if pixel.a != original.a or (original.a >= 1.0 and pixel != original):
				return false
	return true

func check_resource_images() -> void:
	var records: Array[Dictionary] = []
	for relative: String in image_paths:
		var path := "res://" + relative
		verify(ProductionVisuals.image_exists(path), "Imported project images remain available: " + relative)
		if packed_images:
			verify(not FileAccess.file_exists(path), "The packed control excludes the original image file: " + relative)
		var expected := Image.load_from_file(image_family.path_join("reference").path_join(relative))
		var actual := ProductionVisuals.read_image(path)
		if not verify(actual != null and expected != null, "Both independent image paths decode: " + relative):
			continue
		verify(actual.get_size() == expected.get_size(), "Imported image dimensions are unchanged: " + relative)
		actual.clear_mipmaps()
		actual.convert(expected.get_format())
		var equal := actual.get_data() == expected.get_data()
		var alpha_border_only := false
		if not equal and packed_images and relative == "opening/assets/worker-second/opacity_color.webp":
			var descriptor := ConfigFile.new()
			alpha_border_only = descriptor.load(path + ".import") == OK \
				and descriptor.get_value("params", "process/fix_alpha_border", false) == true \
				and preserves_opaque_and_alpha(actual, expected)
		verify(equal or alpha_border_only,
			"Imported pixels match the source or preserve opaque color and alpha under the declared border fix: " + relative)
		# Material preparation may convert formats and generate mipmaps, so it
		# must receive its own image rather than mutate the cached resource.
		actual.resize(1, 1)
		var again := ProductionVisuals.read_image(path)
		verify(again != null and again.get_size() == expected.get_size(), "Preparing one image does not mutate its cached resource: " + relative)
		records.append({"path": relative, "pixels_equal": equal, "alpha_border_only": alpha_border_only,
			"format": expected.get_format(),
			"size": [expected.get_width(), expected.get_height()]})
	verify(not ProductionVisuals.image_exists("res://opening/assets/missing-material.webp")
		and ProductionVisuals.read_image("res://opening/assets/missing-material.webp") == null,
		"An absent resource remains an explicit absence without raw-file fallback.")
	verify(ProductionVisuals.read_image(image_family.path_join("reference").path_join(image_paths[0])) != null,
		"External preparation inputs retain filesystem decoding.")
	for source in [ProductionTransmissionFinish, ProductionPaddleArt,
			ProductionSteelFloor, ProductionFoundationArt, ProductionConveyorArt]:
		verify(source.read_images().status == "ready", "The complete runtime material set uses imported resources.")
	var cast: StandardMaterial3D = Finish.material("cast", Color("76644d"), 0.8, 0.7)
	verify(cast != null and cast.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED
		and cast.normal_enabled and cast.roughness_texture == Finish.textures.cast_roughness
		and cast.normal_texture == Finish.textures.cast_normal,
		"The transmission still binds the original normal and red-channel roughness maps.")
	verify(cast == Finish.material("cast", Color("76644d"), 0.8, 0.7), "Imported material preparation preserves finish reuse.")
	ProductionWheelArt._prepare()
	verify(ProductionWheelArt.source_status == "ready", "The rotor still receives its complete imported material.")
	var sky: Dictionary = ProductionEnvironment.read_sky()
	verify(sky.status == "ready" and sky.image.get_format() == Image.FORMAT_RGBF,
		"Imported sky preparation preserves floating HDR radiance.")
	var presenter := preload("res://opening/character_presenter.gd").new()
	for role: String in ["body", "head", "opacity"]:
		var material: StandardMaterial3D = presenter._adult_material("f004_" + role)
		if not verify(material != null, "The adult material uses imported images: " + role):
			continue
		var color := Image.load_from_file(image_family.path_join("reference/opening/assets/worker/" + role + "_color.webp"))
		color.generate_mipmaps()
		verify(material.albedo_texture.get_image().get_data() == color.get_data(),
			"Adult color and alpha mipmaps retain their original pixels: " + role)
		if role != "opacity":
			var normal := Image.load_from_file(image_family.path_join("reference/opening/assets/worker/" + role + "_normal.webp"))
			normal.generate_mipmaps(true)
			verify(material.normal_texture.get_image().get_data() == normal.get_data(),
				"Adult normal mipmaps retain their original vectors: " + role)
		else:
			verify(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				and is_equal_approx(material.alpha_scissor_threshold, 0.4),
				"The hair and eyelash alpha rule remains unchanged.")
	presenter.free()
	var report := {"status": "fail" if failed else "pass", "checks": checks, "mode": mode,
		"packed_without_raw_images": packed_images,
		"images": records, "native_gameplay": "not_run", "desktop": "not_used"}
	var file := FileAccess.open(image_report, FileAccess.WRITE)
	if verify(file != null, "The imported-image report is retained."):
		report.checks = checks
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "images": records.size(),
		"mode": mode, "packed_without_raw_images": packed_images,
		"native_gameplay": "not_run", "desktop": "not_used"}))

class MaterialHost extends RefCounted:
	var state: Dictionary = {}
	var ready := true
	func _can_present_confirmed_motion() -> bool:
		return ready

func periodic_noise(noise: FastNoiseLite, x: int, y: int, scale_x: float, scale_y: float) -> float:
	var u := float(posmod(x, WORKED_SIZE))
	var v := float(posmod(y, WORKED_SIZE))
	var tx := u / WORKED_SIZE
	var ty := v / WORKED_SIZE
	# Smooth endpoint weights make the sampled field periodic in both axes.
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	return lerpf(lerpf(noise.get_noise_2d(u * scale_x, v * scale_y),
		noise.get_noise_2d((u - WORKED_SIZE) * scale_x, v * scale_y), tx),
		lerpf(noise.get_noise_2d(u * scale_x, (v - WORKED_SIZE) * scale_y),
		noise.get_noise_2d((u - WORKED_SIZE) * scale_x, (v - WORKED_SIZE) * scale_y), tx), ty)

func encode_map(image: Image, target: String) -> Dictionary:
	if image.save_webp(target, false) != OK:
		push_error("Cannot encode prepared transmission map: " + target)
		return {"status": "fail"}
	var decoded := Image.load_from_file(target)
	if decoded == null:
		push_error("Cannot decode prepared transmission map: " + target)
		return {"status": "fail"}
	decoded.convert(image.get_format())
	if decoded.get_size() != image.get_size() or decoded.get_data() != image.get_data():
		push_error("Prepared transmission pixels differ after lossless encoding.")
		return {"status": "fail"}
	return {"status": "pass", "size": [image.get_width(), image.get_height()], "format": image.get_format(),
		"prepared_pixel_equality": true, "bytes": FileAccess.get_file_as_bytes(target).size()}

func prepare_material_maps() -> void:
	var pins := {"normal": "3e2b0ddc58564d28685f0949ede839fc680c84ae8a0f97127de6aa91ab5b392c",
		"roughness": "e7756912587a45d0a4bd93465e487dde09084486cda922014c07b7c3947d4a34"}
	for file_name in Finish.FILES.values():
		if FileAccess.file_exists(map_output.path_join(file_name)):
			push_error("Refuse an existing prepared transmission output.")
			quit(1)
			return
	for role in pins:
		if FileAccess.get_sha256(map_source.path_join(role + ".png")) != pins[role]:
			push_error("Refuse an unpinned transmission source: " + role)
			quit(1)
			return
	var report: Dictionary = {"status": "pass", "mode": mode, "maps": {}}
	for role in pins:
		var image := Image.load_from_file(map_source.path_join(role + ".png"))
		if image == null or image.get_size() != Vector2i(1024, 1024):
			push_error("Expected the pinned one-kilopixel cast image: " + role)
			quit(1)
			return
		var decoded_format := image.get_format()
		var normal_map: bool = role == "normal"
		image.convert(Image.FORMAT_RGBF if normal_map else Image.FORMAT_RF)
		image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		var pixels := PackedByteArray()
		pixels.resize(512 * 512 * (3 if normal_map else 1))
		var maximum_length_error := 0.0
		var maximum_angle := 0.0
		for y in range(512):
			for x in range(512):
				var color := image.get_pixel(x, y)
				if normal_map:
					var normal := Vector3(color.r, color.g, color.b) * 2.0 - Vector3.ONE
					if not normal.is_finite() or normal.length_squared() < 0.000001:
						push_error("Invalid resized cast normal.")
						quit(1)
						return
					normal = normal.normalized()
					var at := (y * 512 + x) * 3
					for axis in range(3):
						pixels[at + axis] = clampi(roundi((normal[axis] * 0.5 + 0.5) * 255), 0, 255)
					var returned := Vector3(pixels[at], pixels[at + 1], pixels[at + 2]) / 255.0 * 2.0 - Vector3.ONE
					maximum_length_error = maxf(maximum_length_error, absf(returned.length() - 1.0))
					maximum_angle = maxf(maximum_angle, rad_to_deg(acos(clampf(returned.normalized().dot(normal), -1, 1))))
				else:
					pixels[y * 512 + x] = clampi(roundi(color.r * 255), 0, 255)
		if maximum_length_error >= 0.01 or maximum_angle >= 0.5:
			push_error("Prepared cast normal exceeds its representation bound.")
			quit(1)
			return
		image = Image.create_from_data(512, 512, false, Image.FORMAT_RGB8 if normal_map else Image.FORMAT_L8, pixels)
		var result := encode_map(image, map_output.path_join(Finish.FILES["cast_" + role]))
		if result.status != "pass":
			quit(1)
			return
		result["source_decoded_format"] = decoded_format
		result["maximum_normal_length_error"] = maximum_length_error
		result["maximum_normal_encoding_angle_degrees"] = maximum_angle
		report.maps["cast_" + role] = result
	var noise := FastNoiseLite.new()
	noise.seed = 74391
	noise.frequency = 1.0
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	var heights := PackedFloat32Array()
	heights.resize(WORKED_SIZE * WORKED_SIZE)
	var roughness := PackedByteArray()
	roughness.resize(heights.size())
	for y in range(WORKED_SIZE):
		for x in range(WORKED_SIZE):
			var fine := periodic_noise(noise, x, y, 1.7, 1.7)
			var bands := periodic_noise(noise, x, y, 0.05, 0.35)
			var at := y * WORKED_SIZE + x
			heights[at] = bands * 0.8 + fine * 0.2
			roughness[at] = roundi(clampf(0.34 + bands * 0.05 + fine * 0.015, 0.28, 0.42) * 255)
	var normals := PackedByteArray()
	normals.resize(heights.size() * 3)
	var texel_metres := Finish.WORKED_METRES / WORKED_SIZE
	var maximum_worked_error := 0.0
	for y in range(WORKED_SIZE):
		for x in range(WORKED_SIZE):
			var dx := (heights[y * WORKED_SIZE + posmod(x + 1, WORKED_SIZE)] - heights[y * WORKED_SIZE + posmod(x - 1, WORKED_SIZE)]) * WORKED_RELIEF_METRES / (2.0 * texel_metres)
			var dy := (heights[posmod(y + 1, WORKED_SIZE) * WORKED_SIZE + x] - heights[posmod(y - 1, WORKED_SIZE) * WORKED_SIZE + x]) * WORKED_RELIEF_METRES / (2.0 * texel_metres)
			var normal := Vector3(-dx, -dy, 1).normalized()
			var at := (y * WORKED_SIZE + x) * 3
			for axis in range(3):
				normals[at + axis] = roundi((normal[axis] * 0.5 + 0.5) * 255)
			var returned := Vector3(normals[at], normals[at + 1], normals[at + 2]) / 255.0 * 2.0 - Vector3.ONE
			maximum_worked_error = maxf(maximum_worked_error, absf(returned.length() - 1.0))
	var worked_images := {"worked_normal": Image.create_from_data(WORKED_SIZE, WORKED_SIZE, false, Image.FORMAT_RGB8, normals),
		"worked_roughness": Image.create_from_data(WORKED_SIZE, WORKED_SIZE, false, Image.FORMAT_L8, roughness)}
	for role in worked_images:
		var result := encode_map(worked_images[role], map_output.path_join(Finish.FILES[role]))
		if result.status != "pass":
			quit(1)
			return
		report.maps[role] = result
	report["worked_recipe"] = {"seed": 74391, "tile_metres": Finish.WORKED_METRES,
		"height_amplitude_metres": WORKED_RELIEF_METRES, "maximum_normal_length_error": maximum_worked_error,
		"geometry_displacement": false, "runtime_generation": false}
	print(JSON.stringify(report))
	quit(0)

func verify(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failed = true
		push_error(message)
	return condition

func key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000)]

func check_mesh(mesh: Mesh) -> void:
	if checked_meshes.has(mesh):
		return
	checked_meshes[mesh] = true
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for n in range(vertices.size()):
			indices.append(n)
	verify(vertices.size() > 0 and indices.size() % 3 == 0 and normals.size() == vertices.size()
		and uvs.size() == vertices.size() and tangents.size() == vertices.size() * 4,
		"Every new render mesh has complete normal-mapped triangle attributes.")
	var edges: Dictionary = {}
	var valid_faces := true
	var valid_attributes := true
	var volume := 0.0
	for n in range(0, indices.size(), 3):
		var a := vertices[indices[n]]
		var b := vertices[indices[n + 1]]
		var c := vertices[indices[n + 2]]
		var cross := (b - a).cross(c - a)
		valid_faces = valid_faces and cross.length_squared() > 0.00000000000001
		valid_faces = valid_faces and cross.dot(normals[indices[n]]) < 0
		volume += a.dot(b.cross(c)) / 6.0
		for pair in [[a, b], [b, c], [c, a]]:
			var first := key(pair[0])
			var second := key(pair[1])
			var edge := first + "/" + second if first < second else second + "/" + first
			edges[edge] = int(edges.get(edge, 0)) + 1
	for n in range(vertices.size()):
		var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
		max_tangent_dot = maxf(max_tangent_dot, absf(tangent.dot(normals[n])))
		valid_attributes = valid_attributes and vertices[n].is_finite() and normals[n].is_finite() and uvs[n].is_finite()
		valid_attributes = valid_attributes and is_equal_approx(normals[n].length(), 1.0)
		valid_attributes = valid_attributes and tangent.is_finite() and tangent.length() > 0.99
		valid_attributes = valid_attributes and absf(tangent.dot(normals[n])) < 0.0002
	var closed := true
	for count in edges.values():
		closed = closed and count == 2
	verify(valid_faces and volume < -0.00000001, "New assets retain clockwise outward faces and a nonzero enclosed volume.")
	verify(closed, "Every geometric edge of the authored solid is closed exactly twice.")
	verify(valid_attributes, "Packed normals, tangents and surface coordinates remain finite and usable.")

func batch_pose(batch: MultiMesh, index: int) -> Transform3D:
	# Decode the actual retained server buffer, not the dummy renderer's
	# unsupported individual-transform getter (see GDC-09).
	var data := batch.buffer
	var offset := index * 12
	return Transform3D(Basis(Vector3(data[offset], data[offset + 4], data[offset + 8]),
		Vector3(data[offset + 1], data[offset + 5], data[offset + 9]),
		Vector3(data[offset + 2], data[offset + 6], data[offset + 10])),
		Vector3(data[offset + 3], data[offset + 7], data[offset + 11]))

func check_mesh_bounds(mesh: Mesh, pose: Transform3D, center: Vector3, axis: Vector3,
		radius: float, half_length: float) -> void:
	visual_instances += 1
	check_mesh(mesh)
	var bounded := true
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		var point: Vector3 = pose * vertex - center
		var along := point.dot(axis)
		var radial := point - axis * along
		bounded = bounded and absf(along) <= half_length + 0.000001 and radial.length() <= radius + 0.000001
	verify(bounded, "Fitted details stay inside the independently specified native/pick envelope on the actual axis.")

func check_bounds(node: Node3D, pose: Transform3D, center: Vector3, axis: Vector3,
		radius: float, half_length: float) -> void:
	verify(not node is CollisionObject3D and not node is CollisionShape3D and node.get_script() == null,
		"The asset module supplies no collision, input or state-owner node.")
	if node is MeshInstance3D:
		check_mesh_bounds(node.mesh, pose, center, axis, radius, half_length)
	elif node is MultiMeshInstance3D:
		for index in range(node.multimesh.instance_count):
			check_mesh_bounds(node.multimesh.mesh, pose * batch_pose(node.multimesh, index), center, axis, radius, half_length)
	for child in node.get_children():
		if child is Node3D:
			check_bounds(child, pose * child.transform, center, axis, radius, half_length)

func roles(node: Node, role: String) -> int:
	var count := 1 if node.get_meta("asset_role", "") == role else 0
	if count == 1 and node is MultiMeshInstance3D:
		count = node.multimesh.instance_count
	for child in node.get_children():
		count += roles(child, role)
	return count

func check_rim_face_relief(mesh: Mesh, radius: float) -> void:
	var inner := radius * 0.56
	var band := radius - 0.1 - inner
	var relief := minf(0.008, band * 0.075)
	var recessed := [0, 0]
	var shoulders := [0, 0]
	for vertex in mesh.get_faces():
		var radial := Vector2(vertex.x, vertex.z).length()
		if radial < inner + band * 0.3 or radial > inner + band * 0.7:
			continue
		var side := 1 if vertex.y > 0 else 0
		if absf(absf(vertex.y) - (0.07 - relief)) < 0.0001:
			recessed[side] += 1
		if absf(absf(vertex.y) - 0.07) < 0.0001:
			shoulders[side] += 1
	verify(recessed[0] > 0 and recessed[1] > 0 and shoulders[0] > 0 and shoulders[1] > 0,
		"Both actual cog faces retain a measurable recessed annular track and full-height shoulders.")

func check_assemblies() -> void:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var center := Vector3(-1.65, 0.9125, 3.3)
	var previous: Mesh = null
	for axis in range(3):
		var gear := Node3D.new()
		gear.position = center
		gear.basis = Presenter.axis_basis(axis)
		Assets.gear(gear, 0.825, 2, Color("ba9459"))
		verify(roles(gear, "GearTooth") == 16 and roles(gear, "GearSpoke") == 4
			and roles(gear, "HubFastener") == 8, "The ordinary two-unit gear has sixteen beveled render teeth, four spokes and fitted hub fasteners.")
		verify(gear.get_node("Gear").mesh == previous if previous != null else true,
			"Changing the world axis reuses the identical cached rim mesh.")
		previous = gear.get_node("Gear").mesh
		verify(gear.get_node("GearTooth").multimesh.mesh == Assets.tooth_mesh(0.825, 16),
			"Repeated teeth share one closed authored tooth asset.")
		check_rim_face_relief(gear.get_node("Gear").mesh, 0.825)
		check_bounds(gear, gear.transform, center, axes[axis], 0.825, 0.12)
		var shaft := Node3D.new()
		shaft.position = center
		shaft.basis = Presenter.axis_basis(axis)
		Assets.shaft(shaft, 1.65, Color("687a7b"))
		var mesh: CylinderMesh = shaft.get_node("Shaft").mesh
		verify(is_equal_approx(mesh.height, 1.65) and is_equal_approx(mesh.top_radius, 0.03) and mesh.radial_segments == 48,
			"The named shaft remains a CylinderMesh with its exact endpoint length and declared art radius.")
		verify(roles(shaft, "ShaftCollar") == 2 and roles(shaft, "ShaftKey") == 2,
			"The shaft has a fitted collar and key at both ends.")
		check_bounds(shaft, shaft.transform, center, axes[axis], 0.08, 0.825)
		gear.free()
		shaft.free()
	for units in [1, 3]:
		var gear := Node3D.new()
		var radius := float(units) * 0.4125
		Assets.gear(gear, radius, units, Color("687a7b"))
		verify(roles(gear, "GearTooth") == units * 8, "Decorative tooth density remains proportional for other ratio sizes.")
		check_rim_face_relief(gear.get_node("Gear").mesh, radius)
		check_bounds(gear, Transform3D.IDENTITY, Vector3.ZERO, Vector3.UP, radius, 0.12)
		gear.free()

func material_part(root_node: Node, id: String) -> Node3D:
	for child in root_node.get_children():
		if child.get_meta("entity", "") == id:
			return child
	return null

func check_materials() -> void:
	var historical := mode == "historical-material-only"
	var surface_instances := 0
	for axis in range(3):
		for moving in [false, true]:
			var host := MaterialHost.new()
			host.state = {"context": "material-fixture", "options": {"native": true}, "entities": {},
				"transmission_parts": {
					"gear": {"kind": "gear", "center": [-4, 1, 8], "axis": axis, "teeth": 2, "generation": 1},
					"shaft": {"kind": "shaft", "center": [0, 1, 8], "axis": axis, "half_span": 2, "generation": 2}},
				"motion": {"gear": {"state": "rotating" if moving else "stopped", "numerator": 1 if moving else 0, "denominator": 1},
					"shaft": {"state": "rotating" if moving else "stopped", "numerator": -1 if moving else 0, "denominator": 1}}, "engagements": []}
			var before: Dictionary = host.state.duplicate(true)
			var view := Presenter.new()
			view.configure(host)
			var gear := material_part(view, "gear")
			var shaft := material_part(view, "shaft")
			verify(gear != null and shaft != null, "The existing presenter mounts the literal projected cog and shaft.")
			if gear == null or shaft == null:
				view.free()
				continue
			var tint := Color("687a7b")
			var expected_colors := {"Gear": tint, "GearSpoke": tint, "GearTooth": tint,
				"Hub": Color("a6b4af"), "HubFastener": Color("b8c3bb"),
				"Shaft": tint, "ShaftCollar": Color("a6b4af"), "ShaftKey": Color("b87945")}
			var counts := [0, 0, 0]
			for part_node in [gear, shaft]:
				for child in part_node.get_children():
					if not child is GeometryInstance3D or not child.has_meta("asset_role"):
						continue
					var role: String = child.get_meta("asset_role")
					var expected_surface := "copper" if role == "ShaftKey" else ("cast" if role in ["Gear", "GearSpoke"] else "worked")
					var expected_color: Color = expected_colors[role]
					var material := child.material_override as StandardMaterial3D
					var copies: int = child.multimesh.instance_count if child is MultiMeshInstance3D else 1
					surface_instances += copies
					counts[["cast", "worked", "copper"].find(expected_surface)] += copies
					verify(material != null and child.get_meta("surface_role") == expected_surface
						and material.albedo_color == expected_color and material.albedo_texture == null,
						"The actual part keeps its physical metal finish and declared surface role across motion states.")
					if material == null:
						continue
					if expected_surface == "copper" or historical:
						verify(material == Assets.Visuals.material(expected_color, 0.85, 0.38),
							"Copper and actual historical missing-map parts retain their original generated material.")
						continue
					verify(material == Finish.material(expected_surface, expected_color, 0.85, 0.38)
						and material.normal_texture == Finish.textures[expected_surface + "_normal"]
						and material.roughness_texture == Finish.textures[expected_surface + "_roughness"],
						"Repeated actual parts share their exact cached material and surface images.")
					var metres := 0.25 if expected_surface == "cast" else 0.08
					verify(material.uv1_triplanar and not material.uv1_world_triplanar
						and material.uv1_scale.is_equal_approx(Vector3.ONE / metres)
						and material.normal_enabled and is_equal_approx(material.normal_scale, 0.35 if expected_surface == "cast" else 1.0),
						"Local-space surface detail follows rigid rotation at its declared metre scale.")
					verify(is_equal_approx(material.metallic, 0.85) and is_equal_approx(material.roughness, 1.0)
						and material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED
						and material.metallic_texture == null and not material.ao_enabled,
						"Scalar roughness remains linear and no source color, metallic map, occlusion or displacement is invented.")
			# The cog's integral axle adds one core, two collars and two keys.
			verify(counts == [5, 31, 4], "The cog, integral axle and separate shaft expose five cast, thirty-one worked and four copper pieces.")
			var cylinder: CylinderMesh = shaft.get_node("Shaft").mesh
			verify(is_equal_approx(cylinder.height, 1.65) and is_equal_approx(cylinder.top_radius, 0.03)
				and gear.basis.y.is_equal_approx([Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis]),
				"The material adapter preserves the literal shaft geometry and projected assembly axis.")
			verify(host.state == before, "Material assignment does not mutate the projected native facts.")
			view.free()
	verify(Finish.source_status == ("missing" if historical else "ready"),
		"The complete and historical captured projects report their actual resource state.")
	if not historical:
		verify(Finish.material("cast", Color.WHITE, 0.85, 0.38) != Finish.material("worked", Color.WHITE, 0.85, 0.38),
			"The cast and worked roles cannot alias one cached material.")
		var maximum_normal_error := 0.0
		for role in Finish.textures:
			var image: Image = Finish.textures[role].get_image()
			var extent := 512 if role.begins_with("cast") else 256
			verify(image != null and image.get_size() == Vector2i(extent, extent) and image.has_mipmaps(),
				"Every actual source or authored image retains its declared size and mip chain.")
			var low := INF
			var high := -INF
			var valid := true
			for y in range(extent):
				for x in range(extent):
					var pixel := image.get_pixel(x, y)
					if role.ends_with("normal"):
						var normal := Vector3(pixel.r, pixel.g, pixel.b) * 2.0 - Vector3.ONE
						maximum_normal_error = maxf(maximum_normal_error, absf(normal.length() - 1.0))
						valid = valid and normal.is_finite() and absf(normal.length() - 1.0) < 0.012
					else:
						low = minf(low, pixel.r)
						high = maxf(high, pixel.r)
			verify(valid, "Actual decoded tangent normals retain their finite near-unit vectors.")
			if role == "worked_roughness":
				verify(low >= 0.28 - 1.0 / 255.0 and high <= 0.42 + 1.0 / 255.0 and high - low > 0.03,
					"The authored worked finish has restrained scalar variation inside its disclosed roughness range.")
		print(JSON.stringify({"maximum_decoded_normal_length_error": maximum_normal_error}))
	verify(Finish.read_images("user://transmission-material-controls/missing").status == "missing",
		"Missing images are explicitly distinguishable from a complete material set.")
	var partial := "user://transmission-material-controls/partial"
	DirAccess.make_dir_recursive_absolute(partial)
	var file := FileAccess.open(partial.path_join("cast_normal_gl.webp"), FileAccess.WRITE)
	if file != null:
		file.store_string("partial control")
		file.close()
	verify(file != null and Finish.read_images(partial).status == "invalid",
		"An incomplete set is invalid instead of silently claiming new materials.")
	print(JSON.stringify({"surface_instances": surface_instances, "geometry_changed": false,
		"host_facts": "invented read-only projection", "source_state": Finish.source_status}))

func bore_segment_radius(a: Vector2, b: Vector2) -> float:
	var edge := b - a
	var amount := clampf(-a.dot(edge) / edge.length_squared(), 0.0, 1.0) if edge.length_squared() > 0.0 else 0.0
	return (a + edge * amount).length()

func bore_triangle_radius(a: Vector2, b: Vector2, c: Vector2) -> float:
	# A cap can cover the axis while every one of its vertices is outside it.
	var area := (b - a).cross(c - a)
	if absf(area) > 0.000000000001:
		var signs := [(b - a).cross(-a), (c - b).cross(-b), (a - c).cross(-c)]
		if (signs[0] >= 0.0 and signs[1] >= 0.0 and signs[2] >= 0.0) or (signs[0] <= 0.0 and signs[1] <= 0.0 and signs[2] <= 0.0):
			return 0.0
	return minf(bore_segment_radius(a, b), minf(bore_segment_radius(b, c), bore_segment_radius(c, a)))

func bore_triangles(mesh: Mesh) -> PackedVector3Array:
	# Mesh.get_faces() passes through a snapped TriangleMesh cache. Measure the
	# original indexed surface arrays for this fine visual clearance instead.
	var faces := PackedVector3Array()
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array and not arrays[Mesh.ARRAY_INDEX].is_empty():
			for index in arrays[Mesh.ARRAY_INDEX]:
				faces.append(vertices[index])
		else:
			faces.append_array(vertices)
	return faces

func bore_mesh_facts(mesh: Mesh, pose: Transform3D = Transform3D.IDENTITY, cached_faces: bool = false) -> Dictionary:
	var vertices := mesh.get_faces() if cached_faces else bore_triangles(mesh)
	var minimum_radius := INF
	var maximum_radius := 0.0
	var low := INF
	var high := -INF
	var face_radii: Array[float] = []
	for n in range(0, vertices.size(), 3):
		var a: Vector3 = pose * vertices[n]
		var b: Vector3 = pose * vertices[n + 1]
		var c: Vector3 = pose * vertices[n + 2]
		minimum_radius = minf(minimum_radius, bore_triangle_radius(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)))
		for point in [a, b, c]:
			low = minf(low, point.y)
			high = maxf(high, point.y)
			maximum_radius = maxf(maximum_radius, Vector2(point.x, point.z).length())
			if is_equal_approx(absf(point.y), 0.11):
				face_radii.append(Vector2(point.x, point.z).length())
	face_radii.sort()
	return {"minimum_radius": minimum_radius, "maximum_radius": maximum_radius, "low": low, "high": high,
		"minimum_face_radius": face_radii[0] if not face_radii.is_empty() else 0.0, "triangles": vertices.size() / 3}

func bore_shaft_envelope(node: Node3D, pose: Transform3D = Transform3D.IDENTITY) -> float:
	var radius := 0.0
	if node is MeshInstance3D:
		for vertex in bore_triangles(node.mesh):
			var point: Vector3 = pose * vertex
			radius = maxf(radius, Vector2(point.x, point.z).length())
	for child in node.get_children():
		if child is Node3D and not child is CollisionObject3D:
			radius = maxf(radius, bore_shaft_envelope(child, pose * child.transform))
	return radius

func bore_control_mesh(inner: float) -> Mesh:
	# Deliberately simple controls use independent solid and undersized profiles.
	return Assets.Visuals.turned_mesh(PackedVector2Array([Vector2(inner, -0.11), Vector2(0.14, -0.11),
		Vector2(0.14, 0.11), Vector2(inner, 0.11), Vector2(inner, -0.11)]))

func check_gear_bores() -> void:
	var minimum_clearance := INF
	var minimum_bore_radius := INF
	var assemblies := 0
	var control_radius := 0.0
	var hub_meshes: Dictionary = {}
	var maximum_triangles := 0
	for units in [1, 2, 3, 8]:
		for axis in range(3):
			var host := MaterialHost.new()
			var center := [-4, 1, 8]
			host.state = {"context": "open-cog-hub", "options": {"native": true}, "entities": {},
				"transmission_parts": {"gear": {"kind": "gear", "center": center, "axis": axis, "teeth": units, "generation": 1}},
				"motion": {"gear": {"state": "rotating", "numerator": -1, "denominator": 2}}, "engagements": []}
			var view := Presenter.new()
			view.configure(host)
			var empty_gear := material_part(view, "gear")
			verify(empty_gear != null and material_part(view, "shaft") == null,
				"The real presenter shows the unconnected cog without inventing a shaft.")
			if empty_gear == null:
				view.free()
				continue
			var empty_hub: MeshInstance3D = empty_gear.get_node("Hub")
			var hub_mesh := empty_hub.mesh
			var empty_facts := bore_mesh_facts(hub_mesh, empty_hub.transform)
			print(JSON.stringify({"phase": "unconnected hub", "units": units, "axis": axis, "facts": empty_facts,
				"snapped_cache_facts": bore_mesh_facts(hub_mesh, empty_hub.transform, true)}))
			check_mesh(hub_mesh)
			verify(empty_facts.minimum_radius > 0.0388 and empty_facts.minimum_face_radius > 0.0438
				and is_equal_approx(empty_facts.maximum_radius, minf(0.16, PRESENTED_GEAR_RADIUS * 0.34))
				and is_equal_approx(empty_facts.low, -0.11) and is_equal_approx(empty_facts.high, 0.11),
				"Actual hub triangles leave the whole passage open and chamfer both original end planes.")
			host.state.transmission_parts["shaft"] = {"kind": "shaft", "center": center, "axis": axis, "half_span": 1, "generation": 2}
			host.state.motion["shaft"] = {"state": "rotating", "numerator": -1, "denominator": 2}
			var before: Dictionary = host.state.duplicate(true)
			view.refresh()
			var gear := material_part(view, "gear")
			var shaft := material_part(view, "shaft")
			verify(gear != null and shaft != null, "The real presenter mounts both disclosed coaxial projection facts.")
			if gear == null or shaft == null:
				view.free()
				continue
			var hub: MeshInstance3D = gear.get_node("Hub")
			var facts := bore_mesh_facts(hub.mesh, hub.transform)
			var shaft_radius := bore_shaft_envelope(shaft)
			var clearance: float = facts.minimum_radius - shaft_radius
			minimum_clearance = minf(minimum_clearance, clearance)
			minimum_bore_radius = minf(minimum_bore_radius, facts.minimum_radius)
			control_radius = maxf(control_radius, shaft_radius)
			maximum_triangles = maxi(maximum_triangles, facts.triangles)
			verify(hub.mesh == hub_mesh and facts == empty_facts and clearance > 0.001,
				"Adding a shaft reuses the exact open hub and its measured full-turn clearance for core, collars, keys and keyway.")
			verify(gear.position == Presenter.world_center(center) and shaft.position == gear.position
				and gear.basis.y == [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis] and shaft.basis == gear.basis,
				"The actual assemblies preserve the common confirmed point and positive axis.")
			var gear_pick: CylinderShape3D = gear.get_node("Pick").get_child(0).shape
			var shaft_pick: CylinderShape3D = shaft.get_node("Pick").get_child(0).shape
			verify(is_equal_approx(gear_pick.radius, PRESENTED_GEAR_RADIUS) and is_equal_approx(gear_pick.height, 0.24)
				and is_equal_approx(shaft_pick.radius, 0.08) and is_equal_approx(shaft_pick.height, 0.825),
				"The bore changes no gear or shaft selection envelope or endpoint length.")
			verify(roles(gear, "GearTooth") == units * 8 and roles(gear, "GearSpoke") == 4 and roles(gear, "HubFastener") == 8,
				"The exact original peripheral assembly remains present for every disclosed size.")
			verify(hub.material_override == Finish.material("worked", Color("a6b4af"), 0.85, 0.38)
				and hub.get_script() == null and hub.transform == Transform3D.IDENTITY,
				"The open hub retains its cached machined finish and has no independent motion, offset or controller.")
			view.advance_visual_motion(0.1)
			verify(is_equal_approx(view.visual_angle("gear"), PRESENTED_HALF_RATE_STEP)
				and is_equal_approx(view.visual_angle("shaft"), PRESENTED_HALF_RATE_STEP)
				and gear.basis == shaft.basis and host.state == before,
				"The existing signed cosmetic rate turns the same rigid assembly without changing the invented native facts.")
			var cache_key := str(minf(0.16, PRESENTED_GEAR_RADIUS * 0.34))
			verify(not hub_meshes.has(cache_key) or hub_meshes[cache_key] == hub.mesh,
				"Equivalent local hub dimensions reuse their mesh across world axes and cog sizes.")
			hub_meshes[cache_key] = hub.mesh
			assemblies += 1
			view.free()
	verify(bore_mesh_facts(bore_control_mesh(0.0)).minimum_radius < control_radius,
		"The original solid hub fails the same actual shaft-envelope criterion.")
	verify(bore_mesh_facts(bore_control_mesh(0.02)).minimum_radius < control_radius,
		"An open but undersized bore cannot pass merely by having no central cap.")
	verify(bore_triangle_radius(Vector2(-0.1, -0.1), Vector2(0.1, -0.1), Vector2(0.0, 0.1)) == 0.0,
		"The independent face oracle rejects a closing triangle even when all its vertices clear the shaft.")
	verify(minimum_bore_radius < 0.045, "The former wide shaft would fail the same fitted opening.")
	print(JSON.stringify({"assemblies": assemblies, "sizes": [1, 2, 3, 8], "axes": 3,
		"minimum_full_turn_clearance_metres": minimum_clearance, "maximum_actual_shaft_radius_metres": control_radius,
		"maximum_hub_triangles": maximum_triangles, "hub_meshes": hub_meshes.size(), "negative_controls": 4,
		"projection_facts": "invented read-only", "general_machine_routing": "not_established"}))

func batch_expected_mesh(role: String, units: int) -> Mesh:
	# One tile fixes the physical gear radius; native ratio changes tooth density.
	var radius := PRESENTED_GEAR_RADIUS
	if role == "GearTooth":
		return Assets.tooth_mesh(radius, units * 8)
	if role == "GearSpoke":
		return Assets.Visuals.box_mesh(Vector3(radius * 0.56 - minf(0.16, radius * 0.34) + 0.04, 0.08, 0.09))
	var bolt := CylinderMesh.new()
	bolt.top_radius = 0.022
	bolt.bottom_radius = 0.022
	bolt.height = 0.012
	bolt.radial_segments = 6
	return bolt

func batch_expected_member(role: String, index: int, units: int, point: Vector3, normal: bool) -> Vector3:
	# Scalar reference for the prior individual-piece layout. This does not
	# decode a buffer or use the production poses, Basis or batching helper.
	var radius := PRESENTED_GEAR_RADIUS
	var hub := minf(0.16, radius * 0.34)
	if role == "GearTooth":
		var angle := float(index) * TAU / float(units * 8)
		return Vector3(cos(angle) * point.x + sin(angle) * point.z, point.y,
			-sin(angle) * point.x + cos(angle) * point.z)
	if role == "GearSpoke":
		var angle := float(index) * PI / 2.0
		var offset := 0.0 if normal else (hub + radius * 0.56) / 2.0
		return Vector3(cos(angle) * (point.x + offset) - sin(angle) * point.z, point.y,
			sin(angle) * (point.x + offset) + cos(angle) * point.z)
	var angle := float(index >> 1) * PI / 2.0
	var side := -1.0 if index % 2 == 0 else 1.0
	var origin := Vector3.ZERO if normal else Vector3(cos(angle) * hub * 0.65, side * 0.108, sin(angle) * hub * 0.65)
	return origin + Vector3(point.x, point.y * side, point.z * side)

func batch_expected_world(point: Vector3, axis: int, center: Vector3, angle: float, normal: bool) -> Vector3:
	var rotated := Vector3(cos(angle) * point.x + sin(angle) * point.z, point.y,
		-sin(angle) * point.x + cos(angle) * point.z)
	var mapped := rotated
	if axis == 0:
		mapped = Vector3(rotated.y, -rotated.x, rotated.z)
	elif axis == 2:
		mapped = Vector3(rotated.x, -rotated.z, rotated.y)
	return mapped if normal else center + mapped

func batch_geometry_report(group: MultiMeshInstance3D, role: String, units: int,
		axis: int, center: Vector3, angle: float, tint: Color) -> Dictionary:
	var batch := group.multimesh
	var count := units * 8 if role == "GearTooth" else (4 if role == "GearSpoke" else 8)
	var data := batch.buffer
	var result := {"role": role, "units": units, "axis": axis, "angle": angle,
		"valid": false, "vertices_read": 0, "position_error": 0.0, "normal_error": 0.0,
		"bounds_valid": true, "attributes_exact": false}
	if batch.instance_count != count or batch.transform_format != MultiMesh.TRANSFORM_3D or batch.use_colors or batch.use_custom_data or data.size() != count * 12:
		return result
	var expected_mesh := batch_expected_mesh(role, units)
	var actual := batch.mesh.surface_get_arrays(0)
	var expected := expected_mesh.surface_get_arrays(0)
	var points: PackedVector3Array = actual[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = actual[Mesh.ARRAY_NORMAL]
	var reference_points: PackedVector3Array = expected[Mesh.ARRAY_VERTEX]
	var reference_normals: PackedVector3Array = expected[Mesh.ARRAY_NORMAL]
	if points.size() != reference_points.size() or normals.size() != points.size():
		return result
	result.attributes_exact = actual[Mesh.ARRAY_TEX_UV] == expected[Mesh.ARRAY_TEX_UV] and actual[Mesh.ARRAY_TANGENT] == expected[Mesh.ARRAY_TANGENT] and actual[Mesh.ARRAY_INDEX] == expected[Mesh.ARRAY_INDEX]
	var bound := batch.custom_aabb.grow(0.000001)
	var first_mismatch: Dictionary = {}
	for index in range(count):
		var local := batch_pose(batch, index)
		var pose: Transform3D = group.get_parent().transform * group.transform * local
		for vertex in range(points.size()):
			var actual_point: Vector3 = pose * points[vertex]
			var expected_point := batch_expected_world(batch_expected_member(role, index, units, reference_points[vertex], false), axis, center, angle, false)
			var actual_normal: Vector3 = pose.basis * normals[vertex]
			var expected_normal := batch_expected_world(batch_expected_member(role, index, units, reference_normals[vertex], true), axis, center, angle, true)
			var position_error := actual_point.distance_to(expected_point)
			var normal_error := actual_normal.distance_to(expected_normal)
			result.position_error = maxf(result.position_error, position_error)
			result.normal_error = maxf(result.normal_error, normal_error)
			result.bounds_valid = result.bounds_valid and bound.has_point(local * points[vertex])
			result.vertices_read += 1
			if first_mismatch.is_empty() and (position_error > 0.000004 or normal_error > 0.000002):
				first_mismatch = {"instance": index, "vertex": vertex,
					"actual": [actual_point.x, actual_point.y, actual_point.z],
					"expected": [expected_point.x, expected_point.y, expected_point.z]}
	var surface_role := "cast" if role == "GearSpoke" else "worked"
	var color := Color("b8c3bb") if role == "HubFastener" else tint
	result["material_valid"] = group.material_override == Finish.material(surface_role, color, 0.85, 0.38) and group.get_meta("surface_role") == surface_role
	result["culling_bounds"] = [batch.custom_aabb.position.x, batch.custom_aabb.position.y, batch.custom_aabb.position.z,
		batch.custom_aabb.size.x, batch.custom_aabb.size.y, batch.custom_aabb.size.z]
	result["first_mismatch"] = first_mismatch
	result.valid = result.attributes_exact and result.material_valid and result.bounds_valid and result.position_error <= 0.000004 and result.normal_error <= 0.000002
	return result

func batch_control_copy(source: MultiMeshInstance3D) -> MultiMeshInstance3D:
	var copy := MultiMeshInstance3D.new()
	copy.multimesh = MultiMesh.new()
	copy.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	copy.multimesh.mesh = source.multimesh.mesh
	copy.multimesh.instance_count = source.multimesh.instance_count
	copy.multimesh.buffer = source.multimesh.buffer
	copy.multimesh.custom_aabb = source.multimesh.custom_aabb
	copy.material_override = source.material_override
	copy.set_meta("surface_role", source.get_meta("surface_role"))
	source.get_parent().add_child(copy)
	return copy

func check_gear_batches() -> void:
	const HEIGHT := 0.825 + 0.4125
	var assemblies := 0
	var expanded_vertices := 0
	var maximum_position_error := 0.0
	var maximum_normal_error := 0.0
	var controls := 0
	var mesh_nodes_saved := 0
	var geometry_seen: Dictionary = {}
	for units in [1, 2, 3, 8]:
		for axis in range(3):
			var host := MaterialHost.new()
			host.state = {"context": "batch-cog", "options": {"native": true}, "entities": {},
				"transmission_parts": {"gear": {"kind": "gear", "center": [-4, 1, 8], "axis": axis, "teeth": units, "generation": 1},
					"peer": {"kind": "gear", "center": [0, 1, 8], "axis": axis, "teeth": units, "generation": 2}},
				"motion": {"gear": {"state": "rotating", "numerator": -1, "denominator": 2},
					"peer": {"state": "stopped", "numerator": 0, "denominator": 1}}, "engagements": []}
			var before: Dictionary = host.state.duplicate(true)
			var view := Presenter.new()
			view.configure(host)
			var gear := material_part(view, "gear")
			var peer := material_part(view, "peer")
			verify(gear != null and peer != null, "Both actual presenter anchors consume the original disclosed part facts.")
			if gear == null or peer == null:
				view.free()
				continue
			var original_pick: StaticBody3D = gear.get_node("Pick")
			var original_shape: CylinderShape3D = original_pick.get_child(0).shape
			var original_gear_id := gear.get_instance_id()
			var original_pick_id := original_pick.get_instance_id()
			for member in [gear, peer]:
				var draw_nodes := 0
				for child in member.get_children():
					if child is GeometryInstance3D and child.has_meta("asset_role"):
						draw_nodes += 1
				verify(draw_nodes == 10 and roles(member, "GearTooth") == units * 8
					and roles(member, "GearSpoke") == 4 and roles(member, "HubFastener") == 8
					and roles(member, "Shaft") == 1 and roles(member, "ShaftCollar") == 2
					and roles(member, "ShaftKey") == 2,
					"Ten render objects retain the detailed gear and its five fitted shaft pieces.")
				mesh_nodes_saved += units * 8 + 19 - draw_nodes
				assemblies += 1
			for phase in range(2):
				if phase == 1:
					view.advance_visual_motion(0.1)
				for member in [gear, peer]:
					var moving: bool = member == gear
					var center := Vector3(-1.65 if moving else 0.0, HEIGHT, 3.3)
					var angle := PRESENTED_HALF_RATE_STEP if moving and phase == 1 else 0.0
					var tint := Color("687a7b")
					for role in ["GearTooth", "GearSpoke", "HubFastener"]:
						var group: MultiMeshInstance3D = member.get_node(role)
						var report := batch_geometry_report(group, role, units, axis, center, angle, tint)
						print(JSON.stringify(report))
						verify(report.valid, "Actual submitted vertices, normals, attributes, materials and local culling match the individual-piece reference.")
						expanded_vertices += report.vertices_read
						maximum_position_error = maxf(maximum_position_error, report.position_error)
						maximum_normal_error = maxf(maximum_normal_error, report.normal_error)
						var key_value := str([role, units])
						verify(not geometry_seen.has(key_value) or geometry_seen[key_value] == group.multimesh,
							"Equivalent dimensions reuse batch data across colours, positive axes and signed parent motion.")
						geometry_seen[key_value] = group.multimesh
					var hub: MeshInstance3D = member.get_node("Hub")
					verify(bore_mesh_facts(hub.mesh).minimum_radius > 0.0388 and hub.transform == Transform3D.IDENTITY,
						"Batching leaves the open machined hub and its original mounting intact.")
			verify(host.state == before and is_equal_approx(view.visual_angle("gear"), PRESENTED_HALF_RATE_STEP) and view.visual_angle("peer") == 0.0,
				"The original signed motion and stopped peer remain distinct without mutating the host projection.")
			verify(is_equal_approx(original_shape.radius, PRESENTED_GEAR_RADIUS) and is_equal_approx(original_shape.height, 0.24)
				and original_pick.collision_layer == 4 and original_pick.collision_mask == 0,
				"The existing pick geometry and collision role remain exact.")
			view.refresh()
			verify(material_part(view, "gear") == gear and gear.get_node("Pick") == original_pick and original_pick.get_child(0).shape == original_shape,
				"Unchanged refresh preserves the full anchor and pick identity.")
			host.ready = false
			var old_basis := gear.basis
			view.advance_visual_motion(0.1)
			verify(gear.basis == old_basis and is_equal_approx(view.visual_angle("gear"), PRESENTED_HALF_RATE_STEP),
				"An unavailable source cannot keep moving the new render groups.")
			host.ready = true
			if units == 2 and axis == 0:
				var source: MultiMeshInstance3D = gear.get_node("GearTooth")
				var saved_buffer := source.multimesh.buffer
				for control in range(5):
					var bad := batch_control_copy(source)
					var data := bad.multimesh.buffer
					if control == 0:
						bad.multimesh.instance_count -= 1
						bad.multimesh.buffer = data.slice(0, bad.multimesh.instance_count * 12)
					elif control == 1:
						data[12 + 3] += 0.002
						bad.multimesh.buffer = data
					elif control == 2:
						var swap := data[12 + 2]
						data[12 + 2] = data[12 + 8]
						data[12 + 8] = swap
						bad.multimesh.buffer = data
					elif control == 3:
						bad.multimesh.custom_aabb = AABB(Vector3(-0.001, -0.001, -0.001), Vector3.ONE * 0.002)
					else:
						var altered := StandardMaterial3D.new()
						altered.albedo_color = Color.RED
						bad.material_override = altered
					var report := batch_geometry_report(bad, "GearTooth", units, axis, Vector3(-1.65, HEIGHT, 3.3), PRESENTED_HALF_RATE_STEP, Color("687a7b"))
					var rejected_for_change: bool = report.vertices_read == 0 if control == 0 else (
						report.position_error > 0.000004 if control in [1, 2] else (
							not report.bounds_valid if control == 3 else not report.material_valid))
					print(JSON.stringify({"control": control, "rejected": not report.valid,
						"changed_property_rejected": rejected_for_change, "first_mismatch": report.get("first_mismatch", {})}))
					verify(not report.valid and rejected_for_change,
						"An altered count, displacement, transposed rotation, culling box or material is rejected for its changed property.")
					controls += 1
					bad.free()
				verify(source.multimesh.buffer == saved_buffer, "Negative controls leave the shared real batch data unchanged.")
			host.state.transmission_parts.gear.generation += 1
			view.refresh()
			var replacement := material_part(view, "gear")
			verify(replacement.get_instance_id() != original_gear_id and replacement.get_node("Pick").get_instance_id() != original_pick_id and view.visual_angle("gear") == 0.0
				and replacement.get_node("GearTooth").multimesh == geometry_seen[str(["GearTooth", units])],
				"Rebuilding changes instance identity and resets presentation phase while reusing geometry, without retargeting old picks.")
			view.free()
	print(JSON.stringify({"assemblies": assemblies, "expanded_vertices": expanded_vertices,
		"maximum_position_error_metres": maximum_position_error, "maximum_normal_error": maximum_normal_error,
		"render_nodes_saved": mesh_nodes_saved, "negative_controls": controls,
		"evidence": "Submitted headless bulk buffers and raw mesh arrays; no GPU draw or performance result."}))

func coupling_node(shaft: Node3D) -> Node3D:
	for child in shaft.get_children():
		if child is Node3D and child.get_meta("shaft_coupling", false):
			return child
	return null

func splice_node(shaft: Node3D) -> Node3D:
	for child in shaft.get_children():
		if child is Node3D and child.get_meta("shaft_splice", false):
			return child
	return null

func coupling_material_valid(material: StandardMaterial3D) -> bool:
	return material != null and material.albedo_texture != null and material.albedo_texture.get_width() == 1024 \
		and material.normal_enabled and material.normal_texture != null and material.normal_texture.get_width() == 512 \
		and material.metallic_texture != null and material.metallic_texture == material.roughness_texture \
		and material.ao_texture == material.metallic_texture and material.ao_enabled \
		and material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE \
		and material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN \
		and material.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED \
		and material.cull_mode == BaseMaterial3D.CULL_DISABLED

func check_shaft_couplings() -> void:
	var assemblies := 0
	var minimum_gap := INF
	var minimum_hub_gap := INF
	var maximum_radius := 0.0
	var shared_mesh: Mesh
	for axis in range(3):
		for side in [-1, 1]:
			for reverse in [false, true]:
				var host := MaterialHost.new()
				var shaft_center := [-4, 1, 8]
				var gear_center: Array = shaft_center.duplicate()
				gear_center[axis] += side
				host.state = {"context": "coupling-resource-fixture", "options": {"native": true}, "entities": {},
					"transmission_parts": {
						"gear": {"kind": "gear", "center": gear_center, "axis": axis, "teeth": 2, "generation": 1},
						"shaft": {"kind": "shaft", "center": shaft_center, "axis": axis, "half_span": 2, "generation": 2}},
					"motion": {"gear": {"state": "rotating", "numerator": -1, "denominator": 2},
						"shaft": {"state": "rotating", "numerator": -1, "denominator": 2}}, "engagements": []}
				var view := Presenter.new()
				view.configure(host)
				var shaft := material_part(view, "shaft")
				var gear := material_part(view, "gear")
				verify(shaft != null and gear != null, "The real presenter consumes both disclosed native part records.")
				if shaft == null or gear == null:
					view.free()
					continue
				var shaft_radius := bore_shaft_envelope(shaft)
				var original_core: Mesh = shaft.get_node("Shaft").mesh
				var original_hub: Mesh = gear.get_node("Hub").mesh
				verify(coupling_node(shaft) == null, "Coaxial geometry alone cannot invent a coupling without a confirmed engagement.")
				host.state.engagements = [{"a": "gear" if reverse else "shaft", "b": "shaft" if reverse else "gear", "kind": 1}]
				var before: Dictionary = host.state.duplicate(true)
				view.refresh()
				shaft = material_part(view, "shaft")
				gear = material_part(view, "gear")
				var fitting := coupling_node(shaft)
				verify(fitting != null and Assets.coupling_status == "ready", "The exact confirmed coaxial edge mounts a complete sourced coupling in either endpoint order.")
				if fitting == null:
					view.free()
					continue
				verify(fitting.get_meta("shaft") == "shaft" and fitting.get_meta("gear") == "gear"
					and fitting.get_child_count() == 2 and fitting.get_script() == null,
					"The fitting keeps explicit endpoint identities and only two passive render halves.")
				var expected_center: float = float(side) * (0.4125 - 0.146)
				verify(fitting.position.is_equal_approx(Vector3(0, expected_center, 0))
					and shaft.position == Presenter.world_center(shaft_center)
					and shaft.basis.y == [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis],
					"The proper positive native axis mounts the compact joint towards shaft interior without moving either native centre.")
				verify(shaft.get_node("Shaft").mesh == original_core and gear.get_node("Hub").mesh == original_hub,
					"The exact original shaft length and open gear hub resources remain reused.")
				var pick: StaticBody3D = shaft.get_node("Pick")
				var shape: CylinderShape3D = pick.get_child(0).shape
				verify(pick.get_meta("entity") == "shaft" and pick.collision_layer == Presenter.Geometry.PICK_LAYER and pick.collision_mask == 0
					and is_equal_approx(shape.radius, 0.08) and is_equal_approx(shape.height, 1.65),
					"The original shaft selection identity, mask, radius and full span remain unchanged.")
				var gear_pick: CylinderShape3D = gear.get_node("Pick").get_child(0).shape
				verify(is_equal_approx(gear_pick.radius, Presenter.Geometry.PITCH / 2.0) and is_equal_approx(gear_pick.height, 0.24),
					"The coupling does not change the existing cog pick envelope.")
				for half: MeshInstance3D in fitting.get_children():
					if shared_mesh == null:
						shared_mesh = half.mesh
					verify(half.mesh == shared_mesh and half.mesh.get_surface_count() == 2
						and is_equal_approx(half.basis.determinant(), 1.0),
						"Both halves reuse one two-surface resource with proper rotations, without reflection or rigid-detail stretching.")
					verify(coupling_material_valid(half.get_surface_override_material(0))
						and half.get_surface_override_material(1) == Finish.material("worked", Color("a6b4af"), 0.85, 0.38),
						"Source UVs use the qualified albedo, OpenGL normal and packed channels; the authored cut has the existing worked-metal finish.")
					var facts := bore_mesh_facts(half.mesh, half.transform)
					minimum_gap = minf(minimum_gap, facts.minimum_radius - shaft_radius)
					maximum_radius = maxf(maximum_radius, facts.maximum_radius)
					verify(facts.triangles == 360 and facts.minimum_radius - shaft_radius > 0.001
						and facts.maximum_radius < shape.radius
						and maxf(absf(facts.low), absf(facts.high)) <= Assets.COUPLING_HALF_LENGTH + 0.000001,
						"Actual imported raw triangles preserve the full shaft/collar/key passage and stay inside the original radial envelope.")
					var fit_valid := true
					for point in bore_triangles(half.mesh):
						var at: Vector3 = fitting.transform * half.transform * point
						var hub_gap: float = absf(at.y - float(side) * 0.4125) - 0.114
						minimum_hub_gap = minf(minimum_hub_gap, hub_gap)
						fit_valid = fit_valid and absf(at.y) < shape.height / 2.0 and hub_gap > 0.001
					verify(fit_valid, "All actual fitting vertices stay within shaft ends and clear the existing hub and fastener end planes.")
					for surface in range(2):
						var arrays := half.mesh.surface_get_arrays(surface)
						var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
						var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
						var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
						var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
						var valid := points.size() == normals.size() and uvs.size() == points.size() and tangents.size() == points.size() * 4
						for n in range(points.size()):
							valid = valid and points[n].is_finite() and normals[n].is_finite() and uvs[n].is_finite()
							if tangents.size() == points.size() * 4:
								var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
								valid = valid and tangent.is_finite() and absf(normals[n].dot(tangent)) < 0.0002
						verify(valid, "Both actual surfaces retain finite UV, normal and generated tangent attributes within the declared packed representation bound.")
				var old_pose := fitting.transform
				view.advance_visual_motion(0.1)
				var expected_angle := -0.05 * Presenter.VISUAL_RADIANS_PER_SECOND
				verify(is_equal_approx(view.visual_angle("shaft"), expected_angle) and fitting.transform == old_pose and host.state == before,
					"Both rigid halves follow the existing cosmetic shaft phase without state mutation or an independent clock.")
				host.ready = false
				view.advance_visual_motion(0.1)
				verify(is_equal_approx(view.visual_angle("shaft"), expected_angle), "Unavailable confirmed motion freezes the coupling with its owning shaft.")
				host.state.engagements = []
				view.refresh()
				verify(coupling_node(material_part(view, "shaft")) == null, "Removing the confirmed edge removes its art instead of retaining a decorative connection.")
				for invalid in [0, true, "1"]:
					host.state.engagements = [{"a": "shaft", "b": "gear", "kind": invalid}]
					view.refresh()
					verify(coupling_node(material_part(view, "shaft")) == null, "Wrong or untyped engagement kinds cannot grant a fitting.")
				host.state.engagements = [{"a": "shaft", "b": "missing", "kind": 1}]
				view.refresh()
				verify(coupling_node(material_part(view, "shaft")) == null, "An absent confirmed endpoint cannot produce a fitting.")
				host.state.engagements = [{"a": "shaft", "b": "gear", "kind": 1}]
				host.state.transmission_parts.gear.generation += 1
				view.refresh()
				var rebuilt := coupling_node(material_part(view, "shaft"))
				verify(rebuilt != null and rebuilt.get_child(0).mesh == shared_mesh and view.visual_angle("gear") == 0.0,
					"Rebuilding a new part generation reuses geometry without restoring removed render instances or old part phase.")
				assemblies += 1
				view.free()
	if Assets.coupling_finish != null:
		var wrong := Assets.coupling_finish.duplicate() as StandardMaterial3D
		wrong.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		verify(not coupling_material_valid(wrong), "The material oracle rejects a swapped scalar channel.")
	verify(bore_mesh_facts(bore_control_mesh(0.02)).minimum_radius < 0.037
		and bore_triangle_radius(Vector2(-0.1, -0.1), Vector2(0.1, -0.1), Vector2(0, 0.1)) == 0.0,
		"The independent raw-face oracle rejects undersized and plugged passages.")
	print(JSON.stringify({"assemblies": assemblies, "axes": 3, "halves_per_joint": 2,
		"minimum_shaft_clearance_metres": minimum_gap, "minimum_hub_end_gap_metres": minimum_hub_gap,
		"maximum_fitting_radius_metres": maximum_radius,
		"facts": "Invented read-only native projections consumed by the real presenter.",
		"native_contact_force_and_general_machine_routing": "not_established"}))

func check_shaft_splices() -> void:
	var assemblies := 0
	var shared_mesh: Mesh
	for axis in range(3):
		for side in [-1, 1]:
			for reverse in [false, true]:
				var host := MaterialHost.new()
				var first_center := [-4, 0, 8]
				var second_center: Array = first_center.duplicate()
				second_center[axis] += side * 4
				host.state = {"context": "shaft-splice-fixture", "options": {"native": true}, "entities": {},
					"transmission_parts": {
						"first": {"kind": "shaft", "center": first_center, "axis": axis, "half_span": 2, "generation": 1},
						"second": {"kind": "shaft", "center": second_center, "axis": axis, "half_span": 2, "generation": 2}},
					"motion": {"first": {"state": "rotating", "numerator": 1, "denominator": 2},
						"second": {"state": "rotating", "numerator": 1, "denominator": 2}},
					"engagements": []}
				var view := Presenter.new()
				view.configure(host)
				var original_radius := bore_shaft_envelope(material_part(view, "first"))
				verify(splice_node(material_part(view, "first")) == null,
					"Touching shaft tiles alone cannot invent a visible joint.")
				host.state.engagements = [{"a": "second" if reverse else "first",
					"b": "first" if reverse else "second", "kind": 1}]
				var before: Dictionary = host.state.duplicate(true)
				view.refresh()
				var owner_id := "second" if reverse else "first"
				var other_id := "first" if reverse else "second"
				var owner := material_part(view, owner_id)
				var other := material_part(view, other_id)
				var fitting := splice_node(owner)
				verify(fitting != null and splice_node(other) == null and owner.get_node("Pick") != null,
					"One confirmed shaft pair mounts one passive joint without another selection body.")
				if fitting == null:
					view.free()
					continue
				var local_side: int = side * (-1 if reverse else 1)
				var owner_center: Array = second_center if reverse else first_center
				var seam: Vector3 = Presenter.world_center(owner_center) + [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis] * float(local_side) * 2.0 * Presenter.UNIT
				verify(fitting.get_meta("first_shaft") == owner_id and fitting.get_meta("second_shaft") == other_id
					and fitting.get_child_count() == 2 and fitting.get_script() == null
					and (owner.position + owner.basis * fitting.position).is_equal_approx(seam),
					"Both source halves sit at the exact shared shaft endpoint with stable confirmed identities.")
				for half: MeshInstance3D in fitting.get_children():
					if shared_mesh == null:
						shared_mesh = half.mesh
					var facts := bore_mesh_facts(half.mesh, half.transform)
					verify(half.mesh == shared_mesh and facts.triangles == 360
						and facts.minimum_radius > original_radius + 0.001
						and facts.maximum_radius < 0.08
						and maxf(absf(facts.low), absf(facts.high)) <= Assets.COUPLING_HALF_LENGTH + 0.000001,
						"The source mesh clears both fitted shaft ends without stretching or widening their pick bodies.")
				var owner_core: Mesh = owner.get_node("Shaft").mesh
				var other_core: Mesh = other.get_node("Shaft").mesh
				view.advance_visual_motion(0.1)
				verify(host.state == before and owner.get_node("Shaft").mesh == owner_core
					and other.get_node("Shaft").mesh == other_core,
					"Visual motion retains both original shaft resources and cannot mutate native state.")
				host.state.engagements = []
				view.refresh()
				verify(splice_node(material_part(view, owner_id)) == null,
					"Removing the confirmed edge removes the joint art.")
				for invalid in [0, true, "1"]:
					host.state.engagements = [{"a": owner_id, "b": other_id, "kind": invalid}]
					view.refresh()
					verify(splice_node(material_part(view, owner_id)) == null,
						"An untyped or unrelated edge cannot mount a shaft joint.")
				host.state.engagements = [{"a": owner_id, "b": other_id, "kind": 1}]
				host.state.transmission_parts[other_id].center[axis] += local_side
				view.refresh()
				verify(splice_node(material_part(view, owner_id)) == null,
					"A confirmed but separated shaft pair cannot gain a visual bridge.")
				host.state.transmission_parts[other_id].center[axis] -= local_side * 2
				view.refresh()
				verify(splice_node(material_part(view, owner_id)) == null,
					"Overlapping shaft extents cannot hide behind the butt-joint art.")
				host.state.transmission_parts[other_id].center[axis] += local_side
				var radial_axis := (axis + 1) % 3
				host.state.transmission_parts[other_id].center[radial_axis] += 4
				view.refresh()
				verify(splice_node(material_part(view, owner_id)) == null,
					"Offset parallel shafts cannot receive a coaxial visual joint.")
				host.state.transmission_parts[other_id].center[radial_axis] -= 4
				host.state.transmission_parts[other_id].axis = radial_axis
				view.refresh()
				verify(splice_node(material_part(view, owner_id)) == null,
					"A shaft on another axis cannot share the butt-joint fitting.")
				assemblies += 1
				view.free()
	print(JSON.stringify({"shaft_splice_assemblies": assemblies, "axes": 3, "source_halves_per_joint": 2,
		"facts": "Invented confirmed projections consumed by the real presenter.",
		"native_gameplay_and_visible_quality": "not_established"}))

func _initialize() -> void:
	if not parse_options():
		return
	if mode == "resource-images":
		check_resource_images()
		quit(1 if failed else 0)
		return
	if mode == "shaft-coupling-only":
		check_shaft_couplings()
		check_shaft_splices()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "mode": mode,
			"native_gameplay": "not_run", "rendered_quality": "not_assessed", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	if mode == "gear-batch-only":
		check_gear_batches()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "mode": mode,
			"native_gameplay": "not_run", "rendered_quality": "not_assessed", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	if mode == "gear-bore-only":
		check_gear_bores()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "mode": mode,
			"unique_meshes": checked_meshes.size(), "maximum_packed_tangent_dot": max_tangent_dot,
			"native_gameplay": "not_run", "rendered_quality": "not_assessed", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	if mode == "prepare-transmission-maps":
		prepare_material_maps()
		return
	if mode == "material-only" or mode == "historical-material-only":
		check_materials()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "mode": mode,
			"scope": "actual material assignment over invented projection facts", "native_gameplay": "not_run", "rendered_quality": "not_assessed", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	for units in [1, 2, 3]:
		var mesh: ArrayMesh = Assets.tooth_mesh(float(units) * 0.4125, units * 8)
		verify(mesh == Assets.tooth_mesh(float(units) * 0.4125, units * 8), "The exact tooth profile is cached by its geometry inputs.")
		check_mesh(mesh)
	if mode != "tooth-only":
		check_assemblies()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"mode": mode,
		"unique_meshes": checked_meshes.size(), "visual_instances": visual_instances,
		"maximum_packed_tangent_dot": max_tangent_dot, "rendered_quality": "not_assessed", "desktop": "not_used"}))
	quit(1 if failed else 0)
