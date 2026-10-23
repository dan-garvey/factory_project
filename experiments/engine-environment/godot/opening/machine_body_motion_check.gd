extends SceneTree
## Actual render transforms over invented observations. No Model or game starts.
const Opening = preload("res://opening/opening.gd")
const Shared = preload("res://opening/shared_opening.gd")
const Presenter = preload("res://opening/native_transmission_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const TransmissionAssets = preload("res://opening/native_transmission_assets.gd")
var checks := 0
var failed := false

class SessionFacts extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

class BatchedView extends Opening:
	func _ready() -> void:
		pass

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
	for id in ["collector", "press", "forward", "reverse"]:
		var anchor := machine(view, id)
		if anchor == null:
			continue
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

func bounds_in_view(mesh: MeshInstance3D, view: Node3D) -> AABB:
	var transform := mesh.transform
	var ancestor := mesh.get_parent()
	while ancestor != null and ancestor != view:
		if ancestor is Node3D:
			transform = ancestor.transform * transform
		ancestor = ancestor.get_parent()
	return transform * mesh.mesh.get_aabb()

func conveyor_offset(view: Node3D, id: String) -> float:
	return machine(view, id).get_node("ConveyorLoop").material_override.uv1_offset.x

func expected_rotation(seconds: float) -> float:
	# A rate-one belt covers one world tile per authoritative native tick.
	return seconds * Geometry.PITCH / (Opening.STEP_SECONDS * TransmissionAssets.SPAN_OUTER_RADIUS)

func check_conveyor_motion(shared: bool) -> void:
	var view = Shared.new() if shared else Opening.new()
	var facts := SessionFacts.new()
	if shared:
		view.session = facts
	mount(view)
	for id in ["forward", "reverse"]:
		view.state.entities[id] = {"kind": "belt", "cell": [3 if id == "forward" else 4, 0], "generation": 1, "axis": 2}
		view.state.motion[id] = {"state": "rotating", "numerator": -1 if id == "forward" else 1, "denominator": 1}
	view._rebuild_machines()
	var original: Dictionary = view.state.duplicate(true)
	var first = machine(view, "forward").get_node("ConveyorLoop")
	var second = machine(view, "reverse").get_node("ConveyorLoop")
	verify(first.material_override != second.material_override, "Each conveyor owns its texture offset.")
	var picks := pick_facts(view)
	view._animate_wheel(0.1)
	var positive := conveyor_offset(view, "reverse")
	var negative := conveyor_offset(view, "forward")
	var length_value := 4.0 * Opening.ProductionConveyorArt.HALF_SPAN + TAU * Opening.ProductionConveyorArt.RADIUS
	var repeats := maxi(1, roundi(length_value / Opening.ProductionConveyorArt.SOURCE_METRES))
	var expected := expected_rotation(0.1) * Opening.ProductionConveyorArt.RADIUS * repeats / length_value
	verify(is_equal_approx(positive, expected) and is_equal_approx(negative, 1.0 - expected),
		"Opposite spindle signs move the top texture in opposite world directions at pulley surface speed.")
	view._rebuild_machines()
	verify(is_equal_approx(conveyor_offset(view, "reverse"), positive) and is_equal_approx(conveyor_offset(view, "forward"), negative),
		"Rebuilding conveyor meshes retains their confirmed visual phase.")
	for frame in range(40):
		view._animate_wheel(0.1)
	positive = conveyor_offset(view, "reverse")
	verify(is_equal_approx(positive, fposmod(expected * 41.0, 1.0)),
		"The surface travels continuously through a wrapped shaft angle.")
	view.state.motion.reverse.state = "stalled"
	view._animate_wheel(0.1)
	verify(is_equal_approx(conveyor_offset(view, "reverse"), positive), "A stalled belt keeps its surface phase.")
	view.explanation_open = true
	negative = conveyor_offset(view, "forward")
	view._animate_wheel(0.1)
	verify(is_equal_approx(conveyor_offset(view, "forward"), negative), "Help freezes surface motion.")
	view.explanation_open = false
	if shared:
		facts.ready = false
		view._animate_wheel(0.1)
		verify(is_equal_approx(conveyor_offset(view, "forward"), negative), "A disconnected shared view freezes surface motion.")
	view.state.motion.reverse.state = "rotating"
	verify(view.state == original and pick_facts(view) == picks and view.request_sequence == 0,
		"Conveyor animation changes neither authority facts nor picking or requests.")
	view.free()

func check_held_workpiece_clearance() -> void:
	var view := Opening.new()
	mount(view)
	hold(view)
	view.item_root = Node3D.new()
	view.add_child(view.item_root)
	var observed: Dictionary = view.state.duplicate(true)
	var picks := pick_facts(view)
	view._redraw_items()
	view._animate_wheel(0.1)
	view._animate_wheel(0.1)
	var head: MeshInstance3D
	for row in meshes(view, "press"):
		if row.role == "head":
			head = row.node
	verify(head != null, "The clearance case uses the actual moving press head.")
	if head == null:
		view.free()
		return
	var head_bounds := bounds_in_view(head, view)
	var workpiece_top := -INF
	var billet_count := 0
	var boss_found := false
	for item in view.item_root.get_children():
		if item.get_meta("item_kind", "") != "workpiece_billet":
			continue
		billet_count += 1
		for part in item.get_children():
			if not part is MeshInstance3D:
				continue
			var part_bounds := bounds_in_view(part, view)
			if part_bounds.position.x < head_bounds.end.x and part_bounds.end.x > head_bounds.position.x and part_bounds.position.z < head_bounds.end.z and part_bounds.end.z > head_bounds.position.z:
				workpiece_top = maxf(workpiece_top, part_bounds.end.y)
				boss_found = boss_found or part.get_meta("asset_role", "") == "CenterBoss"
	verify(billet_count == 1 and boss_found and is_finite(workpiece_top),
		"The actual item redraw supplies the held billet and its raised boss under the head.")
	verify(head_bounds.position.y >= workpiece_top + 0.002,
		"The lowered head clears every overlapping held-workpiece part by at least two millimetres.")
	verify(head_bounds.position.y < 0.754 and view.state == observed and pick_facts(view) == picks and view.request_sequence == 0,
		"The head moves while stock, requests and pick geometry remain unchanged.")
	print(JSON.stringify({"phase": "held workpiece clearance", "head_bottom": head_bounds.position.y,
		"workpiece_top": workpiece_top, "gap": head_bounds.position.y - workpiece_top}))
	view.free()

func check_batched_collector_motion() -> void:
	var view := BatchedView.new()
	root.add_child(view)
	mount(view)
	for index in range(11):
		var id := "collector-%d" % index
		# This render fixture reuses the admitted source cell with distinct IDs;
		# it does not claim twelve legal simultaneous placements.
		view.state.entities[id] = {"kind": "collector", "cell": [0, 0],
			"generation": 1, "axis": 2}
		view.state.motion[id] = {"state": "rotating", "numerator": 1, "denominator": 1}
	view._rebuild_machines()
	var observed: Dictionary = view.state.duplicate(true)
	var picks := pick_facts(view)
	verify(view.machine_root.get_child_count() == view.state.entities.size() + 1,
		"The topology rebuild emits one render-batch root for its machines.")
	var first := machine(view, "collector")
	var second := machine(view, "collector-0")
	var first_slot: Dictionary = view.machine_cutter_batch_slots.get(first.get_instance_id(), {})
	var second_slot: Dictionary = view.machine_cutter_batch_slots.get(second.get_instance_id(), {})
	verify(view.machine_cutter_batch_slots.size() == 12 and not first_slot.is_empty()
		and not second_slot.is_empty() and first_slot.mesh == second_slot.mesh
		and first_slot.index != second_slot.index,
		"Twelve collectors share one complete moving assembly while retaining distinct instance slots.")
	if first_slot.is_empty() or second_slot.is_empty():
		view.free()
		return
	for row in meshes(view, "collector"):
		verify(not row.node.visible, "The batched cutter hides its individual source geometry.")
	view.transmission_presenter._native_phase_lazy = true
	view.transmission_presenter._visual_rates["collector"] = 1.0
	view.transmission_presenter._visual_rates["collector-0"] = -1.0
	view.transmission_presenter._native_phase_elapsed = 0.25
	view._animate_machine_bodies(0.1)
	for entry in [[first, first_slot, 1.0], [second, second_slot, -1.0]]:
		var anchor: Node3D = entry[0]
		var slot: Dictionary = entry[1]
		var signed_rate: float = entry[2]
		var angle: float = 0.25 * signed_rate * Presenter.VISUAL_RADIANS_PER_SECOND
		var center := anchor.position + Vector3(-0.22, 1.1, -0.19)
		var flute_at_rest := Vector3(0.015, 1.1, -0.19)
		var expected := center + Basis(Vector3.BACK, angle) * (flute_at_rest - Vector3(-0.22, 1.1, -0.19))
		var actual: Transform3D = slot.mesh.get_instance_transform(slot.index)
		verify((actual * flute_at_rest).is_equal_approx(expected),
			"Each combined cutter follows its own confirmed phase and the real flute orbit.")
	verify(view.state == observed and pick_facts(view) == picks and view.request_sequence == 0,
		"Batching moving art leaves observed state, picks and request sequence unchanged.")
	var cutter_rows: Array = meshes(view, "collector")
	for property: String in ["layers", "cast_shadow"]:
		var originals: Array = []
		for row in cutter_rows:
			originals.append(row.node.get(property))
		var different: int = int(originals[0]) ^ 2 if property == "layers" else \
			(GeometryInstance3D.SHADOW_CASTING_SETTING_ON if originals[0] == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		for row in cutter_rows:
			row.node.set(property, different)
		var groups: Dictionary = {}
		var skipped: Dictionary = {}
		view._batch_collector_cutters(groups, skipped)
		verify(groups.is_empty() and skipped.is_empty(),
			"Collectors with distinct %s retain their own artwork below the compatible batch threshold." % property)
		for index in cutter_rows.size():
			cutter_rows[index].node.set(property, originals[index])
	view._rebuild_machines()
	var replacement := machine(view, "collector")
	var replacement_slot: Dictionary = view.machine_cutter_batch_slots.get(replacement.get_instance_id(), {})
	verify(replacement != first and view.machine_cutter_batch_slots.size() == 12
		and not replacement_slot.is_empty() and replacement_slot.mesh != first_slot.mesh,
		"A topology rebuild replaces stale cutter render slots with the new anchors.")
	view.free()

func _initialize() -> void:
	if "--clearance-only" in OS.get_cmdline_user_args():
		check_held_workpiece_clearance()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"scope": "actual head and redrawn billet clearance", "native_gameplay": "not_run", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
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
	verify(is_equal_approx(view.transmission_presenter.visual_angle("collector"), expected_rotation(0.1)),
		"The cutter consumes the existing presenter angle without a second rate clock.")
	var flute_verified := false
	for row in meshes(view, "collector"):
		if row.node.get_meta("detail_role", "") == "CutterFlute" and row.rest.origin.is_equal_approx(Vector3(0.015, 1.1, -0.19)):
			var actual: Transform3D = row.parent_inverse.affine_inverse() * row.node.transform
			verify(actual.origin.is_equal_approx(Vector3(-0.22 + 0.235 * cos(expected_rotation(0.1)),
				1.1 + 0.235 * sin(expected_rotation(0.1)), -0.19)),
				"A real flute orbits the fixed drum center using an independent trigonometric point.")
			flute_verified = true
	verify(flute_verified and view.state == original and pick_facts(view) == picks and view.request_sequence == sequence,
		"Render motion preserves authoritative observations, request sequence and pick geometry.")
	check_bounds(view)
	hold(view)
	var held: Dictionary = view.state.duplicate(true)
	view._animate_wheel(0.1)
	verify(is_equal_approx(pose(view, "head").origin.y, 0.828), "A newly observed held blank eases the head down rather than snapping or inventing a cycle.")
	view._rebuild_machines()
	verify(is_equal_approx(pose(view, "head").origin.y, 0.828), "An unrelated geometry refresh retains the in-progress render pose.")
	view._animate_wheel(0.1)
	verify(is_equal_approx(pose(view, "head").origin.y, 0.825), "The held pose reaches the bounded 0.015 metre travel.")
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
	verify(is_equal_approx(pose(view, "head").origin.y, 0.837), "Only a new empty-held observation lets the head rise.")
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
	verify(is_equal_approx(pose(view, "head").origin.y, 0.825), "A fresh context starts at its observed held pose without replaying an operation.")
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
	verify(is_equal_approx(pose(shared, "head").origin.y, 0.828), "An unrelated pending shared request does not stop confirmed work presentation.")
	facts.ready = false
	var disconnected := pose_list(shared)
	shared._animate_wheel(0.1)
	verify(pose_list(shared) == disconnected, "Lost shared freshness freezes both cutter and tool.")
	shared.free()
	check_held_workpiece_clearance()
	check_batched_collector_motion()
	check_conveyor_motion(false)
	check_conveyor_motion(true)
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"scope": "actual mesh transforms over invented observations", "native_gameplay": "not_run", "desktop": "not_used"}))
	quit(1 if failed else 0)
