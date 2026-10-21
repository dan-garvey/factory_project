extends SceneTree
## Authored mesh and visual assembly checks. No game authority or desktop.
const Opening = preload("res://opening/opening.gd")
const Shared = preload("res://opening/shared_opening.gd")
const Visuals = Opening.ProductionVisuals
const WheelArt = Opening.ProductionWheelArt
const PaddleArt = Opening.ProductionPaddleArt
const PressArt = Opening.ProductionPressArt
const ConveyorArt = Opening.ProductionConveyorArt
const CollectorArt = Opening.ProductionCollectorArt
const SkidArt = Opening.ProductionSkidArt
const Presenter = preload("res://opening/native_transmission_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const Items = preload("res://opening/workpiece_item_assets.gd")
var checks := 0
var failed := false
var max_tangent_dot := 0.0
var detail_meshes := 0
var minimum_press_gap := INF
var minimum_collector_gap := INF

class PaddleSessionFacts extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

func crown_clip_y(points: Array[Vector3], height: float, above: bool) -> Array[Vector3]:
	var clipped: Array[Vector3] = []
	if points.is_empty():
		return clipped
	var previous: Vector3 = points[-1]
	var previous_inside: bool = previous.y >= height if above else previous.y <= height
	for point in points:
		var inside: bool = point.y >= height if above else point.y <= height
		if inside != previous_inside:
			clipped.append(previous.lerp(point, (height - previous.y) / (point.y - previous.y)))
		if inside:
			clipped.append(point)
		previous = point
		previous_inside = inside
	return clipped

func crown_shaft_gap(crown: Node3D, shaft: MeshInstance3D) -> float:
	# Clip actual fixed triangles to the original shaft's axial interval.
	# Empty space beyond its tip is not a promise that it passes through a cap.
	var shaft_bounds: AABB = shaft.transform * shaft.mesh.get_aabb()
	var closest := INF
	for part: MeshInstance3D in crown.get_children():
		var faces := part.mesh.get_faces()
		for n in range(0, faces.size(), 3):
			var points: Array[Vector3] = [part.transform * faces[n], part.transform * faces[n + 1], part.transform * faces[n + 2]]
			points = crown_clip_y(crown_clip_y(points, shaft_bounds.position.y, true), shaft_bounds.end.y, false)
			for corner in range(1, points.size() - 1):
				var flat: Array[Vector2] = []
				for at in [points[0], points[corner], points[corner + 1]]:
					flat.append(Vector2(at.x - shaft.position.x, at.z - shaft.position.z))
				closest = minf(closest, triangle_radius(flat[0], flat[1], flat[2]))
	return closest - (shaft.mesh as CylinderMesh).top_radius

func check_press_crown() -> void:
	var cached: Dictionary = {}
	var minimum_gap := INF
	var assemblies := 0
	var controls := 0
	var open_rays := 0
	for shared_profile in [false, true]:
		for axis in range(3):
			var view: Variant = Shared.new() if shared_profile else Opening.new()
			view.machine_root = Node3D.new()
			view.add_child(view.machine_root)
			view.state = {"context": "press-crown-fixture", "options": {"native": true},
				"actors": {"P": {"ready": true}}, "transmission_parts": {}, "motion": {},
				"remaining": 0, "stock": {"held": 1}, "entities": {
					"fixture": {"kind": "processor", "cell": [0, 0], "axis": axis, "generation": 1}},
				"links": [], "drive_links": [], "engagements": []}
			var before: Dictionary = view.state.duplicate(true)
			view._rebuild_machines()
			var machine: Node3D = view.machine_root.get_child(0)
			var crown: Node3D = machine.get_node("PressCrown")
			verify(PressArt.source_status == "ready" and crown.get_child_count() == 7
				and crown.get_script() == null and machine.get_node_or_null("PressBridge") == null,
				"The actual native sourced press replaces its box bridge with seven fixed crown pieces.")
			check_bounds(crown, Transform3D.IDENTITY)
			var fixed: Array[Transform3D] = []
			for part: MeshInstance3D in crown.get_children():
				var role: String = part.get_meta("press_crown_role")
				var key := "GuideSocket" if role.begins_with("GuideSocket") else role
				var painted := key not in ["RamLiner", "GuideSocket"]
				verify(part.get_script() == null and part.get_child_count() == 0 and part.scale.is_equal_approx(Vector3.ONE),
					"Every crown piece is a plain fixed mesh with its dimensions baked in metres.")
				if not cached.has(key):
					var limits: Array = {"CastShoulderLeft": [0.028, 0.032], "CastShoulderRight": [0.028, 0.032],
						"RearTie": [0.009, 0.013], "RamHousing": [0.006, 0.012],
						"RamLiner": [0.00048, 0.00055], "GuideSocket": [0.0005, 0.00075]}[key]
					check_closed_asset_mesh(part.mesh, limits[0], limits[1])
					cached[key] = [part.mesh, part.material_override]
				verify(part.mesh == cached[key][0] and part.material_override == cached[key][1],
					"All view classes and drive axes reuse the exact compatible crown resources.")
				var finish_value := part.material_override as StandardMaterial3D
				var color := Color("58634c") if painted else (Color("a6b4af") if key == "RamLiner" else Color("b87945"))
				verify(finish_value.albedo_color == color and is_equal_approx(finish_value.metallic, 0.0 if painted else 0.85)
					and finish_value.normal_texture == Opening.ProductionTransmissionFinish.textures[("cast" if painted else "worked") + "_normal"],
					"The actual crown separates qualified cast coating from exposed worked liners and sockets.")
				fixed.append(part.transform)
			for side in [-1.0, 1.0]:
				var support: MeshInstance3D = machine.get_node("CastPressSupportLeft" if side < 0 else "CastPressSupportRight")
				verify(support.mesh == PressArt.mesh and support.material_override == PressArt.finish
					and support.position.is_equal_approx(Vector3(side * 0.48, 0.24, -0.38))
					and is_equal_approx((support.transform * support.mesh.get_aabb()).end.y, 1.4),
					"The original sourced columns keep their geometry, atlas, mounting positions and crown datum.")
				verify(feed_ray_blocked(crown, Transform3D.IDENTITY,
					Vector3(side * 0.48, 1.39, -0.38), Vector3(side * 0.48, 1.41, -0.38)),
					"The actual shoulder facets meet each existing column instead of hovering above it.")
			var piston: MeshInstance3D = machine.get_node("Piston")
			var head: MeshInstance3D = machine.get_node("ToolHead")
			var guides: Array[MeshInstance3D] = []
			var picks := 0
			for child in machine.get_children():
				if child is StaticBody3D:
					picks += 1
					verify(child.collision_layer == Geometry.PICK_LAYER and child.collision_mask == 0
						and child.get_child_count() == 1 and child.get_child(0).shape.size == Vector3(1.45, 1.65, 1.45)
						and child.get_child(0).position == Vector3(0, 0.8, 0),
						"The original sole entity pick body keeps its size, position and masks.")
				if child is MeshInstance3D and child.mesh is CylinderMesh and is_equal_approx(child.mesh.top_radius, 0.04):
					guides.append(child)
			var rows: Array = machine.get_meta("motion_meshes")
			verify(rows.size() == 2 and rows[0].node == head and rows[1].node == piston,
				"Only the original tool head and piston remain in the existing cosmetic travel group.")
			verify(head.position.is_equal_approx(Vector3(0, 0.825, 0))
				and piston.position.is_equal_approx(Vector3(0, 1.1325, -0.08))
				and is_equal_approx((piston.transform * piston.mesh.get_aabb()).end.y, 1.365),
				"The ordinary builder correctly initializes the existing lowered pose for observed blocked held work.")
			view._apply_press_pose(rows, 0.0)
			verify(picks == 1 and guides.size() == 2 and piston.mesh is CylinderMesh
				and is_equal_approx(piston.mesh.top_radius, 0.075) and is_equal_approx(piston.mesh.height, 0.45)
				and piston.position.is_equal_approx(Vector3(0, 1.14, -0.08))
				and head.position.is_equal_approx(Vector3(0, 0.84, 0))
				and head.mesh == Visuals.box_mesh(Vector3(0.56, 0.17, 0.55)),
				"The original literal ram, tool head and two guide rods define the visual clearance oracle.")
			for guide in guides:
				verify(is_equal_approx(absf(guide.position.x), 0.34) and is_equal_approx(guide.position.y, 1.06)
					and is_equal_approx(guide.position.z, -0.19) and is_equal_approx(guide.mesh.height, 0.6),
					"The original guide lengths and positions are not shortened to hide an intersection.")
			var shafts: Array[MeshInstance3D] = [piston]
			shafts.append_array(guides)
			for travel in [0.0, 0.0075, 0.015]:
				view._apply_press_pose(rows, travel)
				for shaft in shafts:
					var gap := crown_shaft_gap(crown, shaft)
					minimum_gap = minf(minimum_gap, gap)
					verify(is_finite(gap) and gap > 0.002,
						"Actual fixed facets clear each original shaft over its real axial interval at every sampled tool pose.")
				verify(is_equal_approx((piston.transform * piston.mesh.get_aabb()).end.y, 1.365)
					and is_equal_approx(head.position.y, 0.84 - travel),
					"The original rod top stays fixed and the tool retains its exact previously accepted travel.")
				var protected_rows: Array[Dictionary] = []
				press_protected(machine, Transform3D.IDENTITY, protected_rows)
				for part: MeshInstance3D in crown.get_children():
					var bounds: AABB = part.transform * part.mesh.get_aabb()
					for row in protected_rows:
						if row.name == "Piston" or row.name.begins_with("ToolGuide"):
							continue
						var box: AABB = row.bounds
						var gap := maxf(maxf(maxf(box.position.x - bounds.end.x, bounds.position.x - box.end.x),
							maxf(box.position.y - bounds.end.y, bounds.position.y - box.end.y)), maxf(box.position.z - bounds.end.z, bounds.position.z - box.end.z))
						verify(gap > 0, "The crown conservatively clears the unchanged nonshaft working and drive meshes.")
				for n in range(crown.get_child_count()):
					verify(crown.get_child(n).transform == fixed[n], "The supporting crown stays fixed as the original tool moves.")
			for offset in [Vector2.ZERO, Vector2(0.07, 0), Vector2(-0.07, 0), Vector2(0, 0.07), Vector2(0, -0.07)]:
				verify(not feed_ray_blocked(crown, Transform3D.IDENTITY,
					Vector3(offset.x, 1.32, -0.08 + offset.y), Vector3(offset.x, 1.61, -0.08 + offset.y)),
					"Actual facets leave the complete central ram bore open through the crown.")
				open_rays += 1
			if controls == 0:
				var liner: MeshInstance3D = crown.get_node("RamLiner")
				var original: Mesh = liner.mesh
				var filled := CylinderMesh.new()
				filled.top_radius = 0.083
				filled.bottom_radius = 0.083
				filled.height = 0.25
				liner.mesh = filled
				verify(crown_shaft_gap(crown, piston) < 0, "The same clipped-facet oracle rejects a deliberately filled ram bore.")
				liner.mesh = original
				liner.position.x += 0.02
				verify(crown_shaft_gap(crown, piston) < 0, "A liner displaced into the unchanged piston fails the same clearance oracle.")
				liner.position.x -= 0.02
				var socket: MeshInstance3D = crown.get_node("GuideSocketLeft")
				socket.position.z += 0.02
				verify(crown_shaft_gap(crown, guides[0]) < 0, "A guide socket displaced into its original rod also fails the clearance oracle.")
				socket.position.z -= 0.02
				controls = 3
			verify(view.state == before and view.model == null and view.actor_world == null
				and view.request_sequence == 0 and not view.is_inside_tree(),
				"Crown construction and isolated pose checks create no input, state, physics or native authority.")
			assemblies += 1
			view.free()
	for shared_profile in [false, true]:
		var view: Variant = Shared.new() if shared_profile else Opening.new()
		view.state = {"options": {"native": false}}
		var machine := Node3D.new()
		view.add_child(machine)
		view._assemble_machine(machine, {"kind": "processor"})
		var bridge: MeshInstance3D = machine.get_node("PressBridge")
		verify(machine.get_node_or_null("PressCrown") == null
			and bridge.mesh == Visuals.box_mesh(Vector3(1.2, 0.2, 0.36))
			and bridge.position.is_equal_approx(Vector3(0, 1.5, -0.3)),
			"Both nonnative view classes keep their original sourced box bridge and position.")
		view.free()
	print(JSON.stringify({"phase": "press crown", "assemblies": assemblies, "unique_mesh_roles": cached.size(),
		"minimum_shaft_clearance_metres": minimum_gap, "through_bore_rays": open_rays, "altered_geometry_controls": controls,
		"poses_per_assembly": 3, "observations": "invented", "native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

func foot_polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for n in range(points.size()):
		area += points[n].cross(points[(n + 1) % points.size()])
	return absf(area) * 0.5

func foot_clip_triangle(subject: PackedVector2Array, clip: PackedVector2Array) -> PackedVector2Array:
	var result := subject
	var orientation := 1.0 if (clip[1] - clip[0]).cross(clip[2] - clip[0]) > 0 else -1.0
	for edge_index in range(3):
		if result.is_empty():
			break
		var a := clip[edge_index]
		var edge := clip[(edge_index + 1) % 3] - a
		var next := PackedVector2Array()
		var previous := result[result.size() - 1]
		var previous_side := orientation * edge.cross(previous - a)
		for point in result:
			var side := orientation * edge.cross(point - a)
			if (side >= 0.0) != (previous_side >= 0.0):
				next.append(previous.lerp(point, previous_side / (previous_side - side)))
			if side >= 0.0:
				next.append(point)
			previous = point
			previous_side = side
		result = next
	return result

func foot_mesh_triangles(mesh: Mesh, pose: Transform3D) -> Array[PackedVector3Array]:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := vertices.size() if indices.is_empty() else indices.size()
	var triangles: Array[PackedVector3Array] = []
	for n in range(0, count, 3):
		var triangle := PackedVector3Array()
		for corner in range(3):
			triangle.append(pose * vertices[n + corner if indices.is_empty() else indices[n + corner]])
		triangles.append(triangle)
	return triangles

func foot_seating(foot: MeshInstance3D, stand: MeshInstance3D, raised: float = 0.0) -> Dictionary:
	var pose := foot.transform
	pose.origin.y += raised
	var feet := foot_mesh_triangles(foot.mesh, pose)
	var casting := foot_mesh_triangles(stand.mesh, stand.transform)
	var bottom := INF
	for triangle in feet:
		for point in triangle:
			bottom = minf(bottom, point.y)
	var area := 0.0
	var supported := 0.0
	var penetration := 0.0
	for triangle in feet:
		if absf(triangle[0].y - bottom) > 0.000001 or absf(triangle[1].y - bottom) > 0.000001 or absf(triangle[2].y - bottom) > 0.000001:
			continue
		var face := PackedVector2Array([Vector2(triangle[0].x, triangle[0].z),
			Vector2(triangle[1].x, triangle[1].z), Vector2(triangle[2].x, triangle[2].z)])
		area += foot_polygon_area(face)
		for support in casting:
			var projected := PackedVector2Array([Vector2(support[0].x, support[0].z),
				Vector2(support[1].x, support[1].z), Vector2(support[2].x, support[2].z)])
			if foot_polygon_area(projected) < 0.000000000001:
				continue
			var intersection := foot_clip_triangle(face, projected)
			var shared_area := foot_polygon_area(intersection)
			if shared_area < 0.000000000001:
				continue
			var normal := (support[1] - support[0]).cross(support[2] - support[0])
			for point in intersection:
				var height: float = support[0].y - (normal.x * (point.x - support[0].x) + normal.z * (point.y - support[0].z)) / normal.y
				penetration = maxf(penetration, height - bottom)
			if absf(support[0].y - bottom) <= 0.00001 and absf(support[1].y - bottom) <= 0.00001 and absf(support[2].y - bottom) <= 0.00001:
				supported += shared_area
	return {"area": area, "coverage": supported / area if area > 0.0 else 0.0,
		"maximum_penetration": penetration, "bottom": bottom}

func check_wheel_foot_seats() -> void:
	var checked_shapes: Dictionary = {}
	var feet_checked := 0
	var negative_checked := false
	var scale_factor := 0.5 / 0.78
	for shared_profile in [false, true]:
		for axis_index in range(3):
			var view: Variant = Shared.new() if shared_profile else Opening.new()
			view.machine_root = Node3D.new()
			view.add_child(view.machine_root)
			view.state = {"options": {"native": true}, "actors": {}, "transmission_parts": {}, "motion": {},
				"entities": {"seat-fixture": {"kind": "wheel", "cell": [0, 0], "axis": axis_index, "generation": 1}},
				"links": [], "drive_links": [], "engagements": []}
			var before: Dictionary = view.state.duplicate(true)
			view._rebuild_machines()
			var machine: Node3D = view.machine_root.get_child(0)
			var rotor: Node3D = view.wheel_rotor
			var rotating: Array[Dictionary] = []
			if OS.get_cmdline_user_args().has("--foot-seat-geometry"):
				for child in rotor.get_children():
					if child is Node3D:
						wheel_rotating_envelopes(child, Transform3D.IDENTITY, rotating)
			var stands: Array[MeshInstance3D] = []
			for child in machine.get_children():
				if child is MeshInstance3D and child.get_meta("wheel_support_role", "") == "WheelStand":
					stands.append(child)
					var bounds: AABB = child.mesh.get_aabb()
					var expected := AABB(Vector3(-0.195, 0.24, -0.195), Vector3(0.39, 0.22, 0.39)) if axis_index == 1 else AABB(Vector3(-0.19, 0.24, -0.09), Vector3(0.38, 0.38, 0.18))
					verify(bounds.position.is_equal_approx(expected.position * scale_factor) and bounds.size.is_equal_approx(expected.size * scale_factor),
						"Changed seats retain the old exact stand bounds, preserving the conservative swept-clearance proof.")
					if OS.get_cmdline_user_args().has("--foot-seat-geometry") and not checked_shapes.has(axis_index == 1):
						check_closed_asset_mesh(child.mesh, (0.014 if axis_index == 1 else 0.010) * pow(scale_factor, 3),
							(0.024 if axis_index == 1 else 0.020) * pow(scale_factor, 3))
						checked_shapes[axis_index == 1] = true
			for child in machine.get_children():
				if not child is MeshInstance3D or child.get_meta("wheel_support_role", "") != "WheelFootBolt":
					continue
				var closest: MeshInstance3D = null
				for stand in stands:
					if closest == null or child.position.distance_squared_to(stand.position) < child.position.distance_squared_to(closest.position):
						closest = stand
				var seat := foot_seating(child, closest)
				if OS.get_cmdline_user_args().has("--foot-seat-geometry"):
					verify(wheel_support_separates(child.mesh, rotor.transform.affine_inverse() * child.transform, rotating),
						"The changed foot-bolt poses still clear every unchanged nonjournal rotor facet over a full turn.")
				var radius: float = child.mesh.bottom_radius
				verify(absf(seat.area - 3.0 * sqrt(3.0) * radius * radius / 2.0) < 0.00000001,
					"The oracle includes the complete actual hexagonal lower face, not a center sample.")
				verify(absf(seat.coverage - 1.0) < 0.0001 and seat.maximum_penetration < 0.00001,
					"Every bolt head seats across its full lower face without entering a higher shoulder.")
				if not negative_checked:
					var lifted := foot_seating(child, closest, 0.001)
					verify(lifted.coverage < 0.99, "A disclosed one-millimetre lifted-head control fails the same full-face oracle.")
					negative_checked = true
				print(JSON.stringify({"shared": shared_profile, "axis": axis_index, "part": str(child.name), "seat": seat}))
				feet_checked += 1
			verify(view.state == before and view.model == null and view.actor_world == null and view.request_sequence == 0,
				"The actual view callback changes no projection, request or native authority.")
			view.free()
	verify(feet_checked == 24 and negative_checked, "Both view classes and three axes exercise all four foot fasteners.")
	if OS.get_cmdline_user_args().has("--foot-seat-geometry"):
		verify(checked_shapes.size() == 2, "Both changed stand meshes receive the existing closure/attribute checks.")

func feed_aperture(mesh: Mesh, pose: Transform3D = Transform3D.IDENTITY) -> Vector2:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var left := -INF
	var right := INF
	var normal_frame: Basis = pose.basis.inverse().transposed()
	for n in range(vertices.size()):
		var point: Vector3 = pose * vertices[n]
		var normal: Vector3 = (normal_frame * normals[n]).normalized()
		if normal.x > 0.99999 and point.x < 0:
			left = maxf(left, point.x)
		elif normal.x < -0.99999 and point.x > 0:
			right = minf(right, point.x)
	return Vector2(left, right)

func feed_ray_blocked(node: Node3D, parent_pose: Transform3D, from: Vector3, to: Vector3) -> bool:
	var pose := parent_pose * node.transform
	if node is MeshInstance3D:
		var inverse := pose.affine_inverse()
		var a: Vector3 = inverse * from
		var b: Vector3 = inverse * to
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := vertices.size() if indices.is_empty() else indices.size()
		for n in range(0, count, 3):
			if Geometry3D.segment_intersects_triangle(a, b, vertices[n if indices.is_empty() else indices[n]],
					vertices[n + 1 if indices.is_empty() else indices[n + 1]],
					vertices[n + 2 if indices.is_empty() else indices[n + 2]]) != null:
				return true
	for child in node.get_children():
		if child is Node3D and feed_ray_blocked(child, pose, from, to):
			return true
	return false

func feed_item_bounds(node: Node3D, parent_pose: Transform3D) -> AABB:
	var pose := parent_pose * node.transform
	var result := AABB(pose.origin, Vector3.ZERO)
	if node is MeshInstance3D:
		result = pose * node.mesh.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			result = result.merge(feed_item_bounds(child, pose))
	return result

func check_feed_sleeves() -> void:
	var items := Node3D.new()
	var billet := Items.workpiece_billet(items)
	var plate := Items.stamped_plate(items)
	var item_bounds: Array[AABB] = [feed_item_bounds(billet, Transform3D.IDENTITY), feed_item_bounds(plate, Transform3D.IDENTITY)]
	var declared_sizes: Array[Vector3] = [Vector3(0.27, 0.18, 0.36), Vector3(0.44, 0.07, 0.53)]
	var cached: Dictionary = {}
	var assemblies := 0
	var clear_rays := 0
	var minimum_item_gap := INF
	var controls := 0
	for shared_profile in [false, true]:
		for destination in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var view: Variant = Shared.new() if shared_profile else Opening.new()
			view.machine_root = Node3D.new()
			view.add_child(view.machine_root)
			view.state = {"context": "feed-sleeve-fixture", "options": {"native": true},
				"actors": {"P": {"ready": true}}, "transmission_parts": {}, "motion": {},
				"entities": {"from": {"kind": "collector", "cell": [0, 0], "axis": 0, "generation": 1},
					"to": {"kind": "belt", "cell": destination, "axis": 0, "generation": 2}},
				"links": [["from", "to"]], "drive_links": [], "engagements": []}
			var before: Dictionary = view.state.duplicate(true)
			view._rebuild_machines()
			var route: Node3D = view.machine_root.get_node("MaterialRoute")
			var direction := Vector3(destination[0], 0, destination[1]).normalized()
			verify(route.get_meta("feed_sleeve", false) and route.get_child_count() == 8
				and route.basis.z.dot(direction) > 0.99999,
				"Each actual confirmed cardinal link receives one fitted sleeve in its original source-to-destination frame.")
			var channel: MeshInstance3D = route.get_node("FeedChannel")
			var endpoint_low := INF
			var endpoint_high := -INF
			for corner in range(8):
				var point: Vector3 = route.transform * channel.transform * channel.mesh.get_aabb().get_endpoint(corner)
				endpoint_low = minf(endpoint_low, point.dot(direction))
				endpoint_high = maxf(endpoint_high, point.dot(direction))
			verify(absf(endpoint_low - 0.55) < 0.00001 and absf(endpoint_high - 1.10) < 0.00001,
				"The actual channel ends keep the original trimmed native port positions within packed render precision.")
			var aperture := feed_aperture(channel.mesh)
			verify(aperture.is_finite() and is_equal_approx(aperture.x, -0.28) and is_equal_approx(aperture.y, 0.28),
				"The opening is measured from the actual inward wall facets, not the outside bounding box.")
			for n in range(item_bounds.size()):
				var across: Vector3 = route.basis.x
				var actual_width: float = absf(across.x) * item_bounds[n].size.x + absf(across.z) * item_bounds[n].size.z
				var declared_width: float = absf(across.x) * declared_sizes[n].x + absf(across.z) * declared_sizes[n].z
				minimum_item_gap = minf(minimum_item_gap, aperture.y - aperture.x - maxf(actual_width, declared_width))
				verify(actual_width < aperture.y - aperture.x and declared_width < aperture.y - aperture.x,
					"The actual existing billet/plate artwork and their conservative envelopes fit every current cardinal opening.")
			var roles := {"FeedChannel": 0, "FeedCuff": 0, "FeedBolt": 0, "FeedDirection": 0}
			for part: MeshInstance3D in route.get_children():
				var role: String = part.get_meta("feed_sleeve_role")
				roles[role] += 1
				verify(part.get_script() == null and part.get_child_count() == 0 and part.scale.is_equal_approx(Vector3.ONE),
					"Each connection piece is plain render geometry without a controller, collider or span-scaled end detail.")
				if not cached.has(role):
					var limits: Array = {"FeedChannel": [0.004, 0.006], "FeedCuff": [0.00045, 0.00070],
						"FeedBolt": [0.000004, 0.000006], "FeedDirection": [0.000022, 0.000032]}[role]
					check_closed_asset_mesh(part.mesh, limits[0], limits[1])
					cached[role] = [part.mesh, part.material_override]
				verify(part.mesh == cached[role][0] and part.material_override == cached[role][1],
					"Both view classes and all four grid directions reuse their exact compatible meshes and finishes.")
				var finish_value := part.material_override as StandardMaterial3D
				if role == "FeedDirection":
					verify(finish_value.albedo_color == Color("e2c48b") and finish_value.metallic == 0
						and finish_value.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
						and (route.basis * part.basis.y).dot(direction) > 0.99999,
						"The original warm direction cue is an opaque surface mark pointing from producer to receiver.")
					var low := INF
					for corner in range(8):
						low = minf(low, (part.transform * part.mesh.get_aabb().get_endpoint(corner)).y)
					verify(absf(low - 0.09) < 0.000001, "The marking touches the actual channel floor instead of floating above the feed path.")
				else:
					var surface_role := "cast" if role == "FeedCuff" else "worked"
					verify(is_equal_approx(finish_value.metallic, 0.85)
						and finish_value.normal_texture == Opening.ProductionTransmissionFinish.textures[surface_role + "_normal"]
						and finish_value.roughness_texture == Opening.ProductionTransmissionFinish.textures[surface_role + "_roughness"],
						"Channel, cuffs and fasteners retain their actual qualified cast/worked material roles.")
			verify(roles.FeedChannel == 1 and roles.FeedCuff == 2 and roles.FeedBolt == 4 and roles.FeedDirection == 1,
				"The complete connection has one open channel, two fixed cuffs, four fasteners and one floor mark.")
			for x in [-0.26, 0.0, 0.26]:
				for height in [0.11, 0.15]:
					verify(not feed_ray_blocked(route, route.transform.affine_inverse(), Vector3(x, height, -0.35), Vector3(x, height, 0.35)),
						"Actual channel, cuff and hardware facets leave the sampled through-opening unobstructed.")
					clear_rays += 1
			verify(view.state == before and view.model == null and view.actor_world == null and view.request_sequence == 0,
				"Connection rendering changes no confirmed topology, quantity, native actor or request.")
			if controls == 0:
				var narrow := feed_aperture(channel.mesh, Transform3D(Basis.from_scale(Vector3(0.5, 1, 1)), Vector3.ZERO))
				verify(narrow.y - narrow.x < declared_sizes[0].z, "A deliberately narrowed actual channel fails billet clearance.")
				var marker: MeshInstance3D = route.get_node("FeedDirection")
				verify((route.basis.rotated(Vector3.UP, PI) * marker.basis.y).dot(direction) < -0.99999,
					"A reversed marking fails the original producer-to-receiver direction discriminator.")
				var cap := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.60, 0.12, 0.03)
				cap.mesh = box
				cap.position.y = 0.15
				verify(feed_ray_blocked(cap, Transform3D.IDENTITY, Vector3(0, 0.13, -0.35), Vector3(0, 0.13, 0.35)),
					"A filled end cap is detected by the same actual-triangle through-opening check.")
				cap.free()
				controls = 3
			view.state.links = []
			view.pending_link = "from"
			var removed: Dictionary = view.state.duplicate(true)
			view._rebuild_machines()
			verify(view.machine_root.get_node_or_null("MaterialRoute") == null and view.state == removed,
				"Removed or merely pending links do not create or retain feed infrastructure.")
			assemblies += 1
			view.free()
	for span in [0.30, 2.20]:
		var route := Node3D.new()
		verify(Opening.ProductionFeedSleeveArt.mount(route, Vector3.ZERO, Vector3(0, 0, span)),
			"The isolated render helper can vary a middle span without adopting a new native route rule.")
		verify(is_equal_approx(route.get_node("FeedChannel").mesh.get_aabb().size.z, span)
			and route.get_node("FeedCuffN").mesh == cached.FeedCuff[0]
			and route.get_node("FeedBoltNN").mesh == cached.FeedBolt[0],
			"Longer and shorter render spans keep their fixed end cuff and fastener resources unchanged.")
		for suffix in ["N", "P"]:
			var cuff: MeshInstance3D = route.get_node("FeedCuff" + suffix)
			var end: float = cuff.position.z + (cuff.mesh.get_aabb().position.z if suffix == "N" else cuff.mesh.get_aabb().end.z)
			verify(absf(end - (-span / 2.0 if suffix == "N" else span / 2.0)) < 0.00001
				and cuff.scale.is_equal_approx(Vector3.ONE),
				"Each rigid cuff stays flush with its actual channel end rather than stretching with the middle.")
		route.free()
	var equivalent := Node3D.new()
	verify(Opening.ProductionFeedSleeveArt.mount(equivalent, Vector3(5.5, 0, 0), Vector3(6.0500002, 0, 0))
		and equivalent.get_node("FeedChannel").mesh == cached.FeedChannel[0],
		"Tiny packed-coordinate differences reuse the same declared visual mesh length without changing source positions.")
	equivalent.free()
	for end in [Vector3(0, 0, 0.1), Vector3(0, 1, 1), Vector3(INF, 0, 1)]:
		var refused := Node3D.new()
		verify(not Opening.ProductionFeedSleeveArt.mount(refused, Vector3.ZERO, end)
			and refused.get_child_count() == 0 and refused.transform == Transform3D.IDENTITY,
			"Unsupported short, nonlevel or nonfinite render spans refuse before publishing geometry.")
		refused.free()
		controls += 1
	for shared_profile in [false, true]:
		var view: Variant = Shared.new() if shared_profile else Opening.new()
		view.state = {"options": {"native": false}}
		var parent := Node3D.new()
		view.add_child(parent)
		var route: Node3D = view._material_route(parent, Vector3.ZERO, Vector3(1.65, 0, 0))
		verify(route.get_child_count() == 3 and not route.has_meta("feed_sleeve")
			and route.get_node("Rail").mesh is BoxMesh and route.get_node_or_null("ArrowLeft") != null
			and route.get_node_or_null("ArrowRight") != null,
			"Both nonnative view classes retain their earlier rail and two-arrow annotation.")
		view.free()
	items.free()
	print(JSON.stringify({"phase": "feed sleeves", "confirmed_link_assemblies": assemblies,
		"clear_through_rays": clear_rays, "altered_or_invalid_controls": controls,
		"minimum_declared_item_width_margin": minimum_item_gap, "variable_render_spans": [0.30, 2.20],
		"observations": "invented", "native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

func segment_radius(a: Vector2, b: Vector2) -> float:
	var edge := b - a
	if edge.length_squared() == 0:
		return a.length()
	return (a + edge * clampf(-a.dot(edge) / edge.length_squared(), 0, 1)).length()

func triangle_radius(a: Vector2, b: Vector2, c: Vector2) -> float:
	if absf((b - a).cross(c - a)) > 0.000000000001:
		var first := (b - a).cross(-a)
		var second := (c - b).cross(-b)
		var third := (a - c).cross(-c)
		if (first >= 0 and second >= 0 and third >= 0) or (first <= 0 and second <= 0 and third <= 0):
			return 0
	return minf(segment_radius(a, b), minf(segment_radius(b, c), segment_radius(c, a)))

func wheel_mesh_envelope(mesh: Mesh, pose: Transform3D, about_y: bool = false) -> Dictionary:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var points: Array[Vector2] = []
	var low := INF
	var high := -INF
	var minimum_radius := INF
	for vertex in vertices:
		var point := pose * vertex
		low = minf(low, point.y if about_y else point.z)
		high = maxf(high, point.y if about_y else point.z)
		points.append(Vector2(point.x, point.z) if about_y else Vector2(point.x, point.y))
	var corners := vertices.size() if indices.is_empty() else indices.size()
	for n in range(0, corners, 3):
		var a: Vector2 = points[n if indices.is_empty() else indices[n]]
		var b: Vector2 = points[n + 1 if indices.is_empty() else indices[n + 1]]
		var c: Vector2 = points[n + 2 if indices.is_empty() else indices[n + 2]]
		minimum_radius = minf(minimum_radius, triangle_radius(a, b, c))
	return {"low": low, "high": high, "minimum_radius": minimum_radius if not vertices.is_empty() else 0.0}

func wheel_rotating_envelopes(node: Node3D, parent_pose: Transform3D, rows: Array[Dictionary]) -> void:
	var pose := parent_pose * node.transform
	if node is MeshInstance3D and str(node.name) != "WheelHub":
		rows.append(wheel_mesh_envelope(node.mesh, pose))
	for child in node.get_children():
		if child is Node3D:
			wheel_rotating_envelopes(child, pose, rows)

func wheel_support_separates(mesh: Mesh, pose: Transform3D, rotating: Array[Dictionary]) -> bool:
	var low := INF
	var high := -INF
	var maximum_radius := 0.0
	for n in range(8):
		var point := pose * mesh.get_aabb().get_endpoint(n)
		low = minf(low, point.z)
		high = maxf(high, point.z)
		maximum_radius = maxf(maximum_radius, Vector2(point.x, point.y).length())
	for row in rotating:
		if not (high < row.low or low > row.high or maximum_radius < row.minimum_radius):
			return false
	return true

func check_wheel_supports() -> void:
	var cached: Dictionary = {}
	var scale_factor := 0.5 / 0.78
	var minimum_gap := INF
	var entries: Array[float] = []
	var assemblies := 0
	var controls := 0
	for shared_profile in [false, true]:
		for axis_index in range(3):
			var axis: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis_index]
			var view: Variant = Shared.new() if shared_profile else Opening.new()
			view.machine_root = Node3D.new()
			view.add_child(view.machine_root)
			view.state = {"context": "wheel-support-fixture", "options": {"native": true},
				"actors": {"P": {"ready": true}}, "transmission_parts": {}, "motion": {},
				"entities": {"fixture": {"kind": "wheel", "cell": [0, 0], "axis": axis_index, "generation": 1}},
				"links": [], "drive_links": [], "engagements": []}
			var before: Dictionary = view.state.duplicate(true)
			view._rebuild_machines()
			var machine: Node3D = view.machine_root.get_child(0)
			var rotor: Node3D = view.wheel_rotor
			var source: MeshInstance3D = rotor.get_node("SourcedTimberRotor")
			var hub: MeshInstance3D = rotor.get_node("WheelHub")
			verify(source.mesh == WheelArt.mesh and source.material_override == WheelArt.finish
				and source.transform == Transform3D.IDENTITY and hub.mesh is CylinderMesh
				and is_equal_approx(hub.mesh.top_radius, 0.13) and is_equal_approx(hub.mesh.height, 0.45),
				"The new fixed castings retain the exact original sourced rotor, atlas and literal journal cylinder.")
			verify(rotor.position.is_equal_approx(Vector3(0, 0.5, 0))
				and rotor.basis.z.normalized().dot(axis) > 0.99999
				and rotor.scale.is_equal_approx(Vector3.ONE * scale_factor),
				"The original native rotor center, scale and projected spindle axis remain.")
			var rotating: Array[Dictionary] = []
			for child in rotor.get_children():
				if child is Node3D:
					wheel_rotating_envelopes(child, Transform3D.IDENTITY, rotating)
			var inverse: Transform3D = rotor.transform.affine_inverse()
			var counts := {"WheelStand": 0, "AxleBearing": 0, "BearingLiner": 0, "WheelFootBolt": 0}
			var picks := 0
			for child in machine.get_children():
				if child is StaticBody3D:
					picks += 1
					verify(child.collision_layer == Geometry.PICK_LAYER and child.collision_mask == 0
						and child.get_meta("entity") == "fixture" and child.get_child_count() == 1
						and child.get_child(0).shape is BoxShape3D
						and child.get_child(0).shape.size == Vector3(1.45, 1.65, 1.45),
						"The unchanged machine pick box remains separate from the detailed bearing artwork.")
				if not child is MeshInstance3D or not child.has_meta("wheel_support_role"):
					continue
				var role: String = child.get_meta("wheel_support_role")
				counts[role] += 1
				verify(child.get_script() == null and child.get_child_count() == 0 and child.scale.is_equal_approx(Vector3.ONE),
					"Fixed hardware is plain cached render geometry with its scale baked in metres.")
				check_bounds(child, Transform3D.IDENTITY)
				var cache_key := role + ("Vertical" if role == "WheelStand" and axis_index == 1 else "")
				if not cached.has(cache_key):
					var limits: Array = {"WheelStand": [0.010, 0.020], "WheelStandVertical": [0.014, 0.024],
						"AxleBearing": [0.002, 0.009], "BearingLiner": [0.002, 0.004],
						"WheelFootBolt": [0.000020, 0.000025]}[cache_key]
					check_closed_asset_mesh(child.mesh, limits[0] * pow(scale_factor, 3), limits[1] * pow(scale_factor, 3))
					cached[cache_key] = [child.mesh, child.material_override]
				verify(child.mesh == cached[cache_key][0] and child.material_override == cached[cache_key][1],
					"Every view and compatible native axis reuses the same exact hardware resources.")
				var finish_value := child.material_override as StandardMaterial3D
				var surface_role := "worked" if role in ["BearingLiner", "WheelFootBolt"] else "cast"
				verify(finish_value != null and is_equal_approx(finish_value.metallic, 0.85)
					and finish_value.normal_texture == Opening.ProductionTransmissionFinish.textures[surface_role + "_normal"]
					and finish_value.roughness_texture == Opening.ProductionTransmissionFinish.textures[surface_role + "_roughness"],
					"Fixed castings and exposed liners/fasteners use their distinct qualified metal image roles.")
				verify(wheel_support_separates(child.mesh, inverse * child.transform, rotating),
					"Every fixed hardware envelope clears all nonjournal rotor facets throughout a complete turn.")
				if role == "BearingLiner":
					var bore: Dictionary = wheel_mesh_envelope(child.mesh, Transform3D.IDENTITY, true)
					var delta: Vector3 = child.position - rotor.position
					var radial_offset: float = (delta - axis * delta.dot(axis)).length()
					var gap: float = bore.minimum_radius - hub.mesh.top_radius * scale_factor - radial_offset
					minimum_gap = minf(minimum_gap, gap)
					verify(absf(child.basis.y.dot(axis)) > 0.99999 and gap > 0.004 * scale_factor,
						"The complete actual faceted liner bore is coaxial and clears the original rotating journal.")
					var axial_center: float = delta.dot(axis)
					var entry := minf(axial_center + bore.high, 0.225 * scale_factor) \
						- maxf(axial_center + bore.low, -0.225 * scale_factor)
					entries.append(entry)
					verify(entry > 0.07 * scale_factor and entry < 0.09 * scale_factor,
						"The original journal enters each actual liner instead of ending short of a floating bearing.")
					if not shared_profile and axis_index == 0 and controls == 0:
						var filled := CylinderMesh.new()
						filled.top_radius = 0.16 * scale_factor
						filled.bottom_radius = filled.top_radius
						filled.height = 0.2 * scale_factor
						verify(wheel_mesh_envelope(filled, Transform3D.IDENTITY, true).minimum_radius < 0.001 * scale_factor,
							"A deliberately filled bearing cap fails the actual-facet bore discriminator.")
						verify(gap - 0.03 * scale_factor < 0, "The clearance oracle rejects a liner displaced across the journal.")
						controls += 2
				if role == "WheelStand":
					var high := -INF
					for corner in range(8):
						high = maxf(high, (child.transform * child.mesh.get_aabb().get_endpoint(corner)).y)
					verify(high < rotor.position.y - (0.225 if axis_index == 1 else 0.13) * scale_factor,
						"The fixed stand stays below the journal's actual swept cylinder.")
					if not shared_profile and axis_index == 0 and controls == 2:
						var displaced: Transform3D = child.transform
						displaced.origin = Vector3.ZERO
						verify(not wheel_support_separates(child.mesh, inverse * displaced, rotating),
							"Moving a stand into the rotor fails the conservative whole-turn separation oracle.")
						controls += 1
			verify(picks == 1 and counts.WheelStand == (1 if axis_index == 1 else 2)
				and counts.AxleBearing == counts.WheelStand and counts.BearingLiner == counts.WheelStand
				and counts.WheelFootBolt == 4, "The actual native axis has its declared supports, liners and four fitted foot bolts.")
			verify(view.state == before and view.model == null and view.actor_world == null
				and view.request_sequence == 0 and not view.is_inside_tree(),
				"Hardware construction changes no projection, request, native body or authority.")
			assemblies += 1
			view.free()
	verify(controls == 3 and cached.size() == 5, "The three discriminating controls and five unique mesh roles were exercised.")
	var legacy_assemblies := 0
	for shared_profile in [false, true]:
		var view: Variant = Shared.new() if shared_profile else Opening.new()
		view.state = {"options": {"native": false}}
		var machine := Node3D.new()
		view.add_child(machine)
		view._assemble_machine(machine, {"kind": "wheel", "axis": 0})
		var counts := {"stands": 0, "bearings": 0}
		for child in machine.get_children():
			verify(not child.has_meta("wheel_support_role"), "The nonnative assembly does not mount native support artwork.")
			if not child is MeshInstance3D:
				continue
			if child.mesh == Visuals.box_mesh(Vector3(0.16, 0.54, 0.16)):
				counts.stands += 1
				verify(is_equal_approx(child.position.y, 0.51) and is_equal_approx(absf(child.position.z), 0.42)
					and child.material_override == Visuals.material(Color("465a60"), 0.08, 0.5),
					"Historical support posts keep their original positions, shape and finish.")
			elif child.mesh is CylinderMesh and is_equal_approx(child.mesh.top_radius, 0.145):
				counts.bearings += 1
				verify(is_equal_approx(child.mesh.height, 0.18) and is_equal_approx(child.position.y, 0.78)
					and child.material_override == Visuals.material(Color("a6b4af"), 0.85, 0.4),
					"Historical solid bearings retain their exact earlier primitive and material.")
		verify(counts.stands == 2 and counts.bearings == 2, "Both nonnative view classes retain the earlier two-support layout.")
		legacy_assemblies += 1
		view.free()
	print(JSON.stringify({"phase": "waterwheel supports", "assemblies": assemblies, "unique_mesh_roles": cached.size(),
		"minimum_journal_clearance_metres": minimum_gap, "journal_entries_metres": entries, "controls": controls,
		"legacy_assemblies": legacy_assemblies,
		"full_turn_check": "Conservative separation of actual facet envelopes, not native contact or force proof.",
		"observations": "invented", "native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

func check_collector_coating(historical: bool) -> void:
	var surface := Opening.ProductionTransmissionFinish
	var cached: Dictionary = {}
	var assemblies := 0
	var coated_parts := 0
	for shared_profile in [false, true]:
		for axis in range(3):
			var view: Variant = Shared.new() if shared_profile else Opening.new()
			view.state = {"options": {"native": true}, "entities": {}, "transmission_parts": {},
				"motion": {}, "actors": {"P": {"ready": true}}}
			var before: Dictionary = view.state.duplicate(true)
			var machine := Node3D.new()
			view.add_child(machine)
			view._assemble_machine(machine, {"kind": "collector", "axis": axis})
			var frame: Node3D = machine.get_node("CollectorCastFrame")
			var count := 0
			for part: MeshInstance3D in frame.get_children():
				var role: String = part.get_meta("collector_frame_role")
				var finish_value := part.material_override as StandardMaterial3D
				if role == "FixedBearingLiner":
					verify(finish_value == surface.material("worked", Color("a6b4af"), 0.85, 0.38),
						"The real bearing liner retains its original exposed worked-metal material.")
					continue
				count += 1
				var color := Color("d6a34d").darkened(0.09) if role == "CastLowerHousing" else Color("d6a34d")
				verify(finish_value != null and finish_value.albedo_color == color,
					"Each actual cast role preserves its original design color and housing shade.")
				if historical:
					verify(finish_value == Visuals.material(color, 0.08, 0.72),
						"A missing historical map set retains the exact original generated coating resource.")
				else:
					verify(finish_value.metallic == 0 and finish_value.metallic_texture == null
						and finish_value.metallic_specular == 0.5 and finish_value.albedo_texture == null
						and finish_value.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
						and not finish_value.clearcoat_enabled and not finish_value.ao_enabled,
						"The authored opaque paint is a dielectric without a second coat, metallic mask or invented occlusion.")
					verify(finish_value.normal_enabled and is_equal_approx(finish_value.normal_scale, 0.12)
						and finish_value.normal_texture == surface.textures.cast_normal
						and finish_value.roughness_texture == surface.textures.cast_roughness
						and finish_value.roughness == 1 and finish_value.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED,
						"The coating reuses the exact qualified cast maps with reduced normal strength and explicit scalar roughness.")
					verify(finish_value.uv1_triplanar and not finish_value.uv1_world_triplanar
						and finish_value.uv1_scale == Vector3(4, 4, 4)
						and finish_value.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
						"Local mapping retains the declared quarter-metre art scale and mip filtering.")
					var original := surface.material("cast", color, 0.0, 0.72)
					verify(finish_value != original and is_equal_approx(original.normal_scale, 0.35),
						"Reducing coating relief does not mutate the independently cached source material.")
				if cached.has(color):
					verify(finish_value == cached[color], "Every view and axis shares one coating material per original tint.")
				else:
					cached[color] = finish_value
			verify(count == 6, "Exactly six existing painted casting roles receive the coating.")
			coated_parts += count
			var drum: MeshInstance3D = machine.get_node("CutterDrum")
			verify(drum.material_override == Visuals.material(Color("465a60"), 0.85, 0.4),
				"The original moving cutter's metal finish is not recolored or treated as paint.")
			verify(view.state == before and view.model == null and view.actor_world == null
				and view.request_sequence == 0 and not view.is_inside_tree(),
				"Material construction changes no projection, authority, native body or request.")
			assemblies += 1
			view.free()
	verify(cached.size() == 2 and surface.source_status == ("missing" if historical else "ready"),
		"Two original tints and the declared resource presence remain explicit.")
	print(JSON.stringify({"phase": "collector coating", "assemblies": assemblies, "coated_parts": coated_parts,
		"coating_materials": cached.size(), "historical_missing_set": historical,
		"maps": "existing qualified cast normal and roughness", "geometry_changed": false,
		"native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

func check_closed_asset_mesh(mesh: Mesh, minimum_volume: float, maximum_volume: float) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var corners := vertices.size() if indices.is_empty() else indices.size()
	verify(vertices.size() > 0 and corners % 3 == 0 and normals.size() == vertices.size()
		and tangents.size() == vertices.size() * 4 and uv.size() == vertices.size(),
		"Each original casting has complete normal-mapped triangle attributes.")
	var edges: Dictionary = {}
	var volume := 0.0
	var valid := true
	var winding := true
	for n in range(0, corners, 3):
		var first_index: int = n if indices.is_empty() else indices[n]
		var a := vertices[first_index]
		var b := vertices[n + 1 if indices.is_empty() else indices[n + 1]]
		var c := vertices[n + 2 if indices.is_empty() else indices[n + 2]]
		var cross := (b - a).cross(c - a)
		winding = winding and cross.length_squared() > 0.00000000000001 and cross.dot(normals[first_index]) < 0
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

func paddle_local_bounds(node: Node3D, parent_pose: Transform3D) -> void:
	var pose := parent_pose * node.transform
	verify(node.get_script() == null and not node is CollisionObject3D and not node is CollisionShape3D,
		"Paddle pieces are plain render nodes without a controller or collider.")
	if node is MeshInstance3D:
		var bounded := true
		for corner in range(8):
			var point: Vector3 = pose * node.mesh.get_aabb().get_endpoint(corner)
			bounded = bounded and absf(point.x) <= 0.07001 and absf(point.y) <= 0.08001 and absf(point.z) <= 0.14001
		verify(bounded, "Every blade, cleat, strap and bolt fits the original paddle's literal local envelope.")
	for child in node.get_children():
		if child is Node3D:
			paddle_local_bounds(child, pose)

func check_paddle_maps() -> void:
	var finish_value: StandardMaterial3D = PaddleArt.finish
	verify(finish_value != null and finish_value.albedo_color == Color.WHITE and finish_value.metallic == 0
		and finish_value.metallic_texture == null and not finish_value.ao_enabled
		and finish_value.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"The actual timber material is opaque nonmetallic wood without invented occlusion or opacity.")
	verify(finish_value.normal_enabled and finish_value.normal_scale == 1
		and finish_value.roughness == 1 and finish_value.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED
		and not finish_value.uv1_triplanar and finish_value.uv1_scale.is_equal_approx(Vector3.ONE / 0.6),
		"The explicit red scalar and local authored UVs preserve the declared visual grain scale.")
	var normal := finish_value.normal_texture.get_image()
	var roughness := finish_value.roughness_texture.get_image()
	verify(finish_value.albedo_texture.get_size() == Vector2(1024, 1024)
		and normal.get_size() == Vector2i(512, 512) and roughness.get_size() == Vector2i(512, 512)
		and normal.get_format() == Image.FORMAT_RGB8 and roughness.get_format() == Image.FORMAT_L8
		and normal.has_mipmaps() and roughness.has_mipmaps() and finish_value.albedo_texture.get_image().has_mipmaps(),
		"Actual cached image textures retain their dimensions, data formats and mip chains.")
	var valid := true
	var maximum_error := 0.0
	var low := INF
	var high := -INF
	for y in range(0, 512, 32):
		for x in range(0, 512, 32):
			var color := normal.get_pixel(x, y)
			var decoded := Vector3(color.r, color.g, color.b) * 2 - Vector3.ONE
			maximum_error = maxf(maximum_error, absf(decoded.length() - 1))
			valid = valid and decoded.is_finite() and decoded.z > 0 and absf(decoded.length() - 1) < 0.01
			low = minf(low, roughness.get_pixel(x, y).r)
			high = maxf(high, roughness.get_pixel(x, y).r)
	verify(valid and low >= 0 and high <= 1 and high - low > 0.05,
		"Actual normal texels remain finite outward unit vectors and roughness has nonconstant scalar content.")
	var missing: Dictionary = PaddleArt.read_images("user://paddle-controls/missing")
	verify(missing.status == "missing", "An absent historical timber set is explicitly distinguishable.")
	var partial := "user://paddle-controls/partial"
	DirAccess.make_dir_recursive_absolute(partial)
	verify(DirAccess.copy_absolute(PaddleArt.ROOT.path_join("timber_albedo.jpg"), partial.path_join("timber_albedo.jpg")) == OK,
		"The partial-set control contains an actual valid color file.")
	verify(PaddleArt.read_images(partial).status == "invalid", "A partial source set cannot become sourced timber success.")
	var wrong := "user://paddle-controls/wrong-size"
	DirAccess.make_dir_recursive_absolute(wrong)
	var small := Image.create(8, 8, false, Image.FORMAT_RGB8)
	small.fill(Color(0.5, 0.5, 1))
	for role in PaddleArt.FILES:
		var path := wrong.path_join(PaddleArt.FILES[role])
		verify((DirAccess.copy_absolute(PaddleArt.ROOT.path_join(PaddleArt.FILES.albedo), path)
			if role == "albedo" else small.save_webp(path, false)) == OK,
			"The size control uses valid encoded images rather than a decoder failure.")
	verify(PaddleArt.read_images(wrong).status == "invalid", "A complete but wrongly sized image set is refused.")
	print(JSON.stringify({"phase": "paddle material", "maximum_sampled_normal_length_error": maximum_error,
		"roughness_sample_range": [low, high], "resource_controls": 3}))

func check_timber_paddles(historical: bool = false) -> void:
	verify(PaddleArt.read_images().status == ("missing" if historical else "ready"),
		"This captured project has the explicitly declared timber resource presence.")
	var cached: Dictionary = {}
	var root_counts: Array[int] = []
	var assemblies := 0
	for shared_profile in [false, true]:
		for axis in range(3):
			var view: Variant = Shared.new() if shared_profile else Opening.new()
			var facts := PaddleSessionFacts.new()
			if shared_profile:
				view.session = facts
			view.machine_root = Node3D.new()
			view.add_child(view.machine_root)
			view.state = {"context": "paddle-asset-fixture", "options": {"native": true, "physical": true},
				"actors": {"P": {"ready": true}}, "parts": {}, "inventories": {"P": 0},
				"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
				"entities": {"fixture": {"kind": "wheel", "cell": [0, 0], "axis": axis, "generation": 1}},
				"transmission_parts": {}, "links": [], "drive_links": [], "engagements": [],
				"motion": {"fixture": {"state": "rotating", "numerator": -2, "denominator": 1}}}
			var before: Dictionary = view.state.duplicate(true)
			view.transmission_presenter = Presenter.new()
			view.add_child(view.transmission_presenter)
			view.transmission_presenter.configure(view)
			view._rebuild_machines()
			var machine: Node3D = view.machine_root.get_child(0)
			var rotor: Node3D = view.wheel_rotor
			var source: MeshInstance3D = rotor.get_node("SourcedTimberRotor")
			verify(source.mesh == WheelArt.mesh and source.material_override == WheelArt.finish
				and source.transform == Transform3D.IDENTITY and source.get_child_count() == 0,
				"The original sourced rotor mesh, atlas and rigid placement remain exact.")
			print(JSON.stringify({"phase": "paddle mount observation", "shared_class": shared_profile, "axis": axis,
				"center": [rotor.position.x, rotor.position.y, rotor.position.z],
				"axis_vector": [rotor.basis.z.normalized().x, rotor.basis.z.normalized().y, rotor.basis.z.normalized().z]}))
			verify(rotor.position.is_equal_approx(Vector3(0, 0.5, 0))
				and rotor.basis.z.normalized().dot([Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis]) > 0.99999,
				"The ordinary wheel keeps its literal native center and projected spindle axis.")
			var blades := 0
			for child in rotor.get_children():
				if not child is MeshInstance3D:
					continue
				if historical:
					if child.mesh == Visuals.box_mesh(Vector3(0.14, 0.16, 0.28)):
						blades += 1
						verify(child.get_child_count() == 0 and child.material_override == Visuals.material(Color("b48c52"), 0.05, 0.88),
							"Historical missing-map captures retain their exact earlier blocks and finish.")
					continue
				if child.get_meta("detail_role", "") != "WheelPaddle":
					continue
				blades += 1
				var index: int = child.get_meta("paddle_index")
				var angle := float(index) * TAU / 12
				verify(index >= 0 and index < 12 and child.position.is_equal_approx(Vector3(cos(angle), sin(angle), 0) * 0.62)
					and child.basis.is_equal_approx(Basis(Vector3.BACK, angle)),
					"Each original paddle position and angular frame remains fixed to the rotor.")
				paddle_local_bounds(child, child.transform.affine_inverse())
				verify(child.get_child_count() == 5 and count_role(child, "PaddleRootCleat") == 1
					and count_role(child, "PaddleIronStrap") == 2 and count_role(child, "PaddleBolt") == 2,
					"Every timber blade has one fitted root, two iron straps and two bolts.")
				var pieces: Array = [child]
				pieces.append_array(child.get_children())
				for part: MeshInstance3D in pieces:
					var role: String = part.get_meta("detail_role")
					if not cached.has(role):
						cached[role] = [part.mesh, part.material_override]
						var limits: Array = {"WheelPaddle": [0.00065, 0.00071], "PaddleRootCleat": [0.00021, 0.000241],
							"PaddleIronStrap": [0.0000095, 0.0000106], "PaddleBolt": [0.0000049, 0.0000052]}[role]
						check_closed_asset_mesh(part.mesh, limits[0], limits[1])
						if role == "WheelPaddle":
							verify(part.mesh.get_aabb().size.is_equal_approx(Vector3(0.14, 0.018, 0.28)),
								"The original blade span now has a literal eighteen-millimetre timber thickness.")
							var arrays: Array = part.mesh.surface_get_arrays(0)
							var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
							var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
							var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
							var broad_faces := 0
							var aligned := true
							for n in range(positions.size()):
								if absf(normals[n].y) > 0.99999:
									broad_faces += 1
									aligned = aligned and uv[n].is_equal_approx(Vector2(positions[n].x, positions[n].z))
							verify(aligned and broad_faces > 0, "The actual broad blade UVs put source grain V along its longer axial span.")
					verify(part.mesh == cached[role][0] and part.material_override == cached[role][1],
						"All blade assemblies reuse their exact role-specific mesh and material resources.")
					var material := part.material_override as StandardMaterial3D
					verify(material != null and (material == PaddleArt.finish if role in ["WheelPaddle", "PaddleRootCleat"]
						else is_equal_approx(material.metallic, 0.85) and material.albedo_color == Color("46504e")),
						"Timber and attachment iron retain distinct actual material bindings.")
				if not shared_profile and axis == 0:
					var vertices: PackedVector3Array = source.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
					var inverse: Transform3D = child.transform.affine_inverse()
					var cleat: MeshInstance3D = child.get_child(0)
					var inside := 0
					for point in vertices:
						var local: Vector3 = inverse * point - cleat.position
						if absf(local.x) < 0.015 and absf(local.y) < 0.025 and absf(local.z) < 0.045:
							inside += 1
					root_counts.append(inside)
					verify(inside > 0, "The actual unchanged imported rotor intersects every new root's conservative interior.")
			verify(blades == 12 and PaddleArt.source_status == ("missing" if historical else "ready"),
				"The ordinary builder keeps exactly twelve paddles and the declared source qualification.")
			var base := rotor.basis
			for sample in range(24):
				rotor.basis = base * Basis(Vector3.BACK, float(sample) * TAU / 24)
				check_bounds(rotor, Transform3D.IDENTITY)
			rotor.basis = base
			view._animate_wheel(0.1)
			verify(rotor.basis.is_equal_approx(base * Basis(Vector3.BACK, -0.16)) and view.state == before,
				"The complete paddle assembly consumes the existing signed cosmetic angle without changing native observations.")
			view.state.motion.fixture.state = "stalled"
			var stopped: Dictionary = view.state.duplicate(true)
			var held := rotor.basis
			view._animate_wheel(0.2)
			verify(rotor.basis == held and view.state == stopped,
				"A confirmed mechanical stall freezes the whole timber assembly.")
			verify(view.model == null and view.actor_world == null and view.request_sequence == 0,
				"The asset fixture creates no state authority, character body or material request.")
			view.free()
			assemblies += 1
	if not historical:
		check_paddle_maps()
	print(JSON.stringify({"phase": "timber paddles", "assemblies": assemblies, "paddles_per_assembly": 12,
		"historical_missing_set": historical, "original_source_vertices_inside_each_root": root_counts,
		"observations": "invented", "native_gameplay": "not_run"}))

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
				check_closed_asset_mesh(part.mesh, limits[role][0], limits[role][1])
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

func skid_ray(mesh: Mesh, x: float, z: float, from_y: float, to_y: float) -> Variant:
	var faces := mesh.get_faces()
	var from := Vector3(x, from_y, z)
	var to := Vector3(x, to_y, z)
	var closest: Variant = null
	for n in range(0, faces.size(), 3):
		var at: Variant = Geometry3D.segment_intersects_triangle(from, to, faces[n], faces[n + 1], faces[n + 2])
		if at != null and (closest == null or from.distance_squared_to(at) < from.distance_squared_to(closest)):
			closest = at
	return closest

func check_machine_support_skid() -> void:
	var mesh := SkidArt.skid_mesh()
	verify(mesh == SkidArt.skid_mesh() and mesh.get_surface_count() == 1,
		"All base components share one cached mesh surface and material binding.")
	check_closed_asset_mesh(mesh, 0.13, 0.15)
	var bounds := mesh.get_aabb()
	verify(bounds.position.is_equal_approx(Vector3(-0.675, -0.12, -0.675))
		and bounds.size.is_equal_approx(Vector3(1.35, 0.24, 1.35)),
		"The open support skid keeps the exact old plinth outer envelope.")
	var open: Variant = skid_ray(mesh, 0, 0, -0.3, 0.07)
	verify(open == null, "The actual combined geometry leaves the central underside open below its mounting deck.")
	verify(skid_ray(Visuals.box_mesh(Vector3(1.35, 0.24, 1.35)), 0, 0, -0.3, 0.07) != null,
		"The earlier solid block does not satisfy the new open-underside art requirement.")
	var rail: Variant = skid_ray(mesh, -0.61, 0, -0.3, 0.07)
	var cross_tie: Variant = skid_ray(mesh, 0, 0.38, -0.3, 0.07)
	var deck: Variant = skid_ray(mesh, 0, 0, 0.3, 0.07)
	verify(rail != null and absf(rail.y + 0.12) < 0.00001,
		"The formed rail web provides actual closed support down to the original base plane.")
	verify(cross_tie != null and absf(cross_tie.y - 0.0225) < 0.00001,
		"The internal cross ties are actual geometry across the two side channels.")
	verify(deck != null and absf(deck.y - 0.12) < 0.00001,
		"The actual mounting deck retains the literal top plane.")
	var instances := 0
	for kind in ["collector", "belt", "processor", "wheel"]:
		for axis in range(3):
			var view := Opening.new()
			view.machine_root = Node3D.new()
			view.state = {"options": {"native": true}, "remaining": 0, "stock": {"held": 0},
				"entities": {"fixture": {"kind": kind, "cell": [0, 0], "axis": axis, "generation": 1}},
				"links": [], "drive_links": []}
			var before: Dictionary = view.state.duplicate(true)
			view._rebuild_machines()
			var machine: Node3D = view.machine_root.get_child(0)
			var plinth := machine.get_node("Plinth") as MeshInstance3D
			verify(plinth != null and plinth.mesh == mesh and plinth.position == Vector3(0, 0.12, 0)
				and plinth.basis == Basis.IDENTITY and plinth.get_meta("asset_role", "") == "MachineSupportSkid",
				"Every actual machine family and projected spindle axis mounts the same base at the original pose.")
			verify(plinth.get_script() == null and plinth.get_child_count() == 0
				and plinth.material_override == Visuals.material(Color("273c41"), 0.08, 0.5),
				"The base retains its original opaque finish and has no physical or control children.")
			var picks := 0
			for child in machine.get_children():
				if child is StaticBody3D:
					picks += 1
					verify(child.collision_layer == Geometry.PICK_LAYER and child.collision_mask == 0
						and child.get_meta("entity", "") == "fixture" and child.get_child_count() == 1
						and child.get_child(0).shape.size == Vector3(1.45, 1.65, 1.45),
						"The base changes neither the original pick dimensions nor its entity, layers or masks.")
			verify(picks == 1 and count_role(machine, "FoundationFastener") == 4,
				"The original four mounting fasteners and sole entity pick body remain.")
			verify(view.state == before and view.model == null and view.actor_world == null and view.request_sequence == 0,
				"The shared base cannot change observed quantities, construction, requests or authority.")
			instances += 1
			view.machine_root.free()
			view.free()
	print(JSON.stringify({"phase": "machine support skid", "machine_instances": instances,
		"underside_open": open == null, "mounting_plane": 0.24, "triangles": mesh.get_faces().size() / 3}))

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
				verify(child.mesh is ArrayMesh and child.get_meta("wheel_support_role", "") == "AxleBearing"
					and absf(child.basis.y.normalized().dot(axis)) > 0.99999,
					"The open bearing follows its actual projected axle.")
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
			"The original foundation envelope and mounting height stay intact.")
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
		var old_supports := 0
		for child in view.machine_root.get_child(0).get_children():
			verify(not child.has_meta("wheel_support_role"),
				"The missing-source roster does not mount supports fitted to a different rotor.")
			if child is MeshInstance3D and child.mesh == Visuals.box_mesh(Vector3(0.16, 0.54, 0.16)
					* (0.5 / 0.78 if native_profile else 1.0)):
				old_supports += 1
		verify(old_supports == 2, "The historical native and scripted wheel retain their original two posts.")
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

func prepare_paddle_maps() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Use --prepare-paddle-maps SOURCE_DIRECTORY FRESH_OUTPUT_DIRECTORY.")
		quit(1)
		return
	var source := args[1]
	var output := args[2]
	var directory := DirAccess.open(output)
	if directory == null or not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		push_error("The prepared paddle directory must already exist and be empty.")
		quit(1)
		return
	var pins := {"albedo.jpg": "d171f45ef01bc6e239b00dfaa4961bcd27f7d8e93e3962da3bd3d0ce703d802c",
		"normal.png": "ed173765ea09b3f19ddb2ab71e8d205815b980263c3dcb71695c13f704663514",
		"roughness.png": "0e8cd8d6f16e7a05278ed45f11b51fb6e5d227e71c71d5a556f1a939d513694d"}
	for name_value in pins:
		if FileAccess.get_sha256(source.path_join(name_value)) != pins[name_value]:
			push_error("The paddle source hash differs: " + name_value)
			quit(1)
			return
	var originals: Dictionary = {}
	var formats: Dictionary = {}
	var source_alpha: Dictionary = {}
	# Independent raw PNG8 row-filter decoding supplies these RGB byte hashes.
	var decoded_pins := {"normal": "8f381633310af70a23a4779a32050d2b7383b94b970d3a6eec211b831710c4fb",
		"roughness": "f17b032cc08cbc36b76d59eaeb3448de458bb98756246ed4dc596f88f5d2672e"}
	for role in ["normal", "roughness"]:
		var original := Image.load_from_file(source.path_join(role + ".png"))
		if original == null or original.get_size() != Vector2i(1024, 1024):
			push_error("Expected the pinned one-kilopixel paddle data map: " + role)
			quit(1)
			return
		formats[role] = original.get_format()
		var raw: Image = original.duplicate()
		original.convert(Image.FORMAT_RGBF)
		var minimum_alpha := 255
		var maximum_alpha := 0
		var nonopaque := 0
		var raw_rgb := PackedByteArray()
		raw_rgb.resize(1024 * 1024 * 3)
		# Material normals ignore alpha; roughness explicitly selects red. Keep
		# every data component unchanged when dropping this unused channel.
		# A full pixel comparison also rejects accidental premultiplication.
		for y in range(1024):
			for x in range(1024):
				var before := raw.get_pixel(x, y)
				var after := original.get_pixel(x, y)
				if Vector3(before.r, before.g, before.b) != Vector3(after.r, after.g, after.b):
					push_error("Dropping unused alpha changed the paddle data channels: " + role)
					quit(1)
					return
				var at := (y * 1024 + x) * 3
				for channel in range(3):
					raw_rgb[at + channel] = clampi(roundi(before[channel] * 255), 0, 255)
				var alpha := clampi(roundi(before.a * 255), 0, 255)
				minimum_alpha = mini(minimum_alpha, alpha)
				maximum_alpha = maxi(maximum_alpha, alpha)
				if alpha != 255:
					nonopaque += 1
		var hash_context := HashingContext.new()
		if hash_context.start(HashingContext.HASH_SHA256) != OK or hash_context.update(raw_rgb) != OK:
			push_error("Cannot verify the original paddle data channels.")
			quit(1)
			return
		var raw_digest := hash_context.finish().hex_encode()
		if raw_digest != decoded_pins[role]:
			push_error("Paddle image loading changed the pinned PNG data channels: " + role)
			quit(1)
			return
		source_alpha[role] = {"minimum": minimum_alpha, "maximum": maximum_alpha,
			"nonopaque_pixels": nonopaque, "all_data_channels_preserved": true, "original_rgb_sha256": raw_digest}
		original.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		originals[role] = original
	var report: Dictionary = {"status": "pass", "source_size": [1024, 1024], "source_alpha": source_alpha, "maps": {}}
	for role in originals:
		var normal_map: bool = role == "normal"
		var channels := 3 if normal_map else 1
		var pixels := PackedByteArray()
		pixels.resize(512 * 512 * channels)
		var maximum_length_error := 0.0
		var maximum_angle := 0.0
		for y in range(512):
			for x in range(512):
				var color: Color = originals[role].get_pixel(x, y)
				var at := (y * 512 + x) * channels
				if normal_map:
					var normal := Vector3(color.r * 2 - 1, color.g * 2 - 1, color.b * 2 - 1)
					if not normal.is_finite() or normal.length_squared() < 0.000001:
						push_error("The prepared paddle normal cannot be normalized.")
						quit(1)
						return
					normal = normal.normalized()
					for axis in range(3):
						pixels[at + axis] = clampi(roundi((normal[axis] * 0.5 + 0.5) * 255), 0, 255)
					var decoded := Vector3(pixels[at], pixels[at + 1], pixels[at + 2]) / 255.0 * 2.0 - Vector3.ONE
					maximum_length_error = maxf(maximum_length_error, absf(decoded.length() - 1))
					maximum_angle = maxf(maximum_angle, rad_to_deg(acos(clampf(decoded.normalized().dot(normal), -1, 1))))
				else:
					pixels[at] = clampi(roundi(color.r * 255), 0, 255)
		if maximum_length_error >= 0.01 or maximum_angle >= 0.5:
			push_error("The prepared paddle normal exceeds its encoding bound.")
			quit(1)
			return
		var format := Image.FORMAT_RGB8 if normal_map else Image.FORMAT_L8
		var prepared := Image.create_from_data(512, 512, false, format, pixels)
		var target := output.path_join("timber_normal_gl.webp" if normal_map else "timber_roughness.webp")
		if prepared.save_webp(target, false) != OK:
			push_error("Cannot encode the paddle data map: " + role)
			quit(1)
			return
		var packed := Image.load_from_file(target)
		if packed == null:
			push_error("Cannot decode the prepared paddle map: " + role)
			quit(1)
			return
		packed.convert(format)
		if packed.get_size() != Vector2i(512, 512) or packed.get_data() != pixels:
			push_error("Prepared paddle pixels changed in lossless encoding: " + role)
			quit(1)
			return
		report.maps[role] = {"source_decoded_format": formats[role], "runtime_format": format,
			"prepared_pixel_equality": true, "maximum_normal_length_error": maximum_length_error,
			"maximum_normal_encoding_angle_degrees": maximum_angle, "bytes": FileAccess.get_file_as_bytes(target).size()}
	var albedo := output.path_join("timber_albedo.jpg")
	if DirAccess.copy_absolute(source.path_join("albedo.jpg"), albedo) != OK \
			or FileAccess.get_sha256(albedo) != pins["albedo.jpg"]:
		push_error("Cannot preserve the original paddle albedo bytes.")
		quit(1)
		return
	report.maps.albedo = {"original_jpeg_bytes_preserved": true, "bytes": FileAccess.get_file_as_bytes(albedo).size()}
	report.processing = "Unused alpha dropped with exact full-image RGB preservation. Float Lanczos resize, normalized OpenGL normals, nearest RGB8/L8 encoding and exact lossless WebP roundtrip. Original color JPEG is not reencoded."
	print(JSON.stringify(report))
	quit(0)

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--press-crown-only"):
		check_press_crown()
		finish()
		return
	if OS.get_cmdline_user_args().has("--wheel-foot-seats-only"):
		check_wheel_foot_seats()
		finish()
		return
	if OS.get_cmdline_user_args().has("--feed-sleeves-only"):
		check_feed_sleeves()
		finish()
		return
	if OS.get_cmdline_user_args().has("--wheel-supports-only"):
		check_wheel_supports()
		finish()
		return
	if OS.get_cmdline_user_args().has("--collector-coating-only") or OS.get_cmdline_user_args().has("--historical-coating-only"):
		check_collector_coating(OS.get_cmdline_user_args().has("--historical-coating-only"))
		finish()
		return
	if OS.get_cmdline_user_args().has("--paddles-only") or OS.get_cmdline_user_args().has("--historical-paddles-only"):
		check_timber_paddles(OS.get_cmdline_user_args().has("--historical-paddles-only"))
		finish()
		return
	if OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "--prepare-paddle-maps":
		prepare_paddle_maps()
		return
	if OS.get_cmdline_user_args().has("--machine-skid-only"):
		check_machine_support_skid()
		check_collector_cast_frame()
		finish()
		return
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
