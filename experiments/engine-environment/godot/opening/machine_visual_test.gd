extends SceneTree
## Automated mesh/collision-contract checks. No desktop, input or game stepping.
const Opening = preload("res://opening/opening.gd")
const Geometry = preload("res://opening/site_geometry.gd")

class PerformanceView extends Opening:
	var target := Vector2i(1, 2)
	func _ready() -> void:
		pass
	func _preview_pointer_clear() -> bool:
		return true
	func _machine_preview_cell() -> Vector2i:
		return target

class PerformanceControls extends RefCounted:
	var selected_axis := "x"
	var active_tool := ""

class MotionStub extends RefCounted:
	func advance_visual_motion(_delta: float) -> void:
		pass
	func visual_angle(id: String) -> float:
		return 0.1 * float(int(id.trim_prefix("wheel-")) + 1)

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
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--compare-images="):
			_compare_images(argument.trim_prefix("--compare-images="))
			return
	if "--performance-benchmark" in OS.get_cmdline_user_args():
		_performance_benchmark.call_deferred()
		return
	if "--batch-motion-check" in OS.get_cmdline_user_args():
		_batch_motion_check.call_deferred()
		return
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

func _compare_images(paths: String) -> void:
	var parts := paths.split("|")
	if parts.size() != 2:
		quit(2)
		return
	var left := Image.load_from_file(parts[0])
	var right := Image.load_from_file(parts[1])
	if left == null or right == null or left.get_size() != right.get_size():
		quit(2)
		return
	var changed := 0
	var strong := 0
	var maximum := 0.0
	var low := Vector2i(left.get_width(), left.get_height())
	var high := Vector2i.ZERO
	for y in left.get_height():
		for x in left.get_width():
			var a := left.get_pixel(x, y)
			var b := right.get_pixel(x, y)
			var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			if delta > 0.0:
				changed += 1
				strong += int(delta > 0.1)
				maximum = maxf(maximum, delta)
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	print("MACHINE_IMAGE_DIFFERENCE " + JSON.stringify({"pixels": changed,
		"strong_pixels": strong, "max_channel_delta": maximum,
		"low": [low.x, low.y], "high": [high.x, high.y]}))
	quit()

func _batch_motion_check() -> void:
	var view := PerformanceView.new()
	view.state = {"context": "synthetic-batch-check", "options": {"native": true},
		"entities": {}, "foundations": {}, "links": [], "drive_links": [],
		"actors": {"P": {"ready": true}}, "stock": {"held": 0}, "remaining": 0}
	view.machine_root = Node3D.new()
	view.add_child(view.machine_root)
	root.add_child(view)
	view.transmission_presenter = MotionStub.new()
	for index in 12:
		view.state.entities["wheel-%d" % index] = {"kind": "wheel", "axis": index % 3,
			"tiles": 2 + index % 3, "cell": [index, 0], "level": 0}
	view._rebuild_machines()
	var batch_root := view.machine_root.get_node_or_null("MachineVisualBatches")
	_check(batch_root != null and batch_root.get_child_count() > 0
		and not view.machine_dynamic_batches.is_empty(),
		"Twelve native wheels share static and moving render batches.")
	var retained_joinery := 0
	var hidden_core := 0
	for part in view.machine_root.get_child(0).get_node("WheelRotor").find_children("*", "MeshInstance3D", true, false):
		if part.visibility_range_end > 0.0 and part.visible:
			retained_joinery += 1
		elif part.visibility_range_end <= 0.0 and not part.visible:
			hidden_core += 1
	_check(retained_joinery > 0 and hidden_core > 0,
		"Wheel core batches preserve the original distance-cullable joinery.")
	var bases: Array[Basis] = []
	for index in 12:
		bases.append((view.machine_root.get_child(index).get_node("WheelRotor") as Node3D).basis)
	var first_multi: MultiMesh = view.machine_dynamic_batches[0].mesh
	var old_instance := first_multi.get_instance_transform(0)
	view._animate_wheel(0.1)
	if DisplayServer.get_name() != "headless":
		_check(not first_multi.get_instance_transform(0).is_equal_approx(old_instance),
			"The rendered wheel instance follows its confirmed moving rotor.")
	for index in 12:
		var anchor: Node3D = view.machine_root.get_child(index)
		var rotor := anchor.get_node_or_null("WheelRotor") as Node3D
		_check(rotor != null and rotor.basis.is_equal_approx(bases[index] * Basis(Vector3.BACK,
			0.1 * float(index + 1))),
			"Every wheel keeps its own confirmed motion instead of borrowing the last wheel rotor.")
	view.state.entities.erase("wheel-11")
	view._rebuild_machines()
	_check(view.machine_root.get_node_or_null("MachineVisualBatches") == null
		and view.machine_dynamic_batches.is_empty(),
		"Falling below the batching threshold restores direct render meshes.")
	view.free()
	var belt_view := PerformanceView.new()
	belt_view.state = {"context": "synthetic-conveyor-check", "options": {"native": true},
		"entities": {}, "foundations": {}, "links": [], "drive_links": [],
		"actors": {"P": {"ready": true}}, "stock": {"held": 0}, "remaining": 0}
	belt_view.machine_root = Node3D.new()
	belt_view.add_child(belt_view.machine_root)
	root.add_child(belt_view)
	for index in 12:
		belt_view.state.entities["belt-%d" % index] = {"kind": "belt", "axis": 0,
			"cell": [index, 0], "level": 0}
	belt_view._rebuild_machines()
	_check(belt_view.machine_conveyor_batches.size() == 1,
		"Conveyor loops retain one shared render batch and individual source materials.")
	if belt_view.machine_conveyor_batches.size() == 1:
		var first := belt_view.machine_root.get_child(0) as Node3D
		var second := belt_view.machine_root.get_child(1) as Node3D
		belt_view._apply_conveyor_motion(first, 0.5)
		belt_view._apply_conveyor_motion(second, 1.0)
		belt_view._update_machine_dynamic_batches()
		var first_loop := first.find_child("ConveyorLoop", true, false) as MeshInstance3D
		var second_loop := second.find_child("ConveyorLoop", true, false) as MeshInstance3D
		_check(first_loop != null and second_loop != null and not first_loop.visible
			and not second_loop.visible and first_loop.material_override.uv1_offset.x !=
			second_loop.material_override.uv1_offset.x,
			"Batched conveyor loops keep distinct hidden source phases.")
		if DisplayServer.get_name() != "headless":
			var belt_multi: MultiMesh = belt_view.machine_conveyor_batches[0].mesh
			_check(absf(belt_multi.get_instance_custom_data(0).r -
				first_loop.material_override.uv1_offset.x) < 0.001 and absf(
				belt_multi.get_instance_custom_data(1).r - second_loop.material_override.uv1_offset.x) < 0.001,
				"Each rendered conveyor loop follows its own source phase.")
	belt_view.free()
	print("MACHINE_BATCH_MOTION_%s %d" % ["PASS" if not failed else "FAIL", checks])
	quit(1 if failed else 0)

func _performance_benchmark() -> void:
	var count := 100
	var kind := "collector"
	var prewarm := false
	var batch := false
	var capture := ""
	var describe_unbatched := false
	var close_view := false
	var silhouette := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--count="):
			count = int(argument.trim_prefix("--count="))
		elif argument.begins_with("--kind="):
			kind = argument.trim_prefix("--kind=")
		elif argument == "--prewarm":
			prewarm = true
		elif argument == "--batch":
			batch = true
		elif argument.begins_with("--capture="):
			capture = argument.trim_prefix("--capture=")
		elif argument == "--describe-unbatched":
			describe_unbatched = true
		elif argument == "--close":
			close_view = true
		elif argument == "--silhouette":
			silhouette = true
	if count < 0 or count > 500 or kind not in ["collector", "belt", "processor", "wheel"]:
		push_error("Choose 0 to 500 collector, belt, processor or wheel visuals.")
		quit(2)
		return
	var view := PerformanceView.new()
	view.state = {"options": {"native": true, "physical": true}, "entities": {}, "foundations": {},
		"part_kits": {"P": {kind: 1}}, "actors": {"P": {"ready": true,
		"position": [0.0, 0.9, 0.0]}}, "links": [], "drive_links": [], "revision": 1}
	view.transmission_controls = PerformanceControls.new()
	view.mode = kind
	if kind == "collector":
		view.target = Vector2i(0, 1)
	var prime_ms := 0.0
	if prewarm:
		var prime_start := Time.get_ticks_usec()
		view._prime_machine_visuals()
		prime_ms = float(Time.get_ticks_usec() - prime_start) / 1000.0
	view.machine_root = Node3D.new()
	var before := Time.get_ticks_usec()
	view._refresh_machine_preview()
	var first_preview_ms := float(Time.get_ticks_usec() - before) / 1000.0
	if view.machine_preview == null or not view.machine_preview.visible or view.machine_preview.get_child_count() == 0:
		push_error("The selected machine preview was not constructed in the fixture.")
		view.machine_root.free()
		view.free()
		quit(1)
		return
	view.machine_preview_key = ""
	before = Time.get_ticks_usec()
	view._refresh_machine_preview()
	var warm_preview_ms := float(Time.get_ticks_usec() - before) / 1000.0
	var scene := Node3D.new()
	root.add_child(scene)
	scene.add_child(view.machine_root)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 3.2, 8) if close_view else Vector3(0, 30, 43)
	camera.current = true
	scene.add_child(camera)
	camera.look_at(Vector3(0, 0.8, 0) if close_view else Vector3.ZERO)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, -0.5, 0)
	scene.add_child(light)
	var columns := ceili(sqrt(float(maxi(count, 1))))
	var build_start := Time.get_ticks_usec()
	var fixture_rotors: Array[Node3D] = []
	for index in count:
		var holder := Node3D.new()
		holder.position = Vector3(float(index % columns - columns / 2) * 1.65, 0,
			float(index / columns - columns / 2) * 1.65)
		view.machine_root.add_child(holder)
		var anchor := Node3D.new()
		anchor.position = Vector3(0, 0, 1.65) if kind == "collector" else Vector3.ZERO
		holder.add_child(anchor)
		view._assemble_machine(anchor, {"kind": kind, "axis": 0, "tiles": 3,
			"rotation": 0, "cell": [0, 1] if kind == "collector" else [0, 0], "level": 0})
		if kind == "wheel":
			fixture_rotors.append(anchor.find_child("WheelRotor", true, false) as Node3D)
		var rows: Array[Dictionary] = []
		view._remember_machine_motion(anchor, kind, Transform3D.IDENTITY, rows)
		holder.set_meta("motion_meshes", rows)
	var build_ms := float(Time.get_ticks_usec() - build_start) / 1000.0
	var batch_start := Time.get_ticks_usec()
	if batch:
		view._batch_machine_visuals()
	var batch_ms := float(Time.get_ticks_usec() - batch_start) / 1000.0
	var batch_root := view.machine_root.get_node_or_null("MachineVisualBatches")
	var batch_groups := batch_root.get_child_count() if batch_root != null else 0
	if describe_unbatched:
		var remaining := {}
		for part in view.machine_root.find_children("*", "MeshInstance3D", true, false):
			if not part.is_visible_in_tree():
				continue
			var parent_name: String = str(part.get_parent().name)
			if parent_name.begins_with("@"):
				parent_name = str(part.get_parent().get_parent().name)
			var label: String = parent_name + "/" + ("anonymous" if str(part.name).begins_with("@") else str(part.name))
			label += ":%d" % part.mesh.get_surface_count()
			remaining[label] = int(remaining.get(label, 0)) + 1
		print("MACHINE_UNBATCHED " + JSON.stringify(remaining))
	if batch and count >= 12 and (batch_groups == 0 or
			(kind in ["collector", "processor", "wheel"] and view.machine_dynamic_batches.is_empty())):
		push_error("The fixture did not batch static and moving machine forms.")
		view.free()
		scene.free()
		quit(1)
		return
	if silhouette:
		var flat := StandardMaterial3D.new()
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.albedo_color = Color.WHITE
		for part in scene.find_children("*", "GeometryInstance3D", true, false):
			if part is MeshInstance3D or part is MultiMeshInstance3D:
				part.material_override = flat
	var frames: Array[float] = []
	var motion_times: Array[float] = []
	var draws: Array[int] = []
	for frame in 150:
		var start := Time.get_ticks_usec()
		for index in count:
			var holder: Node3D = view.machine_root.get_child(index)
			var anchor: Node3D = holder.get_child(0)
			match kind:
				"collector":
					view._apply_cutter_pose(anchor, holder.get_meta("motion_meshes"), float(frame) * 0.02)
				"belt":
					view._apply_conveyor_motion(anchor, float(frame) * 0.02)
				"processor":
					view._apply_press_pose(holder.get_meta("motion_meshes"), 0.015 if frame % 2 == 0 else 0.0)
				"wheel":
					fixture_rotors[index].rotation.z += 0.02
		if batch:
			view._update_machine_dynamic_batches()
		var motion_ms := float(Time.get_ticks_usec() - start) / 1000.0
		await process_frame
		if frame >= 30:
			frames.append(float(Time.get_ticks_usec() - start) / 1000.0)
			motion_times.append(motion_ms)
			draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	frames.sort()
	motion_times.sort()
	draws.sort()
	if not capture.is_empty():
		root.get_texture().get_image().save_png(capture)
	print("MACHINE_PERFORMANCE " + JSON.stringify({"kind": kind, "count": count,
		"first_preview_ms": first_preview_ms, "warm_preview_ms": warm_preview_ms,
		"prime_ms": prime_ms, "build_ms": build_ms, "batch_ms": batch_ms,
		"motion_median_ms": motion_times[motion_times.size() / 2],
		"frame_median_ms": frames[frames.size() / 2],
		"frame_p95_ms": frames[int(frames.size() * 0.95)],
		"draw_calls_median": draws[draws.size() / 2], "batched": batch,
		"batch_groups": batch_groups, "dynamic_groups": view.machine_dynamic_batches.size()}))
	view.free()
	scene.free()
	quit()
