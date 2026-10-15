extends "res://rider/authority.gd"
## One inherited signed goal owner and its bounded native operating trajectory.
const TURN_TICKS := 24
var turn_tick := TURN_TICKS
var turn_from := 0.0
var turn_goal := 0.0
var operating_requested := 0.0

func _position(branch: String, phase: float) -> Vector3:
	if branch == "B":
		return Vector3(0, HEIGHT, 0)
	return super._position(branch, phase)

func _sync_bodies() -> void:
	super._sync_bodies()
	turn_from = operating_requested
	turn_goal = phases.B
	turn_tick = 0 if absf(turn_goal - turn_from) > ALIGN_EPSILON else TURN_TICKS

func _physics_process(delta: float) -> void:
	if turn_tick < TURN_TICKS:
		turn_tick += 1
		operating_requested = lerpf(turn_from, turn_goal, float(turn_tick) / TURN_TICKS)
		# The declared trajectory is a unit basis at an absolute angle. Updating
		# one Euler component would preserve scale roundoff from native sync.
		bodies.B.basis = Basis(Vector3.UP, operating_requested)
	super._physics_process(delta)

func _native_synchronized() -> bool:
	if not super._native_synchronized():
		return false
	var pose: Transform3D = PhysicsServer3D.body_get_state(bodies.B.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var wanted := Basis(Vector3.UP, phases.B)
	return pose.basis.x.distance_to(wanted.x) <= ALIGN_EPSILON and pose.basis.y.distance_to(wanted.y) <= ALIGN_EPSILON \
		and pose.basis.z.distance_to(wanted.z) <= ALIGN_EPSILON

func native_pose() -> Dictionary:
	var pose: Transform3D = PhysicsServer3D.body_get_state(bodies.B.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	return {"position": _array(pose.origin), "basis": [_array(pose.basis.x), _array(pose.basis.y), _array(pose.basis.z)]}

func _publish_native() -> void:
	super._publish_native()
	var pose := native_pose()
	published["basis"] = pose.basis
	published["operating_angle"] = operating_requested

func projection() -> Dictionary:
	var state: Dictionary = super.projection()
	state["motion"] = {"ticks": turn_tick, "subdivisions": TURN_TICKS, "from": turn_from,
		"goal": turn_goal, "requested_angle": operating_requested}
	return state
