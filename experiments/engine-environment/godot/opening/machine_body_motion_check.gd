extends SceneTree
## Actual render transforms over invented observations. No Model or game starts.
const Opening = preload("res://opening/opening.gd")
const Shared = preload("res://opening/shared_opening.gd")
const Presenter = preload("res://opening/native_transmission_presenter.gd")
var checks := 0
var failed := false

class SessionFacts extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func snapshot() -> Dictionary:
	return {"context": "body-fixture", "options": {"native": true, "physical": true},
		"actors": {"P": {"ready": true}}, "parts": {}, "inventories": {"P": 0},
		"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
		"remaining": 0, "entities": {
			"collector": {"kind": "collector", "cell": [0, 0], "generation": 1, "axis": 2},
			"press": {"kind": "processor", "cell": [2, 0], "generation": 1, "axis": 0}},
		"transmission_parts": {}, "links": [], "drive_links": [], "engagements": [],
		"motion": {"collector": {"state": "rotating", "numerator": 1, "denominator": 1},
			"press": {"state": "rotating", "numerator": 1, "denominator": 1}}}

func mount(view: Node3D) -> void:
	view.client = "P"
	view.state = snapshot()
	view.machine_root = Node3D.new()
	view.add_child(view.machine_root)
	view.transmission_presenter = Presenter.new()
	view.add_child(view.transmission_presenter)
	view.transmission_presenter.configure(view)
	view._rebuild_machines()

func machine(view: Node3D, id: String) -> Node3D:
	for node in view.machine_root.get_children():
		if node.get_meta("machine_entity", "") == id:
			return node
	return null

func meshes(view: Node3D, id: String) -> Array:
	return machine(view, id).get_meta("motion_meshes")

func pose(view: Node3D, role: String) -> Transform3D:
	for row in meshes(view, "press"):
		if row.role == role:
			return row.parent_inverse.affine_inverse() * row.node.transform
	return Transform3D.IDENTITY

func pose_list(view: Node3D) -> Array:
	var result: Array = []
	for id in ["collector", "press"]:
		for row in meshes(view, id):
			result.append(row.node.transform)
	return result

func pick_facts(view: Node3D) -> Array:
	var result: Array = []
	for id in ["collector", "press"]:
		var anchor := machine(view, id)
		for node in anchor.get_children():
			if node is StaticBody3D:
				var shape: CollisionShape3D = node.get_child(0)
				result.append([anchor.transform, node.transform, node.collision_layer,
					node.collision_mask, node.get_meta("entity"), shape.transform, shape.shape.size])
	return result

func check_bounds(view: Node3D) -> void:
	for id in ["collector", "press"]:
		for row in meshes(view, id):
			var bounds: AABB = row.node.mesh.get_aabb()
			var transform: Transform3D = row.parent_inverse.affine_inverse() * row.node.transform
			var contained := true
			for corner in range(8):
				var point := transform * bounds.get_endpoint(corner)
				contained = contained and absf(point.x) <= 0.725 and absf(point.z) <= 0.725 and point.y >= -0.025 and point.y <= 1.625
			verify(contained, "Each moving render bound stays inside the unchanged machine pick envelope.")

func hold(view: Node3D) -> void:
	view.state.stock.source = 15
	view.state.stock.held = 1
	view.state.remaining = 2

func _initialize() -> void:
	var view := Opening.new()
	mount(view)
	var original: Dictionary = view.state.duplicate(true)
	var picks := pick_facts(view)
	var sequence: int = view.request_sequence
	verify(meshes(view, "collector").size() == 10 and meshes(view, "press").size() == 2,
		"Only the drum, hub, eight flutes, head and rod are selected for motion.")
	verify(picks.size() == 2 and picks[0][2] == 4 and picks[0][3] == 0 and picks[0][6] == Vector3(1.45, 1.65, 1.45),
		"The real builder retains literal pick dimensions and layers.")
	view._animate_wheel(0.1)
	verify(is_equal_approx(view.transmission_presenter.visual_angle("collector"), 0.08),
		"The cutter consumes the existing presenter angle without a second rate clock.")
	var flute_verified := false
	for row in meshes(view, "collector"):
		if row.node.get_meta("detail_role", "") == "CutterFlute" and row.rest.origin.is_equal_approx(Vector3(0.015, 1.1, -0.19)):
			var actual: Transform3D = row.parent_inverse.affine_inverse() * row.node.transform
			verify(actual.origin.is_equal_approx(Vector3(-0.22 + 0.235 * cos(0.08), 1.1 + 0.235 * sin(0.08), -0.19)),
				"A real flute orbits the fixed drum center using an independent trigonometric point.")
			flute_verified = true
	verify(flute_verified and view.state == original and pick_facts(view) == picks and view.request_sequence == sequence,
		"Render motion preserves authoritative observations, request sequence and pick geometry.")
	check_bounds(view)
	hold(view)
	var held: Dictionary = view.state.duplicate(true)
	view._animate_wheel(0.1)
	verify(is_equal_approx(pose(view, "head").origin.y, 0.72), "A newly observed held blank eases the head down rather than snapping or inventing a cycle.")
	view._rebuild_machines()
	verify(is_equal_approx(pose(view, "head").origin.y, 0.72), "An unrelated geometry refresh retains the in-progress render pose.")
	view._animate_wheel(0.1)
	verify(is_equal_approx(pose(view, "head").origin.y, 0.70), "The held pose reaches the bounded 0.14 metre travel.")
	var rod := pose(view, "rod")
	verify(is_equal_approx(rod.origin.y + rod.basis.y.length() * 0.225, 1.365),
		"The extending rod retains its original fixed top endpoint.")
	check_bounds(view)
	verify(view.state == held and view.request_sequence == sequence, "Presentation does not decrement remaining ticks or release held stock.")
	view.state.stock.source = 14
	view.state.stock.output = 1
	view.state.remaining = 0
	view.state.motion.collector.state = "stalled"
	view.state.motion.press.state = "stalled"
	var blocked: Dictionary = view.state.duplicate(true)
	var stopped := pose_list(view)
	view._animate_wheel(0.5)
	verify(pose_list(view) == stopped and view.state == blocked,
		"A blocked READY press retains held work and a stopped cutter retains its angle.")
	view.state.stock.held = 0
	view.state.inventories.P = 1
	view._animate_wheel(0.1)
	verify(is_equal_approx(pose(view, "head").origin.y, 0.82), "Only a new empty-held observation lets the head rise.")
	view._animate_wheel(0.1)
	verify(is_equal_approx(pose(view, "head").origin.y, 0.84), "The empty pose returns to the exact original rest transform.")
	for invalid in [true, 1.0, -1]:
		view.state.stock.held = invalid
		var before := pose_list(view)
		view._animate_wheel(0.1)
		verify(pose_list(view) == before, "Malformed held values do not guess a tool pose.")
	view.state.stock.held = 1
	for invalid in [false, 1.0, -1]:
		view.state.remaining = invalid
		var before := pose_list(view)
		view._animate_wheel(0.1)
		verify(pose_list(view) == before, "Malformed remaining values do not guess a tool pose.")
	view.state.remaining = 0
	for gate in ["help", "startup", "unready"]:
		view.explanation_open = gate == "help"
		view.startup_save_pending = gate == "startup"
		view.state.actors.P.ready = gate != "unready"
		var before := pose_list(view)
		view._animate_wheel(0.1)
		verify(pose_list(view) == before, "Help, startup and absent actor readiness freeze body presentation.")
	view.explanation_open = false
	view.startup_save_pending = false
	view.state.actors.P.ready = true
	for delta in [-1.0, 0.0, INF, NAN]:
		var before := pose_list(view)
		view._animate_wheel(delta)
		verify(pose_list(view) == before, "Nonpositive and nonfinite frame deltas cannot move a render part.")
	view.state.context = "new-observed-context"
	view._rebuild_machines()
	verify(is_equal_approx(pose(view, "head").origin.y, 0.70), "A fresh context starts at its observed held pose without replaying an operation.")
	view.state.entities.press.generation = 2
	view.state.stock.held = 0
	view._rebuild_machines()
	verify(is_equal_approx(pose(view, "head").origin.y, 0.84), "A replacement generation cannot inherit the previous tool travel.")
	view.free()
	var shared := Shared.new()
	var facts := SessionFacts.new()
	shared.session = facts
	mount(shared)
	hold(shared)
	shared.pending_actions = {"unrelated-build": {"status": "pending"}}
	shared._animate_wheel(0.1)
	verify(is_equal_approx(pose(shared, "head").origin.y, 0.72), "An unrelated pending shared request does not stop confirmed work presentation.")
	facts.ready = false
	var disconnected := pose_list(shared)
	shared._animate_wheel(0.1)
	verify(pose_list(shared) == disconnected, "Lost shared freshness freezes both cutter and tool.")
	shared.free()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"scope": "actual mesh transforms over invented observations", "native_gameplay": "not_run", "desktop": "not_used"}))
	quit(1 if failed else 0)
