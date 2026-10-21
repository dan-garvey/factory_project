extends SceneTree
## Isolated widget refreshes. No game startup, body, Model or transport runs.

var checks := 0
var failures := 0

class SessionStub extends RefCounted:
	func is_ready() -> bool:
		return true

class RefreshView extends "res://opening/shared_opening.gd":
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _update_cursor() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func verify(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("PARTS_REFRESH_FAILURE: " + reason)

func caption(view, count: int, reason: String, scope: String = "carried") -> void:
	view._refresh_ui()
	verify(view.building_hotbar.catalog_buttons.drive.text == "Shaft\n%d %s" % [count, scope], reason)

func _run() -> void:
	var view := RefreshView.new()
	view.session = SessionStub.new()
	view.client = "P"
	view.state = {"context": "kit-refresh-fixture", "revision": 0, "order": 0,
		"options": {"physical": true, "native": true},
		"actors": {"P": {"ready": true}, "Q": {"ready": true}},
		"entities": {}, "links": [], "drive_links": [],
		"inventories": {"P": 0, "Q": 0},
		"parts": {"collector": 1, "belt": 1, "processor": 1, "wheel": 1, "shaft": 7},
		"part_kits": {"P": {"collector": 1, "belt": 1, "processor": 1, "wheel": 1, "shaft": 3}},
		"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
		"remaining": 0, "powered": false, "power_enabled": true}
	root.add_child(view)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	view._build_interface()
	caption(view, 3, "A populated native kit displays its own three shafts.")
	view.client = "Q"
	caption(view, 0, "Switching to an absent native actor kit clears the previous count.")
	view.state.part_kits.clear()
	caption(view, 0, "Empty native kits do not display the compatibility alias.")
	view.state.part_kits.Q = {"shaft": 2}
	caption(view, 2, "A later confirmed kit replaces the zero count.")
	view.state.options.native = false
	caption(view, 7, "The scripted shared profile displays the actual shared kit.", "shared")
	view.state.options.native = true
	view.state.erase("part_kits")
	var before: Dictionary = view.state.duplicate(true)
	caption(view, 0, "A missing native kit map clears the prior scripted count.")
	verify(view.state == before and view.model == null and view.request_sequence == 0 and view.pending_actions.is_empty(),
		"Widget refresh leaves the projection and command authority unchanged.")
	view.queue_free()
	await process_frame
	print("OPENING_PARTS_REFRESH_%s %d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
