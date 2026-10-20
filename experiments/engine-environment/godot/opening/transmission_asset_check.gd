extends SceneTree
## Fitted transmission geometry only. No World, input, network or desktop.
const Assets = preload("res://opening/native_transmission_assets.gd")
const Presenter = preload("res://opening/native_transmission_presenter.gd")
var checks := 0
var failed := false
var checked_meshes: Dictionary = {}
var max_tangent_dot := 0.0
var visual_instances := 0

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000)]

func check_mesh(mesh: Mesh) -> void:
	if checked_meshes.has(mesh):
		return
	checked_meshes[mesh] = true
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for n in range(vertices.size()):
			indices.append(n)
	verify(vertices.size() > 0 and indices.size() % 3 == 0 and normals.size() == vertices.size()
		and uvs.size() == vertices.size() and tangents.size() == vertices.size() * 4,
		"Every new render mesh has complete normal-mapped triangle attributes.")
	var edges: Dictionary = {}
	var valid_faces := true
	var valid_attributes := true
	var volume := 0.0
	for n in range(0, indices.size(), 3):
		var a := vertices[indices[n]]
		var b := vertices[indices[n + 1]]
		var c := vertices[indices[n + 2]]
		var cross := (b - a).cross(c - a)
		valid_faces = valid_faces and cross.length_squared() > 0.00000000000001
		valid_faces = valid_faces and cross.dot(normals[indices[n]]) < 0
		volume += a.dot(b.cross(c)) / 6.0
		for pair in [[a, b], [b, c], [c, a]]:
			var first := key(pair[0])
			var second := key(pair[1])
			var edge := first + "/" + second if first < second else second + "/" + first
			edges[edge] = int(edges.get(edge, 0)) + 1
	for n in range(vertices.size()):
		var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
		max_tangent_dot = maxf(max_tangent_dot, absf(tangent.dot(normals[n])))
		valid_attributes = valid_attributes and vertices[n].is_finite() and normals[n].is_finite() and uvs[n].is_finite()
		valid_attributes = valid_attributes and is_equal_approx(normals[n].length(), 1.0)
		valid_attributes = valid_attributes and tangent.is_finite() and tangent.length() > 0.99
		valid_attributes = valid_attributes and absf(tangent.dot(normals[n])) < 0.0002
	var closed := true
	for count in edges.values():
		closed = closed and count == 2
	verify(valid_faces and volume < -0.00000001, "New assets retain clockwise outward faces and a nonzero enclosed volume.")
	verify(closed, "Every geometric edge of the authored solid is closed exactly twice.")
	verify(valid_attributes, "Packed normals, tangents and surface coordinates remain finite and usable.")

func check_bounds(node: Node3D, pose: Transform3D, center: Vector3, axis: Vector3,
		radius: float, half_length: float) -> void:
	verify(not node is CollisionObject3D and not node is CollisionShape3D and node.get_script() == null,
		"The asset module supplies no collision, input or state-owner node.")
	if node is MeshInstance3D:
		visual_instances += 1
		check_mesh(node.mesh)
		var bounded := true
		var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point: Vector3 = pose * vertex - center
			var along := point.dot(axis)
			var radial := point - axis * along
			bounded = bounded and absf(along) <= half_length + 0.000001 and radial.length() <= radius + 0.000001
		verify(bounded, "Fitted details stay inside the independently specified native/pick envelope on the actual axis.")
	for child in node.get_children():
		if child is Node3D:
			check_bounds(child, pose * child.transform, center, axis, radius, half_length)

func roles(node: Node, role: String) -> int:
	var count := 1 if node.get_meta("asset_role", "") == role else 0
	for child in node.get_children():
		count += roles(child, role)
	return count

func check_assemblies() -> void:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var center := Vector3(-1.65, 0.9125, 3.3)
	var previous: Mesh = null
	for axis in range(3):
		var gear := Node3D.new()
		gear.position = center
		gear.basis = Presenter.axis_basis(axis)
		Assets.gear(gear, 0.825, 2, Color("ba9459"))
		verify(roles(gear, "GearTooth") == 16 and roles(gear, "GearSpoke") == 4
			and roles(gear, "HubFastener") == 8, "The ordinary two-unit gear has sixteen beveled render teeth, four spokes and fitted hub fasteners.")
		verify(gear.get_node("Gear").mesh == previous if previous != null else true,
			"Changing the world axis reuses the identical cached rim mesh.")
		previous = gear.get_node("Gear").mesh
		verify(gear.get_node("GearTooth").mesh == Assets.tooth_mesh(0.825, 16),
			"Repeated teeth share one closed authored tooth asset.")
		check_bounds(gear, gear.transform, center, axes[axis], 0.825, 0.12)
		var shaft := Node3D.new()
		shaft.position = center
		shaft.basis = Presenter.axis_basis(axis)
		Assets.shaft(shaft, 1.65, Color("687a7b"))
		var mesh: CylinderMesh = shaft.get_node("Shaft").mesh
		verify(is_equal_approx(mesh.height, 1.65) and is_equal_approx(mesh.top_radius, 0.045) and mesh.radial_segments == 48,
			"The named shaft remains a CylinderMesh with its literal endpoint length and core radius.")
		verify(roles(shaft, "ShaftCollar") == 2 and roles(shaft, "ShaftKey") == 2,
			"The shaft has a fitted collar and key at both ends.")
		check_bounds(shaft, shaft.transform, center, axes[axis], 0.08, 0.825)
		gear.free()
		shaft.free()
	for units in [1, 3]:
		var gear := Node3D.new()
		var radius := float(units) * 0.4125
		Assets.gear(gear, radius, units, Color("687a7b"))
		verify(roles(gear, "GearTooth") == units * 8, "Decorative tooth density remains proportional for other ratio sizes.")
		check_bounds(gear, Transform3D.IDENTITY, Vector3.ZERO, Vector3.UP, radius, 0.12)
		gear.free()

func _initialize() -> void:
	for units in [1, 2, 3]:
		var mesh: ArrayMesh = Assets.tooth_mesh(float(units) * 0.4125, units * 8)
		verify(mesh == Assets.tooth_mesh(float(units) * 0.4125, units * 8), "The exact tooth profile is cached by its geometry inputs.")
		check_mesh(mesh)
	if "--tooth-only" not in OS.get_cmdline_user_args():
		check_assemblies()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"unique_meshes": checked_meshes.size(), "visual_instances": visual_instances,
		"maximum_packed_tangent_dot": max_tangent_dot, "rendered_quality": "not_assessed", "desktop": "not_used"}))
	quit(1 if failed else 0)
