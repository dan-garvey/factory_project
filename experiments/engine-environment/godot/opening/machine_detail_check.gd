extends SceneTree
## Authored mesh and visual assembly checks. No game authority or desktop.
const Opening = preload("res://opening/opening.gd")
const Visuals = Opening.ProductionVisuals
const WheelArt = Opening.ProductionWheelArt
const PressArt = Opening.ProductionPressArt
const ConveyorArt = Opening.ProductionConveyorArt
const CollectorArt = Opening.ProductionCollectorArt
const Presenter = preload("res://opening/native_transmission_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")
var checks := 0
var failed := false
var max_tangent_dot := 0.0
var detail_meshes := 0
var minimum_press_gap := INF
var minimum_collector_gap := INF

func collector_mesh(mesh: ArrayMesh, minimum_volume: float, maximum_volume: float) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	verify(vertices.size() > 0 and vertices.size() % 3 == 0 and normals.size() == vertices.size()
		and tangents.size() == vertices.size() * 4 and uv.size() == vertices.size(),
		"Each original casting has complete normal-mapped triangle attributes.")
	var edges: Dictionary = {}
	var volume := 0.0
	var valid := true
	var winding := true
	for n in range(0, vertices.size(), 3):
		var a := vertices[n]
		var b := vertices[n + 1]
		var c := vertices[n + 2]
		var cross := (b - a).cross(c - a)
		winding = winding and cross.length_squared() > 0.00000000000001 and cross.dot(normals[n]) < 0
		volume += a.dot(b.cross(c)) / 6.0
		for pair in [[a, b], [b, c], [c, a]]:
			var first := vertex_key(pair[0])
			var second := vertex_key(pair[1])
			var edge := first + "/" + second if first < second else second + "/" + first
			edges[edge] = int(edges.get(edge, 0)) + 1
	for n in range(vertices.size()):
		var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
		var dot := absf(tangent.dot(normals[n]))
		max_tangent_dot = maxf(max_tangent_dot, dot)
		valid = valid and vertices[n].is_finite() and uv[n].is_finite() and normals[n].is_finite()
		valid = valid and absf(normals[n].length() - 1) < 0.003
		valid = valid and tangent.is_finite() and absf(tangent.length() - 1) < 0.003 and dot < 0.003
	var closed := true
	for count in edges.values():
		closed = closed and count == 2
	verify(winding and closed, "The casting has outward clockwise faces and exactly two faces per geometric edge.")
	verify(valid, "Casting normals, tangents and UVs remain finite and usable after mesh packing.")
	verify(absf(volume) > minimum_volume and absf(volume) < maximum_volume,
		"The solid or annular casting retains an independently bounded volume.")

func point_triangle_distance(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	var area := absf((b - a).cross(c - a))
	if area > 0.00000001 and Geometry2D.is_point_in_polygon(point, PackedVector2Array([a, b, c])):
		return 0.0
	return minf(point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)),
		minf(point.distance_to(Geometry2D.get_closest_point_to_segment(point, b, c)),
		point.distance_to(Geometry2D.get_closest_point_to_segment(point, c, a))))

func collector_clearance(frame: Node3D, moving: Array) -> float:
	var minimum := INF
	for part: MeshInstance3D in frame.get_children():
		var vertices: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for n in range(0, vertices.size(), 3):
			var a: Vector3 = part.transform * vertices[n]
			var b: Vector3 = part.transform * vertices[n + 1]
			var c: Vector3 = part.transform * vertices[n + 2]
			var low := a.min(b).min(c)
			var high := a.max(b).max(c)
			for row in moving:
				var node: MeshInstance3D = row.node
				var transform: Transform3D = row.parent_inverse.affine_inverse() * node.transform
				var gap := -INF
				if node.mesh is CylinderMesh:
					# The unchanged drum and hub are circular about Z. Their true
					# radial envelope avoids filling the bearing's annular hole.
					var cylinder: CylinderMesh = node.mesh
					var center := transform.origin
					var radial := point_triangle_distance(Vector2(center.x, center.y),
						Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y)) - cylinder.top_radius
					var axial := maxf(low.z - center.z - cylinder.height / 2,
						center.z - cylinder.height / 2 - high.z)
					gap = maxf(radial, axial)
				else:
					# Conservative transformed flute bounds, sampled over a turn.
					var box: AABB = transform * node.mesh.get_aabb()
					gap = maxf(maxf(maxf(low.x - box.end.x, box.position.x - high.x),
						maxf(low.y - box.end.y, box.position.y - high.y)),
						maxf(low.z - box.end.z, box.position.z - high.z))
				minimum = minf(minimum, gap)
	return minimum

func check_collector_cast_frame() -> void:
	var cached: Dictionary = {}
	var limits := {"CastCheekLeft": [0.020, 0.045], "CastCheekRight": [0.020, 0.045],
		"CastLowerHousing": [0.07, 0.10], "CastUpperHood": [0.05, 0.08],
		"BearingHanger": [0.001, 0.003], "FixedBearingHousing": [0.0006, 0.0013],
		"FixedBearingLiner": [0.00024, 0.00026]}
	for axis in range(3):
		var view := Opening.new()
		view.machine_root = Node3D.new()
		view.add_child(view.machine_root)
		view.state = {"context": "collector-cast-fixture", "options": {"native": true},
			"actors": {"P": {"ready": true}}, "entities": {
				"fixture": {"kind": "collector", "cell": [0, 0], "axis": axis, "generation": 1}},
			"transmission_parts": {}, "motion": {"fixture": {"state": "rotating", "numerator": 1, "denominator": 1}},
			"links": [], "drive_links": [], "engagements": []}
		view.transmission_presenter = Presenter.new()
		view.add_child(view.transmission_presenter)
		view.transmission_presenter.configure(view)
		var before: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		var machine: Node3D = view.machine_root.get_child(0)
		var frame: Node3D = machine.get_node("CollectorCastFrame")
		verify(frame.get_script() == null and frame.get_child_count() == 7,
			"The real collector mounts seven plain reusable cast and bearing parts.")
		verify(machine.get_node_or_null("HeadSupport") == null and machine.get_node_or_null("HeadCover") == null
			and machine.get_node_or_null("BackHousing") == null,
			"The cast kit replaces the old rectangular frame instead of stacking duplicate silhouettes.")
		check_bounds(frame, Transform3D.IDENTITY)
		for part: MeshInstance3D in frame.get_children():
			var role: String = part.get_meta("collector_frame_role", "")
			verify(limits.has(role) and part.get_script() == null and part.get_child_count() == 0,
				"Every frame role has a declared plain-mesh identity.")
			if not limits.has(role):
				continue
			if axis == 0:
				collector_mesh(part.mesh, limits[role][0], limits[role][1])
				cached[role] = [part.mesh, part.material_override]
			verify(part.mesh == cached[role][0] and part.material_override == cached[role][1],
				"All projected spindle axes reuse the exact frame meshes and finishes.")
			var finish_value := part.material_override as StandardMaterial3D
			verify(finish_value != null and finish_value.albedo_color == Color("a6b4af")
				if role == "FixedBearingLiner" else finish_value != null and finish_value.metallic < 0.1,
				"The liner is exposed worked steel while the fixed cast structure remains painted.")
		var bed: MeshInstance3D = machine.get_node("StockBed")
		verify(bed.position == Vector3(0, 0.51, 0) and bed.mesh == Visuals.box_mesh(Vector3(1.25, 0.1, 0.67)),
			"The literal feed bed and its top plane remain unchanged.")
		var rows: Array = machine.get_meta("motion_meshes")
		verify(rows.size() == 10 and count_role(machine, "CutterFlute") == 8,
			"Only the original drum, hub and eight flutes belong to the moving group.")
		var drum: MeshInstance3D = machine.get_node("CutterDrum")
		var hub: MeshInstance3D = machine.get_node("CutterHub")
		verify(drum.position == Vector3(-0.22, 1.1, -0.19) and drum.mesh is CylinderMesh
			and is_equal_approx(drum.mesh.top_radius, 0.24) and is_equal_approx(drum.mesh.height, 0.34)
			and hub.position == Vector3(-0.22, 1.1, 0.01) and hub.mesh is CylinderMesh
			and is_equal_approx(hub.mesh.top_radius, 0.085) and is_equal_approx(hub.mesh.height, 0.08),
			"The original literal drum and hub define the clearance oracle, with no moving-geometry replacement.")
		var picks: Array = []
		for child in machine.get_children():
			if child is StaticBody3D:
				picks.append(child)
		verify(picks.size() == 1 and picks[0].collision_layer == Geometry.PICK_LAYER and picks[0].collision_mask == 0
			and picks[0].get_meta("entity", "") == "fixture" and picks[0].get_child_count() == 1
			and picks[0].get_child(0).shape.size == Vector3(1.45, 1.65, 1.45)
			and picks[0].get_child(0).position == Vector3(0, Geometry.MACHINE_CENTER_HEIGHT, 0),
			"The real builder keeps one original entity pick body with its exact size, position and masks.")
		for sample in range(24):
			view._apply_cutter_pose(machine, rows, float(sample) * TAU / 24)
			var gap := collector_clearance(frame, rows)
			minimum_collector_gap = minf(minimum_collector_gap, gap)
			verify(gap > 0.006, "The fixed frame clears the actual original moving cutter, flutes and hub across a full turn.")
		view._apply_cutter_pose(machine, rows, 0)
		if axis == 0:
			var hood: MeshInstance3D = frame.get_node("CastUpperHood")
			hood.position.y -= 0.2
			verify(collector_clearance(frame, rows) < 0, "The clearance oracle rejects an actual hood displaced into the drum.")
			hood.position.y += 0.2
			var liner: MeshInstance3D = frame.get_node("FixedBearingLiner")
			liner.position.x += 0.03
			verify(collector_clearance(frame, rows) < 0, "The clearance oracle rejects a bearing displaced into its rotating hub.")
			liner.position.x -= 0.03
		verify(collector_clearance(frame, rows) > 0.006, "The original assembly is restored after the two asset controls.")
		var fixed: Array = []
		for part in frame.get_children():
			fixed.append(part.transform)
		view._animate_wheel(0.1)
		verify(is_equal_approx(view.transmission_presenter.visual_angle("fixture"), 0.08),
			"The original collector angle still comes from the sole existing cosmetic presenter cache.")
		for n in range(frame.get_child_count()):
			verify(frame.get_child(n).transform == fixed[n], "The supporting casting remains fixed as the original cutter turns.")
		verify(view.state == before and view.request_sequence == 0 and view.model == null and view.actor_world == null,
			"Frame assembly and motion leave all projection facts, requests and authority untouched.")
		view.free()
	print(JSON.stringify({"phase": "collector cast frame", "minimum_separating_gap": minimum_collector_gap,
		"axes": 3, "rotation_samples_per_axis": 24, "altered_asset_controls": 2}))

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func vertex_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000)]

func check_profile(profile: PackedVector2Array, minimum_volume: float, maximum_volume: float) -> void:
	var mesh := Visuals.turned_mesh(profile)
	verify(mesh == Visuals.turned_mesh(profile), "Repeated hardware reuses the exact authored profile mesh.")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	verify(vertices.size() > 0 and vertices.size() % 3 == 0 and normals.size() == vertices.size()
		and coordinates.size() == vertices.size() and tangents.size() == vertices.size() * 4,
		"The turned asset has complete normal-mapped triangle attributes.")
	var edges: Dictionary = {}
	var volume := 0.0
	var valid_faces := true
	var valid_attributes := true
	for n in range(0, vertices.size(), 3):
		var a := vertices[n]
		var b := vertices[n + 1]
		var c := vertices[n + 2]
		var cross := (b - a).cross(c - a)
		valid_faces = valid_faces and cross.length_squared() > 0.00000000000001 and cross.dot(normals[n]) < 0
		volume += a.dot(b.cross(c)) / 6.0
		for pair in [[a, b], [b, c], [c, a]]:
			var first := vertex_key(pair[0])
			var second := vertex_key(pair[1])
			var key := first + "/" + second if first < second else second + "/" + first
			edges[key] = int(edges.get(key, 0)) + 1
	for n in range(vertices.size()):
		var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
		max_tangent_dot = maxf(max_tangent_dot, absf(tangent.dot(normals[n])))
		valid_attributes = valid_attributes and vertices[n].is_finite() and normals[n].is_finite()
		valid_attributes = valid_attributes and is_equal_approx(normals[n].length(), 1.0)
		valid_attributes = valid_attributes and coordinates[n].is_finite() and tangent.is_finite()
		valid_attributes = valid_attributes and tangent.length() > 0.99 and absf(tangent.dot(normals[n])) < 0.0002
	var closed := true
	for count in edges.values():
		closed = closed and count == 2
	verify(valid_faces, "Every authored face is noncollapsed and has clockwise outward winding.")
	verify(closed, "The turned hardware closes every geometric edge without hidden holes.")
	verify(absf(volume) > minimum_volume and absf(volume) < maximum_volume,
		"The closed asset retains the independently bounded solid or annular volume.")
	verify(valid_attributes, "UVs, normals and packed-attribute tangents remain finite and usable.")

func check_bounds(node: Node3D, parent_pose: Transform3D) -> void:
	var pose := parent_pose * node.transform
	verify(not node is CollisionObject3D and not node is CollisionShape3D,
		"New hardware has no collision or construction authority.")
	if node is MeshInstance3D:
		detail_meshes += 1
		var box: AABB = node.mesh.get_aabb()
		var bounded := true
		for n in range(8):
			var point := pose * box.get_endpoint(n)
			bounded = bounded and point.is_finite() and absf(point.x) <= 0.72501 and absf(point.z) <= 0.72501
			bounded = bounded and point.y >= -0.02501 and point.y <= 1.62501
		verify(bounded, "All new hardware stays inside the unchanged conservative machine envelope.")
	for child in node.get_children():
		if child is Node3D:
			check_bounds(child, pose)

func count_role(node: Node, role: String) -> int:
	var count := 1 if node.get_meta("detail_role", "") == role else 0
	for child in node.get_children():
		count += count_role(child, role)
	return count

func check_sourced_mesh(instance: MeshInstance3D) -> void:
	verify(instance.get_script() == null and instance.get_child_count() == 0,
		"The sourced rotor is a plain mesh without a controller, skeleton or physical children.")
	var arrays := instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	verify(vertices.size() == 5632 and indices.size() == 8574 * 3,
		"The loaded mesh contains exactly the extracted rim, hub and twelve spokes.")
	verify(normals.size() == vertices.size() and coordinates.size() == vertices.size()
		and tangents.size() == vertices.size() * 4,
		"The sourced mesh has complete normal-mapped attributes.")
	if normals.size() != vertices.size() or tangents.size() != vertices.size() * 4:
		return
	var attributes_ok := true
	var radius := 0.0
	var uv_low := Vector2.ONE
	var uv_high := Vector2.ZERO
	for n in range(vertices.size()):
		var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
		max_tangent_dot = maxf(max_tangent_dot, absf(tangent.dot(normals[n])))
		attributes_ok = attributes_ok and vertices[n].is_finite() and normals[n].is_finite()
		attributes_ok = attributes_ok and absf(normals[n].length() - 1.0) < 0.002
		attributes_ok = attributes_ok and tangent.is_finite() and absf(tangent.length() - 1.0) < 0.002
		attributes_ok = attributes_ok and absf(tangent.dot(normals[n])) < 0.003 and coordinates[n].is_finite()
		radius = maxf(radius, Vector2(vertices[n].x, vertices[n].y).length())
		uv_low = uv_low.min(coordinates[n])
		uv_high = uv_high.max(coordinates[n])
	verify(attributes_ok, "Actual imported source normals, tangents, positions and UVs remain finite and usable.")
	verify(radius > 0.5699 and radius < 0.5701 and instance.mesh.get_aabb().size.z < 0.14,
		"The source rotor has the normalized radial and axial envelope, without its stand or drive belt.")
	verify((uv_high - uv_low).x > 0.5 and (uv_high - uv_low).y > 0.5,
		"The original atlas coordinates retain a nontrivial surface footprint.")
	var material := instance.material_override as StandardMaterial3D
	verify(material != null and material == WheelArt.finish,
		"All sourced instances use the cached original material.")
	if material == null:
		return
	verify(material.albedo_texture.get_size() == Vector2(1024, 1024)
		and material.normal_texture.get_size() == Vector2(512, 512)
		and material.roughness_texture.get_size() == Vector2(512, 512),
		"The decoded source color and prepared data maps retain their declared resolutions.")
	verify(material.metallic_texture == material.roughness_texture and material.ao_texture == material.roughness_texture
		and material.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED
		and material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		and material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE,
		"Occlusion, roughness and metallic use the correct shared linear packed channels.")
	verify(material.normal_enabled and not material.uv1_triplanar
		and material.albedo_texture.get_image().has_mipmaps() and material.normal_texture.get_image().has_mipmaps()
		and material.roughness_texture.get_image().has_mipmaps(),
		"The atlas retains source UVs and has mipmapped normal, color and scalar textures.")

func check_wheel_axes() -> void:
	verify(WheelArt.resource_status() == "complete", "The complete source set is present in this captured project.")
	var cached_mesh: Mesh
	var cached_material: Material
	for axis_index in range(3):
		var axis: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis_index]
		var view := Opening.new()
		view.machine_root = Node3D.new()
		view.state = {"options": {"native": true}, "powered": true,
			"entities": {"fixture": {"kind": "wheel", "cell": [0, 0], "axis": axis_index}}, "links": [], "drive_links": []}
		var before: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		var anchor: Node3D = view.machine_root.get_child(0)
		var rotor: Node3D = anchor.get_node("WheelRotor")
		var sourced := rotor.get_node_or_null("SourcedTimberRotor") as MeshInstance3D
		verify(WheelArt.source_status == "ready" and sourced != null,
			"Every supported wheel axis mounts the actual sourced rotor.")
		if sourced != null:
			check_sourced_mesh(sourced)
			if cached_mesh == null:
				cached_mesh = sourced.mesh
				cached_material = sourced.material_override
			verify(sourced.mesh == cached_mesh and sourced.material_override == cached_material,
				"All wheel axes share their exact mesh and material resources.")
		verify(count_role(rotor, "WheelRim") == 0 and count_role(rotor, "RimFastener") == 0,
			"The new source replaces the old rim instead of stacking duplicate silhouettes.")
		verify(rotor.position.distance_to(Vector3.UP * Geometry.ANCHOR_HEIGHT) < 0.00001
			and rotor.basis.z.normalized().dot(axis) > 0.99999,
			"The actual sourced rotor follows the confirmed native hub and projected axis.")
		var hub: MeshInstance3D = rotor.get_node("WheelHub")
		verify(hub.mesh is CylinderMesh and hub.position == Vector3.ZERO
			and absf((rotor.basis * hub.basis.y).normalized().dot(axis)) > 0.99999,
			"The existing visible spindle still lies on the native hub axis.")
		var bearings := 0
		for child in anchor.get_children():
			if child is MeshInstance3D and str(child.name).begins_with("AxleBearing"):
				bearings += 1
				verify(child.mesh is CylinderMesh and absf(child.basis.y.normalized().dot(axis)) > 0.99999,
					"The existing bearing follows its actual projected axle.")
		verify(bearings == (1 if axis_index == 1 else 2), "The original vertical and horizontal bearing layouts remain intact.")
		check_bounds(rotor, Transform3D.IDENTITY)
		var original: Transform3D = rotor.transform
		view._animate_wheel(1.0)
		verify(rotor.transform == original, "Powered state alone cannot invent a native wheel phase.")
		verify(view.state == before and view.model == null and view.actor_world == null,
			"Asset assembly preserves the projection and creates no game or character authority.")
		view.machine_root.free()
		view.free()
	var missing := "user://wheel-resource-controls/missing"
	verify(WheelArt.resource_status(missing) == "missing", "An absent historical source set is distinguishable from a complete asset.")
	var partial := "user://wheel-resource-controls/partial"
	DirAccess.make_dir_recursive_absolute(partial)
	var file := FileAccess.open(partial.path_join("rotor.gltf"), FileAccess.WRITE)
	if file != null:
		file.store_string("{}")
		file.close()
	verify(file != null and WheelArt.resource_status(partial) == "incomplete",
		"A partial asset set cannot be reported as sourced success.")

func press_protected(node: Node3D, parent_pose: Transform3D, rows: Array[Dictionary]) -> void:
	var pose := parent_pose * node.transform
	if node is MeshInstance3D:
		var name_value := str(node.name)
		if name_value in ["Anvil", "ToolHead", "Piston", "OutputTray", "DriveStub"] or name_value.begins_with("ToolGuide") or node.get_meta("detail_role", "") == "GuideCollar":
			rows.append({"bounds": pose * node.mesh.get_aabb(), "name": name_value})
	for child in node.get_children():
		if child is Node3D:
			press_protected(child, pose, rows)

func press_clearance(support: MeshInstance3D, protected_rows: Array[Dictionary]) -> void:
	var arrays := support.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var clear := true
	var first_overlap := ""
	# Individual triangle boxes keep the wide mounting collar at its actual
	# low height; a whole-column box would falsely fill the empty upper space.
	for n in range(0, indices.size(), 3):
		var a: Vector3 = support.transform * vertices[indices[n]]
		var b: Vector3 = support.transform * vertices[indices[n + 1]]
		var c: Vector3 = support.transform * vertices[indices[n + 2]]
		var low := a.min(b).min(c)
		var high := a.max(b).max(c)
		for row in protected_rows:
			var box: AABB = row.bounds
			var gap := maxf(maxf(maxf(box.position.x - high.x, low.x - box.end.x),
				maxf(box.position.y - high.y, low.y - box.end.y)), maxf(box.position.z - high.z, low.z - box.end.z))
			minimum_press_gap = minf(minimum_press_gap, gap)
			if gap <= 0:
				clear = false
				if first_overlap.is_empty():
					first_overlap = row.name
	verify(clear, "The sourced support leaves the existing work, guide and drive meshes clear: " + first_overlap)

func check_press_supports() -> void:
	verify(PressArt.resource_status() == "complete", "The actual captured press resource set is complete.")
	var shared_mesh: Mesh
	var shared_material: Material
	for axis in range(3):
		var view := Opening.new()
		view.machine_root = Node3D.new()
		view.state = {"options": {"native": true}, "remaining": 0, "stock": {"held": 0},
			"entities": {"fixture": {"kind": "processor", "cell": [0, 0], "axis": axis, "generation": 1}}, "links": [], "drive_links": []}
		var before: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		var machine: Node3D = view.machine_root.get_child(0)
		var supports: Array[MeshInstance3D] = []
		for child in machine.get_children():
			if child is MeshInstance3D and child.get_meta("detail_role", "") == "CastPressSupport":
				supports.append(child)
		verify(PressArt.source_status == "ready" and supports.size() == 2,
			"The ordinary processor mounts two actual sourced support components.")
		verify(machine.get_node_or_null("PressUpright") == null,
			"The sourced supports replace the old upright geometry.")
		verify(machine.get_node("Plinth").position == Vector3(0, 0.12, 0)
			and machine.get_node("Plinth").mesh.get_aabb().size.is_equal_approx(Vector3(1.35, 0.24, 1.35)),
			"The original foundation geometry and mounting height stay intact.")
		verify(machine.get_node("Anvil").position == Vector3(0, 0.46, 0.05)
			and machine.get_node("OutputTray").position == Vector3(0.46, 0.33, 0.15),
			"The actual anvil and outlet retain their original working coordinates.")
		var rows: Array = machine.get_meta("motion_meshes")
		verify(rows.size() == 2, "Only the original head and piston join the existing press pose path.")
		for support in supports:
			verify(support.get_script() == null and support.get_child_count() == 0,
				"The source creates no controller, collision child or state owner.")
			if shared_mesh == null:
				shared_mesh = support.mesh
				shared_material = support.material_override
			verify(support.mesh == shared_mesh and support.material_override == shared_material,
				"Both supports and all projected drive axes share the same mesh and material.")
			var arrays := support.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			verify(vertices.size() == 1977 and arrays[Mesh.ARRAY_INDEX].size() == 6282,
				"The loaded support has the declared source column, collar and mounting fasteners.")
			var usable := normals.size() == vertices.size() and coordinates.size() == vertices.size() and tangents.size() == vertices.size() * 4
			if usable:
				for n in range(vertices.size()):
					var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
					max_tangent_dot = maxf(max_tangent_dot, absf(tangent.dot(normals[n])))
					usable = usable and vertices[n].is_finite() and normals[n].is_finite() and coordinates[n].is_finite()
					usable = usable and absf(normals[n].length() - 1) < 0.002 and tangent.is_finite()
					usable = usable and absf(tangent.length() - 1) < 0.002 and absf(tangent.dot(normals[n])) < 0.003
			verify(usable, "The actual source support retains usable normals, tangents and atlas coordinates.")
			verify(is_equal_approx(support.position.y, 0.24) and is_equal_approx(support.position.z, -0.38)
				and is_equal_approx(absf(support.position.x), 0.48)
				and absf((support.transform * support.mesh.get_aabb()).end.y - 1.4) < 0.00001,
				"The source mounting plane meets the original foundation and its top meets the bridge.")
			check_bounds(support, Transform3D.IDENTITY)
		for travel in [0.0, 0.015]:
			view._apply_press_pose(rows, travel)
			var protected_rows: Array[Dictionary] = []
			press_protected(machine, Transform3D.IDENTITY, protected_rows)
			verify(protected_rows.size() >= 10, "The clearance check includes actual head, work, guide and drive meshes.")
			for support in supports:
				press_clearance(support, protected_rows)
		verify(view.state == before and view.model == null and view.actor_world == null,
			"The asset and existing end-pose checks preserve projection and create no game authority.")
		view.machine_root.free()
		view.free()
	var material := shared_material as StandardMaterial3D
	verify(material != null and material.albedo_color == Color.WHITE and material.cull_mode == BaseMaterial3D.CULL_DISABLED,
		"The original source color and double-sided shading remain intact.")
	if material != null:
		verify(material.albedo_texture.get_size() == Vector2(1024, 1024)
			and material.normal_texture.get_size() == Vector2(512, 512) and material.roughness_texture.get_size() == Vector2(512, 512),
			"The actual source color and prepared data maps retain their declared sizes.")
		verify(material.roughness_texture == material.metallic_texture and material.ao_texture == material.roughness_texture
			and material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			and material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			and material.ao_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED,
			"The cached material uses the original packed scalar channel meanings.")
		verify(material.normal_enabled and not material.uv1_triplanar and material.albedo_texture.get_image().has_mipmaps()
			and material.normal_texture.get_image().has_mipmaps() and material.roughness_texture.get_image().has_mipmaps(),
			"The source atlas and normalized normal mip chain remain active.")

func check_historical_press() -> void:
	verify(PressArt.resource_status() == "missing", "This deliberately reduced roster omits the sourced press assets.")
	var view := Opening.new()
	view.machine_root = Node3D.new()
	view.state = {"options": {"native": true}, "entities": {"fixture": {"kind": "processor", "cell": [0, 0], "axis": 0}}, "links": [], "drive_links": []}
	var before: Dictionary = view.state.duplicate(true)
	view._rebuild_machines()
	var machine: Node3D = view.machine_root.get_child(0)
	verify(PressArt.source_status == "missing" and machine.get_node_or_null("PressUpright") != null
		and machine.get_node_or_null("CastPressSupportLeft") == null, "The actual historical source roster retains its original upright assembly.")
	verify(machine.get_node("SurfaceDetail").get_node_or_null("FrameJoint") != null,
		"The historical rectangular frame retains its fitted service cover.")
	verify(is_equal_approx((machine.get_node("PressBridge").material_override as StandardMaterial3D).metallic, 0.08),
		"The historical frame retains its original low-metal paint response.")
	verify(view.state == before and view.model == null and view.actor_world == null,
		"The historical art path preserves state and has no game authority.")
	view.machine_root.free()
	view.free()

func finish() -> void:
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "detail_meshes": detail_meshes,
		"maximum_packed_tangent_dot": max_tangent_dot, "source_status": WheelArt.source_status,
		"press_source_status": PressArt.source_status, "minimum_press_separating_gap": minimum_press_gap if is_finite(minimum_press_gap) else null,
		"rendered_quality": "not_assessed", "desktop": "not_used"}))
	quit(1 if failed else 0)

func check_historical_wheel() -> void:
	verify(WheelArt.resource_status() == "missing", "This deliberately reduced historical roster has no sourced wheel files.")
	var view := Opening.new()
	view.machine_root = Node3D.new()
	for native_profile in [true, false]:
		view.state = {"options": {"native": native_profile}, "powered": true,
			"entities": {"fixture": {"kind": "wheel", "cell": [0, 0], "axis": 0}}, "links": [], "drive_links": []}
		var before: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		var rotor: Node3D = view.machine_root.get_child(0).get_node("WheelRotor")
		verify(WheelArt.source_status == "missing" and rotor.get_node_or_null("SourcedTimberRotor") == null,
			"Historical native and scripted views explicitly retain their earlier procedural art.")
		verify(count_role(rotor, "WheelRim") == 2 and count_role(rotor, "RimFastener") == 24,
			"The actual fallback still mounts both original rims and their fasteners.")
		verify(view.state == before and view.model == null and view.actor_world == null,
			"Missing artwork does not create authority or change the projection.")
	view.machine_root.free()
	view.free()

func check_conveyor_loop() -> void:
	var mesh := ConveyorArt.loop_mesh()
	verify(mesh == ConveyorArt.loop_mesh(), "Every conveyor shares the same authored loop mesh.")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	verify(vertices.size() == 2400 and normals.size() == vertices.size()
		and coordinates.size() == vertices.size() and tangents.size() == vertices.size() * 4,
		"The loop has the complete attributes of its eight-sided section and two sampled return arcs.")
	var edges: Dictionary = {}
	var seam: Dictionary = {}
	var volume := 0.0
	var faces_ok := true
	var attributes_ok := true
	var hollow_ok := true
	for n in range(0, vertices.size(), 3):
		var a := vertices[n]
		var b := vertices[n + 1]
		var c := vertices[n + 2]
		var cross := (b - a).cross(c - a)
		faces_ok = faces_ok and cross.length_squared() > 0.00000000000001
		faces_ok = faces_ok and cross.dot(normals[n] + normals[n + 1] + normals[n + 2]) < 0
		volume += a.dot(b.cross(c)) / 6.0
		for pair in [[a, b], [b, c], [c, a]]:
			var first := vertex_key(pair[0])
			var second := vertex_key(pair[1])
			var key := first + "/" + second if first < second else second + "/" + first
			edges[key] = int(edges.get(key, 0)) + 1
	for n in range(vertices.size()):
		var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
		max_tangent_dot = maxf(max_tangent_dot, absf(tangent.dot(normals[n])))
		attributes_ok = attributes_ok and vertices[n].is_finite() and normals[n].is_finite()
		attributes_ok = attributes_ok and absf(normals[n].length() - 1.0) < 0.0002
		attributes_ok = attributes_ok and tangent.is_finite() and absf(tangent.length() - 1.0) < 0.0002
		attributes_ok = attributes_ok and absf(tangent.dot(normals[n])) < 0.0002 and coordinates[n].is_finite()
		var xy := Vector2(vertices[n].x, vertices[n].y)
		var center := Vector2(clampf(xy.x, -0.57, 0.57), 0)
		var radial_distance := xy.distance_to(center)
		hollow_ok = hollow_ok and radial_distance >= 0.07799 and radial_distance <= 0.09001
		if coordinates[n].x < 0.00001 or coordinates[n].x > 3.99999:
			var key := vertex_key(vertices[n])
			if not seam.has(key):
				seam[key] = [INF, -INF]
			seam[key][0] = minf(seam[key][0], coordinates[n].x)
			seam[key][1] = maxf(seam[key][1], coordinates[n].x)
	var closed := true
	for count in edges.values():
		closed = closed and count == 2
	var seam_ok := seam.size() == 8
	for row in seam.values():
		seam_ok = seam_ok and absf(float(row[1]) - float(row[0]) - 4.0) < 0.00001
	verify(faces_ok and closed, "Every actual belt face has clockwise outward winding and every geometric edge closes twice.")
	verify(absf(volume) > 0.0213 and absf(volume) < 0.0218,
		"The closed mesh has the independently bounded rubber-shell volume rather than a solid filled block.")
	verify(hollow_ok, "All actual vertices retain the empty loop interior and twelve-millimetre radial thickness.")
	verify(attributes_ok, "Actual loop UVs, unit normals and orthogonal unit tangents remain finite.")
	verify(seam_ok, "All eight section corners close the longitudinal seam at exactly four texture repeats.")
	var bounds := mesh.get_aabb()
	verify(bounds.position.is_equal_approx(Vector3(-0.66, -0.09, -0.32))
		and bounds.end.is_equal_approx(Vector3(0.66, 0.09, 0.32)),
		"The authored loop retains its declared span, return radius and original belt width.")
	verify(absf(bounds.end.y + ConveyorArt.HEIGHT - 0.555) < 0.00001,
		"The top stays at the original cleat height instead of entering the workpiece.")
	for axis in range(3):
		var view := Opening.new()
		view.machine_root = Node3D.new()
		view.state = {"options": {"native": true}, "entities": {"fixture": {"kind": "belt", "cell": [0, 0], "axis": axis}},
			"links": [], "drive_links": [], "stock": {"belt": 1}}
		var before: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		var anchor: Node3D = view.machine_root.get_child(0)
		var loop := anchor.get_node("ConveyorLoop") as MeshInstance3D
		verify(loop != null and loop.mesh == mesh and loop.material_override == ConveyorArt.material(),
			"The ordinary belt assembly mounts the exact shared loop and cached rubber material.")
		verify(anchor.get_node_or_null("ConveyorBand") == null and anchor.get_node_or_null("ConveyorCleat") == null,
			"The closed loop replaces the old solid band and floating top blocks.")
		var legs := 0
		var channels := 0
		var rollers := 0
		for child in anchor.get_children():
			if child is MeshInstance3D:
				check_bounds(child, Transform3D.IDENTITY)
				var role := str(child.get_meta("detail_role", ""))
				if role.begins_with("ConveyorLeg"):
					legs += 1
					var box: AABB = child.transform * child.mesh.get_aabb()
					verify(is_equal_approx(absf(child.position.z), 0.36) and minf(absf(box.position.z), absf(box.end.z)) >= 0.32999,
						"The supports stay outside the returning rubber instead of intersecting it.")
				elif role.begins_with("ConveyorChannel"):
					channels += 1
					verify(is_equal_approx(absf(child.position.z), 0.36) and is_equal_approx(child.position.y, 0.43),
						"Both structural channels connect the side supports outside the belt path.")
				elif role.begins_with("ConveyorRoller"):
					rollers += 1
					verify(child.mesh is ArrayMesh and is_equal_approx(absf(child.position.x), 0.57) and is_equal_approx(child.position.y, 0.465),
						"Both turned end drums retain their existing centers and fit inside the loop.")
		print(JSON.stringify({"axis": axis, "supports": legs, "channels": channels, "drums": rollers}))
		verify(legs == 4 and channels == 2 and rollers == 2,
			"The actual assembly contains four supports, two channels and two end drums.")
		var drive := anchor.get_node("DriveStub") as MeshInstance3D
		var direction: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis]
		verify(absf(drive.basis.y.normalized().dot(direction)) > 0.99999,
			"The original native drive interface still follows its projected axis.")
		view.item_root = Node3D.new()
		view._redraw_items()
		var lowest := INF
		var pending: Array = [[view.item_root, Transform3D.IDENTITY]]
		while not pending.is_empty():
			var row: Array = pending.pop_back()
			var node: Node3D = row[0]
			var pose: Transform3D = row[1] * node.transform
			if node is MeshInstance3D:
				var box: AABB = pose * node.mesh.get_aabb()
				lowest = minf(lowest, box.position.y)
			for child in node.get_children():
				if child is Node3D:
					pending.append([child, pose])
		verify(view.item_root.get_child_count() == 1 and lowest - (bounds.end.y + ConveyorArt.HEIGHT) > 0.00499,
			"The actual unchanged workpiece redraw remains at least five millimetres above the new rubber surface.")
		verify(view.state == before and view.model == null and view.actor_world == null,
			"The asset changes no projection, input, material authority or physical character.")
		view.item_root.free()
		view.machine_root.free()
		view.free()
	var material := ConveyorArt.material()
	if OS.get_cmdline_user_args().has("--historical-conveyor-only"):
		verify(ConveyorArt.source_status == "missing" and material.albedo_texture == null and material.metallic == 0.0,
			"An actual missing-resource capture uses explicit generated dielectric rubber, without claiming a sourced material.")
	else:
		verify(ConveyorArt.source_status == "ready" and material.albedo_color == Color.WHITE and material.metallic == 0.0,
			"The complete source set uses its original albedo with dielectric rubber shading.")
		verify(material.albedo_texture.get_size() == Vector2(1024, 1024)
			and material.normal_texture.get_size() == Vector2(512, 512)
			and material.roughness_texture.get_size() == Vector2(512, 512),
			"The actual color, OpenGL normal and roughness images have the declared resolutions.")
		verify(material.roughness == 1.0 and material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED
			and material.normal_enabled and not material.uv1_triplanar and not material.ao_enabled,
			"Scalar roughness and tangent normals use their own channels without invented metallic or occlusion maps.")
		verify(material.albedo_texture.get_image().has_mipmaps() and material.normal_texture.get_image().has_mipmaps()
			and material.roughness_texture.get_image().has_mipmaps(), "Every decoded source image has mipmaps.")
	var missing := "user://conveyor-controls/missing"
	verify(ConveyorArt.read_images(missing).status == "missing", "A missing source set is explicit.")
	var partial := "user://conveyor-controls/partial"
	DirAccess.make_dir_recursive_absolute(partial)
	var file := FileAccess.open(partial.path_join("rubber_albedo.webp"), FileAccess.WRITE)
	if file != null:
		file.store_string("invalid partial fixture")
		file.close()
	verify(file != null and ConveyorArt.read_images(partial).status == "invalid",
		"A partial source set is rejected rather than reported as valid artwork.")
	print(JSON.stringify({"loop_volume": absf(volume), "longitudinal_repeats": 4,
		"longitudinal_texture_metres": (4.0 * 0.57 + TAU * 0.09) / 4.0}))

func prepare_conveyor_maps() -> void:
	var args := OS.get_cmdline_user_args()
	args.remove_at(0)
	if args.size() != 2:
		push_error("Use SOURCE_DIRECTORY PREPARED_ASSET_DIRECTORY.")
		quit(1)
		return
	var source := args[0]
	var output := args[1]
	var pins := {"albedo": "559ddef0d43572ff96015da9a12a218d8fcff3be9fb2a1febf00731d5b31e121",
		"normal": "3a20ce99ec4cb929d96c0f4643c5484bdede6537b3448900d841f94fb20def70",
		"roughness": "3969d0cd375fa94f849bcbc7fe836ebc619aed4b80673cb59ce823e1423db699"}
	var report: Dictionary = {"status": "pass", "maps": {}}
	for role in pins:
		var target: String = output.path_join(ConveyorArt.FILES[role])
		var source_path: String = source.path_join(role + ".png")
		if FileAccess.file_exists(target) or FileAccess.get_sha256(source_path) != pins[role]:
			push_error("Refuse an existing output or unpinned conveyor source: " + role)
			quit(1)
			return
		var image := Image.load_from_file(source_path)
		if image == null or image.get_size() != Vector2i(1024, 1024):
			push_error("Expected the pinned one-kilopixel source image: " + role)
			quit(1)
			return
		var decoded_format := image.get_format()
		var maximum_normal_error := 0.0
		var maximum_normal_angle := 0.0
		if role == "albedo":
			image.convert(Image.FORMAT_RGB8)
		elif role == "roughness":
			image.convert(Image.FORMAT_RF)
			image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
			var scalar := PackedByteArray()
			scalar.resize(512 * 512)
			for y in range(512):
				for x in range(512):
					scalar[y * 512 + x] = clampi(roundi(image.get_pixel(x, y).r * 255), 0, 255)
			image = Image.create_from_data(512, 512, false, Image.FORMAT_L8, scalar)
		else:
			image.convert(Image.FORMAT_RGBF)
			image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
			var pixels := PackedByteArray()
			pixels.resize(512 * 512 * 3)
			for y in range(512):
				for x in range(512):
					var color := image.get_pixel(x, y)
					var normal := Vector3(color.r * 2 - 1, color.g * 2 - 1, color.b * 2 - 1)
					if not normal.is_finite() or normal.length_squared() < 0.000001:
						push_error("Invalid resized conveyor normal.")
						quit(1)
						return
					normal = normal.normalized()
					var at := (y * 512 + x) * 3
					for axis in range(3):
						pixels[at + axis] = clampi(roundi((normal[axis] * 0.5 + 0.5) * 255), 0, 255)
					var decoded := Vector3(pixels[at], pixels[at + 1], pixels[at + 2]) / 255.0 * 2.0 - Vector3.ONE
					maximum_normal_error = maxf(maximum_normal_error, absf(decoded.length() - 1.0))
					maximum_normal_angle = maxf(maximum_normal_angle, rad_to_deg(acos(clampf(decoded.normalized().dot(normal), -1, 1))))
			image = Image.create_from_data(512, 512, false, Image.FORMAT_RGB8, pixels)
		if maximum_normal_error >= 0.01 or maximum_normal_angle >= 0.5 or image.save_webp(target, false) != OK:
			push_error("Cannot encode conveyor map within its normal representation bounds: " + role)
			quit(1)
			return
		var packed := Image.load_from_file(target)
		if packed == null:
			push_error("Cannot decode the prepared conveyor map: " + role)
			quit(1)
			return
		packed.convert(image.get_format())
		if packed.get_size() != image.get_size() or packed.get_data() != image.get_data():
			push_error("The lossless conveyor map pixels differ: " + role)
			quit(1)
			return
		report.maps[role] = {"source_decoded_format": decoded_format, "prepared_format": image.get_format(),
			"width": image.get_width(), "height": image.get_height(), "prepared_pixel_equality": true,
			"maximum_normal_length_error": maximum_normal_error, "maximum_normal_encoding_angle_degrees": maximum_normal_angle,
			"bytes": FileAccess.get_file_as_bytes(target).size()}
	print(JSON.stringify(report))
	quit(0)

func prepare_component_maps(prefix: String) -> void:
	var args := OS.get_cmdline_user_args()
	args.remove_at(0)
	if args.size() != 2:
		push_error("Use SOURCE_DIRECTORY PREPARED_ASSET_DIRECTORY.")
		quit(1)
		return
	var source := args[0]
	var output := args[1]
	var report: Dictionary = {"status": "pass", "source_size": [1024, 1024], "maps": {}}
	for name_value in ["normal", "arm"]:
		var target := output.path_join(prefix + "_" + name_value + ".webp")
		if FileAccess.file_exists(target):
			push_error("Refuse to replace a prepared map: " + target)
			quit(1)
			return
		var original := Image.load_from_file(source.path_join(name_value + ".png"))
		if original == null or original.get_size() != Vector2i(1024, 1024):
			push_error("Expected the pinned one-kilopixel source PNG: " + name_value)
			quit(1)
			return
		var decoded_format := original.get_format()
		# Resize linear data in float precision. Renormalize tangent normals,
		# then round once to RGB8. Packed scalar channel meanings stay intact.
		original.convert(Image.FORMAT_RGBF)
		original.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		var pixels := PackedByteArray()
		pixels.resize(512 * 512 * 3)
		var maximum_normal_error := 0.0
		var maximum_normal_angle := 0.0
		for y in range(512):
			for x in range(512):
				var color := original.get_pixel(x, y)
				var normal := Vector3.ZERO
				if name_value == "normal":
					normal = Vector3(color.r * 2 - 1, color.g * 2 - 1, color.b * 2 - 1)
					if not normal.is_finite() or normal.length_squared() < 0.000001:
						push_error("The resized source normal cannot be normalized.")
						quit(1)
						return
					normal = normal.normalized()
					color = Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5)
				var at := (y * 512 + x) * 3
				pixels[at] = clampi(roundi(color.r * 255), 0, 255)
				pixels[at + 1] = clampi(roundi(color.g * 255), 0, 255)
				pixels[at + 2] = clampi(roundi(color.b * 255), 0, 255)
				if name_value == "normal":
					var decoded := Vector3(pixels[at], pixels[at + 1], pixels[at + 2]) / 255.0 * 2.0 - Vector3.ONE
					maximum_normal_error = maxf(maximum_normal_error, absf(decoded.length() - 1.0))
					maximum_normal_angle = maxf(maximum_normal_angle, rad_to_deg(acos(clampf(decoded.normalized().dot(normal), -1, 1))))
		var prepared := Image.create_from_data(512, 512, false, Image.FORMAT_RGB8, pixels)
		if maximum_normal_error >= 0.01 or maximum_normal_angle >= 0.5:
			push_error("The prepared normal exceeds its encoding bound.")
			quit(1)
			return
		if prepared.save_webp(target, false) != OK:
			push_error("Cannot encode the lossless data map: " + name_value)
			quit(1)
			return
		var packed := Image.load_from_file(target)
		if packed == null:
			push_error("Cannot decode the prepared map: " + name_value)
			quit(1)
			return
		packed.convert(Image.FORMAT_RGB8)
		if packed.get_size() != prepared.get_size() or packed.get_data() != pixels:
			push_error("The lossless data-map pixels differ from the prepared representation: " + name_value)
			quit(1)
			return
		report.maps[name_value] = {"source_decoded_format": decoded_format,
			"runtime_format": Image.FORMAT_RGB8, "size": [512, 512], "prepared_pixel_equality": true,
			"maximum_normal_length_error": maximum_normal_error, "maximum_normal_encoding_angle_degrees": maximum_normal_angle,
			"bytes": FileAccess.get_file_as_bytes(target).size()}
	var albedo_target := output.path_join(prefix + "_albedo.jpg")
	if FileAccess.file_exists(albedo_target) or DirAccess.copy_absolute(
			source.path_join("albedo.jpg"), albedo_target) != OK:
		push_error("Cannot copy the original provider albedo into a fresh path.")
		quit(1)
		return
	if FileAccess.get_file_as_bytes(albedo_target) != FileAccess.get_file_as_bytes(source.path_join("albedo.jpg")):
		push_error("Albedo copy differs from the original provider bytes.")
		quit(1)
		return
	report.maps.albedo = {"representation": "original provider JPEG", "reencoded": false,
		"bytes": FileAccess.get_file_as_bytes(albedo_target).size()}
	report.processing = "Float-precision Lanczos data-map resize, normalized OpenGL normals, nearest RGB8 encoding and lossless WebP. No channel reorder, normal-axis flip or color-space conversion."
	print(JSON.stringify(report))
	quit(0)

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--collector-frame-only"):
		check_collector_cast_frame()
		finish()
		return
	if OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "--prepare-conveyor-maps":
		prepare_conveyor_maps()
		return
	if OS.get_cmdline_user_args().has("--conveyor-only") or OS.get_cmdline_user_args().has("--historical-conveyor-only"):
		check_conveyor_loop()
		finish()
		return
	if OS.get_cmdline_user_args().has("--sourced-press-only"):
		check_press_supports()
		finish()
		return
	if OS.get_cmdline_user_args().has("--historical-press-only"):
		check_historical_press()
		finish()
		return
	if OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "--prepare-waterwheel-maps":
		prepare_component_maps("wood")
		return
	if OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "--prepare-press-support-maps":
		prepare_component_maps("cast")
		return
	if OS.get_cmdline_user_args().has("--sourced-wheel-material-only"):
		var parent := Node3D.new()
		verify(WheelArt.mount(parent), "The changed material loads through the shipped source helper.")
		var rotor := parent.get_node_or_null("SourcedTimberRotor") as MeshInstance3D
		if rotor != null:
			check_sourced_mesh(rotor)
			verify((rotor.material_override as StandardMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED,
				"The source material retains its documented double-sided shading.")
		parent.free()
		finish()
		return
	if OS.get_cmdline_user_args().has("--historical-wheel-only"):
		check_historical_wheel()
		finish()
		return
	if OS.get_cmdline_user_args().has("--sourced-wheel-only"):
		check_wheel_axes()
		finish()
		return
	var washer := PackedVector2Array([Vector2(0, 0), Vector2(0.038, 0), Vector2(0.043, 0.002),
		Vector2(0.043, 0.004), Vector2(0.038, 0.006), Vector2(0, 0.006)])
	check_profile(washer, 0.00002, 0.00004)
	var rim := PackedVector2Array([Vector2(0.51, -0.022), Vector2(0.518, -0.03), Vector2(0.582, -0.03),
		Vector2(0.59, -0.022), Vector2(0.59, 0.022), Vector2(0.582, 0.03),
		Vector2(0.518, 0.03), Vector2(0.51, 0.022), Vector2(0.51, -0.022)])
	check_profile(rim, 0.014, 0.018)
	verify(Visuals.turned_mesh(rim) != Visuals.turned_mesh(washer), "Different exact profiles cannot alias a cached resource.")
	var head: CylinderMesh = Visuals.fastener_head_mesh()
	verify(head == Visuals.fastener_head_mesh() and head.radial_segments == 6,
		"Repeated fasteners share their deliberate hexagonal head geometry.")
	var view := Opening.new()
	view.machine_root = Node3D.new()
	for item in [["collector", 0], ["belt", 0], ["processor", 0], ["wheel", 0], ["wheel", 1], ["wheel", 2]]:
		view.state = {"options": {"native": true}, "entities": {"fixture": {"kind": item[0], "cell": [0, 0], "axis": item[1]}},
			"links": [], "drive_links": []}
		var before: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		var machine: Node3D = view.machine_root.get_child(0)
		var details: Node3D = machine.get_node("SurfaceDetail")
		verify(count_role(details, "FoundationFastener") == 4,
			"Every actual machine has four fitted foundation fasteners.")
		check_bounds(details, Transform3D.IDENTITY)
		match item[0]:
			"collector":
				verify(count_role(details, "CutterFlute") == 8 and count_role(details, "ServiceVent") == 5,
					"The actual collector includes its cutter flutes and fitted service cover.")
			"belt":
				verify(count_role(details, "RollerBearing") == 4, "The actual conveyor has four fitted roller bearings.")
			"processor":
				verify(count_role(details, "GuideCollar") == 4, "The actual press has fitted collars at both guide ends.")
			"wheel":
				var rotor: Node3D = machine.get_node("WheelRotor")
				if WheelArt.source_status == "ready":
					verify(count_role(rotor, "SourcedTimberRotor") == 1 and count_role(rotor, "WheelRim") == 0,
						"The actual wheel mounts the sourced component instead of procedural rims.")
				else:
					verify(count_role(rotor, "WheelRim") == 2 and count_role(rotor, "RimFastener") == 24,
						"A historical capture retains its two continuous procedural rims and fitted fasteners.")
				check_bounds(rotor, Transform3D.IDENTITY)
		verify(view.state == before and view.model == null, "Detail assembly cannot mutate the projection or create a Model.")
	view.machine_root.free()
	view.free()
	finish()
