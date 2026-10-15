extends "res://rider/authority.gd"
## The two existing phase-owned bodies become coupled native carriages.
const CAR_SPACING := 3.0

func _ready() -> void:
	super._ready()
	bodies.U.get_node("CollisionShape3D").shape.size = DECK_SIZE
	bodies.U.collision_layer = 4
	bodies.U.sync_to_physics = true
	_sync_bodies()

func _position(branch: String, phase: float) -> Vector3:
	return Vector3(SPAN * sin(phase) + (CAR_SPACING if branch == "U" else 0.0), HEIGHT, 0)

func _native_synchronized() -> bool:
	if not super._native_synchronized():
		return false
	# Sync-to-physics can revert a Node to its previous native pose while a
	# target is queued. Node == RID alone does not confirm the phase-owned goal.
	for branch in ["B", "U"]:
		var pose: Transform3D = PhysicsServer3D.body_get_state(bodies[branch].get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		if pose.origin.distance_to(_position(branch, phases[branch])) > ALIGN_EPSILON:
			return false
	return true
