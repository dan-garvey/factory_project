extends SceneTree
## Fitted transmission geometry only. No World, input, network or desktop.
const Assets = preload("res://opening/native_transmission_assets.gd")
const Presenter = preload("res://opening/native_transmission_presenter.gd")
const Finish = Assets.Finish
const WORKED_SIZE := 256
const WORKED_RELIEF_METRES := 0.00001
var checks := 0
var failed := false
var checked_meshes: Dictionary = {}
var max_tangent_dot := 0.0
var visual_instances := 0

class MaterialHost extends RefCounted:
	var state: Dictionary = {}
	func _can_present_confirmed_motion() -> bool:
		return true

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
	var args := OS.get_cmdline_user_args()
	args.remove_at(0)
	if args.size() != 2:
		push_error("Use SOURCE_DIRECTORY PREPARED_ASSET_DIRECTORY.")
		quit(1)
		return
	var source := args[0]
	var output := args[1]
	var pins := {"normal": "3e2b0ddc58564d28685f0949ede839fc680c84ae8a0f97127de6aa91ab5b392c",
		"roughness": "e7756912587a45d0a4bd93465e487dde09084486cda922014c07b7c3947d4a34"}
	for file_name in Finish.FILES.values():
		if FileAccess.file_exists(output.path_join(file_name)):
			push_error("Refuse an existing prepared transmission output.")
			quit(1)
			return
	for role in pins:
		if FileAccess.get_sha256(source.path_join(role + ".png")) != pins[role]:
			push_error("Refuse an unpinned transmission source: " + role)
			quit(1)
			return
	var report: Dictionary = {"status": "pass", "maps": {}}
	for role in pins:
		var image := Image.load_from_file(source.path_join(role + ".png"))
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
		var result := encode_map(image, output.path_join(Finish.FILES["cast_" + role]))
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
		var result := encode_map(worked_images[role], output.path_join(Finish.FILES[role]))
		if result.status != "pass":
			quit(1)
			return
		report.maps[role] = result
	report["worked_recipe"] = {"seed": 74391, "tile_metres": Finish.WORKED_METRES,
		"height_amplitude_metres": WORKED_RELIEF_METRES, "maximum_normal_length_error": maximum_worked_error,
		"geometry_displacement": false, "runtime_generation": false}
	print(JSON.stringify(report))
	quit(0)

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

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

func check_bounds(node: Node3D, pose: Transform3D, center: Vector3, axis: Vector3,
		radius: float, half_length: float) -> void:
	verify(not node is CollisionObject3D and not node is CollisionShape3D and node.get_script() == null,
		"The asset module supplies no collision, input or state-owner node.")
	if node is MeshInstance3D:
		visual_instances += 1
		check_mesh(node.mesh)
		var bounded := true
		var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point: Vector3 = pose * vertex - center
			var along := point.dot(axis)
			var radial := point - axis * along
			bounded = bounded and absf(along) <= half_length + 0.000001 and radial.length() <= radius + 0.000001
		verify(bounded, "Fitted details stay inside the independently specified native/pick envelope on the actual axis.")
	for child in node.get_children():
		if child is Node3D:
			check_bounds(child, pose * child.transform, center, axis, radius, half_length)

func roles(node: Node, role: String) -> int:
	var count := 1 if node.get_meta("asset_role", "") == role else 0
	for child in node.get_children():
		count += roles(child, role)
	return count

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
		verify(gear.get_node("GearTooth").mesh == Assets.tooth_mesh(0.825, 16),
			"Repeated teeth share one closed authored tooth asset.")
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
		check_bounds(gear, Transform3D.IDENTITY, Vector3.ZERO, Vector3.UP, radius, 0.12)
		gear.free()

func material_part(root_node: Node, id: String) -> Node3D:
	for child in root_node.get_children():
		if child.get_meta("entity", "") == id:
			return child
	return null

func check_materials() -> void:
	var historical := OS.get_cmdline_user_args().has("--historical-material-only")
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
			var tint := Color("ba9459") if moving else Color("687a7b")
			var expected_colors := {"Gear": tint, "GearSpoke": tint, "GearTooth": tint,
				"Hub": Color("a6b4af"), "HubFastener": Color("b8c3bb"),
				"Shaft": tint, "ShaftCollar": Color("a6b4af"), "ShaftKey": Color("b87945")}
			var counts := [0, 0, 0]
			for part_node in [gear, shaft]:
				for child in part_node.get_children():
					if not child is MeshInstance3D or not child.has_meta("asset_role"):
						continue
					var role: String = child.get_meta("asset_role")
					var expected_surface := "copper" if role == "ShaftKey" else ("cast" if role in ["Gear", "GearSpoke"] else "worked")
					var expected_color: Color = expected_colors[role]
					var material := child.material_override as StandardMaterial3D
					surface_instances += 1
					counts[["cast", "worked", "copper"].find(expected_surface)] += 1
					verify(material != null and child.get_meta("surface_role") == expected_surface
						and material.albedo_color == expected_color and material.albedo_texture == null,
						"The actual part keeps its original motion or fixed metal tint and receives its declared surface role.")
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
			verify(counts == [5, 28, 2], "Each actual assembly separates five cast, twenty-eight worked and two copper pieces.")
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

func _initialize() -> void:
	if OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "--prepare-transmission-maps":
		prepare_material_maps()
		return
	if OS.get_cmdline_user_args().has("--material-only") or OS.get_cmdline_user_args().has("--historical-material-only"):
		check_materials()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"scope": "actual material assignment over invented projection facts", "native_gameplay": "not_run", "rendered_quality": "not_assessed", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	for units in [1, 2, 3]:
		var mesh: ArrayMesh = Assets.tooth_mesh(float(units) * 0.4125, units * 8)
		verify(mesh == Assets.tooth_mesh(float(units) * 0.4125, units * 8), "The exact tooth profile is cached by its geometry inputs.")
		check_mesh(mesh)
	if "--tooth-only" not in OS.get_cmdline_user_args():
		check_assemblies()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"unique_meshes": checked_meshes.size(), "visual_instances": visual_instances,
		"maximum_packed_tangent_dot": max_tangent_dot, "rendered_quality": "not_assessed", "desktop": "not_used"}))
	quit(1 if failed else 0)
