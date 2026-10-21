extends "res://opening/native_first_shift_check.gd"
## Actual ordinary-scene callbacks and Store continuation. The inherited helpers
## retain typed facts and finite custody; this observer sets no state or pose.

func _targets(before: Dictionary, action: Dictionary) -> Array:
	var result: Array = super._targets(before, action)
	if action.action == "place" and action.kind == "belt":
		# This disclosed case places Collector [0,1] and Press [2,1] first.
		# The new Belt [1,1] must admit both of those existing endpoints.
		result.append([0.0, 0.5, 1.65])
		result.append([3.3, 0.5, 1.65])
	return result

func _native_admission(before: Dictionary, action: Dictionary, reply: Dictionary, cut: Dictionary) -> bool:
	if reply.get("accepted") == true:
		return super._native_admission(before, action, reply, cut)
	var reach: Dictionary = reply.get("reach", {})
	var sample: Dictionary = cut.get("sample", {})
	if not _expect(reply.get("reason") == "out_of_reach" and cut.get("available") == true
		and cut.get("actor") == "P" and sample.get("registered") == true and sample.get("ready") == true
		and typeof(reply.get("native_epoch")) == TYPE_INT and reply.native_epoch > 0
		and reply.native_epoch == sample.get("native_epoch") and reply.native_epoch == reach.get("native_epoch")
		and reach.get("actor") == "P" and reach.get("build_reach") == 4.0
		and _finite_point3(sample.get("position")) and _same(sample.position, sample.get("node_position"))
		and _same(sample.position, reply.get("actor_position")) and _same(sample.position, reach.get("position")),
		"The refused attachment retains its original registered native actor cut"):
		return false
	var targets: Array = _targets(before, action)
	var distances: Array = []
	for target: Array in targets:
		var squared := 0.0
		for axis in range(3):
			var difference: float = sample.position[axis] - target[axis]
			squared += difference * difference
		distances.append(squared)
	return _expect(_same(targets, reach.get("targets")) and _same(targets, reply.get("targets"))
		and _same(distances, reach.get("distances_squared")) and _same(distances, reply.get("distances_squared"))
		and distances.size() == 3 and distances[0] <= 16.0 and distances[1] <= 16.0 and distances[2] > 16.0,
		"The new belt and Collector are reachable, while the Press endpoint refuses the entire transaction")

func _build(kind: String, cell: Vector2i) -> void:
	opening.tool_buttons[kind].pressed.emit()
	opening._world_click(cell)

func _place_material(kind: String, cell: Vector2i, accepts: bool = true) -> Dictionary:
	return _action("ordinary " + kind + " button and world click",
		{"action": "place", "kind": kind, "cell": [cell.x, cell.y],
			"axis": opening.transmission_controls.selected_axis}, _build.bind(kind, cell), accepts)

func _walk(right: bool) -> bool:
	var before: Dictionary = opening.actor_world.diagnostics("P")
	var keys := [KEY_D, KEY_S] if right else [KEY_A, KEY_W]
	for key: Key in keys:
		_key(key, true)
	var reached := false
	while Time.get_ticks_msec() < deadline:
		var x: float = opening.model.projection().actors.P.position[0]
		reached = x >= 1.0 if right else x <= -1.0
		if reached:
			break
		await physics_frame
		await process_frame
	for key: Key in keys:
		_key(key, false)
	opening.character_presenter.release()
	for _frame in range(4):
		await physics_frame
		await process_frame
	var after: Dictionary = opening.actor_world.diagnostics("P")
	if not facts.has("walks"):
		facts["walks"] = []
	facts.walks.append({"right": right, "before": before, "after": after})
	var body: CharacterBody3D = opening.actor_world.bodies.P
	return _expect(reached and after.controls > before.controls and after.releases > before.releases
		and body.velocity.x == 0.0 and body.velocity.z == 0.0,
		"Ordinary character callbacks move and release the native motor before construction")

func _connected(ids: Dictionary) -> bool:
	var snapshot: Dictionary = opening.model.projection()
	var step: Dictionary = opening._guided_step({"collector": true, "belt": true, "processor": true})
	facts["confirmed_guidance"] = {"step": step, "snapshot": snapshot}
	if not _expect(_same(snapshot.links, [[ids.collector, ids.belt], [ids.belt, ids.press]])
		and snapshot.drive_links.is_empty() and not snapshot.powered and snapshot.stock.source == 16
		and step.get("tool") == "wheel", "Confirmed links skip Connect advice without creating power"):
		return false
	for id: String in ids.values():
		_select(id)
		if not _expect(not "[F]" in opening._inspection_hint(), "Connected machine inspection needs no redundant material link"):
			return false
	return _conserved(snapshot)

func _cached(wire: Dictionary, original: Dictionary, label: String) -> bool:
	var before: Dictionary = opening.model.checkpoint()
	var reply: Dictionary = opening.model.command(wire)
	if not facts.has("historical_lookups"):
		facts["historical_lookups"] = []
	facts.historical_lookups.append({"label": label, "reply": reply, "original": original})
	return _expect(reply.get("duplicate") == true and reply.get("accepted") == original.get("accepted")
		and reply.get("reason") == original.get("reason") and reply.get("entity") == original.get("entity")
		and _same(reply.get("reach"), original.get("reach")) and _same(before, opening.model.checkpoint()),
		label + " preserves the original outcome and admission without retargeting current geometry")

func _prepare() -> void:
	if not _expect(opening.model.projection().entities.is_empty(), "Preparation starts at the ordinary empty worksite") or not await _walk(true): return
	var collector := _place_material("collector", Vector2i(0, 1))
	if written: return
	var press := _place_material("processor", Vector2i(2, 1))
	if written or not await _walk(false): return
	var original_state: Dictionary = opening.model.checkpoint().world.state
	var refused := _place_material("belt", Vector2i(1, 1), false)
	if written: return
	var refused_wire: Dictionary = facts.actions[-1].intent.duplicate(true)
	if not _expect(_same(original_state, opening.model.checkpoint().world.state)
		and "closer" in opening.status_label.text.to_lower(), "A failed attachment spends nothing and gives readable reach advice"): return
	if not await _walk(true) or not _cached(refused_wire, refused, "A nearby pose cannot turn an old refusal into acceptance"): return
	var belt := _place_material("belt", Vector2i(1, 1))
	if written: return
	var original_wire: Dictionary = facts.actions[-1].intent.duplicate(true)
	var ids := {"collector": collector.entity, "belt": belt.entity, "press": press.entity}
	if not _connected(ids): return
	_select(belt.entity)
	_action("remove selected belt", {"action": "remove", "entity": belt.entity}, func(): opening.remove_button.pressed.emit())
	if written: return
	if not _expect(opening.model.projection().links.is_empty() and opening.model.projection().part_kits.P.belt == 2,
		"Removal refunds the exact belt and removes both incident material links"): return
	var rebuilt := _place_material("belt", Vector2i(1, 1))
	if written: return
	ids["belt"] = rebuilt.entity
	if not _expect(rebuilt.entity != belt.entity, "Reconstruction uses a new part identity") or not _connected(ids) \
		or not _cached(original_wire, belt, "An old accepted receipt cannot target its replacement"): return
	facts.merge({"ids": ids, "original_namespace": opening.request_namespace, "refused_wire": refused_wire,
		"refused_reply": refused, "original_wire": original_wire, "original_reply": belt})
	if not _expect(opening._save_worksite().accepted, "The ordinary Store saves the attachment history"): return
	facts["prepared_checkpoint"] = opening.model.checkpoint()
	facts["original_save"] = opening.save_slot
	facts["original_save_sha256"] = FileAccess.get_sha256(opening.save_slot)
	_finish("pass")

func _resume() -> void:
	var input := FileAccess.open(prior_path, FileAccess.READ)
	if not _expect(input != null and input.get_length() <= 8388608, "The retained producer result is present and bounded"): return
	var prior: Variant = bytes_to_var(input.get_buffer(input.get_length()))
	input.close()
	if not _expect(prior is Dictionary and prior.get("status") == "pass" and prior.get("mode") == "prepare",
		"The original process completed before reopening its file"): return
	facts["startup_loaded_checkpoint"] = opening.startup_resume_checkpoint
	if not _expect(_same(opening.startup_resume_checkpoint, prior.prepared_checkpoint)
		and _same(opening.model.checkpoint().world, prior.prepared_checkpoint.world)
		and _same(opening.actor_world.diagnostics("P").declared_seed, prior.prepared_checkpoint.actors.P)
		and opening.request_sequence == 0 and opening.request_namespace != prior.original_namespace,
		"A fresh ordinary Host restores typed history and the native seed before new material input"): return
	if not _connected(prior.ids) or not _cached(prior.refused_wire, prior.refused_reply, "Restored refusal stays historical") \
		or not _cached(prior.original_wire, prior.original_reply, "Restored accepted identity stays historical"): return
	if not _expect(opening.request_sequence == 0 and opening._save_worksite().accepted
		and opening.save_slot != prior.original_save and FileAccess.get_sha256(prior.original_save) == prior.original_save_sha256,
		"Read-only continuation and a separate output preserve the original binary without new material requests"): return
	_finish("pass")

func _run() -> void:
	facts["evidence"] = "ordinary_atomic_material_attachment"
	deadline = Time.get_ticks_msec() + 25000
	if mode not in ["prepare", "resume"] or not destination.is_absolute_path() or FileAccess.file_exists(destination) \
		or not DirAccess.dir_exists_absolute(destination.get_base_dir()):
		push_error("Use a declared mode and a fresh owned evidence path")
		quit(1)
		return
	opening = load("res://opening/opening.tscn").instantiate()
	root.add_child(opening)
	if not _expect(opening.model is NativeModel and opening.model.native.get_class() == "FactoryNativeWorld"
		and opening.auto_advance and opening.save_slot_ready, "The ordinary scene owns the sole live native World"): return
	var ready := func() -> bool:
		return opening.model.projection().actors.P.ready and opening.actor_world.bodies.P.is_on_floor() and not opening.startup_save_pending
	if not await _until(ready, "The actual native body is ready before ordinary construction"): return
	facts["initial_projection"] = opening.model.projection()
	opening.catalog_button.pressed.emit()
	if mode == "prepare":
		await _prepare()
	else:
		_resume()
