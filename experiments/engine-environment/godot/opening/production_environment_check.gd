extends SceneTree
## Isolated visual resources and 3D world assembly. No gameplay or desktop input.
const Opening = preload("res://opening/opening.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const Scenery = Opening.ProductionEnvironment
var checks := 0
var failed := false
var error_count := 0
var mode := "environment"
var fixture_directory := ""
const TANGENT_EPSILON := 0.0005

class FixtureView:
	extends "res://opening/opening.gd"
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

class WaterFrameView extends Opening:
	var frame_seconds := 0.0
	func _ready() -> void:
		set_process(false)
	func _water_time_seconds() -> float:
		return frame_seconds
	func _refresh_machine_preview() -> void: pass
	func _refresh_endpoint_cue() -> void: pass
	func _refresh_mechanical_audio() -> void: pass
	func _animate_wheel(_delta: float) -> void: pass
	func _update_camera() -> void: pass

func verify(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failed = true
		error_count += 1
		if error_count <= 12:
			push_error(message)
	return condition

func inspect_visual(node: Node) -> void:
	verify(not node is CollisionObject3D and not node is CollisionShape3D,
		"Scenery must not introduce physical or pick authority: " + str(node.name))
	verify(node.get_script() == null, "Scenery has no independent controller or clock: " + str(node.name))
	for child in node.get_children():
		inspect_visual(child)

func check_mesh_attributes(mesh: ArrayMesh, label: String, sample_step: int = 1) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	verify(vertices.size() >= 36 and vertices.size() % 3 == 0,
		label + " has complete triangle vertices.")
	verify(normals.size() == vertices.size() and uvs.size() == vertices.size()
		and tangents.size() == vertices.size() * 4,
		label + " binds normals, UVs and tangents for every vertex.")
	for idx in range(0, vertices.size(), sample_step):
		var v := vertices[idx]
		var n := normals[idx]
		var uv := uvs[idx]
		var t := Vector3(tangents[idx * 4], tangents[idx * 4 + 1], tangents[idx * 4 + 2])
		verify(v.is_finite() and n.is_finite() and is_equal_approx(n.length(), 1.0) and uv.is_finite(),
			label + " vertex attributes are finite and unit-normal.")
		verify(t.is_finite() and t.length() > 0.98 and absf(t.dot(n)) < TANGENT_EPSILON,
			label + " tangents are finite and orthogonal to the surface normal.")

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--environment-case="):
			mode = argument.trim_prefix("--environment-case=")
		elif argument.begins_with("--artifacts="):
			fixture_directory = argument.trim_prefix("--artifacts=")
	call_deferred("run")

func check_multimesh(instances: MultiMesh, min_pad_clearance: float, label: String) -> void:
	# The dummy renderer preserves bulk uploads but ignores per-instance getters.
	# Inspect the actual retained buffer, not a separately recomputed layout.
	var buffer := instances.buffer
	verify(buffer.size() == instances.instance_count * 16,
		label + " buffer contains each complete matrix and color.")
	if buffer.size() != instances.instance_count * 16:
		return
	var elevated_count := 0
	for n in range(instances.instance_count):
		var offset := n * 16
		var origin := Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
		var basis := Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
			Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
			Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10]))
		var expected_y: float = Scenery.Surface.height_at(origin.x, origin.z)
		if origin.y > Geometry.GROUND_HEIGHT + 0.25:
			elevated_count += 1
		verify(origin.is_finite() and basis.is_finite() and basis.determinant() > 0.2
			and is_equal_approx(origin.y, expected_y)
			and (absf(origin.x - 1.65) > min_pad_clearance or absf(origin.z - 1.65) > min_pad_clearance)
			and absf(origin.x - Scenery.river_center_x(origin.z)) >= Scenery.channel_half_width(origin.z),
			label + " stays on the 3D valley terrain outside the construction pad and clear of the river channel.")
		for channel in range(4):
			verify(is_finite(buffer[offset + 12 + channel]) and buffer[offset + 12 + channel] >= 0
				and buffer[offset + 12 + channel] <= 1, label + " uploaded color channel is finite and bounded.")
	verify(elevated_count >= instances.instance_count / 3,
		label + " populates the elevated 3D valley slopes rather than a flat plane.")

func finish() -> void:
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "mode": mode,
		"scope": {"surface-composition": "shared renderer/physical geometry and bed/water composition",
			"sourced-foliage": "runtime tuft import, cutout material and existing terrain placement",
			"foliage-mipmaps": "corrected runtime texture mipmap generation and binding",
			"meadow-patches": "changed terrain-aware grass patch placement and culling envelopes",
			"sourced-sky": "original HDR radiance, cached sky and ordinary key-light binding",
			"ground-material": "scanned ground material, data channels and cache separation",
			"water-flow": "changed cosmetic water material and ordinary frame consumer",
			"rock-collision-shape": "visible rock corners versus rigid collision descriptors",
			"flat-fallback": "historical flat source-roster fallback", "foliage": "changed foliage bulk upload",
			"environment": "3D valley terrain, millrace, architecture and foundation"}.get(mode, "unknown"),
		"rendered_quality": "not_assessed", "desktop": "not_used", "authority_started": false}))
	quit(1 if failed else 0)

func check_surface_composition() -> void:
	# Changed geometry only. The retained 11,058 checks cover unchanged mesh
	# attributes, water, sky and material behavior at their original revision.
	var shared = Scenery.Surface
	var view := FixtureView.new()
	root.add_child(view)
	view._build_world()
	var scenery: Node3D = view.get_node("ProductionScenery")
	var ground: MeshInstance3D = scenery.get_node("GroundSurface")
	verify(ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == shared.faces(),
		"The renderer emits exactly the immutable triangle vertices used by ActorWorld.")
	verify(view.model == null and view.actor_world == null, "Scenery assembly starts no authority or producer.")
	inspect_visual(scenery)
	var rendered := {}
	collect_solids(view, rendered)
	var expected := {}
	for spec in shared.support_boxes():
		expected[spec.id] = spec
		if spec.id.begins_with("rock_"):
			continue
		verify(rendered.has(spec.id), "Every architectural/deck collision descriptor has a real visible mesh: " + spec.id)
		if not rendered.has(spec.id):
			continue
		var mesh: MeshInstance3D = rendered[spec.id]
		verify(mesh.global_position.is_equal_approx(spec.center) and mesh.global_basis.is_equal_approx(spec.basis)
			and mesh.mesh.get_aabb().size.is_equal_approx(spec.size), "Visible and physical box transforms agree: " + spec.id)
		if spec.id.begins_with("pad_"):
			verify(mesh.material_override == Scenery.ground_material()
				and mesh.get_meta("surface_role") == "foundation",
				"The natural bedrock terrace panels use the shared rocky-ground material instead of man-made steel floor plates.")
	verify(rendered.size() == expected.size() - 64, "The shared descriptor set has no invisible architecture boxes.")
	var rocks: MultiMesh = scenery.get_node("RockOutcrops").multimesh
	check_rock_shapes(rocks)
	var bed: MeshInstance3D = scenery.get_node("MillraceArchitecture/ChannelBed")
	var bed_bounds := bed.mesh.get_aabb()
	var top := bed.global_position.y + bed_bounds.end.y
	var stream: MeshInstance3D = scenery.get_node("StreamSurface")
	var water: PackedVector3Array = stream.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var covered := 0
	var minimum_gap := INF
	# A linear triangle attains its minimum at a vertex. Clipping its actual
	# world-space polygon to the bed footprint also tests boundary intersections.
	var low := Vector2(bed.global_position.x + bed_bounds.position.x, bed.global_position.z + bed_bounds.position.z)
	var high := Vector2(bed.global_position.x + bed_bounds.end.x, bed.global_position.z + bed_bounds.end.z)
	for first in range(0, water.size(), 3):
		var polygon: Array[Vector3] = [water[first] + stream.global_position,
			water[first + 1] + stream.global_position, water[first + 2] + stream.global_position]
		# Exclude the two vertical skirt strips, which are below the water top.
		var column := floori(float(first) / 6.0) % 8
		if column == 0 or column == 7:
			continue
		for boundary in [[0, low.x, true], [0, high.x, false], [2, low.y, true], [2, high.y, false]]:
			polygon = clip_polygon(polygon, boundary[0], boundary[1], boundary[2])
		for point in polygon:
			covered += 1
			minimum_gap = minf(minimum_gap, point.y - top)
	verify(covered > 0 and minimum_gap > 0.05, "The whole bed stays below overlapping emitted water triangles, including the original downstream defect.")
	print(JSON.stringify({"relation": "bed_below_emitted_water", "minimum_gap": minimum_gap, "clipped_vertices": covered,
		"visible_boxes": rendered.size(), "rock_instances": 64, "triangle_vertices": water.size()}))
	view.free()

func check_water_flow() -> void:
	var water := Scenery.water_material()
	var texture := water.normal_texture
	var mesh := Scenery.stream_mesh()
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].duplicate()
	verify(water == Scenery.water_material() and water.metallic == 0.0,
		"The water keeps a shared dielectric material rather than metallic shading.")
	verify(water.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and water.normal_enabled
		and texture != null and texture.get_image().has_mipmaps() and water.texture_repeat,
		"Moving detail retains the existing opaque, repeated and mipmapped normal surface.")
	verify(Scenery.animate_water(0.0) and water.uv1_offset == Vector3.ZERO, "The visual phase starts at the original normal-map coordinates.")
	var before := water.uv1_offset
	verify(Scenery.animate_water(1.0) and water.uv1_offset.y < before.y,
		"The actual texture transform advances the pattern toward positive downstream Z.")
	var travelled := -(water.uv1_offset.y - before.y) / (0.08 * water.uv1_scale.y)
	verify(absf(travelled - 0.4) < 0.000001, "The declared environmental ripple speed is 0.4 metres per second in the authored stream UVs.")
	var once := water.uv1_offset
	verify(Scenery.animate_water(1.0) and water.uv1_offset == once,
		"Repeated updates at the same absolute time cannot accelerate the shared texture.")
	verify(Scenery.animate_water(3.90625) and water.uv1_offset.length() < 0.000001,
		"One complete normal-texture period wraps to its initial coordinates.")
	verify(Scenery.animate_water(1000000.25) and water.uv1_offset.is_finite()
		and water.uv1_offset.y <= 0.0 and water.uv1_offset.y > -1.0, "Long-running presentation retains a bounded finite offset.")
	var valid := water.uv1_offset
	for invalid in [-1.0, NAN, INF]:
		verify(not Scenery.animate_water(invalid) and water.uv1_offset == valid,
			"Invalid presentation time preserves the last valid material phase.")
	var view := WaterFrameView.new()
	view.auto_advance = false
	root.add_child(view)
	view.frame_seconds = 2.0
	view._process(0.016)
	verify(water.uv1_offset.distance_to(Vector3(0.0, -0.512, 0.0)) < 0.000001
		and view.model == null and view.state.is_empty() and view.elapsed == 0.0,
		"The actual ordinary frame path moves water without creating or advancing a Model.")
	var second := WaterFrameView.new()
	second.auto_advance = false
	root.add_child(second)
	second.frame_seconds = 2.0
	second._process(1.0)
	verify(water.uv1_offset.distance_to(Vector3(0.0, -0.512, 0.0)) < 0.000001,
		"A second view and a different frame delta preserve the same shared visual phase.")
	view.legacy_fixture = true
	view.frame_seconds = 0.0
	view._refresh_water()
	verify(water.uv1_offset.distance_to(Vector3(0.0, -0.512, 0.0)) < 0.000001,
		"Historical explicit fixtures do not change the new water material.")
	verify(Scenery.stream_mesh() == mesh and mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices
		and water.normal_texture == texture, "Animation preserves every water vertex and the shared normal resource.")
	second.free()
	view.free()

func check_ground_material() -> void:
	if not fixture_directory.is_absolute_path() or not DirAccess.dir_exists_absolute(fixture_directory):
		verify(false, "Use the declared external material-test artifact directory.")
		return
	var ground := Scenery.ground_material()
	verify(Scenery.ground_source_status == "ready" and ground != null,
		"The ordinary ground material loads the complete sourced bitmap set.")
	if ground == null:
		return
	verify(ground == Scenery.ground_material() and Opening.ProductionSteelFloor.source_status == "uninitialized",
		"Terrain material reuse does not consume or poison the independent steel cache.")
	verify(ground.albedo_texture.get_image().get_size() == Vector2i(1024, 1024)
		and ground.normal_texture.get_image().get_size() == Vector2i(512, 512)
		and ground.roughness_texture.get_image().get_size() == Vector2i(512, 512),
		"The bounded albedo, OpenGL normal and scalar map retain their declared resolutions.")
	verify(ground.albedo_texture.get_image().has_mipmaps() and ground.normal_texture.get_image().has_mipmaps()
		and ground.roughness_texture.get_image().has_mipmaps(), "All shared terrain resources have mipmaps.")
	verify(ground.ao_enabled and ground.ao_texture == ground.roughness_texture
		and ground.metallic_texture == ground.roughness_texture and ground.metallic == 0.0
		and ground.roughness == 1.0 and ground.ao_light_affect == 0.0,
		"One packed linear map supplies ambient occlusion and roughness while preserving the provider's dielectric factor.")
	verify(ground.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED
		and ground.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		and ground.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE,
		"Packed scalar roles remain red occlusion, green roughness and blue metallic.")
	verify(ground.normal_enabled and ground.normal_scale == 1.0 and ground.vertex_color_use_as_albedo
		and ground.albedo_color == Color.WHITE and ground.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"The scanned finish remains opaque and uses its original normal convention with restrained vertex tint.")
	verify(ground.uv1_triplanar and ground.uv1_world_triplanar and ground.uv1_scale == Vector3.ONE * 0.5
		and ground.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
		"World-space mapping preserves the two-metre extent across steep terrain faces.")
	var packed := Image.load_from_file(Scenery.GROUND_ROOT.path_join(Scenery.GROUND_FILES.arm))
	var actual := ground.ao_texture.get_image()
	for pixel in [Vector2i(0, 0), Vector2i(117, 239), Vector2i(511, 511)]:
		verify(actual.get_pixelv(pixel) == packed.get_pixelv(pixel), "Material construction preserves decoded scalar channels without a color transform.")
	var mesh := Scenery.terrain_mesh()
	verify(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == Scenery.Surface.faces(),
		"Photographic shading cannot alter the shared terrain triangle positions.")
	var color := Scenery._terrain_vertex_color(30, 6.222421626752348, 1.65, Vector3.UP)
	verify(color.r >= 0.75 and color.g >= 0.75 and color.b >= 0.75,
		"The source albedo is not multiplied by a second dark procedural base coat.")
	var empty := fixture_directory.path_join("ground-empty")
	var partial := fixture_directory.path_join("ground-partial")
	var wrong := fixture_directory.path_join("ground-wrong-extent")
	for directory in [empty, partial, wrong]:
		if not verify(not DirAccess.dir_exists_absolute(directory) and DirAccess.make_dir_absolute(directory) == OK,
			"Negative material cases preserve existing outputs."):
			return
	var missing := Opening.ProductionSteelFloor.read_images(empty, Scenery.GROUND_FILES, Vector2i(512, 512))
	verify(missing.status == "missing" and missing.images.is_empty(), "An absent bitmap set is an explicit procedural fallback.")
	var albedo_path: String = Scenery.GROUND_ROOT.path_join(Scenery.GROUND_FILES.albedo)
	if not verify(DirAccess.copy_absolute(albedo_path, partial.path_join(Scenery.GROUND_FILES.albedo)) == OK,
		"Retain the real partial-set negative input."):
		return
	var incomplete := Opening.ProductionSteelFloor.read_images(partial, Scenery.GROUND_FILES, Vector2i(512, 512))
	verify(incomplete.status == "invalid" and incomplete.reason == "incomplete_material_set" and incomplete.images.is_empty(),
		"A partial set is never labelled as a sourced ready material.")
	for role in Scenery.GROUND_FILES:
		if not verify(DirAccess.copy_absolute(Scenery.GROUND_ROOT.path_join(Scenery.GROUND_FILES[role]),
			wrong.path_join(Scenery.GROUND_FILES[role])) == OK, "Retain the complete extent-negative input."):
			return
	var tiny := Image.create(4, 4, false, Image.FORMAT_RGB8)
	if not verify(tiny.save_webp(wrong.path_join(Scenery.GROUND_FILES.normal), false, 1.0) == OK,
		"Replace only the disposable negative normal map with a valid wrong-size image."):
		return
	var invalid := Opening.ProductionSteelFloor.read_images(wrong, Scenery.GROUND_FILES, Vector2i(512, 512))
	verify(invalid.status == "invalid" and invalid.reason == "invalid_normal" and invalid.images.is_empty(),
		"A valid image with the wrong normal extent fails the declared material contract.")
	verify(Opening.ProductionSteelFloor.read_images().status == "ready",
		"The shared decoder's original default filenames still load the unchanged steel set.")

func check_rock_shapes(rocks: MultiMesh) -> void:
	var specs: Array[Dictionary] = Scenery.Surface.rock_boxes()
	var buffer := rocks.buffer
	verify(rocks.instance_count == specs.size() and specs.size() == 64,
		"Every shared rock collision descriptor has one visible instance.")
	verify(buffer.size() == specs.size() * 16, "Read the actual uploaded rock transforms and colors.")
	if buffer.size() != specs.size() * 16:
		return
	var half := rocks.mesh.get_aabb().size / 2.0
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var offset := index * 16
		var origin := Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
		var uploaded := Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
			Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
			Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10]))
		verify(origin.is_equal_approx(spec.center), "Visible and physical rock origins agree: " + spec.id)
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					var sign := Vector3(x, y, z)
					var visible_corner := origin + uploaded * (half * sign)
					var physical_corner: Vector3 = spec.center + spec.basis * (spec.size * sign / 2.0)
					verify(visible_corner.is_equal_approx(physical_corner),
						"The uploaded visible corner matches the rigid collision box: " + spec.id + " " + str(sign))

func collect_solids(node: Node, result: Dictionary) -> void:
	if node.has_meta("site_solid_id"):
		var id: String = node.get_meta("site_solid_id")
		verify(not result.has(id), "Visible solid identities are unique: " + id)
		result[id] = node
	for child in node.get_children():
		collect_solids(child, result)

func clip_polygon(polygon: Array[Vector3], axis: int, boundary: float, keep_above: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if polygon.is_empty():
		return result
	var previous := polygon[-1]
	var previous_inside: bool = previous[axis] >= boundary if keep_above else previous[axis] <= boundary
	for point in polygon:
		var inside: bool = point[axis] >= boundary if keep_above else point[axis] <= boundary
		if inside != previous_inside:
			result.append(previous.lerp(point, (boundary - previous[axis]) / (point[axis] - previous[axis])))
		if inside:
			result.append(point)
		previous = point
		previous_inside = inside
	return result

func check_sourced_foliage() -> void:
	var node := Scenery._foliage()
	if not verify(Scenery.foliage_source_status == "ready", "The ordinary foliage path imports the captured self-contained GLB."):
		node.free()
		return
	inspect_visual(node)
	var mesh := node.multimesh.mesh as ArrayMesh
	var material := node.material_override as StandardMaterial3D
	verify(node.multimesh.instance_count == 96 and mesh == Scenery.foliage_cluster_mesh,
		"The selected mesh retains the existing 96 terrain-anchored instances.")
	check_multimesh(node.multimesh, 6.9, "Sourced grass")
	var bounds := mesh.get_aabb()
	verify(bounds.position.distance_to(Vector3(-0.1529102474, -0.0066887620, -0.1753695011)) < 0.00001
		and bounds.end.distance_to(Vector3(0.2226673961, 0.3487543762, 0.2266876996)) < 0.00001,
		"The imported source mesh has the declared uniform scale and omits catalogue placement.")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verify(vertices.size() == 1386 and normals.size() == 1386 and uvs.size() == 1386
		and tangents.size() == 5544 and indices.size() == 3771, "The runtime importer preserves geometry and generates tangent space for the normal map."):
		for index in range(vertices.size()):
			var tangent := Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])
			verify(vertices[index].is_finite() and normals[index].is_finite() and uvs[index].is_finite()
				and absf(normals[index].length() - 1.0) < 0.003 and absf(tangent.length() - 1.0) < 0.003
				and absf(tangent.dot(normals[index])) < 0.003 and absf(tangents[index * 4 + 3]) == 1.0,
				"Imported source vertices retain finite unit normal/tangent frames.")
		for index in indices:
			verify(index >= 0 and index < vertices.size(), "Every triangle index refers to an actual imported vertex.")
	if verify(material != null, "The actual MultiMesh has the imported shared material."):
		verify(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			and is_equal_approx(material.alpha_scissor_threshold, 0.5) and material.cull_mode == BaseMaterial3D.CULL_DISABLED
			and material.metallic == 0.0 and material.normal_enabled and material.ao_enabled,
			"Grass is a double-sided dielectric cutout with normal and occlusion maps.")
		var color := material.albedo_texture.get_image()
		verify(color.get_size() == Vector2i(384, 384) and color.has_mipmaps()
			and material.normal_texture.get_image().get_size() == Vector2i(256, 256)
			and material.normal_texture.get_image().has_mipmaps(), "Runtime color and normal textures retain their prepared extents and mipmaps.")
		var coverage := 0
		for y in range(384):
			for x in range(384):
				if color.get_pixel(x, y).a >= 0.5:
					coverage += 1
		verify(absf(float(coverage) / (384 * 384) - 0.160257975260417) < 0.00001,
			"The actual material retains the prepared transparent spaces between blades.")
		verify(material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			and material.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED and material.vertex_color_use_as_albedo,
			"The retained scalar channels and restrained instance tint reach the actual material.")
	verify(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,
		"The cutout participates in ordinary two-sided shadow presentation.")
	var second := Scenery._foliage()
	verify(second.multimesh.mesh == mesh and second.material_override == material,
		"A second view reuses the mesh and material rather than decoding the asset again.")
	for index in range(96):
		var at := index * 16
		for channel in range(3):
			verify(node.multimesh.buffer[at + 12 + channel] >= 0.8, "The scanned color is not multiplied by the old dark generated-blade tint.")
	verify(Scenery.read_foliage(fixture_directory.path_join("missing.glb")).status == "missing",
		"Missing historical payloads retain an explicit source status.")
	var small_path := fixture_directory.path_join("short.glb")
	var file := FileAccess.open(small_path, FileAccess.WRITE)
	if verify(file != null, "The negative import fixture retains its own disposable input."):
		file.store_string("incomplete")
		file.close()
		verify(Scenery.read_foliage(small_path).status == "invalid", "A present invalid asset is not reported as ready or missing.")
	var view := FixtureView.new()
	root.add_child(view)
	view._build_world()
	verify(view.model == null and view.actor_world == null and view.state.is_empty(),
		"The ordinary environment assembles sourced grass without creating any gameplay authority.")
	verify(view.get_node("ProductionScenery/GroundFoliage").multimesh.mesh == mesh,
		"The ordinary worksite consumes the same sourced cached mesh.")
	view.free()
	second.free()
	node.free()
	print(JSON.stringify({"vertices_per_tuft": vertices.size(), "triangles_per_tuft": indices.size() / 3,
		"instances": 96, "authored_triangles_before_culling": indices.size() / 3 * 96,
		"imported_bounds": str(bounds), "limits": "No frame-time, rendered quality, gameplay or desktop claim."}))

func check_foliage_mipmaps() -> void:
	var node := Scenery._foliage()
	if not verify(Scenery.foliage_source_status == "ready", "The corrected ordinary foliage material initializes successfully."):
		node.free()
		return
	var material := node.material_override as StandardMaterial3D
	for texture in [material.albedo_texture, material.normal_texture, material.roughness_texture]:
		var image: Image = texture.get_image()
		verify(image.has_mipmaps() and image.get_mipmap_count() == 8,
			"Each corrected texture has its complete eight-level mip chain.")
	verify(material.roughness_texture == material.metallic_texture and material.roughness_texture == material.ao_texture,
		"Packed scalar channels share the corrected mipmapped image.")
	var normal := material.normal_texture.get_image()
	normal.convert(Image.FORMAT_RGB8)
	var maximum_error := 0.0
	var extent := 256
	var data := normal.get_data()
	for level in range(1, normal.get_mipmap_count() + 1):
		extent = maxi(1, extent / 2)
		var first := normal.get_mipmap_offset(level)
		for pixel in range(extent * extent):
			var at := first + pixel * 3
			var vector := Vector3(data[at], data[at + 1], data[at + 2]) / 255.0 * 2.0 - Vector3.ONE
			maximum_error = maxf(maximum_error, absf(vector.length() - 1.0))
	verify(maximum_error < 0.015, "Generated normal mip levels retain bounded unit vectors after RGB8 quantization.")
	verify(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and material.metallic == 0
		and material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		and material.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED,
		"Rebinding mipmapped textures retains cutout and dielectric channel semantics.")
	var second := Scenery._foliage()
	verify(second.material_override == material, "The corrected material is generated once and reused by later scenery.")
	print(JSON.stringify({"maximum_normal_mip_length_error": maximum_error, "geometry_checks": "reused from the retained first import", "rendered_quality": "not_assessed"}))
	second.free()
	node.free()

func check_meadow_patches() -> void:
	var view := FixtureView.new()
	root.add_child(view)
	view._build_world()
	var meadow: Node3D = view.get_node("ProductionScenery/MeadowPatches")
	inspect_visual(meadow)
	verify(view.model == null and view.actor_world == null and view.state.is_empty(),
		"Ordinary meadow assembly creates no authority or simulation state.")
	verify(meadow.get_child_count() > 0 and meadow.get_child_count() <= 24,
		"Ordinary scenery has a bounded set of spatially grouped grass patches.")
	var faces: PackedVector3Array = view.get_node("ProductionScenery/GroundSurface").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var solids: Array = Scenery.Surface.support_boxes()
	var total := 0
	for patch: MultiMeshInstance3D in meadow.get_children():
		var instances := patch.multimesh
		var data := instances.buffer
		verify(instances.instance_count > 0 and instances.instance_count <= 32 and data.size() == instances.instance_count * 16,
			"Each patch uploads at most 32 complete transform/color records.")
		verify(instances.mesh == Scenery.foliage_cluster_mesh and patch.material_override == Scenery.foliage_finish
			and patch.visibility_range_end == 62.0 and patch.visibility_range_begin == 0.0,
			"Patches share the published resource cache and declare a bounded cosmetic visibility range.")
		for instance in range(instances.instance_count):
			var at := instance * 16
			var basis := Basis(Vector3(data[at], data[at + 4], data[at + 8]),
				Vector3(data[at + 1], data[at + 5], data[at + 9]),
				Vector3(data[at + 2], data[at + 6], data[at + 10]))
			var local := Vector3(data[at + 3], data[at + 7], data[at + 11])
			var position := local + patch.global_position
			var cell: Vector2i = Scenery.Surface.cell(position.x, position.z)
			var offset: int = (cell.y * Scenery.Surface.SUBDIVISIONS + cell.x) * 6
			var found := false
			for triangle in range(2):
				var a := faces[offset + triangle * 3]
				var b := faces[offset + triangle * 3 + 1]
				var c := faces[offset + triangle * 3 + 2]
				if not Geometry2D.point_is_inside_triangle(Vector2(position.x, position.z), Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)):
					continue
				var normal := (c - a).cross(b - a).normalized()
				var height := a.y - (normal.x * (position.x - a.x) + normal.z * (position.z - a.z)) / normal.y
				verify(absf(position.y - height) < 0.0001 and basis.y.normalized().dot(normal) > 0.99999 and normal.y >= 0.82,
					"Each uploaded root lies on an actual emitted triangle, aligned to its nonsteep face.")
				found = true
				break
			verify(found and position.is_finite() and basis.is_finite() and basis.determinant() > 0.5,
				"The actual patch transform has finite positive scale on the visible terrain.")
			verify((absf(position.x - 1.65) > 7.7 or absf(position.z - 1.65) > 7.7)
				and absf(position.x - Scenery.river_center_x(position.z)) > Scenery.channel_half_width(position.z) + 0.8,
				"Uploaded meadow roots remain clear of the construction pad and river.")
			for solid in solids:
				var point: Vector3 = solid.basis.transposed() * (position - solid.center)
				verify(absf(point.x) > solid.size.x * 0.5 + 0.9 or absf(point.y) > solid.size.y * 0.5 + 0.9
					or absf(point.z) > solid.size.z * 0.5 + 0.9, "Grass retains a conservative whole-clump separation from every static solid.")
			var bounds := instances.custom_aabb.grow(0.0001)
			var mesh_bounds := instances.mesh.get_aabb()
			for x in [mesh_bounds.position.x, mesh_bounds.end.x]:
				for y in [mesh_bounds.position.y, mesh_bounds.end.y]:
					for z in [mesh_bounds.position.z, mesh_bounds.end.z]:
						verify(bounds.has_point(basis * Vector3(x, y, z) + local),
							"The actual culling box encloses all transformed mesh bounds corners.")
			total += 1
	verify(total >= 384 and total <= 768, "The bounded composition adds a substantial patch population without exceeding its declared maximum.")
	print(JSON.stringify({"patches": meadow.get_child_count(), "new_tufts": total,
		"new_triangles_before_culling": total * 1257, "existing_tufts": 96,
		"limits": "Resource and placement evidence, not rendered quality or measured performance."}))
	view.free()

func check_sourced_sky() -> void:
	var material := Scenery.panorama_material()
	if not verify(Scenery.sky_source_status == "ready", "The ordinary sky consumes the captured licensed HDR source."):
		return
	var image := material.panorama.get_image()
	verify(image.get_size() == Vector2i(1024, 512) and image.get_format() == Image.FORMAT_RGBF
		and image.has_mipmaps() and image.get_mipmap_count() == 10,
		"The source radiance keeps its floating representation, extent and full mip chain.")
	var maximum := 0.0
	var minimum := INF
	var peak := Vector2i.ZERO
	var mean := 0.0
	var weights := 0.0
	var finite := true
	for y in range(512):
		var weight := sin(PI * (y + 0.5) / 512.0)
		for x in range(1024):
			var color := image.get_pixel(x, y)
			finite = finite and is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and minf(color.r, minf(color.g, color.b)) >= 0
			var luminance := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			if luminance > maximum:
				maximum = luminance
				peak = Vector2i(x, y)
			minimum = minf(minimum, luminance)
			mean += luminance * weight
			weights += weight
	verify(finite and absf(maximum - 32175.5392) < 0.01 and absf(minimum - 0.0653322265625) < 0.000001,
		"The actual material retains finite unclipped source radiance, including values above one.")
	verify(absf(mean / weights - 0.597089132840752) < 0.000001 and peak == Vector2i(614, 89),
		"No hidden tone mapping, gamma conversion or resize changes the source distribution.")
	var phi := TAU * (peak.x + 0.5) / 1024.0
	var theta := PI * (peak.y + 0.5) / 512.0
	var direction := Vector3(sin(theta) * sin(phi), cos(theta), -sin(theta) * cos(phi))
	var view := FixtureView.new()
	root.add_child(view)
	view._build_world()
	var scenery := view.get_node("ProductionScenery")
	var light: DirectionalLight3D = scenery.get_node("WorksiteSun")
	var environment: Environment = scenery.get_node("WorksiteEnvironment").environment
	verify(light.global_basis.z.dot(direction) > 0.99999,
		"The actual key light points from the measured bright source texel in the pinned panorama convention.")
	verify(environment.sky.sky_material == material and Scenery.panorama_material() == material
		and environment.ambient_light_source == Environment.AMBIENT_SOURCE_SKY
		and environment.reflected_light_source == Environment.REFLECTION_SOURCE_SKY,
		"Ordinary background, ambient and reflection use the same cached sourced environment.")
	verify(environment.tonemap_exposure == 1.0 and environment.tonemap_mode == Environment.TONE_MAPPER_ACES
		and light.light_energy == 1.25 and light.shadow_enabled,
		"The initial exposure, key intensity and shadow policy remain explicit art defaults.")
	verify(view.model == null and view.actor_world == null and view.state.is_empty(),
		"Sourced sky assembly starts no authority or gameplay clock.")
	verify(Scenery.read_sky(fixture_directory.path_join("absent.hdr")).status == "missing",
		"Missing historical sky files retain an explicit status.")
	var invalid_path := fixture_directory.path_join("short.hdr")
	var file := FileAccess.open(invalid_path, FileAccess.WRITE)
	if verify(file != null, "The negative decoder input is retained in the owned fixture."):
		file.store_string("incomplete")
		file.close()
		verify(Scenery.read_sky(invalid_path).status == "invalid", "A present invalid panorama is never reported as ready.")
	print(JSON.stringify({"maximum_linear_luminance": maximum, "spherical_mean_luminance": mean / weights,
		"key_direction": [direction.x, direction.y, direction.z], "exposure": environment.tonemap_exposure,
		"limits": "Radiance and source binding only; no rendered balance, shadow image, photometric calibration or human quality verdict."}))
	view.free()

func run() -> void:
	if mode == "sourced-sky":
		check_sourced_sky()
		finish()
		return
	if mode == "meadow-patches":
		check_meadow_patches()
		finish()
		return
	if mode == "foliage-mipmaps":
		check_foliage_mipmaps()
		finish()
		return
	if mode == "sourced-foliage":
		check_sourced_foliage()
		finish()
		return
	if mode == "ground-material":
		check_ground_material()
		finish()
		return
	if mode == "water-flow":
		check_water_flow()
		finish()
		return
	if mode == "rock-collision-shape":
		var rocks := Scenery._rock_outcrops()
		check_rock_shapes(rocks.multimesh)
		rocks.free()
		finish()
		return
	if mode == "flat-fallback":
		verify(Scenery.Surface == null, "The historical fixed-roster fixture deliberately has no site helper.")
		var flat := FixtureView.new()
		root.add_child(flat)
		flat._build_world()
		var count := 0
		for child in flat.get_children():
			if child is MeshInstance3D and child.get_meta("surface_role", "") == "foundation":
				count += 1
				verify(is_equal_approx(child.position.x / 1.65, roundf(child.position.x / 1.65))
					and is_equal_approx(child.position.z / 1.65, roundf(child.position.z / 1.65)), "Historical panel centres retain their original grid coordinates.")
		verify(count == 49 and flat.model == null and flat.actor_world == null, "The historical flat view creates its original deck without authority.")
		verify(flat.get_node("ProductionScenery/GroundSurface").mesh is PlaneMesh, "A historical plane collider still has the matching flat presentation.")
		flat.free()
		finish()
		return
	if mode == "surface-composition":
		check_surface_composition()
		finish()
		return
	if mode == "foliage":
		var node := Scenery._foliage()
		inspect_visual(node)
		check_multimesh(node.multimesh, 6.9, "GroundFoliage")
		node.free()
		finish()
		return
	if mode != "environment":
		verify(false, "Declare an environment or changed-foliage case.")
		finish()
		return
	var view := FixtureView.new()
	root.add_child(view)
	view._build_world()
	var scenery: Node3D = view.get_node("ProductionScenery")
	inspect_visual(scenery)
	verify(view.model == null and view.actor_world == null and view.state.is_empty(),
		"The actual world-construction hunk cannot create or mutate game authority.")
	var ground: MeshInstance3D = scenery.get_node("GroundSurface")
	verify(ground.mesh is ArrayMesh and ground.mesh == Scenery.terrain_mesh()
		and ground.position == Vector3.ZERO,
		"GroundSurface uses the cached 3D contoured valley ArrayMesh rather than a flat PlaneMesh.")
	var ground_bounds := ground.mesh.get_aabb()
	verify(is_equal_approx(ground_bounds.size.x, Geometry.DISPLAY_TERRAIN_SIZE)
		and is_equal_approx(ground_bounds.size.z, Geometry.DISPLAY_TERRAIN_SIZE)
		and ground_bounds.size.y > 10.0 and ground_bounds.position.y < Geometry.GROUND_HEIGHT - 1.0,
		"The 3D terrain spans 256x256 with a deep carved river gorge and >10m surrounding valley relief.")
	check_mesh_attributes(ground.mesh, "GroundSurface", 9)
	for sample_z in [-4.0, -1.65, 0.0, 1.65, 4.95, 6.6]:
		verify(Scenery.terrain_height(-2.7, sample_z) < Geometry.GROUND_HEIGHT - 1.0,
			"The terrain under the millrace is excavated into a deep 3D channel.")
		for sample_x in [-3.8, -1.4, 0.0, 1.65, 3.3, 6.6]:
			verify(Scenery.terrain_height(sample_x, sample_z) <= Geometry.GROUND_HEIGHT + 0.0001,
				"Contoured terrain never protrudes above the flat physical floor inside the traversable pad.")
	var stream: MeshInstance3D = scenery.get_node("StreamSurface")
	verify(stream.mesh is ArrayMesh and stream.mesh == Scenery.stream_mesh()
		and stream.position.is_equal_approx(Vector3(-2.7, 0.0, 1.65)),
		"StreamSurface uses the cached 3D contoured water volume ArrayMesh along the x=-2.7 millrace.")
	var stream_bounds := stream.mesh.get_aabb()
	verify(stream_bounds.size.x > 1.2 and stream_bounds.size.y > 0.8 and stream_bounds.size.z > 100.0,
		"The 3D water volume spans from upstream headwaters through the millrace and down the tailrace waterfall.")
	check_mesh_attributes(stream.mesh, "StreamSurface", 3)
	for race_z in [-3.3, -1.65, 0.0, 1.65, 3.3, 6.6]:
		var water_y := Scenery.stream_surface_height(-2.7, race_z)
		verify(water_y < Geometry.GROUND_HEIGHT - 0.05 and water_y > -0.48,
			"Millrace water flows inside the recessed channel below the walkway deck and above the stone bed.")
	verify(Scenery.stream_surface_height(-2.7, 8.1) - Scenery.stream_surface_height(-2.7, 10.2) > 0.42,
		"The river drops over a 3D stepped waterfall weir at the south tailrace.")
	var arch: Node3D = scenery.get_node("MillraceArchitecture")
	var channel_bed: MeshInstance3D = arch.get_node("ChannelBed")
	var west_wall: MeshInstance3D = arch.get_node("WestChannelWall")
	var east_wall: MeshInstance3D = arch.get_node("EastChannelWall")
	var headrace: Node3D = arch.get_node("HeadraceGorge")
	var tailrace: Node3D = arch.get_node("TailraceCascade")
	verify(channel_bed != null and west_wall != null and east_wall != null
		and headrace != null and tailrace != null,
		"MillraceArchitecture includes the bedrock channel bed, canyon walls, upstream gorge narrows and downstream cascade.")
	verify(west_wall.position.y + west_wall.mesh.get_aabb().size.y * 0.5 <= Geometry.GROUND_HEIGHT
		and east_wall.position.y + east_wall.mesh.get_aabb().size.y * 0.5 <= Geometry.GROUND_HEIGHT,
		"Recessed canyon channel walls stay at or below the physical floor height.")
	verify(headrace.position.z < -5.2 and tailrace.position.z > 8.4
		and headrace.get_node("WestGorgeCrag") != null and headrace.get_node("EastGorgeCrag") != null
		and tailrace.get_node("UpperCascadeLedge") != null and tailrace.get_node("LowerCascadeLedge") != null,
		"Natural upstream gorge crags and downstream stepped cascade ledges frame the north and south ends of the stream.")
	var east_sub: MeshInstance3D = view.get_node("EastBedrockShelf")
	var west_sub: MeshInstance3D = view.get_node("WestBankBedrockShelf")
	var seam_headwall: Node3D = view.get_node("NorthSeamOutcrop")
	verify(east_sub != null and west_sub != null and seam_headwall != null
		and seam_headwall.get_node("SeamCragWest") != null and seam_headwall.get_node("SeamOverhangLedge") != null,
		"The worksite builds split east/west natural bedrock shelves and a 3D north ore-vein rock outcrop.")
	for forbidden in ["HeadraceSluice", "TailraceWeir", "SluiceHandwheel", "SluiceLiftStem",
			"SluiceGateLeaf", "SluiceHeadbeam", "TrashRackBar", "FlumePost", "FlumeCapBeam",
			"ChannelTimberSill", "MinePortalPost", "MinePortalCap", "FoundryCrossGirder",
			"SeamCurbRail", "WestBankSurveyMarker", "MillraceWharfBeam", "FoundationPanel"]:
		verify(view.find_child(forbidden, true, false) == null,
			"Unbuilt worksite contains no pre-existing man-made structure node: " + forbidden)
	var east_min_x := east_sub.position.x - east_sub.mesh.get_aabb().size.x * 0.5
	var west_max_x := west_sub.position.x + west_sub.mesh.get_aabb().size.x * 0.5
	verify(east_min_x > -2.0 and west_max_x < -3.4,
		"The split bedrock shelf leaves the recessed stream gorge open around x=-2.7.")
	verify(ground.material_override == Scenery.ground_material()
		and stream.material_override == Scenery.water_material(),
		"Repeated world views share the authored material resources.")
	var soil: StandardMaterial3D = ground.material_override
	if Scenery.ground_source_status == "ready":
		verify(soil.albedo_texture is ImageTexture and soil.normal_texture is ImageTexture
			and soil.normal_enabled and soil.uv1_world_triplanar and soil.vertex_color_use_as_albedo,
			"The scanned ground uses shared world-space color/normal maps with restrained elevation tint.")
	else:
		verify(soil.albedo_texture is NoiseTexture2D and soil.normal_texture is NoiseTexture2D
			and soil.normal_enabled and soil.albedo_texture.seamless and soil.normal_texture.seamless
			and soil.vertex_color_use_as_albedo,
			"Missing historical ground maps retain the repeating procedural finish.")
	var water: StandardMaterial3D = stream.material_override
	var ripples: Image = water.normal_texture.get_image()
	verify(ripples.get_width() == 128 and ripples.get_height() == 128 and ripples.has_mipmaps()
		and water.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"Water uses an opaque mipmapped ripple surface without a sorting dependency.")
	for y in range(0, 128, 16):
		for x in range(0, 128, 16):
			var pixel := ripples.get_pixel(x, y)
			var normal := Vector3(pixel.r, pixel.g, pixel.b) * 2.0 - Vector3.ONE
			verify(normal.is_finite() and absf(normal.length() - 1.0) < 0.02 and normal.z > 0.9,
				"The encoded surface normals remain finite and forward-facing after eight-bit packing.")
	var environment: Environment = scenery.get_node("WorksiteEnvironment").environment
	verify(environment.sky.sky_material == Scenery.panorama_material()
		and environment.background_mode == Environment.BG_SKY
		and environment.reflected_light_source == Environment.REFLECTION_SOURCE_SKY,
		"The actual environment uses the shared original sky for background and reflections.")
	verify(environment.fog_mode == Environment.FOG_MODE_DEPTH
		and environment.fog_depth_begin > 24.0 + 6.7 * sqrt(2.0)
		and environment.fog_depth_end < view.camera.far,
		"Distance haze begins beyond the normal worksite and closes before the far clip.")
	var panorama: Image = environment.sky.sky_material.panorama.get_image()
	var sourced: bool = Scenery.sky_source_status == "ready"
	verify(panorama.get_size() == (Vector2i(1024, 512) if sourced else Vector2i(512, 256))
		and panorama.get_format() == Image.FORMAT_RGBF and panorama.has_mipmaps(),
		"The self-contained sky preserves actual HDR data and a mip chain.")
	var brightest := Vector2i.ZERO
	var energy := 0.0
	for y in range(panorama.get_height()):
		if not sourced:
			verify(panorama.get_pixel(0, y).is_equal_approx(panorama.get_pixel(511, y)),
				"The generated panorama keeps its duplicated longitude endpoints.")
		for x in range(panorama.get_width()):
			var color := panorama.get_pixel(x, y)
			var value := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722 if sourced else color.r
			if value > energy:
				energy = value
				brightest = Vector2i(x, y)
	var latitude := PI * (0.5 - (float(brightest.y) + 0.5) / panorama.get_height()) if sourced else PI * (0.5 - float(brightest.y) / 255.0)
	var longitude := TAU * (float(brightest.x) + 0.5) / panorama.get_width() if sourced else TAU * float(brightest.x) / 511.0
	var sampled_direction := Vector3(cos(latitude) * sin(longitude), sin(latitude), -cos(latitude) * cos(longitude))
	var sun: DirectionalLight3D = scenery.get_node("WorksiteSun")
	verify(energy > 4.0 and sampled_direction.dot(sun.basis.z) > 0.999,
		"The HDR sun aligns with the actual light in the pinned SKY_COORDS convention.")
	verify(sun.shadow_enabled and sun.directional_shadow_max_distance >= environment.fog_depth_begin
		and not scenery.get_node("WorksiteFill").shadow_enabled,
		"Only the actual key light creates a worksite shadow map.")
	var foliage: MultiMesh = scenery.get_node("GroundFoliage").multimesh
	check_multimesh(foliage, 6.9, "GroundFoliage")
	var outcrops: MultiMesh = scenery.get_node("RockOutcrops").multimesh
	check_multimesh(outcrops, 7.5, "RockOutcrops")
	verify(not view.machine_root.get_child_count() and view.character_presenter == null,
		"The environment fixture creates neither machines nor controlled actors.")
	view.free()
	finish()
