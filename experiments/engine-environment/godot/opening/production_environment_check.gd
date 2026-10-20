extends SceneTree
## Isolated visual resources and 3D world assembly. No gameplay or desktop input.
const Opening = preload("res://opening/opening.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const Scenery = Opening.ProductionEnvironment
var checks := 0
var failed := false
var error_count := 0
var mode := "environment"
const TANGENT_EPSILON := 0.0005

class FixtureView:
	extends "res://opening/opening.gd"
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		error_count += 1
		if error_count <= 12:
			push_error(message)

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
			verify(mesh.material_override == Opening.ProductionSteelFloor.material()
				and mesh.get_meta("surface_role") == "foundation", "The changed wharf rectangles retain the scanned steel material.")
	verify(rendered.size() == expected.size() - 64, "The shared descriptor set has no invisible architecture boxes.")
	var rocks: MultiMesh = scenery.get_node("RockOutcrops").multimesh
	var buffer := rocks.buffer
	for index in range(64):
		var spec: Dictionary = expected["rock_%d" % index]
		var offset := index * 16
		var origin := Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
		var basis := Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
			Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]), Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10]))
		verify(origin.is_equal_approx(spec.center) and basis.is_equal_approx(spec.basis.scaled(spec.scale)),
			"Every visible rock retains the same native box transform and scale.")
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

func run() -> void:
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
	var headrace: Node3D = arch.get_node("HeadraceSluice")
	var tailrace: Node3D = arch.get_node("TailraceWeir")
	verify(channel_bed != null and west_wall != null and east_wall != null
		and headrace != null and tailrace != null,
		"MillraceArchitecture includes the stone channel bed, side walls, headrace sluice gate and tailrace weir.")
	verify(west_wall.position.y + west_wall.mesh.get_aabb().size.y * 0.5 <= Geometry.GROUND_HEIGHT
		and east_wall.position.y + east_wall.mesh.get_aabb().size.y * 0.5 <= Geometry.GROUND_HEIGHT,
		"Recessed millrace channel walls stay at or below the physical floor height.")
	verify(headrace.position.z < -5.2 and tailrace.position.z > 8.4
		and headrace.get_node("SluiceHandwheel") != null and tailrace.get_node("UpperWeirCrest") != null,
		"The 3D headrace sluice gate and tailrace stepped weir frame the north and south ends of the millrace.")
	var east_sub: MeshInstance3D = view.get_node("EastFoundrySubstructure")
	var west_sub: MeshInstance3D = view.get_node("WestWharfSubstructure")
	var seam_headwall: Node3D = view.get_node("NorthSeamOutcrop")
	verify(east_sub != null and west_sub != null and seam_headwall != null,
		"The worksite builds split east/west substructures and a 3D north ore-seam rock headwall.")
	var east_min_x := east_sub.position.x - east_sub.mesh.get_aabb().size.x * 0.5
	var west_max_x := west_sub.position.x + west_sub.mesh.get_aabb().size.x * 0.5
	verify(east_min_x > -2.0 and west_max_x < -3.4,
		"The split foundation substructure leaves the recessed millrace corridor open around x=-2.7.")
	verify(ground.material_override == Scenery.ground_material()
		and stream.material_override == Scenery.water_material(),
		"Repeated world views share the authored material resources.")
	var soil: StandardMaterial3D = ground.material_override
	verify(soil.albedo_texture is NoiseTexture2D and soil.normal_texture is NoiseTexture2D
		and soil.normal_enabled and soil.albedo_texture.seamless and soil.normal_texture.seamless
		and soil.vertex_color_use_as_albedo,
		"The ground uses repeating color/normal detail combined with 3D elevation vertex shading.")
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
	verify(panorama.get_width() == 512 and panorama.get_height() == 256
		and panorama.get_format() == Image.FORMAT_RGBF and panorama.has_mipmaps(),
		"The self-contained sky preserves actual HDR data and a mip chain.")
	var brightest := Vector2i.ZERO
	var energy := 0.0
	for y in range(256):
		verify(panorama.get_pixel(0, y).is_equal_approx(panorama.get_pixel(511, y)),
			"The panorama wraps without an authored longitude seam.")
		for x in range(512):
			var color := panorama.get_pixel(x, y)
			if color.r > energy:
				energy = color.r
				brightest = Vector2i(x, y)
	var latitude := PI * (0.5 - float(brightest.y) / 255.0)
	var longitude := TAU * float(brightest.x) / 511.0
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
