extends SceneTree
## New headless visual regression checks. No input or authoritative game steps.
const Opening = preload("res://opening/opening.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const EPSILON := 0.00001

var checks := 0
var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_meshes(child))
	return result

func _ends(mesh: MeshInstance3D) -> Array[Vector3]:
	var size := (mesh.mesh as BoxMesh).size
	return [mesh.global_transform * Vector3(0, 0, -size.z / 2.0),
		mesh.global_transform * Vector3(0, 0, size.z / 2.0)]

func _check_direction(cell: Vector2i) -> void:
	var view := Opening.new()
	view.machine_root = Node3D.new()
	# Attach only the mesh container. Opening._ready never runs; there is no
	# Model, controller, actor or gameplay tick. This also supports the retained
	# predecessor's world-space bar construction for a discriminating baseline.
	root.add_child(view.machine_root)
	view.state = {"entities": {
		"source": {"kind": "collector", "cell": [0, 0]},
		"target": {"kind": "belt", "cell": [cell.x, cell.y]}},
		"links": [["source", "target"]], "drive_links": []}
	var before: Dictionary = view.state.duplicate(true)
	view._rebuild_machines()
	var route: Node = view.machine_root.get_child(view.machine_root.get_child_count() - 1)
	var parts := _meshes(route)
	_check(parts.size() == 3, "A confirmed route needs a rail and two directional arrow arms.")
	var rail := parts[0]
	for mesh in parts:
		if (mesh.mesh as BoxMesh).size.z > (rail.mesh as BoxMesh).size.z:
			rail = mesh
	var expected := Vector3(cell.x, 0, cell.y).normalized()
	var target := expected * Geometry.PITCH
	var ends := _ends(rail)
	for point in ends:
		var planar := Vector3(point.x, 0, point.z)
		_check(planar.cross(expected).length() < EPSILON,
			"Route endpoints must align with their actual linked grid direction.")
		_check(planar.dot(expected) > 0.0 and planar.dot(expected) < target.length(),
			"The rail stays between the confirmed source and target centers.")
		_check(absf(point.y - 0.45) < EPSILON, "The existing transfer height remains exact.")
	if parts.size() == 3:
		var arms: Array[MeshInstance3D] = []
		for mesh in parts:
			if mesh != rail:
				arms.append(mesh)
		var left := _ends(arms[0])
		var right := _ends(arms[1])
		var common := false
		for i in range(2):
			for j in range(2):
				if left[i].distance_to(right[j]) < EPSILON:
					common = true
					_check(left[i].dot(expected) > left[1 - i].dot(expected)
						and right[j].dot(expected) > right[1 - j].dot(expected),
						"The shared arrow tip must point toward the confirmed target.")
		_check(common, "The two arrow arms meet at one tip.")
	_check(view.state == before, "Route drawing cannot modify confirmed topology.")
	view.machine_root.free()
	view.free()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not root.is_inside_tree():
		push_error("Route fixture requires an entered scene tree before reading global transforms.")
		quit(1)
		return
	for cell in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		_check_direction(cell)
	print(JSON.stringify({"status": "pass" if failures.is_empty() else "fail",
		"checks": checks, "failures": failures, "cardinal_cases": 4,
		"scope": "invented headless confirmed-route geometry", "desktop": "not_used"}))
	quit(0 if failures.is_empty() else 1)
