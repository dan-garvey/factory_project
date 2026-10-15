extends "res://mechanics/authority.gd"
## One existing drive owner; the B body becomes this fixture's passenger deck.
const DECK_SIZE := Vector3(3, 0.35, 3)

func _ready() -> void:
	super._ready()
	bodies.B.get_node("CollisionShape3D").shape.size = DECK_SIZE
	bodies.B.sync_to_physics = true
	target.collision_layer = 0
	_sync_bodies()

func _position(branch: String, phase: float) -> Vector3:
	if branch == "U":
		return Vector3(-8, HEIGHT, -7)
	return super._position(branch, phase)

func command(intent: Dictionary) -> Dictionary:
	if intent.get("action") not in ["run", "step"]:
		return _answer(false, "fixed_passenger_fixture")
	return super.command(intent)
