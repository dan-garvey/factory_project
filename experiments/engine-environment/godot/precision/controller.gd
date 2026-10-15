extends RefCounted
## Six explicit sensor-to-actuator rows; this circuit owns no material.
const ROWS = ["take_output", "reject_X", "return_extra_A", "return_extra_B", "feed_A", "feed_B"]
const METER = ["take_output", "feed_A", "feed_B"]
const RECOVERY = ["reject_X", "return_extra_A", "return_extra_B"]
const LABELS = {"take_output": "Output C > 0  →  collect C",
	"reject_X": "Input X > 0  →  route X to reject bin",
	"return_extra_A": "Input A > 2  →  return one A",
	"return_extra_B": "Input B > 1  →  return one B",
	"feed_A": "Input A < 2  →  feed A, returns first",
	"feed_B": "Input B < 1  →  feed B, returns first"}
var _enabled: Dictionary = {}

func _init() -> void:
	for row in ROWS: _enabled[row] = false

func configure(row: String, active: bool) -> bool:
	var changed: bool = _enabled[row] != active
	_enabled[row] = active
	return changed

func wiring() -> Dictionary:
	return _enabled.duplicate(true)

func propose(reading: Dictionary) -> Dictionary:
	# Priority and one transfer per step are fixture wiring, not extra stock.
	if _enabled.take_output and reading.output > 0:
		return {"action": "collect"}
	if reading.current_job > 0:
		return {} # The captured chamber is closed until this job completes.
	var chamber: Dictionary = reading.locations.input
	if _enabled.reject_X and chamber.X > 0:
		return {"action": "recover", "kind": "X"}
	if _enabled.return_extra_A and chamber.A > 2:
		return {"action": "recover", "kind": "A"}
	if _enabled.return_extra_B and chamber.B > 1:
		return {"action": "recover", "kind": "B"}
	for kind in ["A", "B"]:
		var target: int = 2 if kind == "A" else 1
		if _enabled["feed_" + kind] and chamber[kind] < target:
			if reading.locations.returns[kind] > 0:
				return {"action": "feed_return", "kind": kind}
			if reading.locations.source[kind] > 0:
				return {"action": "insert", "kind": kind}
	return {}
