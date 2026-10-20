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
	if "--structures-only" in OS.get_cmdline_user_args():
		check_structures()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"scope": "changed immutable support solids and rotated box contacts", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	var points := Surface.vertices()
	var faces := Surface.faces()
	verify(points.size() == 5329 and faces.size() == 31104,
		"The original 72-cell terrain lattice and triangle count are preserved.")
	verify(faces[0] == points[0] and faces[1] == points[1] and faces[2] == points[74]
		and faces[3] == points[0] and faces[4] == points[74] and faces[5] == points[73],
		"The original diagonal and clockwise render triangle ordering are preserved.")
	verify(absf(Surface.raw_height(30.0, 1.65) - 5.944855778225841) < 0.000001,
		"The original analytical terrain value remains unchanged.")
	verify(absf(Surface.height_at(30.0, 1.65) - 6.222421626752348) < 0.00001,
		"The counterexample uses the actual emitted triangle height rather than the smooth function.")
	verify(Surface.height_at(30.0, 1.65) > 1.78,
		"The fix does not hide or lower the hill to evade the original buried-capsule finding.")
	var first := points[0]
	points[0] = Vector3.ZERO
	faces[0] = Vector3.ZERO
	verify(Surface.vertex(0, 0) == first and Surface.faces()[0] == first,
		"Renderer and physics callers receive copies rather than mutable cache aliases.")
	for corner in [Vector2(-128, -128), Vector2(128, -128), Vector2(-128, 128), Vector2(128, 128)]:
		var gx := 0 if corner.x < 0 else 72
		var gz := 0 if corner.y < 0 else 72
		verify(is_equal_approx(Surface.height_at(corner.x, corner.y), Surface.vertex(gx, gz).y),
			"Closed-domain edge coordinates retain their actual endpoint height.")
	verify(is_nan(Surface.height_at(129, 0)) and is_nan(Surface.height_at(NAN, 0)),
		"An absent terrain surface is explicit instead of inventing a flat extension.")
	var panels := Surface.pad_panels()
	var flat := panels.size() == 49
	var east := false
	var west := false
	for panel in panels:
		flat = flat and is_equal_approx(panel.center.y + panel.size.y / 2.0, -0.02)
		if panel.cell == Vector2i(-1, 1):
			east = panel.center.is_equal_approx(Vector3(-1.41, -0.08, 1.65)) and panel.size.is_equal_approx(Vector3(1.13, 0.12, 1.615))
		if panel.cell == Vector2i(-2, 1):
			west = panel.center.is_equal_approx(Vector3(-3.76, -0.08, 1.65)) and panel.size.is_equal_approx(Vector3(0.69, 0.12, 1.615))
	verify(flat and east and west, "The real deck rectangles retain the flat pad and visible wharf openings.")
	# An independent geometric construction places the lower capsule sphere
	# tangent to the interior of the literal counterexample cell's triangle.
	var a := Surface.vertex(44, 36)
	var b := Surface.vertex(45, 37)
	var c := Surface.vertex(44, 37)
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
	verify(buried.valid and buried.subsurface_depth > 6.0 and buried.geometric_overlap,
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
	var wharf_count := 0
	for spec in specs:
		verify(not identities.has(spec.id), "Shared solid identities are unique: " + spec.id)
		identities[spec.id] = true
		verify(spec.center.is_finite() and spec.size.is_finite() and spec.size.x > 0.0 and spec.size.y > 0.0
			and spec.size.z > 0.0 and spec.basis.is_equal_approx(spec.basis.orthonormalized()), "Every native box descriptor is finite and rigid.")
		if spec.get("label") == "MillraceWharfBeam":
			wharf_count += 1
	verify(wharf_count == 42, "All 42 visible open-span wharf beams have actual support descriptors.")
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
