extends SceneTree
## Actual loopback clients use ordinary view callbacks; only the server owns World.
const Geometry = preload("res://opening/site_geometry.gd")
var session
var actor := ""
var phase := ""
var directory := ""
var previous := ""
var replies: Dictionary = {}
var opening
var checks := 0
var deadline := 0
var written := false
var facts: Dictionary = {"steps": [], "input_edges": [], "evidence": "ordinary_shared_cog_callbacks"}

func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--session-role="):
			actor = argument.trim_prefix("--session-role=")
		elif argument.begins_with("--cog-phase="):
			phase = argument.trim_prefix("--cog-phase=")
		elif argument.begins_with("--cog-directory="):
			directory = argument.trim_prefix("--cog-directory=")
		elif argument.begins_with("--cog-previous="):
			previous = argument.trim_prefix("--cog-previous=")
	deadline = Time.get_ticks_msec() + 30000
	facts = {"steps": [], "input_edges": [], "evidence": "ordinary_shared_cog_callbacks"}
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

func _expect(condition: bool, reason: String) -> bool:
	checks += 1
	if not condition:
		_record("fail", reason)
		push_error(reason)
	return condition

func _write(name: String, value: Dictionary) -> bool:
	var path := directory.path_join(name)
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".writing"):
		return false
	var bytes := var_to_bytes(value)
	if bytes.size() > 8388608:
		return false
	var file := FileAccess.open(path + ".writing", FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return DirAccess.rename_absolute(path + ".writing", path) == OK

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 8388608:
		return {}
	var value: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	return value if value is Dictionary else {}

func _record(status: String, reason: String = "") -> void:
	if written:
		return
	written = true
	facts.merge({"status": status, "reason": reason, "actor": actor, "phase": phase,
		"checks": checks, "process_id": OS.get_process_id()})
	if session != null:
		facts.merge({"projection": session.projection(), "namespace": session.request_namespace,
			"request_sequence": session.request_sequence, "client_world_is_null": session.world == null,
			"pending": opening.pending_actions.duplicate(true), "selected": opening.selected})
	if not _write(actor + "-result.bin", facts):
		push_error("Cannot retain the shared cog client result")
		quit(1)
		return
	print(JSON.stringify({"status": status, "actor": actor, "phase": phase, "checks": checks, "reason": reason}))
	quit(0 if status == "pass" else 1)

func _barrier(name: String) -> Dictionary:
	var path := directory.path_join(name)
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(path):
		await process_frame
	var observed := _read(path)
	if not _expect(observed.get("status") == "pass", "Only an explicit validated peer marker may release input: " + name):
		return {}
	return observed

func _order(minimum: int) -> bool:
	while Time.get_ticks_msec() < deadline and opening.state.get("order", -1) < minimum:
		await process_frame
	await physics_frame
	return _expect(opening.state.get("order", -1) >= minimum and opening.pending_actions.is_empty(),
		"The client must receive and settle the required confirmed order")

func _anchor(center: Array) -> Array:
	return [float(center[0]) * Geometry.PITCH / 4.0,
		Geometry.ANCHOR_HEIGHT + float(center[1]) * Geometry.PITCH / 4.0,
		float(center[2]) * Geometry.PITCH / 4.0]

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		facts.input_edges.append({"kind": "key", "code": int(code), "pressed": pressed})
		opening._unhandled_input(event)

func _click(center: Array) -> void:
	var at := _anchor(center)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = opening.camera.unproject_position(Vector3(at[0], at[1], at[2]))
	var cell: Vector2i = opening._screen_cell(event.position)
	facts.input_edges.append({"kind": "projected_click", "center": center.duplicate(),
		"screen": [event.position.x, event.position.y], "resolved_cell": [cell.x, cell.y],
		"resolved_quarter": opening._transmission_center(event.position), "picked_before": opening._screen_entity(event.position),
		"mode": opening.mode, "tool": opening.transmission_controls.active_tool})
	opening._unhandled_input(event)

func _point(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate: Variant in value:
		if typeof(coordinate) != TYPE_FLOAT or not is_finite(coordinate):
			return false
	return true

func _callback(label: String, wire: Dictionary, targets: Array, callback: Callable) -> Dictionary:
	var before: Dictionary = session.projection()
	var sequence: int = session.request_sequence
	callback.call()
	var queued: Dictionary = opening.last_submission.duplicate(true)
	var row := {"label": label, "expected": wire.duplicate(true), "before": before,
		"queued": queued, "sequence_before": sequence, "immediate": session.projection(),
		"local_result": opening.last_local_result.duplicate(true)}
	facts.steps.append(row)
	if not _expect(session.request_sequence == sequence + 1 and queued.get("queued", false)
		and queued.get("accepted") == false and opening.pending_actions.has(queued.get("request", "")),
		label + " must queue one ordinary client request without accepting it locally"):
		return {}
	if not _expect(_same(_material_view(before), _material_view(row.immediate)),
		label + " must not speculate geometry, custody or order while its request is pending"):
		return {}
	var request: String = queued.request
	while Time.get_ticks_msec() < deadline and (opening.pending_actions.has(request) or not replies.has(request)):
		await process_frame
	row["after"] = session.projection()
	row["pending_after"] = opening.pending_actions.duplicate(true)
	if not _expect(not opening.pending_actions.has(request) and replies.has(request), label + " must settle its original server outcome"):
		return {}
	var outcome: Dictionary = replies[request][-1].duplicate(true)
	row["outcome"] = outcome
	var actual: Dictionary = session._sent.get(request, {}).duplicate(true)
	row["wire"] = actual.duplicate(true)
	for key in ["context", "client", "request"]:
		actual.erase(key)
	if not _expect(_same(actual, wire) and outcome.get("accepted") == true and outcome.get("duplicate") == false,
		label + " must preserve its literal input and receive one fresh native acceptance"):
		return {}
	if not _expect(outcome.get("order") == before.get("order", -1) + 1 and opening.state.order >= outcome.order,
		label + " must advance exactly one authoritative request before its confirmed display"):
		return {}
	var reach: Dictionary = outcome.get("reach", {})
	if not _expect(reach.get("actor") == actor and typeof(outcome.get("native_epoch")) == TYPE_INT
		and outcome.native_epoch > 0 and reach.get("native_epoch") == outcome.native_epoch
		and _point(outcome.get("actor_position")) and _same(reach.get("position"), outcome.actor_position)
		and _same(reach.get("targets"), targets) and reach.get("build_reach") == 4.0,
		label + " must carry this actor's original native cut and literal targets"):
		return {}
	var distances: Array = []
	for target: Variant in targets:
		if not _expect(_point(target), label + " needs an exact finite three-coordinate target"):
			return {}
		var squared := 0.0
		for axis in range(3):
			var difference: float = outcome.actor_position[axis] - target[axis]
			squared += difference * difference
		distances.append(squared)
		if not _expect(squared <= 16.0, label + " must stay within scalar three-dimensional reach"):
			return {}
	if not _expect(_same(reach.get("distances_squared"), distances), label + " must preserve the exact admission distances"):
		return {}
	return outcome

func _material_view(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["context", "order", "initial_feed", "recipe_input", "entities", "transmission_parts", "links",
		"drive_links", "engagements", "motion", "stock", "cargo", "inventories", "part_kits", "part_specifications", "remaining", "power_enabled"]:
		result[key] = snapshot.get(key)
	return result

func _part_node(id: String) -> Node3D:
	for node: Node in opening.transmission_presenter.get_children():
		if node.get_meta("entity", "") == id:
			return node
	return null

func _geometry(ids: Dictionary, running: bool) -> bool:
	var state: Dictionary = opening.state
	var expected := {ids.a: [-4, 4, 4], ids.b: [0, 4, 4], ids.shaft_a: [-4, 2, 4], ids.shaft_b: [0, 2, 4]}
	var rendered: Dictionary = {}
	for id: String in expected:
		var node := _part_node(id)
		var observed := {"present": node != null}
		if node != null:
			var pick := node.get_node_or_null("Pick") as StaticBody3D
			var arrow: Node = node.get_node_or_null("ConfirmedDirection")
			observed.merge({"position": [node.position.x, node.position.y, node.position.z],
				"basis_x": [node.basis.x.x, node.basis.x.y, node.basis.x.z],
				"basis_y": [node.basis.y.x, node.basis.y.y, node.basis.y.z],
				"basis_z": [node.basis.z.x, node.basis.z.y, node.basis.z.z],
				"pick_entity": pick.get_meta("entity", "") if pick != null else "",
				"pick_layer": pick.collision_layer if pick != null else 0,
				"pick_mask": pick.collision_mask if pick != null else -1,
				"direction": arrow.get_meta("sign", 0) if arrow != null else 0})
		rendered[id] = observed
	if not facts.has("presentations"):
		facts["presentations"] = []
	facts.presentations.append({"running": running, "snapshot": state.duplicate(true), "rendered": rendered})
	if not _expect(state.transmission_parts.size() == 4 and state.power_enabled == running and state.powered == running,
		"Confirmed geometry must contain the exact finite train and drive state"):
		return false
	for id: String in expected:
		var part: Dictionary = state.transmission_parts.get(id, {})
		var node := _part_node(id)
		var gear := id in [ids.a, ids.b]
		if not _expect(part.get("axis") == 1 and typeof(part.get("axis")) == TYPE_INT
			and part.get("kind") == ("gear" if gear else "shaft")
			and _same(part.get("teeth"), 2 if gear else 0) and _same(part.get("half_span"), 0 if gear else 2)
			and _same(part.get("center"), expected[id]) and node != null and node.basis.y == Vector3.UP
			and node.basis.is_finite() and is_equal_approx(node.basis.determinant(), 1.0)
			and rendered[id].pick_entity == id and rendered[id].pick_layer == Geometry.PICK_LAYER and rendered[id].pick_mask == 0,
			"Both clients must render the original confirmed quarter-grid parts with their pick identities"):
			return false
	for pair in [[ids.a, 1], [ids.b, -1]]:
		var motion: Dictionary = state.motion.get(pair[0], {})
		var arrow: Node = _part_node(pair[0]).get_node_or_null("ConfirmedDirection")
		if running:
			if not _expect(_same(motion, {"state": "rotating", "numerator": pair[1], "denominator": 1})
				and arrow != null and arrow.get_meta("sign", 0) == pair[1], "Both clients must show the literal reversed signed rates"):
				return false
		elif not _expect(arrow == null, "Stopped confirmed geometry must not show a rotating glyph"):
			return false
	return _expect(_same(state.stock, {"source": 15, "collector": 1, "belt": 0, "input": 0, "held": 0, "output": 0, "player": 0})
		and _same(state.part_kits, {"P": {"collector": 0, "belt": 1, "processor": 1, "wheel": 0, "shaft": 1, "gear": 0},
			"Q": {"collector": 0, "belt": 0, "processor": 0, "wheel": 0, "shaft": 0, "gear": 0}})
		and _same(state.inventories, {"P": 0, "Q": 0})
		and _same(state.cargo, {"P": {"raw": 0, "products": 0, "work_lots": []}, "Q": {"raw": 0, "products": 0, "work_lots": []}}),
		"The train retains the original sixteen raw units without a product or throughput claim")

func _inspect(id: String, center: Array) -> bool:
	_key(KEY_I)
	await physics_frame
	_click(center)
	await process_frame
	await process_frame
	if not facts.has("inspections"):
		facts["inspections"] = []
	var worksite: Rect2 = opening.remove_button.get_parent().get_parent().get_global_rect()
	var footer: Rect2 = opening.status_label.get_parent().get_parent().get_global_rect()
	facts.inspections.append({"target": id, "selected": opening.selected, "text": opening.inspector.text,
		"remove_disabled": opening.remove_button.disabled, "request_sequence": session.request_sequence,
		"snapshot": session.projection(), "viewport": [root.size.x, root.size.y],
		"worksite": [worksite.position.x, worksite.position.y, worksite.size.x, worksite.size.y],
		"footer": [footer.position.x, footer.position.y, footer.size.x, footer.size.y]})
	return _expect(opening.selected == id and "Cogwheel" in opening.inspector.text and not opening.remove_button.disabled,
		"Ordinary inspection must select the confirmed cog through its actual pick body") and _expect(
		worksite.end.y <= footer.position.y and worksite.end.x <= root.size.x - 18,
		"The actual selected shared cog inspector must fit above its connection footer")

func _initial() -> bool:
	var observed: Dictionary = session.projection()
	if not _expect(_write(actor + "-initial.bin", {"status": "observed", "snapshot": observed,
		"namespace": session.request_namespace, "request_sequence": session.request_sequence,
		"view_sequence": opening.request_sequence, "selected": opening.selected,
		"client_world_is_null": session.world == null, "model_is_session": opening.model == session,
		"actor_world_is_null": opening.actor_world == null,
		"save_disabled": opening.save_button.disabled, "load_disabled": opening.load_button.disabled}), "Retain complete initial values before checking them"):
		return false
	facts["initial"] = observed.duplicate(true)
	if not _expect(observed.get("options") is Dictionary and observed.get("actors") is Dictionary
		and observed.actors.get("P") is Dictionary and observed.actors.get("Q") is Dictionary,
		"The initial shared projection must retain its declared native actor schema"):
		return false
	if not _expect(session.world == null and opening.model == session and opening.actor_world == null and not opening.auto_advance
		and session.request_sequence == 0 and opening.request_sequence == 0 and opening.selected.is_empty()
		and opening.save_button.disabled and opening.load_button.disabled
		and observed.options.get("native") == true and observed.actors.P.get("ready") == true and observed.actors.Q.get("ready") == true,
		"Fresh ordinary clients must have no World, producer, material request or retained UI selection"):
		return false
	if phase == "resume":
		var original := _read(previous.path_join("server-final.bin"))
		var ready := _read(directory.path_join("server-ready.bin"))
		var old_client := _read(previous.path_join(actor + "-result.bin"))
		if not _expect(original.get("status") == "pass" and old_client.get("status") == "pass"
			and session.request_namespace != old_client.get("namespace")
			and _same(ready.get("persistence", {}).get("loaded_checkpoint"), original.get("checkpoint"))
			and _same(_material_view(observed), _material_view(original.get("snapshot", {}))),
			"The fresh host must load the original typed save and allocate new client namespaces before input"):
			return false
	elif not _expect(observed.order == 0 and observed.stock.source == 16, "Production begins with the original finite empty worksite"):
		return false
	if not _expect(_write(actor + "-initial-ready.bin", {"status": "pass", "observed_sha256": FileAccess.get_sha256(directory.path_join(actor + "-initial.bin"))}),
		"Validated initial barriers must be separate from raw observations"):
		return false
	return not (await _barrier(("Q" if actor == "P" else "P") + "-initial-ready.bin")).is_empty()

func _produce_p() -> bool:
	if (await _barrier("Q-kit-refused.bin")).is_empty():
		return false
	opening.tool_buttons.wheel.pressed.emit()
	var wheel := await _callback("P wheel button and world click", {"action": "place", "kind": "wheel", "cell": [-1, 1], "axis": "y"},
		[_anchor([-4, 0, 4])], func(): _click([-4, 0, 4]))
	if wheel.is_empty():
		return false
	opening.tool_buttons.collector.pressed.emit()
	var collector := await _callback("P collector button and world click", {"action": "place", "kind": "collector", "cell": [0, 1], "axis": "y"},
		[_anchor([0, 0, 4])], func(): _click([0, 0, 4]))
	if collector.is_empty():
		return false
	_key(KEY_6)
	var a := await _callback("P first cog shortcut and screen click", {"action": "place_gear", "center": [-4, 4, 4], "axis": "y", "teeth": 2},
		[_anchor([-4, 4, 4])], func(): _click([-4, 4, 4]))
	if a.is_empty():
		return false
	var b := await _callback("P second cog screen click", {"action": "place_gear", "center": [0, 4, 4], "axis": "y", "teeth": 2},
		[_anchor([0, 4, 4])], func(): _click([0, 4, 4]))
	if b.is_empty():
		return false
	_key(KEY_G)
	_click([-4, 0, 4])
	var sa := await _callback("P source shaft endpoints", {"action": "connect_drive", "from": wheel.entity, "to": a.entity},
		[_anchor([-4, 0, 4]), _anchor([-4, 4, 4])], func(): _click([-4, 4, 4]))
	if sa.is_empty():
		return false
	_click([0, 4, 4])
	var sb := await _callback("P output shaft endpoints", {"action": "connect_drive", "from": b.entity, "to": collector.entity},
		[_anchor([0, 4, 4]), _anchor([0, 0, 4])], func(): _click([0, 0, 4]))
	if sb.is_empty():
		return false
	var ids := {"wheel": wheel.entity, "collector": collector.entity, "a": a.entity, "b": b.entity, "shaft_a": sa.entity, "shaft_b": sb.entity}
	facts["ids"] = ids
	if (await _callback("P ordinary Start drive", {"action": "set_power", "active": true}, [_anchor([-4, 0, 4])],
		func(): opening.power_button.pressed.emit())).is_empty():
		return false
	while Time.get_ticks_msec() < deadline and opening.state.stock.source != 15:
		await process_frame
	if not _geometry(ids, true) or not _expect(_write("train-running.bin", {"status": "pass", "ids": ids, "order": opening.state.order}), "Publish the validated train"):
		return false
	if (await _barrier("Q-confirmed-running.bin")).is_empty():
		return false
	if (await _callback("P ordinary Stop drive", {"action": "set_power", "active": false}, [_anchor([-4, 0, 4])],
		func(): opening.power_button.pressed.emit())).is_empty() or not _geometry(ids, false):
		return false
	var old_request: String = facts.steps[2].queued.request
	var old_reply: Dictionary = facts.steps[2].outcome
	var seen: int = replies[old_request].size()
	var queued: Dictionary = session.retry(old_request)
	while Time.get_ticks_msec() < deadline and replies[old_request].size() == seen:
		await process_frame
	var retry: Dictionary = replies[old_request][-1]
	facts["shared_retry"] = {"queued": queued, "outcome": retry.duplicate(true), "original": old_reply.duplicate(true)}
	if not _expect(queued.get("queued", false) and retry.get("duplicate") == true and retry.get("entity") == ids.a
		and retry.get("native_epoch") == old_reply.get("native_epoch") and opening.state.order == 8 and session.request_sequence == 8,
		"The existing Session retry must return the original gear receipt without another admission or request"):
		return false
	return _expect(_write("P-stopped.bin", {"status": "pass", "ids": ids, "order": opening.state.order}), "Retain the stopped train before host save")

func _produce_q() -> bool:
	var before := _material_view(session.projection())
	_key(KEY_6)
	_click([-4, 4, 4])
	var after := _material_view(session.projection())
	facts["empty_kit"] = {"before": before, "after": after, "request_sequence": session.request_sequence,
		"menu_disabled": opening.transmission_controls.get_popup().is_item_disabled(0)}
	if not _expect(session.request_sequence == 0 and opening.last_submission.is_empty() and _same(before, after)
		and opening.transmission_controls.get_popup().is_item_disabled(0), "Q's real shortcut click cannot borrow P's finite cog kit"):
		return false
	if not _expect(_write("Q-kit-refused.bin", {"status": "pass"}), "Publish the validated local kit refusal"):
		return false
	var train := await _barrier("train-running.bin")
	if train.is_empty() or not await _order(train.order) or not _geometry(train.ids, true) or not await _inspect(train.ids.a, [-4, 4, 4]):
		return false
	facts["ids"] = train.ids
	if not _expect(_write("Q-confirmed-running.bin", {"status": "pass", "selected": opening.selected}), "Q confirms the remote train and selected cog"):
		return false
	var stopped := await _barrier("P-stopped.bin")
	return not stopped.is_empty() and await _order(stopped.order) and _geometry(train.ids, false)

func _resume_q(ids: Dictionary) -> bool:
	if not await _inspect(ids.a, [-4, 4, 4]):
		return false
	if (await _callback("Q restored selected-cog removal", {"action": "remove", "entity": ids.a}, [_anchor([-4, 4, 4])],
		func(): opening.remove_button.pressed.emit())).is_empty():
		return false
	if not _expect(opening.state.part_kits.Q.gear == 1 and opening.state.part_kits.P.gear == 0
		and not opening.state.transmission_parts.has(ids.a), "The exact removed cog enters Q's confirmed kit without duplication"):
		return false
	_key(KEY_6)
	var rebuilt := await _callback("Q restored-train reconstruction", {"action": "place_gear", "center": [-4, 4, 4], "axis": "y", "teeth": 2},
		[_anchor([-4, 4, 4])], func(): _click([-4, 4, 4]))
	if rebuilt.is_empty() or not _expect(rebuilt.entity != ids.a, "Reconstruction creates a new gear identity"):
		return false
	facts["old_gear"] = ids.a
	ids = ids.duplicate(true)
	ids["a"] = rebuilt.entity
	facts["ids"] = ids
	if not _geometry(ids, false) or not _expect(_write("Q-rebuilt.bin", {"status": "pass", "ids": ids, "order": opening.state.order}), "Q publishes the confirmed replacement"):
		return false
	var running := await _barrier("resumed-running.bin")
	if running.is_empty() or not await _order(running.order) or not _geometry(ids, true) or not await _inspect(ids.a, [-4, 4, 4]):
		return false
	if not _expect(_write("Q-resumed-confirmed.bin", {"status": "pass"}), "Q confirms resumed signed motion"):
		return false
	var stopped := await _barrier("P-resumed-stopped.bin")
	return not stopped.is_empty() and await _order(stopped.order) and _geometry(ids, false)

func _resume_p() -> bool:
	var rebuilt := await _barrier("Q-rebuilt.bin")
	if rebuilt.is_empty() or not await _order(rebuilt.order) or not _geometry(rebuilt.ids, false):
		return false
	facts["ids"] = rebuilt.ids
	if (await _callback("P starts Q's reconstructed train", {"action": "set_power", "active": true}, [_anchor([-4, 0, 4])],
		func(): opening.power_button.pressed.emit())).is_empty() or not _geometry(rebuilt.ids, true):
		return false
	if not _expect(_write("resumed-running.bin", {"status": "pass", "order": opening.state.order}), "P publishes resumed native motion"):
		return false
	if (await _barrier("Q-resumed-confirmed.bin")).is_empty():
		return false
	if (await _callback("P stops the reconstructed train", {"action": "set_power", "active": false}, [_anchor([-4, 0, 4])],
		func(): opening.power_button.pressed.emit())).is_empty() or not _geometry(rebuilt.ids, false):
		return false
	return _expect(opening.state.order == 12 and _write("P-resumed-stopped.bin", {"status": "pass", "order": opening.state.order}),
		"The fresh cohort adds exactly four requests before its stopped save")

func _run() -> void:
	if actor not in ["P", "Q"] or phase not in ["produce", "resume"] or not directory.is_absolute_path():
		push_error("The shared cog client requires its role, phase and owned directory")
		quit(1)
		return
	opening = load("res://opening/shared_opening.tscn").instantiate()
	root.add_child(opening)
	session = opening.session
	session.outcome.connect(func(outcome: Dictionary):
		var request: String = outcome.get("request", "")
		if not replies.has(request):
			replies[request] = []
		replies[request].append(outcome.duplicate(true)))
	while Time.get_ticks_msec() < deadline and not session.is_ready():
		await process_frame
	if not _expect(session.is_ready(), "Both ordinary clients must join the native server") or not await _initial():
		return
	opening._select_tool("gear")
	opening.transmission_controls._axes.id_pressed.emit(1)
	if not _expect(opening.mode == "gear" and opening.transmission_controls.visible and opening.transmission_controls.selected_axis == "y",
		"Ordinary tool selection and axis menu signals configure the native tools"):
		return
	var passed := false
	if phase == "produce":
		if actor == "P":
			passed = await _produce_p()
		else:
			passed = await _produce_q()
	else:
		var old := _read(previous.path_join("P-stopped.bin"))
		if not _expect(old.get("status") == "pass", "Continuation uses the original validated stopped train"):
			return
		if actor == "P":
			passed = await _resume_p()
		else:
			passed = await _resume_q(old.ids)
	if passed and not written:
		_record("pass")
