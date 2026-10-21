extends SceneTree
## Automated headless consumer of the ordinary scene, not a desktop playtest.
const NativeModel = preload("res://opening/native_model.gd")
const OpeningGeometry = preload("res://opening/site_geometry.gd")
var opening
var destination := ""
var mode := ""
var checks := 0
var deadline := 0
var facts: Dictionary = {"steps": [], "evidence": "native_offline_scene_consumer"}
var written := false

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--native-check-output="):
			destination = argument.trim_prefix("--native-check-output=")
		if argument.begins_with("--native-check-mode="):
			mode = argument.trim_prefix("--native-check-mode=")
	deadline = Time.get_ticks_msec() + (45000 if mode == "foundations" else 15000)
	call_deferred("_run")

func _same(expected: Variant, actual: Variant, depth: int = 0) -> bool:
	if depth > 32 or typeof(expected) != typeof(actual):
		return false
	if expected is Dictionary:
		if expected.size() != actual.size():
			return false
		for key in expected:
			if not actual.has(key) or not _same(expected[key], actual[key], depth + 1):
				return false
		return true
	if expected is Array:
		if expected.size() != actual.size():
			return false
		for index in range(expected.size()):
			if not _same(expected[index], actual[index], depth + 1):
				return false
		return true
	return expected == actual

func _record(status: String, reason: String = "") -> void:
	if written:
		return
	written = true
	facts.merge({"status": status, "reason": reason, "mode": mode, "checks": checks,
		"process_id": OS.get_process_id(), "physics_frames": Engine.get_physics_frames()})
	if opening != null and opening.model != null:
		facts["final_projection"] = opening.model.projection()
		facts["final_checkpoint"] = opening.model.checkpoint()
		if opening.actor_world != null:
			facts["producer"] = opening.actor_world.diagnostics()
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		push_error("Cannot retain the native adapter consumer result")
		quit(1)
		return
	# The binary retains integer/float distinctions. JSON is only a short log.
	file.store_buffer(var_to_bytes(facts))
	file.close()
	print(JSON.stringify({"status": status, "evidence": facts.evidence, "mode": mode, "checks": checks, "reason": reason}))
	quit(0 if status == "pass" else 1)

func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		_record("fail", message)
		push_error(message)
	return condition

func _issue(action: Dictionary) -> Dictionary:
	var reply: Dictionary = opening.issue(action)
	var cut: Dictionary = {}
	if reply.get("reach") is Dictionary:
		cut = opening.actor_world.diagnostics("P", reply.reach.native_epoch)
	facts.steps.append({"action": action.duplicate(true), "reply": reply.duplicate(true), "native_cut": cut})
	return reply

func _run() -> void:
	if destination.is_empty() or mode not in ["produce", "resume", "foundations"]:
		push_error("The native adapter check requires an output and a declared mode")
		quit(1)
		return
	if FileAccess.file_exists(destination):
		push_error("The native adapter check refuses an existing result")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	root.add_child(opening)
	if not _expect(opening.model is NativeModel and opening.model.native.get_class() == "FactoryNativeWorld", "The ordinary scene must own the native model"):
		return
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		await process_frame
		if opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending:
			break
	if not _expect(opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending, "A real registered actor must reach the floor before commands"):
		return
	facts["initial_projection"] = opening.model.projection()
	facts["initial_native"] = opening.actor_world.diagnostics("P")
	if mode == "foundations":
		await _foundations()
		return
	if mode == "resume":
		_resume()
		return
	var collector: Dictionary = _issue({"action": "place", "kind": "collector", "cell": [0, 1]})
	if not _expect(collector.accepted, "The observed actor can place the nearby collector"):
		return
	var wheel: Dictionary = _issue({"action": "place", "kind": "wheel", "cell": [-1, 1]})
	if not _expect(wheel.accepted, "The observed actor can place the nearby wheel"):
		return
	if not _expect(_issue({"action": "connect_drive", "from": wheel.entity, "to": collector.entity}).accepted, "The drive action must consume a real shaft"):
		return
	if not _expect(_issue({"action": "set_power", "active": true}).accepted, "The nearby source starts through native admission"):
		return
	while Time.get_ticks_msec() < deadline and opening.model.projection().stock.collector != 1:
		await process_frame
	var before: Dictionary = opening.model.projection()
	if not _expect(before.stock.source == 15 and before.stock.collector == 1 and before.powered, "The ordinary scene's natural tick moves one of sixteen units"):
		return
	if not _expect(_issue({"action": "recover", "entity": collector.entity}).accepted, "Recovery moves the original raw unit into cargo"):
		return
	var recovery_wire: Dictionary = opening.model.checkpoint().world.history.records[-1].intent.wire
	if not _expect(_issue({"action": "remove", "entity": collector.entity}).accepted, "An emptied collector can be removed with the source still enabled"):
		return
	var rebuilt: Dictionary = _issue({"action": "place", "kind": "collector", "cell": [0, 1]})
	if not _expect(rebuilt.accepted and rebuilt.entity != collector.entity, "Rebuilding issues a new entity identity"):
		return
	var retry: Dictionary = opening.model.command(recovery_wire)
	facts["historical_retry"] = retry
	if not _expect(retry.accepted and retry.duplicate and retry.entity == collector.entity, "An exact retry retains the removed target's original recovery"):
		return
	if not _expect(_issue({"action": "insert_raw", "entity": rebuilt.entity, "amount": 1}).accepted, "The carried unit returns without refill or conversion"):
		return
	var final: Dictionary = opening.model.projection()
	if not _expect(final.stock.source == 15 and final.stock.collector == 1 and final.cargo.P.raw == 0 and final.order == 8 and final.power_enabled, "Running recovery and rebuilding retain the literal sixteen-unit custody"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts["save_result"] = saved
	facts["save_slot"] = opening.save_slot
	if not _expect(saved.accepted and saved.native_preflight.accepted and FileAccess.file_exists(opening.save_slot), "Store publishes the native-validated checkpoint after a real body preflight"):
		return
	_record("pass")

func _walk_to(target: Vector2, jump: bool = false) -> bool:
	var jumped := false
	var highest_foot := -INF
	while Time.get_ticks_msec() < deadline:
		var body = opening.actor_world.bodies.P
		var at: Vector3 = body.global_position
		highest_foot = maxf(highest_foot, at.y - OpeningGeometry.CAPSULE_HEIGHT / 2.0)
		var gap := target - Vector2(at.x, at.z)
		if gap.length() < 0.08:
			opening.actor_world.release_control("P")
			if jump:
				facts["foundation_jump"] = {"edge_sent": jumped, "highest_foot": highest_foot}
			return true
		var jump_edge: bool = jump and not jumped and gap.length() < 1.2 and body.is_on_floor()
		if not _expect(opening.actor_world.set_control("P", gap.normalized(), jump_edge).accepted,
				"The fixture walks through the real character motor without setting a pose"):
			return false
		jumped = jumped or jump_edge
		await physics_frame
		await process_frame
	opening.actor_world.release_control("P")
	return _expect(false, "The bounded native walk must reach its declared target")

func _foundations() -> void:
	# A new automated construction case, not a replay of produce/resume, a
	# desktop-input test or evidence that a human understood the interaction.
	opening.auto_advance = false
	opening.set_process(false)
	if not await _walk_to(Vector2(9.0, 6.0)):
		return
	var before: Dictionary = opening.model.projection()
	var first: Dictionary = _issue({"action": "place_foundation", "cell": [5, 2], "level": 2})
	if not _expect(first.accepted, "The real nearby actor can build beyond the removed local rectangle"):
		return
	var second: Dictionary = _issue({"action": "place_foundation", "cell": [6, 2], "level": 2})
	if not _expect(second.accepted, "An independently placed foundation shares the absolute height grid"):
		return
	for _frame in range(3):
		await physics_frame
		await process_frame
	opening._select_tool("foundation")
	opening._adjust_foundation_level(2)
	if not _expect(opening.foundation_level == 2 and opening.foundation_level_label.text.begins_with("Level 2"),
			"The actual controls show an absolute world height rather than a local terrain offset"):
		return
	if not _expect(opening.actor_world._geometry_registered(), "Displayed foundation levels match registered native box bodies"):
		return
	if not await _walk_to(Vector2(8.25, 3.3), true):
		return
	if not _expect(facts.foundation_jump.edge_sent and facts.foundation_jump.highest_foot > 2.0 * OpeningGeometry.HEIGHT_STEP + 0.05,
			"The actual jump lifts the capsule feet above one full foundation before landing"):
		return
	for _frame in range(40):
		await physics_frame
		await process_frame
	var body = opening.actor_world.bodies.P
	facts["standing_on_foundation"] = opening.actor_world.diagnostics("P")
	if not _expect(body.is_on_floor() and absf(body.global_position.y - OpeningGeometry.CAPSULE_HEIGHT / 2.0 - 2.0 * OpeningGeometry.HEIGHT_STEP) < 0.02,
			"The real capsule walks and lands on the constructed surface at the common height"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts["foundation_save"] = saved
	if not _expect(saved.accepted and saved.native_preflight.accepted,
			"Store accepts the real registered pose and foundation custody: " + str(saved)):
		return
	if not await _walk_to(Vector2(9.0, 6.0)):
		return
	opening._select_tool("belt")
	opening._world_click(Vector2i(5, 2))
	if not _expect(opening.model.projection().entities.size() == 1, "The first ordinary machine placement succeeds before dependent probing"):
		return
	opening._select_tool("processor")
	opening._world_click(Vector2i(6, 2))
	for _frame in range(3):
		await physics_frame
		await process_frame
	var current: Dictionary = opening.model.projection()
	if not _expect(current.entities.size() == 2 and current.links.size() == 1 and current.part_kits.P.foundation == 22,
			"The ordinary scene placement path aligns a belt and press on separately built foundations"):
		return
	for id in current.entities:
		var entity: Dictionary = current.entities[id]
		var physical: StaticBody3D = opening.actor_world.machines[id]
		if not _expect(entity.level == 2 and absf(physical.position.y - OpeningGeometry.MACHINE_CENTER_HEIGHT - 2.0 * OpeningGeometry.HEIGHT_STEP) < 0.00001,
				"Machine projection, mesh and native contact share the foundation height"):
			return
	if not _expect(current.stock.source == before.stock.source and current.stock.source == 16 and current.remaining == 0,
			"Construction changes no mineral quantity or material clock"):
		return
	if not _expect(_issue({"action": "remove", "entity": first.entity}).reason == "foundation_in_use",
			"A supporting foundation cannot disappear beneath a machine"):
		return
	_record("pass")

func _resume() -> void:
	var input := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="):
			input = argument.trim_prefix("--resume-input=")
	if not _expect(not input.is_empty() and opening.last_load_result.get("accepted", false), "The ordinary scene must load the retained Store binary"):
		return
	var bytes := FileAccess.get_file_as_bytes(input)
	var expected = bytes_to_var(bytes.slice("FACTORY-SAVE-1\n".length() + 65))
	facts["loaded_before_native"] = opening.startup_resume_checkpoint.duplicate(true)
	if not _expect(expected is Dictionary and _same(expected, opening.startup_resume_checkpoint), "Store-loaded native state and original history must match every saved type and value"):
		return
	var initial: Dictionary = opening.model.projection()
	if not _expect(opening.request_sequence == 0 and initial.order == 8 and initial.stock.source == 15 and initial.stock.collector == 1 and initial.cargo.P.raw == 0, "Fresh startup publishes no material command and preserves running custody"):
		return
	if not _expect(_same(opening.actor_world.seeds, expected.actors), "The fresh producer uses the exact saved actor seeds"):
		return
	if not _expect(_same(opening.model.checkpoint().world, expected.world), "Natural blocked ticks do not alter restored history or material state"):
		return
	var collector := ""
	for id in initial.entities:
		if initial.entities[id].kind == "collector":
			collector = id
	if not _expect(not collector.is_empty() and _issue({"action": "recover", "entity": collector}).accepted, "The fresh process can recover the retained actual unit"):
		return
	var final: Dictionary = opening.model.projection()
	if not _expect(final.stock.source == 15 and final.stock.collector == 0 and final.cargo.P.raw == 1 and final.order == 9, "Fresh native admission moves custody once without creating or losing material"):
		return
	var saved: Dictionary = opening._save_worksite()
	facts["save_result"] = saved
	facts["save_slot"] = opening.save_slot
	if not _expect(saved.accepted, "The fresh process publishes its separate continuation save"):
		return
	_record("pass")
