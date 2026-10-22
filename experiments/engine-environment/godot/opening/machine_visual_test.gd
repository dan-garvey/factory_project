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

class MixedAssetScaleView extends Opening:
	## Render-only chapter-one density fixture. The production art constructors and
	## worksite scenery are reused; no synthetic part enters the authoritative World.

	var asset_count := 0
	var batch_static := false
	var production_batch := false
	var built_meshes := 0
	var batch_instances := 0
	var batch_draw_groups := 0
	var shared_conveyor_finish := false
	var inventory_only := false
	var mesh_lod := false
	var camera_close := false
	var lod_inventory: Array[Dictionary] = []
	var triangle_inventory := {}
	var build_ms := 0.0
	var batch_ms := 0.0
	var fixture_root: Node3D

	func _ready() -> void:
		state = {"options": {"native": true}}
		var start := Time.get_ticks_usec()
		_build_world()
		if production_batch:
			fixture_root = machine_root
		else:
			fixture_root = Node3D.new()
			fixture_root.name = "SyntheticAssetField"
			machine_root.add_child(fixture_root)
		var columns := ceili(sqrt(float(maxi(asset_count, 1))))
		var field_x := maxf(10.0, float(columns) * PITCH * 0.5 + 5.0)
		for index in asset_count:
			var x := index % columns
			var z := floori(float(index) / float(columns))
			var placement := Node3D.new()
			var kind: String = ["collector", "belt", "processor"][index % 3]
			if production_batch:
				placement.set_meta("machine_kind", kind)
				placement.set_meta("machine_entity", "machine-%d" % index)
			var site_x := field_x + (float(x) - float(columns - 1) / 2.0) * PITCH
			var site_z := 1.65 + (float(z) - float(columns - 1) / 2.0) * PITCH
			var site_y: float = ProductionEnvironment.Surface.height_at(site_x, site_z)
			placement.position = Vector3(site_x, site_y, site_z)
			fixture_root.add_child(placement)
			var anchor := Node3D.new()
			placement.add_child(anchor)
			_assemble_machine(anchor, {"kind": kind, "cell": [0, 0], "axis": 0,
				"rotation": 0, "generation": 1})
			if production_batch:
				var rows: Array[Dictionary] = []
				_remember_machine_motion(placement, kind, Transform3D.IDENTITY, rows)
				placement.set_meta("motion_meshes", rows)
		built_meshes = _mesh_count(fixture_root)
		if inventory_only:
			_collect_triangle_inventory(fixture_root, {})
		var batch_start := Time.get_ticks_usec()
		if production_batch:
			_batch_machine_visuals()
			if mesh_lod:
				_prepare_composite_lod()
			var batches := machine_root.get_node_or_null("MachineVisualBatches")
			if batches != null:
				for visual in batches.get_children():
					if visual is MultiMeshInstance3D:
						batch_instances += visual.multimesh.instance_count
						batch_draw_groups += 1
		elif batch_static:
			_batch_repeated_meshes()
		batch_ms = float(Time.get_ticks_usec() - batch_start) / 1000.0
		build_ms = float(Time.get_ticks_usec() - start) / 1000.0
		camera.fov = 58.0
		camera.far = 130.0
		var reach := maxf(13.0, float(columns) * PITCH * 1.45)
		camera.position = Vector3(field_x + reach * 0.65, reach * 0.83, 1.65 + reach * 0.95)
		camera.look_at(Vector3(field_x, 0.3, 1.65))
		if camera_close and asset_count > 0:
			var near_machine := fixture_root.get_child(asset_count / 2) as Node3D
			camera.position = near_machine.position + Vector3(3.4, 2.5, 5.8)
			camera.look_at(near_machine.position + Vector3(0.0, 0.9, 0.0))
		camera.make_current()

	func _process(_delta: float) -> void:
		# Keep the view and asset geometry fixed for equivalent frame comparisons.
		pass

	func _prepare_composite_lod() -> void:
		var batches := machine_root.get_node_or_null("MachineVisualBatches") as Node3D
		if batches == null:
			return
		# Preserve the composite surfaces and material finishes while testing
		# Godot's default one-pixel mesh LOD threshold.
		for batch_index in 3:
			var original := batches.get_node_or_null("MachineBatch%d" % batch_index) as MultiMeshInstance3D
			if original == null:
				continue
			var importer := ImporterMesh.from_mesh(original.multimesh.mesh)
			var start := Time.get_ticks_usec()
			importer.generate_lods(60.0, 60.0, [])
			var lod_mesh := importer.get_mesh()
			var lod_counts: Array[int] = []
			for surface_index in importer.get_surface_count():
				lod_counts.append(importer.get_surface_lod_count(surface_index))
			lod_inventory.append({"batch": batch_index, "surface_lods": lod_counts,
				"generation_ms": float(Time.get_ticks_usec() - start) / 1000.0})
			original.multimesh.mesh = lod_mesh

	func _mesh_count(node: Node) -> int:
		var count := int(node is MeshInstance3D)
		for child in node.get_children():
			count += _mesh_count(child)
		return count

	func _collect_triangle_inventory(node: Node, cache: Dictionary) -> void:
		if node is MeshInstance3D:
			var part := node as MeshInstance3D
			if part.mesh != null:
				var mesh: Mesh = part.mesh
				var mesh_id := mesh.get_instance_id()
				if not cache.has(mesh_id):
					cache[mesh_id] = mesh.get_faces().size() / 3
				var role := str(part.name)
				if role.begins_with("@MeshInstance3D@"):
					role = "(unnamed MeshInstance3D)"
				if not triangle_inventory.has(role):
					triangle_inventory[role] = {"instances": 0, "triangles": 0}
				triangle_inventory[role].instances += 1
				triangle_inventory[role].triangles += cache[mesh_id]
		for child in node.get_children():
			_collect_triangle_inventory(child, cache)

	func _collect_meshes(node: Node, groups: Dictionary) -> void:
		if node is MeshInstance3D:
			var part := node as MeshInstance3D
			if part.visible and part.mesh != null:
				# The live opening helper copies any per-surface finish onto an exact
				# mesh resource that MultiMesh can share without dropping that finish.
				var prepared: Mesh = _machine_batch_surface_mesh(part)
				part.set_meta("fixture_batch_mesh", prepared)
				var finish := part.material_override
				if shared_conveyor_finish and part.name == "ConveyorLoop" \
						and finish is StandardMaterial3D:
					var conveyor_finish: StandardMaterial3D = ProductionConveyorArt.material()
					if conveyor_finish != null and (finish as StandardMaterial3D).uv1_offset == conveyor_finish.uv1_offset:
						# The fixed fixture never advances loop phase. Mount created
						# exact duplicates of this source finish for live belt motion.
						finish = conveyor_finish
				part.set_meta("fixture_batch_finish", finish)
				var overlay := part.material_overlay
				var key := str([prepared.get_instance_id(),
					finish.get_instance_id() if finish != null else 0,
					overlay.get_instance_id() if overlay != null else 0,
					part.cast_shadow, part.layers])
				if not groups.has(key):
					groups[key] = []
				groups[key].append(part)
		for child in node.get_children():
			_collect_meshes(child, groups)

	func _batch_repeated_meshes() -> void:
		var groups := {}
		_collect_meshes(fixture_root, groups)
		for key in groups:
			var parts: Array = groups[key]
			if parts.size() < 2:
				continue
			var example := parts[0] as MeshInstance3D
			var batch := MultiMesh.new()
			batch.transform_format = MultiMesh.TRANSFORM_3D
			batch.mesh = example.get_meta("fixture_batch_mesh") as Mesh
			batch.instance_count = parts.size()
			for index in parts.size():
				var part := parts[index] as MeshInstance3D
				batch.set_instance_transform(index,
					fixture_root.global_transform.affine_inverse() * part.global_transform)
				part.visible = false
			var visual := MultiMeshInstance3D.new()
			visual.name = "RepeatedAssetDetail"
			visual.multimesh = batch
			visual.material_override = example.get_meta("fixture_batch_finish") as Material
			visual.material_overlay = example.material_overlay
			visual.cast_shadow = example.cast_shadow
			visual.layers = example.layers
			fixture_root.add_child(visual)
			batch_instances += parts.size()
			batch_draw_groups += 1

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
	if "--mixed-scale" in OS.get_cmdline_user_args():
		_mixed_scale_benchmark.call_deferred()
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

func _mixed_scale_benchmark() -> void:
	var count := 200
	var batched := false
	var production_batch := false
	var shared_conveyor_finish := false
	var profile_scene := false
	var inventory_only := false
	var mesh_lod := false
	var camera_close := false
	var capture := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--count="):
			count = int(argument.trim_prefix("--count="))
		elif argument == "--batch":
			batched = true
		elif argument == "--production-batch":
			production_batch = true
			batched = true
		elif argument == "--share-static-conveyor-finish":
			shared_conveyor_finish = true
		elif argument == "--profile-scene":
			profile_scene = true
		elif argument == "--inventory-only":
			inventory_only = true
		elif argument == "--mesh-lod":
			mesh_lod = true
		elif argument == "--camera-close":
			camera_close = true
		elif argument.begins_with("--capture="):
			capture = argument.trim_prefix("--capture=")
	if count < 0 or count > 1000:
		push_error("Choose 0 to 1,000 asset assemblies.")
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var view := MixedAssetScaleView.new()
	view.asset_count = count
	view.batch_static = batched
	view.production_batch = production_batch
	view.shared_conveyor_finish = shared_conveyor_finish
	view.inventory_only = inventory_only
	view.mesh_lod = mesh_lod
	view.camera_close = camera_close
	root.add_child(view)
	if inventory_only:
		var batch_rows: Array[Dictionary] = []
		var batches := view.machine_root.get_node_or_null("MachineVisualBatches") as Node3D
		if batches != null:
			for child in batches.get_children():
				if child is MultiMeshInstance3D:
					var visual := child as MultiMeshInstance3D
					var per_instance: int = visual.multimesh.mesh.get_faces().size() / 3
					batch_rows.append({"name": str(visual.name),
						"instances": visual.multimesh.instance_count,
						"triangles_per_instance": per_instance,
						"total_triangles": per_instance * visual.multimesh.instance_count})
		print("MIXED_MESH_INVENTORY " + JSON.stringify({"count": count,
			"roles": view.triangle_inventory, "batches": batch_rows,
			"lod_inventory": view.lod_inventory}))
		quit()
		return
	if profile_scene:
		var profiled: bool = await _profile_mixed_scene(view)
		quit(0 if profiled else 1)
		return
	var frame_ms: Array[float] = []
	var calls: Array[int] = []
	var primitives: Array[int] = []
	for frame in 150:
		var start := Time.get_ticks_usec()
		await process_frame
		if frame >= 30:
			frame_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
			calls.append(RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			primitives.append(RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	frame_ms.sort()
	calls.sort()
	primitives.sort()
	if not capture.is_empty():
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null or image.is_empty() or image.save_png(capture) != OK:
			push_error("Cannot save rendered asset frame.")
			quit(1)
			return
	print("MIXED_ASSET_SCALE " + JSON.stringify({"count": count, "batch": batched,
		"production_batch": production_batch,
		"mesh_lod": mesh_lod,
		"camera_close": camera_close,
		"lod_inventory": view.lod_inventory,
		"shared_conveyor_finish": shared_conveyor_finish,
		"built_meshes": view.built_meshes, "batch_instances": view.batch_instances,
		"batch_groups": view.batch_draw_groups, "build_ms": view.build_ms,
		"batch_ms": view.batch_ms,
		"median_ms": frame_ms[frame_ms.size() / 2],
		"p95_ms": frame_ms[int(frame_ms.size() * 0.95)],
		"draw_calls_median": calls[calls.size() / 2],
		"primitives_median": primitives[primitives.size() / 2],
		"viewport": root.size, "renderer":
			ProjectSettings.get_setting("rendering/renderer/rendering_method")}))
	quit()

func _profile_mixed_scene(view: MixedAssetScaleView) -> bool:
	# Diagnostic visibility ablations only. Every case starts from the same
	# complete constructed scene and restores its changed setting afterward.
	var scenery := view.get_node_or_null("ProductionScenery") as Node3D
	if scenery == null:
		push_error("The production scenery is required for a scene profile.")
		return false
	var cases: Array[Dictionary] = [{"name": "all_visible", "nodes": []}]
	cases.append({"name": "machine_field", "nodes": [view.machine_root]})
	for child in scenery.get_children():
		if child is Node3D:
			cases.append({"name": str(child.name), "nodes": [child]})
	var site_meshes: Array[Node3D] = []
	for child in view.get_children():
		if child is MeshInstance3D:
			site_meshes.append(child)
	cases.append({"name": "site_root_meshes", "nodes": site_meshes})
	var environment := scenery.get_node_or_null("WorksiteEnvironment") as WorldEnvironment
	if environment != null and environment.environment != null:
		cases.append({"name": "fog", "nodes": [], "fog": true})
	var sun := scenery.get_node_or_null("WorksiteSun") as DirectionalLight3D
	if sun != null:
		cases.append({"name": "sun_shadow", "nodes": [], "shadow": true})
	cases.append({"name": "all_visible_repeat", "nodes": []})
	var results: Array[Dictionary] = []
	for entry in cases:
		var hidden: Array = entry.nodes
		var fog_before := environment.environment.fog_enabled if entry.get("fog", false) else false
		var shadow_before := sun.shadow_enabled if entry.get("shadow", false) else false
		for node in hidden:
			(node as Node3D).visible = false
		if entry.get("fog", false):
			environment.environment.fog_enabled = false
		if entry.get("shadow", false):
			sun.shadow_enabled = false
		var frame_ms: Array[float] = []
		var calls: Array[int] = []
		var primitives: Array[int] = []
		for frame in 90:
			var start := Time.get_ticks_usec()
			await process_frame
			if frame >= 30:
				frame_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
				calls.append(RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
				primitives.append(RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		frame_ms.sort()
		calls.sort()
		primitives.sort()
		results.append({"name": entry.name, "median_ms": frame_ms[frame_ms.size() / 2],
			"p95_ms": frame_ms[int(frame_ms.size() * 0.95)],
			"draw_calls_median": calls[calls.size() / 2],
			"primitives_median": primitives[primitives.size() / 2]})
		for node in hidden:
			(node as Node3D).visible = true
		if entry.get("fog", false):
			environment.environment.fog_enabled = fog_before
		if entry.get("shadow", false):
			sun.shadow_enabled = shadow_before
	print("MIXED_SCENE_PROFILE " + JSON.stringify({"count": view.asset_count,
		"production_batch": view.production_batch, "cases": results}))
	return true
