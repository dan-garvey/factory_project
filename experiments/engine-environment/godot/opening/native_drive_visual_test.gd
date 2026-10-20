extends SceneTree
## Isolated native-profile mesh checks; no live Model, tree entry or input.
const Opening = preload("res://opening/opening.gd")
const Geometry = preload("res://opening/site_geometry.gd")

var checks := 0
var failed := false
const EPSILON := 0.00001

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func check_bounds(node: Node, parent_transform: Transform3D, low: Vector3, high: Vector3) -> void:
	var at := parent_transform
	if node is Node3D:
		at = parent_transform * node.transform
	if node is MeshInstance3D:
		var bounds: AABB = node.mesh.get_aabb()
		for x in [bounds.position.x, bounds.end.x]:
			for y in [bounds.position.y, bounds.end.y]:
				for z in [bounds.position.z, bounds.end.z]:
					var point: Vector3 = at * Vector3(x, y, z)
					verify(point.x >= low.x - EPSILON and point.x <= high.x + EPSILON
						and point.y >= low.y - EPSILON and point.y <= high.y + EPSILON
						and point.z >= low.z - EPSILON and point.z <= high.z + EPSILON,
						"Native-profile mesh leaves the original machine envelope: " + str(node.name))
	for child in node.get_children():
		check_bounds(child, at, low, high)

func check_machine(kind: String, axis_index: int, cell: Array) -> void:
	var expected_axis: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis_index]
	var view := Opening.new()
	view.machine_root = Node3D.new()
	view.state = {"options": {"native": true}, "powered": true,
		"entities": {"fixture": {"kind": kind, "cell": cell,
			"center": [cell[0] * 4, 0, cell[1] * 4], "axis": axis_index}}, "links": [], "drive_links": []}
	var before: Dictionary = view.state.duplicate(true)
	view._rebuild_machines()
	var anchor: Node3D = view.machine_root.get_child(0)
	var expected_hub := Vector3(cell[0] * Geometry.PITCH, Geometry.ANCHOR_HEIGHT, cell[1] * Geometry.PITCH)
	var hub: MeshInstance3D
	var at: Transform3D
	if kind == "wheel":
		hub = view.wheel_rotor.get_node("WheelHub")
		at = anchor.transform * view.wheel_rotor.transform * hub.transform
		verify(view.wheel_rotor.basis.z.normalized().dot(expected_axis) > 1.0 - EPSILON,
			"The wheel plane follows its projected axis: " + str(axis_index))
		var bearings := 0
		for child in anchor.get_children():
			if child is MeshInstance3D and str(child.name).begins_with("AxleBearing"):
				bearings += 1
				verify(child.mesh is CylinderMesh and absf(child.basis.y.normalized().dot(expected_axis)) > 1.0 - EPSILON,
					"Each wheel bearing follows the projected axle.")
				verify((anchor.position + child.position - expected_hub).cross(expected_axis).length() < EPSILON,
					"Each bearing lies on the confirmed hub axis.")
		verify(bearings == (1 if axis_index == 1 else 2),
			"A vertical wheel uses its pedestal bearing; horizontal axles retain two bearings.")
		var original_transform: Transform3D = view.wheel_rotor.transform
		view._animate_wheel(1.0)
		verify(view.wheel_rotor.transform == original_transform,
			"Native powered state alone cannot invent a rotation phase.")
	else:
		hub = anchor.get_node("DriveStub")
		at = anchor.transform * hub.transform
	verify(hub.mesh is CylinderMesh, "A visible cylindrical spindle represents the hub.")
	verify(at.origin.distance_to(expected_hub) < EPSILON,
		"The visible spindle passes through the confirmed native hub center.")
	verify(absf(at.basis.y.normalized().dot(expected_axis)) > 1.0 - EPSILON,
		"The visible spindle follows the projected axis: " + str(axis_index))
	var half := Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2]) / 2.0
	var center: Vector3 = anchor.position + Vector3.UP * Geometry.MACHINE_CENTER_HEIGHT
	check_bounds(anchor, Transform3D.IDENTITY, center - half, center + half)
	verify(view.state == before and view.model == null,
		"Native-profile mesh construction cannot mutate projection or create authority.")
	view.machine_root.free()
	view.free()

func check_legacy_boundary() -> void:
	var view := Opening.new()
	view.machine_root = Node3D.new()
	view.state = {"options": {"native": false}, "powered": true,
		"entities": {"fixture": {"kind": "wheel", "cell": [0, 0], "axis": 1}}, "links": [], "drive_links": []}
	view._rebuild_machines()
	verify(view.wheel_rotor.position == Vector3(0, 0.78, 0) and view.wheel_rotor.scale == Vector3.ONE,
		"Scripted wheels retain their original height and dimensions.")
	verify(view.wheel_rotor.basis.z == Vector3.BACK,
		"A native-only axis field cannot rotate the scripted wheel.")
	view._animate_wheel(1.0)
	verify(is_equal_approx(view.wheel_rotor.rotation.z, 0.8),
		"The scripted decorative clock remains available.")
	view.machine_root.free()
	view.free()

func _initialize() -> void:
	for axis_index in range(3):
		for kind in ["collector", "belt", "processor", "wheel"]:
			# These two Y cases use the Host's documented first equal-gear layout.
			var cell := [-1, 1] if axis_index == 1 and kind == "wheel" else [0, 1] if axis_index == 1 and kind == "collector" else [1, 2]
			check_machine(kind, axis_index, cell)
	check_legacy_boundary()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"machine_cases": 12, "axes": ["x", "y", "z"],
		"scope": "projected machine hub, wheel and bearing axes, mesh envelopes and animation boundary",
		"desktop": "not_used", "gameplay": "not_assessed"}))
	quit(1 if failed else 0)
