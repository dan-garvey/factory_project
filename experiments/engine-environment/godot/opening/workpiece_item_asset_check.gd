extends SceneTree
## Headless verification of fitted seam blanks, workpiece billets and stamped
## product plates. No World, input, network or desktop execution.

const Assets = preload("res://opening/workpiece_item_assets.gd")
const Visuals = preload("res://opening/opening.gd").ProductionVisuals
const Geometry = preload("res://opening/site_geometry.gd")

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


func vertex_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000)]


func check_mesh(mesh: Mesh, min_volume: float = 0.0000001, max_volume: float = 1.0) -> void:
	if checked_meshes.has(mesh):
		return
	checked_meshes[mesh] = true
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	verify(
		vertices.size() > 0
		and vertices.size() % 3 == 0
		and normals.size() == vertices.size()
		and uvs.size() == vertices.size()
		and tangents.size() == vertices.size() * 4,
		"Every authored item mesh has complete normal-mapped triangle attributes."
	)
	var edges: Dictionary = {}
	var valid_faces := true
	var valid_attributes := true
	var volume := 0.0
	for n in range(0, vertices.size(), 3):
		var a := vertices[n]
		var b := vertices[n + 1]
		var c := vertices[n + 2]
		var cross := (b - a).cross(c - a)
		valid_faces = valid_faces and cross.length_squared() > 0.00000000000001
		valid_faces = valid_faces and cross.dot(normals[n]) < 0.0
		volume += a.dot(b.cross(c)) / 6.0
		for pair in [[a, b], [b, c], [c, a]]:
			var first := vertex_key(pair[0])
			var second := vertex_key(pair[1])
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
	verify(valid_faces, "Every triangle is noncollapsed with clockwise outward winding.")
	verify(closed, "Every geometric edge of the item mesh is closed exactly twice.")
	verify(
		absf(volume) >= min_volume and absf(volume) <= max_volume,
		"The closed item mesh retains its bounded solid or annular volume."
	)
	verify(valid_attributes, "Normals, UVs and tangents remain finite and orthogonal.")


func check_bounds(node: Node3D, pose: Transform3D, anchor: Vector3, half_extents: Vector3) -> void:
	verify(
		not node is CollisionObject3D and not node is CollisionShape3D and node.get_script() == null,
		"Workpiece and plate visual assemblies contain no collision, input or script authority."
	)
	if node is MeshInstance3D:
		visual_instances += 1
		check_mesh(node.mesh)
		var bounded := true
		var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var offset: Vector3 = (pose * vertex) - anchor
			bounded = bounded and offset.is_finite()
			bounded = bounded and absf(offset.x) <= half_extents.x + 0.0001
			bounded = bounded and absf(offset.y) <= half_extents.y + 0.0001
			bounded = bounded and absf(offset.z) <= half_extents.z + 0.0001
		verify(bounded, "All fitted item hardware stays inside the existing conservative item envelope.")
	for child in node.get_children():
		if child is Node3D:
			check_bounds(child, pose * child.transform, anchor, half_extents)


func count_role(node: Node, role: String) -> int:
	var count := 1 if node.get_meta("asset_role", "") == role else 0
	for child in node.get_children():
		count += count_role(child, role)
	return count


func count_kind(node: Node, kind: String) -> int:
	var count := 1 if node.get_meta("item_kind", "") == kind else 0
	for child in node.get_children():
		count += count_kind(child, kind)
	return count


func _initialize() -> void:
	var boss := Visuals.turned_mesh(Assets.boss_profile(), 32)
	var lug := Visuals.turned_mesh(Assets.lug_profile(), 32)
	var bushing := Visuals.turned_mesh(Assets.bushing_profile(), 48)
	var rivet := Visuals.turned_mesh(Assets.rivet_profile(), 6)
	verify(
		boss == Visuals.turned_mesh(Assets.boss_profile(), 32)
		and lug == Visuals.turned_mesh(Assets.lug_profile(), 32)
		and bushing == Visuals.turned_mesh(Assets.bushing_profile(), 48)
		and rivet == Visuals.turned_mesh(Assets.rivet_profile(), 6),
		"Repeated item hardware reuses cached turned ArrayMesh instances."
	)
	verify(
		boss != lug and lug != bushing and bushing != rivet,
		"Distinct turned item profiles do not alias each other in the mesh cache."
	)
	check_mesh(boss, 0.0001, 0.001)
	check_mesh(lug, 0.00005, 0.0005)
	check_mesh(bushing, 0.0002, 0.001)
	check_mesh(rivet, 0.000005, 0.0001)

	var holder := Node3D.new()
	var center := Vector3(1.65, 0.65, 1.65)

	var blank := Assets.seam_blank(holder, center)
	verify(
		count_role(blank, "SeamCradle") == 1
		and count_role(blank, "BlankIngot") == 1
		and count_role(blank, "ClampBand") == 2
		and count_role(blank, "LiftingLug") == 1,
		"Each seam blank includes its cradle, ingot, twin clamp bands and turned lifting lug."
	)
	check_bounds(blank, blank.transform, center, Assets.SEAM_HALF_EXTENTS)

	var billet := Assets.workpiece_billet(holder, center)
	verify(
		count_role(billet, "CarrierTray") == 1
		and count_role(billet, "TrayRail") == 2
		and count_role(billet, "BilletCore") == 1
		and count_role(billet, "IndexRib") == 2
		and count_role(billet, "CenterBoss") == 1,
		"Each workpiece billet includes its carrier tray, side rails, billet core, index ribs and turned boss."
	)
	check_bounds(billet, billet.transform, center, Assets.BILLET_HALF_EXTENTS)

	var plate := Assets.stamped_plate(holder, center)
	verify(
		count_role(plate, "PlateSheet") == 1
		and count_role(plate, "StampedRim") == 4
		and count_role(plate, "PlateBushing") == 1
		and count_role(plate, "PlateFastener") == 4,
		"Each stamped plate includes its sheet, four perimeter stiffening ribs, bronze bushing and four corner fasteners."
	)
	check_bounds(plate, plate.transform, center, Assets.PLATE_HALF_EXTENTS)
	holder.free()

	var item_root := Node3D.new()
	var state := {
		"entities": {
			"c1": {"kind": "collector", "cell": [0, 1]},
			"b1": {"kind": "belt", "cell": [1, 1]},
			"p1": {"kind": "processor", "cell": [2, 1]},
		},
		"stock": {
			"source": 11,
			"collector": 1,
			"belt": 1,
			"input": 1,
			"held": 1,
			"output": 1,
			"player": 0,
		},
	}
	var before: Dictionary = state.duplicate(true)
	Assets.populate_items(item_root, state, Geometry.PITCH)
	verify(
		count_kind(item_root, "seam_blank") == 11
		and count_kind(item_root, "workpiece_billet") == 4
		and count_kind(item_root, "stamped_plate") == 1
		and item_root.get_child_count() == 16,
		"populate_items builds the exact seam, in-line billet and outlet plate assemblies from confirmed stock."
	)
	verify(state == before, "Item assembly population never mutates the confirmed projection state.")
	item_root.free()

	var ok: bool = not failed and checks >= 40
	print(JSON.stringify({
		"status": "pass" if ok else "fail",
		"checks": checks,
		"unique_meshes": checked_meshes.size(),
		"visual_instances": visual_instances,
		"maximum_packed_tangent_dot": max_tangent_dot,
		"rendered_quality": "not_assessed",
		"desktop": "not_used",
	}))
	quit(0 if ok else 1)
