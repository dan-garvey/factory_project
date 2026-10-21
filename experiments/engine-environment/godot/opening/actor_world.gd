extends Node3D
## Native physical producer shared by offline play and the dedicated server.
## Model owns permissions/materials; the trusted caller bridges pose_published.
signal pose_published(actor: String, sample: Dictionary)
signal initialization_failed(actor: String, reason: String)

const Geometry = preload("res://opening/site_geometry.gd")
const ActorBody = preload("res://opening/actor_body.gd")
const REGISTRATION_FRAME_LIMIT := 120 # Fixture watchdog, not a game delay.
const DIAGNOSTIC_HISTORY_LIMIT := 2048 # Read-only evidence, never permission.

var model
var bodies: Dictionary = {}
var machines: Dictionary = {}
var machine_specs: Dictionary = {}
var foundations: Dictionary = {}
var foundation_specs: Dictionary = {}
var seeds: Dictionary = {}
var created_frames: Dictionary = {}
var samples: Dictionary = {}
var failures: Dictionary = {}
var control_counts: Dictionary = {}
var release_counts: Dictionary = {}
var floor_body: StaticBody3D
var site_surface
var site_bodies: Dictionary = {}
var site_specs: Dictionary = {}
var site_shapes: Dictionary = {}
var terrain_faces := PackedVector3Array()
var floor_error := ""
var observation_ordinal := 0
var sample_history: Dictionary = {}
var last_checkpoint_check: Dictionary = {}

func configure(authority) -> Dictionary:
	if model != null and model != authority:
		return {"accepted": false, "reason": "already_configured"}
	if authority == null or not authority.has_method("projection"):
		return {"accepted": false, "reason": "missing_authority"}
	var snapshot: Dictionary = authority.projection()
	if snapshot.get("options", {}).get("physical") != true or not snapshot.get("actors") is Dictionary:
		return {"accepted": false, "reason": "physical_state_required"}
	model = authority
	if is_inside_tree():
		if not _create_floor():
			return {"accepted": false, "reason": floor_error}
		return sync_topology()
	return {"accepted": true, "reason": "configured"}

func _ready() -> void:
	get_tree().physics_frame.connect(_on_native_cut)
	if model != null:
		if not _create_floor():
			for actor in model.projection().get("actors", {}):
				_fail(actor, floor_error)
			return
		sync_topology()

func _create_floor() -> bool:
	if floor_body != null:
		return true
	var native_site: bool = model.projection().get("options", {}).get("native", false) or ResourceLoader.exists("res://opening/site_surface.gd", "Script")
	if native_site:
		# Complete current captures use the same site as their renderer.
		# Historical fixed rosters retain their plane; native never falls back.
		var path := "res://opening/site_surface.gd"
		if not ResourceLoader.exists(path, "Script"):
			floor_error = "native_site_geometry_missing"
			return false
		site_surface = load(path)
		if site_surface == null:
			floor_error = "native_site_geometry_invalid"
			return false
		terrain_faces = site_surface.faces()
		# The same prepared woody triangles are visible in the ordinary scene.
		# Retain the existing sole floor body and its strict native-data guard.
		terrain_faces.append_array(site_surface.fir_collision_faces())
	floor_body = StaticBody3D.new()
	floor_body.name = "PhysicalGround"
	floor_body.collision_layer = Geometry.GROUND_LAYER
	floor_body.collision_mask = Geometry.ACTOR_LAYER
	var collider := CollisionShape3D.new()
	if native_site:
		var terrain := ConcavePolygonShape3D.new()
		terrain.backface_collision = true
		terrain.set_faces(terrain_faces)
		collider.shape = terrain
	else:
		var boundary := WorldBoundaryShape3D.new()
		boundary.plane = Plane(Vector3.UP, Geometry.GROUND_HEIGHT)
		collider.shape = boundary
	floor_body.add_child(collider)
	add_child(floor_body)
	if native_site:
		for spec in site_surface.support_boxes():
			var body := StaticBody3D.new()
			body.name = spec.id
			body.collision_layer = Geometry.GROUND_LAYER
			body.collision_mask = Geometry.ACTOR_LAYER
			body.position = spec.center
			body.basis = spec.basis
			var panel := CollisionShape3D.new()
			var rock := ConvexPolygonShape3D.new()
			rock.points = spec.points
			rock.margin = 0.0
			panel.shape = rock
			body.add_child(panel)
			site_bodies[spec.id] = body
			site_specs[spec.id] = spec.duplicate(true)
			site_shapes[spec.id] = rock
			add_child(body)
	return true

func sync_topology() -> Dictionary:
	if model == null or not is_inside_tree():
		return {"accepted": false, "reason": "not_configured"}
	var snapshot: Dictionary = model.projection()
	var entities: Dictionary = snapshot.get("entities", {})
	for entity in machines.keys():
		if not entities.has(entity) or machine_specs[entity] != entities[entity]:
			var old: StaticBody3D = machines[entity]
			remove_child(old)
			old.queue_free()
			machines.erase(entity)
			machine_specs.erase(entity)
	for entity in entities:
		if machines.has(entity):
			continue
		var anchor: Array = Geometry.work_anchor(entities[entity].get("cell", []))
		if anchor.size() != 3:
			return {"accepted": false, "reason": "invalid_topology"}
		var body := StaticBody3D.new()
		body.set_meta("entity", entity)
		body.collision_layer = Geometry.MACHINE_LAYER
		body.collision_mask = Geometry.ACTOR_LAYER
		var wheel: bool = entities[entity].get("kind") == "wheel" and snapshot.get("options", {}).get("native", false)
		body.position = Vector3(anchor[0], (Geometry.ANCHOR_HEIGHT if wheel else Geometry.MACHINE_CENTER_HEIGHT) + float(entities[entity].get("level", 0)) * Geometry.HEIGHT_STEP, anchor[2])
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Geometry.wheel_half_extents(int(entities[entity].get("axis", 0)), int(entities[entity].get("tiles", 3))) * 2.0 if wheel else Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])
		collider.shape = box
		body.add_child(collider)
		machines[entity] = body
		machine_specs[entity] = entities[entity].duplicate(true)
		add_child(body)
	var surfaces: Dictionary = snapshot.get("foundations", {})
	for id in foundations.keys():
		if not surfaces.has(id) or foundation_specs[id] != surfaces[id]:
			var old: StaticBody3D = foundations[id]
			remove_child(old)
			old.queue_free()
			foundations.erase(id)
			foundation_specs.erase(id)
	for id in surfaces:
		if foundations.has(id):
			continue
		var spec: Dictionary = surfaces[id]
		var body := StaticBody3D.new()
		body.name = "Foundation_" + str(id)
		body.set_meta("foundation", id)
		body.collision_layer = Geometry.GROUND_LAYER
		body.collision_mask = Geometry.ACTOR_LAYER
		body.position = Vector3(spec.cell[0] * Geometry.PITCH, float(spec.level) * Geometry.HEIGHT_STEP - Geometry.FOUNDATION_DEPTH / 2.0, spec.cell[1] * Geometry.PITCH)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH)
		collider.shape = shape
		body.add_child(collider)
		foundations[id] = body
		foundation_specs[id] = spec.duplicate(true)
		add_child(body)
	return {"accepted": true, "reason": "topology_synchronized"}

func ensure_actor(actor: String) -> Dictionary:
	if model == null or not is_inside_tree():
		return {"accepted": false, "reason": "not_configured"}
	if not floor_error.is_empty():
		return _fail(actor, floor_error)
	if failures.has(actor):
		return {"accepted": false, "reason": failures[actor]}
	if bodies.has(actor):
		if bodies[actor].motion_enabled:
			_publish_existing(actor, "admission")
		return {"accepted": not failures.has(actor), "ready": bodies[actor].motion_enabled,
			"reason": "actor_ready" if bodies[actor].motion_enabled else "actor_initializing"}
	var actors: Dictionary = model.projection().get("actors", {})
	if not actors.has(actor) or not Geometry.valid_position(actors[actor].get("position")):
		return _fail(actor, "missing_actor_seed")
	var seed: Array = actors[actor].position.duplicate()
	seeds[actor] = seed
	var at := Vector3(float(seed[0]), float(seed[1]), float(seed[2]))
	if not at.is_finite() or not _same_position(_array(at), seed):
		return _fail(actor, "actor_position_unrepresentable")
	var body = ActorBody.new()
	body.name = "Actor" + actor
	body.set_meta("actor", actor)
	body.position = at
	bodies[actor] = body
	created_frames[actor] = Engine.get_physics_frames()
	control_counts[actor] = 0
	release_counts[actor] = 0
	add_child(body)
	return {"accepted": true, "ready": false, "reason": "actor_initializing"}

func set_control(actor: String, world_xz, jump) -> Dictionary:
	if not world_xz is Vector2 or not jump is bool or not world_xz.is_finite() or absf(world_xz.x) > 1.0 or absf(world_xz.y) > 1.0:
		return {"accepted": false, "reason": "invalid_control"}
	if not bodies.has(actor) or not bodies[actor].motion_enabled or failures.has(actor):
		return {"accepted": false, "reason": "actor_unready"}
	bodies[actor].set_control(world_xz, jump)
	control_counts[actor] += 1
	return {"accepted": true, "reason": "control_received"}

func release_control(actor: String) -> void:
	if bodies.has(actor):
		bodies[actor].release_control()
		release_counts[actor] += 1

func _same_position(a: Array, b: Array) -> bool:
	for axis in range(3):
		if absf(float(a[axis]) - float(b[axis])) > Geometry.NATIVE_POSE_EPSILON:
			return false
	return true

func _array(at: Vector3) -> Array:
	return [at.x, at.y, at.z]

func _geometry_registered() -> bool:
	if floor_body == null or global_transform != Transform3D.IDENTITY:
		return false
	var space: RID = get_world_3d().space
	for id in foundations:
		var body: StaticBody3D = foundations[id]
		var rid: RID = body.get_rid()
		var spec: Dictionary = foundation_specs[id]
		var expected := Vector3(spec.cell[0] * Geometry.PITCH, float(spec.level) * Geometry.HEIGHT_STEP - Geometry.FOUNDATION_DEPTH / 2.0, spec.cell[1] * Geometry.PITCH)
		var pose: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
		if PhysicsServer3D.body_get_space(rid) != space or PhysicsServer3D.body_get_shape_count(rid) != 1 or PhysicsServer3D.body_get_collision_layer(rid) != Geometry.GROUND_LAYER:
			return false
		if pose.basis != Basis.IDENTITY or pose.origin.distance_to(expected) > Geometry.NATIVE_POSE_EPSILON or body.position.distance_to(expected) > Geometry.NATIVE_POSE_EPSILON:
			return false
		if PhysicsServer3D.body_get_shape_transform(rid, 0) != Transform3D.IDENTITY:
			return false
		var data = PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(rid, 0))
		if not data is Vector3 or data.distance_to(Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH) / 2.0) > Geometry.NATIVE_POSE_EPSILON:
			return false
	var expected_half := Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2]) / 2
	for body in [floor_body] + machines.values():
		var rid: RID = body.get_rid()
		if PhysicsServer3D.body_get_space(rid) != space or PhysicsServer3D.body_get_shape_count(rid) != 1:
			return false
		var at: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
		if at.basis != Basis.IDENTITY or not _same_position(_array(at.origin), _array(body.global_position)):
			return false
		if PhysicsServer3D.body_get_shape_transform(rid, 0) != Transform3D.IDENTITY:
			return false
		var data = PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(rid, 0))
		if body == floor_body:
			# Shared terrain/wood vertices are already in world coordinates.
			# Matching a shifted native body to a shifted node is insufficient.
			if at != Transform3D.IDENTITY or floor_body.transform != Transform3D.IDENTITY:
				return false
			if PhysicsServer3D.body_get_collision_layer(rid) != Geometry.GROUND_LAYER:
				return false
			if site_surface != null:
				if not data is Dictionary or data.get("faces") != terrain_faces or data.get("backface_collision") != true:
					return false
			else:
				if not data is Plane or data.normal.distance_to(Vector3.UP) > Geometry.NATIVE_POSE_EPSILON or absf(data.d - Geometry.GROUND_HEIGHT) > Geometry.NATIVE_POSE_EPSILON:
					return false
		else:
			var id: String = str(body.get_meta("entity", ""))
			var spec: Dictionary = machine_specs.get(id, {})
			var half := expected_half
			if spec.get("kind") == "wheel" and site_surface != null:
				half = Geometry.wheel_half_extents(int(spec.get("axis", 0)), int(spec.get("tiles", 3)))
			if PhysicsServer3D.body_get_collision_layer(rid) != Geometry.MACHINE_LAYER or not data is Vector3 or data.distance_to(half) > Geometry.NATIVE_POSE_EPSILON:
				return false
	for id in site_bodies:
		var body: StaticBody3D = site_bodies[id]
		var rid: RID = body.get_rid()
		if PhysicsServer3D.body_get_space(rid) != space or PhysicsServer3D.body_get_shape_count(rid) != 1 or PhysicsServer3D.body_get_collision_layer(rid) != Geometry.GROUND_LAYER:
			return false
		var at: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
		if not at.basis.is_equal_approx(site_specs[id].basis) or not _same_position(_array(at.origin), _array(site_specs[id].center)) or PhysicsServer3D.body_get_shape_transform(rid, 0) != Transform3D.IDENTITY:
			return false
		var shape_rid: RID = PhysicsServer3D.body_get_shape(rid, 0)
		var data: Variant = PhysicsServer3D.shape_get_data(shape_rid)
		var expected: PackedVector3Array = site_specs[id].points
		if PhysicsServer3D.shape_get_type(shape_rid) != PhysicsServer3D.SHAPE_CONVEX_POLYGON \
			or not data is PackedVector3Array or site_shapes[id].get_rid() != shape_rid \
			or site_shapes[id].points != expected or site_shapes[id].margin != 0.0:
			return false
		if site_surface.match_native_rock(data, expected).is_empty():
			return false
	return true

func _read_actor(actor: String, cut: String) -> Dictionary:
	var body = bodies[actor]
	var rid: RID = body.get_rid()
	var space: RID = get_world_3d().space
	var at: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var shape_rid := RID()
	var shape_data = null
	if PhysicsServer3D.body_get_shape_count(rid) == 1:
		shape_rid = PhysicsServer3D.body_get_shape(rid, 0)
		shape_data = PhysicsServer3D.shape_get_data(shape_rid)
	var registered: bool = PhysicsServer3D.body_get_space(rid) == space and shape_rid == body.capsule.get_rid()
	registered = registered and PhysicsServer3D.body_get_collision_layer(rid) == Geometry.ACTOR_LAYER
	registered = registered and at.basis.y == Vector3.UP
	if shape_rid.is_valid():
		registered = registered and PhysicsServer3D.body_get_shape_transform(rid, 0) == Transform3D.IDENTITY
	registered = registered and shape_data is Dictionary
	if registered:
		registered = absf(float(shape_data.get("radius", -1)) - Geometry.CAPSULE_RADIUS) <= Geometry.NATIVE_POSE_EPSILON and absf(float(shape_data.get("height", -1)) - Geometry.CAPSULE_HEIGHT) <= Geometry.NATIVE_POSE_EPSILON
	observation_ordinal += 1
	return {"position": _array(at.origin), "ready": body.motion_enabled and registered,
		"registered": registered, "native_epoch": observation_ordinal,
		"physics_frame": Engine.get_physics_frames(), "cut": cut,
		"body_id": body.get_instance_id(), "rid": rid.get_id(),
		"space": PhysicsServer3D.body_get_space(rid).get_id(), "expected_space": space.get_id(),
		"shape_rid": shape_rid.get_id(), "shape_data": shape_data,
		"basis": [_array(at.basis.x), _array(at.basis.y), _array(at.basis.z)],
		"node_position": _array(body.global_position), "seed": seeds[actor].duplicate(),
		"body_ticks": body.ticks, "floor_id": body.floor_id, "on_floor": body.is_on_floor(),
		"control": [body.direction.x, body.direction.y], "jump_queued": body.jump_requested,
		"controls": control_counts[actor], "releases": release_counts[actor]}

func _initial_overlaps(actor: String) -> Array:
	var body = bodies[actor]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body.capsule
	query.transform = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	query.margin = 0.0
	query.collision_mask = Geometry.GROUND_LAYER | Geometry.MACHINE_LAYER
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [body.get_rid()]
	var hits: Array = get_world_3d().direct_space_state.intersect_shape(query, 32)
	var result: Array = []
	var terrain_hit := false
	for hit in hits:
		var measured := _penetration(actor, hit.rid)
		terrain_hit = terrain_hit or hit.rid == floor_body.get_rid()
		measured.merge({"rid": hit.rid.get_id(), "collider_id": hit.collider_id, "shape": hit.shape, "native_query_hit": true})
		result.append(measured)
	if site_surface != null:
		if hits.size() == 32:
			result.append({"unsupported_overlap": true, "kind": "site_contact_query_limit", "native_query_hit": false})
		if not terrain_hit:
			# A trimesh query cannot see a capsule wholly below its hollow
			# surface. Label this guard separately from genuine native hits.
			var below := _penetration(actor, floor_body.get_rid())
			if below.get("geometric_overlap", false):
				below.merge({"rid": floor_body.get_rid().get_id(), "native_query_hit": false,
					"analytical_burial_guard": true})
				result.append(below)
	return result

func _penetration(actor: String, other: RID) -> Dictionary:
	# Keep every native query hit. This is an analytical overlap measure for
	# the actual upright capsule and registered solids, not native contact depth.
	# The existing motor safe margin bounds numerical contact acceptance;
	# it never changes the Model's exact construction-reach sphere.
	var body = bodies[actor]
	var at: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var capsule: Dictionary = PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(body.get_rid(), 0))
	var target: Transform3D = PhysicsServer3D.body_get_state(other, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var shape = PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(other, 0))
	if other == floor_body.get_rid() and site_surface != null:
		var measured: Dictionary = site_surface.capsule_overlap(at.origin, float(capsule.radius), float(capsule.height))
		measured.merge({"unsupported_overlap": measured.analytical_overlap_measure > Geometry.SAFE_MARGIN,
			"contact_tolerance": Geometry.SAFE_MARGIN, "kind": "terrain", "actor_position": _array(at.origin)})
		return measured
	if other == floor_body.get_rid() and shape is Plane:
		var gap: float = at.origin.y - float(capsule.height) / 2.0 - target.origin.y - shape.d
		return {"unsupported_overlap": gap < -Geometry.SAFE_MARGIN,
			"geometric_overlap": gap < 0.0, "contact_tolerance": Geometry.SAFE_MARGIN,
			"kind": "floor", "gap": gap, "analytical_overlap_measure": maxf(-gap, 0.0),
			"actor_position": _array(at.origin), "height": capsule.height, "floor_height": target.origin.y + shape.d}
	var owned := false
	for machine in machines.values():
		owned = owned or machine.get_rid() == other
	var foundation_owned := false
	for foundation in foundations.values():
		foundation_owned = foundation_owned or foundation.get_rid() == other
	owned = owned or foundation_owned
	var site_owned := false
	var site_id := ""
	for id in site_bodies:
		if site_bodies[id].get_rid() == other:
			site_owned = true
			site_id = id
	owned = owned or site_owned
	if site_owned:
		var expected: PackedVector3Array = site_specs[site_id].points
		if not shape is PackedVector3Array:
			return {"unsupported_overlap": true, "kind": "unexpected_site_solid"}
		var actual: PackedVector3Array = site_surface.match_native_rock(shape, expected)
		if actual.is_empty():
			return {"unsupported_overlap": true, "kind": "changed_site_solid"}
		var native_faces: PackedVector3Array = site_surface.rock_faces_for_vertices(actual)
		var overlap: float = site_surface.capsule_convex_overlap(at.origin, float(capsule.radius),
			float(capsule.height), target, native_faces)
		return {"unsupported_overlap": overlap > Geometry.SAFE_MARGIN, "geometric_overlap": overlap > 0.0,
			"analytical_overlap_measure": overlap, "contact_tolerance": Geometry.SAFE_MARGIN,
			"kind": "site_convex_rock", "actor_position": _array(at.origin), "site_position": _array(target.origin),
			"site_vertices": shape.size(), "site_basis": [_array(target.basis.x), _array(target.basis.y), _array(target.basis.z)]}
	if owned and shape is Vector3 and target.basis == Basis.IDENTITY:
		var radius: float = capsule.radius
		var segment_half: float = float(capsule.height) / 2.0 - radius
		var dx := maxf(absf(float(at.origin.x) - float(target.origin.x)) - float(shape.x), 0.0)
		var dz := maxf(absf(float(at.origin.z) - float(target.origin.z)) - float(shape.z), 0.0)
		var below: float = float(target.origin.y) - float(shape.y) - (float(at.origin.y) + segment_half)
		var above: float = float(at.origin.y) - segment_half - (float(target.origin.y) + float(shape.y))
		var dy := maxf(maxf(below, above), 0.0)
		var distance_squared := dx * dx + dy * dy + dz * dz
		var overlap_measure := maxf(radius - sqrt(distance_squared), 0.0)
		return {"unsupported_overlap": overlap_measure > Geometry.SAFE_MARGIN,
			"geometric_overlap": distance_squared < radius * radius,
			"contact_tolerance": Geometry.SAFE_MARGIN, "analytical_overlap_measure": overlap_measure,
			"kind": "foundation" if foundation_owned else "site_panel" if site_owned else "machine",
			"distance_squared": distance_squared, "radius_squared": radius * radius,
			"actor_position": _array(at.origin), "radius": radius, "height": capsule.height,
			"machine_position": _array(target.origin), "machine_half_extents": _array(shape)}
	return {"unsupported_overlap": true, "kind": "unexpected_solid"}

func _on_native_cut() -> void:
	if model == null or not is_inside_tree():
		return
	var topology := sync_topology()
	if not topology.accepted:
		for actor in bodies.keys():
			_fail(actor, "actor_topology_invalid")
		return
	for actor in bodies.keys():
		if failures.has(actor):
			continue
		if bodies[actor].motion_enabled:
			_publish_existing(actor, "physics_boundary")
			continue
		var sample := _read_actor(actor, "initial_physics_boundary")
		samples[actor] = sample
		if Engine.get_physics_frames() <= created_frames[actor]:
			continue
		if not _geometry_registered() or not sample.registered or not _same_position(sample.position, seeds[actor]):
			if Engine.get_physics_frames() - created_frames[actor] > REGISTRATION_FRAME_LIMIT:
				_fail(actor, "actor_native_registration_failed")
			continue
		var contacts := _initial_overlaps(actor)
		var penetrations: Array = contacts.filter(func(hit: Dictionary): return hit.unsupported_overlap)
		sample["initial_contacts"] = contacts
		sample["initial_overlaps"] = penetrations
		if not penetrations.is_empty():
			_fail(actor, "actor_saved_pose_overlaps")
			continue
		bodies[actor].motion_enabled = true
		sample.ready = true
		samples[actor] = sample
		_remember(actor, sample)
		pose_published.emit(actor, sample.duplicate(true))
		if not _bridge_current(actor, sample):
			_fail(actor, "actor_bridge_failed")

func _publish_existing(actor: String, cut: String) -> void:
	var sample := _read_actor(actor, cut)
	samples[actor] = sample
	if not sample.registered or not Geometry.valid_position(sample.position):
		_fail(actor, "actor_native_state_lost")
		return
	_remember(actor, sample)
	pose_published.emit(actor, sample.duplicate(true))
	if not _bridge_current(actor, sample):
		_fail(actor, "actor_bridge_failed")

func _bridge_current(actor: String, sample: Dictionary) -> bool:
	var current: Dictionary = model.projection().get("actors", {}).get(actor, {})
	return current.get("ready", false) and current.get("native_epoch", -1) == sample.native_epoch and current.get("position", []) == sample.position

func checkpoint_status() -> Dictionary:
	# Validate a current native cut before the caller writes any checkpoint.
	# This never moves/depenetrates a body or changes material/build state.
	last_checkpoint_check = {"accepted": false, "reason": "actor_geometry_pending", "actors": {}}
	if model == null or not is_inside_tree():
		return last_checkpoint_check.duplicate(true)
	var topology := sync_topology()
	if not topology.accepted or not _geometry_registered():
		return last_checkpoint_check.duplicate(true)
	for actor in model.projection().get("actors", {}):
		if not bodies.has(actor) or not bodies[actor].motion_enabled or failures.has(actor):
			last_checkpoint_check.reason = "actor_unready"
			return last_checkpoint_check.duplicate(true)
		var sample := _read_actor(actor, "checkpoint")
		if not sample.registered or not Geometry.valid_position(sample.position):
			last_checkpoint_check.reason = "actor_native_state_lost"
			return last_checkpoint_check.duplicate(true)
		var contacts := _initial_overlaps(actor)
		sample["checkpoint_contacts"] = contacts
		var unsupported: bool = contacts.any(func(hit: Dictionary): return hit.unsupported_overlap)
		sample["checkpoint_supported"] = not unsupported
		samples[actor] = sample
		_remember(actor, sample)
		pose_published.emit(actor, sample.duplicate(true))
		last_checkpoint_check.actors[actor] = sample.duplicate(true)
		if not _bridge_current(actor, sample):
			last_checkpoint_check.reason = "actor_bridge_failed"
			return last_checkpoint_check.duplicate(true)
		if unsupported:
			last_checkpoint_check.reason = "actor_pose_not_settled"
			return last_checkpoint_check.duplicate(true)
	last_checkpoint_check.accepted = true
	last_checkpoint_check.reason = "native_checkpoint_ready"
	return last_checkpoint_check.duplicate(true)

func _remember(actor: String, sample: Dictionary) -> void:
	sample_history[sample.native_epoch] = {"actor": actor, "sample": sample.duplicate(true)}
	while sample_history.size() > DIAGNOSTIC_HISTORY_LIMIT:
		sample_history.erase(sample_history.keys()[0])

func _fail(actor: String, reason: String) -> Dictionary:
	if not failures.has(actor):
		failures[actor] = reason
		if bodies.has(actor):
			bodies[actor].motion_enabled = false
			bodies[actor].release_control()
		initialization_failed.emit(actor, reason)
	return {"accepted": false, "ready": false, "reason": reason}

func diagnostics(actor: String = "", native_epoch: int = -1) -> Dictionary:
	if native_epoch >= 0:
		if not sample_history.has(native_epoch) or sample_history[native_epoch].actor != actor:
			return {"available": false, "reason": "native_sample_not_retained", "native_epoch": native_epoch}
		return {"available": true, "actor": actor, "sample": sample_history[native_epoch].sample.duplicate(true)}
	if not actor.is_empty():
		return {"sample": samples.get(actor, {}).duplicate(true),
			"declared_seed": seeds.get(actor, []).duplicate(),
			"failure": failures.get(actor, ""), "controls": control_counts.get(actor, 0),
			"releases": release_counts.get(actor, 0)}
	return {"samples": samples.duplicate(true), "failures": failures.duplicate(true),
		"last_checkpoint_check": last_checkpoint_check.duplicate(true),
		"retained_native_samples": sample_history.size(), "diagnostic_history_limit": DIAGNOSTIC_HISTORY_LIMIT,
		"physics_engine_setting": ProjectSettings.get_setting("physics/3d/physics_engine", ""),
		"world_boundary_size_setting": ProjectSettings.get_setting("physics/jolt_physics_3d/limits/world_boundary_shape_size", null),
		"native_epoch": observation_ordinal, "floor_rid": floor_body.get_rid().get_id() if floor_body != null else 0}
