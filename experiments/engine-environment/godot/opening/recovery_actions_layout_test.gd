extends SceneTree
## Regression for RECOVERY-UI-LAYOUT-R1. This uses the real UI containers over
## invented records, without starting a Model, body, network or game scene.

class SessionStub extends RefCounted:
	func is_ready() -> bool:
		return true

class LayoutView extends "res://opening/shared_opening.gd":
	var submitted: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _update_cursor() -> void:
		pass
	func issue(action: Dictionary) -> Dictionary:
		submitted.append(action.duplicate(true))
		return {"accepted": false, "queued": true}

func _initialize() -> void:
	call_deferred("_run")

func _ignore() -> void:
	pass

func _bounds(view) -> Dictionary:
	var panel: Control = view.inspector.get_parent()
	var footer: Control = view.status_label.get_parent().get_parent()
	var right: Rect2 = panel.get_global_rect()
	var bottom: Rect2 = footer.get_global_rect()
	return {"right": [right.position.x, right.position.y, right.size.x, right.size.y],
		"footer": [bottom.position.x, bottom.position.y, bottom.size.x, bottom.size.y],
		"minimum_required_bottom": right.position.y + panel.get_combined_minimum_size().y,
		"right_minimum_height": panel.get_combined_minimum_size().y,
		"overlap": right.intersects(bottom), "recovery_visible": view.recovery_actions.visible}

func _settle() -> void:
	for _frame: int in range(4):
		await process_frame

func _collector_control(view: LayoutView) -> bool:
	var panel = view.arrival_assembly_controls
	var snapshot := {"options": {"native": true}, "hand_sources": {"ore": {}},
		"cargo": {"P": {"components": {}, "timber": 0, "raw": 0}},
		"placed_components": {"frame": {"component": "wooden_frame", "center": [0, 4, 4]},
			"mount": {"component": "tool_mount", "center": [0, 4, 5]},
			"tray": {"component": "receiver_tray", "center": [0, 4, 3]}},
		"crank_items": {"crank": {"holder": "", "attached_to": "mount", "port": [0, 4, 5]}},
		"collector_assemblies": [{"center": [0, 4, 4], "status": "ready",
			"parts": {"frame": "frame", "mount": "mount", "edge": "edge",
				"receiver": "tray", "shaft": "shaft"}}],
		"dropped_material": []}
	panel.refresh(snapshot, "P", "shaft", true)
	var ready: bool = panel.collector_cut_button.visible and not panel.collector_cut_button.disabled \
		and panel.collector_cut_button.tooltip_text == "Cut one ore blank · X"
	panel.collector_cut_button.pressed.emit()
	var exact: bool = view.submitted == [{"action": "turn_hand_crank", "entity": "mount"}]
	view.submitted.clear()
	snapshot.crank_items.crank = {"holder": "Q", "attached_to": "", "port": []}
	panel.refresh(snapshot, "P", "shaft", true)
	var held_elsewhere: bool = panel.collector_cut_button.disabled \
		and panel.collector_cut_button.tooltip_text.contains("Fit a crafted crank")
	snapshot.crank_items.crank = {"holder": "", "attached_to": "mount", "port": [0, 4, 5]}
	snapshot.dropped_material = [{"center": [0, 4, 3], "raw": 1}]
	panel.refresh(snapshot, "P", "shaft", true)
	var full: bool = panel.collector_cut_button.disabled and "Pick it up" in panel.collector_status.text
	snapshot.dropped_material = []
	snapshot.collector_assemblies[0] = {"center": [0, 4, 4], "status": "missing_mount"}
	panel.refresh(snapshot, "P", "frame", true)
	var missing: bool = panel.collector_cut_button.disabled and "tool mount" in panel.collector_status.text
	return ready and exact and held_elsewhere and full and missing and view.submitted.is_empty()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var view := LayoutView.new()
	view.session = SessionStub.new()
	view.connect_on_ready = false
	view.client = "P"
	view.selected = "press"
	view.mode = "inspect"
	root.add_child(view)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	view._build_interface()
	var column: VBoxContainer = view.power_label.get_parent()
	view.connection_label = view._label(column, "", 14)
	column.move_child(view.connection_label, 1)
	view.reconnect_button = view._button(column, "Reconnect to session", _ignore)
	view.disconnect_button = view._button(column, "Disconnect", _ignore)
	view.state = {"context": "layout-fixture", "revision": 0, "order": 0,
		"entities": {"collector": {"kind": "collector", "cell": [0, 1]},
			"belt": {"kind": "belt", "cell": [1, 1]},
			"press": {"kind": "processor", "cell": [2, 1]},
			"wheel": {"kind": "wheel", "cell": [-1, 1]}},
		"links": [], "drive_links": [],
		"parts": {"collector": 0, "belt": 0, "processor": 0, "wheel": 0, "shaft": 0},
		"stock": {"source": 7, "collector": 1, "belt": 1, "input": 1, "held": 1, "output": 1, "player": 1},
		"remaining": 2, "power_enabled": true, "powered": false,
		"options": {"physical": true, "native": false},
		"actors": {"P": {"ready": true}}, "inventories": {"P": 1},
		"cargo": {"P": {"raw": 2, "products": 1,
			"work_lots": [{"id": 7, "recipe_input": 1, "cycle_ticks": 4, "remaining": 2}]}}}
	view._refresh_ui()
	await _settle()
	var baseline: Dictionary = _bounds(view)
	view.state.options.native = true
	view._refresh_ui()
	var panel: Control = view.inspector.get_parent()
	panel.size.y = 490
	await _settle()
	var recovery: Dictionary = _bounds(view)
	var tooltip: String = view.recovery_actions.action_button.tooltip_text
	var separate_forms: bool = "2 blanks" in tooltip and "1 plate" in tooltip and "1 workpiece" in tooltip
	var available: bool = recovery.recovery_visible and not view.recovery_actions.action_button.disabled
	var bar_top: float = view.building_hotbar.get_global_rect().position.y
	var fit: bool = not recovery.overlap and recovery.minimum_required_bottom <= bar_top - 12.0 \
		and recovery.right[1] + recovery.right[3] <= bar_top - 12.0
	var collector_control: bool = _collector_control(view)
	var passed: bool = not baseline.overlap and fit and available and separate_forms \
		and collector_control and view.model == null
	var report: Dictionary = {"status": "pass" if passed else "fail",
		"evidence": "headless_ui_container_bounds", "viewport": [root.size.x, root.size.y],
		"baseline_without_recovery": baseline, "with_recovery": recovery,
		"action_available": available, "separate_carried_forms": separate_forms,
		"collector_control": collector_control,
		"carried_tooltip": tooltip, "model_created": view.model != null}
	print(JSON.stringify(report))
	view.queue_free()
	await process_frame
	quit(0 if passed else 1)
