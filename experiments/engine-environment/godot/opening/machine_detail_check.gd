extends SceneTree
## Authored mesh and visual assembly checks. No game authority or desktop.
const Opening = preload("res://opening/opening.gd")
const Shared = preload("res://opening/shared_opening.gd")
const Visuals = Opening.ProductionVisuals
const WheelArt = Opening.ProductionWheelArt
const PaddleArt = Opening.ProductionPaddleArt
const PressArt = Opening.ProductionPressArt
const DieArt = Opening.ProductionPressDieArt
const TrayArt = Opening.ProductionPressTrayArt
const ConveyorArt = Opening.ProductionConveyorArt
const CollectorArt = Opening.ProductionCollectorArt
const CollectorToolingArt = Opening.ProductionCollectorToolingArt
const DriveJournalArt = Opening.ProductionDriveJournalArt
const FoundationArt = Opening.ProductionFoundationArt
const SkidArt = Opening.ProductionSkidArt
const Presenter = preload("res://opening/native_transmission_presenter.gd")
const TransmissionAssets = preload("res://opening/native_transmission_assets.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const Items = preload("res://opening/workpiece_item_assets.gd")
var checks := 0
var failed := false
var max_tangent_dot := 0.0
var detail_meshes := 0
var minimum_press_gap := INF
var minimum_collector_gap := INF
var foundation_art_complete := false
var press_input_checks_complete := false
var wheel_support_checks_complete := false
var span_belt_checks_complete := false
var paddle_grain_checks_complete := false
var paddle_hardware_checks_complete := false

func paddle_fastener_bounds(mesh: Mesh, pose: Transform3D) -> AABB:
	var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for point in points:
		var world_point := pose * point
		minimum = minimum.min(world_point)
		maximum = maximum.max(world_point)
	return AABB(minimum, maximum - minimum)

func paddle_fastener_facts(mesh: Mesh, pose: Transform3D, strap_pose: Transform3D) -> Dictionary:
	var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var axis := (pose.basis * Vector3.UP).normalized()
	var inverse_strap := strap_pose.affine_inverse()
	var minimum_radius := INF
	var maximum_radius := 0.0
	var minimum_axial := INF
	var maximum_axial := -INF
	var cap_points := 0
	var seated_points := 0
	var largest_gap := 0.0
	for point in points:
		var mapped := pose.basis * point
		var axial := mapped.dot(axis)
		minimum_axial = minf(minimum_axial, axial)
		maximum_axial = maxf(maximum_axial, axial)
		if Vector2(point.x, point.z).length() < 0.005:
			continue
		var radius := (mapped - axis * axial).length()
		minimum_radius = minf(minimum_radius, radius)
		maximum_radius = maxf(maximum_radius, radius)
		if absf(point.y - 0.005) < 0.000001:
			cap_points += 1
			var on_strap: Vector3 = inverse_strap * (pose * point)
			# Strap-local coordinates must be converted before reporting a metre gap.
			largest_gap = maxf(largest_gap, absf(on_strap.y + 0.003) * strap_pose.basis.y.length())
			if absf(on_strap.y + 0.003) < 0.00001 and absf(on_strap.x) < 0.03428 \
				and absf(on_strap.z) < 0.01178:
				seated_points += 1
	return {"minimum_radius": minimum_radius, "maximum_radius": maximum_radius,
		"height": maximum_axial - minimum_axial, "cap_points": cap_points,
		"seated_points": seated_points, "largest_gap": largest_gap}

func check_paddle_hardware() -> void:
	paddle_hardware_checks_complete = false
	var observations: Array = []
	var assemblies := 0
	var cached_mesh: Mesh
	var cached_finish: Material
	var old_head := CylinderMesh.new()
	old_head.top_radius = 0.014
	old_head.bottom_radius = 0.014
	old_head.height = 0.01
	old_head.radial_segments = 6
	for shared_profile in [false, true]:
		for axis in [0, 2]:
			for tiles in [3, 5, 8]:
				var view: Variant = Shared.new() if shared_profile else Opening.new()
				if shared_profile:
					view.session = PaddleSessionFacts.new()
				view.state = {"context": "paddle-hardware-fixture", "options": {"native": true, "physical": true},
					"actors": {"P": {"ready": true}}, "stock": {}, "entities": {}, "parts": {},
					"transmission_parts": {}, "motion": {}, "links": [], "drive_links": [], "engagements": []}
				var before: Dictionary = view.state.duplicate(true)
				var machine := Node3D.new()
				view._assemble_machine(machine, {"kind": "wheel", "axis": axis, "tiles": tiles,
					"cell": [0, 0], "generation": 1})
				var rotor: Node3D = view.wheel_rotor
				var blade: MeshInstance3D
				for child in rotor.get_children():
					if child is MeshInstance3D and child.get_meta("paddle_index", -1) == 0:
						blade = child
						break
				verify(blade != null, "The ordinary wheel provides a first mounted paddle.")
				if blade == null:
					machine.free()
					view.free()
					continue
				var paddle_pose := rotor.transform * blade.transform
				var bolt_count := 0
				for part in blade.get_children():
					if part.get_meta("detail_role", "") != "PaddleBolt":
						continue
					var bolt: MeshInstance3D = part
					var strap: MeshInstance3D
					for candidate in blade.get_children():
						if candidate.get_meta("detail_role", "") == "PaddleIronStrap" \
							and is_equal_approx(candidate.position.z, bolt.position.z):
							strap = candidate
							break
					verify(strap != null, "Every head has the original matching formed strap.")
					if strap == null:
						continue
					var pose := paddle_pose * bolt.transform
					var strap_pose := paddle_pose * strap.transform
					var facts := paddle_fastener_facts(bolt.mesh, pose, strap_pose)
					verify(facts.cap_points >= 6 and facts.seated_points == facts.cap_points
						and facts.largest_gap < 0.00001,
						"Every upper hex corner sits on the existing strap underside and inside its flat face.")
					verify(absf(facts.minimum_radius - 0.013) < 0.00001
						and absf(facts.maximum_radius - 0.013) < 0.00001
						and absf(facts.height - 0.01) < 0.00001,
						"The mounted fastener keeps its regular 13 mm corners and 10 mm height.")
					var old_pose := paddle_pose * Transform3D(Basis(), Vector3(-0.05, -0.041, bolt.position.z))
					var old_bounds := paddle_fastener_bounds(old_head, old_pose)
					var new_bounds := paddle_fastener_bounds(bolt.mesh, pose)
					for coordinate in 3:
						verify(new_bounds.position[coordinate] >= old_bounds.position[coordinate] - 0.00001
							and new_bounds.end[coordinate] <= old_bounds.end[coordinate] + 0.00001,
							"The rigid head stays inside the previous conservative visual envelope.")
					var distorted := bolt.transform
					distorted.basis = Basis()
					var distortion := paddle_fastener_facts(bolt.mesh, paddle_pose * distorted, strap_pose)
					verify(distortion.maximum_radius - distortion.minimum_radius > 0.01
						and distortion.height > 0.03,
						"The original inherited scale is rejected as a distorted head.")
					var lifted := bolt.transform
					lifted.origin.y += 0.002 / rotor.scale.y
					var lift := paddle_fastener_facts(bolt.mesh, paddle_pose * lifted, strap_pose)
					verify(lift.seated_points < lift.cap_points and lift.largest_gap > 0.0019,
						"A lifted head cannot pass the full-face seat test.")
					if cached_mesh == null:
						cached_mesh = bolt.mesh
						cached_finish = bolt.material_override
						check_closed_asset_mesh(cached_mesh, 0.0000042, 0.0000046)
					verify(bolt.mesh == cached_mesh and bolt.material_override == cached_finish,
						"Both straps and every wheel size reuse the same head mesh and worked finish.")
					bolt_count += 1
					observations.append({"shared_profile": shared_profile, "axis": axis, "tiles": tiles,
						"radius_min_metres": facts.minimum_radius, "radius_max_metres": facts.maximum_radius,
						"height_metres": facts.height, "full_face_seated": facts.seated_points == facts.cap_points})
				verify(bolt_count == 2 and view.state == before and view.model == null
					and view.actor_world == null and view.request_sequence == 0,
					"The two fitted heads change no native authority, material or player command.")
				machine.free()
				view.free()
				assemblies += 1
	paddle_hardware_checks_complete = not failed and assemblies == 12 and observations.size() == 24
	print(JSON.stringify({"phase": "native paddle hardware", "assemblies": assemblies,
		"heads": observations, "completed": paddle_hardware_checks_complete, "checks": checks,
		"native_world": false, "game_entry": false}))

func paddle_grain_range(node: MeshInstance3D, pose: Transform3D, mesh_override: Mesh = null) -> Vector2:
	var mesh: Mesh = node.mesh if mesh_override == null else mesh_override
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var scale: Vector3 = node.material_override.uv1_scale
	var minimum := INF
	var maximum := 0.0
	for n in range(0, points.size(), 3):
		var direction := normals[n].abs()
		if direction[direction.max_axis_index()] < 0.99999:
			continue
		for pair in [[n, n + 1], [n + 1, n + 2], [n + 2, n]]:
			var difference: Vector2 = (uv[pair[1]] - uv[pair[0]]) * Vector2(scale.x, scale.y)
			if (absf(difference.x) < 0.000001) == (absf(difference.y) < 0.000001):
				continue
			var physical_repeat: float = (pose.basis * (points[pair[1]] - points[pair[0]])).length() / difference.length()
			minimum = minf(minimum, physical_repeat)
			maximum = maxf(maximum, physical_repeat)
	return Vector2(minimum, maximum)

func check_paddle_grain() -> void:
	paddle_grain_checks_complete = false
	var cache: Dictionary = {}
	var observations: Array = []
	var assemblies := 0
	for shared_profile in [false, true]:
		for axis in [0, 2]:
			for tiles in [3, 5, 8]:
				var view: Variant = Shared.new() if shared_profile else Opening.new()
				if shared_profile:
					view.session = PaddleSessionFacts.new()
				view.state = {"context": "paddle-grain-fixture", "options": {"native": true, "physical": true},
					"actors": {"P": {"ready": true}}, "stock": {}, "entities": {}, "parts": {},
					"transmission_parts": {}, "motion": {}, "links": [], "drive_links": [], "engagements": []}
				var before: Dictionary = view.state.duplicate(true)
				var machine := Node3D.new()
				view._assemble_machine(machine, {"kind": "wheel", "axis": axis, "tiles": tiles, "cell": [0, 0], "generation": 1})
				var rows: Array[Dictionary] = []
				hub_mesh_rows(machine, Transform3D.IDENTITY, rows)
				var timber_parts := 0
				var minimum_repeat := INF
				var maximum_repeat := 0.0
				for row in rows:
					var part: MeshInstance3D = row.node
					var role: String = part.get_meta("detail_role", "")
					if role not in ["WheelPaddle", "PaddleRootCleat"]:
						continue
					var size := Vector3(0.14, 0.018, 0.28) if role == "WheelPaddle" else Vector3(0.04, 0.06, 0.10)
					var original := Visuals.box_mesh(size)
					var arrays := part.mesh.surface_get_arrays(0)
					var old_arrays := original.surface_get_arrays(0)
					verify(arrays[Mesh.ARRAY_VERTEX] == old_arrays[Mesh.ARRAY_VERTEX]
						and arrays[Mesh.ARRAY_NORMAL] == old_arrays[Mesh.ARRAY_NORMAL]
						and arrays[Mesh.ARRAY_TANGENT] == old_arrays[Mesh.ARRAY_TANGENT],
						"Timber UV preparation preserves every original vertex, normal and tangent exactly.")
					var measured := paddle_grain_range(part, row.pose)
					minimum_repeat = minf(minimum_repeat, measured.x)
					maximum_repeat = maxf(maximum_repeat, measured.y)
					verify(absf(measured.x - 0.6) < 0.00001 and absf(measured.y - 0.6) < 0.00001,
						"Actual transformed broad-face edges keep the chosen 0.6 m repeat in both texture directions.")
					var key := [role, tiles]
					if not cache.has(key):
						cache[key] = part.mesh
						var limits := Vector2(0.00065, 0.00071) if role == "WheelPaddle" else Vector2(0.00021, 0.000241)
						check_closed_asset_mesh(part.mesh, limits.x, limits.y)
						var old_repeat := paddle_grain_range(part, row.pose, original)
						verify(old_repeat.y > 2.0 and old_repeat.x > 0.7,
							"The original uncorrected coordinates still fail the same physical-repeat measurement.")
						for angle in [0.0, 0.83, 2.2]:
							var moved: Transform3D = Transform3D(Basis(Vector3.UP, angle), Vector3(4, 2, -7)) * row.pose
							var rotated := paddle_grain_range(part, moved)
							verify(rotated.is_equal_approx(measured), "Rigid rotation and translation leave local grain attached to the board.")
					verify(part.mesh == cache[key] and part.material_override == PaddleArt.finish
						and not part.material_override.uv1_triplanar,
						"Equal diameters reuse the exact mesh and unchanged board-local timber material in both views.")
					timber_parts += 1
				verify(timber_parts == 24 and view.state == before and view.model == null and view.actor_world == null
					and view.request_sequence == 0 and not view.is_inside_tree(),
					"All twelve blades and cleats remain passive and change no native authority, observation or request.")
				observations.append({"shared_profile": shared_profile, "axis": axis, "tiles": tiles,
					"timber_parts": timber_parts, "minimum_repeat_metres": minimum_repeat, "maximum_repeat_metres": maximum_repeat})
				machine.free()
				view.free()
				assemblies += 1
	verify(cache.size() == 6 and PaddleArt.timber_mesh(Vector3(0.14, 0.018, 0.28)) == Visuals.box_mesh(Vector3(0.14, 0.018, 0.28)),
		"Six diameter/role variants are cached while the nonnative default retains its original mesh.")
	paddle_grain_checks_complete = not failed and assemblies == 12
	print(JSON.stringify({"phase": "native paddle grain", "assemblies": observations, "cached_timber_meshes": cache.size(),
		"completed": paddle_grain_checks_complete, "checks": checks, "native_world": false, "game_entry": false}))

func span_shell_closed(mesh: Mesh) -> bool:
	var edges: Dictionary = {}
	var neighbours: Dictionary = {}
	var faces := mesh.get_faces()
	for n in range(0, faces.size(), 3):
		for pair in [[faces[n], faces[n + 1]], [faces[n + 1], faces[n + 2]], [faces[n + 2], faces[n]]]:
			var a := vertex_key(pair[0])
			var b := vertex_key(pair[1])
			var key := a + "/" + b if a < b else b + "/" + a
			edges[key] = int(edges.get(key, 0)) + 1
			if not neighbours.has(a):
				neighbours[a] = []
			if not neighbours.has(b):
				neighbours[b] = []
			neighbours[a].append(b)
			neighbours[b].append(a)
	if neighbours.is_empty() or edges.values().any(func(count): return count != 2):
		return false
	var pending: Array = [neighbours.keys()[0]]
	var seen: Dictionary = {}
	while not pending.is_empty():
		var key: String = pending.pop_back()
		if seen.has(key):
			continue
		seen[key] = true
		pending.append_array(neighbours[key])
	return seen.size() == neighbours.size()

func span_ray_hits(mesh: Mesh, pose: Transform3D, from: Vector3, to: Vector3) -> int:
	var hits: Array[Vector3] = []
	var faces := mesh.get_faces()
	for n in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to,
			pose * faces[n], pose * faces[n + 1], pose * faces[n + 2])
		if typeof(hit) != TYPE_VECTOR3:
			continue
		if not hits.any(func(previous): return previous.distance_to(hit) < 0.00001):
			hits.append(hit)
	return hits.size()

func span_return_clearance(mesh: Mesh, distance: float) -> float:
	var minimum := INF
	var centre := Vector2(distance / 2.0, 0)
	var faces := mesh.get_faces()
	for n in range(0, faces.size(), 3):
		if minf(faces[n].x, minf(faces[n + 1].x, faces[n + 2].x)) < centre.x - 0.000001:
			continue
		minimum = minf(minimum, point_triangle_distance(centre, Vector2(faces[n].x, faces[n].y),
			Vector2(faces[n + 1].x, faces[n + 1].y), Vector2(faces[n + 2].x, faces[n + 2].y)))
	return minimum

func span_pulley_fits(pulley: MeshInstance3D, return_radius: float) -> bool:
	var radial_maximum := 0.0
	for point in pulley.mesh.get_faces():
		var actual: Vector3 = pulley.transform * point
		radial_maximum = maxf(radial_maximum, Vector2(actual.x, actual.z).length())
	return radial_maximum + 0.001 < return_radius

func resource_span(parent: Node3D, distance: float = Geometry.PITCH * 2.0) -> void:
	TransmissionAssets.belt_loop(parent, distance, 0)
	for side in [-1.0, 1.0]:
		var shaft := Node3D.new()
		shaft.position.x = side * distance / 2.0
		shaft.basis = Presenter.axis_basis(2)
		parent.add_child(shaft)
		TransmissionAssets.shaft(shaft, Geometry.PITCH, Color("a6b4af"))
		TransmissionAssets.belt_pulley(shaft)

func check_span_belt_art() -> void:
	span_belt_checks_complete = false
	var default_mesh := ConveyorArt.loop_mesh()
	check_closed_asset_mesh(default_mesh, 0.0213, 0.0218)
	verify(default_mesh.get_aabb().position.is_equal_approx(Vector3(-0.66, -0.09, -0.32))
		and default_mesh.get_aabb().end.is_equal_approx(Vector3(0.66, 0.09, 0.32)),
		"The default conveyor keeps its original complete geometry when parameterized.")
	var pulley_cache: Mesh
	var loop_cache: Dictionary = {}
	var observations: Array = []
	var minimum_frame_contact := INF
	var displaced_frame_controls := 0
	for travel_axis in [0, 2]:
		for tiles in [1, 2, 7, 19]:
			var distance: float = tiles * Geometry.PITCH
			var anchor := Node3D.new()
			var loop := TransmissionAssets.belt_loop(anchor, distance, travel_axis)
			verify(loop != null and loop.get_script() == null and loop.material_override == ConveyorArt.material()
				and ConveyorArt.source_status == "ready", "A passive span uses the complete qualified rubber set.")
			if loop == null:
				anchor.free()
				return
			var frame_parts := 0
			for child in loop.get_children():
				if child is MeshInstance3D and child.has_meta("span_frame_role"):
					frame_parts += 1
					var frame_box: AABB = child.transform * child.mesh.get_aabb()
					var inner_side := minf(absf(frame_box.position.z), absf(frame_box.end.z))
					var outer_side := maxf(absf(frame_box.position.z), absf(frame_box.end.z))
					verify(inner_side > TransmissionAssets.SPAN_HALF_WIDTH + 0.03
						and outer_side < TransmissionAssets.SPAN_HALF_WIDTH + 0.10
						and frame_box.position.y > -TransmissionAssets.SPAN_OUTER_RADIUS
						and frame_box.end.y < TransmissionAssets.SPAN_OUTER_RADIUS
						and frame_box.position.x > -distance / 2.0 - TransmissionAssets.SPAN_OUTER_RADIUS
						and frame_box.end.x < distance / 2.0 + TransmissionAssets.SPAN_OUTER_RADIUS,
						"Every fixed frame facet stays outside the rubber and cargo lane but inside the admitted span envelope.")
					verify(child.get_script() == null and child.get_child_count() == 0
						and not child is CollisionObject3D,
						"The belt frame adds no controller or collision authority.")
			verify(frame_parts == 6, "A span has exactly two rigid side rails and four open shaft seats.")
			for side in [-1.0, 1.0]:
				var rail: MeshInstance3D = loop.get_node("SpanFrameRailN" if side < 0 else "SpanFrameRailP")
				verify(span_ray_hits(rail.mesh, rail.transform,
					Vector3(0, -0.1, side * 0.535), Vector3(0, 0.1, side * 0.535)) == 4
					and span_ray_hits(rail.mesh, rail.transform,
					Vector3(0, -0.1, side * 0.495), Vector3(0, 0.1, side * 0.495)) == 2,
					"Each closed side channel has two open-side flanges and one continuous inward web, not a solid bar.")
				for end in [-1.0, 1.0]:
					var seat: MeshInstance3D = loop.get_node("SpanFrameSeat" + ("N" if end < 0 else "P") + ("N" if side < 0 else "P"))
					# Sample inside the channel's bevelled end cap, still within
					# the bored seat surrounding this confirmed shaft centre.
					var from := Vector3(end * (distance / 2.0 - 0.01), -0.2, side * 0.515)
					var overlap := press_input_overlap(rail, seat, from, from + Vector3.UP * 0.4)
					minimum_frame_contact = minf(minimum_frame_contact, overlap)
					verify(overlap > 0.005 and seat.mesh == loop.get_node("SpanFrameSeatNN").mesh,
						"Each reusable bored shaft seat has measured solid contact with its fixed side rail.")
					if tiles == 1 and travel_axis == 0 and side < 0 and end < 0:
						var original_rail := rail.position
						rail.position.z += side * 0.15
						verify(press_input_overlap(rail, seat, from, from + Vector3.UP * 0.4) <= 0,
							"A displaced side rail fails the same raw shaft-seat contact predicate.")
						rail.position = original_rail
						displaced_frame_controls += 1
			if tiles == 1 and travel_axis == 0:
				check_closed_asset_mesh(loop.get_node("SpanFrameRailN").mesh, 0.0025, 0.004)
				check_closed_asset_mesh(loop.get_node("SpanFrameSeatNN").mesh, 0.0005, 0.0008)
			# A rubber shell's volume is its stadium perimeter times the radial
			# section. These bounds allow bevel/facet loss, not a filled loop.
			var volume := (2.0 * distance * 0.045 + PI * (0.1425 * 0.1425 - 0.0975 * 0.0975)) * (Geometry.PITCH * 0.55)
			if not loop_cache.has(tiles):
				check_closed_asset_mesh(loop.mesh, volume * 0.98, volume * 1.001)
				verify(span_shell_closed(loop.mesh), "The belt is one connected closed shell, including both returns.")
				loop_cache[tiles] = loop.mesh
			verify(loop.mesh == loop_cache[tiles], "Compatible X and Z spans reuse their physical mesh.")
			var bounds: AABB = loop.transform * loop.mesh.get_aabb()
			verify(absf(bounds.position[travel_axis] + distance / 2.0 + 0.1425) < 0.00001
				and absf(bounds.end[travel_axis] - distance / 2.0 - 0.1425) < 0.00001
				and absf(bounds.size[2 if travel_axis == 0 else 0] - Geometry.PITCH * 0.55) < 0.00001,
				"Both horizontal orientations preserve the existing strip width and add only the intended end returns.")
			var levels := hub_loop_planes(loop)
			verify(levels.size() == 4 and absf(levels[0] + 0.1425) < 0.000001
				and absf(levels[1] + 0.0975) < 0.000001 and absf(levels[2] - 0.0975) < 0.000001
				and absf(levels[3] - 0.1425) < 0.000001, "All four original flat-run surface heights remain exact.")
			for side in [-1.0, 1.0]:
				var from := Vector3(0, -1, 0)
				from[travel_axis] = side * (distance / 2.0 + 0.05)
				verify(span_ray_hits(loop.mesh, loop.transform, from, from + Vector3.UP * 2.0) == 4,
					"Each return has inner and outer rubber on both sides of its empty interior.")
			var arrays := loop.mesh.surface_get_arrays(0)
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var maximum_u := 0.0
			for coordinate in uv:
				maximum_u = maxf(maximum_u, coordinate.x)
			var physical_repeat: float = (2.0 * distance + TAU * 0.1425) / maximum_u
			var seam: Dictionary = {}
			for n in range(vertices.size()):
				if uv[n].x > 0.000001 and uv[n].x < maximum_u - 0.000001:
					continue
				var key := vertex_key(vertices[n])
				if not seam.has(key):
					seam[key] = [INF, -INF]
				seam[key][0] = minf(seam[key][0], uv[n].x)
				seam[key][1] = maxf(seam[key][1], uv[n].x)
			verify(physical_repeat > 0.66 and physical_repeat < 0.84 and maximum_u == roundf(maximum_u)
				and seam.size() == 8 and seam.values().all(func(row): return absf(row[1] - row[0] - maximum_u) < 0.000001),
				"The source rubber has a physical repeat near 0.75 m and closes each section corner at a whole repeat.")
			var shaft := Node3D.new()
			TransmissionAssets.shaft(shaft, Geometry.PITCH, Color.WHITE)
			var pulley := TransmissionAssets.belt_pulley(shaft)
			var seat: MeshInstance3D = loop.get_node("SpanFrameSeatNN")
			verify(absf(seat.position.z) - 0.020 > pulley.mesh.get_aabb().end.y
				and absf(seat.position.z) + 0.020 < Geometry.PITCH / 2.0,
				"The open seat sits on actual shaft stock beyond the pulley face, not at an invented shaft tip.")
			if pulley_cache == null:
				check_closed_asset_mesh(pulley.mesh, 0.017, 0.025)
				pulley_cache = pulley.mesh
			verify(pulley.mesh == pulley_cache and TransmissionAssets.belt_pulley(shaft) == pulley,
				"The fitted pulley reuses one cached mesh and mounts only once per shaft.")
			var inner_return := span_return_clearance(loop.mesh, distance)
			verify(span_pulley_fits(pulley, inner_return) and inner_return > 0.097,
				"Every actual return facet clears the complete pulley envelope by more than one millimetre.")
			verify(collector_tooling_bore(pulley.mesh) > 0.0388 and absf(pulley.mesh.get_aabb().position.y + 0.49) < 0.000001
				and absf(pulley.mesh.get_aabb().end.y - 0.49) < 0.000001,
				"The complete open bore clears the actual shaft and key, and its axial ends stay between the existing collars.")
			pulley.position.x += 0.02
			verify(not span_pulley_fits(pulley, inner_return), "A displaced pulley fails the same full-envelope clearance predicate.")
			pulley.position.x -= 0.02
			observations.append({"travel_axis": travel_axis, "tiles": tiles, "inner_return_radius": inner_return,
				"rubber_repeat_metres": physical_repeat})
			shaft.free()
			anchor.free()
	var broken := SurfaceTool.new()
	broken.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := default_mesh.get_faces()
	for n in range(3, faces.size()):
		broken.add_vertex(faces[n])
	verify(not span_shell_closed(broken.commit()), "Removing one real facet opens the shell and fails closure.")
	var old_strips := SurfaceTool.new()
	old_strips.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		old_strips.append_from(Visuals.box_mesh(Vector3(Geometry.PITCH, 0.045, Geometry.PITCH * 0.55)), 0,
			Transform3D(Basis.IDENTITY, Vector3(0, side * 0.12, 0)))
	verify(not span_shell_closed(old_strips.commit()), "Two individually closed original strips are rejected as disconnected rubber.")
	verify(ConveyorArt.loop_mesh() == default_mesh and loop_cache.size() == 4,
		"Native span variants never replace the original conveyor's cached mesh.")
	span_belt_checks_complete = not failed and observations.size() == 8 and displaced_frame_controls == 1
	print(JSON.stringify({"phase": "closed native belt artwork", "assemblies": observations,
		"completed": span_belt_checks_complete, "checks": checks,
		"minimum_frame_contact_metres": minimum_frame_contact,
		"displaced_frame_controls": displaced_frame_controls, "native_world": false, "game_entry": false}))

class PaddleSessionFacts extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

class HubShaftFacts extends RefCounted:
	var state: Dictionary = {}
	func _can_present_confirmed_motion() -> bool:
		return true

func hub_mesh_rows(node: Node3D, parent_pose: Transform3D, rows: Array[Dictionary]) -> void:
	var pose := parent_pose * node.transform
	if node is MeshInstance3D:
		rows.append({"node": node, "pose": pose})
	for child in node.get_children():
		if child is Node3D:
			hub_mesh_rows(child, pose, rows)

func hub_loop_planes(loop: MeshInstance3D) -> Array[float]:
	var arrays := loop.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var levels: Array[float] = []
	for n in range(vertices.size()):
		if absf(normals[n].y) < 0.999999:
			continue
		var height: float = (loop.transform * vertices[n]).y
		var seen := false
		for level in levels:
			seen = seen or absf(level - height) < 0.000001
		if not seen:
			levels.append(height)
	levels.sort()
	return levels

func hub_empty_window(mesh: Mesh, pose: Transform3D, planes: Array[float]) -> bool:
	var bounds: AABB = pose * mesh.get_aabb()
	if bounds.position.z > 0.32 or bounds.end.z < -0.32:
		return true
	return bounds.position.x > -0.57 and bounds.end.x < 0.57 \
		and bounds.position.y > planes[1] and bounds.end.y < planes[2]

func hub_loop_separation(mesh: Mesh, pose: Transform3D, loop: MeshInstance3D) -> float:
	var bounds: AABB = pose * mesh.get_aabb()
	var faces := loop.mesh.get_faces()
	var minimum := INF
	for n in range(0, faces.size(), 3):
		var a: Vector3 = loop.transform * faces[n]
		var b: Vector3 = loop.transform * faces[n + 1]
		var c: Vector3 = loop.transform * faces[n + 2]
		var low := a.min(b).min(c)
		var high := a.max(b).max(c)
		var gap := maxf(maxf(maxf(bounds.position.x - high.x, low.x - bounds.end.x),
			maxf(bounds.position.y - high.y, low.y - bounds.end.y)), maxf(bounds.position.z - high.z, low.z - bounds.end.z))
		minimum = minf(minimum, gap)
	return minimum

func hub_vertical_hits(node: MeshInstance3D, probe: Vector2) -> Array[float]:
	# Use a longer probe, then retain exact hit heights. The pinned API's
	# absolute determinant guard can discard small faces on short segments.
	var from := Vector3(probe.x, -0.6, probe.y)
	var to := Vector3(probe.x, 1.6, probe.y)
	var faces := node.mesh.get_faces()
	var hits: Array[float] = []
	for n in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to,
			node.transform * faces[n], node.transform * faces[n + 1], node.transform * faces[n + 2])
		if hit == null:
			continue
		var seen := false
		for height in hits:
			seen = seen or absf(height - hit.y) < 0.000001
		if not seen:
			hits.append(hit.y)
	hits.sort()
	return hits

func hub_joint_overlap(housing: MeshInstance3D, support: MeshInstance3D, probe: Vector2) -> Dictionary:
	var a := hub_vertical_hits(housing, probe)
	var b := hub_vertical_hits(support, probe)
	var valid := not a.is_empty() and not b.is_empty() and a.size() % 2 == 0 and b.size() % 2 == 0
	var overlap := 0.0
	if valid:
		for first in range(0, a.size(), 2):
			for second in range(0, b.size(), 2):
				overlap = maxf(overlap, minf(a[first + 1], b[second + 1]) - maxf(a[first], b[second]))
	return {"valid": valid, "housing_hits": a, "support_hits": b, "solid_overlap": overlap}

func hub_short_probe_determinant(housing: MeshInstance3D) -> float:
	var rel: Vector3 = housing.basis.inverse() * Vector3(0, 0.01, 0)
	var faces := housing.mesh.get_faces()
	var maximum := 0.0
	for n in range(0, faces.size(), 3):
		maximum = maxf(maximum, absf((faces[n + 1] - faces[n]).dot(rel.cross(faces[n + 2] - faces[n]))))
	return maximum

func check_conveyor_hub() -> void:
	var cache: Dictionary = {}
	var assemblies := 0
	var shaft_cases := 0
	var minimum_loop_gap := INF
	var minimum_shaft_gap := INF
	var controls := 0
	var shaft_faces := 0
	var joint_probes := 0
	for shared_profile in [false, true]:
		for cell in [[0, 0], [2, -1]]:
			for axis in range(3):
				var view: Variant = Shared.new() if shared_profile else Opening.new()
				view.machine_root = Node3D.new()
				view.item_root = Node3D.new()
				view.add_child(view.machine_root)
				view.add_child(view.item_root)
				view.state = {"context": "conveyor-hub-fixture", "options": {"native": true},
					"actors": {}, "transmission_parts": {}, "motion": {}, "stock": {"belt": 1},
					"entities": {"fixture": {"kind": "belt", "cell": cell, "center": [cell[0] * 4, 0, cell[1] * 4],
						"axis": axis, "generation": 1}}, "links": [], "drive_links": [], "engagements": []}
				var before: Dictionary = view.state.duplicate(true)
				view._rebuild_machines()
				view._redraw_items()
				var machine: Node3D = view.machine_root.get_child(0)
				var journal: MeshInstance3D = machine.get_node("DriveStub")
				var expected := Presenter.world_center(view.state.entities.fixture.center)
				var direction: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis]
				verify(machine.get_meta("conveyor_hub", false)
					and (machine.transform * journal.transform).origin.is_equal_approx(expected)
					and journal.basis.y.dot(direction) > 0.99999 and journal.mesh is CylinderMesh,
					"The actual view keeps the public journal on the native hub point and positive projected axis, including translated cells.")
				var loop: MeshInstance3D = machine.get_node("ConveyorLoop")
				verify(loop.mesh == ConveyorArt.loop_mesh() and loop.material_override == ConveyorArt.material(),
					"The actual original rubber geometry and prepared material stay exact.")
				var planes := hub_loop_planes(loop)
				verify(planes.size() == 4 and is_equal_approx(planes[1], 0.387) and is_equal_approx(planes[2], 0.543),
					"The empty working window is measured from actual inner belt facets, with distinct outer surfaces.")
				var parts: Array[MeshInstance3D] = []
				var rollers: Array[MeshInstance3D] = []
				var side_beams: Array[MeshInstance3D] = []
				var picks := 0
				for child in machine.get_children():
					if child is MeshInstance3D:
						if child.has_meta("conveyor_hub_role"):
							parts.append(child)
						if child.get_meta("detail_role", "") == "ConveyorRoller":
							rollers.append(child)
						if child.get_meta("conveyor_frame_role", "") == "SideBeam":
							side_beams.append(child)
					elif child is StaticBody3D:
						picks += 1
						verify(child.collision_layer == Geometry.PICK_LAYER and child.collision_mask == 0
							and child.get_child_count() == 1 and child.get_child(0).shape.size == Vector3(1.45, 1.65, 1.45)
							and child.get_child(0).position.is_equal_approx(Vector3(0, 0.8, 0)),
							"The entity pick identity, dimensions, centre and masks remain unchanged.")
				verify(parts.size() == 10 and rollers.size() == 2 and side_beams.size() == 2 and picks == 1,
					"The compact journal and open housing share eight supported carrier pieces within the original machine.")
				var items: Array[Dictionary] = []
				hub_mesh_rows(view.item_root, Transform3D.IDENTITY, items)
				verify(not items.is_empty(), "The ordinary item redraw supplies the actual retained billet artwork.")
				for part in parts:
					var role: String = part.get_meta("conveyor_hub_role")
					var key := role + ("Y" if axis == 1 and role in ["HubHousing", "HubJournal"] else "")
					if role == "HubFork":
						key += "N" if part.mesh.get_aabb().position.x < 0 else "P"
					verify(part.get_script() == null and part.get_child_count() == 0 and part.scale.is_equal_approx(Vector3.ONE),
						"Every hub piece is fixed plain geometry without a controller, collider or scale-stretched detail.")
					check_bounds(part, Transform3D.IDENTITY)
					if not cache.has(key):
						var volumes: Array = {"HubCarrierRail": [0.00055, 0.00070], "HubMountCleat": [0.000015, 0.000022],
							"HubBridge": [0.000030, 0.000045], "HubPedestal": [0.0000045, 0.0000065],
							"HubForkN": [0.000007, 0.000010], "HubForkP": [0.000007, 0.000010],
							"HubHousing": [0.00007, 0.000085], "HubHousingY": [0.00035, 0.00042],
							"HubJournal": [0.00029, 0.00030], "HubJournalY": [0.00019, 0.00020]}[key]
						check_closed_asset_mesh(part.mesh, volumes[0], volumes[1])
						cache[key] = [part.mesh, part.material_override]
					verify(part.mesh == cache[key][0] and part.material_override == cache[key][1],
						"All cells and both view classes reuse each compatible fitted mesh and finish.")
					var gap := hub_loop_separation(part.mesh, part.transform, loop)
					minimum_loop_gap = minf(minimum_loop_gap, gap)
					verify(hub_empty_window(part.mesh, part.transform, planes) and gap > 0.0005,
						"Every complete new mesh stays in the measured empty window or outside the belt width and clears every actual belt facet.")
					for roller in rollers:
						verify(frame_shaft_clearance(part.mesh, part.transform, roller) > 0.001,
							"The fitted hub and its supports also clear the unchanged actual roller meshes.")
					var box: AABB = machine.transform * part.transform * part.mesh.get_aabb()
					for item in items:
						var item_box: AABB = item.pose * item.node.mesh.get_aabb()
						verify(box.end.y < item_box.position.y or box.position.z > item_box.end.z or box.end.z < item_box.position.z,
							"The complete new hub pieces conservatively clear every actual carried-work mesh.")
					if role == "HubMountCleat":
						var beam: MeshInstance3D = side_beams[0] if signf(side_beams[0].position.z) == signf(part.position.z) else side_beams[1]
						verify(feed_ray_blocked(beam, Transform3D.IDENTITY,
							Vector3(part.position.x, 0.38, part.position.z), Vector3(part.position.x, 0.39, part.position.z))
							and box.position.y < 0.385 and (part.transform * part.mesh.get_aabb()).end.y > 0.415,
							"The carrier cleat meets the actual formed beam and overlaps its rail joint, rather than hovering between them.")
				var housing: MeshInstance3D = machine.get_node("HubHousing")
				for x in ([-0.052, 0.052] if axis == 1 else [0.002]):
					var support: MeshInstance3D = machine.get_node(("HubForkN" if x < 0 else "HubForkP") if axis == 1 else "HubPedestal")
					var contact := hub_joint_overlap(housing, support, Vector2(x, 0.003))
					var old_x := signf(x) * 0.05 if axis == 1 else 0.0
					var old_hit := feed_ray_blocked(housing, Transform3D.IDENTITY,
						Vector3(old_x, 0.455 if axis != 1 else 0.465, 0), Vector3(old_x, 0.465 if axis != 1 else 0.475, 0))
					var determinant := hub_short_probe_determinant(housing)
					print(JSON.stringify({"phase": "hub joint", "shared": shared_profile, "cell": cell, "axis": axis,
						"probe_xz": Vector2(x, 0.003), "contact": contact, "old_short_probe_hit": old_hit,
						"maximum_short_probe_determinant": determinant}))
					verify(contact.valid and contact.solid_overlap > 0.0001,
						"Actual closed housing and support intervals overlap at the designed fixed joint.")
					verify(not old_hit and determinant < 0.00001,
						"The original short probe is rejected by the pinned absolute determinant guard, not evidence of an absent joint.")
					if not shared_profile and cell == [0, 0] and axis != 2:
						var rest := support.position
						support.position.y -= 0.01
						verify(hub_joint_overlap(housing, support, Vector2(x, 0.003)).solid_overlap == 0,
							"The same interval oracle rejects a support deliberately lowered away from its housing.")
						support.position = rest
						controls += 1
					joint_probes += 1
				if not shared_profile and cell == [0, 0]:
					for half_span in [1, 3]:
						for end in [-1, 0, 1]:
							var center: Array = view.state.entities.fixture.center.duplicate()
							center[axis] += end * half_span
							var host := HubShaftFacts.new()
							host.state = {"context": "hub-shaft-alternative", "options": {"native": true}, "entities": {},
								"transmission_parts": {"shaft": {"kind": "shaft", "center": center, "axis": axis, "half_span": half_span, "generation": 1}},
								"motion": {"shaft": {"state": "rotating", "numerator": -1, "denominator": 1}}, "engagements": []}
							var original: Dictionary = host.state.duplicate(true)
							var presenter := Presenter.new()
							presenter.configure(host)
							presenter.advance_visual_motion(0.1)
							var shaft: Node3D = presenter.get_child(0)
							var core: MeshInstance3D = shaft.get_node("Shaft")
							var length: float = float(half_span) * 0.825
							verify(core.mesh is CylinderMesh and is_equal_approx(core.mesh.height, length)
								and is_equal_approx(core.mesh.top_radius, 0.03)
								and shaft.position.is_equal_approx(Presenter.world_center(center))
								and shaft.basis.y.dot(direction) > 0.99999,
								"The actual presenter retains the prescribed centre, axis, length and declared shaft art radius.")
							var pick: StaticBody3D = shaft.get_node("Pick")
							verify(pick.collision_layer == 4 and pick.collision_mask == 0
								and is_equal_approx(pick.get_child(0).shape.radius, 0.08)
								and is_equal_approx(pick.get_child(0).shape.height, length),
								"Thinner shaft art does not shrink or move its real selection proxy.")
							var meshes: Array[Dictionary] = []
							hub_mesh_rows(shaft, Transform3D.IDENTITY, meshes)
							var inverse := Transform3D(Presenter.axis_basis(axis), expected).affine_inverse()
							var maximum_radius := 0.0
							var low := INF
							var high := -INF
							for row in meshes:
								var pose: Transform3D = inverse * row.pose
								for vertex in row.node.mesh.get_faces():
									var point: Vector3 = pose * vertex
									maximum_radius = maxf(maximum_radius, Vector2(point.x, point.z).length())
									low = minf(low, point.y)
									high = maxf(high, point.y)
								shaft_faces += row.node.mesh.get_faces().size() / 3
							verify(maximum_radius < 0.038 and meshes.size() == 6,
								"Actual shaft, collars, end keys and the moved keyway all stay inside the declared rotating envelope.")
							for part in parts:
								if part == journal:
									continue
								var pose: Transform3D = inverse * machine.transform * part.transform
								var bounds: AABB = pose * part.mesh.get_aabb()
								if bounds.position.y > high or bounds.end.y < low:
									continue
								var band := frame_mesh_band(part.mesh, pose, low, high)
								var gap: float = band.minimum - maximum_radius
								minimum_shaft_gap = minf(minimum_shaft_gap, gap)
								verify(not frame_axis_occupied(part.mesh, pose, low, high, maximum_radius) and gap > 0.0005,
									"A conservative full-turn envelope of each actual shaft alternative clears all fixed local hub furniture.")
							verify(host.state == original and is_equal_approx(presenter.visual_angle("shaft"), -0.08),
								"The existing signed cosmetic cache changes no prescribed shaft or native facts.")
							presenter.free()
							shaft_cases += 1
					var old := CylinderMesh.new()
					old.top_radius = 0.085
					old.bottom_radius = 0.085
					old.height = 0.9 if axis == 1 else 1.35
					verify(not hub_empty_window(old, journal.transform, planes)
						and hub_loop_separation(old, journal.transform, loop) < 0,
						"The original complete decorative bar fails the same measured empty-window and actual-facet separation requirements.")
					controls += 1
					if axis == 0:
						var band := frame_mesh_band(housing.mesh, Transform3D.IDENTITY, -0.05, 0.05)
						verify(band.minimum - 0.045 < 0, "The old wide shaft core cannot pass the new actual bore-clearance discriminator.")
						var contained := BoxMesh.new()
						contained.size = Vector3.ONE * 0.003
						verify(not hub_empty_window(contained, Transform3D(Basis.IDENTITY, Vector3(0, 0.549, 0)), planes),
							"A tiny solid contained inside the rubber cannot pass by avoiding its boundary triangles.")
						var original_position := journal.position
						journal.position.x += 0.01
						verify(not (machine.transform * journal.transform).origin.is_equal_approx(expected),
							"A displaced visible journal fails the confirmed native-point discriminator.")
						journal.position = original_position
						controls += 3
				verify(view.state == before and view.model == null and view.actor_world == null and view.request_sequence == 0,
					"The new art changes no material ownership, topology, request, actor or native authority.")
				assemblies += 1
				view.free()
	for shared_profile in [false, true]:
		var view: Variant = Shared.new() if shared_profile else Opening.new()
		view.state = {"options": {"native": false}}
		var machine := Node3D.new()
		view.add_child(machine)
		view._assemble_machine(machine, {"kind": "belt", "axis": 1})
		var journal: MeshInstance3D = machine.get_node("DriveStub")
		verify(not machine.get_meta("conveyor_hub", false) and is_equal_approx(journal.mesh.top_radius, 0.085)
			and is_equal_approx(journal.mesh.height, 0.18) and journal.position.is_equal_approx(Vector3(0, 0.35, 0.55)),
			"Both nonnative views retain their exact historical decorative stub.")
		view.free()
	print(JSON.stringify({"phase": "conveyor hub", "assemblies": assemblies, "unique_mesh_roles": cache.size(),
		"shaft_alternatives": shaft_cases, "actual_shaft_triangles_read": shaft_faces,
		"retained_joint_probes": joint_probes,
		"minimum_belt_facet_separation_metres": minimum_loop_gap, "minimum_local_shaft_clearance_metres": minimum_shaft_gap,
		"altered_geometry_controls": controls, "observations": "invented", "native_gameplay": "not_run",
		"rendered_quality": "not_assessed", "shaft_scope": "Local hub furniture only; not a claim of general through-machine routing."}))

func frame_mesh_band(mesh: Mesh, pose: Transform3D, low: float, high: float) -> Dictionary:
	var faces := mesh.get_faces()
	var minimum := INF
	var maximum := 0.0
	for n in range(0, faces.size(), 3):
		var points: Array[Vector3] = [pose * faces[n], pose * faces[n + 1], pose * faces[n + 2]]
		points = crown_clip_y(crown_clip_y(points, low, true), high, false)
		for corner in range(1, points.size() - 1):
			var a := Vector2(points[0].x, points[0].z)
			var b := Vector2(points[corner].x, points[corner].z)
			var c := Vector2(points[corner + 1].x, points[corner + 1].z)
			minimum = minf(minimum, triangle_radius(a, b, c))
			maximum = maxf(maximum, maxf(a.length(), maxf(b.length(), c.length())))
	return {"minimum": minimum, "maximum": maximum}

func frame_axis_occupied(mesh: Mesh, pose: Transform3D, low: float, high: float, radius: float) -> bool:
	# A surrounding solid can have all its side facets outside the cylinder.
	# Pair full closed-mesh crossings to reject that containment as well.
	# The off-centre ray stays strictly inside the tested radial envelope and
	# avoids the primitive cap's shared centre vertex. It changes no game pose.
	var bounds: AABB = pose * mesh.get_aabb()
	var from := Vector3(radius * 0.137, bounds.position.y - 1, radius * 0.219)
	var to := Vector3(from.x, bounds.end.y + 1, from.z)
	var faces := mesh.get_faces()
	var hits: Array[float] = []
	for n in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, pose * faces[n], pose * faces[n + 1], pose * faces[n + 2])
		if hit == null:
			continue
		var duplicate := false
		for height in hits:
			duplicate = duplicate or absf(height - hit.y) < 0.000001
		if not duplicate:
			hits.append(hit.y)
	hits.sort()
	if hits.size() % 2 != 0:
		return true
	for n in range(0, hits.size(), 2):
		if hits[n] <= high and hits[n + 1] >= low:
			return true
	return false

func frame_shaft_clearance(mesh: Mesh, pose: Transform3D, shaft: MeshInstance3D) -> float:
	var relative: Transform3D = shaft.transform.affine_inverse() * pose
	var fixed_bounds: AABB = relative * mesh.get_aabb()
	var shaft_bounds := shaft.mesh.get_aabb()
	var low := maxf(fixed_bounds.position.y, shaft_bounds.position.y)
	var high := minf(fixed_bounds.end.y, shaft_bounds.end.y)
	if low > high:
		return INF
	var moving := frame_mesh_band(shaft.mesh, Transform3D.IDENTITY, low, high)
	var fixed := frame_mesh_band(mesh, relative, low, high)
	if frame_axis_occupied(mesh, relative, low, high, moving.maximum):
		return -moving.maximum
	return fixed.minimum - moving.maximum

func frame_seat(bolt: MeshInstance3D, seat: MeshInstance3D, lifted: float = 0.0) -> Dictionary:
	var a := MeshInstance3D.new()
	var b := MeshInstance3D.new()
	a.mesh = bolt.mesh
	b.mesh = seat.mesh
	var frame := Transform3D(bolt.basis.inverse(), Vector3.ZERO)
	a.transform = frame * bolt.transform
	b.transform = frame * seat.transform
	var result := foot_seating(a, b, lifted)
	a.free()
	b.free()
	return result

func check_conveyor_frame() -> void:
	var cache: Dictionary = {}
	var assemblies := 0
	var minimum_gap := INF
	var minimum_entry := INF
	var seats := 0
	var controls := 0
	for shared_profile in [false, true]:
		for axis in range(3):
			var view: Variant = Shared.new() if shared_profile else Opening.new()
			view.machine_root = Node3D.new()
			view.add_child(view.machine_root)
			view.state = {"context": "conveyor-frame-fixture", "options": {"native": true},
				"actors": {}, "transmission_parts": {}, "motion": {}, "stock": {"belt": 1},
				"entities": {"fixture": {"kind": "belt", "cell": [0, 0], "axis": axis, "generation": 1}},
				"links": [], "drive_links": [], "engagements": []}
			var before: Dictionary = view.state.duplicate(true)
			view._rebuild_machines()
			var machine: Node3D = view.machine_root.get_child(0)
			verify(machine.get_meta("conveyor_frame", false), "The actual native conveyor mounts its fitted fixed furniture.")
			var rollers: Array[MeshInstance3D] = []
			var parts: Array[MeshInstance3D] = []
			var picks := 0
			var loop: MeshInstance3D = machine.get_node("ConveyorLoop")
			verify(loop.mesh == ConveyorArt.loop_mesh() and loop.material_override == ConveyorArt.material()
				and loop.position.is_equal_approx(Vector3(0, 0.465, 0)),
				"The new furniture preserves the exact original rubber loop, material and mounting height.")
			for child in machine.get_children():
				if child is MeshInstance3D:
					if child.get_meta("detail_role", "") == "ConveyorRoller":
						rollers.append(child)
					if child.has_meta("conveyor_frame_role"):
						parts.append(child)
				elif child is StaticBody3D:
					picks += 1
					verify(child.collision_layer == Geometry.PICK_LAYER and child.collision_mask == 0
						and child.get_child_count() == 1 and child.get_child(0).shape.size == Vector3(1.45, 1.65, 1.45)
						and child.get_child(0).position.is_equal_approx(Vector3(0, 0.8, 0)),
						"The sole entity pick body retains its original size, centre and masks.")
			verify(picks == 1 and rollers.size() == 2 and parts.size() == (34 if axis == 2 else 32),
				"The kit has four complete end frames, eight seated feet and the appropriate rigid guards.")
			for roller in rollers:
				verify(is_equal_approx(absf(roller.position.x), 0.57) and is_equal_approx(roller.position.y, 0.465)
					and roller.position.z == 0 and roller.mesh.get_aabb().position.is_equal_approx(Vector3(-0.077, -0.35, -0.077))
					and roller.mesh.get_aabb().size.is_equal_approx(Vector3(0.154, 0.7, 0.154)),
					"The literal original turned roller envelope and centre remain unchanged.")
			var drive: MeshInstance3D = machine.get_node("DriveStub")
			var compact: bool = machine.get_meta("conveyor_hub", false)
			var journal_height := (0.08 if axis == 1 else 0.12) if compact else (0.9 if axis == 1 else 1.35)
			var journal_art: bool = (drive.mesh is CylinderMesh and is_equal_approx(drive.mesh.top_radius, 0.028)
				and is_equal_approx(drive.mesh.height, journal_height)) if compact else drive.mesh == DriveJournalArt.mesh(journal_height)
			verify(journal_art
				and drive.position.is_equal_approx(Vector3(0, 0.5, 0))
				and absf(drive.basis.y.dot([Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis])) > 0.99999,
				"The native hub point and confirmed axis remain exact, with the declared current journal artwork.")
			var shafts: Array[MeshInstance3D] = [drive]
			shafts.append_array(rollers)
			for part in parts:
				var role: String = part.get_meta("conveyor_frame_role")
				verify(part.get_script() == null and part.get_child_count() == 0 and part.scale.is_equal_approx(Vector3.ONE),
					"Every fixed piece is plain geometry with baked dimensions and no controller or collider.")
				check_bounds(part, Transform3D.IDENTITY)
				if not cache.has(role):
					var volumes: Array = {"FrameCheek": [0.0012, 0.0018], "BearingCup": [0.0023, 0.0028],
						"BearingLiner": [0.00007, 0.00008], "EndCap": [0.00014, 0.00020],
						"CapBolt": [0.000021, 0.000024], "FootBolt": [0.0000043, 0.0000046],
						"SideBeam": [0.0016, 0.0020], "GuardRail": [0.004, 0.006], "GuardHalf": [0.0020, 0.0024]}[role]
					check_closed_asset_mesh(part.mesh, volumes[0], volumes[1])
					cache[role] = [part.mesh, part.material_override]
				verify(part.mesh == cache[role][0] and part.material_override == cache[role][1],
					"Both builders and all drive axes share every compatible mesh and material.")
				var painted := role in ["FrameCheek", "BearingCup", "SideBeam", "GuardRail", "GuardHalf"]
				var material := part.material_override as StandardMaterial3D
				verify(material.albedo_color == (Color("538e88") if painted else Color("a6b4af"))
					and is_equal_approx(material.metallic, 0.0 if painted else 0.85)
					and material.normal_texture == Opening.ProductionTransmissionFinish.textures[("cast" if painted else "worked") + "_normal"],
					"The actual kit keeps cast coating and exposed worked metal distinct with shared qualified maps.")
				for shaft in shafts:
					var gap := frame_shaft_clearance(part.mesh, part.transform, shaft)
					minimum_gap = minf(minimum_gap, gap)
					verify(gap > 0.001, "Every complete fixed piece conservatively clears the original drive and roller facets.")
				if part.has_meta("frame_seat"):
					var seat: MeshInstance3D = machine.get_node(NodePath(str(part.get_meta("frame_seat"))))
					var contact := frame_seat(part, seat)
					verify(contact.area > 0 and absf(contact.coverage - 1) < 0.0001 and contact.maximum_penetration < 0.00001,
						"Each complete hexagonal lower face sits on its explicit flat seat without penetrating a shoulder.")
					seats += 1
				if role == "BearingLiner":
					var roller: MeshInstance3D = rollers[0] if is_equal_approx(rollers[0].position.x, part.position.x) else rollers[1]
					var local: Transform3D = roller.transform.affine_inverse() * part.transform
					var box: AABB = local * part.mesh.get_aabb()
					var entry := minf(0.35, box.end.y) - maxf(-0.35, box.position.y)
					minimum_entry = minf(minimum_entry, entry)
					verify(entry > 0.008, "Each actual original roller tip enters its fitted open liner instead of stopping short.")
				if controls == 0 and role == "BearingLiner":
					var filled := CylinderMesh.new()
					filled.top_radius = 0.065
					filled.bottom_radius = 0.065
					filled.height = 0.093
					verify(frame_shaft_clearance(filled, part.transform, rollers[0]) < 0,
						"A deliberately filled bearing fails the same finite-shaft clearance oracle.")
					var old_channel := Visuals.box_mesh(Vector3(1.34, 0.08, 0.05))
					verify(frame_shaft_clearance(old_channel, Transform3D(Basis.IDENTITY, Vector3(0, 0.43, 0.36)), rollers[0]) < 0,
						"The original high box channel fails the same actual roller-tip clearance requirement.")
					var enclosing := BoxMesh.new()
					enclosing.size = Vector3.ONE
					verify(frame_shaft_clearance(enclosing, rollers[0].transform, rollers[0]) < 0,
						"A surrounding solid cannot pass merely because its side surfaces are far from the shaft.")
					var foot: MeshInstance3D = machine.get_node("FootBoltNNN")
					var seat: MeshInstance3D = machine.get_node(NodePath(str(foot.get_meta("frame_seat"))))
					verify(frame_seat(foot, seat, 0.001).coverage < 0.99, "A lifted foot bolt fails the same complete-face seating requirement.")
					controls = 4
			verify(view.state == before and view.model == null and view.actor_world == null and view.request_sequence == 0,
				"The fixed furniture changes no projection, material request, physics or native authority.")
			assemblies += 1
			view.free()
	for shared_profile in [false, true]:
		var view: Variant = Shared.new() if shared_profile else Opening.new()
		view.state = {"options": {"native": false}}
		var machine := Node3D.new()
		view.add_child(machine)
		view._assemble_machine(machine, {"kind": "belt"})
		verify(not machine.get_meta("conveyor_frame", false) and count_role(machine, "ConveyorLeg") == 4
			and count_role(machine, "ConveyorChannel") == 2 and count_role(machine, "RollerBearing") == 4,
			"Both nonnative view classes retain their earlier posts, channels and bearing disks.")
		view.free()
	print(JSON.stringify({"phase": "conveyor frame", "assemblies": assemblies, "unique_mesh_roles": cache.size(),
		"minimum_facet_clearance_metres": minimum_gap, "minimum_roller_entry_metres": minimum_entry,
		"complete_bolt_seats": seats, "altered_geometry_controls": controls,
		"observations": "invented", "native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

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
				and head.mesh == DieArt.tool_mesh()
				and head.mesh.get_aabb().size.is_equal_approx(Vector3(0.56, 0.17, 0.55)),
				"The literal original ram, tool envelope and two guide rods define the visual clearance oracle.")
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
					var stand_scale := Vector3(scale_factor, scale_factor if axis_index == 1 else Geometry.ANCHOR_HEIGHT / 0.78, scale_factor)
					verify(bounds.position.is_equal_approx(expected.position * stand_scale) and bounds.size.is_equal_approx(expected.size * stand_scale),
						"Stand bounds retain the original width while reaching the shared axle height.")
					if OS.get_cmdline_user_args().has("--foot-seat-geometry") and not checked_shapes.has(axis_index == 1):
						var volume_scale := pow(scale_factor, 3) * (1.0 if axis_index == 1 else Geometry.ANCHOR_HEIGHT / 0.5)
						check_closed_asset_mesh(child.mesh, (0.014 if axis_index == 1 else 0.010) * volume_scale,
							(0.024 if axis_index == 1 else 0.020) * volume_scale)
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

func wheel_journal_measure(mesh: Mesh, pose: Transform3D) -> Dictionary:
	var radius := 0.0
	var low := INF
	var high := -INF
	for surface in range(mesh.get_surface_count()):
		for vertex in die_faces(mesh, surface):
			var point: Vector3 = pose * vertex
			radius = maxf(radius, Vector2(point.x, point.y).length())
			low = minf(low, point.z)
			high = maxf(high, point.z)
	return {"radius": radius, "low": low, "high": high}

func check_wheel_supports() -> void:
	wheel_support_checks_complete = false
	var samples: Array[Dictionary] = []
	for diameter in [3, 5, 8]:
		for translated in [false, true]:
			samples.append({"tiles": diameter, "cell": [2, -1] if translated else [0, 0], "level": 4 if translated else 0})
	var cached: Dictionary = {}
	var scale_factor := 0.5 / 0.78
	var minimum_gap := INF
	var entries: Array[float] = []
	var assemblies := 0
	var controls := 0
	var rejected_rim_scale := false
	var checked_paddle_joins := 0
	for shared_profile in [false, true]:
		for axis_index in [0, 2]:
			var axis: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis_index]
			for sample: Dictionary in samples:
				var view: Variant = Shared.new() if shared_profile else Opening.new()
				view.machine_root = Node3D.new()
				view.add_child(view.machine_root)
				view.state = {"context": "wheel-support-fixture", "options": {"native": true},
					"actors": {"P": {"ready": true}}, "transmission_parts": {}, "motion": {},
					"entities": {"fixture": {"kind": "wheel", "cell": sample.cell, "level": sample.level,
						"tiles": sample.tiles, "axis": axis_index, "generation": 1}},
					"links": [], "drive_links": [], "engagements": []}
				var before: Dictionary = view.state.duplicate(true)
				view._rebuild_machines()
				var machine: Node3D = view.machine_root.get_child(0)
				var rotor: Node3D = view.wheel_rotor
				var source: MeshInstance3D = rotor.get_node("SourcedTimberRotor")
				var hub: MeshInstance3D = rotor.get_node("WheelHub")
				var journal := wheel_journal_measure(hub.mesh, Transform3D(Basis.from_scale(rotor.scale), Vector3.ZERO) * hub.transform)
				var expected_radius := 0.13 * scale_factor
				var expected_half_span := 0.225 * Geometry.WATERWHEEL_RADIUS / 0.70
				var first_liner: MeshInstance3D = machine.get_node("BearingLinerN")
				var measured_bore := wheel_mesh_envelope(first_liner.mesh, Transform3D.IDENTITY, true)
				print(JSON.stringify({"case": "sized_wheel_journal", "shared": shared_profile, "axis": axis_index,
					"tiles": sample.tiles, "cell": sample.cell, "level": sample.level, "journal": journal,
					"liner_minimum_radius_metres": measured_bore.minimum_radius,
					"actual_radial_gap_metres": measured_bore.minimum_radius - journal.radius,
					"expected_radius_metres": expected_radius, "expected_half_span_metres": expected_half_span}))
				var fitted := absf(journal.radius - expected_radius) < 0.000001 and absf(journal.low + expected_half_span) < 0.000001 \
					and absf(journal.high - expected_half_span) < 0.000001
				verify(fitted, "The actual transformed journal keeps its fixed bearing radius and original axial ends as wheel diameter changes.")
				if not fitted:
					view.free()
					return
				if not rejected_rim_scale:
					var enlarged_pose := Transform3D(Basis.from_scale(rotor.scale), Vector3.ZERO) \
						* Transform3D(hub.basis.orthonormalized(), hub.position)
					var enlarged := wheel_journal_measure(hub.mesh, enlarged_pose)
					verify(enlarged.radius > measured_bore.minimum_radius,
						"The actual journal facets fail the bore predicate when the old radial-growth transform is restored.")
					rejected_rim_scale = true
				verify(source.mesh == WheelArt.centre_for_tiles(sample.tiles) and source.material_override == WheelArt.centre_finish
					and source.transform == Transform3D.IDENTITY,
					"The fitted assembly retains one correctly sized hub and spoke set with its atlas.")
				check_split_wheel_rims(rotor, sample.tiles)
				var rim: MeshInstance3D = rotor.get_node("SourcedTimberRimN")
				var rim_radius := wheel_source_radial_extents(rim.mesh)
				var spoke_radius := wheel_source_radial_extents(source.mesh)
				var actual_wall := (rim_radius.y - rim_radius.x) * rotor.scale.x
				var smallest_wall := (WheelArt.RIM_OUTER_RADIUS - WheelArt.RIM_INNER_RADIUS) \
					* Geometry.WATERWHEEL_RADIUS / 0.70 * 3.0
				var growth := sqrt(float(sample.tiles) / 3.0)
				verify(absf(actual_wall - smallest_wall * growth) < 0.003
					and spoke_radius.y > rim_radius.x + 0.015 and spoke_radius.y < rim_radius.y,
					"The rim wall grows sublinearly with admitted diameter and retains seated spoke ends.")
				var original_points: PackedVector3Array = WheelArt.hub_spokes_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var sized_points: PackedVector3Array = source.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var original_hub := 0.0
				var actual_hub := 0.0
				for index in range(original_points.size()):
					var source_radius := Vector2(original_points[index].x, original_points[index].y).length()
					if source_radius <= WheelArt.HUB_OUTER_RADIUS:
						original_hub = maxf(original_hub, source_radius)
						actual_hub = maxf(actual_hub, Vector2(sized_points[index].x, sized_points[index].y).length())
				verify(absf(actual_hub * rotor.scale.x - original_hub * Geometry.WATERWHEEL_RADIUS / 0.70 * 3.0 * growth) < 0.001,
					"The timber hub grows sublinearly with the outer wheel rather than copying the wheel radius.")
				if not shared_profile and axis_index == 0 and sample.cell == [0, 0]:
					check_sourced_mesh(source, 4056, 6702, spoke_radius.y)
					check_sourced_mesh(rim, 1576, 1872, rim_radius.y)
					for child in rotor.get_children():
						if child is MeshInstance3D and child.get_meta("detail_role", "") == "WheelPaddle":
							var contact := wheel_root_rim_contact(rotor, child)
							verify(contact.x > 0 and contact.y == 0,
								"Every diameter seats its actual rim bounds in each paddle root and rejects displacement.")
							checked_paddle_joins += 1
				verify(hub.mesh is ArrayMesh and journal_shape_matches(hub.mesh, expected_half_span * 2.0, expected_radius),
					"The actual journal retains its outer planes with real end chamfers, relieved bands and recessed centres.")
				var finish := hub.material_override as StandardMaterial3D
				verify(finish == DriveJournalArt.material() and finish != null
					and finish.normal_texture == Opening.ProductionTransmissionFinish.textures.worked_normal
					and finish.roughness_texture == Opening.ProductionTransmissionFinish.textures.worked_roughness
					and finish.uv1_triplanar and not finish.uv1_world_triplanar
					and finish.uv1_scale.is_equal_approx(Vector3.ONE / Opening.ProductionTransmissionFinish.WORKED_METRES),
					"The journal reuses the qualified local worked-metal maps at their physical repeat.")
				if not cached.has("Journal"):
					check_closed_asset_mesh(hub.mesh, 0.0108, 0.0116)
					cached.Journal = [hub.mesh, finish]
					var plain := CylinderMesh.new()
					plain.top_radius = expected_radius
					plain.bottom_radius = expected_radius
					plain.height = expected_half_span * 2.0
					plain.radial_segments = 48
					verify(not journal_shape_matches(plain, plain.height, expected_radius),
						"The prior plain cylinder fails the same machining and recessed-centre predicate.")
				verify(hub.mesh == cached.Journal[0] and finish == cached.Journal[1],
					"Every admitted axis and diameter reuses the one fixed machined mesh and finish.")
				var rotor_rest := rotor.transform
				for angle in [0.0, 0.7, -1.6]:
					rotor.basis = rotor_rest.basis * Basis(Vector3.BACK, angle)
					var pose: Transform3D = machine.transform * rotor.transform * hub.transform
					verify(absf(pose.basis.x.length() - 1.0) < 0.000001
						and absf(pose.basis.y.length() - 1.0) < 0.000001
						and absf(pose.basis.z.length() - 1.0) < 0.000001
						and absf(pose.basis.x.dot(pose.basis.y)) < 0.000001
						and absf(pose.basis.y.dot(pose.basis.z)) < 0.000001
						and absf(pose.basis.z.dot(pose.basis.x)) < 0.000001,
						"Invented rotor poses keep the journal rigid and its local material scale in metres.")
				rotor.transform = rotor_rest
				verify(rotor.position.is_equal_approx(Vector3.UP * Geometry.ANCHOR_HEIGHT)
					and rotor.basis.z.normalized().dot(axis) > 0.99999
					and rotor.scale.is_equal_approx(Vector3(Geometry.WATERWHEEL_RADIUS / 0.70 * sample.tiles,
						Geometry.WATERWHEEL_RADIUS / 0.70 * sample.tiles, Geometry.WATERWHEEL_RADIUS / 0.70))
					and machine.position.is_equal_approx(Vector3(sample.cell[0] * Geometry.PITCH,
						sample.level * Geometry.HEIGHT_STEP, sample.cell[1] * Geometry.PITCH)),
					"The confirmed radius, axial thickness, spindle axis and common absolute grid origin remain unchanged.")
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
							and child.get_child(0).shape.size.is_equal_approx(Geometry.wheel_half_extents(axis_index, sample.tiles) * 2.0)
							and child.get_child(0).position.is_equal_approx(Vector3.UP * Geometry.ANCHOR_HEIGHT),
							"The native diameter-aware pick box remains separate from the fitted artwork.")
					if not child is MeshInstance3D or not child.has_meta("wheel_support_role"):
						continue
					var role: String = child.get_meta("wheel_support_role")
					counts[role] += 1
					verify(child.get_script() == null and child.get_child_count() == 0 and child.scale.is_equal_approx(Vector3.ONE),
						"Fixed hardware is plain cached render geometry with its scale baked in metres.")
					check_bounds(child, Transform3D.IDENTITY)
					var cache_key := role
					if not cached.has(cache_key):
						var limits: Array = {"WheelStand": [0.010, 0.020],
							"AxleBearing": [0.002, 0.009], "BearingLiner": [0.002, 0.004],
							"WheelFootBolt": [0.000020, 0.000025]}[cache_key]
						var volume_scale := pow(scale_factor, 3) * (Geometry.ANCHOR_HEIGHT / 0.5 if cache_key == "WheelStand" else 1.0)
						check_closed_asset_mesh(child.mesh, limits[0] * volume_scale, limits[1] * volume_scale)
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
						var gap: float = bore.minimum_radius - journal.radius - radial_offset
						minimum_gap = minf(minimum_gap, gap)
						verify(absf(child.basis.y.dot(axis)) > 0.99999 and gap > 0.004 * scale_factor,
							"The complete actual faceted liner bore is coaxial and clears the original rotating journal.")
						var axial_center: float = delta.dot(axis)
						var entry: float = minf(axial_center + bore.high, journal.high) \
							- maxf(axial_center + bore.low, journal.low)
						entries.append(entry)
						verify(absf(entry - (bore.high - bore.low)) < 0.000001
							and journal.high > axial_center + bore.high + 0.04
							and journal.low < axial_center + bore.low - 0.04,
							"The current journal crosses the full liner and retains exposed outer ends rather than stopping short.")
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
						verify(high < rotor.position.y - journal.radius,
							"The fixed stand stays below the journal's actual swept cylinder.")
						if not shared_profile and axis_index == 0 and controls == 2:
							var displaced: Transform3D = child.transform
							displaced.origin = Vector3.ZERO
							verify(not wheel_support_separates(child.mesh, inverse * displaced, rotating),
								"Moving a stand into the rotor fails the conservative whole-turn separation oracle.")
							controls += 1
				verify(picks == 1 and counts.WheelStand == 2
					and counts.AxleBearing == counts.WheelStand and counts.BearingLiner == counts.WheelStand
					and counts.WheelFootBolt == 4, "The actual native axis has its declared supports, liners and four fitted foot bolts.")
				verify(view.state == before and view.model == null and view.actor_world == null
					and view.request_sequence == 0 and not view.is_inside_tree(),
					"Hardware construction changes no projection, request, native body or authority.")
				assemblies += 1
				view.free()
	verify(controls == 3 and rejected_rim_scale and cached.size() == 5 and assemblies == 24
		and checked_paddle_joins == 36,
		"Both horizontal axes, three diameters and two absolute placements exercise all fixed mesh roles and negative controls.")
	var vertical_sizes := check_vertical_sized_wheels()
	verify(vertical_sizes == 2, "Both larger vertical wheels reuse the same resized source components and native axis.")
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
	wheel_support_checks_complete = assemblies == 24 and vertical_sizes == 2 and not failed
	print(JSON.stringify({"phase": "waterwheel supports", "assemblies": assemblies, "unique_mesh_roles": cached.size(),
		"diameter_paddle_joins": checked_paddle_joins, "vertical_sizes": vertical_sizes,
		"checks": checks, "checked_detail_parts": detail_meshes, "maximum_packed_tangent_dot": max_tangent_dot,
		"minimum_journal_clearance_metres": minimum_gap, "journal_entries_metres": entries, "controls": controls,
		"old_radial_growth_rejected": rejected_rim_scale,
		"legacy_assemblies": legacy_assemblies,
		"full_turn_check": "Conservative separation of actual facet envelopes, not native contact or force proof.",
		"observations": "invented", "native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

func check_vertical_sized_wheels() -> int:
	var checked := 0
	for tiles in [5, 8]:
		var view := Opening.new()
		view.machine_root = Node3D.new()
		view.add_child(view.machine_root)
		view.state = {"options": {"native": true},
			"entities": {"fixture": {"kind": "wheel", "cell": [0, 0], "axis": 1, "tiles": tiles, "generation": 1}},
			"links": [], "drive_links": [], "motion": {}}
		var before: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		var rotor: Node3D = view.wheel_rotor
		var source: MeshInstance3D = rotor.get_node("SourcedTimberRotor")
		verify(source.mesh == WheelArt.centre_for_tiles(tiles)
			and rotor.basis.z.normalized().dot(Vector3.UP) > 0.99999,
			"The sized vertical wheel keeps its sourced center on the native axle.")
		check_split_wheel_rims(rotor, tiles)
		check_native_wheel_bounds(rotor, Transform3D.IDENTITY, Vector3.UP, tiles)
		var supports := 0
		for child in view.machine_root.get_child(0).get_children():
			if child is MeshInstance3D and str(child.name).begins_with("AxleBearing"):
				supports += 1
		verify(supports == 1 and view.state == before and view.model == null and view.actor_world == null,
			"The vertical support count and observed native state remain unchanged by art sizing.")
		checked += 1
		view.free()
	return checked

func satin_coating_properties(finish: StandardMaterial3D) -> bool:
	var surface := Opening.ProductionTransmissionFinish
	return finish != null and finish.metallic == 0 and finish.metallic_texture == null \
		and finish.albedo_texture == null and finish.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
		and not finish.clearcoat_enabled and not finish.ao_enabled and finish.normal_enabled \
		and is_equal_approx(finish.normal_scale, 0.08) and finish.normal_texture == surface.textures.cast_normal \
		and finish.roughness == 1 and finish.roughness_texture == CollectorArt.paint_roughness \
		and finish.roughness_texture != surface.textures.cast_roughness \
		and finish.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED \
		and finish.uv1_triplanar and not finish.uv1_world_triplanar and finish.uv1_scale == Vector3(4, 4, 4)

func check_satin_coating() -> void:
	var surface := Opening.ProductionTransmissionFinish
	var original := surface.material("cast", Color("f3c16c"), 0.0, 0.72)
	verify(original != null and surface.source_status == "ready", "The existing qualified cast source is available before paint preparation.")
	if original == null or surface.source_status != "ready":
		return
	var source_image: Image = surface.textures.cast_roughness.get_image()
	verify(source_image != null and not source_image.is_empty() and source_image.get_size() == Vector2i(512, 512),
		"The source supplies its complete scalar image before the coating transformation is checked.")
	if source_image == null or source_image.is_empty():
		return
	var source_bytes := source_image.get_data()
	var worked_bytes: PackedByteArray = surface.textures.worked_roughness.get_image().get_data()
	var finish := CollectorArt.coating(Color("f3c16c"))
	verify(satin_coating_properties(finish), "The actual authored coating is opaque satin dielectric paint, distinct from its metal source.")
	if finish == null or finish.roughness_texture == null:
		return
	var paint := finish.roughness_texture.get_image()
	verify(paint != null and paint.get_size() == Vector2i(512, 512) and paint.has_mipmaps(),
		"The cached coating response keeps the qualified image dimensions and a complete mip chain.")
	if paint == null or paint.get_size() != source_image.get_size():
		return
	var valid := true
	var low := 255
	var high := 0
	var original_low := 255
	var original_high := 0
	for y in range(paint.get_height()):
		for x in range(paint.get_width()):
			var from := roundi(source_image.get_pixel(x, y).r * 255.0)
			var actual := roundi(paint.get_pixel(x, y).r * 255.0)
			var expected := clampi(roundi(165.75 + float(from) * 0.25), 166, 229)
			valid = valid and actual == expected and actual >= 166 and actual <= 229
			low = mini(low, actual)
			high = maxi(high, actual)
			original_low = mini(original_low, from)
			original_high = maxi(original_high, from)
	verify(valid and low < high, "Every actual paint pixel retains bounded source variation in the independently specified satin response.")
	verify(surface.textures.cast_roughness.get_image().get_data() == source_bytes
		and surface.textures.worked_roughness.get_image().get_data() == worked_bytes
		and original.roughness_texture == surface.textures.cast_roughness and is_equal_approx(original.normal_scale, 0.35),
		"Paint preparation leaves the original cast/worked image bytes and independently cached material unchanged.")
	var replacement := CollectorArt.coating(Color("58634c"))
	verify(replacement != finish and replacement.roughness_texture == finish.roughness_texture
		and replacement.normal_texture == finish.normal_texture and replacement.albedo_color == Color("58634c"),
		"Different original tints share the same authored paint texture without sharing mutable material identity.")
	var control := finish.duplicate(false) as StandardMaterial3D
	control.roughness_texture = surface.textures.cast_roughness
	verify(not satin_coating_properties(control), "The original untransformed metal roughness cannot substitute for the authored paint response.")
	control.roughness_texture = finish.roughness_texture
	control.metallic = 0.85
	verify(not satin_coating_properties(control), "A metallic substitution cannot pass the coating role predicate.")
	print(JSON.stringify({"satin_pixels": paint.get_width() * paint.get_height(), "paint_bytes": [low, high],
		"source_bytes": [original_low, original_high], "negative_controls": 2, "source_images_unchanged": true,
		"observations": "invented read-only materials", "gameplay": "not_run"}))

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
				var color := Color("96805c")
				if role == "CastLowerHousing":
					color = color.darkened(0.09)
				elif role == "CastUpperHood":
					color = Color("394f59")
				verify(finish_value != null and finish_value.albedo_color == color,
					"The formed hood and original cast roles retain their distinct declared coating colors.")
				if historical:
					verify(finish_value == Visuals.material(color, 0.08, 0.72),
						"A missing historical map set retains the exact original generated coating resource.")
				else:
					verify(finish_value.metallic == 0 and finish_value.metallic_texture == null
						and finish_value.metallic_specular == 0.5 and finish_value.albedo_texture == null
						and finish_value.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
						and not finish_value.clearcoat_enabled and not finish_value.ao_enabled,
						"The authored opaque paint is a dielectric without a second coat, metallic mask or invented occlusion.")
					verify(finish_value.normal_enabled and is_equal_approx(finish_value.normal_scale, 0.08)
						and finish_value.normal_texture == surface.textures.cast_normal
						and finish_value.roughness_texture == CollectorArt.paint_roughness
						and finish_value.roughness_texture != surface.textures.cast_roughness
						and finish_value.roughness == 1 and finish_value.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED,
						"The coating shares qualified normal detail and a separate authored satin response without changing exposed metal maps.")
					verify(finish_value.uv1_triplanar and not finish_value.uv1_world_triplanar
						and finish_value.uv1_scale == Vector3(4, 4, 4)
						and finish_value.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
						"Local mapping retains the declared quarter-metre art scale and mip filtering.")
					var original := surface.material("cast", color, 0.0, 0.72)
					verify(finish_value != original and is_equal_approx(original.normal_scale, 0.35),
						"Reducing coating relief does not mutate the independently cached source material.")
				if cached.has(color):
					verify(finish_value == cached[color], "Every view and axis shares one coating material per declared tint.")
				else:
					cached[color] = finish_value
			verify(count == 6, "Exactly six existing painted casting roles receive the coating.")
			coated_parts += count
			var drum: MeshInstance3D = machine.get_node("CutterDrum")
			var expected_metal := Visuals.material(Color("465a60"), 0.85, 0.4) if historical \
				else Opening.ProductionTransmissionFinish.material("worked", Color("465a60"), 0.85, 0.4)
			verify(drum.material_override == expected_metal,
				"The moving cutter remains metal, with the current qualified worked finish or the exact historical fallback.")
			verify(view.state == before and view.model == null and view.actor_world == null
				and view.request_sequence == 0 and not view.is_inside_tree(),
				"Material construction changes no projection, authority, native body or request.")
			assemblies += 1
			view.free()
	verify(cached.size() == 3 and surface.source_status == ("missing" if historical else "ready"),
		"Three distinct cast tints and the declared resource presence remain explicit.")
	print(JSON.stringify({"phase": "collector coating", "assemblies": assemblies, "coated_parts": coated_parts,
		"coating_materials": cached.size(), "historical_missing_set": historical,
		"maps": "historical generated coating" if historical else "qualified cast normal and authored satin roughness", "geometry_changed": false,
		"native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

func foundation_plane(node: MeshInstance3D, upward: bool) -> Dictionary:
	var faces := die_faces(node.mesh, 0)
	var height := -INF if upward else INF
	var area := 0.0
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var triangles := 0
	for n in range(0, faces.size(), 3):
		var a: Vector3 = node.transform * faces[n]
		var b: Vector3 = node.transform * faces[n + 1]
		var c: Vector3 = node.transform * faces[n + 2]
		var cross := (b - a).cross(c - a)
		if absf(a.y - b.y) > 0.0000001 or absf(a.y - c.y) > 0.0000001 \
			or cross.y * (1.0 if upward else -1.0) >= 0:
			continue
		if (a.y > height + 0.0000001 if upward else a.y < height - 0.0000001):
			height = a.y
			area = 0.0
			low = Vector2(INF, INF)
			high = Vector2(-INF, -INF)
			triangles = 0
		if absf(a.y - height) < 0.0000001:
			area += absf(cross.y) / 2.0
			triangles += 1
			for point in [a, b, c]:
				low = low.min(Vector2(point.x, point.z))
				high = high.max(Vector2(point.x, point.z))
	return {"height": height, "area": area, "low": low, "high": high, "triangles": triangles}

func foundation_contact(footing: MeshInstance3D, deck: MeshInstance3D) -> Dictionary:
	var support := foundation_plane(footing, true)
	var foot := foundation_plane(deck, false)
	var overlap: Vector2 = (support.high.min(foot.high) - support.low.max(foot.low)).max(Vector2.ZERO)
	var contact: float = overlap.x * overlap.y
	var ratio: float = contact / foot.area if foot.area > 0 else 0.0
	var gap: float = foot.height - support.height
	return {"valid": support.triangles == 24 and foot.triangles == 18 and absf(gap) < 0.000001 and ratio >= 0.97,
		"gap": gap, "contact_area": contact, "deck_foot_area": foot.area, "supported_fraction": ratio,
		"support_plane": support.height, "deck_foot_plane": foot.height}

func foundation_bounds_match(parent: Node3D) -> bool:
	var bounds := feed_item_bounds(parent, parent.transform.affine_inverse())
	return bounds.position.is_equal_approx(Vector3(-Geometry.PITCH / 2.0, -Geometry.FOUNDATION_DEPTH, -Geometry.PITCH / 2.0)) \
		and bounds.size.is_equal_approx(Vector3(Geometry.PITCH, Geometry.FOUNDATION_DEPTH, Geometry.PITCH))

func check_foundation_art() -> void:
	var control_root := OS.get_environment("FACTORY_FOUNDATION_RESOURCE_CONTROLS")
	if not control_root.is_absolute_path() or not DirAccess.dir_exists_absolute(control_root):
		verify(false, "The foundation fixture needs an existing owned external control directory.")
		return
	verify(FoundationArt.read_images().status == "ready", "The complete qualified concrete set is present.")
	verify(FoundationArt.read_images(control_root.path_join("missing")).status == "missing",
		"A missing set is distinguishable from a complete surface.")
	var partial := control_root.path_join("partial")
	verify(DirAccess.make_dir_absolute(partial) == OK, "The incomplete-set control uses a fresh owned directory.")
	var entry := FileAccess.open(partial.path_join(FoundationArt.FILES.albedo), FileAccess.WRITE)
	verify(entry != null, "The incomplete-set control can retain its placeholder.")
	if entry == null:
		return
	entry.store_string("This is a deliberately incomplete control, not an image.")
	entry.close()
	verify(FoundationArt.read_images(partial).status == "invalid", "A partial set is never described as qualified.")
	var concrete := FoundationArt.material()
	var deck_finish := Opening.ProductionSteelFloor.material()
	verify(FoundationArt.source_status == "ready" and concrete != null and concrete.metallic == 0
		and concrete.metallic_texture == null and not concrete.ao_enabled and concrete.ao_texture == null
		and concrete.albedo_color == Color.WHITE and concrete.albedo_texture == FoundationArt.textures.albedo
		and concrete.roughness == 1 and concrete.roughness_texture == FoundationArt.textures.arm
		and concrete.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN,
		"Concrete keeps qualified color and green roughness without metallic or invented occlusion bindings.")
	verify(concrete.normal_enabled and concrete.normal_texture == FoundationArt.textures.normal and concrete.normal_scale == 1
		and concrete.uv1_triplanar and concrete.uv1_world_triplanar and concrete.uv1_scale == Vector3(0.5, 0.5, 0.5)
		and concrete.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
		"Normal mapping and mip-filtered two-metre world-space coordinates stay continuous across stationary tiles.")
	var normal := concrete.normal_texture.get_image()
	var scalars := concrete.roughness_texture.get_image()
	verify(normal.get_size() == Vector2i(512, 512) and scalars.get_size() == Vector2i(512, 512)
		and normal.get_format() == Image.FORMAT_RGB8 and scalars.get_format() == Image.FORMAT_RGB8
		and normal.has_mipmaps() and scalars.has_mipmaps()
		and concrete.albedo_texture.get_size() == Vector2(1024, 1024) and concrete.albedo_texture.get_image().has_mipmaps(),
		"Actual textures retain the qualified dimensions, data formats and mip chains.")
	var valid_normals := true
	var rough_low := INF
	var rough_high := -INF
	for y in range(512):
		for x in range(512):
			var color := normal.get_pixel(x, y)
			var direction := Vector3(color.r, color.g, color.b) * 2.0 - Vector3.ONE
			valid_normals = valid_normals and direction.is_finite() and absf(direction.length() - 1) < 0.01
			var roughness: float = scalars.get_pixel(x, y).g
			rough_low = minf(rough_low, roughness)
			rough_high = maxf(rough_high, roughness)
	verify(valid_normals and rough_low >= 0 and rough_high <= 1 and rough_high > rough_low,
		"Every actual base-level normal remains normalized within its encoding bound, with finite varied source roughness.")
	var seen: Dictionary = {}
	var contacts: Array[Dictionary] = []
	for offset in [Vector3.ZERO, Vector3(3.3, 1.65, -1.65)]:
		var parent := Node3D.new()
		parent.position = offset
		verify(FoundationArt.mount(parent) and parent.get_child_count() == 2 and parent.position == offset
			and parent.basis == Basis.IDENTITY and foundation_bounds_match(parent),
			"The reusable kit keeps one full tile below its caller's top-plane origin without another height grid.")
		var footing := parent.get_node("FoundationBlock") as MeshInstance3D
		var deck := parent.get_node("FoundationTop") as MeshInstance3D
		for part in [footing, deck]:
			verify(part.get_script() == null and part.get_child_count() == 0 and part.scale == Vector3.ONE
				and not part is CollisionObject3D and part.mesh.get_surface_count() == 1,
				"Each piece is baked passive geometry, without collision, input, processing or state authority.")
			var key := str(part.name)
			if not seen.has(key):
				check_closed_asset_mesh(part.mesh, 2.12 if part == footing else 0.063,
					2.19 if part == footing else 0.066)
				seen[key] = [part.mesh, part.material_override]
			verify(part.mesh == seen[key][0] and part.material_override == seen[key][1],
				"Translated and stacked sections reuse the same actual mesh and surface resources.")
		verify(footing.material_override == concrete and deck.material_override == deck_finish,
			"The original qualified steel deck and the new concrete have distinct cached responses.")
		var contact := foundation_contact(footing, deck)
		verify(contact.valid, "The steel deck meets the actual concrete support plane; only its narrow chamfer lip overhangs.")
		contacts.append(contact)
		var top := foundation_plane(deck, true)
		var bottom := foundation_plane(footing, false)
		verify(absf(top.height) < 0.000001 and absf(bottom.height + Geometry.FOUNDATION_DEPTH) < 0.000001,
			"The actual top and base facets meet the common zero and two-step stacking datums.")
		var deck_pose := deck.position
		deck.position.y += 0.01
		verify(not foundation_contact(footing, deck).valid, "A floating deck fails despite unchanged mesh bounds.")
		deck.position = deck_pose
		footing.scale.x = 0.8
		verify(not foundation_contact(footing, deck).valid, "Insufficient support cannot pass merely because the plane heights match.")
		footing.scale = Vector3.ONE
		parent.free()
	var patch := Node3D.new()
	var confirmed := {"a": {"cell": [0, 0], "level": 0}, "b": {"cell": [1, 0], "level": 0},
		"c": {"cell": [0, 1], "level": 0}, "d": {"cell": [1, 1], "level": 0},
		"raised": {"cell": [0, -1], "level": 2}}
	var masks: Dictionary = FoundationArt.neighbor_masks(confirmed)
	verify(masks == {"a": FoundationArt.EAST | FoundationArt.SOUTH, "b": FoundationArt.WEST | FoundationArt.SOUTH,
		"c": FoundationArt.EAST | FoundationArt.NORTH, "d": FoundationArt.WEST | FoundationArt.NORTH,
		"raised": 0}, "Only confirmed same-level cardinal neighbors close a foundation edge.")
	for id in ["a", "b", "c", "d"]:
		var cell := Vector2i(confirmed[id].cell[0], confirmed[id].cell[1])
		var tile := Node3D.new()
		tile.position = Vector3(cell.x * Geometry.PITCH, 0, cell.y * Geometry.PITCH)
		patch.add_child(tile)
		verify(FoundationArt.mount(tile, masks[id]), "Each joined tile uses its confirmed same-level perimeter kit.")
	var patch_bounds := feed_item_bounds(patch, Transform3D.IDENTITY)
	verify(patch_bounds.position.is_equal_approx(Vector3(-0.825, -Geometry.FOUNDATION_DEPTH, -0.825))
		and patch_bounds.size.is_equal_approx(Vector3(3.3, Geometry.FOUNDATION_DEPTH, 3.3)),
		"A two-by-two assembly joins on the one world grid without cumulative local offsets.")
	patch.free()
	var perimeter_meshes := 0
	for mask in range(16):
		var mesh: ArrayMesh = FoundationArt.deck_mesh(mask)
		check_closed_asset_mesh(mesh, 0.063, 0.066)
		verify(mesh == FoundationArt.deck_mesh(mask), "Each of the sixteen edge variants is cached without another state owner.")
		var concrete_mesh: ArrayMesh = FoundationArt.footing_mesh(mask)
		check_closed_asset_mesh(concrete_mesh, 2.12, 2.19)
		verify(concrete_mesh == FoundationArt.footing_mesh(mask),
			"The concrete exterior courses reuse one bounded mesh per confirmed neighbor arrangement.")
		var tile := Node3D.new()
		verify(FoundationArt.mount(tile, mask) and foundation_contact(tile.get_node("FoundationBlock"),
			tile.get_node("FoundationTop")).valid and foundation_bounds_match(tile),
			"Every perimeter combination preserves closed deck, footing support and the original tile envelope.")
		tile.free()
		perimeter_meshes += 1
	var half := Geometry.PITCH / 2.0
	var top := FoundationArt.DECK_THICKNESS / 2.0
	var joined_vertices := 0
	for vertex: Vector3 in FoundationArt.deck_mesh(FoundationArt.EAST).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(vertex.x - half) < 0.000001:
			joined_vertices += 1
			verify(absf(vertex.y - top) < 0.000001,
				"Every vertex on a joined east edge reaches the common unbroken deck plane.")
	var exposed_recess := false
	for vertex: Vector3 in FoundationArt.deck_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(vertex.x - half) < 0.000001 and vertex.y < top - 0.001:
			exposed_recess = true
	verify(joined_vertices >= 4 and exposed_recess,
		"A true perimeter keeps the edge bevel while a joined edge does not recreate a groove.")
	var north_exposed_extent := -INF
	var north_joined_extent := -INF
	for vertex: Vector3 in FoundationArt.footing_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(vertex.z + half) < 0.000001:
			north_exposed_extent = maxf(north_exposed_extent, vertex.x)
	for vertex: Vector3 in FoundationArt.footing_mesh(FoundationArt.EAST).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(vertex.z + half) < 0.000001:
			north_joined_extent = maxf(north_joined_extent, vertex.x)
	verify(absf(north_exposed_extent - (half - FoundationArt.FOOTING_BEVEL)) < 0.000001
		and absf(north_joined_extent - (half - FoundationArt.JOIN_CORNER)) < 0.000001,
		"An exposed concrete corner keeps its bevel, while a confirmed adjoining tile closes the accidental wall groove.")
	var panel_height: float = (Geometry.FOUNDATION_DEPTH - FoundationArt.DECK_THICKNESS) / 2.0 - 0.15
	var panel_edge: float = half - FoundationArt.BAY_MARGIN - FoundationArt.BAY_SHOULDER
	var exposed_bay := false
	var joined_bay := false
	for vertex: Vector3 in FoundationArt.footing_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(vertex.y - panel_height) < 0.000001 and absf(absf(vertex.x) - panel_edge) < 0.000001 \
				and absf(vertex.z + half - FoundationArt.BAY_RECESS) < 0.000001:
			exposed_bay = true
	for vertex: Vector3 in FoundationArt.footing_mesh(FoundationArt.NORTH).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(vertex.y - panel_height) < 0.000001 and absf(absf(vertex.x) - panel_edge) < 0.000001 \
				and absf(vertex.z + half) < 0.000001:
			joined_bay = true
	verify(exposed_bay and joined_bay,
		"Exposed walls recess their central casting bay while a confirmed shared wall stays flat.")
	confirmed.erase("b")
	var removed_masks: Dictionary = FoundationArt.neighbor_masks(confirmed)
	verify(removed_masks.a == FoundationArt.SOUTH and removed_masks.d == FoundationArt.WEST,
		"Removing a tile re-exposes the missing side on the next projection rebuild.")
	var view := Opening.new()
	view.machine_root = Node3D.new()
	view.state = {"options": {"native": true, "physical": true}, "foundations": confirmed,
		"entities": {}, "links": [], "drive_links": [], "transmission_parts": {}, "motion": {}, "engagements": []}
	var before_state: Dictionary = view.state.duplicate(true)
	view._rebuild_machines()
	var actual_masks: Dictionary = {}
	var actual_footings: Dictionary = {}
	for anchor: Node3D in view.machine_root.get_children():
		var found_id := ""
		for id in confirmed:
			if anchor.position.is_equal_approx(view._entity_position(confirmed[id])):
				found_id = id
		if not found_id.is_empty():
			actual_masks[found_id] = anchor.get_node("FoundationTop").mesh
			actual_footings[found_id] = anchor.get_node("FoundationBlock").mesh
			var picking := false
			for child in anchor.get_children():
				if child is StaticBody3D:
					picking = child.get_meta("entity", "") == found_id and child.collision_layer == Geometry.PICK_LAYER
			verify(picking,
				"Presentation selection leaves the original per-tile picking body in place.")
	verify(actual_masks.size() == confirmed.size() and view.state == before_state
		and view.model == null and view.actor_world == null and view.request_sequence == 0,
		"The ordinary rebuild uses only confirmed projection rows and changes no native authority or requests.")
	for id in confirmed:
		verify(actual_masks[id] == FoundationArt.deck_mesh(removed_masks[id]),
			"The ordinary rebuilt foundation mounts the exact edge variant for its confirmed neighbors.")
		verify(actual_footings[id] == FoundationArt.footing_mesh(removed_masks[id]),
			"Concrete joins and exposed corners follow the same confirmed layout after removal.")
	view.machine_root.free()
	view.free()
	var lower := Node3D.new()
	var upper := Node3D.new()
	upper.position.y = Geometry.FOUNDATION_DEPTH
	verify(FoundationArt.mount(lower) and FoundationArt.mount(upper), "Stacked tiles mount the same passive kit.")
	var lower_deck := foundation_plane(lower.get_node("FoundationTop"), true)
	var upper_base := foundation_plane(upper.get_node("FoundationBlock"), false)
	verify(absf(lower_deck.height + lower.position.y - upper_base.height - upper.position.y) < 0.000001
		and upper_base.low.x >= lower_deck.low.x and upper_base.low.y >= lower_deck.low.y
		and upper_base.high.x <= lower_deck.high.x and upper_base.high.y <= lower_deck.high.y,
		"The actual upper footing sits on the full lower deck support at the same world-space stacking datum.")
	lower.free()
	upper.free()
	print(JSON.stringify({"phase": "foundation art", "checks": checks, "cached_meshes": seen.size(),
		"perimeter_meshes": perimeter_meshes,
		"contact_observations": contacts, "normal_pixels": 512 * 512, "roughness_range": [rough_low, rough_high],
		"negative_control_types": 3, "native_foundation_gameplay": "not_run", "rendered_quality": "not_assessed"}))
	foundation_art_complete = true

func journal_section_radius(mesh: Mesh, height: float) -> float:
	var maximum := -INF
	for surface in range(mesh.get_surface_count()):
		var faces := die_faces(mesh, surface)
		for n in range(0, faces.size(), 3):
			for edge in [[0, 1], [1, 2], [2, 0]]:
				var a := faces[n + edge[0]]
				var b := faces[n + edge[1]]
				if absf(a.y - height) < 0.000001:
					maximum = maxf(maximum, Vector2(a.x, a.z).length())
				if (a.y < height and b.y > height) or (a.y > height and b.y < height):
					var cut := a.lerp(b, (height - a.y) / (b.y - a.y))
					maximum = maxf(maximum, Vector2(cut.x, cut.z).length())
	return maximum

func journal_center_hits(mesh: Mesh) -> Array[float]:
	var hits: Array[float] = []
	for surface in range(mesh.get_surface_count()):
		var faces := die_faces(mesh, surface)
		for n in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3(0, -1, 0), Vector3(0, 1, 0),
				faces[n], faces[n + 1], faces[n + 2])
			if hit == null:
				continue
			var known := false
			for previous in hits:
				known = known or absf(previous - hit.y) < 0.000001
			if not known:
				hits.append(hit.y)
	hits.sort()
	return hits

func journal_shape_matches(mesh: Mesh, height: float, radius: float = 0.085) -> bool:
	var half := height / 2.0
	var ratio := radius / 0.085
	var bounds := mesh.get_aabb()
	if not bounds.position.is_equal_approx(Vector3(-radius, -half, -radius)) \
		or not bounds.size.is_equal_approx(Vector3(radius * 2.0, height, radius * 2.0)):
		return false
	for level in [0.0, -half + 0.08, half - 0.08]:
		if absf(journal_section_radius(mesh, level) - radius) > 0.000001:
			return false
	for sign_value in [-1.0, 1.0]:
		if absf(journal_section_radius(mesh, sign_value * (half - 0.051)) - 0.081 * ratio) > 0.000001 \
			or absf(journal_section_radius(mesh, sign_value * (half - 0.007)) - 0.078 * ratio) > 0.000001:
			return false
	var hits := journal_center_hits(mesh)
	return hits.size() == 2 and absf(hits[0] + half - 0.020) < 0.000001 \
		and absf(hits[1] - half + 0.020) < 0.000001

func journal_pose_matches(journal: MeshInstance3D, axis: int) -> bool:
	return journal.position.is_equal_approx(Vector3(0, Geometry.ANCHOR_HEIGHT, 0)) and journal.scale.is_equal_approx(Vector3.ONE) \
		and journal.basis.y.dot([Vector3.LEFT, Vector3.UP, Vector3.BACK][axis]) > 0.99999

func press_input_hits(part: MeshInstance3D, from: Vector3, to: Vector3) -> Array[float]:
	var hits: Array[float] = []
	var direction := (to - from).normalized()
	for surface in range(part.mesh.get_surface_count()):
		var faces := die_faces(part.mesh, surface)
		for n in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(from, to,
				part.transform * faces[n], part.transform * faces[n + 1], part.transform * faces[n + 2])
			if hit == null:
				continue
			var distance: float = (hit - from).dot(direction)
			var seen := false
			for previous in hits:
				seen = seen or absf(previous - distance) < 0.000001
			if not seen:
				hits.append(distance)
	hits.sort()
	return hits

func press_input_overlap(a: MeshInstance3D, b: MeshInstance3D, from: Vector3, to: Vector3) -> float:
	var first := press_input_hits(a, from, to)
	var second := press_input_hits(b, from, to)
	if first.is_empty() or second.is_empty() or first.size() % 2 != 0 or second.size() % 2 != 0:
		return -INF
	var overlap := -INF
	for i in range(0, first.size(), 2):
		for j in range(0, second.size(), 2):
			overlap = maxf(overlap, minf(first[i + 1], second[j + 1]) - maxf(first[i], second[j]))
	return overlap

func press_input_bore_radius(mesh: Mesh) -> float:
	var radius := INF
	for surface in range(mesh.get_surface_count()):
		var faces := die_faces(mesh, surface)
		for n in range(0, faces.size(), 3):
			var points: Array[Vector2] = [Vector2(faces[n].x, faces[n].z),
				Vector2(faces[n + 1].x, faces[n + 1].z), Vector2(faces[n + 2].x, faces[n + 2].z)]
			var area := (points[1] - points[0]).cross(points[2] - points[0])
			var signs: Array[float] = []
			for edge_index in range(3):
				var a := points[edge_index]
				var b := points[(edge_index + 1) % 3]
				var edge := b - a
				var t := clampf(-a.dot(edge) / edge.length_squared(), 0, 1) if edge.length_squared() > 0 else 0.0
				radius = minf(radius, (a + edge * t).length())
				signs.append(edge.cross(-a))
			if absf(area) > 0.000000000001 and ((signs[0] >= 0 and signs[1] >= 0 and signs[2] >= 0)
				or (signs[0] <= 0 and signs[1] <= 0 and signs[2] <= 0)):
				return 0.0
	return radius

func check_press_input_clearance() -> void:
	press_input_checks_complete = false
	var cache: Dictionary = {}
	var assemblies := 0
	var displaced_support_controls := 0
	var minimum_gap := INF
	var minimum_support := INF
	for shared_profile in [false, true]:
		for axis in [0, 2]:
			for cell in [[0, 0], [2, -1]]:
				for level in [0, 4]:
					var view: Variant = Shared.new() if shared_profile else Opening.new()
					view.machine_root = Node3D.new()
					view.item_root = Node3D.new()
					view.add_child(view.machine_root)
					view.add_child(view.item_root)
					view.state = {"context": "press-input-art", "options": {"native": true, "physical": true},
						"actors": {}, "inventories": {"P": 0}, "stock": {"source": 15, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 1},
						"remaining": 0, "entities": {"fixture": {"kind": "processor", "cell": cell, "level": level, "axis": axis, "generation": 1}},
						"transmission_parts": {}, "motion": {}, "links": [], "drive_links": [], "engagements": []}
					var before: Dictionary = view.state.duplicate(true)
					view._rebuild_machines()
					view._redraw_items()
					var machine: Node3D = view.machine_root.get_child(0)
					var journal: MeshInstance3D = machine.get_node("DriveStub")
					var anvil: MeshInstance3D = machine.get_node("Anvil")
					var head: MeshInstance3D = machine.get_node("ToolHead")
					var gap := tray_mesh_gap(journal, anvil.transform * anvil.mesh.get_aabb())
					print(JSON.stringify({"case": "horizontal_press_input", "shared": shared_profile,
						"axis": axis, "cell": cell, "level": level, "journal_anvil_gap_metres": gap}))
					verify(gap > 0.02, "Horizontal input journal facets clear the complete anvil instead of crossing its working body.")
					if gap <= 0.02:
						view.free()
						return
					minimum_gap = minf(minimum_gap, gap)
					verify(journal_pose_matches(journal, axis) and machine.position.is_equal_approx(
						Vector3(cell[0] * Geometry.PITCH, level * Geometry.HEIGHT_STEP, cell[1] * Geometry.PITCH)),
						"Input reference frames preserve the confirmed axis, world origin and absolute construction level.")
					verify(journal.mesh.get_aabb().position.is_equal_approx(Vector3(-0.085, -0.675, -0.085))
						and journal.mesh.get_aabb().size.is_equal_approx(Vector3(0.17, 1.35, 0.17)),
						"Both original outer input ends and their radial envelope remain unchanged.")
					var centre_hits := journal_center_hits(journal.mesh)
					verify(centre_hits.size() == 4 and absf(centre_hits[0] + 0.655) < 0.000001
						and absf(centre_hits[1] + 0.515) < 0.000001 and absf(centre_hits[2] - 0.515) < 0.000001
						and absf(centre_hits[3] - 0.655) < 0.000001,
						"Actual facets retain two closed recessed input ends and leave the full central span open.")
					for side in [-1.0, 1.0]:
						verify(absf(journal_section_radius(journal.mesh, side * 0.60) - 0.077) < 0.000001
							and absf(journal_section_radius(journal.mesh, side * 0.65) - 0.085) < 0.000001,
							"Relieved inboard shoulders clear product hardware while the outboard bearing cuffs keep their original radius.")
					if not cache.has("journal"):
						check_closed_asset_mesh(journal.mesh, 0.0064, 0.0068)
						cache.journal = journal.mesh
						var former := MeshInstance3D.new()
						former.mesh = DriveJournalArt.mesh(1.35)
						former.transform = journal.transform
						# The earlier lower axle crossed the working body. The current
						# confirmed shaft height is tested separately above.
						former.position.y = 0.5
						verify(tray_mesh_gap(former, anvil.transform * anvil.mesh.get_aabb()) <= 0,
							"The former lower full-width journal fails the raw-facet clearance predicate.")
						former.free()
					verify(journal.mesh == cache.journal and journal.material_override == DriveJournalArt.material(),
						"Both axes and view classes reuse the same complete journal mesh and qualified worked finish.")
					var rows: Array = machine.get_meta("motion_meshes")
					verify(rows.size() == 2 and rows[0].node == head and str(rows[1].node.name) == "Piston",
						"Only the existing head and piston consume observed motion.")
					var fixed: Array[MeshInstance3D] = [journal]
					for child in machine.get_children():
						if child is MeshInstance3D and child.has_meta("press_input_role"):
							fixed.append(child)
					verify(fixed.size() == (7 if axis == 0 else 5), "Every horizontal input has its two supported fixed bearing housings.")
					var poses: Array[Transform3D] = []
					for part in fixed:
						poses.append(part.transform)
						verify(part.get_script() == null and part.get_child_count() == 0, "Input art remains a passive rigid mesh.")
						check_bounds(part, Transform3D.IDENTITY)
						var role: String = part.get_meta("press_input_role", "journal")
						var key := role + str(axis) if role == "Post" else role
						if role != "journal" and not cache.has(key):
							check_closed_asset_mesh(part.mesh, 0.00015 if role == "Bearing" else 0.0001,
								0.0003 if role == "Bearing" else 0.01)
							cache[key] = part.mesh
						if role != "journal":
							verify(part.mesh == cache[key], "Repeated fixed input hardware shares its cached geometry.")
							verify(tray_mesh_gap(part, anvil.transform * anvil.mesh.get_aabb()) > 0.02,
								"Fixed bearing hardware leaves the anvil and feed opening clear.")
						if role == "Bearing":
							verify(press_input_bore_radius(part.mesh) - 0.085 > 0.0015,
								"Raw inner facets leave a real annular gap around the unchanged journal radius.")
						if role in ["Post", "Bracket"]:
							verify(tray_mesh_gap(journal, part.transform * part.mesh.get_aabb()) > 0.003,
								"Actual journal facets clear their fixed supporting brackets.")
						if role == "Post":
							var probe := Vector2(part.position.x + (0.12 if axis == 2 else 0.0), part.position.z)
							var deck: MeshInstance3D = machine.get_node("Plinth")
							verify(absf(die_height(part.mesh, 0, part.transform, probe, false)
								- die_height(deck.mesh, 0, deck.transform, probe, true)) < 0.000001,
								"Each real pedestal bottom meets the actual skid top.")
					for side in [-1, 1]:
						var suffix := "Left" if side < 0 else "Right"
						var bearing: MeshInstance3D = machine.get_node("PressInputBearing" + suffix)
						var post: MeshInstance3D = machine.get_node("PressInputPost" + suffix)
						var support := -INF
						if axis == 0:
							var bracket: MeshInstance3D = machine.get_node("PressInputBracket" + suffix)
							var ear_join := press_input_overlap(bearing, bracket,
								Vector3(side * 0.66, Geometry.ANCHOR_HEIGHT - 0.035, -1),
								Vector3(side * 0.66, Geometry.ANCHOR_HEIGHT - 0.035, 1))
							var foot_join := press_input_overlap(post, bracket,
								Vector3(side * 0.66, -0.1, -0.175), Vector3(side * 0.66, 1, -0.175))
							support = minf(ear_join, foot_join)
							if not shared_profile and cell == [0, 0] and level == 0 and side < 0:
								var original_bracket_position := bracket.position
								bracket.position.y += 0.20
								verify(press_input_overlap(bearing, bracket,
									Vector3(side * 0.66, Geometry.ANCHOR_HEIGHT - 0.035, -1),
									Vector3(side * 0.66, Geometry.ANCHOR_HEIGHT - 0.035, 1)) <= 0,
									"The raw contact oracle rejects a lifted X-axis bearing ear.")
								bracket.position = original_bracket_position
								displaced_support_controls += 1
						else:
							support = press_input_overlap(bearing, post,
								Vector3(0.095, -0.1, side * 0.66), Vector3(0.095, 1, side * 0.66))
							if not shared_profile and cell == [0, 0] and level == 0 and side < 0:
								var original_post_position := post.position
								post.position.x += 0.20
								verify(press_input_overlap(bearing, post,
									Vector3(0.095, -0.1, side * 0.66), Vector3(0.095, 1, side * 0.66)) <= 0,
									"The raw contact oracle rejects a displaced Z-axis support cheek.")
								post.position = original_post_position
								displaced_support_controls += 1
						minimum_support = minf(minimum_support, support)
						verify(support > 0.001, "Raw closed-mesh probes establish finite bearing-to-frame contact.")
					var item_rows: Array[Dictionary] = []
					var plates := 0
					for item in view.item_root.get_children():
						if item is Node3D and item.get_meta("item_kind", "") == "stamped_plate":
							plates += 1
							hub_mesh_rows(item, machine.transform.affine_inverse() * view.item_root.transform, item_rows)
					verify(plates == 1 and item_rows.size() == 10, "The clearance oracle sees every original component of the confirmed finished plate.")
					for item in item_rows:
						var box: AABB = item.pose * item.node.mesh.get_aabb()
						for part in fixed:
							var item_gap := tray_mesh_gap(part, box)
							if item_gap <= 0.000001:
								print(JSON.stringify({"case": "press_input_outlet_clearance", "axis": axis, "shared": shared_profile,
									"cell": cell, "level": level, "fixed_part": str(part.name),
									"product_part": str(item.node.name), "gap_metres": item_gap}))
							verify(item_gap > 0.000001,
								"Actual input facets clear each complete finished-plate component at its original outlet pose.")
					for travel in [0.0, 0.0075, 0.015]:
						view._apply_press_pose(rows, travel)
						var sweep: AABB = head.transform * head.mesh.get_aabb()
						for index in range(fixed.size()):
							verify(fixed[index].transform == poses[index] and tray_mesh_gap(fixed[index], sweep) > 0.02,
								"Fixed input hardware clears both original tool endpoints and the intermediate pose.")
					verify(view.state == before and view.model == null and view.actor_world == null and view.request_sequence == 0,
						"Ordinary offline/shared assembly changes no confirmed state, requests or authority.")
					assemblies += 1
					view.free()
	print(JSON.stringify({"phase": "horizontal press inputs", "assemblies": assemblies, "axes": ["x", "z"],
		"minimum_anvil_gap_metres": minimum_gap if is_finite(minimum_gap) else null,
		"minimum_support_overlap_metres": minimum_support if is_finite(minimum_support) else null,
		"displaced_support_controls": displaced_support_controls,
		"vertical_layout": "unchanged and not accepted by this case", "native_gameplay": "not_run"}))
	press_input_checks_complete = assemblies == 16 and not failed

func check_collector_input_support() -> void:
	var assemblies := 0
	var minimum_bearing_join := INF
	var minimum_foot_join := INF
	var displaced_controls := 0
	var outboard := DriveJournalArt.press_mesh()
	verify(outboard.get_aabb().position.is_equal_approx(Vector3(-0.085, -0.675, -0.085))
		and outboard.get_aabb().size.is_equal_approx(Vector3(0.17, 1.35, 0.17)),
		"Collector input ends preserve the established attachment planes and radial envelope.")
	verify(journal_section_radius(outboard, 0) == -INF
		and journal_section_radius(DriveJournalArt.mesh(1.35), 0) > 0.08,
		"Raw facets reject the former exposed cross-bed middle while retaining the old geometry as a negative control.")
	for shared_profile in [false, true]:
		for axis_index in [0, 2]:
			var axis: Vector3 = Vector3.RIGHT if axis_index == 0 else Vector3.BACK
			for cell in [[0, 0], [2, -1]]:
				var view: Variant = Shared.new() if shared_profile else Opening.new()
				view.machine_root = Node3D.new()
				view.add_child(view.machine_root)
				view.state = {"context": "collector-input-art", "options": {"native": true, "physical": true},
					"actors": {}, "parts": {}, "inventories": {}, "stock": {}, "remaining": 0,
					"entities": {"fixture": {"kind": "collector", "cell": cell, "axis": axis_index, "generation": 1}},
					"transmission_parts": {}, "motion": {}, "links": [], "drive_links": [], "engagements": []}
				var before: Dictionary = view.state.duplicate(true)
				view._rebuild_machines()
				var machine: Node3D = view.machine_root.get_child(0)
				var journal: MeshInstance3D = machine.get_node("DriveStub")
				var bed: MeshInstance3D = machine.get_node("StockBed")
				var bed_box: AABB = bed.transform * bed.mesh.get_aabb()
				verify(journal.mesh == outboard and journal_pose_matches(journal, axis_index)
					and machine.position.is_equal_approx(Vector3(cell[0] * Geometry.PITCH, 0, cell[1] * Geometry.PITCH)),
					"Both view builders keep the native input centre, axis and world-space construction origin.")
				var fixed_count := 0
				for child in machine.get_children():
					if child is MeshInstance3D and child.has_meta("collector_input_role"):
						fixed_count += 1
						verify(child.get_script() == null and child.get_child_count() == 0,
							"Collector input support is rigid presentation without a controller.")
						check_bounds(child, Transform3D.IDENTITY)
				verify(fixed_count == 6 and machine.get_meta("motion_meshes").size() == 10,
					"Two bearings, posts and feet add no motion callback or missing fixed part.")
				for side in [-1.0, 1.0]:
					var suffix := "Left" if side < 0 else "Right"
					var bearing: MeshInstance3D = machine.get_node("CollectorInputBearing" + suffix)
					var post: MeshInstance3D = machine.get_node("CollectorInputPost" + suffix)
					var foot: MeshInstance3D = machine.get_node("CollectorInputFoot" + suffix)
					verify(bearing.get_meta("collector_input_role") == "Bearing"
						and post.get_meta("collector_input_role") == "Post"
						and foot.get_meta("collector_input_role") == "Foot",
						"The complete outboard load path is individually identified.")
					var bearing_box: AABB = bearing.transform * bearing.mesh.get_aabb()
					var post_box: AABB = post.transform * post.mesh.get_aabb()
					var foot_box: AABB = foot.transform * foot.mesh.get_aabb()
					verify(not bearing_box.intersects(bed_box) and not post_box.intersects(bed_box)
						and foot_box.end.y < bed_box.position.y,
						"Bearings and posts clear the stock bed, and their feet pass beneath its working surface.")
					var bearing_join := press_input_overlap(bearing, post,
						axis * side * 0.66 + Vector3(0, -0.1, 0), axis * side * 0.66 + Vector3(0, 1, 0))
					var foot_join := press_input_overlap(foot, post,
						axis * side * 0.675 + Vector3(0, -0.1, 0), axis * side * 0.675 + Vector3(0, 1, 0))
					minimum_bearing_join = minf(minimum_bearing_join, bearing_join)
					minimum_foot_join = minf(minimum_foot_join, foot_join)
					verify(bearing_join > 0.005 and foot_join > 0.005,
						"Raw mesh probes connect each annular bearing to its cast post and skid foot.")
					if not shared_profile and cell == [0, 0] and side < 0:
						var original_post := post.position
						post.position += Vector3(0, 0, 0.25) if axis_index == 0 else Vector3(0.25, 0, 0)
						verify(press_input_overlap(bearing, post,
							axis * side * 0.66 + Vector3(0, -0.1, 0), axis * side * 0.66 + Vector3(0, 1, 0)) <= 0,
							"A displaced support cannot pass the bearing-contact control.")
						post.position = original_post
						displaced_controls += 1
				verify(view.state == before and view.model == null and view.actor_world == null
					and view.request_sequence == 0 and not view.is_inside_tree(),
					"Input presentation leaves material, authority, requests and native bodies untouched.")
				assemblies += 1
				view.free()
	verify(assemblies == 8 and displaced_controls == 2, "Both axes and view builders complete their support controls.")
	print(JSON.stringify({"phase": "collector input support", "assemblies": assemblies,
		"minimum_bearing_join_metres": minimum_bearing_join, "minimum_foot_join_metres": minimum_foot_join,
		"displaced_support_controls": displaced_controls, "native_gameplay": "not_run"}))

func check_drive_journals(geometry_checks: bool = true) -> void:
	var meshes: Dictionary = {}
	var assemblies := 0
	var geometry_observations: Array[Dictionary] = []
	for height in [0.9, 1.35]:
		var mesh := DriveJournalArt.mesh(height)
		meshes[height] = mesh
		if not geometry_checks:
			continue
		verify(mesh == DriveJournalArt.mesh(height) and mesh.get_surface_count() == 1,
			"Equal journal lengths reuse one passive mesh and one material surface.")
		verify(journal_shape_matches(mesh, height),
			"Raw facets preserve the full central bearing span, envelope, relieved bands, chamfered ends and two real center recesses.")
		check_closed_asset_mesh(mesh, 0.0198 if height < 1 else 0.0300, 0.0205 if height < 1 else 0.0307)
		var plain := CylinderMesh.new()
		plain.top_radius = 0.085
		plain.bottom_radius = 0.085
		plain.height = height
		plain.radial_segments = 48
		verify(not journal_shape_matches(plain, height),
			"A plain cylinder cannot pass the actual machining and recessed-end controls.")
		geometry_observations.append({"height": height, "bounds": str(mesh.get_aabb()),
			"central_radius": journal_section_radius(mesh, 0),
			"relief_radius": journal_section_radius(mesh, height / 2.0 - 0.051),
			"chamfer_radius": journal_section_radius(mesh, height / 2.0 - 0.007), "axis_hits": journal_center_hits(mesh)})
	var material := DriveJournalArt.material()
	if geometry_checks:
		verify(meshes[0.9] != meshes[1.35], "Different native journal lengths cannot alias a cached mesh.")
		verify(material == Opening.ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.38)
			and material != null and material.albedo_color == Color("a6b4af") and is_equal_approx(material.metallic, 0.85)
			and material.roughness_texture == Opening.ProductionTransmissionFinish.textures.worked_roughness
			and material.normal_texture == Opening.ProductionTransmissionFinish.textures.worked_normal
			and material.uv1_triplanar and not material.uv1_world_triplanar,
			"Exposed journals reuse the qualified worked steel finish and its local physical map scale.")
	for shared_profile in [false, true]:
		for kind in ["collector", "processor"]:
			for axis in range(3):
				for cell in [[0, 0], [2, -1]]:
					var view: Variant = Shared.new() if shared_profile else Opening.new()
					view.machine_root = Node3D.new()
					view.add_child(view.machine_root)
					view.state = {"context": "drive-journal-fixture", "options": {"native": true, "physical": true},
						"actors": {}, "parts": {}, "inventories": {}, "stock": {}, "remaining": 0,
						"entities": {"fixture": {"kind": kind, "cell": cell, "axis": axis, "generation": 1}},
						"transmission_parts": {}, "motion": {}, "links": [], "drive_links": [], "engagements": []}
					var before: Dictionary = view.state.duplicate(true)
					view._rebuild_machines()
					var machine: Node3D = view.machine_root.get_child(0)
					var journal: MeshInstance3D = machine.get_node("DriveStub")
					var height := 0.9 if axis == 1 else 1.35
					var expected_mesh: ArrayMesh = DriveJournalArt.press_mesh() if axis != 1 else meshes[height]
					verify(journal.mesh == expected_mesh and journal.material_override == material
						and journal.get_child_count() == 0 and journal.get_script() == null and journal_pose_matches(journal, axis),
						"Both view builders mount the fitted journal variant on the existing native centre and confirmed axis.")
					verify(machine.position.is_equal_approx(Vector3(cell[0] * 1.65, 0, cell[1] * 1.65)),
						"Translated constructions retain the common world-space grid origin and height.")
					if geometry_checks:
						check_bounds(journal, Transform3D.IDENTITY)
						var picks := 0
						for child in machine.get_children():
							if child is StaticBody3D:
								picks += 1
								verify(child.collision_layer == 4 and child.collision_mask == 0 and child.get_child_count() == 1
									and child.get_child(0).shape.size == Vector3(1.45, 1.65, 1.45)
									and child.get_child(0).position == Vector3(0, 0.8, 0),
									"The sole conservative pick body keeps its original dimensions, center and masks.")
						var rows: Array = machine.get_meta("motion_meshes")
						var original_rows := 10 if kind == "collector" else 2
						var journal_fixed := rows.size() == original_rows
						for row in rows:
							journal_fixed = journal_fixed and row.node != journal
						verify(picks == 1 and journal_fixed,
							"The journal gains neither another pick body nor a fabricated rotation callback.")
					var pose := journal.position
					journal.position.x += 0.01
					verify(not journal_pose_matches(journal, axis), "A displaced journal is rejected even when its own mesh is valid.")
					journal.position = pose
					if geometry_checks:
						verify(view.state == before and view.model == null and view.actor_world == null
							and view.request_sequence == 0 and not view.is_inside_tree(),
							"Mesh assembly leaves material projection, authority, input and native bodies untouched.")
					assemblies += 1
					view.free()
	print(JSON.stringify({"phase": "machine drive journals", "assemblies": assemblies,
		"cached_meshes": meshes.size(), "geometry": geometry_observations,
		"geometry_checks": geometry_checks, "negative_control_types": 2 if geometry_checks else 1,
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
			verify(source.mesh == WheelArt.hub_spokes_mesh and source.material_override == WheelArt.centre_finish
				and source.transform == Transform3D.IDENTITY and source.get_child_count() == 0,
				"The separated hub and spokes keep their sourced atlas and rigid center.")
			check_split_wheel_rims(rotor)
			print(JSON.stringify({"phase": "paddle mount observation", "shared_class": shared_profile, "axis": axis,
				"center": [rotor.position.x, rotor.position.y, rotor.position.z],
				"axis_vector": [rotor.basis.z.normalized().x, rotor.basis.z.normalized().y, rotor.basis.z.normalized().z]}))
			verify(rotor.position.is_equal_approx(Vector3.UP * Geometry.ANCHOR_HEIGHT)
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
						"PaddleIronStrap": [0.0000095, 0.0000106], "PaddleBolt": [0.0000042, 0.0000046]}[role]
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
									aligned = aligned and uv[n].is_equal_approx(Vector2(positions[n].x * rotor.scale.x, positions[n].z * rotor.scale.z))
							verify(aligned and broad_faces > 0, "The actual broad blade UVs retain axial grain V at the declared physical repeat.")
					verify(part.mesh == cached[role][0] and part.material_override == cached[role][1],
						"All blade assemblies reuse their exact role-specific mesh and material resources.")
					var material := part.material_override as StandardMaterial3D
					verify(material != null and (material == PaddleArt.finish if role in ["WheelPaddle", "PaddleRootCleat"]
						else is_equal_approx(material.metallic, 0.85) and material.albedo_color == Color("46504e")),
						"Timber and attachment iron retain distinct actual material bindings.")
				if not shared_profile and axis == 0:
					var contact := wheel_root_rim_contact(rotor, child)
					root_counts.append(contact.x)
					verify(contact.x > 0 and contact.y == 0,
						"Actual rim triangle bounds meet every cleat's narrow attachment box; a radial displacement is rejected.")
			verify(blades == 12 and PaddleArt.source_status == ("missing" if historical else "ready"),
				"The ordinary builder keeps exactly twelve paddles and the declared source qualification.")
			var base := rotor.basis
			for sample in range(24):
				rotor.basis = base * Basis(Vector3.BACK, float(sample) * TAU / 24)
				check_native_wheel_bounds(rotor, Transform3D.IDENTITY,
					[Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis])
			rotor.basis = base
			view._animate_wheel(0.1)
			verify(rotor.basis.is_equal_approx(base * Basis(Vector3.BACK,
				view.transmission_presenter.visual_angle("fixture"))) and view.state == before,
				"The complete paddle assembly consumes the presenter's cosmetic angle without changing native observations.")
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
		"historical_missing_set": historical, "rim_triangle_boxes_inside_each_root": root_counts,
		"observations": "invented", "native_gameplay": "not_run"}))

func point_triangle_distance(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	var area := absf((b - a).cross(c - a))
	if area > 0.00000001 and Geometry2D.is_point_in_polygon(point, PackedVector2Array([a, b, c])):
		return 0.0
	return minf(point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)),
		minf(point.distance_to(Geometry2D.get_closest_point_to_segment(point, b, c)),
		point.distance_to(Geometry2D.get_closest_point_to_segment(point, c, a))))

func collector_tooling_extent(mesh: Mesh) -> Vector2:
	var radius_squared := 0.0
	var half_height := 0.0
	for surface in range(mesh.get_surface_count()):
		var points: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for point in points:
			radius_squared = maxf(radius_squared, point.x * point.x + point.z * point.z)
			half_height = maxf(half_height, absf(point.y))
	return Vector2(sqrt(radius_squared), half_height)

func collector_clearance(frame: Node3D, moving: Array) -> float:
	var minimum := INF
	var rotary_extents: Dictionary = {}
	for row in moving:
		var node: MeshInstance3D = row.node
		if node.mesh is CylinderMesh:
			var cylinder := node.mesh as CylinderMesh
			rotary_extents[node] = Vector2(cylinder.top_radius, cylinder.height / 2)
		elif node.get_meta("collector_tooling_role", "") in ["BoredDrum", "SteppedHub"]:
			rotary_extents[node] = collector_tooling_extent(node.mesh)
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
				if rotary_extents.has(node):
					# The native tooling stays inside a raw-vertex cylinder about
					# the same Z axis. Do not fill the fixed bearing's empty bore.
					var extent: Vector2 = rotary_extents[node]
					var center := transform.origin
					var radial := point_triangle_distance(Vector2(center.x, center.y),
						Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y)) - extent.x
					var axial := maxf(low.z - center.z - extent.y, center.z - extent.y - high.z)
					gap = maxf(radial, axial)
				else:
					# Conservative transformed flute bounds, sampled over a turn.
					var box: AABB = transform * node.mesh.get_aabb()
					gap = maxf(maxf(maxf(low.x - box.end.x, box.position.x - high.x),
						maxf(low.y - box.end.y, box.position.y - high.y)),
						maxf(low.z - box.end.z, box.position.z - high.z))
				minimum = minf(minimum, gap)
	return minimum

func collector_feed_fit(feed: Node3D, bed: MeshInstance3D) -> bool:
	if feed.get_child_count() != 10:
		return false
	var top := bed.position.y + bed.mesh.get_aabb().end.y
	var bed_edge := bed.mesh.get_aabb().end.z
	var rails: Array[MeshInstance3D] = []
	var clamps: Array[MeshInstance3D] = []
	var heads: Array[MeshInstance3D] = []
	for child in feed.get_children():
		if not child is MeshInstance3D:
			return false
		match child.get_meta("collector_feed_role", ""):
			"FormedGuide": rails.append(child)
			"GuideClamp": clamps.append(child)
			"ClampHead": heads.append(child)
			_: return false
	if rails.size() != 2 or clamps.size() != 4 or heads.size() != 4:
		return false
	var inner_faces: Array[float] = []
	for rail in rails:
		var box: AABB = rail.mesh.get_aabb()
		if absf(rail.position.y + box.position.y - top) > 0.0001:
			return false
		var inner := rail.position.z - signf(rail.position.z) * box.size.z / 2.0
		if absf(inner) > bed_edge or absf(inner) < 0.29:
			return false
		inner_faces.append(inner)
	if absf(inner_faces[1] - inner_faces[0]) < 0.58:
		return false
	for clamp in clamps:
		var box: AABB = clamp.mesh.get_aabb()
		var low := clamp.position + box.position
		var high := clamp.position + box.end
		if low.y >= top or high.y <= top or high.y < rails[0].mesh.get_aabb().position.y:
			return false
		if absf(clamp.position.z) - box.size.z / 2.0 >= bed_edge:
			return false
		if absf(clamp.position.z - rails[0].position.z) > 0.001 \
				and absf(clamp.position.z - rails[1].position.z) > 0.001:
			return false
	for head in heads:
		var bottom := head.position.y + head.scale.y * head.mesh.get_aabb().position.y
		if absf(bottom - rails[0].mesh.get_aabb().end.y) > 0.0001:
			return false
	return true

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
		var feed: Node3D = machine.get_node("CollectorFeedGuides")
		verify(machine.get_node_or_null("StockGuide") == null and collector_feed_fit(feed, bed),
			"Both formed guides leave a clear lane and their clamps seat on the original bed.")
		check_bounds(feed, Transform3D.IDENTITY)
		if axis == 0:
			var clamp: MeshInstance3D = feed.get_child(1)
			clamp.position.y += 0.12
			verify(not collector_feed_fit(feed, bed), "The feed fit check rejects a detached clamp.")
			clamp.position.y -= 0.12
			var rail: MeshInstance3D = feed.get_child(0)
			rail.position.z += 0.10
			verify(not collector_feed_fit(feed, bed), "The feed fit check rejects a guide outside the bed edge.")
			rail.position.z -= 0.10
			verify(collector_feed_fit(feed, bed), "The original clamp fit is restored.")
		if axis == 0:
			var hood: MeshInstance3D = frame.get_node("CastUpperHood")
			var vertices: PackedVector3Array = hood.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var crown := -INF
			var left_shoulder := -INF
			var right_shoulder := -INF
			for point in vertices:
				if point.x > -0.26 and point.x < -0.12:
					crown = maxf(crown, point.y)
				elif point.x < -0.60:
					left_shoulder = maxf(left_shoulder, point.y)
				elif point.x > 0.20:
					right_shoulder = maxf(right_shoulder, point.y)
			verify(crown > 1.52 and crown - maxf(left_shoulder, right_shoulder) > 0.04
				and hood.material_override == CollectorArt.coating(Color("394f59")),
				"The formed hood has a raised crown over both dark-coated shoulders rather than a bright flat canopy.")
		var rows: Array = machine.get_meta("motion_meshes")
		verify(rows.size() == 10 and count_role(machine, "CutterFlute") == 8,
			"Only the original drum, hub and eight flutes belong to the moving group.")
		var drum: MeshInstance3D = machine.get_node("CutterDrum")
		var hub: MeshInstance3D = machine.get_node("CutterHub")
		verify(drum.position == Vector3(-0.22, 1.1, -0.19) and collector_tooling_extent(drum.mesh).is_equal_approx(Vector2(0.24, 0.17))
			and hub.position == Vector3(-0.22, 1.1, 0.01) and collector_tooling_extent(hub.mesh).is_equal_approx(Vector2(0.085, 0.04)),
			"The current native tooling keeps the original literal radial and axial clearance envelopes and centres.")
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
		# One tile per 0.45-second native tick turns the 0.1425-metre pulley rim.
		var expected_angle := 0.1 * Geometry.PITCH / (0.45 * 0.1425)
		verify(is_equal_approx(view.transmission_presenter.visual_angle("fixture"), expected_angle),
			"The fixed collector frame stays still while its cosmetic cutter angle follows confirmed belt travel.")
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

func check_native_wheel_bounds(node: Node3D, parent_pose: Transform3D, axis: Vector3, tiles: int = 3) -> void:
	var pose := parent_pose * node.transform
	verify(not node is CollisionObject3D and not node is CollisionShape3D,
		"Wheel artwork has no collision or construction authority.")
	if node is MeshInstance3D:
		detail_meshes += 1
		var box: AABB = node.mesh.get_aabb()
		var bounded := true
		for n in range(8):
			var point := pose * box.get_endpoint(n) - Vector3.UP * Geometry.ANCHOR_HEIGHT
			var axial := point.dot(axis)
			var radial := (point - axis * axial).length()
			bounded = bounded and point.is_finite() and absf(axial) <= Geometry.PITCH / 2.0 + 0.00001
			# A mesh AABB corner can be outside the circular rotor even when
			# its vertices fit; the enclosing square is the conservative bound.
			bounded = bounded and radial <= Geometry.WATERWHEEL_RADIUS * float(tiles) * sqrt(2.0) + 0.00001
		verify(bounded, "Each actual wheel mesh stays within its selected rotor envelope.")
	for child in node.get_children():
		if child is Node3D:
			check_native_wheel_bounds(child, pose, axis, tiles)

func count_role(node: Node, role: String) -> int:
	var count := 1 if node.get_meta("detail_role", "") == role else 0
	for child in node.get_children():
		count += count_role(child, role)
	return count

func wheel_source_radial_extents(mesh: Mesh) -> Vector2:
	var low := INF
	var high := 0.0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in vertices:
		var radius := Vector2(point.x, point.y).length()
		low = minf(low, radius)
		high = maxf(high, radius)
	return Vector2(low, high)

func wheel_root_rim_contact(rotor: Node3D, blade: MeshInstance3D) -> Vector2i:
	var inverse: Transform3D = blade.transform.affine_inverse()
	var cleat: MeshInstance3D = blade.get_child(0)
	var inside := 0
	var displaced := 0
	for side: String in ["N", "P"]:
		var rim: MeshInstance3D = rotor.get_node("SourcedTimberRim" + side)
		var arrays := rim.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for n in range(0, indices.size(), 3):
			var low := Vector3(INF, INF, INF)
			var high := Vector3(-INF, -INF, -INF)
			for corner in range(3):
				var point: Vector3 = inverse * (rim.transform * vertices[indices[n + corner]]) - cleat.position
				low = low.min(point)
				high = high.max(point)
			if low.x < 0.015 and high.x > -0.015 and low.y < 0.025 and high.y > -0.025 \
				and low.z < 0.045 and high.z > -0.045:
				inside += 1
			if low.x < -0.185 and high.x > -0.215 and low.y < 0.025 and high.y > -0.025 \
				and low.z < 0.045 and high.z > -0.045:
				displaced += 1
	return Vector2i(inside, displaced)

func check_split_wheel_rims(rotor: Node3D, tiles: int = 3) -> void:
	for side: String in ["N", "P"]:
		var rim := rotor.get_node_or_null("SourcedTimberRim" + side) as MeshInstance3D
		verify(rim != null, "Each side of the waterwheel has its own sourced rim instance.")
		if rim == null:
			continue
		var offset := -0.08 if side == "N" else 0.08
		verify(rim.mesh == WheelArt.rim_for_tiles(tiles) and rim.material_override == WheelArt.finish
			and rim.position.is_equal_approx(Vector3(0, 0, offset))
			and rim.basis == Basis.IDENTITY and rim.get_script() == null and rim.get_child_count() == 0,
			"Both sourced rims share one mesh and material at the exact symmetric axial seats.")
	verify(count_role(rotor, "SourcedTimberRim") == 2 and count_role(rotor, "WheelRim") == 0,
		"The split source replaces the procedural rims without creating a third wheel silhouette.")

func check_sourced_mesh(instance: MeshInstance3D, expected_vertices: int = 4056,
		expected_triangles: int = 6702, expected_radius: float = 0.524) -> void:
	verify(instance.get_script() == null and instance.get_child_count() == 0,
		"The sourced rotor is a plain mesh without a controller, skeleton or physical children.")
	var arrays := instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var coordinates: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	verify(vertices.size() == expected_vertices and indices.size() == expected_triangles * 3,
		"The loaded mesh contains exactly its selected source components.")
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
	verify(absf(radius - expected_radius) < 0.002 and instance.mesh.get_aabb().size.z < 0.14,
		"The source component has its declared radial and axial envelope, without the stand or drive belt.")
	var minimum_v_span := 0.35 if expected_vertices == 1576 else 0.7
	verify((uv_high - uv_low).x > 0.7 and (uv_high - uv_low).y > minimum_v_span,
		"The original atlas coordinates retain a nontrivial surface footprint.")
	var material := instance.material_override as StandardMaterial3D
	var centre := instance.name == "SourcedTimberRotor"
	verify(material != null and material == (WheelArt.centre_finish if centre else WheelArt.finish),
		"The rim and center reuse their separate cached source-derived materials.")
	if material == null:
		return
	if centre:
		verify(material != WheelArt.finish and material.albedo_color == Color.WHITE
			and material.albedo_texture != WheelArt.finish.albedo_texture
			and material.normal_texture == WheelArt.finish.normal_texture
			and material.roughness_texture == WheelArt.finish.roughness_texture
			and material.metallic_texture == WheelArt.finish.metallic_texture
			and material.ao_texture == WheelArt.finish.ao_texture,
			"The center changes only its qualified color atlas; source normals and packed surface channels remain shared.")
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

func check_wheel_resource_contract() -> void:
	var current := ["rim.gltf", "rim.bin", "hub_spokes.gltf", "hub_spokes.bin",
		"wood_albedo.jpg", "wood_normal.webp", "wood_arm.webp"]
	var rosters := [
		["rotor.gltf", "rotor.bin", "wood_albedo.jpg", "wood_normal.webp", "wood_arm.webp"],
		current, current.slice(0, current.size() - 1)]
	for index in range(rosters.size()):
		var directory := "user://wheel-roster-contract-" + str(index)
		verify(DirAccess.make_dir_recursive_absolute(directory) == OK,
			"Resource admission uses a fresh owned synthetic roster.")
		for name_value: String in rosters[index]:
			var file := FileAccess.open(directory.path_join(name_value), FileAccess.WRITE)
			if file == null:
				verify(false, "The synthetic roster file can be created.")
				return
			file.close()
		verify(WheelArt.resource_status(directory) == ("complete" if index == 1 else "incomplete"),
			"Only the current complete two-rim runtime roster is admitted; obsolete or partial rosters refuse.")
	verify(WheelArt.resource_status("user://wheel-roster-contract-missing") == "missing",
		"Entirely missing resources remain distinct from an obsolete or partial set.")

func check_wheel_axes() -> void:
	verify(WheelArt.resource_status() == "complete", "The current two-rim source set is present in this captured project.")
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
			check_split_wheel_rims(rotor)
			for side: String in ["N", "P"]:
				var rim := rotor.get_node_or_null("SourcedTimberRim" + side) as MeshInstance3D
				if rim != null:
					check_sourced_mesh(rim, 1576, 1872, 0.57)
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
		verify(hub.mesh is ArrayMesh and hub.position == Vector3.ZERO
			and journal_shape_matches(hub.mesh, 0.45 * Geometry.WATERWHEEL_RADIUS / 0.70,
				0.13 * 0.5 / 0.78),
			"The existing worked journal keeps its native axial form at the wheel center.")
		var bearings := 0
		for child in anchor.get_children():
			if child is MeshInstance3D and str(child.name).begins_with("AxleBearing"):
				bearings += 1
				verify(child.mesh is ArrayMesh and child.get_meta("wheel_support_role", "") == "AxleBearing"
					and absf(child.basis.y.normalized().dot(axis)) > 0.99999,
					"The open bearing follows its actual projected axle.")
		verify(bearings == (1 if axis_index == 1 else 2), "The original vertical and horizontal bearing layouts remain intact.")
		check_native_wheel_bounds(rotor, Transform3D.IDENTITY, axis)
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
	var file := FileAccess.open(partial.path_join("rim.gltf"), FileAccess.WRITE)
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
					* (Geometry.ANCHOR_HEIGHT / 0.78 if native_profile else 1.0)):
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
					verify(is_equal_approx(absf(child.position.z), 0.36)
						and is_equal_approx(child.position.y, 0.355 if anchor.get_meta("conveyor_frame", false) else 0.43),
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

func prepare_wheel_center_color() -> void:
	const SOURCE := "res://opening/assets/waterwheel/wood_albedo.jpg"
	const SOURCE_SHA256 := "b81f7849d93841e34c68292a26cb7825ceeff204b51717c3703b6c6a0b86450e"
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2 or not arguments[1].is_absolute_path() \
		or FileAccess.file_exists(arguments[1]) or FileAccess.get_sha256(SOURCE) != SOURCE_SHA256:
		push_error("Supply a fresh absolute output path and the pinned original wheel color atlas.")
		quit(1)
		return
	var source := Image.load_from_file(SOURCE)
	if source == null or source.get_size() != Vector2i(1024, 1024):
		push_error("The original wheel color atlas is missing or has changed dimensions.")
		quit(1)
		return
	var output := source.duplicate() as Image
	var dark_count := 0
	var total_lift := 0.0
	for y in range(output.get_height()):
		for x in range(output.get_width()):
			var color := source.get_pixel(x, y)
			var luminance := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			var weight := pow(1.0 - luminance, 2.0)
			var tint := Color(0.18, 0.11, 0.06) * weight
			output.set_pixel(x, y, Color(minf(color.r + tint.r, 1.0),
				minf(color.g + tint.g, 1.0), minf(color.b + tint.b, 1.0)))
			if luminance < 0.2:
				dark_count += 1
			total_lift += tint.r * 0.2126 + tint.g * 0.7152 + tint.b * 0.0722
	if output.save_webp(arguments[1], true, 0.82) != OK:
		push_error("Cannot save the center-only color candidate.")
		quit(1)
		return
	print(JSON.stringify({"source": "wood_albedo.jpg", "width": output.get_width(),
		"height": output.get_height(), "dark_pixels": dark_count,
		"mean_luma_lift": total_lift / float(output.get_width() * output.get_height()),
		"output_sha256": FileAccess.get_sha256(arguments[1])}))
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

func die_faces(mesh: Mesh, surface: int) -> PackedVector3Array:
	# Use raw arrays: the TriangleMesh convenience cache snaps fine geometry.
	var arrays := mesh.surface_get_arrays(surface)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		return points
	var faces := PackedVector3Array()
	for index in indices:
		faces.append(points[index])
	return faces

func die_height(mesh: Mesh, surface: int, pose: Transform3D, probe: Vector2, up: bool) -> float:
	var result := -INF if up else INF
	var faces := die_faces(mesh, surface)
	for n in range(0, faces.size(), 3):
		var a: Vector3 = pose * faces[n]
		var b: Vector3 = pose * faces[n + 1]
		var c: Vector3 = pose * faces[n + 2]
		var cross := (b - a).cross(c - a)
		if absf(a.y - b.y) > 0.0000001 or absf(a.y - c.y) > 0.0000001 or cross.y * (1.0 if up else -1.0) >= 0.0:
			continue
		var p := Vector2(a.x, a.z)
		var q := Vector2(b.x, b.z)
		var r := Vector2(c.x, c.z)
		var sides := [(q - p).cross(probe - p), (r - q).cross(probe - q), (p - r).cross(probe - r)]
		if not ((sides[0] >= -0.000000001 and sides[1] >= -0.000000001 and sides[2] >= -0.000000001)
			or (sides[0] <= 0.000000001 and sides[1] <= 0.000000001 and sides[2] <= 0.000000001)):
			continue
		result = maxf(result, a.y) if up else minf(result, a.y)
	return result

func die_box_gap(a: AABB, b: AABB) -> float:
	return maxf(maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x),
		maxf(a.position.y - b.end.y, b.position.y - a.end.y)), maxf(a.position.z - b.end.z, b.position.z - a.end.z))

func die_supports(machine: Node3D, rib: MeshInstance3D) -> bool:
	var deck: MeshInstance3D = machine.get_node("Plinth")
	var anvil: MeshInstance3D = machine.get_node("Anvil")
	var probe := Vector2(rib.position.x, rib.position.z)
	var base := die_height(rib.mesh, 0, rib.transform, probe, false)
	var top := die_height(rib.mesh, 0, rib.transform, probe, true)
	var deck_top := die_height(deck.mesh, 0, deck.transform, probe, true)
	var anvil_base := die_height(anvil.mesh, 0, anvil.transform, probe, false)
	return is_finite(base) and is_finite(top) and is_finite(deck_top) and is_finite(anvil_base) \
		and absf(base - deck_top) < 0.000001 and absf(top - anvil_base) < 0.000001

func die_materials(part: MeshInstance3D, color: Color) -> bool:
	return part.material_override == null and part.get_surface_override_material(0) == CollectorArt.coating(color) \
		and part.get_surface_override_material(1) == Opening.ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.32) \
		and part.get_surface_override_material(2) == Opening.ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.85, 0.38)

func check_press_die() -> void:
	var cache: Dictionary = {}
	var assemblies := 0
	var controls := 0
	var minimum_item_gap := INF
	var minimum_drive_gap := INF
	var press_cartridge: Mesh = DieArt.tool_mesh()
	var cutter_sample: Mesh = DieArt.tool_mesh("cut_sample")
	verify(press_cartridge != null and cutter_sample != null and press_cartridge != cutter_sample
		and DieArt.tool_mesh("cut_sample") == cutter_sample and DieArt.tool_mesh("unsupported") == null,
		"The installed press and disclosed cutter sample are distinct cached heads; unsupported tools have no art substitute.")
	if press_cartridge != null and cutter_sample != null:
		verify(cutter_sample.get_surface_count() == 3
			and cutter_sample.surface_get_name(1) == "WorkingFace"
			and cutter_sample.surface_get_arrays(0) == press_cartridge.surface_get_arrays(0)
			and cutter_sample.surface_get_arrays(2) == press_cartridge.surface_get_arrays(2),
			"Both complete tool heads have the same actual carrier and locking hardware mesh data.")
		verify(cutter_sample.get_aabb().size.x == press_cartridge.get_aabb().size.x
			and cutter_sample.get_aabb().size.y == press_cartridge.get_aabb().size.y
			and cutter_sample.get_aabb().size.z < press_cartridge.get_aabb().size.z,
			"The sample changes the working insert inside the same rigid mount envelope.")
		verify(absf(die_height(cutter_sample, 1, Transform3D.IDENTITY, Vector2.ZERO, false) + 0.085) < 0.000001
			and die_height(cutter_sample, 1, Transform3D.IDENTITY, Vector2(0, 0.05), false) > -0.07
			and not is_finite(die_height(cutter_sample, 1, Transform3D.IDENTITY, Vector2(0, 0.20), false))
			and is_finite(die_height(press_cartridge, 1, Transform3D.IDENTITY, Vector2(0, 0.20), false)),
			"A narrow cutter edge has the same lower reference plane but cannot masquerade as the full press face.")
		for cartridge in [press_cartridge, cutter_sample]:
			verify(absf(die_height(cartridge, 2, Transform3D.IDENTITY, Vector2(0.27, 0), true) - 0.055) < 0.000001
				and absf(die_height(cartridge, 2, Transform3D.IDENTITY, Vector2(0, 0.255), true) - 0.0575) < 0.000001,
				"Actual side rails and end locks are present on both cartridge meshes, rather than only in their source builder.")
		var cutter_face := SurfaceTool.new()
		cutter_face.create_from(cutter_sample, 1)
		check_closed_asset_mesh(cutter_face.commit(), 0.0015, 0.0018)
		var cutter_hardware := SurfaceTool.new()
		cutter_hardware.create_from(cutter_sample, 2)
		check_closed_asset_mesh(cutter_hardware.commit(), 0.0020, 0.0025)
	for shared_profile in [false, true]:
		for axis in range(3):
			for cell in [[0, 0], [2, -1]]:
				var view: Variant = Shared.new() if shared_profile else Opening.new()
				view.client = "P"
				if shared_profile:
					view.session = PaddleSessionFacts.new()
				view.machine_root = Node3D.new()
				view.item_root = Node3D.new()
				view.add_child(view.machine_root)
				view.add_child(view.item_root)
				view.state = {"context": "press-die-fixture", "options": {"native": true, "physical": true},
					"actors": {"P": {"ready": true}}, "parts": {}, "inventories": {"P": 0},
					"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0}, "remaining": 0,
					"entities": {"fixture": {"kind": "processor", "cell": cell, "axis": axis, "generation": 1}},
					"transmission_parts": {}, "motion": {}, "links": [], "drive_links": [], "engagements": []}
				view.transmission_presenter = Presenter.new()
				view.add_child(view.transmission_presenter)
				view.transmission_presenter.configure(view)
				var before: Dictionary = view.state.duplicate(true)
				view._rebuild_machines()
				var machine: Node3D = view.machine_root.get_child(0)
				var head: MeshInstance3D = machine.get_node("ToolHead")
				var anvil: MeshInstance3D = machine.get_node("Anvil")
				var piston: MeshInstance3D = machine.get_node("Piston")
				var drive: MeshInstance3D = machine.get_node("DriveStub")
				var ribs: Array[MeshInstance3D] = [machine.get_node("AnvilPedestalLeft"), machine.get_node("AnvilPedestalRight")]
				verify(head.mesh == DieArt.tool_mesh() and anvil.mesh == DieArt.anvil_mesh()
					and head.position.is_equal_approx(Vector3(0, 0.84, 0)) and anvil.position == Vector3(0, 0.46, 0.05),
					"The ordinary native builder mounts the die and saddle at their literal original centres.")
				verify(head.mesh.get_aabb().size.is_equal_approx(Vector3(0.56, 0.17, 0.55))
					and anvil.mesh.get_aabb().size.is_equal_approx(Vector3(0.7, 0.16, 0.63)),
					"The new complete head and anvil keep the exact original local envelopes.")
				verify(die_materials(head, Color("58634c")) and die_materials(anvil, Color("394a44")),
					"Coated holders, exposed working faces and hardware use their separate cached qualified finishes.")
				for part in [head, anvil]:
					var is_head: bool = part == head
					var role := "head" if is_head else "anvil"
					verify(part.mesh.get_surface_count() == 3 and part.mesh.surface_get_name(1) == "WorkingFace"
						and part.mesh.surface_get_name(2) == "MountingHardware" and part.get_child_count() == 0 and part.get_script() == null,
						"Each rigid tool keeps three material surfaces in one passive cached mesh, without extra controllers or detail-node motion.")
					if not cache.has(role):
						var volumes: Array = [[0.030, 0.036], [0.013, 0.014], [0.0020, 0.0025]] if is_head else [[0.039, 0.0401], [0.010, 0.011], [0.0003, 0.0006]]
						for surface in range(3):
							var isolated := SurfaceTool.new()
							isolated.create_from(part.mesh, surface)
							check_closed_asset_mesh(isolated.commit(), volumes[surface][0], volumes[surface][1])
						cache[role] = part.mesh
					verify(part.mesh == cache[role], "Every axis and both ordinary view classes reuse the same complete tool geometry.")
				var rows: Array = machine.get_meta("motion_meshes")
				verify(rows.size() == 2 and rows[0].node == head and rows[1].node == piston,
					"Only the original head and piston consume the existing observed travel.")
				var fixed: Array[Transform3D] = [anvil.transform, ribs[0].transform, ribs[1].transform]
				for rib in ribs:
					verify(rib.mesh == DieArt.pedestal_mesh() and rib.get_script() == null and rib.get_child_count() == 0
						and rib.material_override == CollectorArt.coating(Color("394a44")) and die_supports(machine, rib),
						"Fixed cast ribs meet the actual skid top and anvil bottom across the original visible support gap.")
					if not cache.has("rib"):
						check_closed_asset_mesh(rib.mesh, 0.0044, 0.0049)
						cache.rib = rib.mesh
					var gap := die_box_gap(rib.transform * rib.mesh.get_aabb(), drive.transform * drive.mesh.get_aabb())
					minimum_drive_gap = minf(minimum_drive_gap, gap)
					verify(gap > 0.02, "The added support clears the unchanged drive journal on every native axis.")
					check_bounds(rib, Transform3D.IDENTITY)
				var picks := 0
				for child in machine.get_children():
					if child is StaticBody3D:
						picks += 1
						verify(child.collision_layer == Geometry.PICK_LAYER and child.collision_mask == 0
							and child.get_meta("entity") == "fixture" and child.get_child_count() == 1
							and child.get_child(0).shape.size == Vector3(1.45, 1.65, 1.45)
							and child.get_child(0).position == Vector3(0, 0.8, 0),
							"The sole original entity pick keeps its identity, dimensions, centre and masks.")
				verify(picks == 1 and view.state == before, "Passive assembly adds no state, extra pick body or material action.")
				for travel in [0.0, 0.0075, 0.015]:
					view._apply_press_pose(rows, travel)
					var head_plane := die_height(head.mesh, 1, head.transform, Vector2.ZERO, false)
					var anvil_plane := die_height(anvil.mesh, 1, anvil.transform, Vector2.ZERO, true)
					verify(absf(head_plane - (0.755 - travel)) < 0.000001 and absf(anvil_plane - 0.54) < 0.000001,
						"Actual centre working faces retain the old literal lower die and upper anvil planes at both endpoints and the intermediate pose.")
					verify(anvil.transform == fixed[0] and ribs[0].transform == fixed[1] and ribs[1].transform == fixed[2]
						and is_equal_approx((piston.transform * piston.mesh.get_aabb()).end.y, 1.365),
						"The saddle, pedestal and original rod top stay fixed while the complete die follows its existing motion anchor.")
				view._apply_press_pose(rows, 0.0)
				view.state.stock.source = 15
				view.state.stock.held = 1
				before = view.state.duplicate(true)
				view._redraw_items()
				view._animate_machine_bodies(0.1)
				view._animate_machine_bodies(0.1)
				var working_plane := die_height(head.mesh, 1, head.transform, Vector2.ZERO, false)
				var item_top := -INF
				var billets := 0
				var bosses := 0
				var boss_covered := true
				for item in view.item_root.get_children():
					if item.get_meta("item_kind", "") != "workpiece_billet":
						continue
					billets += 1
					item_top = maxf(item_top, feed_item_bounds(item, Transform3D.IDENTITY).end.y)
					for part in item.get_children():
						if not part is MeshInstance3D or part.get_meta("asset_role", "") != "CenterBoss":
							continue
						bosses += 1
						var bounds: AABB = machine.transform.affine_inverse() * item.transform * part.transform * part.mesh.get_aabb()
						for x in [bounds.position.x, bounds.end.x]:
							for z in [bounds.position.z, bounds.end.z]:
								boss_covered = boss_covered and absf(die_height(head.mesh, 1, head.transform, Vector2(x, z), false) - working_plane) < 0.000001
				var item_gap := working_plane + machine.position.y - item_top
				minimum_item_gap = minf(minimum_item_gap, item_gap)
				verify(billets == 1 and bosses == 1 and boss_covered and is_finite(item_top) and item_gap >= 0.002 and is_equal_approx(head.position.y, 0.825),
					"The ordinary observed held-work path lowers the complete die while clearing the actual redrawn billet and its boss.")
				view.explanation_open = true
				var paused := head.transform
				view._animate_machine_bodies(0.1)
				verify(head.transform == paused, "Unavailable presentation cannot keep moving the die.")
				view.explanation_open = false
				verify(view.state == before and view.request_sequence == 0 and view.model == null and view.actor_world == null,
					"Both actual view classes retain the invented projection without starting authority, requests or bodies.")
				if controls == 0:
					head.position.y -= 0.02
					verify(die_height(head.mesh, 1, head.transform, Vector2.ZERO, false) + machine.position.y - item_top < 0.002,
						"The same working-face oracle rejects a die displaced into the real held billet.")
					head.transform = paused
					ribs[0].position.y += 0.01
					verify(not die_supports(machine, ribs[0]), "A floating pedestal fails the same actual support-plane oracle.")
					ribs[0].transform = fixed[1]
					var material := head.get_surface_override_material(0)
					head.set_surface_override_material(0, head.get_surface_override_material(1))
					verify(not die_materials(head, Color("58634c")), "A uniform metal substitution cannot pass the coating and working-face separation.")
					head.set_surface_override_material(0, material)
					controls = 3
				view.state.stock.held = 0
				view.state.stock.source = 16
				view._animate_machine_bodies(0.1)
				view._animate_machine_bodies(0.1)
				verify(head.position.is_equal_approx(Vector3(0, 0.84, 0)), "The unchanged observed empty state returns the entire die to its original rest pose.")
				view.state.entities.fixture.generation = 2
				view._rebuild_machines()
				var rebuilt: Node3D = view.machine_root.get_child(0)
				verify(rebuilt.get_node("ToolHead").mesh == cache.head and rebuilt.get_node("Anvil").mesh == cache.anvil
					and rebuilt.get_node("AnvilPedestalLeft").mesh == cache.rib,
					"Removal and rebuilding reuse passive geometry without carrying an old moving instance into a new generation.")
				assemblies += 1
				view.free()
	var historical := Opening.new()
	historical.legacy_fixture = true
	var root_node := Node3D.new()
	historical._press_visual(root_node)
	verify(root_node.get_node("ToolHead").mesh == Visuals.box_mesh(Vector3(0.56, 0.17, 0.55))
		and root_node.get_node("Anvil").mesh == Visuals.box_mesh(Vector3(0.7, 0.16, 0.63))
		and root_node.get_node_or_null("AnvilPedestalLeft") == null,
		"The historical fixture retains its previous head and anvil rather than receiving an unclaimed native-art result.")
	root_node.free()
	historical.free()
	print(JSON.stringify({"assemblies": assemblies, "axes": 3, "unique_meshes": cache.size(),
		"poses_per_assembly": 3, "negative_controls": controls, "minimum_held_item_gap_metres": minimum_item_gap,
		"minimum_added_support_drive_gap_metres": minimum_drive_gap,
		"observations": "invented read-only", "native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

func tray_triangle_gap(a: Vector3, b: Vector3, c: Vector3, box: AABB) -> float:
	# Separating-axis test over raw facets and a conservative complete-item box.
	# Diagonal cap triangles must not fill the saddle's actual outlet relief.
	var edges: Array[Vector3] = [b - a, c - b, a - c]
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK, edges[0].cross(edges[1])]
	for edge in edges:
		for basis_axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			axes.append(edge.cross(basis_axis))
	var centre := box.get_center()
	var half := box.size / 2.0
	var separating_gap := -INF
	for axis in axes:
		if axis.length_squared() < 0.000000000000000001:
			continue
		var unit := axis.normalized()
		var lo := minf(unit.dot(a), minf(unit.dot(b), unit.dot(c)))
		var hi := maxf(unit.dot(a), maxf(unit.dot(b), unit.dot(c)))
		var mid := unit.dot(centre)
		var radius := unit.abs().dot(half)
		separating_gap = maxf(separating_gap, maxf(mid - radius - hi, lo - mid - radius))
	return separating_gap

func tray_mesh_gap(part: MeshInstance3D, box: AABB, only_surface: int = -1) -> float:
	var result := INF
	for surface in range(part.mesh.get_surface_count()):
		if only_surface >= 0 and surface != only_surface:
			continue
		var faces := die_faces(part.mesh, surface)
		for n in range(0, faces.size(), 3):
			result = minf(result, tray_triangle_gap(part.transform * faces[n], part.transform * faces[n + 1], part.transform * faces[n + 2], box))
	return result

func tray_bracket_seated(machine: Node3D, bracket: MeshInstance3D) -> bool:
	var deck: MeshInstance3D = machine.get_node("Plinth")
	var tray: MeshInstance3D = machine.get_node("OutputTray")
	for z in [-0.10, 0.0, 0.10]:
		var probe := Vector2(bracket.position.x, bracket.position.z + z)
		var bottom := die_height(bracket.mesh, 0, bracket.transform, probe, false)
		var top := die_height(bracket.mesh, 0, bracket.transform, probe, true)
		var deck_top := die_height(deck.mesh, 0, deck.transform, probe, true)
		var tray_bottom := die_height(tray.mesh, 0, tray.transform, probe, false)
		if not (is_finite(bottom) and is_finite(top) and is_finite(deck_top) and is_finite(tray_bottom)) \
			or absf(bottom - deck_top) > 0.000001 or absf(top - tray_bottom) > 0.000001:
			return false
	return true

func check_press_output_tray() -> void:
	var cache: Dictionary = {}
	var assemblies := 0
	var controls := 0
	var minimum_plate_gap := INF
	var minimum_drive_gap := INF
	var minimum_saddle_gap := INF
	var minimum_source_gap := INF
	for shared_profile in [false, true]:
		for axis in range(3):
			for cell in [[0, 0], [2, -1]]:
				var view: Variant = Shared.new() if shared_profile else Opening.new()
				view.client = "P"
				if shared_profile:
					view.session = PaddleSessionFacts.new()
				view.machine_root = Node3D.new()
				view.item_root = Node3D.new()
				view.add_child(view.machine_root)
				view.add_child(view.item_root)
				view.state = {"context": "press-output-tray-fixture", "options": {"native": true, "physical": true},
					"actors": {"P": {"ready": true}}, "parts": {}, "inventories": {"P": 0},
					"stock": {"source": 15, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 1}, "remaining": 0,
					"entities": {"fixture": {"kind": "processor", "cell": cell, "axis": axis, "generation": 1}},
					"transmission_parts": {}, "motion": {}, "links": [], "drive_links": [], "engagements": []}
				var before: Dictionary = view.state.duplicate(true)
				view._rebuild_machines()
				view._redraw_items()
				var machine: Node3D = view.machine_root.get_child(0)
				var tray: MeshInstance3D = machine.get_node("OutputTray")
				var drive: MeshInstance3D = machine.get_node("DriveStub")
				var anvil: MeshInstance3D = machine.get_node("Anvil")
				var parts: Array[MeshInstance3D] = [tray, machine.get_node("TrayBracketLeft"), machine.get_node("TrayBracketRight"),
					anvil, machine.get_node("AnvilPedestalLeft"), machine.get_node("AnvilPedestalRight")]
				var plate: Node3D = null
				var plate_count := 0
				for item in view.item_root.get_children():
					if item.get_meta("item_kind", "") == "stamped_plate":
						plate = item
						plate_count += 1
				verify(plate_count == 1 and plate != null and machine.basis == Basis.IDENTITY,
					"The ordinary observed-output path draws one complete plate at the translated processor, without rotating its reference frame.")
				if plate == null:
					view.free()
					continue
				var plate_pose := machine.transform.affine_inverse() * plate.transform
				var plate_box := machine.transform.affine_inverse() * feed_item_bounds(plate, Transform3D.IDENTITY)
				verify(plate_pose.origin.is_equal_approx(Vector3(0.46, 0.39, 0.15)) and plate_pose.basis == Basis.IDENTITY
					and absf(plate_box.position.y - 0.36) < 0.000001,
					"The complete original plate keeps its observed pose and actual sheet bottom, including its existing five-millimetre receiving allowance.")
				verify(tray.mesh == TrayArt.tray_mesh() and tray.position == Vector3(0.46, 0.33, 0.15)
					and tray.mesh.get_aabb().size.is_equal_approx(Vector3(0.48, 0.023, 0.58)),
					"The formed pan keeps the original root and horizontal footprint, with a thin floor and raised returned sides.")
				var receiving_plane := die_height(tray.mesh, 0, tray.transform, Vector2(0.46, 0.15), true)
				verify(absf(receiving_plane - 0.355) < 0.000001 and absf((plate_box.position.y - receiving_plane) - 0.005) < 0.000001,
					"The actual broad floor retains the original receiving plane and sheet clearance instead of moving the output item.")
				verify(tray.material_override == Opening.ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.5),
					"The formed sheet reuses the qualified worked finish without a new texture or authority input.")
				if cache.is_empty():
					check_closed_asset_mesh(tray.mesh, 0.00235, 0.00245)
					for surface in range(2):
						var isolated := SurfaceTool.new()
						isolated.create_from(parts[1].mesh, surface)
						check_closed_asset_mesh(isolated.commit(), 0.0010 if surface == 0 else 0.0000015,
							0.0012 if surface == 0 else 0.0000021)
					check_closed_asset_mesh(parts[4].mesh, 0.0044, 0.0049)
					var saddle_surface := SurfaceTool.new()
					saddle_surface.create_from(anvil.mesh, 0)
					check_closed_asset_mesh(saddle_surface.commit(), 0.039, 0.0401)
					cache = {"tray": tray.mesh, "bracket": parts[1].mesh, "rib": parts[4].mesh, "anvil": anvil.mesh}
				verify(tray.mesh == cache.tray and parts[1].mesh == cache.bracket and parts[2].mesh == cache.bracket
					and parts[4].mesh == cache.rib and anvil.mesh == cache.anvil,
					"Both view classes, every axis and translated placements share the complete cached rigid meshes.")
				verify(anvil.position == Vector3(0, 0.46, 0.05) and anvil.mesh.get_aabb().size.is_equal_approx(Vector3(0.7, 0.16, 0.63))
					and absf(die_height(anvil.mesh, 1, anvil.transform, Vector2.ZERO, true) - 0.54) < 0.000001,
					"The relieved saddle preserves the complete original envelope, centre and working plane around its existing machine drive interface.")
				var rows: Array = machine.get_meta("motion_meshes")
				verify(rows.size() == 2 and str(rows[0].node.name) == "ToolHead" and str(rows[1].node.name) == "Piston",
					"The original head and piston remain the only moving press parts.")
				var fixed: Array[Transform3D] = []
				for part in parts:
					fixed.append(part.transform)
					verify(part.get_script() == null and part.get_child_count() == 0, "Outlet and supporting parts are passive rigid meshes without controllers or colliders.")
					var gap := tray_mesh_gap(part, plate_box)
					minimum_plate_gap = minf(minimum_plate_gap, gap)
					verify(gap > 0.000001, "Every actual raw outlet, anvil and support facet clears the conservative complete output-plate box.")
					# The original journal enters the complete anvil body. Do not
					# confuse that retained interface with the new free-standing
					# supports. The reseated anvil fasteners must clear it too.
					var drive_gap := tray_mesh_gap(part, drive.transform * drive.mesh.get_aabb(), 2 if part == anvil else -1)
					minimum_drive_gap = minf(minimum_drive_gap, drive_gap)
					verify(drive_gap > 0.02, "The new pan, brackets, narrowed pedestals and reseated anvil fasteners clear every original drive axis.")
					check_bounds(part, Transform3D.IDENTITY)
				for bracket in [parts[1], parts[2]]:
					verify(bracket.mesh.get_surface_count() == 2 and bracket.material_override == null
						and bracket.get_surface_override_material(0) == CollectorArt.coating(Color("394a44"))
						and bracket.get_surface_override_material(1) == Opening.ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.85, 0.38)
						and tray_bracket_seated(machine, bracket),
						"Fixed coated brackets and worked foot fasteners meet the actual skid and pan underside at three independent support probes.")
				for rib in [parts[4], parts[5]]:
					verify(die_supports(machine, rib), "The narrowed anvil pedestals still meet the actual deck and complete anvil underside.")
				for part in [tray, parts[1], parts[2]]:
					var gap := tray_mesh_gap(anvil, part.transform * part.mesh.get_aabb())
					minimum_saddle_gap = minf(minimum_saddle_gap, gap)
					verify(gap > 0.000001, "The pan and its brackets also clear the actual relieved anvil facets.")
				var protected_rows: Array[Dictionary] = []
				for part in parts:
					protected_rows.append({"name": str(part.name), "bounds": part.transform * part.mesh.get_aabb()})
				for source_name in ["CastPressSupportLeft", "CastPressSupportRight"]:
					var source: MeshInstance3D = machine.get_node(source_name)
					for row in protected_rows:
						var gap := tray_mesh_gap(source, row.bounds)
						minimum_source_gap = minf(minimum_source_gap, gap)
						verify(gap > 0.000001, "The sourced support's actual facets remain clear of the composed outlet and anvil pieces.")
				var picks := 0
				for child in machine.get_children():
					if child is StaticBody3D:
						picks += 1
						verify(child.collision_layer == Geometry.PICK_LAYER and child.collision_mask == 0
							and child.get_meta("entity") == "fixture" and child.get_child_count() == 1
							and child.get_child(0).shape.size == Vector3(1.45, 1.65, 1.45)
							and child.get_child(0).position == Vector3(0, 0.8, 0),
							"The sole original pick retains its exact entity, dimensions, centre and masks.")
				verify(picks == 1 and view.state == before, "The ordinary builders preserve every observed state field and create no extra authority or pick body.")
				for travel in [0.0, 0.0075, 0.015]:
					view._apply_press_pose(rows, travel)
					var unchanged := true
					for index in range(parts.size()):
						unchanged = unchanged and parts[index].transform == fixed[index]
					verify(unchanged, "The complete outlet and all supports stay fixed at both original head endpoints and the intermediate pose.")
				if controls == 0:
					tray.position.x += 0.03
					verify(tray_mesh_gap(tray, plate_box) <= 0, "A fold displaced into the actual plate fails the same raw-facet clearance oracle.")
					tray.transform = fixed[0]
					parts[1].position.y += 0.01
					verify(not tray_bracket_seated(machine, parts[1]), "A bracket floating above the skid fails the same support-plane checks.")
					parts[1].transform = fixed[1]
					var old_rib := PackedVector2Array([Vector2(-0.09, -0.07), Vector2(0.09, -0.07), Vector2(0.09, -0.045),
						Vector2(0.045, -0.045), Vector2(0.04, 0.045), Vector2(0.075, 0.045), Vector2(0.075, 0.07),
						Vector2(-0.075, 0.07), Vector2(-0.075, 0.045), Vector2(-0.04, 0.045), Vector2(-0.045, -0.045), Vector2(-0.09, -0.045)])
					parts[5].mesh = Visuals.prism_mesh(old_rib, 0.53, 0.003)
					parts[5].position.x = 0.22
					var old_rib_gap := tray_mesh_gap(parts[5], plate_box)
					verify(old_rib_gap <= 0, "The exact former wide rib and centre fail the same positive-clearance predicate; contact is not clearance.")
					parts[5].mesh = cache.rib
					parts[5].transform = fixed[5]
					var old_saddle := PackedVector2Array([Vector2(-0.35, -0.08), Vector2(0.35, -0.08), Vector2(0.35, -0.045),
						Vector2(0.27, -0.045), Vector2(0.24, -0.015), Vector2(0.24, 0.04), Vector2(-0.24, 0.04),
						Vector2(-0.24, -0.015), Vector2(-0.27, -0.045), Vector2(-0.35, -0.045)])
					anvil.mesh = Visuals.prism_mesh(old_saddle, 0.63, 0.004)
					var old_saddle_gap := tray_mesh_gap(anvil, plate_box)
					verify(old_saddle_gap <= 0, "The former saddle also fails the complete-output clearance check, without changing the plate.")
					anvil.mesh = cache.anvil
					print(JSON.stringify({"former_rib_control_gap_metres": old_rib_gap, "former_saddle_control_gap_metres": old_saddle_gap,
						"control_rule": "A separating gap must be positive; zero contact and negative overlap both fail."}))
					controls = 4
				view.state.entities.fixture.generation = 2
				view._rebuild_machines()
				var rebuilt: Node3D = view.machine_root.get_child(0)
				verify(rebuilt.get_node("OutputTray").mesh == cache.tray and rebuilt.get_node("TrayBracketLeft").mesh == cache.bracket
					and rebuilt.get_node("AnvilPedestalRight").mesh == cache.rib,
					"Replacement generations reuse cached geometry rather than carrying old nodes or adding structural inventory.")
				view.state.entities.clear()
				view.state.stock.source = 16
				view.state.stock.output = 0
				before = view.state.duplicate(true)
				view._rebuild_machines()
				view._redraw_items()
				var remaining_plates := 0
				for item in view.item_root.get_children():
					if item.get_meta("item_kind", "") == "stamped_plate":
						remaining_plates += 1
				verify(view.machine_root.get_child_count() == 0 and remaining_plates == 0 and view.state == before,
					"Observed removal clears the complete outlet, brackets and output display without altering the replacement state.")
				assemblies += 1
				view.free()
	var historical := Opening.new()
	historical.legacy_fixture = true
	var old_root := Node3D.new()
	historical._press_visual(old_root)
	verify(old_root.get_node("OutputTray").mesh == Visuals.box_mesh(Vector3(0.48, 0.05, 0.58))
		and old_root.get_node_or_null("TrayBracketLeft") == null,
		"The historical nonnative fixture retains its previous tray and roster.")
	old_root.free()
	historical.free()
	print(JSON.stringify({"assemblies": assemblies, "axes": 3, "unique_meshes": cache.size(), "negative_controls": controls,
		"minimum_complete_plate_facet_gap_metres": minimum_plate_gap, "minimum_drive_facet_gap_metres": minimum_drive_gap,
		"minimum_tray_saddle_facet_gap_metres": minimum_saddle_gap, "minimum_source_facet_gap_metres": minimum_source_gap,
		"drive_clearance_scope": "Pan, brackets, pedestals and anvil fasteners. The original journal enters the retained anvil body.",
		"receiving_plane_metres": 0.355, "existing_plate_sheet_gap_metres": 0.005,
		"observations": "invented read-only", "native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

func collector_tooling_sweeps(rows: Array) -> Array[Dictionary]:
	# Every facet is contained by its vertices' maximum radial and axial extent.
	# This bounds a COMPLETE turn, rather than inferring it from sampled poses.
	var result: Array[Dictionary] = []
	var pivot := Vector2(-0.22, 1.1)
	for row in rows:
		var node: MeshInstance3D = row.node
		var pose: Transform3D = row.parent_inverse.affine_inverse() * node.transform
		var radius := 0.0
		var low := INF
		var high := -INF
		for surface in range(node.mesh.get_surface_count()):
			var points: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point in points:
				var at := pose * point
				radius = maxf(radius, Vector2(at.x, at.y).distance_to(pivot))
				low = minf(low, at.z)
				high = maxf(high, at.z)
		result.append({"radius": radius, "low": low, "high": high, "name": str(node.name)})
	return result

func collector_tooling_frame_gap(frame: Node3D, sweeps: Array[Dictionary]) -> float:
	var minimum := INF
	var pivot := Vector2(-0.22, 1.1)
	for part: MeshInstance3D in frame.get_children():
		var pose := frame.transform * part.transform
		for surface in range(part.mesh.get_surface_count()):
			var faces := die_faces(part.mesh, surface)
			for n in range(0, faces.size(), 3):
				var a := pose * faces[n]
				var b := pose * faces[n + 1]
				var c := pose * faces[n + 2]
				var radial := point_triangle_distance(pivot, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
				for sweep in sweeps:
					var axial := maxf(minf(a.z, minf(b.z, c.z)) - float(sweep.high),
						float(sweep.low) - maxf(a.z, maxf(b.z, c.z)))
					minimum = minf(minimum, maxf(radial - float(sweep.radius), axial))
	return minimum

func collector_tooling_stock_gap(box: AABB, sweeps: Array[Dictionary]) -> float:
	var nearest := Vector2(clampf(-0.22, box.position.x, box.end.x), clampf(1.1, box.position.y, box.end.y))
	var radial := nearest.distance_to(Vector2(-0.22, 1.1))
	var result := INF
	for sweep in sweeps:
		var axial := maxf(box.position.z - float(sweep.high), float(sweep.low) - box.end.z)
		result = minf(result, maxf(radial - float(sweep.radius), axial))
	return result

func collector_tooling_seated(mesh: Mesh) -> bool:
	for z in [-0.10, 0.0, 0.10]:
		var probe := Vector2(0, z)
		var holder := die_height(mesh, 0, Transform3D.IDENTITY, probe, true)
		var insert := die_height(mesh, 1, Transform3D.IDENTITY, probe, false)
		if not is_finite(holder) or not is_finite(insert) or absf(holder - 0.0075) > 0.000001 or absf(insert - holder) > 0.000001:
			return false
	for z in [-0.14, 0.14]:
		var probe := Vector2(0, z)
		var holder := die_height(mesh, 0, Transform3D.IDENTITY, probe, true)
		var head := die_height(mesh, 2, Transform3D.IDENTITY, probe, false)
		if not is_finite(head) or absf(head - holder) > 0.000001:
			return false
	return true

func collector_tooling_bore(mesh: Mesh) -> float:
	var minimum := INF
	for surface in range(mesh.get_surface_count()):
		var faces := die_faces(mesh, surface)
		for n in range(0, faces.size(), 3):
			minimum = minf(minimum, point_triangle_distance(Vector2.ZERO, Vector2(faces[n].x, faces[n].z),
				Vector2(faces[n + 1].x, faces[n + 1].z), Vector2(faces[n + 2].x, faces[n + 2].z)))
	return minimum

func collector_tooling_section(mesh: Mesh, height: float, angle: float) -> float:
	# Use raw facets and a long ray. Short unnormalised triangle probes can
	# miss small faces under the separately recorded GDC-14 adapter behavior.
	var start := Vector3(0, height, 0)
	var end := start + Vector3(cos(angle), 0, sin(angle)) * 2.0
	var first := INF
	for surface in range(mesh.get_surface_count()):
		var faces := die_faces(mesh, surface)
		for n in range(0, faces.size(), 3):
			var cut: Variant = Geometry3D.segment_intersects_triangle(start, end, faces[n], faces[n + 1], faces[n + 2])
			if typeof(cut) == TYPE_VECTOR3:
				first = minf(first, start.distance_to(cut))
	return first

func collector_tooling_materials(flute: MeshInstance3D) -> bool:
	return flute.material_override == null \
		and flute.get_surface_override_material(0) == Opening.ProductionTransmissionFinish.material("worked", Color("465a60"), 0.85, 0.4) \
		and flute.get_surface_override_material(1) == Opening.ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.9, 0.3) \
		and flute.get_surface_override_material(2) == Opening.ProductionTransmissionFinish.material("worked", Color("778b8c"), 0.85, 0.4)

func check_collector_tooling() -> void:
	var cache: Dictionary = {}
	var assemblies := 0
	var controls := 0
	var minimum_frame_gap := INF
	var minimum_stock_gap := INF
	var maximum_moving_radius := 0.0
	var bore_radius := INF
	for shared_profile in [false, true]:
		for axis in range(3):
			for cell in [[0, 0], [2, -1]]:
				var view: Variant = Shared.new() if shared_profile else Opening.new()
				view.client = "P"
				if shared_profile:
					view.session = PaddleSessionFacts.new()
				view.machine_root = Node3D.new()
				view.item_root = Node3D.new()
				view.add_child(view.machine_root)
				view.add_child(view.item_root)
				view.transmission_presenter = Presenter.new()
				view.add_child(view.transmission_presenter)
				view.transmission_presenter.configure(view)
				view.state = {"context": "collector-tooling-fixture", "options": {"native": true, "physical": true},
					"actors": {"P": {"ready": true}}, "parts": {}, "inventories": {"P": 0},
					"stock": {"source": 15, "collector": 1, "belt": 0, "input": 0, "held": 0, "output": 0}, "remaining": 0,
					"entities": {"fixture": {"kind": "collector", "cell": cell, "axis": axis, "generation": 1}},
					"transmission_parts": {}, "motion": {"fixture": {"state": "rotating", "numerator": 1, "denominator": 1}},
					"links": [], "drive_links": [], "engagements": []}
				var before: Dictionary = view.state.duplicate(true)
				view._rebuild_machines()
				view._redraw_items()
				var machine: Node3D = view.machine_root.get_child(0)
				var frame: Node3D = machine.get_node("CollectorCastFrame")
				var drum: MeshInstance3D = machine.get_node("CutterDrum")
				var hub: MeshInstance3D = machine.get_node("CutterHub")
				var rows: Array = machine.get_meta("motion_meshes")
				verify(rows.size() == 10 and count_role(machine, "CutterFlute") == 8,
					"The native builder keeps the original ten moving observations and all eight flute identities.")
				verify(drum.position == Vector3(-0.22, 1.1, -0.19) and hub.position == Vector3(-0.22, 1.1, 0.01)
					and drum.mesh == CollectorToolingArt.drum_mesh() and hub.mesh == CollectorToolingArt.hub_mesh()
					and drum.mesh.get_aabb().size.is_equal_approx(Vector3(0.48, 0.34, 0.48))
					and hub.mesh.get_aabb().size.is_equal_approx(Vector3(0.17, 0.08, 0.17)),
					"The stepped native drum and hub preserve their original centres and complete local envelopes.")
				verify(drum.material_override == Opening.ProductionTransmissionFinish.material("worked", Color("465a60"), 0.85, 0.4)
					and hub.material_override == Opening.ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.4),
					"The rotating metal uses the qualified worked surfaces without changing the frame's coating.")
				var flutes: Array[MeshInstance3D] = []
				for row in rows:
					verify(row.role == "cutter" and row.node.get_script() == null and row.node.get_child_count() == 0,
						"All moving tooling remains passive rigid meshes consumed by the existing cutter callback.")
					if row.node.get_meta("detail_role", "") == "CutterFlute":
						flutes.append(row.node)
						verify(row.node.mesh == CollectorToolingArt.flute_mesh() and row.node.mesh.get_surface_count() == 3
							and row.node.mesh.surface_get_name(1) == "CuttingInsert" and row.node.mesh.surface_get_name(2) == "RetainingHeads"
							and row.node.mesh.get_aabb().size.is_equal_approx(Vector3(0.04, 0.045, 0.29))
							and collector_tooling_seated(row.node.mesh) and collector_tooling_materials(row.node),
							"Each fitted cartridge keeps its old envelope while separating a seated cutting insert, holder and retaining heads.")
				verify(flutes.size() == 8, "Every original flute receives the same fitted tooling rather than extra moving nodes.")
				if cache.is_empty():
					cache = {"drum": drum.mesh, "hub": hub.mesh, "flute": flutes[0].mesh}
					check_closed_asset_mesh(drum.mesh, 0.047, 0.053)
					check_closed_asset_mesh(hub.mesh, 0.0014, 0.0018)
					var volumes: Array = [[0.00032, 0.00035], [0.000125, 0.000135], [0.00000023, 0.00000030]]
					for surface in range(3):
						var isolated := SurfaceTool.new()
						isolated.create_from(flutes[0].mesh, surface)
						check_closed_asset_mesh(isolated.commit(), volumes[surface][0], volumes[surface][1])
					bore_radius = collector_tooling_bore(drum.mesh)
					verify(bore_radius > 0.0847, "The actual annular facets leave a real open drum bore instead of a dark filled cap.")
					for index in range(8):
						var angle := PI / 48.0 + float(index) * TAU / 8.0
						var bore := collector_tooling_section(drum.mesh, 0.168, angle)
						var plug := collector_tooling_section(hub.mesh, -0.032, angle)
						verify(is_finite(bore) and is_finite(plug) and absf(bore - plug) < 0.000001,
							"The raw drum bore and stepped hub share the same mating facets in their existing axial overlap.")
				verify(drum.mesh == cache.drum and hub.mesh == cache.hub and flutes[0].mesh == cache.flute,
					"Both ordinary view classes and every placement reuse the complete cached tooling resources.")
				var sweeps := collector_tooling_sweeps(rows)
				for sweep in sweeps:
					maximum_moving_radius = maxf(maximum_moving_radius, float(sweep.radius))
					verify(float(sweep.radius) <= sqrt(0.2575 * 0.2575 + 0.02 * 0.02) + 0.000001
						and float(sweep.low) >= -0.360001 and float(sweep.high) <= 0.050001,
						"Every actual raw facet remains inside the original complete continuous-turn radial and axial envelope.")
				var frame_gap := collector_tooling_frame_gap(frame, sweeps)
				minimum_frame_gap = minf(minimum_frame_gap, frame_gap)
				verify(frame_gap > 0.006, "Conservative full-turn cylinders derived from actual vertices clear every raw fixed-frame facet, including the annular bearing.")
				var billet_count := 0
				for item in view.item_root.get_children():
					if item.get_meta("item_kind", "") == "workpiece_billet":
						billet_count += 1
					var box := machine.transform.affine_inverse() * feed_item_bounds(item, Transform3D.IDENTITY)
					var stock_gap := collector_tooling_stock_gap(box, sweeps)
					minimum_stock_gap = minf(minimum_stock_gap, stock_gap)
					verify(stock_gap > 0.000001, "The complete continuous tooling envelope clears every actually redrawn stock and source-item box.")
				verify(billet_count == 1, "The observed collector buffer keeps one original billet without changing stock ownership or pose.")
				var picks := 0
				for child in machine.get_children():
					if child is StaticBody3D:
						picks += 1
						verify(child.get_meta("entity", "") == "fixture" and child.collision_layer == Geometry.PICK_LAYER
							and child.collision_mask == 0 and child.get_child_count() == 1
							and child.get_child(0).shape.size == Vector3(1.45, 1.65, 1.45)
							and child.get_child(0).position == Vector3(0, 0.8, 0),
							"The sole original entity pick keeps its identity, dimensions, centre and masks.")
				verify(picks == 1 and view.model == null and view.actor_world == null and view.request_sequence == 0,
					"The art builder creates no authority, native body, material request or extra collider.")
				var fixed: Array[Transform3D] = []
				for part in frame.get_children():
					fixed.append(part.transform)
				for step in range(24):
					var angle := float(step) * TAU / 24.0
					view._apply_cutter_pose(machine, rows, angle)
					var spin := Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO)
					var pivot := Vector3(-0.22, 1.1, -0.19)
					spin.origin = pivot - spin.basis * pivot
					var correct := true
					for row in rows:
						var actual: Transform3D = row.parent_inverse.affine_inverse() * row.node.transform
						var expected: Transform3D = spin * row.rest
						correct = correct and actual.is_equal_approx(expected)
					for index in range(fixed.size()):
						correct = correct and frame.get_child(index).transform == fixed[index]
					verify(correct and view.state == before, "The original callback turns all fitted tooling rigidly about the same centre while frame and observed state stay fixed.")
				view._apply_cutter_pose(machine, rows, 0.0)
				if controls == 0:
					var floated := ArrayMesh.new()
					for surface in range(3):
						var piece := SurfaceTool.new()
						piece.begin(Mesh.PRIMITIVE_TRIANGLES)
						piece.append_from(flutes[0].mesh, surface, Transform3D(Basis.IDENTITY, Vector3.UP * (0.01 if surface == 1 else 0.0)))
						piece.commit(floated)
					verify(not collector_tooling_seated(floated), "A floating insert fails the same actual holder and fastener support-plane oracle.")
					var filled := CylinderMesh.new()
					filled.top_radius = 0.24
					filled.bottom_radius = 0.24
					filled.height = 0.34
					filled.radial_segments = 48
					verify(collector_tooling_bore(filled) == 0.0, "The former filled cylinder cannot pass the raw open-bore requirement.")
					var saved := hub.transform
					hub.position.x += 0.03
					verify(collector_tooling_frame_gap(frame, collector_tooling_sweeps(rows)) < 0,
						"An off-centre hub fails the same whole-turn bearing clearance oracle.")
					hub.transform = saved
					var finish_value := flutes[0].get_surface_override_material(1)
					flutes[0].set_surface_override_material(1, CollectorArt.coating(Color("465a60")))
					verify(not collector_tooling_materials(flutes[0]), "A painted cutting insert fails the qualified metal-role requirement.")
					flutes[0].set_surface_override_material(1, finish_value)
					controls = 4
				view.state.entities.fixture.generation = 2
				view._rebuild_machines()
				var rebuilt: Node3D = view.machine_root.get_child(0)
				verify(rebuilt.get_node("CutterDrum").mesh == cache.drum and rebuilt.get_node("CutterHub").mesh == cache.hub
					and count_role(rebuilt, "CutterFlute") == 8,
					"Replacement generations reuse geometry and rebuild their own original motion group.")
				view.state.entities.clear()
				view.state.stock.source = 16
				view.state.stock.collector = 0
				before = view.state.duplicate(true)
				view._rebuild_machines()
				verify(view.machine_root.get_child_count() == 0 and view.state == before,
					"Observed removal clears the entire collector without generating material, tools or an orphaned motion owner.")
				assemblies += 1
				view.free()
	for shared_profile in [false, true]:
		var historical: Variant = Shared.new() if shared_profile else Opening.new()
		historical.legacy_fixture = true
		var old_root := Node3D.new()
		historical._collector_visual(old_root)
		historical._machine_surface_detail(old_root, "collector")
		var drum: MeshInstance3D = old_root.get_node("CutterDrum")
		verify(drum.mesh is CylinderMesh and is_equal_approx(drum.mesh.top_radius, 0.24)
			and is_equal_approx(drum.mesh.height, 0.34) and not drum.has_meta("collector_tooling_role")
			and drum.material_override == Visuals.material(Color("465a60"), 0.85, 0.4),
			"Both historical nonnative view classes retain the exact original drum primitive and finish.")
		var details: Node3D = old_root.get_node("SurfaceDetail")
		var old_flutes := 0
		for part in details.get_children():
			if part.get_meta("detail_role", "") == "CutterFlute":
				old_flutes += 1
				verify(part.mesh == Visuals.box_mesh(Vector3(0.04, 0.045, 0.29)) and not part.has_meta("collector_tooling_role"),
					"The historical eight flutes keep their original boxes without new native tooling.")
		verify(old_flutes == 8, "The original nonnative flute roster is preserved.")
		old_root.free()
		historical.free()
	print(JSON.stringify({"assemblies": assemblies, "axes": 3, "unique_meshes": cache.size(), "negative_controls": controls,
		"poses_per_assembly": 24, "moving_rows": 10, "maximum_actual_moving_radius_metres": maximum_moving_radius,
		"minimum_continuous_frame_gap_metres": minimum_frame_gap, "minimum_continuous_stock_gap_metres": minimum_stock_gap,
		"minimum_actual_bore_facet_radius_metres": bore_radius, "observations": "invented read-only",
		"continuous_clearance": "Conservative raw-vertex full-turn cylinders against actual frame facets and item boxes.",
		"native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

func check_collector_bearing_seat() -> void:
	var assemblies := 0
	var minimum_liner_gap := INF
	var minimum_frame_gap := INF
	var maximum_mating_difference := 0.0
	var control_gap := 0.0
	for shared_profile in [false, true]:
		for cell in [[0, 0], [2, -1]]:
			var view: Variant = Shared.new() if shared_profile else Opening.new()
			view.client = "P"
			if shared_profile:
				view.session = PaddleSessionFacts.new()
			view.machine_root = Node3D.new()
			view.add_child(view.machine_root)
			view.transmission_presenter = Presenter.new()
			view.add_child(view.transmission_presenter)
			view.transmission_presenter.configure(view)
			view.state = {"context": "collector-bearing-seat", "options": {"native": true, "physical": true},
				"actors": {"P": {"ready": true}}, "parts": {}, "inventories": {"P": 0},
				"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0}, "remaining": 0,
				"entities": {"fixture": {"kind": "collector", "cell": cell, "axis": 0, "generation": 1}},
				"transmission_parts": {}, "motion": {"fixture": {"state": "rotating", "numerator": 1, "denominator": 1}},
				"links": [], "drive_links": [], "engagements": []}
			var before: Dictionary = view.state.duplicate(true)
			view._rebuild_machines()
			var machine: Node3D = view.machine_root.get_child(0)
			var frame: Node3D = machine.get_node("CollectorCastFrame")
			var hub: MeshInstance3D = machine.get_node("CutterHub")
			var drum: MeshInstance3D = machine.get_node("CutterDrum")
			var liner: MeshInstance3D = frame.get_node("FixedBearingLiner")
			var liner_in_hub := hub.transform.affine_inverse() * frame.transform * liner.transform
			verify(liner_in_hub.origin.is_equal_approx(Vector3(0, 0.035, 0)) and liner_in_hub.basis.is_equal_approx(Basis.IDENTITY),
				"The ordinary view still mounts the actual spindle and fixed liner coaxially at their literal original overlap.")
			verify(hub.mesh == CollectorToolingArt.hub_mesh() and collector_tooling_extent(hub.mesh).is_equal_approx(Vector2(0.085, 0.04))
				and hub.position == Vector3(-0.22, 1.1, 0.01),
				"The revised spindle fits the exact original radial and axial envelope, preserving the previous conservative-clearance coverage.")
			if assemblies == 0:
				check_closed_asset_mesh(hub.mesh, 0.0017, 0.0018)
			for index in range(8):
				var angle := PI / 48.0 + float(index) * TAU / 8.0
				var reference := collector_tooling_section(drum.mesh, 0.168, angle)
				var mating := collector_tooling_section(hub.mesh, -0.032, angle)
				maximum_mating_difference = maxf(maximum_mating_difference, absf(reference - mating))
				verify(is_finite(reference) and is_finite(mating) and absf(reference - mating) < 0.000001,
					"The changed spindle retains its actual fitted drum-bore facets at the original mounting overlap.")
				for offset in [-0.005, 0.0, 0.003]:
					var spindle := collector_tooling_section(hub.mesh, liner_in_hub.origin.y + offset, angle)
					var opening := collector_tooling_section(liner.mesh, offset, angle)
					var gap := opening - spindle
					minimum_liner_gap = minf(minimum_liner_gap, gap)
					verify(is_finite(spindle) and is_finite(opening) and absf(spindle - reference) < 0.000001
						and gap > 0.009 and gap < 0.011,
						"The actual supported spindle span keeps its original radius at three bearing planes and the original liner clearance.")
			var rows: Array = machine.get_meta("motion_meshes")
			var hub_row: Dictionary = {}
			for row in rows:
				if row.node == hub:
					hub_row = row
			verify(rows.size() == 10 and not hub_row.is_empty(), "The changed spindle is still in the original ten-row motion group.")
			if hub_row.is_empty():
				view.free()
				continue
			var frame_gap := collector_tooling_frame_gap(frame, collector_tooling_sweeps([hub_row]))
			minimum_frame_gap = minf(minimum_frame_gap, frame_gap)
			verify(frame_gap > 0.006, "The changed raw spindle also clears the existing frame through its complete conservative turn.")
			if assemblies == 0:
				var previous := Visuals.turned_mesh(PackedVector2Array([
					Vector2(0, -0.04), Vector2(0.074, -0.04), Vector2(0.085, -0.033),
					Vector2(0.085, 0.017), Vector2(0.077, 0.025), Vector2(0.068, 0.025),
					Vector2(0.068, 0.04), Vector2(0, 0.04)]))
				var reference := collector_tooling_section(drum.mesh, 0.168, PI / 48.0)
				control_gap = reference - collector_tooling_section(previous, 0.035, PI / 48.0)
				verify(control_gap > 0.016, "The exact first stepped spindle fails the same bearing-seat radius requirement rather than being accepted only by its outer bounds.")
			view._apply_cutter_pose(machine, rows, PI / 3.0)
			var spin := Transform3D(Basis(Vector3.BACK, PI / 3.0), Vector3.ZERO)
			var pivot := Vector3(-0.22, 1.1, -0.19)
			spin.origin = pivot - spin.basis * pivot
			var actual: Transform3D = hub_row.parent_inverse.affine_inverse() * hub.transform
			verify(actual.is_equal_approx(spin * hub_row.rest) and view.state == before and view.model == null
				and view.actor_world == null and view.request_sequence == 0,
				"The revised spindle still follows the original callback without changing observations, authority or requests.")
			assemblies += 1
			view.free()
	print(JSON.stringify({"assemblies": assemblies, "seat_planes": 3, "directions_per_plane": 8, "negative_controls": 1,
		"minimum_liner_gap_metres": minimum_liner_gap, "minimum_continuous_frame_gap_metres": minimum_frame_gap,
		"maximum_mating_difference_metres": maximum_mating_difference, "previous_spindle_seat_deficit_metres": control_gap,
		"reused_coverage": "The first 1001-check component case retains the unchanged drum, inserts, full envelopes, all axes, stock, lifecycle and pick results.",
		"observations": "invented read-only", "native_gameplay": "not_run", "rendered_quality": "not_assessed"}))

func collector_service_foot_contact(panel: MeshInstance3D, hardware: MeshInstance3D, offset := Vector3.ZERO) -> Dictionary:
	var panel_faces := die_faces(panel.mesh, 0)
	var plane := INF
	for point in panel_faces:
		plane = minf(plane, (panel.transform * point).z)
	var pose := hardware.transform
	pose.origin += offset
	var faces := die_faces(hardware.mesh, 0)
	var foot_plane := -INF
	for point in faces:
		foot_plane = maxf(foot_plane, (pose * point).z)
	var supported: Array[PackedVector2Array] = []
	for n in range(0, panel_faces.size(), 3):
		var a: Vector3 = panel.transform * panel_faces[n]
		var b: Vector3 = panel.transform * panel_faces[n + 1]
		var c: Vector3 = panel.transform * panel_faces[n + 2]
		if absf(a.z - plane) < 0.000001 and absf(b.z - plane) < 0.000001 and absf(c.z - plane) < 0.000001:
			supported.append(PackedVector2Array([Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y)]))
	var seated := true
	var area := 0.0
	var foot_triangles := 0
	var maximum_distance := 0.0
	for n in range(0, faces.size(), 3):
		var a: Vector3 = pose * faces[n]
		var b: Vector3 = pose * faces[n + 1]
		var c: Vector3 = pose * faces[n + 2]
		if absf(a.z - plane) > 0.000001 or absf(b.z - plane) > 0.000001 or absf(c.z - plane) > 0.000001:
			continue
		foot_triangles += 1
		area += (b - a).cross(c - a).length() / 2.0
		for point in [Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y)]:
			var distance := INF
			for triangle in supported:
				distance = minf(distance, point_triangle_distance(point, triangle[0], triangle[1], triangle[2]))
			maximum_distance = maxf(maximum_distance, distance)
			seated = seated and distance < 0.000001
	return {"seated": seated and area > 0 and absf(foot_plane - plane) < 0.000001, "area": area,
		"support_plane": plane, "foot_plane": foot_plane, "foot_triangles": foot_triangles,
		"maximum_projected_gap": maximum_distance, "supported_triangles": supported.size(),
		"bounding_foot_plane": (pose * hardware.mesh.get_aabb()).end.z}

func check_collector_rear_service() -> void:
	var cache: Dictionary = {}
	var assemblies := 0
	var minimum_gap := INF
	var maximum_seat_error := 0.0
	for shared_profile in [false, true]:
		for axis in range(3):
			for cell in [[0, 0], [2, -1]]:
				var view = Shared.new() if shared_profile else Opening.new()
				if shared_profile:
					view.session = PaddleSessionFacts.new()
				view.machine_root = Node3D.new()
				view.add_child(view.machine_root)
				view.state = {"context": "collector-service-fixture", "options": {"native": true, "physical": true},
					"actors": {"P": {"ready": true}}, "parts": {}, "inventories": {"P": 0},
					"stock": {"source": 15, "collector": 1, "belt": 0, "input": 0, "held": 0, "output": 0}, "remaining": 0,
					"entities": {"fixture": {"kind": "collector", "cell": cell, "axis": axis, "generation": 1}},
					"transmission_parts": {}, "motion": {}, "links": [], "drive_links": [], "engagements": []}
				var before: Dictionary = view.state.duplicate(true)
				view._rebuild_machines()
				var machine: Node3D = view.machine_root.get_child(0)
				var detail: Node3D = machine.get_node("SurfaceDetail")
				var housing: MeshInstance3D = machine.get_node("CollectorCastFrame/CastLowerHousing")
				var gasket := detail.get_node_or_null("RearServiceGasket") as MeshInstance3D
				var panel := detail.get_node_or_null("RearServicePanel") as MeshInstance3D
				var hardware := detail.get_node_or_null("RearServiceHardware") as MeshInstance3D
				verify(gasket != null and panel != null and hardware != null,
					"The native collector contains the complete rear-service kit before geometry is inspected.")
				if gasket == null or panel == null or hardware == null:
					view.free()
					return
				var back := (housing.transform * housing.mesh.get_aabb()).position.z
				var gasket_bounds := gasket.transform * gasket.mesh.get_aabb()
				var panel_bounds := panel.transform * panel.mesh.get_aabb()
				verify(absf(gasket_bounds.end.z - back) < 0.000001 and absf(panel_bounds.end.z - gasket_bounds.position.z) < 0.000001,
					"The actual rear housing, gasket and panel support planes meet without a floating cover.")
				verify(collector_service_foot_contact(housing, gasket).seated and collector_service_foot_contact(gasket, panel).seated,
					"The complete contacting gasket and panel facets rest within their actual supporting surfaces.")
				var contact := collector_service_foot_contact(panel, hardware)
				if assemblies == 0:
					print(JSON.stringify({"collector_service_first_contact": contact}))
				var expected_area := 4.0 * 12.0 * sin(TAU / 24.0) * (pow(0.038 * 0.45, 2) - pow(0.014 * 0.45, 2))
				maximum_seat_error = maxf(maximum_seat_error, absf(float(contact.area) - expected_area))
				verify(contact.seated and absf(float(contact.area) - expected_area) < 0.000001,
					"All four complete washer feet, not just their centres, lie on the real flat panel facets.")
				for part in [gasket, panel, hardware]:
					var role: String = part.get_meta("collector_service_role")
					if not cache.has(role):
						cache[role] = [part.mesh, part.material_override]
						var limits: Array = {"gasket": [0.0009, 0.0011], "panel": [0.0055, 0.0059], "hardware": [0.00001, 0.0001]}[role]
						check_closed_asset_mesh(part.mesh, limits[0], limits[1])
					verify(part.mesh == cache[role][0] and part.material_override == cache[role][1]
						and part.get_script() == null and part.get_child_count() == 0 and part.scale == Vector3.ONE,
						"Both native views and translated placements reuse the same passive service-art resources.")
					check_bounds(part, detail.transform)
					for sweep in collector_tooling_sweeps(machine.get_meta("motion_meshes")):
						var gap: float = sweep.low - (part.transform * part.mesh.get_aabb()).end.z
						minimum_gap = minf(minimum_gap, gap)
						verify(gap > 0.14, "The new fixed rear parts clear the actual cutter facets through their complete rotational sweep.")
				var paint := panel.material_override as StandardMaterial3D
				var steel := hardware.material_override as StandardMaterial3D
				verify(paint.metallic == 0 and is_equal_approx(paint.normal_scale, 0.08) and paint.roughness == 1
					and paint.roughness_texture == CollectorArt.paint_roughness
					and is_equal_approx(steel.metallic, 0.85) and steel.normal_texture == Opening.ProductionTransmissionFinish.textures.worked_normal,
					"Paint and exposed worked hardware retain their distinct qualified material roles.")
				var picks := 0
				for child in machine.get_children():
					if child is StaticBody3D:
						picks += 1
						verify(child.collision_layer == 4 and child.collision_mask == 0 and child.get_child_count() == 1
							and child.get_child(0).shape.size == Vector3(1.45, 1.65, 1.45), "The original independent pick envelope stays unchanged.")
				verify(picks == 1 and machine.get_meta("motion_meshes").size() == 10 and view.state == before
					and view.model == null and view.actor_world == null and view.request_sequence == 0,
					"Fixed service artwork changes no motion rows, observations, authority, requests or pick ownership.")
				if assemblies == 0:
					var washer := Visuals.turned_mesh(PackedVector2Array([
						Vector2(0.014, 0), Vector2(0.038, 0), Vector2(0.043, 0.002),
						Vector2(0.043, 0.004), Vector2(0.038, 0.006), Vector2(0.014, 0.006), Vector2(0.014, 0)]), 24)
					var expected_corners := die_faces(washer, 0).size() + die_faces(Visuals.fastener_head_mesh(), 0).size()
					var predecessor := SurfaceTool.new()
					predecessor.begin(Mesh.PRIMITIVE_TRIANGLES)
					predecessor.append_from(washer, 0, Transform3D.IDENTITY)
					predecessor.append_from(Visuals.fastener_head_mesh(), 0, Transform3D.IDENTITY)
					verify(die_faces(predecessor.commit(), 0).size() < expected_corners
						and die_faces(hardware.mesh, 0).size() == expected_corners * 4,
						"The original mixed-index pattern omits washer faces; the corrected hardware retains every input triangle.")
					verify(not collector_service_foot_contact(panel, hardware, Vector3(0.5, 0, 0)).seated,
						"A washer assembly moved beyond the panel fails the complete-foot contact oracle.")
					verify(not collector_service_foot_contact(panel, hardware, Vector3(0, 0, -0.002)).seated,
						"An outward-floating washer assembly fails the same support-plane oracle.")
				assemblies += 1
				view.free()
	for legacy_profile in [false, true]:
		var old_view := Opening.new()
		old_view.legacy_fixture = legacy_profile
		old_view.state = {"options": {"native": legacy_profile}}
		var old_machine := Node3D.new()
		old_view.add_child(old_machine)
		old_view._assemble_machine(old_machine, {"kind": "collector", "axis": 0})
		verify(old_machine.get_node("SurfaceDetail").get_node_or_null("RearServicePanel") == null,
			"Historical and nonnative profiles retain their original rear casting.")
		old_view.free()
	print(JSON.stringify({"collector_service_assemblies": assemblies, "negative_controls": 2, "mixed_index_control": 1,
		"minimum_full_turn_axial_gap_metres": minimum_gap, "maximum_washer_foot_area_error": maximum_seat_error,
		"observations": "invented read-only", "gameplay": "not_run"}))

func resource_render_write(path: String, report: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	return true

func resource_render_counts(node: Node, counts: Dictionary) -> void:
	if node is MeshInstance3D:
		counts.meshes += 1
		for surface in range(node.mesh.get_surface_count()):
			counts.triangles += int(die_faces(node.mesh, surface).size() / 3)
	if node is CollisionObject3D or node is CollisionShape3D or node.get_script() != null:
		counts.active_nodes += 1
	for child in node.get_children():
		resource_render_counts(child, counts)

func resource_render_pixels(image: Image) -> Dictionary:
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	var foreground := 0
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var at := (y * image.get_width() + x) * 4
			var difference := absi(int(data[at]) - int(data[0])) + absi(int(data[at + 1]) - int(data[1])) + absi(int(data[at + 2]) - int(data[2]))
			if difference > 12:
				foreground += 1
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	return {"foreground_pixels": foreground, "fraction": float(foreground) / float(image.get_width() * image.get_height()),
		"bounds_min": [low.x, low.y], "bounds_max": [high.x, high.y],
		"rule": "RGB distance from the flat corner background exceeds twelve byte levels in total. This detects blank or clipped readback, not visual quality."}

func render_buildable_resources() -> void:
	var output := OS.get_environment("FACTORY_RESOURCE_RENDER_OUTPUT").simplify_path()
	if OS.get_environment("FACTORY_RESOURCE_RENDER_MODE") != "isolated" \
		or DisplayServer.get_name().to_lower() != "x11" or not output.is_absolute_path() \
		or not DirAccess.dir_exists_absolute(output) or output.begins_with(ProjectSettings.globalize_path("res://").simplify_path()):
		push_error("Resource rendering requires the isolated private display case and an existing external output directory.")
		quit(1)
		return
	var manifest := output.path_join("resource-views.json")
	if FileAccess.file_exists(manifest):
		push_error("The resource-render output already exists; preserve it instead of overwriting a first result.")
		quit(1)
		return
	var report := {"status": "running", "evidence_class": "Isolated passive resource renders over invented read-only observations.",
		"engine": Engine.get_version_info(), "display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(),
		"size": [960, 960], "images": [], "gameplay": "not_run", "authority": "not_instantiated",
		"desktop_control": "not_used", "human_quality": "not_assessed"}
	if not resource_render_write(manifest, report):
		push_error("The resource-render manifest cannot be retained.")
		quit(1)
		return
	Engine.max_fps = 30
	var subjects: Array = [{"name": "collector", "kind": "collector"}, {"name": "press", "kind": "processor"},
		{"name": "press-cartridge", "kind": "tool_cartridge", "tool": "press", "sample_only": true},
		{"name": "cutter-cartridge-sample", "kind": "tool_cartridge", "tool": "cut_sample", "sample_only": true},
		{"name": "conveyor", "kind": "belt"}, {"name": "waterwheel", "kind": "wheel"},
		{"name": "waterwheel-large", "kind": "wheel", "tiles": 8},
		{"name": "belt-span", "kind": "belt_span"}, {"name": "belt-pulley", "kind": "belt_pulley"},
		{"name": "waterwheel-journal", "kind": "wheel", "cutaway": true},
		{"name": "paddle-small", "kind": "wheel", "tiles": 3, "paddle_cutaway": true, "cutaway": true},
		{"name": "paddle-large", "kind": "wheel", "tiles": 8, "paddle_cutaway": true, "cutaway": true},
		{"name": "foundation", "kind": "foundation"}, {"name": "foundation-patch", "kind": "foundation"},
		{"name": "foundation-corner", "kind": "foundation"}]
	var selected_subject := OS.get_environment("FACTORY_RESOURCE_RENDER_SUBJECT")
	if not selected_subject.is_empty():
		var wanted := selected_subject.split(",")
		subjects = subjects.filter(func(subject): return subject.name in wanted)
		if subjects.size() != wanted.size():
			report.status = "fail"
			report.reason = "The requested resource-render subject is unknown."
			resource_render_write(manifest, report)
			push_error(report.reason)
			quit(1)
			return
	for subject in subjects:
		var view := Opening.new()
		view.legacy_fixture = false
		view.state = {"context": "resource-studio", "options": {"native": true, "physical": true},
			"actors": {"P": {"ready": true}}, "parts": {}, "inventories": {"P": 0},
			"stock": {"source": 0, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0}, "remaining": 0,
			"entities": {}, "transmission_parts": {}, "motion": {}, "links": [], "drive_links": [], "engagements": []}
		var before: Dictionary = view.state.duplicate(true)
		var model := Node3D.new()
		model.name = "ResourceModel"
		if subject.kind == "foundation":
			var cells := [Vector2i.ZERO] if subject.name == "foundation" else [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN]
			if subject.name == "foundation-patch":
				cells.append(Vector2i.ONE)
			var projected: Dictionary = {}
			for index in range(cells.size()):
				projected[str(index)] = {"cell": [cells[index].x, cells[index].y], "level": 0}
			var edge_masks: Dictionary = FoundationArt.neighbor_masks(projected)
			for index in range(cells.size()):
				var cell: Vector2i = cells[index]
				var tile := Node3D.new()
				tile.position = Vector3(cell.x * Geometry.PITCH, 0, cell.y * Geometry.PITCH)
				model.add_child(tile)
				FoundationArt.mount(tile, edge_masks[str(index)])
		elif subject.kind == "belt_span":
			resource_span(model)
		elif subject.kind == "belt_pulley":
			var shaft := Node3D.new()
			shaft.basis = Presenter.axis_basis(2)
			model.add_child(shaft)
			TransmissionAssets.shaft(shaft, Geometry.PITCH, Color("a6b4af"))
			TransmissionAssets.belt_pulley(shaft)
		elif subject.kind == "tool_cartridge":
			var cartridge := MeshInstance3D.new()
			cartridge.name = subject.name
			cartridge.mesh = DieArt.tool_mesh(subject.tool)
			cartridge.set_surface_override_material(0, CollectorArt.coating(Color("58634c")))
			cartridge.set_surface_override_material(1,
				Opening.ProductionTransmissionFinish.material("worked", Color("a6b4af"), 0.85, 0.32))
			cartridge.set_surface_override_material(2,
				Opening.ProductionTransmissionFinish.material("worked", Color("b8c3bb"), 0.85, 0.38))
			model.add_child(cartridge)
		else:
			view._assemble_machine(model, {"kind": subject.kind, "cell": [0, 0], "axis": 0, "tiles": subject.get("tiles", 3), "generation": 1})
		if subject.get("paddle_cutaway", false):
			# Keep one actual native paddle in its complete ordinary transform.
			# Only other artwork is hidden for this disclosed component study.
			for child in model.get_children():
				if child != view.wheel_rotor:
					child.free()
			for child in view.wheel_rotor.get_children():
				if child.get_meta("paddle_index", -1) != 0:
					child.free()
		elif subject.get("cutaway", false):
			# A disclosed passive journal study. Hide only the rotating timber
			# and paddle artwork in this fixture, leaving the assembled hub and
			# all fixed supports in their ordinary transforms.
			for child in view.wheel_rotor.get_children():
				if str(child.name) != "WheelHub":
					child.free()
		var counts := {"meshes": 0, "triangles": 0, "active_nodes": 0}
		resource_render_counts(model, counts)
		if view.legacy_fixture or not view._native_transmission() or counts.meshes == 0 \
			or counts.active_nodes != 0 or view.state != before or view.model != null \
			or view.actor_world != null or view.request_sequence != 0 or view.is_inside_tree():
			report.status = "fail"
			report.reason = "The resource builder produced active nodes, no meshes or changed observations."
			resource_render_write(manifest, report)
			model.free()
			view.free()
			push_error(report.reason)
			quit(1)
			return
		var bounds := feed_item_bounds(model, Transform3D.IDENTITY)
		if subject.get("paddle_cutaway", false):
			# Empty ancestor origins are not part of the visible cutaway. Frame
			# the actual mesh bounds without relocating or scaling the paddle.
			var pieces: Array[Dictionary] = []
			hub_mesh_rows(model, Transform3D.IDENTITY, pieces)
			bounds = pieces[0].pose * pieces[0].node.mesh.get_aabb()
			for piece in pieces:
				var box: AABB = piece.pose * piece.node.mesh.get_aabb()
				bounds = bounds.merge(box)
		var centre := bounds.get_center()
		var diagonal := bounds.size.length()
		var viewport := SubViewport.new()
		viewport.name = "ResourceViewport"
		viewport.size = Vector2i(960, 960)
		viewport.own_world_3d = true
		viewport.handle_input_locally = false
		viewport.gui_disable_input = true
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var studio := Node3D.new()
		viewport.add_child(studio)
		studio.add_child(model)
		var world := WorldEnvironment.new()
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("26333b")
		var sky := Sky.new()
		sky.sky_material = Opening.ProductionEnvironment.panorama_material()
		environment.sky = sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_energy = 0.6
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		environment.tonemap_exposure = 1.0
		world.environment = environment
		studio.add_child(world)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-48, -30, 0)
		if Opening.ProductionEnvironment.sky_source_status == "ready":
			sun.basis = Basis.looking_at(-Opening.ProductionEnvironment.SKY_SUN_DIRECTION, Vector3.UP)
		sun.light_color = Color("fff0d4")
		sun.light_energy = 1.25
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 15.0
		studio.add_child(sun)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-32, 135, 0)
		fill.light_color = Color("b9d2ea")
		fill.light_energy = 0.18
		studio.add_child(fill)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = diagonal * 1.15
		camera.near = 0.05
		camera.far = 100.0
		studio.add_child(camera)
		camera.current = true
		var directions: Array = [{"name": "front-right", "offset": Vector3(3, 1.8, 4)},
			{"name": "back-left", "offset": Vector3(-4, 1.5, -3)}]
		if subject.kind == "tool_cartridge":
			# Show the actual working surface rather than letting the common
			# carrier hide the only difference between the two head samples.
			directions = [{"name": "front-below", "offset": Vector3(3, -2.2, 4)},
				{"name": "back-below", "offset": Vector3(-4, -1.8, -3)}]
		for direction in directions:
			var direction_offset: Vector3 = direction.offset
			camera.position = centre + direction_offset.normalized() * diagonal * 2.0
			camera.look_at(centre, Vector3.UP)
			var framed := true
			for corner in range(8):
				var projected := camera.unproject_position(bounds.get_endpoint(corner))
				framed = framed and projected.is_finite() and projected.x > 4 and projected.y > 4 and projected.x < 956 and projected.y < 956
			if not framed:
				report.status = "fail"
				report.reason = "The complete resource bounds are not framed inside the isolated viewport."
				resource_render_write(manifest, report)
				viewport.free()
				view.free()
				push_error(report.reason)
				quit(1)
				return
			# Complete two draws after the scene/camera change, then read only
			# this viewport's texture, never an OS screen capture.
			for _frame in range(2):
				await process_frame
				await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			if image == null or image.is_empty() or image.get_size() != Vector2i(960, 960):
				report.status = "fail"
				report.reason = "The isolated renderer returned no complete resource image."
				resource_render_write(manifest, report)
				viewport.free()
				view.free()
				push_error(report.reason)
				quit(1)
				return
			var pixels := resource_render_pixels(image)
			var file_name: String = subject.name + "-" + direction.name + ".png"
			var image_path := output.path_join(file_name)
			if FileAccess.file_exists(image_path) or image.save_png(image_path) != OK:
				report.status = "fail"
				report.reason = "The resource image cannot be retained without overwriting evidence."
				resource_render_write(manifest, report)
				viewport.free()
				view.free()
				push_error(report.reason)
				quit(1)
				return
			if float(pixels.fraction) < 0.02 or float(pixels.fraction) > 0.85 \
				or int(pixels.bounds_min[0]) <= 2 or int(pixels.bounds_min[1]) <= 2 \
				or int(pixels.bounds_max[0]) >= 957 or int(pixels.bounds_max[1]) >= 957:
				report.status = "fail"
				report.reason = "The resource image is blank or clipped."
				report.failed_image = {"file": file_name, "sha256": FileAccess.get_sha256(image_path)}
				report.failed_pixels = pixels
				resource_render_write(manifest, report)
				viewport.free()
				view.free()
				push_error(report.reason)
				quit(1)
				return
			var frame := {"subject": subject.name, "kind": subject.kind, "view": direction.name, "file": file_name,
				"cutaway": subject.get("cutaway", false),
				"sample_only": subject.get("sample_only", false),
				"sha256": FileAccess.get_sha256(image_path), "pixels": pixels, "geometry": counts,
				"profile": {"legacy_fixture": view.legacy_fixture, "native_transmission": view._native_transmission(),
					"native_options": view.state.options.native, "request_sequence": view.request_sequence},
				"camera_position": [camera.position.x, camera.position.y, camera.position.z],
				"camera_target": [centre.x, centre.y, centre.z], "orthographic_size": camera.size,
				"qualified_worked_maps": Opening.ProductionTransmissionFinish.source_status,
				"panorama_source": Opening.ProductionEnvironment.sky_source_status}
			report.images.append(frame)
			if not resource_render_write(manifest, report):
				viewport.free()
				view.free()
				push_error("The completed resource image metadata cannot be retained.")
				quit(1)
				return
			print(JSON.stringify({"resource_image": file_name, "sha256": frame.sha256, "foreground_fraction": pixels.fraction}))
		viewport.queue_free()
		view.free()
		await process_frame
	report.status = "pass"
	report.images_expected = subjects.size() * 2
	report.limits = "Studio lighting and passive mesh observations. The cutter cartridge is an isolated visual sample, not native cutting or interchangeable gameplay. No actual app, game state, user understanding, export, performance or human-quality verdict."
	if not resource_render_write(manifest, report):
		push_error("The final resource-render result cannot be retained.")
		quit(1)
		return
	print(JSON.stringify({"status": "pass", "resource_images": report.images.size(), "output": output,
		"gameplay": "not_run", "desktop_control": "not_used", "human_quality": "not_assessed"}))
	quit(0)

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--paddle-hardware-only"):
		check_paddle_hardware()
		verify(paddle_hardware_checks_complete, "All twelve fitted wheel assemblies must pass.")
		finish()
		return
	if OS.get_cmdline_user_args().has("--paddle-grain-only"):
		check_paddle_grain()
		verify(paddle_grain_checks_complete, "All twelve native paddle assemblies must complete.")
		finish()
		return
	if OS.get_cmdline_user_args().has("--span-belt-only"):
		check_span_belt_art()
		verify(span_belt_checks_complete, "All eight span assemblies must complete.")
		finish()
		return
	if OS.get_cmdline_user_args().has("--foundation-art-only"):
		check_foundation_art()
		finish()
		return
	if OS.get_cmdline_user_args().has("--render-buildable-resources"):
		if OS.get_cmdline_user_args().has("--paddle-hardware-check"):
			check_paddle_hardware()
			if failed or not paddle_hardware_checks_complete:
				verify(paddle_hardware_checks_complete, "All fitted heads must pass before rendering.")
				finish()
				return
		if OS.get_cmdline_user_args().has("--paddle-grain-check"):
			check_paddle_grain()
			if failed or not paddle_grain_checks_complete:
				verify(paddle_grain_checks_complete, "All twelve native paddle assemblies must pass before rendering.")
				finish()
				return
		if OS.get_cmdline_user_args().has("--span-belt-check"):
			check_span_belt_art()
			if failed or not span_belt_checks_complete:
				verify(span_belt_checks_complete, "All eight span assemblies must pass before rendering.")
				finish()
				return
		if OS.get_cmdline_user_args().has("--wheel-supports-check"):
			check_wheel_supports()
			if failed or not wheel_support_checks_complete:
				verify(wheel_support_checks_complete, "Every sized wheel assembly must pass before resource rendering.")
				finish()
				return
		if OS.get_cmdline_user_args().has("--press-input-clearance-check"):
			check_press_input_clearance()
			if failed or not press_input_checks_complete:
				verify(press_input_checks_complete, "All sixteen press input assemblies must pass before resource rendering.")
				finish()
				return
		if OS.get_cmdline_user_args().has("--foundation-art-check"):
			check_foundation_art()
			if failed or not foundation_art_complete:
				verify(foundation_art_complete, "The foundation checks must complete before resource rendering begins.")
				finish()
				return
		if OS.get_cmdline_user_args().has("--drive-journal-mount-check"):
			check_drive_journals(false)
			if failed:
				finish()
				return
		if OS.get_cmdline_user_args().has("--drive-journal-check"):
			check_drive_journals()
			if failed:
				finish()
				return
		if OS.get_cmdline_user_args().has("--collector-input-support-check"):
			check_collector_input_support()
			if failed:
				finish()
				return
		if OS.get_cmdline_user_args().has("--satin-coating-check"):
			check_satin_coating()
			check_collector_coating(false)
			if failed:
				finish()
				return
		if OS.get_cmdline_user_args().has("--collector-rear-service-check"):
			check_press_die()
			check_collector_rear_service()
			if failed:
				finish()
				return
		call_deferred("render_buildable_resources")
		return
	if OS.get_cmdline_user_args().has("--press-input-clearance-only"):
		check_press_input_clearance()
		verify(press_input_checks_complete, "The dedicated press input case passes all sixteen required assemblies.")
		finish()
		return
	if OS.get_cmdline_user_args().has("--collector-input-support-only"):
		check_collector_input_support()
		finish()
		return
	if OS.get_cmdline_user_args().has("--drive-journal-only"):
		check_drive_journals()
		finish()
		return
	if OS.get_cmdline_user_args().has("--satin-coating-only"):
		check_satin_coating()
		check_collector_coating(false)
		finish()
		return
	if OS.get_cmdline_user_args().has("--collector-rear-service-only"):
		check_collector_rear_service()
		finish()
		return
	if OS.get_cmdline_user_args().has("--collector-bearing-seat-only"):
		check_collector_bearing_seat()
		finish()
		return
	if OS.get_cmdline_user_args().has("--collector-tooling-only"):
		check_collector_tooling()
		finish()
		return
	if OS.get_cmdline_user_args().has("--press-output-tray-only"):
		check_press_output_tray()
		finish()
		return
	if OS.get_cmdline_user_args().has("--press-die-only"):
		check_press_die()
		finish()
		return
	if OS.get_cmdline_user_args().has("--conveyor-hub-only"):
		check_conveyor_hub()
		finish()
		return
	if OS.get_cmdline_user_args().has("--conveyor-frame-only"):
		check_conveyor_frame()
		finish()
		return
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
		verify(wheel_support_checks_complete, "The dedicated sized-wheel case passes all twenty-four required assemblies.")
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
	if OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "--prepare-wheel-center-color":
		prepare_wheel_center_color()
		return
	if OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "--prepare-press-support-maps":
		prepare_component_maps("cast")
		return
	if OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "--prepare-coupling-maps":
		prepare_component_maps("coupling")
		return
	if OS.get_cmdline_user_args().has("--wheel-resource-contract-only"):
		check_wheel_resource_contract()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"scope": "synthetic wheel resource admission", "native_gameplay": "not_run"}))
		quit(1 if failed else 0)
		return
	if OS.get_cmdline_user_args().has("--sourced-wheel-material-only"):
		var parent := Node3D.new()
		verify(WheelArt.mount(parent), "The changed material loads through the shipped source helper.")
		var rotor := parent.get_node_or_null("SourcedTimberRotor") as MeshInstance3D
		if rotor != null:
			check_sourced_mesh(rotor)
			check_split_wheel_rims(parent)
			for side: String in ["N", "P"]:
				var rim := parent.get_node_or_null("SourcedTimberRim" + side) as MeshInstance3D
				if rim != null:
					check_sourced_mesh(rim, 1576, 1872, 0.57)
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
	for item in [["collector", 0], ["processor", 0], ["wheel", 0], ["wheel", 1], ["wheel", 2]]:
		view.state = {"options": {"native": true}, "entities": {"fixture": {"kind": item[0], "cell": [0, 0], "axis": item[1]}},
			"links": [], "drive_links": []}
		var before: Dictionary = view.state.duplicate(true)
		view._rebuild_machines()
		var machine: Node3D = view.machine_root.get_child(0)
		var details := machine.get_node_or_null("SurfaceDetail") as Node3D
		if item[0] != "wheel":
			verify(details != null and count_role(details, "FoundationFastener") == 4,
				"Every supported machine has four fitted foundation fasteners.")
			if details != null:
				check_bounds(details, Transform3D.IDENTITY)
		else:
			verify(details == null, "The waterwheel uses its own supports rather than a machine skid.")
		match item[0]:
			"collector":
				verify(count_role(details, "CutterFlute") == 8 and count_role(details, "ServiceVent") == 5,
					"The actual collector includes its cutter flutes and fitted service cover.")
			"processor":
				verify(count_role(details, "GuideCollar") == 4, "The actual press has fitted collars at both guide ends.")
			"wheel":
				var rotor: Node3D = machine.get_node("WheelRotor")
				if WheelArt.source_status == "ready":
					verify(count_role(rotor, "SourcedTimberRotor") == 1 and count_role(rotor, "SourcedTimberRim") == 2
						and count_role(rotor, "WheelRim") == 0,
						"The actual wheel mounts one sourced center and two sourced rims instead of procedural rims.")
				else:
					verify(count_role(rotor, "WheelRim") == 2 and count_role(rotor, "RimFastener") == 24,
						"A historical capture retains its two continuous procedural rims and fitted fasteners.")
				check_native_wheel_bounds(rotor, Transform3D.IDENTITY, [Vector3.RIGHT, Vector3.UP, Vector3.BACK][item[1]])
		verify(view.state == before and view.model == null, "Detail assembly cannot mutate the projection or create a Model.")
	view.machine_root.free()
	view.free()
	finish()
