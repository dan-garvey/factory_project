extends "res://opening/native_adapter_check.gd"
## Automated native-body integration. This does not control a desktop.
const CogGeometry = preload("res://opening/site_geometry.gd")
var wheel_id := ""
var collector_id := ""
var gear_a := ""
var gear_b := ""
var first_gear_wire: Dictionary = {}

func _point3(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate in value:
		if not coordinate is float or not is_finite(coordinate):
			return false
	return true

func _anchor(center: Array) -> Array:
	var unit := CogGeometry.PITCH / 4.0
	return [float(center[0]) * unit, float(center[1]) * unit + CogGeometry.ANCHOR_HEIGHT, float(center[2]) * unit]

func _command(action: Dictionary, targets: Array, accepted := true, reason := "ok") -> Dictionary:
	var reply: Dictionary = _issue(action)
	if not _expect(reply.get("accepted") == accepted and reply.get("reason") == reason,
		"The actual cog command must have its declared outcome: " + str(action)):
		return {}
	var step: Dictionary = facts.steps[-1]
	var cut: Dictionary = step.native_cut
	var sample: Dictionary = cut.get("sample", {})
	var reach: Dictionary = reply.get("reach", {})
	if not _expect(cut.get("available", false) and cut.get("actor") == "P" and sample.get("ready", false) and sample.get("registered", false),
		"Every new command must retain its actual registered actor cut"):
		return {}
	if not _expect(sample.get("native_epoch") is int and sample.native_epoch > 0 and sample.native_epoch == reply.get("native_epoch") and reach.get("native_epoch") == sample.native_epoch,
		"The receipt and native sample must name the same positive observation ordinal"):
		return {}
	if not _expect(_point3(sample.get("position")) and _point3(sample.get("node_position")) and _point3(reach.get("position")) and _point3(reply.get("actor_position")),
		"Admission positions must contain exactly three finite native floating coordinates"):
		return {}
	if not _expect(_same(sample.position, reach.position) and _same(sample.position, reply.actor_position) and _same(sample.position, sample.node_position),
		"Native, node and authority positions must agree without a reach tolerance"):
		return {}
	if not _expect(sample.get("space", 0) > 0 and sample.space == sample.get("expected_space") and sample.get("body_ticks", 0) > 0 and sample.get("on_floor", false) and _same(sample.get("control"), [0.0, 0.0]) and not sample.get("jump_queued", true),
		"The admitted body must be registered, stepped, grounded and released"):
		return {}
	if not _expect(reach.get("actor") == "P" and reply.get("client") == "P" and reach.get("build_reach") is float and reach.build_reach == 4.0 and _same(reach.get("targets"), targets),
		"Reach must use the literal placed-part anchors and the fixed four-unit capability"):
		return {}
	var distances: Array = []
	var reachable := true
	for target in targets:
		if not _expect(_point3(target), "Each literal target is exactly three finite coordinates"):
			return {}
		var squared := 0.0
		for axis in range(3):
			var delta: float = sample.position[axis] - target[axis]
			squared += delta * delta
		distances.append(squared)
		reachable = reachable and squared <= 16.0
	if not _expect(_same(reach.get("distances_squared"), distances) and reach.get("reachable") == reachable and reachable == accepted,
		"Scalar three-dimensional reach must independently explain this accepted or refused cut"):
		return {}
	return reply

func _gear(center: Array) -> Dictionary:
	return {"action": "place_gear", "center": center, "axis": "y", "teeth": 2}

func _motion(id: String, numerator: int) -> bool:
	return _expect(_same(opening.model.projection().motion.get(id), {"state": "rotating", "numerator": numerator, "denominator": 1}),
		"The native train must derive the literal signed rate for " + id)

func _custody(gears_in_kit: int, raw_in_cargo: int, raw_in_collector: int) -> bool:
	var state: Dictionary = opening.model.projection()
	var expected_stock := {"source": 15, "collector": raw_in_collector, "belt": 0, "input": 0, "held": 0, "output": 0, "player": 0}
	var expected_kit := {"collector": 0, "belt": 1, "processor": 1, "wheel": 0, "gear": gears_in_kit, "shaft": 1}
	if not _expect(_same(state.stock, expected_stock) and _same(state.parts, expected_kit) and _same(state.cargo.P, {"raw": raw_in_cargo, "products": 0, "work_lots": []}) and state.inventories.P == 0 and 15 + raw_in_cargo + raw_in_collector == 16,
		"The literal raw custody and carried physical kit must remain exact"):
		return false
	var gears := 0
	var shafts := 0
	for part in state.transmission_parts.values():
		if part.kind == "gear":
			gears += 1
			if not _expect(part.teeth is int and part.teeth == 2 and part.axis == 1, "Placed gears use the original carried specification and Y axis"):
				return false
		elif part.kind == "shaft":
			shafts += 1
			if not _expect(part.half_span is int and part.half_span == 2 and part.axis == 1, "Placed shafts retain their original finite dimensions"):
				return false
		else:
			return _expect(false, "The transmission view must not invent another part kind")
	return _expect(gears + gears_in_kit == 2 and shafts == 2, "Placed and carried transmission parts conserve both original gears and all three shafts")

func _save() -> bool:
	var result: Dictionary = opening._save_worksite()
	facts["save_result"] = result
	facts["save_slot"] = opening.save_slot
	return _expect(result.get("accepted", false) and result.get("native_preflight", {}).get("accepted", false) and FileAccess.file_exists(opening.save_slot),
		"Store must publish the same native World after a real body preflight")

func _run() -> void:
	facts.evidence = "native_cog_body_and_store_consumer"
	if destination.is_empty() or mode not in ["produce", "resume"] or FileAccess.file_exists(destination):
		push_error("The native cog consumer needs a fresh output and a declared mode")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	root.add_child(opening)
	if not _expect(opening.model is NativeModel and opening.model.native.get_class() == "FactoryNativeWorld", "The ordinary scene must use the sole native World"):
		return
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		await process_frame
		if opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending:
			break
	if not _expect(opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending, "The actual actor must initialize and settle before commands"):
		return
	facts["initial_projection"] = opening.model.projection()
	facts["initial_native"] = opening.actor_world.diagnostics("P")
	if mode == "resume":
		_resume()
	else:
		await _produce()

func _produce() -> void:
	var original: Dictionary = opening.model.checkpoint().world.state
	var far := [-4, 16, 8]
	if _command(_gear(far), [_anchor(far)], false, "out_of_reach").is_empty():
		return
	if not _expect(_same(original, opening.model.checkpoint().world.state), "Vertical reach refusal cannot consume a part or alter material"):
		return
	var wheel: Dictionary = _command({"action": "place", "kind": "wheel", "cell": [-1, 1], "axis": "y"}, [_anchor([-4, 0, 4])])
	if wheel.is_empty():
		return
	wheel_id = wheel.entity
	var collector: Dictionary = _command({"action": "place", "kind": "collector", "cell": [0, 1], "axis": "y"}, [_anchor([0, 0, 4])])
	if collector.is_empty():
		return
	collector_id = collector.entity
	var a: Dictionary = _command(_gear([-4, 4, 4]), [_anchor([-4, 4, 4])])
	if a.is_empty():
		return
	gear_a = a.entity
	var b: Dictionary = _command(_gear([0, 4, 4]), [_anchor([0, 4, 4])])
	if b.is_empty():
		return
	gear_b = b.entity
	first_gear_wire = opening.model.checkpoint().world.history.records[-1].intent.wire.duplicate(true)
	facts["first_gear_wire"] = first_gear_wire.duplicate(true)
	if _command({"action": "connect_drive", "from": wheel_id, "to": gear_a}, [_anchor([-4, 0, 4]), _anchor([-4, 4, 4])]).is_empty() or _command({"action": "connect_drive", "from": gear_b, "to": collector_id}, [_anchor([0, 4, 4]), _anchor([0, 0, 4])]).is_empty():
		return
	if _command({"action": "set_power", "active": true}, [_anchor([-4, 0, 4])]).is_empty() or not _motion(gear_a, 1) or not _motion(gear_b, -1) or not _motion(collector_id, -1):
		return
	while Time.get_ticks_msec() < deadline and opening.model.projection().stock.collector != 1:
		await process_frame
	if not _custody(0, 0, 1):
		return
	if _command({"action": "remove", "entity": gear_b}, [_anchor([0, 4, 4])]).is_empty() or not _expect(not opening.model.projection().powered, "Running removal must actually interrupt collector transmission"):
		return
	var misplaced: Dictionary = _command(_gear([1, 4, 4]), [_anchor([1, 4, 4])])
	if misplaced.is_empty() or not _expect(not opening.model.projection().powered, "A one-grid displacement cannot preserve the old mesh or shaft power"):
		return
	if _command({"action": "remove", "entity": misplaced.entity}, [_anchor([1, 4, 4])]).is_empty():
		return
	var rebuilt: Dictionary = _command(_gear([0, 4, 4]), [_anchor([0, 4, 4])])
	if rebuilt.is_empty() or not _expect(rebuilt.entity != gear_b and opening.model.projection().powered, "Correct rebuilding must restore geometry using a new part identity"):
		return
	var replay: Dictionary = opening.model.command(first_gear_wire)
	facts["historical_retry"] = replay.duplicate(true)
	if not _expect(replay.get("accepted", false) and replay.get("duplicate", false) and replay.get("entity") == gear_b, "The removed gear's exact old request cannot be retargeted to its replacement"):
		return
	gear_b = rebuilt.entity
	if _command({"action": "disconnect_drive", "from": gear_b, "to": collector_id}, [_anchor([0, 4, 4]), _anchor([0, 0, 4])]).is_empty() or not _expect(opening.model.projection().parts.shaft == 2 and not opening.model.projection().powered, "Disconnect returns one actual shaft and removes collector power"):
		return
	if _command({"action": "connect_drive", "from": gear_b, "to": collector_id}, [_anchor([0, 4, 4]), _anchor([0, 0, 4])]).is_empty() or _command({"action": "set_power", "active": false}, [_anchor([-4, 0, 4])]).is_empty():
		return
	if not _expect(opening.model.projection().order == 15, "Every accepted or refused original intent must remain in the fifteen-request history") or not _custody(0, 0, 1) or not _save():
		return
	_record("pass")

func _resume() -> void:
	var input := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="):
			input = argument.trim_prefix("--resume-input=")
	if not _expect(not input.is_empty() and opening.last_load_result.get("accepted", false), "The fresh ordinary scene must load the original Store input"):
		return
	var bytes := FileAccess.get_file_as_bytes(input)
	var saved = bytes_to_var(bytes.slice("FACTORY-SAVE-1\n".length() + 65))
	facts["loaded_before_native"] = opening.startup_resume_checkpoint.duplicate(true)
	if not _expect(saved is Dictionary and _same(saved, opening.startup_resume_checkpoint) and _same(saved.world, opening.model.checkpoint().world), "All original typed geometry, material, kit and cache must survive before fresh commands"):
		return
	if not _expect(opening.request_sequence == 0 and opening.model.projection().order == 15 and _same(opening.actor_world.seeds, saved.actors), "Fresh startup must preserve native seeds and issue zero material requests") or not _custody(0, 0, 1):
		return
	for id in opening.model.projection().entities:
		var entity: Dictionary = opening.model.projection().entities[id]
		if entity.kind == "wheel":
			wheel_id = id
		elif entity.kind == "collector":
			collector_id = id
	for id in opening.model.projection().transmission_parts:
		var part: Dictionary = opening.model.projection().transmission_parts[id]
		if part.kind == "gear" and _same(part.center, [-4, 4, 4]):
			gear_a = id
		elif part.kind == "gear" and _same(part.center, [0, 4, 4]):
			gear_b = id
	if not _expect(not wheel_id.is_empty() and not collector_id.is_empty() and not gear_a.is_empty() and not gear_b.is_empty(), "The restored actual part identities must resolve from saved geometry"):
		return
	var old_gear: Dictionary = saved.world.history.records[4]
	var replay: Dictionary = opening.model.command(old_gear.intent.wire)
	facts["resumed_historical_retry"] = replay.duplicate(true)
	if not _expect(old_gear.intent.wire.action == "place_gear" and replay.get("accepted", false) and replay.get("duplicate", false) and replay.get("entity") == old_gear.result.entity and replay.entity != gear_b and _same(saved.world, opening.model.checkpoint().world),
		"A fresh process must replay the removed gear's old receipt without treating its old observation as a new admission"):
		return
	if _command({"action": "set_power", "active": true}, [_anchor([-4, 0, 4])]).is_empty() or not _motion(gear_a, 1) or not _motion(gear_b, -1) or not _motion(collector_id, -1):
		return
	if _command({"action": "disconnect_drive", "from": gear_b, "to": collector_id}, [_anchor([0, 4, 4]), _anchor([0, 0, 4])]).is_empty() or not _expect(not opening.model.projection().powered and opening.model.projection().parts.shaft == 2, "Fresh disconnect must return its real shaft"):
		return
	if _command({"action": "connect_drive", "from": gear_b, "to": collector_id}, [_anchor([0, 4, 4]), _anchor([0, 0, 4])]).is_empty() or _command({"action": "remove", "entity": gear_b}, [_anchor([0, 4, 4])]).is_empty():
		return
	if not _expect(opening.model.projection().power_enabled and not opening.model.projection().powered, "Fresh running gear removal must isolate the collector without disabling the source"):
		return
	if _command({"action": "recover", "entity": collector_id}, [_anchor([0, 0, 4])]).is_empty() or not _custody(1, 1, 0):
		return
	var final: Dictionary = opening.model.checkpoint()
	if not _expect(final.world.history.order == 20 and _same(saved.world.history.records, final.world.history.records.slice(0, 15)), "All fifteen original intents and outcomes must remain unchanged before five fresh operations") or not _save():
		return
	_record("pass")
