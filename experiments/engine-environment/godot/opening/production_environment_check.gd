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

class SharedBankView:
	extends "res://opening/shared_opening.gd"
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
			"stone-material": "sourced natural-stone material, cache and unchanged shape consumer",
			"bank-ferns": "sourced low-fern import, whole-clump terrain placement and ordinary scene consumer",
			"foreground-bank": "near-bank placement and confirmed offline/shared machine-footprint suppression",
			"pine-understory": "complete pine resource, terrain and confirmed-machine visibility consumer",
			"construction-vegetation": "detached offline/shared plant clearance at confirmed construction heights",
			"pine-roots": "focused edge-inclusive terrain-root oracle correction",
			"pine-reflectance": "source-derived normal-incidence dielectric reflectance and cache isolation",
			"fir-resource": "complete sourced fir, generated distance detail and common resource interface",
			"bank-firs": "ordinary fir mounting, deterministic terrain poses and matching woody triangles",
			"bank-fir-lifecycle": "ordinary scene mounting inside the actual node tree",
			"ground-material": "qualified forest-floor material, data channels and cache separation",
			"ground-render": "source-period and frame-stability observations on separate passive planes",
			"water-flow": "layered translucent river resources and ordinary frame consumer",
			"rock-collision-shape": "visible rock facets versus the shared convex collision hull",
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
	verify(shared.pad_panels().is_empty() and shared.foundation_boxes().is_empty()
		and shared.architecture_boxes().is_empty(), "No old platform or canal survives in the physical site catalogue.")
	var stream: MeshInstance3D = scenery.get_node("StreamSurface")
	var water: PackedVector3Array = stream.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var covered := 0
	var minimum_gap := INF
	for first in range(0, water.size(), 3):
		var column := floori(float(first) / 6.0) % 8
		if column == 0 or column == 7:
			continue
		for offset in range(3):
			var point: Vector3 = water[first + offset] + stream.global_position
			if point.z >= -4.0 and point.z <= 7.0:
				covered += 1
				minimum_gap = minf(minimum_gap, point.y - shared.height_at(point.x, point.z))
	verify(covered > 0 and minimum_gap > 0.05,
		"The emitted river surface clears its actual natural terrain bed throughout the working reach.")
	print(JSON.stringify({"relation": "natural_bed_below_water", "minimum_gap": minimum_gap,
		"sampled_vertices": covered, "visible_boxes": rendered.size(), "rock_instances": 64}))
	view.free()

func _plant_patches(view: Node3D) -> Array[MultiMeshInstance3D]:
	var scenery: Node3D = view.get_node("ProductionScenery")
	var patches: Array[MultiMeshInstance3D] = []
	for name in ["GroundFoliage", "ForegroundBank", "PineUnderstory"]:
		patches.append(scenery.get_node(name) as MultiMeshInstance3D)
	for patch: MultiMeshInstance3D in scenery.get_node("MeadowPatches").get_children():
		patches.append(patch)
	return patches

func _plant_bounds(patch: MultiMeshInstance3D, data: PackedFloat32Array, offset: int) -> AABB:
	# Independent corner extrema of the actual mesh and uploaded transform.
	# Do not obtain a prediction from the production construction filter.
	var local := Transform3D(Basis(
		Vector3(data[offset], data[offset + 4], data[offset + 8]),
		Vector3(data[offset + 1], data[offset + 5], data[offset + 9]),
		Vector3(data[offset + 2], data[offset + 6], data[offset + 10])),
		Vector3(data[offset + 3], data[offset + 7], data[offset + 11]))
	var transform := patch.global_transform * local
	var mesh_bounds := patch.multimesh.mesh.get_aabb()
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for x in [mesh_bounds.position.x, mesh_bounds.end.x]:
		for y in [mesh_bounds.position.y, mesh_bounds.end.y]:
			for z in [mesh_bounds.position.z, mesh_bounds.end.z]:
				var at: Vector3 = transform * Vector3(x, y, z)
				low = low.min(at)
				high = high.max(at)
	return AABB(low, high - low)

func _expected_plants(patch: MultiMeshInstance3D, original: PackedFloat32Array, volumes: Array[AABB]) -> PackedFloat32Array:
	var kept := PackedFloat32Array()
	var stride := 16 if patch.multimesh.use_colors else 12
	for offset in range(0, original.size(), stride):
		var bounds := _plant_bounds(patch, original, offset)
		var intersects := false
		for volume: AABB in volumes:
			if bounds.intersects(volume.grow(0.08)):
				intersects = true
				break
		if not intersects:
			kept.append_array(original.slice(offset, offset + stride))
	return kept

func check_construction_vegetation() -> void:
	# Invented confirmed facts exercise the ordinary detached view callback.
	# No command, native body, Model, Store or network host is created.
	for axis in [0, 2]:
		var facts := {"options": {"native": true}, "entities": {"wheel": {"kind": "wheel", "cell": [-2, 1], "level": 2, "axis": axis, "tiles": 3}}}
		var boxes: Array[AABB] = Scenery._construction_volumes(facts)
		var center := Vector3(-3.3, 2.0 * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT, 1.65)
		var half: Vector3 = Geometry.wheel_half_extents(axis, 3)
		verify(boxes.size() == 1 and boxes[0].is_equal_approx(AABB(center - half, half * 2.0).grow(0.08)),
			"Vegetation clearance follows the wheel's size, axis and common shaft height.")
	for shared in [false, true]:
		var view: Variant = SharedBankView.new() if shared else FixtureView.new()
		root.add_child(view)
		view._build_world()
		var snapshots: Array[Dictionary] = []
		for patch: MultiMeshInstance3D in _plant_patches(view):
			if not verify(patch.multimesh != null and patch.multimesh.instance_count > 0,
					"The actual sourced plant population is available for the construction case."):
				view.free()
				return
			snapshots.append({"patch": patch, "buffer": patch.multimesh.buffer,
				"mesh": patch.multimesh.mesh, "material": patch.material_override,
				"aabb": patch.multimesh.custom_aabb})
		var bank: MultiMeshInstance3D = view.get_node("ProductionScenery/ForegroundBank")
		var original := bank.multimesh.buffer
		var sample := _plant_bounds(bank, original, 0)
		var cell := Vector2i(roundi(original[3] / Geometry.PITCH), roundi(original[11] / Geometry.PITCH))
		var level := ceili((sample.position.y + minf(sample.size.y * 0.5, 0.25)) / Geometry.HEIGHT_STEP)
		var top := Vector3(cell.x * Geometry.PITCH, level * Geometry.HEIGHT_STEP, cell.y * Geometry.PITCH)
		var foundation := AABB(top - Vector3(Geometry.PITCH * 0.5, Geometry.FOUNDATION_DEPTH, Geometry.PITCH * 0.5),
			Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH))
		verify(sample.intersects(foundation), "The regression fixture actually intersects its original source clump.")
		view.state = {"entities": {}, "foundations": {"surface": {"cell": [cell.x, cell.y], "level": level}}, "links": []}
		view._rebuild_machines()
		print(JSON.stringify({"case": "foundation_overlap", "shared": shared,
			"before": original.size() / 16, "after": bank.multimesh.instance_count,
			"cell": [cell.x, cell.y], "level": level}))
		if not verify(bank.multimesh.instance_count < original.size() / 16,
				"Confirmed foundations suppress intersecting soft plants before they clip through the surface."):
			view.free()
			return
		var machine_level := floori((sample.get_center().y - Geometry.MACHINE_CENTER_HEIGHT) / Geometry.HEIGHT_STEP)
		var machine_size := Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])
		var machine_center := Vector3(top.x, machine_level * Geometry.HEIGHT_STEP + Geometry.MACHINE_CENTER_HEIGHT, top.z)
		var cases: Array[Dictionary] = [
			{"name": "foundation", "entities": {}, "foundations": {"surface": {"cell": [cell.x, cell.y], "level": level}},
				"volumes": [foundation]},
			{"name": "elevated_machine", "entities": {"belt": {"kind": "belt", "cell": [cell.x, cell.y], "level": 1000}},
				"foundations": {}, "volumes": [AABB(Vector3(top.x, 1000 * Geometry.HEIGHT_STEP + Geometry.MACHINE_CENTER_HEIGHT, top.z) - machine_size * 0.5, machine_size)]},
			{"name": "machine_at_plant_height", "entities": {"belt": {"kind": "belt", "cell": [cell.x, cell.y], "level": machine_level}},
				"foundations": {}, "volumes": [AABB(machine_center - machine_size * 0.5, machine_size)]},
			{"name": "high_foundation", "entities": {}, "foundations": {"high": {"cell": [cell.x, cell.y], "level": 1000}},
				"volumes": [AABB(Vector3(top.x - Geometry.PITCH * 0.5, 1000 * Geometry.HEIGHT_STEP - Geometry.PITCH, top.z - Geometry.PITCH * 0.5), Vector3.ONE * Geometry.PITCH)]},
			{"name": "buried_foundation", "entities": {}, "foundations": {"low": {"cell": [cell.x, cell.y], "level": -1000}},
				"volumes": [AABB(Vector3(top.x - Geometry.PITCH * 0.5, -1000 * Geometry.HEIGHT_STEP - Geometry.PITCH, top.z - Geometry.PITCH * 0.5), Vector3.ONE * Geometry.PITCH)]}]
		# Give every actual patch an intersecting confirmed block in one state.
		var all_foundations := {}
		var all_volumes: Array[AABB] = []
		for index in range(snapshots.size()):
			var patch: MultiMeshInstance3D = snapshots[index].patch
			var data: PackedFloat32Array = snapshots[index].buffer
			var root_at: Vector3 = patch.global_transform * Vector3(data[3], data[7], data[11])
			var plant := _plant_bounds(patch, data, 0)
			var patch_cell := Vector2i(roundi(root_at.x / Geometry.PITCH), roundi(root_at.z / Geometry.PITCH))
			var patch_level := ceili((plant.position.y + minf(plant.size.y * 0.5, 0.25)) / Geometry.HEIGHT_STEP)
			all_foundations[str(index)] = {"cell": [patch_cell.x, patch_cell.y], "level": patch_level}
			all_volumes.append(AABB(Vector3(patch_cell.x * Geometry.PITCH - Geometry.PITCH * 0.5,
				patch_level * Geometry.HEIGHT_STEP - Geometry.PITCH, patch_cell.y * Geometry.PITCH - Geometry.PITCH * 0.5), Vector3.ONE * Geometry.PITCH))
		cases.append({"name": "all_patch_kinds", "entities": {}, "foundations": all_foundations, "volumes": all_volumes})
		for scenario in cases:
			view.state = {"entities": scenario.entities, "foundations": scenario.foundations, "links": []}
			var supplied: Dictionary = view.state.duplicate(true)
			var volumes: Array[AABB] = []
			volumes.assign(scenario.volumes)
			view._rebuild_machines()
			for snapshot in snapshots:
				var patch: MultiMeshInstance3D = snapshot.patch
				var expected := _expected_plants(patch, snapshot.buffer, volumes)
				verify(patch.multimesh.buffer == expected,
					"Actual complete plant records match independent world-space clearance: " + scenario.name + "/" + str(patch.name))
				verify(patch.multimesh.mesh == snapshot.mesh and patch.material_override == snapshot.material
					and patch.multimesh.custom_aabb == snapshot.aabb,
					"Filtering preserves sourced resources and the conservative original visibility bounds.")
				if scenario.name == "all_patch_kinds":
					verify(expected.size() < snapshot.buffer.size(), "Every plant population participates in construction clearance.")
			view._rebuild_machines()
			verify(view.state == supplied and view.model == null and view.actor_world == null and view.request_sequence == 0,
				"Repeated offline/shared presentation leaves confirmed facts intact and creates no authority or requests.")
			for snapshot in snapshots:
				verify(snapshot.patch.multimesh.buffer == _expected_plants(snapshot.patch, snapshot.buffer, volumes),
					"Repeated filtering always uses the original candidates.")
		var moved: MultiMeshInstance3D = snapshots.back().patch
		var old_position := moved.position
		moved.position += Vector3(2.0 * Geometry.PITCH, 8.0 * Geometry.HEIGHT_STEP, -Geometry.PITCH)
		var moved_data: PackedFloat32Array = snapshots.back().buffer
		var moved_root: Vector3 = moved.global_transform * Vector3(moved_data[3], moved_data[7], moved_data[11])
		var moved_bounds := _plant_bounds(moved, moved_data, 0)
		var moved_cell := Vector2i(roundi(moved_root.x / Geometry.PITCH), roundi(moved_root.z / Geometry.PITCH))
		var moved_level := ceili((moved_bounds.position.y + minf(moved_bounds.size.y * 0.5, 0.25)) / Geometry.HEIGHT_STEP)
		var moved_volume := AABB(Vector3(moved_cell.x * Geometry.PITCH - Geometry.PITCH * 0.5,
			moved_level * Geometry.HEIGHT_STEP - Geometry.PITCH, moved_cell.y * Geometry.PITCH - Geometry.PITCH * 0.5), Vector3.ONE * Geometry.PITCH)
		view.state = {"entities": {}, "foundations": {"moved": {"cell": [moved_cell.x, moved_cell.y], "level": moved_level}}, "links": []}
		view._rebuild_machines()
		var moved_expected := _expected_plants(moved, moved_data, [moved_volume])
		verify(moved_expected.size() < moved_data.size() and moved.multimesh.buffer == moved_expected,
			"Translated local meadow records are cleared at their world-space height and position.")
		moved.position = old_position
		view.state = {"entities": {}, "foundations": {}, "links": []}
		view._rebuild_machines()
		for snapshot in snapshots:
			verify(snapshot.patch.multimesh.buffer == snapshot.buffer, "Removing construction restores every original candidate byte.")
		view.free()

func check_bank_ferns() -> void:
	var group := Scenery._bank_ferns()
	verify(Scenery.fern_source_status == "ready" and group.get_child_count() == 1,
		"The complete capture mounts the sourced fern component.")
	if group.get_child_count() != 1:
		group.free()
		return
	var clumps: MultiMeshInstance3D = group.get_child(0)
	var instances := clumps.multimesh
	var mesh := instances.mesh
	var material := clumps.material_override as StandardMaterial3D
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	verify(vertices.size() == 544 and indices.size() == 2352 and normals.size() == 544
		and tangents.size() == 2176 and uv.size() == 544,
		"Runtime import retains the selected clump and complete normal-mapped attributes.")
	for n in range(vertices.size()):
		var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
		verify(vertices[n].is_finite() and normals[n].is_finite() and uv[n].is_finite()
			and absf(normals[n].length() - 1.0) < 0.002 and tangent.is_finite()
			and tangent.length() > 0.99 and absf(tangent.dot(normals[n])) < 0.002,
			"Imported fern geometry has finite unit normals and orthogonal tangent frames.")
	for index in indices:
		verify(index >= 0 and index < vertices.size(), "Every imported leaf triangle references the selected mesh.")
	verify(mesh.get_aabb().size.x < 0.56 and mesh.get_aabb().size.z < 0.62
		and mesh.get_aabb().size.y < 0.30,
		"The compact source stays at its original metre scale without catalogue placement.")
	verify(material != null and material.metallic == 0.0 and material.ao_enabled
		and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		and is_equal_approx(material.alpha_scissor_threshold, 0.5) and material.cull_mode == BaseMaterial3D.CULL_DISABLED,
		"The two-sided fern uses dielectric cutout foliage rather than blended opaque cards.")
	for texture in [material.albedo_texture, material.normal_texture, material.roughness_texture]:
		verify(texture != null and texture.get_image().has_mipmaps(), "Every actual fern texture has cached mip levels.")
	var color := material.albedo_texture.get_image()
	var covered := 0
	for y in range(color.get_height()):
		for x in range(color.get_width()):
			if color.get_pixel(x, y).a >= 0.5:
				covered += 1
	verify(color.get_size() == Vector2i(384, 384) and absf(float(covered) / (384 * 384) - 0.153910319010417) < 0.000001,
		"The runtime cutout retains the prepared leaf silhouette coverage.")
	var buffer := instances.buffer
	verify(instances.instance_count >= 4 and instances.instance_count <= 32
		and buffer.size() == instances.instance_count * 16, "A bounded modest set of low plants is actually uploaded.")
	var near_count := 0
	var solids: Array = Scenery.Surface.support_boxes()
	for n in range(instances.instance_count):
		var offset := n * 16
		var at := Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
		var basis := Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
			Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
			Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10]))
		var envelope: AABB = Transform3D(basis, at) * mesh.get_aabb()
		verify(at.is_finite() and basis.is_finite() and basis.determinant() > 0.5
			and absf(at.y - Scenery.Surface.height_at(at.x, at.z)) < 0.0001,
			"Each actual low-plant root follows the unchanged terrain with a finite upright frame.")
		if absf(at.z - 1.65) < 25.0:
			near_count += 1
		var corners: Array[Vector3] = []
		for corner in range(8):
			var point := envelope.get_endpoint(corner)
			corners.append(point)
			verify((absf(point.x - 1.65) > 7.0 or absf(point.z - 1.65) > 7.0)
				and absf(point.x - Scenery.river_center_x(point.z)) > Scenery.channel_half_width(point.z) + 0.55
				and instances.custom_aabb.grow(0.0001).has_point(point),
				"The whole transformed clump clears the pad and channel and lies inside its actual culling bounds.")
		var clear := true
		for solid in solids:
			var separated := false
			for axis_index in range(3):
				var axis: Vector3 = solid.basis[axis_index]
				var low := INF
				var high := -INF
				for point in corners:
					low = minf(low, point.dot(axis))
					high = maxf(high, point.dot(axis))
				var center: float = solid.center.dot(axis)
				var radius: float = solid.size[axis_index] * 0.5
				separated = separated or high < center - radius - 0.05 or low > center + radius + 0.05
			clear = clear and separated
		verify(clear, "Actual whole-clump envelopes have a separating axis from every existing solid.")
	verify(near_count >= 2, "Undergrowth includes the worksite's near surroundings rather than only distant points.")
	verify(Scenery.read_foliage(Scenery.FERN_FILE).status == "invalid"
		and Scenery.read_foliage(fixture_directory.path_join("not-shipped-fern.glb"), 544, 2352).status == "missing",
		"Wrong-profile and absent assets remain distinct from a valid selected component.")
	var view := FixtureView.new()
	root.add_child(view)
	view._build_world()
	var actual_clumps: MultiMeshInstance3D = view.get_node("ProductionScenery/BankFerns/FernClumps")
	verify(actual_clumps.multimesh.mesh == mesh and actual_clumps.material_override == material
		and actual_clumps.multimesh.buffer == buffer and view.model == null and view.actor_world == null,
		"The ordinary scenery consumer reuses deterministic fern resources without starting authority.")
	inspect_visual(view.get_node("ProductionScenery/BankFerns"))
	print(JSON.stringify({"clumps": instances.instance_count, "near_clumps": near_count,
		"triangles_before_culling": instances.instance_count * 784, "gpu_performance": "not_measured"}))
	view.free()
	group.free()

func check_water_flow() -> void:
	var water := Scenery.water_material()
	var texture := water.normal_texture
	var mesh := Scenery.stream_mesh()
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].duplicate()
	var fine := water.detail_normal
	verify(water == Scenery.water_material() and water.metallic == 0.0,
		"The water keeps a shared dielectric material rather than metallic shading.")
	verify(water.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and water.normal_enabled
		and texture != null and texture.get_image().has_mipmaps() and water.texture_repeat,
		"Moving detail uses repeated mipmapped normals with explicit alpha transmission.")
	verify(water.albedo_color.r == 1.0 and water.albedo_color.g == 1.0 and water.albedo_color.b == 1.0
		and water.albedo_color.a > 0.4 and water.albedo_color.a < 0.9 and water.vertex_color_use_as_albedo,
		"The existing river palette is applied once, with partial transmission instead of a second dark tint.")
	verify(water.roughness > 0.05 and water.roughness < 0.3 and water.metallic_specular > 0.0
		and water.metallic_specular < 0.5 and not water.refraction_enabled
		and water.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY,
		"The lit dielectric surface retains reflections without screen refraction or a transparent depth occluder.")
	verify(water.detail_enabled and water.detail_uv_layer == BaseMaterial3D.DETAIL_UV_2
		and water.detail_blend_mode == BaseMaterial3D.BLEND_MODE_MUL and fine != texture
		and fine != null and fine.get_image().has_mipmaps(),
		"Independent secondary coordinates blend a distinct mipmapped fine-normal layer.")
	var blend := water.detail_albedo.get_image().get_pixel(0, 0)
	verify(blend.r == 1.0 and blend.g == 1.0 and blend.b == 1.0 and blend.a > 0.34 and blend.a < 0.36,
		"The detail blend preserves albedo and retains both normal layers.")
	var arrays := mesh.surface_get_arrays(0)
	verify(arrays[Mesh.ARRAY_TEX_UV2] == arrays[Mesh.ARRAY_TEX_UV],
		"Every actual stream vertex supplies matching undeformed secondary texture coordinates.")
	for ripple in [texture, fine]:
		var original: Image = ripple.get_image()
		var bytes := original.get_data()
		verify(original.get_format() == Image.FORMAT_RGB8 and original.get_size() == Vector2i(128, 128),
			"Both authored normal maps use the declared RGB8 extent.")
		for level in range(original.get_mipmap_count() + 1):
			var dimension := maxi(1, original.get_width() >> level)
			var offset := original.get_mipmap_offset(level)
			var mip := Image.create_from_data(dimension, dimension, false, Image.FORMAT_RGB8,
				bytes.slice(offset, offset + dimension * dimension * 3))
			for y in range(0, mip.get_height(), maxi(1, mip.get_height() >> 4)):
				for x in range(0, mip.get_width(), maxi(1, mip.get_width() >> 4)):
					var pixel := mip.get_pixel(x, y)
					var normal := Vector3(pixel.r, pixel.g, pixel.b) * 2.0 - Vector3.ONE
					verify(normal.is_finite() and absf(normal.length() - 1.0) < 0.02 and normal.z > 0.9,
						"Both ripple layers retain finite forward unit normals through every mip level.")
	verify(Scenery.animate_water(0.0) and water.uv1_offset == Vector3.ZERO, "The visual phase starts at the original normal-map coordinates.")
	verify(water.uv2_offset == Vector3.ZERO, "The fine layer also starts at its original coordinates.")
	var before := water.uv1_offset
	verify(Scenery.animate_water(1.0) and water.uv1_offset.y < before.y,
		"The actual texture transform advances the pattern toward positive downstream Z.")
	var travelled := -(water.uv1_offset.y - before.y) / (0.08 * water.uv1_scale.y)
	verify(absf(travelled - 0.4) < 0.000001, "The declared environmental ripple speed is 0.4 metres per second in the authored stream UVs.")
	verify(absf(-water.uv2_offset.y - 0.536) < 0.000001
		and absf(-water.uv2_offset.x / (0.22 * water.uv2_scale.x) - 0.025) < 0.000001,
		"The higher-density normal advects one full period plus 0.536 downstream and drifts gently across the river.")
	var once := water.uv1_offset
	var fine_once := water.uv2_offset
	verify(Scenery.animate_water(1.0) and water.uv1_offset == once,
		"Repeated updates at the same absolute time cannot accelerate the shared texture.")
	verify(water.uv2_offset == fine_once, "The fine-layer phase is also idempotent across views.")
	verify(Scenery.animate_water(3.90625) and water.uv1_offset.length() < 0.000001,
		"One complete normal-texture period wraps to its initial coordinates.")
	verify(Scenery.animate_water(1000000.25) and water.uv1_offset.is_finite()
		and water.uv1_offset.y <= 0.0 and water.uv1_offset.y > -1.0, "Long-running presentation retains a bounded finite offset.")
	var valid := water.uv1_offset
	var fine_valid := water.uv2_offset
	for invalid in [-1.0, NAN, INF]:
		verify(not Scenery.animate_water(invalid) and water.uv1_offset == valid and water.uv2_offset == fine_valid,
			"Invalid presentation time preserves both last valid material phases.")
	verify(Scenery.animate_water(1e308) and water.uv1_offset.is_finite() and water.uv2_offset.is_finite()
		and water.uv2_offset.x <= 0.0 and water.uv2_offset.x > -1.0
		and water.uv2_offset.y <= 0.0 and water.uv2_offset.y > -1.0,
		"Even an extreme finite presentation time cannot overflow the faster layer.")
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
	var historical := Opening.FlatFixtureEnvironment.water_material()
	verify(historical != water and historical.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"The separate historical flat fixture keeps its original opaque water.")
	view.legacy_fixture = false
	view._build_world()
	var stream: MeshInstance3D = view.get_node("ProductionScenery/StreamSurface")
	verify(stream.material_override == water and stream.mesh == mesh
		and stream.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and view.model == null and view.actor_world == null and view.state.is_empty(),
		"The ordinary scene binds the layered finish without starting authority or creating a shadow occluder.")
	verify(Scenery.stream_mesh() == mesh and mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices
		and water.normal_texture == texture and water.detail_normal == fine,
		"Animation preserves every water vertex and both shared normal resources.")
	second.free()
	view.free()

func check_ground_material() -> void:
	if not fixture_directory.is_absolute_path() or not DirAccess.dir_exists_absolute(fixture_directory):
		verify(false, "Use the declared external material-test artifact directory.")
		return
	var ground := Scenery.ground_material()
	verify(Scenery.ground_source_status == "ready" and ground is ShaderMaterial,
		"The ordinary ground material loads the complete sourced bitmap set.")
	if ground == null:
		return
	verify(ground == Scenery.ground_material() and Opening.ProductionSteelFloor.source_status == "uninitialized",
		"Terrain material reuse does not consume or poison the independent steel cache.")
	var albedo: Texture2D = ground.get_shader_parameter("albedo_map")
	var normal: Texture2D = ground.get_shader_parameter("normal_map")
	var scalars: Texture2D = ground.get_shader_parameter("arm_map")
	verify(albedo.get_image().get_size() == Vector2i(1024, 1024)
		and normal.get_image().get_size() == Vector2i(512, 512)
		and scalars.get_image().get_size() == Vector2i(512, 512),
		"The bounded albedo, OpenGL normal and scalar map retain their declared resolutions.")
	verify(albedo.get_image().has_mipmaps() and normal.get_image().has_mipmaps()
		and scalars.get_image().has_mipmaps(), "All shared terrain resources have mipmaps.")
	verify(ground.shader == Scenery.GROUND_SHADER and is_equal_approx(ground.get_shader_parameter("source_extent"), 1.3),
		"The cached stochastic surface binds the same qualified 1.3-metre source scale and stationary world-space shader.")
	var packed := Image.load_from_file(Scenery.GROUND_ROOT.path_join(Scenery.GROUND_FILES.arm))
	var actual := scalars.get_image()
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
	verify(missing.status == "missing" and missing.images.is_empty(), "An absent bitmap set cannot masquerade as a qualified surface.")
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


func image_difference(first: Image, second: Image, shift: int = 0) -> float:
	var difference := 0.0
	var samples := 0
	for y in range(8, first.get_height() - 8, 4):
		for x in range(8, first.get_width() - shift - 8, 4):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x + shift, y)
			difference += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			samples += 1
	return difference / float(maxi(1, samples))


func check_ground_render() -> void:
	if not verify(DisplayServer.get_name().to_lower() != "headless" and fixture_directory.is_absolute_path(),
		"Shader rendering requires an owned viewport on a real renderer and an absolute artifact directory."):
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 320)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.0
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	camera.position = Vector3(0, 10, 0)
	camera.rotation_degrees.x = -90
	world.add_child(camera)
	camera.current = true
	var ground := Scenery.ground_material()
	var reference := StandardMaterial3D.new()
	reference.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	reference.albedo_texture = ground.get_shader_parameter("albedo_map")
	reference.uv1_triplanar = true
	reference.uv1_world_triplanar = true
	reference.uv1_scale = Vector3.ONE / 1.3
	var planes: Array[MeshInstance3D] = []
	for x in [-5.2, 5.2]:
		var plane := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(10.4, 6.5)
		plane.mesh = mesh
		plane.position.x = x
		plane.material_override = reference
		world.add_child(plane)
		planes.append(plane)
	await process_frame
	await RenderingServer.frame_post_draw
	var repeated := viewport.get_texture().get_image()
	for plane in planes:
		plane.material_override = ground
	await process_frame
	await RenderingServer.frame_post_draw
	var varied := viewport.get_texture().get_image()
	await process_frame
	await RenderingServer.frame_post_draw
	var stable := viewport.get_texture().get_image()
	for entry in [["ground-reference.png", repeated], ["ground-stochastic.png", varied], ["ground-stable.png", stable]]:
		var path: String = fixture_directory.path_join(entry[0])
		verify(not FileAccess.file_exists(path) and entry[1].save_png(path) == OK,
			"Retain each original own-viewport observation without replacing a previous image.")
	# The 20.8-metre view has 64 pixels per original 1.3-metre source period.
	var periodic_error := image_difference(repeated, repeated, 64)
	var varied_error := image_difference(varied, varied, 64)
	var frame_error := image_difference(varied, stable)
	verify(periodic_error < 0.003, "The independent repeating reference proves that the source period is resolved by the viewport.")
	verify(varied_error > maxf(0.01, periodic_error * 8.0),
		"The actual shader breaks the source-period repeat across separately positioned terrain meshes.")
	verify(frame_error < 0.00001, "Stationary ground shading is stable across completed rendered frames.")
	print(JSON.stringify({"phase": "ground-render", "reference_period_error": periodic_error,
		"stochastic_period_error": varied_error, "frame_error": frame_error, "display": DisplayServer.get_name(),
		"source_extent_metres": 1.3, "source_period_pixels": 64, "viewport": [1024, 320],
		"game_entry": "not_run", "input": "not_used", "human_quality": "not_assessed"}))
	viewport.free()

func check_rock_shapes(rocks: MultiMesh) -> void:
	var specs: Array[Dictionary] = Scenery.Surface.rock_boxes()
	var buffer := rocks.buffer
	verify(rocks.instance_count == specs.size() and specs.size() == 64,
		"Every shared rock collision descriptor has one visible instance.")
	verify(buffer.size() == specs.size() * 16, "Read the actual uploaded rock transforms and colors.")
	if buffer.size() != specs.size() * 16:
		return
	var vertices: PackedVector3Array = rocks.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	verify(vertices == Scenery.Surface.rock_faces(), "The actual rendered mesh uses the shared convex facets.")
	check_mesh_attributes(rocks.mesh, "Natural convex rock")
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var offset := index * 16
		var origin := Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
		var uploaded := Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
			Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
			Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10]))
		verify(origin.is_equal_approx(spec.center), "Visible and physical rock origins agree: " + spec.id)
		for point in vertices:
			var visible_point := origin + uploaded * point
			var found := false
			for physical_point in spec.points:
				found = found or visible_point.is_equal_approx(spec.center + spec.basis * physical_point)
			verify(found, "Every actually uploaded rock facet vertex belongs to the same native convex hull: " + spec.id)

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
			var offset: int = (cell.y * (Scenery.Surface.grid_size() - 1) + cell.x) * 6
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

func check_foreground_bank() -> void:
	for shared in [false, true]:
		var view = SharedBankView.new() if shared else FixtureView.new()
		root.add_child(view)
		view._build_world()
		var patch: MultiMeshInstance3D = view.get_node("ProductionScenery/ForegroundBank")
		inspect_visual(patch)
		var instances := patch.multimesh
		var original := instances.buffer
		verify(instances.instance_count >= 32 and instances.instance_count <= 96
			and original.size() == instances.instance_count * 16, "A bounded population consumes the actual sourced grass mesh.")
		verify(instances.mesh == Scenery.foliage_cluster_mesh and patch.material_override == Scenery.foliage_finish
			and patch.visibility_range_end == 40.0, "Foreground shares the existing material and declares its culling range.")
		var solids: Array = Scenery.Surface.support_boxes()
		for offset in range(0, original.size(), 16):
			var basis := Basis(Vector3(original[offset], original[offset + 4], original[offset + 8]),
				Vector3(original[offset + 1], original[offset + 5], original[offset + 9]),
				Vector3(original[offset + 2], original[offset + 6], original[offset + 10]))
			var at := Vector3(original[offset + 3], original[offset + 7], original[offset + 11])
			var cell: Vector2i = Scenery.Surface.cell(at.x, at.z)
			var a: Vector3 = Scenery.Surface.vertex(cell.x, cell.y)
			var b: Vector3 = Scenery.Surface.vertex(cell.x + 1, cell.y)
			var c: Vector3 = Scenery.Surface.vertex(cell.x + 1, cell.y + 1)
			var d: Vector3 = Scenery.Surface.vertex(cell.x, cell.y + 1)
			var found := false
			for triangle in [[a, b, c], [a, c, d]]:
				if not Geometry2D.point_is_inside_triangle(Vector2(at.x, at.z), Vector2(triangle[0].x, triangle[0].z),
					Vector2(triangle[1].x, triangle[1].z), Vector2(triangle[2].x, triangle[2].z)):
					continue
				var normal: Vector3 = (triangle[2] - triangle[0]).cross(triangle[1] - triangle[0]).normalized()
				var height: float = triangle[0].y - (normal.x * (at.x - triangle[0].x) + normal.z * (at.z - triangle[0].z)) / normal.y
				verify(absf(at.y - height) < 0.0001 and basis.y.normalized().dot(normal) > 0.99999
					and normal.y >= 0.86, "Actual roots match emitted terrain planes and their normals.")
				found = true
			verify(found and basis.is_finite() and basis.determinant() > 0.6, "Actual transforms are finite and nondegenerate.")
			var envelope: AABB = Transform3D(basis, at) * instances.mesh.get_aabb()
			verify(instances.custom_aabb.grow(0.0001).encloses(envelope), "Culling bounds contain each complete clump.")
			for row in range(33):
				var z := lerpf(envelope.position.z, envelope.end.z, float(row) / 32.0)
				verify(envelope.end.x < Scenery.river_center_x(z) - Scenery.channel_half_width(z) - 0.2,
					"The whole envelope remains on the west bank, clear of water and the east working bank.")
			for solid in solids:
				var local: Vector3 = solid.basis.transposed() * (at - solid.center)
				verify(absf(local.x) > solid.size.x * 0.5 + 0.9 or absf(local.y) > solid.size.y * 0.5 + 0.9
					or absf(local.z) > solid.size.z * 0.5 + 0.9, "Clumps retain conservative separation from real rocks.")
		# Invented confirmed facts exercise the real view callback, not Core admission.
		var cell := [roundi(original[3] / 1.65), roundi(original[11] / 1.65)]
		view.state = {"entities": {"belt-test": {"kind": "belt", "cell": cell}}, "links": []}
		var supplied: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		verify(instances.instance_count < original.size() / 16 and view.machine_root.get_child_count() > 0,
			"Ordinary machine assembly suppresses overlapping bank plants.")
		var kept := instances.buffer
		var size := Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])
		var center := Vector3(cell[0] * 1.65, Geometry.MACHINE_CENTER_HEIGHT, cell[1] * 1.65)
		for offset in range(0, kept.size(), 16):
			var basis := Basis(Vector3(kept[offset], kept[offset + 4], kept[offset + 8]),
				Vector3(kept[offset + 1], kept[offset + 5], kept[offset + 9]),
				Vector3(kept[offset + 2], kept[offset + 6], kept[offset + 10]))
			var at := Vector3(kept[offset + 3], kept[offset + 7], kept[offset + 11])
			var envelope: AABB = Transform3D(basis, at) * instances.mesh.get_aabb()
			verify(not envelope.intersects(AABB(center - size * 0.5, size).grow(0.08)),
				"Every surviving clump clears the projected machine envelope.")
		verify(view.state == supplied and view.model == null and view.actor_world == null and view.request_sequence == 0,
			"Both consumers preserve supplied facts and create no authority or requests.")
		view._rebuild_machines()
		verify(instances.buffer == kept, "Repeated confirmed rebuilds are idempotent.")
		view.state = {"entities": {}, "links": []}
		view._rebuild_machines()
		verify(instances.buffer == original and patch.get_meta("candidate_buffer") == original,
			"Confirmed removal restores candidates without saving vegetation state.")
		print(JSON.stringify({"shared": shared, "foreground_tufts": original.size() / 16,
			"triangles_before_culling": original.size() / 16 * 1257, "suppressed_tufts": (original.size() - kept.size()) / 16}))
		view.free()

func check_pine_reflectance() -> void:
	var source_path := fixture_directory.path_join("qualified-pine.gltf")
	if not verify(FileAccess.get_sha256(source_path) == "f358c01926861dd082f32dba60f7c9fba232b585a985cf38c0d2229eecf4bc48",
		"The independent material oracle reads the pinned original descriptor, without importing geometry."):
		return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var raw := ResourceLoader.load(Scenery.PINE_FILE, "ArrayMesh") as ArrayMesh
	var old_materials: Array[StandardMaterial3D] = []
	var arrays_before: Array = []
	var pixels_before: Array = []
	for surface in range(2):
		old_materials.append(raw.surface_get_material(surface))
		arrays_before.append(raw.surface_get_arrays(surface))
		var maps: Array = []
		for field in ["albedo_texture", "normal_texture", "roughness_texture"]:
			maps.append(old_materials[surface].get(field).get_image().get_data())
		pixels_before.append(maps)
	var loaded := Scenery.read_pine()
	if not verify(loaded.status == "ready", "The actual pine adapter consumes its unchanged prepared resource."):
		return
	for surface in range(2):
		var primitive: Dictionary = source.meshes[0].primitives[surface]
		var original: Dictionary = source.materials[int(primitive.material)]
		var extension: Dictionary = original.extensions.KHR_materials_specular
		var ior: float = original.extensions.KHR_materials_ior.ior
		var factor: Array = extension.specularColorFactor
		verify(original.pbrMetallicRoughness.metallicFactor == 0 and factor[0] == factor[1] and factor[1] == factor[2]
			and extension.get("specularFactor", 1.0) == 1.0 and not extension.has("specularTexture")
			and not extension.has("specularColorTexture"), "The source is the declared untinted, untextured dielectric case.")
		# Khronos' IOR/specular extension and the pinned Compatibility shader
		# define these independently of our adapter's chosen scalar constants.
		var expected := pow((ior - 1.0) / (ior + 1.0), 2.0) * float(factor[0])
		var finish := loaded.mesh.surface_get_material(surface) as StandardMaterial3D
		var actual := 0.16 * finish.metallic_specular * finish.metallic_specular
		verify(absf(actual - expected) < 0.00000001, "Actual normal-incidence reflectance agrees with the qualified source.")
		verify(old_materials[surface].metallic_specular == 0.5, "Binding the pine adaptation preserves the original imported material object.")
		verify(arrays_before[surface] == loaded.mesh.surface_get_arrays(surface), "Adapting reflectance changes no geometry attribute or index.")
		for n in range(3):
			var field: String = ["albedo_texture", "normal_texture", "roughness_texture"][n]
			verify(pixels_before[surface][n] == finish.get(field).get_image().get_data(), "Adapting reflectance preserves every prepared mip pixel.")
		verify(Scenery.read_pine().mesh.surface_get_material(surface) == finish, "Repeated actual reads reuse the bound material instead of creating per-view copies.")
		print(JSON.stringify({"surface": surface, "source_ior": ior, "source_specular_color": factor,
			"expected_F0": expected, "actual_F0": actual, "bound_specular": finish.metallic_specular}))
	verify(FileAccess.get_sha256(Scenery.PINE_FILE) == Scenery.PINE_SHA256, "The prepared native resource stays byte-identical.")

func check_pine_root(basis: Basis, at: Vector3) -> void:
	var cell: Vector2i = Scenery.Surface.cell(at.x, at.z)
	var a: Vector3 = Scenery.Surface.vertex(cell.x, cell.y)
	var b: Vector3 = Scenery.Surface.vertex(cell.x + 1, cell.y)
	var c: Vector3 = Scenery.Surface.vertex(cell.x + 1, cell.y + 1)
	var d: Vector3 = Scenery.Surface.vertex(cell.x, cell.y + 1)
	var found := false
	var strict_found := false
	for triangle in [[a, b, c], [a, c, d]]:
		strict_found = strict_found or Geometry2D.point_is_inside_triangle(Vector2(at.x, at.z),
			Vector2(triangle[0].x, triangle[0].z), Vector2(triangle[1].x, triangle[1].z), Vector2(triangle[2].x, triangle[2].z))
		var aa: Vector3 = triangle[0]
		var bb: Vector3 = triangle[1]
		var cc: Vector3 = triangle[2]
		var denominator := (bb.z - cc.z) * (aa.x - cc.x) + (cc.x - bb.x) * (aa.z - cc.z)
		var u := ((bb.z - cc.z) * (at.x - cc.x) + (cc.x - bb.x) * (at.z - cc.z)) / denominator
		var v := ((cc.z - aa.z) * (at.x - cc.x) + (aa.x - cc.x) * (at.z - cc.z)) / denominator
		# A float32 uploaded root may lie on a triangle edge. Barycentric
		# inclusion accepts the edge; this is an art oracle, not reach epsilon.
		if minf(u, minf(v, 1.0 - u - v)) < -0.00001:
			continue
		var normal: Vector3 = (cc - aa).cross(bb - aa).normalized()
		var height := aa.y - (normal.x * (at.x - aa.x) + normal.z * (at.z - aa.z)) / normal.y
		verify(absf(at.y - height + 0.015) < 0.0001 and normal.y >= 0.86,
			"The original stem root embeds slightly in the actual emitted terrain triangle.")
		found = true
	verify(found and basis.is_finite() and basis.y.normalized().dot(Vector3.UP) > 0.99999
		and basis.y.length() >= 0.8499 and basis.y.length() <= 1.2501,
		"Young stems keep gravity-up orientation and their declared near-source scale.")
	print(JSON.stringify({"root": [at.x, at.y, at.z], "strict_triangle_inclusion": strict_found,
		"edge_inclusive_triangle": found, "up": [basis.y.x, basis.y.y, basis.y.z]}))

func check_pine_roots() -> void:
	var loaded := Scenery.read_pine()
	if not verify(loaded.status == "ready", "The focused root check consumes the unchanged native resource."):
		return
	Scenery.pine_cluster_mesh = loaded.mesh
	Scenery.pine_source_status = "ready"
	var patch := Scenery._pine_understory()
	var buffer := patch.multimesh.buffer
	for offset in range(0, buffer.size(), 12):
		var basis := Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
			Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
			Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10]))
		check_pine_root(basis, Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11]))
	patch.free()

func check_pine_understory() -> void:
	var loaded := Scenery.read_pine()
	if not verify(loaded.status == "ready", "The complete source capture loads the pinned native pine resource."):
		return
	var mesh: ArrayMesh = loaded.mesh
	verify(mesh.get_blend_shape_count() == 0 and mesh.get_surface_count() == 2,
		"The selected sapling retains its two static source surfaces.")
	for surface in range(2):
		var arrays := mesh.surface_get_arrays(surface)
		verify(arrays[Mesh.ARRAY_VERTEX].size() == (315 if surface == 0 else 124481)
			and arrays[Mesh.ARRAY_INDEX].size() == (1458 if surface == 0 else 365247),
			"Every original bark and needle triangle remains in the native resource.")
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		verify(material != null and material.metallic == 0.0 and material.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"The two-sided source surfaces remain dielectric.")
		verify(material.transparency == (BaseMaterial3D.TRANSPARENCY_DISABLED if surface == 0 else BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
			and is_equal_approx(material.metallic_specular, 0.1 if surface == 0 else 0.07071067811865476) and not material.ao_enabled,
			"The actual materials bind the source-derived reflectance and retained cutout/occlusion modes.")
		for field in ["albedo_texture", "normal_texture", "roughness_texture"]:
			var image: Image = material.get(field).get_image()
			var dimension := 384 if field == "albedo_texture" else 256
			verify(image.get_size() == Vector2i(dimension, dimension) and image.get_format() == Image.FORMAT_RGB8
				and image.has_mipmaps(), "The actual native resource embeds every bounded, mipmapped prepared image.")
	verify(Scenery.read_pine(fixture_directory.path_join("not-shipped-pine.res")).status == "missing",
		"A missing historical optional resource is an explicit omission.")
	var wrong_path := fixture_directory.path_join("wrong-pine.res")
	var wrong := FileAccess.open(wrong_path, FileAccess.WRITE)
	wrong.store_string("A mismatched local asset is not a native resource.")
	wrong.close()
	verify(Scenery.read_pine(wrong_path).status == "invalid", "Wrong asset bytes are refused before native-resource deserialization.")
	for shared in [false, true]:
		var view = SharedBankView.new() if shared else FixtureView.new()
		root.add_child(view)
		view._build_world()
		var patch: MultiMeshInstance3D = view.get_node("ProductionScenery/PineUnderstory")
		inspect_visual(patch)
		var instances := patch.multimesh
		if not verify(instances != null and instances.instance_count >= 3 and instances.instance_count <= 6,
			"The ordinary consumer mounts a small, bounded set of complete young plants."):
			view.free()
			return
		var original := instances.buffer
		verify(instances.mesh == mesh and original.size() == instances.instance_count * 12
			and patch.visibility_range_end == 32.0 and patch.material_override == null,
			"Both consumers share original surface materials, cached geometry and a declared visibility range.")
		for offset in range(0, original.size(), 12):
			var basis := Basis(Vector3(original[offset], original[offset + 4], original[offset + 8]),
				Vector3(original[offset + 1], original[offset + 5], original[offset + 9]),
				Vector3(original[offset + 2], original[offset + 6], original[offset + 10]))
			var at := Vector3(original[offset + 3], original[offset + 7], original[offset + 11])
			check_pine_root(basis, at)
			var envelope: AABB = Transform3D(basis, at) * mesh.get_aabb()
			verify(instances.custom_aabb.grow(0.0001).encloses(envelope), "Culling bounds enclose every entire sapling.")
			for row in range(33):
				var z := lerpf(envelope.position.z, envelope.end.z, float(row) / 32.0)
				verify(envelope.end.x < Scenery.river_center_x(z) - Scenery.channel_half_width(z) - 0.3,
					"The complete plant stays outside the water and eastern construction bank.")
			for solid in Scenery.Surface.support_boxes():
				var half: Vector3 = solid.size * 0.5
				var solid_bounds: AABB = Transform3D(solid.basis, solid.center) * AABB(-half, solid.size)
				verify(not envelope.intersects(solid_bounds.grow(0.2)), "The whole plant clears existing rock envelopes.")
		# Disclosed invented confirmed facts call the actual offline/shared view;
		# these are presentation controls, not new material or native admissions.
		var cell := [roundi(original[3] / 1.65), roundi(original[11] / 1.65)]
		view.state = {"entities": {"pine-clearance": {"kind": "belt", "cell": cell}}, "links": []}
		var supplied: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		var kept := instances.buffer
		verify(instances.instance_count < original.size() / 12 and view.machine_root.get_child_count() > 0,
			"An ordinary confirmed-machine rebuild suppresses the intersecting young plant.")
		var center := Vector3(cell[0] * 1.65, Geometry.MACHINE_CENTER_HEIGHT, cell[1] * 1.65)
		var size := Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])
		for offset in range(0, kept.size(), 12):
			var basis := Basis(Vector3(kept[offset], kept[offset + 4], kept[offset + 8]),
				Vector3(kept[offset + 1], kept[offset + 5], kept[offset + 9]),
				Vector3(kept[offset + 2], kept[offset + 6], kept[offset + 10]))
			var at := Vector3(kept[offset + 3], kept[offset + 7], kept[offset + 11])
			verify(not (Transform3D(basis, at) * mesh.get_aabb()).intersects(AABB(center - size * 0.5, size).grow(0.08)),
				"Every retained whole-plant envelope clears the confirmed machine.")
		view._rebuild_machines()
		verify(instances.buffer == kept and view.state == supplied and view.model == null and view.actor_world == null
			and view.request_sequence == 0, "Both consumers are idempotent and create no authority or material requests.")
		view.state = {"entities": {}, "links": []}
		view._rebuild_machines()
		verify(instances.buffer == original, "Removing the confirmed machine restores derived candidates.")
		print(JSON.stringify({"shared": shared, "plants": original.size() / 12,
			"triangles_before_culling": original.size() / 12 * 122235, "suppressed": (original.size() - kept.size()) / 12}))
		view.free()
	var saved_mesh: ArrayMesh = Scenery.pine_cluster_mesh
	Scenery.pine_cluster_mesh = null
	Scenery.pine_source_status = "missing"
	var absent := Scenery._pine_understory()
	verify(absent.multimesh == null and absent.get_child_count() == 0, "An incomplete historical capture has no substitute tree or hidden authority.")
	absent.free()
	Scenery.pine_cluster_mesh = saved_mesh
	Scenery.pine_source_status = "ready"

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

func count_material_users(node: Node, material: Material) -> int:
	var total := 1 if node is MeshInstance3D and node.material_override == material else 0
	for child in node.get_children():
		total += count_material_users(child, material)
	return total

func check_stone_material() -> void:
	var material := Scenery.stone_material()
	if not verify(Scenery.stone_source_status == "ready", "The ordinary stone path consumes the complete photographed source set."):
		return
	verify(material == Scenery.stone_material() and material.albedo_color == Color.WHITE
		and material.vertex_color_use_as_albedo and material.metallic == 0.0 and material.roughness == 1.0,
		"The shared stone cache preserves photographed color and the source dielectric factor.")
	verify(material.normal_enabled and material.ao_enabled and material.normal_scale == 1.0
		and material.roughness_texture == material.metallic_texture and material.roughness_texture == material.ao_texture
		and material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		and material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		and material.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED,
		"The real material binds the linear scalar channels and OpenGL tangent normal.")
	verify(material.uv1_world_triplanar and material.uv1_triplanar
		and material.uv1_scale.is_equal_approx(Vector3.ONE / 1.5), "World-space projection retains the source's one-and-a-half-metre repeat.")
	verify(material.albedo_texture.get_image().get_size() == Vector2i(1024, 1024)
		and material.normal_texture.get_image().get_size() == Vector2i(512, 512)
		and material.roughness_texture.get_image().get_size() == Vector2i(256, 256)
		and material.albedo_texture.get_image().has_mipmaps() and material.normal_texture.get_image().has_mipmaps()
		and material.roughness_texture.get_image().has_mipmaps(), "Prepared extents and mip chains reach all actual stone textures.")
	var rocks := Scenery._rock_outcrops()
	verify(rocks.material_override == material and rocks.multimesh.mesh == Scenery.rock_boulder_mesh,
		"The existing rock draw consumer uses the sourced material and original mesh.")
	check_rock_shapes(rocks.multimesh)
	for index in range(64):
		for channel in range(3):
			verify(rocks.multimesh.buffer[index * 16 + 12 + channel] >= 0.8,
				"The photo is not multiplied by the former dark generated-rock tint.")
	var steel := Opening.ProductionSteelFloor.read_images()
	var ground := Opening.ProductionSteelFloor.read_images(Scenery.GROUND_ROOT, Scenery.GROUND_FILES, Vector2i(512, 512))
	verify(steel.status == "ready" and ground.status == "ready",
		"The extended scalar-extent argument preserves existing steel and ground decoder defaults.")
	verify(Scenery.ground_material() != material and Opening.ProductionSteelFloor.material() != material,
		"Surface roles keep separate material caches.")
	var missing := Opening.ProductionSteelFloor.read_images(fixture_directory.path_join("missing-stone"), Scenery.STONE_FILES, Vector2i(512, 512), Vector2i(256, 256))
	verify(missing.status == "missing", "Historical absent stone maps retain an explicit status.")
	var partial_path := fixture_directory.path_join("partial-stone")
	if verify(DirAccess.make_dir_absolute(partial_path) == OK, "The negative input directory is fresh and owned."):
		var file := FileAccess.open(partial_path.path_join(Scenery.STONE_FILES.albedo), FileAccess.WRITE)
		file.store_buffer(FileAccess.get_file_as_bytes(Scenery.STONE_ROOT.path_join(Scenery.STONE_FILES.albedo)))
		file.close()
		var partial := Opening.ProductionSteelFloor.read_images(partial_path, Scenery.STONE_FILES, Vector2i(512, 512), Vector2i(256, 256))
		verify(partial.status == "invalid" and partial.reason == "incomplete_material_set", "A partial stone package is never accepted as ready.")
	var wrong_extent := Opening.ProductionSteelFloor.read_images(Scenery.STONE_ROOT, Scenery.STONE_FILES, Vector2i(512, 512))
	verify(wrong_extent.status == "invalid" and wrong_extent.reason == "invalid_arm",
		"Scalar-map extents are validated, rather than treating a decode alone as a complete material.")
	var view := FixtureView.new()
	root.add_child(view)
	view._build_world()
	verify(view.model == null and view.actor_world == null and view.state.is_empty(),
		"Ordinary natural-scenery assembly starts no authority or gameplay clock.")
	var users := count_material_users(view, material)
	verify(users >= 5, "Actual natural geological pieces consume the shared source material.")
	verify(view.get_node("ProductionScenery/RockOutcrops").material_override == material,
		"The ordinary rock group binds the same shared photo surface.")
	print(JSON.stringify({"ordinary_material_users": users, "rock_instances": 64,
		"geometry": "Existing natural-geology meshes, support descriptors and actor authority unchanged.",
		"limits": "Source/material and draw-consumer evidence; no new physical traversal, rendered quality or GPU claim."}))
	view.free()
	rocks.free()

func check_fir_resource() -> void:
	var loaded: Dictionary = Scenery.Surface.read_fir()
	if not verify(loaded.status == "ready", "The actual shared fixture interface loads the qualified fir resource."):
		return
	var mesh: ArrayMesh = loaded.mesh
	var imported := ImporterMesh.from_mesh(mesh)
	var descriptor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_directory.path_join("source/fir_sapling_medium_1k.gltf")))
	var full_triangles := 0
	var wood_triangles := 0
	var levels: Array = []
	for surface in range(3):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		verify(vertices.size() == [2157, 476454, 1211][surface] and indices.size() == [11130, 1245906, 5430][surface],
			"The local source model retains all original surfaces and base triangles.")
		full_triangles += indices.size() / 3
		if surface != 1:
			wood_triangles += indices.size() / 3
		var source_accessor: Dictionary = descriptor.accessors[descriptor.meshes[1].primitives[surface].attributes.POSITION]
		var source_bounds := AABB(Vector3(source_accessor.min[0], source_accessor.min[1], source_accessor.min[2]), Vector3.ZERO)
		source_bounds.end = Vector3(source_accessor.max[0], source_accessor.max[1], source_accessor.max[2])
		for vertex in vertices:
			if not source_bounds.grow(0.0005).has_point(vertex):
				verify(false, "The resource remains in its original local source bounds.")
				return
		verify(imported.get_surface_lod_count(surface) >= 2, "Each actual runtime surface retains generated distance detail.")
		var counts: Array = []
		for level in range(imported.get_surface_lod_count(surface)):
			counts.append(imported.get_surface_lod_indices(surface, level).size() / 3)
		levels.append(counts)
		var finish := mesh.surface_get_material(surface) as StandardMaterial3D
		verify(finish != null and finish.metallic == 0 and not finish.ao_enabled,
			"The descriptor's dielectric and absence of an occlusion binding stay explicit.")
		if finish == null:
			return
		var source: Dictionary = descriptor.materials[surface]
		var extensions: Dictionary = source.get("extensions", {})
		var ior: float = extensions.get("KHR_materials_ior", {}).get("ior", 1.5)
		var factor: float = extensions.get("KHR_materials_specular", {}).get("specularFactor", 1.0)
		var f0 := pow((ior - 1) / (ior + 1), 2) * factor
		verify(absf(0.16 * pow(finish.metallic_specular, 2) - f0) < 0.00000001,
			"Actual prepared normal-incidence reflectance follows each source material, including the dead wood default.")
		var expected_scale := Vector3(1.2, 0.1, 1) if surface == 0 else (Vector3(0.8, 0.8, 1) if surface == 2 else Vector3.ONE)
		var expected_offset := Vector3(0, 0.9, 0) if surface == 0 else (Vector3(0, 0.2, 0) if surface == 2 else Vector3.ZERO)
		verify(finish.uv1_scale.is_equal_approx(expected_scale) and finish.uv1_offset.is_equal_approx(expected_offset),
			"The original per-material texture transforms survive resource packaging.")
		for field in ["albedo_texture", "normal_texture", "roughness_texture"]:
			var image: Image = finish.get(field).get_image()
			verify(image.has_mipmaps() and image.get_size() == (Vector2i(384, 384) if field == "albedo_texture" else Vector2i(256, 256)),
				"The delivered resource carries its prepared mipmapped color and data images.")
	verify(Scenery.Surface.read_fir().mesh == mesh, "Repeated reads reuse the same immutable resource.")
	verify(Scenery.Surface.read_fir(fixture_directory.path_join("absent-fir.res")).status == "missing", "An older roster can omit this optional resource.")
	var bad_path := fixture_directory.path_join("wrong-fir.res")
	var file := FileAccess.open(bad_path, FileAccess.WRITE)
	file.store_string("Untrusted resource bytes must never be deserialized.")
	file.close()
	verify(Scenery.Surface.read_fir(bad_path).status == "invalid", "Changed bytes are refused before native deserialization.")
	verify(full_triangles == 420822 and wood_triangles == 5520, "The full canopy and the separate woody source surfaces remain available for the later matched fixture.")
	print(JSON.stringify({"base_triangles": full_triangles, "woody_triangles": wood_triangles, "lod_triangle_counts": levels,
		"mounted_trees": 0, "physics": "not_started", "rendered_quality": "not_assessed"}))

func check_bank_firs() -> void:
	# Exercise the actual absent-file branch before any fir layout cache is
	# built. Only this private captured project's optional asset is moved.
	if not OS.get_cmdline_user_args().has("--fir-layout-only"):
		var original := ProjectSettings.globalize_path(Scenery.Surface.FIR_FILE)
		var retained := fixture_directory.path_join("optional-fir-control.res")
		if not verify(DirAccess.rename_absolute(original, retained) == OK, "The optional resource can be retained outside the private case project."):
			return
		var absent := Scenery._bank_firs()
		verify(absent.get_child_count() == 0 and Scenery.Surface.fir_collision_faces().is_empty(),
			"An absent source creates neither visible trees nor hidden woody collision.")
		absent.free()
		if not verify(DirAccess.rename_absolute(retained, original) == OK, "Restore the exact captured asset before the positive consumer."):
			return
		Scenery.Surface._fir_initialized = false
	var specs: Array[Dictionary] = Scenery.Surface.fir_specs()
	print(JSON.stringify({"phase": "fir layout", "trees": specs.size(), "counts": Scenery.Surface._fir_layout_counts, "poses": specs}))
	if not verify(specs.size() == 3, "The source-qualified site composes exactly three bank trees."):
		return
	var actual_faces: PackedVector3Array = Scenery.Surface.fir_collision_faces()
	verify(actual_faces.size() > 45000 and actual_faces.size() % 3 == 0,
		"The physical fixture retains actual woody triangles rather than a hidden box or foliage shell.")
	for shared_profile in [false, true]:
		var view: Variant = SharedBankView.new() if shared_profile else FixtureView.new()
		root.add_child(view)
		view._build_world()
		var group: Node3D = view.get_node("ProductionScenery/BankFirs")
		verify(group.get_child_count() == specs.size(), "Both ordinary scene builders mount the same complete bank group.")
		var expected := PackedVector3Array()
		for index in range(specs.size()):
			var tree := group.get_child(index) as MeshInstance3D
			var spec: Dictionary = specs[index]
			verify(tree != null and tree.mesh == Scenery.Surface.fir_mesh() and str(tree.name) == spec.id,
				"The actual node shares the qualified resource and deterministic fixture identity.")
			if tree == null:
				continue
			verify(tree.position == spec.center and tree.basis == spec.basis.scaled_local(Vector3.ONE * spec.scale)
				and tree.basis.y.normalized().is_equal_approx(Vector3.UP), "Both scene and physical descriptors use the same gravity-upright pose.")
			verify(absf(tree.position.y - Scenery.Surface.height_at(tree.position.x, tree.position.z) + 0.02) < 0.000001,
				"Tree roots are embedded at the actual terrain triangles, not a smooth-height approximation.")
			var envelope: AABB = tree.transform * tree.mesh.get_aabb()
			var nearest := Vector2(clampf(1.65, envelope.position.x, envelope.end.x), clampf(1.65, envelope.position.z, envelope.end.z))
			verify(nearest.distance_to(Vector2(1.65, 1.65)) > 8 and tree.visibility_range_end == 65.0,
				"Whole canopies keep the working ring clear and retain a finite visibility range.")
			for row in range(65):
				var z := lerpf(envelope.position.z, envelope.end.z, float(row) / 64)
				verify(envelope.end.x < Scenery.river_center_x(z) - Scenery.channel_half_width(z) - 0.4,
					"The actual complete canopy stays on the opposite bank, clear of the channel.")
			for surface in [0, 2]:
				var arrays := tree.mesh.surface_get_arrays(surface)
				var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for n in range(0, indices.size(), 3):
					var a := tree.transform * positions[indices[n]]
					var b := tree.transform * positions[indices[n + 1]]
					var c := tree.transform * positions[indices[n + 2]]
					if (b - a).cross(c - a).length_squared() > 0:
						expected.append_array(PackedVector3Array([a, b, c]))
			inspect_visual(tree)
		verify(expected == actual_faces, "Every actual rendered woody triangle exactly matches the physical fixture input; needles are excluded.")
		verify(view.model == null and view.actor_world == null and view.state.is_empty() and view.request_sequence == 0,
			"Ordinary scene assembly creates no authority, physical actor or material command.")
		view.free()
	var first_root: Vector3 = specs[0].center
	specs[0].center = Vector3(999, 999, 999)
	actual_faces[0] = Vector3(999, 999, 999)
	verify(Scenery.Surface.fir_specs()[0].center == first_root and Scenery.Surface.fir_collision_faces()[0].x < 100,
		"Callers cannot mutate later shared tree poses or native triangle input.")
	print(JSON.stringify({"trees": 3, "actual_wood_triangles": Scenery.Surface.fir_collision_faces().size() / 3,
		"rendered_quality": "not_assessed", "physics": "separate_case", "authority": "not_started"}))

func check_bank_fir_lifecycle() -> void:
	for shared_profile in [false, true]:
		var view: Variant = SharedBankView.new() if shared_profile else FixtureView.new()
		root.add_child(view)
		view._build_world()
		var group: Node3D = view.get_node("ProductionScenery/BankFirs")
		verify(group.is_inside_tree() and group.get_child_count() == 3, "The ordinary fir group is mounted inside the real node tree.")
		verify(view.camera.is_inside_tree() and view.camera.global_transform.is_finite(), "The normal camera mount is valid during world assembly.")
		verify(view.model == null and view.actor_world == null and view.request_sequence == 0, "The mounted fixture still starts no game authority or requests.")
		view.free()

func run() -> void:
	if mode == "construction-vegetation":
		check_construction_vegetation()
		finish()
		return
	if mode == "bank-fir-lifecycle":
		check_bank_fir_lifecycle()
		finish()
		return
	if mode == "bank-firs":
		check_bank_firs()
		finish()
		return
	if mode == "fir-resource":
		check_fir_resource()
		finish()
		return
	if mode == "pine-reflectance":
		check_pine_reflectance()
		finish()
		return
	if mode == "pine-roots":
		check_pine_roots()
		finish()
		return
	if mode == "pine-understory":
		check_pine_understory()
		finish()
		return
	if mode == "stone-material":
		check_stone_material()
		finish()
		return
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
	if mode == "ground-render":
		await check_ground_render()
		finish()
		return
	if mode == "water-flow":
		check_water_flow()
		finish()
		return
	if mode == "bank-ferns":
		check_bank_ferns()
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
	if mode == "foreground-bank":
		check_foreground_bank()
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
	verify(Scenery.Surface.pad_panels().is_empty() and Scenery.Surface.foundation_boxes().is_empty()
		and Scenery.Surface.architecture_boxes().is_empty(),
		"An unbuilt worksite contains terrain and rocks, never manufactured support geometry.")
	verify(scenery.get_node("MillraceArchitecture").find_children("*", "MeshInstance3D", true, false).is_empty(),
		"No renamed piers, bank rungs or straight channel walls remain visible.")
	for forbidden in ["FoundationPanel", "BedrockTerracePanel", "EastBedrockShelf", "WestBankBedrockShelf",
		"SeamVeinBed", "SeamHostRockLip", "SeamOreOutcrop", "StreamBankLedge"]:
		verify(view.find_child(forbidden, true, false) == null,
			"The actual builder removes the old engineered silhouette: " + forbidden)
	verify(ground.material_override == Scenery.ground_material()
		and stream.material_override == Scenery.water_material(),
		"Repeated world views share the authored material resources.")
	var soil: ShaderMaterial = ground.material_override
	verify(Scenery.ground_source_status == "ready" and soil.shader == Scenery.GROUND_SHADER
		and soil.get_shader_parameter("albedo_map") is ImageTexture and soil.get_shader_parameter("normal_map") is ImageTexture,
		"The terrain uses the qualified cached stochastic ground surface without a generated fallback.")
	var water: StandardMaterial3D = stream.material_override
	var ripples: Image = water.normal_texture.get_image()
	verify(ripples.get_width() == 128 and ripples.get_height() == 128 and ripples.has_mipmaps()
		and water.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and water.detail_enabled,
		"Water uses the explicit translucent layered-ripple finish.")
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
