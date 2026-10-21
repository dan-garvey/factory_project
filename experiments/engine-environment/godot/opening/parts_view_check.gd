extends SceneTree
## Default cases inspect unmounted views. --buttons-only mounts actual widgets
## over invented projections. --carried-guidance-only also reads recovery menus.
## None of these modes creates a live Model.

const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")
var checks := 0
var failures := 0

class OfflineWidgets:
	extends "res://opening/opening.gd"
	func _ready() -> void:
		set_process(false)
	func _update_cursor() -> void:
		pass

class SharedWidgets:
	extends "res://opening/shared_opening.gd"
	func _ready() -> void:
		set_process(false)
	func _update_cursor() -> void:
		pass

class SessionStub extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

func verify(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(reason)

func fixture() -> Dictionary:
	return {"parts": {"collector": 0, "belt": 1, "processor": 0, "shaft": 3},
		"part_kits": {"P": {"collector": 0, "belt": 1, "processor": 0, "shaft": 3},
			"Q": {"collector": 0, "belt": 0, "processor": 1, "shaft": 0}},
		"options": {"physical": true}, "actors": {"P": {"ready": true}, "Q": {"ready": true}},
		"entities": {"collector-1": {"kind": "collector", "cell": [0, 1]}},
		"stock": {"output": 0}, "inventories": {"P": 0, "Q": 0}}

func _initialize() -> void:
	if "--carried-guidance-only" in OS.get_cmdline_user_args():
		call_deferred("_carried_guidance")
		return
	if "--buttons-only" in OS.get_cmdline_user_args():
		call_deferred("_buttons")
		return
	var offline = Opening.new()
	offline.state = fixture()
	verify(offline._display_parts() == {"collector": 0, "belt": 1, "processor": 0, "shaft": 3}, "The scripted offline profile retains its existing part display.")
	verify(not offline._parts_are_shared(), "Offline parts retain the carried caption.")
	offline.free()

	var view = SharedOpening.new()
	view.session = SessionStub.new()
	view.client = "Q"
	view.mode = "belt"
	view.state = fixture()
	verify(view._display_parts() == {"collector": 0, "belt": 1, "processor": 0, "shaft": 3}, "The scripted shared profile retains the shared kit even for Q.")
	verify(view._parts_are_shared(), "The scripted shared profile retains its shared caption.")
	view.state.options.native = true
	verify(view._display_parts() == {"collector": 0, "belt": 0, "processor": 1, "shaft": 0}, "Native Q displays Q's actual carried kit.")
	verify(not view._parts_are_shared(), "Native per-actor kits use the carried caption.")
	verify(view._guided_placement_cell().is_empty(), "P's available Belt cannot produce a cue for Q's empty kit.")
	view.state.part_kits.P.belt = 0
	view.state.parts.belt = 0
	view.state.part_kits.Q.belt = 1
	verify(view._guided_placement_cell() == [1, 1], "Q's own Belt produces a cue even when P has none.")
	verify(view._display_parts().shaft == 0, "Q does not borrow P's shaft count.")
	view.client = "P"
	verify(view._display_parts().belt == 0 and view._display_parts().shaft == 3, "Changing the active actor changes every displayed kit field.")
	verify(view._guided_placement_cell().is_empty(), "Q's Belt does not produce a cue for P.")
	view.client = "Q"
	view.state.part_kits.erase("Q")
	verify(view._display_parts().is_empty(), "An absent native actor kit does not fall back to P.")
	view.state.erase("part_kits")
	verify(view._display_parts().is_empty(), "Missing native kits cannot reuse the compatibility alias.")
	view.state = fixture()
	view.state.options.native = true
	view.state.cargo = {"Q": {"raw": 9, "products": 4, "work_lots": [{"id": 7}]}}
	var before: Dictionary = view.state.duplicate(true)
	var sequence: int = view.request_sequence
	var namespace_id: String = view.request_namespace
	verify(view._display_parts().belt == 0, "Carried material is distinct from construction parts.")
	view._guided_placement_cell()
	verify(view.state == before and view.model == null and view.request_sequence == sequence and view.request_namespace == namespace_id, "Display reads change neither projection nor authority/intent state.")
	view.free()
	print("OPENING_PARTS_VIEW_%s %d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _carried_guidance() -> void:
	for shared in [false, true]:
		var view = SharedWidgets.new() if shared else OfflineWidgets.new()
		if shared:
			view.session = SessionStub.new()
		view.state = fixture()
		view.state.context = "native-carried-guidance"
		view.state.options.native = true
		view.state.stock = {"source": 0, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0}
		view.state.remaining = 0
		view.state.power_enabled = true
		view.state.powered = true
		view.state.entities = {"collector": {"kind": "collector", "cell": [0, 1]},
			"belt": {"kind": "belt", "cell": [1, 1]}, "press": {"kind": "processor", "cell": [2, 1]},
			"wheel": {"kind": "wheel", "cell": [0, 0]}}
		view.state.links = [["collector", "belt"], ["belt", "press"]]
		view.state.transmission_parts = {}
		view.state.motion = {}
		view.state.engagements = []
		view.state.part_specifications = {"P": [], "Q": []}
		view.state.cargo = {"P": {"raw": 0, "products": 0, "work_lots": []},
			"Q": {"raw": 0, "products": 0, "work_lots": []}}
		view.mode = "inspect"
		view.selected = "press"
		view.request_sequence = 17
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view._build_interface()
		var identity: String = view.request_namespace
		for actor in ["P", "Q"]:
			view.client = actor
			for sample in [{"raw": 2, "remaining": -1}, {"raw": 0, "remaining": 2},
				{"raw": 0, "remaining": 0}, {"raw": 2, "remaining": 2}]:
				view.state.cargo.P = {"raw": 0, "products": 0, "work_lots": []}
				view.state.cargo.Q = {"raw": 0, "products": 0, "work_lots": []}
				var lots: Array = [] if sample.remaining < 0 else [{"id": 7, "recipe_input": 1,
					"cycle_ticks": 4, "remaining": sample.remaining}]
				view.state.cargo[actor] = {"raw": sample.raw, "products": 0, "work_lots": lots}
				var before: Dictionary = view.state.duplicate(true)
				view._refresh_ui()
				var form: String = "carried blank" if lots.is_empty() else "carried workpiece"
				verify(view.goal_label.text.contains(form) and view.goal_label.text.contains("press")
					and not view.goal_label.text.contains("No blanks"),
					"The real %s goal points %s's %s back to the press." % ["shared" if shared else "offline", actor, form])
				view.recovery_actions._open_menu()
				var offered: Array = []
				var popup: PopupMenu = view.recovery_actions.action_button.get_popup()
				for index in range(popup.item_count):
					offered.append(popup.get_item_metadata(index).wire.action)
				verify(view.recovery_actions.visible and not view.recovery_actions.action_button.disabled
					and ("insert_raw" if lots.is_empty() else "insert_work") in offered,
					"The suggested form has an existing enabled insertion choice at the selected press.")
				verify(view.state == before and view.model == null and view.actor_world == null
					and view.request_sequence == 17 and view.request_namespace == identity,
					"Reading the goal and menu changes no projection, authority or request identity.")
			view.state.cargo[actor] = {"raw": 0, "products": 0, "work_lots": []}
			var peer: String = "Q" if actor == "P" else "P"
			view.state.cargo[peer] = {"raw": 3, "products": 0, "work_lots": [{"id": 9,
				"recipe_input": 1, "cycle_ticks": 4, "remaining": 1}]}
			view._refresh_ui()
			verify(view.goal_label.text.contains("No blanks") and not view.recovery_actions.visible,
				"A peer's carried material does not become the active actor's continuation route.")
		view.state.cargo[view.client] = {"raw": 1, "products": 0, "work_lots": []}
		view.state.stock.output = 1
		view._refresh_ui()
		verify(view.goal_label.text.contains("Plate ready"), "A finished plate still takes priority over reinsertion advice.")
		view.state.stock.output = 0
		view.state.inventories[view.client] = 4
		view._refresh_ui()
		verify(view.confirm_button.visible and not view.confirm_button.disabled and view.goal_label.text.contains("Confirm"),
			"Four collected products retain the original confirmation route.")
		view.state.inventories[view.client] = 0
		view.state.power_enabled = false
		view._refresh_ui()
		verify(view.goal_label.text.contains("Switch on"), "The existing power step retains its priority.")
		view.state.power_enabled = true
		view.state.options.native = false
		view._refresh_ui()
		verify(view.goal_label.text.contains("No blanks"), "Historical guidance ignores native carried-material fields.")
		view.state.options.native = true
		if shared:
			view.pending_actions = {"waiting": {}}
			view._refresh_ui()
			verify(view.goal_label.text.contains("Waiting for the server") and view.recovery_actions.action_button.disabled,
				"A pending shared command retains the waiting message and disabled material menu.")
			view.pending_actions.clear()
			view.session.ready = false
			view._refresh_ui()
			verify(view.goal_label.text.contains("Reconnect") and view.recovery_actions.action_button.disabled,
				"Disconnection retains the read-only prompt and disabled material menu.")
		view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"failures": failures, "models": 0, "desktop_operations": 0, "scope": "carried-material goals and existing press insertion menus"}))
	quit(0 if failures == 0 else 1)

func _buttons() -> void:
	for shared in [false, true]:
		var view = SharedWidgets.new() if shared else OfflineWidgets.new()
		if shared:
			view.session = SessionStub.new()
		view.state = fixture()
		view.state.context = "native-kit-widgets"
		view.state.options.native = true
		view.state.stock = {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0}
		view.state.remaining = 0
		view.state.transmission_parts = {}
		view.state.motion = {}
		view.state.engagements = []
		view.state.part_specifications = {"P": [{"kind": "shaft", "teeth": 0, "half_span": 2, "count": 3}], "Q": []}
		for actor in ["P", "Q"]:
			view.state.part_kits[actor].wheel = 0
		view.show_all_tools = true
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view._build_interface()
		for actor in ["P", "Q"]:
			view.client = actor
			var before: Dictionary = view.state.duplicate(true)
			view._refresh_ui()
			var usable: Array = ["belt", "drive"] if actor == "P" else ["processor"]
			for tool in ["collector", "belt", "processor", "wheel", "drive"]:
				verify(view.tool_buttons[tool].disabled == (tool not in usable),
					"Native %s %s availability follows its own carried kit (shared=%s)." % [actor, tool, shared])
			verify(view.state == before and view.model == null and view.request_sequence == 0,
				"Refreshing real widgets changes no projection, request or authority.")
		var identity: String = view.request_namespace
		view.mode = "inspect"
		view._select_tool("collector")
		verify(view.mode == "collector" and view.request_namespace == identity and view.request_sequence == 0,
			"Explicit tool selection remains available without minting an intent.")
		view.state.options.native = false
		view._refresh_ui()
		verify(not view.tool_buttons.collector.disabled and "0" in view.tool_buttons.collector.text,
			"The historical scripted profile retains its existing zero-count display behavior.")
		view.state.options.native = true
		view.state.part_kits.erase("Q")
		view._refresh_ui()
		for tool in ["collector", "belt", "processor", "wheel", "drive"]:
			verify(view.tool_buttons[tool].disabled, "An absent native actor kit cannot borrow a tool from P.")
		if shared:
			view.state.part_kits.Q = fixture().part_kits.Q
			view.pending_actions = {"waiting": {}}
			view._refresh_ui()
			verify(view.tool_buttons.processor.disabled, "A carried part does not bypass the shared pending barrier.")
			view.pending_actions.clear()
			view.session.ready = false
			view._refresh_ui()
			verify(view.tool_buttons.processor.disabled, "A carried part does not bypass disconnection.")
		view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"failures": failures, "models": 0, "desktop_operations": 0, "scope": "actual kit buttons over invented projections"}))
	quit(0 if failures == 0 else 1)
