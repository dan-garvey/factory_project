extends SceneTree
## Automated mesh/collision-contract checks. No desktop, input or game stepping.
const Opening = preload("res://opening/opening.gd")
const Geometry = preload("res://opening/site_geometry.gd")

var checks := 0
var failed := false
var mesh_count := 0

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func _mesh_bounds(node: Node, parent_transform: Transform3D, low: Vector3, high: Vector3) -> void:
	var at := parent_transform
	if node is Node3D:
		at = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		mesh_count += 1
		var mesh := node as MeshInstance3D
		var bounds: AABB = mesh.mesh.get_aabb()
		_check(mesh.material_override is StandardMaterial3D, "Machine meshes retain explicit built-in materials.")
		for x in [bounds.position.x, bounds.end.x]:
			for y in [bounds.position.y, bounds.end.y]:
				for z in [bounds.position.z, bounds.end.z]:
					var point: Vector3 = at * Vector3(x, y, z)
					# This allowance only accommodates mesh float arithmetic. It
					# changes neither a collider nor an interaction/reach check.
					_check(point.x >= low.x - 0.00001 and point.x <= high.x + 0.00001
						and point.y >= low.y - 0.00001 and point.y <= high.y + 0.00001
						and point.z >= low.z - 0.00001 and point.z <= high.z + 0.00001,
						"Machine mesh exceeds the unchanged collision envelope: " + str(node.name))
	for child in node.get_children():
		_mesh_bounds(child, at, low, high)

func _pick_bodies(node: Node) -> int:
	var count := 0
	if node is CollisionObject3D:
		count += 1
		_check(node is StaticBody3D, "Visuals introduce no additional physics-body type.")
		var body := node as CollisionObject3D
		_check(body.collision_layer == Geometry.PICK_LAYER and body.collision_mask == 0,
			"The original pick layer and mask remain exact.")
		_check(body.get_meta("entity", "") == "fixture", "Picking retains the authoritative entity identifier.")
		_check(body.get_child_count() == 1 and body.get_child(0) is CollisionShape3D,
			"Each entity keeps exactly one pick collider.")
		var collider := body.get_child(0) as CollisionShape3D
		_check(collider.shape is BoxShape3D and (collider.shape as BoxShape3D).size == Vector3(
			Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2]),
			"Visual geometry cannot resize the pick envelope.")
		_check(collider.position == Vector3(0, Geometry.MACHINE_CENTER_HEIGHT, 0),
			"The original pick center remains exact.")
	for child in node.get_children():
		count += _pick_bodies(child)
	return count

func _initialize() -> void:
	var half := Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2]) / 2.0
	var low := Vector3(0, Geometry.MACHINE_CENTER_HEIGHT, 0) - half
	var high := Vector3(0, Geometry.MACHINE_CENTER_HEIGHT, 0) + half
	for kind in ["collector", "belt", "processor", "wheel"]:
		var view := Opening.new()
		view.machine_root = Node3D.new()
		view.item_root = Node3D.new()
		view.state = {
			"entities": {"fixture": {"kind": kind, "cell": [0, 0]}},
			"links": [], "drive_links": [],
			"stock": {"source": 0, "collector": 1, "belt": 1, "input": 1, "held": 1, "output": 1}
		}
		var before: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		_check(_pick_bodies(view.machine_root) == 1, "Presentation keeps one pick body per placed entity.")
		mesh_count = 0
		_mesh_bounds(view.machine_root, Transform3D.IDENTITY, low, high)
		_check(mesh_count >= 3, "Each machine has a distinct constructed silhouette.")
		if kind == "wheel":
			for sample_index in range(24):
				view.wheel_rotor.rotation.z = sample_index * TAU / 24.0
				_mesh_bounds(view.machine_root, Transform3D.IDENTITY, low, high)
		view._redraw_items()
		_mesh_bounds(view.item_root, Transform3D.IDENTITY, low, high)
		_check(view.state == before, "Mesh and item rendering cannot mutate the authoritative projection.")
		view.machine_root.free()
		view.item_root.free()
		view.free()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"scope": "invented headless mesh bounds, pick contract and read-only projection",
		"desktop": "not_used", "gameplay": "not_assessed"}))
	quit(1 if failed else 0)
