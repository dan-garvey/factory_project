extends "res://rider/view.gd"
const RotaryDrive = preload("res://rotary/authority.gd")

func _make_authority() -> Node3D:
	return RotaryDrive.new()

func _fixture_text() -> Dictionary:
	return {"title": "ROTARY RIDER", "deck": "ROTARY DECK · Y AXIS", "summary": "Local rotary passenger experiment"}

func _display_deck(state: Dictionary) -> void:
	# Operating native pose is visible throughout a turn. Completed goal phase
	# is a separate milestone; this presentation never moves a physics body.
	deck_mesh.visible = not state.completed.is_empty()
	if not deck_mesh.visible:
		return
	var pose: Dictionary = authority.native_pose()
	var at: Array = pose.position
	var axes: Array = pose.basis
	deck_mesh.position = Vector3(at[0], at[1], at[2])
	deck_mesh.basis = Basis(Vector3(axes[0][0], axes[0][1], axes[0][2]),
		Vector3(axes[1][0], axes[1][1], axes[1][2]), Vector3(axes[2][0], axes[2][1], axes[2][2]))
