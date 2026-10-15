extends SceneTree
## Paired kinematic/contact cases through the real engine-backed authority.

const Authority = preload("res://mechanics/authority.gd")
var authority
var scene
var observer
var with_view := false
var checks := 0
var failures: Array[String] = []
var report := {"status": "running", "cases": {}}
var boundaries: Array = []

class PhysicsObserver:
	extends Node3D
	signal measured(value: Dictionary)
	var subject
	var points: Dictionary = {}
	var requested := false
	func _physics_process(_delta: float) -> void:
		if not requested:
			return
		requested = false
		var result := {"bodies": {}, "overlaps": {}, "pending": subject.pending,
			"node_positions": subject.projection().positions, "attempts": subject.attempts,
			"committed": subject.committed}
		for branch in ["B", "U"]:
			# Read the engine RID, not the presentation or owner's formula.
			var transform: Transform3D = PhysicsServer3D.body_get_state(subject.get_node(branch).get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			result.bodies[branch] = [transform.origin.x, transform.origin.y, transform.origin.z]
		for label in points:
			var sphere := SphereShape3D.new()
			sphere.radius = 0.035
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = sphere
			query.transform = Transform3D(Basis.IDENTITY, points[label])
			query.collision_mask = 15
			query.collide_with_areas = true
			var names: Array = []
			for hit in get_world_3d().direct_space_state.intersect_shape(query):
				names.append(str(hit.collider.get_meta("fixture_id", "unknown")))
			names.sort()
			result.overlaps[label] = names
		measured.emit(result)

func _initialize() -> void:
	with_view = OS.get_cmdline_user_args().has("--with-view")
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func send(intent: Dictionary) -> Dictionary:
	return scene.issue(intent) if with_view else authority.command(intent)

func fresh() -> void:
	if observer != null:
		observer.queue_free()
	if scene != null:
		scene.queue_free()
		scene = null
	elif authority != null:
		authority.queue_free()
	# A prior test can resume inside an emitted physics signal. Let that stack
	# unwind before removing its authority and registering a fresh collision rig.
	await process_frame
	if with_view:
		scene = load("res://mechanics/main.tscn").instantiate()
		scene.auto_advance = false
		root.add_child(scene)
		authority = scene.authority
	else:
		authority = Authority.new()
		root.add_child(authority)
	observer = PhysicsObserver.new()
	# Explicitly run the independent observer after the authority's callback,
	# both in its integrating frame and its earliest completion frame.
	observer.process_physics_priority = 10
	observer.subject = authority
	root.add_child(observer)
	await physics_frame
	await physics_frame
	check(authority.projection().members == ["B", "U"], "Stable fixture membership after explicit fresh reset")

func step() -> Dictionary:
	var before: Dictionary = authority.projection()
	var completion_result := {}
	authority.advanced.connect(func(value: Dictionary): completion_result["value"] = value, CONNECT_ONE_SHOT)
	var admission := send({"action": "step"})
	check(admission.accepted, "Step admitted to physics boundary")
	if not admission.accepted:
		return {"accepted": false, "state": authority.projection()}
	var queued: Dictionary = authority.projection()
	var duplicate := send({"action": "step"})
	check(not duplicate.accepted and duplicate.reason == "step_pending", "Queued step cannot admit a duplicate advance")
	check(authority.projection() == queued, "Refused duplicate preserves queued operation")
	var integrating: Dictionary = await measure({})
	check(integrating.pending, "Step remains pending after Node update until native completion boundary")
	if with_view:
		scene._refresh()
		var projection: Dictionary = authority.projection()
		check(scene.stats.text.begins_with("NATIVE UPDATE PENDING"), "Actual view labels unfinished native operation as pending")
		for branch in ["B", "U"]:
			if projection.completed.is_empty():
				check(not scene.sliders[branch].visible, "View hides bodies until first coherent native observation")
			else:
				check(near(scene.sliders[branch].position.x, projection.completed.positions[branch][0]),
					"View retains last completed body pose during tentative phase")
	if integrating.pending:
		var in_flight: Dictionary = authority.projection()
		var early := send({"action": "coupling", "active": not authority.coupled})
		check(not early.accepted and early.reason == "step_pending", "Topology change cannot enter the native integration window")
		check(authority.projection() == in_flight, "Refused in-flight command preserves phase/topology/native operation")
	var outcome: Dictionary
	if completion_result.has("value"):
		outcome = completion_result.value
	else:
		outcome = await authority.advanced
	var completed: Dictionary = await measure({})
	var coherent: bool = not completed.pending
	for branch in ["B", "U"]:
		for axis in range(3):
			coherent = coherent and near(completed.bodies[branch][axis], outcome.state.positions[branch][axis])
	check(coherent, "Earliest published completion matches actual native poses before another sweep")
	check(completed.attempts == before.attempts + 1 and completed.committed == before.committed + (1 if outcome.accepted else 0),
		"One admitted request produces exactly one attempted/committed native operation")
	var input_delta: float = PI / 8 if outcome.accepted else 0.0
	check(near(outcome.state.source_phase - before.source_phase, input_delta), "Source advances once per completed request")
	check(near(outcome.state.phases.U - before.phases.U, input_delta * 0.5), "Clear U advances once, including while B is isolated")
	var b_delta: float = input_delta * 20.0 / float(before.teeth) * (1.0 if before.idler else -1.0) if before.coupled else 0.0
	check(near(outcome.state.phases.B - before.phases.B, b_delta), "B advances once if connected and stays retained if isolated")
	boundaries.append({"before": {"attempts": before.attempts, "committed": before.committed, "source": before.source_phase,
		"phases": before.phases, "coupled": before.coupled, "teeth": before.teeth, "idler": before.idler},
		"integrating": integrating, "completed": completed, "accepted": outcome.accepted,
		"published": {"source": outcome.state.source_phase, "phases": outcome.state.phases, "positions": outcome.state.positions}})
	return outcome

func measure(points: Dictionary) -> Dictionary:
	observer.points = points
	observer.requested = true
	var value: Dictionary = await observer.measured
	return value

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 800)
	await fresh()
	check(send({"action": "edit_mount", "branch": "U", "cell": [0, 4]}).accepted,
		"Real stationary construction command changes declared lane mount")
	if with_view:
		await key(KEY_SPACE)
		check(authority.running, "Actual view Space input starts shared authority")
	else:
		check(send({"action": "run", "active": true}).accepted, "Headless source starts")
	var positive_two: Dictionary
	var positive_four: Dictionary
	for tick in range(8):
		var outcome: Dictionary = await step()
		check(outcome.accepted, "Clear positive drive step " + str(tick))
		if tick == 1:
			positive_two = outcome.state
		if tick == 3:
			positive_four = outcome.state
	var quarter: Dictionary = authority.projection()
	check(near(quarter.source_phase, PI) and near(quarter.phases.B, PI / 2), "20:40 pair with idler gives positive half-rate drive")
	check(near(quarter.positions.B[0], 2.0) and quarter.contact_entries == 1,
		"Signed drive reaches actual non-consuming work encounter")
	var physical: Dictionary = await measure({"at_endpoint": Vector3(2, 0.75, 0), "at_construction": Vector3(0, 0.75, 0)})
	check(near(physical.bodies.B[0], 2.0) and near(physical.bodies.U[2], 4.0),
		"Engine body transforms follow operating phase and accepted global construction mount")
	check(physical.overlaps.at_endpoint.has("B") and not physical.overlaps.at_construction.has("B"),
		"Native overlap sees collider at moved endpoint, not parent-only visual construction pose")
	var before_edit: Dictionary = authority.projection()
	check(not send({"action": "edit_mount", "branch": "U", "cell": [0, 3]}).accepted,
		"Construction in motion refused by authority")
	check(authority.projection() == before_edit, "Refused construction preserves complete topology/phase state")
	for _tick in range(24):
		check((await step()).accepted, "Complete fixed out/return cycle")
	var cycle: Dictionary = authority.projection()
	check(near(cycle.phases.B, TAU) and near(cycle.positions.B[0], 0), "One declared 32-step cycle returns without resetting phase")
	check(cycle.committed == 32 and cycle.contact_entries == 1, "Complete cycle retains finite encounter history; no injected work")
	report.cases.clear = {"two": positive_two, "four": positive_four, "quarter": quarter, "cycle": cycle, "physical": physical}
	# Changing mesh parity alters the actual first-quarter encounter, not just gears.
	await fresh()
	check(send({"action": "gearing", "idler": false, "teeth": 40}).accepted, "Initial one-mesh route configured")
	send({"action": "run", "active": true})
	for _tick in range(8):
		check((await step()).accepted, "Negative drive remains physically clear")
	var negative: Dictionary = authority.projection()
	check(near(negative.phases.B, -PI / 2) and near(negative.positions.B[0], -2), "One mesh reverses real slider direction")
	check(negative.contact_entries == 0, "Wrong signed drive misses the work encounter at matched input advancement")
	report.cases.negative = negative
	await fresh()
	check(send({"action": "gearing", "idler": true, "teeth": 20}).accepted, "Initial equal-gear ratio configured")
	send({"action": "run", "active": true})
	for _tick in range(2):
		await step()
	var faster_two: Dictionary = authority.projection()
	check(faster_two.contact_entries == 1 and positive_two.contact_entries == 0,
		"Ratio changes actual contact timing at identical input advancement")
	for _tick in range(2):
		await step()
	var faster_four: Dictionary = authority.projection()
	check(near(faster_four.phases.B, PI / 2) and near(positive_four.phases.B, PI / 4), "Equal gears double output phase versus 20:40 control")
	report.cases.ratio = {"two": faster_two, "four": faster_four}
	# Real static obstruction: all connected phases refuse the same proposed step.
	await fresh()
	send({"action": "fixture_obstacle", "active": true})
	send({"action": "run", "active": true})
	for _tick in range(2):
		check((await step()).accepted, "Approach to solid obstruction is clear")
	var approach: Dictionary = authority.projection()
	var body_ids := [authority.bodies.B.get_instance_id(), authority.bodies.U.get_instance_id()]
	var stopped: Dictionary = await step()
	check(not stopped.accepted and stopped.state.last_collision.collider == "blocker", "Actual native body sweep detects real solid obstacle")
	check(stopped.state.phases == approach.phases and stopped.state.source_phase == approach.source_phase,
		"Connected obstruction stalls source, B and U without phase reset")
	check(stopped.state.positions == approach.positions and stopped.state.members == approach.members,
		"Blocked admission preserves both native members and positions; no destruction")
	var blocked_physics: Dictionary = await measure({"solid": Vector3(1.4, 0.75, 0)})
	check(blocked_physics.overlaps.solid.has("blocker"), "Independent space query confirms obstruction is really in the lane")
	check(send({"action": "coupling", "active": false}).accepted, "Actual control opens coupling K")
	var isolated: Dictionary = (await step()).state
	check(near(isolated.phases.B, approach.phases.B) and isolated.phases.U > approach.phases.U,
		"Isolation retains B while U and the source advance")
	var isolated_physics: Dictionary = await measure({})
	check(near(isolated_physics.bodies.B[0], approach.positions.B[0]) and isolated_physics.bodies.U[0] > blocked_physics.bodies.U[0],
		"Isolation changes real U collider while B collider remains retained")
	send({"action": "run", "active": false})
	var misaligned: Dictionary = authority.projection()
	var refused := send({"action": "coupling", "active": true})
	check(not refused.accepted and refused.reason == "coupling_misaligned", "Misaligned stopped re-engagement is explicitly refused")
	check(authority.projection() == misaligned, "Misaligned re-engagement cannot jump retained phase")
	send({"action": "run", "active": true})
	for _tick in range(31):
		check((await step()).accepted, "Clear isolated branch continues to declared coupling alignment")
	send({"action": "run", "active": false})
	send({"action": "fixture_obstacle", "active": false})
	var before_engage: Dictionary = authority.projection()
	check(send({"action": "coupling", "active": true}).accepted, "Stopped aligned coupling re-engages")
	check(authority.projection().phases == before_engage.phases, "Re-engagement preserves both unwrapped branch phases")
	send({"action": "run", "active": true})
	var recovered: Dictionary = await step()
	check(recovered.accepted and near(recovered.state.phases.B, approach.phases.B + PI / 16),
		"Obstacle removal resumes retained B at its next phase, not home")
	check(body_ids == [authority.bodies.B.get_instance_id(), authority.bodies.U.get_instance_id()],
		"Stall/isolation/recovery preserves actual machine-body identities")
	var recovered_physics: Dictionary = await measure({"old_obstacle": Vector3(1.4, 0.75, 0)})
	check(not recovered_physics.overlaps.old_obstacle.has("blocker"), "Removed obstacle's native collider is parked off the lane")
	report.cases.obstruction = {"approach": approach, "blocked": stopped.state, "physical": blocked_physics,
		"isolated": isolated, "isolated_physical": isolated_physics, "before_engage": before_engage,
		"recovered": recovered.state, "recovered_physical": recovered_physics}
	# Same command boundary: geometry changes, then immediate first intersecting
	# request. No observer/physics wait is inserted before that step admission.
	await fresh()
	send({"action": "run", "active": true})
	for _tick in range(2):
		await step()
	var geometry_before: Dictionary = authority.projection()
	check(send({"action": "fixture_obstacle", "active": true}).accepted, "Same-boundary solid geometry update admitted")
	var immediate_block: Dictionary = await step()
	check(not immediate_block.accepted and immediate_block.state.phases == geometry_before.phases,
		"First intersecting sweep sees newly moved native obstacle without a test sync wait")
	check(send({"action": "fixture_obstacle", "active": false}).accepted, "Same-boundary solid removal admitted")
	var immediate_clear: Dictionary = await step()
	check(immediate_clear.accepted and near(immediate_clear.state.phases.B, 3 * PI / 16),
		"First sweep after removal sees clear native geometry and resumes retained phase")
	report.cases.immediate_geometry = {"before": geometry_before, "blocked": immediate_block.state, "cleared": immediate_clear.state}
	if with_view:
		await process_frame
		var drawn: Vector3 = scene.sliders.B.position
		check(near(drawn.x, immediate_clear.state.positions.B[0]), "Actual rendered consumer follows shared authoritative body projection")
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture=") and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "Real viewport capture saved")
	report.status = "pass" if failures.is_empty() else "fail"
	report["checks"] = checks
	report["boundaries"] = boundaries
	report["failures"] = failures
	report["consumer"] = "rendered_view" if with_view else "headless_physics"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	print("MECHANICS_PASS: %d actual physics checks" % checks if failures.is_empty() else "MECHANICS_FAIL: " + JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
