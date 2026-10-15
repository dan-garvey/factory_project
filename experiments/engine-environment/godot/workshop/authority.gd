extends "res://mechanics/authority.gd"
## The accepted mechanism owner, with bounded player construction commands.
## Configuration pieces and non-consuming encounters are not produced inventory.
const OUTPUT_PEG := [-3, -2]
const IDLER_PEG := [-4, -2]
const B_CELLS := [[-1, 0], [0, 0]]
const U_CELLS := [[0, 3], [0, 4]]
const STOP_CELLS := [[1, 0], [2, 0], [1, 3], [2, 3]]
var pieces := {"B": null, "U": null, "gear": null, "idler": null, "stop": null}

func _ready() -> void:
	idler = false
	super._ready()

func _position(branch: String, phase: float) -> Vector3:
	if pieces[branch] == null:
		return Vector3(-7, HEIGHT, -7 if branch == "B" else -9)
	return super._position(branch, phase)

func _sync_bodies() -> void:
	super._sync_bodies()
	if pieces.stop != null and obstacle_active:
		var cell: Array = pieces.stop.cell
		obstacle.position = Vector3(cell[0], HEIGHT, cell[1])
	else:
		obstacle.position = Vector3(4, HEIGHT, 8)
	geometry_dirty = true

func _complete_layout() -> bool:
	return pieces.B != null and pieces.U != null and pieces.gear != null

func _layout() -> Dictionary:
	return {"pieces": pieces.duplicate(true), "ready": _complete_layout(),
		"stop_retracted": not obstacle_active, "initial_editable": not running and source_phase == 0.0,
		"ratio": _ratio()}

func _publish_native() -> void:
	super._publish_native()
	published["layout"] = _layout()

func _editable() -> bool:
	return not running and source_phase == 0.0

func _cell(intent: Dictionary) -> Array:
	var cell = intent.get("cell")
	if not cell is Array or cell.size() != 2:
		return []
	for value in cell:
		if not value is int:
			return []
	return cell.duplicate()

func _place(intent: Dictionary) -> Dictionary:
	if not _editable():
		return _answer(false, "initial_setup_only")
	var cell := _cell(intent)
	if cell.is_empty():
		return _answer(false, "invalid_cell")
	var kind = intent.get("kind", "")
	var slot := ""
	match kind:
		"B":
			if not cell in B_CELLS:
				return _answer(false, "choose_B_mount")
			slot = "B"
		"U":
			if not cell in U_CELLS:
				return _answer(false, "choose_U_mount")
			slot = "U"
		"gear20", "gear40":
			if cell != OUTPUT_PEG:
				return _answer(false, "choose_output_peg")
			slot = "gear"
		"idler":
			if cell != IDLER_PEG:
				return _answer(false, "choose_idler_peg")
			slot = "idler"
		"stop":
			if not cell in STOP_CELLS:
				return _answer(false, "choose_stop_cell")
			slot = "stop"
		_:
			return _answer(false, "unknown_piece")
	var next := {"kind": kind, "cell": cell}
	if pieces[slot] == next:
		return _answer(false, "already_here")
	pieces[slot] = next
	if slot in ["B", "U"]:
		mounts[slot] = cell.duplicate()
	elif slot == "stop":
		obstacle_active = true
	_configured()
	return _answer(true, "geometry_pending")

func _erase(intent: Dictionary) -> Dictionary:
	if not _editable():
		return _answer(false, "initial_setup_only")
	var cell := _cell(intent)
	if cell.is_empty():
		return _answer(false, "invalid_cell")
	for slot in pieces:
		if pieces[slot] != null and pieces[slot].cell == cell:
			pieces[slot] = null
			if slot == "stop":
				obstacle_active = false
			_configured()
			return _answer(true, "geometry_pending")
	return _answer(false, "empty_cell")

func _configured() -> void:
	# Derive setup inputs; signed phase, gearing, admission and collision remain
	# in the inherited authority. No duplicate phase integrator or work counter.
	driven_teeth = 20 if pieces.gear != null and pieces.gear.kind == "gear20" else 40
	idler = pieces.idler != null
	revision += 1
	_sync_bodies()

func command(intent: Dictionary) -> Dictionary:
	if pending:
		return _answer(false, "step_pending")
	match intent.get("action", ""):
		"place_piece": return _place(intent)
		"erase_piece": return _erase(intent)
		"run":
			if intent.get("active") == true and not _complete_layout():
				return _answer(false, "place_heads_and_output")
		"stop_control":
			if pieces.stop == null:
				return _answer(false, "no_training_stop")
			if running:
				return _answer(false, "pause_before_stop_control")
			if not intent.get("retracted") is bool:
				return _answer(false, "invalid_active")
			# A lever retracts an already mounted training stop. It is not an
			# edit to the stop's construction position or to a moving machine.
			return super.command({"action": "fixture_obstacle", "active": not intent.retracted})
		"gearing", "edit_mount", "fixture_obstacle":
			return _answer(false, "use_workshop_construction")
	return super.command(intent)

func projection() -> Dictionary:
	var state: Dictionary = super.projection()
	state["layout"] = _layout()
	return state
