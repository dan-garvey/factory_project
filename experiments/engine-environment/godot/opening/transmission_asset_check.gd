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
				and is_equal_approx(empty_facts.maximum_radius, minf(0.16, units * 0.4125 * 0.34))
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
			verify(is_equal_approx(gear_pick.radius, units * 0.4125 + 0.103125) and is_equal_approx(gear_pick.height, 0.24)
				and is_equal_approx(shaft_pick.radius, 0.08) and is_equal_approx(shaft_pick.height, 0.825),
				"The bore changes no gear or shaft selection envelope or endpoint length.")
			verify(roles(gear, "GearTooth") == units * 8 and roles(gear, "GearSpoke") == 4 and roles(gear, "HubFastener") == 8,
				"The exact original peripheral assembly remains present for every disclosed size.")
			verify(hub.material_override == Finish.material("worked", Color("a6b4af"), 0.85, 0.38)
				and hub.get_script() == null and hub.transform == Transform3D.IDENTITY,
				"The open hub retains its cached machined finish and has no independent motion, offset or controller.")
			view.advance_visual_motion(0.1)
			verify(is_equal_approx(view.visual_angle("gear"), -0.04) and is_equal_approx(view.visual_angle("shaft"), -0.04)
				and gear.basis == shaft.basis and host.state == before,
				"The existing signed cosmetic rate turns the same rigid assembly without changing the invented native facts.")
			var cache_key := str(minf(0.16, units * 0.4125 * 0.34))
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
	var radius := float(units) * 0.4125
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
	var radius := units * 0.4125
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
		"bounds_valid": true, "attributes_exact": false, "buffer": Array(data)}
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
				verify(draw_nodes == 5 and roles(member, "GearTooth") == units * 8
					and roles(member, "GearSpoke") == 4 and roles(member, "HubFastener") == 8,
					"Five actual render objects retain every detailed piece represented by the prior individual assembly.")
				mesh_nodes_saved += units * 8 + 14 - draw_nodes
				assemblies += 1
			for phase in range(2):
				if phase == 1:
					view.advance_visual_motion(0.1)
				for member in [gear, peer]:
					var moving: bool = member == gear
					var center := Vector3(-1.65 if moving else 0.0, 0.9125, 3.3)
					var angle := -0.04 if moving and phase == 1 else 0.0
					var tint := Color("ba9459") if moving else Color("687a7b")
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
			verify(host.state == before and is_equal_approx(view.visual_angle("gear"), -0.04) and view.visual_angle("peer") == 0.0,
				"The original signed motion and stopped peer remain distinct without mutating the host projection.")
			verify(is_equal_approx(original_shape.radius, units * 0.4125 + 0.103125) and is_equal_approx(original_shape.height, 0.24)
				and original_pick.collision_layer == 4 and original_pick.collision_mask == 0,
				"The existing pick geometry and collision role remain exact.")
			view.refresh()
			verify(material_part(view, "gear") == gear and gear.get_node("Pick") == original_pick and original_pick.get_child(0).shape == original_shape,
				"Unchanged refresh preserves the full anchor and pick identity.")
			host.ready = false
			var old_basis := gear.basis
			view.advance_visual_motion(0.1)
			verify(gear.basis == old_basis and is_equal_approx(view.visual_angle("gear"), -0.04),
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
					var report := batch_geometry_report(bad, "GearTooth", units, axis, Vector3(-1.65, 0.9125, 3.3), -0.04, Color("ba9459"))
					print(JSON.stringify({"control": control, "rejected": not report.valid, "first_mismatch": report.get("first_mismatch", {})}))
					verify(not report.valid, "An altered count, displacement, transposed rotation, culling box or material is rejected.")
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

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--gear-batch-only"):
		check_gear_batches()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"native_gameplay": "not_run", "rendered_quality": "not_assessed", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	if OS.get_cmdline_user_args().has("--gear-bore-only"):
		check_gear_bores()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"unique_meshes": checked_meshes.size(), "maximum_packed_tangent_dot": max_tangent_dot,
			"native_gameplay": "not_run", "rendered_quality": "not_assessed", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
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
