extends SceneTree
## Detached callbacks over invented projections and a request sink, never a game.
const Controls = preload("res://opening/native_transmission_controls.gd")

class OfflineHarness:
	extends "res://opening/opening.gd"
	var requests: Array = []
	func _update_cursor() -> void: pass
	func _refresh_ui() -> void: pass
	func issue(wire: Dictionary) -> Dictionary:
		requests.append(wire.duplicate(true))
		return {"accepted": false, "queued": true}

class SharedHarness:
	extends "res://opening/shared_opening.gd"
	var requests: Array = []
	func _update_cursor() -> void: pass
	func _refresh_ui() -> void: pass
	func _update_camera() -> void: pass
	func issue(wire: Dictionary) -> Dictionary:
		requests.append(wire.duplicate(true))
		return {"accepted": false, "queued": true}

class Connection:
	extends RefCounted
	var ready := true
	func is_ready() -> bool: return ready

var checks := 0
var failures := 0

func verify(condition: bool, words: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(words)

func fixture() -> Dictionary:
	return {"context": "shaft-tiles", "options": {"native": true, "physical": true},
		"actors": {"P": {"ready": true}, "Q": {"ready": true}},
		"entities": {"wheel": {"kind": "wheel", "generation": 1, "axis": 1, "center": [-4, 0, 4]}},
		"transmission_parts": {},
		"part_specifications": {"P": [{"kind": "shaft", "teeth": 0, "half_span": 2, "count": 3}], "Q": []},
		"stock": {}, "parts": {}, "inventories": {"P": 0}, "motion": {}, "engagements": []}

func mount(view) -> void:
	view.state = fixture()
	view.client = "P"
	view.status_label = Label.new()
	view.add_child(view.status_label)
	view.transmission_controls = Controls.new()
	view.add_child(view.transmission_controls)
	view.transmission_controls.configure(view)

func check_direct_shaft_entry(shared: bool) -> void:
	var view = SharedHarness.new() if shared else OfflineHarness.new()
	if shared:
		view.session = Connection.new()
	mount(view)
	var before: Dictionary = view.state.duplicate(true)
	view._select_tool("drive")
	verify(view.transmission_controls.active_tool == "place_shaft" and "highlighted tile" in view.status_label.text,
		"The ordinary Shaft entry selects individual tile placement.")
	view._transmission_click([0, 0, 4], "")
	view._transmission_click([4, 0, 4], "")
	verify(view.requests == [{"action": "place_shaft", "center": [0, 0, 4], "axis": "x", "half_span": 2},
		{"action": "place_shaft", "center": [4, 0, 4], "axis": "x", "half_span": 2}],
		"Two clicks submit two individual shaft tiles.")
	var count: int = view.requests.size()
	for invalid in [[1, 0, 4], [0, 1, 4], [0, 0, 5]]:
		verify(view._transmission_click(invalid, "") and view.requests.size() == count,
			"An off-grid coordinate is consumed without a request.")
	verify(view.state == before and view.model == null,
		"Queued clicks change no confirmed projection and create no Model.")
	view.transmission_controls.cancel()
	verify(not view._transmission_click([0, 0, 4], ""), "Cancel restores ordinary scene input.")
	view.free()

func check_shared_barriers() -> void:
	var view := SharedHarness.new()
	view.session = Connection.new()
	mount(view)
	view._select_tool("drive")
	for blocker in ["disconnected", "pending"]:
		view.session.ready = true
		view.pending_actions.clear()
		if blocker == "disconnected":
			view.session.ready = false
		else:
			view.pending_actions = {"queued": {"action": "place"}}
		verify(view._transmission_click([0, 0, 4], "") and view.requests.is_empty(),
			"Shared freshness prevents direct shaft requests: " + blocker)
	verify(view.model == null, "Shared controls create no local Model.")
	view.free()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check_shared_barriers()
	if "--common-frame-only" not in OS.get_cmdline_user_args():
		check_direct_shaft_entry(false)
		check_direct_shaft_entry(true)
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks, "failures": failures, "evidence": "isolated_shaft_tile_controls", "models": 0, "desktop_operations": 0}))
	quit(0 if failures == 0 else 1)
