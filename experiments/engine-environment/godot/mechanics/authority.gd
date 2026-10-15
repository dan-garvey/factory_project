extends Node3D
## The sole mechanism-state and native physics-query owner for this fixture.
## No items, opening recipes, network replicas or persistence state live here.

signal advanced(outcome: Dictionary)

const INPUT_STEP := PI / 8.0
const SPAN := 2.0
const BODY_SIZE := Vector3(0.55, 0.8, 0.8)
const HEIGHT := 0.75
const ALIGN_EPSILON := 0.00001

var running := false
var coupled := true
var idler := true
var driven_teeth := 40
var source_phase := 0.0
var phases := {"B": 0.0, "U": 0.0}
var mounts := {"B": [0, 0], "U": [0, 3]}
var bodies: Dictionary = {}
var obstacle: StaticBody3D
var target: Area3D
var obstacle_active := false
var pending := false
var completion: Dictionary = {}
var geometry_dirty := true
var published: Dictionary = {}
var attempts := 0
var committed := 0
var revision := 0
var blocked := false
var last_collision: Dictionary = {}
var contact_entries := 0
var target_occupied := false

func _ready() -> void:
	for branch in ["B", "U"]:
		var body := AnimatableBody3D.new()
		body.name = branch
		body.sync_to_physics = false
		body.collision_layer = 4 if branch == "B" else 8
		body.collision_mask = 1
		body.set_meta("fixture_id", branch)
		_shape(body, BODY_SIZE)
		add_child(body)
		bodies[branch] = body
	obstacle = StaticBody3D.new()
	obstacle.name = "Blocker"
	obstacle.collision_layer = 1
	obstacle.collision_mask = 12
	obstacle.set_meta("fixture_id", "blocker")
	_shape(obstacle, Vector3(0.35, 1.5, 1.1))
	add_child(obstacle)
	target = Area3D.new()
	target.name = "WorkEncounter"
	target.collision_layer = 2
	target.collision_mask = 0
	target.set_meta("fixture_id", "work-target")
	_shape(target, Vector3(0.6, 1.2, 1.2))
	add_child(target)
	_sync_bodies()

func _shape(parent: CollisionObject3D, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	parent.add_child(collider)

func _position(branch: String, phase: float) -> Vector3:
	return Vector3(float(mounts[branch][0]) + SPAN * sin(phase), HEIGHT, float(mounts[branch][1]))

func _sync_bodies() -> void:
	for branch in bodies:
		bodies[branch].position = _position(branch, phases[branch])
	obstacle.position = Vector3(1.4, HEIGHT, 0 if obstacle_active else 6)
	target.position = Vector3(1.6, HEIGHT, 0)
	geometry_dirty = true

func _native_synchronized() -> bool:
	for body in [bodies.B, bodies.U, obstacle]:
		var native: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		if native.origin.distance_to(body.global_position) > ALIGN_EPSILON:
			return false
	return true

func _publish_native() -> void:
	var positions := {}
	for branch in bodies:
		var native: Transform3D = PhysicsServer3D.body_get_state(bodies[branch].get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		positions[branch] = _array(native.origin)
	var solid: Transform3D = PhysicsServer3D.body_get_state(obstacle.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	published = {"positions": positions, "source_phase": source_phase, "phases": phases.duplicate(),
		"committed": committed, "contact_entries": contact_entries, "obstacle_position": _array(solid.origin)}

func _ratio() -> float:
	return 20.0 / float(driven_teeth) * (1.0 if idler else -1.0)

func command(intent: Dictionary) -> Dictionary:
	# Local trusted fixture commands, no network/retry or save contract implied.
	if pending:
		return _answer(false, "step_pending")
	match intent.get("action", ""):
		"run":
			if not intent.get("active") is bool:
				return _answer(false, "invalid_active")
			running = intent.active
		"step":
			if not running:
				return _answer(false, "source_stopped")
			pending = true
			return _answer(true, "queued_for_physics")
		"gearing":
			if running or source_phase != 0.0:
				return _answer(false, "initial_stationary_setup_only")
			if not intent.get("idler") is bool or not intent.get("teeth") is int or not intent.teeth in [20, 40]:
				return _answer(false, "invalid_gearing")
			idler = intent.idler
			driven_teeth = intent.teeth
		"coupling":
			if not intent.get("active") is bool:
				return _answer(false, "invalid_active")
			if intent.active and not coupled:
				if running:
					return _answer(false, "stop_before_engage")
				if absf(wrapf(source_phase * _ratio() - phases.B, -PI, PI)) > ALIGN_EPSILON:
					return _answer(false, "coupling_misaligned")
			coupled = intent.active
			blocked = false
		"fixture_obstacle":
			if not intent.get("active") is bool:
				return _answer(false, "invalid_active")
			obstacle_active = intent.active
			_sync_bodies()
			revision += 1
			return _answer(true, "geometry_pending")
		"edit_mount":
			if running or source_phase != 0.0:
				return _answer(false, "initial_stationary_setup_only")
			var branch = intent.get("branch")
			var cell = intent.get("cell")
			if not branch is String or not mounts.has(branch) or not cell is Array or cell.size() != 2:
				return _answer(false, "invalid_mount")
			for value in cell:
				if not value is int or value < -4 or value > 4:
					return _answer(false, "invalid_mount")
			# This rig keeps its two linear lanes apart; general assembly editing
			# and moving/moving contact are deliberately outside this first probe.
			if branch != "U" or cell[0] != 0 or not cell[1] in [3, 4]:
				return _answer(false, "unsupported_fixture_mount")
			mounts[branch] = cell.duplicate()
			_sync_bodies()
			revision += 1
			return _answer(true, "geometry_pending")
		_: return _answer(false, "unsupported_action")
	revision += 1
	return _answer(true, "applied")

func _answer(accepted: bool, reason: String) -> Dictionary:
	return {"accepted": accepted, "reason": reason, "revision": revision}

func _physics_process(_delta: float) -> void:
	# AnimatableBody3D's native state is committed by the physics server after
	# this callback. Publish completion on the following physics boundary, so
	# consumers never mistake the new Node pose for completed native movement.
	if not completion.is_empty():
		if not _native_synchronized():
			return
		var outcome: Dictionary = completion
		completion = {}
		geometry_dirty = false
		_publish_native()
		pending = false
		outcome["state"] = projection()
		advanced.emit(outcome)
		return
	# Configuration can change a native body/obstacle in the same call stack
	# that queues the next drive request. Own that request until its actual
	# source geometry is synchronized; never sweep from a stale native pose.
	if geometry_dirty:
		if not _native_synchronized():
			return
		geometry_dirty = false
		_publish_native()
	if not pending:
		return
	attempts += 1
	var candidate := phases.duplicate()
	candidate.U += INPUT_STEP * 0.5
	if coupled:
		candidate.B += INPUT_STEP * _ratio()
	# Inspect every driven branch before committing ANY source/branch phase.
	# test_move uses the actual body's shapes and this world's native colliders.
	for branch in ["B", "U"]:
		if branch == "B" and not coupled:
			continue
		var body: AnimatableBody3D = bodies[branch]
		var motion: Vector3 = _position(branch, candidate[branch]) - body.position
		var collision := KinematicCollision3D.new()
		if body.test_move(body.global_transform, motion, collision, 0.001):
			blocked = true
			last_collision = {"branch": branch, "collider": str(collision.get_collider().get_meta("fixture_id", "unknown")),
				"from": _array(body.position), "attempted": _array(_position(branch, candidate[branch])),
				"point": _array(collision.get_position()), "normal": _array(collision.get_normal())}
			completion = {"accepted": false, "reason": "solid_obstruction"}
			return
	phases = candidate
	source_phase += INPUT_STEP
	committed += 1
	revision += 1
	blocked = false
	_sync_bodies()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = bodies.B.get_node("CollisionShape3D").shape
	query.transform = bodies.B.global_transform
	query.collision_mask = 2
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var encountered := not get_world_3d().direct_space_state.intersect_shape(query).is_empty()
	if encountered and not target_occupied:
		contact_entries += 1
	target_occupied = encountered
	completion = {"accepted": true, "reason": "advanced"}

func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func projection() -> Dictionary:
	var positions := {}
	for branch in bodies:
		positions[branch] = _array(bodies[branch].global_position)
	return {"running": running, "coupled": coupled, "idler": idler, "teeth": driven_teeth,
		"source_phase": source_phase, "phases": phases.duplicate(), "mounts": mounts.duplicate(true),
		"positions": positions, "body_size": _array(BODY_SIZE), "members": ["B", "U"],
		"obstacle_active": obstacle_active, "obstacle_position": _array(obstacle.position),
		"target_position": _array(target.position), "target_occupied": target_occupied,
		"contact_entries": contact_entries, "blocked": blocked, "last_collision": last_collision.duplicate(true),
		"attempts": attempts, "committed": committed, "pending": pending,
		"native_pending": pending or geometry_dirty, "completed": published.duplicate(true), "revision": revision}
