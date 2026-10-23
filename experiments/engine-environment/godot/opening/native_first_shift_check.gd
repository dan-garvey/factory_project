extends SceneTree
## Automated ordinary-scene integration, not desktop input or human play.
## Native World remains the only material/clock authority. This observer never
## sets a body pose, edits a projection, creates stock or calls advance().
const NativeModel = preload("res://opening/native_model.gd")
const OpeningScene = preload("res://opening/opening.gd")

var opening
var mode := ""
var destination := ""
var prior_path := ""
var deadline := 0
var checks := 0
var written := false
var facts: Dictionary = {"evidence": "native_first_shift_scene_consumer", "actions": [], "approaches": []}

func _init() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--first-shift-mode="):
			mode = argument.trim_prefix("--first-shift-mode=")
		elif argument.begins_with("--first-shift-output="):
			destination = argument.trim_prefix("--first-shift-output=")
		elif argument.begins_with("--first-shift-prior="):
			prior_path = argument.trim_prefix("--first-shift-prior=")
	deadline = Time.get_ticks_msec() + 115000
	call_deferred("_run")

func _same(a: Variant, b: Variant, depth: int = 0) -> bool:
	if depth > 32 or typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not _same(a[key], b[key], depth + 1):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for index: int in range(a.size()):
			if not _same(a[index], b[index], depth + 1):
				return false
		return true
	return a == b

func _finish(status: String, reason: String = "") -> void:
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
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		push_error("Cannot retain first-shift evidence")
		quit(1)
		return
	# Binary evidence preserves checkpoint scalar types and native observations.
	output.store_buffer(var_to_bytes(facts))
	output.close()
	var audio_refs: Array[WeakRef] = []
	for cue in OpeningScene.ConstructionAudio.streams:
		audio_refs.append(weakref(OpeningScene.ConstructionAudio.streams[cue]))
	if opening != null:
		if opening.construction_audio != null:
			var playback = opening.construction_audio.get_stream_playback()
			if playback != null:
				audio_refs.append(weakref(playback))
			playback = null
			opening.construction_audio.stop()
			opening.construction_audio.stream = null
		opening.free()
		opening = null
	OpeningScene.ConstructionAudio.streams.clear()
	OpeningScene.ConstructionAudio.source_status = "uninitialized"
	# The dummy audio driver may release the three stopped voices after scene removal.
	# Observe the retained resources before ending this consumer.
	var audio_deadline := Time.get_ticks_msec() + 2000
	while not audio_refs.is_empty():
		var remaining := 0
		for reference in audio_refs:
			if reference.get_ref() != null:
				remaining += 1
		if remaining == 0:
			break
		if Time.get_ticks_msec() >= audio_deadline:
			push_error("First-shift teardown retains %d construction audio objects" % remaining)
			quit(1)
			return
		await process_frame
	print(JSON.stringify({"status": status, "mode": mode, "checks": checks, "reason": reason}))
	quit(0 if status == "pass" else 1)

func _expect(condition: bool, reason: String) -> bool:
	checks += 1
	if not condition:
		_finish("fail", reason)
		push_error(reason)
	return condition

func _until(condition: Callable, reason: String) -> bool:
	while not written and Time.get_ticks_msec() < deadline:
		if condition.call():
			return _expect(true, reason)
		await process_frame
	return _expect(false, reason)

func _conserved(snapshot: Dictionary) -> bool:
	# Count each unit once and independently check the product aliases.
	if not _expect(snapshot.initial_feed == 4096 and snapshot.recipe_input == 1, "The current finite recipe profile is unchanged"):
		return false
	if not _expect(typeof(snapshot.line_belt_raw) == TYPE_INT and snapshot.line_belt_raw >= 0,
		"Belt material count remains a nonnegative integer"):
		return false
	var total: int = snapshot.line_belt_raw
	for key: String in ["source", "collector", "belt", "input", "held", "output", "player"]:
		var amount: Variant = snapshot.stock.get(key)
		if not _expect(typeof(amount) == TYPE_INT and amount >= 0, "Every material count remains a nonnegative integer"):
			return false
		total += amount
	var products: int = 0
	for actor: String in snapshot.cargo:
		var cargo: Dictionary = snapshot.cargo[actor]
		if not _expect(typeof(cargo.raw) == TYPE_INT and cargo.raw >= 0 and typeof(cargo.products) == TYPE_INT and cargo.products >= 0, "Carried forms retain their integer types"):
			return false
		if not _expect(cargo.products == snapshot.inventories[actor], "Product aliases agree without double-counting"):
			return false
		total += cargo.raw
		products += cargo.products
		for lot: Dictionary in cargo.work_lots:
			if not _expect(typeof(lot.recipe_input) == TYPE_INT and lot.recipe_input == 1 and typeof(lot.remaining) == TYPE_INT and lot.remaining >= 0 and lot.remaining <= lot.cycle_ticks, "A workpiece retains its recipe and progress"):
				return false
			total += lot.recipe_input
	if not _expect(total == 4096 and products == snapshot.stock.player, "Every original unit has exactly one typed owner"):
		return false
	var part_totals: Dictionary = {"collector": 0, "belt": snapshot.belt_spans.size(), "processor": 0,
		"wheel": 0, "shaft": 0, "gear": 0, "gearbox": 0, "vertical_gearbox": 0,
		"chain_drive": 0, "foundation": snapshot.foundations.size()}
	for kit: Dictionary in snapshot.part_kits.values():
		for kind: String in kit:
			if not _expect(part_totals.has(kind) and typeof(kit[kind]) == TYPE_INT and kit[kind] >= 0, "Carried construction parts retain their finite integer counts"):
				return false
			part_totals[kind] += kit[kind]
	for part: Dictionary in snapshot.entities.values() + snapshot.transmission_parts.values():
		if not _expect(part_totals.has(part.kind), "Every placed construction part has a declared kind"):
			return false
		part_totals[part.kind] += 1
	return _expect(_same(part_totals, {"collector": 1, "belt": 2, "processor": 1, "wheel": 1,
		"shaft": 8, "gear": 10, "gearbox": 2, "vertical_gearbox": 2, "chain_drive": 8,
		"foundation": 24}), "Construction and refunds preserve the current finite physical kit")

func _targets(before: Dictionary, action: Dictionary) -> Array:
	var centers: Array = []
	if action.action in ["place", "place_foundation"]:
		centers.append([action.cell[0] * 4, action.level, action.cell[1] * 4])
	elif action.action in ["place_gear", "place_shaft"]:
		centers.append(action.center)
	elif action.action == "place_belt_span":
		centers.append(before.transmission_parts[action.from].center)
		centers.append(before.transmission_parts[action.to].center)
	else:
		var entity: Dictionary = before.entities[action.entity]
		centers.append([entity.cell[0] * 4, entity.level, entity.cell[1] * 4])
	var output: Array = []
	for center: Array in centers:
		# Literal fixture geometry, not a camera/raycast or permission helper.
		output.append([float(center[0]) * 0.4125, 0.825 + float(center[1]) * 0.4125,
			float(center[2]) * 0.4125])
	return output

func _finite_point3(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate: Variant in value:
		if typeof(coordinate) != TYPE_FLOAT or not is_finite(coordinate):
			return false
	return true

func _native_admission(before: Dictionary, action: Dictionary, reply: Dictionary, cut: Dictionary) -> bool:
	var reach: Dictionary = reply.get("reach", {})
	if not _expect(reach.get("actor") == "P" and reach.get("build_reach") == 4.0
		and typeof(reach.get("native_epoch")) == TYPE_INT and reach.native_epoch > 0
		and typeof(reply.get("native_epoch")) == TYPE_INT and reply.native_epoch == reach.native_epoch,
		"P has a positive original admission epoch."):
		return false
	var sample: Dictionary = cut.get("sample", {})
	if not _expect(cut.get("available", false) and cut.get("actor") == "P"
		and sample.get("registered", false) and sample.get("ready", false)
		and typeof(sample.get("native_epoch")) == TYPE_INT and sample.native_epoch == reach.native_epoch,
		"The receipt binds the original ready, registered sample."):
		return false
	if not _expect(_finite_point3(sample.get("position")) and _finite_point3(sample.get("node_position"))
		and _finite_point3(reach.get("position")) and _finite_point3(reply.get("actor_position"))
		and _same(sample.position, sample.node_position) and _same(sample.position, reach.position)
		and _same(sample.position, reply.actor_position), "All admission positions agree exactly."):
		return false
	var targets: Array = _targets(before, action)
	if not _expect(_same(targets, reach.targets) and targets.size() == reach.distances_squared.size(), "Admission uses the literal targets."):
		return false
	for index: int in range(targets.size()):
		if not _expect(_finite_point3(targets[index]), "Each target has three finite coordinates."):
			return false
		var squared: float = 0.0
		for axis: int in range(3):
			var difference: float = float(reach.position[axis]) - float(targets[index][axis])
			squared += difference * difference
		if not _expect(squared == reach.distances_squared[index] and squared <= 16.0, "Reach agrees exactly within four metres."):
			return false
	return true

func _action(label: String, action: Dictionary, callback: Callable, accepted: bool = true) -> Dictionary:
	var before: Dictionary = opening.model.projection()
	var sequence: int = opening.request_sequence
	var record: Dictionary = {"label": label, "expected_action": action.duplicate(true), "before": before, "sequence_before": sequence}
	facts.actions.append(record)
	callback.call()
	record["after"] = opening.model.projection()
	record["sequence_after"] = opening.request_sequence
	if not _expect(opening.request_sequence == sequence + 1, label + " submits exactly one ordinary view request"):
		return {}
	var after: Dictionary = opening.model.projection()
	var intent: Dictionary = action.duplicate(true)
	intent.merge({"context": before.context, "client": "P", "request": opening.request_namespace + str(opening.request_sequence)}, true)
	# Retry only the original UI intent; its cached result must not alter the world.
	var reply: Dictionary = opening.model.command(intent)
	record["intent"] = intent
	record["outcome"] = reply
	var cut: Dictionary = {}
	if reply.get("reach") is Dictionary and typeof(reply.reach.get("native_epoch")) == TYPE_INT:
		cut = opening.actor_world.diagnostics("P", reply.reach.native_epoch)
	record["native_cut"] = cut
	if not _expect(reply.get("duplicate", false) and reply.get("accepted") == accepted and after.order == before.order + 1 and _same(after, opening.model.projection()), label + " returns its cached outcome without another operation."):
		return {}
	if not _native_admission(before, action, reply, cut) or not _conserved(after):
		return {}
	return reply

func _place(kind: String, cell: Vector2i) -> String:
	var action: Dictionary = {"action": "place", "kind": kind, "cell": [cell.x, cell.y],
		"axis": "x" if kind == "wheel" else "z", "level": 4}
	if kind == "wheel":
		action["tiles"] = 3
	else:
		action["rotation"] = 0
	var reply: Dictionary = _action("place " + kind, action, func() -> void:
		opening._select_tool(kind)
		opening.transmission_controls._axis_selected(0 if kind == "wheel" else 2)
		opening.wheel_level = 4
		opening._world_click(cell))
	return reply.get("entity", "")

func _setup(action: Dictionary) -> String:
	# Fixed setup uses the view binding; tool-selection coverage is separate.
	var reply := _action("construct " + str(action.action), action, opening.issue.bind(action))
	return reply.get("entity", "")

func _approach_axis(coordinate: int, target: float) -> bool:
	var before: Dictionary = opening.actor_world.diagnostics("P")
	var direction := signf(target - float(before.sample.position[coordinate]))
	if not _expect(opening.actor_world.set_control("P", Vector2(direction, 0) if coordinate == 0 else Vector2(0, direction), false).accepted,
		"The real native motor admits the declared approach leg"):
		return false
	var arrived: bool = await _until(func() -> bool:
		var at: float = opening.model.projection().actors.P.position[coordinate]
		return at >= target if direction > 0 else at <= target, "The native motor reaches the declared station")
	opening.actor_world.release_control("P")
	for _frame in range(4):
		await physics_frame
	var after: Dictionary = opening.actor_world.diagnostics("P")
	facts.approaches.append({"coordinate": coordinate, "target": target,
		"before": before, "after": after})
	return arrived and _expect(after.sample.ready and after.sample.registered and after.sample.on_floor
		and after.sample.control == [0.0, 0.0], "The approach releases the registered actor on its actual floor")

func _select(target: String) -> void:
	opening._select_tool("inspect")
	var cell: Array = opening.state.entities[target].cell
	opening._world_click(Vector2i(cell[0], cell[1]), target)

func _menu(target: String, action: String, work_id: int = -1) -> Dictionary:
	_select(target)
	var control = opening.recovery_actions
	if not _expect(control != null and control.visible and not control.action_button.disabled, "The actual recovery menu is available"):
		return {}
	control._open_menu()
	var popup: PopupMenu = control.action_button.get_popup()
	for index: int in range(popup.item_count):
		var metadata: Dictionary = popup.get_item_metadata(index)
		var wire: Dictionary = metadata.wire
		if wire.action == action and (work_id < 0 or wire.get("work_id") == work_id):
			return _action("menu " + action, wire, control._choose.bind(popup.get_item_id(index)))
	_expect(false, "The ordinary menu offers the exact requested carried form")
	return {}

func _clock(enabled: bool) -> bool:
	# The fixture controls elapsed ticks; drive power still follows the wheel.
	opening.auto_advance = enabled
	return not written

func _retrieve(press: String) -> bool:
	_select(press)
	var before: int = opening.model.projection().inventories.P
	_action("collect plate", {"action": "retrieve", "entity": press, "amount": 1}, opening._retrieve)
	return not written and _expect(opening.model.projection().inventories.P == before + 1, "The ordinary collection callback transfers one actual product")

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	opening.character_presenter._input(event)

func _prepare() -> void:
	var initial: Dictionary = opening.model.projection()
	if not _conserved(initial) or not _expect(initial.stock.source == 4096 and initial.entities.is_empty(), "The current fresh worksite starts once"):
		return
	var before_input: Dictionary = opening.actor_world.diagnostics("P")
	# Exercise the presenter's key callbacks and native motor without OS input.
	_key(KEY_D, true)
	_key(KEY_S, true)
	if not (await _until(func() -> bool: return opening.model.projection().actors.P.position[0] >= 0.7, "The actual motor reaches construction range")):
		return
	_key(KEY_D, false)
	_key(KEY_S, false)
	opening.character_presenter.release()
	for _frame: int in range(4):
		await physics_frame
		await process_frame
	var after_input: Dictionary = opening.actor_world.diagnostics("P")
	var body: CharacterBody3D = opening.actor_world.bodies.P
	if not _expect(after_input.controls > before_input.controls and after_input.releases > before_input.releases and body.velocity.x == 0.0 and body.velocity.z == 0.0, "The real input path walks and releases the native motor"):
		return
	facts["movement"] = {"before": before_input, "after": after_input}
	# Later approach legs use the native motor without a competing input producer.
	opening.character_presenter.set_physics_process(false)
	if not await _approach_axis(0, -1.2) or not await _approach_axis(2, 3.3): return
	var wheel: String = _place("wheel", Vector2i(-2, 1))
	if written: return
	if _setup({"action": "place_foundation", "cell": [0, 1], "level": 4}).is_empty(): return
	var collector: String = _place("collector", Vector2i(0, 1))
	if written: return
	if not await _approach_axis(0, 4.95): return
	if _setup({"action": "place_foundation", "cell": [3, 1], "level": 4}).is_empty(): return
	var last := _setup({"action": "place_shaft", "center": [8, 4, 4], "axis": "z", "half_span": 2})
	if written or not await _approach_axis(0, 3.3): return
	var first := _setup({"action": "place_shaft", "center": [4, 4, 4], "axis": "z", "half_span": 2})
	if written or not await _approach_axis(2, -1.65): return
	for x in [12, 4]:
		if _setup({"action": "place_shaft", "center": [x, 4, 0], "axis": "z", "half_span": 2}).is_empty(): return
	if not await _approach_axis(2, -3.3): return
	for x in [12, 8, 4]:
		if _setup({"action": "place_gear", "center": [x, 4, -4], "axis": "z", "teeth": 2}).is_empty(): return
	if not await _approach_axis(0, 0.0): return
	for z in [-1, 0]:
		if _setup({"action": "place_foundation", "cell": [0, z], "level": 4}).is_empty(): return
	if _setup({"action": "place_gear", "center": [0, 4, -4], "axis": "z", "teeth": 2}).is_empty(): return
	if _setup({"action": "place_gear", "center": [0, 4, 0], "axis": "z", "teeth": 4}).is_empty(): return
	if not await _approach_axis(0, -1.2) or not await _approach_axis(2, 3.3): return
	if _setup({"action": "place_gear", "center": [-4, 4, 4], "axis": "x", "teeth": 4}).is_empty(): return
	opening.model.advance()
	opening._refresh()
	if not _expect(opening.model.projection().stock.collector == 1, "The incomplete powered line retains its first raw blank"): return
	_menu(collector, "recover")
	if written or not _expect(opening.model.projection().cargo.P.raw == 1 and opening.model.projection().stock.source == 4095, "The bad-line menu recovers the actual blank without refilling the seam"): return
	_select(collector)
	_action("remove powered collector", {"action": "remove", "entity": collector}, opening._remove_selected)
	if written or not _expect(opening.model.projection().power_enabled, "Stationary removal does not switch off the drive"): return
	var rebuilt: String = _place("collector", Vector2i(0, 1))
	if written or not _expect(rebuilt != collector, "Rebuilding allocates a new identity"): return
	_menu(rebuilt, "insert_raw")
	if written or not _clock(false) or not await _approach_axis(0, 3.3): return
	if _setup({"action": "place_belt_span", "from": first, "to": last}).is_empty(): return
	if not await _approach_axis(0, 4.95): return
	var press: String = _place("processor", Vector2i(3, 1))
	if written or not await _approach_axis(0, -1.2) or not _clock(true) or not await _approach_axis(0, 4.95): return
	if not (await _until(func() -> bool: return opening.model.projection().stock.output == 1, "The assembled native line produces a plate")): return
	if not _retrieve(press): return
	if not await _approach_axis(0, -1.2): return
	if not (await _until(func() -> bool: return opening.model.projection().stock.held == 1 and opening.model.projection().remaining == 1, "A later workpiece makes partial progress in the press")): return
	if not _clock(false): return
	if not await _approach_axis(0, 4.95): return
	var held_before: Dictionary = opening.model.checkpoint().world.state.duplicate(true)
	var remaining: int = opening.model.projection().remaining
	if not _expect(remaining == 1 and held_before.material.processing.recipe.cycle_ticks == 2 and held_before.material.processing.recipe.input_units_per_product == 1, "The saved work has progressed beyond its original two-tick recipe start"): return
	_select(press)
	var refused: Dictionary = _action("retain occupied press", {"action": "remove", "entity": press}, opening._remove_selected, false)
	if written or not _expect(refused.reason == "occupied_target" and _same(held_before, opening.model.checkpoint().world.state), "Occupied removal preserves all state and parts."): return
	_menu(press, "recover")
	if written: return
	var lots: Array = opening.model.projection().cargo.P.work_lots
	if not _expect(lots.size() == 1 and lots[0].id == held_before.material.processing.id and lots[0].remaining == 1 and lots[0].cycle_ticks == 2 and lots[0].recipe_input == 1, "Recovery keeps the original work identity and completed first tick"): return
	var work: Dictionary = lots[0].duplicate(true)
	if not _expect(_same(held_before.material.processing, opening.model.checkpoint().world.state.material.cargo.P.work_lots[0]), "The complete typed work record survives recovery."): return
	_select(press)
	_action("remove emptied press", {"action": "remove", "entity": press}, opening._remove_selected)
	if written: return
	var new_press: String = _place("processor", Vector2i(3, 1))
	if written or not _expect(new_press != press, "The recovered press can be rebuilt without reusing its identity"): return
	_menu(new_press, "insert_work", work.id)
	if written or not _expect(opening.model.projection().stock.held == 1 and opening.model.projection().remaining == remaining and opening.model.projection().cargo.P.work_lots.is_empty(), "Reinsertion preserves the same partial work."): return
	if not _expect(_same(held_before.material.processing, opening.model.checkpoint().world.state.material.processing), "Reinsertion preserves the complete typed work record."): return
	facts["recovered_work"] = work
	facts["prepared_projection"] = opening.model.projection()
	facts["prepared_checkpoint"] = opening.model.checkpoint()
	facts["original_namespace"] = opening.request_namespace
	var saved: Dictionary = opening._save_worksite()
	if not _expect(saved.accepted and _same(facts.prepared_checkpoint, opening.model.checkpoint()), "Ordinary Store publication preserves the paused partial work"): return
	facts["original_save"] = opening.save_slot
	facts["original_save_sha256"] = FileAccess.get_sha256(opening.save_slot)
	if not _expect(facts.original_save_sha256.length() == 64, "The original published Store file has a complete content hash"): return
	_finish("pass")

func _resume() -> void:
	var prior_file := FileAccess.open(prior_path, FileAccess.READ)
	if not _expect(prior_file != null and prior_file.get_length() <= 8388608, "The retained first-phase evidence is present and bounded"): return
	var prior: Variant = bytes_to_var(prior_file.get_buffer(prior_file.get_length()))
	prior_file.close()
	if not _expect(prior is Dictionary and prior.get("status") == "pass" and prior.get("mode") == "prepare", "The first process actually completed its preparation"): return
	if not _expect(_same(opening.startup_resume_checkpoint, prior.prepared_checkpoint) and _same(opening.model.checkpoint().world, prior.prepared_checkpoint.world), "The fresh ordinary Host loads the exact typed checkpoint and original history"): return
	if not _expect(_same(opening.actor_world.diagnostics("P").declared_seed, prior.prepared_checkpoint.actors.P) and opening.request_sequence == 0 and opening.request_namespace != prior.original_namespace, "A new native registration uses the saved seed and a fresh request namespace"): return
	var snapshot: Dictionary = opening.model.projection()
	if not _conserved(snapshot) or not _expect(snapshot.inventories.P == 1 and snapshot.stock.held == 1 and snapshot.remaining == 1 and prior.recovered_work.remaining == 1 and prior.recovered_work.cycle_ticks == 2 and snapshot.power_enabled, "Products and completed first-tick progress survive the new process"): return
	var press := ""
	for id: String in snapshot.entities:
		if snapshot.entities[id].kind == "processor": press = id
	if not _expect(not press.is_empty(), "The saved processor identity remains placed"): return
	opening.character_presenter.set_physics_process(false)
	if not await _approach_axis(0, -1.2) or not _clock(true) or not await _approach_axis(0, 4.95): return
	for _plate: int in range(3):
		if not (await _until(func() -> bool: return opening.model.projection().stock.output == 1, "The reopened line produces the next plate")): return
		if not _retrieve(press): return
	var before: Dictionary = opening.model.checkpoint().world
	opening._confirm_goal()
	if not _expect(opening.goal_confirmed and opening.model.projection().inventories.P == 4 and _same(before, opening.model.checkpoint().world), "Four real plates confirm the objective without consuming them"): return
	if not _expect(opening._save_worksite().accepted and FileAccess.get_sha256(prior.original_save) == prior.original_save_sha256 and opening.save_slot != prior.original_save, "The fresh output saves the finished inventory without overwriting the original"): return
	facts["restored_checkpoint"] = opening.startup_resume_checkpoint
	facts["original_save_sha256"] = prior.original_save_sha256
	_finish("pass")

func _run() -> void:
	if mode not in ["prepare", "resume"] or not destination.is_absolute_path() or not DirAccess.dir_exists_absolute(destination.get_base_dir()) or FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
		push_error("Use an explicit first-shift mode and fresh absolute evidence path")
		quit(1)
		return
	if mode == "resume" and (not prior_path.is_absolute_path() or not FileAccess.file_exists(prior_path) or prior_path == destination):
		push_error("Resume requires the retained first-phase evidence")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	opening.auto_advance = false
	root.add_child(opening)
	if not _expect(opening.model is NativeModel and opening.model.native != null and opening.model.native.get_class() == "FactoryNativeWorld" and not opening.auto_advance and opening.save_slot_ready and opening.save_slot != destination, "The ordinary native scene owns its real clock and fresh save slot"): return
	if not (await _until(func() -> bool: return opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending, "The native character is ready on the floor before material commands")): return
	if mode == "prepare":
		await _prepare()
	else:
		await _resume()
