extends SceneTree
## Detached callbacks over invented projections and a request sink, never a game.
const Controls = preload("res://opening/native_transmission_controls.gd")
const Geometry = preload("res://opening/site_geometry.gd")

class OfflineHarness:
	extends "res://opening/opening.gd"
	var requests: Array = []
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
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
	verify(view.transmission_controls.active_tool == "place_shaft" and "match its height" in view.status_label.text,
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

func pick_body(view: Node3D, id: String, position: Vector3, size: Vector3, offset: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Geometry.PICK_LAYER
	body.collision_mask = 0
	body.set_meta("entity", id)
	body.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	body.add_child(shape)
	view.add_child(body)

func check_raised_pointer() -> void:
	# Passive rays over the same confirmed pick bodies used by the opening.
	var view := OfflineHarness.new()
	root.add_child(view)
	mount(view)
	view.state.entities = {"press": {"cell": [1, 0], "level": 4, "axis": 0, "kind": "processor"}}
	view.state.foundations = {"floor": {"cell": [0, 0], "level": 4}}
	view.state.part_specifications.P.append({"kind": "gear", "teeth": 2, "half_span": 0, "count": 2})
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	view.camera.make_current()
	view.hover = MeshInstance3D.new()
	view.add_child(view.hover)
	view.transmission_controls.choose_tool("place_shaft")
	pick_body(view, "floor", Vector3(0, Geometry.PITCH, 0), Vector3.ONE * Geometry.PITCH,
		Vector3.DOWN * Geometry.PITCH / 2.0)
	pick_body(view, "press", Vector3(Geometry.PITCH, Geometry.PITCH, 0),
		Vector3(1.45, 1.65, 1.45), Vector3.UP * 0.8)
	await physics_frame
	view.camera.position = Vector3(0, 6, 5)
	view.camera.look_at(Vector3(0, Geometry.PITCH, 0))
	var floor_screen := view.camera.unproject_position(Vector3(0, Geometry.PITCH, 0))
	var floor_target: Array = view._transmission_center(floor_screen)
	verify(floor_target == [0, 4, 0], "A raised foundation pick follows its confirmed top tile.")
	if failures > 0:
		view.queue_free()
		return
	view._transmission_click(floor_target, "")
	verify(view.requests == [{"action": "place_shaft", "center": [0, 4, 0], "axis": "x", "half_span": 2}],
		"The shaft click submits the raised tile shown by the pointer.")
	view.transmission_controls._height_selected(1)
	verify(not view.transmission_controls.auto_height and view.transmission_controls.gear_height == 8
		and view._transmission_center(floor_screen) == [0, 8, 0], "An explicit height starts above the pointed floor.")
	view.transmission_controls._height_selected(2)
	verify(view.transmission_controls.auto_height and view._transmission_center(floor_screen) == [0, 4, 0],
		"The height menu restores surface following.")
	view.state.foundations["half-floor"] = {"cell": [-1, 0], "level": 2}
	pick_body(view, "half-floor", Vector3(-Geometry.PITCH, Geometry.PITCH / 2.0, 0),
		Vector3.ONE * Geometry.PITCH, Vector3.DOWN * Geometry.PITCH / 2.0)
	await physics_frame
	view.camera.position = Vector3(-Geometry.PITCH, 6, 5)
	view.camera.look_at(Vector3(-Geometry.PITCH, Geometry.PITCH / 2.0, 0))
	var half_screen := view.camera.unproject_position(Vector3(-Geometry.PITCH, Geometry.PITCH / 2.0, 0))
	var half_target: Array = view._transmission_center(half_screen)
	verify(half_target == [-4, 4, 0], "An intermediate foundation selects the next global tile above its surface.")
	view._transmission_click(half_target, "")
	verify(view.requests.size() == 2 and view.requests[1] ==
		{"action": "place_shaft", "center": [-4, 4, 0], "axis": "x", "half_span": 2},
		"The click submits the same aligned tile displayed above the intermediate foundation.")
	view.state.foundations["half-floor"].level = -2
	verify(view._transmission_snap_target("half-floor", Vector3.UP, Vector3.ZERO) == [-4, 0, 0],
		"A negative intermediate foundation rounds upward to the global zero tile.")
	view.transmission_controls._height_selected(1)
	verify(view._transmission_snap_target("half-floor", Vector3.UP, Vector3.ZERO) == [-4, 4, 0],
		"An explicit height still overrides intermediate surface following.")
	view.transmission_controls._height_selected(2)
	view.camera.position = Vector3(5, 3, 0)
	view.camera.look_at(Vector3(Geometry.PITCH, Geometry.PITCH + 0.8, 0))
	var machine_screen := view.camera.unproject_position(Vector3(Geometry.PITCH, Geometry.PITCH + 0.8, 0))
	var machine_target: Array = view._transmission_center(machine_screen)
	verify(machine_target == [8, 4, 0], "The machine face points to its adjacent common-grid axle tile.")
	view.transmission_controls.choose_tool("gear")
	view._transmission_click(machine_target, "")
	verify(view.requests.size() == 3 and view.requests[2] ==
		{"action": "place_gear", "center": [8, 4, 0], "axis": "x", "teeth": 2},
		"The cogwheel click uses the adjacent machine target.")
	view.transmission_controls.selected_axis = "y"
	verify(view._transmission_snap_target("press", Vector3.UP, Vector3(4, 5, 0)) == [4, 8, 0],
		"The vertical axle target advances one shared height tile.")
	view.transmission_controls.selected_axis = "z"
	verify(view._transmission_snap_target("press", Vector3.FORWARD, Vector3(4, 3, -4)) == [4, 4, -4],
		"A second machine face snaps along its selected horizontal axis.")
	for axis in ["x", "y", "z"]:
		view.transmission_controls.selected_axis = axis
		view.hover.basis = Basis(Vector3.DOWN, Vector3.RIGHT, Vector3.BACK)
		view._set_transmission_hover([8, 4, 0])
		verify(view.hover.visible and view.hover.basis.is_equal_approx(Basis.IDENTITY)
			and view.hover.position.is_equal_approx(Vector3(2 * Geometry.PITCH, Geometry.PITCH + 0.03, 0)),
			"The %s placement square stays horizontal on the target floor." % axis)
	view.queue_free()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check_shared_barriers()
	if "--common-frame-only" not in OS.get_cmdline_user_args():
		check_direct_shaft_entry(false)
		check_direct_shaft_entry(true)
		await check_raised_pointer()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks, "failures": failures, "evidence": "isolated_shaft_tile_controls_and_pointer", "models": 0, "desktop_operations": 0}))
	quit(0 if failures == 0 else 1)
