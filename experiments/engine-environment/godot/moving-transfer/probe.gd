extends Node
## Shared actual consumer/oracles; no replacement stock or drive simulation.
var subject
var scene
var failures: Array = []
var checks := 0
var stage := "startup"
var report := {"schema": 1, "cases": {}, "events": [], "queued": [], "inputs": [], "cuts": [], "captures": []}
var capture_directory := ""
var _repeat_stop_requested := false
var _distance_control_queued := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func ledger(stock: Dictionary) -> void:
	expect(stock.keys().size() == 2 and stock.carrier is int and stock.receiver is int \
		and stock.carrier >= 0 and stock.receiver >= 0 and stock.carrier + stock.receiver == 3, "literal typed finite 3 A ledger")

func attach(authority) -> void:
	subject = authority
	subject.transfer_completed.connect(_event)
	subject.transfer_queued.connect(_queued)
	subject.cut_observed.connect(_cut_observed)

func _queued(receipt: Dictionary) -> void:
	ledger(receipt.stock)
	expect(receipt.status == "queued" and not receipt.final, "queue intake is explicitly not material admission")
	expect(subject.projection().stock == receipt.stock, "actual intake has not moved the owner's stock")
	report.queued.append(receipt.duplicate(true))

func _event(event: Dictionary) -> void:
	ledger(event.before)
	ledger(event.after)
	expect(event.owner == subject.get_instance_id(), "sole authority at every transfer attempt")
	if event.disposition.accepted and not event.duplicate:
		expect(event.after.carrier == event.before.carrier - 1 and event.after.receiver == event.before.receiver + 1,
			"one actual atomic unit from carrier to fixed receiver")
	else: expect(event.before == event.after, "refusal or replay cannot move stock")
	report.events.append({"stage": stage, "event": event.duplicate(true)})
	if scene != null and stage == "automatic_native_visit" and event.after.receiver == 3 and scene.repeat_source and not _repeat_stop_requested:
		# Actual input stops repeats before this goal completes, without a pose edit.
		_repeat_stop_requested = true
		inject(KEY_R, true)
		inject(KEY_R, false)

func _cut_observed(state: Dictionary) -> void:
	ledger(state.stock)
	report.cuts.append({"stage": stage, "owner": state.owner, "stock": state.stock.duplicate(true), "observation": state.observation.duplicate(true)})
	var native: Dictionary = state.observation.native
	if stage == "leave_without_requests" and not _distance_control_queued and native.distance > 0.08 and native.facing >= 0.997:
		# Labelled backend negative control, separate from ordinary moving P.
		# The every-cut latch has already observed the unrequested exit. This
		# intent queues for the next cut; no source/dock pose is changed.
		_distance_control_queued = true
		subject.command({"action": "transfer", "actor": "Q", "request": "distance-only", "kind": "A", "amount": 1})

func tick() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame

func inject(code: Key, pressed: bool) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = pressed
	report.inputs.append({"code": code, "pressed": pressed, "stage": stage, "frame": Engine.get_physics_frames()})
	Input.parse_input_event(press)

func key(code: Key) -> void:
	inject(code, true)
	await get_tree().process_frame
	inject(code, false)
	await get_tree().process_frame
	await tick()

func completed(response: Dictionary) -> Dictionary:
	if response.status != "queued": return response
	for _index in 8:
		for row in report.events:
			if row.event.queue_id == response.queue_id: return row.event
		await tick()
	expect(false, "queued intent reaches one final native-cut disposition")
	return {}

func action(code: Key, intent: Dictionary) -> void:
	if scene != null: await key(code)
	else:
		var response: Dictionary = subject.command(intent)
		if response.get("status") == "queued": await completed(response)

func transfer(actor: String, request: String, amount = 1) -> Dictionary:
	return await completed(subject.command({"action": "transfer", "actor": actor, "request": request, "kind": "A", "amount": amount}))

func last_event() -> Dictionary:
	return report.events.back().event

func wait_ready() -> void:
	for _index in 16:
		if not subject.projection().observation.is_empty() and subject.projection().observation.registered: return
		await tick()
	expect(false, "both actual native bodies reach declared initial readiness")

func wait_goal() -> void:
	for _index in 64:
		if not subject.pending: return
		await tick()
	expect(false, "bounded inherited native goal completes")

func capture(name_value: String) -> void:
	if scene == null: return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := capture_directory.path_join(name_value + ".png")
	expect(get_viewport().get_texture().get_image().save_png(path) == OK, "real ordinary viewport PNG")
	var state: Dictionary = subject.projection()
	var visible: Dictionary = scene.visible_facts()
	expect(visible.counts == state.stock, "actual visible cargo tokens agree with sole finite stock")
	report.captures.append({"name": name_value, "path": path, "state": state, "visible": visible})

func _moving(event: Dictionary) -> void:
	var observation: Dictionary = event.disposition.observation
	var angular: Array = observation.native.angular_velocity
	expect(event.disposition.accepted and not event.duplicate and observation.eligible and observation.drive.pending \
		and observation.intermediate and observation.port_displacement > 0.000001 \
		and Vector3(angular[0], angular[1], angular[2]).length() > 0.00001, "transfer at a genuinely changing intermediate native operating pose")

func run(ordinary_scene = null, control := false) -> Dictionary:
	scene = ordinary_scene
	report.mode = "wrong_facing_control" if control else ("ordinary_scene_input" if scene != null else "headless_authority")
	await wait_ready()
	if not failures.is_empty(): return finish()
	var bootstrap: Dictionary = report.events[0].event
	expect(bootstrap.disposition.reason == "native_not_ready" and bootstrap.before == bootstrap.after,
		"first pre-physics refusal retained, not hidden by warmup")
	var retry: Dictionary = await transfer("Q", "bootstrap")
	expect(retry.duplicate and retry.disposition == bootstrap.disposition and retry.before == retry.after,
		"cached startup refusal cannot retarget ready geometry")
	var original: Dictionary = subject.projection()
	var detached: Dictionary = subject.projection()
	detached.stock.carrier = 999
	detached.observation.window.id = 999
	detached.observation.native.outlet[0] = 999
	expect(subject.projection() == original, "read-only projections neither mutate stock nor contact latch")
	report.cases.readiness = {"bootstrap": bootstrap, "ready": original}
	if control:
		stage = "wrong_facing"
		var observation: Dictionary = subject.projection().observation
		expect(observation.native.distance < 0.00001 and observation.native.facing < -0.999 \
			and observation.registered and not observation.eligible, "native coincident port points isolate the facing gate")
		var refused: Dictionary = await transfer("P", "wrong-facing")
		expect(refused.disposition.reason == "ports_ineligible" and refused.after == {"carrier": 3, "receiver": 0}, "wrong-facing actual admission refuses without loss")
		for _index in 4: await tick()
		expect(subject.projection().observation.window.id == 0, "no contact visit opens for wrong facing")
		report.cases.wrong_facing = {"refused": refused, "final": subject.projection()}
		return finish()
	stage = "stationary_competition"
	if scene != null: await key(KEY_C)
	else:
		subject.command({"action": "transfer", "actor": "P", "request": "P-1", "kind": "A", "amount": 1})
		subject.command({"action": "transfer", "actor": "Q", "request": "Q-1", "kind": "A", "amount": 1})
		await tick()
	var first: Dictionary = report.events[-2].event
	var competitor: Dictionary = last_event()
	expect(first.disposition.reason == "transferred" and competitor.disposition.reason == "window_spent" \
		and first.current.native.frame == competitor.current.native.frame \
		and first.current.sample.cut == competitor.current.sample.cut, "fresh same-cut competing requests admit only one unit")
	await action(KEY_D, {"action": "transfer", "actor": "P", "request": "P-1", "kind": "A", "amount": 1})
	var repeated: Dictionary = last_event()
	expect(repeated.duplicate and repeated.disposition == first.disposition and repeated.before == repeated.after,
		"exact accepted retry returns immutable original receipt, no reapplication")
	var detached_receipt: Dictionary = await transfer("P", "P-1")
	detached_receipt.disposition.after.receiver = 999
	var preserved: Dictionary = await transfer("P", "P-1")
	expect(preserved.disposition == first.disposition, "caller cannot corrupt cached receipt")
	report.cases.stationary = {"first": first, "competitor": competitor, "state": subject.projection()}
	await capture("stationary-one-unit")
	if not failures.is_empty(): return finish()
	stage = "leave_without_requests"
	await action(KEY_F, {"action": "run", "active": true})
	await action(KEY_N, {"action": "step"})
	var before_edit: Dictionary = subject.projection()
	var edit: Dictionary = subject.command({"action": "edit_mount", "branch": "B", "cell": [0, 1]})
	expect(before_edit.pending and not edit.accepted and edit.reason == "fixed_passenger_fixture" \
		and subject.projection().mounts == before_edit.mounts, "unsupported edit during motion changes no fixture mount")
	await wait_goal()
	var distance_controls: Array = report.events.filter(func(row): return row.event.intent.request == "distance-only")
	expect(distance_controls.size() == 1, "one labelled backend distance-only refusal is retained")
	if distance_controls.size() == 1:
		var distance_only: Dictionary = distance_controls[0].event
		expect(distance_only.disposition.reason == "ports_ineligible" and distance_only.disposition.native.distance > 0.08 \
			and distance_only.disposition.native.facing >= 0.995, "actual refusal isolates distance with passing native facing")
		report.cases.distance_only = distance_only
	stage = "offsite"
	await action(KEY_Q, {"action": "transfer", "actor": "Q", "request": "Q-2", "kind": "A", "amount": 1})
	var offsite: Dictionary = last_event()
	expect(offsite.disposition.reason == "ports_ineligible" and not offsite.current.sample.window.inside, "actual separated native ports refuse")
	await action(KEY_D, {"action": "transfer", "actor": "P", "request": "P-1", "kind": "A", "amount": 1})
	var replay: Dictionary = last_event()
	expect(replay.duplicate and replay.disposition == first.disposition and not replay.current.native.geometric \
		and replay.disposition.native.geometric, "historical eligible receipt and current ineligible pose remain separate")
	var reused: Dictionary = await transfer("P", "P-1", 2)
	expect(reused.disposition.reason == "request_payload_reuse" and not reused.duplicate, "same identity with altered payload refuses")
	for amount in [true, -1, 0, 2, "1"]:
		var malformed: Dictionary = await transfer("Q", "bad-" + str(typeof(amount)) + "-" + str(amount), amount)
		expect(malformed.disposition.reason == "invalid_transfer" and malformed.before == malformed.after, "typed one-unit transfer boundary")
	report.cases.offsite = {"refused": offsite, "replay": replay, "payload_reuse": reused, "edit": edit}
	if not failures.is_empty(): return finish()
	stage = "manual_native_visit"
	if scene != null: await key(KEY_R)
	var moving: Array = []
	for _index in 1100:
		var observation: Dictionary = subject.projection().observation
		if observation.window.id == 2 and observation.eligible: break
		if scene == null and not subject.pending: subject.command({"action": "step"})
		await tick()
	expect(subject.projection().observation.window.id == 2 and subject.projection().observation.eligible, "natural no-request travel enters the second port visit")
	if not failures.is_empty(): return finish()
	# Ordinary manual request is submitted outside the physics callback. Enable
	# the sensor before the same next cut: FIFO manual wins, sensor must refuse.
	if scene != null:
		inject(KEY_P, true)
		inject(KEY_P, false)
		inject(KEY_T, true)
		inject(KEY_T, false)
	else:
		subject.command({"action": "transfer", "actor": "P", "request": "P-2", "kind": "A", "amount": 1})
		subject.command({"action": "automatic", "active": true})
	await tick()
	var manual: Dictionary = report.events[-2].event
	var sensor_competitor: Dictionary = last_event()
	_moving(manual)
	expect(sensor_competitor.intent.actor == "sensor" and sensor_competitor.disposition.reason == "window_spent" \
		and sensor_competitor.current.sample.cut == manual.current.sample.cut, "same-cut fresh automatic competitor cannot consume the manual admission twice")
	moving.append(manual.duplicate(true))
	report.cases.moving_competition = {"manual": manual, "sensor": sensor_competitor}
	await capture("moving-handoff")
	if not failures.is_empty(): return finish()
	stage = "automatic_native_visit"
	for _index in 2100:
		if subject.projection().stock.receiver == 3: break
		if scene == null and not subject.pending: subject.command({"action": "step"})
		await tick()
		if not failures.is_empty(): break
	var sensor: Dictionary = last_event()
	_moving(sensor)
	moving.append(sensor.duplicate(true))
	if scene != null:
		if scene.repeat_source and not _repeat_stop_requested:
			_repeat_stop_requested = true
			await key(KEY_R)
		for _index in 8:
			if not scene.repeat_source: break
			await tick()
		expect(not scene.repeat_source, "one requested repeat-off input has actually taken effect")
	await wait_goal()
	expect(moving.size() == 2 and subject.projection().stock == {"carrier": 0, "receiver": 3}, "two new native visits exhaust exactly the original three units")
	if not failures.is_empty(): return finish()
	stage = "empty_and_replay"
	await action(KEY_F, {"action": "run", "active": false})
	await action(KEY_P, {"action": "transfer", "actor": "P", "request": "P-3", "kind": "A", "amount": 1})
	var empty: Dictionary = last_event()
	expect(empty.disposition.reason == "source_empty" and empty.before == empty.after, "aligned empty source refuses without replenishment")
	var final_replay: Dictionary = await transfer("P", "P-1")
	expect(final_replay.duplicate and final_replay.disposition == first.disposition and final_replay.after == {"carrier": 0, "receiver": 3}, "old accepted retry never moves or replenishes exhausted stock")
	var final_window: Dictionary = subject.projection().observation.window
	for _index in 6: await tick()
	var stopped: Dictionary = subject.projection()
	expect(not stopped.running and not stopped.pending and stopped.queued_transfers == 0, "final fixture is actually stopped with no pending goal or transfer")
	expect(subject.projection().observation.window.id == final_window.id and subject.projection().observation.window.spent,
		"idle cuts keep the used visit closed without request polling")
	report.cases.moving = moving
	report.cases.final = {"state": subject.projection(), "empty": empty, "retry": final_replay}
	await capture("all-three-received")
	return finish()

func finish() -> Dictionary:
	report.merge({"status": "pass" if failures.is_empty() else "fail", "checks": checks, "failures": failures,
		"pid": OS.get_process_id(), "owner": subject.get_instance_id(), "user_play": "not_assessed"})
	return report

static func publish(path: String, value: Dictionary) -> bool:
	if path.is_empty() or FileAccess.file_exists(path): return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return true
