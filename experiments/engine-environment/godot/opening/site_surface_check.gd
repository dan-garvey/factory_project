extends SceneTree
## Adapter geometry checks only; no Model, bodies, game or desktop starts.
const Surface = preload("res://opening/site_surface.gd")
const ActorWorld = preload("res://opening/actor_world.gd")
var checks := 0
var failed := false

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
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
				"The emitted natural clearing supports the existing character and construction anchors.")
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
	verify(specs.size() == 64, "Only the real natural rock obstacles remain in the box catalogue.")
	for spec in specs:
		verify(not identities.has(spec.id), "Shared solid identities are unique: " + spec.id)
		identities[spec.id] = true
		verify(spec.center.is_finite() and spec.size.is_finite() and spec.size.x > 0.0 and spec.size.y > 0.0
			and spec.size.z > 0.0 and spec.basis.is_equal_approx(spec.basis.orthonormalized()), "Every native box descriptor is finite and rigid.")
		verify(spec.get("finish", "stone") in ["stone", "dark_stone"],
			"Solid canyon descriptors use natural stone finishes rather than timber or iron: " + spec.id)
		verify(spec.id.begins_with("rock_"), "No invisible old canal, platform or seam barrier survives.")
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
	verify(points.size() == 12 and faces.size() == 60, "The shared natural solid has twelve vertices and twenty complete facets.")
	var edges := {}
	for point in points:
		verify(point.is_finite() and absf(point.x) <= Surface.ROCK_SIZE.x / 2.0
			and absf(point.y) <= Surface.ROCK_SIZE.y / 2.0 and absf(point.z) <= Surface.ROCK_SIZE.z / 2.0,
			"The true hull stays inside its unchanged conservative foliage envelope.")
	for first in range(0, faces.size(), 3):
		var a := faces[first]
		var b := faces[first + 1]
		var c := faces[first + 2]
		var normal := (c - a).cross(b - a).normalized()
		verify(normal.is_finite() and normal.dot(a) > 0.0, "Every visible facet faces out from the enclosed origin.")
		for point in points:
			verify(normal.dot(point - a) < 0.000001, "Each facet bounds the same convex hull used by the physics server.")
		for pair in [[a, b], [b, c], [c, a]]:
			var start := points.find(pair[0])
			var end := points.find(pair[1])
			verify(start >= 0 and end >= 0 and start != end, "Every facet edge joins actual distinct native vertices.")
			var key := "%d:%d" % [mini(start, end), maxi(start, end)]
			var entry: Vector2i = edges.get(key, Vector2i.ZERO)
			edges[key] = entry + Vector2i(1, 1 if start < end else -1)
	verify(edges.size() == 30, "The convex surface has the expected closed Euler relation.")
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
		verify(spec.points.size() == 12 and spec.faces.size() == 60,
			"Every instance carries the actual scaled hull, distinct from its clearance envelope.")
	points[0] = Vector3(999, 999, 999)
	faces[0] = Vector3(999, 999, 999)
	specs[0].points[0] = Vector3(999, 999, 999)
	verify(Surface.rock_vertices()[0].x < 1 and Surface.rock_faces()[0].x < 1
		and Surface.rock_boxes()[0].points[0].x < 1, "Callers cannot mutate the shared template or later native descriptors.")
	verify(is_inf(Surface.capsule_convex_overlap(Vector3(NAN, 0, 0), 0.3, 1.8, Transform3D.IDENTITY, Surface.rock_faces()))
		and is_inf(Surface.capsule_convex_overlap(Vector3.ZERO, 0.3, 1.8, Transform3D.IDENTITY, PackedVector3Array())),
		"Invalid contact inputs fail closed.")

func check_native_hull_matching() -> void:
	var source := Surface.rock_vertices()
	var reordered := source.duplicate()
	reordered.reverse()
	verify(Surface.match_native_rock(reordered, source) == source,
		"Native point ordering does not change the source vertex correspondence.")
	var changed := source.duplicate()
	changed[0] += Vector3.ONE * 0.00002
	verify(Surface.match_native_rock(changed, source).size() == 12,
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
	verify(Surface.rock_faces_for_vertices(source) == Surface.rock_faces(), "Mapped native vertices preserve the exact shared facet topology.")
