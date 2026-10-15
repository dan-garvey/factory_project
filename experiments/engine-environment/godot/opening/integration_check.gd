extends "res://opening/opening_check.gd"
## Actual save/load keys and buttons through the shared file adapter and model.

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var slot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save-slot="):
			slot = argument.trim_prefix("--save-slot=")
	if slot.is_empty():
		push_error("Integration check requires a fresh external --save-slot")
		quit(1)
		return
	scene = load("res://opening/opening.tscn").instantiate()
	scene.auto_advance = false
	scene.configure_save_slot(slot)
	root.add_child(scene)
	await process_frame
	await physics_frame
	_check(scene.save_slot_ready and not scene.save_button.disabled and scene.load_button.disabled,
		"Fresh session enables saving without pretending a save already exists.")
	for entry in [[KEY_4, -1], [KEY_1, 0], [KEY_2, 1], [KEY_3, 2]]:
		await _key(entry[0])
		await _click_cell(entry[1])
	await _connect(KEY_F, 0, 1)
	await _connect(KEY_F, 1, 2)
	for pair in [[-1, 0], [0, 1], [1, 2]]:
		await _connect(KEY_G, pair[0], pair[1])
	for _tick in range(6):
		scene.model.advance()
		if scene.model.projection().stock.held > 0:
			break
	await _key(KEY_SPACE)
	scene._refresh()
	var paused: Dictionary = scene.model.checkpoint()
	_check(paused.stock.held == 1 and paused.remaining > 0 and not paused.power_enabled,
		"Save fixture contains actual paused partial production.")
	var item_count: int = scene.item_root.get_child_count()
	await _click_screen(scene.save_button.get_global_rect().get_center())
	_check(scene.last_save_result.get("accepted", false), "Actual Save button publishes paused work.")
	_check(scene.model.checkpoint() == paused, "Saving must not change authority or retained outcomes.")
	var saved_bytes := FileAccess.get_file_as_bytes(slot)
	var old_namespace: String = scene.request_namespace
	# Change actual identity and geometry before loading a lower revision.
	await _key(KEY_I)
	await _click_cell(-1)
	await _click_screen(scene.remove_button.get_global_rect().get_center())
	await _key(KEY_4)
	await _click_cell(-1)
	_check(scene.model.projection().entities.has("wheel-2"), "Ordinary input rebuilds a fresh wheel identity.")
	await _key(KEY_G)
	await _click_cell(0)
	_check(not scene.pending_link.is_empty(), "Load begins with an actual pending link selection.")
	await _key(KEY_F9)
	_check(scene.last_load_result.get("accepted", false), "Actual F9 loads paused work.")
	_check(scene.model.checkpoint() == paused and scene.state == scene.model.projection(),
		"Load restores exact authority and refreshes the actual lower-version projection.")
	_check(scene.item_root.get_child_count() == item_count and not scene.state.entities.has("wheel-2"),
		"Restored meshes and item presentation replace the later worksite.")
	_check(scene.selected.is_empty() and scene.pending_link.is_empty() and not scene.selection_ring.visible,
		"Successful load clears selected and half-connected identities.")
	_check(scene.request_namespace != old_namespace and scene.request_sequence == 0,
		"Successful load starts a fresh opaque intent namespace.")
	_check(FileAccess.get_file_as_bytes(slot) == saved_bytes, "Loading leaves the good save byte-identical.")
	await _key(KEY_SPACE)
	scene.model.advance(4)
	scene._refresh()
	await _key(KEY_I)
	await _click_cell(2)
	await _key(KEY_R)
	_check(scene.state.inventories.get("P", 0) == 1,
		"First eligible ordinary retrieve after restore succeeds without retry.")
	# A full outlet blocks production without losing its in-process blank.
	scene.model.advance(30)
	scene._refresh()
	_check(scene.state.stock.output == 1 and scene.state.stock.held == 1 and _conserved(),
		"Actual blocked outlet retains one plate and its next blank.")
	await _key(KEY_F5)
	_check(scene.last_save_result.get("accepted", false), "Actual F5 saves blocked production to its own slot.")
	var blocked: Dictionary = scene.model.checkpoint()
	saved_bytes = FileAccess.get_file_as_bytes(slot)
	await _key(KEY_F)
	await _click_cell(0)
	var selection: String = scene.selected
	var pending: String = scene.pending_link
	old_namespace = scene.request_namespace
	var sequence: int = scene.request_sequence
	var before_bad: Dictionary = scene.model.checkpoint()
	# Negative candidates go through the same Load handler called by the button.
	# Disposable alternate files preserve the good slot rather than corrupting it.
	var bad_path := slot + ".truncated"
	var file := FileAccess.open(bad_path, FileAccess.WRITE)
	file.store_buffer("broken save".to_utf8_buffer())
	file.close()
	var refused: Dictionary = scene._load_worksite(bad_path)
	_check(not refused.accepted, "Load consumer refuses a truncated file.")
	var invalid: Dictionary = blocked.duplicate(true)
	for record in invalid.requests.values():
		if record.result.accepted and record.intent.action == "retrieve":
			record.intent.entity = "processor-retired"
			break
	bad_path = slot + ".contradictory"
	file = FileAccess.open(bad_path, FileAccess.WRITE)
	file.store_buffer(scene.Store.encode(invalid))
	file.close()
	refused = scene._load_worksite(bad_path)
	_check(not refused.accepted, "Load consumer delegates contradictory cached targets to the sole model validator.")
	_check(scene.model.checkpoint() == before_bad and FileAccess.get_file_as_bytes(slot) == saved_bytes,
		"Rejected candidates preserve all live authority and the last good file.")
	_check(scene.selected == selection and scene.pending_link == pending and scene.request_namespace == old_namespace and scene.request_sequence == sequence,
		"Rejected loads preserve UI identity and pending input.")
	await _key(KEY_I)
	await _click_cell(2)
	await _key(KEY_R)
	_check(scene.state.inventories.get("P", 0) == 2, "Ordinary input continues immediately after a rejected load.")
	await _click_screen(scene.load_button.get_global_rect().get_center())
	_check(scene.last_load_result.get("accepted", false) and scene.model.checkpoint() == blocked,
		"Actual Load button restores exact blocked work after subsequent input.")
	await _collect_four()
	await _click_screen(scene.confirm_button.get_global_rect().get_center())
	_check(scene.goal_confirmed, "Actual confirmation acknowledges four retrieved plates.")
	await _key(KEY_F9)
	_check(not scene.goal_confirmed and scene.confirm_button.disabled and scene.state.inventories.get("P", 0) == 1,
		"Loading less than four plates clears prior confirmation and recalculates eligibility.")
	await _collect_four()
	await _click_screen(scene.save_button.get_global_rect().get_center())
	var four: Dictionary = scene.model.checkpoint()
	await _click_screen(scene.confirm_button.get_global_rect().get_center())
	await _key(KEY_F9)
	_check(not scene.goal_confirmed and not scene.confirm_button.disabled and scene.model.checkpoint() == four,
		"Loaded four-plate inventory is eligible but not automatically confirmed.")
	await _click_screen(scene.confirm_button.get_global_rect().get_center())
	_check(scene.goal_confirmed and scene.model.checkpoint() == four and _conserved(),
		"Reconfirmation is explicit and consumes no authoritative product.")
	refused = scene._load_worksite(slot + ".truncated")
	_check(not refused.accepted and scene.goal_confirmed and scene.model.checkpoint() == four,
		"A rejected load preserves an already confirmed session goal.")
	# A failed publication must keep the previous save and blocking diagnostic.
	saved_bytes = FileAccess.get_file_as_bytes(slot)
	file = FileAccess.open(slot + ".pending", FileAccess.WRITE)
	file.store_string("retained pending diagnostic")
	file.close()
	old_namespace = scene.request_namespace
	await _key(KEY_F5)
	_check(not scene.last_save_result.get("accepted", true) and scene.last_save_result.reason == "pending_file_exists",
		"Actual Save shortcut refuses an existing pending artifact.")
	_check(scene.model.checkpoint() == four and FileAccess.get_file_as_bytes(slot) == saved_bytes and FileAccess.file_exists(slot + ".pending") and scene.request_namespace == old_namespace,
		"Save refusal preserves authority, good file, pending diagnostic and input identity.")
	print("OPENING_SAVE_LOAD_STATE " + JSON.stringify({"paused": {"stock": paused.stock, "remaining": paused.remaining, "power_enabled": paused.power_enabled},
		"blocked": {"stock": blocked.stock, "remaining": blocked.remaining},
		"final": scene.model.projection(), "confirmed": scene.goal_confirmed}))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK,
				"Rendered integration viewport is saved.")
	# A fresh controller refuses to adopt an already existing save as writable.
	scene.free()
	scene = load("res://opening/opening.tscn").instantiate()
	scene.auto_advance = false
	scene.configure_save_slot(slot)
	root.add_child(scene)
	await process_frame
	_check(not scene.save_slot_ready and scene.save_button.disabled, "A fresh session refuses an existing destination.")
	await _key(KEY_F5)
	_check(not scene.last_save_result.get("accepted", true) and FileAccess.get_file_as_bytes(slot) == saved_bytes,
		"Global Save cannot overwrite a pre-existing user save.")
	print("OPENING_SAVE_LOAD_PASS: real save/load input, paused/blocked continuation and refusal preservation" if failures.is_empty() else "OPENING_SAVE_LOAD_FAIL: " + JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

func _collect_four() -> void:
	await _key(KEY_I)
	await _click_cell(2)
	for _tick in range(50):
		if scene.model.projection().stock.output > 0:
			await _key(KEY_R)
		if scene.model.projection().inventories.get("P", 0) >= 4:
			break
		scene.model.advance()
		scene._refresh()
	_check(scene.state.inventories.get("P", 0) >= 4 and _conserved(), "Ordinary retrieval reaches four conserved products.")
