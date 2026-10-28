extends SceneTree
const ProductionVisuals = preload("res://opening/production_surfaces.gd").ProductionVisuals
const ProductionSteelFloor = preload("res://opening/production_surfaces.gd").ProductionSteelFloor
## Isolated visual resources and 3D world assembly. No gameplay or desktop input.
const Opening = preload("res://opening/opening.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const NativeModel = preload("res://opening/native_model.gd")
const Scenery = preload("res://opening/production_environment.gd").ProductionEnvironment
var checks := 0
var failed := false
var error_count := 0
var mode := "environment"
var fixture_directory := ""
var fir_layout_only := false
const TANGENT_EPSILON := 0.0005
const CASES := ["environment", "botanical-species", "collector-carrier",
	"foundation-depth-vegetation", "construction-vegetation", "bank-fir-lifecycle",
	"bank-firs", "fir-resource", "pine-reflectance", "pine-roots", "pine-understory",
	"stone-material", "sourced-sky", "meadow-patches", "foliage-mipmaps",
	"sourced-foliage", "ground-material", "ground-render", "site-render", "ore-field-render",
	"water-flow", "water-pattern", "water-render", "bank-ferns",
	"rock-collision-shape", "surface-composition", "foreground-bank", "foliage"]
const ARTIFACT_CASES := ["bank-firs", "fir-resource", "pine-reflectance",
	"pine-understory", "stone-material", "sourced-sky", "sourced-foliage",
	"ground-material", "ground-render", "site-render", "ore-field-render", "water-render", "bank-ferns"]
const RENDER_CASES := ["ground-render", "site-render", "ore-field-render", "water-render"]

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

func carrier_part_fits(part: MeshInstance3D, envelope: AABB) -> bool:
	if part.mesh == null:
		return false
	for surface in range(part.mesh.get_surface_count()):
		var vertices: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			return false
		for vertex in vertices:
			if not envelope.has_point(part.global_transform * vertex):
				return false
	return true

func check_collector_carrier() -> void:
	var native := NativeModel.new("collector-carrier-geometry-check")
	if not verify(native.boot_result.get("accepted", false),
		"The native and scene carrier profiles agree before visual geometry is checked."):
		return
	for cell in [0, 1]:
		for level in [4, 8]:
			var view := FixtureView.new()
			view.state = {"options": {"native": true}}
			root.add_child(view)
			var anchor := Node3D.new()
			anchor.position = Vector3(0, float(level) * Geometry.HEIGHT_STEP,
				float(cell) * Geometry.PITCH)
			view.add_child(anchor)
			var entity := {"kind": "collector", "cell": [0, cell],
				"level": level, "axis": 0, "rotation": 0, "generation": 1}
			var intake: Dictionary = Geometry.collector_intake_boxes(entity)
			if not verify(intake.get("accepted", false) and intake.boxes.size() == 9,
				"Both raised source cells expose the complete occupied carrier."):
				view.free()
				return
			view._collector_visual(anchor, entity)
			for index in range(5):
				var flight: Dictionary = intake.boxes[index + 3]
				var occupied := AABB(flight.center - flight.size * 0.5,
					flight.size).grow(0.0001)
				var step := anchor.get_node_or_null("SourceLiftFlight%d" % index) as MeshInstance3D
				if not verify(step != null and step.get_child_count() == 3,
					"Every occupied flight has one pan and two formed side cheeks."):
					view.free()
					return
				verify(carrier_part_fits(step, occupied),
					"The visible carrier floor stays inside its native flight body.")
				for child in step.get_children():
					verify(child is MeshInstance3D and carrier_part_fits(child, occupied),
						"The bucket back and both cheeks stay inside the occupied flight body.")
				var bucket := step.get_node("SourceLiftBucket") as MeshInstance3D
				bucket.position.y += 0.03
				verify(not carrier_part_fits(bucket, occupied),
					"A raised bucket outside the native body is rejected by the same vertex check.")
			view.free()

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
	var seen := {}
	for argument: String in OS.get_cmdline_user_args():
		var option := ""
		var value := ""
		if argument.begins_with("--environment-case="):
			option = "--environment-case="
			value = argument.trim_prefix(option)
		elif argument.begins_with("--artifacts="):
			option = "--artifacts="
			value = argument.trim_prefix(option)
		elif argument.begins_with("--test-purpose="):
			option = "--test-purpose="
			value = argument.trim_prefix(option)
		elif argument == "--fir-layout-only":
			option = argument
		if option.is_empty() or seen.has(option) or (option.ends_with("=") and value.is_empty()):
			push_error("Unknown, repeated or empty environment fixture argument: " + argument)
			quit(2)
			return
		seen[option] = true
		match option:
			"--environment-case=": mode = value
			"--artifacts=": fixture_directory = value
			"--fir-layout-only": fir_layout_only = true
	if not CASES.has(mode):
		push_error("Choose a supported production environment fixture case.")
		quit(2)
		return
	if fir_layout_only and mode != "bank-firs":
		push_error("The fir layout control belongs only to the bank-firs case.")
		quit(2)
		return
	var needs_artifacts := ARTIFACT_CASES.has(mode) and not (mode == "bank-firs" and fir_layout_only)
	if seen.has("--artifacts=") != needs_artifacts:
		push_error("The selected environment case requires exactly its declared artifact directory.")
		quit(2)
		return
	if needs_artifacts and (not fixture_directory.is_absolute_path()
			or not DirAccess.dir_exists_absolute(fixture_directory)):
		push_error("Environment fixture artifacts need an existing absolute directory.")
		quit(2)
		return
	if RENDER_CASES.has(mode) and DisplayServer.get_name().to_lower() == "headless":
		push_error("The selected environment render case needs an actual renderer.")
		quit(2)
		return
	if not Opening.apply_test_window_title(self):
		return
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
			"collector-carrier": "formed lift flight vertices against the matching native occupied profile",
			"sourced-foliage": "runtime tuft import, cutout material and existing terrain placement",
			"foliage-mipmaps": "corrected runtime texture mipmap generation and binding",
			"meadow-patches": "changed terrain-aware grass patch placement and culling envelopes",
			"sourced-sky": "original HDR radiance, cached sky and ordinary key-light binding",
			"stone-material": "sourced natural-stone material, cache and unchanged shape consumer",
			"bank-ferns": "sourced low-fern import, whole-clump terrain placement and ordinary scene consumer",
			"foreground-bank": "near-bank placement and confirmed offline/shared machine-footprint suppression",
			"pine-understory": "complete pine resource, terrain and confirmed-machine visibility consumer",
			"botanical-species": "distinct broadleaf trunk contact and soft sourced shrub variants in both opening builders",
			"construction-vegetation": "detached offline/shared plant clearance at confirmed construction heights",
			"foundation-depth-vegetation": "actual clump clearance below and inside a short foundation",
			"pine-roots": "focused edge-inclusive terrain-root oracle correction",
			"pine-reflectance": "source-derived normal-incidence dielectric reflectance and cache isolation",
			"fir-resource": "complete sourced fir, generated distance detail and common resource interface",
			"bank-firs": "ordinary fir mounting, deterministic terrain poses and matching woody triangles",
			"bank-fir-lifecycle": "ordinary scene mounting inside the actual node tree",
			"ground-material": "qualified grass material, data channels and cache separation",
			"ground-render": "source-period and frame-stability observations on separate passive planes",
			"site-render": "passive worksite, default-orbit and bank-side terrain views",
			"water-flow": "layered translucent river resources and ordinary frame consumer",
			"water-pattern": "straight-band normal energy and actual water-surface geometry",
			"water-render": "isolated actual terrain and water with a fixed camera and presentation phases",
			"rock-collision-shape": "visible rock facets versus the shared convex collision hull",
			"foliage": "changed foliage bulk upload",
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
	var expected_visible := 0
	for spec in shared.support_boxes():
		# Loose rocks and the mineable source render through separate object paths.
		if spec.id.begins_with("rock_") or spec.id == "source_outcrop":
			continue
		expected_visible += 1
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
	verify(rendered.size() == expected_visible, "The shared descriptor set has no invisible architecture boxes.")
	var rocks: MultiMesh = scenery.get_node("RockOutcrops").multimesh
	check_rock_shapes(rocks)
	verify(shared.pad_panels().is_empty() and shared.foundation_boxes().is_empty()
		and shared.architecture_boxes().is_empty(), "No old platform or canal survives in the physical site catalogue.")
	var stream: MeshInstance3D = scenery.get_node("StreamSurface")
	var water: PackedVector3Array = stream.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var covered := 0
	var checked_vertices := 0
	var minimum_gap := INF
	var interior_gap := INF
	var minimum_triangle_gap := INF
	for first in range(0, water.size(), 3):
		var column := floori(float(first) / 6.0) % 6
		var centroid: Vector3 = (water[first] + water[first + 1] + water[first + 2]) / 3.0 + stream.global_position
		minimum_triangle_gap = minf(minimum_triangle_gap,
			centroid.y - shared.height_at(centroid.x, centroid.z))
		for offset in range(3):
			var point: Vector3 = water[first + offset] + stream.global_position
			checked_vertices += 1
			var gap: float = point.y - shared.height_at(point.x, point.z)
			minimum_gap = minf(minimum_gap, gap)
			if point.z >= -4.0 and point.z <= 7.0:
				covered += 1
				if column >= 1 and column <= 4:
					interior_gap = minf(interior_gap, gap)
	verify(covered > 0 and minimum_gap >= 0.0 and interior_gap > 0.05 and minimum_triangle_gap >= 0.0,
		"The emitted river meets its banks while clearing the natural bed in the wet interior.")
	print(JSON.stringify({"relation": "natural_bed_below_water", "minimum_gap": minimum_gap,
		"interior_gap": interior_gap, "minimum_triangle_gap": minimum_triangle_gap,
		"sampled_vertices": checked_vertices, "working_reach_vertices": covered,
		"visible_boxes": rendered.size(), "rock_instances": 64}))
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

func _plant_records_match(patch: MultiMeshInstance3D, expected: PackedFloat32Array) -> bool:
	var stride := 16 if patch.multimesh.use_colors else 12
	return patch.multimesh.instance_count * stride == expected.size() \
		and patch.multimesh.buffer.slice(0, expected.size()) == expected

func check_foundation_depth_vegetation() -> void:
	var scenery := Node3D.new()
	root.add_child(scenery)
	var preparation := Scenery._foliage()
	preparation.free()
	var patch := Scenery._foreground_bank()
	scenery.add_child(patch)
	if not verify(patch.multimesh != null and patch.multimesh.instance_count > 0 and patch.has_meta("candidate_buffer"),
		"The depth fixture has an actual prepared foreground population."):
		scenery.free()
		return
	var original: PackedFloat32Array = patch.get_meta("candidate_buffer")
	var source_clump := original.slice(0, 16)
	var clump := _plant_bounds(patch, original, 0)
	var cell := Vector2i(roundi(original[3] / Geometry.PITCH), roundi(original[11] / Geometry.PITCH))
	var level := ceili((clump.end.y + 0.08 + Geometry.FOUNDATION_DEPTH) / Geometry.HEIGHT_STEP)
	var top := Vector3(cell.x * Geometry.PITCH, level * Geometry.HEIGHT_STEP, cell.y * Geometry.PITCH)
	var actual := AABB(top - Vector3(Geometry.PITCH * 0.5, Geometry.FOUNDATION_DEPTH, Geometry.PITCH * 0.5),
		Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH)).grow(0.08)
	var obsolete := AABB(top - Vector3(Geometry.PITCH * 0.5, Geometry.PITCH, Geometry.PITCH * 0.5), Vector3.ONE * Geometry.PITCH).grow(0.08)
	if not verify(not clump.intersects(actual) and clump.intersects(obsolete),
		"The actual clump is below the short slab but inside the obsolete full-height volume."):
		scenery.free()
		return
	var state := {"entities": {}, "foundations": {"slab": {"cell": [cell.x, cell.y], "level": level}}}
	Scenery.refresh_vegetation(scenery, state)
	var retained := false
	for offset in range(0, patch.multimesh.buffer.size(), 16):
		retained = retained or patch.multimesh.buffer.slice(offset, offset + 16) == source_clump
	print(JSON.stringify({"case": "plant_below_short_slab", "level": level, "depth": Geometry.FOUNDATION_DEPTH,
		"clump_top": clump.end.y, "slab_base": actual.position.y, "source_clump_retained": retained}))
	verify(retained, "A raised half-height foundation keeps the actual clear plant beneath it.")
	state.foundations.slab.level = floori((clump.get_center().y + Geometry.FOUNDATION_DEPTH * 0.5) / Geometry.HEIGHT_STEP)
	Scenery.refresh_vegetation(scenery, state)
	var removed := true
	for offset in range(0, patch.multimesh.buffer.size(), 16):
		removed = removed and patch.multimesh.buffer.slice(offset, offset + 16) != source_clump
	verify(removed, "A lowered slab still suppresses a genuinely intersecting clump.")
	Scenery.refresh_vegetation(scenery, {"entities": {}, "foundations": {}})
	verify(patch.multimesh.buffer == original, "Removal restores the complete original plant records.")
	scenery.free()

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
				"volumes": [AABB(Vector3(top.x - Geometry.PITCH * 0.5, 1000 * Geometry.HEIGHT_STEP - Geometry.FOUNDATION_DEPTH, top.z - Geometry.PITCH * 0.5), Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH))]},
			{"name": "buried_foundation", "entities": {}, "foundations": {"low": {"cell": [cell.x, cell.y], "level": -1000}},
				"volumes": [AABB(Vector3(top.x - Geometry.PITCH * 0.5, -1000 * Geometry.HEIGHT_STEP - Geometry.FOUNDATION_DEPTH, top.z - Geometry.PITCH * 0.5), Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH))]}]
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
				patch_level * Geometry.HEIGHT_STEP - Geometry.FOUNDATION_DEPTH, patch_cell.y * Geometry.PITCH - Geometry.PITCH * 0.5), Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH)))
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
				verify(_plant_records_match(patch, expected),
					"Actual active plant counts and records match independent world-space clearance: " + scenario.name + "/" + str(patch.name))
				verify(patch.multimesh.mesh == snapshot.mesh and patch.material_override == snapshot.material
					and patch.multimesh.custom_aabb == snapshot.aabb,
					"Filtering preserves sourced resources and the conservative original visibility bounds.")
				if scenario.name == "all_patch_kinds":
					verify(expected.size() < snapshot.buffer.size(), "Every plant population participates in construction clearance.")
			view._rebuild_machines()
			verify(view.state == supplied and view.model == null and view.actor_world == null and view.request_sequence == 0,
				"Repeated offline/shared presentation leaves confirmed facts intact and creates no authority or requests.")
			for snapshot in snapshots:
				verify(_plant_records_match(snapshot.patch, _expected_plants(snapshot.patch, snapshot.buffer, volumes)),
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
			moved_level * Geometry.HEIGHT_STEP - Geometry.FOUNDATION_DEPTH, moved_cell.y * Geometry.PITCH - Geometry.PITCH * 0.5), Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH))
		view.state = {"entities": {}, "foundations": {"moved": {"cell": [moved_cell.x, moved_cell.y], "level": moved_level}}, "links": []}
		view._rebuild_machines()
		var moved_expected := _expected_plants(moved, moved_data, [moved_volume])
		verify(moved_expected.size() < moved_data.size() and _plant_records_match(moved, moved_expected),
			"Translated local meadow records are cleared at their world-space height and position.")
		moved.position = old_position
		view.state = {"entities": {}, "foundations": {}, "links": []}
		view._rebuild_machines()
		for snapshot in snapshots:
			verify(_plant_records_match(snapshot.patch, snapshot.buffer), "Removing construction restores every original candidate count and byte.")
		if DisplayServer.get_name().to_lower() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
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
			verify(absf(point.x - Scenery.river_center_x(point.z)) > Scenery.channel_half_width(point.z) + 0.55
				and instances.custom_aabb.grow(0.0001).has_point(point),
				"The whole transformed clump clears the channel and lies inside its actual culling bounds.")
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

func check_water_pattern() -> void:
	var water := Scenery.water_material()
	var ratios: Array[float] = []
	for texture: Texture2D in [water.normal_texture, water.detail_normal]:
		var image := texture.get_image()
		var energy := 0.0
		var bands := 0.0
		var mean := 0.0
		var rows: Array[float] = []
		for y in range(image.get_height()):
			var row := 0.0
			for x in range(image.get_width()):
				var sample := image.get_pixel(x, y).g - 0.5
				row += sample
				energy += sample * sample
			row /= image.get_width()
			rows.append(row)
			mean += row
		mean /= image.get_height()
		energy = energy / (image.get_width() * image.get_height()) - mean * mean
		for row: float in rows:
			bands += (row - mean) * (row - mean)
		var ratio := bands / image.get_height() / maxf(energy, 0.0000001)
		ratios.append(ratio)
		verify(energy > 0.00002 and ratio < 0.25,
			"Water normals contain real detail without a dominant straight cross-channel band.")
	var maximum_error := 0.0
	for point: Vector3 in Scenery.stream_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		maximum_error = maxf(maximum_error, absf(point.y - Scenery.Surface.stream_surface_height(point.x - 2.7, point.z + 1.65)))
	verify(maximum_error < 0.00001, "Visible water ends at its actual surface rather than an extruded decorative side wall.")
	var arrays := Scenery.stream_mesh().surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var brightness_rows := {}
	for index in range(points.size()):
		if colors[index].a < 0.99:
			continue
		var key := roundi(points[index].z * 1000.0)
		var row: Vector2i = brightness_rows.get(key, Vector2i.ZERO)
		row.x += int(colors[index].get_luminance() > 0.45)
		row.y += 1
		brightness_rows[key] = row
	var widest_bright_band := 0.0
	for row: Vector2i in brightness_rows.values():
		widest_bright_band = maxf(widest_bright_band, float(row.x) / row.y)
	verify(widest_bright_band < 0.75,
		"The actual water albedo has no painted bright stripe spanning nearly the whole channel.")
	var geometry_hash := HashingContext.new()
	geometry_hash.start(HashingContext.HASH_SHA256)
	for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		geometry_hash.update(var_to_bytes(arrays[attribute]))
	print(JSON.stringify({"case": "water-pattern", "straight_band_energy": ratios, "maximum_surface_error": maximum_error,
		"widest_painted_bright_fraction": widest_bright_band, "geometry_sha256": geometry_hash.finish().hex_encode(),
		"authority": "not_started", "rendered_quality": "separate_observation"}))

func check_water_render() -> void:
	print("WATER_RENDER_SETUP")
	if not verify(DisplayServer.get_name().to_lower() != "headless" and fixture_directory.is_absolute_path(),
		"Water rendering requires an owned renderer and absolute artifact directory."):
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 768)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_SKY
	environment.environment.sky = Sky.new()
	environment.environment.sky.sky_material = Scenery.panorama_material()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.environment.ambient_light_energy = 0.62
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -28, 0)
	sun.light_energy = 1.7
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	ground.mesh = Scenery.terrain_mesh()
	ground.material_override = Scenery.ground_material()
	world.add_child(ground)
	var stream := MeshInstance3D.new()
	stream.mesh = Scenery.stream_mesh()
	stream.material_override = Scenery.water_material()
	stream.position = Vector3(-2.7, 0, 1.65)
	world.add_child(stream)
	var camera := Camera3D.new()
	camera.position = Vector3(14, 13, 22)
	world.add_child(camera)
	camera.look_at(Vector3(-2.7, -0.2, 5))
	camera.current = true
	print("WATER_RENDER_GEOMETRY_READY")
	var images: Array[Image] = []
	for phase in [0.0, 0.65, 0.0]:
		Scenery.animate_water(phase)
		await process_frame
		await RenderingServer.frame_post_draw
		images.append(viewport.get_texture().get_image())
		print("WATER_RENDER_PHASE ", phase)
	for index in range(2):
		var path := fixture_directory.path_join("water-%d.png" % index)
		verify(not FileAccess.file_exists(path) and images[index].save_png(path) == OK,
			"Retain each original own-viewport water observation.")
	var moving := image_difference(images[0], images[1])
	var stable := image_difference(images[0], images[2])
	verify(moving > 0.00001, "The real water material produces visible downstream surface motion.")
	verify(stable < 0.00001, "Returning to the same phase restores the same surface image.")
	print(JSON.stringify({"case": "water-render", "phase_change": moving, "same_phase_error": stable,
		"camera": [14,13,22], "target": [-2.7,-0.2,5], "phases": [0,0.65,0],
		"geometry": "actual terrain and stream", "authority": "not_started", "desktop": "not_used"}))
	viewport.queue_free()
	await process_frame

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
		verify(original.get_format() == Image.FORMAT_RGB8 and original.get_size() == Vector2i(256, 256),
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
	var river_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var visual_speeds := {}
	for z in [1.65, 22.0, 38.0]:
		var row: int = clampi(floori((z + 58.0) / 119.0 * 238.0), 0, 237)
		var density: float = (river_uvs[(row + 1) * 36 + 6].y - river_uvs[row * 36 + 6].y) / 0.5
		var speed: float = -(water.uv1_offset.y - before.y) / (density * water.uv1_scale.y)
		visual_speeds[z] = speed
		verify(absf(speed - Scenery.Surface.display_flow_speed(z)) < 0.05,
			"The normal-layer motion follows the current estimate at each actual riverbed section.")
	verify(visual_speeds[22.0] < visual_speeds[38.0] and visual_speeds[38.0] < visual_speeds[1.65],
		"The visible current slows through the broad pool and accelerates through the constriction.")
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
	verify(ground == Scenery.ground_material() and ProductionSteelFloor.source_status == "uninitialized",
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
	verify(ground.shader == Scenery.GROUND_SHADER and is_equal_approx(ground.get_shader_parameter("source_extent"), 1.4),
		"The cached stochastic surface binds the qualified 1.4-metre source scale and stationary world-space shader.")
	var stone := Scenery.stone_material()
	verify(Scenery.stone_source_status == "ready"
		and ground.get_shader_parameter("stone_albedo_map") == stone.albedo_texture
		and ground.get_shader_parameter("stone_normal_map") == stone.normal_texture
		and ground.get_shader_parameter("stone_arm_map") == stone.roughness_texture
		and is_equal_approx(ground.get_shader_parameter("stone_extent"), 1.5),
		"Steep banks reuse the qualified rock color, normal and linear scalar maps at their declared physical scale.")
	verify(stone.albedo_texture.get_image().has_mipmaps()
		and stone.normal_texture.get_image().has_mipmaps()
		and stone.roughness_texture.get_image().has_mipmaps(),
		"Steep-bank sampling retains every qualified rock mip chain.")
	var packed := ProductionVisuals.read_image(Scenery.GROUND_ROOT.path_join(Scenery.GROUND_FILES.arm))
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
	var missing := ProductionSteelFloor.read_images(empty, Scenery.GROUND_FILES, Vector2i(512, 512))
	verify(missing.status == "missing" and missing.images.is_empty(), "An absent bitmap set cannot masquerade as a qualified surface.")
	var albedo_path: String = Scenery.GROUND_ROOT.path_join(Scenery.GROUND_FILES.albedo)
	if not verify(DirAccess.copy_absolute(albedo_path, partial.path_join(Scenery.GROUND_FILES.albedo)) == OK,
		"Retain the real partial-set negative input."):
		return
	var incomplete := ProductionSteelFloor.read_images(partial, Scenery.GROUND_FILES, Vector2i(512, 512))
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
	var invalid := ProductionSteelFloor.read_images(wrong, Scenery.GROUND_FILES, Vector2i(512, 512))
	verify(invalid.status == "invalid" and invalid.reason == "invalid_normal" and invalid.images.is_empty(),
		"A valid image with the wrong normal extent fails the declared material contract.")
	verify(ProductionSteelFloor.read_images().status == "ready",
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
	camera.size = 7.0
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
	reference.uv1_scale = Vector3.ONE / 1.4
	var planes: Array[MeshInstance3D] = []
	for x in [-5.6, 5.6]:
		var plane := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(11.2, 7.0)
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
	# The 22.4-metre view has 64 pixels per 1.4-metre source period.
	var periodic_error := image_difference(repeated, repeated, 64)
	var varied_error := image_difference(varied, varied, 64)
	var frame_error := image_difference(varied, stable)
	# The old 0.8/0.6 rotation realigns both global frames after five source
	# tiles. Compare that beat with a nearby nonperiodic translation.
	var beat_error := image_difference(varied, varied, 320)
	var nonperiodic_error := image_difference(varied, varied, 352)
	verify(periodic_error < 0.003, "The independent repeating reference proves that the source period is resolved by the viewport.")
	# The denser grass scan has lower broad color contrast than the old leaf map.
	verify(varied_error > maxf(0.004, periodic_error * 8.0),
		"The actual shader breaks the source-period repeat across separately positioned terrain meshes.")
	verify(frame_error < 0.00001, "Stationary ground shading is stable across completed rendered frames.")
	verify(beat_error > nonperiodic_error * 0.75,
		"Ground must not regain a strong common repeat after five source tiles.")
	print(JSON.stringify({"phase": "ground-render", "reference_period_error": periodic_error,
		"stochastic_period_error": varied_error, "frame_error": frame_error, "display": DisplayServer.get_name(),
		"five_tile_error": beat_error, "nonperiodic_error": nonperiodic_error,
		"source_extent_metres": 1.4, "source_period_pixels": 64, "viewport": [1024, 320],
		"game_entry": "not_run", "input": "not_used", "human_quality": "not_assessed"}))
	viewport.free()

func check_site_render() -> void:
	if not verify(DisplayServer.get_name().to_lower() != "headless" and fixture_directory.is_absolute_path(),
		"The site image needs a real renderer and an owned artifact directory."):
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := FixtureView.new()
	viewport.add_child(view)
	view._build_world()
	view.camera.position = Vector3(8.0, 11.0, 15.0)
	view.camera.look_at(Vector3(-12.0, 3.0, 0.0))
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var destination := fixture_directory.path_join("site-passive.png")
	verify(image.get_size() == viewport.size and not FileAccess.file_exists(destination)
		and image.save_png(destination) == OK, "Retain the passive terrain and fir view without replacing prior evidence.")
	view._update_camera()
	await process_frame
	await RenderingServer.frame_post_draw
	var orbit_image := viewport.get_texture().get_image()
	var orbit_path := fixture_directory.path_join("site-starting-orbit.png")
	verify(orbit_image.get_size() == viewport.size and not FileAccess.file_exists(orbit_path)
		and orbit_image.save_png(orbit_path) == OK,
		"Retain the opening's default camera orbit over the unchanged passive scenery.")
	view.camera.position = Vector3(-3.0, 3.2, 10.0)
	view.camera.look_at(Vector3(1.0, 0.0, 3.0))
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var bank_image := viewport.get_texture().get_image()
	var bank_path := fixture_directory.path_join("site-bank-side.png")
	verify(bank_image.get_size() == viewport.size and not FileAccess.file_exists(bank_path)
		and bank_image.save_png(bank_path) == OK,
		"Retain a close bank-side view of the steep slope without starting gameplay.")
	view.camera.position = Vector3(5.0, Scenery.Surface.height_at(5.0, 10.0) + 1.6, 10.0)
	view.camera.look_at(Vector3(3.0, Scenery.Surface.height_at(3.0, 0.0) + 0.65, 0.0))
	await process_frame
	await RenderingServer.frame_post_draw
	var eye_image := viewport.get_texture().get_image()
	var eye_path := fixture_directory.path_join("site-worksite-eye.png")
	verify(eye_image.get_size() == viewport.size and not FileAccess.file_exists(eye_path)
		and eye_image.save_png(eye_path) == OK,
		"Retain a fixed eye-height view across the meadow without game input.")
	verify(view.model == null and view.actor_world == null and view.request_sequence == 0,
		"The passive view starts no game authority or player command.")
	print(JSON.stringify({"phase": "site-render", "views": ["west bank from east worksite",
		"opening default orbit", "bank side from river", "fixed eye height across worksite"], "viewport": [1280, 720],
		"input": "not_used", "gameplay": "not_run"}))
	viewport.free()

func check_ore_field_render() -> void:
	if not verify(DisplayServer.get_name().to_lower() != "headless" and fixture_directory.is_absolute_path(),
		"The field image needs a real renderer and an owned artifact directory."):
		return
	var native := NativeModel.new("ore-field-render", ["P"], true, true)
	if not verify(native.boot_result.get("accepted", false),
		"The field image needs the actual terrain-bound native opening projection."):
		return
	var state: Dictionary = native.projection()
	var deposit: Dictionary = state.get("source_deposit", {})
	verify(deposit.get("cells", []).size() == 100 and deposit.get("cell_regions", []).size() == 100,
		"The scene receives all one hundred ore cells and their native region addresses.")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := FixtureView.new()
	viewport.add_child(view)
	view._build_world()
	view.state = state
	view._refresh_ore_field()
	var field := view.get_node_or_null("ProductionScenery/OreField")
	if not verify(field != null, "The projected ore field appears in the ordinary scenery."):
		viewport.free()
		return
	inspect_visual(field)
	verify(field.get_node_or_null("CopperBearingGround") != null and
		field.get_node_or_null("CopperGravel") != null,
		"The rendered field retains both broad ground and surface stone cues.")
	for shot in [
		["ore-field-bank-side.png", Vector3(-3.0, 3.2, 10.0), Vector3(1.0, 0.0, 3.0)],
		["ore-field-aerial.png", Vector3(14.0, 20.0, 12.0), Vector3(5.0, 0.0, -5.5)],
		["ore-field-land-eye.png", Vector3(9.0, 1.7, 3.6), Vector3(5.0, 0.0, -7.0)]]:
		view.camera.position = shot[1]
		view.camera.look_at(shot[2])
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var destination: String = fixture_directory.path_join(shot[0])
		verify(image.get_size() == viewport.size and not FileAccess.file_exists(destination)
			and image.save_png(destination) == OK,
			"Retain each complete worksite view without replacing prior evidence.")
	# Exercise only the presenter with a representative empty local balance.
	# Native debit, conservation and saved stock are checked by ore_field_test.
	var preview: Dictionary = state.duplicate(true)
	var preview_sources: Dictionary = preview.get("hand_sources", {})
	var depleted_id: String = str(deposit.get("id", "")) + "-region-5"
	var depleted_source: Dictionary = preview_sources.get(depleted_id, {})
	if verify(not depleted_source.is_empty() and int(depleted_source.get("remaining", 0)) > 0,
		"The depletion preview starts from a populated native region projection."):
		depleted_source["remaining"] = 0
		preview_sources[depleted_id] = depleted_source
		view.state = preview
		view._refresh_ore_field()
		view.camera.position = Vector3(14.0, 20.0, 12.0)
		view.camera.look_at(Vector3(5.0, 0.0, -5.5))
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var depleted_image := viewport.get_texture().get_image()
		var depleted_path: String = fixture_directory.path_join("ore-field-depleted-preview.png")
		verify(depleted_image.get_size() == viewport.size and not FileAccess.file_exists(depleted_path)
			and depleted_image.save_png(depleted_path) == OK,
			"Retain the local-depletion presentation preview beside the full field view.")
	print(JSON.stringify({"phase": "ore-field-render", "source": "native terrain-bound opening",
		"cells": deposit.get("cells", []).size(), "views": 4, "viewport": [1600, 900],
		"depletion_preview": "fixture balance override, visual only", "input": "not_used",
		"human_quality": "not_assessed"}))
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
	verify(rocks.mesh == Scenery.Surface.SOURCE_OUTCROP_MESH and vertices.size() == 5748,
		"The uploaded scenery reuses the complete detailed boulder instead of a primitive hull mesh.")
	check_mesh_attributes(rocks.mesh, "Detailed natural rock")
	var source_faces: PackedVector3Array = Scenery.Surface.rock_faces()
	var planes: Array[Plane] = []
	for first in range(0, source_faces.size(), 3):
		var a := source_faces[first]
		var b := source_faces[first + 1]
		var c := source_faces[first + 2]
		var normal := (c - a).cross(b - a).normalized()
		planes.append(Plane(normal, normal.dot(a)))
	var protrusion := 0.0
	var normalized: Vector3 = Scenery.Surface.ROCK_SIZE / rocks.mesh.get_aabb().size
	for point in vertices:
		for plane in planes:
			protrusion = maxf(protrusion, plane.distance_to(point * normalized))
	var limit: float = Scenery.Surface.ROCK_SIZE.length() / 10216.0 + Geometry.NATIVE_POSE_EPSILON
	print(JSON.stringify({"detailed_rock_protrusion_metres": protrusion, "native_cooking_bound_metres": limit}))
	verify(protrusion <= limit,
		"Every detailed vertex fits the actual normalized cooked hull at the documented native precision.")
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var offset := index * 16
		var origin := Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
		var uploaded := Basis(Vector3(buffer[offset], buffer[offset + 4], buffer[offset + 8]),
			Vector3(buffer[offset + 1], buffer[offset + 5], buffer[offset + 9]),
			Vector3(buffer[offset + 2], buffer[offset + 6], buffer[offset + 10]))
		verify(origin.is_equal_approx(spec.center), "Visible and physical rock origins agree: " + spec.id)
		verify(uploaded.is_equal_approx(spec.basis * Basis.from_scale(spec.mesh_scale)),
			"The actual visible transform uses the same normalized scale as the cooked hull: " + spec.id)
		var input: PackedVector3Array = Scenery.Surface.rock_input_vertices()
		for vertex_index in range(input.size()):
			verify((origin + uploaded * (input[vertex_index] / normalized)).is_equal_approx(
				spec.center + spec.basis * spec.points[vertex_index]),
				"Visible and physical original hull inputs share the same world transform: " + spec.id)

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
	var color := material.albedo_texture.get_image()
	color.convert(Image.FORMAT_RGBA8)
	var color_data := color.get_data()
	var document := GLTFDocument.new()
	var raw := GLTFState.new()
	raw.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if not verify(document.append_from_buffer(FileAccess.get_file_as_bytes(Scenery.FOLIAGE_FILE), "", raw) == OK,
		"Decode the pinned original cutout for an independent base-opacity comparison."):
		node.free()
		return
	var raw_mesh: ArrayMesh = raw.get_meshes()[0].mesh.get_mesh()
	var raw_material := raw_mesh.surface_get_material(0) as StandardMaterial3D
	var original := raw_material.albedo_texture.get_image()
	original.convert(Image.FORMAT_RGBA8)
	var original_data := original.get_data()
	var alpha_exact := true
	var green_min := 1.0
	var green_max := 0.0
	for pixel in range(color.get_width() * color.get_height()):
		var at := pixel * 4
		alpha_exact = alpha_exact and color_data[at + 3] == original_data[at + 3]
		if color_data[at + 3] >= 128:
			green_min = minf(green_min, float(color_data[at + 1]) / 255.0)
			green_max = maxf(green_max, float(color_data[at + 1]) / 255.0)
	verify(alpha_exact, "The grass color correction preserves every source base-opacity byte.")
	verify(green_min >= 0.35, "Opaque grass blades retain green color instead of near-black photographed bands.")
	verify(green_max - green_min > 0.10, "The corrected blades retain photographed detail instead of a flat fill.")
	var coverage: Array[float] = []
	for level in range(6):
		var extent := color.get_width() >> level
		var offset := 0 if level == 0 else color.get_mipmap_offset(level)
		var opaque := 0
		for pixel in range(extent * extent):
			if color_data[offset + pixel * 4 + 3] >= 128:
				opaque += 1
		coverage.append(float(opaque) / float(extent * extent))
		verify(absf(coverage[level] - 0.160257975260417) < 0.02,
			"The cutout retains blade coverage from the source atlas through the 12-pixel mip.")
	verify(color_data[color.get_mipmap_offset(color.get_mipmap_count()) + 3] < 128,
		"A subpixel tuft does not turn its mostly transparent atlas into a solid card.")
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
	print(JSON.stringify({"maximum_normal_mip_length_error": maximum_error, "cutout_mip_coverage": coverage,
		"source_alpha_exact": alpha_exact, "opaque_green_range": [green_min, green_max],
		"geometry_checks": "reused from the retained first import", "rendered_quality": "not_assessed"}))
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
	verify(meadow.get_child_count() > 0 and meadow.get_child_count() <= 40,
		"Ordinary scenery has a bounded set of spatially grouped grass patches.")
	var faces: PackedVector3Array = view.get_node("ProductionScenery/GroundSurface").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var solids: Array = Scenery.Surface.support_boxes()
	var total := 0
	var near_worker := 0
	var worker: Array = Geometry.spawn("P")
	for patch: MultiMeshInstance3D in meadow.get_children():
		var instances := patch.multimesh
		var data := instances.buffer
		verify(instances.instance_count > 0 and instances.instance_count <= 48 and data.size() == instances.instance_count * 16,
			"Each patch uploads at most 48 complete transform/color records.")
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
			verify(absf(position.x - Scenery.river_center_x(position.z)) > Scenery.channel_half_width(position.z) + 0.8,
				"Uploaded meadow roots remain clear of the river.")
			if Vector2(position.x, position.z).distance_to(Vector2(worker[0], worker[2])) < Geometry.PITCH * 2.0:
				near_worker += 1
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
	verify(total >= 850 and total <= 1400, "The meadow fills more of the valley without exceeding its triangle budget.")
	verify(near_worker >= 15, "Actual meadow roots reach the worker's natural surroundings instead of reserving an empty build area.")
	print(JSON.stringify({"patches": meadow.get_child_count(), "new_tufts": total,
		"near_worker_tufts": near_worker,
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
		and basis.y.length() >= 1.1499 and basis.y.length() <= 2.9901,
		"Young stems keep gravity-up orientation across the bounded age range.")
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
		var west := 0
		var east := 0
		var shortest := INF
		var tallest := 0.0
		for offset in range(0, original.size(), 12):
			var basis := Basis(Vector3(original[offset], original[offset + 4], original[offset + 8]),
				Vector3(original[offset + 1], original[offset + 5], original[offset + 9]),
				Vector3(original[offset + 2], original[offset + 6], original[offset + 10]))
			var at := Vector3(original[offset + 3], original[offset + 7], original[offset + 11])
			shortest = minf(shortest, basis.y.length())
			tallest = maxf(tallest, basis.y.length())
			check_pine_root(basis, at)
			var envelope: AABB = Transform3D(basis, at) * mesh.get_aabb()
			verify(instances.custom_aabb.grow(0.0001).encloses(envelope), "Culling bounds enclose every entire sapling.")
			for row in range(33):
				var z := lerpf(envelope.position.z, envelope.end.z, float(row) / 32.0)
				var west_edge := Scenery.river_center_x(z) - Scenery.channel_half_width(z) - 0.3
				var east_edge := Scenery.river_center_x(z) + Scenery.channel_half_width(z) + 0.3
				verify(envelope.end.x < west_edge or envelope.position.x > east_edge,
					"The complete plant stays outside the water on its selected bank.")
			if envelope.end.x < Scenery.river_center_x(at.z):
				west += 1
			else:
				east += 1
			for solid in Scenery.Surface.support_boxes():
				var half: Vector3 = solid.size * 0.5
				var solid_bounds: AABB = Transform3D(solid.basis, solid.center) * AABB(-half, solid.size)
				verify(not envelope.intersects(solid_bounds.grow(0.2)), "The whole plant clears existing rock envelopes.")
		verify(west > 0 and east > 0 and tallest - shortest > 0.6,
			"The ordinary scene shows young pines of visibly different ages on both banks.")
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
	var total := 1 if node is GeometryInstance3D and node.material_override == material else 0
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
			var tint: float = rocks.multimesh.buffer[index * 16 + 12 + channel]
			verify(tint >= 0.6 and tint <= 1.0,
				"The authored geological tint preserves a majority of the photographed surface brightness.")
	var steel := ProductionSteelFloor.read_images()
	var ground := ProductionSteelFloor.read_images(Scenery.GROUND_ROOT, Scenery.GROUND_FILES, Vector2i(512, 512))
	verify(steel.status == "ready" and ground.status == "ready",
		"The extended scalar-extent argument preserves existing steel and ground decoder defaults.")
	verify(Scenery.ground_material() != material and ProductionSteelFloor.material() != material,
		"Surface roles keep separate material caches.")
	var missing := ProductionSteelFloor.read_images(fixture_directory.path_join("missing-stone"), Scenery.STONE_FILES, Vector2i(512, 512), Vector2i(256, 256))
	verify(missing.status == "missing", "Historical absent stone maps retain an explicit status.")
	var partial_path := fixture_directory.path_join("partial-stone")
	if verify(DirAccess.make_dir_absolute(partial_path) == OK, "The negative input directory is fresh and owned."):
		var file := FileAccess.open(partial_path.path_join(Scenery.STONE_FILES.albedo), FileAccess.WRITE)
		file.store_buffer(FileAccess.get_file_as_bytes(Scenery.STONE_ROOT.path_join(Scenery.STONE_FILES.albedo)))
		file.close()
		var partial := ProductionSteelFloor.read_images(partial_path, Scenery.STONE_FILES, Vector2i(512, 512), Vector2i(256, 256))
		verify(partial.status == "invalid" and partial.reason == "incomplete_material_set", "A partial stone package is never accepted as ready.")
	var wrong_extent := ProductionSteelFloor.read_images(Scenery.STONE_ROOT, Scenery.STONE_FILES, Vector2i(512, 512))
	verify(wrong_extent.status == "invalid" and wrong_extent.reason == "invalid_arm",
		"Scalar-map extents are validated, rather than treating a decode alone as a complete material.")
	var view := FixtureView.new()
	root.add_child(view)
	view._build_world()
	verify(view.model == null and view.actor_world == null and view.state.is_empty(),
		"Ordinary natural-scenery assembly starts no authority or gameplay clock.")
	var users := count_material_users(view, material)
	verify(users == 1, "The natural outcrop batch consumes the shared material without retired artificial stone architecture.")
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

func check_botanical_species() -> void:
	var loaded: Dictionary = Scenery.Surface.read_broadleaf()
	if not verify(loaded.status == "ready", "The shipped broadleaf source has its pinned self-contained identity."):
		return
	var mesh: ArrayMesh = loaded.mesh
	verify(mesh.get_surface_count() == 3 and mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 39400 * 3
		and mesh.surface_get_arrays(1)[Mesh.ARRAY_INDEX].size() == 275674 * 3
		and mesh.surface_get_arrays(2)[Mesh.ARRAY_INDEX].size() == 6824 * 3,
		"A distinct modeled broadleaf canopy uses its selected source detail level.")
	var leaf_finish := mesh.surface_get_material(1) as StandardMaterial3D
	verify(leaf_finish != null and leaf_finish.albedo_texture.get_image().get_format() == Image.FORMAT_RGB8,
		"Modeled provider leaves retain their sourced color instead of added atlas cards.")
	var specs: Array[Dictionary] = Scenery.Surface.broadleaf_specs()
	if not verify(specs.size() == 2, "Two rooted broadleaf trees join the existing fir and pine species."):
		return
	var source_trunk: PackedInt32Array = mesh.surface_get_arrays(2)[Mesh.ARRAY_INDEX]
	verify(Scenery.Surface.broadleaf_collision_faces().size() == source_trunk.size() * specs.size(),
		"Every rendered broadleaf trunk contributes its exact source triangles to physical contact.")
	var west := 0
	var east := 0
	for spec in specs:
		if spec.center.x < Scenery.river_center_x(spec.center.z):
			west += 1
		else:
			east += 1
		verify(spec.bounds.position.z >= -23.0 and spec.bounds.end.z <= 23.0,
			"Whole broadleaf crowns stay within the opening worksite.")
		for solid in Scenery.Surface.support_boxes():
			var half: Vector3 = solid.size * 0.5
			var rock_bounds: AABB = Transform3D(solid.basis, solid.center) * AABB(-half, solid.size)
			verify(not spec.bounds.intersects(rock_bounds.grow(0.25)), "Broadleaf crowns clear fixed scenery rocks.")
	verify(west == 1 and east == 1, "The broadleaf species reads from both riverbanks.")
	for shared in [false, true]:
		var view: Variant = SharedBankView.new() if shared else FixtureView.new()
		root.add_child(view)
		view._build_world()
		var scenery: Node3D = view.get_node("ProductionScenery")
		var trees: Node3D = scenery.get_node("BankBroadleaf")
		verify(trees.get_child_count() == specs.size(), "Both normal builders mount the source-bound broadleaf group.")
		for index in range(specs.size()):
			var tree := trees.get_child(index) as MeshInstance3D
			var spec: Dictionary = specs[index]
			verify(tree != null and tree.mesh == mesh and tree.name == spec.id and tree.position == spec.center
				and tree.basis == spec.basis.scaled_local(Vector3.ONE * spec.scale),
				"Each visible broadleaf has the exact rooted physical pose.")
			verify(tree.get_child_count() == 0 and spec.bounds.grow(0.001).encloses(tree.transform * mesh.get_aabb()),
				"The complete sourced canopy stays inside its bank-clearance envelope without duplicate fill meshes.")
		var shrubs: Node3D = scenery.get_node("ShrubUnderstory")
		verify(shrubs.get_child_count() == 2, "Both complete woody shrub forms are mounted separately.")
		for variant in range(2):
			var patch := shrubs.get_child(variant) as MultiMeshInstance3D
			if not verify(patch != null and patch.multimesh != null and patch.multimesh.instance_count >= 5,
				"Each shrub form grows at several terrain roots."):
				continue
			var shrub_mesh := patch.multimesh.mesh
			var wood := shrub_mesh.surface_get_material(0) as StandardMaterial3D
			var leaves := shrub_mesh.surface_get_material(1) as StandardMaterial3D
			var twigs := shrub_mesh.surface_get_material(2) as StandardMaterial3D
			verify(shrub_mesh.get_surface_count() == 3 and wood != null and leaves != null and twigs != null
				and wood.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				and leaves.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				and twigs.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				and leaves.albedo_texture.get_image().get_format() == Image.FORMAT_RGBA8,
				"Complete woody bushes retain solid bark and source cutout foliage.")
			var candidate: PackedFloat32Array = patch.get_meta("candidate_buffer")
			verify(candidate.size() == patch.multimesh.instance_count * 12 and patch.visibility_range_end <= 40.0,
				"Soft bushes retain complete transforms and a bounded visibility range.")
			for offset in range(0, candidate.size(), 12):
				var basis := Basis(Vector3(candidate[offset], candidate[offset + 4], candidate[offset + 8]),
					Vector3(candidate[offset + 1], candidate[offset + 5], candidate[offset + 9]),
					Vector3(candidate[offset + 2], candidate[offset + 6], candidate[offset + 10]))
				var at := Vector3(candidate[offset + 3], candidate[offset + 7], candidate[offset + 11])
				var envelope: AABB = Transform3D(basis, at) * patch.multimesh.mesh.get_aabb()
				verify(patch.multimesh.custom_aabb.grow(0.001).encloses(envelope),
					"Bush culling bounds enclose every complete plant.")
				verify(envelope.end.x < Scenery.river_center_x(at.z) - Scenery.channel_half_width(at.z)
					or envelope.position.x > Scenery.river_center_x(at.z) + Scenery.channel_half_width(at.z),
					"Bush geometry stays clear of the river.")
		var first: MultiMeshInstance3D = shrubs.get_child(0)
		var before := first.multimesh.instance_count
		var candidate: PackedFloat32Array = first.get_meta("candidate_buffer")
		var cell := [roundi(candidate[3] / Geometry.PITCH), roundi(candidate[11] / Geometry.PITCH)]
		Scenery.refresh_vegetation(scenery, {"entities": {"shrub-clearance": {"kind": "belt", "cell": cell}}})
		verify(first.multimesh.instance_count < before, "Confirmed construction suppresses intersecting soft bushes.")
		Scenery.refresh_vegetation(scenery, {"entities": {}})
		verify(first.multimesh.instance_count == before, "Removing the confirmed volume restores all bushes.")
		verify(view.model == null and view.actor_world == null and view.request_sequence == 0,
			"The botanical view starts no authoritative world or requests.")
		view.free()
	print(JSON.stringify({"broadleaf_trees": specs.size(), "broadleaf_wood_triangles": source_trunk.size() / 3 * specs.size(),
		"shrub_variants": 2, "authority_started": false}))

func check_bank_firs() -> void:
	# Exercise the actual absent-file branch before any fir layout cache is
	# built. Only this private captured project's optional asset is moved.
	if not fir_layout_only:
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
	if not verify(specs.size() == 6, "The source-qualified site composes three original bank firs and three upper-bank firs."):
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
				var bank_clear := envelope.end.x < Scenery.river_center_x(z) - Scenery.channel_half_width(z) - 0.4 \
					if index < 3 else envelope.position.x > Scenery.river_center_x(z) + Scenery.channel_half_width(z) + 0.4
				verify(bank_clear, "The actual complete canopy stays on its own bank, clear of the channel.")
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
	print(JSON.stringify({"trees": specs.size(), "actual_wood_triangles": Scenery.Surface.fir_collision_faces().size() / 3,
		"rendered_quality": "not_assessed", "physics": "separate_case", "authority": "not_started"}))

func check_bank_fir_lifecycle() -> void:
	for shared_profile in [false, true]:
		var view: Variant = SharedBankView.new() if shared_profile else FixtureView.new()
		root.add_child(view)
		view._build_world()
		var group: Node3D = view.get_node("ProductionScenery/BankFirs")
		verify(group.is_inside_tree() and group.get_child_count() == 6, "The ordinary six-fir group is mounted inside the real node tree.")
		verify(view.camera.is_inside_tree() and view.camera.global_transform.is_finite(), "The normal camera mount is valid during world assembly.")
		verify(view.model == null and view.actor_world == null and view.request_sequence == 0, "The mounted fixture still starts no game authority or requests.")
		view.free()

func run() -> void:
	if mode == "botanical-species":
		check_botanical_species()
		finish()
		return
	if mode == "collector-carrier":
		check_collector_carrier()
		verify(checks == 125, "All raised cells, levels and formed flights complete the fit check.")
		finish()
		return
	if mode == "foundation-depth-vegetation":
		check_foundation_depth_vegetation()
		verify(checks >= 5, "The foundation-depth case completes its required observations.")
		finish()
		return
	if mode == "construction-vegetation":
		await check_construction_vegetation()
		if DisplayServer.get_name().to_lower() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
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
	if mode == "site-render":
		await check_site_render()
		finish()
		return
	if mode == "ore-field-render":
		await check_ore_field_render()
		finish()
		return
	if mode == "water-flow":
		check_water_flow()
		finish()
		return
	if mode == "water-pattern":
		check_water_pattern()
		finish()
		return
	if mode == "water-render":
		await check_water_render()
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
		var river_x: float = Scenery.Surface.river_center_x(sample_z)
		verify(Scenery.Surface.height_at(river_x, sample_z) < Scenery.stream_surface_height(river_x, sample_z) - 0.25,
			"The emitted terrain bed stays submerged at the actual center of the curved river.")
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
	verify(ripples.get_width() == 256 and ripples.get_height() == 256 and ripples.has_mipmaps()
		and water.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and water.detail_enabled,
		"Water uses the explicit translucent layered-ripple finish.")
	for y in range(0, 256, 32):
		for x in range(0, 256, 32):
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
