extends SceneTree
## Default cases inspect unmounted views. --buttons-only mounts actual widgets
## over invented projections. --carried-guidance-only also reads recovery menus.
## None of these modes creates a live Model.

const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")
const SiteSurface = preload("res://opening/site_surface.gd")
var checks := 0
var failures := 0

class OfflineWidgets:
	extends "res://opening/opening.gd"
	var issued: Array = []
	var pointed := ""
	var hand_pointed := ""
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
	func _screen_hand_source(_screen: Vector2) -> String:
		return hand_pointed

class SharedWidgets:
	extends "res://opening/shared_opening.gd"
	var issued: Array = []
	var pointed := ""
	var hand_pointed := ""
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
	func _screen_hand_source(_screen: Vector2) -> String:
		return hand_pointed

class SessionStub extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

class SourceRayView extends "res://opening/opening.gd":
	func _ready() -> void:
		set_process(false)

class SharedSourceRayView extends "res://opening/shared_opening.gd":
	var issued: Array = []
	func _ready() -> void:
		set_process(false)
	func issue(action: Dictionary) -> Dictionary:
		issued.append(action.duplicate(true))
		return {"accepted": false, "reason": "fixture_only"}

class SourceBodyLookup extends RefCounted:
	var site_bodies: Dictionary = {}

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
	if "--hand-trees-only" in OS.get_cmdline_user_args():
		call_deferred("_hand_tree_views")
		return
	if "--multitool-only" in OS.get_cmdline_user_args():
		call_deferred("_multitool_controls")
		return
	if "--ui-shortcuts-only" in OS.get_cmdline_user_args():
		call_deferred("_ui_shortcuts")
		return
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
	var belt_guidance: Dictionary = view._guided_step({"collector": true})
	verify(belt_guidance.tool == "drive" and "shafts" in belt_guidance.text,
		"Native guidance asks Q for a shaft route while only P carries a Belt.")
	view.state.part_kits.P.belt = 0
	view.state.parts.belt = 0
	view.state.part_kits.Q.belt = 1
	verify(view._guided_step({"collector": true}) == belt_guidance,
		"Carrying a Belt does not replace native shaft-route guidance with a grid Belt cue.")
	verify(view._display_parts().shaft == 0, "Q does not borrow P's shaft count.")
	view.client = "P"
	verify(view._display_parts().belt == 0 and view._display_parts().shaft == 3, "Changing the active actor changes every displayed kit field.")
	verify(view._guided_step({"collector": true}) == belt_guidance,
		"Q's Belt does not change P's native shaft-route guidance.")
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
	view._guided_step({"collector": true})
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

func _hand_tree_views() -> void:
	var view = SourceRayView.new()
	if not view.has_method("_refresh_hand_trees"):
		verify(false, "Native timber sources require visible trees with their actual pick identities.")
		view.free()
		print("HAND_TREE_VIEW_FAIL %d" % checks)
		quit(1)
		return
	view.state = hotbar_observation()
	view.state.hand_sources = {
		"tree-east-south": {"kind": "tree", "position": [4.95, 0.825, 4.95], "initial": 8, "remaining": 8},
		"tree-east-north": {"kind": "tree", "position": [4.95, 0.825, 9.9], "initial": 8, "remaining": 8},
		"tree-north": {"kind": "tree", "position": [0.0, 0.825, 11.55], "initial": 8, "remaining": 8},
		"ore": {"kind": "ore_deposit", "position": [-1.2375, 0.825, 0.0], "initial": 16, "remaining": 16}}
	var before: Dictionary = view.state.duplicate(true)
	root.add_child(view)
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	view.camera.current = true
	view._refresh_hand_trees()
	verify(view.hand_tree_nodes.size() == 3, "Only native tree sources receive a presentation; ore and scenery remain separate.")
	for id: String in view.hand_tree_nodes:
		var body: StaticBody3D = view.hand_tree_nodes[id]
		var source: Dictionary = view.state.hand_sources[id]
		verify(body.get_meta("hand_source") == id and body.collision_layer == Opening.Geometry.PICK_LAYER and body.collision_mask == 0,
			"Each soft tree has one exact pick identity and no new actor-collision authority.")
		verify(is_equal_approx(body.position.x, float(source.position[0])) and is_equal_approx(body.position.z, float(source.position[2]))
			and is_equal_approx(body.position.y, SiteSurface.height_at(body.position.x, body.position.z)),
			"Visible tree roots use the native horizontal anchor and the actual emitted terrain height.")
		var crown: MeshInstance3D = body.get_node("Tree")
		verify(crown.visible and not body.get_node("Stump").visible, "Uncut native stock has a complete sourced tree.")
		# Aim at a real bark triangle, using the qualified asset's independent
		# 315-vertex surface identity. A fixed line above the root can miss a
		# leaning trunk even when its rendered and picked geometry match.
		var bark: Array = []
		for surface in range(crown.mesh.get_surface_count()):
			var arrays: Array = crown.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_VERTEX].size() == 315:
				bark = arrays
		verify(not bark.is_empty(), "The fixture selects the original asset's bark rather than its needle planes.")
		var vertices: PackedVector3Array = bark[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = bark[Mesh.ARRAY_INDEX]
		var target := Vector3.ZERO
		var closest := INF
		for first in range(0, indices.size(), 3):
			var center := (vertices[indices[first]] + vertices[indices[first + 1]] + vertices[indices[first + 2]]) / 3.0
			if absf(center.y - 0.18) < closest:
				closest = absf(center.y - 0.18)
				target = center
		var aim: Vector3 = crown.to_global(target)
		view.camera.position = aim + Vector3(0.0, 0.0, 3.0)
		view.camera.look_at(aim)
		await physics_frame
		await process_frame
		verify(view._screen_hand_source(view.camera.unproject_position(aim)) == id,
			"A real PhysicsServer ray selects the visible native trunk.")
	var old_body: StaticBody3D = view.hand_tree_nodes["tree-east-south"]
	var old_shape: Shape3D = old_body.get_node("PickShape").shape
	view._refresh_hand_trees()
	verify(view.hand_tree_nodes["tree-east-south"] == old_body and old_body.get_node("PickShape").shape == old_shape,
		"An unchanged refresh preserves the tree and pick-shape identities.")
	verify(view.state == before and view.model == null and view.request_sequence == 0,
		"Tree construction is a read-only projection with no Model or native request.")
	view.state.hand_sources["tree-east-south"].remaining = 7
	view._refresh_hand_trees()
	verify(view.hand_tree_nodes["tree-east-south"] == old_body and old_body.get_node("Tree").visible
		and old_body.get_node("PickShape").shape == old_shape and old_body.get_node("Cut").visible,
		"A partial cut preserves the standing tree without rebuilding its pick body.")
	view.state.hand_sources["tree-east-south"].remaining = 0
	view._refresh_hand_trees()
	verify(not old_body.get_node("Tree").visible and old_body.get_node("Stump").visible
		and old_body.get_node("PickShape").shape != old_shape,
		"Native depletion leaves a stump and removes the invisible full-trunk pick shape.")
	var stump_aim := old_body.to_global(Vector3(0.0, 0.06, 0.0))
	view.camera.position = stump_aim + Vector3(0.0, 0.0, 2.0)
	view.camera.look_at(stump_aim)
	await physics_frame
	await process_frame
	verify(view._screen_hand_source(view.camera.unproject_position(stump_aim)) == "tree-east-south",
		"The remaining visible stump keeps the depleted identity on a real pick ray.")
	var restored = SourceRayView.new()
	restored.state = view.state.duplicate(true)
	root.add_child(restored)
	restored._refresh_hand_trees()
	verify(not restored.hand_tree_nodes["tree-east-south"].get_node("Tree").visible,
		"A newly constructed view of depleted native data cannot regrow the tree.")
	view.state.hand_sources.erase("tree-east-north")
	view._refresh_hand_trees()
	verify(view.hand_tree_nodes.size() == 2 and not view.hand_tree_nodes.has("tree-east-north"),
		"A removed source cannot leave a stale visible or selectable tree.")
	view.free()
	restored.free()
	print("HAND_TREE_VIEW_%s %d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _multitool_controls() -> void:
	for shared in [false, true]:
		var view = SharedWidgets.new() if shared else OfflineWidgets.new()
		if not view.has_method("_interact_pointed"):
			verify(false, "The ordinary opening must route a pointed source to the native multitool command.")
			view.free()
			continue
		if shared:
			view.session = SessionStub.new()
		view.state = hotbar_observation()
		view.state.hand_sources = {"ore": {"kind": "ore_deposit", "position": [0.0, 0.825, 0.0], "initial": 16, "remaining": 2},
			"tree": {"kind": "tree", "position": [1.65, 0.825, 0.0], "initial": 8, "remaining": 1}}
		view.state.cargo = {"P": {"raw": 1, "timber": 3}, "Q": {"raw": 0, "timber": 0}}
		view.mode = "inspect"
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view._build_interface()
		view._refresh_ui()
		var before: Dictionary = view.state.duplicate(true)
		verify("FIRST WORKSHOP" in view.objective_heading.text and "3 timber" in view.goal_label.text
			and "1 softmetal" in view.goal_label.text and not view.goal_progress.visible,
			"The arrival view teaches actual carried materials instead of the obsolete four-plate goal.")
		verify(not view.confirm_button.visible and not view.lesson_button.visible,
			"Arrival offers neither old objective confirmation nor the completed-machine lesson.")
		view._toggle_explanation()
		verify(not view.explanation_open and view.example_presenter == null,
			"The retired lesson shortcut cannot create its historical example in arrival.")
		view.hand_pointed = "ore"
		view._refresh_placement_options()
		verify(view.placement_options_panel.visible and view.placement_options_title.text == "CUT SOFTMETAL"
			and "2 remaining" in view.placement_options_hint.text and "E" in view.placement_options_hint.text,
			"The pointed ore shows its native remaining stock and the real interaction key.")
		view._interact_pointed()
		verify(view.issued == [{"action": "harvest_source", "target": "ore"}],
			"The ordinary source interaction submits only its native target identity.")
		view.issued.clear()
		view.hand_pointed = "tree"
		view._refresh_placement_options()
		verify(view.placement_options_title.text == "CUT TIMBER" and "1 remaining" in view.placement_options_hint.text,
			"Timber uses the same confirmed-stock interaction rather than another inventory.")
		view._interact_pointed()
		verify(view.issued == [{"action": "harvest_source", "target": "tree"}], "The tree keeps its distinct native source identity.")
		view.issued.clear()
		verify(view.state == before and view.model == null and view.request_sequence == 0,
			"Presentation and request selection do not debit local stock or create a Model.")
		verify(view._harvest_result_text({"moved_timber": 1, "moved_raw": 0}) == "Collected 1 timber."
			and view._harvest_result_text({"moved_timber": 0, "moved_raw": 1}) == "Collected 1 softmetal blank.",
			"Success text reports actual native moved quantities for both resource kinds.")
		verify("depleted" in view._material_refusal_message({"reason": "unavailable_source"}, "fallback")
			and "full" in view._material_refusal_message({"reason": "inventory_full"}, "fallback"),
			"Native stock and capacity refusals retain actionable advice.")
		view.state.hand_sources.tree.remaining = 0
		view._refresh_placement_options()
		view._interact_pointed()
		verify("Depleted" in view.placement_options_hint.text and view.issued.is_empty(),
			"A confirmed depleted source stays readable without submitting another harvest.")
		view.state.hand_sources.tree.remaining = 1
		view.state.actors.P.ready = false
		view._interact_pointed()
		verify(view.issued.is_empty(), "An unready physical actor cannot submit a harvest.")
		view.state.actors.P.ready = true
		view.explanation_open = true
		view._interact_pointed()
		verify(view.issued.is_empty(), "Help prevents world interaction.")
		view.explanation_open = false
		view.building_hotbar.open_catalog()
		view._interact_pointed()
		verify(view.issued.is_empty(), "The catalog consumes interaction while open.")
		view.building_hotbar.catalog.hide()
		if shared:
			view.pending_actions["pending"] = {"action": {}, "outcome": {}}
			view._interact_pointed()
			verify(view.issued.is_empty(), "An unsettled shared command prevents a second harvest request.")
			view.hand_pointed = ""
			view.pointed = "read-only-machine"
			view.state.entities[view.pointed] = {"kind": "collector", "cell": [0, 0], "axis": 0, "generation": 1}
			view._interact_pointed()
			verify(view.selected == view.pointed and view.issued.is_empty(),
				"A pending mutation still permits ordinary read-only machine inspection.")
			view.pending_actions.clear()
			view.session.ready = false
			view.hand_pointed = "tree"
			view._interact_pointed()
			verify(view.issued.is_empty(), "A disconnected shared view cannot submit a harvest.")
		view.free()
	await _multitool_ray_selection()
	await _shared_ore_ray_selection()
	print("MULTITOOL_UI_%s %d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _multitool_ray_selection() -> void:
	var view := SourceRayView.new()
	view.state = hotbar_observation()
	view.state.hand_sources = {"ore": {"kind": "ore_deposit", "position": [0.0, 0.825, 0.0], "remaining": 2},
		"tree": {"kind": "tree", "position": [0.0, 0.825, 0.0], "remaining": 3}}
	root.add_child(view)
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	view.camera.position = Vector3(0.0, 2.0, 5.0)
	view.camera.look_at(Vector3(0.0, 0.4, 0.0))
	view.camera.make_current()
	var ore := StaticBody3D.new()
	ore.collision_layer = 1
	ore.collision_mask = 0
	ore.position = Vector3(0.0, 0.4, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 0.8
	shape.shape = box
	ore.add_child(shape)
	view.add_child(ore)
	var lookup := SourceBodyLookup.new()
	lookup.site_bodies.source_outcrop = ore
	view.actor_world = lookup
	await physics_frame
	await physics_frame
	var screen: Vector2 = view.camera.unproject_position(ore.position)
	verify(view._screen_hand_source(screen) == "ore", "A real ray hitting the existing ore collider resolves its sole native deposit identity.")
	var wall := StaticBody3D.new()
	wall.collision_layer = 2
	wall.position = Vector3(0.0, 1.04, 2.0)
	var wall_shape := CollisionShape3D.new()
	wall_shape.shape = box
	wall.add_child(wall_shape)
	view.add_child(wall)
	await physics_frame
	verify(view._screen_hand_source(screen).is_empty(), "A foreground physical machine blocks resource interaction behind it.")
	wall.free()
	ore.set_meta("hand_source", "tree")
	view.actor_world = null
	await physics_frame
	verify(view._screen_hand_source(screen) == "tree", "A shared view can read an exact source pick identity without owning an ActorWorld.")
	ore.set_meta("hand_source", "unregistered")
	verify(view._screen_hand_source(screen).is_empty(), "An unregistered hit identity cannot target another native source.")
	view.free()
	await process_frame
	await physics_frame

func _shared_ore_ray_selection() -> void:
	var view := SharedSourceRayView.new()
	view.state = hotbar_observation()
	view.state.hand_sources = {"ore": {"kind": "ore_deposit", "position": [-1.05, 0.825, 0.05], "remaining": 2}}
	view.state.source_deposit = {"id": "ore"}
	view.client = "P"
	view.mode = "inspect"
	view.distance = 0.0
	view.session = SessionStub.new()
	root.add_child(view)
	view._install_shared_ore_picker()
	var spec: Dictionary = SiteSurface.source_outcrop()
	var picker := view.get_node_or_null("SharedOreSourcePicker") as StaticBody3D
	verify(picker != null and picker.position == spec.center and picker.collision_layer == 4
		and picker.get_child(0).shape.points == spec.points,
		"The normal shared view installs a read-only ore pick body at the visible source hull.")
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	view.camera.position = spec.center + Vector3(0.0, 0.7, 4.0)
	view.camera.look_at(spec.center)
	view.camera.make_current()
	await physics_frame
	await physics_frame
	var screen: Vector2 = view.camera.unproject_position(spec.center)
	verify(view._screen_hand_source(screen) == "ore", "A shared camera ray resolves the projected ore identity on its real source shape.")
	view._interact_pointed()
	verify(view.issued == [{"action": "harvest_source", "target": "ore"}],
		"The shared source ray submits only the authoritative source target.")
	view.issued.clear()
	var occluder := StaticBody3D.new()
	occluder.collision_layer = 4
	occluder.position = spec.center + Vector3(0.0, 0.35, 2.0)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.5, 0.2)
	collider.shape = shape
	occluder.add_child(collider)
	view.add_child(occluder)
	await physics_frame
	verify(view._screen_hand_source(screen).is_empty(), "A foreground machine blocks shared ore picking.")
	occluder.collision_layer = 32
	await physics_frame
	verify(view._screen_hand_source(screen).is_empty(), "The shared terrain pick layer also blocks ore behind a ridge.")
	occluder.free()
	view.state.source_deposit.id = "other"
	await physics_frame
	verify(view._screen_hand_source(screen).is_empty(), "A source absent from the projection cannot be inferred from the shared pick body.")
	view.free()
	await process_frame
	await physics_frame

func _ui_shortcuts() -> void:
	for shared in [false, true]:
		var view = SharedWidgets.new() if shared else OfflineWidgets.new()
		if shared:
			view.session = SessionStub.new()
		view.state = hotbar_observation()
		view.state.part_kits.P.gearbox = 1
		view.mode = "inspect"
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view._build_interface()
		view._refresh_ui()
		var before: Dictionary = view.state.duplicate(true)
		var bar = view.building_hotbar
		bar.open_catalog()
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = KEY_8
		bar._input(event)
		verify(bar.destination.selected == 7, "Number keys choose a catalog destination without changing the world.")
		event.keycode = KEY_H
		bar._input(event)
		verify(bar.slots[7] == "gearbox" and view.mode == "gearbox" and not bar.catalog.visible,
			"A catalog letter assigns a mechanical part and activates its native placement view.")
		bar.open_catalog(7)
		event.keycode = KEY_DELETE
		bar._input(event)
		verify(bar.slots[7].is_empty() and view.mode == "inspect", "Delete clears the selected catalog slot.")
		event.keycode = KEY_D
		event.ctrl_pressed = true
		view._input(event)
		verify(view.show_details and view.stock_label.visible, "Ctrl+D reveals the detailed worksite view.")
		view._input(event)
		verify(not view.show_details and not view.stock_label.visible, "Ctrl+D closes the detailed worksite view.")
		event.ctrl_pressed = false
		event.alt_pressed = true
		event.keycode = KEY_4
		view._input(event)
		verify(view.mode == "gearbox", "Alt+4 reaches a mechanical tool outside the default hotbar.")
		event.alt_pressed = false
		view._refresh_placement_options()
		event.keycode = KEY_T
		view._input(event)
		verify(view.transmission_controls.get_popup().visible, "T opens the mounted mechanical options menu.")
		view.transmission_controls.get_popup().hide()
		event.keycode = KEY_DELETE
		view._input(event)
		verify(view.issued.is_empty(), "Delete cannot dismantle an absent or disabled selection.")
		verify(view.state == before and view.model == null and view.actor_world == null and view.request_sequence == 0,
			"UI shortcuts change only presentation until a valid world action is issued.")
		view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"failures": failures, "models": 0, "desktop_operations": 0, "scope": "ordinary/shared keyboard UI over invented projections"}))
	quit(0 if failures == 0 else 1)

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
		view.state.stock.output = 1
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
		verify(view.transmission_controls.selected_axis in ["x", "z"],
			"The wheel axle button offers only the horizontal axes accepted by native placement.")
		view.placement_options_axis.pressed.emit()
		verify(view.transmission_controls.selected_axis == old_axis,
			"Two wheel axle choices return to the starting horizontal orientation.")
		view._select_tool("drive")
		view.transmission_controls._axis_selected(1)
		view._select_tool("wheel")
		verify(view.transmission_controls.selected_axis in ["x", "z"],
			"Choosing a wheel after a vertical shaft restores a valid horizontal axle.")
		var wheel_axis: String = view.transmission_controls.selected_axis
		view._rotate_building()
		verify(view.transmission_controls.selected_axis in ["x", "z"]
			and view.transmission_controls.selected_axis != wheel_axis and view.issued.is_empty()
			and view.request_sequence == sequence and view.state == before,
			"Wheel rotation stays available without a native request or confirmed-state change.")
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
		key.keycode = KEY_R
		for rotation in [["collector", "x", 1], ["processor", "x", 1], ["wheel", "z", 0],
			["gear", "y", 0], ["drive", "y", 0], ["vertical_gearbox", "z", 0], ["chain_drive", "y", 0],
			["foundation", "x", 0], ["gearbox", "y", 0], ["belt", "x", 0],
			["flow", "x", 0], ["deconstruct", "x", 0]]:
			view._select_tool(rotation[0])
			view.transmission_controls._axis_selected(0)
			view.building_rotation = 0
			view._unhandled_input(key)
			verify(view.transmission_controls.selected_axis == rotation[1] and view.building_rotation == rotation[2],
				"R follows the existing orientation choices for %s." % rotation[0])
			verify(view.issued.is_empty() and view.request_sequence == sequence and view.state == before
				and view.selected == "press",
				"R in %s mode never retrieves from the previously selected output-ready press." % rotation[0])
			view.issued.clear()
		view._select_tool("gear")
		view.transmission_controls._axis_selected(0)
		view.state.actors.P.ready = false
		view._unhandled_input(key)
		verify(view.transmission_controls.selected_axis == "x" and view.issued.is_empty(),
			"An unready actor cannot rotate a cog or retrieve from its old selection.")
		view.state.actors.P.ready = true
		view.issued.clear()
		if shared:
			view.pending_actions = {"fixture": {"action": {"action": "retrieve"}, "outcome": {}}}
			view._unhandled_input(key)
			verify(view.transmission_controls.selected_axis == "x" and view.issued.is_empty(),
				"A pending shared request blocks rotation without submitting another action.")
			view.pending_actions.clear()
			view.issued.clear()
			view.session.ready = false
			view._unhandled_input(key)
			verify(view.transmission_controls.selected_axis == "x" and view.issued.is_empty(),
				"A disconnected shared view cannot rotate a cog or submit a retrieval.")
			view.session.ready = true
			view.issued.clear()
		view._select_tool("inspect")
		view._unhandled_input(key)
		verify(view.issued == [{"action": "retrieve", "amount": 1, "entity": "press"}] and view.state == before,
			"R in inspection mode still submits the selected press's existing collection action.")
		view.issued.clear()
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
		view.transmission_controls.get_popup().id_pressed.emit(8)
		view._refresh_placement_options()
		verify(view.mode == "gearbox" and view.transmission_controls.active_tool == "gearbox"
			and view.placement_options_panel.visible,
			"Choosing a gearbox from the placement menu leaves deconstruction and shows its ghost options.")
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
	view._message("Choose Collector [1] on the ore-colored ground beside the rock.")
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
