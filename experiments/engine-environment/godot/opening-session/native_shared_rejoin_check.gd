extends "res://opening-session/native_shared_cog_check.gd"
## A live reconnect consumer of the paused shared-work checkpoint.
## The ordinary server retains the only World, actor bodies and material clock.
var prepared: Dictionary = {}
var baseline: Dictionary = {}
const INITIAL_ORE := 4096
var outcomes: Dictionary = {}

func _init() -> void:
	super._init()
	if phase in ["firstplate", "firstplate-resume", "running-cog", "running-cog-resume"]:
		deadline = Time.get_ticks_msec() + 240000
		if phase == "running-cog":
			facts.evidence = "ordinary_shared_running_cog_repair_scene"
		elif phase == "running-cog-resume":
			facts.evidence = "ordinary_shared_running_cog_reopen_scene"
		else:
			facts.evidence = "ordinary_shared_first_plate_scene"
	else:
		deadline = Time.get_ticks_msec() + 45000
		facts.evidence = "shared_native_carried_work_rejoin"

func _until(condition: Callable, reason: String) -> bool:
	while Time.get_ticks_msec() < deadline and not condition.call():
		await process_frame
	return _expect(condition.call(), reason)

func _retain(name: String) -> bool:
	return _expect(_write(name, {"status": "observed", "snapshot": session.projection(),
		"namespace": session.request_namespace, "request_sequence": session.request_sequence,
		"pending": opening.pending_actions.duplicate(true), "selected": opening.selected,
		"ready": session.is_ready(), "client_world_is_null": session.world == null,
		"actor_world_is_null": opening.actor_world == null}), "Retain the complete client observation before comparing it")

func _unchanged(order: int) -> bool:
	var observed := _material_view(session.projection())
	var expected := baseline.duplicate(true)
	expected.order = order
	return _expect(_same(observed, expected), "The original material, parts, work recipe and individual credit remain exact") and _conserved()

func _conserved() -> bool:
	var state: Dictionary = session.projection()
	var total := 0
	var products := 0
	for key: String in ["source", "collector", "belt", "input", "held", "output", "player"]:
		var amount: Variant = state.stock.get(key)
		if not _expect(typeof(amount) == TYPE_INT and amount >= 0 and amount <= 16, "Stock retains bounded integer quantities"):
			return false
		total += amount
	for owner: String in ["P", "Q"]:
		var cargo: Dictionary = state.cargo[owner]
		if not _expect(typeof(cargo.raw) == TYPE_INT and cargo.raw >= 0 and cargo.raw <= 16
			and typeof(cargo.products) == TYPE_INT and cargo.products >= 0 and cargo.products <= 16
			and _same(cargo.products, state.inventories[owner]), "Individual typed product credit agrees with cargo"):
			return false
		total += cargo.raw
		products += cargo.products
		for work: Dictionary in cargo.work_lots:
			if not _expect(typeof(work.id) == TYPE_INT and work.id > 0 and _same(work.recipe_input, 1)
				and _same(work.cycle_ticks, 2) and _same(work.remaining, 1), "Carried work retains its original typed recipe and progress"):
				return false
			total += work.recipe_input
	return _expect(_same(state.initial_feed, 16) and _same(state.recipe_input, 1)
		and total == 16 and products == state.stock.player, "Every original unit has exactly one weighted material owner")

func _marker(name: String, extra: Dictionary = {}) -> bool:
	var record := {"status": "pass", "order": opening.state.order}
	record.merge(extra)
	return _expect(_write(name, record), "Publish a validated peer barrier")

func _peer(name: String) -> Dictionary:
	var record := await _barrier(name)
	if record.is_empty() or not await _order(record.order):
		return {}
	return record

func _target() -> Array:
	var cell: Array = opening.state.entities[prepared.ids.press].cell
	return _anchor([cell[0] * 4, 0, cell[1] * 4])

func _bad_insert(work_id: int, label: String) -> Dictionary:
	var before := _material_view(session.projection())
	var sequence: int = session.request_sequence
	var wire := {"action": "insert_work", "entity": prepared.ids.press, "work_id": work_id}
	# Deliberate invalid input through the normal view, not an offered menu item.
	var queued: Dictionary = opening.issue(wire)
	if not _expect(queued.get("queued") == true and session.request_sequence == sequence + 1,
		"The invalid transfer queues one request through the ordinary Session"):
		return {}
	var request: String = queued.request
	if not await _until(func(): return replies.has(request) and opening.pending_actions.is_empty(),
		"The original native refusal settles before the disconnect boundary"):
		return {}
	var outcome: Dictionary = replies[request][-1]
	facts.steps.append({"label": label, "before": before, "wire": session._sent[request].duplicate(true),
		"queued": queued, "outcome": outcome.duplicate(true), "after": session.projection()})
	if not _expect(outcome.get("accepted") == false and outcome.get("duplicate") == false
		and outcome.get("reason") == "unavailable_cargo" and _same(outcome.get("order"), before.order + 1),
		"Missing or foreign work cannot be inserted or credited") or not _unchanged(before.order + 1):
		return {}
	return outcome

func _menu(action: String) -> bool:
	opening._select_tool("inspect")
	var cell: Array = opening.state.entities[prepared.ids.press].cell
	opening._world_click(Vector2i(cell[0], cell[1]), prepared.ids.press)
	var control = opening.recovery_actions
	if not _expect(control != null and control.visible and not control.action_button.disabled,
		"The reconnected actor can use the ordinary material menu"):
		return false
	control._open_menu()
	var popup: PopupMenu = control.action_button.get_popup()
	var wire := {"action": action, "entity": prepared.ids.press}
	if action == "insert_work":
		wire["work_id"] = prepared.lot.id
	for index: int in range(popup.item_count):
		if _same(popup.get_item_metadata(index).wire, wire):
			return not (await _callback("Reconnected Q " + action, wire, [_target()],
				control._choose.bind(popup.get_item_id(index)))).is_empty()
	return _expect(false, "The menu must offer the literal transfer of the original work")

func _only_p_connected() -> bool:
	# Lifecycle diagnostics only; JSON values never become material authority.
	var path := directory.path_join("status.json")
	if not FileAccess.file_exists(path):
		return false
	var status: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return status is Dictionary and status.get("peer_count") == 1 and status.get("roles") is Dictionary \
		and status.roles.has("P") and not status.roles.has("Q")

func _p() -> bool:
	if (await _peer("Q-refusal-settled.bin")).is_empty() or not _unchanged(baseline.order + 1):
		return false
	if (await _barrier("Q-disconnected.bin")).is_empty() or not await _until(_only_p_connected,
		"The original host releases Q's peer binding before foreign input or reconnection"):
		return false
	facts["disconnected_server_status"] = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("status.json")))
	if (await _bad_insert(prepared.lot.id, "P refuses Q's carried work while Q is disconnected")).is_empty():
		return false
	if not _marker("P-foreign-refused.bin") or (await _peer("Q-material-cycled.bin")).is_empty():
		return false
	return _retain("P-final-observed.bin") and _unchanged(baseline.order + 4)

func _q() -> bool:
	var refused := await _bad_insert(prepared.lot.id + 1, "Q settles a missing-work refusal in its old namespace")
	if refused.is_empty() or not _marker("Q-refusal-settled.bin"):
		return false
	var old_namespace: String = session.request_namespace
	var old_request: String = refused.request
	var old_sequence: int = session.request_sequence
	if not _retain("Q-before-disconnect.bin"):
		return false
	opening.disconnect_button.pressed.emit()
	if not _retain("Q-disconnected-observed.bin") or not _expect(not session.is_ready()
		and session.world == null and opening.actor_world == null and opening.pending_actions.is_empty()
		and opening.selected.is_empty(), "Disconnect leaves a read-only client and no local material owner"):
		return false
	var blocked: Dictionary = opening.issue({"action": "insert_work", "entity": prepared.ids.press, "work_id": prepared.lot.id})
	facts["disconnected_submission"] = blocked.duplicate(true)
	if not _expect(blocked.get("queued") == false and blocked.get("reason") == "session_not_ready"
		and session.request_sequence == old_sequence, "Disconnected material input cannot queue or spend a request"):
		return false
	if not _marker("Q-disconnected.bin") or (await _barrier("P-foreign-refused.bin")).is_empty():
		return false
	opening.reconnect_button.pressed.emit()
	if not await _until(func(): return session.is_ready() and not opening.connecting,
		"The ordinary reconnect control rejoins the same live host") or not _retain("Q-rejoined-observed.bin"):
		return false
	if not _expect(session.request_namespace != old_namespace and session.request_sequence == 0
		and opening.request_sequence == 0 and session._sent.is_empty() and opening.pending_actions.is_empty()
		and opening.uncertain_actions.is_empty() and opening.selected.is_empty() and opening.pending_link.is_empty()
		and session.world == null and opening.actor_world == null,
		"Reconnection creates a fresh namespace without replaying settled input or creating authority"):
		return false
	if not _unchanged(baseline.order + 2):
		return false
	var retry: Dictionary = session.retry(old_request)
	facts["old_request_retry"] = {"request": old_request, "old_namespace": old_namespace,
		"new_namespace": session.request_namespace, "result": retry.duplicate(true)}
	if not _expect(retry.get("queued") == false and retry.get("reason") == "unknown_request"
		and session.request_sequence == 0, "An old namespace's settled request cannot be sent by the new binding"):
		return false
	if not await _menu("insert_work") or not _retain("Q-inserted-observed.bin"):
		return false
	var expected := baseline.duplicate(true)
	expected.order = baseline.order + 3
	expected.stock.held = 1
	expected.remaining = 1
	expected.cargo.Q.work_lots = []
	if not _expect(_same(_material_view(session.projection()), expected),
		"Reinsertion moves exactly the original one-tick work from Q to the empty press"):
		return false
	if not _conserved():
		return false
	if not await _menu("recover") or not _retain("Q-final-observed.bin") or not _unchanged(baseline.order + 4):
		return false
	return _expect(session.request_sequence == 2 and opening.uncertain_actions.is_empty(),
		"Only two explicit material transfers occur after reconnection") and _marker("Q-material-cycled.bin")

func _run() -> void:
	if phase in ["firstplate", "firstplate-resume"]:
		await _run_firstplate()
		return
	if phase in ["running-cog", "running-cog-resume"]:
		await _run_running_cog()
		return
	if actor not in ["P", "Q"] or phase != "resume" or not directory.is_absolute_path() or not previous.is_absolute_path():
		push_error("The reconnect consumer requires P or Q and the original producer directory")
		quit(1)
		return
	prepared = _read(previous.path_join("P-stopped.bin"))
	if not _expect(prepared.get("status") == "pass" and prepared.get("lot") is Dictionary
		and _same(prepared.lot.get("remaining"), 1) and _same(prepared.lot.get("cycle_ticks"), 2),
		"Use the original observed positively progressed work, never a manufactured checkpoint"):
		return
	opening = load("res://opening/shared_opening.tscn").instantiate()
	root.add_child(opening)
	session = opening.session
	session.outcome.connect(func(outcome: Dictionary):
		var request: String = outcome.get("request", "")
		if not replies.has(request):
			replies[request] = []
		replies[request].append(outcome.duplicate(true)))
	if not await _until(func(): return session.is_ready(), "Both ordinary clients join the restored native host") or not await _initial():
		return
	# Q may settle its refusal while P resumes from the initial peer barrier.
	# The inherited deep copy was already validated before either peer could
	# proceed; the live projection is no longer an immutable initial baseline.
	baseline = _material_view(facts.initial)
	if not _expect(_same(baseline.cargo, {"P": {"raw": 0, "products": 0, "work_lots": []},
		"Q": {"raw": 1, "products": 1, "work_lots": [prepared.lot]}})
		and _same(baseline.inventories, {"P": 0, "Q": 1}) and baseline.stock.held == 0
		and not baseline.power_enabled and _same(baseline.order, prepared.order),
		"The original paused worksite has separate raw, product and whole-work custody"):
		return
	if not _conserved():
		return
	opening.catalog_button.pressed.emit()
	var passed := await _p() if actor == "P" else await _q()
	if passed and not written:
		_record("pass")

func _wait_for(predicate: Callable, label: String) -> bool:
	while Time.get_ticks_msec() < deadline and not predicate.call():
		await process_frame
	return _expect(predicate.call(), label)

func _send(action: Dictionary, label: String) -> Dictionary:
	var before: Dictionary = session.projection()
	var queued: Dictionary = opening.issue(action)
	if not _expect(queued.get("queued") == true and not queued.get("accepted", true)
			and session.world == null and opening.actor_world == null,
		label + " queues through the ordinary client without local authority"):
		return {}
	var request: String = str(queued.get("request", ""))
	if not await _wait_for(func(): return outcomes.has(request) and \
			not opening.pending_actions.has(request), label + " receives one native decision"):
		return {}
	var reply: Dictionary = outcomes[request]
	outcomes.erase(request)
	var wire: Dictionary = session._sent.get(request, {}).duplicate(true)
	for key in ["context", "client", "request"]:
		wire.erase(key)
	facts.steps.append({"label": label, "wire": wire, "order_before": before.order,
		"order_after": session.projection().order, "reply": reply})
	if not _expect(wire == action and reply.get("accepted") == true
			and reply.get("duplicate") == false and reply.get("order") == before.order + 1,
		label + " preserves its literal intent and one accepted native order"):
		return {}
	if action.get("action") == "harvest_source":
		var source: String = str(action.get("target", ""))
		var remaining: int = int(before.hand_sources[source].remaining) - 1
		if not await _wait_for(func(): return int(session.projection().hand_sources[source].remaining) == remaining,
			label + " reaches finite physical contact"):
			return {}
	return reply

func _walk(target: Vector2) -> bool:
	var start: Dictionary = session.projection().actors[actor].duplicate(true)
	var leg_deadline := mini(deadline, Time.get_ticks_msec() + 25000)
	while Time.get_ticks_msec() < leg_deadline:
		var sample: Dictionary = session.projection().actors[actor]
		var position: Array = sample.position
		var gap := target - Vector2(float(position[0]), float(position[2]))
		if gap.length() < 0.10:
			opening._release_character_input()
			return _expect(sample.native_epoch > start.native_epoch and sample.ready,
				"The observed server body walks to " + str(target))
		opening._send_character_input(gap.normalized(), false)
		await process_frame
	opening._release_character_input()
	facts["failed_walk"] = {"target": target, "at": session.projection().actors[actor].position}
	return _expect(false, "The physical shared actor reaches " + str(target))

func _walk_points(points: Array[Vector2]) -> bool:
	for point in points:
		if not await _walk(point):
			return false
	return true

func _id_for(kind: String) -> String:
	for id: String in session.projection().placed_components:
		if session.projection().placed_components[id].component == kind:
			return id
	return ""

func _crank_id() -> String:
	var items: Dictionary = session.projection().get("crank_items", {})
	return str(items.keys()[0]) if items.size() == 1 else ""

func _initial_p() -> bool:
	if (await _barrier("Q-ready.bin")).is_empty():
		return false
	var start: Dictionary = session.projection()
	var inventory = opening.building_hotbar
	if not _expect(start.order == 0 and start.cargo.P.products == 0
			and inventory.slots.all(func(slot: String) -> bool: return slot.is_empty())
			and session.world == null and opening.actor_world == null,
		"The shared arrival starts with an empty hotbar and no client material authority"):
		return false
	inventory.open_catalog()
	if not _expect(inventory.recipe_buttons.has("component:anvil")
			and inventory.recipe_buttons.has("component:flat_head")
			and inventory.recipe_buttons.has("component:wooden_slide")
			and inventory.recipe_buttons.has("component:hand_crank")
			and not inventory.recipe_buttons.has("component:wooden_cog"),
		"The first-plate catalog exposes only required press components"):
		return false
	inventory.catalog.hide()
	if not await _walk(Vector2(6.0, 3.45)):
		return false
	for index in range(5):
		if (await _send({"action": "harvest_source", "target": "tree-east-south"},
			"Timber cut %d" % index)).is_empty():
			return false
	if not await _walk_points([Vector2(4.95, 3.3), Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return false
	for index in range(4):
		if (await _send({"action": "harvest_source", "target": "opening-copper"},
			"Copper cut %d" % index)).is_empty():
			return false
	if not _expect(session.projection().cargo.P.timber == 5
			and session.projection().cargo.P.raw == 4
			and session.projection().hand_sources["opening-copper"].remaining == INITIAL_ORE - 4,
		"Five real timber and four real copper cuts fund the complete preplate bill"):
		return false
	if not await _walk_points([Vector2(0.0, 1.65), Vector2(3.3, 4.95)]):
		return false
	var bench: String = str(session.projection().fabrication_hub.id)
	for kind in ["anvil", "flat_head", "wooden_slide", "hand_crank"]:
		if (await _send({"action": "craft_component", "entity": bench, "component": kind},
			"Craft " + kind)).is_empty():
			return false
	var crank: String = _crank_id()
	if not _expect(not crank.is_empty() and session.projection().crank_items[crank].holder == "P"
			and session.projection().cargo.P.timber == 0 and session.projection().cargo.P.raw == 1,
		"The paid hand crank has an individual carried ID after finite crafting"):
		return false
	if not await _walk(Vector2(4.95, 4.95)):
		return false
	for part in [{"kind": "anvil", "center": [12, 0, 16]},
			{"kind": "flat_head", "center": [12, 1, 16]},
			{"kind": "wooden_slide", "center": [12, 2, 16]}]:
		if (await _send({"action": "place_component", "component": part.kind,
			"center": part.center}, "Place " + part.kind)).is_empty():
			return false
	var anvil := _id_for("anvil")
	var slide := _id_for("wooden_slide")
	if not _expect(not anvil.is_empty() and not slide.is_empty()
			and session.projection().sliding_press_assemblies.size() == 1,
		"Three individually placed parts assemble the native preplate press"):
		return false
	if (await _send({"action": "attach_hand_crank", "entity": slide,
			"crank": crank, "port": [13, 2, 16]}, "Fit paid crank to exterior slide input")).is_empty():
		return false
	if not _expect(session.projection().crank_items[crank].attached_to == slide,
		"Both clients can identify the same fitted crank"):
		return false
	var press: Dictionary = session.projection().sliding_press_assemblies[0]
	var route: Dictionary = press.open_feeds[0]
	if (await _send({"action": "feed_press", "entity": anvil, "entry": route.entry},
		"Feed the final carried blank to the workbed")).is_empty():
		return false
	var formed := false
	for index in range(64):
		if (await _send({"action": "turn_slide_crank", "entity": slide,
			"port": [13, 2, 16]}, "Turn fitted slide %d" % index)).is_empty():
			return false
		for drop: Dictionary in session.projection().dropped_material:
			if drop.center == press.work_center and drop.products == 1:
				formed = true
				break
		if formed:
			break
	if not _expect(formed and session.projection().cargo.P.products == 0
			and session.projection().workshop_completed_actors.is_empty(),
		"Forming on the supported workbed does not complete the carried-item milestone"):
		return false
	if not await _walk(Vector2(4.1, 6.0)):
		return false
	var expected_output: Dictionary = {}
	for drop: Dictionary in session.projection().dropped_material:
		if drop.center == press.work_center:
			expected_output = drop.duplicate(true)
			break
	if not _expect(not expected_output.is_empty(), "The same supported workbed retains the plate"):
		return false
	expected_output.erase("center")
	if (await _send({"action": "pickup_material", "center": press.work_center,
			"expected": expected_output},
		"Carry the first copper plate")).is_empty():
		return false
	if not _expect(session.projection().cargo.P.products == 1
			and session.projection().workshop_completed_actors.has("P"),
		"Only the carried first plate completes the shared native milestone"):
		return false
	if (await _send({"action": "detach_hand_crank", "entity": crank},
		"Detach the same reusable crank")).is_empty():
		return false
	if not _expect(session.projection().crank_items[crank].holder == "P"
			and session.projection().crank_items[crank].attached_to == "",
		"The paid crank returns to its original inventory identity"):
		return false
	return _expect(_write("P-complete.bin", {"status": "pass", "crank": crank,
		"slide": slide, "order": session.projection().order}),
		"Publish P's exact confirmed plate and crank IDs")

func _initial_q() -> bool:
	if not _expect(session.projection().order == 0
			and _write("Q-ready.bin", {"status": "pass"}),
		"Q joins before finite stock is spent"):
		return false
	var complete: Dictionary = await _barrier("P-complete.bin")
	if complete.is_empty() or not await _wait_for(
		func(): return session.projection().order >= complete.order,
		"Q receives the finished native chapter projection"):
		return false
	var view: Dictionary = session.projection()
	return _expect(view.cargo.P.products == 1
		and view.workshop_completed_actors.has("P")
		and view.crank_items.has(complete.crank)
		and view.crank_items[complete.crank].holder == "P"
		and view.placed_components.has(complete.slide)
		and view.hand_sources["opening-copper"].remaining == INITIAL_ORE - 4,
		"Q sees P's carried plate, exact crank and finite copper debit")

func _firstplate_resume_p() -> bool:
	if (await _barrier("Q-ready.bin")).is_empty():
		return false
	var view: Dictionary = session.projection()
	var saved: Dictionary = _read(previous.path_join("P-complete.bin"))
	if not _expect(saved.get("status") == "pass" and view.cargo.P.products == 1
			and view.crank_items.has(saved.crank)
			and view.crank_items[saved.crank].holder == "P"
			and view.placed_components.has(saved.slide)
			and view.workshop_completed_actors.has("P"),
		"Fresh server and ordinary client restore the same paid crank and plate"):
		return false
	if (await _send({"action": "attach_hand_crank", "entity": saved.slide,
			"crank": saved.crank, "port": [13, 2, 16]},
		"Refit the saved crank after rejoin")).is_empty():
		return false
	return _expect(_write("P-complete.bin", {"status": "pass", "crank": saved.crank,
		"order": session.projection().order}),
		"Publish the confirmed post-rejoin attachment")

func _firstplate_resume_q() -> bool:
	if not _expect(_write("Q-ready.bin", {"status": "pass"}),
		"Q rejoins the fresh native server"):
		return false
	var complete: Dictionary = await _barrier("P-complete.bin")
	if complete.is_empty() or not await _wait_for(
		func(): return session.projection().order >= complete.order,
		"Q receives the refitted saved crank"):
		return false
	var view: Dictionary = session.projection()
	return _expect(view.cargo.P.products == 1
		and view.crank_items.has(complete.crank)
		and not view.crank_items[complete.crank].attached_to.is_empty()
		and view.hand_sources["opening-copper"].remaining == INITIAL_ORE - 4,
		"Q sees the same crank ID fitted after restart without extra material")

func _running_cog_p() -> bool:
	if (await _barrier("Q-ready.bin")).is_empty():
		return false
	var start: Dictionary = session.projection()
	if not _expect(start.first_plate_unlock and start.workshop_completed_actors.has("P")
			and start.cargo.P.products == 1 and start.part_kits.P.gear == 0
			and start.part_kits.Q.gear == 0,
		"The saved first plate unlocks finite transmission crafting without a gifted cog"):
		return false
	if not await _walk_points([Vector2(6.6, 4.95), Vector2(6.6, 9.9), Vector2(6.0, 10.05)]):
		return false
	for index in range(6):
		if (await _send({"action": "harvest_source", "target": "tree-east-north"},
			"Gather cog-route timber %d" % index)).is_empty():
			return false
	if not await _walk_points([Vector2(6.6, 4.95), Vector2(4.1, 4.95),
			Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return false
	for index in range(3):
		if (await _send({"action": "harvest_source", "target": "opening-copper"},
			"Gather cog-route copper %d" % index)).is_empty():
			return false
	if not await _walk_points([Vector2(0.0, 1.65), Vector2(4.1, 4.95)]):
		return false
	var bench: String = str(session.projection().fabrication_hub.id)
	for part in [{"role": "waterwheel", "half_span": 0},
			{"role": "gear", "half_span": 0, "teeth": 4},
			{"role": "gear", "half_span": 0, "teeth": 4}]:
		var wire: Dictionary = {"action": "craft_part", "entity": bench,
			"role": part.role, "half_span": part.half_span}
		if part.has("teeth"):
			wire["teeth"] = part.teeth
		if (await _send(wire, "Craft paid " + str(part.role))).is_empty():
			return false
	var crafted: Dictionary = session.projection()
	if not _expect(crafted.cargo.P.timber == 0 and crafted.cargo.P.raw == 0
			and crafted.part_kits.P.wheel == 1 and crafted.part_kits.P.gear == 2
			and crafted.part_kits.Q.gear == 0,
		"Gathered ingredients become one P-owned waterwheel and two large cogs"):
		return false
	if not await _walk_points([Vector2(3.3, 3.3), Vector2(0.0, 3.3)]):
		return false
	var wheel := await _send({"action": "place", "kind": "wheel", "cell": [-2, 2],
		"axis": "x", "level": 4}, "Place the paid waterwheel")
	if wheel.is_empty() or not await _walk(Vector2(0.0, 4.95)):
		return false
	var source := await _send({"action": "place_gear", "center": [-4, 4, 8],
		"axis": "x", "teeth": 4}, "Place source cog")
	if source.is_empty() or not await _walk(Vector2(0.0, 6.6)):
		return false
	var output := await _send({"action": "place_gear", "center": [0, 4, 12],
		"axis": "z", "teeth": 4}, "Place output cog")
	if output.is_empty():
		return false
	var ids := {"wheel": str(wheel.entity), "source": str(source.entity), "output": str(output.entity)}
	var running: Dictionary = session.projection()
	if not _expect(running.motion[ids.wheel].state == "rotating"
			and running.motion[ids.source].state == "rotating"
			and running.motion[ids.output].state == "rotating",
		"The current placed gear train actually runs before either worker removes a part"):
		return false
	if not _expect(_write("train-running.bin", {"status": "pass", "ids": ids,
			"order": running.order, "cargo": running.cargo.duplicate(true)}),
		"Publish exact server-confirmed running part identities"):
		return false
	var removed: Dictionary = await _barrier("Q-removed.bin")
	if removed.is_empty() or not await _wait_for(func(): return session.projection().order >= removed.order,
		"P observes Q's confirmed removal"):
		return false
	var after: Dictionary = session.projection()
	if not _expect(not after.transmission_parts.has(ids.output)
			and after.part_kits.P.gear == 0 and after.part_kits.Q.gear == 1
			and after.motion[ids.wheel].state == "rotating"
			and after.motion[ids.source].state == "rotating"
			and after.cargo.P == running.cargo.P and after.cargo.Q == running.cargo.Q,
		"P sees only Q receive the removed cog while the waterwheel and source keep running"):
		return false
	if not _expect(_write("P-observed-removal.bin", {"status": "pass", "order": after.order}),
		"P confirms Q's removal before Q rebuilds the branch"):
		return false
	var rebuilt: Dictionary = await _barrier("Q-rebuilt.bin")
	if rebuilt.is_empty() or not await _wait_for(func(): return session.projection().order >= rebuilt.order,
		"P observes the server-confirmed replacement"):
		return false
	var final: Dictionary = session.projection()
	return _expect(rebuilt.new_output != ids.output and final.transmission_parts.has(rebuilt.new_output)
		and final.motion[rebuilt.new_output].state == "rotating"
		and final.part_kits.P.gear == 0 and final.part_kits.Q.gear == 0
		and _write("P-complete.bin", {"status": "pass", "ids": ids,
			"new_output": rebuilt.new_output, "order": final.order}),
		"P sees Q's replacement return the output branch to live motion")

func _running_cog_q() -> bool:
	if not await _walk(Vector2(4.1, 3.3)):
		return false
	if not _expect(_write("Q-ready.bin", {"status": "pass"}),
		"Q clears the output tile before P builds the running train"):
		return false
	var train: Dictionary = await _barrier("train-running.bin")
	if train.is_empty() or not await _wait_for(func(): return session.projection().order >= train.order,
		"Q receives P's running line from the native host"):
		return false
	var ids: Dictionary = train.ids
	if not await _walk(Vector2(2.5, 3.3)):
		return false
	var before: Dictionary = session.projection()
	if not _expect(before.motion[ids.output].state == "rotating" and before.part_kits.Q.gear == 0
		and before.part_kits.P.gear == 0,
		"Q reaches the live output cog without borrowing P's paid kit"):
		return false
	_key(KEY_F)
	if not _expect(opening.mode == "deconstruct", "F selects the ordinary dismantling control"):
		return false
	var removed := await _callback("Q removes P's running output cog",
		{"action": "remove", "entity": ids.output}, [_anchor([0, 4, 12])],
		func(): opening._world_click(Vector2i(0, 3), ids.output))
	if removed.is_empty():
		return false
	var after: Dictionary = session.projection()
	if not _expect(not after.transmission_parts.has(ids.output)
			and after.part_kits.Q.gear == 1 and after.part_kits.P.gear == 0
			and after.motion[ids.wheel].state == "rotating"
			and after.motion[ids.source].state == "rotating"
			and after.cargo == before.cargo and after.material_mass.accounted_mass == after.material_mass.initial_mass,
		"The server refunds only Q, interrupts the output, and conserves carried material"):
		return false
	if not _expect(_write("Q-removed.bin", {"status": "pass", "order": after.order}),
		"Publish Q's confirmed removal for P's independent view"):
		return false
	if (await _barrier("P-observed-removal.bin")).is_empty():
		return false
	var locked_before: Dictionary = session.projection()
	var locked_wire := {"action": "place_gear", "center": [0, 4, 12],
		"axis": "z", "teeth": 4}
	var locked_queue: Dictionary = opening.issue(locked_wire)
	if not _expect(locked_queue.get("queued") == true and not locked_queue.get("accepted", true)
			and _same(_material_view(session.projection()), _material_view(locked_before)),
		"Q's preplate rebuild request remains pending without local part or motion changes"):
		return false
	var locked_request: String = str(locked_queue.get("request", ""))
	if not await _wait_for(func(): return outcomes.has(locked_request) and \
			not opening.pending_actions.has(locked_request),
		"The native host decides Q's preplate rebuild attempt"):
		return false
	var locked_reply: Dictionary = outcomes[locked_request]
	var locked_after: Dictionary = session.projection()
	var unchanged: Dictionary = _material_view(locked_before)
	unchanged.order = locked_after.order
	facts.steps.append({"label": "Q's preplate rebuild is refused", "wire": locked_wire,
		"queue": locked_queue, "reply": locked_reply})
	if not _expect(locked_reply.get("accepted") == false
			and locked_reply.get("duplicate") == false
			and locked_reply.get("reason") == "first_plate_required"
			and locked_reply.get("order") == locked_before.order + 1
			and _same(_material_view(locked_after), unchanged)
			and locked_after.part_kits.Q.gear == 1,
		"Q keeps the refunded cog when the per-worker first-plate gate refuses placement"):
		return false
	if not await _walk_points([Vector2(0.0, 1.65), Vector2(-0.5, 0.0)]):
		return false
	if (await _send({"action": "harvest_source", "target": "opening-copper"},
		"Q gathers a separate copper blank for the first-plate lesson")).is_empty():
		return false
	if not await _walk_points([Vector2(0.0, 1.65), Vector2(4.1, 4.95), Vector2(4.1, 6.0)]):
		return false
	var press: Dictionary = session.projection().sliding_press_assemblies[0]
	var route: Dictionary = press.open_feeds[0]
	var anvil: String = str(press.anvil)
	var slide: String = str(press.parts.slide)
	if (await _send({"action": "feed_press", "entity": anvil, "entry": route.entry},
		"Q feeds a paid blank onto the shared workbed")).is_empty():
		return false
	var formed := false
	for index in range(64):
		if (await _send({"action": "turn_slide_crank", "entity": slide,
				"port": [13, 2, 16]}, "Q turns the fitted slide %d" % index)).is_empty():
			return false
		for drop: Dictionary in session.projection().dropped_material:
			if drop.center == press.work_center and drop.products == 1:
				formed = true
				break
		if formed:
			break
	if not _expect(formed and not session.projection().workshop_completed_actors.has("Q"),
		"Q's new plate stays on the workbed until Q carries it"):
		return false
	var output: Dictionary = {}
	for drop: Dictionary in session.projection().dropped_material:
		if drop.center == press.work_center:
			output = drop.duplicate(true)
			break
	if not _expect(not output.is_empty(), "Q's formed plate remains at the native workbed center"):
		return false
	output.erase("center")
	if (await _send({"action": "pickup_material", "center": press.work_center,
			"expected": output}, "Q carries the independently made plate")).is_empty():
		return false
	if not _expect(session.projection().workshop_completed_actors.has("Q")
			and session.projection().cargo.P.products == 1
			and session.projection().cargo.Q.products == 1
			and session.projection().part_kits.Q.gear == 1,
		"Q's own carried plate unlocks rebuilding without transferring P's plate or cog"):
		return false
	if not await _walk_points([Vector2(4.1, 4.95), Vector2(2.5, 3.3)]):
		return false
	opening.transmission_controls._size_selected(1)
	opening.transmission_controls._axis_selected(2)
	opening.transmission_controls.auto_height = false
	opening.transmission_controls.gear_height = 4
	opening._select_tool("gear")
	var target: Array = _anchor([0, 4, 12])
	var target_point := Vector3(target[0], target[1], target[2])
	var snap_views: Array = []
	var clear_view := false
	for yaw in [2.15, 2.4, 1.9, 2.7, 1.6, PI]:
		opening.orbit_yaw = yaw
		opening.orbit_pitch = 0.35
		opening._update_camera()
		await process_frame
		opening._update_camera()
		var screen: Vector2 = opening.camera.unproject_position(target_point)
		var snapped: Array = opening._transmission_center(screen)
		snap_views.append({"yaw": yaw, "screen": [screen.x, screen.y],
			"snapped": snapped.duplicate(), "picked": opening._screen_entity(screen)})
		if snapped == [0, 4, 12]:
			clear_view = true
			break
	facts["rebuild_snap_views"] = snap_views
	if not _expect(clear_view, "Q can point at the vacated output tile from a clear camera angle"):
		return false
	var rebuilt := await _callback("Q replaces the cog from Q's refunded kit",
		{"action": "place_gear", "center": [0, 4, 12], "axis": "z", "teeth": 4},
		[_anchor([0, 4, 12])], func(): _click([0, 4, 12]))
	if rebuilt.is_empty():
		return false
	var final: Dictionary = session.projection()
	var retry_before: int = replies[locked_request].size()
	var sequence_before: int = session.request_sequence
	var retry_queue: Dictionary = session.retry(locked_request)
	if not await _wait_for(func(): return replies[locked_request].size() == retry_before + 1,
		"The prior refusal returns its original decision on retry"):
		return false
	var retry_reply: Dictionary = replies[locked_request][-1]
	facts["preplate_retry"] = {"queued": retry_queue, "reply": retry_reply,
		"original": locked_reply}
	return _expect(rebuilt.entity != ids.output and final.motion[str(rebuilt.entity)].state == "rotating"
		and final.part_kits.Q.gear == 0 and final.part_kits.P.gear == 0
		and final.material_mass.accounted_mass == final.material_mass.initial_mass
		and retry_queue.get("queued") == true and retry_reply.get("duplicate") == true
		and retry_reply.get("accepted") == false
		and retry_reply.get("reason") == "first_plate_required"
		and retry_reply.get("order") == locked_reply.get("order")
		and session.request_sequence == sequence_before
		and _same(_material_view(session.projection()), _material_view(final))
		and _write("Q-rebuilt.bin", {"status": "pass", "new_output": str(rebuilt.entity),
			"order": final.order}),
		"Q's same refunded part rebuilds a running output under a new identity")

func _run_running_cog() -> void:
	if actor not in ["P", "Q"] or not directory.is_absolute_path() or not previous.is_absolute_path():
		push_error("The shared running cog needs both clients and the previous saved cohort")
		quit(1)
		return
	opening = load("res://opening/shared_opening.tscn").instantiate()
	root.add_child(opening)
	session = opening.session
	session.outcome.connect(func(reply: Dictionary):
		var request: String = str(reply.get("request", ""))
		outcomes[request] = reply.duplicate(true)
		if not replies.has(request):
			replies[request] = []
		replies[request].append(reply.duplicate(true)))
	if not await _wait_for(func(): return session.is_ready(),
		"Both ordinary clients join the current native arrival host"):
		return
	var passed := false
	if phase == "running-cog":
		passed = await _running_cog_p() if actor == "P" else await _running_cog_q()
	else:
		var saved: Dictionary = _read(previous.path_join("P-complete.bin"))
		var view: Dictionary = session.projection()
		passed = _expect(saved.get("status") == "pass" and view.transmission_parts.has(saved.new_output)
			and not view.transmission_parts.has(saved.ids.output)
			and view.motion[saved.ids.wheel].state == "rotating"
			and view.motion[saved.ids.source].state == "rotating"
			and view.motion[saved.new_output].state == "rotating"
			and view.part_kits.P.gear == 0 and view.part_kits.Q.gear == 0
			and view.cargo.P.products == 1 and view.cargo.Q.products == 1
			and view.workshop_completed_actors.has("P")
			and view.workshop_completed_actors.has("Q")
			and view.material_mass.accounted_mass == view.material_mass.initial_mass,
			"Fresh P and Q clients restore the exact rebuilt running line and separate kits")
	if passed and not written:
		_record("pass")

func _run_firstplate() -> void:
	if actor not in ["P", "Q"] or phase not in ["firstplate", "firstplate-resume"] \
			or not directory.is_absolute_path() or \
			(phase == "firstplate-resume" and not previous.is_absolute_path()):
		push_error("The first-plate consumer requires P or Q and an owned absolute directory")
		quit(1)
		return
	opening = load("res://opening/shared_opening.tscn").instantiate()
	root.add_child(opening)
	session = opening.session
	session.outcome.connect(func(reply: Dictionary):
		outcomes[str(reply.get("request", ""))] = reply.duplicate(true))
	if not await _wait_for(func(): return session.is_ready(),
		"The ordinary client joins its physical native server"):
		return
	var passed := false
	if phase == "firstplate":
		passed = await _initial_p() if actor == "P" else await _initial_q()
	else:
		passed = await _firstplate_resume_p() if actor == "P" else await _firstplate_resume_q()
	if passed and not written:
		_record("pass")
