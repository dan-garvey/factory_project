extends SceneTree
## Real view callbacks over invented projections and a request sink, never a game.
const Controls = preload("res://opening/native_transmission_controls.gd")
const Cue = preload("res://opening/native_transmission_endpoint_cue.gd")

class OfflineHarness:
	extends "res://opening/opening.gd"
	var requests: Array = []
	func issue(wire: Dictionary) -> Dictionary:
		requests.append(wire.duplicate(true))
		return {"accepted": false, "queued": true}

class SharedHarness:
	extends "res://opening/shared_opening.gd"
	var requests: Array = []
	func _update_camera() -> void:
		pass # Detached callback controls create no camera or viewport input.
	func issue(wire: Dictionary) -> Dictionary:
		requests.append(wire.duplicate(true))
		return {"accepted": false, "queued": true}

class Connection:
	extends RefCounted
	var ready := true
	func is_ready() -> bool:
		return ready

var checks := 0
var failures := 0

func verify(condition: bool, words: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(words)

func fixture() -> Dictionary:
	return {"context": "endpoint-cue", "options": {"native": true, "physical": true},
		"actors": {"P": {"ready": true}, "Q": {"ready": true}},
		"entities": {"wheel": {"kind": "wheel", "generation": 1, "axis": 1, "center": [-4, 0, 4]}},
		"transmission_parts": {"gear": {"kind": "gear", "generation": 2, "axis": 1, "center": [0, 4, 4], "teeth": 2}},
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

func first(view, id: String = "wheel") -> void:
	view.transmission_controls.choose_tool("shaft")
	view._transmission_click([], id)

func physics_nodes(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += physics_nodes(child)
	return count

func check_offline() -> void:
	var view := OfflineHarness.new()
	mount(view)
	var original: Dictionary = view.state.duplicate(true)
	view._refresh_endpoint_cue()
	verify(view.transmission_endpoint_cue == null, "An idle tool creates no marker or native resource dependency.")
	first(view)
	var cue = view.transmission_endpoint_cue
	verify(cue != null and cue.visible, "The actual first-click callback immediately marks its endpoint.")
	verify(cue.position.is_equal_approx(Vector3(-1.65, 0.5, 1.65)) and cue.basis.y == Vector3.UP, "The machine cue uses its literal confirmed center and axis.")
	verify(view.requests.is_empty() and view.state == original and view.model == null, "The first click creates no request, quantity or authority.")
	verify(physics_nodes(cue) == 0, "The cue has no pick, physics or actor shape.")
	var ring: MeshInstance3D = cue.get_node("EndpointRing")
	var ring_id: int = ring.get_instance_id()
	var mesh_id: int = ring.mesh.get_instance_id()
	var material_id: int = ring.material_override.get_instance_id()
	view._refresh_endpoint_cue()
	verify(cue == view.transmission_endpoint_cue and ring.get_instance_id() == ring_id and ring.mesh.get_instance_id() == mesh_id and ring.material_override.get_instance_id() == material_id, "An unchanged refresh retains the cue, mesh and finish.")
	var annotation: Dictionary = view.transmission_controls.pending_endpoint()
	annotation.center[0] = 999
	verify(view.state == original and view.transmission_controls.pending_endpoint().center == [-4, 0, 4], "The annotation exposes no mutable projection alias.")
	view._transmission_click([], "gear")
	verify(view.requests == [{"action": "connect_drive", "from": "wheel", "to": "gear"}] and not cue.visible, "The second click preserves the exact existing request and clears the annotation even for a queued reply.")
	first(view)
	view.transmission_controls.cancel()
	view._refresh_endpoint_cue()
	verify(not cue.visible, "Cancellation hides the annotation.")
	for change in ["generation", "remove", "context", "actor", "axis", "center", "kit"]:
		view.state = fixture()
		view.client = "P"
		first(view)
		match change:
			"generation": view.state.entities.wheel.generation = 9
			"remove": view.state.entities.erase("wheel")
			"context": view.state.context = "other-world"
			"actor": view.client = "Q"
			"axis": view.state.entities.wheel.axis = true
			"center": view.state.entities.wheel.center = [-4.0, 0, 4]
			"kit": view.state.part_specifications.P[0].count = 0
		view._refresh_endpoint_cue()
		verify(not cue.visible, "An unusable first endpoint cannot retain its annotation: " + change)
	view.state = fixture()
	view.client = "P"
	for flag in ["explanation_open", "startup_save_pending"]:
		first(view)
		view.set(flag, true)
		view.transmission_controls.refresh()
		view._refresh_endpoint_cue()
		verify(not cue.visible, "A blocked view hides the annotation: " + flag)
		view.set(flag, false)
	first(view)
	view.state.actors.P.ready = false
	view._refresh_endpoint_cue()
	verify(not cue.visible, "An unready actor cannot retain an active annotation.")
	view.state = fixture()
	for axis in range(3):
		view.state.transmission_parts.gear.axis = axis
		first(view, "gear")
		verify(cue.position.is_equal_approx(Vector3(0, 2.15, 1.65)) and cue.basis.y.is_equal_approx([Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis]), "Cog annotations follow every declared spindle axis.")
		verify((cue.basis * cue.get_node("EndpointCaption").position).is_equal_approx(Vector3.UP * 1.155), "The caption remains above the spindle on every axis.")
		verify(is_equal_approx(ring.mesh.inner_radius, 0.905) and is_equal_approx(ring.mesh.outer_radius, 0.945), "The cog cue outlines its confirmed view radius.")
	verify(view.state.stock.is_empty() and view.model == null, "Axis controls add no material or authority.")
	view.state = fixture()
	view.state.part_specifications.P = [{"kind": "shaft", "teeth": 0, "half_span": 4, "count": 2}]
	first(view)
	verify(cue.visible and view.transmission_controls.pending_endpoint().get("id") == "wheel",
		"A long-only kit keeps the first endpoint marker visible.")
	view.state.part_specifications.P[0].count = 0
	view._refresh_endpoint_cue()
	verify(not cue.visible, "The marker still disappears when the last long shaft is gone.")
	view.free()

func check_shared() -> void:
	var view := SharedHarness.new()
	view.session = Connection.new()
	mount(view)
	first(view)
	verify(view.transmission_endpoint_cue.visible and view.requests.is_empty(), "A ready shared view marks its first endpoint locally.")
	for blocker in ["disconnected", "pending"]:
		view.session.ready = true
		view.pending_actions.clear()
		first(view)
		if blocker == "disconnected":
			view.session.ready = false
		else:
			view.pending_actions = {"queued": {"action": "place"}}
		view.transmission_controls.refresh()
		view._refresh_endpoint_cue()
		verify(not view.transmission_endpoint_cue.visible and view.requests.is_empty(), "Shared freshness hides the cue without a request: " + blocker)
	verify(view.model == null, "Shared annotation creates no Model or transport.")
	view.session.ready = true
	view.pending_actions.clear()
	view.state = fixture()
	view.state.part_specifications.P = [{"kind": "shaft", "teeth": 0, "half_span": 4, "count": 1}]
	first(view)
	verify(view.transmission_endpoint_cue.visible and view.requests.is_empty(),
		"A shared long-only kit displays the selected endpoint without issuing a request.")
	view.free()

func check_invalid() -> void:
	var cue := Cue.new()
	for data in [{}, {"id": "a", "kind": "gear", "center": [0, 0, 0], "axis": false, "teeth": 2},
		{"id": "a", "kind": "gear", "center": [0.0, 0, 0], "axis": 1, "teeth": 2},
		{"id": "a", "kind": "gear", "center": [0, 0, 0], "axis": 1, "teeth": true}]:
		cue.refresh(data)
		verify(not cue.visible, "Malformed annotation data creates no usable cue.")
	cue.free()

func check_common_frame() -> void:
	var view := SharedHarness.new()
	view.session = Connection.new()
	mount(view)
	for action in ["cancel", "change_tool", "disconnect"]:
		view.session.ready = true
		first(view)
		verify(view.transmission_endpoint_cue.visible, "The first endpoint is initially displayed before the local change.")
		match action:
			"cancel": view.transmission_controls.cancel()
			"change_tool": view.transmission_controls.choose_tool("gear")
			"disconnect": view.session.ready = false
		# No server snapshot or manual annotation refresh occurs here. Exercise
		# the real shared/common presentation callback with no Model attached.
		view._process(0.016)
		verify(not view.transmission_endpoint_cue.visible,
			"The next common frame hides the obsolete shared annotation: " + action)
	verify(view.requests.is_empty() and view.model == null,
		"Common-frame cancellation sends no request and creates no Model.")
	view.free()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if "--common-frame-only" in OS.get_cmdline_user_args():
		check_common_frame()
	else:
		check_offline()
		check_shared()
		check_invalid()
		check_common_frame()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks, "failures": failures, "evidence": "isolated_endpoint_annotation", "models": 0, "desktop_operations": 0}))
	quit(0 if failures == 0 else 1)
