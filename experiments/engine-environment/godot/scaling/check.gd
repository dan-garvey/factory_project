extends SceneTree
## Real shared drive + spatial native-query consumer, headless and rendered.
const Authority = preload("res://scaling/authority.gd")
var authority
var scene
var with_view := false
var checks := 0
var failures: Array[String] = []
var cases := {}
var parent_boundaries: Array = []

func _initialize() -> void:
	with_view = OS.get_cmdline_user_args().has("--with-view")
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func send(intent: Dictionary) -> Dictionary:
	return scene.issue(intent) if with_view else authority.command(intent)

func native_facts() -> Dictionary:
	var heads: Array = []
	var rays: Array = []
	var head_shapes: Array = []
	var coupon_facts: Array = []
	for coupon in authority.coupons:
		var pose: Transform3D = PhysicsServer3D.body_get_state(coupon.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		var size: Vector3 = coupon.get_child(0).shape.size
		coupon_facts.append({"name": str(coupon.name), "position": [pose.origin.x, pose.origin.y, pose.origin.z], "size": [size.x, size.y, size.z], "layer": coupon.collision_layer})
	for head in authority.heads:
		var native: Transform3D = PhysicsServer3D.body_get_state(head.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		heads.append([native.origin.x, native.origin.y, native.origin.z])
		var size: Vector3 = head.get_child(0).shape.size
		head_shapes.append({"size": [size.x, size.y, size.z], "layer": head.collision_layer, "mask": head.collision_mask})
		var start := native.origin - native.basis.y * 0.2
		var query := PhysicsRayQueryParameters3D.create(start, start - native.basis.y * 1.2, 48)
		var hit: Dictionary = head.get_world_3d().direct_space_state.intersect_ray(query)
		var ray := {"from": [start.x, start.y, start.z], "to": [query.to.x, query.to.y, query.to.z], "hit": ""}
		if not hit.is_empty():
			ray.hit = str(hit.collider.name)
			ray.point = [hit.position.x, hit.position.y, hit.position.z]
			ray.normal = [hit.normal.x, hit.normal.y, hit.normal.z]
		rays.append(ray)
	var sources: Array = []
	for drive in authority.drives:
		var native: Transform3D = PhysicsServer3D.body_get_state(drive.bodies.B.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		sources.append({"body": [native.origin.x, native.origin.y, native.origin.z], "state": drive.projection()})
	var shield: Transform3D = PhysicsServer3D.body_get_state(authority.shield.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	return {"heads": heads, "sources": sources, "rays": rays, "coupons": coupon_facts,
		"shield": [shield.origin.x, shield.origin.y, shield.origin.z], "head_shapes": head_shapes,
		"shield_layer": authority.shield.collision_layer}

func parent_boundary(_outcome: Dictionary) -> void:
	if authority.remaining_drives != 0:
		return
	var before: Dictionary = authority.projection()
	check(before.pending and authority.awaiting_heads, "Outer request survives parent-drive completion")
	check(before.completed.steps == before.steps, "Parent completion cannot publish unfinished child geometry")
	check(not send({"action": "step"}).accepted, "No next request between parent and native-head completion")
	check(not send({"action": "run", "active": false}).accepted, "No source change between parent and native-head completion")
	check(not authority.configure("rotary_base"), "No construction change in native-head window")
	check(authority.projection() == before, "Rejected child-window controls preserve full owner state")
	var requested: Array = []
	for head in authority.heads:
		requested.append([head.position.x, head.position.y, head.position.z])
	parent_boundaries.append({"case": authority.case_name, "step_before": before.steps,
		"state": before, "native": native_facts(), "requested": requested})

func fresh(name: String) -> void:
	if scene != null:
		scene.queue_free()
		scene = null
	elif authority != null:
		authority.queue_free()
	await process_frame
	if with_view:
		scene = load("res://scaling/main.tscn").instantiate()
		scene.case_name = name
		scene.auto_advance = false
		root.add_child(scene)
		authority = scene.authority
	else:
		authority = Authority.new()
		check(authority.configure(name), "Initial fixture configuration")
		root.add_child(authority)
	# Wait on an explicit native/publication condition, not elapsed wall time.
	while authority.projection().completed.is_empty():
		await physics_frame
	check(not authority.configure("rotary_base"), "Construction configuration rejected after fixture admission")
	check(not send({"action": "step"}).accepted, "Stopped source cannot step")
	check(send({"action": "run", "active": true}).accepted, "Actual shared drive run control")
	for drive in authority.drives:
		drive.advanced.connect(parent_boundary)

func step() -> Dictionary:
	var before: Dictionary = authority.projection()
	var done := {}
	authority.advanced.connect(func(value: Dictionary): done["value"] = value, CONNECT_ONE_SHOT)
	check(send({"action": "step"}).accepted, "One source request admitted")
	check(not send({"action": "step"}).accepted, "No overlapping request")
	check(not send({"action": "run", "active": false}).accepted, "No run change during owned request")
	if not done.has("value"):
		await authority.advanced
	var state: Dictionary = authority.projection()
	var physical := native_facts()
	check(not state.pending and state.steps == before.steps + 1, "Once-only earliest completed publication")
	for index in range(physical.heads.size()):
		for axis in range(3):
			check(near(physical.heads[index][axis], state.completed.heads[index].position[axis]), "Independent native head pose equals published result")
		if with_view:
			# Completion signal refreshes the actual presentation consumer.
			check(scene.meshes[index].position.distance_to(Vector3(physical.heads[index][0], physical.heads[index][1], physical.heads[index][2])) < 0.00001,
				"Actual view renders completed native head pose")
	for index in range(physical.sources.size()):
		var source: Dictionary = physical.sources[index]
		check(source.state.committed == state.steps, "Inherited drive commits exactly once per source request")
		check(near(source.body[0], 2.0 * sin(state.completed.drives[index].phases.B)), "Independent native inherited slider follows the consumed branch phase")
	return {"state": state, "native": physical}

func _run() -> void:
	for name in Authority.CASES:
		await fresh(name)
		var samples: Array = [{"state": authority.projection(), "native": native_facts()}]
		for index in range(32):
			samples.append(await step())
		var result: Dictionary = authority.projection()
		cases[name] = {"final": result, "samples": samples}
		var expected := 0 if name in ["reversed_face", "low_mount", "far_mount", "shielded", "empty"] else 2 if name in ["gantry_base", "rotary_base", "overclock"] else 4
		check(result.completed.visited.size() == expected, name + " fixed common-site coverage")
		for encounter in result.completed.encounters:
			check(near(encounter.point[1], 0.1) and near(encounter.normal[1], 1.0), "Real top-face contact and outward native normal")
		check(result.completed.drives.size() == (2 if name == "duplicate" else 1), "Duplication uses actual separate drive owners")
		check(near(result.completed.drives[0].phases.B, TAU * (2 if name == "overclock" else 1)), "Complete inherited cycle, no local phase reset")
	# Final native rendered capture deliberately shows grown gantry after work.
	if with_view:
		await fresh("gantry_grown")
		for index in range(32):
			await step()
		await process_frame
		await RenderingServer.frame_post_draw
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture="):
				check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "Actual viewport PNG")
	var report := {"status": "pass" if failures.is_empty() else "fail", "checks": checks, "failures": failures, "cases": cases, "parent_boundaries": parent_boundaries}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report))
	print("SPATIAL_SCALING_PASS" if failures.is_empty() else "SPATIAL_SCALING_FAIL")
	quit(0 if failures.is_empty() else 1)
