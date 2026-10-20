extends SceneTree
## Actual offline/shared redraw callbacks over invented projection facts only.
const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")

class ItemsView extends Opening:
	func _ready() -> void: set_process(false)
	func _refresh_ui() -> void: pass

class SharedItemsView extends SharedOpening:
	func _ready() -> void: set_process(false)
	func _refresh_ui() -> void: pass

class Facts extends RefCounted:
	var state: Dictionary = {}
	func projection() -> Dictionary: return state
	func is_ready() -> bool: return true

var checks := 0
var failed := false

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func observation() -> Dictionary:
	return {"context": "fitted-item-mount", "revision": 7, "order": 0,
		"options": {"physical": true, "native": true},
		"actors": {"P": {"ready": true, "position": [0.0, 0.9, 0.0]}},
		"inventories": {"P": 0}, "parts": {}, "entities": {
		"collector": {"kind": "collector", "cell": [0, 1]},
		"belt": {"kind": "belt", "cell": [1, 1]},
		"press": {"kind": "processor", "cell": [2, 1]}},
		"links": [], "drive_links": [], "stock": {
			"source": 3, "collector": 1, "belt": 2, "input": 2, "held": 1, "output": 4}}

func counts(items: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for child in items.get_children():
		var kind: String = child.get_meta("item_kind", "")
		result[kind] = int(result.get(kind, 0)) + 1
	return result

func has_item(items: Node3D, kind: String, at: Vector3) -> bool:
	for child in items.get_children():
		if child.get_meta("item_kind", "") == kind and child.position.is_equal_approx(at):
			return true
	return false

func check_view(view, shared: bool) -> void:
	var facts := Facts.new()
	facts.state = observation()
	view.model = facts
	if shared:
		view.session = facts
	view.geometry_key = JSON.stringify([facts.state.entities, facts.state.links, facts.state.drive_links])
	view.item_root = Node3D.new()
	view.add_child(view.item_root)
	root.add_child(view)
	var before: Dictionary = facts.state.duplicate(true)
	view._refresh()
	verify(counts(view.item_root) == {"seam_blank": 3, "workpiece_billet": 6, "stamped_plate": 1},
		"The actual refresh mounts fitted items with the existing stock counts and one visible outlet plate.")
	verify(has_item(view.item_root, "workpiece_billet", Vector3(-0.17, 0.65, 1.65))
		and has_item(view.item_root, "workpiece_billet", Vector3(1.8, 0.65, 1.65)),
		"Collector and belt workpieces retain their original world positions.")
	verify(has_item(view.item_root, "workpiece_billet", Vector3(3.77, 0.65, 1.65))
		and has_item(view.item_root, "stamped_plate", Vector3(3.76, 0.39, 1.8)),
		"Held/input work and the outlet plate retain the original press offsets.")
	verify(has_item(view.item_root, "seam_blank", Vector3(-0.16, 0.11, -2.9))
		and has_item(view.item_root, "seam_blank", Vector3(-0.16, 0.11, -1.75)),
		"The finite seam stays in its marked column.")
	verify(view.state == before and facts.state == before and view.actor_world == null
		and view.request_sequence == 0, "Item refresh does not mutate projection facts or create authority/input.")
	if view.item_root.get_child_count() == 0:
		view.free()
		return
	var old_items: Array[WeakRef] = []
	for child in view.item_root.get_children(): old_items.append(weakref(child))
	var old_mesh: Mesh = view.item_root.get_child(0).get_node("BilletCore").mesh
	var asset_script = view.workpiece_item_assets
	facts.state.revision += 1
	facts.state.stock = {"source": 0, "collector": 0, "belt": 3, "input": 1, "held": 0, "output": 0}
	before = facts.state.duplicate(true)
	view._refresh()
	verify(counts(view.item_root) == {"workpiece_billet": 4},
		"A later confirmed stock revision removes collected plates and depleted seam blanks.")
	var old_items_freed := true
	for previous in old_items: old_items_freed = old_items_freed and previous.get_ref() == null
	verify(old_items_freed, "Replacing a revision frees every superseded item without leaving duplicate assemblies.")
	verify(view.item_root.get_child(0).get_node("BilletCore").mesh == old_mesh
		and view.workpiece_item_assets == asset_script,
		"The ordinary redraw reuses the loaded helper and shared mesh resources.")
	verify(view.state == before and facts.state == before, "The revised confirmed projection remains immutable.")
	var first_item_id: int = view.item_root.get_child(0).get_instance_id()
	view._refresh()
	verify(view.item_root.get_child(0).get_instance_id() == first_item_id,
		"An unchanged revision retains its assemblies through the actual refresh path.")
	view.free()

func _initialize() -> void:
	call_deferred("_run")

func check_historical_view(view, shared: bool) -> void:
	var facts := Facts.new()
	facts.state = observation()
	facts.state.options.native = false
	view.model = facts
	if shared:
		view.session = facts
	view.geometry_key = JSON.stringify([facts.state.entities, facts.state.links, facts.state.drive_links])
	view.item_root = Node3D.new()
	view.add_child(view.item_root)
	root.add_child(view)
	var before: Dictionary = facts.state.duplicate(true)
	view._refresh()
	var all_boxes := true
	var previous_items: Array[WeakRef] = []
	for child in view.item_root.get_children():
		all_boxes = all_boxes and child is MeshInstance3D and child.mesh is BoxMesh
		previous_items.append(weakref(child))
	verify(all_boxes and view.item_root.get_child_count() == 10,
		"A historical payload without the optional module retains its existing primitive presentation.")
	if view.item_root.get_child_count() == 0:
		view.free()
		return
	verify(view.item_root.get_child(0).position.is_equal_approx(Vector3(-0.17, 0.65, 1.65))
		and view.item_root.get_child(9).position.is_equal_approx(Vector3(-0.16, 0.11, -1.75)),
		"The historical carrier and finite-seam positions remain unchanged.")
	verify(view.state == before and facts.state == before and view.actor_world == null
		and view.request_sequence == 0, "Historical presentation does not mutate facts or create authority/input.")
	facts.state.revision += 1
	facts.state.stock = {"source": 0, "collector": 0, "belt": 3, "input": 1, "held": 0, "output": 0}
	before = facts.state.duplicate(true)
	view._refresh()
	verify(view.item_root.get_child_count() == 4, "Historical redraw follows the next confirmed stock revision.")
	var previous_freed := true
	for previous in previous_items: previous_freed = previous_freed and previous.get_ref() == null
	verify(previous_freed and view.state == before and facts.state == before,
		"Historical redraw frees superseded items and preserves projection facts.")
	verify(view.workpiece_item_assets == null, "The absent optional script is never loaded.")
	view.free()

func _run() -> void:
	var shared_only := "--shared-only" in OS.get_cmdline_user_args()
	var historical_only := "--historical-only" in OS.get_cmdline_user_args()
	if historical_only:
		verify(not ResourceLoader.exists("res://opening/workpiece_item_assets.gd", "Script"),
			"This declared historical derivative really omits the optional workpiece module.")
		check_historical_view(ItemsView.new(), false)
		check_historical_view(SharedItemsView.new(), true)
	else:
		if not shared_only:
			check_view(ItemsView.new(), false)
		check_view(SharedItemsView.new(), true)
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"phase": "historical missing module" if historical_only else "shared correction" if shared_only else "offline and shared",
		"scope": "ordinary offline/shared item callbacks with invented facts",
		"native_gameplay": "not_run", "desktop": "not_used"}))
	quit(1 if failed else 0)
