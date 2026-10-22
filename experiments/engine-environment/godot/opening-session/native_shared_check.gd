extends "res://opening-session/native_shared_cog_check.gd"
## Headless ordinary callbacks over the existing Session and native World.
## The inherited reader retains typed observations before initial assertions.
const SharedOpening = preload("res://opening/shared_opening.gd")

func _init() -> void:
	super._init()
	deadline = Time.get_ticks_msec() + 45000
	facts.evidence = "shared_native_work_recovery"

func _initial() -> bool:
	if not await super._initial():
		return false
	facts["prepared_audio"] = {}
	for kind: String in ["collector", "belt", "processor", "wheel"]:
		var stream: AudioStreamWAV = SharedOpening.MechanicalAmbience.loops.get(kind)
		if not _expect(stream != null and stream.data.size() == 176400 and stream.mix_rate == 44100
			and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"Shared startup prepares the original cached audio before any material input"):
			return false
		facts.prepared_audio[kind] = {"bytes": stream.data.size(), "stream_id": stream.get_instance_id()}
	return true

func _until(condition: Callable, reason: String) -> bool:
	while Time.get_ticks_msec() < deadline and not condition.call():
		await process_frame
	return _expect(condition.call(), reason)

func _running_audio() -> bool:
	if not await _until(func(): return opening.mechanical_ambience != null and opening.mechanical_ambience.emitters.size() == 4,
		"The real running machines use their prepared audio"):
		return false
	facts["running_audio"] = {}
	for id: String in opening.state.entities:
		var kind: String = opening.state.entities[id].kind
		var emitter: AudioStreamPlayer3D = opening.mechanical_ambience.emitters.get(id)
		var cached: AudioStreamWAV = SharedOpening.MechanicalAmbience.loops[kind]
		if not _expect(emitter != null and emitter.stream == cached,
			"The real emitter reuses the original stream prepared before connection"):
			return false
		facts.running_audio[id] = {"kind": kind, "stream_id": cached.get_instance_id(),
			"reused_prepared_stream": true}
	return true

func _conserved() -> bool:
	var state: Dictionary = session.projection()
	var total := 0
	var products := 0
	for key: String in ["source", "collector", "belt", "input", "held", "output", "player"]:
		var amount: Variant = state.stock.get(key)
		if not _expect(typeof(amount) == TYPE_INT and amount >= 0, "Stock remains typed and nonnegative"):
			return false
		total += amount
	for owner: String in ["P", "Q"]:
		var cargo: Dictionary = state.cargo[owner]
		if not _expect(typeof(cargo.raw) == TYPE_INT and cargo.raw >= 0 and typeof(cargo.products) == TYPE_INT
			and cargo.products >= 0 and _same(cargo.products, state.inventories[owner]), "Individual product aliases agree"):
			return false
		total += cargo.raw
		products += cargo.products
		for lot: Dictionary in cargo.work_lots:
			if not _expect(typeof(lot.id) == TYPE_INT and lot.id > 0 and _same(lot.recipe_input, 1)
				and _same(lot.cycle_ticks, 2) and typeof(lot.remaining) == TYPE_INT and lot.remaining in [0, 1, 2], "Whole work keeps its typed recipe and progress"):
				return false
			total += lot.recipe_input
	return _expect(_same(state.initial_feed, 16) and _same(state.recipe_input, 1)
		and total == 16 and products == state.stock.player, "Every original unit has one weighted owner")

func _target(id: String) -> Array:
	var cell: Array = opening.state.entities[id].cell
	return _anchor([cell[0] * 4, 0, cell[1] * 4])

func _call(label: String, wire: Dictionary, targets: Array, callback: Callable) -> Dictionary:
	if written:
		return {}
	var outcome: Dictionary = await _callback(label, wire, targets, callback)
	if outcome.is_empty() or not _conserved():
		return {}
	return outcome

func _place(kind: String, cell: Vector2i) -> String:
	opening.tool_buttons[kind].pressed.emit()
	var targets := [_anchor([cell.x * 4, 0, cell.y * 4])]
	# This fixture builds Collector, Wheel, Belt, then Press. Placement also
	# admits the original neighboring material port in the same transaction.
	if kind in ["belt", "processor"]:
		targets.append(_anchor([0 if kind == "belt" else 4, 0, 4]))
	var outcome := await _call("Place " + kind, {"action": "place", "kind": kind, "cell": [cell.x, cell.y], "axis": "x"},
		targets, func(): opening._world_click(cell))
	return outcome.get("entity", "")

func _link(tool: String, from: String, to: String) -> bool:
	opening._select_tool(tool)
	var cell: Array = opening.state.entities[from].cell
	opening._world_click(Vector2i(cell[0], cell[1]), from)
	cell = opening.state.entities[to].cell
	return not (await _call("Connect " + tool, {"action": "connect" if tool == "flow" else "connect_drive", "from": from, "to": to},
		[_target(from), _target(to)], func(): opening._world_click(Vector2i(cell[0], cell[1]), to))).is_empty()

func _select(id: String) -> void:
	opening._select_tool("inspect")
	var cell: Array = opening.state.entities[id].cell
	opening._world_click(Vector2i(cell[0], cell[1]), id)

func _menu(id: String, action: String, work_id: int = -1) -> bool:
	_select(id)
	var control = opening.recovery_actions
	if not _expect(control != null and control.visible and not control.action_button.disabled, "The ordinary material menu is usable"):
		return false
	control._open_menu()
	var popup: PopupMenu = control.action_button.get_popup()
	var expected := {"action": action, "entity": id}
	if action == "insert_work":
		expected["work_id"] = work_id
	for index: int in range(popup.item_count):
		if _same(popup.get_item_metadata(index).wire, expected):
			return not (await _call("Material menu " + action, expected, [_target(id)],
				control._choose.bind(popup.get_item_id(index)))).is_empty()
	return _expect(false, "The menu must offer the literal requested material transfer")

func _power(enabled: bool, wheel: String) -> bool:
	# Retained scripted-profile fixture command; the opening exposes no switch.
	return not (await _call("Scripted fixture drive", {"action": "set_power", "active": enabled}, [_target(wheel)],
		func(): opening.issue({"action": "set_power", "active": enabled}))).is_empty() and _expect(opening.state.power_enabled == enabled, "The historical fixture drive reaches its requested state")

func _collect(press: String) -> bool:
	_select(press)
	var count: int = opening.state.inventories[actor]
	return not (await _call("Collect product", {"action": "retrieve", "entity": press, "amount": 1}, [_target(press)],
		func(): opening.retrieve_button.pressed.emit())).is_empty() and _expect(opening.state.inventories[actor] == count + 1, "One product reaches only its authenticated actor")

func _marker(name: String, extra: Dictionary = {}) -> bool:
	var value := {"status": "pass", "order": opening.state.order}
	value.merge(extra)
	return _expect(_write(name, value), "Publish a validated peer barrier")

func _peer(name: String) -> Dictionary:
	var record := await _barrier(name)
	if record.is_empty() or not await _order(record.order):
		return {}
	return record

func _walk_to_line() -> bool:
	# Q stays outside the wheel's 1.45-wide collision box and capsule radius.
	# Its approach waypoint changes no reach or collision tolerance. All legs
	# use the ordinary presenter's held-key path and the server's real motor.
	var legs := [[KEY_D, KEY_S]] if actor == "P" else [[KEY_D, KEY_W], [KEY_D, KEY_S]]
	for index: int in range(legs.size()):
		for code: Key in legs[index]:
			var edge := InputEventKey.new()
			edge.keycode = code
			edge.pressed = true
			opening.character_presenter._input(edge)
		var moved := await _until(func():
			return opening.state.actors[actor].position[2] <= 3.0 if actor == "Q" and index == 0 else opening.state.actors[actor].position[0] >= 0.7,
			"The actual server motor reaches the declared approach lane")
		for code: Key in legs[index]:
			var edge := InputEventKey.new()
			edge.keycode = code
			edge.pressed = false
			opening.character_presenter._input(edge)
		opening.character_presenter.release()
		if not moved:
			return false
		for _frame in range(4):
			await physics_frame
	facts["walked_actor"] = opening.state.actors[actor].duplicate(true)
	return true

func _foreign_work(press: String, lot: Dictionary) -> bool:
	var before: Dictionary = _material_view(session.projection())
	var wire := {"action": "insert_work", "entity": press, "work_id": lot.id}
	# Deliberate invalid request through the ordinary view, not an offered menu.
	opening.issue(wire)
	var queued: Dictionary = opening.last_submission.duplicate(true)
	if not _expect(queued.get("queued") == true, "The adversarial P request reaches Session"):
		return false
	var request: String = queued.request
	if not await _until(func(): return replies.has(request) and opening.pending_actions.is_empty(), "The foreign-custody request settles"):
		return false
	var reply: Dictionary = replies[request][-1]
	var after := _material_view(session.projection())
	facts["foreign_work"] = {"before": before.duplicate(true), "wire": wire, "queued": queued, "outcome": reply, "after": after.duplicate(true)}
	if not _expect(reply.get("accepted") == false and reply.get("reason") == "unavailable_cargo"
		and reply.get("duplicate") == false and _same(reply.get("order"), before.order + 1)
		and _same(after.order, reply.order), "P cannot insert the whole lot owned by Q"):
		return false
	before.erase("order")
	after.erase("order")
	return _expect(_same(before, after), "The refused insertion preserves all material and parts") and _conserved()

func _partial_changed(confirmed: Dictionary, wheel: String, watch: Dictionary) -> void:
	if watch.triggered or int(confirmed.revision) <= watch.revision:
		return
	var before: Dictionary = watch.previous
	watch.previous = confirmed.duplicate(true)
	watch.revision = int(confirmed.revision)
	facts.partial_observations.append({"revision": confirmed.revision, "order": confirmed.order,
		"remaining": confirmed.remaining, "stock": confirmed.stock.duplicate(true),
		"inventories": confirmed.inventories.duplicate(true), "serial": session.last_serial,
		"observed_msec": Time.get_ticks_msec()})
	# React at the actual material transition, not a cached phase observed after
	# a filesystem barrier and another process/physics-frame round trip.
	if not opening.pending_actions.is_empty() or before.stock.held != 1 or not before.power_enabled:
		return
	if confirmed.stock.held != 1 or confirmed.remaining != 1 or confirmed.stock.output != 0 \
		or not confirmed.power_enabled or not _same(confirmed.inventories, {"P": 0, "Q": 1}):
		return
	var progressed: bool = (before.order == confirmed.order and before.remaining == 2
		and before.stock.output == 0 and _same(before.inventories, {"P": 0, "Q": 1}))
	# The same lot can already have progressed before Q's collection is admitted.
	# That fresh collection exposes its empty outlet without advancing the lot.
	var collected: bool = (confirmed.order == before.order + 1 and confirmed.revision == before.revision + 1
		and before.remaining == 1 and before.stock.output == 1 and _same(before.inventories, {"P": 0, "Q": 0}))
	if not progressed and not collected:
		return
	# Consume this one opportunity before _call yields. Repeated pose snapshots
	# cannot queue another Stop or substitute a later natural workpiece.
	watch.triggered = true
	facts["partial_stop"] = {"before": before, "transition": confirmed.duplicate(true),
		"edge": "progress" if progressed else "collection", "serial": session.last_serial,
		"trigger_msec": Time.get_ticks_msec()}
	var outcome := await _call("Pause partial work", {"action": "set_power", "active": false}, [_target(wheel)],
		func(): opening.issue({"action": "set_power", "active": false}))
	watch.settled = true
	if outcome.is_empty():
		return
	facts.partial_stop["settled_msec"] = Time.get_ticks_msec()
	watch.passed = _expect(_same(outcome.snapshot.revision, confirmed.revision + 1)
		and _same(outcome.snapshot.remaining, 1) and _same(outcome.snapshot.stock.held, 1)
		and _same(outcome.snapshot.stock.output, 0) and not outcome.snapshot.power_enabled
		and _same(opening.state.remaining, 1) and not opening.state.power_enabled,
		"The ordinary Stop preserves the same freshly observed positive partial phase")

func _produce_p() -> bool:
	opening.transmission_controls._axes.id_pressed.emit(0)
	if not await _walk_to_line():
		return false
	var collector := await _place("collector", Vector2i(0, 1))
	var wheel := await _place("wheel", Vector2i(-1, 1))
	var belt := await _place("belt", Vector2i(1, 1))
	var press := await _place("processor", Vector2i(2, 1))
	if written or collector.is_empty() or wheel.is_empty() or belt.is_empty() or press.is_empty():
		return false
	if not _expect(_same(opening.state.links, [[collector, belt], [belt, press]]), "Placement already attached the two literal material links"):
		return false
	for link: Array in [[wheel, collector], [collector, belt], [belt, press]]:
		if not await _link("drive", link[0], link[1]):
			return false
	var ids := {"press": press, "wheel": wheel}
	if not _marker("line-built.bin", {"ids": ids}) or (await _peer("Q-positioned.bin")).is_empty():
		return false
	var watch := {"previous": session.projection(), "revision": int(opening.state.revision),
		"triggered": false, "settled": false, "passed": false}
	facts["partial_observations"] = []
	var observer: Callable = _partial_changed.bind(wheel, watch)
	session.changed.connect(observer)
	var started := await _power(true, wheel)
	if started:
		started = await _running_audio()
	var stopped := started and await _until(func(): return watch.settled,
		"A fresh confirmed partial-work transition admits the ordinary Stop")
	session.changed.disconnect(observer)
	if not stopped or not watch.passed:
		return false
	# Q's marker still certifies its validated callback and custody. It no longer
	# delays observing the short-lived processing phase on the authoritative clock.
	if (await _peer("Q-product.bin")).is_empty():
		return false
	if not _marker("partial-paused.bin", {"ids": ids}):
		return false
	var recovered := await _peer("Q-work.bin")
	if recovered.is_empty() or not _partial_lot(recovered.lot) or not await _foreign_work(press, recovered.lot):
		return false
	return _final(0) and _marker("P-stopped.bin", {"ids": ids, "lot": recovered.lot})

func _partial_lot(lot: Variant) -> bool:
	return _expect(lot is Dictionary and typeof(lot.get("id")) == TYPE_INT and lot.id > 0
		and _same(lot.get("recipe_input"), 1) and _same(lot.get("cycle_ticks"), 2) and _same(lot.get("remaining"), 1),
		"The original lot is positively progressed, not blocked ready work")

func _produce_q() -> bool:
	var line := await _peer("line-built.bin")
	if line.is_empty() or not await _walk_to_line() or not _marker("Q-positioned.bin"):
		return false
	if not await _until(func(): return opening.state.stock.output == 1, "The real line produces Q's first plate"):
		return false
	if not await _collect(line.ids.press) or not _marker("Q-product.bin"):
		return false
	if (await _peer("partial-paused.bin")).is_empty() or not await _menu(line.ids.press, "recover"):
		return false
	var lots: Array = opening.state.cargo.Q.work_lots
	if not _expect(lots.size() == 1 and opening.state.inventories.Q == 1 and opening.state.inventories.P == 0, "Q separately owns its finished plate and recovered work"):
		return false
	if not _partial_lot(lots[0]) or not _marker("Q-work.bin", {"lot": lots[0]}):
		return false
	return not (await _peer("P-stopped.bin")).is_empty() and _final(0)

func _resume_q(_ids: Dictionary) -> bool:
	var prepared := _read(previous.path_join("P-stopped.bin"))
	if not _expect(prepared.get("status") == "pass" and _same(opening.state.cargo.Q.work_lots, [prepared.lot])
		and opening.state.inventories.Q == 1 and not opening.state.power_enabled, "Fresh custody includes the original paused lot and product"):
		return false
	if not await _menu(prepared.ids.press, "insert_work", prepared.lot.id):
		return false
	if not _expect(opening.state.stock.held == 1 and opening.state.remaining == 1 and opening.state.cargo.Q.work_lots.is_empty(), "Reinsertion keeps the original remaining tick"):
		return false
	if not _marker("Q-inserted.bin", {"ids": prepared.ids}):
		return false
	return not (await _peer("P-four-products.bin")).is_empty() and _final(3)

func _resume_p() -> bool:
	var inserted := await _peer("Q-inserted.bin")
	if inserted.is_empty() or not await _power(true, inserted.ids.wheel):
		return false
	for _plate in range(3):
		if not await _until(func(): return opening.state.stock.output == 1, "The reopened line finishes an actual product") or not await _collect(inserted.ids.press):
			return false
	if not await _power(false, inserted.ids.wheel):
		return false
	return _final(3) and _marker("P-four-products.bin")

func _final(p_products: int) -> bool:
	return _conserved() and _expect(_same(opening.state.inventories, {"P": p_products, "Q": 1})
		and not opening.state.power_enabled, "Final per-actor product custody and paused drive are exact")
