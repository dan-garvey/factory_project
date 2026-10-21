extends SceneTree
## Isolated native capsule sweeps against the ordinary site's registered rocks.
## No game authority, movement input, renderer, desktop or saved world is used.
const Site = preload("res://opening/actor_world.gd")
const Body = preload("res://opening/actor_body.gd")
const Surface = preload("res://opening/site_surface.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const CONTACT_TOLERANCE := 0.004

class EmptySite extends RefCounted:
	func projection() -> Dictionary:
		return {"options": {"native": true, "physical": true}, "actors": {}, "entities": {}}

var checks := 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var dimensions: Dictionary = {}
var output := ""
var registration_only := false
var registration: Array[Dictionary] = []
var site
var capsule

func verify(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		if failures.size() <= 8:
			push_error(message)
	return condition

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--result="):
			output = argument.trim_prefix("--result=")
		elif argument == "--registration-only":
			registration_only = true
	call_deferred("run")

func finish() -> void:
	if site != null:
		site.free()
	var facts := {"status": "pass" if failures.is_empty() else "fail", "checks": checks,
		"failures": failures, "sweeps": observations, "capsule_dimensions": dimensions,
		"registration": registration,
		"scope": "Native capsule queries against all 64 ordinary registered convex rocks",
		"exclusions": "Each query isolates its target rock by excluding the ground and other supports.",
		"desktop": "not_used", "game_authority": "not_started", "human_play": "not_run"}
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			push_error("Cannot retain the rock contact result.")
			quit(2)
			return
		file.store_string(JSON.stringify(facts, "  ") + "\n")
		file.close()
	print(JSON.stringify({"status": facts.status, "checks": checks, "sweeps": observations.size()}))
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	site = Site.new()
	site.model = EmptySite.new()
	root.add_child(site)
	capsule = Body.new()
	capsule.position = Vector3(0, 100, 0)
	site.add_child(capsule)
	await physics_frame
	await physics_frame
	verify(site.floor_error.is_empty() and site.floor_body != null,
		"The ordinary ActorWorld creates its shared site without a game authority.")
	verify(not capsule.motion_enabled and site.bodies.is_empty(),
		"The fixture starts no gameplay movement producer or actor permission binding.")
	# Godot's native shape stores real_t dimensions as binary32. Match that
	# exact representation rather than comparing it with a binary64 literal.
	var native_dimensions := PackedFloat32Array([Geometry.CAPSULE_RADIUS, Geometry.CAPSULE_HEIGHT])
	dimensions = {"radius": capsule.capsule.radius, "height": capsule.capsule.height,
		"expected_radius": native_dimensions[0], "expected_height": native_dimensions[1]}
	verify(capsule.capsule.radius == native_dimensions[0]
		and capsule.capsule.height == native_dimensions[1]
		and capsule.collision_mask == (Geometry.GROUND_LAYER | Geometry.MACHINE_LAYER),
		"Sweeps use the unchanged ordinary capsule and collision mask.")
	var rocks := Surface.rock_boxes()
	verify(rocks.size() == 64, "All authored outcrops are covered.")
	verify(site._geometry_registered(), "The ordinary producer binds the actual convex shape data before contact checks.")
	if registration_only:
		for spec in rocks:
			var target: StaticBody3D = site.site_bodies[spec.id]
			var shape_rid: RID = PhysicsServer3D.body_get_shape(target.get_rid(), 0)
			var data: Variant = PhysicsServer3D.shape_get_data(shape_rid)
			var entry := {"rock": spec.id, "shape_type": PhysicsServer3D.shape_get_type(shape_rid),
				"data_type": typeof(data), "expected_vertices": spec.points.size()}
			if data is PackedVector3Array:
				entry.actual_vertices = data.size()
				entry.maximum_nearest_distance = 0.0
				entry.exact_matches = 0
				for point in spec.points:
					entry.exact_matches += 1 if data.has(point) else 0
					var distance := INF
					for actual in data:
						distance = minf(distance, point.distance_to(actual))
					entry.maximum_nearest_distance = maxf(entry.maximum_nearest_distance, distance)
				if registration.is_empty():
					entry.actual_points = []
					entry.expected_points = []
					for point in data:
						entry.actual_points.append([point.x, point.y, point.z])
					for point in spec.points:
						entry.expected_points.append([point.x, point.y, point.z])
			registration.append(entry)
		finish()
		return
	for spec in rocks:
		if not verify(site.site_bodies.has(spec.id), "The native site registers " + spec.id):
			continue
		var target: StaticBody3D = site.site_bodies[spec.id]
		var target_rid := target.get_rid()
		var shape_rid: RID = PhysicsServer3D.body_get_shape(target_rid, 0)
		var points: PackedVector3Array = PhysicsServer3D.shape_get_data(shape_rid)
		var native_points := Surface.match_native_rock(points, spec.points)
		verify(target.global_transform.is_equal_approx(Transform3D(spec.basis, spec.center))
			and PhysicsServer3D.shape_get_type(shape_rid) == PhysicsServer3D.SHAPE_CONVEX_POLYGON
			and native_points.size() == spec.points.size(), "Native transforms, hull type and documented cooked vertices match: " + spec.id)
		var native_faces := Surface.rock_faces_for_vertices(native_points)
		var exclusions: Array[RID] = [site.floor_body.get_rid()]
		for id in site.site_bodies:
			if id != spec.id:
				exclusions.append(site.site_bodies[id].get_rid())
		for outward in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3.UP]:
			var parameters := PhysicsTestMotionParameters3D.new()
			var distance: float = spec.size.length() + Geometry.CAPSULE_HEIGHT + 1.0
			parameters.from = Transform3D(Basis.IDENTITY, spec.center + outward * distance)
			parameters.motion = -outward * distance
			parameters.margin = Geometry.SAFE_MARGIN
			parameters.exclude_bodies = exclusions
			var result := PhysicsTestMotionResult3D.new()
			var hit := PhysicsServer3D.body_test_motion(capsule.get_rid(), parameters, result)
			if not verify(hit and result.get_collision_count() > 0, "The capsule cannot cross " + spec.id):
				continue
			verify(result.get_collider_rid() == target_rid
				and result.get_travel().length() > 0.0 and result.get_collision_safe_fraction() < 1.0,
				"The intended rock stops a nonzero approach before its center: " + spec.id)
			var stopped: Vector3 = parameters.from.origin + result.get_travel()
			var penetration := Surface.capsule_convex_overlap(stopped, Geometry.CAPSULE_RADIUS,
				Geometry.CAPSULE_HEIGHT, Transform3D(spec.basis, spec.center), native_faces)
			verify(penetration <= CONTACT_TOLERANCE,
				"The stopped capsule remains outside the rock interior: " + spec.id)
			observations.append({"rock": spec.id, "approach": [outward.x, outward.y, outward.z],
				"safe_fraction": result.get_collision_safe_fraction(), "penetration": penetration})
			# Discriminating control: the same path must be clear when its sole
			# remaining physical obstacle is explicitly excluded from this query.
			if outward == Vector3.UP:
				var all_excluded := exclusions.duplicate()
				all_excluded.append(target_rid)
				parameters.exclude_bodies = all_excluded
				verify(not PhysicsServer3D.body_test_motion(capsule.get_rid(), parameters),
					"Removing only the target from the query removes the contact: " + spec.id)
		# This line lies inside the former box's X/Z corner but outside the
		# visible hull. A hidden surrounding box would produce a false hit.
		var transform := Transform3D(spec.basis, spec.center)
		var corner := Vector3(spec.size.x * 0.45, spec.size.y * 2.0, spec.size.z * 0.45)
		var ray := PhysicsRayQueryParameters3D.create(transform * corner,
			transform * Vector3(corner.x, -corner.y, corner.z), Geometry.GROUND_LAYER, exclusions)
		verify(site.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),
			"The old box corner remains truly empty in native physics: " + spec.id)
		var inside := PhysicsShapeQueryParameters3D.new()
		inside.shape = capsule.capsule
		inside.transform = Transform3D(Basis.IDENTITY, spec.center)
		inside.collision_mask = Geometry.GROUND_LAYER
		inside.exclude = exclusions
		var interior: Array = site.get_world_3d().direct_space_state.intersect_shape(inside, 2)
		verify(interior.size() == 1 and interior[0].rid == target_rid
			and Surface.capsule_convex_overlap(spec.center, Geometry.CAPSULE_RADIUS,
				Geometry.CAPSULE_HEIGHT, transform, native_faces) > 0.29,
			"The real solid and analytical guard both detect a capsule through its interior: " + spec.id)
	verify(observations.size() == 320, "Five complete approaches cover every rock.")
	finish()
