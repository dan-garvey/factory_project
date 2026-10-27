extends "res://opening/native_adapter_check.gd"
## Automated native-body integration. This does not control a desktop.
const CogGeometry = preload("res://opening/site_geometry.gd")
var wheel_id := ""
var collector_id := ""
var gear_a := ""
var gear_b := ""
var shaft_id := ""
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
	return {"action": "place_gear", "center": center, "axis": "z", "teeth": 4}

func _construct(action: Dictionary) -> Dictionary:
	if mode == "arrival-cog-resume":
		return super._construct(action)
	var center: Array = action.get("center", [])
	if center.is_empty():
		center = [action.cell[0] * 4, action.level, action.cell[1] * 4]
	return _command(action, [_anchor(center)])

func _motion(id: String, multiplier: int) -> bool:
	var motion: Dictionary = opening.model.projection().motion
	var source: Dictionary = motion[wheel_id]
	var rate: Dictionary = motion[id]
	return _expect(source.state == "rotating" and source.numerator != 0 and source.denominator > 0
		and rate.state == "rotating" and rate.denominator > 0
		and rate.numerator * source.denominator == multiplier * source.numerator * rate.denominator,
		"The real immersed source and declared corner geometry determine the signed rate for " + id)

func _custody(gears_in_kit: int, raw_in_cargo: int, raw_in_collector: int) -> bool:
	var state: Dictionary = opening.model.projection()
	var expected_stock := {"source": 4095, "collector": raw_in_collector, "belt": 0, "input": 0, "held": 0, "output": 0, "player": 0}
	var expected_kit := {"collector": 0, "belt": 2, "processor": 1, "wheel": 0, "gear": gears_in_kit + 8,
		"shaft": 7, "foundation": 23, "gearbox": 2, "vertical_gearbox": 2, "chain_drive": 8}
	if not _expect(_same(state.stock, expected_stock) and _same(state.parts, expected_kit) and _same(state.cargo.P, {"raw": raw_in_cargo, "products": 0, "work_lots": []}) and state.inventories.P == 0 and 4095 + raw_in_cargo + raw_in_collector == 4096,
		"The literal raw custody and carried physical kit must remain exact"):
		return false
	var gears := 0
	var shafts := 0
	for part in state.transmission_parts.values():
		if part.kind == "gear":
			gears += 1
			if not _expect(part.teeth is int and part.teeth == 4 and part.axis in [0, 2], "Placed corner cogs retain their carried large specification and perpendicular horizontal axes"):
				return false
		elif part.kind == "shaft":
			shafts += 1
			if not _expect(part.half_span is int and part.half_span == 2 and part.axis == 2, "Placed shafts retain their original finite dimensions on Z"):
				return false
		else:
			return _expect(false, "The transmission view must not invent another part kind")
	return _expect(gears + gears_in_kit == 2 and shafts == 1 and state.foundations.size() == 1,
		"The two large cogs, one actual shaft, one foundation and all current spare parts remain conserved")

func _save() -> bool:
	var result: Dictionary = opening._save_worksite()
	facts["save_result"] = result
	facts["save_slot"] = opening.save_slot
	return _expect(result.get("accepted", false) and result.get("native_preflight", {}).get("accepted", false) and FileAccess.file_exists(opening.save_slot),
		"Store must publish the same native World after a real body preflight")

func _run() -> void:
	facts.evidence = "native_cog_body_and_store_consumer"
	if destination.is_empty() or mode not in ["produce", "resume", "arrival-cog-resume",
			"arrival-cog-finish-resume"] or FileAccess.file_exists(destination):
		push_error("The native cog consumer needs a fresh output and a declared mode")
		quit(1)
		return
	if mode == "arrival-cog-resume":
		deadline = Time.get_ticks_msec() + 180000
	opening = load("res://opening/opening.tscn").instantiate()
	opening.auto_advance = false
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
	if mode == "arrival-cog-resume":
		await _arrival_cog_produce()
	elif mode == "arrival-cog-finish-resume":
		_arrival_cog_finish_resume()
	elif mode == "resume":
		_resume()
	else:
		await _produce()

func _arrival_recipe(kind: String, teeth: int = 0) -> bool:
	var recipes: Array = opening.model.projection().get("part_recipes", [])
	var index := -1
	for candidate in range(recipes.size()):
		if recipes[candidate].get("kind") == kind and int(recipes[candidate].get("teeth", 0)) == teeth:
			index = candidate
			break
	if not _expect(index >= 0, "The ordinary workshop projects the requested finite cog route recipe"):
		return false
	return _press_inventory_recipe("part:%d" % index,
		str(opening.model.projection().fabrication_hub.id))

func _arrival_cog_produce() -> void:
	facts.evidence = "native_normal_arrival_cog_body_and_store_consumer"
	var start: Dictionary = opening.model.projection()
	if not _expect(opening.last_load_result.get("accepted", false)
			and start.get("first_plate_unlock", false)
			and start.get("workshop_completed_actors", []).has("P")
			and int(start.get("part_kits", {}).get("P", {}).get("gear", 0)) == 0,
		"A real first-plate Store resume opens with P's milestone and no gifted cogwheel kit"):
		return
	if not await _approach_points([Vector2(6.6, 4.95), Vector2(6.6, 9.9), Vector2(6.0, 10.05)]):
		return
	for index in range(6):
		if _construct({"action": "harvest_source", "target": "tree-east-north"}).is_empty():
			return
	if not await _approach_points([Vector2(6.6, 4.95), Vector2(4.1, 4.95),
			Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return
	for index in range(3):
		if _construct({"action": "harvest_source", "target": "opening-copper"}).is_empty():
			return
	if not await _approach_points([Vector2(0.0, 1.65), Vector2(4.1, 4.95)]):
		return
	opening.building_hotbar.all_focus_button.pressed.emit()
	if not _expect(opening.building_hotbar.recipe_focus == "all",
		"The inventory's All parts control reveals the waterwheel alongside the cogwheels"):
		return
	for part in [{"kind": "wheel", "teeth": 0},
			{"kind": "gear", "teeth": 4}, {"kind": "gear", "teeth": 4}]:
		if not _arrival_recipe(part.kind, part.teeth):
			return
	var crafted: Dictionary = opening.model.projection()
	var large_gears := 0
	for specification: Dictionary in crafted.get("part_specifications", {}).get("P", []):
		if specification.get("kind") == "gear" and int(specification.get("teeth", 0)) == 4:
			large_gears = int(specification.get("count", 0))
	if not _expect(large_gears == 2 and int(crafted.part_kits.P.get("wheel", 0)) == 1
			and int(crafted.cargo.P.get("timber", -1)) == 0
			and int(crafted.cargo.P.get("raw", -1)) == 0,
		"Six gathered timber and three copper become one wheel and two separately owned large cogs"):
		return
	if not await _approach_points([Vector2(3.3, 3.3), Vector2(0.0, 3.3)]):
		return
	var wheel := _construct({"action": "place", "kind": "wheel", "cell": [-2, 2],
		"axis": "x", "level": 4})
	if wheel.is_empty() or not await _approach(Vector2(0.0, 4.95)):
		return
	var source := _construct({"action": "place_gear", "center": [-4, 4, 8],
		"axis": "x", "teeth": 4})
	if source.is_empty() or not await _approach(Vector2(0.0, 6.6)):
		return
	var output := _construct({"action": "place_gear", "center": [0, 4, 12],
		"axis": "z", "teeth": 4})
	if output.is_empty():
		return
	wheel_id = str(wheel.entity)
	gear_a = str(source.entity)
	gear_b = str(output.entity)
	if not _motion(gear_a, 1) or not _motion(gear_b, 1):
		return
	var before_remove: Dictionary = opening.model.projection()
	var before_remove_checkpoint: Dictionary = opening.model.checkpoint()
	var old_gear_wire: Dictionary = before_remove_checkpoint.world.history.records[-1].intent.wire.duplicate(true)
	if not _expect(old_gear_wire.get("action") == "place_gear"
			and old_gear_wire.get("center") == [0, 4, 12],
		"The running output cog keeps its original native placement request"):
		return
	var remove_key := InputEventKey.new()
	remove_key.keycode = KEY_F
	remove_key.pressed = true
	opening._unhandled_input(remove_key)
	if not _expect(opening.mode == "deconstruct", "F selects the ordinary deconstruction tool during wheel drive"):
		return
	opening._world_click(Vector2i(0, 3), gear_b)
	var removed: Dictionary = opening.model.projection()
	var remove_history: Array = opening.model.checkpoint().world.history.records
	if not _expect(int(removed.order) == int(before_remove.order) + 1
			and not removed.transmission_parts.has(gear_b)
			and not removed.motion.has(gear_b)
			and int(removed.part_kits.P.gear) == 1
			and removed.motion[wheel_id].state == "rotating"
			and removed.motion[gear_a].state == "rotating"
			and _same(removed.cargo.P, before_remove.cargo.P)
			and removed.material_mass.accounted_mass == removed.material_mass.initial_mass
			and remove_history.size() == before_remove_checkpoint.world.history.records.size() + 1
			and remove_history[-1].intent.wire.action == "remove"
			and remove_history[-1].intent.wire.entity == gear_b
			and remove_history[-1].result.accepted,
		"One F-click removes the running output cog, refunds its part, and leaves the source and material intact"):
		return
	var rebuilt := _construct({"action": "place_gear", "center": [0, 4, 12],
		"axis": "z", "teeth": 4})
	if rebuilt.is_empty() or not _motion(str(rebuilt.entity), 1):
		return
	var before_retry: Dictionary = opening.model.checkpoint()
	var old_retry: Dictionary = opening.model.command(old_gear_wire)
	if not _expect(old_retry.get("accepted", false) and old_retry.get("duplicate", false)
			and old_retry.get("entity") == gear_b and str(rebuilt.entity) != gear_b
			and _same(opening.model.checkpoint().world, before_retry.world),
		"Retrying the earlier placement returns its original receipt without changing the rebuilt line"):
		return
	opening.configure_save_slot(destination + ".final.worksite")
	if not _save():
		return
	_record("pass")

func _arrival_cog_finish_resume() -> void:
	facts.evidence = "native_normal_arrival_cog_saved_line_consumer"
	var input := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="):
			input = argument.trim_prefix("--resume-input=")
	var saved = bytes_to_var(FileAccess.get_file_as_bytes(input).slice(
		"FACTORY-SAVE-1\n".length() + 65))
	var restored: Dictionary = opening.model.checkpoint()
	if not _expect(saved is Dictionary and opening.last_load_result.get("accepted", false)
			and _same(saved, opening.startup_resume_checkpoint)
			and _same(saved.world, restored.world)
			and opening.request_sequence == 0,
		"A fresh scene restores the exact saved native World before making another request"):
		return
	var state: Dictionary = opening.model.projection()
	var old_gear_wire: Dictionary = {}
	var output_id := ""
	var source_id := ""
	for id in state.transmission_parts:
		var part: Dictionary = state.transmission_parts[id]
		if part.kind == "gear" and part.center == [0, 4, 12]:
			output_id = str(id)
		elif part.kind == "gear" and part.center == [-4, 4, 8]:
			source_id = str(id)
	for id in state.entities:
		if state.entities[id].kind == "wheel":
			wheel_id = str(id)
	for record: Dictionary in saved.world.history.records:
		if record.intent.wire.action == "place_gear" \
				and record.intent.wire.center == [0, 4, 12] \
				and record.result.entity != output_id:
			old_gear_wire = record.intent.wire.duplicate(true)
	if not _expect(not wheel_id.is_empty() and not source_id.is_empty()
			and not output_id.is_empty() and not old_gear_wire.is_empty()
			and int(state.part_kits.P.get("gear", -1)) == 0
			and state.material_mass.accounted_mass == state.material_mass.initial_mass
			and state.motion[wheel_id].state == "rotating"
			and state.motion[source_id].state == "rotating"
			and state.motion[output_id].state == "rotating",
		"The reopened worksite retains both individually owned cogs and the running wheel"):
		return
	var replay: Dictionary = opening.model.command(old_gear_wire)
	if not _expect(replay.get("accepted", false) and replay.get("duplicate", false)
			and replay.get("entity") != output_id
			and _same(opening.model.checkpoint().world, restored.world),
		"An old cog placement still replays its old receipt without replacing the saved cog"):
		return
	_record("pass")

func _produce() -> void:
	var original: Dictionary = opening.model.checkpoint().world.state
	var far := [-4, 16, 8]
	if _command(_gear(far), [_anchor(far)], false, "out_of_reach").is_empty():
		return
	if not _expect(_same(original, opening.model.checkpoint().world.state), "Vertical reach refusal cannot consume a part or alter material"):
		return
	var route: Dictionary = await _collector_route()
	if route.is_empty(): return
	wheel_id = route.wheel
	collector_id = route.collector
	gear_a = route.source_cog
	gear_b = route.output_cog
	shaft_id = route.shaft
	for record: Dictionary in opening.model.checkpoint().world.history.records:
		if record.intent.wire.action == "place_gear" and record.result.entity == gear_b:
			first_gear_wire = record.intent.wire.duplicate(true)
	facts["first_gear_wire"] = first_gear_wire.duplicate(true)
	if not _expect(not first_gear_wire.is_empty(), "The original output-cog intent remains identifiable in native history"): return
	if not _motion(gear_a, 1) or not _motion(gear_b, 1) or not _motion(collector_id, 1):
		return
	opening.model.advance() # Controlled fixture tick after automatic source motion is confirmed.
	opening._refresh()
	if not _custody(0, 0, 1):
		return
	if _command({"action": "remove", "entity": gear_b}, [_anchor([0, 4, 12])]).is_empty() or not _expect(not opening.model.projection().powered, "Running removal must actually interrupt collector transmission"):
		return
	var misplaced: Dictionary = _command(_gear([4, 4, 12]), [_anchor([4, 4, 12])])
	if misplaced.is_empty() or not _expect(not opening.model.projection().powered, "A legal one-tile displacement cannot preserve the old mesh or shaft power"):
		return
	if _command({"action": "remove", "entity": misplaced.entity}, [_anchor([4, 4, 12])]).is_empty():
		return
	var rebuilt: Dictionary = _command(_gear([0, 4, 12]), [_anchor([0, 4, 12])])
	if rebuilt.is_empty() or not _expect(rebuilt.entity != gear_b and opening.model.projection().powered, "Correct rebuilding must restore geometry using a new part identity"):
		return
	var replay: Dictionary = opening.model.command(first_gear_wire)
	facts["historical_retry"] = replay.duplicate(true)
	if not _expect(replay.get("accepted", false) and replay.get("duplicate", false) and replay.get("entity") == gear_b, "The removed gear's exact old request cannot be retargeted to its replacement"):
		return
	gear_b = rebuilt.entity
	if _command({"action": "remove", "entity": shaft_id}, [_anchor([0, 4, 8])]).is_empty() or not _expect(opening.model.projection().parts.shaft == 8 and not opening.model.projection().powered, "Removing the individual shaft returns it and removes collector power"):
		return
	var new_shaft := _command({"action": "place_shaft", "center": [0, 4, 8], "axis": "z", "half_span": 2}, [_anchor([0, 4, 8])])
	if new_shaft.is_empty():
		return
	shaft_id = new_shaft.entity
	for _frame in range(4):
		await physics_frame
		await process_frame
	if not _expect(opening.model.projection().order == 13, "Every accepted or refused original intent remains in the thirteen-request history") or not _custody(0, 0, 1) or not _save():
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
	if not _expect(opening.request_sequence == 0 and opening.model.projection().order == 13 and _same(opening.actor_world.seeds, saved.actors), "Fresh startup must preserve native seeds and issue zero material requests") or not _custody(0, 0, 1):
		return
	for id in opening.model.projection().entities:
		var entity: Dictionary = opening.model.projection().entities[id]
		if entity.kind == "wheel":
			wheel_id = id
		elif entity.kind == "collector":
			collector_id = id
	for id in opening.model.projection().transmission_parts:
		var part: Dictionary = opening.model.projection().transmission_parts[id]
		if part.kind == "gear" and _same(part.center, [-4, 4, 8]):
			gear_a = id
		elif part.kind == "gear" and _same(part.center, [0, 4, 12]):
			gear_b = id
		elif part.kind == "shaft" and _same(part.center, [0, 4, 8]):
			shaft_id = id
	if not _expect(not wheel_id.is_empty() and not collector_id.is_empty() and not gear_a.is_empty() and not gear_b.is_empty() and not shaft_id.is_empty(), "The restored actual part identities must resolve from saved geometry"):
		return
	var old_gear: Dictionary = {}
	for record: Dictionary in saved.world.history.records:
		if record.intent.wire.action == "place_gear" and record.result.entity != gear_b and record.intent.wire.center == [0, 4, 12]:
			old_gear = record
			break
	if not _expect(not old_gear.is_empty(), "The removed output cog retains its original typed history record"): return
	var replay: Dictionary = opening.model.command(old_gear.intent.wire)
	facts["resumed_historical_retry"] = replay.duplicate(true)
	if not _expect(old_gear.intent.wire.action == "place_gear" and replay.get("accepted", false) and replay.get("duplicate", false) and replay.get("entity") == old_gear.result.entity and replay.entity != gear_b and _same(saved.world, opening.model.checkpoint().world),
		"A fresh process must replay the removed gear's old receipt without treating its old observation as a new admission"):
		return
	if not _motion(gear_a, 1) or not _motion(gear_b, 1) or not _motion(collector_id, 1):
		return
	if _command({"action": "remove", "entity": shaft_id}, [_anchor([0, 4, 8])]).is_empty() or not _expect(not opening.model.projection().powered and opening.model.projection().parts.shaft == 8, "Fresh individual-shaft removal must return its real part"):
		return
	if _command({"action": "place_shaft", "center": [0, 4, 8], "axis": "z", "half_span": 2}, [_anchor([0, 4, 8])]).is_empty() or _command({"action": "remove", "entity": gear_b}, [_anchor([0, 4, 12])]).is_empty():
		return
	if not _expect(opening.model.projection().power_enabled and not opening.model.projection().powered, "Fresh running gear removal must isolate the collector without disabling the source"):
		return
	if _command({"action": "recover", "entity": collector_id}, [_anchor([0, 4, 4])]).is_empty() or not _custody(1, 1, 0):
		return
	var final: Dictionary = opening.model.checkpoint()
	if not _expect(final.world.history.order == 17 and _same(saved.world.history.records, final.world.history.records.slice(0, 13)), "All thirteen original intents and outcomes remain unchanged before four fresh operations") or not _save():
		return
	_record("pass")
