extends SceneTree
## Passive mineral exposure, workpiece billets and stamped product plates.
## No World, input, network or desktop execution.

const Assets = preload("res://opening/workpiece_item_assets.gd")
const Visuals = preload("res://opening/opening.gd").ProductionVisuals
const Geometry = preload("res://opening/site_geometry.gd")
const Opening = preload("res://opening/opening.gd")
const Shared = preload("res://opening/shared_opening.gd")

var checks := 0
var failed := false
var checked_meshes: Dictionary = {}
var max_tangent_dot := 0.0
var visual_instances := 0

class DetachedOpening extends Opening:
	func _message(_words: String, _refused: bool = false) -> void:
		pass
	func _refresh_machine_preview() -> void:
		pass
	func _update_camera() -> void:
		pass

class DetachedShared extends Shared:
	func _message(_words: String, _refused: bool = false) -> void:
		pass
	func _refresh_machine_preview() -> void:
		pass
	func _update_camera() -> void:
		pass


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
	if "--mineral-seam-only" in OS.get_cmdline_user_args():
		check_mineral_seam()
		return
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
		"initial_feed": 4096,
		"source_deposit": {"cells": [[0, 0], [0, 1]]},
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
		count_kind(item_root, "mineral_deposit") == 1
		and count_kind(item_root, "workpiece_billet") == 4
		and count_kind(item_root, "stamped_plate") == 1
		and item_root.get_child_count() == 6,
		"Confirmed quantities produce fitted workpieces and one continuous deposit, rather than eleven source props."
	)
	verify(state == before, "Item assembly population never mutates the confirmed projection state.")
	item_root.free()

	var rotated := {
		"options": {"native": true},
		"entities": {
			"c": {"kind": "collector", "cell": [0, 1], "axis": 2},
			"b": {"kind": "belt", "cell": [0, 2], "axis": 0},
			"p": {"kind": "processor", "cell": [0, 3], "axis": 2},
		},
		"links": [["c", "b"], ["b", "p"]],
		"stock": {"source": 0, "collector": 0, "belt": 1, "input": 0, "held": 0, "output": 1},
	}
	for shared in [false, true]:
		var view: Variant = DetachedShared.new() if shared else DetachedOpening.new()
		view.state = rotated
		verify(view._material_rotated("b", rotated.entities.b),
			"The X-axis belt rotates its material artwork in both consumers.")
		verify(not view._material_rotated("c", rotated.entities.c),
			"The collector keeps its own confirmed facing when connected to the belt.")
		verify(not view._material_rotated("p", rotated.entities.p),
			"The press keeps its own confirmed facing when connected to the belt.")
		var anchor := Node3D.new()
		view._assemble_machine(anchor, rotated.entities.b, true)
		var assembly := anchor.get_node_or_null("RotatedMachineVisual") as Node3D
		verify(assembly != null and (assembly.basis * Vector3.RIGHT).is_equal_approx(Vector3.BACK),
			"The rotated belt artwork maps its local material path to world +Z.")
		view._apply_conveyor_motion(anchor, 0.5)
		var loop := anchor.find_child("ConveyorLoop", true, false) as MeshInstance3D
		verify(loop != null and loop.material_override.uv1_offset.x > 0.5,
			"Positive X axle rotation advances the rotated belt toward its outlet.")
		anchor.free()
		view.free()
	var turned_items := Node3D.new()
	Assets.populate_items(turned_items, rotated, Geometry.PITCH)
	var billet_node: Node3D
	var plate_node: Node3D
	for child in turned_items.get_children():
		if child.get_meta("item_kind", "") == "workpiece_billet":
			billet_node = child
		elif child.get_meta("item_kind", "") == "stamped_plate":
			plate_node = child
	verify(billet_node != null and billet_node.position.is_equal_approx(Vector3(0, 0.65, 3.13))
		and is_equal_approx(billet_node.rotation.y, -PI / 2.0), "The billet follows the rotated belt.")
	verify(plate_node != null and plate_node.position.is_equal_approx(Vector3(-0.15, 0.39, 5.41))
		and is_equal_approx(plate_node.rotation.y, -PI / 2.0), "The finished plate follows the rotated press tray.")
	turned_items.free()

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


func check_exposure_mesh(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	verify(points.size() > 0 and points.size() % 3 == 0 and normals.size() == points.size()
		and tangents.size() == points.size() * 4 and uvs.size() == points.size(),
		"The draped mineral relief has complete actual triangle, normal, UV and tangent attributes.")
	var attributes := true
	var contact := true
	var winding := true
	var top_contacts := 0
	var side_contacts := 0
	var spec: Dictionary = Assets.Scenery.Surface.source_outcrop()
	var inverse := Transform3D(spec.basis, spec.center).affine_inverse()
	var query: TriangleMesh = Assets.Scenery.Surface.SOURCE_OUTCROP_MESH.generate_triangle_mesh()
	for n in range(points.size()):
		var point := points[n]
		var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
		attributes = attributes and point.is_finite() and normals[n].is_finite() and uvs[n].is_finite()
		attributes = attributes and is_equal_approx(normals[n].length(), 1.0) and tangent.is_finite()
		attributes = attributes and absf(tangent.dot(normals[n])) < 0.0002
		var hit := query.intersect_ray(inverse * Vector3(point.x, spec.center.y + spec.size.y, point.z),
			inverse.basis * Vector3.DOWN)
		var on_top := false
		if not hit.is_empty():
			var rock_point: Vector3 = Transform3D(spec.basis, spec.center) * hit.position
			var gap := point.y - rock_point.y
			on_top = gap >= 0.0059 and gap <= 0.0141 and normals[n].y >= 0.0
		if on_top:
			top_contacts += 1
		else:
			var west := Vector3(spec.center.x - spec.size.x * 0.5 - 0.1, point.y, point.z)
			var side_hit := query.intersect_ray(inverse * west, inverse.basis * Vector3.RIGHT)
			if side_hit.is_empty():
				contact = false
			else:
				var side_point: Vector3 = Transform3D(spec.basis, spec.center) * side_hit.position
				var side_gap := side_point.x - point.x
				contact = contact and side_gap >= 0.0059 and side_gap <= 0.0141 and normals[n].x < 0.0
				side_contacts += 1
	for n in range(0, points.size(), 3):
		var a := points[n]
		var b := points[n + 1]
		var c := points[n + 2]
		var cross := (b - a).cross(c - a)
		winding = winding and cross.length_squared() > 0.000000000001 and cross.dot(normals[n]) < 0
	verify(attributes and winding, "All surface facets have finite orthogonal attributes and outward clockwise winding.")
	verify(contact and top_contacts > 0 and side_contacts > 0,
		"Top and west-side mineral relief both hug the delivered rock within the declared allowance.")


func check_mineral_seam() -> void:
	var cells := [[0, 0], [0, 1]]
	var rock_mesh: Mesh
	var mineral_material: Material
	var full_veins: Mesh
	for amount in [4096, 2048, 1023, 1, 0]:
		var holder := Node3D.new()
		var facts := {"initial_feed": 4096, "source_deposit": {"cells": cells},
			"entities": {}, "stock": {"source": amount}}
		var before: Dictionary = facts.duplicate(true)
		Assets.populate_items(holder, facts)
		verify(holder.get_child_count() == 1 and count_kind(holder, "mineral_deposit") == 1,
			"A larger, partly mined or exhausted reserve is one natural exposure rather than a count of repeated pebbles.")
		var exposure: Node3D = holder.get_child(0)
		verify(exposure.get_script() == null and exposure.position == Vector3.ZERO
			and exposure.get_meta("remaining") == amount and exposure.get_child_count() == (3 if amount > 0 else 1),
			"Only unowned presentation surfaces represent confirmed reserve and depletion.")
		var rock: MeshInstance3D = exposure.get_node("ExposedRock")
		if rock_mesh == null:
			rock_mesh = rock.mesh
			check_exposure_boundary(rock)
		verify(rock.mesh == rock_mesh, "The exhausted host exposure reuses the same geometry throughout depletion.")
		for part in exposure.get_children():
			verify(part is MeshInstance3D and part.get_child_count() == 0 and part.get_script() == null
				and not part is CollisionObject3D and part.scale == Vector3.ONE,
				"The mineral node has no collider, script, input, clock, manufactured hardware or second authority.")
		if amount > 0:
			var ground: MeshInstance3D = exposure.get_node("OreSurface")
			var footprint := ground.mesh.get_aabb()
			verify(footprint.size.x > 1.3 and footprint.size.z > 2.6
				and footprint.position.z < 0.0 and footprint.end.z > Geometry.PITCH,
				"The visible ore field spans both admitted collector cells beyond the narrow source rock.")
			verify(ground.material_override == Assets.source_ground and ground.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"The wider ore color remains a passive surface without a second shadow or collider.")
			var veins: MeshInstance3D = exposure.get_node("MineralVeins")
			verify(veins.transform == Transform3D.IDENTITY, "The vein mesh uses the same world placement as its surface queries.")
			check_exposure_mesh(veins.mesh)
			if mineral_material == null:
				mineral_material = veins.material_override
				full_veins = veins.mesh
			verify(veins.material_override == mineral_material and not mineral_material.emission_enabled,
				"Mineral relief shares its restrained cached source finish without an active glow.")
			if amount == 1:
				verify(veins.mesh != full_veins, "A nearly depleted reserve has visibly narrower mineral veins.")
		else:
			verify(not exposure.has_node("MineralVeins") and not exposure.has_node("OreSurface"),
				"No visible mineral remains when the sole native reserve is exhausted.")
		verify(facts == before, "Geometry preparation never changes confirmed stock, coverage or value types.")
		holder.free()
	for amount in range(0, 4097, 256):
		var holder := Node3D.new()
		Assets.populate_items(holder, {"initial_feed": 4096, "source_deposit": {"cells": cells},
			"entities": {}, "stock": {"source": amount}})
		holder.free()
	verify(Assets.source_meshes.size() == 8, "Eight depletion surfaces bound the vein cache independently of reserve size; the immutable rock is one resource.")
	var unknown := Node3D.new()
	Assets.populate_items(unknown, {"initial_feed": 4096, "entities": {}, "stock": {"source": 4096}})
	verify(unknown.get_child_count() == 0, "Stock without declared source coverage never invents a local resource row.")
	unknown.free()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"mode": "mineral-seam-only", "reserve_observations": [4096, 2048, 1023, 1, 0],
		"cache_entries": Assets.source_meshes.size(), "maximum_vein_relief_metres": 0.014,
		"authority_started": false, "rendered_quality": "not_assessed", "desktop": "not_used"}))
	quit(1 if failed else 0)


func check_exposure_boundary(rock: MeshInstance3D) -> void:
	var surface = Assets.Scenery.Surface
	var spec: Dictionary = surface.source_outcrop()
	verify(rock.mesh == surface.SOURCE_OUTCROP_MESH
		and rock.transform == Transform3D(spec.basis, spec.center),
		"The visible fixed rock uses the sole site's immutable mesh and exact native obstacle transform.")
	var visible: AABB = rock.transform * rock.mesh.get_aabb()
	var obstacle: AABB = Transform3D(spec.basis, spec.center) * AABB(-spec.size * 0.5, spec.size)
	verify(visible.is_equal_approx(obstacle) and visible.end.y - surface.height_at(spec.center.x, spec.center.z) > 0.6,
		"The placement obstacle has the visible rock envelope and substantial relief above ground.")
	verify(spec.points.size() == 201 and spec.native_points.size() == 200 and spec.faces.size() == 396 * 3,
		"The shared descriptor keeps original cooking input and cooked reference facets separate.")
	var finish: StandardMaterial3D = rock.material_override
	verify(finish.albedo_texture.get_size() == Vector2(512, 512)
		and finish.normal_texture.get_size() == Vector2(256, 256)
		and finish.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		and finish.metallic == 0.0 and finish.cull_mode == BaseMaterial3D.CULL_DISABLED
		and finish.albedo_color == Color("c78a54"),
		"The actual rock uses its prepared texture and distinct copper tint while retaining the matched physical hull.")
	verify(rock.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"The substantial outcrop participates in the normal scene's shadows.")
