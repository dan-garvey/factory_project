extends SceneTree
## Invented confirmed projections and a request sink, never a Model or game.
const Controls = preload("res://opening/native_transmission_controls.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const ActorWorld = preload("res://opening/actor_world.gd")
const PhysicalActor = preload("res://opening/actor_body.gd")
const Presenter = preload("res://opening/native_transmission_presenter.gd")
const Assets = preload("res://opening/native_transmission_assets.gd")
const LooseControls = preload("res://opening/recovery_actions.gd").LooseMaterialControls
const Session = preload("res://opening-session/session.gd")
var checks := 0
var failures := 0

class HostStub extends RefCounted:
	var state: Dictionary
	var client := "P"
	var legacy_fixture := false
	var explanation_open := false
	var startup_save_pending := false
	var mutate_allowed := true
	var motion_fresh := true
	var calls: Array = []
	var messages: Array = []
	var reply_mode := "queued"
	func _can_mutate() -> bool:
		return mutate_allowed
	func _can_present_confirmed_motion() -> bool:
		return motion_fresh
	func issue(wire: Dictionary) -> Dictionary:
		calls.append(wire.duplicate(true))
		if reply_mode == "accepted":
			return {"accepted": true, "request": "request-%d" % calls.size()}
		if reply_mode == "refused":
			return {"accepted": false, "reason": "out_of_reach"}
		return {"queued": true, "accepted": false, "request": "request-%d" % calls.size()}
	func _message(words: String, _refused: bool) -> void:
		messages.append(words)

class ReadySession extends RefCounted:
	func is_ready() -> bool:
		return true

class SharedSettlement extends "res://opening/shared_opening.gd":
	func _usable_snapshot() -> bool:
		return true
	func _refresh_ui() -> void:
		pass
	func _message(_words: String, _refused: bool = false) -> void:
		pass

class PhysicalProjection extends RefCounted:
	var state: Dictionary
	func projection() -> Dictionary:
		return state.duplicate(true)
	func observe(actor: String, sample: Dictionary) -> void:
		state.actors[actor]["position"] = sample.position.duplicate()
		state.actors[actor]["ready"] = sample.ready
		state.actors[actor]["native_epoch"] = sample.native_epoch

func verify(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("TRANSMISSION_VIEW_FAILURE: " + reason)

func fixture() -> Dictionary:
	return {"context": "helper-fixture", "options": {"native": true},
		"actors": {"P": {"ready": true}, "Q": {"ready": true}},
		"entities": {"wheel": {"kind": "wheel", "generation": 1, "center": [-4, 0, 4], "axis": 1}},
		"transmission_parts": {
			"a": {"kind": "gear", "generation": 2, "center": [-4, 4, 4], "axis": 1, "teeth": 2, "half_span": 0},
			"b": {"kind": "gear", "generation": 3, "center": [0, 4, 4], "axis": 1, "teeth": 2, "half_span": 0},
			"sx": {"kind": "shaft", "generation": 4, "center": [2, 0, 4], "axis": 0, "teeth": 0, "half_span": 2},
			"sy": {"kind": "shaft", "generation": 5, "center": [0, 2, 0], "axis": 1, "teeth": 0, "half_span": 2},
			"sz": {"kind": "shaft", "generation": 6, "center": [0, 0, 2], "axis": 2, "teeth": 0, "half_span": 2}},
		"part_specifications": {
			"P": [{"kind": "gear", "teeth": 2, "half_span": 0, "count": 2}, {"kind": "shaft", "teeth": 0, "half_span": 2, "count": 3}],
			"Q": [{"kind": "gear", "teeth": 2, "half_span": 0, "count": 0}, {"kind": "shaft", "teeth": 0, "half_span": 2, "count": 0}]},
		"parts": {"gear": 99, "shaft": 99}, "drive_links": [], "powered": false,
		"motion": {"a": {"state": "rotating", "numerator": 1, "denominator": 1},
			"b": {"state": "rotating", "numerator": -1, "denominator": 1},
			"sx": {"state": "unpowered", "numerator": 0, "denominator": 1},
			"sy": {"state": "rotating", "numerator": 1, "denominator": 1},
			"sz": {"state": "stalled", "numerator": 0, "denominator": 1}},
		"engagements": [{"a": "a", "b": "b", "kind": 0}]}

func _initialize() -> void:
	call_deferred("_run")

func _controls() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var view := Controls.new()
	view.configure(host)
	verify(view.gear_height == 0, "The default cog height shares the worksite machine level.")
	view.gear_height = 4
	verify(view.visible and not view.disabled and "2 carried" in view.get_popup().get_item_text(0), "P sees its own finite kit.")
	view.get_popup().emit_signal("id_pressed", 1)
	var before: Dictionary = host.state.duplicate(true)
	var center := [-4, 4, 4]
	verify(view.handle_world_click(center, ""), "An active gear tool consumes its click.")
	verify(host.calls.back() == {"action": "place_gear", "center": [-4, 4, 4], "axis": "x", "teeth": 2}, "Gear placement delegates the exact integer center and specification.")
	verify(center == [-4, 4, 4] and host.state == before and "2 carried" in view.get_popup().get_item_text(0), "A queued response creates no speculative kit credit or geometry.")
	view._axes.emit_signal("id_pressed", 1)
	view._heights.emit_signal("id_pressed", 1)
	view.handle_world_click([0, 8, 4], "")
	verify(view.selected_axis == "y" and view.gear_height == 8 and host.calls.back() == {"action": "place_gear", "center": [0, 8, 4], "axis": "y", "teeth": 2}, "The axis and height menus use the shared tile step.")
	view._heights.emit_signal("id_pressed", 0)
	view.handle_world_click([-12, 4, 16], "")
	verify(host.calls.back().center == [-12, 4, 16], "The view delegates tile points outside the obsolete restricted construction area.")
	var sent: int = host.calls.size()
	for invalid in [[0.0, 4, 4], [true, 4, 4], [0, 4], [-1000001, 4, 4], [0, 3, 4], [0, 4, 1000001], [1, 4, 4], [0, 4, 5]]:
		verify(view.handle_world_click(invalid, ""), "Invalid active-tool coordinates are consumed.")
	verify(host.calls.size() == sent, "Malformed, off-plane and out-of-profile coordinates send no request.")
	host.client = "Q"
	view.refresh()
	verify(view.get_popup().is_item_disabled(0) and "0 carried" in view.get_popup().get_item_text(0), "Q never borrows P's aggregate parts.")
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "An empty current kit refuses without click fallthrough.")
	host.client = "P"
	for flag in ["explanation_open", "startup_save_pending"]:
		host.set(flag, true)
		view.refresh()
		verify(view.disabled and view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "Blocked view clicks are consumed without a request.")
		host.set(flag, false)
	host.mutate_allowed = false
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "The shared mutation barrier suppresses submission.")
	host.mutate_allowed = true
	host.state.actors.P.ready = false
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "An unready character cannot submit.")
	host.state.actors.P.ready = true
	host.state.part_specifications.erase("P")
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "An absent actor kit does not use the compatibility alias.")
	host.state = fixture()
	host.state.part_specifications.P[1].count = 0
	host.state.part_specifications.P.append({"kind": "shaft", "teeth": 0, "half_span": 4, "count": 2})
	view.refresh()
	verify(view.get_popup().is_item_disabled(view.get_popup().get_item_index(6)), "A long-only kit does not offer a one-tile shaft.")
	view.choose_tool("place_shaft")
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "A long-only kit cannot submit a one-tile shaft.")
	host.client = "P"
	host.state = fixture()
	view.choose_tool("remove")
	view.handle_world_click([], "a")
	verify(host.calls.back() == {"action": "remove", "entity": "a"}, "Individual cog removal preserves its exact identifier.")
	view.handle_world_click([], "sy")
	verify(host.calls.back() == {"action": "remove", "entity": "sy"}, "An orphaned shaft remains selectable for removal.")
	sent = host.calls.size()
	verify(view.handle_world_click([], "wheel") and host.calls.size() == sent, "The transmission removal tool does not replace machine inspection.")
	view.choose_tool("gear")
	host.state.options.native = false
	view.refresh()
	verify(not view.visible and view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "A missing native profile hides controls and consumes its stale active click.")
	view.cancel()
	verify(not view.handle_world_click([0, 4, 4], ""), "A cancelled tool returns normal input to the scene.")
	view.free()

func _gear_sizes() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.part_specifications.P.append({"kind": "gear", "teeth": 4, "half_span": 0, "count": 1})
	var view := Controls.new()
	view.configure(host)
	view.gear_height = 4
	view.choose_tool("gear")
	view._axes.id_pressed.emit(1)
	view._heights.id_pressed.emit(1)
	view._sizes.id_pressed.emit(1)
	verify(view.gear_teeth == 4 and view.selected_axis == "y" and view.gear_height == 8,
		"Selecting the large cog retains the independent axis and height selections.")
	verify("1 carried" in view.get_popup().get_item_text(0) and "Large" in view.get_popup().get_item_text(view.get_popup().get_item_index(102)),
		"The selected large cog count comes from P's exact carried specification.")
	var original: Dictionary = host.state.duplicate(true)
	view.handle_world_click([0, 8, 4], "")
	verify(host.calls.back() == {"action": "place_gear", "center": [0, 8, 4], "axis": "y", "teeth": 4} and host.state == original,
		"A large-cog request has its actual size and a queued reply changes no confirmed inventory.")
	var sent := host.calls.size()
	host.client = "Q"
	view.refresh()
	verify(view.get_popup().is_item_disabled(0) and "0 carried" in view.get_popup().get_item_text(0),
		"An actor without the selected large cog cannot borrow P's inventory.")
	verify(view.handle_world_click([0, 8, 4], "") and host.calls.size() == sent,
		"An unavailable large cog consumes the click without issuing a request.")
	host.client = "P"
	host.mutate_allowed = false
	verify(view.handle_world_click([0, 8, 4], "") and host.calls.size() == sent,
		"A disconnected or pending shared view cannot submit a large cog.")
	host.mutate_allowed = true
	view._sizes.id_pressed.emit(0)
	view.handle_world_click([0, 8, 4], "")
	verify(view.gear_teeth == 2 and host.calls.back().get("teeth") == 2 and host.calls.size() == sent + 1,
		"Reselecting the small cog submits its own specification.")
	view.free()

func _shaft_segments() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.part_specifications.P.append({"kind": "shaft", "teeth": 0, "half_span": 4, "count": 1})
	var view := Controls.new()
	view.configure(host)
	view.gear_height = 4
	view.get_popup().id_pressed.emit(6)
	var original: Dictionary = host.state.duplicate(true)
	view.handle_world_click([0, 4, 4], "")
	verify(host.calls.back() == {"action": "place_shaft", "center": [0, 4, 4], "axis": "x", "half_span": 2} and host.state == original,
		"An individual short segment delegates its exact geometry without speculative inventory.")
	verify(view.get_popup().get_item_index(104) < 0, "The obsolete endpoint menu is absent.")
	view._axes.id_pressed.emit(2)
	view.handle_world_click([0, 4, 8], "")
	verify(host.calls.back() == {"action": "place_shaft", "center": [0, 4, 8], "axis": "z", "half_span": 2},
		"The segment uses its selected axis and one-tile specification.")
	var sent := host.calls.size()
	view.handle_world_click([0, 3, 8], "")
	host.client = "Q"
	view.refresh()
	verify(view.get_popup().is_item_disabled(view.get_popup().get_item_index(6)) and view.handle_world_click([0, 4, 8], "") and host.calls.size() == sent,
		"Off-plane clicks and an actor without the selected shaft never submit a request.")
	host.client = "P"
	host.mutate_allowed = false
	verify(view.handle_world_click([0, 4, 8], "") and host.calls.size() == sent,
		"A pending shared mutation consumes the click without placing a segment.")
	view.free()
	var long_host := HostStub.new()
	long_host.state = fixture()
	long_host.state.part_specifications.P[1].count = 0
	long_host.state.part_specifications.P.append({"kind": "shaft", "teeth": 0, "half_span": 4, "count": 1})
	var long_view := Controls.new()
	long_view.configure(long_host)
	verify(long_view.get_popup().is_item_disabled(long_view.get_popup().get_item_index(6)),
		"An obsolete long shaft cannot be selected as a one-tile part.")
	long_view.choose_tool("place_shaft")
	verify(long_view.shaft_half_span == 2, "The shaft tool always uses the one-tile specification.")
	long_view.free()

func _belt_spans() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.transmission_parts["left"] = {"kind": "shaft", "generation": 11, "center": [0, 0, 0], "axis": 2, "half_span": 2}
	host.state.transmission_parts["right"] = {"kind": "shaft", "generation": 12, "center": [12, 0, 0], "axis": 2, "half_span": 2}
	host.state.transmission_parts["middle"] = {"kind": "shaft", "generation": 14, "center": [4, 0, 0], "axis": 2, "half_span": 2}
	host.state.belt_spans = {}
	var controls := Controls.new()
	controls.configure(host)
	controls.choose_tool("belt_span")
	var before: Dictionary = host.state.duplicate(true)
	controls.handle_world_click([], "left")
	verify(host.calls == [{"action": "select_belt_shaft", "entity": "left"}], "The first endpoint submits an authoritative reach selection.")
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 1, "A queued first endpoint cannot be used before server acceptance.")
	controls.settle_belt_selection("unrelated", true)
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 1, "An unrelated outcome cannot confirm the endpoint.")
	controls.settle_belt_selection("request-1", true)
	controls.handle_world_click([], "right")
	verify(host.calls.back() == {"action": "place_selected_belt_span", "from": "left", "to": "right", "selection": "request-1"} and host.state == before,
		"Two confirmed shafts submit a span without speculative geometry or inventory.")
	controls.settle_belt_placement("request-2", true, "")
	controls.handle_world_click([], "left")
	host.state.transmission_parts.left.generation = 13
	controls.settle_belt_selection("request-3", true)
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 3, "A replaced first shaft cannot be silently reused.")
	controls.handle_world_click([], "left")
	host.mutate_allowed = false
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 4, "A pending shared request prevents a span submission.")
	host.mutate_allowed = true
	controls.settle_belt_selection("request-4", false)
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 5 and host.calls.back().action == "select_belt_shaft", "A rejected first endpoint allows a fresh first selection.")
	controls.clear_belt_selection()
	controls.handle_world_click([], "left")
	verify(host.calls.size() == 6 and host.calls.back().action == "select_belt_shaft", "A disconnected selection cannot survive into a new session.")
	var presenter := Presenter.new()
	presenter.configure(host)
	verify(_part(presenter, "span") == null, "An unconfirmed span is not rendered.")
	host.state.belt_spans["span"] = {"generation": 1, "from": "left", "to": "right"}
	presenter.refresh()
	var span := _part(presenter, "span")
	verify(span != null and span.get_node("Pick").get_meta("entity") == "span", "A confirmed span has a selectable visual.")
	verify(span.has_node("BeltLoop") and not span.has_node("BeltStrip"), "The confirmed span uses the fitted closed loop.")
	verify(_part(presenter, "left").has_node("BeltPulley") and _part(presenter, "right").has_node("BeltPulley") and _part(presenter, "middle").has_node("BeltPulley"), "Endpoint and intermediate shafts receive fitted pulleys.")
	verify(not _part(presenter, "sx").has_node("BeltPulley"), "An unrelated shaft never acquires a pulley.")
	verify(_part(presenter, "left").get_node("Pick").get_meta("entity") == "left" and _part(presenter, "right").get_node("Pick").get_meta("entity") == "right", "Both shaft picks remain independently selectable.")
	var original_parts: Dictionary = host.state.transmission_parts.duplicate(true)
	for id in ["left", "right", "middle"]:
		var old: Array = host.state.transmission_parts[id].center
		host.state.transmission_parts[id].center = [0, old[1], old[0]]
		host.state.transmission_parts[id].axis = 0
	presenter.refresh()
	span = _part(presenter, "span")
	verify(span.has_node("BeltLoop") and is_equal_approx(span.get_node("BeltLoop").rotation.y, -PI / 2.0) and _part(presenter, "middle").has_node("BeltPulley"), "The other horizontal axis rotates the fitted loop and keeps intermediate pulleys.")
	host.state.transmission_parts = original_parts
	presenter.refresh()
	var raw := {"raw": 1, "products": 0, "work_lots": []}
	var product := {"raw": 0, "products": 1, "work_lots": []}
	var work := {"raw": 0, "products": 0, "work_lots": [{"id": 7}]}
	host.state.belt_spans["span"].slots = [raw, null, product, work]
	host.state.belt_spans["span"].phase = 0
	presenter.refresh()
	span = _part(presenter, "span")
	var item0 := _belt_item(span, 0)
	var item2 := _belt_item(span, 2)
	var item3 := _belt_item(span, 3)
	verify(item0 != null and item0.get_meta("belt_item") == "raw" and is_equal_approx(item0.position.x, -2.475),
		"A confirmed raw unit is rendered on its exact first endpoint tile.")
	verify(_belt_item(span, 1) == null and item2 != null and item2.get_meta("belt_item") == "product" and item3 != null and item3.get_meta("belt_item") == "work",
		"Empty positions remain empty and distinct confirmed item types retain their positions.")
	host.state.belt_spans["span"].phase = 2048
	presenter.refresh()
	span = _part(presenter, "span")
	verify(is_equal_approx(_belt_item(span, 0).position.x, -1.65), "A free slot shows the confirmed half-tile forward phase.")
	verify(is_equal_approx(_belt_item(span, 2).position.x, 0.825) and is_equal_approx(_belt_item(span, 3).position.x, 2.475), "A chain blocked at the end does not visually pass through its neighbor.")
	host.state.belt_spans["span"].phase = -2048
	presenter.refresh()
	span = _part(presenter, "span")
	verify(is_equal_approx(_belt_item(span, 0).position.x, -2.475) and is_equal_approx(_belt_item(span, 2).position.x, 0.0) and is_equal_approx(_belt_item(span, 3).position.x, 1.65), "Reverse phase moves an unblocked chain together while the endpoint stays bounded.")
	verify(Presenter.belt_slot_fraction([raw, null], 0, 0.5) == 0.0 and Presenter.belt_slot_fraction([raw, null], 0, 4096) == 0.0, "Malformed and out-of-range phases do not invent motion.")
	var session := Session.new()
	session.context = host.state.context
	session._ready_for_commands = true
	host.state.revision = 1
	host.state.order = 1
	session._apply_frame({"context": host.state.context, "serial": 1, "snapshot": host.state})
	var remote := HostStub.new()
	remote.state = session.projection()
	var remote_presenter := Presenter.new()
	remote_presenter.configure(remote)
	verify(_belt_item(_part(remote_presenter, "span"), 2).get_meta("belt_item") == "product",
		"A read-only Session frame preserves the same confirmed belt contents.")
	host.state.belt_spans["span"].slots = [null, raw, product, work]
	presenter.refresh()
	span = _part(presenter, "span")
	verify(_belt_item(span, 0) == null and _belt_item(span, 1).get_meta("belt_item") == "raw",
		"Only the next confirmed snapshot moves the displayed item to its new slot.")
	verify(_belt_item(_part(remote_presenter, "span"), 0) != null,
		"An older shared snapshot does not acquire the next local item position.")
	var older: Dictionary = remote.state.duplicate(true)
	host.state.revision = 2
	host.state.order = 2
	session._apply_frame({"context": host.state.context, "serial": 2, "snapshot": host.state})
	remote.state = session.projection()
	remote_presenter.refresh()
	verify(_belt_item(_part(remote_presenter, "span"), 1).get_meta("belt_item") == "raw",
		"A newer shared frame renders the updated confirmed slot.")
	session._apply_frame({"context": host.state.context, "serial": 1, "snapshot": older})
	verify(session.projection().belt_spans["span"].slots[1] == raw,
		"An out-of-order shared frame cannot roll the item back.")
	remote_presenter.free()
	session.free()
	controls.choose_tool("remove")
	controls.handle_world_click([], "span")
	verify(host.calls.back() == {"action": "remove_belt_span", "entity": "span"}, "Belt removal delegates its confirmed identity.")
	host.state.belt_spans.clear()
	presenter.refresh()
	verify(_part(presenter, "span") == null, "A confirmed removal clears the visual.")
	verify(not _part(presenter, "left").has_node("BeltPulley") and not _part(presenter, "middle").has_node("BeltPulley"), "Removing the span removes its fitted pulleys.")
	controls.free()
	presenter.free()

func _belt_retry() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.transmission_parts["left"] = {"kind": "shaft", "generation": 1, "center": [0, 0, 0], "axis": 2, "half_span": 2}
	host.state.transmission_parts["right"] = {"kind": "shaft", "generation": 2, "center": [12, 0, 0], "axis": 2, "half_span": 2}
	var controls := Controls.new()
	controls.configure(host)
	controls.choose_tool("belt_span")
	controls.handle_world_click([], "left")
	controls.settle_belt_selection("request-1", true)
	controls.handle_world_click([], "right")
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 2, "A pending belt placement cannot be submitted twice.")
	controls.settle_belt_placement("unrelated", false, "out_of_reach")
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 2, "An unrelated result cannot release a pending placement.")
	var shared := SharedSettlement.new()
	shared.session = ReadySession.new()
	shared.transmission_controls = controls
	shared.state = {"context": "helper-fixture", "revision": 1, "order": 1}
	shared.pending_actions = {"request-2": {"action": {"action": "place_selected_belt_span"},
		"outcome": {"context": "helper-fixture", "revision": 2, "order": 2, "accepted": false, "reason": "out_of_reach"}}}
	shared._settle_pending()
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 2, "A shared refusal waits for its confirmed worksite before allowing retry.")
	shared.state.revision = 2
	shared.state.order = 2
	shared._settle_pending()
	controls.handle_world_click([], "right")
	verify(host.calls.back() == {"action": "place_selected_belt_span", "from": "left", "to": "right", "selection": "request-1"},
		"A refused second endpoint reuses the confirmed first selection.")
	controls.settle_belt_placement("request-3", true, "")
	controls.handle_world_click([], "right")
	verify(host.calls.back() == {"action": "select_belt_shaft", "entity": "right"}, "Successful placement consumes the selection.")
	controls.settle_belt_selection("request-4", true)
	controls.handle_world_click([], "left")
	controls.settle_belt_placement("request-5", false, "invalid_belt_selection")
	controls.handle_world_click([], "left")
	verify(host.calls.back() == {"action": "select_belt_shaft", "entity": "left"}, "An invalid authority selection starts over.")
	controls.choose_tool("belt_span")
	host.reply_mode = "accepted"
	controls.handle_world_click([], "left")
	host.reply_mode = "refused"
	controls.handle_world_click([], "right")
	host.reply_mode = "accepted"
	controls.handle_world_click([], "right")
	verify(host.calls.back().action == "place_selected_belt_span" and host.calls.back().selection == "request-7",
		"A synchronous refusal preserves the first selection for an ordinary local retry.")
	controls.handle_world_click([], "right")
	verify(host.calls.back().action == "select_belt_shaft", "A synchronous successful placement clears the selection.")
	shared.transmission_controls = null
	shared.free()
	controls.free()

func _span_guidance() -> void:
	var view := SharedSettlement.new()
	view.legacy_fixture = false
	view.client = "P"
	view.state = fixture()
	view.state.entities = {
		"collector": {"kind": "collector", "center": [-4, 0, 0]},
		"press": {"kind": "processor", "center": [16, 0, 0]},
		"wheel": {"kind": "wheel", "center": [0, 0, -4]}}
	view.state.transmission_parts = {
		"a0": {"kind": "shaft", "center": [0, 0, 0], "axis": 2},
		"a1": {"kind": "shaft", "center": [4, 0, 0], "axis": 2},
		"b0": {"kind": "shaft", "center": [8, 0, 0], "axis": 2},
		"b1": {"kind": "shaft", "center": [12, 0, 0], "axis": 2}}
	var empty := [null, null]
	view.state.belt_spans = {"first": {"from": "a0", "to": "a1", "slots": empty.duplicate()},
		"second": {"from": "b0", "to": "b1", "slots": [{"raw": 1, "products": 0, "work_lots": []}, null]}}
	view.state.motion = {"a0": {"state": "rotating", "numerator": -1},
		"b0": {"state": "rotating", "numerator": -1},
		"collector": {"state": "rotating", "numerator": 1},
		"press": {"state": "rotating", "numerator": 1}}
	view.state.links = []
	view.state.power_enabled = true
	view.state.inventories = {"P": 0}
	view.state.stock = {"source": 0, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0}
	var kinds := {"collector": true, "processor": true, "wheel": true}
	var route: Dictionary = view._guided_span_routes()
	verify(route.physical and route.powered and route.cargo and view._guided_step(kinds).text.begins_with("Follow a blank"),
		"A powered two-span line and its in-flight material need no legacy belt or manual links.")
	view.state.motion.b0.numerator = 1
	verify(view._guided_span_routes().physical and not view._guided_span_routes().powered and "direction" in view._guided_step(kinds).text,
		"A reversed downstream span cannot be advertised as a working route.")
	view.state.motion.b0.state = "stalled"
	verify(not view._guided_span_routes().powered and "Power the belt" in view._guided_step(kinds).text,
		"A stalled belt produces a power instruction.")
	view.state.motion.b0.state = "rotating"
	view.state.motion.b0.numerator = -1
	view.state.entities.press.center = [20, 0, 0]
	verify(not view._guided_span_routes().physical and "Connect the collector" in view._guided_step(kinds).text,
		"A separated press is not presented as connected.")
	view.state.entities.press.center = [16, 0, 0]
	view.state.belt_spans.second.from = "b1"
	view.state.belt_spans.second.to = "b0"
	view.state.motion.b1 = {"state": "rotating", "numerator": -1}
	verify(view._guided_span_routes().powered, "Reversing endpoint order preserves the actual travel direction.")
	for entity: Dictionary in view.state.entities.values():
		var center: Array = entity.center
		entity.center = [0, center[0], center[0]]
	for part: Dictionary in view.state.transmission_parts.values():
		var center: Array = part.center
		part.center = [0, center[0], center[0]]
		part.axis = 0
	for id in ["a0", "b0", "b1"]:
		view.state.motion[id].numerator = 1
	verify(view._guided_span_routes().physical and view._guided_span_routes().powered,
		"The same route is recognized on inclined belts with X-axis shafts.")
	view.state.transmission_parts.b1.center = [0, 12, 16]
	verify(not view._guided_span_routes().physical, "A disconnected sloped endpoint does not invent a route.")
	view.state.belt_spans.clear()
	kinds.erase("processor")
	verify("two parallel shafts" in view._guided_step(kinds).text and view._guided_step(kinds).tool == "drive",
		"The native opening introduces shaft endpoints for a new belt.")
	view.free()

func _nonhorizontal_presentation() -> void:
	var raw := {"raw": 1, "products": 0, "work_lots": []}
	for case in [
		{"axis": 2, "first": [0, 8, 0], "middle": [4, 12, 0], "last": [8, 16, 0], "cargo": true},
		{"axis": 0, "first": [0, 16, 0], "middle": [0, 12, 4], "last": [0, 8, 8], "cargo": true},
		{"axis": 2, "first": [0, 8, 0], "middle": [0, 12, 0], "last": [0, 16, 0], "cargo": false},
		{"axis": 1, "first": [0, 8, 0], "middle": [4, 8, 0], "last": [8, 8, 0], "cargo": false}]:
		var host := HostStub.new()
		host.state = fixture()
		host.state.transmission_parts = {}
		for id in ["first", "middle", "last"]:
			host.state.transmission_parts[id] = {"kind": "shaft", "generation": 1, "center": case[id], "axis": case.axis, "half_span": 2}
		host.state.belt_spans = {"span": {"generation": 1, "from": "first", "to": "last", "slots": [raw, null, null], "phase": 2048}}
		var controls := Controls.new()
		controls.configure(host)
		controls.choose_tool("belt_span")
		var confirmed: Dictionary = host.state.duplicate(true)
		controls.handle_world_click([], "first")
		controls.settle_belt_selection("request-1", true)
		controls.handle_world_click([], "last")
		verify(host.calls.size() == 2 and host.calls[0] == {"action": "select_belt_shaft", "entity": "first"} and host.calls[1] == {"action": "place_selected_belt_span", "from": "first", "to": "last", "selection": "request-1"} and host.state == confirmed, "Endpoint controls submit the path without inventing confirmed state.")
		controls.free()
		var presenter := Presenter.new()
		presenter.configure(host)
		var span := _part(presenter, "span")
		verify(span != null and span.has_node("BeltLoop"), "A confirmed nonhorizontal path renders a loop.")
		if span == null or not span.has_node("BeltLoop"):
			presenter.free()
			continue
		var loop: Node3D = span.get_node("BeltLoop")
		var near_rail: MeshInstance3D = loop.get_node_or_null("SpanFrameRailN")
		var far_rail: MeshInstance3D = loop.get_node_or_null("SpanFrameRailP")
		verify(near_rail != null and far_rail != null
			and loop.has_node("SpanFrameSeatNN") and loop.has_node("SpanFrameSeatPP")
			and near_rail.get_meta("span_frame_role", "") == "Rail"
			and far_rail.get_meta("span_frame_role", "") == "Rail"
			and near_rail.position.z < -Assets.SPAN_HALF_WIDTH
			and far_rail.position.z > Assets.SPAN_HALF_WIDTH,
			"The same loop carries its fixed outboard frame through horizontal and inclined orientations.")
		var start := Presenter.world_center(case.first)
		var finish := Presenter.world_center(case.last)
		var axis := Vector3.ZERO
		axis[case.axis] = 1.0
		verify(absf(loop.basis.x.dot((finish - start).normalized())) > 0.999 and absf(loop.basis.z.dot(axis)) > 0.999 and loop.basis.determinant() > 0.999, "The loop follows the path and rotates about its shaft axis.")
		verify(_part(presenter, "middle").has_node("BeltPulley") and span.get_node("Pick").basis.is_equal_approx(loop.basis), "The intermediate pulley and selection body follow the path.")
		var item := _belt_item(span, 0)
		if case.cargo:
			verify(item != null and (span.position + item.position).is_equal_approx(start.lerp(finish, 0.25) + Vector3.UP * 0.24), "Inclined cargo follows the confirmed half-slot phase.")
		else:
			verify(item == null, "Power-only vertical and sideways paths do not display cargo.")
		var session := Session.new()
		session.context = host.state.context
		session._ready_for_commands = true
		host.state.revision = 1
		host.state.order = 1
		session._apply_frame({"context": host.state.context, "serial": 1, "snapshot": host.state})
		var remote := HostStub.new()
		remote.state = session.projection()
		var remote_presenter := Presenter.new()
		remote_presenter.configure(remote)
		var remote_span := _part(remote_presenter, "span")
		verify(remote_span != null and remote_span.has_node("BeltLoop") and remote_span.get_node("BeltLoop").basis.is_equal_approx(loop.basis) and (_belt_item(remote_span, 0) != null) == case.cargo, "A confirmed Session frame preserves the path orientation and cargo presentation.")
		remote_presenter.free()
		session.free()
		var original_basis := loop.basis
		host.state.belt_spans.span.from = "last"
		host.state.belt_spans.span.to = "first"
		presenter.refresh()
		span = _part(presenter, "span")
		verify(span.get_node("BeltLoop").basis.is_equal_approx(original_basis), "Endpoint order does not flip the loop.")
		presenter.free()

func _belt_picking() -> void:
	for case in [
		{"axis": 2, "first": [0, 8, 0], "middle": [4, 12, 0], "last": [8, 16, 0]},
		{"axis": 0, "first": [0, 16, 0], "middle": [0, 12, 4], "last": [0, 8, 8]},
		{"axis": 2, "first": [0, 8, 0], "middle": [4, 8, 0], "last": [8, 8, 0]},
		{"axis": 2, "first": [0, 8, 0], "middle": [0, 12, 0], "last": [0, 16, 0]},
		{"axis": 1, "first": [0, 8, 0], "middle": [4, 8, 0], "last": [8, 8, 0]}]:
		var host := HostStub.new()
		host.state = fixture()
		host.state.transmission_parts = {}
		for id in ["first", "middle", "last"]:
			host.state.transmission_parts[id] = {"kind": "shaft", "generation": 1, "center": case[id], "axis": case.axis, "half_span": 2}
		host.state.belt_spans = {"span": {"generation": 1, "from": "first", "to": "last"}}
		var presenter := Presenter.new()
		root.add_child(presenter)
		presenter.configure(host)
		await physics_frame
		await physics_frame
		var span := _part(presenter, "span")
		var normal: Vector3 = span.get_node("BeltLoop").basis.y
		var first := Presenter.world_center(case.first)
		var middle := Presenter.world_center(case.middle)
		for probe in [{"point": first, "id": "first"}, {"point": middle, "id": "middle"},
			{"point": first.lerp(middle, 0.5), "id": "span"}]:
			var point: Vector3 = probe.point
			var ray := PhysicsRayQueryParameters3D.create(point + normal * 2.0, point - normal * 2.0, Geometry.PICK_LAYER)
			var hit := presenter.get_world_3d().direct_space_state.intersect_ray(ray)
			verify(not hit.is_empty() and hit.collider.get_meta("entity", "") == probe.id, "A selection ray reaches the intended %s on the belt path." % probe.id)
		presenter.queue_free()
		await process_frame

func _cog_axles() -> void:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for axis in range(3):
		for next_kind in ["gear", "shaft"]:
			var host := HostStub.new()
			host.state = fixture()
			var next_center := [0, 0, 0]
			next_center[axis] = 4
			host.state.transmission_parts = {
				"first": {"kind": "gear", "generation": 1, "center": [0, 0, 0], "axis": axis, "teeth": 2},
				"next": {"kind": next_kind, "generation": 2, "center": next_center, "axis": axis, "teeth": 4, "half_span": 2}}
			host.state.belt_spans = {}
			host.state.engagements = []
			var presenter := Presenter.new()
			root.add_child(presenter)
			presenter.configure(host)
			await physics_frame
			await physics_frame
			var first := _part(presenter, "first")
			var next := _part(presenter, "next")
			var first_shaft: CylinderMesh = first.get_node("Shaft").mesh
			var next_shaft: CylinderMesh = next.get_node("Shaft").mesh
			verify(is_equal_approx(first_shaft.height, Geometry.PITCH) and is_equal_approx(next_shaft.height, Geometry.PITCH)
				and (first.position + axes[axis] * first_shaft.height / 2.0).is_equal_approx(next.position - axes[axis] * next_shaft.height / 2.0),
				"Adjacent cog and %s integral axles meet exactly at their common tile face." % next_kind)
			var normal := Vector3.UP if axis != 1 else Vector3.RIGHT
			for probe in [{"part": first, "id": "first"}, {"part": next, "id": "next"}]:
				var point: Vector3 = probe.part.position + axes[axis] * 0.5
				var ray := PhysicsRayQueryParameters3D.create(point + normal * 0.4, point - normal * 0.4, Geometry.PICK_LAYER)
				var hit := presenter.get_world_3d().direct_space_state.intersect_ray(ray)
				verify(not hit.is_empty() and hit.collider.get_meta("entity", "") == probe.id,
					"The exposed axle selects its own confirmed %s tile." % probe.id)
			presenter.queue_free()
			await process_frame

func _belt_item(span: Node3D, slot: int) -> Node3D:
	if span == null:
		return null
	for child: Node in span.get_children():
		if child.get_meta("belt_slot", -1) == slot:
			return child
	return null

func _part(view: Node3D, id: String) -> Node3D:
	for child in view.get_children():
		if child.get_meta("entity", "") == id:
			return child
	return null

func _marks(view: Node3D) -> int:
	var count := 0
	for child in view.get_children():
		if child.has_meta("from"):
			count += 1
	return count

func _presentation() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var before: Dictionary = host.state.duplicate(true)
	var view := Presenter.new()
	view.configure(host)
	var a := _part(view, "a")
	var b := _part(view, "b")
	verify(a != null and b != null and a.position.is_equal_approx(Vector3(-1.65, 2.475, 1.65)) and b.position.is_equal_approx(Vector3(0, 2.475, 1.65)), "Quarter-grid centers map to the declared world anchors.")
	verify(a.get_node("ConfirmedDirection").get_meta("sign") == 1 and b.get_node("ConfirmedDirection").get_meta("sign") == -1, "Opposite signed rates produce opposite direction marks without a phase clock.")
	verify(_marks(view) == 1, "Only the confirmed engagement produces a contact mark.")
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var firsts := [Vector3(0, 0.825, 1.65), Vector3(0, 0.825, 0), Vector3(0, 0.825, 0)]
	var lasts := [Vector3(1.65, 0.825, 1.65), Vector3(0, 2.475, 0), Vector3(0, 0.825, 1.65)]
	for index in range(3):
		var part := _part(view, ["sx", "sy", "sz"][index])
		var mesh: CylinderMesh = part.get_node("Shaft").mesh
		verify(part.basis.y.is_equal_approx(axes[index]) and is_equal_approx(part.basis.determinant(), 1.0), "Each shaft uses a proper axis basis, including the vertical case.")
		verify((part.position - part.basis.y * mesh.height / 2).is_equal_approx(firsts[index]) and (part.position + part.basis.y * mesh.height / 2).is_equal_approx(lasts[index]), "Shaft endpoints match independent literal world coordinates.")
	verify(not _part(view, "sz").has_node("ConfirmedDirection"), "Stalled state is not animated or advertised as rotation.")
	for child in view.get_children():
		if child.has_meta("entity"):
			var body: StaticBody3D = child.get_node("Pick")
			verify(body.collision_layer == 4 and body.collision_mask == 0 and body.get_meta("entity") == child.get_meta("entity"), "Pick geometry cannot become actor or machine collision authority.")
	var first_id: int = a.get_instance_id()
	view.refresh()
	verify(_part(view, "a").get_instance_id() == first_id and host.state == before and host.calls.is_empty(), "An unchanged refresh reuses geometry and changes no projection or request.")
	for axis in range(3):
		host.state.transmission_parts.a.axis = axis
		view.refresh()
		verify(_part(view, "a").basis.y.is_equal_approx(axes[axis]), "Gear planes follow all three confirmed axes.")
	host.state.engagements = []
	view.refresh()
	verify(_marks(view) == 0, "Proximity alone never invents engagement.")
	host.state.transmission_parts.bad = {"kind": "gear", "center": [0, 0, 0], "axis": true, "teeth": 2}
	view.refresh()
	verify(_part(view, "bad") == null, "Malformed axis data does not create pick geometry.")
	host.state.options.native = false
	view.refresh()
	verify(not view.visible and view.get_child_count() == 0, "A scripted projection cannot retain old native geometry.")
	view.free()

func _belt_surface_motion() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.transmission_parts = {
		"a0": {"kind": "shaft", "generation": 10, "center": [0, 0, 0], "axis": 2, "half_span": 2},
		"a1": {"kind": "shaft", "generation": 11, "center": [8, 0, 0], "axis": 2, "half_span": 2},
		"b0": {"kind": "shaft", "generation": 12, "center": [0, 0, 8], "axis": 2, "half_span": 2},
		"b1": {"kind": "shaft", "generation": 13, "center": [8, 0, 8], "axis": 2, "half_span": 2}}
	host.state.motion = {"a0": {"state": "rotating", "numerator": 1, "denominator": 1},
		"a1": {"state": "rotating", "numerator": 1, "denominator": 1},
		"b0": {"state": "rotating", "numerator": -2, "denominator": 1},
		"b1": {"state": "rotating", "numerator": -2, "denominator": 1}}
	host.state.belt_spans = {"belt-a": {"from": "a0", "to": "a1"}, "belt-b": {"from": "b0", "to": "b1"}}
	var before: Dictionary = host.state.duplicate(true)
	var view := Presenter.new()
	view.configure(host)
	var loop_a: MeshInstance3D = _part(view, "belt-a").get_node("BeltLoop")
	var loop_b: MeshInstance3D = _part(view, "belt-b").get_node("BeltLoop")
	var material_a := loop_a.material_override as StandardMaterial3D
	var material_b := loop_b.material_override as StandardMaterial3D
	verify(material_a != material_b, "Each belt has its own surface phase without changing the cached rubber material.")
	view.advance_visual_motion(0.001)
	verify(is_equal_approx(view.visual_rotation("a0") * Assets.SPAN_OUTER_RADIUS,
		Geometry.PITCH * 0.001 / 0.45), "The pulley rim travels one tile per native tick at unit shaft rate.")
	var a_delta := wrapf(material_a.uv1_offset.x, -0.5, 0.5)
	var b_delta := wrapf(material_b.uv1_offset.x, -0.5, 0.5)
	verify(a_delta > 0.0 and b_delta < 0.0 and is_equal_approx(b_delta, -2.0 * a_delta),
		"Belt surfaces follow independent signed shaft rates.")
	var before_long_frame := view.visual_rotation("a0")
	var surface_before_long_frame := material_a.uv1_offset.x
	var factor: float = _part(view, "belt-a").get_meta("belt_uv_factor")
	view.advance_visual_motion(0.25)
	var expected_step := Presenter.VISUAL_RADIANS_PER_SECOND * 0.25
	verify(is_equal_approx(view.visual_rotation("a0") - before_long_frame, expected_step),
		"A long frame advances the shaft for the full elapsed duration.")
	verify(is_equal_approx(material_a.uv1_offset.x, fposmod(surface_before_long_frame + expected_step * factor, 1.0)),
		"A long frame advances the belt surface at the same confirmed shaft speed.")
	var prior_a := material_a.uv1_offset.x
	host.motion_fresh = false
	view.advance_visual_motion(0.1)
	verify(is_equal_approx(material_a.uv1_offset.x, prior_a), "A stale view cannot invent belt movement.")
	host.motion_fresh = true
	host.state.motion.a0 = {"state": "stalled", "numerator": 0, "denominator": 1}
	view.refresh()
	material_a = _part(view, "belt-a").get_node("BeltLoop").material_override
	verify(is_equal_approx(material_a.uv1_offset.x, prior_a), "A rebuilt stopped belt preserves its cosmetic phase.")
	view.advance_visual_motion(0.1)
	verify(is_equal_approx(material_a.uv1_offset.x, prior_a), "A stalled belt surface remains still.")
	verify(before.transmission_parts == host.state.transmission_parts and host.calls.is_empty(),
		"Cosmetic belt motion does not submit commands or alter transmission geometry.")
	view.free()
	for example in [
		{"axis": 2, "end": [8, 0, 0], "sign": 1.0},
		{"axis": 0, "end": [0, 0, 8], "sign": -1.0},
		{"axis": 2, "end": [8, 8, 0], "sign": 1.0},
		{"axis": 2, "end": [0, 8, 0], "sign": 1.0},
		{"axis": 1, "end": [8, 0, 0], "sign": 1.0}]:
		for reversed in [false, true]:
			var oriented := HostStub.new()
			oriented.state = fixture()
			oriented.state.transmission_parts = {
				"first": {"kind": "shaft", "generation": 1, "center": [0, 0, 0], "axis": example.axis, "half_span": 2},
				"last": {"kind": "shaft", "generation": 2, "center": example.end, "axis": example.axis, "half_span": 2}}
			oriented.state.motion = {"first": {"state": "rotating", "numerator": 1, "denominator": 1},
				"last": {"state": "rotating", "numerator": 1, "denominator": 1}}
			oriented.state.belt_spans = {"span": {"from": "last" if reversed else "first", "to": "first" if reversed else "last"}}
			var presenter := Presenter.new()
			presenter.configure(oriented)
			var loop: MeshInstance3D = _part(presenter, "span").get_node("BeltLoop")
			presenter.advance_visual_motion(0.001)
			var offset: float = (loop.material_override as StandardMaterial3D).uv1_offset.x
			verify(wrapf(offset, -0.5, 0.5) * example.sign > 0.0,
				"Surface travel respects axle orientation and is independent of endpoint order.")
			presenter.free()

func _cache_regression() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var view := Presenter.new()
	view.configure(host)
	var first_id: int = _part(view, "a").get_instance_id()
	var pick_id: int = _part(view, "a").get_node("Pick").get_instance_id()
	view.refresh()
	verify(_part(view, "a").get_instance_id() == first_id and _part(view, "a").get_node("Pick").get_instance_id() == pick_id, "An unchanged refresh preserves both mesh subtree and pick-body identities.")
	host.state.parts.gear = 88
	view.refresh()
	verify(_part(view, "a").get_instance_id() == first_id, "An unrelated compatibility counter does not rebuild transmission geometry.")
	host.state.motion.a.numerator = -1
	view.refresh()
	verify(_part(view, "a").get_instance_id() != first_id and _part(view, "a").get_node("ConfirmedDirection").get_meta("sign") == -1, "Changed signed motion refreshes the confirmed direction mark.")
	host.state.motion.a.state = "unpowered"
	host.state.motion.a.numerator = 0
	view.refresh()
	verify(not _part(view, "a").has_node("ConfirmedDirection"), "Stopping confirmed motion removes the rotation indication.")
	host.state.transmission_parts.a.center = [-3, 4, 4]
	view.refresh()
	verify(_part(view, "a").position.is_equal_approx(Vector3(-1.2375, 2.475, 1.65)), "A changed center refreshes its world-space geometry.")
	first_id = _part(view, "a").get_instance_id()
	host.state.context = "another-context"
	view.refresh()
	verify(_part(view, "a").get_instance_id() != first_id, "A new confirmed context does not retain old pick identities.")
	host.state.engagements = []
	view.refresh()
	verify(_marks(view) == 0, "A changed engagement catalogue removes the old contact mark.")
	var before: Dictionary = host.state.duplicate(true)
	view.refresh()
	verify(host.state == before and host.calls.is_empty(), "Cache refresh reads do not mutate projection or submit a command.")
	view.free()

func _direction_basis() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var view := Presenter.new()
	view.configure(host)
	for axis in range(3):
		host.state.transmission_parts.a.axis = axis
		host.state.transmission_parts.b.axis = axis
		view.refresh()
		for id in ["a", "b"]:
			var part := _part(view, id)
			var segment: MeshInstance3D = part.get_node("ConfirmedDirection").get_child(0)
			var radial := segment.position
			radial.y = 0
			var signed_normal: float = part.basis.y.dot((part.basis * radial.normalized()).cross(part.basis * segment.basis.y))
			var sign_value: int = host.state.motion[id].numerator
			verify(signed_normal * float(sign_value) > 0.9, "The actual direction arc follows signed right-hand rotation on every declared axis.")
	view.free()

func _tool_guidance() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.messages.append("Previous machine-placement advice.")
	var view := Controls.new()
	view.configure(host)
	var before: Dictionary = host.state.duplicate(true)
	for choice in [[1, "cogwheel"], [6, "shaft tile"], [4, "remove"], [5, "construction tool"]]:
		var count: int = host.messages.size()
		view.get_popup().id_pressed.emit(choice[0])
		verify(host.messages.size() == count + 1 and str(host.messages.back()).contains(choice[1]),
			"Popup selection replaces stale advice for operation " + str(choice[0]))
	verify(host.calls.is_empty() and host.state == before, "Popup advice sends no request and changes no confirmed facts.")
	host.mutate_allowed = false
	var count: int = host.messages.size()
	view.get_popup().id_pressed.emit(1)
	verify(host.messages.size() == count, "An unusable view preserves connection advice.")
	print(JSON.stringify({"popup_messages": host.messages, "requests": host.calls.size()}))
	view.free()

func _loose_material() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.dropped_material = [{"center": [2, 0, 4], "raw": 3, "products": 0, "work_lots": []}]
	var menu := LooseControls.new()
	menu.configure(host)
	verify(menu.visible and not menu.disabled, "A confirmed loose stack is offered to the ready actor.")
	menu._open()
	var before: Dictionary = host.state.duplicate(true)
	menu._choose(0)
	verify(host.calls == [{"action": "pickup_material", "center": [2, 0, 4], "expected": {"raw": 3, "products": 0, "work_lots": []}}] and host.state == before,
		"Pickup submits the exact confirmed location without speculatively changing custody.")
	menu._open()
	host.state.context = "another-world"
	menu._choose(0)
	verify(host.calls.size() == 1, "A menu opened for another world cannot submit a stale selection.")
	host.state.context = "helper-fixture"
	menu._open()
	host.state.dropped_material = []
	menu._choose(0)
	verify(host.calls.size() == 1, "A vanished stack cannot be selected from an old menu.")
	host.state.dropped_material = [{"center": [2, 0, 4], "raw": 3, "products": 0, "work_lots": []}]
	menu._open()
	host.mutate_allowed = false
	menu._choose(0)
	verify(host.calls.size() == 1, "A shared mutation barrier prevents pickup submission.")
	var presenter := Presenter.new()
	presenter.configure(host)
	var blank := presenter.get_node_or_null("LooseBlank")
	verify(blank is MeshInstance3D and blank.position == Presenter.world_center([2, 0, 4]),
		"The confirmed stack is rendered at its world location without requiring the belt to exist.")
	host.mutate_allowed = true
	for drop in [{"center": [2, 0, 4], "raw": 0, "products": 1, "work_lots": []},
		{"center": [2, 0, 4], "raw": 0, "products": 0, "work_lots": [{"id": 7}]}]:
		host.state.dropped_material = [drop]
		presenter.refresh()
		menu._open()
		verify(menu.get_popup().item_count == 1 and not presenter.get_node_or_null("LooseBlank"), "A plate or workpiece has a loose-material offer and a distinct visual.")
		menu._choose(0)
		var expected: Dictionary = drop.duplicate(true)
		expected.erase("center")
		verify(host.calls.back() == {"action": "pickup_material", "center": [2, 0, 4], "expected": expected}, "Typed loose cargo uses the confirmed pickup request.")
		menu._open()
		host.state.dropped_material = [{"center": [2, 0, 4], "raw": 1, "products": 0, "work_lots": []}]
		var count := host.calls.size()
		menu._choose(0)
		verify(host.calls.size() == count, "A replacement at the same location cannot use an outdated menu offer.")
	host.state.dropped_material = []
	presenter.refresh()
	verify(presenter.get_node_or_null("LooseBlank") == null, "The presentation removes a picked-up stack after confirmed state changes.")
	menu.free()
	presenter.free()
	var session := Session.new()
	session.context = "helper-fixture"
	session._ready_for_commands = true
	host.state.dropped_material = [{"center": [2, 0, 4], "raw": 3, "products": 0, "work_lots": []}]
	host.state.revision = 1
	host.state.order = 1
	session._apply_frame({"context": "helper-fixture", "serial": 1, "snapshot": host.state})
	verify(session.projection().dropped_material == host.state.dropped_material,
		"The read-only Session frame retains the server's loose-material projection.")
	var mixed := {"center": [2, 0, 4], "raw": 1, "products": 1, "work_lots": [{"id": 7, "recipe_input": 1, "cycle_ticks": 2, "remaining": 1, "completed_subticks": 123}]}
	host.state.dropped_material = [mixed]
	host.state.revision = 2
	host.state.order = 2
	session._apply_frame({"context": "helper-fixture", "serial": 2, "snapshot": host.state})
	var remote := HostStub.new()
	remote.state = session.projection()
	var remote_menu := LooseControls.new()
	remote_menu.configure(remote)
	remote_menu._open()
	remote_menu._choose(0)
	var expected := mixed.duplicate(true)
	expected.erase("center")
	verify(remote.state.dropped_material == [mixed] and remote.calls == [{"action": "pickup_material", "center": [2, 0, 4], "expected": expected}], "A Session projection preserves a mixed stack and submits its exact confirmed work identity.")
	remote_menu.free()
	host.state.dropped_material = []
	host.state.revision = 3
	host.state.order = 3
	session._apply_frame({"context": "helper-fixture", "serial": 3, "snapshot": host.state})
	verify(session.projection().dropped_material.is_empty(), "A later confirmed Session frame removes the picked-up stack.")
	session.free()

func _mechanical_collision_geometry() -> void:
	var state := {"options": {"native": true}, "transmission_parts": {
		"a": {"kind": "shaft", "center": [0, 0, 0], "axis": 2, "half_span": 2},
		"b": {"kind": "shaft", "center": [8, 0, 0], "axis": 2, "half_span": 2},
		"c": {"kind": "gear", "center": [0, 4, 4], "axis": 0, "teeth": 4}},
		"belt_spans": {"belt": {"from": "a", "to": "b"}}}
	var result := Geometry.mechanical_boxes(state)
	verify(result.accepted and result.boxes.size() == 4, "Every confirmed mechanical part receives exactly one body.")
	verify(result.boxes.a.center.is_equal_approx(Vector3(0, 0.825, 0)) and result.boxes.a.size.is_equal_approx(Vector3(0.2, 0.2, 1.65)), "Shaft bounds match Host placement dimensions.")
	verify(result.boxes.c.center.is_equal_approx(Vector3(0, 2.475, 1.65)) and result.boxes.c.size.is_equal_approx(Vector3(0.08, 1.65, 1.65)), "Cog bounds use the axle plane and shared height origin.")
	verify(result.boxes.c.axle_size.is_equal_approx(Vector3(1.65, 0.2, 0.2)), "The cog's separate axle reaches exactly its tile faces.")
	verify(result.boxes.belt.center.is_equal_approx(Vector3(1.65, 0.825, 0)) and result.boxes.belt.size.is_equal_approx(Vector3(4.95, 0.3, 0.6)), "Belt bounds cover every tile including both pulleys.")
	var reversed: Dictionary = state.duplicate(true)
	reversed.belt_spans.belt = {"from": "b", "to": "a"}
	verify(Geometry.mechanical_boxes(reversed).boxes.belt == result.boxes.belt, "Reversing endpoints preserves physical bounds.")
	var moved: Dictionary = state.duplicate(true)
	moved.transmission_parts.b.center = [0, 0, 8]
	moved.transmission_parts.a.axis = 0
	moved.transmission_parts.b.axis = 0
	var rotated := Geometry.mechanical_boxes(moved)
	verify(rotated.accepted and rotated.boxes.belt.size.is_equal_approx(Vector3(0.6, 0.3, 4.95)), "The other horizontal direction rotates the span bounds.")
	for axle in [0, 2]:
		for sign_value in [-1, 1]:
			var slope: Dictionary = state.duplicate(true)
			slope.transmission_parts.a.axis = axle
			slope.transmission_parts.b.axis = axle
			slope.transmission_parts.b.center = [8 if axle == 2 else 0, 8 * sign_value, 8 if axle == 0 else 0]
			var sloped := Geometry.mechanical_boxes(slope)
			var reverse_slope: Dictionary = slope.duplicate(true)
			reverse_slope.belt_spans.belt = {"from": "b", "to": "a"}
			verify(sloped.accepted and sloped.boxes.belt.has("basis") and Geometry.mechanical_boxes(reverse_slope).boxes.belt == sloped.boxes.belt, "An inclined belt has a stable rotated body for either axle and slope.")
	var vertical: Dictionary = state.duplicate(true)
	vertical.transmission_parts.b.center = [0, 8, 0]
	verify(Geometry.mechanical_boxes(vertical).boxes.belt.size.is_equal_approx(Vector3(0.3, 4.95, 0.6)), "A vertical power-only belt has a narrow vertical body.")
	var sideways: Dictionary = state.duplicate(true)
	sideways.transmission_parts.a.axis = 1
	sideways.transmission_parts.b.axis = 1
	verify(Geometry.mechanical_boxes(sideways).boxes.belt.size.is_equal_approx(Vector3(4.95, 0.6, 0.3)), "A sideways power-only belt has a narrow side-facing body.")
	var bad_slope: Dictionary = state.duplicate(true)
	bad_slope.transmission_parts.b.center = [8, 4, 0]
	verify(not Geometry.mechanical_boxes(bad_slope).accepted, "An unequal slope is rejected by physical geometry.")
	var removed: Dictionary = state.duplicate(true)
	removed.belt_spans.clear()
	removed.transmission_parts.erase("b")
	verify(Geometry.mechanical_boxes(removed).boxes.size() == 2, "Removing a span and shaft removes their derived bodies.")
	for fault: String in ["missing_endpoint", "off_grid", "invalid_axis", "too_long", "duplicate_identity"]:
		var bad: Dictionary = state.duplicate(true)
		match fault:
			"missing_endpoint": bad.belt_spans.belt.to = "missing"
			"off_grid": bad.transmission_parts.a.center = [1, 0, 0]
			"invalid_axis": bad.transmission_parts.a.axis = true
			"too_long": bad.transmission_parts.b.center = [80, 0, 0]
			"duplicate_identity": bad.belt_spans = {"a": {"from": "a", "to": "b"}}
		verify(not Geometry.mechanical_boxes(bad).accepted, "Malformed %s topology fails closed." % fault)
	verify(Geometry.mechanical_boxes({"options": {"native": false}}).boxes.is_empty(), "Legacy fixtures do not invent transmission bodies.")

func _cog_axle_collision() -> void:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for axis in range(3):
		var authority := PhysicalProjection.new()
		authority.state = {"options": {"native": true, "physical": true}, "actors": {}, "entities": {}, "foundations": {},
			"transmission_parts": {"cog": {"kind": "gear", "center": [0, 8, 0], "axis": axis, "teeth": 2}}, "belt_spans": {}}
		var physical := ActorWorld.new()
		root.add_child(physical)
		verify(physical.configure(authority).accepted, "A cog projection initializes native collision.")
		await physics_frame
		await physics_frame
		var cog: StaticBody3D = physical.mechanical_bodies.cog
		verify(physical._geometry_registered() and PhysicsServer3D.body_get_shape_count(cog.get_rid()) == 2, "Disc and axle are registered under one cog body.")
		var query := PhysicsShapeQueryParameters3D.new()
		var probe := SphereShape3D.new()
		probe.radius = 0.04
		query.shape = probe
		query.collision_mask = Geometry.MACHINE_LAYER
		query.transform.origin = cog.position + axes[axis] * 0.6
		var hits := physical.get_world_3d().direct_space_state.intersect_shape(query)
		verify(hits.any(func(hit: Dictionary): return hit.rid == cog.get_rid() and hit.shape == 1), "A native query hits the exposed cog axle.")
		var across := Vector3.RIGHT if axis == 1 else Vector3.UP
		query.transform.origin += across * 0.5
		hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
		verify(not hits.any(func(hit: Dictionary): return hit.rid == cog.get_rid()), "The space beside the axle remains empty.")
		var actor := PhysicalActor.new()
		actor.position = cog.position + axes[axis] * (1.55 if axis == 1 else 0.6)
		root.add_child(actor)
		await physics_frame
		await physics_frame
		physical.bodies["P"] = actor
		var contacts: Array = physical._initial_overlaps("P")
		physical.bodies.erase("P")
		verify(contacts.any(func(hit: Dictionary): return hit.get("rid") == cog.get_rid().get_id() and hit.get("shape") == 1 and hit.get("unsupported_overlap", false)), "Admission measures the actual axle hit and rejects penetration.")
		actor.queue_free()
		await process_frame
		var axle: BoxShape3D = cog.get_child(1).shape
		var size := axle.size
		axle.size *= 0.5
		verify(not physical._geometry_registered(), "Changing the axle shape fails the registration guard.")
		axle.size = size
		authority.state.transmission_parts.clear()
		verify(physical.sync_topology().accepted and not physical.mechanical_bodies.has("cog"), "Removing the cog removes both collision shapes.")
		authority.state.transmission_parts["cog"] = {"kind": "gear", "center": [0, 8, 0], "axis": axis, "teeth": 2}
		verify(physical.sync_topology().accepted, "Restoring the cog rebuilds its collision body.")
		await physics_frame
		await physics_frame
		verify(physical._geometry_registered(), "Both restored shapes pass the native registration guard.")
		physical.queue_free()
		await process_frame

func _collision_body_lifecycle() -> void:
	var authority := PhysicalProjection.new()
	authority.state = {"options": {"native": true, "physical": true}, "actors": {}, "entities": {}, "foundations": {},
		"transmission_parts": {
			"left": {"kind": "shaft", "center": [0, 8, 0], "axis": 2, "half_span": 2},
			"right": {"kind": "shaft", "center": [8, 8, 0], "axis": 2, "half_span": 2},
			"cog": {"kind": "gear", "center": [0, 8, 4], "axis": 2, "teeth": 2}},
		"belt_spans": {"belt": {"from": "left", "to": "right"}}}
	var physical := ActorWorld.new()
	root.add_child(physical)
	verify(physical.configure(authority).accepted, "A synthetic projection initializes the physical geometry.")
	await physics_frame
	await physics_frame
	verify(physical._geometry_registered() and physical.mechanical_bodies.size() == 4, "Confirmed parts and span have registered native bodies.")
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := SphereShape3D.new()
	probe.radius = 0.05
	query.shape = probe
	query.collision_mask = Geometry.MACHINE_LAYER
	query.transform.origin = Vector3(1.65, 3.8, 0)
	var hits := physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(hits.any(func(hit: Dictionary): return hit.rid == physical.mechanical_bodies.belt.get_rid()), "The native physics query intersects the belt body.")
	var capsule := CapsuleShape3D.new()
	capsule.radius = Geometry.CAPSULE_RADIUS
	capsule.height = Geometry.CAPSULE_HEIGHT
	query.shape = capsule
	query.transform.origin = Vector3(1.65, 4.35, 0)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(hits.any(func(hit: Dictionary): return hit.rid == physical.mechanical_bodies.belt.get_rid()), "The actual character-sized capsule detects the belt body.")
	query.transform.origin = Vector3(1.65, 3.8, -2.0)
	query.motion = Vector3(0, 0, 4.0)
	var sweep := physical.get_world_3d().direct_space_state.cast_motion(query)
	verify(sweep.size() == 2 and sweep[0] < 1.0, "A character-sized sweep is blocked by the belt.")
	query.motion = Vector3.ZERO
	query.shape = probe
	query.transform.origin = Vector3(0, 3.8, 0)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(hits.any(func(hit: Dictionary): return hit.rid == physical.mechanical_bodies.left.get_rid()), "The native physics query intersects the shaft body.")
	query.transform.origin = Vector3(0, 3.8, 1.65)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(hits.any(func(hit: Dictionary): return hit.rid == physical.mechanical_bodies.cog.get_rid()), "The native physics query intersects the cog body.")
	var belt: StaticBody3D = physical.mechanical_bodies.belt
	var actor := PhysicalActor.new()
	actor.position = Vector3(1.65, 3.8, 0)
	root.add_child(actor)
	await physics_frame
	await physics_frame
	physical.bodies["P"] = actor
	var penetrating: Dictionary = physical._penetration("P", belt.get_rid())
	var occupied_contacts: Array = physical._initial_overlaps("P")
	physical.bodies.erase("P")
	verify(penetrating.get("unsupported_overlap", false), "The actor overlap guard rejects a capsule inside the belt.")
	verify(occupied_contacts.any(func(hit: Dictionary): return hit.get("rid") == belt.get_rid().get_id() and hit.get("unsupported_overlap", false)), "The admission and checkpoint query detects the actual belt penetration.")
	actor.position = Vector3(1.65, 4.85, 0)
	await physics_frame
	await physics_frame
	physical.bodies["P"] = actor
	var resting: Dictionary = physical._penetration("P", belt.get_rid())
	var resting_contacts: Array = physical._initial_overlaps("P")
	physical.bodies.erase("P")
	verify(not resting.get("unsupported_overlap", true), "The actor overlap guard accepts contact at the belt surface.")
	verify(not resting_contacts.any(func(hit: Dictionary): return hit.get("unsupported_overlap", true)), "The admission and checkpoint query accepts the supported surface contact.")
	actor.queue_free()
	await process_frame
	var belt_shape: BoxShape3D = belt.get_child(0).shape
	var original := belt_shape.size
	belt_shape.size = Vector3(0.1, 0.1, 0.1)
	verify(not physical._geometry_registered(), "A changed native collision shape fails the registration guard.")
	belt_shape.size = original
	belt.position.x += 1.0
	verify(not physical._geometry_registered(), "A displaced collision body fails the registration guard.")
	belt.position.x -= 1.0
	authority.state.belt_spans.clear()
	authority.state.transmission_parts.erase("right")
	verify(physical.sync_topology().accepted, "The removed span and shaft synchronize.")
	await physics_frame
	await physics_frame
	verify(physical._geometry_registered() and not physical.mechanical_bodies.has("belt") and not physical.mechanical_bodies.has("right"), "Removed bodies leave the native world without damaging remaining registrations.")
	query.transform.origin = Vector3(1.65, 3.8, 0)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(hits.is_empty(), "The removed belt no longer blocks its former center.")
	query.shape = capsule
	query.transform.origin = Vector3(1.65, 3.8, -2.0)
	query.motion = Vector3(0, 0, 4.0)
	sweep = physical.get_world_3d().direct_space_state.cast_motion(query)
	verify(sweep.size() == 2 and sweep[0] == 1.0, "The same character-sized sweep is clear after belt removal.")
	query.shape = probe
	query.motion = Vector3.ZERO
	query.transform.origin = Vector3(1.65, 3.8, 0)
	authority.state.transmission_parts["right"] = {"kind": "shaft", "center": [8, 8, 0], "axis": 2, "half_span": 2}
	authority.state.belt_spans["belt"] = {"from": "left", "to": "right"}
	verify(physical.sync_topology().accepted, "A restored projection rebuilds its span and shaft bodies.")
	await physics_frame
	await physics_frame
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(physical._geometry_registered() and hits.any(func(hit: Dictionary): return hit.rid == physical.mechanical_bodies.belt.get_rid()), "Restored bodies register and block the belt center again.")
	authority.state.transmission_parts.right.center = [8, 16, 0]
	verify(physical.sync_topology().accepted, "An inclined projection synchronizes rotated collision geometry.")
	await physics_frame
	await physics_frame
	var incline: StaticBody3D = physical.mechanical_bodies.belt
	query.transform.origin = Vector3(1.65, 5.45, 0)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(physical._geometry_registered() and hits.any(func(hit: Dictionary): return hit.rid == incline.get_rid()), "The registered inclined body blocks its actual midpoint.")
	query.transform.origin = Vector3(1.65, 3.8, 0)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(not hits.any(func(hit: Dictionary): return hit.rid == incline.get_rid()), "The inclined body does not fill the empty space below its midpoint.")
	var slope_actor := PhysicalActor.new()
	var normal := incline.basis.y
	slope_actor.position = incline.position + normal * (0.15 + Geometry.CAPSULE_RADIUS) + Vector3.UP * (Geometry.CAPSULE_HEIGHT / 2.0 - Geometry.CAPSULE_RADIUS)
	root.add_child(slope_actor)
	await physics_frame
	physical.bodies["slope"] = slope_actor
	verify(not physical._penetration("slope", incline.get_rid()).get("unsupported_overlap", true), "An upright capsule may rest against the inclined surface.")
	physical.bodies.erase("slope")
	slope_actor.position -= normal * 0.1
	await physics_frame
	await physics_frame
	physical.bodies["slope"] = slope_actor
	verify(physical._penetration("slope", incline.get_rid()).get("unsupported_overlap", false), "The inclined overlap guard rejects penetration.")
	physical.bodies.erase("slope")
	slope_actor.queue_free()
	incline.basis = Basis.IDENTITY
	verify(not physical._geometry_registered(), "A changed inclined body orientation fails the registration guard.")
	physical.queue_free()
	await process_frame

func _belt_actor_transport() -> void:
	var authority := PhysicalProjection.new()
	authority.state = {"options": {"native": true, "physical": true}, "entities": {}, "foundations": {},
		"actors": {"P": {"position": [0.0, 5.175, 0.0], "ready": false, "native_epoch": 0}},
		"transmission_parts": {
			"left": {"kind": "shaft", "center": [0, 8, 0], "axis": 2, "half_span": 2},
			"right": {"kind": "shaft", "center": [8, 8, 0], "axis": 2, "half_span": 2}},
		"belt_spans": {"belt": {"from": "left", "to": "right"}},
		"motion": {"left": {"state": "rotating", "numerator": -1, "denominator": 4}}}
	var physical := ActorWorld.new()
	physical.set_belt_step_seconds(0.45)
	physical.pose_published.connect(authority.observe)
	root.add_child(physical)
	verify(physical.configure(authority).accepted and physical.ensure_actor("P").accepted, "The synthetic character starts on a confirmed belt.")
	var belt_id: int = physical.mechanical_bodies.belt.get_instance_id()
	var sample: Dictionary = authority.projection()
	var expected_speed := Geometry.PITCH / (4.0 * 0.45)
	verify(physical._belt_surface_velocity(sample, belt_id).is_equal_approx(Vector2(expected_speed, 0)), "The X travel rate matches the native quarter-tile per simulation step.")
	sample.transmission_parts.right.center = [8, 16, 0]
	var slope_speed := floorf(1024.0 * 2896.0 / 4096.0) / 4096.0 * Geometry.PITCH / 0.45
	verify(physical._belt_surface_velocity(sample, belt_id).is_equal_approx(Vector2(slope_speed, 0)), "Inclined actor carry uses the same fixed-point horizontal progress as cargo.")
	sample.transmission_parts.right.center = [8, 8, 0]
	sample.transmission_parts.left.axis = 0
	sample.motion.left.numerator = 1
	verify(physical._belt_surface_velocity(sample, belt_id).is_equal_approx(Vector2(0, expected_speed)), "The other horizontal shaft axis transports along Z with the correct sign.")
	sample.transmission_parts.right.center = [0, 16, 0]
	verify(physical._belt_surface_velocity(sample, belt_id) == Vector2.ZERO, "A vertical power-only belt does not carry actors.")
	verify(physical._belt_surface_velocity(sample, 0) == Vector2.ZERO, "A character without belt floor contact receives no transport.")
	for frame in 40:
		await physics_frame
	verify(not physical.failures.has("P") and physical.bodies.P.motion_enabled, "The native actor registers without penetrating the belt.")
	var forward: float = physical.bodies.P.position.x
	verify(forward > 0.15 and absf(physical.bodies.P.position.z) < 0.05, "A powered belt carries the uncommanded actor in the cargo direction.")
	var supported_cut: Dictionary = physical.checkpoint_status()
	verify(supported_cut.accepted and supported_cut.reason == "native_checkpoint_ready", "A capsule supported by the belt can pass checkpoint admission.")
	var body: CharacterBody3D = physical.bodies.P
	var original_pose := body.global_transform
	body.set_physics_process(false)
	var embedded_pose := original_pose
	embedded_pose.origin = Vector3(1.65, 3.8, 0.0)
	body.global_transform = embedded_pose
	await physics_frame
	await physics_frame
	var blocked_cut: Dictionary = physical.checkpoint_status()
	verify(not blocked_cut.accepted and blocked_cut.reason == "actor_pose_not_settled", "Checkpoint admission rejects a capsule embedded in the belt.")
	verify(body.global_transform == embedded_pose and PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) == embedded_pose, "The rejected checkpoint does not move the capsule.")
	body.global_transform = original_pose
	await physics_frame
	await physics_frame
	verify(physical.checkpoint_status().accepted, "Checkpoint admission succeeds again after restoring the supported pose.")
	body.set_physics_process(true)
	authority.state.motion.left.state = "stopped"
	for frame in 10:
		await physics_frame
	var stopped: float = physical.bodies.P.position.x
	verify(absf(stopped - forward) < 0.05, "Stopping the shaft stops belt transport.")
	authority.state.motion.left.state = "rotating"
	authority.state.motion.left.numerator = 1
	for frame in 25:
		await physics_frame
	var reversed: float = physical.bodies.P.position.x
	verify(reversed < stopped - 0.15, "Reversing the shaft reverses actor transport.")
	physical.set_belt_step_seconds(0.0)
	for frame in 10:
		await physics_frame
	verify(absf(physical.bodies.P.position.x - reversed) < 0.05, "A frozen simulation clock stops belt transport.")
	physical.bodies.P.set_control(Vector2(1, 0), false)
	for frame in 6:
		await physics_frame
	verify(physical.bodies.P.position.x > reversed + 0.1, "Synthetic walking control still moves the character on the belt.")
	physical.bodies.P.release_control()
	physical.bodies.P.set_control(Vector2.ZERO, true)
	for frame in 8:
		await physics_frame
	verify(physical.bodies.P.position.y > 4.95, "Synthetic jump control still lifts the character off the belt.")
	physical.queue_free()
	await process_frame
	# Exercise the actual host setup with no actors or network/game startup.
	authority.state.actors = {}
	var host_root := Node.new()
	host_root.name = "OpeningShared"
	root.add_child(host_root)
	for step in [0.45, 0.0]:
		var host := Session.new()
		host.name = "Session"
		host._authoritative = true
		host.world = authority
		host._tick_seconds = step
		host_root.add_child(host)
		host.set_process(false)
		verify(host.start_physical_world() == OK and host.actor_world.belt_step_seconds == step, "The host passes its simulation clock to the physical world.")
		host.queue_free()
		await process_frame
	host_root.queue_free()

func _inclined_belt_actor() -> void:
	for axle in [0, 2]:
		for slope in [-1, 1]:
			var authority := PhysicalProjection.new()
			var first_y := 8 if slope > 0 else 16
			var last_y := 16 if slope > 0 else 8
			var end := [8 if axle == 2 else 0, last_y, 8 if axle == 0 else 0]
			var actor_position := [1.65 if axle == 2 else 0.0, 7.605, 1.65 if axle == 0 else 0.0]
			authority.state = {"options": {"native": true, "physical": true}, "entities": {}, "foundations": {},
				"actors": {"P": {"position": actor_position, "ready": false, "native_epoch": 0}},
				"transmission_parts": {"left": {"kind": "shaft", "center": [0, first_y, 0], "axis": axle, "half_span": 2},
					"right": {"kind": "shaft", "center": end, "axis": axle, "half_span": 2}},
				"belt_spans": {"belt": {"from": "left", "to": "right"}},
				"motion": {"left": {"state": "stopped", "numerator": 0, "denominator": 1}}}
			var physical := ActorWorld.new()
			physical.set_belt_step_seconds(0.45)
			physical.pose_published.connect(authority.observe)
			root.add_child(physical)
			verify(physical.configure(authority).accepted and physical.ensure_actor("P").accepted, "The inclined fixture creates its physical actor.")
			for frame in 55:
				await physics_frame
			var body = physical.bodies.P
			verify(not physical.failures.has("P") and body.motion_enabled and body.is_on_floor() and body.floor_id == physical.mechanical_bodies.belt.get_instance_id(), "An actor registers stable floor contact on an inclined belt.")
			var start: Vector3 = body.position
			authority.state.motion.left.state = "rotating"
			authority.state.motion.left.numerator = 1 if axle == 0 else -1
			authority.state.motion.left.denominator = 4
			for frame in 55:
				await physics_frame
			var forward: Vector3 = body.position
			var travel := forward.z - start.z if axle == 0 else forward.x - start.x
			verify(travel > 0.15 and (forward.y - start.y) * slope > 0.1, "The inclined belt carries an uncommanded actor along and up or down its slope.")
			authority.state.motion.left.numerator *= -1
			for frame in 50:
				await physics_frame
			var reverse: Vector3 = body.position
			verify((reverse.z - forward.z if axle == 0 else reverse.x - forward.x) < -0.1, "Reversing the shaft reverses inclined actor transport.")
			authority.state.motion.left.state = "stopped"
			for frame in 12:
				await physics_frame
			var stopped: Vector3 = body.position
			verify(absf(stopped.z - reverse.z if axle == 0 else stopped.x - reverse.x) < 0.05, "A stopped inclined belt holds the actor.")
			authority.state.motion.left.state = "rotating"
			physical.set_belt_step_seconds(0.0)
			for frame in 12:
				await physics_frame
			var frozen: Vector3 = body.position
			verify(absf(frozen.z - stopped.z if axle == 0 else frozen.x - stopped.x) < 0.05, "A frozen clock stops inclined actor transport.")
			physical.queue_free()
			await process_frame

func _run() -> void:
	if "--tool-guidance-only" in OS.get_cmdline_user_args():
		_tool_guidance()
	elif "--refresh-cache-only" in OS.get_cmdline_user_args():
		_cache_regression()
	elif "--belt-surface-only" in OS.get_cmdline_user_args():
		_belt_surface_motion()
	elif "--direction-basis-only" in OS.get_cmdline_user_args():
		_direction_basis()
	elif "--loose-material-only" in OS.get_cmdline_user_args():
		_loose_material()
	elif "--mechanical-collision-only" in OS.get_cmdline_user_args():
		_mechanical_collision_geometry()
	elif "--collision-lifecycle-only" in OS.get_cmdline_user_args():
		await _collision_body_lifecycle()
	elif "--cog-axle-collision-only" in OS.get_cmdline_user_args():
		await _cog_axle_collision()
	elif "--belt-actor-only" in OS.get_cmdline_user_args():
		await _belt_actor_transport()
	elif "--inclined-belt-actor-only" in OS.get_cmdline_user_args():
		await _inclined_belt_actor()
	elif "--nonhorizontal-presentation-only" in OS.get_cmdline_user_args():
		_nonhorizontal_presentation()
	elif "--belt-picking-only" in OS.get_cmdline_user_args():
		await _belt_picking()
	elif "--cog-axles-only" in OS.get_cmdline_user_args():
		await _cog_axles()
	else:
		_controls()
		_gear_sizes()
		_shaft_segments()
		_belt_spans()
		_belt_retry()
		_span_guidance()
		_belt_surface_motion()
		_presentation()
	print("NATIVE_TRANSMISSION_VIEW_%s %d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
