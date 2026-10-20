extends Node
## Test-only autoload in a captured external project; the normal scene owns play.
## Window geometry and ordinary input are observed without writing game state.
var scene
var shared := false
var role := "P"
var report_path := ""
var finish_path := ""
var directory := ""
var deadline := 0
var samples: Array = []
var clicks: Array = []
var disclosure_checks: Array = []
var failures: Array[String] = []
var connected_revision := -1
var polling_held := false
var original_poll := true

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--layout-report="):
			report_path = argument.trim_prefix("--layout-report=")
		elif argument.begins_with("--launch-report="):
			shared = true
			report_path = argument.trim_prefix("--launch-report=")
		elif argument.begins_with("--launch-finish-file="):
			finish_path = argument.trim_prefix("--launch-finish-file=")
		elif argument.begins_with("--session-role="):
			role = argument.trim_prefix("--session-role=")
	deadline = Time.get_ticks_msec() + 20000
	if not need(report_path.is_absolute_path(), "The observer requires an owned absolute report path."):
		finish()
		return
	directory = report_path.get_base_dir()
	if not await wait_for(ready, "The normal physical opening must become ready."):
		finish()
		return
	connected_revision = projection().revision
	if not await guided_start():
		finish()
		return
	if not await collector():
		finish()
		return
	await key(KEY_I)
	await click_cell(Vector2i(0, 0))
	if not need(scene.selected == "collector-1", "Ordinary inspection must select the actual collector."):
		finish()
		return
	if not await guided_collector():
		finish()
		return
	await rendered()
	if not await capture("initial"):
		finish()
		return
	if not need(get_window().min_size == Vector2i(1280, 800), "The opening must disclose its revisable minimum client size.") or not await resize_to(Vector2i(960, 600)):
		finish()
		return
	if not need(get_window().size == Vector2i(1280, 800), "An undersized request must respect the declared minimum."):
		finish()
		return
	for size in [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1920, 800)]:
		var before: Dictionary = logical()
		if not await resize_to(size) or not await capture("resize-%d-%d" % [size.x, size.y]):
			finish()
			return
		need(logical() == before, "Resizing must preserve material, parts, topology, context and command order.")
		need(scene.selected == "collector-1", "Resizing must preserve the inspected machine.")
		if not failures.is_empty():
			finish()
			return
	var restored_size: Vector2i = get_window().size
	get_window().mode = Window.MODE_MAXIMIZED
	if not await wait_for(func() -> bool: return get_window().mode == Window.MODE_MAXIMIZED and get_window().size != restored_size, "The native window must actually enter maximized mode at a changed size."):
		finish()
		return
	await rendered()
	if not await capture("maximized"):
		finish()
		return
	get_window().mode = Window.MODE_WINDOWED
	if not await wait_for(func() -> bool: return get_window().mode == Window.MODE_WINDOWED and get_window().size == restored_size, "Restore must recover the previous native window size."):
		finish()
		return
	await rendered()
	if not await capture("restored") or not await resize_to(Vector2i(1280, 800)) or not await capture("minimum-restored"):
		finish()
		return
	var help_button: Button
	for child in scene.tool_buttons.collector.get_parent().get_children():
		if child is Button and child.text.begins_with("How this line works"):
			help_button = child
	if not need(help_button != null, "The ordinary Help button must exist."):
		finish()
		return
	var before_help: Dictionary = logical()
	if not await click_button(help_button, "Open Help") or not need(scene.explanation_open, "The actual Help button must open the separate example.") or not await capture("help-minimum"):
		finish()
		return
	if not await resize_to(Vector2i(1920, 1080)) or not await capture("help-enlarged") or not await click_button(scene.lesson_return, "Return from Help"):
		finish()
		return
	if not need(not scene.explanation_open and logical() == before_help, "Help and its resizing must leave the live worksite unchanged.") or not await resize_to(Vector2i(1600, 900)):
		finish()
		return
	var before_walk: Array = projection().actors[role].position.duplicate()
	await key_edge(KEY_W, true)
	for _frame in range(5):
		await get_tree().physics_frame
	await key_edge(KEY_W, false)
	if not await wait_for(func() -> bool:
		return projection().actors[role].position != before_walk and scene.character_presenter.held_keys.is_empty(), "Ordinary walking after resize must move and release the physical actor."):
		finish()
		return
	if not await released_walk():
		finish()
		return
	await rendered()
	if not await capture("walk-released"):
		finish()
		return
	if shared:
		if not await shared_views():
			finish()
			return
	else:
		if not await click_button(scene.remove_button, "Dismantle empty collector"):
			finish()
			return
		need(projection().entities.is_empty() and projection().parts.collector == 1 and projection().order == 2, "The actual resized removal button must refund the single empty collector once.")
	if not failures.is_empty() or not await guided_return():
		finish()
		return
	await capture("final")
	finish()

func ready() -> bool:
	scene = get_tree().current_scene
	if scene == null or scene.get("model") == null or scene.get("legacy_fixture") != false:
		return false
	if shared and (scene.get("session") == null or not scene.session.is_ready()):
		return false
	return projection().get("actors", {}).get(role, {}).get("ready", false)

func projection() -> Dictionary:
	return scene.model.projection()

func logical() -> Dictionary:
	var state: Dictionary = projection()
	var value: Dictionary = {}
	for field in ["context", "initial_feed", "recipe_input", "entities", "links", "drive_links", "parts", "inventories", "remaining", "options", "power_enabled", "order", "stock"]:
		value[field] = state[field]
	return value

func wait_for(predicate: Callable, label: String) -> bool:
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return need(false, label)

func rendered() -> void:
	for _frame in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

func resize_to(size: Vector2i) -> bool:
	if not failures.is_empty():
		return false
	get_window().size = size
	var wanted := Vector2i(maxi(size.x, get_window().min_size.x), maxi(size.y, get_window().min_size.y))
	if not await wait_for(func() -> bool: return get_window().size == wanted, "The actual native window must reach its requested supported size."):
		return false
	await rendered()
	return failures.is_empty()

func rectangle(control: Control) -> Array:
	var bounds := control.get_global_rect()
	return [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]

func capture(label: String) -> bool:
	await rendered()
	var viewport := get_viewport().get_visible_rect()
	var right: Control = scene.inspector.get_parent().get_parent()
	var bottom: Control = scene.status_label.get_parent().get_parent()
	var build: Control = scene.tool_buttons.collector.get_parent().get_parent()
	var value := {"label": label, "window_size": [get_window().size.x, get_window().size.y],
		"viewport": [viewport.position.x, viewport.position.y, viewport.size.x, viewport.size.y],
		"window_mode": get_window().mode, "inspector_panel": rectangle(right),
		"footer_panel": rectangle(bottom), "build_panel": rectangle(build),
		"inspector": scene.inspector.text, "status": scene.status_label.text,
		"selected": scene.selected, "projection": projection(),
		"namespace": scene.request_namespace, "material_sequence": scene.request_sequence,
		"help_open": scene.explanation_open, "buttons": {},
		"guided_view": {"all_tools": scene.show_all_tools, "details": scene.show_details,
			"visible_tools": visible_tools(), "goal": scene.goal_label.text,
			"stock_visible": scene.stock_label.is_visible_in_tree(), "power_visible": scene.power_label.is_visible_in_tree()}}
	if shared:
		value["pending"] = scene.pending_actions.duplicate(true)
		value["connected"] = scene.session.is_ready()
	var right_rect := right.get_global_rect()
	var bottom_rect := bottom.get_global_rect()
	need(absf(right_rect.end.x - (viewport.end.x - 18)) <= 1, label + ": The inspector must follow the right viewport edge.")
	need(absf(bottom_rect.end.x - (viewport.end.x - 18)) <= 1, label + ": The footer must expand to the right viewport edge.")
	need(absf(bottom_rect.end.y - (viewport.end.y - 18)) <= 1, label + ": The footer must follow the bottom viewport edge.")
	need(not right_rect.intersects(bottom_rect), label + ": Inspector controls must remain above the footer.")
	need(viewport.encloses(build.get_global_rect()) and not build.get_global_rect().intersects(right_rect), label + ": The build panel must remain visible and separate.")
	var entries := [["confirm", scene.confirm_button], ["retrieve", scene.retrieve_button], ["power", scene.power_button], ["remove", scene.remove_button], ["save", scene.save_button], ["load", scene.load_button], ["all_tools", scene.all_tools_button], ["details", scene.details_button]]
	for tool in scene.tool_buttons:
		entries.append(["tool-" + tool, scene.tool_buttons[tool]])
	for entry in entries:
		var button: Button = entry[1]
		var visible := button.is_visible_in_tree()
		value.buttons[entry[0]] = {"rect": rectangle(button), "visible": visible, "disabled": button.disabled, "text": button.text}
		if visible:
			need(viewport.encloses(button.get_global_rect()), label + ": Every visible named button must remain in the actual viewport.")
			need(not button.get_global_rect().intersects(bottom_rect), label + ": Visible buttons must not be hidden by the footer.")
			var owner_bounds := build.get_global_rect() if build.is_ancestor_of(button) else right_rect
			need(owner_bounds.encloses(button.get_global_rect()), label + ": A visible named button must fit its containing panel.")
	need(scene.goal_label.size.y + 1 >= scene.goal_label.get_minimum_size().y, label + ": The next-action prompt must retain its complete wrapped text.")
	need(scene.inspector.size.y + 1 >= scene.inspector.get_minimum_size().y, label + ": The inspector must retain its complete wrapped text.")
	need(scene.status_label.size.y + 1 >= scene.status_label.get_minimum_size().y, label + ": The status must retain its complete wrapped text.")
	if scene.explanation_open:
		value["lesson_panel"] = rectangle(scene.lesson_panel)
		value["example_panel"] = rectangle(scene.example_presenter)
		for panel in [scene.lesson_panel, scene.example_presenter]:
			var bounds: Rect2 = panel.get_global_rect()
			need(viewport.encloses(bounds) and not bounds.intersects(right_rect) and not bounds.intersects(bottom_rect) and not bounds.intersects(build.get_global_rect()), label + ": Help must fit between the live interface panels.")
		need(scene.all_tools_button.disabled and scene.details_button.disabled, label + ": Help must keep both ordinary view toggles disabled.")
	var image := directory.path_join("layout-" + label + ".png")
	need(get_tree().root.get_texture().get_image().save_png(image) == OK, label + ": The original rendered viewport must be retained.")
	value["image"] = image
	samples.append(value)
	publish(directory.path_join("layout-" + label + ".json"), value)
	return failures.is_empty()

func key_edge(code: Key, pressed: bool) -> void:
	if pressed and not failures.is_empty():
		return
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().process_frame

func key(code: Key) -> void:
	await key_edge(code, true)
	await key_edge(code, false)

func click(point: Vector2) -> void:
	if not failures.is_empty():
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func click_cell(cell: Vector2i) -> void:
	var point: Vector2 = scene.camera.unproject_position(Vector3(cell.x * 1.65, 0.08, cell.y * 1.65))
	await click(point)

func click_button(button: Button, label: String) -> bool:
	if not failures.is_empty():
		return false
	await rendered()
	if not need(button.is_visible_in_tree() and get_viewport().get_visible_rect().encloses(button.get_global_rect()), label + ": An ordinary click requires a visible button inside the viewport."):
		return false
	var observed := {"pressed": 0}
	var listener := func() -> void: observed.pressed += 1
	button.pressed.connect(listener)
	var point := button.get_global_rect().get_center()
	var record := {"label": label, "rect": rectangle(button), "point": [point.x, point.y], "disabled": button.disabled}
	await click(point)
	button.pressed.disconnect(listener)
	record["pressed"] = observed.pressed
	clicks.append(record)
	return need(not record.disabled and observed.pressed == 1, label + ": One ordinary enabled click must emit one actual pressed signal.")

func visible_tools() -> Array:
	var tools: Array[String] = []
	for tool in scene.tool_buttons:
		if scene.tool_buttons[tool].is_visible_in_tree():
			# The oracle compares names, not interned-key or mixed Variant ordering.
			tools.append(String(tool))
	tools.sort()
	return tools

func record_disclosure(label: String) -> bool:
	await rendered()
	var keys: Array = []
	for tool in scene.tool_buttons:
		var button: Button = scene.tool_buttons[tool]
		keys.append({"name": String(tool), "key_type": type_string(typeof(tool)),
			"visible": button.is_visible_in_tree(), "disabled": button.disabled})
	var value := {"label": label, "actor": role, "frame": Engine.get_process_frames(),
		"all_tools": scene.show_all_tools, "details": scene.show_details,
		"mode": String(scene.mode), "visible_tools": visible_tools(), "tool_keys": keys,
		"button_clicks": clicks.duplicate(true), "namespace": scene.request_namespace,
		"material_sequence": scene.request_sequence}
	var image := directory.path_join("disclosure-" + label + ".png")
	if not need(get_tree().root.get_texture().get_image().save_png(image) == OK, "The actual post-click disclosure image must be retained."):
		return false
	value["image"] = image
	disclosure_checks.append(value)
	return publish(directory.path_join("disclosure-" + label + ".json"), value)

func guided_start() -> bool:
	var before: Dictionary = logical()
	if not need(projection().entities.is_empty() and projection().order == 0 and projection().stock.source == 16, "Both fresh clients must see the unchanged empty finite worksite before any build."):
		return false
	if not need(not scene.show_all_tools and not scene.show_details and visible_tools() == ["collector"], "The actual fresh view must offer only the Collector build tool."):
		return false
	if not need(not scene.stock_label.is_visible_in_tree() and not scene.power_label.is_visible_in_tree() and not scene.save_button.is_visible_in_tree() and not scene.load_button.is_visible_in_tree() and not scene.power_button.is_visible_in_tree(), "Fresh disclosure must hide global details, save controls and the unused power control.") or not await capture("fresh-guided"):
		return false
	await key(KEY_4)
	if not need(scene.mode == "wheel" and visible_tools() == ["collector", "wheel"], "An original early keyboard choice must remain visible without placing anything."):
		return false
	await key(KEY_1)
	if not await click_button(scene.all_tools_button, "Show every existing tool"):
		return false
	if not await record_disclosure("all-tools"):
		return false
	if not need(scene.show_all_tools and visible_tools() == ["belt", "collector", "drive", "flow", "inspect", "processor", "wheel"], "All tools must expose every existing tool through its ordinary button."):
		return false
	if not await click_button(scene.details_button, "Show worksite details"):
		return false
	if not need(scene.show_details and scene.stock_label.is_visible_in_tree() and scene.power_label.is_visible_in_tree() and scene.save_button.is_visible_in_tree() and scene.load_button.is_visible_in_tree(), "Details must expose the original counters and save controls.") or not await capture("fresh-all-details"):
		return false
	if not await click_button(scene.details_button, "Hide fresh worksite details") or not await click_button(scene.all_tools_button, "Restore fresh guided tools"):
		return false
	if not need(not scene.show_all_tools and not scene.show_details and visible_tools() == ["collector"] and logical() == before, "Ordinary view toggles and early tool selection must preserve the entire logical worksite."):
		return false
	if shared:
		var common := directory.get_base_dir()
		var other := "Q" if role == "P" else "P"
		if not publish_phase(common, "fresh-view", {}) or not await wait_phase(common, other, "fresh-view"):
			return false
	return true

func guided_collector() -> bool:
	if not need(visible_tools() == ["belt", "collector", "inspect"] and not scene.show_details and "Add a belt" in scene.goal_label.text, "The confirmed Collector must expose the Belt and inspection without revealing all tools.") or not await capture("collector-guided"):
		return false
	var before: Dictionary = logical()
	if not await click_button(scene.all_tools_button, "Show all tools for resize coverage") or not await click_button(scene.details_button, "Show all details for resize coverage"):
		return false
	return need(scene.show_all_tools and scene.show_details and logical() == before, "The worst visible tool/detail view must be reached only through ordinary non-mutating clicks.")

func guided_return() -> bool:
	var before: Dictionary = logical()
	if not await click_button(scene.tool_buttons.collector, "Choose Collector after dismantling") or not await click_button(scene.details_button, "Hide final worksite details") or not await click_button(scene.all_tools_button, "Return to guided tools after dismantling"):
		return false
	return need(not scene.show_all_tools and not scene.show_details and visible_tools() == ["collector"] and "Place a collector" in scene.goal_label.text and logical() == before, "The dismantled worksite must derive fresh guidance without resetting material, parts or history.")

func collector() -> bool:
	if not shared or role == "P":
		await key(KEY_1)
		await click_cell(Vector2i(0, 0))
	return await wait_for(func() -> bool:
		return projection().entities.has("collector-1") and projection().order == 1 and (not shared or scene.pending_actions.is_empty()), "One ordinary input must place the finite starter collector.")

func released_walk() -> bool:
	var previous: Dictionary = projection().actors[role]
	var stable := 0
	while Time.get_ticks_msec() < deadline and stable < 3:
		await get_tree().physics_frame
		await get_tree().process_frame
		var current: Dictionary = projection().actors[role]
		if current.native_epoch <= previous.native_epoch:
			continue
		stable = stable + 1 if current.position[0] == previous.position[0] and current.position[2] == previous.position[2] else 0
		previous = current
	return need(stable == 3 and scene.character_presenter.held_keys.is_empty(), "Three fresh native observations must show stable horizontal position after the walking keys are released.")

func shared_views() -> bool:
	if not failures.is_empty():
		return false
	var common := directory.get_base_dir()
	if not publish_phase(common, "resized", {}):
		return false
	if role == "P":
		if not await wait_phase(common, "Q", "resized"):
			return false
		# This local observer shortcut holds client receipt processing only.
		# The server remains live and owns the ordinary request and its outcome.
		original_poll = get_tree().multiplayer_poll
		polling_held = true
		get_tree().multiplayer_poll = false
		if not await click_button(scene.remove_button, "Remove with a retained pending view"):
			restore_polling()
			return false
		need(scene.pending_actions.size() == 1, "The actual ordinary removal must have one unresolved client request.")
		await capture("pending")
		need("Action awaiting the server." in scene.inspector.text, "The rendered pending inspector must name its actual wait.")
		need(scene.goal_label.text == "Waiting for the server decision.", "Pending disclosure must name the same unresolved server decision.")
		restore_polling()
		if not failures.is_empty():
			return false
		if not await wait_for(func() -> bool: return scene.pending_actions.is_empty() and projection().order == 2, "The same pending request must settle after ordinary polling resumes."):
			return false
		if not need(scene.last_outcome.accepted and not scene.last_outcome.duplicate and scene.last_outcome.reason == "removed", "The original pending removal must have one fresh accepted disposition."):
			return false
		if not need(projection().entities.is_empty() and projection().parts.collector == 1 and projection().stock.source == 16, "Validated removal readiness requires the actual refunded part and conserved material."):
			return false
		if not publish_phase(common, "removal-settled", {"order": projection().order, "last_outcome": scene.last_outcome}):
			return false
	else:
		if not await wait_phase(common, "P", "removal-settled") or not await wait_for(func() -> bool: return projection().order == 2, "Q must observe P's same authoritative removal."):
			return false
	if not need(projection().entities.is_empty() and projection().parts.collector == 1 and projection().stock.source == 16, "The shared removal must refund the empty part without changing finite material."):
		return false
	var old_namespace: String = scene.request_namespace
	if not await click_button(scene.disconnect_button, "Disconnect after resize") or not await resize_to(Vector2i(1920, 800)) or not await capture("disconnected"):
		return false
	if not need(not scene.session.is_ready() and "Last confirmed state only." in scene.inspector.text and scene.goal_label.text == "Reconnect to continue.", "The resized disconnected inspector and guidance must identify their stale view.") or not await click_button(scene.reconnect_button, "Reconnect after resize"):
		return false
	if not await wait_for(func() -> bool: return scene.session.is_ready() and scene.request_namespace != old_namespace, "An ordinary reconnect must obtain its own new namespace."):
		return false
	if not need(scene.request_sequence == 0 and scene.pending_actions.is_empty() and projection().order == 2, "Reconnect must retain the world while starting only the new caller sequence."):
		return false
	if not publish_phase(common, "reconnected", {"namespace": scene.request_namespace}):
		return false
	var other := "Q" if role == "P" else "P"
	if not await wait_phase(common, other, "reconnected"):
		return false
	if not await wait_for(func() -> bool:
		return projection().actors.P.ready and projection().actors.Q.ready, "Both ordinary reconnects must finish before either final normal observation."):
		return false
	return true

func restore_polling() -> void:
	if polling_held:
		get_tree().multiplayer_poll = original_poll
		polling_held = false

func publish_phase(common: String, phase: String, details: Dictionary) -> bool:
	if not failures.is_empty():
		return false
	if not need(not polling_held, "Validated readiness requires the original client polling mode to be restored."):
		return false
	var value := {"status": "pass", "actor": role, "phase": phase, "details": details}
	return publish(common.path_join("layout-" + role + "-" + phase + "-validated.json"), value)

func wait_phase(common: String, actor: String, phase: String) -> bool:
	var path := common.path_join("layout-" + actor + "-" + phase + "-validated.json")
	while Time.get_ticks_msec() < deadline and failures.is_empty():
		if FileAccess.file_exists(path):
			var value = JSON.parse_string(FileAccess.get_file_as_string(path))
			return need(value is Dictionary and value.get("status") == "pass" and value.get("actor") == actor and value.get("phase") == phase, "Only an explicitly successful matching peer phase may release dependent input.")
		var peer_report := common.path_join(actor).path_join("observation.json")
		if FileAccess.file_exists(peer_report):
			var diagnostic = JSON.parse_string(FileAccess.get_file_as_string(peer_report))
			if diagnostic is Dictionary and diagnostic.get("status") == "fail":
				return need(false, "The peer observer failed before validated phase readiness.")
		await get_tree().process_frame
	return need(false, "The validated peer phase did not become ready before the original deadline.")

func publish(path: String, value: Dictionary) -> bool:
	if not need(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".writing"), "Every observer artifact must use a fresh owned path."):
		return false
	var file := FileAccess.open(path + ".writing", FileAccess.WRITE)
	if not need(file != null, "The owned observer artifact must open."):
		return false
	file.store_string(JSON.stringify(value, "", true, true))
	file.close()
	return need(DirAccess.rename_absolute(path + ".writing", path) == OK, "The closed observer artifact must publish atomically.")

func need(condition: bool, label: String) -> bool:
	if not condition:
		failures.append(label)
	return condition

func finish() -> void:
	restore_polling()
	var passed := failures.is_empty()
	# The unchanged normal launcher owns schema 1; case details are additive.
	var value := {"schema": 1, "case": "guided-layout", "status": "pass" if passed else "fail", "actor": role,
		"pid": OS.get_process_id(), "samples": samples,
		"button_clicks": clicks, "disclosure_checks": disclosure_checks, "failures": failures, "limits": [
			"This is agent ordinary-input and rendered-window evidence, not human play or operating-system focus.",
			"The pending cut pauses only client multiplayer polling; it does not establish a natural network delay.",
			"The unchanged empty-collector rules do not resolve trapped stock or running-drive removal."]}
	if scene != null and scene.get("model") != null:
		value["scene"] = scene.scene_file_path
		value["script"] = scene.get_script().resource_path
		value["projection"] = projection()
		value["connected_revision"] = connected_revision
		value["view"] = {"ready": scene.session.is_ready(), "connecting": scene.connecting,
			"model_is_session": scene.model == scene.session, "client_world_is_null": scene.session.world == null,
			"auto_advance": scene.auto_advance, "model_script": scene.model.get_script().resource_path,
			"namespace": scene.request_namespace, "sequence": scene.request_sequence,
			"session_namespace": scene.session.request_namespace, "session_sequence": scene.session.request_sequence,
			"save_slot": scene.save_slot, "save_ready": scene.save_slot_ready, "save_owned": scene.save_slot_owned,
			"save_disabled": scene.save_button.disabled, "load_disabled": scene.load_button.disabled} if shared else {"sequence": scene.request_sequence, "namespace": scene.request_namespace}
		if shared:
			value["session_path"] = str(scene.session.get_path())
	if report_path.is_absolute_path():
		if not publish(report_path, value):
			print("SHARED_OPENING_OBSERVER_FAIL The original observer report could not be published.")
			get_tree().quit(1)
			return
	if shared:
		if not passed:
			print("SHARED_OPENING_OBSERVER_FAIL " + JSON.stringify(failures))
			get_tree().quit(1)
			return
		print("SHARED_OPENING_OBSERVED " + JSON.stringify({"actor": role, "pid": OS.get_process_id()}))
		if not await wait_for(func() -> bool: return FileAccess.file_exists(finish_path), "The original normal supervisor must publish its finish marker."):
			get_tree().quit(1)
			return
	print("OPENING_LAYOUT_PASS" if passed else "OPENING_LAYOUT_FAIL " + JSON.stringify(failures))
	get_tree().quit(0 if passed else 1)
