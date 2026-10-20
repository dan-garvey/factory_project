extends SceneTree
## Regression for RECOVERY-UI-LAYOUT-R1. This uses the real UI containers over
## invented records, without starting a Model, body, network or game scene.

class SessionStub extends RefCounted:
	func is_ready() -> bool:
		return true

class LayoutView extends "res://opening/shared_opening.gd":
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _ignore() -> void:
	pass

func _bounds(view) -> Dictionary:
	var panel: Control = view.power_button.get_parent().get_parent()
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

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var view := LayoutView.new()
	view.session = SessionStub.new()
	view.connect_on_ready = false
	view.client = "P"
	view.show_all_tools = true
	view.show_details = true
	view.selected = "press"
	view.mode = "inspect"
	root.add_child(view)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	view._build_interface()
	var column: VBoxContainer = view.power_button.get_parent()
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
	var panel: Control = view.power_button.get_parent().get_parent()
	panel.size.y = 490
	await _settle()
	var recovery: Dictionary = _bounds(view)
	var tooltip: String = view.recovery_actions.action_button.tooltip_text
	var separate_forms: bool = "2 blanks" in tooltip and "1 plate" in tooltip and "1 workpiece" in tooltip
	var available: bool = recovery.recovery_visible and not view.recovery_actions.action_button.disabled
	var fit: bool = not recovery.overlap and recovery.minimum_required_bottom <= recovery.footer[1]
	var passed: bool = not baseline.overlap and fit and available and separate_forms and view.model == null
	var report: Dictionary = {"status": "pass" if passed else "fail",
		"evidence": "headless_ui_container_bounds", "viewport": [root.size.x, root.size.y],
		"baseline_without_recovery": baseline, "with_recovery": recovery,
		"action_available": available, "separate_carried_forms": separate_forms,
		"carried_tooltip": tooltip, "model_created": view.model != null}
	print(JSON.stringify(report))
	view.queue_free()
	await process_frame
	quit(0 if passed else 1)
