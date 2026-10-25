extends SceneTree
## Adapter geometry and isolated physical-fixture checks; no game or desktop.
const Surface = preload("res://opening/site_surface.gd")
const ActorWorld = preload("res://opening/actor_world.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const NativeModel = preload("res://opening/native_model.gd")
const Opening = preload("res://opening/opening.gd")
var checks := 0
var failed := false
var failures := 0

class EmptyPhysicalFacts extends RefCounted:
	func projection() -> Dictionary:
		return {"context": "fir-physics-fixture", "options": {"physical": true, "native": true},
			"actors": {}, "entities": {}, "transmission_parts": {}, "belt_spans": {}}

class NativeChallengeFacts extends RefCounted:
	var state: Dictionary
	var client := "P"
	var legacy_fixture := false

class MaturePhysicalFacts extends RefCounted:
	var sources := {}
	func projection() -> Dictionary:
		return {"context": "mature-tree-physics", "options": {"physical": true, "native": true},
			"actors": {}, "entities": {}, "transmission_parts": {}, "belt_spans": {},
			"hand_sources": sources}

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	if "--outcrop-native-only" in OS.get_cmdline_user_args():
		check_outcrop_native()
		return
	if "--belt-water-native-only" in OS.get_cmdline_user_args():
		check_belt_water_native(false)
		return
	if "--belt-water-native-forward-only" in OS.get_cmdline_user_args():
		check_belt_water_native(true)
		return
	if "--water-samples-only" in OS.get_cmdline_user_args():
		check_flow_cells()
		return
	if "--water-native-only" in OS.get_cmdline_user_args():
		check_water_native()
		return
	if "--flow-sections-only" in OS.get_cmdline_user_args():
		check_flow_sections()
		return
	if "--waterwheel-visual-only" in OS.get_cmdline_user_args():
		check_waterwheel_visual()
		return
	if "--bank-firs-physics-only" in OS.get_cmdline_user_args():
		call_deferred("check_bank_firs_physics")
		return
	if "--mature-tree-depletion-only" in OS.get_cmdline_user_args():
		call_deferred("check_mature_tree_depletion")
		return
	if "--native-hull-matching-only" in OS.get_cmdline_user_args():
		check_native_hull_matching()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"scope": "pinned native hull projection matching", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	if "--convex-only" in OS.get_cmdline_user_args():
		check_convex_rocks()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"scope": "shared convex rock topology and independent capsule contacts", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	if "--structures-only" in OS.get_cmdline_user_args():
		check_structures()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"scope": "changed immutable support solids and rotated box contacts", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	var points := Surface.vertices()
	var faces := Surface.faces()
	var stride := Surface.grid_size()
	verify(stride > 73 and points.size() == stride * stride and faces.size() == (stride - 1) * (stride - 1) * 6,
		"Local refinement has one complete shared vertex/triangle lattice.")
	verify(faces[0] == points[0] and faces[1] == points[1] and faces[2] == points[stride + 1]
		and faces[3] == points[0] and faces[4] == points[stride + 1] and faces[5] == points[stride],
		"Refinement preserves the clockwise diagonal used by both consumers.")
	verify(absf(Surface.raw_height(30.0, 1.65) - 5.944855778225841) < 0.000001,
		"The original analytical terrain value remains unchanged.")
	verify(Surface.height_at(30.0, 1.65) > 5.5,
		"Refinement does not hide the original hill or evade its buried-capsule finding.")
	var first := points[0]
	points[0] = Vector3.ZERO
	faces[0] = Vector3.ZERO
	verify(Surface.vertex(0, 0) == first and Surface.faces()[0] == first,
		"Renderer and physics callers receive copies rather than mutable cache aliases.")
	for corner in [Vector2(-128, -128), Vector2(128, -128), Vector2(-128, 128), Vector2(128, 128)]:
		var gx := 0 if corner.x < 0 else stride - 1
		var gz := 0 if corner.y < 0 else stride - 1
		verify(is_equal_approx(Surface.height_at(corner.x, corner.y), Surface.vertex(gx, gz).y),
			"Closed-domain edge coordinates retain their actual endpoint height.")
	verify(is_nan(Surface.height_at(129, 0)) and is_nan(Surface.height_at(NAN, 0)),
		"An absent terrain surface is explicit instead of inventing a flat extension.")
	verify(Surface.pad_panels().is_empty() and Surface.foundation_boxes().is_empty()
		and Surface.architecture_boxes().is_empty(), "The unbuilt site has no hidden or visible platform/canal catalogue.")
	for x in [-1.65, 0.0, 1.65, 3.3, 6.6]:
		for z in [-3.3, 0.0, 3.3, 6.6]:
			verify(absf(Surface.height_at(x, z) - (-0.02)) < 0.00001,
				"The emitted clearing supports the existing character and construction anchor at " + str(Vector2(x, z)) + ".")
	for z in [-3.3, 0.0, 3.3, 6.6]:
		var x := Surface.river_center_x(z)
		var at := Surface.cell(x, z)
		verify(Surface.vertex(at.x + 1, at.y).x - Surface.vertex(at.x, at.y).x <= 0.25001
			and Surface.vertex(at.x, at.y + 1).z - Surface.vertex(at.x, at.y).z <= 0.25001,
			"The actual narrow bank uses local samples rather than a hidden box strip.")
		verify(Surface.height_at(x, z) < -0.9, "The visible stream retains a real recessed terrain bed.")
	verify(Surface.river_center_x(-4.0) < Surface.river_center_x(1.65) - 0.9
		and Surface.river_center_x(8.0) < Surface.river_center_x(1.65) - 1.0,
		"The unbuilt stream bends west of the worksite rather than retaining a straight canal cut.")
	for bank_z in [-30.0, -22.0, 23.0, 30.0]:
		var river_x := Surface.river_center_x(bank_z)
		for side in [-1.0, 1.0]:
			var edge := Surface.channel_half_width(bank_z)
			var steepest := 0.0
			for step in range(1, 61):
				var outer := edge + float(step) * 0.5
				var previous := Surface.height_at(river_x + side * (outer - 0.5), bank_z)
				var current := Surface.height_at(river_x + side * outer, bank_z)
				steepest = maxf(steepest, absf(current - previous) / 0.5)
			verify(steepest < 0.95,
				"The emitted distant riverbank rises without a near-vertical cut at "
				+ str(Vector2(side, bank_z)) + ".")
	for sample in [Vector2(-2.7, 1.65), Vector2(-1.65, 3.3), Vector2(0.125, 2.125),
		Vector2(11.99, -9.99), Vector2(12.01, -10.01), Vector2(30.0, 1.65), Vector2(30.0, 30.0)]:
		var at := Surface.cell(sample.x, sample.y)
		var a := Surface.vertex(at.x, at.y)
		var b := Surface.vertex(at.x + 1, at.y)
		var c := Surface.vertex(at.x + 1, at.y + 1)
		var d := Surface.vertex(at.x, at.y + 1)
		for center in [(a + b + c) / 3.0, (a + c + d) / 3.0]:
			verify(absf(Surface.height_at(center.x, center.z) - center.y) < 0.00002,
				"The height query agrees with the centroid plane of each actual emitted triangle.")
	# An independent geometric construction places the lower capsule sphere
	# tangent to the interior of the literal counterexample cell's triangle.
	var far_cell := Surface.cell(30.0, 30.0)
	var a := Surface.vertex(far_cell.x, far_cell.y)
	var b := Surface.vertex(far_cell.x + 1, far_cell.y + 1)
	var c := Surface.vertex(far_cell.x, far_cell.y + 1)
	var center := (a + b + c) / 3.0
	var normal := (b - a).cross(c - a).normalized()
	if normal.y < 0:
		normal = -normal
	var radius := 0.3
	var half_segment := 0.6
	var tangent := center + normal * radius + Vector3.UP * half_segment
	var resting: Dictionary = Surface.capsule_overlap(tangent, radius, 1.8)
	verify(resting.valid and resting.analytical_overlap_measure < 0.0005,
		"An independently constructed tangent capsule is not classified as deep penetration.")
	var penetrated: Dictionary = Surface.capsule_overlap(tangent - normal * 0.02, radius, 1.8)
	verify(penetrated.valid and penetrated.analytical_overlap_measure > 0.015,
		"A positive capsule/face penetration cannot hide behind a center-height-only check.")
	var buried: Dictionary = Surface.capsule_overlap(Vector3(30, 0.88, 1.65), radius, 1.8)
	verify(buried.valid and buried.subsurface_depth > 5.5 and buried.geometric_overlap,
		"The original saved pose wholly beneath a hollow trimesh remains a positive burial.")
	verify(not Surface.capsule_overlap(Vector3(NAN, 0, 0), radius, 1.8).valid
		and not Surface.capsule_overlap(tangent, -1, 1.8).valid,
		"Invalid contact data fails closed.")
	var world := ActorWorld.new()
	verify(world.model == null and world.bodies.is_empty() and world.floor_body == null,
		"Parsing the actual producer adds no authority or physical body to this resource check.")
	world.free()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"scope": "static terrain adapter geometry", "native_movement": "not_run", "desktop": "not_used"}))
	quit(1 if failed else 0)

func check_structures() -> void:
	var specs := Surface.support_boxes()
	var identities := {}
	verify(specs.size() == 65, "The real natural rocks and one mineable source are the only site obstacles.")
	for spec in specs:
		verify(not identities.has(spec.id), "Shared solid identities are unique: " + spec.id)
		identities[spec.id] = true
		verify(spec.center.is_finite() and spec.size.is_finite() and spec.size.x > 0.0 and spec.size.y > 0.0
			and spec.size.z > 0.0 and spec.basis.is_equal_approx(spec.basis.orthonormalized()), "Every native box descriptor is finite and rigid.")
		verify(spec.get("finish", "stone") in ["stone", "dark_stone"],
			"Solid canyon descriptors use natural stone finishes rather than timber or iron: " + spec.id)
		verify(spec.id.begins_with("rock_") or spec.id == "source_outcrop", "No invisible old canal, platform or seam barrier survives.")
	verify(identities.has("rock_63") and not identities.has("architecture_foam"), "Rock support is present; water/foam is excluded.")
	var first: Vector3 = specs[0].center
	specs[0].center = Vector3(999, 999, 999)
	verify(Surface.support_boxes()[0].center == first, "Descriptor callers cannot mutate later renderer or producer inputs.")
	for angle in [0.0, 0.3, 1.1]:
		var rotation := Basis.from_euler(Vector3(angle, angle * 0.8, 0.0))
		var transform := Transform3D(rotation, Vector3(4, 2, 8))
		var face := transform * Vector3(0.5, 0, 0)
		var normal: Vector3 = rotation.x
		var tangent := face + normal * 0.3
		verify(Surface.capsule_box_overlap(tangent, 0.3, 0.6, transform, Vector3.ONE * 0.5) < 0.000001,
			"An independently constructed sphere/rotated box tangent is accepted.")
		verify(absf(Surface.capsule_box_overlap(tangent - normal * 0.02, 0.3, 0.6, transform, Vector3.ONE * 0.5) - 0.02) < 0.000001,
			"An independent 20mm rotated-face penetration is retained.")
		verify(Surface.capsule_box_overlap(transform.origin, 0.3, 1.8, transform, Vector3.ONE * 0.5) > 0.29,
			"A capsule segment crossing or buried in a rotated box is refused.")

func check_convex_rocks() -> void:
	var points := Surface.rock_vertices()
	var faces := Surface.rock_faces()
	verify(points.size() > 12 and points.size() <= 512 and faces.size() > 60 and faces.size() % 3 == 0,
		"The simplified asset envelope retains its bounded cooked hull and complete facets.")
	var edges := {}
	for point in points:
		verify(point.is_finite(), "Every native hull vertex is finite.")
	for first in range(0, faces.size(), 3):
		var a := faces[first]
		var b := faces[first + 1]
		var c := faces[first + 2]
		var normal := (c - a).cross(b - a).normalized()
		verify(normal.is_finite() and normal.dot(a) > 0.0, "Every collision facet faces out from the enclosed origin.")
		for point in points:
			verify(normal.dot(point - a) < 0.000001, "Each facet bounds the same convex hull used by the physics server.")
		for pair in [[a, b], [b, c], [c, a]]:
			var start := points.find(pair[0])
			var end := points.find(pair[1])
			verify(start >= 0 and end >= 0 and start != end, "Every facet edge joins actual distinct native vertices.")
			var key := "%d:%d" % [mini(start, end), maxi(start, end)]
			var entry: Vector2i = edges.get(key, Vector2i.ZERO)
			edges[key] = entry + Vector2i(1, 1 if start < end else -1)
	verify(points.size() - edges.size() + faces.size() / 3 == 2,
		"The complete convex surface has the closed Euler relation.")
	for edge in edges.values():
		verify(edge == Vector2i(2, 0), "Every edge is shared twice with opposite directed winding.")
	for angle in [0.0, 0.4, 1.1]:
		var transform := Transform3D(Basis.from_euler(Vector3(angle, angle * 0.8, -angle * 0.3)), Vector3(4, 2, 8))
		for first in [0, 21, 51]:
			var a := faces[first]
			var b := faces[first + 1]
			var c := faces[first + 2]
			var center := transform * ((a + b + c) / 3.0)
			var normal: Vector3 = transform.basis * (c - a).cross(b - a).normalized()
			var radius := 0.035
			var tangent := center + normal * radius
			verify(Surface.capsule_convex_overlap(tangent, radius, 2.0 * radius, transform, faces) < 0.000001,
				"An independently constructed sphere/facet tangent has no deep overlap.")
			verify(absf(Surface.capsule_convex_overlap(tangent - normal * 0.02, radius, 2.0 * radius, transform, faces) - 0.02) < 0.000002,
				"A real twenty-millimetre facet penetration is measured in each rigid orientation.")
		verify(Surface.capsule_convex_overlap(transform.origin, 0.3, 1.8, transform, faces) > 0.29,
			"A capsule crossing the solid interior cannot evade contact as a hollow surface.")
	var specs := Surface.rock_boxes()
	for spec in specs:
		verify(spec.points.size() == Surface.rock_input_vertices().size()
			and spec.native_points.size() > 12 and spec.native_points.size() <= 512 and spec.faces.size() % 3 == 0,
			"Every instance separates original cooking input from its bounded cooked hull and clearance envelope.")
		for point: Vector3 in spec.native_points:
			verify(point.abs().x <= spec.size.x * 0.5 and point.abs().y <= spec.size.y * 0.5
				and point.abs().z <= spec.size.z * 0.5,
				"Every actual native point fits its declared physical clearance envelope.")
	points[0] = Vector3(999, 999, 999)
	faces[0] = Vector3(999, 999, 999)
	specs[0].points[0] = Vector3(999, 999, 999)
	verify(Surface.rock_vertices()[0].x < 1 and Surface.rock_faces()[0].x < 1
		and Surface.rock_boxes()[0].points[0].x < 1, "Callers cannot mutate the shared template or later native descriptors.")
	verify(is_inf(Surface.capsule_convex_overlap(Vector3(NAN, 0, 0), 0.3, 1.8, Transform3D.IDENTITY, Surface.rock_faces()))
		and is_inf(Surface.capsule_convex_overlap(Vector3.ZERO, 0.3, 1.8, Transform3D.IDENTITY, PackedVector3Array())),
		"Invalid contact inputs fail closed.")

func check_bank_firs_physics() -> void:
	var world := ActorWorld.new()
	verify(world.configure(EmptyPhysicalFacts.new()).accepted, "The existing physical producer accepts the empty invented fixture.")
	root.add_child(world)
	for frame in range(3):
		await physics_frame
		await process_frame
	verify(world._geometry_registered(), "The actual registered floor contains the complete matching terrain and woody fixture.")
	var rid: RID = world.floor_body.get_rid()
	var shape_rid := PhysicsServer3D.body_get_shape(rid, 0)
	var registered: Dictionary = PhysicsServer3D.shape_get_data(shape_rid)
	var expected := Surface.faces()
	expected.append_array(Surface.fir_collision_faces())
	expected.append_array(Surface.broadleaf_collision_faces())
	verify(registered.faces == expected and registered.backface_collision == true,
		"Original terrain plus exact transformed woody facets is the actual native two-sided floor shape.")
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	query.shape = capsule
	query.collision_mask = 1
	query.margin = 0.0
	var contacts: Array = []
	for spec in Surface.fir_specs():
		var at: Vector3 = spec.center + Vector3.UP * 1.2
		query.transform = Transform3D(Basis.IDENTITY, at)
		var hits := world.get_world_3d().direct_space_state.intersect_shape(query, 128)
		var native_hit := false
		for hit in hits:
			native_hit = native_hit or hit.rid == rid
		var measured := Surface.capsule_overlap(at, capsule.radius, capsule.height)
		verify(native_hit and measured.geometric_overlap and measured.nearest_fir == spec.id and measured.fir_triangles_measured > 0,
			"A real capsule intersects the woody trunk and the matching analytical contact is retained.")
		verify(measured.subsurface_depth == 0.0, "The positive witness is above the ground, so terrain burial cannot substitute for wood contact.")
		contacts.append({"tree": spec.id, "at": at, "native_hit": native_hit, "measure": measured})
	for spec in Surface.broadleaf_specs():
		var at: Vector3 = spec.center + Vector3.UP * 1.2
		query.transform = Transform3D(Basis.IDENTITY, at)
		var hits := world.get_world_3d().direct_space_state.intersect_shape(query, 128)
		var native_hit := false
		for hit in hits:
			native_hit = native_hit or hit.rid == rid
		var measured := Surface.capsule_overlap(at, capsule.radius, capsule.height)
		verify(native_hit and measured.geometric_overlap and measured.nearest_broadleaf == spec.id
			and measured.broadleaf_triangles_measured > 0,
			"A real capsule intersects each broadleaf trunk and matching analytical contact is retained.")
		verify(measured.subsurface_depth == 0.0,
			"Broadleaf contact comes from the woody surface rather than terrain burial.")
		contacts.append({"tree": spec.id, "at": at, "native_hit": native_hit, "measure": measured})
	query.transform = Transform3D(Basis.IDENTITY, Vector3(1.65, 2, 1.65))
	var clear := world.get_world_3d().direct_space_state.intersect_shape(query, 128)
	verify(clear.is_empty() and not Surface.capsule_overlap(query.transform.origin, 0.3, 1.8).geometric_overlap,
		"The original working area remains clear in both native and analytical queries.")
	var floor_shape := world.floor_body.get_child(0).shape as ConcavePolygonShape3D
	floor_shape.set_faces(Surface.faces())
	for frame in range(2):
		await physics_frame
		await process_frame
	verify(not world._geometry_registered(), "Removing tree triangles from the actual native floor fails the existing exact geometry guard.")
	floor_shape.set_faces(expected)
	for frame in range(2):
		await physics_frame
		await process_frame
	verify(world._geometry_registered(), "Restoring the exact expected facets restores registration.")
	world.floor_body.position.x = 0.02
	for frame in range(2):
		await physics_frame
		await process_frame
	var shifted: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
	verify(absf(shifted.origin.x - 0.02) < 0.000001 and shifted.origin == world.floor_body.position,
		"The altered-pose control moves the real native body and its node together.")
	verify(not world._geometry_registered(), "A consistent but shifted floor cannot pass for the immutable world-space fixture.")
	world.floor_body.position = Vector3.ZERO
	for frame in range(2):
		await physics_frame
		await process_frame
	verify(world._geometry_registered() and world.bodies.is_empty() and world.machines.is_empty(),
		"The restored fixture remains registered without a player, machine or second state owner.")
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "scope": "actual static fixture registration and capsule queries",
		"tree_contacts": contacts, "terrain_triangles": Surface.faces().size() / 3,
		"wood_triangles": (Surface.fir_collision_faces().size() + Surface.broadleaf_collision_faces().size()) / 3,
		"authority": "invented empty facts only", "gameplay": "not_run", "desktop": "not_used"}))
	world.free()
	quit(1 if failed else 0)

func check_mature_tree_depletion() -> void:
	var facts := MaturePhysicalFacts.new()
	for row in Surface.mature_tree_collision_rows():
		facts.sources[row.id] = {"remaining": 8}
	var world := ActorWorld.new()
	verify(world.configure(facts).accepted, "A physical site accepts the finite mature-tree projection.")
	root.add_child(world)
	for frame in range(3):
		await physics_frame
		await process_frame
	var tree: Dictionary = Surface.broadleaf_specs()[0]
	var at: Vector3 = tree.center + Vector3.UP * 1.2
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	query.shape = capsule
	query.collision_mask = Geometry.GROUND_LAYER
	query.transform = Transform3D(Basis.IDENTITY, at)
	var rid: RID = world.floor_body.get_rid()
	var before: Array = world.get_world_3d().direct_space_state.intersect_shape(query, 128)
	verify(world._geometry_registered() and before.any(func(hit: Dictionary) -> bool: return hit.rid == rid),
		"The standing broadleaf has its exact physical trunk in the actor floor.")
	facts.sources[tree.id].remaining = 0
	verify(world.sync_topology().accepted, "Native projected depletion refreshes the physical floor.")
	for frame in range(3):
		await physics_frame
		await process_frame
	var after: Array = world.get_world_3d().direct_space_state.intersect_shape(query, 128)
	var expected := Surface.faces()
	expected.append_array(Surface.mature_tree_collision_faces(world.active_woody_ids))
	var measured := Surface.capsule_overlap(at, capsule.radius, capsule.height, world.active_woody_ids)
	verify(world._geometry_registered() and world.terrain_faces == expected \
		and not after.any(func(hit: Dictionary) -> bool: return hit.rid == rid)
		and not measured.geometric_overlap and measured.nearest_broadleaf == "",
		"Depletion removes the invisible trunk from native physics and analytical contact.")
	verify(facts.sources["broadleaf_01"].remaining == 8 and world.active_woody_ids.has("broadleaf_01"),
		"A neighboring broadleaf keeps its own finite and physical identity.")
	facts.sources[tree.id].remaining = 8
	verify(world.sync_topology().accepted, "A fresh projection can reconstruct the standing tree collision.")
	for frame in range(3):
		await physics_frame
		await process_frame
	var restored: Array = world.get_world_3d().direct_space_state.intersect_shape(query, 128)
	verify(world._geometry_registered() and restored.any(func(hit: Dictionary) -> bool: return hit.rid == rid),
		"Restored native source state reconstructs the exact standing trunk.")
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"scope": "native-projected mature tree collision and depletion", "desktop": "not_used"}))
	world.free()
	quit(1 if failed else 0)

func check_native_hull_matching() -> void:
	var source := Surface.rock_vertices()
	var reordered := source.duplicate()
	reordered.reverse()
	verify(Surface.match_native_rock(reordered, source) == source,
		"Native point ordering does not change the source vertex correspondence.")
	var changed := source.duplicate()
	changed[0] += Vector3.ONE * 0.00002
	verify(Surface.match_native_rock(changed, source).size() == source.size(),
		"A sub-quantum cooked displacement is distinguished from a geometry change.")
	changed[0] += Vector3.RIGHT * 0.01
	verify(Surface.match_native_rock(changed, source).is_empty(), "A real ten-millimetre shape change fails closed.")
	changed = source.duplicate()
	changed[0] = changed[1]
	verify(Surface.match_native_rock(changed, source).is_empty(), "A duplicate cannot hide a missing physical vertex.")
	changed = source.duplicate()
	changed.remove_at(0)
	verify(Surface.match_native_rock(changed, source).is_empty(), "An incomplete native point set is refused.")
	changed = source.duplicate()
	changed[0] = Vector3(NAN, 0, 0)
	verify(Surface.match_native_rock(changed, source).is_empty(), "Invalid native coordinates are refused.")
	verify(Surface.rock_faces_for_vertices(source, {"native_points": source, "faces": Surface.rock_faces()}) == Surface.rock_faces(),
		"Mapped native vertices preserve the exact shared facet topology.")

func check_flow_cells() -> void:
	var rows: Array = Surface.flow_cells()
	var found := false
	for row: Array in rows:
		assert(row.size() == 3)
		var x: float = float(row[0]) * Geometry.HEIGHT_STEP
		var z: float = float(row[1]) * Geometry.HEIGHT_STEP
		var center := Surface.river_center_x(z)
		assert(x > center - Surface.wet_half_width(z, -1.0)
			and x < center + Surface.wet_half_width(z, 1.0))
		assert(float(row[2]) * Geometry.HEIGHT_STEP / 100.0 > Surface.height_at(x, z))
		if row[0] == -8 and row[1] == 4:
			found = true
	assert(found, "A wheel cell at the first worksite intersects the actual river.")
	var narrow := Surface.wet_half_width(1.65, -1.0) + Surface.wet_half_width(1.65, 1.0)
	assert(narrow > 4.5, "The emitted starting wet cross-section exceeds 4.5 meters.")
	assert(Surface.river_center_x(1.65) + Surface.wet_half_width(1.65, 1.0) < -1.65,
		"The wider river preserves the dry character and construction anchor.")
	var broad := Surface.wet_half_width(22.0, -1.0) + Surface.wet_half_width(22.0, 1.0)
	var rapid := Surface.wet_half_width(38.0, -1.0) + Surface.wet_half_width(38.0, 1.0)
	assert(broad > narrow + 1.0 and broad > rapid + 1.0, "The emitted riverbed has a broad wheel-test section between narrower reaches.")
	for z in [1.65, 22.0, 38.0]:
		for side in [-1.0, 1.0]:
			var at: float = Surface.river_center_x(z) + side * Surface.wet_half_width(z, side)
			assert(Surface.height_at(at, z) < Surface.stream_surface_height(at, z), "The wet edge is inside the actual terrain bank.")
	print("terrain flow cell and riverbed section controls passed: ", rows.size())
	quit(0)

func expect(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		push_error(message)
		quit(1)
	return value

func check_outcrop_native() -> void:
	for cell_z in [0, 1]:
		for level in [0, 4]:
			var context := "fitted-source-%d-%d" % [cell_z, level]
			var model = NativeModel.new(context, ["P"])
			if not expect(model.boot_result.get("accepted", false),
					"Bind the actual site and its source-rock obstacle"):
				return
			var before: Dictionary = model.projection()
			if not expect(before.source_deposit.cells.has([0, cell_z]),
					"The native source policy includes this exact deposit cell"):
				return
			if not expect(model.publish_actor("P", [1.65, 1.0, float(cell_z) * Geometry.PITCH], 1).get("accepted", false),
					"The actor can reach the deposit from its clear east side"):
				return
			if level > 0:
				var foundation: Dictionary = model.command({"context": context, "client": "P",
					"request": "floor-%d" % cell_z, "action": "place_foundation", "cell": [0, cell_z], "level": level})
				if not expect(foundation.get("accepted", false),
						"A foundation can cover the ore deposit: " + str(foundation)):
					return
			var placed: Dictionary = model.command({"context": context, "client": "P",
				"request": "source-%d" % cell_z, "action": "place", "kind": "collector",
				"cell": [0, cell_z], "level": level, "axis": "z"})
			if not expect(placed.get("accepted", false),
					"A collector fits the exposed or covered deposit: " + str(placed)):
				return
			var after: Dictionary = model.projection()
			if not expect(after.stock.source == before.stock.source and after.entities.has(placed.entity),
					"Placement preserves the one finite source reserve and records one machine"):
				return
	print(JSON.stringify({"status": "pass", "checks": checks,
		"scope": "actual native collector admission at both source cells, ground and raised foundation",
		"desktop": "not_used", "human_play": "not_run"}))
	quit(0)

func check_belt_water_native(forward: bool) -> void:
	var side := -1 if forward else 1
	var model = NativeModel.new("belt-water-site", ["P"])
	if not expect(model.boot_result.get("accepted", false), "Bind the generated river site: " + str(model.boot_result)):
		return
	var counter := {"epoch": 0, "serial": 0}
	var observe := func(x: float, z: float) -> bool:
		counter.epoch += 1
		return model.publish_actor("P", [x, 1.0, z], counter.epoch).get("accepted", false)
	var issue := func(action: String, args: Dictionary) -> Dictionary:
		counter.serial += 1
		var wire := {"context": "belt-water-site", "client": "P", "request": "route-" + str(counter.serial), "action": action}
		wire.merge(args)
		return model.command(wire)
	var hubs: Array[String] = []
	if not expect(observe.call(0.0, 0.0), "Reach the raised machine foundations"):
		return
	if not expect(issue.call("place_foundation", {"cell": [0, 1], "level": 4}).get("accepted", false), "Place the raised collector foundation"):
		return
	if not expect(observe.call(4.95, 0.0) and issue.call("place_foundation", {"cell": [3, 1], "level": 4}).get("accepted", false), "Place the raised press foundation"):
		return
	for entry in [["wheel", -2, "x"], ["collector", 0, "z"], ["processor", 3, "z"]]:
		if not expect(observe.call(-1.65 if entry[0] == "wheel" else float(entry[1]) * 1.65, 3.3 if entry[0] == "wheel" else 0.0), "Synthetic actor reaches a machine placement"):
			return
		var args := {"kind": entry[0], "cell": [entry[1], 1], "axis": entry[2], "level": 4}
		var placed: Dictionary = issue.call("place", args)
		if not expect(placed.get("accepted", false), "Generated site admits machine: " + str(placed)):
			return
		hubs.append(placed.entity)
	if not expect(observe.call(-3.3, 0.0), "Reach input cog"):
		return
	var input: Dictionary = issue.call("place_gear", {"center": [-4, 4, 4], "axis": "x", "teeth": 4})
	if not expect(input.get("accepted", false), "Place large input cog: " + str(input)):
		return
	if not expect(observe.call(-3.3, side * 1.65), "Reach output cog"):
		return
	var output: Dictionary = issue.call("place_gear", {"center": [0, 4, 4 + side * 4], "axis": "z", "teeth": 4})
	if not expect(output.get("accepted", false), "Place large output cog: " + str(output)):
		return
	for x in [0, 4]:
		if not expect(observe.call(float(x) * 1.65 / 4.0, (4.0 + side * 8.0) * Geometry.HEIGHT_STEP - 1.65), "Reach front cog"):
			return
		var cog: Dictionary = issue.call("place_gear", {"center": [x, 4, 4 + side * 8], "axis": "z", "teeth": 2})
		if not expect(cog.get("accepted", false), "Place small cog: " + str(cog)):
			return
	for x in [4, 8, 12]:
		if not expect(observe.call(float(x) * Geometry.HEIGHT_STEP, (4.0 + side * 12.0) * Geometry.HEIGHT_STEP - 1.65), "Reach rear cog"):
			return
		var cog: Dictionary = issue.call("place_gear", {"center": [x, 4, 4 + side * 12], "axis": "z", "teeth": 2})
		if not expect(cog.get("accepted", false), "Place rear cog: " + str(cog)):
			return
	for center in [[4, 4 + side * 4], [12, 4 + side * 8], [12, 4 + side * 4]]:
		if not expect(observe.call(float(center[0]) * Geometry.HEIGHT_STEP, float(center[1]) * Geometry.HEIGHT_STEP - 1.65), "Reach the shaft between machine and cog row"):
			return
		var shaft: Dictionary = issue.call("place_shaft", {"center": [center[0], 4, center[1]], "axis": "z", "half_span": 2})
		if not expect(shaft.get("accepted", false), "Place one-tile drive shaft: " + str(shaft)):
			return
	var endpoints: Array[String] = []
	for x in [4, 8]:
		if not expect(observe.call(float(x) * Geometry.HEIGHT_STEP, 0.0), "Reach belt endpoint"):
			return
		var shaft: Dictionary = issue.call("place_shaft", {"center": [x, 4, 4], "axis": "z", "half_span": 2})
		if not expect(shaft.get("accepted", false), "Place belt endpoint shaft: " + str(shaft)):
			return
		endpoints.append(shaft.entity)
	if not expect(observe.call(2.475, 0.0), "Reach both belt endpoints"):
		return
	var belt: Dictionary = issue.call("place_belt_span", {"from": endpoints[0], "to": endpoints[1]})
	if not expect(belt.get("accepted", false), "Place physical shaft span: " + str(belt)):
		return
	if not expect(model.projection().parts.shaft == 3, "Five one-tile shafts consume the finite starter stock"):
		return
	if not expect(observe.call(-1.65, 0.0), "Observe the actual current"):
		return
	for entity in [hubs[1], endpoints[0], endpoints[1], hubs[2]]:
		var motion: Dictionary = model.projection().motion[entity]
		if not expect(motion.state == "rotating", "Generated river powers machine or belt endpoint: " + str(motion)):
			return
	var belt_motion: Dictionary = model.projection().motion[endpoints[0]]
	if not expect(belt_motion.numerator < 0 if forward else belt_motion.numerator > 0, "Belt shaft rate has the expected cargo direction: " + str(belt_motion)):
		return
	model.advance()
	if not expect(model.projection().stock.source < model.projection().initial_feed, "Collector extracts actual-site material"):
		return
	# The water's measured rate also determines press work per tick.
	for turn in range(96):
		if model.projection().stock.output > 0:
			break
		model.advance()
	if not forward:
		var reverse: Dictionary = model.projection()
		if not expect(reverse.stock.output == 0 and reverse.stock.input == 0 and reverse.stock.collector == 32,
			"Reverse belt leaves extracted blanks buffered at the collector"):
			return
		var saved_reverse: Dictionary = model.checkpoint()
		var restored = NativeModel.new("fresh-reverse-belt", ["P"])
		if not expect(restored.boot_result.get("accepted", false) and restored.restore_checkpoint(saved_reverse).get("accepted", false)
			and restored.projection().stock == reverse.stock, "Buffered reverse-route blanks survive checkpoint restore"):
			return
		if not expect(observe.call(0.0, 0.0) and issue.call("recover", {"entity": hubs[1]}).get("accepted", false),
			"Recover the blanks held at the collector"):
			return
		if not expect(model.projection().cargo.P.raw == 32, "Recovered blanks belong to the actor"):
			return
		print("native actual river belt route controls passed: ", checks)
		quit(0)
		return
	if not expect(model.projection().stock.output > 0, "The complete actual-site line produces a finished plate"):
		return
	if not expect(observe.call(4.95, 0.0 if forward else 3.3), "Reach the press for retrieval"):
		return
	for turn in range(512):
		if model.projection().inventories.P >= 4:
			break
		if model.projection().stock.output > 0:
			if not expect(issue.call("retrieve", {"entity": hubs[2], "amount": 1}).get("accepted", false), "Retrieve a produced plate"):
				return
		else:
			model.advance()
	if not expect(model.projection().inventories.P == 4, "Collect four plates through the actual-site route"):
		return
	var saved: Dictionary = model.checkpoint()
	var fresh = NativeModel.new("fresh-belt-water-site", ["P"])
	if not expect(fresh.boot_result.get("accepted", false) and fresh.restore_checkpoint(saved).get("accepted", false), "Restore actual-site route"):
		return
	var restored: Dictionary = fresh.projection()
	if not expect(fresh.checkpoint() == saved and restored.inventories.P == 4
		and restored.stock.output == 0 and not restored.actors.P.ready,
		"The fresh Host restores the exact productive line and custody without inheriting actor readiness"):
		return
	if not expect(fresh.publish_actor("P", [4.95, 1.0, 0.0], 1).get("accepted", false),
		"A new trusted actor observation readies the restored producer"):
		return
	var resumed_output := false
	for turn in range(512):
		fresh.advance()
		if fresh.projection().stock.output > 0:
			resumed_output = true
			break
	if not expect(resumed_output, "The restored river line produces a later plate through its shaft span"):
		return
	var resumed_receipt: Dictionary = fresh.command({"context": "belt-water-site", "client": "P",
		"request": "restored-product", "action": "retrieve", "entity": hubs[2], "amount": 1})
	if not expect(resumed_receipt.get("accepted", false) and fresh.projection().inventories.P == 5
		and model.checkpoint() == saved,
		"The resumed plate reaches the same actor while the original Host stays unchanged"):
		return
	if not expect(observe.call(-3.3, side * 1.65) and issue.call("remove", {"entity": output.entity}).get("accepted", false), "Remove the corner cog"):
		return
	if not expect(model.projection().motion[endpoints[0]].state != "rotating", "Removing the corner cog stops the belt"):
		return
	var host := NativeChallengeFacts.new()
	host.state = model.projection()
	var challenge = load("res://opening/upstream_drive_challenge.gd").new()
	challenge.configure(host, Vector2i(-2, 0))
	var report: Dictionary = challenge.evaluate()
	if not expect(report.phase == "move_source" and report.diagnostic_code == "relocate_wheel", "The presenter follows the authoritative upstream target: " + str(report)):
		challenge.free()
		return
	challenge.free()
	print("native actual river belt route controls passed: ", checks)
	quit(0)

func check_flow_sections() -> void:
	var sections := [
		{"name": "starting reach", "cell": [-2, 0], "level": 4, "tiles": 3},
		{"name": "broad deep reach", "cell": [-1, 13], "level": 8, "tiles": 6},
		{"name": "downstream reach", "cell": [3, 33], "level": 4, "tiles": 4},
	]
	var tangential: Array[float] = []
	for section in sections:
		var model = NativeModel.new("flow-section-" + section.name, ["P"])
		if not expect(model.boot_result.get("accepted", false), "Bind the real riverbed for " + section.name):
			return
		var x: float = float(section.cell[0]) * Geometry.PITCH
		var z: float = float(section.cell[1]) * Geometry.PITCH
		if section.tiles > 3:
			for sample in range(41):
				var span_z: float = z + (float(sample) / 40.0 * 2.0 - 1.0) * float(section.tiles) * Geometry.PITCH * 0.5
				var river_x: float = Surface.river_center_x(span_z)
				var west: float = river_x - Surface.wet_half_width(span_z, -1.0)
				var east: float = river_x + Surface.wet_half_width(span_z, 1.0)
				if not expect(x - Geometry.PITCH * 0.5 > west and x + Geometry.PITCH * 0.5 < east,
					"The larger wheel's complete one-tile-wide span stays in the wet channel at " + section.name):
					return
		if not expect(model.publish_actor("P", [x + 1.5, float(section.level) * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT, z], 1).get("accepted", false), "Reach " + section.name):
			return
		var wheel: Dictionary = model.command({"context": "flow-section-" + section.name, "client": "P", "request": "wheel", "action": "place", "kind": "wheel", "cell": section.cell, "level": section.level, "tiles": section.tiles, "axis": "x"})
		if not expect(wheel.get("accepted", false), "The real bed admits the selected wheel at " + section.name + ": " + str(wheel)):
			return
		var motion: Dictionary = model.projection().motion[wheel.entity]
		if not expect(motion.state == "rotating" and motion.numerator < 0, "Terrain descent supplies signed current at " + section.name):
			return
		tangential.append(absf(float(motion.numerator) / float(motion.denominator)) * float(section.tiles))
	if not expect(tangential[1] < tangential[2] and tangential[2] < tangential[0], "The broad reach is slower than the selected downstream and starting reaches: " + str(tangential)):
		return
	# Compare the native current in each terrain section even though the old
	# constriction wheel site requires an axle between global transmission tiles.
	# These are native water samples, not proof that a wheel fits that site.
	var water_model = NativeModel.new("flow-sample-comparison", ["P"])
	var samples := {}
	for sample: Dictionary in water_model.checkpoint().world.profile.water:
		if [sample.x, sample.z] in [[-8, 0], [-4, 52], [16, 92]]:
			samples[Vector2i(sample.x, sample.z)] = absi(sample.velocity_z)
	if not expect(samples.size() == 3 and samples[Vector2i(-4, 52)] < samples[Vector2i(-8, 0)]
		and samples[Vector2i(-8, 0)] < samples[Vector2i(16, 92)],
		"The widened starting reach flows between the broad pool and downstream constriction: " + str(samples)):
		return
	var bank = NativeModel.new("blocked-bank", ["P"])
	if not expect(bank.boot_result.get("accepted", false) and bank.publish_actor("P", [1.5, 1.0, 1.65], 1).get("accepted", false), "Bind the solid east bank"):
		return
	var blocked: Dictionary = bank.command({"context": "blocked-bank", "client": "P", "request": "wheel", "action": "place", "kind": "wheel", "cell": [0, 1], "level": 4, "tiles": 3, "axis": "x"})
	if not expect(not blocked.get("accepted", false) and blocked.get("reason") == "not_at_stream", "The actual solid bank carries no current or wheel site"):
		return
	print("native riverbed flow and wheel-size sections passed: ", checks)
	quit(0)

func check_water_native() -> void:
	var model = NativeModel.new("water-site", ["P"])
	if not expect(model.boot_result.get("accepted", false), "Native model must bind actual terrain and water: " + str(model.boot_result)):
		return
	if not expect(model.publish_actor("P", [-1.65, 1.0, 3.3], 1).get("accepted", false), "Register synthetic actor"):
		return
	var wheel := {"context": "water-site", "client": "P", "request": "wheel", "action": "place", "kind": "wheel", "cell": [-2, 1], "level": 4, "tiles": 3, "axis": "x"}
	var reply: Dictionary = model.command(wheel)
	if not expect(reply.get("accepted", false), "Actual river must admit an immersed wheel: " + str(reply)):
		return
	var id: String = reply.entity
	var motion: Dictionary = model.projection().motion[id]
	if not expect(motion.state == "rotating" and motion.numerator < 0, "Downstream current drives the wheel in the expected direction"):
		return
	var checkpoint: Dictionary = model.checkpoint()
	var restored = NativeModel.new("fresh-water-site", ["P"])
	if not expect(restored.boot_result.get("accepted", false) and restored.restore_checkpoint(checkpoint).get("accepted", false), "The actual site can restore its wheel checkpoint"):
		return
	var large = NativeModel.new("large-water-site", ["P"])
	if not expect(large.boot_result.get("accepted", false) and large.publish_actor("P", [-1.65, 3.0, 3.3], 1).get("accepted", false), "Bind the same actual site for a larger wheel"):
		return
	var big := wheel.duplicate()
	big.context = "large-water-site"
	big.request = "large-wheel"
	big.level = 8
	big.tiles = 5
	var placed: Dictionary = large.command(big)
	if not expect(placed.get("accepted", false), "The five-square wheel must clear actual terrain: " + str(placed)):
		return
	var slower: Dictionary = large.projection().motion[placed.entity]
	if not expect(slower.numerator * motion.denominator * 5 == motion.numerator * slower.denominator * 3,
		"The larger diameter reduces rotational speed in proportion to size at the same current"):
		return
	var upstream = NativeModel.new("upstream-water-site", ["P"])
	if not expect(upstream.boot_result.get("accepted", false) and upstream.publish_actor("P", [-1.65, 1.0, 1.65], 1).get("accepted", false), "Bind a synthetic actor near the upstream objective"):
		return
	var target := wheel.duplicate()
	target.context = "upstream-water-site"
	target.request = "upstream-wheel"
	target.cell = [-2, 0]
	if not expect(upstream.command(target).get("accepted", false), "The upstream objective must admit an immersed wheel in the generated site"):
		return
	var line = NativeModel.new("actual-water-line", ["P"])
	if not expect(line.boot_result.get("accepted", false) and line.publish_actor("P", [-1.65, 1.0, 3.3], 1).get("accepted", false), "Bind the actual site for a synthetic construction route"):
		return
	var base: Dictionary = line.command({"context": "actual-water-line", "client": "P", "request": "base", "action": "place_foundation", "cell": [0, 1], "level": 4})
	var line_wheel: Dictionary = line.command({"context": "actual-water-line", "client": "P", "request": "wheel", "action": "place", "kind": "wheel", "cell": [-2, 1], "level": 4, "axis": "x"})
	var collector: Dictionary = line.command({"context": "actual-water-line", "client": "P", "request": "collector", "action": "place", "kind": "collector", "cell": [0, 1], "level": 4, "axis": "x"})
	var cog: Dictionary = line.command({"context": "actual-water-line", "client": "P", "request": "cog", "action": "place_gear", "center": [-4, 4, 4], "axis": "x", "teeth": 2})
	if not expect(base.get("accepted", false) and line_wheel.get("accepted", false) and collector.get("accepted", false) and cog.get("accepted", false), "The actual worksite admits the immersed wheel, supported collector and cog"):
		return
	for link in [["shaft-a", line_wheel.entity, cog.entity], ["shaft-b", cog.entity, collector.entity]]:
		var connected := false
		for edge: Dictionary in line.projection().engagements:
			if edge.kind == 1 and ((edge.a == link[1] and edge.b == link[2]) or (edge.a == link[2] and edge.b == link[1])):
				connected = true
		if not expect(connected, "The adjacent axle faces engage without a shaft"):
			return
		if not expect(line.command({"context": "actual-water-line", "client": "P", "request": link[0], "action": "connect_drive", "from": link[1], "to": link[2]}).get("reason", "") == "individual_shaft_required", "Endpoint-created shafts remain unavailable"):
			return
	if not expect(line.projection().powered, "River current reaches the collector through the built train"):
		return
	line.advance()
	if not expect(line.projection().stock.collector == 1, "The powered collector advances material at the actual site"):
		return
	print("native water site controls passed: ", checks)
	quit(0)

func verify_water_visual(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func inspect_meshes(node: Node, parent: Transform3D, half: Vector3, axis: int, rotor: bool = false) -> void:
	var at := parent
	if node is Node3D:
		at = parent * node.transform
	if node.name == "WheelRotor":
		rotor = true
	if node is MeshInstance3D:
		for surface_index in node.mesh.get_surface_count():
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var p: Vector3 = at * vertex - Vector3.UP * Geometry.ANCHOR_HEIGHT
				verify_water_visual(absf(p.x) <= half.x + 0.0001 and absf(p.y) <= half.y + 0.0001 and absf(p.z) <= half.z + 0.0001,
					"Wheel visual exceeds its native collision envelope: " + str(node.name))
				if rotor:
					verify_water_visual(Vector2(p.y, p.z if axis == 0 else p.x).length() <= half.y + 0.0001,
						"The complete rotor must stay inside its swept circle")
	for child in node.get_children():
		inspect_meshes(child, at, half, axis, rotor)

func check_waterwheel_visual() -> void:
	for axis in [0, 2]:
		for tiles in [3, 4, 6]:
			var view := Opening.new()
			view.state = {"options": {"native": true}}
			var anchor := Node3D.new()
			view._assemble_machine(anchor, {"kind": "wheel", "axis": axis, "tiles": tiles})
			verify_water_visual(view.wheel_rotor.position == Vector3.UP * Geometry.ANCHOR_HEIGHT,
				"Every wheel center shares the shaft offset")
			inspect_meshes(anchor, Transform3D.IDENTITY, Geometry.wheel_half_extents(axis, tiles), axis)
			anchor.free()
			view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks, "scope": "wheel mesh bounds and common shaft center"}))
	quit(0 if failures == 0 else 1)
