extends SceneTree
## Exercise actual scene input, then inspect the shared authoritative model.

var scene
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _click_screen(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await physics_frame
	await process_frame

func _click_cell(x: int, z: int = 0) -> void:
	var point: Vector2 = scene.camera.unproject_position(Vector3(x * scene.PITCH, 0.08, z * scene.PITCH))
	await _click_screen(point)

func _connect(key: Key, from_x: int, to_x: int) -> void:
	await _key(key)
	await _click_cell(from_x)
	await _click_cell(to_x)

func _conserved() -> bool:
	var snapshot: Dictionary = scene.model.projection()
	var stock: Dictionary = snapshot.stock
	var raw: int = stock.source + stock.collector + stock.belt + stock.input + stock.held
	return raw + snapshot.recipe_input * (stock.output + stock.player) == snapshot.initial_feed

func _run() -> void:
	root.size = Vector2i(1280, 800)
	scene = load("res://opening/opening.tscn").instantiate()
	scene.auto_advance = false
	root.add_child(scene)
	await process_frame
	await physics_frame
	await process_frame
	_check(scene.model.projection().stock.source == 16, "Opening source must be finite and declared.")
	_check(not scene.goal_confirmed, "Goal cannot begin confirmed.")
	# Mouse placement uses the same actual _unhandled_input path as the player.
	for entry in [[KEY_5, -1], [KEY_1, 0], [KEY_3, 1], [KEY_4, 2]]:
		await _key(entry[0])
		await _click_cell(entry[1])
	var built: Dictionary = scene.model.projection()
	_check(built.entities.size() == 4, "Real scene input must place wheel/collector/belt/press.")
	for kind in ["collector", "belt", "processor", "wheel"]:
		_check(int(built.parts.get(kind, 1)) == 0, "Placement must debit actual carried %s." % kind)
	var revision_before: int = built.revision
	await _key(KEY_1)
	await _click_cell(0)
	_check(scene.model.projection().revision == revision_before, "Refused occupied placement must not mutate authority.")
	await _connect(KEY_F, 0, 1)
	await _connect(KEY_F, 1, 2)
	_check(scene.model.projection().links.size() == 2, "Input must connect real material ports.")
	for pair in [[-1, 0], [0, 1], [1, 2]]:
		await _connect(KEY_G, pair[0], pair[1])
	_check(scene.model.projection().get("drive_links", []).size() == 3, "Input must connect actual drive shafts.")
	_check(scene.model.projection().powered, "Reachable waterwheel must power the built line.")
	# Read-only explanation cannot issue an accidental placement.
	await _key(KEY_H)
	var explained: Dictionary = scene.model.projection()
	await _click_cell(3, 1)
	_check(scene.model.projection() == explained, "Inspectable explanation must not mutate machinery.")
	await _key(KEY_H)
	# Stop with real in-process work, then ensure logical advancement retains it.
	for _tick in range(6):
		scene.model.advance()
		if scene.model.projection().stock.held > 0:
			break
	_check(scene.model.projection().stock.held > 0, "The actual processor must own partial work.")
	await _key(KEY_SPACE)
	var paused: Dictionary = scene.model.projection()
	scene.model.advance(5)
	var still: Dictionary = scene.model.projection()
	_check(still.stock == paused.stock and still.remaining == paused.remaining, "Stopped drive must retain phase and every quantity.")
	scene._refresh()
	await _key(KEY_I)
	await _click_cell(2)
	var held_revision: int = scene.model.projection().revision
	await _click_screen(scene.remove_button.get_global_rect().get_center())
	_check(scene.model.projection().revision == held_revision, "Dismantle must refuse to lose held material.")
	await _key(KEY_SPACE)
	scene.model.advance(18)
	scene._refresh()
	_check(scene.model.projection().stock.output == 1, "Occupied output must retain exactly one plate.")
	_check(_conserved(), "Backpressure must preserve per-kind accounting.")
	# A fresh actual view of restored work must not reuse the old view's IDs.
	var restored = load("res://model.gd").new()
	_check(restored.restore_checkpoint(scene.model.checkpoint()).accepted, "The view can attach to restored authoritative work.")
	scene.free()
	scene = load("res://opening/opening.tscn").instantiate()
	scene.model = restored
	scene.auto_advance = false
	root.add_child(scene)
	await process_frame
	await physics_frame
	await _key(KEY_I)
	await _click_cell(2)
	var collected_before: int = scene.model.projection().inventories.get("P", 0)
	await _key(KEY_R)
	_check(int(scene.model.projection().inventories.get("P", 0)) == collected_before + 1,
		"First eligible retrieval after restored-view creation must succeed without a blind retry.")
	for _tick in range(50):
		scene._refresh()
		if scene.model.projection().stock.output > 0:
			await _key(KEY_R)
		if int(scene.model.projection().inventories.get("P", 0)) >= 4:
			break
		scene.model.advance()
	_check(scene.model.projection().inventories.get("P", 0) >= collected_before + 4, "Real retrieve input must collect four products.")
	_check(_conserved(), "Retrieval must move stock rather than create it.")
	scene._refresh()
	var before_confirm: Dictionary = scene.model.projection()
	await _click_screen(scene.confirm_button.get_global_rect().get_center())
	_check(scene.goal_confirmed, "Actual confirm button must acknowledge eligible session goal.")
	_check(scene.model.projection() == before_confirm, "Goal confirmation must not consume material.")
	# Empty stopped wheel removal tests the real finite-part refund path.
	await _key(KEY_SPACE)
	await _key(KEY_I)
	await _click_cell(-1)
	await _click_screen(scene.remove_button.get_global_rect().get_center())
	_check(scene.model.projection().parts.get("wheel", 0) == 1, "Dismantling must refund the physical wheel part.")
	await _key(KEY_5)
	await _click_cell(-1)
	_check(scene.model.projection().parts.get("wheel", 1) == 0, "Rebuild must use that returned part.")
	await _connect(KEY_G, -1, 0)
	await _key(KEY_SPACE)
	scene._refresh()
	_check(scene.model.projection().powered, "Global Space must resume drive even after a GUI button had focus.")
	_check(not scene.status_label.text.begins_with("Stop the drive"), "Space release must not also activate the previously focused dismantle button.")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			_check(image.save_png(argument.trim_prefix("--capture=")) == OK, "Rendered viewport capture must be saved.")
	if failures.is_empty():
		print("OPENING_INPUT_PASS: actual placement/flow/drive/retention/retrieval/refund/goal scene consumers")
		print(JSON.stringify(scene.model.projection()))
		quit(0)
	else:
		print("OPENING_INPUT_FAIL: ", JSON.stringify(failures))
		quit(1)
