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
	var issued: Array = []
	var pointed := ""
	func issue(action: Dictionary) -> Dictionary:
		issued.append(action.duplicate(true))
		return {"accepted": false, "reason": "fixture_only"}
	func _ready() -> void:
		set_process(false)
	func _update_cursor() -> void:
		pass
	func _update_camera() -> void:
		pass
	func _screen_entity(_screen: Vector2) -> String:
		return pointed

class SharedWidgets:
	extends "res://opening/shared_opening.gd"
	var issued: Array = []
	var pointed := ""
	func issue(action: Dictionary) -> Dictionary:
		issued.append(action.duplicate(true))
		return {"accepted": false, "reason": "fixture_only"}
	func _ready() -> void:
		set_process(false)
	func _update_cursor() -> void:
		pass
	func _update_camera() -> void:
		pass
	func _screen_entity(_screen: Vector2) -> String:
		return pointed

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
	if "--interaction-only" in OS.get_cmdline_user_args():
		call_deferred("_interaction_controls")
		return
	if "--building-rotation-only" in OS.get_cmdline_user_args():
		call_deferred("_building_rotation")
		return
	if "--hotbar-render-only" in OS.get_cmdline_user_args():
		call_deferred("_render_hotbar")
		return
	if "--hotbar-only" in OS.get_cmdline_user_args():
		call_deferred("_hotbar")
		return
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
	verify(view._guided_placement_cell().is_empty() and view._guided_step({"collector": true}).tool == "drive",
		"Native shaft-belt guidance does not suggest a grid Belt cell even when Q carries a Belt.")
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

func hotbar_observation() -> Dictionary:
	var kit := {"collector": 1, "foundation": 24, "belt": 1, "processor": 1, "wheel": 1, "gear": 10, "shaft": 8}
	var other := {"collector": 0, "foundation": 2, "belt": 0, "processor": 1, "wheel": 0, "gear": 1, "shaft": 2}
	return {"context": "hotbar-fixture", "revision": 7, "order": 0,
		"options": {"physical": true, "native": true, "foundations": true},
		"actors": {"P": {"ready": true, "position": [0.0, 1.0, 0.0]}, "Q": {"ready": true, "position": [3.0, 1.0, 0.0]}},
		"parts": kit.duplicate(), "part_kits": {"P": kit.duplicate(), "Q": other},
		"part_specifications": {"P": [{"kind": "gear", "count": 8, "teeth": 2, "half_span": 0},
			{"kind": "gear", "count": 2, "teeth": 4, "half_span": 0},
			{"kind": "shaft", "count": 8, "teeth": 0, "half_span": 2}], "Q": []},
		"entities": {}, "foundations": {}, "transmission_parts": {}, "motion": {}, "engagements": [],
		"links": [], "drive_links": [], "inventories": {"P": 0, "Q": 0},
		"stock": {"source": 4096, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
		"remaining": 0, "powered": false, "power_enabled": false}

func settle_widgets() -> void:
	for _frame in range(4):
		await process_frame

func _building_rotation() -> void:
	for shared in [false, true]:
		var view = SharedWidgets.new() if shared else OfflineWidgets.new()
		if shared:
			view.session = SessionStub.new()
		view.state = hotbar_observation()
		view.mode = "collector"
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view._build_interface()
		view._refresh_transmission()
		view.transmission_controls.selected_axis = "z"
		var before: Dictionary = view.state.duplicate(true)
		var sequence: int = view.request_sequence
		for turn in range(4):
			view._refresh_ui()
			verify(view.rotation_button.visible and not view.rotation_button.disabled and "%d°" % (turn * 90) in view.rotation_button.text,
				"The ordinary rotate control shows each available facing in offline and shared views.")
			verify(view.building_rotation == turn and view._preview_axis() == (2 if turn % 2 == 0 else 0),
				"Quarter turns rotate the preview's horizontal drive axis with its body.")
			var anchor := Node3D.new()
			view._assemble_machine(anchor, {"kind": "collector", "axis": view._preview_axis(),
				"rotation": turn, "cell": [0, 0], "level": 0})
			var body := anchor.get_node_or_null("RotatedMachineVisual")
			verify(body == null and anchor.get_node_or_null("SourcePickupHousing") != null,
				"The collector keeps its source-facing intake while its selected outlet turns.")
			view._preview_port(anchor, turn, true)
			var port: Label3D = anchor.get_node("MaterialPortLabel")
			verify(port.text == "OUT" and (port.get_meta("port_side") as Vector3).is_equal_approx(Vector3.RIGHT.rotated(Vector3.UP, -float(turn) * PI / 2.0)),
				"The collector preview labels the selected output side.")
			anchor.free()
			view._world_click(Vector2i(0, 1))
			verify(view.issued.size() == turn + 1 and view.issued[-1] == {"action": "place", "kind": "collector", "cell": [0, 1],
				"level": 0, "axis": ["z", "x", "z", "x"][turn], "rotation": turn},
				"The ordinary placement callback emits the literal selected facing and drive axis.")
			view.rotation_button.pressed.emit()
		verify(view.building_rotation == 0 and view.state == before and view.request_sequence == sequence and view.model == null,
			"Four ordinary rotate callbacks wrap without changing authority, stock or requests.")
		view.mode = "processor"
		var key := InputEventKey.new()
		key.keycode = KEY_R
		key.pressed = true
		view._unhandled_input(key)
		verify(view.building_rotation == 1 and view.request_sequence == sequence,
			"The ordinary R callback turns a building without submitting an action.")
		for _turn in range(3):
			view._rotate_building()
		var press_port := Node3D.new()
		view._preview_port(press_port, 1, false)
		verify(press_port.get_node("MaterialPortLabel").text == "IN" and (press_port.get_node("MaterialPortLabel").get_meta("port_side") as Vector3).is_equal_approx(Vector3.FORWARD),
			"The press input is opposite its output at the rotated side.")
		press_port.free()
		view.explanation_open = true
		view._rotate_building()
		verify(view.building_rotation == 0, "Help prevents construction rotation callbacks.")
		view.explanation_open = false
		view.startup_save_pending = true
		view._rotate_building()
		verify(view.building_rotation == 0, "Pending startup restoration prevents construction rotation callbacks.")
		view.startup_save_pending = false
		view.mode = "wheel"
		view.transmission_controls.selected_axis = "x"
		view._rotate_building()
		verify(view.transmission_controls.selected_axis == "z", "Rotate turns a horizontal wheel axle by a quarter turn.")
		view.transmission_controls.selected_axis = "y"
		view._refresh_ui()
		view._rotate_building()
		verify(view.rotation_button.disabled and view.transmission_controls.selected_axis == "y",
			"A horizontal turn does not silently tilt a vertical wheel axle.")
		view.mode = "foundation"
		view._refresh_ui()
		view._rotate_building()
		verify(not view.rotation_button.visible and view.building_rotation == 0,
			"Square foundations retain their common grid rather than a cosmetic rotation state.")
		view.free()
	print("%d building-rotation view checks" % checks)
	quit(1 if failures else 0)

func _interaction_controls() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)
	for shared in [false, true]:
		var view = SharedWidgets.new() if shared else OfflineWidgets.new()
		if shared:
			view.session = SessionStub.new()
		view.state = hotbar_observation()
		view.state.entities = {"press": {"kind": "processor", "cell": [1, 0], "level": 0, "axis": 2}}
		view.mode = "collector"
		view.pointed = "press"
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view._build_interface()
		view._refresh_ui()
		var before: Dictionary = view.state.duplicate(true)
		var sequence: int = view.request_sequence
		verify(view.tool_buttons.has("flow") and not view.tool_buttons.has("inspect")
			and view.placement_options_panel != null and not view.placement_options_panel.visible,
			"The playable build UI has no Inspect button or idle ghost options.")
		view.machine_preview = Node3D.new()
		view.add_child(view.machine_preview)
		view.machine_preview.visible = true
		view._refresh_placement_options()
		verify(view.placement_options_panel.visible and view.placement_options_title.text == "PLACE COLLECTOR"
			and view.rotation_button.visible and "R" in view.rotation_button.text,
			"A selected collector ghost exposes a visible placement menu and Rotate action.")
		view.rotation_button.pressed.emit()
		verify(view.building_rotation == 1 and view.issued.is_empty() and view.state == before,
			"The ghost menu turns local placement state without issuing a build command.")
		view.mode = "wheel"
		view._refresh_ui()
		view._refresh_placement_options()
		var old_axis: String = view.transmission_controls.selected_axis
		view.placement_options_axis.pressed.emit()
		verify(view.placement_options_axis.visible and view.transmission_controls.selected_axis != old_axis
			and view.foundation_level_controls.visible and view.wheel_size_controls.visible,
			"The wheel ghost offers axle, height and diameter controls in the same menu.")
		view.mode = "foundation"
		view._refresh_ui()
		view._refresh_placement_options()
		verify(view.foundation_area_toggle.visible and view.foundation_steps_toggle.visible
			and view.placement_options_panel.visible,
			"The foundation ghost exposes area, access step and height choices.")
		view.machine_preview.visible = false
		view._refresh_placement_options()
		verify(not view.placement_options_panel.visible, "The placement menu leaves when its ghost leaves.")
		view.mode = "gear"
		view.transmission_controls.choose_tool("gear")
		view._refresh_placement_options()
		verify(view.placement_options_panel.visible and view.placement_options_axis.visible
			and view.transmission_controls.get_parent() == view.placement_options_column,
			"Cogwheel placement keeps axis, height and size in the contextual menu.")
		view.transmission_controls.cancel()
		view.mode = "collector"
		view.machine_preview.visible = true
		view.building_hotbar.open_catalog()
		view._refresh_placement_options()
		verify(not view.placement_options_panel.visible, "The modal catalog hides the ghost options.")
		view.building_hotbar.catalog.hide()
		view.machine_preview.visible = false
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_E
		view._unhandled_input(key)
		verify(view.mode == "inspect" and view.selected == "press" and view.inspector.visible
			and view.issued.is_empty() and view.request_sequence == sequence,
			"E opens the pointed press through the existing read-only inspector without an authority request.")
		key.keycode = KEY_F
		view._unhandled_input(key)
		verify(view.mode == "deconstruct" and view.transmission_controls.active_tool.is_empty(),
			"F enters a separate deconstruction mode and cancels placement.")
		view._world_click(Vector2i(1, 0), "press")
		verify(view.issued.size() == 1 and view.issued[0] == {"action": "remove", "entity": "press"},
			"Clicking a machine in deconstruction mode submits its existing native removal action.")
		view.state.belt_spans = {"span": {"from": "shaft-a", "slots": []}}
		view._world_click(Vector2i.ZERO, "span")
		verify(view.issued.size() == 2 and view.issued[1] == {"action": "remove_belt_span", "entity": "span"},
			"The same mode uses the distinct native belt-span removal action.")
		view._world_click(Vector2i.ZERO)
		verify(view.issued.size() == 2, "An empty click cannot invent a deconstruction target.")
		key.keycode = KEY_ESCAPE
		view._unhandled_input(key)
		verify(view.mode == "inspect" and view.issued.size() == 2 and view.state.get("entities") == before.entities,
			"Escape leaves deconstruction without changing the confirmed worksite.")
		view.free()
	print("%d placement-interaction view checks" % checks)
	quit(1 if failures else 0)

func _hotbar() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)
	for shared in [false, true]:
		var view = SharedWidgets.new() if shared else OfflineWidgets.new()
		if shared:
			view.session = SessionStub.new()
		view.state = hotbar_observation()
		view.request_sequence = 17
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view._build_interface()
		if view.building_hotbar == null or view.building_hotbar.buttons.size() != 8 or view.building_hotbar.catalog == null:
			verify(false, "The complete hotbar must mount before dependent controls run.")
			view.free()
			quit(1)
			return
		view._refresh_ui()
		await settle_widgets()
		var bar = view.building_hotbar
		var before: Dictionary = view.state.duplicate(true)
		view._update_fps_counter(0.26)
		verify(view.fps_label.text.begins_with("FPS ") and view.fps_label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"The live frame-rate readout updates without intercepting construction input.")
		verify(bar.buttons.size() == 8 and not bar.catalog.visible and not view.tool_buttons.collector.is_visible_in_tree(),
			"Eight quick slots replace the visible construction text list.")
		verify(bar.selected_slot == -1 and not view.inspector.visible
			and not bar.buttons.any(func(button: Button): return button.button_pressed)
			and view.issued.is_empty() and view.request_sequence == 17 and view.state == before,
			"An untouched view has no active construction slot and sends no game request.")
		var first_choice := InputEventKey.new()
		first_choice.keycode = KEY_1
		first_choice.pressed = true
		view._unhandled_input(first_choice)
		verify(view.mode == "collector" and bar.selected_slot == 0 and bar.buttons[0].button_pressed
			and view.issued.is_empty() and view.request_sequence == 17 and view.state == before,
			"An intentional Collector quick-slot choice selects only local construction state.")
		var identities: Array = bar.buttons.map(func(button: Button): return button.get_instance_id())
		view._refresh_ui()
		view._refresh_ui()
		verify(bar.buttons.map(func(button: Button): return button.get_instance_id()) == identities,
			"Repeated confirmed-state refresh reuses the mounted slots.")
		var event := InputEventKey.new()
		event.keycode = KEY_3
		event.pressed = true
		view._unhandled_input(event)
		verify(view.mode == "belt" and view.transmission_controls.active_tool == "belt_span" and bar.selected_slot == 2 and bar.buttons[2].button_pressed,
			"The Belt quick slot selects shaft-to-shaft placement through the ordinary selection path.")
		view.transmission_controls.cancel()
		view._world_click(Vector2i.ZERO)
		verify(view.request_sequence == 17 and "two parallel shafts" in view.status_label.text,
			"A missing active connector cannot fall back to single-cell belt placement.")
		bar.select_slot(2)
		bar.open_catalog(7)
		verify(bar.catalog.visible and bar.destination.item_count == 8 and bar.destination.selected == 7,
			"The catalog exposes a concrete destination slot.")
		verify(not view._can_control_character() and not bar.catalog_buttons.processor.disabled,
			"The modal catalog holds movement while keeping part assignment available.")
		bar.catalog_buttons.processor.pressed.emit()
		verify(bar.slots[7] == "processor" and view.mode == "processor" and not bar.catalog.visible and view._can_control_character(),
			"Choosing a carried part assigns the slot and selects its actual tool.")
		bar.open_catalog(7)
		bar.catalog_buttons.collector.pressed.emit()
		verify(bar.slots[7] == "collector" and view.mode == "collector" and bar.selected_slot == 7,
			"The same catalog interaction replaces an existing assignment.")
		bar.open_catalog(7)
		bar.clear_slot()
		verify(bar.slots[7].is_empty() and view.mode == "inspect", "Clearing the active slot returns to inspection.")
		bar.select_slot(7)
		verify(bar.catalog.visible and bar.destination.selected == 7, "An empty slot opens its assignment catalog.")
		bar.catalog.hide()
		bar.select_slot(5)
		verify(view.mode == "gear" and view.transmission_controls.active_tool == "gear", "Cog slots reuse the native transmission selector.")
		view.transmission_controls.gear_teeth = 4
		bar.select_slot(5)
		verify(view.transmission_controls.gear_teeth == 4, "A valid chosen cog size survives quick selection.")
		bar.select_slot(6)
		verify(view.mode == "drive" and view.transmission_controls.active_tool == "place_shaft", "Shaft slots select actual segment placement.")
		verify(view.state == before and view.model == null and view.actor_world == null and view.request_sequence == 17,
			"Assignment, replacement and tool selection create no authority or construction requests.")
		view._select_tool("inspect")
		view.state.part_kits.P.collector = 0
		view._refresh_ui()
		bar.select_slot(0)
		verify(bar.buttons[0].disabled and "×0" in bar.buttons[0].text and view.mode == "inspect",
			"An exhausted kit disables the slot without borrowing the compatibility stock alias.")
		bar.destination.select(7)
		bar.catalog_buttons.collector.pressed.emit()
		verify(bar.slots[7].is_empty() and view.mode == "inspect", "An unavailable catalog item cannot activate or fill a slot.")
		view.client = "Q"
		view._refresh_ui()
		verify("×2" in bar.buttons[1].text and bar.buttons[0].disabled, "Every slot follows the active actor's own kit.")
		view.state.part_kits.erase("Q")
		view._refresh_ui()
		verify(bar.buttons[1].disabled and "×0" in bar.buttons[1].text, "Missing actor kits have no fallback owner.")
		view.client = "P"
		view.state = hotbar_observation()
		if shared:
			view.pending_actions = {"waiting": {}}
			view._refresh_ui()
			bar.select_slot(0)
			verify(bar.buttons[0].disabled and view.mode == "inspect", "Shared pending decisions block quick selection.")
			view.pending_actions.clear()
			view._select_tool("collector")
			view.session.ready = false
			view._refresh_ui()
			verify(bar.buttons[0].disabled, "Disconnection leaves the retained kit unavailable.")
			bar.open_catalog(0)
			bar.clear_slot()
			verify(bar.slots[0].is_empty() and view.mode == "inspect" and view.transmission_controls.active_tool.is_empty(),
				"Clearing an active slot while disconnected cancels local construction without a request.")
			bar.slots[0] = "collector"
			view.session.ready = true
		view.startup_save_pending = true
		view._refresh_ui()
		verify(bar.buttons[0].disabled, "The startup save barrier also gates the hotbar.")
		view.startup_save_pending = false
		view.state.actors.P.ready = false
		view._refresh_ui()
		verify(bar.buttons[0].disabled, "A ready connection cannot substitute for the actor's readiness.")
		view.state.actors.P.ready = true
		view.explanation_open = true
		view._refresh_ui()
		bar.open_catalog()
		verify(bar.catalog_button.disabled and not bar.catalog.visible and bar.buttons[0].disabled, "Help keeps both selection surfaces inactive.")
		view.explanation_open = false
		view._refresh_ui()
		for dimensions in [Vector2i(1280, 800), Vector2i(1600, 900), Vector2i(1920, 1080)]:
			root.size = dimensions
			await settle_widgets()
			var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
			var bounds: Rect2 = bar.get_global_rect()
			verify(viewport.encloses(bounds) and is_equal_approx(bounds.end.y, dimensions.y - 18.0), "The complete hotbar fits the supported viewport and bottom margin.")
			var fps_bounds: Rect2 = view.fps_label.get_global_rect()
			verify(viewport.encloses(fps_bounds) and fps_bounds.end.x < bounds.position.x - 8.0,
				"The FPS readout stays in the free lower-left margin at supported viewport sizes.")
			for button: Button in bar.buttons:
				verify(bounds.encloses(button.get_global_rect()) and button.size.x >= button.get_combined_minimum_size().x, "Every slot remains inside the bar without shrinking its content.")
			verify(view.status_footer.get_global_rect().end.y <= bounds.position.y - 11.5, "The status footer stays above the hotbar.")
			bar.open_catalog(0)
			await settle_widgets()
			verify(viewport.encloses(Rect2(Vector2(bar.catalog.position), Vector2(bar.catalog.size))), "The complete catalog fits the supported viewport.")
			verify(bar.catalog.position.y + bar.catalog.size.y <= view.status_footer.position.y - 11.5,
				"The catalog leaves status text readable below its own surface.")
			bar.catalog.hide()
		bar.open_catalog(0)
		root.size = Vector2i(1280, 800)
		await settle_widgets()
		verify(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(Rect2(Vector2(bar.catalog.position), Vector2(bar.catalog.size))),
			"An already open catalog stays inside the viewport after shrinking it.")
		bar.catalog.hide()
		verify(view.request_sequence == 17 and view.model == null and view.actor_world == null,
			"Layout and connection transitions create neither a request nor a simulation.")
		view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"failures": failures, "models": 0, "desktop_operations": 0, "scope": "ordinary/shared hotbar over invented projections"}))
	quit(0 if failures == 0 else 1)

func _render_hotbar() -> void:
	var prefix := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--hotbar-image-prefix="):
			prefix = argument.trim_prefix("--hotbar-image-prefix=")
	if prefix.is_empty() or DisplayServer.get_name().to_lower() == "headless":
		verify(false, "The presentation readback requires an output prefix and isolated rendered display.")
		quit(1)
		return
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)
	var view := OfflineWidgets.new()
	view.state = hotbar_observation()
	root.add_child(view)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	view._build_interface()
	view._refresh_ui()
	view._update_fps_counter(0.26)
	view._message("Choose Collector [1] to build at the mineral seam.")
	await settle_widgets()
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-bar.png") == OK, "Retain the isolated hotbar presentation.")
	var bar = view.building_hotbar
	bar.open_catalog(7)
	await settle_widgets()
	verify(not view.inspector.get_parent().get_parent().visible,
		"Opening the fresh catalog does not expose an unused machine inspector.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-catalog.png") == OK, "Retain the isolated assignment catalog.")
	var record := FileAccess.open(prefix + "-layout.json", FileAccess.WRITE)
	verify(record != null, "Retain actual widget bounds beside the isolated images.")
	if record != null:
		record.store_string(JSON.stringify({"observation": "invented offline widgets", "viewport": [root.size.x, root.size.y],
			"bar_position": [bar.position.x, bar.position.y], "bar_size": [bar.size.x, bar.size.y],
			"catalog_position": [bar.catalog.position.x, bar.catalog.position.y], "catalog_size": [bar.catalog.size.x, bar.catalog.size.y],
			"slots": bar.slots, "models": 0, "desktop_operations": 0}))
		record.close()
	view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"models": 0, "desktop_operations": 0, "observations": "invented", "scope": "isolated UI images; no logical-case replay"}))
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
		verify(view.tool_buttons.collector.disabled and "0" in view.tool_buttons.collector.text,
			"An unavailable catalog part stays disabled when the observation profile changes.")
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
