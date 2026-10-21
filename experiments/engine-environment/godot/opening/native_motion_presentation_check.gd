extends SceneTree
## Invented confirmed-state structures exercise presentation only. No Model,
## actor, Session transport, native step or desktop interaction is created.
const Opening = preload("res://opening/opening.gd")
const Shared = preload("res://opening/shared_opening.gd")
const Presenter = preload("res://opening/native_transmission_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")

class Connection extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

var checks := 0
var failures := 0

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fixture() -> Dictionary:
	return {"context": "motion-view", "options": {"native": true, "physical": true},
		"actors": {"P": {"ready": true}}, "parts": {}, "stock": {}, "inventories": {"P": 0},
		"entities": {"wheel": {"kind": "wheel", "generation": 1, "axis": 0, "center": [-4, 0, 0], "cell": [-1, 0]}},
		"transmission_parts": {
			"a": {"kind": "gear", "generation": 2, "axis": 0, "center": [0, 0, 0], "teeth": 2},
			"b": {"kind": "gear", "generation": 3, "axis": 0, "center": [0, 0, 4], "teeth": 2},
			"s": {"kind": "shaft", "generation": 4, "axis": 0, "center": [-2, 0, 0], "half_span": 2}},
		"motion": {"wheel": {"state": "rotating", "numerator": 1, "denominator": 1},
			"a": {"state": "rotating", "numerator": 1, "denominator": 1},
			"b": {"state": "rotating", "numerator": -1, "denominator": 1},
			"s": {"state": "rotating", "numerator": 1, "denominator": 1}},
		"engagements": []}

func mount(view) -> void:
	view.state = fixture()
	view.client = "P"
	view.transmission_presenter = Presenter.new()
	view.add_child(view.transmission_presenter)
	view.transmission_presenter.configure(view)

func part(view, id: String) -> Node3D:
	for child: Node in view.transmission_presenter.get_children():
		if child.get_meta("entity", "") == id:
			return child
	return null

func inside_wheel_proxy(node: Node, parent: Transform3D, half: Vector3) -> bool:
	var at: Transform3D = parent * node.transform if node is Node3D else parent
	if node is MeshInstance3D:
		for surface_index in node.mesh.get_surface_count():
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point: Vector3 = at * vertex - Vector3.UP * Geometry.ANCHOR_HEIGHT
				if not point.is_finite() or absf(point.x) > half.x + 0.0001 or absf(point.y) > half.y + 0.0001 or absf(point.z) > half.z + 0.0001:
					return false
	for child: Node in node.get_children():
		if not inside_wheel_proxy(child, at, half):
			return false
	return true

func check_rotation_and_identity() -> void:
	var one_step := wrapf(Presenter.VISUAL_RADIANS_PER_SECOND * 0.1, -PI, PI)
	var two_steps := wrapf(Presenter.VISUAL_RADIANS_PER_SECOND * 0.2, -PI, PI)
	var negative_one_and_half := wrapf(-Presenter.VISUAL_RADIANS_PER_SECOND * 0.15, -PI, PI)
	var view := Opening.new()
	mount(view)
	var original: Dictionary = view.state.duplicate(true)
	var presenter = view.transmission_presenter
	var a := part(view, "a")
	var pick: Node3D = a.get_node("Pick")
	var shape: CylinderShape3D = pick.get_child(0).shape
	var original_pick := shape.get_instance_id()
	var original_center := a.position
	var original_axis := a.basis.y
	view._animate_wheel(0.1)
	verify(is_equal_approx(presenter.visual_angle("a"), one_step) and is_equal_approx(presenter.visual_angle("b"), -one_step),
		"Confirmed equal rates illustrate opposite signed rotation.")
	verify(view.state == original and view.model == null, "Illustration neither mutates the confirmed projection nor creates authority.")
	verify(a.position == original_center and a.basis.y.is_equal_approx(original_axis), "Cosmetic rotation retains the exact spindle center and axis.")
	verify(shape.get_instance_id() == original_pick and pick.collision_layer == 4 and pick.collision_mask == 0,
		"The original axisymmetric pick shape is retained, without an actor collider.")
	verify((a.basis * a.get_node("ConfirmedDirection").basis).is_equal_approx(Presenter.axis_basis(0)),
		"The signed direction annotation stays fixed while the rotor turns.")
	verify(part(view, "s").has_node("Keyway") and is_equal_approx(presenter.visual_angle("s"), one_step),
		"A shaft keyway makes its confirmed motion visible without changing the span.")
	presenter.refresh()
	verify(part(view, "a") == a and is_equal_approx(presenter.visual_angle("a"), one_step), "An unchanged refresh preserves nodes and cosmetic angle.")
	# Invented rate changes test display mapping, not a new mechanical solution.
	view.state.motion.b = {"state": "rotating", "numerator": -1, "denominator": 2}
	presenter.refresh()
	view._animate_wheel(0.1)
	verify(is_equal_approx(presenter.visual_angle("a"), two_steps) and is_equal_approx(presenter.visual_angle("b"), negative_one_and_half),
		"A changed native ratio changes only subsequent cosmetic speed, without resetting the retained angle.")
	for status: String in ["stalled", "disconnected", "unknown"]:
		for entry: Dictionary in view.state.motion.values():
			entry.state = status
		presenter.refresh()
		view._animate_wheel(0.1)
		verify(is_equal_approx(presenter.visual_angle("a"), two_steps), "Nonrotating confirmed state freezes presentation: " + status)
	view.state = original.duplicate(true)
	presenter.refresh()
	var before: Dictionary = view.state.duplicate(true)
	for delta: float in [-1.0, 0.0, INF, NAN]:
		view._animate_wheel(delta)
		verify(is_equal_approx(presenter.visual_angle("a"), two_steps), "Invalid or nonpositive frame time adds no angle.")
	verify(view.state == before, "All invalid-time controls leave their input projection unchanged.")
	view.explanation_open = true
	view._animate_wheel(0.1)
	verify(is_equal_approx(presenter.visual_angle("a"), two_steps), "Help suspends cosmetic motion without touching the factory.")
	view.explanation_open = false
	view.state.transmission_parts.a.generation = 9
	presenter.refresh()
	verify(presenter.visual_angle("a") == 0.0 and is_equal_approx(presenter.visual_angle("b"), negative_one_and_half), "Replacement identity resets only that part's cosmetic state.")
	view.state.transmission_parts.erase("b")
	presenter.refresh()
	verify(presenter.visual_angle("b") == 0.0, "Removed part state is pruned.")
	view.state.context = "another-world"
	presenter.refresh()
	verify(presenter.visual_angle("a") == 0.0 and presenter.visual_angle("wheel") == 0.0, "A new world never borrows another context's presentation.")
	verify(view.model == null, "Fixture identity edits never create a game authority.")
	view.free()

func check_wheels() -> void:
	var one_step := wrapf(Presenter.VISUAL_RADIANS_PER_SECOND * 0.1, -PI, PI)
	for axis: int in [0, 1, 2]:
		var view := Opening.new()
		mount(view)
		view.state.entities.wheel.axis = axis
		var holder := Node3D.new()
		view.add_child(holder)
		view._wheel_visual(holder, view.state.entities.wheel)
		var before: Dictionary = view.state.duplicate(true)
		var original: Transform3D = view.wheel_rotor.transform
		view._animate_wheel(0.1)
		verify(view.wheel_rotor.basis.is_equal_approx(original.basis * Basis(Vector3.BACK, one_step)), "The native wheel follows confirmed rotation on axis " + str(axis))
		verify(view.wheel_rotor.position == original.origin and view.wheel_rotor.scale.is_equal_approx(original.basis.get_scale()), "Wheel motion preserves its fitted hub and scale.")
		verify(inside_wheel_proxy(holder, Transform3D.IDENTITY, Geometry.wheel_half_extents(axis, 3)),
			"The illustrated wheel remains inside the native three-tile collision envelope on axis " + str(axis))
		holder.position.x = Geometry.wheel_half_extents(axis, 3).x * 2.0 + 1.0
		verify(not inside_wheel_proxy(holder, Transform3D.IDENTITY, Geometry.wheel_half_extents(axis, 3)),
			"The wheel envelope check rejects displaced artwork on axis " + str(axis))
		holder.position.x = 0.0
		view._wheel_visual(holder, view.state.entities.wheel)
		view._animate_wheel(0.0)
		verify(view.wheel_rotor.basis.is_equal_approx(original.basis * Basis(Vector3.BACK, one_step)), "A rebuilt wheel mesh recovers the same identity's cosmetic angle.")
		for sample in range(12):
			view._animate_wheel(0.037)
			verify(inside_wheel_proxy(holder, Transform3D.IDENTITY, Geometry.wheel_half_extents(axis, 3)),
				"Rotating wheel artwork stays inside its native envelope on axis %d at sample %d." % [axis, sample])
		verify(view.state == before and view.model == null, "Wheel illustration mutates neither projection nor authority.")
		view.free()

func check_shared_freshness() -> void:
	var one_step := wrapf(Presenter.VISUAL_RADIANS_PER_SECOND * 0.1, -PI, PI)
	var view := Shared.new()
	mount(view)
	view.session = Connection.new()
	var before: Dictionary = view.state.duplicate(true)
	view.pending_actions = {"queued": {"action": {"action": "place_gear"}}}
	view._animate_wheel(0.1)
	verify(is_equal_approx(view.transmission_presenter.visual_angle("a"), one_step), "Pending construction does not change a still-confirmed running drive.")
	view.session.ready = false
	view._animate_wheel(0.1)
	verify(is_equal_approx(view.transmission_presenter.visual_angle("a"), one_step), "A disconnected shared view cannot keep inventing operation.")
	verify(view.state == before and view.model == null, "Shared presentation emits no command or material update.")
	view.free()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check_rotation_and_identity()
	check_wheels()
	check_shared_freshness()
	for motion: Variant in [{}, {"state": "rotating", "numerator": true, "denominator": 1},
		{"state": "rotating", "numerator": 1, "denominator": 0}, {"state": "rotating", "numerator": 1.0, "denominator": 1}]:
		verify(Presenter.signed_rate(motion) == 0.0, "Malformed rate facts cannot animate parts.")
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks, "failures": failures,
		"evidence": "isolated_native_motion_presentation", "native_models": 0, "desktop_operations": 0}))
	quit(0 if failures == 0 else 1)
