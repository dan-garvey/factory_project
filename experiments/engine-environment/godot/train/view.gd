extends "res://rider/view.gd"
## Both visible carriages consume the one completed native packet.
const TrainDrive = preload("res://train/authority.gd")
var trailing_mesh: MeshInstance3D

func _make_authority() -> Node3D:
	return TrainDrive.new()

func _fixture_text() -> Dictionary:
	return {"title": "COUPLED CARRIAGES", "deck": "STRAIGHT FIXED CYCLE", "summary": "Local two-car passenger experiment"}

func _ready() -> void:
	super._ready()
	distance = 16
	wall.position.x = 9
	for child in get_children():
		if child is Label3D and child.text == "FIXED BOUNDARY":
			child.position.x = 9
	trailing_mesh = _box(self, Vector3.ZERO, TrainDrive.DECK_SIZE, Color("668fa2"))
	_box(trailing_mesh, Vector3(0, 0.18, 0), Vector3(2.8, 0.02, 0.04), Color("d8edf0"))
	for z in [-0.9, 0.9]:
		_box(self, Vector3(1.5, 0.4, z), Vector3(12, 0.08, 0.08), Color("82958f"))
	_refresh()

func _display_deck(state: Dictionary) -> void:
	deck_mesh.visible = not state.completed.is_empty()
	if trailing_mesh != null:
		trailing_mesh.visible = not state.completed.is_empty()
	if state.completed.is_empty():
		return
	super._display_deck(state)
	if trailing_mesh != null:
		var at: Array = state.completed.positions.U
		trailing_mesh.position = Vector3(at[0], at[1], at[2])

func _support_text() -> String:
	if player.floor_id == authority.bodies.B.get_instance_id():
		return "carriage B"
	if player.floor_id == authority.bodies.U.get_instance_id():
		return "carriage U"
	return "ground" if player.floor_id == ground.get_instance_id() else "air"
