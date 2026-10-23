extends "res://opening-session/native_shared_cog_check.gd"
## A live reconnect consumer of the original paused shared-work checkpoint.
## The ordinary server retains the only World, actor bodies and material clock.
var prepared: Dictionary = {}
var baseline: Dictionary = {}
var shipment_capture_prefix := ""

func _chapter_ui_material(snapshot: Dictionary) -> Dictionary:
	return {"order": snapshot.get("order"), "cargo": snapshot.get("cargo"),
		"hand_sources": snapshot.get("hand_sources"),
		"placed_components": snapshot.get("placed_components"),
		"dropped_material": snapshot.get("dropped_material"),
		"hand_crank": snapshot.get("hand_crank")}

func _chapter_ui_call(label: String, expected: Dictionary, callback: Callable) -> Dictionary:
	var before: Dictionary = session.projection()
	var sequence: int = session.request_sequence
	callback.call()
	var queued: Dictionary = opening.last_submission.duplicate(true)
	var request: String = str(queued.get("request", ""))
	var row := {"label": label, "expected": expected.duplicate(true), "before": _chapter_ui_material(before),
		"queued": queued, "immediate": _chapter_ui_material(session.projection())}
	facts.steps.append(row)
	if not _expect(queued.get("queued") == true and queued.get("accepted") == false
			and session.request_sequence == sequence + 1 and opening.pending_actions.has(request)
			and _same(row.before, row.immediate),
		label + " queues one ordinary view command without speculative material"):
		return {}
	if not await _until(func(): return replies.has(request) and not opening.pending_actions.has(request),
		label + " settles its server outcome"):
		return {}
	var wire: Dictionary = session._sent.get(request, {}).duplicate(true)
	for key in ["context", "client", "request"]:
		wire.erase(key)
	var result: Dictionary = replies[request][-1].duplicate(true)
	row["wire"] = wire
	row["outcome"] = result
	row["after"] = _chapter_ui_material(session.projection())
	if not _expect(_same(wire, expected) and result.get("accepted") == true
			and result.get("duplicate") == false and result.get("order") == before.order + 1
			and opening.state.order >= result.order and session.world == null and opening.actor_world == null,
		label + " preserves its literal command and one native decision without client authority"):
		return {}
	return result

func _chapter_ui_walk(target: Vector2) -> bool:
	var start: Dictionary = session.projection().actors.P.duplicate(true)
	var leg_deadline := mini(deadline, Time.get_ticks_msec() + 16000)
	while Time.get_ticks_msec() < leg_deadline:
		var pose: Array = session.projection().actors.P.position
		var gap := target - Vector2(float(pose[0]), float(pose[2]))
		if gap.length() < 0.15:
			opening._release_character_input()
			facts["actor_motion"] = {"start": start, "end": session.projection().actors.P.duplicate(true),
				"source": "ordinary_shared_control_callback"}
			return _expect(session.projection().actors.P.native_epoch > start.native_epoch
				and session.projection().actors.P.ready, "The actual server actor walks into the harvest aisle")
		opening._send_character_input(gap.normalized(), false)
		await process_frame
	opening._release_character_input()
	return _expect(false, "The bounded ordinary control cannot reach the harvest aisle")

func _chapter_ui_initial() -> bool:
	var state: Dictionary = session.projection()
	return _expect(state.get("options", {}).get("native") == true and state.order == 0
		and state.get("fabrication_hub", {}).get("id") == "pod-fabrication-hub"
		and state.get("placed_components", {}).is_empty()
		and state.get("hand_sources", {}).get("tree-east-south", {}).get("remaining") == 8
		and state.cargo.P.timber == 0 and session.world == null and opening.actor_world == null,
		"Both ordinary shared scenes begin with one native pod and no fabricated components")

func _chapter_ui_frame(snapshot: Dictionary, installed: bool) -> bool:
	var parts: Dictionary = snapshot.get("placed_components", {})
	return _expect(snapshot.order == (5 if installed else 6)
		and snapshot.hand_sources["tree-east-south"].remaining == 5
		and parts.size() == (1 if installed else 0)
		and (not installed or parts.get("native-part-1", {}).get("component") == "wooden_frame")
		and snapshot.cargo.P.components.get("wooden_frame", 0) == (0 if installed else 1)
		and snapshot.cargo.P.timber == 0 and snapshot.cargo.Q.timber == 0,
		"Both peers see the same finite tree debit and exact frame custody")

func _chapter_ui_p() -> bool:
	if (await _barrier("Q-ready.bin")).is_empty() or not _chapter_ui_initial():
		return false
	if not await _chapter_ui_walk(Vector2(3.3, 4.95)):
		return false
	opening.distance = 0.0
	for index in range(3):
		var pose: Array = session.projection().actors.P.position
		opening.camera.global_position = Vector3(float(pose[0]), float(pose[1]) + 0.7, float(pose[2]))
		opening.camera.look_at(Vector3(6.6, 0.2, 3.3))
		if not _expect(opening._screen_hand_source(opening._pointed_screen_position()) == "tree-east-south",
			"The ordinary E ray selects the physical finite tree trunk at each cut"):
			return false
		if (await _chapter_ui_call("Multitool harvest %d" % index,
			{"action": "harvest_source", "target": "tree-east-south"},
			opening._interact_pointed)).is_empty():
			return false
	var panel = opening.arrival_assembly_controls
	if not _expect(panel != null and panel.field_craft_button.visible
			and not panel.field_craft_button.disabled and panel.selected_name() == "wooden_frame"
			and session.projection().cargo.P.timber == 3,
		"Three cuts enable the ordinary wooden-frame multitool recipe"):
		return false
	if (await _chapter_ui_call("Field craft a wooden frame",
		{"action": "field_craft", "component": "wooden_frame"}, panel.field_craft_button.pressed.emit)).is_empty():
		return false
	opening._select_tool("component")
	var tile := Vector2i(3, 4)
	if not _expect(opening._component_place_center(tile, "") == [12, 0, 16],
		"The ordinary component cursor uses the shared quarter-grid center"):
		return false
	if (await _chapter_ui_call("Place the shaped press frame",
		{"action": "place_component", "component": "wooden_frame", "center": [12, 0, 16]},
		opening._world_click.bind(tile))).is_empty() or not _chapter_ui_frame(session.projection(), true):
		return false
	if not _expect(_write("P-complete.bin", {"status": "pass", "order": 5,
			"component": "native-part-1"}), "Publish the confirmed ordinary P component"):
		return false
	if (await _barrier("Q-result.bin")).is_empty():
		return false
	return true

func _chapter_ui_q() -> bool:
	if not _chapter_ui_initial() or not _expect(_write("Q-ready.bin", {"status": "pass"}),
		"Q joins the same native server before P harvests"):
		return false
	if (await _barrier("P-complete.bin")).is_empty() or not await _until(func(): return session.projection().order >= 5,
		"Q receives P's placed frame"):
		return false
	return _chapter_ui_frame(session.projection(), true)

func _chapter_ui_resume_p() -> bool:
	if (await _barrier("Q-ready.bin")).is_empty() or not _chapter_ui_frame(session.projection(), true):
		return false
	opening._select_tool("deconstruct")
	if (await _chapter_ui_call("Reclaim the restored frame",
		{"action": "reclaim_component", "entity": "native-part-1"},
		opening._world_click.bind(Vector2i(3, 4), "native-part-1"))).is_empty() \
			or not _chapter_ui_frame(session.projection(), false):
		return false
	if not _expect(_write("P-complete.bin", {"status": "pass", "order": 6}),
		"Publish the confirmed resumed component custody"):
		return false
	return not (await _barrier("Q-result.bin")).is_empty()

func _chapter_ui_resume_q() -> bool:
	if not _chapter_ui_frame(session.projection(), true) or not _expect(_write("Q-ready.bin", {"status": "pass"}),
		"Q rejoins the saved native frame before P acts"):
		return false
	if (await _barrier("P-complete.bin")).is_empty() or not await _until(func(): return session.projection().order >= 6,
		"Q receives P's resumed frame recovery"):
		return false
	return _chapter_ui_frame(session.projection(), false)

func _collector_ui_drop(snapshot: Dictionary) -> bool:
	for value in snapshot.get("dropped_material", []):
		if value is Dictionary and value.get("center") == [0, 4, 3] and value.get("raw") == 1:
			return true
	return false

func _collector_ui_issue(label: String, action: Dictionary) -> Dictionary:
	return await _chapter_ui_call(label, action, opening.issue.bind(action))

func _collector_ui_select(shaft: String, receiver_clear: bool = true) -> bool:
	opening._select_tool("inspect")
	opening._world_click(Vector2i(0, 1), shaft)
	var panel = opening.arrival_assembly_controls
	return _expect(opening.selected == shaft and panel != null and panel.collector_cut_button.visible
		and panel.collector_cut_button.disabled == not receiver_clear
		and ("Collector ready" in panel.collector_status.text if receiver_clear else
			"receiver holds" in panel.collector_status.text),
		"The ordinary selected shaft reflects its confirmed collector receiver and crank")

func _collector_ui_p() -> bool:
	if (await _barrier("Q-ready.bin")).is_empty() or not _chapter_ui_initial():
		return false
	if not await _chapter_ui_walk(Vector2(3.3, 4.95)):
		return false
	opening.distance = 0.0
	for index in range(7):
		var pose: Array = session.projection().actors.P.position
		opening.camera.global_position = Vector3(float(pose[0]), float(pose[1]) + 0.7, float(pose[2]))
		opening.camera.look_at(Vector3(6.6, 0.2, 3.3))
		if not _expect(opening._screen_hand_source(opening._pointed_screen_position()) == "tree-east-south",
			"The ordinary E ray still sees the finite tree trunk"):
			return false
		if (await _chapter_ui_call("Multitool timber cut %d" % index,
			{"action": "harvest_source", "target": "tree-east-south"},
			opening._interact_pointed)).is_empty():
			return false
	for kind in ["wooden_frame", "tool_mount", "receiver_tray", "wooden_shaft"]:
		if (await _collector_ui_issue("Shape collector " + kind,
			{"action": "field_craft", "component": kind})).is_empty():
			return false
	if not await _chapter_ui_walk(Vector2(3.3, 1.65)) or not await _chapter_ui_walk(Vector2(0.0, 1.65)):
		return false
	if (await _collector_ui_issue("Harvest one finite edge blank",
		{"action": "harvest_source", "target": "opening-softmetal"})).is_empty():
		return false
	if not await _chapter_ui_walk(Vector2(1.65, 4.95)):
		return false
	if (await _collector_ui_issue("Craft the separate cutting edge",
		{"action": "craft_component", "entity": "pod-fabrication-hub", "component": "cutting_edge"})).is_empty():
		return false
	if (await _collector_ui_issue("Take the original pod crank",
		{"action": "take_hand_crank", "entity": "pod-hand-crank"})).is_empty():
		return false
	if not await _chapter_ui_walk(Vector2(0.7, 3.3)):
		return false
	if (await _collector_ui_issue("Build the collector deck",
		{"action": "place_foundation", "cell": [0, 1], "level": 4})).is_empty():
		return false
	var shaft := ""
	for part in [
		{"component": "wooden_frame", "center": [0, 4, 4]},
		{"component": "tool_mount", "center": [-1, 4, 4]},
		{"component": "cutting_edge", "center": [-2, 4, 4]},
		{"component": "receiver_tray", "center": [0, 4, 3]},
		{"component": "wooden_shaft", "center": [1, 4, 4]}]:
		var placed: Dictionary = await _collector_ui_issue("Fit collector " + part.component,
			{"action": "place_component", "component": part.component, "center": part.center})
		if placed.is_empty():
			return false
		if part.component == "wooden_shaft":
			shaft = str(placed.get("entity", ""))
	if not _expect(not shaft.is_empty() and session.projection().collector_assemblies.any(
		func(item: Dictionary) -> bool: return item.get("status") == "ready" and item.get("parts", {}).get("shaft") == shaft),
		"Five issued pieces form one ready native collector") or not _collector_ui_select(shaft):
		return false
	var cut: Dictionary = await _chapter_ui_call("Press the ordinary collector cut button",
		{"action": "turn_hand_crank", "entity": shaft},
		opening.arrival_assembly_controls.collector_cut_button.pressed.emit)
	if cut.is_empty() or not _expect(cut.get("receiver_raw") == 1 and _collector_ui_drop(session.projection())
		and session.projection().hand_sources["opening-softmetal"].remaining == 14
		and opening.arrival_assembly_controls.collector_cut_button.disabled,
		"One accepted panel cut debits finite ore and fills the receiver without an automatic second cut"):
		return false
	if not _expect(_write("P-complete.bin", {"status": "pass", "order": session.projection().order,
		"shaft": shaft}), "Retain the confirmed collector shaft and cut order"):
		return false
	return not (await _barrier("Q-result.bin")).is_empty()

func _collector_ui_q() -> bool:
	if not _chapter_ui_initial() or not _expect(_write("Q-ready.bin", {"status": "pass"}),
		"Q joins before the ordinary collector assembly"):
		return false
	var complete: Dictionary = await _barrier("P-complete.bin")
	if complete.is_empty() or not await _until(func(): return session.projection().order >= complete.order,
		"Q receives P's confirmed collector cut"):
		return false
	return _expect(_collector_ui_drop(session.projection()) and session.projection().cargo.P.raw == 0
		and session.projection().hand_sources["tree-east-south"].remaining == 1
		and session.projection().hand_sources["opening-softmetal"].remaining == 14,
		"Q sees the same seven timber debits, one ore debit and exact receiver custody")

func _collector_ui_resume_p() -> bool:
	if (await _barrier("Q-ready.bin")).is_empty():
		return false
	var restored: Dictionary = session.projection()
	var shaft := ""
	for item: Dictionary in restored.get("collector_assemblies", []):
		if item.get("status") == "ready":
			shaft = str(item.get("parts", {}).get("shaft", ""))
	if not _expect(restored.order == 21 and not shaft.is_empty() and _collector_ui_drop(restored)
		and restored.hand_crank.holder == "P" and restored.hand_sources["opening-softmetal"].remaining == 14,
		"Fresh host restores the issued collector, full receiver and original crank holder") \
			or not _collector_ui_select(shaft, false):
		return false
	if (await _collector_ui_issue("Pick up the saved receiver blank",
		{"action": "pickup_material", "center": [0, 4, 3],
			"expected": {"raw": 1, "products": 0, "work_lots": []}})).is_empty():
		return false
	if not _expect(session.projection().cargo.P.raw == 1 and not _collector_ui_drop(session.projection()),
		"Original receiver blank becomes one carried blank after native pickup") \
			or not _collector_ui_select(shaft):
		return false
	var cut: Dictionary = await _chapter_ui_call("Cut again after restored receiver pickup",
		{"action": "turn_hand_crank", "entity": shaft},
		opening.arrival_assembly_controls.collector_cut_button.pressed.emit)
	if cut.is_empty() or not _expect(cut.get("source_remaining") == 13
		and _collector_ui_drop(session.projection()) and session.projection().cargo.P.raw == 1
		and opening.arrival_assembly_controls.collector_cut_button.disabled,
		"Restored collector cuts exactly one more finite blank after its receiver is cleared"):
		return false
	if not _expect(_write("P-complete.bin", {"status": "pass", "order": 23, "shaft": shaft}),
		"Retain restored collector work for Q"):
		return false
	return not (await _barrier("Q-result.bin")).is_empty()

func _collector_ui_resume_q() -> bool:
	var restored: Dictionary = session.projection()
	if not _expect(restored.order == 21 and _collector_ui_drop(restored)
		and restored.hand_sources["opening-softmetal"].remaining == 14,
		"Q joins the same Store-restored native receiver") \
			or not _expect(_write("Q-ready.bin", {"status": "pass"}),
			"Q announces its restored collector view"):
		return false
	if (await _barrier("P-complete.bin")).is_empty() or not await _until(
		func(): return session.projection().order >= 23,
		"Q receives both restored receiver pickup and second cut"):
		return false
	return _expect(_collector_ui_drop(session.projection()) and session.projection().cargo.P.raw == 1
		and session.projection().hand_sources["opening-softmetal"].remaining == 13,
		"Q sees one carried blank, one receiver blank and exactly thirteen uncut ore units")

func _run_collector_ui() -> void:
	if actor not in ["P", "Q"] or phase not in ["collector-ui", "collector-ui-resume"] \
			or not directory.is_absolute_path():
		push_error("The collector UI consumer needs P or Q and an owned directory")
		quit(1)
		return
	deadline = Time.get_ticks_msec() + 90000
	facts.evidence = "ordinary_shared_native_collector_cut_callbacks"
	opening = load("res://opening/shared_opening.tscn").instantiate()
	root.add_child(opening)
	session = opening.session
	session.outcome.connect(func(outcome: Dictionary):
		var request: String = outcome.get("request", "")
		if not replies.has(request):
			replies[request] = []
		replies[request].append(outcome.duplicate(true)))
	if not await _until(func(): return session.is_ready(), "The ordinary collector scene joins native Session"):
		return
	var passed := false
	if phase == "collector-ui":
		passed = await _collector_ui_p() if actor == "P" else await _collector_ui_q()
	else:
		passed = await _collector_ui_resume_p() if actor == "P" else await _collector_ui_resume_q()
	if passed and not written:
		_record("pass")

func _plate_ui_drop(snapshot: Dictionary, center: Array) -> Dictionary:
	for item: Variant in snapshot.get("dropped_material", []):
		if item is Dictionary and item.get("center", []) == center:
			return item
	return {}

func _plate_ui_ready_press(snapshot: Dictionary) -> Dictionary:
	for item: Variant in snapshot.get("press_assemblies", []):
		if item is Dictionary and item.get("status") == "ready" and item.get("center") == [12, 0, 16]:
			return item
	return {}

func _plate_ui_p() -> bool:
	if (await _barrier("Q-ready.bin")).is_empty():
		return false
	var restored: Dictionary = session.projection()
	var collector_shaft := ""
	for item: Dictionary in restored.get("collector_assemblies", []):
		if item.get("status") == "ready" and item.get("center") == [0, 4, 4]:
			collector_shaft = str(item.get("parts", {}).get("shaft", ""))
	if not _expect(restored.order == 21 and not collector_shaft.is_empty()
		and restored.hand_crank.holder == "P" and _collector_ui_drop(restored)
		and restored.hand_sources["opening-softmetal"].remaining == 14,
		"Fresh host restores the actual first collector cut before press work"):
		return false
	for index in range(5):
		if (await _collector_ui_issue("Pick up collector blank %d" % index,
			{"action": "pickup_material", "center": [0, 4, 3],
				"expected": {"raw": 1, "products": 0, "work_lots": []}})).is_empty():
			return false
		if index == 4:
			break
		if not _collector_ui_select(collector_shaft):
			return false
		var cut: Dictionary = await _chapter_ui_call("Turn the fitted collector shaft %d" % index,
			{"action": "turn_hand_crank", "entity": collector_shaft},
			opening.arrival_assembly_controls.collector_cut_button.pressed.emit)
		if cut.is_empty() or not _expect(cut.get("receiver_raw") == 1 and _collector_ui_drop(session.projection()),
			"Every panel cut fills only the cleared collector receiver"):
			return false
	if not _expect(session.projection().cargo.P.raw == 5 and not _collector_ui_drop(session.projection())
		and session.projection().hand_sources["opening-softmetal"].remaining == 10,
		"Five real collector cuts supply the four metal fittings and one press input"):
		return false
	if not await _chapter_ui_walk(Vector2(0.0, 9.9)):
		return false
	opening.distance = 0.0
	for index in range(8):
		var pose: Array = session.projection().actors.P.position
		opening.camera.global_position = Vector3(float(pose[0]), float(pose[1]) + 0.7, float(pose[2]))
		opening.camera.look_at(Vector3(0.0, 0.2, 11.55))
		if not _expect(opening._screen_hand_source(opening._pointed_screen_position()) == "tree-north",
			"The ordinary E ray identifies the second finite tree"):
			return false
		if (await _chapter_ui_call("Harvest second-tree timber %d" % index,
			{"action": "harvest_source", "target": "tree-north"}, opening._interact_pointed)).is_empty():
			return false
	if not _expect(session.projection().cargo.P.timber == 8
		and session.projection().hand_sources["tree-north"].remaining == 0,
		"Eight actual cuts supply the separate press wood bill"):
		return false
	for kind in ["wooden_frame", "sliding_guide", "tool_mount", "wooden_shaft", "wooden_cog"]:
		if (await _collector_ui_issue("Shape press " + kind,
			{"action": "field_craft", "component": kind})).is_empty():
			return false
	if not await _chapter_ui_walk(Vector2(0.0, 4.95)) \
			or not await _chapter_ui_walk(Vector2(1.65, 4.95)):
		return false
	for kind in ["anvil", "ram_face"]:
		if (await _collector_ui_issue("Fabricate press " + kind,
			{"action": "craft_component", "entity": "pod-fabrication-hub", "component": kind})).is_empty():
			return false
	if not _expect(session.projection().cargo.P.timber == 0 and session.projection().cargo.P.raw == 1,
		"Four collector-cut blanks and eight timber became seven carried press components"):
		return false
	if not await _chapter_ui_walk(Vector2(3.3, 4.95)):
		return false
	var frame := ""
	for part in [
		{"component": "wooden_frame", "center": [12, 0, 16]},
		{"component": "anvil", "center": [12, 1, 16]},
		{"component": "ram_face", "center": [12, 2, 16]},
		{"component": "sliding_guide", "center": [12, 3, 16]},
		{"component": "tool_mount", "center": [12, 4, 16]},
		{"component": "wooden_shaft", "center": [13, 4, 16]},
		{"component": "wooden_cog", "center": [14, 4, 16]}]:
		var placed: Dictionary = await _collector_ui_issue("Fit press " + part.component,
			{"action": "place_component", "component": part.component, "center": part.center})
		if placed.is_empty():
			return false
		if part.component == "wooden_frame":
			frame = str(placed.get("entity", ""))
	var press: Dictionary = _plate_ui_ready_press(session.projection())
	if not _expect(not frame.is_empty() and press.get("frame") == frame
		and press.get("open_feeds", []).size() > 0,
		"Seven separately issued parts create one ready press beside the collector"):
		return false
	opening._select_tool("inspect")
	opening._world_click(Vector2i(3, 4), frame)
	var panel = opening.arrival_assembly_controls
	if not _expect(opening.selected == frame and panel != null and panel.press_section.visible
		and not panel.feed_button.disabled and "Press ready" in panel.press_status.text,
		"Selecting the press frame opens its ordinary hand-feed controls"):
		return false
	var route: Dictionary = press.open_feeds[0]
	if (await _chapter_ui_call("Press the ordinary Feed blank button",
		{"action": "feed_press", "entity": frame, "entry": route.entry},
		panel.feed_button.pressed.emit)).is_empty():
		return false
	if not _expect(_write("P-fed.bin", {"status": "pass", "order": session.projection().order,
		"work_center": press.work_center, "exit": route.exit}),
		"Retain the native feed before turning") or (await _barrier("Q-fed.bin")).is_empty():
		return false
	var turn_wire := {"action": "turn_press_crank", "entity": frame,
		"drive": press.parts.shaft, "exit": route.exit}
	for turn in range(3):
		if not _expect(not panel.turn_button.disabled, "The carried crank can advance the retained press work"):
			return false
		if (await _chapter_ui_call("Press the ordinary Turn crank button %d" % turn,
			turn_wire, panel.turn_button.pressed.emit)).is_empty():
			return false
		if turn == 0:
			if not _expect(_write("P-work.bin", {"status": "pass", "order": session.projection().order,
				"work_center": press.work_center}), "Retain one native WorkLot before it finishes") \
					or (await _barrier("Q-work.bin")).is_empty():
				return false
	if not _expect(_plate_ui_drop(session.projection(), route.exit).get("products") == 1,
		"Three ordinary crank turns form one physical plate at the selected exit"):
		return false
	if not _expect(_write("P-plate.bin", {"status": "pass", "order": session.projection().order,
		"exit": route.exit}), "Retain the completed product before pickup") \
			or (await _barrier("Q-plate.bin")).is_empty():
		return false
	if not _expect(not panel.pickup_button.disabled, "The ordinary press panel enables its actual exit pickup"):
		return false
	if (await _chapter_ui_call("Press the ordinary Pick up exit product button",
		{"action": "pickup_material", "center": route.exit,
			"expected": {"raw": 0, "products": 1, "work_lots": []}},
		panel.pickup_button.pressed.emit)).is_empty():
		return false
	if not _expect(session.projection().cargo.P.products == 1 and session.projection().cargo.P.raw == 0
		and session.projection().hand_sources["opening-softmetal"].remaining == 10
		and _plate_ui_drop(session.projection(), route.exit).is_empty(),
		"The first carried plate comes from the collector's finite ore through the separate press"):
		return false
	if not _expect(_write("P-complete.bin", {"status": "pass", "order": session.projection().order,
		"collector_shaft": collector_shaft, "press_frame": frame}),
		"Retain both real machine identities and the plate order"):
		return false
	return not (await _barrier("Q-result.bin")).is_empty()

func _plate_ui_q() -> bool:
	var restored: Dictionary = session.projection()
	if not _expect(restored.order == 21 and _collector_ui_drop(restored)
		and restored.hand_sources["opening-softmetal"].remaining == 14,
		"Q starts from the unchanged first collector-cut Store input") \
			or not _expect(_write("Q-ready.bin", {"status": "pass"}),
			"Q joins before the ordinary press route moves material"):
		return false
	var fed: Dictionary = await _barrier("P-fed.bin")
	if fed.is_empty() or not await _until(func(): return session.projection().order >= fed.order,
		"Q receives the pressed blank after finite fabrication"):
		return false
	if not _expect(_plate_ui_drop(session.projection(), fed.work_center).get("raw") == 1
		and session.projection().cargo.P.raw == 0
		and session.projection().hand_sources["opening-softmetal"].remaining == 10,
		"Q sees collector ore under the press head, with no remote raw copy") \
			or not _expect(_write("Q-fed.bin", {"status": "pass"}), "Release P's first press turn"):
		return false
	var work: Dictionary = await _barrier("P-work.bin")
	if work.is_empty() or not await _until(func(): return session.projection().order >= work.order,
		"Q receives the unfinished native press work"):
		return false
	var held: Dictionary = _plate_ui_drop(session.projection(), work.work_center)
	if not _expect(held.get("raw") == 0 and held.get("work_lots", []).size() == 1,
		"Q sees one retained WorkLot rather than a speculative plate") \
			or not _expect(_write("Q-work.bin", {"status": "pass"}), "Release P's remaining turns"):
		return false
	var formed: Dictionary = await _barrier("P-plate.bin")
	if formed.is_empty() or not await _until(func(): return session.projection().order >= formed.order,
		"Q receives the physical plate at its selected exit"):
		return false
	if not _expect(_plate_ui_drop(session.projection(), formed.exit).get("products") == 1
		and session.projection().cargo.P.products == 0,
		"Q sees one formed plate at the press, before P picks it up") \
			or not _expect(_write("Q-plate.bin", {"status": "pass"}), "Release P's real product pickup"):
		return false
	var complete: Dictionary = await _barrier("P-complete.bin")
	if complete.is_empty() or not await _until(func(): return session.projection().order >= complete.order,
		"Q receives the same first carried plate"):
		return false
	return _expect(session.projection().cargo.P.products == 1 and session.projection().cargo.P.raw == 0
		and session.projection().hand_sources["opening-softmetal"].remaining == 10
		and not session.projection().placed_components.get(complete.press_frame, {}).is_empty()
		and not session.projection().placed_components.get(complete.collector_shaft, {}).is_empty(),
		"Q retains one product and both separate machines without stock duplication")

func _plate_ui_resume() -> bool:
	var earlier: Dictionary = _read(previous.path_join("P-result.bin"))
	var saved: Dictionary = earlier.get("projection", {})
	var restored: Dictionary = session.projection()
	return _expect(earlier.get("status") == "pass" and saved.get("order") == 57
		and restored.get("order") == saved.get("order")
		and _same(restored.get("placed_components"), saved.get("placed_components"))
		and _same(restored.get("dropped_material"), saved.get("dropped_material"))
		and _same(restored.get("cargo"), saved.get("cargo"))
		and _same(restored.get("hand_sources"), saved.get("hand_sources"))
		and restored.get("hand_crank", {}).get("holder") == "P"
		and restored.get("cargo", {}).get("P", {}).get("products") == 1
		and not _plate_ui_ready_press(restored).is_empty(),
		"Fresh native Store host preserves exact collector, press, source and first-plate custody")

func _run_plate_ui() -> void:
	if actor not in ["P", "Q"] or phase not in ["collector-plate", "collector-plate-resume"] \
			or not directory.is_absolute_path() or (phase == "collector-plate-resume" and not previous.is_absolute_path()):
		push_error("The ordinary collector-to-plate consumer needs role, phase and owned evidence paths")
		quit(1)
		return
	deadline = Time.get_ticks_msec() + 160000
	facts.evidence = "ordinary_shared_native_collector_to_press_callbacks"
	opening = load("res://opening/shared_opening.tscn").instantiate()
	root.add_child(opening)
	session = opening.session
	session.outcome.connect(func(outcome: Dictionary):
		var request: String = outcome.get("request", "")
		if not replies.has(request):
			replies[request] = []
		replies[request].append(outcome.duplicate(true)))
	if not await _until(func(): return session.is_ready(), "The ordinary first-product scene joins native Session"):
		return
	var passed := false
	if phase == "collector-plate":
		passed = await _plate_ui_p() if actor == "P" else await _plate_ui_q()
	else:
		passed = _plate_ui_resume()
	if passed and not written:
		_record("pass")

func _shipment_initial() -> bool:
	var earlier: Dictionary = _read(previous.path_join("P-result.bin"))
	var plate: Dictionary = earlier.get("projection", {})
	var current: Dictionary = session.projection()
	return _expect(earlier.get("status") == "pass" and plate.get("order") == 57
		and current.get("order") == plate.get("order")
		and _same(current.get("placed_components"), plate.get("placed_components"))
		and _same(current.get("cargo"), plate.get("cargo"))
		and _same(current.get("hand_sources"), plate.get("hand_sources"))
		and _same(current.get("dropped_material"), plate.get("dropped_material"))
		and _same(current.get("freight_beacon"), plate.get("freight_beacon"))
		and current.cargo.P.products == 1 and current.freight_beacon.shipped_products == 0
		and current.hand_sources["opening-softmetal"].remaining == 10,
		"Both scenes open the exact collector-derived carried plate checkpoint")

func _shipment_p() -> bool:
	if not _shipment_initial() or (await _barrier("Q-ready.bin")).is_empty():
		return false
	for target in [Vector2(4.95, 4.95), Vector2(6.6, 4.95),
			Vector2(6.6, 8.25), Vector2(9.9, 8.25)]:
		if not await _chapter_ui_walk(target):
			return false
	await process_frame
	opening.distance = 0.0
	opening.orbit_yaw = 0.0
	opening.orbit_pitch = 0.18
	opening._update_camera()
	var hit: Dictionary = opening._screen_pick(root.get_visible_rect().size / 2.0)
	if not _expect(not hit.is_empty() and hit.get("collider") == opening.freight_beacon_visual,
		"The normal first-person E ray picks the actual freight beacon after walking there"):
		return false
	if not shipment_capture_prefix.is_empty():
		await process_frame
		if not _expect(root.get_texture().get_image().save_png(shipment_capture_prefix + "-ready.png") == OK,
			"Retain the passive beacon view before its one-plate shipment"):
			return false
	var beacon: String = str(session.projection().freight_beacon.id)
	if (await _chapter_ui_call("Ship the collector-derived plate through ordinary E",
		{"action": "deliver_first_plate", "entity": beacon}, opening._interact_pointed)).is_empty():
		return false
	var shipped: Dictionary = session.projection()
	if not _expect(shipped.order == 58 and shipped.cargo.P.products == 0
		and shipped.freight_beacon.shipped_products == 1
		and shipped.freight_beacon.order_complete
		and shipped.freight_beacon.repeat_order_shipped == 0
		and not shipped.freight_beacon.repeat_order_complete
		and shipped.hand_sources["opening-softmetal"].remaining == 10
		and shipped.dropped_material.is_empty()
		and opening.manager_log_repeat_entry.visible
		and "REPEAT ORDER" in opening.goal_label.text,
		"The native beacon takes one real plate and reveals the repeat commission"):
		return false
	if not shipment_capture_prefix.is_empty():
		await process_frame
		if not _expect(root.get_texture().get_image().save_png(shipment_capture_prefix + "-delivered.png") == OK,
			"Retain the passive completed freight view and next commission"):
			return false
	if not _expect(_write("P-shipped.bin", {"status": "pass", "order": shipped.order,
		"beacon": beacon, "components": shipped.placed_components.size()}),
		"Publish the exact freight receipt to Q"):
		return false
	return not (await _barrier("Q-shipped.bin")).is_empty()

func _shipment_q() -> bool:
	if not _shipment_initial() or not _expect(_write("Q-ready.bin", {"status": "pass"}),
		"Q confirms the same pre-shipment plate custody"):
		return false
	var marker: Dictionary = await _barrier("P-shipped.bin")
	if marker.is_empty() or not await _until(func(): return session.projection().order >= marker.order,
		"Q receives the actual first freight receipt"):
		return false
	var shipped: Dictionary = session.projection()
	if not _expect(shipped.order == 58 and shipped.cargo.P.products == 0
		and shipped.freight_beacon.id == marker.beacon
		and shipped.freight_beacon.shipped_products == 1
		and shipped.freight_beacon.order_complete
		and shipped.freight_beacon.repeat_order_shipped == 0
		and shipped.placed_components.size() == marker.components
		and shipped.hand_sources["opening-softmetal"].remaining == 10
		and shipped.dropped_material.is_empty(),
		"Q independently sees one shipped plate and unchanged two-machine stock"):
		return false
	return _expect(_write("Q-shipped.bin", {"status": "pass", "order": shipped.order}),
		"Release P only after Q sees the freight debit")

func _shipment_resume() -> bool:
	var earlier: Dictionary = _read(previous.path_join("P-result.bin"))
	var shipped: Dictionary = earlier.get("projection", {})
	var current: Dictionary = session.projection()
	return _expect(earlier.get("status") == "pass" and shipped.get("order") == 58
		and current.get("order") == shipped.get("order")
		and _same(current.get("placed_components"), shipped.get("placed_components"))
		and _same(current.get("cargo"), shipped.get("cargo"))
		and _same(current.get("hand_sources"), shipped.get("hand_sources"))
		and _same(current.get("dropped_material"), shipped.get("dropped_material"))
		and _same(current.get("freight_beacon"), shipped.get("freight_beacon"))
		and current.freight_beacon.order_complete and current.freight_beacon.shipped_products == 1
		and current.cargo.P.products == 0 and opening.manager_log_repeat_entry.visible,
		"Fresh Store host preserves the exact source-to-shipment receipt and next commission")

func _mirrored_press_p() -> bool:
	if not _shipment_resume() or (await _barrier("Q-ready.bin")).is_empty():
		return false
	for target in [Vector2(6.6, 8.25), Vector2(6.6, 4.95),
			Vector2(4.95, 4.95), Vector2(3.3, 4.95)]:
		if not await _chapter_ui_walk(target):
			return false
	var original: Dictionary = _plate_ui_ready_press(session.projection())
	var frame: String = str(original.get("frame", ""))
	var old_shaft: String = str(original.get("parts", {}).get("shaft", ""))
	var old_cog: String = str(original.get("parts", {}).get("drive_cog", ""))
	if not _expect(not frame.is_empty() and original.shaft_center == [13, 4, 16]
		and original.cog_center == [14, 4, 16] and not old_shaft.is_empty() and not old_cog.is_empty(),
		"The first shipped plate left the original east-side press drive intact"):
		return false
	for item in [old_cog, old_shaft]:
		if (await _collector_ui_issue("Reclaim the original press drive " + item,
			{"action": "reclaim_component", "entity": item})).is_empty():
			return false
	var reclaimed: Dictionary = session.projection()
	if not _expect(not reclaimed.placed_components.has(old_cog)
		and not reclaimed.placed_components.has(old_shaft)
		and reclaimed.cargo.P.components.get("wooden_shaft", 0) == 1
		and reclaimed.cargo.P.components.get("wooden_cog", 0) == 1
		and reclaimed.dropped_material.is_empty()
		and reclaimed.hand_sources["opening-softmetal"].remaining == 10,
		"Reclaiming the empty drive returns exactly the two reusable wooden parts"):
		return false
	var new_shaft: Dictionary = await _collector_ui_issue("Fit the press shaft on its south face",
		{"action": "place_component", "component": "wooden_shaft", "center": [12, 4, 15]})
	if new_shaft.is_empty():
		return false
	var new_cog: Dictionary = await _collector_ui_issue("Fit the press cog beyond its south shaft",
		{"action": "place_component", "component": "wooden_cog", "center": [12, 4, 14]})
	if new_cog.is_empty():
		return false
	var mirrored: Dictionary = _plate_ui_ready_press(session.projection())
	if not _expect(mirrored.get("frame") == frame
		and mirrored.get("shaft_center") == [12, 4, 15]
		and mirrored.get("cog_center") == [12, 4, 14]
		and mirrored.get("parts", {}).get("shaft") == new_shaft.get("entity")
		and mirrored.get("parts", {}).get("drive_cog") == new_cog.get("entity")
		and mirrored.get("open_feeds", []).size() > 0
		and session.projection().cargo.P.components.get("wooden_shaft", 0) == 0
		and session.projection().cargo.P.components.get("wooden_cog", 0) == 0,
		"The same frame now has a real ready drive on a different world-grid face"):
		return false
	if not _expect(_write("P-mirrored.bin", {"status": "pass", "order": session.projection().order,
		"frame": frame, "old_shaft": old_shaft, "old_cog": old_cog,
		"new_shaft": new_shaft.entity, "new_cog": new_cog.entity}),
		"Retain both exact drive layouts before obtaining the next blank") \
			or (await _barrier("Q-mirrored.bin")).is_empty():
		return false
	for target in [Vector2(1.65, 4.95), Vector2(0.0, 4.95)]:
		if not await _chapter_ui_walk(target):
			return false
	var collector_shaft := ""
	for item: Dictionary in session.projection().get("collector_assemblies", []):
		if item.get("status") == "ready" and item.get("center") == [0, 4, 4]:
			collector_shaft = str(item.get("parts", {}).get("shaft", ""))
	if not _expect(not collector_shaft.is_empty() and _collector_ui_select(collector_shaft),
		"The original collector remains selectable after the press drive moves"):
		return false
	var panel = opening.arrival_assembly_controls
	if (await _chapter_ui_call("Cut a second plate blank at the original collector",
		{"action": "turn_hand_crank", "entity": collector_shaft},
		panel.collector_cut_button.pressed.emit)).is_empty():
		return false
	if not _expect(_collector_ui_drop(session.projection())
		and session.projection().hand_sources["opening-softmetal"].remaining == 9,
		"The second layout needs one more genuinely collector-cut ore blank"):
		return false
	if not _expect(_write("P-cut.bin", {"status": "pass", "order": session.projection().order}),
		"Publish the one-blank collector receiver before pickup") \
			or (await _barrier("Q-cut.bin")).is_empty():
		return false
	if not await _chapter_ui_walk(Vector2(0.0, 3.3)):
		return false
	if (await _collector_ui_issue("Carry the second collector blank",
		{"action": "pickup_material", "center": [0, 4, 3],
			"expected": {"raw": 1, "products": 0, "work_lots": []}})).is_empty():
		return false
	for target in [Vector2(1.65, 4.95), Vector2(3.3, 4.95)]:
		if not await _chapter_ui_walk(target):
			return false
	opening._select_tool("inspect")
	opening._world_click(Vector2i(3, 4), frame)
	panel = opening.arrival_assembly_controls
	if not _expect(opening.selected == frame and panel.press_section.visible
		and not panel.feed_button.disabled and not _plate_ui_ready_press(session.projection()).is_empty(),
		"The ordinary panel reopens the newly mirrored press for hand feeding"):
		return false
	var route: Dictionary = mirrored.open_feeds[0]
	if (await _chapter_ui_call("Feed the new collector blank into the mirrored press",
		{"action": "feed_press", "entity": frame, "entry": route.entry},
		panel.feed_button.pressed.emit)).is_empty():
		return false
	if not _expect(_write("P-fed.bin", {"status": "pass", "order": session.projection().order,
		"work_center": mirrored.work_center}), "Publish the second retained feed") \
			or (await _barrier("Q-fed.bin")).is_empty():
		return false
	var turn_wire := {"action": "turn_press_crank", "entity": frame,
		"drive": new_shaft.entity, "exit": route.exit}
	for turn in range(3):
		if not _expect(not panel.turn_button.disabled, "The mirrored press drive remains hand-operable"):
			return false
		if (await _chapter_ui_call("Turn the mirrored press crank %d" % turn,
			turn_wire, panel.turn_button.pressed.emit)).is_empty():
			return false
	if not _expect(_plate_ui_drop(session.projection(), route.exit).get("products") == 1,
		"The mirrored drive forms one second plate at its selected clear exit"):
		return false
	if not _expect(_write("P-formed.bin", {"status": "pass", "order": session.projection().order,
		"exit": route.exit}), "Publish the formed second plate before pickup") \
			or (await _barrier("Q-formed.bin")).is_empty():
		return false
	if (await _chapter_ui_call("Pick up the second mirrored-drive plate",
		{"action": "pickup_material", "center": route.exit,
			"expected": {"raw": 0, "products": 1, "work_lots": []}},
		panel.pickup_button.pressed.emit)).is_empty():
		return false
	var complete: Dictionary = session.projection()
	if not _expect(complete.order == 69 and complete.cargo.P.products == 1
		and complete.cargo.P.raw == 0 and complete.dropped_material.is_empty()
		and complete.freight_beacon.shipped_products == 1
		and complete.hand_sources["opening-softmetal"].remaining == 9,
		"The mirrored press holds a new carried product after the first freight receipt"):
		return false
	if not _expect(_write("P-complete.bin", {"status": "pass", "order": complete.order,
		"frame": frame, "new_shaft": new_shaft.entity, "new_cog": new_cog.entity}),
		"Publish the second real product and both changed drive identities"):
		return false
	return not (await _barrier("Q-result.bin")).is_empty()

func _mirrored_press_q() -> bool:
	if not _shipment_resume() or not _expect(_write("Q-ready.bin", {"status": "pass"}),
		"Q joins the same first-shipment Store before the press is changed"):
		return false
	var mirror: Dictionary = await _barrier("P-mirrored.bin")
	if mirror.is_empty() or not await _until(func(): return session.projection().order >= mirror.order,
		"Q receives the changed press geometry"):
		return false
	var state: Dictionary = session.projection()
	var press: Dictionary = _plate_ui_ready_press(state)
	if not _expect(state.order == 62 and not state.placed_components.has(mirror.old_shaft)
		and not state.placed_components.has(mirror.old_cog)
		and state.placed_components.has(mirror.new_shaft)
		and state.placed_components.has(mirror.new_cog)
		and press.get("frame") == mirror.frame and press.get("shaft_center") == [12, 4, 15]
		and press.get("cog_center") == [12, 4, 14]
		and state.hand_sources["opening-softmetal"].remaining == 10,
		"Q sees reused parts on the new face without a material debit") \
			or not _expect(_write("Q-mirrored.bin", {"status": "pass"}), "Release the second collector cut"):
		return false
	var cut: Dictionary = await _barrier("P-cut.bin")
	if cut.is_empty() or not await _until(func(): return session.projection().order >= cut.order,
		"Q receives the second collector cut"):
		return false
	if not _expect(_collector_ui_drop(session.projection())
		and session.projection().hand_sources["opening-softmetal"].remaining == 9,
		"Q sees one source-debited blank in the original collector receiver") \
			or not _expect(_write("Q-cut.bin", {"status": "pass"}), "Release the second blank pickup"):
		return false
	var fed: Dictionary = await _barrier("P-fed.bin")
	if fed.is_empty() or not await _until(func(): return session.projection().order >= fed.order,
		"Q receives the mirrored press feed"):
		return false
	if not _expect(_plate_ui_drop(session.projection(), fed.work_center).get("raw") == 1
		and session.projection().cargo.P.raw == 0,
		"Q sees the same second blank under the mirrored press head") \
			or not _expect(_write("Q-fed.bin", {"status": "pass"}), "Release the mirrored press turns"):
		return false
	var formed: Dictionary = await _barrier("P-formed.bin")
	if formed.is_empty() or not await _until(func(): return session.projection().order >= formed.order,
		"Q receives the second formed plate"):
		return false
	if not _expect(_plate_ui_drop(session.projection(), formed.exit).get("products") == 1
		and session.projection().cargo.P.products == 0,
		"Q sees the mirrored press output before P takes it") \
			or not _expect(_write("Q-formed.bin", {"status": "pass"}), "Release product pickup"):
		return false
	var complete: Dictionary = await _barrier("P-complete.bin")
	if complete.is_empty() or not await _until(func(): return session.projection().order >= complete.order,
		"Q receives the same carried second plate"):
		return false
	return _expect(session.projection().cargo.P.products == 1
		and session.projection().hand_sources["opening-softmetal"].remaining == 9
		and session.projection().freight_beacon.shipped_products == 1
		and not _plate_ui_ready_press(session.projection()).is_empty()
		and session.projection().placed_components.has(complete.new_shaft)
		and session.projection().placed_components.has(complete.new_cog),
		"Q retains the second plate and mirrored drive without duplicating the first shipment")

func _mirrored_press_resume() -> bool:
	var earlier: Dictionary = _read(previous.path_join("P-result.bin"))
	var saved: Dictionary = earlier.get("projection", {})
	var restored: Dictionary = session.projection()
	var press: Dictionary = _plate_ui_ready_press(restored)
	return _expect(earlier.get("status") == "pass" and saved.get("order") == 69
		and restored.get("order") == saved.get("order")
		and _same(restored.get("placed_components"), saved.get("placed_components"))
		and _same(restored.get("cargo"), saved.get("cargo"))
		and _same(restored.get("hand_sources"), saved.get("hand_sources"))
		and _same(restored.get("dropped_material"), saved.get("dropped_material"))
		and _same(restored.get("freight_beacon"), saved.get("freight_beacon"))
		and press.get("shaft_center") == [12, 4, 15]
		and press.get("cog_center") == [12, 4, 14]
		and restored.cargo.P.products == 1 and restored.freight_beacon.shipped_products == 1,
		"Fresh Store host preserves the second plate and reused mirrored drive identities")

func _alternate_collector(snapshot: Dictionary) -> Dictionary:
	for item: Variant in snapshot.get("collector_assemblies", []):
		if item is Dictionary and item.get("status") == "ready" and item.get("center") == [0, 4, 4]:
			return item
	return {}

func _alternate_collector_p() -> bool:
	if not _shipment_resume() or (await _barrier("Q-ready.bin")).is_empty():
		return false
	for target in [Vector2(6.6, 8.25), Vector2(6.6, 4.95),
			Vector2(4.95, 4.95), Vector2(3.3, 4.95),
			Vector2(1.65, 4.95), Vector2(0.0, 4.95), Vector2(0.0, 3.3)]:
		if not await _chapter_ui_walk(target):
			return false
	var original: Dictionary = _alternate_collector(session.projection())
	var frame: String = str(original.get("parts", {}).get("frame", ""))
	var old_tray: String = str(original.get("parts", {}).get("receiver", ""))
	var old_shaft: String = str(original.get("parts", {}).get("shaft", ""))
	if not _expect(not frame.is_empty() and not old_tray.is_empty() and not old_shaft.is_empty()
		and session.projection().placed_components.get(old_tray, {}).get("center") == [0, 4, 3]
		and session.projection().placed_components.get(old_shaft, {}).get("center") == [1, 4, 4],
		"The first shipment leaves the original south receiver and east drive ready"):
		return false
	for item in [old_shaft, old_tray]:
		if (await _collector_ui_issue("Recover original collector part " + item,
			{"action": "reclaim_component", "entity": item})).is_empty():
			return false
	var recovered: Dictionary = session.projection()
	if not _expect(not recovered.placed_components.has(old_shaft)
		and not recovered.placed_components.has(old_tray)
		and recovered.cargo.P.components.get("wooden_shaft", 0) == 1
		and recovered.cargo.P.components.get("receiver_tray", 0) == 1
		and recovered.dropped_material.is_empty()
		and recovered.hand_sources["opening-softmetal"].remaining == 10,
		"An empty receiver and its drive return as the same reusable parts"):
		return false
	var new_tray: Dictionary = await _collector_ui_issue("Fit the collector receiver on its north side",
		{"action": "place_component", "component": "receiver_tray", "center": [0, 4, 5]})
	if new_tray.is_empty():
		return false
	var new_shaft: Dictionary = await _collector_ui_issue("Fit the collector drive opposite its receiver",
		{"action": "place_component", "component": "wooden_shaft", "center": [0, 4, 3]})
	if new_shaft.is_empty():
		return false
	var alternate: Dictionary = _alternate_collector(session.projection())
	if not _expect(alternate.get("parts", {}).get("frame") == frame
		and session.projection().placed_components.get(new_tray.entity, {}).get("center") == [0, 4, 5]
		and session.projection().placed_components.get(new_shaft.entity, {}).get("center") == [0, 4, 3]
		and alternate.get("parts", {}).get("receiver") == new_tray.get("entity")
		and alternate.get("parts", {}).get("shaft") == new_shaft.get("entity")
		and session.projection().cargo.P.components.get("receiver_tray", 0) == 0
		and session.projection().cargo.P.components.get("wooden_shaft", 0) == 0,
		"The same collector cuts toward ore with a different physical receiver and drive route"):
		return false
	if not _expect(_write("P-alternate.bin", {"status": "pass", "order": session.projection().order,
		"frame": frame, "old_tray": old_tray, "old_shaft": old_shaft,
		"new_tray": new_tray.entity, "new_shaft": new_shaft.entity}),
		"Publish exact replacement identities before operating the second layout") \
			or (await _barrier("Q-alternate.bin")).is_empty():
		return false
	if not _collector_ui_select(new_shaft.entity):
		return false
	var panel = opening.arrival_assembly_controls
	var cut: Dictionary = await _chapter_ui_call("Cut ore using the alternate collector arrangement",
		{"action": "turn_hand_crank", "entity": new_shaft.entity},
		panel.collector_cut_button.pressed.emit)
	if cut.is_empty() or not _expect(cut.get("source_remaining") == 9
		and _plate_ui_drop(session.projection(), [0, 4, 5]).get("raw") == 1
		and _plate_ui_drop(session.projection(), [0, 4, 3]).is_empty(),
		"The alternate outlet receives exactly one finite ore blank"):
		return false
	if not _expect(_write("P-cut.bin", {"status": "pass", "order": session.projection().order}),
		"Publish the new receiver stock before it is picked up") \
			or (await _barrier("Q-cut.bin")).is_empty():
		return false
	if (await _collector_ui_issue("Carry the blank from the alternate receiver",
		{"action": "pickup_material", "center": [0, 4, 5],
			"expected": {"raw": 1, "products": 0, "work_lots": []}})).is_empty():
		return false
	var complete: Dictionary = session.projection()
	if not _expect(complete.order == 64 and complete.cargo.P.raw == 1
		and complete.cargo.P.products == 0 and complete.dropped_material.is_empty()
		and complete.hand_sources["opening-softmetal"].remaining == 9
		and complete.freight_beacon.shipped_products == 1
		and not _plate_ui_ready_press(complete).is_empty(),
		"The alternate collector yields a carried blank beside the unchanged press and freight receipt"):
		return false
	if not _expect(_write("P-complete.bin", {"status": "pass", "order": complete.order,
		"new_tray": new_tray.entity, "new_shaft": new_shaft.entity}),
		"Retain exact carried ore and alternate part identities"):
		return false
	return not (await _barrier("Q-result.bin")).is_empty()

func _alternate_collector_q() -> bool:
	if not _shipment_resume() or not _expect(_write("Q-ready.bin", {"status": "pass"}),
		"Q joins the same first-shipment Store before collector recovery"):
		return false
	var alternate: Dictionary = await _barrier("P-alternate.bin")
	if alternate.is_empty() or not await _until(func(): return session.projection().order >= alternate.order,
		"Q receives the alternate collector arrangement"):
		return false
	var changed: Dictionary = session.projection()
	var collector: Dictionary = _alternate_collector(changed)
	if not _expect(changed.order == 62 and collector.get("parts", {}).get("frame") == alternate.frame
		and collector.get("parts", {}).get("receiver") == alternate.new_tray
		and collector.get("parts", {}).get("shaft") == alternate.new_shaft
		and not changed.placed_components.has(alternate.old_tray)
		and not changed.placed_components.has(alternate.old_shaft)
		and changed.placed_components.get(alternate.new_tray, {}).get("center") == [0, 4, 5]
		and changed.placed_components.get(alternate.new_shaft, {}).get("center") == [0, 4, 3]
		and changed.hand_sources["opening-softmetal"].remaining == 10
		and changed.dropped_material.is_empty(),
		"Q sees the same parts reused in a distinct ready collector geometry") \
			or not _expect(_write("Q-alternate.bin", {"status": "pass"}),
			"Release the new collector cut after Q observes its geometry"):
		return false
	var cut: Dictionary = await _barrier("P-cut.bin")
	if cut.is_empty() or not await _until(func(): return session.projection().order >= cut.order,
		"Q receives one actual cut through the alternate layout"):
		return false
	if not _expect(session.projection().order == 63
		and session.projection().hand_sources["opening-softmetal"].remaining == 9
		and _plate_ui_drop(session.projection(), [0, 4, 5]).get("raw") == 1
		and _plate_ui_drop(session.projection(), [0, 4, 3]).is_empty(),
		"Q sees one finite blank only in the moved receiver") \
			or not _expect(_write("Q-cut.bin", {"status": "pass"}),
			"Release pickup after Q observes the deposited ore"):
		return false
	var complete: Dictionary = await _barrier("P-complete.bin")
	if complete.is_empty() or not await _until(func(): return session.projection().order >= complete.order,
		"Q receives exact final alternate collector custody"):
		return false
	var final: Dictionary = session.projection()
	return _expect(final.order == 64 and final.cargo.P.raw == 1
		and final.dropped_material.is_empty() and final.freight_beacon.shipped_products == 1
		and final.hand_sources["opening-softmetal"].remaining == 9
		and _alternate_collector(final).get("parts", {}).get("receiver") == complete.new_tray
		and _alternate_collector(final).get("parts", {}).get("shaft") == complete.new_shaft,
		"Q retains the carried alternate blank, source debit and distinct part identities")

func _alternate_collector_resume() -> bool:
	var earlier: Dictionary = _read(previous.path_join("P-result.bin"))
	var saved: Dictionary = earlier.get("projection", {})
	var restored: Dictionary = session.projection()
	var collector: Dictionary = _alternate_collector(restored)
	return _expect(earlier.get("status") == "pass" and saved.get("order") == 64
		and restored.get("order") == saved.get("order")
		and _same(restored.get("placed_components"), saved.get("placed_components"))
		and _same(restored.get("cargo"), saved.get("cargo"))
		and _same(restored.get("hand_sources"), saved.get("hand_sources"))
		and _same(restored.get("dropped_material"), saved.get("dropped_material"))
		and _same(restored.get("freight_beacon"), saved.get("freight_beacon"))
		and restored.cargo.P.raw == 1 and restored.freight_beacon.shipped_products == 1
		and restored.placed_components.get(collector.get("parts", {}).get("receiver", ""), {}).get("center") == [0, 4, 5]
		and restored.placed_components.get(collector.get("parts", {}).get("shaft", ""), {}).get("center") == [0, 4, 3],
		"Fresh Store host preserves the alternate collector and its finite carried blank")

func _alternate_repeat_p() -> bool:
	if not _alternate_collector_resume() or (await _barrier("Q-ready.bin")).is_empty():
		return false
	for target in [Vector2(0.0, 4.95), Vector2(1.65, 4.95), Vector2(3.3, 4.95)]:
		if not await _chapter_ui_walk(target):
			return false
	var press: Dictionary = _plate_ui_ready_press(session.projection())
	var frame: String = str(press.get("frame", ""))
	if not _expect(not frame.is_empty() and press.get("open_feeds", []).size() > 0
		and session.projection().cargo.P.raw == 1
		and _alternate_collector(session.projection()).get("status") == "ready",
		"The alternate collector's one carried blank can reach the original ready press"):
		return false
	opening._select_tool("inspect")
	opening._world_click(Vector2i(3, 4), frame)
	var panel = opening.arrival_assembly_controls
	if not _expect(opening.selected == frame and panel.press_section.visible
		and not panel.feed_button.disabled,
		"The ordinary panel opens the same press for the alternate collector blank"):
		return false
	var route: Dictionary = press.open_feeds[0]
	if (await _chapter_ui_call("Feed the alternate collector blank into the press",
		{"action": "feed_press", "entity": frame, "entry": route.entry},
		panel.feed_button.pressed.emit)).is_empty():
		return false
	if not _expect(_write("P-fed.bin", {"status": "pass", "order": session.projection().order,
		"work_center": press.work_center}), "Publish the second source-to-press feed") \
			or (await _barrier("Q-fed.bin")).is_empty():
		return false
	var turn_wire := {"action": "turn_press_crank", "entity": frame,
		"drive": press.parts.shaft, "exit": route.exit}
	for turn in range(3):
		if not _expect(not panel.turn_button.disabled,
			"The same press drive remains available for the alternate source"):
			return false
		if (await _chapter_ui_call("Turn the second-source press work %d" % turn,
			turn_wire, panel.turn_button.pressed.emit)).is_empty():
			return false
		if turn == 0:
			if not _expect(_write("P-work.bin", {"status": "pass", "order": session.projection().order,
				"work_center": press.work_center}), "Publish the retained second WorkLot") \
					or (await _barrier("Q-work.bin")).is_empty():
				return false
	if not _expect(_plate_ui_drop(session.projection(), route.exit).get("products") == 1,
		"Three turns form a plate from the alternate receiver's ore"):
		return false
	if not _expect(_write("P-formed.bin", {"status": "pass", "order": session.projection().order,
		"exit": route.exit}), "Publish the second plate before taking it") \
			or (await _barrier("Q-formed.bin")).is_empty():
		return false
	if (await _chapter_ui_call("Pick up the alternate collector's formed plate",
		{"action": "pickup_material", "center": route.exit,
			"expected": {"raw": 0, "products": 1, "work_lots": []}},
		panel.pickup_button.pressed.emit)).is_empty():
		return false
	if not _expect(session.projection().cargo.P.products == 1
		and session.projection().cargo.P.raw == 0 and session.projection().order == 69,
		"The second plate is carried without duplicating its ore blank"):
		return false
	if not _expect(_write("P-carried.bin", {"status": "pass", "order": session.projection().order}),
		"Publish the carried product before repeat freight") \
			or (await _barrier("Q-carried.bin")).is_empty():
		return false
	for target in [Vector2(4.95, 4.95), Vector2(6.6, 4.95),
			Vector2(6.6, 8.25), Vector2(9.9, 8.25)]:
		if not await _chapter_ui_walk(target):
			return false
	await process_frame
	opening.distance = 0.0
	opening.orbit_yaw = 0.0
	opening.orbit_pitch = 0.18
	opening._update_camera()
	var hit: Dictionary = opening._screen_pick(root.get_visible_rect().size / 2.0)
	if not _expect(not hit.is_empty() and hit.get("collider") == opening.freight_beacon_visual,
		"The E ray still selects the physical freight pylon for the repeat order"):
		return false
	if not shipment_capture_prefix.is_empty():
		await process_frame
		if not _expect(root.get_texture().get_image().save_png(shipment_capture_prefix + "-ready.png") == OK,
			"Retain the passive second-plate view before repeat freight"):
			return false
		opening._update_camera()
		if not _expect(opening._screen_pick(root.get_visible_rect().size / 2.0).get("collider")
			== opening.freight_beacon_visual,
			"The live E ray still points at the pylon after passive capture"):
			return false
	var beacon: String = str(session.projection().freight_beacon.id)
	if (await _chapter_ui_call("Deliver the alternate collector's plate through ordinary E",
		{"action": "deliver_repeat_plate", "entity": beacon},
		opening._interact_pointed)).is_empty():
		return false
	var shipped: Dictionary = session.projection()
	if not _expect(shipped.order == 70 and shipped.cargo.P.products == 0
		and shipped.freight_beacon.shipped_products == 2
		and shipped.freight_beacon.repeat_order_shipped == 1
		and not shipped.freight_beacon.repeat_order_complete
		and shipped.hand_sources["opening-softmetal"].remaining == 9
		and shipped.dropped_material.is_empty(),
		"Repeat freight debits exactly one collector-derived plate and retains the remaining work order"):
		return false
	if not shipment_capture_prefix.is_empty():
		await process_frame
		if not _expect(root.get_texture().get_image().save_png(shipment_capture_prefix + "-delivered.png") == OK,
			"Retain the passive repeat-order receipt view"):
			return false
	if not _expect(_write("P-shipped.bin", {"status": "pass", "order": shipped.order,
		"beacon": beacon}), "Publish the second native freight receipt"):
		return false
	return not (await _barrier("Q-shipped.bin")).is_empty()

func _alternate_repeat_q() -> bool:
	if not _alternate_collector_resume() or not _expect(_write("Q-ready.bin", {"status": "pass"}),
		"Q joins the exact carried alternate-output blank before press work"):
		return false
	var fed: Dictionary = await _barrier("P-fed.bin")
	if fed.is_empty() or not await _until(func(): return session.projection().order >= fed.order,
		"Q receives the alternate-source press feed"):
		return false
	if not _expect(session.projection().order == 65
		and _plate_ui_drop(session.projection(), fed.work_center).get("raw") == 1
		and session.projection().cargo.P.raw == 0,
		"Q sees the same finite blank under the press head") \
			or not _expect(_write("Q-fed.bin", {"status": "pass"}), "Release press turns"):
		return false
	var work: Dictionary = await _barrier("P-work.bin")
	if work.is_empty() or not await _until(func(): return session.projection().order >= work.order,
		"Q receives partial second-source work"):
		return false
	if not _expect(_plate_ui_drop(session.projection(), work.work_center).get("work_lots", []).size() == 1,
		"Q sees retained native WorkLot before the product forms") \
			or not _expect(_write("Q-work.bin", {"status": "pass"}), "Release final turns"):
		return false
	var formed: Dictionary = await _barrier("P-formed.bin")
	if formed.is_empty() or not await _until(func(): return session.projection().order >= formed.order,
		"Q receives the second formed plate"):
		return false
	if not _expect(_plate_ui_drop(session.projection(), formed.exit).get("products") == 1
		and session.projection().cargo.P.products == 0,
		"Q sees the second plate at the press exit before P takes it") \
			or not _expect(_write("Q-formed.bin", {"status": "pass"}), "Release product pickup"):
		return false
	var carried: Dictionary = await _barrier("P-carried.bin")
	if carried.is_empty() or not await _until(func(): return session.projection().order >= carried.order,
		"Q receives the carried alternate-source plate"):
		return false
	if not _expect(session.projection().cargo.P.products == 1
		and session.projection().freight_beacon.shipped_products == 1
		and session.projection().hand_sources["opening-softmetal"].remaining == 9,
		"Q sees the product move into P cargo without a source refill") \
			or not _expect(_write("Q-carried.bin", {"status": "pass"}), "Release repeat freight"):
		return false
	var receipt: Dictionary = await _barrier("P-shipped.bin")
	if receipt.is_empty() or not await _until(func(): return session.projection().order >= receipt.order,
		"Q receives the native repeat freight receipt"):
		return false
	var shipped: Dictionary = session.projection()
	return _expect(shipped.order == 70 and shipped.cargo.P.products == 0
		and shipped.freight_beacon.id == receipt.beacon
		and shipped.freight_beacon.shipped_products == 2
		and shipped.freight_beacon.repeat_order_shipped == 1
		and shipped.hand_sources["opening-softmetal"].remaining == 9
		and shipped.dropped_material.is_empty()
		and _alternate_collector(shipped).get("status") == "ready",
		"Q retains one repeat shipment from the alternate layout with both machines intact") \
		and _expect(_write("Q-shipped.bin", {"status": "pass"}),
		"Release P after Q confirms the exact freight debit")

func _alternate_repeat_resume() -> bool:
	var earlier: Dictionary = _read(previous.path_join("P-result.bin"))
	var saved: Dictionary = earlier.get("projection", {})
	var restored: Dictionary = session.projection()
	return _expect(earlier.get("status") == "pass" and saved.get("order") == 70
		and restored.get("order") == saved.get("order")
		and _same(restored.get("placed_components"), saved.get("placed_components"))
		and _same(restored.get("cargo"), saved.get("cargo"))
		and _same(restored.get("hand_sources"), saved.get("hand_sources"))
		and _same(restored.get("dropped_material"), saved.get("dropped_material"))
		and _same(restored.get("freight_beacon"), saved.get("freight_beacon"))
		and restored.freight_beacon.shipped_products == 2
		and restored.freight_beacon.repeat_order_shipped == 1
		and restored.cargo.P.products == 0 and restored.cargo.P.raw == 0
		and _alternate_collector(restored).get("status") == "ready"
		and not _plate_ui_ready_press(restored).is_empty(),
		"Fresh Store host preserves alternate-source repeat freight and both ready machines")

func _run_shipment_ui() -> void:
	if actor not in ["P", "Q"] or phase not in ["collector-shipment", "collector-shipment-resume",
			"mirrored-press", "mirrored-press-resume", "alternate-collector", "alternate-collector-resume",
			"alternate-repeat", "alternate-repeat-resume"] \
			or not directory.is_absolute_path() or not previous.is_absolute_path():
		push_error("The collector-derived shipment needs role, phase and owned evidence paths")
		quit(1)
		return
	deadline = Time.get_ticks_msec() + 180000
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cog-capture-prefix="):
			shipment_capture_prefix = argument.trim_prefix("--cog-capture-prefix=")
	if phase.begins_with("mirrored-"):
		facts.evidence = "ordinary_shared_native_mirrored_press_callbacks"
	elif phase.begins_with("alternate-repeat"):
		facts.evidence = "ordinary_shared_native_alternate_collector_repeat_freight_callbacks"
	elif phase.begins_with("alternate-"):
		facts.evidence = "ordinary_shared_native_alternate_collector_callbacks"
	else:
		facts.evidence = "ordinary_shared_native_collector_to_freight_callbacks"
	opening = load("res://opening/shared_opening.tscn").instantiate()
	root.add_child(opening)
	session = opening.session
	session.outcome.connect(func(outcome: Dictionary):
		var request: String = outcome.get("request", "")
		if not replies.has(request):
			replies[request] = []
		replies[request].append(outcome.duplicate(true)))
	if not await _until(func(): return session.is_ready(), "The ordinary freight scene joins native Session"):
		return
	var passed := false
	if phase == "collector-shipment":
		passed = await _shipment_p() if actor == "P" else await _shipment_q()
	elif phase == "collector-shipment-resume":
		passed = _shipment_resume()
	elif phase == "mirrored-press":
		passed = await _mirrored_press_p() if actor == "P" else await _mirrored_press_q()
	elif phase == "mirrored-press-resume":
		passed = _mirrored_press_resume()
	elif phase == "alternate-collector":
		passed = await _alternate_collector_p() if actor == "P" else await _alternate_collector_q()
	elif phase == "alternate-collector-resume":
		passed = _alternate_collector_resume()
	elif phase == "alternate-repeat":
		passed = await _alternate_repeat_p() if actor == "P" else await _alternate_repeat_q()
	else:
		passed = _alternate_repeat_resume()
	if passed and not written:
		_record("pass")

func _run_chapter_ui() -> void:
	if actor not in ["P", "Q"] or phase not in ["chapter-ui", "chapter-ui-resume"] \
			or not directory.is_absolute_path():
		push_error("The ordinary native chapter UI consumer needs role, phase and owned directory")
		quit(1)
		return
	facts.evidence = "ordinary_shared_native_arrival_callbacks"
	opening = load("res://opening/shared_opening.tscn").instantiate()
	root.add_child(opening)
	session = opening.session
	session.outcome.connect(func(outcome: Dictionary):
		var request: String = outcome.get("request", "")
		if not replies.has(request):
			replies[request] = []
		replies[request].append(outcome.duplicate(true)))
	if not await _until(func(): return session.is_ready(), "The ordinary scene joins its native Session"):
		return
	var passed := false
	if phase == "chapter-ui":
		passed = await _chapter_ui_p() if actor == "P" else await _chapter_ui_q()
	else:
		passed = await _chapter_ui_resume_p() if actor == "P" else await _chapter_ui_resume_q()
	if passed and not written:
		_record("pass")

func _init() -> void:
	super._init()
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
	if phase in ["collector-shipment", "collector-shipment-resume", "mirrored-press", "mirrored-press-resume",
			"alternate-collector", "alternate-collector-resume", "alternate-repeat", "alternate-repeat-resume"]:
		await _run_shipment_ui()
		return
	if phase in ["collector-plate", "collector-plate-resume"]:
		await _run_plate_ui()
		return
	if phase in ["collector-ui", "collector-ui-resume"]:
		await _run_collector_ui()
		return
	if phase in ["chapter-ui", "chapter-ui-resume"]:
		await _run_chapter_ui()
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
