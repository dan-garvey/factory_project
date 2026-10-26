extends SceneTree
## Default cases inspect unmounted views. --buttons-only mounts actual widgets
## over invented projections. --carried-guidance-only also reads recovery menus.
## None of these modes creates a live Model.

const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")
const SiteSurface = preload("res://opening/site_surface.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const ComponentPresenter = preload("res://opening/native_transmission_presenter.gd")
const RecoveryActions = preload("res://opening/recovery_actions.gd")
const BuildingHotbar = preload("res://opening/building_hotbar.gd")
const SUITES := {
	"--slide-view-only": "_slide_view_check",
	"--component-placement-only": "_component_placement_check",
	"--object-menu-only": "_object_menu_check",
	"--slide-controls-only": "_slide_controls_check",
	"--slide-inventory-render-only": "_slide_inventory_render_check",
	"--workshop-pages-only": "_workshop_pages",
	"--field-craft-widget-only": "_field_craft_widget",
	"--pod-floor-only": "_pod_floor_views",
	"--multitool-view-only": "_multitool_presentation",
	"--hand-trees-only": "_hand_tree_views",
	"--multitool-only": "_multitool_controls",
	"--ui-shortcuts-only": "_ui_shortcuts",
	"--interaction-only": "_interaction_controls",
	"--shared-crank-hold-only": "_shared_crank_hold_check",
	"--building-rotation-only": "_building_rotation",
	"--hotbar-render-only": "_render_hotbar",
	"--arrival-hotbar-render-only": "_render_arrival_hotbar",
	"--hotbar-only": "_hotbar",
	"--arrival-hotbar-only": "_arrival_hotbar",
	"--carried-guidance-only": "_carried_guidance",
	"--shared-component-results-only": "_shared_component_results",
	"--buttons-only": "_buttons",
}
const CAPTURE_SUITES := {
	"--image-prefix=": ["--component-placement-only", "--object-menu-only"],
	"--arrival-hotbar-image-prefix=": ["--arrival-hotbar-render-only"],
	"--hotbar-image-prefix=": ["--hotbar-render-only"],
	"--inventory-resize-capture-prefix=": ["--field-craft-widget-only"],
	"--slide-image=": ["--slide-view-only"],
	"--slide-inventory-image-prefix=": ["--slide-inventory-render-only"],
	"--workshop-pages-image-prefix=": ["--workshop-pages-only"],
}
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

class OfflineWorkshopWidgets extends OfflineWidgets:
	var accept_press_turn := true
	func _screen_pick(_screen: Vector2) -> Dictionary:
		return {}
	func issue(action: Dictionary) -> Dictionary:
		if action.get("action", "") == "turn_press_crank":
			issued.append(action.duplicate(true))
			return {"accepted": accept_press_turn}
		return super.issue(action)

class SharedWorkshopWidgets extends SharedWidgets:
	func _screen_pick(_screen: Vector2) -> Dictionary:
		return {}

class SharedSettlementView:
	extends "res://opening/shared_opening.gd"
	var observed := ""
	var observed_refusal := false
	func _ready() -> void:
		pass
	func _refresh_ui() -> void:
		pass
	func _construction_feedback(_intent: Dictionary, _outcome: Dictionary) -> void:
		pass
	func _message(words: String, refused: bool = false) -> void:
		observed = words
		observed_refusal = refused

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
	var floor_body: StaticBody3D

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
	var selected := ""
	var captures: Array[String] = []
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-purpose="):
			continue
		if SUITES.has(argument):
			if not selected.is_empty():
				push_error("Select exactly one parts-view fixture suite")
				quit(2)
				return
			selected = argument
			continue
		var capture := ""
		for prefix: String in CAPTURE_SUITES:
			if argument.begins_with(prefix) and argument.length() > prefix.length():
				capture = prefix
				break
		if capture.is_empty() or captures.has(capture):
			push_error("Unknown or duplicate parts-view fixture argument: " + argument)
			quit(2)
			return
		captures.append(capture)
	for capture in captures:
		if selected not in CAPTURE_SUITES[capture]:
			push_error("The parts-view capture argument does not belong to the selected suite: " + capture)
			quit(2)
			return
	if not Opening.apply_test_window_title(self):
		return
	if not selected.is_empty():
		call_deferred(SUITES[selected])
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

class ComponentPlacementChoice extends Node:
	var kind := "anvil"
	func selected_name() -> String:
		return kind
	func select_component_name(component_name: String) -> bool:
		kind = component_name
		return true
	func press_anvil_for(_selected: String) -> String:
		return ""

class ComponentPlacementView extends "res://opening/opening.gd":
	var aimed := "frame"
	var aim_normal := Vector3.UP
	var pointed_cell := Vector2i.ZERO
	var hit_body: StaticBody3D
	var issued: Array = []
	func _ready() -> void:
		set_process(false)
	func _screen_cell(_screen: Vector2) -> Vector2i:
		return pointed_cell
	func _screen_pick(_screen: Vector2) -> Dictionary:
		return {"collider": hit_body, "normal": aim_normal} if not aimed.is_empty() else {}
	func _screen_entity(_screen: Vector2) -> String:
		return aimed
	func _preview_pointer_clear() -> bool:
		return true
	func _placement_ready() -> bool:
		return true
	func _refresh_machine_preview() -> void:
		pass
	func _refresh_machine_captions() -> void:
		pass
	func _refresh_placement_options() -> void:
		pass
	func _update_cursor() -> void:
		_refresh_component_preview()
	func _refresh_ui() -> void:
		pass
	func issue(action: Dictionary) -> Dictionary:
		issued.append(action.duplicate(true))
		return {"accepted": false, "reason": "fixture_only"}

func _component_key(code: Key, pressed: bool, alt := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.alt_pressed = alt
	return event

func _component_center_hit(camera: Camera3D) -> Dictionary:
	var screen := root.get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin,
		origin + camera.project_ray_normal(screen) * 5.0)
	query.collision_mask = Geometry.PICK_LAYER
	return camera.get_world_3d().direct_space_state.intersect_ray(query)

func _component_placement_check() -> void:
	var prefix := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--image-prefix="):
			prefix = argument.trim_prefix("--image-prefix=")
	var view := ComponentPlacementView.new()
	view.mode = "component"
	view.state = {"options": {"native": true}, "actors": {"P": {"ready": true}},
		"cargo": {"P": {"components": {"anvil": 1, "ram_face": 1}}},
		"placed_components": {"frame": {"component": "wooden_frame", "center": [0, 0, 0],
			"generation": 1, "occupied": {"center": [0.0, 0.45, 0.0],
			"half": [0.2025, 0.45, 0.2025]}}},
		"transmission_parts": {}, "belt_spans": {}, "entities": {}, "foundations": {}}
	root.add_child(view)
	var choice := ComponentPlacementChoice.new()
	view.add_child(choice)
	view.arrival_assembly_controls = choice
	var presenter := ComponentPresenter.new()
	view.add_child(presenter)
	view.transmission_presenter = presenter
	var body := StaticBody3D.new()
	body.set_meta("component_entity", "frame")
	view.add_child(body)
	view.hit_body = body
	var frame := Node3D.new()
	frame.position.y = 0.45
	view.add_child(frame)
	presenter.preview_component(frame, "wooden_frame", Vector3(0.405, 0.9, 0.405))
	var environment := WorldEnvironment.new()
	var backdrop := Environment.new()
	backdrop.background_mode = Environment.BG_COLOR
	backdrop.background_color = Color("263039")
	environment.environment = backdrop
	view.add_child(environment)
	view.component_preview = Node3D.new()
	view.add_child(view.component_preview)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	view.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(1.15, 2.05, 2.4)
	camera.fov = 40
	view.add_child(camera)
	camera.look_at(Vector3(0, 1.15, 0))
	camera.make_current()
	view.camera = camera
	var snapped: Array = view._component_place_center(Vector2i.ZERO, "frame")
	verify(snapped == [0, 1, 0], "The anvil snaps one height step above a pointed frame top.")
	view._refresh_component_preview()
	verify(view.component_preview.visible and view.component_preview_kind == "anvil"
		and view.component_preview.has_node("WorkbedWeb")
		and view.component_preview.has_node("ReplaceableDiePlate")
		and not view.component_preview_blocked,
		"The frame-top anvil ghost uses the placed anvil mesh and is initially clear.")
	verify(view.component_preview_snap == "Above wooden frame"
		and "Aim at a floor or built surface" in view._component_placement_hint(),
		"The anvil hint allows a floor or built surface without requiring a press frame.")
	var head_box: Dictionary = view._component_candidate_box("flat_head", [12, 1, 8])
	var slide_box: Dictionary = view._component_candidate_box("copper_slide", [12, 2, 8])
	var workbed_box: Dictionary = view._component_candidate_box("anvil", [12, 0, 8])
	verify(absf(head_box.center.y - head_box.half.y - 0.4125) < 0.0001
		and absf(head_box.center.y + head_box.half.y - 1.44375) < 0.0001
		and absf(slide_box.center.y - slide_box.half.y - 1.03125) < 0.0001
		and absf(head_box.center.y - head_box.half.y -
			(workbed_box.center.y + workbed_box.half.y)) < 0.0001,
		"The flat head reaches the anvil face while the slide rails keep feed clearance.")
	view.state.placed_components["sample-head"] = {"component": "flat_head", "center": [12, 1, 8],
		"generation": 1, "occupied": {"center": [head_box.center.x, head_box.center.y, head_box.center.z],
		"half": [head_box.half.x, head_box.half.y, head_box.half.z]}}
	verify(not view._component_candidate_blocked("copper_slide", [12, 2, 8], slide_box),
		"The slide ghost accepts the exact fitted head overlap.")
	view.state.placed_components.erase("sample-head")
	view.state.placed_components["sample-slide"] = {"component": "copper_slide", "center": [12, 2, 8],
		"generation": 1, "occupied": {"center": [slide_box.center.x, slide_box.center.y, slide_box.center.z],
		"half": [slide_box.half.x, slide_box.half.y, slide_box.half.z]}}
	verify(not view._component_candidate_blocked("flat_head", [12, 1, 8], head_box),
		"The head ghost accepts the same fitted slide overlap in reverse build order.")
	view.state.placed_components.erase("sample-slide")
	var head_sample := Node3D.new()
	head_sample.position = head_box.center
	view.add_child(head_sample)
	presenter.preview_component(head_sample, "flat_head", head_box.size)
	var workbed_sample := Node3D.new()
	workbed_sample.position = workbed_box.center
	view.add_child(workbed_sample)
	presenter.preview_component(workbed_sample, "anvil", workbed_box.size)
	var slide_sample := Node3D.new()
	slide_sample.position = slide_box.center
	view.add_child(slide_sample)
	presenter.preview_component(slide_sample, "copper_slide", slide_box.size)
	verify(head_sample.has_node("FlatHeadMovingDie/FlatHeadFace") and slide_sample.has_node("SlideCarriage"),
		"The separate flat die and unchanged powered carriage both have visible meshes.")
	var stroke_phase := {"subticks": 2048, "remainder": 0, "denominator": 1,
		"cycle_subticks": 4096}
	var stroked_head := Node3D.new()
	stroked_head.position = head_box.center
	view.add_child(stroked_head)
	presenter._placed_component(stroked_head, "flat_head", Vector3.ZERO, head_box.size,
		"", 0.0, 0.0, Vector3.ZERO, stroke_phase)
	var stroked_slide := Node3D.new()
	stroked_slide.position = slide_box.center
	view.add_child(stroked_slide)
	presenter._placed_component(stroked_slide, "copper_slide", Vector3.ZERO, slide_box.size,
		"", 0.0, 0.0, Vector3.ZERO, stroke_phase)
	var head_drop: float = stroked_head.get_node("FlatHeadMovingDie").position.y \
		- head_sample.get_node("FlatHeadMovingDie").position.y
	var carriage_drop: float = stroked_slide.get_node("SlideCarriage").position.y \
		- slide_sample.get_node("SlideCarriage").position.y
	verify(absf(head_drop + head_box.size.y - 0.175) < 0.0001
		and absf(carriage_drop + slide_box.size.y - Geometry.HEIGHT_STEP - 0.175) < 0.0001
		and head_drop < carriage_drop and carriage_drop < 0.0,
		"The die reaches the lower work face while its driven carriage stays within the slide rails.")
	if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
		camera.position = head_box.center + Vector3(1.1, 0.45, 2.4)
		camera.look_at(head_box.center - Vector3(0, 0.18, 0))
		stroked_head.visible = false
		stroked_slide.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-flat-head-slide.png") == OK,
			"Retain the low flat head and slide as an isolated visual sample.")
		head_sample.visible = false
		slide_sample.visible = false
		stroked_head.visible = true
		stroked_slide.visible = true
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-flat-head-stroke.png") == OK,
			"Retain the driven head at native half-cycle over the passive workbed.")
	var broad_origin := [20, 0, 8]
	var broad_bed_box: Dictionary = view._component_candidate_box("broad_anvil", broad_origin)
	var broad_head_box: Dictionary = view._component_candidate_box("broad_flat_head", [20, 1, 8])
	var broad_slide_box: Dictionary = view._component_candidate_box("copper_slide", [22, 2, 10])
	verify(absf(broad_bed_box.size.x - 2.0 * Geometry.PITCH) < 0.0001
		and absf(broad_head_box.size.z - 2.0 * Geometry.PITCH) < 0.0001
		and view._guided_press_part_snap("broad_flat_head", "broad_anvil", broad_origin,
			Vector3.RIGHT).center == [20, 1, 8]
		and view._guided_press_part_snap("copper_slide", "broad_flat_head", [20, 1, 8],
			Vector3.RIGHT).center == [22, 2, 10],
		"One broad support and face occupy four contiguous cells with one fitted central slide.")
	var broad_bed_sample := Node3D.new()
	broad_bed_sample.position = broad_bed_box.center
	view.add_child(broad_bed_sample)
	presenter.preview_component(broad_bed_sample, "broad_anvil", broad_bed_box.size)
	var broad_head_sample := Node3D.new()
	broad_head_sample.position = broad_head_box.center
	view.add_child(broad_head_sample)
	presenter.preview_component(broad_head_sample, "broad_flat_head", broad_head_box.size)
	var broad_slide_sample := Node3D.new()
	broad_slide_sample.position = broad_slide_box.center
	view.add_child(broad_slide_sample)
	presenter.preview_component(broad_slide_sample, "copper_slide", broad_slide_box.size)
	verify(broad_bed_sample.has_node("JoinedWorkbedBase")
		and broad_head_sample.has_node("BroadHeadMovingDie/JoinedFlatFace")
		and broad_slide_sample.has_node("SlideCarriage"),
		"The sized workbed, single moving face and slide have separate visible parts.")
	if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
		camera.position = broad_bed_box.center + Vector3(5.0, 3.0, 6.0)
		camera.look_at(broad_bed_box.center + Vector3.UP * 0.55)
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-sized-workbed.png") == OK,
			"Retain the 2×2 workbed, joined face and one slide from a passive view.")
	broad_bed_sample.free()
	broad_head_sample.free()
	broad_slide_sample.free()
	view.state.placed_components["workbed"] = {"component": "anvil", "center": [12, 0, 8],
		"generation": 1, "occupied": {"center": [workbed_box.center.x, workbed_box.center.y,
			workbed_box.center.z], "half": [workbed_box.half.x, workbed_box.half.y,
			workbed_box.half.z]}}
	view.state.cargo.P.components.flat_head = 1
	choice.kind = "flat_head"
	view.aimed = "workbed"
	view.aim_normal = Vector3.RIGHT
	body.set_meta("component_entity", "workbed")
	body.collision_layer = Geometry.PICK_LAYER
	body.position = workbed_box.center
	var press_collision := CollisionShape3D.new()
	var press_shape := BoxShape3D.new()
	press_shape.size = workbed_box.size
	press_collision.shape = press_shape
	body.add_child(press_collision)
	camera.position = workbed_box.center + Vector3(1.05, 1.2, 2.2)
	camera.look_at(workbed_box.center)
	await physics_frame
	var workbed_hit := _component_center_hit(camera)
	verify(workbed_hit.get("collider") == body and absf(workbed_hit.get("normal", Vector3.UP).y) < 0.5,
		"A standing eye-level center ray can hit a side of the lower workbed.")
	view._refresh_component_preview()
	verify(view._component_place_center(Vector2i.ZERO, "workbed") == [12, 1, 8]
		and view.component_preview.visible and not view.component_preview_blocked
		and view.component_preview_snap == "Head over workbed"
		and "Aim at the anvil to place the head above" in view._component_placement_hint(),
		"A standing side-face aim on the anvil shows a clear fitted head and names the target.")
	view._world_click(Vector2i.ZERO, "workbed")
	verify(view.issued.back().center == [12, 1, 8],
		"A click on the anvil side sends the displayed elevated head center to Host.")
	view.aim_normal = Vector3.UP
	verify(view._component_place_center(Vector2i.ZERO, "workbed") == [12, 1, 8],
		"Top-face aiming retains the same fitted head socket.")
	verify(view._guided_press_part_snap("ram_face", "anvil", [12, 0, 8], Vector3.RIGHT).center == [12, 1, 8]
		and view._guided_press_part_snap("flat_head", "wooden_frame", [12, 0, 8], Vector3.RIGHT).is_empty(),
		"A player can snap the guided ram from an anvil side without changing unrelated fittings.")
	if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
		view.aim_normal = Vector3.RIGHT
		view._refresh_component_preview()
		workbed_sample.visible = true
		frame.visible = false
		head_sample.visible = false
		slide_sample.visible = false
		stroked_head.visible = false
		stroked_slide.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-head-side-snap.png") == OK,
			"Retain the actor-eye head ghost from an anvil side aim.")
	view.state.placed_components["sample-head"] = {"component": "flat_head", "center": [12, 1, 8],
		"generation": 1, "occupied": {"center": [head_box.center.x, head_box.center.y,
			head_box.center.z], "half": [head_box.half.x, head_box.half.y, head_box.half.z]}}
	view.state.cargo.P.components.copper_slide = 1
	choice.kind = "copper_slide"
	view.aimed = "sample-head"
	view.aim_normal = Vector3.RIGHT
	body.set_meta("component_entity", "sample-head")
	body.position = head_box.center
	press_shape.size = head_box.size
	camera.look_at(head_box.center)
	await physics_frame
	var head_hit := _component_center_hit(camera)
	verify(head_hit.get("collider") == body and absf(head_hit.get("normal", Vector3.UP).y) < 0.5,
		"A standing eye-level center ray can hit the fitted head's side.")
	view._refresh_component_preview()
	verify(view._component_place_center(Vector2i.ZERO, "sample-head") == [12, 2, 8]
		and view.component_preview.visible and not view.component_preview_blocked
		and view.component_preview_snap == "Slide over head"
		and "Aim at the flat head to place the slide above" in view._component_placement_hint(),
		"A standing side-face aim on the head shows a clear fitted slide and names the target.")
	view._world_click(Vector2i.ZERO, "sample-head")
	verify(view.issued.back().center == [12, 2, 8],
		"A click on the head side sends the displayed elevated slide center to Host.")
	view.aim_normal = Vector3.UP
	verify(view._component_place_center(Vector2i.ZERO, "sample-head") == [12, 2, 8],
		"Top-face aiming retains the same fitted slide socket.")
	if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
		view.aim_normal = Vector3.RIGHT
		view._refresh_component_preview()
		head_sample.visible = true
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-slide-side-snap.png") == OK,
			"Retain the actor-eye slide ghost from a head side aim.")
	view.state.placed_components.erase("sample-head")
	view.state.placed_components.erase("workbed")
	view.issued.clear()
	choice.kind = "anvil"
	view.aimed = "frame"
	view.aim_normal = Vector3.UP
	body.set_meta("component_entity", "frame")
	press_collision.free()
	body.position = Vector3.ZERO
	frame.visible = true
	head_sample.free()
	workbed_sample.free()
	slide_sample.free()
	stroked_head.free()
	stroked_slide.free()
	view.component_nudge_active = true
	view.state.cargo.P.components.anvil = 4
	choice.kind = "broad_anvil"
	var clear_area: Array = []
	for x in range(-24, 25, 4):
		for z in range(-24, 25, 4):
			var candidate := [x, 0, z]
			if view._component_area_bounds_allowed("broad_anvil", candidate) \
					and not view._component_candidate_blocked("broad_anvil", candidate,
						view._component_candidate_box("broad_anvil", candidate)):
				clear_area = candidate
				break
		if not clear_area.is_empty():
			break
	verify(not clear_area.is_empty(), "The isolated fixture has one clear, contiguous workbed site.")
	if not clear_area.is_empty():
		view.component_nudge_center = clear_area.duplicate()
		view._refresh_component_preview()
		verify(view.component_preview.visible and not view.component_preview_blocked
			and view.component_preview_kind == "broad_anvil"
			and view.component_preview.has_node("JoinedWorkbedBase"),
			"The broad choice previews one joined workbed over the full native occupied area.")
		view.issued.clear()
		view._world_click(Vector2i.ZERO)
		verify(view.issued.size() == 1 and view.issued[0].component == "broad_anvil"
			and view.issued[0].center == clear_area,
			"One click sends one four-part workbed placement with the previewed center.")
		view.issued.clear()
		var blocker_center := [clear_area[0] + 2, 0, clear_area[2] + 2]
		var blocking_box := view._component_candidate_box("wooden_frame", blocker_center)
		view.state.placed_components["broad_obstacle"] = {"component": "wooden_frame",
			"center": blocker_center, "generation": 2,
			"occupied": {"center": [blocking_box.center.x, blocking_box.center.y,
				blocking_box.center.z], "half": [blocking_box.half.x,
				blocking_box.half.y, blocking_box.half.z]}}
		view._refresh_component_preview()
		verify(view.component_preview.visible and view.component_preview_blocked
			and view.component_preview_material.albedo_color.r > 0.9
			and view.component_preview_material.albedo_color.g < 0.4,
			"Any obstruction turns the whole joined workbed ghost red.")
		view.state.placed_components.erase("broad_obstacle")
		if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			view._refresh_component_preview()
			camera.position = view.component_preview.position + Vector3(5.0, 2.0, 6.0)
			camera.look_at(view.component_preview.position)
			await process_frame
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(prefix + "-broad-ground.png") == OK,
				"Retain the joined workbed ghost from a passive view.")
		var last_inside := floori((SiteSurface.HALF - Geometry.HEIGHT_STEP / 2.0) \
			/ Geometry.HEIGHT_STEP)
		view.component_nudge_center = [last_inside, 0, 0]
		view._refresh_component_preview()
		verify(view._component_center_allowed(view.component_nudge_center)
			and not view._component_area_bounds_allowed("broad_anvil", view.component_nudge_center)
			and view.component_preview_blocked,
			"A workbed crossing the terrain edge refuses as one complete footprint.")
	choice.kind = "anvil"
	view.component_nudge_active = false
	view.component_preview_pose_key = ""
	view._refresh_component_preview()
	view._input(_component_key(KEY_ALT, true, true))
	view._input(_component_key(KEY_RIGHT, true, true))
	view._input(_component_key(KEY_PAGEUP, true, true))
	verify(view.component_nudge_center == [1, 2, 0],
		"Alt, Right and Page Up move the locked center by quarter-grid steps.")
	view.aimed = ""
	view.pointed_cell = Vector2i(4, 4)
	var old_hover := view.hover_cell
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(900, 300)
	view._unhandled_input(motion)
	verify(view.hover_cell == old_hover,
		"Mouse motion does not update the component pointer datum while Alt is held.")
	# The fixture uses a close passive camera; the view's normal motion handler
	# also updates its gameplay camera, so restore this capture framing.
	camera.position = Vector3(1.15, 2.05, 2.4)
	camera.look_at(Vector3(0, 1.15, 0))
	verify(view._component_place_center(view.pointed_cell, "") == [1, 2, 0],
		"Pointer movement does not move the ghost while Alt is held.")
	view._world_click(view.pointed_cell)
	verify(view.issued.size() == 1 and view.issued[0].center == [1, 2, 0],
		"Click sends the exact visible nudged center to Host.")
	view._input(_component_key(KEY_ALT, false))
	verify(not view.component_nudge_active and view._component_place_center(view.pointed_cell, "") == [16, 0, 16],
		"Releasing Alt resumes the pointer's construction datum.")
	view.aimed = "frame"
	view.pointed_cell = Vector2i.ZERO
	view.state.placed_components["anvil"] = {"component": "anvil", "center": [0, 1, 0],
		"generation": 1, "occupied": {"center": [0.0, 0.61875, 0.0],
		"half": [0.2025, 0.20625, 0.14]}}
	var placed_anvil := Node3D.new()
	placed_anvil.position.y = 0.61875
	view.add_child(placed_anvil)
	presenter.preview_component(placed_anvil, "anvil", Vector3(0.405, 0.4125, 0.28))
	view._refresh_component_preview()
	verify(view.component_preview_blocked and view.component_preview_material.albedo_color.r > 0.9
		and view.component_preview_material.albedo_color.g < 0.4,
		"An occupied candidate stays visible and turns red.")
	if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-blocked.png") == OK,
			"Retain the red ghost at an occupied anvil point.")
	view._input(_component_key(KEY_ALT, true, true))
	view._input(_component_key(KEY_RIGHT, true, true))
	verify(view.component_nudge_center == [1, 1, 0] and not view.component_preview_blocked
		and view.component_preview.visible,
		"An obstructed red ghost can be nudged directly to a clear amber point.")
	view._input(_component_key(KEY_ALT, false))
	choice.kind = "ram_face"
	body.set_meta("component_entity", "anvil")
	view.aimed = "anvil"
	view._refresh_component_preview()
	verify(view._component_place_center(Vector2i.ZERO, "anvil") == [0, 2, 0]
		and view.component_preview.has_node("MovingDie") and not view.component_preview_blocked,
		"The ram face snaps above the anvil with its placed-part die visible.")
	view.state.cargo.P.components.sliding_guide = 1
	choice.kind = "sliding_guide"
	view._refresh_component_preview()
	verify(view._component_place_center(Vector2i.ZERO, "anvil") == [0, 4, 0]
		and view.component_preview.visible and not view.component_preview_blocked
		and view.component_preview_snap == "Guide over anvil"
		and view.component_preview.has_node("GuideCrown"),
		"Pointing at the reachable anvil top shows the guide at the native raised socket.")
	verify("Aim at the anvil or ram top" in view._component_placement_hint(),
		"The guide hint names the part the player can point at.")
	view._world_click(Vector2i.ZERO, "anvil")
	verify(view.issued.back().center == [0, 4, 0],
		"Click sends the same elevated guide center shown by the ghost.")
	var ram_box := view._component_candidate_box("ram_face", [0, 2, 0])
	view.state.placed_components["ram"] = {"component": "ram_face", "center": [0, 2, 0],
		"generation": 1,
		"occupied": {"center": [ram_box.center.x, ram_box.center.y, ram_box.center.z],
			"half": [ram_box.half.x, ram_box.half.y, ram_box.half.z]}}
	var ram_record: Dictionary = view.state.placed_components.ram
	var placed_ram := Node3D.new()
	placed_ram.position = ram_box.center
	view.add_child(placed_ram)
	presenter.preview_component(placed_ram, "ram_face", ram_box.size)
	var fitted_guide_box := view._component_candidate_box("sliding_guide", [0, 3, 0])
	verify(not view._component_candidate_blocked("sliding_guide", [0, 3, 0], fitted_guide_box)
		and fitted_guide_box.center.y - fitted_guide_box.half.y < ram_box.center.y + ram_box.half.y,
		"The full guide rails preview around the exact fitted ram without hiding their occupied span.")
	view.state.placed_components["fitted_guide"] = {"component": "sliding_guide", "center": [0, 3, 0],
		"generation": 1, "occupied": {"center": [fitted_guide_box.center.x,
			fitted_guide_box.center.y, fitted_guide_box.center.z],
			"half": [fitted_guide_box.half.x, fitted_guide_box.half.y, fitted_guide_box.half.z]}}
	view.state.placed_components.erase("ram")
	verify(not view._component_candidate_blocked("ram_face", [0, 2, 0], ram_box)
		and view._component_candidate_blocked("wooden_shaft", [0, 2, 0],
			view._component_candidate_box("wooden_shaft", [0, 2, 0])),
		"A ram can fit into the guide in reverse order, while an unrelated shaft cannot enter the rails.")
	view.state.placed_components.erase("fitted_guide")
	view.state.placed_components["ram"] = ram_record
	view.aimed = "ram"
	body.set_meta("component_entity", "ram")
	view._refresh_component_preview()
	verify(view._component_place_center(Vector2i.ZERO, "ram") == [0, 4, 0]
		and view.component_preview_snap == "Guide over ram"
		and not view.component_preview_blocked,
		"Pointing at the fitted ram top finds the same clear guide socket across the stroke gap.")
	if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
		camera.position = Vector3(1.7, 3.4, 3.8)
		camera.look_at(Vector3(0, 2.0, 0))
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-guide.png") == OK,
			"Retain the anvil-targeted raised guide ghost in a passive view.")
		camera.position = Vector3(1.15, 2.05, 2.4)
		camera.look_at(Vector3(0, 1.15, 0))
	view.state.placed_components.erase("ram")
	placed_ram.free()
	view.aimed = "anvil"
	body.set_meta("component_entity", "anvil")
	view.state.cargo.P.components.wooden_shaft = 1
	choice.kind = "wooden_shaft"
	view.aim_normal = Vector3.RIGHT
	view._refresh_component_preview()
	verify(view._component_place_center(Vector2i.ZERO, "anvil") == [1, 5, 0]
		and view.component_preview.visible and not view.component_preview_blocked
		and view.component_preview_snap == "Press drive from anvil",
		"Pointing at an anvil side exposes the elevated neighboring drive shaft.")
	view._world_click(Vector2i.ZERO, "anvil")
	verify(view.issued.back().center == [1, 5, 0],
		"Click uses the shaft's visible anvil-side target rather than the ground datum.")
	view.state.cargo.P.components.copper_cog = 1
	choice.kind = "copper_cog"
	view._refresh_component_preview()
	verify(view._component_place_center(Vector2i.ZERO, "anvil") == [2, 5, 0]
		and view.component_preview.visible and not view.component_preview_blocked,
		"The same reachable anvil side points to the cog beyond the shaft.")
	view._world_click(Vector2i.ZERO, "anvil")
	verify(view.issued.back().center == [2, 5, 0],
		"Cog click agrees with the elevated preview center.")
	view.aim_normal = Vector3.BACK
	view._refresh_component_preview()
	verify(view._component_place_center(Vector2i.ZERO, "anvil") == [0, 5, 2]
		and not view.component_preview_blocked,
		"The anvil's other open side offers a second horizontal press-drive layout.")
	view.aim_normal = Vector3.RIGHT
	view._input(_component_key(KEY_ALT, true, true))
	view._input(_component_key(KEY_PAGEUP, true, true))
	verify(view._component_place_center(Vector2i.ZERO, "anvil") == [2, 6, 0],
		"Manual nudge still overrides the suggested press socket.")
	view._input(_component_key(KEY_ALT, false))
	view.aim_normal = Vector3.UP
	choice.kind = "sliding_guide"
	var guide_box := view._component_candidate_box("sliding_guide", [0, 4, 0])
	view.state.placed_components["occupied_guide"] = {"component": "sliding_guide",
		"center": [0, 4, 0], "generation": 1,
		"occupied": {"center": [guide_box.center.x, guide_box.center.y, guide_box.center.z],
			"half": [guide_box.half.x, guide_box.half.y, guide_box.half.z]}}
	view._refresh_component_preview()
	verify(view.component_preview.visible and view.component_preview_blocked,
		"The snapped upper socket remains visibly blocked when another part occupies it.")
	view.state.placed_components.erase("occupied_guide")
	choice.kind = "ram_face"
	view._refresh_component_preview()
	if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-ram.png") == OK,
			"Retain the isolated ram-face ghost over an anvil and wooden frame.")
		choice.kind = "anvil"
		body.set_meta("component_entity", "frame")
		view.aimed = "frame"
		view.state.placed_components.erase("anvil")
		placed_anvil.free()
		view._refresh_component_preview()
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-anvil.png") == OK,
			"Retain the isolated anvil ghost snapped to the frame top.")
	view.state.placed_components.clear()
	view.state.cargo.P.components.wooden_frame = 1
	choice.kind = "wooden_frame"
	view.aimed = ""
	view.component_nudge_active = true
	view.state.foundations = {"raised_floor": {"cell": [1, 0], "level": 1}}
	view.component_nudge_center = [4, 0, 0]
	view._refresh_component_preview()
	verify(view.component_preview.visible and view.component_preview_blocked,
		"A component nudged into a projected foundation shows the native occupied point in red.")
	if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
		camera.position = view.component_preview.position + Vector3(1.15, 1.7, 2.4)
		camera.look_at(view.component_preview.position)
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-foundation-blocked.png") == OK,
			"Retain the foundation-obstructed component ghost.")
	view.component_nudge_center = [8, 0, 0]
	view._refresh_component_preview()
	verify(view.component_preview.visible and not view.component_preview_blocked,
		"Nudging away from the foundation restores a clear ghost.")
	view.state.foundations.clear()
	var rock: Dictionary = SiteSurface.support_boxes()[0]
	view.component_nudge_center = [roundi(rock.center.x / Geometry.HEIGHT_STEP),
		roundi(rock.center.y / Geometry.HEIGHT_STEP),
		roundi(rock.center.z / Geometry.HEIGHT_STEP)]
	view._refresh_component_preview()
	verify(view.component_preview.visible and view.component_preview_blocked,
		"A normal terrain rock's shared occupied envelope turns the ghost red.")
	view.state.cargo.P.components.cutting_edge = 1
	view.state.collector_assemblies = [{"center": [0, 0, 0], "toward_ore": [-1, 0, 0]}]
	choice.kind = "cutting_edge"
	view.component_nudge_center = [-2, 0, 0]
	var source: Dictionary = SiteSurface.source_outcrop()
	var source_box: AABB = Transform3D(source.basis, source.center) * \
		AABB(-source.size * 0.5, source.size)
	var cutter: Dictionary = view._component_candidate_box(choice.kind, view.component_nudge_center)
	verify(source_box.intersects(AABB(cutter.center - cutter.half, cutter.size)),
		"The trusted cutter point actually overlaps the source envelope in this control.")
	view._refresh_component_preview()
	verify(view.component_preview.visible and not view.component_preview_blocked,
		"The trusted ore-face cutting edge remains clear despite its allowed source contact.")
	verify(view.component_preview.has_node("EdgeSupportPostLeft")
		and is_equal_approx(view.component_preview.position.y,
			view.component_nudge_center[1] * Geometry.HEIGHT_STEP + Geometry.ANCHOR_HEIGHT - 0.015),
		"The cutter ghost includes its floor-reaching support at the native head height.")
	if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
		camera.position = view.component_preview.position + Vector3(1.15, 1.7, 2.4)
		camera.look_at(view.component_preview.position)
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-ore-cutter.png") == OK,
			"Retain the allowed ore-face cutter and its floor-reaching support.")
	view.client = "P"
	view.component_nudge_active = false
	view.state.placed_components = {"shaft": {"component": "wooden_shaft",
		"center": [0, 4, 0], "position": [0.0, 2.475, 0.0],
		"input_ports": [[0, 4, 0]], "crank_axis": 0}}
	view.state.crank_items = {"crank-id": {"holder": "P"}}
	view.state.cargo.P.components.hand_crank = 1
	view.state.actors.P.position = [1.0, 1.0, 0.0]
	choice.kind = "hand_crank"
	view.aimed = "shaft"
	view.aim_normal = Vector3.RIGHT
	body.set_meta("component_entity", "shaft")
	view._refresh_component_preview()
	verify(view.component_preview.visible and not view.component_preview_blocked
		and absf(view.component_preview.position.x - 0.22) < 0.001
		and absf(view.component_preview.rotation.y) < 0.001,
		"The ordinary crank ghost follows the native positive X spindle face.")
	view._world_click(Vector2i.ZERO, "shaft")
	verify(view.issued.back().face == [1, 0, 0],
		"Fitting from the positive X side sends the projected spindle face for native validation.")
	view.state.actors.P.position = [-1.0, 1.0, 0.0]
	view._refresh_component_preview()
	verify(absf(view.component_preview.position.x + 0.22) < 0.001
		and absf(absf(view.component_preview.rotation.y) - PI) < 0.001,
		"Approaching the other side mirrors the visible crank preview.")
	view._world_click(Vector2i.ZERO, "shaft")
	verify(view.issued.back().face == [-1, 0, 0],
		"The mirrored native attachment request matches the ordinary preview.")
	view.state.placed_components.shaft.crank_axis = 2
	view.state.actors.P.position = [0.0, 1.0, 1.0]
	view._refresh_component_preview()
	verify(absf(view.component_preview.position.z - 0.22) < 0.001
		and absf(view.component_preview.rotation.y + PI * 0.5) < 0.001,
		"A native Z spindle rotates the preview around the actual horizontal axis.")
	view._world_click(Vector2i.ZERO, "shaft")
	verify(view.issued.back().face == [0, 0, 1],
		"The ordinary Z-facing fit sends the same signed face as its preview.")
	view.state.actors.P.position = [0.0, 1.0, -1.0]
	view._world_click(Vector2i.ZERO, "shaft")
	verify(view.issued.back().face == [0, 0, -1],
		"Approaching the opposite Z face reverses the requested native winding.")
	view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"failures": failures, "models": 0, "desktop_operations": 0,
		"scope": "isolated component placement input and preview"}))
	quit(0 if failures == 0 else 1)

func hotbar_observation() -> Dictionary:
	var kit := {"collector": 1, "foundation": 24, "belt": 1, "processor": 1, "wheel": 1, "gear": 10, "shaft": 8}
	var other := {"collector": 0, "foundation": 2, "belt": 0, "processor": 1, "wheel": 0, "gear": 1, "shaft": 2}
	return {"context": "hotbar-fixture", "revision": 7, "order": 0,
		"options": {"physical": true, "native": true, "foundations": true},
		"actors": {"P": {"ready": true, "position": [0.0, 1.0, 0.0],
			"capabilities": {"build_reach": 4.0, "harvest_reach": 2.55}},
			"Q": {"ready": true, "position": [3.0, 1.0, 0.0],
				"capabilities": {"build_reach": 4.0, "harvest_reach": 2.55}}},
		"parts": kit.duplicate(), "part_kits": {"P": kit.duplicate(), "Q": other},
		"part_specifications": {"P": [{"kind": "gear", "count": 8, "teeth": 2, "half_span": 0},
			{"kind": "gear", "count": 2, "teeth": 4, "half_span": 0},
			{"kind": "shaft", "count": 8, "teeth": 0, "half_span": 2}], "Q": []},
		"entities": {}, "foundations": {}, "transmission_parts": {}, "motion": {}, "engagements": [],
		"links": [], "drive_links": [], "inventories": {"P": 0, "Q": 0},
		"stock": {"source": 4096, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
		"remaining": 0, "powered": false, "power_enabled": false}

func _multitool_grip_distance(body: Node3D, tool: Node3D) -> float:
	var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
	var grip: MeshInstance3D = tool.get_node("GripCore")
	var grip_center: Vector3 = tool.transform * grip.transform * grip.mesh.get_aabb().get_center()
	var hand_pose: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 R Hand"))
	var farthest := 0.0
	for finger in ["Bip01 R Finger12", "Bip01 R Finger22", "Bip01 R Finger32"]:
		var joint: Vector3 = hand_pose.affine_inverse() * skeleton.get_bone_global_pose(
			skeleton.find_bone(finger)).origin
		farthest = maxf(farthest, grip_center.distance_to(joint))
	return farthest

func _multitool_presentation() -> void:
	for shared in [false, true]:
		var view = SharedWidgets.new() if shared else OfflineWidgets.new()
		view.client = "P"
		view.state = hotbar_observation()
		view.state.hand_sources = {"tree": {"kind": "tree", "position": [2.0, 0.8, 0.0], "remaining": 8}}
		var original: Dictionary = view.state.duplicate(true)
		view.camera = Camera3D.new()
		view.add_child(view.camera)
		root.add_child(view)
		view._start_character_presenter()
		var presenter = view.character_presenter
		presenter.set_process(false)
		presenter.set_physics_process(false)
		var body: Node3D = presenter.views.P.get_node("BodyView")
		verify(body.has_meta("multitool_attachment"), "The ordinary arriving worker has a visible reusable multitool.")
		if not body.has_meta("multitool_attachment"):
			view.free()
			break
		var attachment: BoneAttachment3D = body.get_node(body.get_meta("multitool_attachment"))
		verify(attachment.bone_name == "Bip01 R Hand" and attachment.get_parent() is Skeleton3D,
			"The tool is attached to the qualified hand rather than the world or native actor body.")
		var blade: MeshInstance3D = attachment.get_child(0).get_node("CuttingBlade")
		verify(blade.mesh.get_surface_count() > 0 and blade.mesh.get_aabb().size.z > 0.15,
			"The cutter has actual blade geometry with a readable authored silhouette.")
		var q_body: Node3D = presenter.views.Q.get_node("BodyView")
		var q_attachment: BoneAttachment3D = q_body.get_node(q_body.get_meta("multitool_attachment"))
		verify(q_attachment.get_child(0).get_node("CuttingBlade").mesh == blade.mesh,
			"Both shared actors reuse the same tool mesh resources.")
		verify(_multitool_grip_distance(body, attachment.get_child(0)) < 0.05
			and _multitool_grip_distance(q_body, q_attachment.get_child(0)) < 0.05,
			"Both sourced hands curl around the actual cutter grip instead of hovering beside it.")
		verify(presenter.eye_multitool == null, "The third-person view does not allocate a hidden first-person hand.")
		var identity := attachment.get_instance_id()
		for frame in range(10):
			presenter.refresh()
		verify(body.get_node(body.get_meta("multitool_attachment")).get_instance_id() == identity,
			"Unchanged presentation reuses the hand attachment.")
		view.distance = 0.0
		presenter.refresh()
		verify(presenter.eye_multitool != null and presenter.eye_multitool.visible and not presenter.views.P.visible and presenter.views.Q.visible,
			"Eye-level presentation shows one local tool while retaining the other actor's normal body.")
		var hand: MeshInstance3D = presenter.eye_multitool.get_node("QualifiedRightHand")
		var sleeve: MeshInstance3D = presenter.eye_multitool.get_node_or_null("QualifiedSleeve")
		var arm_bounds: AABB = hand.mesh.get_aabb().merge(sleeve.mesh.get_aabb()) if sleeve != null else hand.mesh.get_aabb()
		verify(hand.mesh.get_surface_count() > 0 and arm_bounds.size.length() > 0.55
			and arm_bounds.size.length() < 0.85 and arm_bounds.size.y < 0.30,
			"The close view includes the qualified worker's hand and connected forearm without torso geometry: " + str(arm_bounds))
		verify(sleeve != null and sleeve.mesh.get_surface_count() > 0,
			"The first-person modeled hand stays seated under its sourced worker sleeve.")
		verify(presenter.eye_multitool.get_node("CuttingBlade").mesh == blade.mesh,
			"First- and third-person presentations use the exact same authored cutter.")
		var hand_id := hand.mesh.get_instance_id()
		var tool_id: int = presenter.eye_multitool.get_instance_id()
		for frame in range(10):
			presenter.refresh()
		verify(presenter.eye_multitool.get_instance_id() == tool_id and hand.mesh.get_instance_id() == hand_id,
			"The close view does not reconstruct its tool or skinned hand every frame.")
		view.state.actors.P.ready = false
		presenter.refresh()
		verify(not presenter.eye_multitool.visible, "An unready actor cannot present an active first-person tool.")
		view.state.actors.P.ready = true
		view.distance = 14.0
		presenter.refresh()
		verify(not presenter.eye_multitool.visible and presenter.views.P.visible,
			"Returning to the ordinary camera hides the close view and restores the actual actor.")
		verify(view.state == original and view.issued.is_empty() and presenter.find_children("*", "CollisionObject3D", true, false).is_empty(),
			"Tool presentation changes no source stock, actor authority, request or collision body.")
		view.free()
		await process_frame
	print("MULTITOOL_PRESENTATION_%s %d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func settle_widgets() -> void:
	for _frame in range(4):
		await process_frame

func _pod_surface_hit(node: Node3D, start: Vector3, end: Vector3) -> bool:
	for part: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var a := part.to_local(start)
		var b := part.to_local(end)
		var faces := part.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(a, b, faces[index], faces[index + 1], faces[index + 2]) != null:
				return true
	return false

func _pod_floor_views() -> void:
	for shared in [false, true]:
		for level in [-4, 0, 8]:
			var view = SharedSourceRayView.new() if shared else SourceRayView.new()
			var floor_y: float = level * Opening.Geometry.HEIGHT_STEP
			view.state = {"options": {"native": true},
				"landing_pod": {"id": "landing-pod", "center": [1, level, 4], "deployed": true},
				"fabrication_hub": {"id": "pod-fabrication-hub", "installed": true, "center": [2, level, 4],
					"position": [3.3, floor_y + Opening.Geometry.ANCHOR_HEIGHT, 6.6]},
				"crank_items": {}}
			var before: Dictionary = view.state.duplicate(true)
			root.add_child(view)
			view.camera = Camera3D.new()
			view.add_child(view.camera)
			view.machine_root = Node3D.new()
			view.add_child(view.machine_root)
			var deck := Node3D.new()
			deck.position = view._entity_position({"cell": [1, 4], "level": level})
			deck.set_meta("arrival_deck_panel", true)
			deck.set_meta("arrival_deck_anchor", deck.position)
			view.machine_root.add_child(deck)
			view._sync_landing_pod_visual()
			var pod_floor := Vector3(1.65, floor_y, 6.6)
			var hub_floor := Vector3(3.3, floor_y, 6.6)
			verify(view.landing_pod_visual.position.is_equal_approx(pod_floor)
				and view.landing_hub_visual.position.is_equal_approx(hub_floor),
				"Pod and bench roots share the foundation top plane at every native grid height.")
			var foot: MeshInstance3D = view.landing_pod_visual.find_children("*LandingFoot*", "MeshInstance3D", true, false)[0]
			var leg: MeshInstance3D = view.landing_hub_visual.find_children("BenchLeg*", "MeshInstance3D", true, false)[0]
			verify(absf((foot.global_transform * foot.get_aabb()).position.y - deck.position.y) < 0.00001
				and absf((leg.global_transform * leg.get_aabb()).position.y - deck.position.y) < 0.00001,
				"Actual authored feet and bench legs meet the deck instead of floating at the spindle anchor.")
			var original_pod: Node3D = view.landing_pod_visual
			var original_hub: Node3D = view.landing_hub_visual
			view._sync_landing_pod_visual()
			verify(view.landing_pod_visual == original_pod and view.landing_hub_visual == original_hub
				and view.state == before and view.model == null and view.request_sequence == 0,
				"An unchanged refresh reuses presentation without mutating native facts or making requests.")
			var restored = SharedSourceRayView.new() if shared else SourceRayView.new()
			restored.state = before.duplicate(true)
			root.add_child(restored)
			restored._sync_landing_pod_visual()
			verify(restored.landing_pod_visual.position.is_equal_approx(pod_floor)
				and restored.landing_hub_visual.position.is_equal_approx(hub_floor),
				"A newly constructed saved-state view uses the same floor datum.")
			view.arrival_reveal_pod_anchor = view.landing_pod_visual.position
			view.arrival_reveal_active = true
			view.arrival_reveal_elapsed = 0.0
			view._pose_arrival_reveal()
			verify(view.landing_pod_visual.position.is_equal_approx(pod_floor + Vector3.UP * 8.0)
				and not view.landing_hub_visual.visible,
				"The reveal starts above the actual floor and keeps the unopened bench hidden.")
			var cabin: Node3D = view.landing_pod_visual
			var interior: Vector3 = cabin.to_global(Vector3(0, 0.75, -0.25))
			verify(_pod_surface_hit(cabin, interior, cabin.to_global(Vector3(0, 2.0, -0.25)))
				and _pod_surface_hit(cabin, interior, cabin.to_global(Vector3(0, 0.75, -1.4))),
				"The descending package has actual roof and forward hatch surfaces over its interior.")
			verify(leg.global_basis.get_scale().is_equal_approx(Vector3.ONE),
				"The packed bench remains rigid rather than shrinking vertically.")
			var pod_children: Array = view.landing_pod_visual.find_children("*", "MeshInstance3D", true, false)
			for sample in [1.7, 2.2]:
				view.arrival_reveal_elapsed = sample
				view._pose_arrival_reveal()
				verify(leg.global_basis.get_scale().is_equal_approx(Vector3.ONE)
					and view.landing_pod_visual.find_children("*", "MeshInstance3D", true, false) == pod_children
					and view.state == before,
					"Unfolding preserves rigid bench geometry, cached meshes and confirmed native facts.")
			view.arrival_reveal_elapsed = view.ARRIVAL_REVEAL_SECONDS
			view._pose_arrival_reveal()
			verify(view.landing_pod_visual.position.is_equal_approx(pod_floor)
				and view.landing_hub_visual.position.is_equal_approx(hub_floor)
				and view.landing_hub_visual.scale == Vector3.ONE and is_equal_approx(deck.position.y, floor_y),
				"The reveal endpoint seats the pod and bench on the unfolded foundation.")
			interior = cabin.to_global(Vector3(0, 0.75, -0.25))
			verify(not _pod_surface_hit(cabin, interior, cabin.to_global(Vector3(0, 2.0, -0.25)))
				and not _pod_surface_hit(cabin, interior, cabin.to_global(Vector3(0, 0.75, -1.4))),
				"The folded canopy leaves the front opening clear after touchdown.")
			var restored_interior: Vector3 = restored.landing_pod_visual.to_global(Vector3(0, 0.75, -0.25))
			verify(not _pod_surface_hit(restored.landing_pod_visual, restored_interior,
					restored.landing_pod_visual.to_global(Vector3(0, 2.0, -0.25))),
				"Saved and shared deployed views construct the already opened canopy without replaying arrival.")
			view.arrival_reveal_active = false
			view._sync_landing_pod_visual()
			verify(view.landing_pod_visual.position.is_equal_approx(pod_floor)
				and view.landing_hub_visual.position.is_equal_approx(hub_floor) and view.state == before,
				"Ordinary refresh after touchdown applies the datum conversion exactly once.")
			view.state = before.duplicate(true)
			view.state.fabrication_hub.installed = false
			view.state.fabrication_hub.holder = "P"
			view._sync_landing_pod_visual()
			verify(not view.landing_hub_visual.visible and view.landing_hub_pick.collision_layer == 0,
				"Stowing the issued workshop removes its view and pick.")
			view.arrival_reveal_elapsed = 2.2
			view._pose_arrival_reveal()
			verify(not view.landing_hub_visual.visible and view.landing_hub_pick.collision_layer == 0,
				"Local reveal posing cannot make a natively held workshop visible or selectable.")
			view.arrival_reveal_elapsed = view.ARRIVAL_REVEAL_SECONDS
			view._pose_arrival_reveal()
			view.state.fabrication_hub.installed = true
			view.state.fabrication_hub.erase("holder")
			view.state.fabrication_hub.center = [4, level, 4]
			view.state.fabrication_hub.position = [6.6, floor_y + Opening.Geometry.ANCHOR_HEIGHT, 6.6]
			view._sync_landing_pod_visual()
			verify(view.landing_hub_visual.visible and view.landing_hub_pick.collision_layer == Opening.Geometry.PICK_LAYER
				and view.landing_hub_visual.position.is_equal_approx(Vector3(6.6, floor_y, 6.6))
				and view.landing_pod_visual.position.is_equal_approx(pod_floor),
				"A moved workshop keeps the rigid bench and matching pick separate from the fixed pod.")
			restored.free()
			view.free()
	print("POD_FLOOR_VIEW_%s %d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

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
	var scar: MeshInstance3D = old_body.get_node("Cut")
	verify(scar.mesh is ArrayMesh and scar.mesh.get_aabb().size.y > 0.5
		and scar.material_override is ShaderMaterial
		and is_equal_approx(scar.material_override.get_shader_parameter("cut_fraction"), 0.125),
		"The first cut covers the actual bark mesh with native-count-driven surface scarring.")
	var scar_material: Material = scar.material_override
	view.state.hand_sources["tree-east-south"].remaining = 6
	var changed_counts: Dictionary = view.state.duplicate(true)
	view._refresh_hand_trees()
	verify(scar.material_override == scar_material
		and is_equal_approx(scar.material_override.get_shader_parameter("cut_fraction"), 0.25)
		and old_body.get_node("PickShape").shape == old_shape and view.state == changed_counts,
		"Further cuts reuse the same material and pick geometry without changing native data.")
	view.state.hand_sources["tree-east-south"].remaining = 0
	view._refresh_hand_trees()
	verify(not old_body.get_node("Tree").visible and old_body.get_node("Stump").visible
		and old_body.get_node("PickShape").shape != old_shape,
		"Native depletion leaves a stump and removes the invisible full-trunk pick shape.")
	var stump: MeshInstance3D = old_body.get_node("Stump")
	verify(stump.mesh is ArrayMesh and stump.mesh.get_aabb().end.y < 0.06
		and old_body.get_node("Cut").mesh is ArrayMesh and scar.material_override == null,
		"Depletion uses a low clipped trunk with its matching cap, not a lathed post or scar override.")
	var cut_plane_matches := true
	for point: Vector3 in old_body.get_node("Cut").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		cut_plane_matches = cut_plane_matches and absf(point.y - 0.045 - point.x * 0.15 - point.z * 0.10) < 0.000001
	verify(cut_plane_matches, "The irregular cap follows the same shallow plane that clips the actual bark.")
	var stump_aim := old_body.to_global(Vector3(0.0, 0.02, 0.0))
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
		view.state.hand_sources = {"ore": {"kind": "ore_deposit", "position": [0.0, 0.825, 0.0],
			"contact_bounds": [[-0.25, 0.5, -1.14], [0.25, 1.2, 1.14]],
			"initial": 16, "remaining": 2},
			"tree": {"kind": "tree", "position": [1.65, 0.825, 0.0], "initial": 8, "remaining": 1}}
		view.state.cargo = {"P": {"raw": 1, "timber": 3}, "Q": {"raw": 0, "timber": 0}}
		view.mode = "inspect"
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view.camera = Camera3D.new()
		view.add_child(view.camera)
		view._build_interface()
		view._refresh_ui()
		var before: Dictionary = view.state.duplicate(true)
		verify("FIRST WORKSHOP" in view.objective_heading.text and not view.goal_progress.visible
			and not view.goal_label.text.contains("3 timber") and not view.goal_label.text.contains("1 copper")
			and view.building_hotbar.material_counts.timber.text == "3"
			and view.building_hotbar.material_counts.raw.text == "1",
			"The arrival objective stays focused on the order while build/inventory shows confirmed cargo.")
		verify("Craft a part in Build [B]." in view.goal_label.text,
			"The stocked worker sees the build control without a required press recipe.")
		view.state.cargo.P.components = {"anvil": 1}
		view._refresh_ui()
		verify("Place a carried part [B]." in view.goal_label.text
			and not view.goal_label.text.contains("ram, guide, shaft and cog"),
			"A carried anvil does not become a mandatory press blueprint in the local or shared HUD.")
		view.state.placed_components = {"standalone-anvil": {"component": "anvil", "center": [0, 0, 0]}}
		view._refresh_ui()
		verify("Inspect parts [E] or build [B]." in view.goal_label.text
			and not view.goal_label.text.contains("Fit the press parts"),
			"A standalone work support retains component-level inspection guidance.")
		view.state = before.duplicate(true)
		view._refresh_ui()
		verify(not view.confirm_button.visible and view.help_button.visible,
			"Arrival offers current Help without the old objective confirmation.")
		view._toggle_explanation()
		verify(view.explanation_open and view.help_panel.visible
			and view.help_body.text.contains(view.goal_label.text),
			"Arrival Help shows the current objective without a separate example world.")
		view._toggle_explanation()
		verify(not view.explanation_open and not view.help_panel.visible,
			"Help returns to the same worksite.")
		view.hand_pointed = "ore"
		var ore_summary: Dictionary = view._pointed_summary_data(Vector2.ZERO)
		verify(ore_summary.get("name") == "Ore deposit" and "2 left" in ore_summary.get("detail", "")
			and "E Harvest" in ore_summary.get("detail", ""),
			"The pointed ore shows its native remaining stock and the real interaction key.")
		view._interact_pointed()
		verify(view.issued == [{"action": "harvest_source", "target": "ore"}],
			"The ordinary source interaction submits only its native target identity.")
		view.issued.clear()
		view.hand_pointed = "tree"
		var tree_summary: Dictionary = view._pointed_summary_data(Vector2.ZERO)
		verify(tree_summary.get("name") == "Timber tree" and "1 left" in tree_summary.get("detail", "")
			and "E Harvest" in tree_summary.get("detail", ""),
			"Timber uses the same confirmed-stock interaction rather than another inventory.")
		view._interact_pointed()
		verify(view.issued == [{"action": "harvest_source", "target": "tree"}], "The tree keeps its distinct native source identity.")
		view.issued.clear()
		view.state.actors.P.position = [0.0, 0.825, 3.70]
		view.hand_pointed = "ore"
		verify("Move closer" in view._pointed_summary_data(Vector2.ZERO).detail,
			"The ore prompt omits the harvest key beyond the projected native cut boundary.")
		view._interact_pointed()
		verify(view.issued.is_empty(), "A far source pick does not submit a misleading harvest request.")
		view.state.actors.P.position = [0.0, 0.825, 3.68]
		verify("E Harvest" in view._pointed_summary_data(Vector2.ZERO).detail,
			"The same ore pick offers the action inside the native cut boundary.")
		view._interact_pointed()
		verify(view.issued == [{"action": "harvest_source", "target": "ore"}],
			"An in-range source pick submits the native harvest command.")
		view.issued.clear()
		view.state.actors.P.harvest_clear = {"ore": false, "tree": true}
		verify("Move around" in view._pointed_summary_data(Vector2.ZERO).detail,
			"A source hidden from the physical actor does not offer the harvest key despite radial reach.")
		view._interact_pointed()
		verify(view.issued.is_empty(),
			"The pointed interaction does not submit a harvest through a native obstacle.")
		view.state.actors.P.harvest_clear = {"ore": true, "tree": true}
		verify("E Harvest" in view._pointed_summary_data(Vector2.ZERO).detail,
			"A newly clear path restores the source prompt at the same standing distance.")
		view.state.actors.P.position = before.actors.P.position
		view.state.actors.P.erase("harvest_clear")
		view.hand_pointed = "tree"
		verify(view.state == before and view.model == null and view.request_sequence == 0,
			"Presentation and request selection do not debit local stock or create a Model.")
		verify(view._harvest_result_text({"moved_timber": 1, "moved_raw": 0}) == "Collected 1 timber."
			and view._harvest_result_text({"moved_timber": 0, "moved_raw": 1}) == "Collected 1 copper piece."
			and view._harvest_result_text({"moved_timber": 0, "moved_raw": 0}) == "Cutting…",
			"The start receipt is not mislabeled as collected stock; contact reports actual moved quantities.")
		verify("depleted" in view._material_refusal_message({"reason": "unavailable_source"}, "fallback")
			and view._material_refusal_message({"reason": "inventory_full"}, "fallback") == "fallback",
			"Native stock advice remains, while the obsolete carried-cap advice is absent.")
		view.state.hand_sources.tree.remaining = 0
		var depleted_summary: Dictionary = view._pointed_summary_data(Vector2.ZERO)
		view._interact_pointed()
		verify(depleted_summary.get("detail") == "Depleted" and view.issued.is_empty(),
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
	root.size = Vector2i(1280, 800)
	for shared in [false, true]:
		var view = SharedWidgets.new() if shared else OfflineWidgets.new()
		if shared:
			view.session = SessionStub.new()
		view.state = hotbar_observation()
		view.state.part_kits.P.gearbox = 1
		view.state.foundations = {"floor": {"cell": [0, 0], "level": 0}}
		view.pointed = "floor"
		view.mode = "inspect"
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view._build_interface()
		view.building_hotbar.slots.assign(["collector", "foundation", "belt", "processor", "wheel", "gear", "drive", ""])
		view._refresh_ui()
		var before: Dictionary = view.state.duplicate(true)
		var bar = view.building_hotbar
		bar.open_catalog()
		await process_frame
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = KEY_8
		bar._input(event)
		verify(bar.slots[7].is_empty(), "A number alone does not create a hotbar target or assignment.")
		bar.catalog_buttons.gearbox.grab_focus()
		bar._input(event)
		verify(bar.slots[7] == "gearbox" and not bar.catalog.visible,
			"A focused carried placeable and number key bind that exact slot.")
		bar.open_catalog()
		event.keycode = KEY_H
		bar._input(event)
		verify(bar.slots[7] == "gearbox" and view.mode == "gearbox" and not bar.catalog.visible,
			"A catalog letter selects a carried mechanical part without changing its hotbar binding.")
		bar.open_catalog()
		bar.catalog_slots[7].grab_focus()
		event.keycode = KEY_DELETE
		bar._input(event)
		verify(bar.slots[7].is_empty() and view.mode == "inspect", "Delete clears the focused hotbar slot.")
		bar._close_catalog()
		event.keycode = KEY_D
		event.ctrl_pressed = true
		view._input(event)
		verify(not view.pause_menu.visible and not view.stock_label.is_visible_in_tree(),
			"Ctrl+D leaves the unobstructed game view unchanged.")
		view._open_pointed_machine()
		view._input(event)
		verify(view.object_menu.visible and view.inspector.is_visible_in_tree()
			and not view.stock_label.is_visible_in_tree(),
			"The selected-object panel keeps its inspection without a worksite submenu.")
		event.ctrl_pressed = false
		event.keycode = KEY_ESCAPE
		view._input(event)
		verify(not view.object_menu.visible, "Escape closes the object panel before opening the worksite menu.")
		await settle_widgets()
		view._input(event)
		verify(view.pause_menu.visible, "A later Escape opens the worksite menu after closing an object panel.")
		verify(view.stock_label.is_visible_in_tree(), "The Escape menu displays worksite stock.")
		verify(view.pause_resume_button.has_focus(), "The Escape menu focuses Resume.")
		verify(view.save_button.get_parent() == view.load_button.get_parent(),
			"Save and Reopen share the Escape menu action grid.")
		verify(view.save_button.accessibility_name == "Save worksite, shortcut F5"
			and view.load_button.accessibility_name == "Reopen save, shortcut F9",
			"The icon actions announce their keyboard shortcuts at focus.")
		view._input(event)
		verify(not view.pause_menu.visible, "Escape resumes from the worksite menu.")
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
			var pickup: Dictionary = Geometry.collector_intake_boxes({"kind": "collector",
				"cell": [0, 0], "level": 0}).boxes[0]
			var admitted := AABB(pickup.center - pickup.size * 0.5, pickup.size).grow(0.001)
			for part_name in ["SourcePickupHousing", "SourcePickupFloor",
					"SourcePickupCheekLeft", "SourcePickupCheekRight"]:
				var part := anchor.get_node_or_null(part_name) as MeshInstance3D
				verify(part != null and admitted.encloses(part.transform * part.mesh.get_aabb()),
					"The open pickup fits the native intake box for every selected outlet.")
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
		verify(view.mode == "inspect" and view.selected == "press" and view.object_menu.visible
			and view.inspector.is_visible_in_tree()
			and view.issued.is_empty() and view.request_sequence == sequence,
			"E opens the pointed press in its centered panel without an authority request.")
		key.keycode = KEY_ESCAPE
		view._input(key)
		verify(not view.object_menu.visible and view.selected.is_empty(),
			"Escape closes the object panel and releases its selected target.")
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
				and view.selected.is_empty(),
				"R in %s mode never retrieves from a closed object panel." % rotation[0])
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
		view._open_pointed_machine()
		key.ctrl_pressed = true
		view._input(key)
		verify(view.issued == [{"action": "retrieve", "amount": 1, "entity": "press"}] and view.state == before,
			"Ctrl+R in the press panel submits the existing collection action.")
		key.ctrl_pressed = false
		key.keycode = KEY_ESCAPE
		view._input(key)
		# A second physical press arrives after the menu's same-frame close guard.
		while Engine.get_process_frames() == view.object_menu_closed_frame:
			await process_frame
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
		view._input(key)
		verify(view.mode == "inspect" and not view.pause_menu.visible and view.issued.size() == 2
			and view.state.get("entities") == before.entities,
			"Escape cancels active construction without changing the confirmed worksite.")
		view.free()
	var crank_view := CrankInteractionView.new()
	crank_view.client = "P"
	crank_view.mode = "inspect"
	crank_view.state = _object_menu_snapshot()
	crank_view.state.crank_items = {"fitted-crank": {"attached_to": "shaft", "port": [0, 0, 0]}}
	root.add_child(crank_view)
	crank_view.camera = Camera3D.new()
	crank_view.add_child(crank_view.camera)
	var crank_pick := StaticBody3D.new()
	crank_pick.set_meta("crank_entity", "fitted-crank")
	crank_view.add_child(crank_pick)
	crank_view.hit_body = crank_pick
	verify(crank_view._pointed_summary_data(Vector2.ZERO).detail.contains("Hold E"),
		"A fitted world crank exposes its direct hold key before a machine panel opens.")
	crank_view._interact_pointed()
	verify(crank_view.issued == [{"action": "operate_hand_crank", "entity": "fitted-crank"}]
		and crank_view.held_crank == "fitted-crank",
		"Pointing at a fitted crank sends one native source pulse and starts its hold.")
	crank_view._advance_held_crank(crank_view.STEP_SECONDS)
	verify(crank_view.issued.size() == 2,
		"Continuing the hold sends a new bounded source pulse.")
	crank_view._stop_held_crank()
	crank_view._advance_held_crank(crank_view.STEP_SECONDS)
	verify(crank_view.issued.size() == 2,
		"Release leaves no stored source that can turn on another frame.")
	crank_view._interact_pointed()
	crank_view.allow_hold = false
	crank_view._advance_held_crank(crank_view.STEP_SECONDS)
	verify(crank_view.held_crank.is_empty() and crank_view.issued.size() == 3,
		"Loss of focus stops the ordinary hold without another source pulse.")
	crank_view.allow_hold = true
	crank_view._interact_pointed()
	crank_view.hit_body = null
	crank_view._advance_held_crank(crank_view.STEP_SECONDS)
	verify(crank_view.held_crank.is_empty() and crank_view.issued.size() == 4,
		"Leaving the fitted crank target stops the hold.")
	crank_view.hit_body = crank_pick
	crank_view.accept_pulse = false
	crank_view._interact_pointed()
	verify(crank_view.held_crank.is_empty() and crank_view.issued.size() == 5,
		"A native refusal stops the hold before another request.")
	crank_view.mode = "deconstruct"
	verify(crank_view._pointed_summary_data(Vector2.ZERO).detail.contains("Click  Detach"),
		"The deconstruction cue names the separate detach action.")
	crank_view._world_click(Vector2i.ZERO)
	verify(crank_view.issued.back() == {"action": "detach_hand_crank", "entity": "fitted-crank"},
		"Clicking the fitted crank with F selected asks native custody to detach that item.")
	crank_view.free()
	print("%d placement-interaction view checks" % checks)
	quit(1 if failures else 0)

func _shared_crank_hold_check() -> void:
	var session := CrankSessionStub.new()
	var view := SharedCrankInteractionView.new()
	view.session = session
	view.client = "P"
	view.mode = "inspect"
	view.state = _object_menu_snapshot()
	view.state.crank_items = {"fitted-crank": {"attached_to": "shaft", "port": [0, 0, 0]}}
	root.add_child(view)
	var pick := StaticBody3D.new()
	pick.set_meta("crank_entity", "fitted-crank")
	view.add_child(pick)
	view.hit_body = pick
	view._interact_pointed()
	var first_request := session.request_namespace + "1"
	verify(session.sent == [{"action": "operate_hand_crank", "entity": "fitted-crank"}]
		and view.pending_actions.has(first_request) and view.held_crank_request == first_request,
		"A queued shared crank pulse retains its unique request and live E hold without claiming acceptance.")
	view._advance_held_crank(view.STEP_SECONDS * 2.0)
	verify(session.sent.size() == 1 and view.held_crank == "fitted-crank",
		"Holding E cannot submit a second pulse while the first server decision is pending.")
	view._outcome_received({"request": first_request, "client": "P",
		"context": view.state.context, "revision": 2, "order": 0, "accepted": true})
	verify(view.pending_actions.has(first_request) and session.sent.size() == 1,
		"A server acceptance alone cannot release the hold barrier before its projected revision arrives.")
	view.state.revision = 2
	view._settle_pending()
	view._advance_held_crank(0.0)
	var second_request := session.request_namespace + "2"
	verify(session.sent.size() == 2 and view.pending_actions.has(second_request)
		and view.held_crank_request == second_request and first_request != second_request,
		"A fresh confirmed projection permits exactly one new native request during the same hold.")
	var release := InputEventKey.new()
	release.keycode = KEY_E
	release.pressed = false
	view._input(release)
	view._outcome_received({"request": second_request, "client": "P",
		"context": view.state.context, "revision": 2, "order": 0, "accepted": true})
	view._advance_held_crank(view.STEP_SECONDS)
	verify(view.held_crank.is_empty() and view.held_crank_request.is_empty()
		and session.sent.size() == 2 and view.pending_actions.is_empty(),
		"Releasing E prevents another pulse even when an earlier shared request later succeeds.")
	view._interact_pointed()
	var focus_request := session.request_namespace + "3"
	view.allow_hold = false
	view._advance_held_crank(view.STEP_SECONDS)
	view._outcome_received({"request": focus_request, "client": "P",
		"context": view.state.context, "revision": 2, "order": 0, "accepted": true})
	verify(view.held_crank.is_empty() and session.sent.size() == 3,
		"Focus loss stops a queued shared hold before the next pulse.")
	view.allow_hold = true
	view._interact_pointed()
	var target_request := session.request_namespace + "4"
	view.hit_body = null
	view._advance_held_crank(view.STEP_SECONDS)
	view.hit_body = pick
	view._outcome_received({"request": target_request, "client": "P",
		"context": view.state.context, "revision": 2, "order": 0, "accepted": true})
	verify(view.held_crank.is_empty() and session.sent.size() == 4,
		"Leaving the fitted crank target cancels repetition without canceling its already submitted request.")
	view._interact_pointed()
	var refusal_request := session.request_namespace + "5"
	view._outcome_received({"request": refusal_request, "client": "P",
		"context": view.state.context, "revision": 2, "order": 0,
		"accepted": false, "reason": "out_of_reach"})
	view._advance_held_crank(view.STEP_SECONDS)
	verify(view.held_crank.is_empty() and session.sent.size() == 5,
		"A confirmed native refusal stops the shared hold and does not mint a sixth request.")
	view._interact_pointed()
	view.state.context = "reopened-worksite"
	view._advance_held_crank(view.STEP_SECONDS)
	verify(view.held_crank.is_empty() and session.sent.size() == 6,
		"Reopening a different world context stops a queued hold even if the crank ID is reused.")
	view._disconnected("closed")
	view._welcomed("P", "reconnected-", view.state)
	view._advance_held_crank(view.STEP_SECONDS)
	verify(view.pending_actions.is_empty() and view.held_crank.is_empty()
		and session.sent.size() == 6,
		"Disconnect and reconnect never resume an uncertain crank request from the old binding.")
	view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"scope": "shared queued crank hold over invented confirmed projections", "desktop_operations": 0}))
	quit(0 if failures == 0 else 1)

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
		view.building_hotbar.slots.assign(["collector", "foundation", "belt", "processor", "wheel", "gear", "drive", ""])
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
		verify(bar.buttons.all(func(button: Button): return button.size == Vector2(54, 54) and button.text.is_empty())
			and bar.slot_icons.all(func(icon: TextureRect): return icon.size == Vector2(32, 32)),
			"The hotbar gives every part the same icon area and fixed slot size without face labels.")
		var bar_surface := bar.get_theme_stylebox("panel") as StyleBoxFlat
		var idle_alpha: float = (bar.buttons[0].get_theme_stylebox("normal") as StyleBoxFlat).bg_color.a
		verify(bar_surface.bg_color.a == 0.0 and bar_surface.border_width_left == 0
			and idle_alpha >= 0.55 and idle_alpha <= 0.8,
			"The hotbar has no framing border and its idle cells remain readable over scenery without hiding it.")
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
		bar.open_catalog()
		verify(bar.catalog.visible and bar.catalog_slots.size() == 8,
			"The inventory exposes eight numbered hotbar drop slots.")
		verify(not view._can_control_character() and not bar.catalog_buttons.processor.disabled,
			"The modal inventory holds movement while keeping carried parts available.")
		var processor_drag: Dictionary = bar._drag_payload("processor")
		verify(bar.catalog_slots[7]._can_drop_data(Vector2.ZERO, processor_drag),
			"A carried processor can be dragged to key 8 inside inventory.")
		bar.catalog_slots[7]._drop_data(Vector2.ZERO, processor_drag)
		verify(bar.slots[7] == "processor" and not bar.catalog.visible and view.mode == "belt",
			"Dropping a placeable binds the slot without selecting placement or changing custody.")
		bar.open_catalog()
		bar.catalog_buttons.processor.pressed.emit()
		verify(bar.slots[7] == "processor" and view.mode == "processor" and not bar.catalog.visible and view._can_control_character(),
			"Clicking a carried part selects placement without changing its binding.")
		bar.open_catalog()
		bar.catalog_buttons.collector.grab_focus()
		var rebind := InputEventKey.new()
		rebind.keycode = KEY_8
		rebind.pressed = true
		bar._input(rebind)
		verify(bar.slots[7] == "collector" and not bar.catalog.visible,
			"A focused carried item and number key replace an existing binding.")
		bar.select_slot(7)
		verify(view.mode == "collector" and bar.selected_slot == 7,
			"Numbered hotbar selection arms the newly bound tool.")
		bar.open_catalog()
		bar.clear_slot(7)
		verify(bar.slots[7].is_empty() and view.mode == "inspect", "Clearing the active slot returns to inspection.")
		bar._close_catalog()
		bar.select_slot(7)
		verify(not bar.catalog.visible and bar.slots[7].is_empty(),
			"An empty hotbar key does not open the old assignment flow.")
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
		verify(bar.slot_counts[0].text == "0" and view.mode == "inspect",
			"An exhausted kit cannot be selected without borrowing the compatibility stock alias.")
		bar.open_catalog()
		verify(not bar.catalog_slots[7]._can_drop_data(Vector2.ZERO,
			{"hotbar_owner": bar.get_instance_id(), "tool": "collector"}),
			"An exhausted carried item cannot be rebound by drag.")
		bar.catalog_buttons.collector.pressed.emit()
		verify(bar.slots[7].is_empty() and view.mode == "inspect", "An unavailable catalog item cannot activate or fill a slot.")
		view.client = "Q"
		view._refresh_ui()
		verify(bar.slot_counts[1].text == "2" and bar.buttons[0].modulate != Color.WHITE, "Every slot follows the active actor's own kit.")
		view.state.part_kits.erase("Q")
		view._refresh_ui()
		verify(bar.slot_counts[1].text == "0", "Missing actor kits have no fallback owner.")
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
			bar.open_catalog()
			bar.clear_slot(0)
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
			bar.open_catalog()
			await settle_widgets()
			verify(viewport.encloses(Rect2(Vector2(bar.catalog.position), Vector2(bar.catalog.size))), "The complete catalog fits the supported viewport.")
			verify(bar.catalog.size.y <= dimensions.y - 16,
				"The inventory window fits vertically and scrolls its item grid.")
			bar.catalog.hide()
		bar.open_catalog()
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

func _arrival_hotbar() -> void:
	var view := OfflineWidgets.new()
	view.client = "P"
	view.state = hotbar_observation()
	view.state.hand_sources = {}
	view.state.cargo = {"P": {"components": {}}, "Q": {"components": {"wooden_frame": 1}}}
	view.state.fabrication_hub = {"id": "pod-fabrication-hub", "installed": true}
	view.state.component_recipes = {
		"wooden_frame": {"timber": 3, "copper": 0},
		"wooden_shaft": {"timber": 1, "copper": 0, "load_rating": 8},
		"wooden_cog": {"timber": 1, "copper": 0, "load_rating": 8},
		"receiver_tray": {"timber": 2, "copper": 0},
		"tool_mount": {"timber": 2, "copper": 0},
		"cutting_edge": {"timber": 0, "copper": 1},
		"anvil": {"timber": 0, "copper": 2},
		"flat_head": {"timber": 0, "copper": 1},
		"ram_face": {"timber": 0, "copper": 2},
		"copper_cog": {"timber": 0, "copper": 2, "load_rating": 24},
		"wooden_slide": {"timber": 3, "copper": 0, "load_rating": 8},
		"hand_crank": {"timber": 2, "copper": 0},
		"copper_slide": {"timber": 0, "copper": 4, "load_rating": 24}}
	view.state.foundation_recipe = {"timber": 2, "copper": 0}
	view.state.part_recipes = [{"kind": "shaft", "timber": 1, "copper": 0,
		"teeth": 0, "half_span": 2}]
	view.state.component_capacity = 20
	view.state.first_plate_unlock = true
	view.state.placed_components = {}
	root.add_child(view)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	view._build_interface()
	view._refresh_ui()
	var bar = view.building_hotbar
	verify(bar.slots == bar.ARRIVAL_SLOTS and bar.slots.all(func(slot: String) -> bool: return slot.is_empty())
		and bar.slot_icons.all(func(icon: TextureRect) -> bool: return icon.texture == null),
		"Native arrival begins with eight empty assignable slots.")
	var component_icon_paths := {}
	for component: String in bar._component_names:
		var texture: Texture2D = bar.component_buttons[component].icon
		var icon_kind := "anvil" if component == "broad_anvil" else \
			"flat_head" if component == "broad_flat_head" else \
			"workshop-crank" if component == "hand_crank" else component
		verify(texture != null and texture.resource_path.ends_with("/" + icon_kind + ".svg"),
			"Each fabricated component uses its own named item icon in the inventory.")
		component_icon_paths[texture.resource_path] = true
	verify(component_icon_paths.size() == bar._component_names.size() - 2,
		"The two sized arrangements reuse the literal icons of their four carried parts.")
	verify(bar.buttons.size() == 8 and bar.buttons[0].accessibility_name.contains("Empty hotbar key 1"),
		"Each empty hotbar slot describes its number and drag assignment path.")
	var face_labels: Array[String] = []
	for child: Node in bar.buttons[0].get_children():
		if child is Label:
			face_labels.append(child.text)
	verify(face_labels == ["1", "+"], "An empty slot shows its number and assignment cue.")
	verify(not bar.catalog_buttons.collector.visible and not bar.catalog_buttons.processor.visible
		and bar.recipe_side.visible and bar.component_buttons.size() == view.arrival_assembly_controls.COMPONENTS.size(),
		"The arrival inventory hides historical machines and has icons for every fabricated component.")
	verify(bar.component_buttons.has("anvil") and bar.component_buttons.has("ram_face")
		and bar.component_buttons.anvil.disabled and bar.component_buttons.ram_face.disabled,
		"The catalog names anvil and ram face directly and disables parts absent from carried cargo.")
	verify(not bar.buttons[0].disabled and bar.slot_counts[0].text == "+"
		and not bar.component_buttons.wooden_frame.visible,
		"An empty slot remains assignable while an unowned part stays absent from the catalog.")
	verify(bar.recipe_buttons.has("component:anvil")
		and bar.recipe_buttons.has("component:flat_head")
		and bar.recipe_buttons.has("component:wooden_slide")
		and bar.recipe_buttons.has("component:hand_crank")
		and not bar.recipe_buttons.has("component:wooden_cog")
		and not bar.recipe_buttons.has("component:receiver_tray")
		and not bar.recipe_buttons.has("foundation"),
		"Before the first carried plate, the inventory exposes only the four required press recipes.")
	verify(not bar.collector_focus_button.visible and bar.recipe_tip_label.visible,
		"The post-plate project choices do not crowd the starter build view.")
	var initial: Dictionary = view.state.duplicate(true)
	view.state.cargo.P.components = {"wooden_frame": 2, "copper_cog": 1,
		"anvil": 1, "ram_face": 1, "hand_crank": 1}
	view._refresh_ui()
	verify(not bar.component_buttons.anvil.disabled and not bar.component_buttons.ram_face.disabled
		and bar.component_counts.anvil.text == "1"
		and "Anvil" in bar.component_buttons.anvil.tooltip_text,
		"The component icon shows its authoritative count and accessible name.")
	view.state.cargo.P.components.anvil = 4
	view.state.cargo.P.components.flat_head = 4
	view._refresh_ui()
	verify(bar.component_buttons.broad_anvil.visible and bar.component_buttons.broad_flat_head.visible
		and bar.component_counts.broad_anvil.text == "1"
		and bar.component_counts.broad_flat_head.text == "1"
		and bar.component_buttons.broad_anvil.tooltip_text.contains("four carried parts"),
		"Four owned parts of each kind expose one sized workbed and one fitted face.")
	view.state.cargo.P.components.anvil = 1
	view.state.cargo.P.components.erase("flat_head")
	view._refresh_ui()
	view.state.cargo.P.timber = 5
	view.state.cargo.P.raw = 3
	view.state.cargo.P.products = 1
	view.state.cargo.P.work_lots = [{"id": 7}]
	view.state.crank_items = {"crank-1": {"holder": "P", "attached_to": "", "port": []}}
	view.state.workshop_completed_actors = ["P"]
	view._refresh_ui()
	verify(bar.material_counts.timber.text == "5" and bar.material_counts.raw.text == "3"
		and bar.material_counts.products.text == "1" and bar.material_counts.work_lots.text == "1"
		and bar.component_counts.hand_crank.text == "1"
		and "5 carried" in bar.material_buttons.timber.accessibility_name,
		"Carried material icons read the active actor's confirmed cargo and hand tools.")
	verify(bar.material_buttons.raw.tooltip_text == "Copper · 3 carried"
		and bar.material_buttons.raw.accessibility_name == "Copper, 3 carried"
		and bar.material_buttons.products.tooltip_text == "Copper plate · 1 carried"
		and bar.material_buttons.work_lots.tooltip_text == "Copper workpiece · 1 carried"
		and bar.material_buttons.work_lots.icon.resource_path.ends_with("/workpiece.svg")
		and bar.material_buttons.raw.icon.resource_path.ends_with("/ore.svg")
		and bar.material_buttons.products.icon.resource_path.ends_with("/plate.svg"),
		"Copper stock, partial work and plate use literal item icons with matching pointer and focus names.")
	verify(bar.carried_label.text == "CARRIED" and bar.component_buttons.hand_crank.visible,
		"The inventory shows the crafted crank as carried component stock.")
	verify(not view.goal_label.text.contains("timber ·") and not view.goal_label.text.contains("ore blanks carried")
		and view.goal_label.text.contains("Open Work log [J]"),
		"The objective completes from the actor's plate while the inventory window owns counts: " + view.goal_label.text)
	verify(bar.collector_focus_button.visible and bar.recipe_focus == "collector"
		and bar.recipe_buttons["component:wooden_frame"].visible
		and bar.recipe_buttons["component:cutting_edge"].visible
		and bar.recipe_buttons["component:receiver_tray"].visible
		and bar.recipe_buttons["component:wooden_cog"].visible
		and bar.recipe_buttons["part:0"].visible
		and not bar.recipe_buttons["component:anvil"].visible
		and not bar.recipe_buttons.foundation.visible,
		"The post-plate Build view offers the collector kit while retaining full native availability.")
	bar.open_catalog()
	bar.all_focus_button.grab_focus()
	await settle_widgets()
	verify(bar.focus_description.text.contains("All parts")
		and bar.all_focus_button.accessibility_name == "All unlocked recipes",
		"Keyboard focus describes the way to every earned recipe.")
	bar.all_focus_button.pressed.emit()
	verify(bar.recipe_focus == "all" and bar.recipe_buttons["component:anvil"].visible
		and bar.recipe_buttons.foundation.visible,
		"All parts restores the complete earned recipe list without changing cargo.")
	bar.material_buttons.timber.grab_focus()
	await settle_widgets()
	verify("Timber · 5 carried" in bar.focus_description.text,
		"Keyboard focus exposes the same item and count as pointer hover.")
	verify(bar.recipe_buttons.has("component:wooden_frame")
		and "3 timber" in bar.recipe_buttons["component:wooden_frame"].tooltip_text
		and "Open a fabrication bench" in bar.recipe_buttons["component:cutting_edge"].tooltip_text,
		"The shared recipe grid shows field cost and names a bench for metal components.")
	bar.recipe_buttons["component:wooden_frame"].pressed.emit()
	verify(view.issued.size() == 1 and view.issued[0] == {
		"action": "field_craft", "component": "wooden_frame"},
		"The field recipe icon sends the exact native shaping command.")
	bar.open_at_bench("pod-fabrication-hub")
	bar.recipe_buttons["component:cutting_edge"].pressed.emit()
	bar.recipe_buttons.foundation.pressed.emit()
	bar.recipe_buttons["part:0"].pressed.emit()
	verify(view.issued.size() == 4
		and view.issued[1] == {"action": "craft_component", "entity": "pod-fabrication-hub", "component": "cutting_edge"}
		and view.issued[2] == {"action": "craft_foundation", "entity": "pod-fabrication-hub"}
		and view.issued[3] == {"action": "craft_part", "entity": "pod-fabrication-hub", "role": "shaft", "half_span": 2}
		and view.state.cargo.P.components.wooden_frame == 2,
		"E on a workshop exposes component, foundation and part icons without fixture-owned stock changes.")
	var context_key := InputEventKey.new()
	context_key.keycode = KEY_S
	context_key.pressed = true
	bar._input(context_key)
	verify(view.issued.size() == 5 and view.issued[4] == {
		"action": "stow_fabrication_hub", "entity": "pod-fabrication-hub"},
		"The bench inventory retains the pod stow action on its visible S shortcut.")
	view.state.fabrication_hub = {"id": "pod-fabrication-hub", "installed": false, "holder": "P"}
	bar.catalog.hide()
	bar.open_catalog()
	var hub_drag: Dictionary = bar._drag_payload("pod_workshop")
	verify(bar.catalog_slots[2]._can_drop_data(Vector2.ZERO, hub_drag),
		"A stowed pod workshop is a carried placeable hotbar source.")
	bar.catalog_slots[2]._drop_data(Vector2.ZERO, hub_drag)
	verify(bar.slots[2] == "pod_workshop" and bar.slot_icons[2].texture == bar.material_buttons.fabrication_hub.icon,
		"The pod workshop binds with its literal inventory icon.")
	await process_frame
	bar.open_catalog()
	context_key.keycode = KEY_P
	bar._input(context_key)
	verify(view.mode == "pod_workshop" and not bar.catalog.visible
		and bar.material_counts.fabrication_hub.text == "1",
		"A carried pod tile and its P shortcut select placement from the same inventory.")
	view.state.fabrication_hub = {"id": "pod-fabrication-hub", "installed": true}
	view._select_tool("inspect")
	view.issued.clear()
	bar.catalog.hide()
	view.state.cargo.P.timber = 2
	view.state.cargo.P.raw = 0
	view.state.cargo.P.components.anvil = 0
	view.state.cargo.P.components.hand_crank = 0
	view.state.crank_items["crank-1"] = {"holder": "", "attached_to": "slide", "port": [13, 2, 8]}
	view._refresh_ui()
	verify(bar.material_counts.timber.text == "2" and bar.material_counts.raw.text == "0"
		and bar.component_counts.hand_crank.text == "0" and bar.component_counts.anvil.text == "0"
		and not bar.material_buttons.raw.visible and not bar.component_buttons.anvil.visible,
		"Crafting and attachment refresh icon counts from the next confirmed projection.")
	verify(bar.carried_label.text == "CARRIED" and not bar.component_buttons.hand_crank.visible,
		"An attached crank no longer appears as carried stock.")
	view.state.crank_items["crank-1"].holder = "Q"
	view.state.crank_items["crank-1"].attached_to = ""
	view.state.crank_items["crank-1"].port = []
	view._refresh_ui()
	verify(bar.carried_label.text == "CARRIED" and not bar.component_buttons.hand_crank.visible,
		"A crank held by another worker does not appear in this actor's inventory.")
	view._refresh_ui()
	view.state.cargo.P.components.anvil = 1
	view._refresh_ui()
	bar.open_catalog()
	var frame_drag: Dictionary = bar._drag_payload("component:wooden_frame")
	verify(bar.catalog_slots[0]._can_drop_data(Vector2.ZERO, frame_drag),
		"A carried fabricated frame can be dragged to the first hotbar key.")
	bar.catalog_slots[0]._drop_data(Vector2.ZERO, frame_drag)
	verify(not bar.buttons[0].disabled and bar.slot_counts[0].text == "2",
		"A confirmed fabricated frame enables its quick slot with the active actor's count.")
	await process_frame
	bar.open_catalog()
	bar.inventory_scroll.ensure_control_visible(bar.component_buttons.wooden_frame)
	await process_frame
	var frame_center: Vector2 = bar.component_buttons.wooden_frame.get_global_rect().get_center()
	verify(bar.bind_number_key(5, frame_center) and bar.slots[5] == "component:wooden_frame",
		"Hovering a visible carried placeable and pressing key 6 binds that exact key.")
	verify(bar._drag_payload("raw").is_empty() and not bar.catalog_slots[2]._can_drop_data(
		Vector2.ZERO, {"hotbar_owner": bar.get_instance_id(), "tool": "raw"}),
		"Raw stock cannot masquerade as a placeable hotbar source.")
	bar._close_catalog()
	bar.select_slot(0)
	verify(view.mode == "component" and view.arrival_assembly_controls.selected_name() == "wooden_frame"
		and bar.selected_slot == 0 and view.issued.is_empty(),
		"A component quick slot changes the ordinary placement selection without issuing construction.")
	view.state.part_kits.P = {"foundation": 15}
	view._refresh_ui()
	bar.open_catalog()
	verify(bar.catalog_buttons.foundation.visible and not bar.catalog_buttons.belt.visible
		and not bar.catalog_buttons.wheel.visible,
		"The arrival catalog gives space to carried parts instead of unavailable machine cards.")
	var cog_index: int = bar._component_names.find("copper_cog")
	verify(cog_index >= 0 and bar.catalog.visible, "The catalog includes the stronger metal cog.")
	if cog_index >= 0:
		verify(not bar.component_buttons.copper_cog.disabled
			and bar.component_counts.copper_cog.text == "1",
			"The inventory reads the carried metal cog from native component cargo.")
		bar.component_buttons.copper_cog.grab_focus()
		var cog_key := InputEventKey.new()
		cog_key.keycode = KEY_8
		cog_key.pressed = true
		bar._input(cog_key)
		bar._close_catalog()
		bar.select_slot(7)
		verify(bar.slots[7] == "component:copper_cog" and view.mode == "component"
			and view.arrival_assembly_controls.selected_name() == "copper_cog"
			and bar.slot_icons[7].texture == bar.component_buttons.copper_cog.icon
			and view.issued.is_empty(),
			"Focused-item number binding selects the exact component through ordinary placement.")
	bar.open_catalog()
	var ram_drag: Dictionary = bar._drag_payload("component:ram_face")
	bar.catalog_slots[6]._drop_data(Vector2.ZERO, ram_drag)
	bar._close_catalog()
	bar.select_slot(6)
	verify(bar.slots[6] == "component:ram_face" and view.mode == "component"
		and view.arrival_assembly_controls.selected_name() == "ram_face" and view.issued.is_empty(),
		"Dragging a carried ram face binds and then selects its placement tool.")
	root.size = Vector2i(640, 480)
	await settle_widgets()
	bar.open_catalog()
	await settle_widgets()
	verify(bar.catalog.visible and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
		Rect2(Vector2(bar.catalog.position), Vector2(bar.catalog.size)))
		and bar.catalog.size.y <= 464,
		"The combined inventory stays inside the narrow viewport with a scrollable item grid.")
	bar._close_catalog()
	view.client = "Q"
	view._refresh_ui()
	verify(bar.slot_counts[0].text == "1" and bar.slot_counts[7].text == "0" and bar.buttons[7].modulate != Color.WHITE,
		"Switching actor changes component availability without borrowing the previous actor's cargo.")
	verify(bar.material_counts.timber.text == "0" and bar.component_counts.anvil.text == "0",
		"A new actor or restored projection cannot retain another actor's inventory counts.")
	view.state.cargo.Q.timber = 4
	view._refresh_ui()
	verify(bar.material_counts.timber.text == "4", "A restored actor projection refreshes the inventory icon count.")
	view.client = "P"
	bar.select_slot(7)
	view.state.cargo.P.components.copper_cog = 0
	view._refresh_ui()
	bar.select_slot(7)
	verify(bar.slot_counts[7].text == "0"
		and view.arrival_assembly_controls.selected_name() == "copper_cog"
		and view.issued.is_empty(),
		"An exhausted fabricated component cannot create a construction command.")
	verify(view.state.cargo.P.components.wooden_frame == 2 and initial.cargo.P.components.is_empty()
		and view.model == null and view.actor_world == null,
		"Hotbar interaction changes no component custody or simulation state.")
	view.state.cargo.P.components.wooden_slide = 1
	view.state.cargo.P.components.copper_slide = 1
	view.state.cargo.P.timber = 3
	view.state.cargo.P.raw = 4
	view._refresh_ui()
	bar._close_catalog()
	bar.open_catalog()
	var slide_key := InputEventKey.new()
	slide_key.keycode = KEY_8
	slide_key.pressed = true
	bar.component_buttons.wooden_slide.grab_focus()
	verify(bar.focus_description.text.contains("Wooden slide")
		and bar.component_buttons.wooden_slide.icon != bar.component_buttons.copper_slide.icon
		and bar.component_counts.wooden_slide.text == "1",
		"Each slide has a distinct focused icon with its actual carried count.")
	bar._input(slide_key)
	bar._close_catalog()
	bar.select_slot(7)
	verify(bar.slots[7] == "component:wooden_slide" and view.mode == "component"
		and view.arrival_assembly_controls.selected_name() == "wooden_slide",
		"A focused wooden slide and number bind its ordinary placement tool.")
	bar.open_catalog()
	bar.recipe_buttons["component:wooden_slide"].pressed.emit()
	verify(view.issued.back() == {"action": "field_craft", "component": "wooden_slide"},
		"The wooden slide recipe uses the existing finite field craft command.")
	bar.open_at_bench("pod-fabrication-hub")
	bar.recipe_buttons["component:copper_slide"].pressed.emit()
	verify(view.issued.back() == {"action": "craft_component", "entity": "pod-fabrication-hub",
		"component": "copper_slide"},
		"The metal slide recipe uses the existing bench and native custody path.")
	view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"failures": failures, "models": 0, "desktop_operations": 0,
		"scope": "native-arrival hotbar over invented projections"}))
	quit(0 if failures == 0 else 1)

func _carried_grid_state(bar) -> Dictionary:
	var items := 0
	var blanks := 0
	var last_item := -1
	var first_blank := -1
	for tile in bar.material_grid.get_children():
		if not tile.visible:
			continue
		if tile is Button:
			items += 1
			last_item = tile.get_index()
		elif bar.inventory_empty.has(tile):
			blanks += 1
			if first_blank < 0:
				first_blank = tile.get_index()
	return {"items": items, "blanks": blanks,
		"items_before_blanks": first_blank < 0 or last_item < first_blank}

func _render_arrival_hotbar() -> void:
	var prefix := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--arrival-hotbar-image-prefix="):
			prefix = argument.trim_prefix("--arrival-hotbar-image-prefix=")
	if prefix.is_empty() or DisplayServer.get_name().to_lower() == "headless":
		verify(false, "Arrival hotbar readback requires an output prefix and isolated rendered display.")
		quit(1)
		return
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)
	var view := OfflineWidgets.new()
	view.client = "P"
	view.state = hotbar_observation()
	view.state.hand_sources = {}
	view.state.first_plate_unlock = true
	view.state.workshop_completed_actors = ["P"]
	view.state.part_kits.P = {"foundation": 15}
	view.state.cargo = {"P": {"components": {"wooden_frame": 2, "wooden_shaft": 1,
		"tool_mount": 1, "receiver_tray": 1, "cutting_edge": 1, "copper_cog": 1,
		"wooden_slide": 1, "copper_slide": 1, "hand_crank": 1},
		"timber": 7, "raw": 3, "products": 1, "offcuts": 2, "sheets": 1,
		"work_lots": [{"id": 7}]}}
	view.state.crank_items = {"component-1": {"holder": "P", "attached_to": ""}}
	view.state.fabrication_hub = {"id": "pod-fabrication-hub", "installed": true}
	view.state.component_recipes = {
		"wooden_frame": {"timber": 3, "copper": 0},
		"wooden_shaft": {"timber": 1, "copper": 0, "load_rating": 8},
		"wooden_cog": {"timber": 1, "copper": 0, "load_rating": 8},
		"receiver_tray": {"timber": 2, "copper": 0},
		"tool_mount": {"timber": 2, "copper": 0},
		"cutting_edge": {"timber": 0, "copper": 1},
		"anvil": {"timber": 0, "copper": 2},
		"copper_cog": {"timber": 0, "copper": 2, "load_rating": 24},
		"wooden_slide": {"timber": 3, "copper": 0, "load_rating": 8},
		"hand_crank": {"timber": 2, "copper": 0},
		"copper_slide": {"timber": 0, "copper": 4, "load_rating": 24}}
	view.state.foundation_recipe = {"timber": 2, "copper": 0}
	view.state.part_recipes = [{"kind": "shaft", "timber": 1, "copper": 0,
		"teeth": 0, "half_span": 2}]
	view.state.component_capacity = 20
	view.state.placed_components = {}
	root.add_child(view)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	view._build_interface()
	view._refresh_ui()
	var bar = view.building_hotbar
	bar.open_catalog()
	var partial_grid := _carried_grid_state(bar)
	verify(partial_grid.items > 0 and partial_grid.items + partial_grid.blanks == 32
		and partial_grid.items_before_blanks,
		"Partly filled carried inventory has thirty-two cells with spare cells after owned items.")
	var render_slide_drag: Dictionary = bar._drag_payload("component:wooden_slide")
	bar.catalog_slots[7]._drop_data(Vector2.ZERO, render_slide_drag)
	bar._close_catalog()
	bar.select_slot(7)
	view._refresh_ui()
	await settle_widgets()
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-bar.png") == OK,
		"Retain the rendered arrival component hotbar.")
	bar.open_catalog()
	var inventory_scroll: ScrollContainer = bar.catalog.find_child("InventoryItems", true, false)
	inventory_scroll.ensure_control_visible(bar.component_buttons.copper_slide)
	await settle_widgets()
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-catalog.png") == OK,
		"Retain the rendered arrival component catalog.")
	verify(bar.recipe_buttons.has("component:wooden_frame") and
		bar.recipe_buttons.has("component:anvil") and bar.recipe_buttons.has("part:0"),
		"The item inventory presents field and bench recipes beside carried stock.")
	verify(bar.recipe_focus == "collector" and bar.recipe_buttons["component:wooden_frame"].visible
		and not bar.recipe_buttons["component:anvil"].visible,
		"The first post-plate catalog shows a collector-sized recipe group.")
	bar.all_focus_button.pressed.emit()
	await settle_widgets()
	verify(bar.recipe_buttons["component:anvil"].visible and bar.recipe_buttons.foundation.visible,
		"All parts reveals the full set of native-unlocked recipes.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-all-recipes.png") == OK,
		"Retain the full unlocked recipe view reached from the project group.")
	var stocked_cargo: Dictionary = view.state.cargo.P.duplicate(true)
	view.state.cargo.P = {"components": {}}
	view.state.crank_items.clear()
	view.state.part_kits.P = {}
	view._refresh_ui()
	await settle_widgets()
	var empty_grid := _carried_grid_state(bar)
	verify(bar.catalog.visible and bar.carried_label.text == "CARRIED"
		and not bar.material_buttons.timber.visible and not bar.component_buttons.wooden_frame.visible
		and bar.recipe_buttons["component:wooden_frame"].visible
		and empty_grid.items == 0 and empty_grid.blanks == 32,
		"Empty carried stock shows thirty-two blank cells beside the discoverable recipe.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-empty.png") == OK,
		"Retain the empty-inventory recipe catalog.")
	bar.inventory_scroll.scroll_vertical = 10000
	await settle_widgets()
	verify(bar.inventory_scroll.scroll_vertical > 0 and
		bar.inventory_scroll.get_global_rect().encloses(bar.inventory_empty.back().get_global_rect()),
		"The final empty cell remains reachable by scrolling the thirty-two-cell grid.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-empty-bottom.png") == OK,
		"Retain the lower empty inventory rows after scrolling.")
	view.state.cargo.P = stocked_cargo
	view.state.crank_items = {"component-1": {"holder": "P", "attached_to": ""}}
	view.state.part_kits.P = {"foundation": 15}
	view._refresh_ui()
	await settle_widgets()
	inventory_scroll.scroll_vertical = int(inventory_scroll.get_v_scroll_bar().max_value)
	await settle_widgets()
	verify(bar.component_buttons.wooden_frame.visible and bar.component_buttons.copper_cog.visible
		and inventory_scroll.get_v_scroll_bar() != null,
		"The restored cargo and scrollable inventory show named component icons.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-components.png") == OK,
		"Retain the visible component icon grid after scrolling.")
	root.size = Vector2i(900, 600)
	bar._close_catalog()
	await settle_widgets()
	bar.collector_focus_button.pressed.emit()
	bar.open_catalog()
	await settle_widgets()
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-project-narrow.png") == OK,
		"Retain the project recipe group in a narrow actor viewport.")
	root.size = Vector2i(640, 480)
	bar._close_catalog()
	await settle_widgets()
	bar.all_focus_button.pressed.emit()
	bar.open_catalog()
	await settle_widgets()
	var catalog_surface: StyleBoxFlat = bar.catalog.get_theme_stylebox("panel", "PopupPanel") as StyleBoxFlat
	verify(bar.catalog.position.x == 0 and bar.catalog.size.x == root.size.x
		and catalog_surface.bg_color.a == 1.0,
		"The narrow inventory covers the HUD edge and blocks underlying text from showing through.")
	verify(bar.catalog.visible and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
		Rect2(Vector2(bar.catalog.position), Vector2(bar.catalog.size))),
		"The rendered inventory fits the narrow viewport.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-narrow-catalog.png") == OK,
		"Retain the rendered narrow inventory window.")
	bar.recipe_scroll.scroll_vertical = 10000
	await settle_widgets()
	verify(bar.recipe_scroll.scroll_vertical > 0
		and bar.recipe_scroll.get_v_scroll_bar().max_value > bar.recipe_scroll.size.y,
		"The advanced recipe grid remains scrollable in the narrow inventory.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-narrow-recipes-bottom.png") == OK,
		"Retain the lower named recipe rows in the narrow inventory.")
	bar._close_catalog()
	root.size = Vector2i(1280, 800)
	await settle_widgets()
	for component: String in bar._component_names:
		view.state.cargo.P.components[component] = 1
	view.state.part_kits.P = {"foundation": 1, "belt": 1, "wheel": 1,
		"gear": 1, "shaft": 1, "gearbox": 1, "vertical_gearbox": 1, "chain_drive": 1}
	view._refresh_ui()
	bar.open_catalog()
	await settle_widgets()
	var full_grid := _carried_grid_state(bar)
	verify(full_grid.items > 32 and full_grid.blanks == 0,
		"Every supported carried kind remains listed when owned items exceed thirty-two cells.")
	bar.inventory_scroll.scroll_vertical = 0
	await settle_widgets()
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-full-catalog.png") == OK,
		"Retain the large carried inventory at normal width.")
	bar._close_catalog()
	root.size = Vector2i(560, 480)
	await settle_widgets()
	bar.open_catalog()
	await settle_widgets()
	bar.component_buttons.channel_broad_z.grab_focus()
	await settle_widgets()
	var focused_tile: Button = bar.component_buttons.channel_broad_z
	verify(bar.catalog.visible and bar.material_grid.columns == 3
		and bar.catalog.gui_get_focus_owner() == focused_tile
		and bar.inventory_scroll.get_global_rect().encloses(focused_tile.get_global_rect()),
		"A late carried item remains keyboard reachable and scrolls into the narrow inventory.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-full-narrow-catalog.png") == OK,
		"Retain the focused late carried item in the narrow inventory.")
	view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"failures": failures, "models": 0, "desktop_operations": 0,
		"scope": "isolated rendered arrival hotbar over invented cargo"}))
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
	bar.open_catalog()
	await settle_widgets()
	verify(not view.inspector.get_parent().get_parent().visible,
		"Opening the fresh catalog does not expose an unused machine inspector.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-catalog.png") == OK, "Retain the isolated assignment catalog.")
	bar.catalog.hide()
	view.state.entities = {"press": {"kind": "processor", "cell": [2, 1]}}
	view.selected = "press"
	view._refresh_ui()
	await settle_widgets()
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-inspection.png") == OK,
		"Retain the compact selected-machine inspector in the same isolated view.")
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
		view.state.motion = {"collector": {"state": "rotating", "numerator": -1},
			"belt": {"state": "rotating", "numerator": -1},
			"press": {"state": "rotating", "numerator": -1}}
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
				var form: String = "carried copper" if lots.is_empty() else "carried copper workpiece"
				verify(view.goal_label.text.contains(form) and view.goal_label.text.contains("press")
					and not view.goal_label.text.contains("No copper"),
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
			verify(view.goal_label.text.contains("No copper") and not view.recovery_actions.visible,
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
		view.state.motion.collector.state = "stopped"
		view._refresh_ui()
		verify(view.goal_label.text.contains("Use cogs and shafts"),
			"Stopped native motion takes priority over carried-material reinsertion advice.")
		view.state.power_enabled = true
		view.state.motion.collector.state = "rotating"
		view.state.options.native = false
		view._refresh_ui()
		verify(view.goal_label.text.contains("No copper"), "Historical guidance ignores native carried-material fields.")
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

func _shared_component_results() -> void:
	var cases := [
		{"action": "craft_component", "accepted": true, "reason": "", "text": "Component crafted from carried material."},
		{"action": "field_craft", "accepted": true, "reason": "", "text": "Wooden component shaped with your multitool."},
		{"action": "place_component", "accepted": true, "reason": "", "text": "Component placed on the shared grid."},
		{"action": "reclaim_component", "accepted": true, "reason": "", "text": "Component returned to your carried cargo."},
		{"action": "craft_component", "accepted": false, "reason": "unavailable_input", "text": "Gather the timber or copper shown for this component."},
		{"action": "craft_component", "accepted": false, "reason": "out_of_reach", "text": "Move beside the selected workshop to craft this component."},
		{"action": "field_craft", "accepted": false, "reason": "unavailable_input", "text": "Gather the timber shown for this component."},
		{"action": "field_craft", "accepted": false, "reason": "unavailable_recipe", "text": "Metal components need a workshop."},
		{"action": "craft_part", "accepted": false, "reason": "out_of_reach", "text": "Move beside the selected workshop to make a transmission kit."},
		{"action": "load_belt_slot", "accepted": false, "reason": "belt_cannot_carry", "text": "This belt is too narrow for broad work. Carry it to the next machine."},
		{"action": "load_belt_slot", "accepted": false, "reason": "belt_path_cannot_carry", "text": "This belt transmits rotation but cannot carry items along this path."}]
	for sample: Dictionary in cases:
		var view := SharedSettlementView.new()
		view.session = SessionStub.new()
		view.client = "P"
		view.state = fixture()
		view.state.context = "shared-component-results"
		view.state.revision = 4
		view.state.order = 9
		view.state.options = {"native": true, "physical": true}
		var before: Dictionary = view.state.duplicate(true)
		var result := {"accepted": sample.accepted, "reason": sample.reason,
			"context": view.state.context, "revision": 4, "order": 9}
		view.pending_actions = {"P-1": {"action": {"action": sample.action, "component": "wooden_shaft"}, "outcome": result}}
		view._settle_pending()
		verify(view.observed == sample.text and view.observed_refusal == not sample.accepted,
			"Shared %s %s receives its exact confirmed component feedback." % [sample.action, sample.reason])
		verify(view.pending_actions.is_empty() and view.state == before and view.model == null,
			"Settling shared component feedback consumes only the confirmed request, not native stock.")
		view.free()
	var width_view := Opening.new()
	width_view.state = fixture()
	width_view.state.options = {"native": true, "physical": true}
	verify(width_view._material_refusal_message({"reason": "belt_cannot_carry", "uncertain": true},
		"uncertain outcome", "load_belt_slot") == "uncertain outcome"
		and width_view._material_refusal_message({"reason": "belt_cannot_carry"},
			"other action", "place_component") == "other action",
		"A width explanation never turns uncertain delivery or another action into a belt refusal.")
	width_view.free()
	for sample: Dictionary in [
		{"status": "missing_ram", "text": "No working face contacts this support."},
		{"status": "missing_guide", "text": "The working face has no guided stroke."},
		{"status": "missing_cog", "text": "No rotary input reaches this working face."},
		{"status": "", "text": "No compatible working face acts on this support."},
	]:
		var press_view := SharedSettlementView.new()
		press_view.session = SessionStub.new()
		press_view.client = "P"
		press_view.state = fixture()
		press_view.state.context = "shared-press-refusal"
		press_view.state.revision = 4
		press_view.state.order = 9
		press_view.state.options = {"native": true, "physical": true}
		press_view.state.guided_press_assemblies = [] if sample.status.is_empty() else [
			{"anvil": "press-anvil", "status": sample.status}]
		var before_press: Dictionary = press_view.state.duplicate(true)
		press_view.pending_actions = {"P-press": {"action": {"action": "feed_press", "entity": "press-anvil"},
			"outcome": {"accepted": false, "reason": "incomplete_assembly", "entity": "press-anvil",
			"context": press_view.state.context, "revision": 4, "order": 9}}}
		press_view._settle_pending()
		verify(press_view.observed == sample.text and press_view.observed_refusal
			and press_view.state == before_press and press_view.pending_actions.is_empty(),
			"A shared refused press operation explains the projected local contact state without changing work.")
		var local_view := Opening.new()
		local_view.state = press_view.state.duplicate(true)
		verify(local_view._material_refusal_message(
			{"reason": "incomplete_assembly", "entity": "press-anvil"}, "fallback", "feed_press") == sample.text,
			"A local refused press operation uses the same projected contact explanation.")
		verify(local_view._material_refusal_message(
			{"reason": "incomplete_assembly", "entity": "press-anvil"}, "fallback", "place_component") == "fallback",
			"Other incomplete actions do not receive press contact feedback.")
		local_view.free()
		press_view.free()
	var collector_view := SharedSettlementView.new()
	collector_view.session = SessionStub.new()
	collector_view.client = "P"
	collector_view.state = fixture()
	collector_view.state.context = "shared-collector-refusal"
	collector_view.state.revision = 4
	collector_view.state.order = 9
	collector_view.state.options = {"native": true, "physical": true}
	collector_view.pending_actions = {"P-collector": {"action": {"action": "turn_hand_crank", "entity": "shaft"},
		"outcome": {"accepted": false, "reason": "incomplete_assembly", "entity": "shaft",
		"context": collector_view.state.context, "revision": 4, "order": 9}}}
	collector_view._settle_pending()
	verify(collector_view.observed == "Fit the collector's missing component before cutting ore."
		and collector_view.observed_refusal,
		"The collector retains its own native incomplete-assembly refusal.")
	collector_view.free()
	var waiting := SharedSettlementView.new()
	waiting.session = SessionStub.new()
	waiting.client = "P"
	waiting.state = fixture()
	waiting.state.context = "shared-component-results"
	waiting.state.revision = 4
	waiting.state.order = 9
	waiting.state.options = {"native": true, "physical": true}
	waiting.pending_actions = {"P-2": {"action": {"action": "craft_component"},
		"outcome": {"accepted": true, "reason": "", "context": waiting.state.context, "revision": 5, "order": 10}}}
	waiting._settle_pending()
	verify(waiting.pending_actions.has("P-2") and waiting.observed.contains("Waiting for the current worksite"),
		"An outcome newer than the shared snapshot stays pending without claiming a crafted component.")
	waiting.state.revision = 5
	waiting.state.order = 10
	waiting._settle_pending()
	verify(waiting.pending_actions.is_empty() and waiting.observed == "Component crafted from carried material.",
		"Shared craft feedback appears only after the confirming snapshot catches up.")
	waiting.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"models": 0, "desktop_operations": 0, "scope": "confirmed shared component feedback"}))
	quit(0 if failures == 0 else 1)

func _workshop_pages() -> void:
	root.size = Vector2i(1280, 800)
	root.gui_embed_subwindows = true
	var image_prefix := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--workshop-pages-image-prefix="):
			image_prefix = argument.trim_prefix("--workshop-pages-image-prefix=")
	for shared in [false, true]:
		var view = SharedWorkshopWidgets.new() if shared else OfflineWorkshopWidgets.new()
		if shared:
			view.session = SessionStub.new()
			view.client = "Q"
		view.state = fixture()
		view.state.merge({"context": "workshop-pages", "revision": 1, "order": 1})
		view.state.options.native = true
		view.state.hand_sources = {}
		view.state.stock = {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0}
		view.state.cargo = {"P": {"raw": 1, "timber": 3, "components": {}},
			"Q": {"raw": 1, "timber": 3, "components": {}}}
		view.state.component_recipes = {"wooden_frame": {"timber": 3, "copper": 0}}
		view.state.first_plate_unlock = false
		view.state.foundation_recipe = {"timber": 2, "copper": 0}
		view.state.part_recipes = [
			{"kind": "gearbox", "timber": 2, "copper": 1, "half_span": 0, "teeth": 0},
			{"kind": "vertical_gearbox", "timber": 2, "copper": 1, "half_span": 0, "teeth": 0},
			{"kind": "chain_drive", "timber": 2, "copper": 1, "half_span": 0, "teeth": 0}]
		view.state.component_capacity = 20
		view.state.workshop_completed_actors = []
		view.state.fabrication_hub = {"id": "pod-fabrication-hub", "installed": true}
		view.state.fabrication_benches = [{"id": "field-bench", "center": [4, 0, 4]}]
		view.state.placed_components = {"field-bench": {"component": "wooden_workbench", "center": [4, 0, 4]},
			"press-anvil": {"component": "anvil", "center": [8, 0, 8]},
			"press-ram": {"component": "ram_face", "center": [8, 1, 8]},
			"press-shaft": {"component": "wooden_shaft", "center": [9, 4, 8],
				"input_ports": [[9, 4, 8]]},
			"collector-mount": {"component": "tool_mount", "center": [-1, 0, 0],
				"input_ports": [[-1, 0, 0]]},
			"collector-frame": {"component": "wooden_frame", "center": [0, 0, 0]}}
		view.state.guided_press_assemblies = [{"anvil": "press-anvil", "center": [8, 0, 8],
			"work_center": [8, 0, 8], "status": "ready", "parts": {"ram": "press-ram", "shaft": "press-shaft"},
			"open_feeds": [{"entry": [9, 0, 8], "exit": [7, 0, 8]}]}]
		view.state.collector_assemblies = [{"status": "ready", "center": [0, 0, 0],
			"parts": {"frame": "collector-frame", "mount": "collector-mount", "shaft": "collector-shaft"}}]
		view.state.crank_items = {"crank": {"holder": "", "attached_to": "press-shaft",
			"port": [9, 4, 8]}}
		var before: Dictionary = view.state.duplicate(true)
		view.camera = Camera3D.new()
		view.add_child(view.camera)
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view._build_interface()
		view._refresh_ui()
		var panel = view.arrival_assembly_controls
		var inventory = view.building_hotbar
		verify(inventory.carried_label.text == "CARRIED"
			and view._crank_turn_refusal("press").contains("Fit a crafted hand crank"),
			"The workshop points to a crafted fitted crank without presenting pod custody.")
		await process_frame
		await process_frame
		verify(not view.object_menu.visible and not panel.is_visible_in_tree()
			and not inventory.catalog.visible and not panel.press_section.visible,
			"A fresh opening leaves workshop controls off the game view.")
		var escape := InputEventKey.new()
		escape.pressed = true
		escape.keycode = KEY_ESCAPE
		view._input(escape)
		verify(view.pause_menu.visible and view.pause_menu_scrim.visible
			and view.save_button.get_parent() == view.pause_resume_button.get_parent()
			and view.load_button.get_parent() == view.pause_resume_button.get_parent()
			and view.save_button.text.is_empty() and view.load_button.text.is_empty(),
			"Idle Escape opens icon-led worksite actions outside the object panel.")
		await process_frame
		var resume_rect: Rect2 = view.pause_resume_button.get_global_rect()
		for frame_index in range(31 if not shared and not image_prefix.is_empty() else 4):
			await process_frame
			verify(view.pause_menu.visible and view.pause_resume_button.has_focus()
				and view.pause_resume_button.get_global_rect() == resume_rect,
				"The open Resume control keeps its focus and layout across idle frames.")
			if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless" \
					and frame_index in [0, 10, 20, 30]:
				await RenderingServer.frame_post_draw
				verify(root.get_texture().get_image().save_png(image_prefix + "-escape-%02d.png" % frame_index) == OK,
					"Retain a timed worksite menu frame.")
		view.save_button.grab_focus()
		await process_frame
		verify(view.save_button.has_focus() and not view.pause_resume_button.has_focus()
			and view.pause_menu.visible,
			"Keyboard focus can leave Resume without dismissing the worksite menu.")
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-escape-save-focus.png") == OK,
				"Retain the worksite menu with focus on Save.")
		view.pause_resume_button.grab_focus()
		verify(view.pause_resume_button.has_focus() and view.pause_menu.visible,
			"Keyboard focus returns to Resume without rebuilding the menu.")
		view._input(escape)
		verify(not view.pause_menu.visible and not view.pause_menu_scrim.visible,
			"Escape resumes the worksite from the pause menu.")
		view._open_pause_menu()
		root.size = Vector2i(900, 600)
		await process_frame
		await process_frame
		verify(view.pause_menu.visible and view.pause_menu_scrim.visible
			and view.pause_resume_button.has_focus()
			and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(view.pause_menu.get_global_rect()),
			"A repeated Escape menu opening stays centered and focused during a window resize.")
		view.pause_resume_button.pressed.emit()
		verify(not view.pause_menu.visible and not view.pause_menu_scrim.visible,
			"The Resume icon closes the worksite menu after resizing.")
		root.size = Vector2i(1280, 800)
		await process_frame
		if failures > 0:
			view.free()
			break
		view.pointed = "pod-fabrication-hub"
		view._open_pointed_machine()
		verify(inventory.catalog.visible and inventory.context_bench == view.pointed
			and not view.object_menu.visible and inventory.recipe_buttons["component:wooden_frame"].visible
			and not view.save_button.is_visible_in_tree() and not view.load_button.is_visible_in_tree(),
			"Ordinary E shows pod crafting directly in the shared inventory.")
		verify(inventory.recipe_buttons["foundation"].visible
			and "2 timber + 0 copper" in inventory.recipe_buttons["foundation"].tooltip_text,
			"The foundation recipe keeps its native name and cost beside the icon.")
		verify("Horizontal gearbox" in inventory.recipe_buttons["part:0"].tooltip_text
			and "Vertical gearbox" in inventory.recipe_buttons["part:1"].tooltip_text
			and inventory.recipe_buttons["part:0"].icon.resource_path.ends_with("/gearbox.svg")
			and inventory.recipe_buttons["part:1"].icon.resource_path.ends_with("/vertical_gearbox.svg"),
			"The ordinary workshop shows each relay recipe by its own name and icon.")
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-foundation-label.png") == OK,
				"Retain the visible foundation label in the ordinary workshop panel.")
		root.size = Vector2i(640, 480)
		view._fit_object_menu(Vector2i(640, 480))
		await process_frame
		inventory._configure_catalog_layout(Vector2i(640, 480))
		inventory._place_catalog()
		var popup_rect := Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size))
		verify(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(popup_rect)
			and not inventory.recipe_scroll.get_h_scroll_bar().visible,
			"The foundation recipe and cost fit inside the narrow inventory window.")
		root.size = Vector2i(1280, 800)
		inventory._configure_catalog_layout(Vector2i(1280, 800))
		inventory._input(escape)
		verify(not inventory.catalog.visible and not view.pause_menu.visible,
			"Escape closes inventory without opening the worksite menu underneath it.")
		view._input(escape)
		verify(view.pause_menu.visible, "The next idle Escape opens worksite actions.")
		view.pause_exit_button.pressed.emit()
		verify(view.pause_exit_confirmation.visible, "Exit asks before discarding unsaved work.")
		view._input(escape)
		verify(not view.pause_exit_confirmation.visible and view.pause_menu.visible,
			"Escape dismisses exit confirmation and leaves worksite actions open.")
		view.pause_menu.hide()
		await process_frame
		view._open_pointed_machine()
		verify(inventory.catalog.visible and inventory.context_bench == "pod-fabrication-hub",
			"Ordinary E reopens the same workshop recipes.")
		inventory.catalog.hide()
		await process_frame
		view.pointed = "field-bench"
		view._open_pointed_machine()
		verify(inventory.catalog.visible and inventory.context_bench == "field-bench"
			and inventory.context_action.visible and "Reclaim wooden workbench" in inventory.context_action.tooltip_text
			and not view.object_menu.visible,
			"The built workbench shows its recipes and one reclaim icon without pod controls.")
		inventory.catalog.hide()
		await process_frame
		view.pointed = "press-anvil"
		view._open_pointed_machine()
		verify(view.object_menu.visible and panel.press_section.is_visible_in_tree() and not panel.collector_section.visible
			and panel.feed_button.is_visible_in_tree() and not panel.feed_button.disabled,
			"Ordinary E on a confirmed press exposes its existing feed controls.")
		var press_icons := [panel.feed_button, panel.refeed_work_button, panel.turn_button,
			panel.compact_button, panel.pickup_button, panel.recover_work_button]
		var icons_described := true
		for button: Button in press_icons:
			icons_described = icons_described and button.text.is_empty() and button.icon != null \
				and not button.tooltip_text.is_empty() and not button.accessibility_name.is_empty() \
				and button.focus_mode == Control.FOCUS_ALL
		verify(icons_described, "Press actions use focusable icons with an action description and shortcut.")
		verify(panel.feed_button.tooltip_text.contains("F") and panel.turn_button.tooltip_text.contains("T")
			and panel.pickup_button.tooltip_text.contains("P")
			and panel.recover_work_button.tooltip_text.contains("U"),
			"Press action tooltips retain their keyboard routes.")
		view.state.crank_items.crank = {"holder": view.client, "attached_to": "", "port": []}
		panel.refresh(view.state, view.client, view.selected, true)
		verify(panel.turn_button.disabled and panel.turn_button.tooltip_text.contains("Fit a crafted crank"),
			"A carried crank must be fitted before the press offers a turn.")
		view.state.crank_items.crank = {"holder": "", "attached_to": "press-shaft", "port": [9, 4, 8]}
		panel.refresh(view.state, view.client, view.selected, true)
		panel.feed_button.pressed.emit()
		verify(view.issued == [{"action": "feed_press", "entity": "press-anvil", "entry": [9, 0, 8]}],
			"The pointer feed icon sends the selected anvil and route to the native adapter.")
		view.issued.clear()
		for offset in [[4, 0, 0], [0, 0, 4], [4, 0, 4]]:
			var center := [8 + offset[0], offset[1], 8 + offset[2]]
			view.state.placed_components["broad-anvil-%s" % str(offset)] = {
				"component": "anvil", "center": center}
		view.state.broad_press_assemblies = [{"origin": [8, 0, 8], "geometry_status": "ready",
			"parts": {"anvils": ["press-anvil", "broad-anvil-a", "broad-anvil-b", "broad-anvil-c"]}}]
		view.state.cargo[view.client].raw = 3
		panel.refresh(view.state, view.client, view.selected, true)
		verify(panel.inventory_section.is_visible_in_tree() and panel._inventory_broad
			and not panel.feed_button.visible and panel.inventory_counts.player_raw.text == "3"
			and panel.inventory_workbed_heading.text.contains("2×2 WORKBED")
			and not panel.inventory_slots.has("workbed_target")
			and not panel.inventory_slots.has("player_target")
			and panel.inventory_player_region.destination == "player"
			and panel.inventory_workbed_region.destination == "workbed"
			and panel.inventory_slots.player_raw.tooltip_text.contains("three"),
			"A complete four-anvil press offers actual carried stock and whole-row drop regions without target glyphs.")
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-broad-workbed.png") == OK,
				"Retain the four-anvil inventory transfer in the selected anvil panel.")
			root.size = Vector2i(900, 600)
			await process_frame
			await process_frame
			verify(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(Rect2(
				Vector2(view.object_menu.position), Vector2(view.object_menu.size)))
				and panel.inventory_section.is_visible_in_tree(),
				"The broad workbed transfer remains inside a narrow ordinary window.")
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-broad-workbed-narrow.png") == OK,
				"Retain the broad workbed grid in a narrow ordinary window.")
			root.size = Vector2i(1280, 800)
			await process_frame
		var broad_blanks: Dictionary = panel.inventory_drag("player_raw")
		verify(broad_blanks.get("wire", {}) == {"action": "feed_broad_press", "entity": "press-anvil"}
			and broad_blanks.get("actor") == view.client
			and panel.inventory_can_drop("workbed", broad_blanks),
			"Three carried blanks target the native broad workbed through the same inventory drag contract.")
		if shared:
			view.client = "P"
			panel.refresh(view.state, view.client, view.selected, true)
			verify(not panel.inventory_workbed_region._can_drop_data(Vector2.ZERO, broad_blanks)
				and view.state.cargo.P.raw == 1 and view.state.cargo.Q.raw == 3,
				"A second actor cannot complete the first actor's carried-material drag.")
			view.client = "Q"
			panel.refresh(view.state, view.client, view.selected, true)
			view.pending_actions = {"waiting": {}}
			verify(not panel.inventory_workbed_region._can_drop_data(Vector2.ZERO, broad_blanks),
				"A pending shared action blocks a repeated material transfer.")
			view.pending_actions.clear()
			panel.refresh(view.state, view.client, view.selected, true)
		verify(panel.inventory_workbed_region._can_drop_data(Vector2.ZERO, broad_blanks),
			"The original ready actor can resume its exact material transfer.")
		view.state.context = "different-saved-worksite"
		panel.refresh(view.state, view.client, view.selected, true)
		verify(not panel.inventory_workbed_region._can_drop_data(Vector2.ZERO, broad_blanks),
			"A drag from another saved worksite context cannot transfer material.")
		view.state.context = "workshop-pages"
		panel.refresh(view.state, view.client, view.selected, true)
		panel.inventory_drop("workbed", broad_blanks)
		verify(view.issued == [broad_blanks.wire],
			"Dragging three blanks submits one native broad feed without changing local cargo.")
		view.issued.clear()
		var broad_feed_key := InputEventKey.new()
		broad_feed_key.keycode = KEY_F
		broad_feed_key.pressed = true
		view._input(broad_feed_key)
		verify(view.issued == [broad_blanks.wire],
			"F transfers the same three blanks through the ordinary selected-anvil keyboard route.")
		view.issued.clear()
		view.state.cargo[view.client].raw = 2
		panel.refresh(view.state, view.client, view.selected, true)
		view._input(broad_feed_key)
		verify(view.issued.is_empty() and panel.inventory_drag("player_raw").is_empty()
			and panel.inventory_slots.player_raw.disabled,
			"Fewer than three carried blanks disable the workbed transfer without issuing a native command.")
		view.state.cargo[view.client].raw = 3
		view.state.dropped_material = [{"center": [8, 0, 8], "raw": 0, "products": 0,
			"offcuts": 0, "sheets": 0, "sheet_items": [], "work_lots": [
				{"id": 81, "recipe_input": 3, "output_form": "sheet", "remaining": 2}]}]
		panel.refresh(view.state, view.client, view.selected, true)
		var broad_work: Dictionary = panel.inventory_drag("workbed_work")
		verify(panel.inventory_counts.workbed_work.text == "1"
			and panel.inventory_slots.workbed_work.icon.resource_path.ends_with("/sheet.svg")
			and panel.inventory_slots.workbed_work.tooltip_text.contains("sheet work")
			and broad_work.get("wire", {}).get("action") == "pickup_material"
			and broad_work.wire.center == [8, 0, 8]
			and panel.inventory_drag("player_raw").is_empty(),
			"A retained broad lot occupies the four-anvil workbed and blocks another feed.")
		view.state.dropped_material = [{"center": [8, 0, 8], "raw": 0, "products": 0,
			"offcuts": 0, "sheets": 1, "sheet_items": [{"id": 82, "rotation": 0}], "work_lots": []}]
		panel.refresh(view.state, view.client, view.selected, true)
		var broad_sheet: Dictionary = panel.inventory_drag("workbed_output")
		verify(panel.inventory_counts.workbed_output.text == "1"
			and panel.inventory_slots.workbed_output.icon.resource_path.ends_with("/sheet.svg")
			and panel.inventory_slots.workbed_work.icon == null
			and panel.inventory_counts.workbed_work.text.is_empty()
			and broad_sheet.get("wire", {}).get("action") == "pickup_material"
			and broad_sheet.wire.center == [8, 0, 8]
			and panel.inventory_drag("workbed_work").is_empty()
			and panel.inventory_player_region._can_drop_data(Vector2.ZERO, broad_sheet),
			"The formed sheet has a literal output tile and can drop onto the whole carried region.")
		var sheet_preview := TextureRect.new()
		sheet_preview.texture = panel.inventory_slots.workbed_output.icon
		panel.inventory_slots.workbed_output.force_drag(broad_sheet, sheet_preview)
		await process_frame
		verify(root.gui_is_dragging() and panel.inventory_player_region.highlighted
			and not panel.inventory_workbed_region.highlighted
			and sheet_preview.texture.resource_path.ends_with("/" + BuildingHotbar.MATERIALS.sheets[1]),
			"Dragging a supported output highlights the entire carried-inventory region.")
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-broad-output-drag.png") == OK,
				"Retain the highlighted carried region during a broad output drag.")
		var drag_escape := InputEventKey.new()
		drag_escape.keycode = KEY_ESCAPE
		drag_escape.pressed = true
		Input.parse_input_event(drag_escape)
		await process_frame
		verify(not root.gui_is_dragging() and not view.pause_menu.visible and view.issued.is_empty(),
			"One ordinary Escape ends the focused output drag without opening pause or issuing a command.")
		drag_escape.pressed = false
		Input.parse_input_event(drag_escape)
		await process_frame
		verify(not view.object_menu.visible and not root.gui_is_dragging()
			and not view.pause_menu.visible and view.issued.is_empty(),
			"The focused popup closes on drag Escape release without opening pause or changing custody.")
		if root.gui_is_dragging():
			root.gui_cancel_drag()
		await process_frame
		verify(not panel.inventory_player_region.highlighted,
			"The carried-inventory highlight clears when the drag ends.")
		view._open_object_menu_for("press-anvil")
		await process_frame
		verify(view.object_menu.visible and panel.inventory_section.is_visible_in_tree(),
			"The same workbed reopens after the focused drag is canceled.")
		panel.inventory_player_region._drop_data(Vector2(250, 50), broad_sheet)
		verify(view.issued == [broad_sheet.wire],
			"Dropping a sheet on ordinary empty space in the carried region sends one native pickup.")
		view.issued.clear()
		view.state.order += 1
		panel.refresh(view.state, view.client, view.selected, true)
		verify(not panel.inventory_player_region._can_drop_data(Vector2.ZERO, broad_sheet),
			"A stale output drag cannot transfer after the native order changes.")
		view.state.order -= 1
		panel.refresh(view.state, view.client, view.selected, true)
		var broad_pickup_key := InputEventKey.new()
		broad_pickup_key.keycode = KEY_P
		broad_pickup_key.pressed = true
		view._input(broad_pickup_key)
		verify(view.issued == [broad_sheet.wire],
			"P picks up the confirmed broad sheet through the same workbed inventory path.")
		view.issued.clear()
		view.state.dropped_material.clear()
		view.state.cargo[view.client].work_lots = [
			{"id": 7, "recipe_input": 1, "remaining": 1},
			{"id": 41, "recipe_input": 3, "output_form": "sheet", "remaining": 2}]
		panel.refresh(view.state, view.client, view.selected, true)
		var broad_work_input: Dictionary = panel.inventory_drag("player_broad_work:41")
		verify(panel.broad_refeed_button.is_visible_in_tree() and not panel.broad_refeed_button.disabled
			and panel.broad_refeed_button.text.is_empty() and panel.broad_refeed_button.icon != null
			and panel.broad_refeed_button.icon.resource_path.ends_with("/broad-refeed.svg")
			and panel.broad_refeed_button.tooltip_text.contains("N")
			and not panel.broad_refeed_button.accessibility_name.is_empty()
			and panel._held_work_ids == [7]
			and panel.inventory_slots.has("player_broad_work:41")
			and not panel.inventory_slots.has("player_work")
			and broad_work_input.get("wire", {}) == {"action": "refeed_broad_press_work",
				"entity": "press-anvil", "work_id": 41}
			and panel.inventory_workbed_region._can_drop_data(Vector2.ZERO, broad_work_input),
			"The broad workbed lists only its supported carried lot with exact identity and transfer.")
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-broad-refeed.png") == OK,
				"Retain the distinct broad-work refeed icon in the selected anvil panel.")
		var broad_refeed_key := InputEventKey.new()
		broad_refeed_key.keycode = KEY_N
		broad_refeed_key.pressed = true
		view._input(broad_refeed_key)
		verify(panel.broad_refeed_button.get_popup().item_count == 1,
			"N lists only identity-bearing carried sheet work.")
		panel.broad_refeed_button.get_popup().id_pressed.emit(0)
		panel.broad_refeed_button.get_popup().hide()
		verify(view.issued == [{"action": "refeed_broad_press_work", "entity": "press-anvil", "work_id": 41}],
			"The selected broad lot reenters native authority with its exact ID and first anvil.")
		view.issued.clear()
		view.state.cargo[view.client].work_lots.remove_at(1)
		panel.broad_refeed_button.get_popup().id_pressed.emit(0)
		panel.refresh(view.state, view.client, view.selected, true)
		verify(view.issued.is_empty() and not panel.broad_refeed_button.visible,
			"A stale broad-work choice cannot reinsert a lot the actor no longer carries.")
		verify(not panel.inventory_slots.has("player_broad_work:41")
			and not panel.inventory_workbed_region._can_drop_data(Vector2.ZERO, broad_work_input),
			"The carried broad-work tile vanishes when custody changes, and stale drags are refused.")
		view.state.cargo[view.client].work_lots.clear()
		view.state.cargo[view.client].raw = 1
		view.state.broad_press_assemblies = [{"origin": [8, 0, 8], "geometry_status": "missing_ram"}]
		panel.refresh(view.state, view.client, view.selected, true)
		verify(not panel.inventory_section.visible,
			"The four-anvil workbed transfer disappears when the native broad press is incomplete.")
		view.state.cargo[view.client].sheets = 1
		view.state.cargo[view.client].sheet_items = [{"id": 37, "rotation": 0}]
		panel.refresh(view.state, view.client, view.selected, true)
		verify(panel.sheet_button.is_visible_in_tree() and not panel.sheet_button.disabled
			and panel.sheet_button.text.is_empty() and panel.sheet_button.icon != null
			and panel.sheet_button.tooltip_text.contains("S")
			and not panel.sheet_button.accessibility_name.is_empty(),
			"A carried broad sheet exposes one described staging icon on its selected anvil.")
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-sheet-stage.png") == OK,
				"Retain the selected anvil panel with its sheet staging icon.")
		var sheet_key := InputEventKey.new()
		sheet_key.keycode = KEY_S
		sheet_key.pressed = true
		view._input(sheet_key)
		verify(panel.sheet_button.get_popup().item_count == 1,
			"The S shortcut opens the exact projected sheet and four-anvil origin.")
		panel.sheet_button.get_popup().id_pressed.emit(0)
		panel.sheet_button.get_popup().hide()
		verify(view.issued == [{"action": "place_sheet", "center": [8, 0, 8], "sheet_id": 37}],
			"Staging submits the native sheet identity and full-area origin without changing local cargo.")
		view.issued.clear()
		view.state.cargo[view.client].sheet_items.clear()
		panel.sheet_button.get_popup().id_pressed.emit(0)
		panel.refresh(view.state, view.client, view.selected, true)
		verify(view.issued.is_empty() and not panel.sheet_button.visible,
			"A stale staging choice cannot submit a sheet the actor no longer carries.")
		view.state.broad_shear_assemblies = [{"origin": [8, 0, 8], "status": "ready",
			"parts": {"anvils": ["press-anvil", "broad-anvil-a", "broad-anvil-b", "broad-anvil-c"]},
			"sheet_id": 37, "strokes": 0}]
		panel.refresh(view.state, view.client, view.selected, true)
		verify(panel.shear_button.is_visible_in_tree() and not panel.shear_button.disabled
			and panel.shear_button.text.is_empty() and panel.shear_button.icon != null
			and panel.shear_button.tooltip_text.contains("X")
			and not panel.shear_button.accessibility_name.is_empty(),
			"A staged native sheet exposes one focused cutting icon on its selected anvil.")
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-sheet-shear.png") == OK,
				"Retain the selected anvil panel with a staged sheet-cutting icon.")
		var shear_key := InputEventKey.new()
		shear_key.keycode = KEY_X
		shear_key.pressed = true
		view._input(shear_key)
		verify(view.issued == [{"action": "stroke_broad_shear", "entity": "press-anvil", "sheet_id": 37}],
			"X sends the first native shear anvil and staged sheet identity.")
		verify(view._material_refusal_message({"reason": "output_full"}, "unavailable", "stroke_broad_shear")
			.contains("Clear the other anvil squares")
			and view._material_refusal_message({"reason": "shear_unpowered"}, "unavailable", "stroke_broad_shear")
			.contains("Drive the cutting head forward"),
			"Native blocked-output and wrong-drive refusals point to the physical correction.")
		view.issued.clear()
		view.state.broad_shear_assemblies[0].status = "unpowered"
		panel.refresh(view.state, view.client, view.selected, true)
		view._input(shear_key)
		verify(view.issued.is_empty() and panel.shear_button.disabled,
			"An unpowered cutting head exposes its state without issuing a stroke.")
		view.state.erase("broad_shear_assemblies")
		panel.refresh(view.state, view.client, view.selected, true)
		verify(not panel.shear_button.visible,
			"Cutting controls disappear after the staged sheet leaves native projection.")
		view.state.placed_components["sized-bed"] = {"component": "broad_anvil", "center": [16, 0, 8]}
		view.state.broad_press_assemblies = [{"origin": [16, 0, 8], "geometry_status": "ready",
			"status": "unpowered", "parts": {"anvils": ["sized-bed"],
				"heads": ["sized-head"], "slide": "sized-slide"}}]
		view.state.cargo[view.client].raw = 3
		view.selected = "sized-bed"
		panel.refresh(view.state, view.client, view.selected, true)
		panel.open_context()
		verify(panel.press_section.visible and panel._inventory_broad
			and panel.inventory_workbed_heading.text.contains("2×2 WORKBED")
			and panel.inventory_drag("player_raw").get("wire", {}) == {
				"action": "feed_broad_press", "entity": "sized-bed"},
			"The selected sized workbed offers one ordinary three-stock transfer on its own native ID.")
		view.selected = "press-anvil"
		view.state.placed_components.erase("sized-bed")
		view.state.erase("broad_press_assemblies")
		view.state.cargo[view.client].erase("sheet_items")
		view.state.cargo[view.client].erase("sheets")
		panel.refresh(view.state, view.client, view.selected, true)
		panel.open_context()
		var action_key := InputEventKey.new()
		action_key.pressed = true
		action_key.keycode = KEY_F
		view._input(action_key)
		verify(view.issued == [{"action": "feed_press", "entity": "press-anvil", "entry": [9, 0, 8]}],
			"F in the press panel uses its visible feed button and existing request payload.")
		view.issued.clear()
		if not shared:
			view.state.dropped_material = [{"center": [8, 0, 8], "work_id": 1}]
			panel.refresh(view.state, view.client, view.selected, true)
			var turn_payload := {"action": "turn_press_crank", "entity": "press-anvil",
				"drive": "press-shaft", "exit": [7, 0, 8]}
			verify(not panel.turn_button.disabled and "Hold T" in panel.turn_button.tooltip_text,
				"Retained work enables the described held crank action.")
			panel.turn_button.button_down.emit()
			panel.turn_button.pressed.emit()
			await create_timer(0.40).timeout
			verify(view.issued.size() >= 2 and view.issued.all(func(action: Variant) -> bool:
				return action == turn_payload),
				"Holding the pointer sends repeated exact native turn requests after one immediate turn.")
			panel.turn_button.button_up.emit()
			var pointer_turn_count: int = view.issued.size()
			await create_timer(0.40).timeout
			verify(view.issued.size() == pointer_turn_count and panel.turn_hold_source.is_empty(),
				"Pointer release stops the crank without a trailing request.")
			view.issued.clear()
			var turn_key := InputEventKey.new()
			turn_key.keycode = KEY_T
			turn_key.pressed = true
			view._input(turn_key)
			turn_key.echo = true
			view._input(turn_key)
			verify(view.issued == [turn_payload],
				"T starts with one exact turn and ignores keyboard auto-repeat.")
			await create_timer(0.40).timeout
			verify(view.issued.size() >= 2 and view.issued.all(func(action: Variant) -> bool:
				return action == turn_payload),
				"Holding T advances retained work through the same native payload.")
			turn_key.echo = false
			turn_key.pressed = false
			view._input(turn_key)
			var key_turn_count: int = view.issued.size()
			await create_timer(0.40).timeout
			verify(view.issued.size() == key_turn_count and panel.turn_hold_source.is_empty(),
				"T release stops the crank without a trailing request.")
			view.issued.clear()
			view.accept_press_turn = false
			panel.turn_button.button_down.emit()
			panel.turn_button.pressed.emit()
			verify(view.issued == [turn_payload] and panel.turn_hold_source.is_empty()
				and panel.turn_repeat_timer.is_stopped(),
				"A refused first pointer turn cancels its hold immediately.")
			await create_timer(0.40).timeout
			verify(view.issued == [turn_payload],
				"A refused pointer turn never sends a second native request.")
			panel.turn_button.button_up.emit()
			view.issued.clear()
			turn_key.pressed = true
			view._input(turn_key)
			verify(view.issued == [turn_payload] and panel.turn_hold_source.is_empty()
				and panel.turn_repeat_timer.is_stopped(),
				"A refused first T turn cancels its hold immediately.")
			await create_timer(0.40).timeout
			verify(view.issued == [turn_payload],
				"A refused T turn never sends a second native request.")
			turn_key.pressed = false
			view._input(turn_key)
			view.accept_press_turn = true
			view.issued.clear()
			panel.turn_button.button_down.emit()
			panel.turn_button.pressed.emit()
			panel.turn_button.focus_exited.emit()
			verify(panel.turn_hold_source.is_empty() and panel.turn_repeat_timer.is_stopped(),
				"Leaving the turn control cancels a pointer hold.")
			view.issued.clear()
			view.state.dropped_material = [{"center": [8, 0, 8], "offcuts": 1}]
			panel.refresh(view.state, view.client, view.selected, true)
			verify(panel.turn_button.disabled and "Pick up the copper offcut" in panel.turn_button.tooltip_text,
				"A retained offcut blocks held turns until it is recovered.")
			view.state.erase("dropped_material")
			panel.refresh(view.state, view.client, view.selected, true)
		panel.refresh(view.state, view.client, view.selected, false)
		verify(panel.press_section.is_visible_in_tree() and panel.feed_button.disabled
			and panel.feed_button.tooltip_text.contains("Wait for the character")
			and panel.reclaim_button.disabled
			and panel.reclaim_button.tooltip_text.contains("Wait for the character"),
			"An unready actor cannot feed the press even while its panel is open.")
		view.issued.clear()
		var unready_delete := InputEventKey.new()
		unready_delete.keycode = KEY_DELETE
		unready_delete.pressed = true
		view._input(unready_delete)
		verify(view.issued.is_empty(),
			"Delete cannot reclaim a selected placed part while its icon is disabled.")
		panel.refresh(view.state, view.client, view.selected, true)
		view.object_menu.hide()
		await process_frame
		verify(view.selected.is_empty() and not view.object_menu.visible,
			"Leaving the press panel releases its selected target for another interaction.")
		view.pointed = "press-ram"
		view._open_pointed_machine()
		verify(view.object_menu.visible and view.object_menu_target == "press-ram"
			and view.object_menu_operations.is_visible_in_tree()
			and view.object_menu_operations_label.text == "PRESS WORK"
			and panel.press_section.is_visible_in_tree() and panel.feed_button.is_visible_in_tree(),
			"Ordinary E on a guided ram exposes the same press actions as its anvil.")
		verify(panel.reclaim_button.is_visible_in_tree() and not view.remove_button.visible
			and "Delete" in panel.reclaim_button.tooltip_text
			and "shortcut Delete" in panel.reclaim_button.accessibility_name
			and panel.reclaim_row.get_parent() == view.inspector.get_parent()
			and not view.inspector.text.contains("Reclaim with Delete"),
			"The guided ram keeps one described reclaim icon in its detail column without standing shortcut text.")
		await process_frame
		var detail_bounds: Rect2 = view.object_menu_detail_panel.get_global_rect()
		var reclaim_bounds: Rect2 = panel.reclaim_button.get_global_rect()
		verify(reclaim_bounds.position.x >= detail_bounds.position.x
			and reclaim_bounds.end.x <= detail_bounds.end.x
			and reclaim_bounds.end.y <= detail_bounds.end.y
			and reclaim_bounds.end.y >= detail_bounds.end.y - 28.0,
			"The reclaim icon sits at the bottom left of the ordinary component details.")
		var reclaim_key := InputEventKey.new()
		reclaim_key.keycode = KEY_DELETE
		reclaim_key.pressed = true
		view._input(reclaim_key)
		verify(view.issued == [{"action": "reclaim_component", "entity": "press-ram"}],
			"Delete reaches the same native reclaim payload when the old Remove button is hidden.")
		view.issued.clear()
		panel.reclaim_button.pressed.emit()
		verify(view.issued == [{"action": "reclaim_component", "entity": "press-ram"}],
			"Pressing the relocated icon uses the same native reclaim payload as Delete.")
		view.issued.clear()
		root.size = Vector2i(640, 480)
		view._fit_object_menu(Vector2i(640, 480))
		await process_frame
		var narrow_actions: Rect2 = view.object_menu_operations.get_global_rect()
		var narrow_details: Rect2 = view.object_menu_detail_panel.get_global_rect()
		var narrow_reclaim: Rect2 = panel.reclaim_button.get_global_rect()
		verify(panel.feed_button.get_global_rect().position.x >= narrow_actions.position.x
			and panel.compact_button.get_global_rect().end.x <= narrow_actions.end.x,
			"Both grouped press action rows fit inside the narrow object panel.")
		verify(narrow_reclaim.position.x >= narrow_details.position.x
			and narrow_reclaim.end.x <= narrow_details.end.x
			and narrow_reclaim.end.y <= narrow_details.end.y
			and narrow_reclaim.end.y >= narrow_details.end.y - 28.0,
			"The reclaim icon remains at the bottom left of the narrow component panel.")
		if not image_prefix.is_empty() and not shared and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var narrow_frame: Image = root.get_texture().get_image().get_region(Rect2i(0, 0, 640, 480))
			verify(narrow_frame.get_size() == Vector2i(640, 480)
				and narrow_frame.save_png(image_prefix + "-guided-ram-menu-narrow.png") == OK,
				"Retain the press panel fitted to a 640 by 480 view as a passive frame crop.")
		root.size = Vector2i(1280, 800)
		view._fit_object_menu(Vector2i(1280, 800))
		await process_frame
		if not image_prefix.is_empty() and not shared and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-guided-ram-menu.png") == OK,
				"Retain the passive guided ram action panel.")
		if not shared:
			view.state.dropped_material = [{"center": [8, 0, 8], "work_id": 2}]
			panel.refresh(view.state, view.client, view.selected, true)
			panel.turn_button.button_down.emit()
			panel.turn_button.pressed.emit()
		view.object_menu.hide()
		await process_frame
		if not shared:
			verify(panel.turn_hold_source.is_empty() and panel.turn_repeat_timer.is_stopped(),
				"Closing the object menu cancels a held crank before another request.")
			view.issued.clear()
			view.state.erase("dropped_material")
		verify(not panel.press_section.is_visible_in_tree(),
			"Closing a press panel removes its actions from the game view.")
		view.state.crank_items.crank = {"holder": "", "attached_to": "collector-mount", "port": [-1, 0, 0]}
		view.pointed = "collector-frame"
		view._open_pointed_machine()
		verify(view.object_menu.visible and panel.collector_section.is_visible_in_tree()
			and not panel.press_section.visible
			and panel.collector_cut_button.is_visible_in_tree(),
			"Ordinary E on a collector shows its cutting controls without unrelated crafting.")
		verify(panel.collector_cut_button.text.is_empty() and panel.collector_cut_button.icon != null
			and "Cut one copper piece" in panel.collector_cut_button.tooltip_text
			and "shortcut X" in panel.collector_cut_button.accessibility_name,
			"The collector exposes a described cutting icon when a crank is fitted.")
		view.state.crank_items.crank = {"holder": "P" if shared else "Q", "attached_to": "", "port": []}
		panel.refresh(view.state, view.client, view.selected, true)
		verify(panel.collector_cut_button.disabled
			and panel.collector_cut_button.tooltip_text.contains("Fit a crafted crank"),
			"A carried crank cannot cut until fitted to the collector mount.")
		view.state.crank_items.crank = {"holder": "", "attached_to": "collector-mount", "port": [-1, 0, 0]}
		panel.refresh(view.state, view.client, view.selected, true)
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-collector.png") == OK,
			"Retain the ordinary collector menu with its cutting icon.")
		action_key.keycode = KEY_X
		view._input(action_key)
		verify(view.issued == [{"action": "turn_hand_crank", "entity": "collector-mount"}],
			"X in the collector panel uses its visible cut button and existing request payload.")
		view.issued.clear()
		action_key.keycode = KEY_T
		view._input(action_key)
		verify(view.issued.is_empty(),
			"T in the collector panel cannot issue a removed pod custody command.")
		view.issued.clear()
		view.object_menu.hide()
		await process_frame
		view.state.guided_press_assemblies = [{"anvil": "press-anvil", "center": [8, 0, 8],
			"status": "missing_ram", "parts": {}, "open_feeds": []}]
		view.state.placed_components.erase("press-ram")
		view._refresh_ui()
		view.pointed = "press-anvil"
		view._open_pointed_machine()
		verify(view.object_menu.visible and panel.press_section.is_visible_in_tree()
			and view.object_menu_operations_label.text == "PART ACTIONS"
			and view.object_menu_desired_extent == Vector2i(620, 280)
			and not view.inspector.text.contains("press route")
			and panel.press_status.text == "Anvil · work support"
			and panel.reclaim_button.is_visible_in_tree()
			and not panel.feed_actions.is_visible_in_tree()
			and not panel.output_actions.is_visible_in_tree(),
			"A standalone anvil shows its work support and reclaim without an unfinished press checklist.")
		action_key.keycode = KEY_F
		view._input(action_key)
		action_key.keycode = KEY_T
		view._input(action_key)
		verify(view.issued.is_empty(),
			"Hidden press actions do not send feed or turn commands from keyboard shortcuts.")
		view.state.guided_press_assemblies.clear()
		view._refresh_ui()
		verify(panel.press_section.is_visible_in_tree()
			and panel.press_status.text == "Anvil · work support"
			and not panel.feed_actions.is_visible_in_tree(),
			"A bare anvil remains inspectable without any projected press assembly.")
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-standalone-anvil.png") == OK,
				"Retain the passive standalone work-support panel.")
		view.object_menu.hide()
		view.arrival_assembly_controls.select_component_name("anvil")
		view._select_tool("component")
		view.building_hotbar.refresh()
		view.building_hotbar.catalog.hide()
		verify(view.building_hotbar.footprint_button.visible
			and view.building_hotbar.footprint_catalog_button.visible
			and view.building_hotbar.footprint_button.tooltip_text.contains("1x1"),
			"Local and shared build controls expose an icon-led anvil footprint choice.")
		var footprint_key := InputEventKey.new()
		footprint_key.pressed = true
		footprint_key.keycode = KEY_V
		view._input(footprint_key)
		verify(view.arrival_assembly_controls.selected_name() == "broad_anvil"
			and view.building_hotbar.footprint_button.tooltip_text.contains("one click")
			and view.building_hotbar.footprint_button.tooltip_text.contains("four carried anvils"),
			"V selects one joined workbed identity and shows its four-part cost.")
		view.building_hotbar.open_catalog()
		view.building_hotbar._input(footprint_key)
		verify(view.arrival_assembly_controls.selected_name() == "anvil"
			and view.building_hotbar.footprint_catalog_button.icon ==
				view.building_hotbar.FOOTPRINT_ONE_ICON,
			"The same V shortcut returns to the small workbed while the build catalog is open.")
		view.arrival_assembly_controls.select_component_name("flat_head")
		view._select_tool("component")
		view.building_hotbar._input(footprint_key)
		verify(view.arrival_assembly_controls.selected_name() == "broad_flat_head"
			and view.building_hotbar.footprint_button.tooltip_text.contains("four carried flat heads"),
			"V selects the matching one-piece broad head with its four-part cost.")
		view.building_hotbar.catalog.hide()
		view._input(footprint_key)
		verify(view.arrival_assembly_controls.selected_name() == "flat_head",
			"V returns the flat head to its small size.")
		view.building_hotbar.catalog.hide()
		view._select_tool("inspect")
		view.state = before.duplicate(true)
		view._refresh_ui()
		verify(view.state == before and view.issued.is_empty() and view.model == null,
			"Workshop disclosure changes only local presentation, with no request or native state mutation.")
		view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"models": 0, "desktop_operations": 0, "scope": "offline/shared workshop disclosure and ordinary E callbacks over invented projections"}))
	quit(0 if failures == 0 else 1)

func _field_craft_widget() -> void:
	var capture_prefix := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--inventory-resize-capture-prefix="):
			capture_prefix = argument.trim_prefix("--inventory-resize-capture-prefix=")
	var view := OfflineWidgets.new()
	view.state = fixture()
	view.state.options.native = true
	view.state.hand_sources = {}
	view.state.first_plate_unlock = true
	view.state.workshop_completed_actors = ["P"]
	view.state.cargo = {"P": {"raw": 1, "timber": 3, "components": {}},
		"Q": {"raw": 0, "timber": 0, "components": {}}}
	view.state.component_recipes = {"wooden_frame": {"timber": 3, "copper": 0},
		"cutting_edge": {"timber": 0, "copper": 1},
		"flat_head": {"timber": 0, "copper": 1},
		"wooden_shaft": {"timber": 1, "copper": 0, "load_rating": 8},
		"copper_shaft": {"timber": 0, "copper": 2, "load_rating": 24}}
	view.state.foundation_recipe = {"timber": 2, "copper": 0}
	view.state.fabrication_hub = {"id": "pod-fabrication-hub", "installed": true}
	root.add_child(view)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	view._build_interface()
	var inventory = view.building_hotbar
	inventory.open_catalog()
	verify(inventory.recipe_focus == "collector"
		and inventory.recipe_buttons["component:wooden_frame"].visible
		and not inventory.recipe_buttons["component:flat_head"].visible,
		"Post-plate Build opens on a small next project instead of every advanced part.")
	inventory.all_focus_button.pressed.emit()
	var frame: Button = inventory.recipe_buttons["component:wooden_frame"]
	var edge: Button = inventory.recipe_buttons["component:cutting_edge"]
	var head: Button = inventory.recipe_buttons["component:flat_head"]
	var foundation: Button = inventory.recipe_buttons["foundation"]
	verify(inventory.catalog.visible and frame.visible and edge.visible and head.visible and foundation.visible
		and frame.icon != null and edge.icon != null and head.icon != null and foundation.icon != null
		and "3 timber + 0 copper" in frame.tooltip_text and "Field or bench" in frame.tooltip_text
		and "Bench" in edge.tooltip_text and "Flat pressing head" in head.tooltip_text
		and "1 copper" in head.tooltip_text and "2 timber + 0 copper" in foundation.tooltip_text,
		"The shared inventory shows described field and bench recipes with native bills.")
	frame.grab_focus()
	verify(inventory.focus_description.text == frame.tooltip_text and not frame.accessibility_name.is_empty(),
		"Recipe focus and hover expose the same cost and action description.")
	frame.pressed.emit()
	verify(view.issued == [{"action": "field_craft", "component": "wooden_frame"}],
		"A field recipe submits an actor-bound native shape action without a forged bench.")
	view.issued.clear()
	edge.pressed.emit()
	verify(view.issued.is_empty() and "Open a fabrication bench" in inventory.focus_description.text,
		"A metal recipe explains its bench requirement in the field.")
	inventory.catalog.hide()
	inventory.open_at_bench("pod-fabrication-hub")
	edge.pressed.emit()
	verify(view.issued == [{"action": "craft_component", "entity": "pod-fabrication-hub", "component": "cutting_edge"}],
		"The same recipe uses the selected native pod identity at a bench.")
	view.issued.clear()
	head.pressed.emit()
	verify(view.issued == [{"action": "craft_component", "entity": "pod-fabrication-hub",
		"component": "flat_head"}],
		"The separate head icon crafts one native bench component, without a hidden press recipe.")
	view.issued.clear()
	foundation.pressed.emit()
	verify(view.issued == [{"action": "craft_foundation", "entity": "pod-fabrication-hub"}],
		"The foundation recipe sends one native bench craft action.")
	view.issued.clear()
	view.state.cargo.P.timber = 1
	inventory.refresh()
	foundation.pressed.emit()
	verify(view.issued.is_empty() and "Carry the ingredients" in inventory.focus_description.text,
		"Missing timber keeps the foundation recipe visible without sending a command.")
	view.state.cargo.P.timber = 3
	view.state.part_recipes = [
		{"kind": "belt", "timber": 2, "copper": 1, "half_span": 0, "teeth": 0},
		{"kind": "gearbox", "timber": 2, "copper": 1, "half_span": 0, "teeth": 0},
		{"kind": "vertical_gearbox", "timber": 2, "copper": 1, "half_span": 0, "teeth": 0},
		{"kind": "chain_drive", "timber": 2, "copper": 1, "half_span": 0, "teeth": 0}]
	view.state.part_specifications = {"P": [{"kind": "belt", "teeth": 0, "half_span": 0, "count": 1}]}
	inventory.refresh()
	var belt_recipe: Button = inventory.recipe_buttons["part:0"]
	verify("2 timber + 1 copper" in belt_recipe.tooltip_text and belt_recipe.icon != null
		and "rated for 8 load" in inventory.recipe_buttons["component:wooden_shaft"].tooltip_text
		and "rated for 24 load" in inventory.recipe_buttons["component:copper_shaft"].tooltip_text,
		"The recipe grid shows actual drive bills and load ratings.")
	belt_recipe.pressed.emit()
	verify(view.issued == [{"action": "craft_part", "entity": "pod-fabrication-hub", "role": "belt", "half_span": 0}],
		"The powered-route recipe keeps the selected workshop identity.")
	var gearbox_recipe: Button = inventory.recipe_buttons["part:1"]
	var vertical_gearbox_recipe: Button = inventory.recipe_buttons["part:2"]
	var chain_recipe: Button = inventory.recipe_buttons["part:3"]
	verify("Horizontal gearbox" in gearbox_recipe.tooltip_text
		and "Vertical gearbox" in vertical_gearbox_recipe.tooltip_text
		and "Chain drive" in chain_recipe.tooltip_text
		and gearbox_recipe.icon.resource_path.ends_with("/gearbox.svg")
		and vertical_gearbox_recipe.icon.resource_path.ends_with("/vertical_gearbox.svg")
		and chain_recipe.icon.resource_path.ends_with("/chain_drive.svg")
		and gearbox_recipe.accessibility_name != vertical_gearbox_recipe.accessibility_name,
		"Native relay recipes have distinct visible icons and accessible identities.")
	frame.grab_focus()
	var bindings_before_resize: Array[String] = inventory.slots.duplicate()
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		verify(inventory.catalog.visible,
			"The original wide inventory is still open when its passive frame is captured.")
		verify(root.get_texture().get_image().save_png(capture_prefix + "-wide.png") == OK,
			"Retain the open inventory before resizing as a passive frame.")
	root.size = Vector2i(640, 480)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	verify(inventory.catalog.visible and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
		Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size)))
		and not inventory.recipe_scroll.get_h_scroll_bar().visible
		and inventory.catalog.gui_get_focus_owner() == frame
		and inventory.slots == bindings_before_resize,
		"An open inventory stays visible, reachable and keyboard-focused after narrowing the viewport.")
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		verify(root.get_texture().get_image().save_png(capture_prefix + "-narrow.png") == OK,
			"Retain the narrowed open inventory as a passive frame.")
	root.size = Vector2i(1280, 800)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	verify(inventory.catalog.visible and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
		Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size)))
		and inventory.catalog.gui_get_focus_owner() == frame
		and inventory.slots == bindings_before_resize,
		"The same inventory and recipe focus remain available when the viewport grows again.")
	if not capture_prefix.is_empty() and DisplayServer.get_name() != "headless":
		verify(root.get_texture().get_image().save_png(capture_prefix + "-restored.png") == OK,
			"Retain the reopened wide inventory as a passive frame.")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	inventory._input(escape)
	root.size = Vector2i(640, 480)
	await process_frame
	await process_frame
	verify(not inventory.catalog.visible,
		"Escape closes the inventory, and a later resize does not reopen it.")
	var close_button: Button
	for candidate: Node in inventory.catalog.find_children("*", "Button", true, false):
		if (candidate as Button).tooltip_text.begins_with("Close build and inventory"):
			close_button = candidate
	verify(close_button != null, "The inventory close icon remains available.")
	for close_mode: String in ["escape", "button", "toggle"]:
		root.size = Vector2i(1280, 800)
		await process_frame
		await process_frame
		inventory.open_catalog()
		verify(inventory.catalog.visible, "The inventory opens before the resize-close race.")
		root.size = Vector2i(640, 480)
		match close_mode:
			"escape": inventory._input(escape)
			"button": close_button.pressed.emit()
			"toggle": inventory.open_catalog()
		await process_frame
		await process_frame
		verify(not inventory.catalog.visible,
			"A %s dismissal during resize is not reversed by deferred popup recovery." % close_mode)
	var shared := SharedWidgets.new()
	shared.session = SessionStub.new()
	shared.client = "Q"
	shared.state = view.state.duplicate(true)
	shared.state.workshop_completed_actors = ["P", "Q"]
	root.add_child(shared)
	shared._build_interface()
	shared.building_hotbar.open_at_bench("pod-fabrication-hub")
	var shared_recipe: Button = shared.building_hotbar.recipe_buttons["component:copper_shaft"]
	verify("rated for 24 load" in shared_recipe.tooltip_text
		and "Carry the ingredients" in shared_recipe.tooltip_text and shared.issued.is_empty(),
		"A shared worker sees its own cargo and native recipe ratings.")
	shared.free()
	view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"models": 0, "desktop_operations": 0, "scope": "field and bench inventory recipes over invented projection"}))
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
		verify(view.tool_buttons.collector.disabled and "0" in view.tool_buttons.collector.accessibility_name,
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

## Passive pointer and E-panel consumer over a confirmed-shaped snapshot.
class ObjectMenuWidgets:
	extends "res://opening/opening.gd"
	var hit := {}
	var source_id := ""
	var issued: Array = []
	func _ready() -> void:
		set_process(false)
	func _screen_pick(_screen: Vector2) -> Dictionary:
		return hit
	func _screen_hand_source(_screen: Vector2) -> String:
		return source_id
	func _pointed_screen_position() -> Vector2:
		return Vector2(640, 400)
	func _update_camera() -> void:
		pass
	func _update_cursor() -> void:
		pass
	func issue(action: Dictionary) -> Dictionary:
		issued.append(action.duplicate(true))
		return {"accepted": false, "reason": "fixture_only"}

class CrankInteractionView:
	extends "res://opening/opening.gd"
	var hit_body: StaticBody3D
	var issued: Array = []
	var allow_hold := true
	var accept_pulse := true
	func _ready() -> void:
		set_process(false)
	func _pointed_screen_position() -> Vector2:
		return Vector2.ZERO
	func _screen_pick(_screen: Vector2) -> Dictionary:
		return {"collider": hit_body} if hit_body != null else {}
	func _crank_hold_allowed() -> bool:
		return allow_hold and _can_control_character()
	func issue(action: Dictionary) -> Dictionary:
		issued.append(action.duplicate(true))
		return {"accepted": accept_pulse}

class CrankSessionStub:
	extends RefCounted
	var ready := true
	var request_namespace := "shared-crank-"
	var request_sequence := 0
	var sent: Array[Dictionary] = []
	func is_ready() -> bool:
		return ready
	func submit(action: Dictionary) -> Dictionary:
		request_sequence += 1
		sent.append(action.duplicate(true))
		return {"queued": true, "accepted": false,
			"request": request_namespace + str(request_sequence)}
	func set_control(_direction: Vector2, _jump: bool) -> void:
		pass

class SharedCrankInteractionView:
	extends "res://opening/shared_opening.gd"
	var hit_body: StaticBody3D
	var allow_hold := true
	func _ready() -> void:
		set_process(false)
	func _pointed_screen_position() -> Vector2:
		return Vector2.ZERO
	func _screen_pick(_screen: Vector2) -> Dictionary:
		return {"collider": hit_body} if hit_body != null else {}
	func _crank_hold_allowed() -> bool:
		return allow_hold and _can_control_character()
	func _refresh() -> void:
		_settle_pending()
	func _refresh_ui() -> void:
		pass
	func _message(_words: String, _refused: bool = false) -> void:
		pass
	func _construction_feedback(_intent: Dictionary, _outcome: Dictionary) -> void:
		pass
	func _update_cursor() -> void:
		pass

func _object_menu_snapshot() -> Dictionary:
	return {"context": "object-menu-fixture", "revision": 1, "order": 0,
		"options": {"native": true, "physical": true, "foundations": true},
		"first_plate_unlock": false,
		"actors": {"P": {"ready": true, "position": [0.0, 1.0, 0.0]}},
		"inventories": {"P": 0}, "parts": {}, "part_kits": {"P": {}},
		"entities": {}, "foundations": {}, "transmission_parts": {}, "belt_spans": {},
		"placed_components": {"bench": {"component": "wooden_workbench", "center": [0, 0, 0]}},
		"fabrication_benches": [{"id": "bench", "center": [0, 0, 0]}],
		"fabrication_hub": {"id": "pod", "installed": true, "center": [4, 0, 0]},
		"hand_sources": {"tree": {"kind": "tree", "position": [1.0, 1.0, 0.0], "remaining": 8}},
		"cargo": {"P": {"timber": 4, "raw": 0, "components": {}}},
		"component_recipes": {"wooden_frame": {"timber": 3, "copper": 0},
			"wooden_shaft": {"timber": 2, "copper": 0}},
		"component_capacity": 20, "part_recipes": [], "part_specifications": {"P": []},
		"guided_press_assemblies": [], "collector_assemblies": [], "dropped_material": [],
		"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
		"remaining": 0, "powered": false, "power_enabled": false, "motion": {},
		"links": [], "drive_links": [], "opening_engineering": {}}

func _slide_controls_check() -> void:
	var view := OfflineWidgets.new()
	get_root().add_child(view)
	var panel := RecoveryActions.ArrivalAssemblyControls.new()
	panel.configure(view)
	view.add_child(panel)
	var snapshot := _object_menu_snapshot()
	snapshot.placed_components = {
		"anvil": {"component": "anvil", "center": [12, 0, 8]},
		"head": {"component": "flat_head", "center": [12, 1, 8]},
		"slide": {"component": "wooden_slide", "center": [12, 2, 8],
			"input_ports": [[11, 2, 8], [13, 2, 8]]}}
	snapshot.sliding_press_assemblies = [{"anvil": "anvil", "center": [12, 0, 8],
		"status": "ready", "work_center": [12, 0, 8], "selected_exit": [13, 0, 8],
		"parts": {"anvil": "anvil", "head": "head", "slide": "slide"},
		"open_feeds": [{"entry": [13, 0, 8], "exit": [11, 0, 8]},
			{"entry": [11, 0, 8], "exit": [13, 0, 8]}]}]
	snapshot.crank_items = {"crank-1": {"id": "crank-1", "holder": "",
		"attached_to": "slide", "port": [11, 2, 8]}}
	snapshot.cargo.P.raw = 1
	snapshot.dropped_material = [{"center": [12, 0, 8], "raw": 1, "products": 0,
		"offcuts": 0, "work_lots": []}]
	view.state = snapshot
	view.client = "P"
	view.selected = "slide"
	panel.refresh(snapshot, "P", "slide", true)
	panel.open_context()
	verify(panel.press_anvil_for("head") == "anvil" and panel.press_anvil_for("slide") == "anvil",
		"The fitted head and slide resolve to the same native work support.")
	verify(panel.press_section.visible and panel.route_choice.disabled and panel._route_index == 1
		and not panel.slide_port_choice.visible and panel.turn_button.visible
		and not panel.turn_button.disabled,
		"The E-menu turns the fitted slide input without a side selector.")
	verify(panel.inventory_section.visible and not panel.feed_button.visible
		and not panel.refeed_work_button.visible and not panel.pickup_button.visible
		and not panel.recover_work_button.visible
		and panel.inventory_counts.workbed_work.text == "1"
		and panel.inventory_slots.workbed_work.icon != null,
		"A fitted slide shows supported material on the workbed instead of separate Feed and pickup icons.")
	verify(panel.inventory_slots.workbed_work.icon.resource_path.ends_with("/" + BuildingHotbar.MATERIALS.raw[1])
		and panel.inventory_slots.player_raw.icon == panel.inventory_slots.workbed_work.icon
		and panel.inventory_slots.workbed_work.tooltip_text.contains(BuildingHotbar.MATERIALS.raw[0])
		and not panel.inventory_slots.has("player_offcut"),
		"Carried copper and retained copper use one literal stock icon and name without an unsupported offcut input.")
	var retained_blank: Dictionary = panel.inventory_drag("workbed_work")
	verify(retained_blank.get("wire", {}).get("action") == "pickup_material"
		and panel.inventory_can_drop("player", retained_blank)
		and not panel.inventory_can_drop("workbed", retained_blank),
		"A workbed blank can be dragged into carried inventory only.")
	panel.inventory_drop("player", retained_blank)
	verify(view.issued.back() == {"action": "pickup_material", "center": [12, 0, 8],
		"expected": {"raw": 1, "products": 0, "offcuts": 0, "work_lots": []}},
		"Click and drag recovery submits the exact supported work snapshot.")
	view.issued.clear()
	panel._turn()
	verify(view.issued.back() == {"action": "turn_slide_crank", "entity": "slide",
		"port": [11, 2, 8]}, "The turn icon sends the fitted native input port.")
	verify(not panel.cycle_slide_port(),
		"The workbed has no crank-side cycling control.")
	snapshot.crank_items["crank-1"].port = [13, 2, 8]
	panel.refresh(snapshot, "P", "slide", true)
	panel._turn()
	verify(view.issued.back().port == [13, 2, 8],
		"Refitting the crank on the other side changes the actual drive port.")
	snapshot.sliding_press_assemblies[0].open_feeds = [{"entry": [13, 0, 8],
		"exit": [11, 0, 8]}]
	panel.refresh(snapshot, "P", "slide", true)
	verify(panel.turn_button.disabled and panel.route_choice.disabled
		and panel.press_status.text.contains("Selected outlet blocked"),
		"A different clear outlet cannot silently replace the route owned by the work.")
	snapshot.sliding_press_assemblies[0].status = "blocked_feed"
	snapshot.sliding_press_assemblies[0].open_feeds.clear()
	panel.refresh(snapshot, "P", "slide", true)
	verify(panel.press_status.text == "No clear through-feed route. Close [Esc], press F, then click the blocking part."
		and panel.feed_button.disabled and panel.inventory_section.visible
		and panel.inventory_drag("player_raw").is_empty(),
		"One side obstruction blocks every through-feed route without implying blockers on both sides.")
	snapshot.sliding_press_assemblies[0].status = "ready"
	snapshot.sliding_press_assemblies[0].open_feeds.append({"entry": [13, 0, 8],
		"exit": [11, 0, 8]})
	snapshot.sliding_press_assemblies[0].open_feeds.append({"entry": [11, 0, 8],
		"exit": [13, 0, 8]})
	snapshot.dropped_material.clear()
	snapshot.sliding_press_assemblies[0].erase("selected_exit")
	panel.refresh(snapshot, "P", "anvil", true)
	view.selected = "anvil"
	var auto_snapshot: Dictionary = snapshot.duplicate(true)
	auto_snapshot.sliding_press_assemblies[0].auto_route = true
	auto_snapshot.sliding_press_assemblies[0].auto_feed = {
		"entry": [11, 0, 8], "exit": [13, 0, 8]}
	panel._route_index = 0
	panel.refresh(auto_snapshot, "P", "anvil", true)
	var auto_blank: Dictionary = panel.inventory_drag("player_raw")
	verify(not panel.route_choice.visible and panel.auto_route_cue.visible
		and panel.auto_route_cue.text.contains("WEST → EAST")
		and panel.flow_diagram.visible and panel.flow_diagram.route == auto_snapshot.sliding_press_assemblies[0].auto_feed
		and panel.flow_diagram.accessibility_name.contains("WEST → EAST")
		and panel.flow_diagram.focus_mode == Control.FOCUS_ALL
		and not panel.cycle_feed_route()
		and auto_blank.get("wire", {}).get("entry", []) == [11, 0, 8],
		"The native Auto route drives the focused material diagram and carried feed without a G selector.")
	auto_snapshot.sliding_press_assemblies[0].auto_feed = {
		"entry": [13, 0, 8], "exit": [11, 0, 8]}
	panel.refresh(auto_snapshot, "P", "anvil", true)
	var connected_blank: Dictionary = panel.inventory_drag("player_raw")
	verify(not panel.route_choice.visible and panel.auto_route_cue.text.contains("EAST → WEST")
		and panel.flow_diagram.route == auto_snapshot.sliding_press_assemblies[0].auto_feed
		and panel.flow_diagram.accessibility_name.contains("EAST → WEST")
		and connected_blank.get("wire", {}).get("entry", []) == [13, 0, 8],
		"A reversed native Auto projection changes the diagram and carried-copper entry together.")
	auto_snapshot.sliding_press_assemblies[0].erase("auto_feed")
	panel.refresh(auto_snapshot, "P", "anvil", true)
	verify(panel.auto_route_cue.text.contains("ROUTE BLOCKED")
		and panel.flow_diagram.route.is_empty()
		and panel.flow_diagram.accessibility_name.contains("ROUTE BLOCKED")
		and panel.inventory_drag("player_raw").is_empty(),
		"A blocked native Auto route shows no inferred arrow or alternate feed.")
	panel.refresh(snapshot, "P", "anvil", true)
	verify(panel.cycle_feed_route() and panel._route_index == 1,
		"G changes the next feed direction after the retained route is released.")
	var carried_blank: Dictionary = panel.inventory_drag("player_raw")
	verify(panel.inventory_slots.player_raw.icon.resource_path.ends_with("/" + BuildingHotbar.MATERIALS.raw[1]),
		"A carried copper tile uses the same stock icon as copper retained on the workbed.")
	verify(panel.inventory_can_drop("workbed", carried_blank)
		and carried_blank.get("wire", {}) == {"action": "feed_press", "entity": "anvil",
			"entry": [11, 0, 8]},
		"The selected carried blank targets the clear workbed route.")
	panel.inventory_drop("workbed", carried_blank)
	verify(view.issued.back() == carried_blank.wire,
		"Dragging a carried blank to the workbed sends one native feed command.")
	view.issued.clear()
	verify(panel.inventory_shortcut(KEY_F) and view.issued.back() == carried_blank.wire,
		"F transfers the same selected blank through the workbed inventory.")
	view.issued.clear()
	snapshot.revision = 2
	verify(not panel.inventory_can_drop("workbed", carried_blank),
		"A stale drag cannot transfer after the native projection advances.")
	panel.refresh(snapshot, "P", "anvil", true)
	snapshot.cargo.P.work_lots = [{"id": 7, "remaining": 2, "cycle_ticks": 3,
		"recipe_input": 1}]
	panel.refresh(snapshot, "P", "anvil", true)
	var carried_work: Dictionary = panel.inventory_drag("player_work")
	verify(panel.inventory_slots.player_work.icon.resource_path.ends_with("/" + BuildingHotbar.MATERIALS.work_lots[1])
		and panel.inventory_slots.player_work.tooltip_text.contains(BuildingHotbar.MATERIALS.work_lots[0]),
		"Carried partial work keeps its copper workpiece identity and puts remaining strokes in the tooltip.")
	verify(carried_work.get("wire", {}).get("action") == "refeed_press_work"
		and carried_work.wire.work_id == 7 and panel.inventory_can_drop("workbed", carried_work),
		"The selected partial workpiece has its own workbed transfer.")
	view.issued.clear()
	verify(panel.inventory_shortcut(KEY_R) and view.issued.back() == carried_work.wire,
		"R transfers the selected partial workpiece through the workbed inventory.")
	view.issued.clear()
	snapshot.dropped_material = [{"center": [13, 0, 8], "raw": 0, "products": 1,
		"offcuts": 0, "work_lots": []}]
	panel.refresh(snapshot, "P", "anvil", true)
	var formed_plate: Dictionary = panel.inventory_drag("workbed_output")
	verify(panel.inventory_slots.workbed_output.icon.resource_path.ends_with("/" + BuildingHotbar.MATERIALS.products[1])
		and panel.inventory_slots.workbed_output.tooltip_text.contains(BuildingHotbar.MATERIALS.products[0]),
		"The outlet uses the full inventory's copper plate art and name.")
	verify(panel.inventory_can_drop("player", formed_plate)
		and not panel.inventory_can_drop("workbed", formed_plate)
		and panel.inventory_counts.workbed_output.text == "1",
		"A blocked outlet keeps its formed plate visible until it is carried.")
	verify(panel.inventory_shortcut(KEY_P) and view.issued.back() == formed_plate.wire,
		"P recovers the exact outlet plate through the workbed inventory.")
	view.issued.clear()
	var released_route: Dictionary = snapshot.duplicate(true)
	released_route.sliding_press_assemblies[0].auto_route = true
	released_route.sliding_press_assemblies[0].auto_feed = {
		"entry": [11, 0, 8], "exit": [13, 0, 8]}
	released_route.dropped_material[0].center = [11, 0, 8]
	panel.refresh(released_route, "P", "anvil", true)
	verify(panel.inventory_drag("workbed_output").get("wire", {}).get("center", []) == [11, 0, 8],
		"Auto keeps a completed plate recoverable at its old selected outlet after route release.")
	panel.refresh(snapshot, "P", "anvil", true)
	snapshot.dropped_material.append({"center": [12, 0, 8], "raw": 0,
		"products": 0, "offcuts": 1, "work_lots": []})
	panel.refresh(snapshot, "P", "anvil", true)
	verify(panel.inventory_counts.workbed_work.text == "1"
		and panel.inventory_slots.workbed_work.tooltip_text.contains("offcut")
		and panel.inventory_slots.workbed_work.icon.resource_path.ends_with("/" + BuildingHotbar.MATERIALS.offcuts[1])
		and panel.inventory_drag("player_raw").is_empty()
		and panel.inventory_drag("workbed_work").get("wire", {}).get("expected", {}).get("offcuts") == 1,
		"A retained offcut occupies the work face and must be recovered before another blank.")
	snapshot.dropped_material.pop_back()
	panel.refresh(snapshot, "P", "anvil", true)
	panel.refresh(snapshot, "P", "anvil", false)
	verify(panel.inventory_drag("workbed_output").is_empty()
		and not panel.inventory_shortcut(KEY_P) and view.issued.is_empty(),
		"An unready actor can inspect workbed custody but cannot transfer it.")
	panel.refresh(snapshot, "P", "anvil", true)
	var shared := SharedWorkshopWidgets.new()
	shared.session = SessionStub.new()
	shared.state = snapshot
	shared.client = "P"
	shared.selected = "anvil"
	get_root().add_child(shared)
	var shared_panel := RecoveryActions.ArrivalAssemblyControls.new()
	shared_panel.configure(shared)
	shared.add_child(shared_panel)
	shared_panel.refresh(snapshot, "P", "anvil", true)
	shared_panel.open_context()
	verify(not shared_panel.inventory_drag("workbed_output").is_empty(),
		"A connected shared actor reads the same confirmed outlet custody.")
	shared.pending_actions = {"waiting": {}}
	shared_panel.inventory_drop("player", formed_plate)
	verify(shared_panel.inventory_drag("workbed_output").is_empty() and shared.issued.is_empty(),
		"An unsettled shared request makes workbed transfer read-only.")
	shared.pending_actions.clear()
	shared.session.ready = false
	shared_panel.inventory_drop("player", formed_plate)
	verify(shared_panel.inventory_drag("workbed_output").is_empty() and shared.issued.is_empty(),
		"A disconnected shared actor can inspect the workbed without submitting pickup.")
	shared.free()
	panel._feed()
	verify(view.issued.back() == {"action": "feed_press", "entity": "anvil",
		"entry": [11, 0, 8]}, "The chosen feed side still sends the native anvil route.")
	snapshot.dropped_material = [{"center": [13, 0, 8], "raw": 0, "products": 1,
		"offcuts": 0, "work_lots": []}]
	panel.refresh(snapshot, "P", "anvil", true)
	panel._pickup_exit()
	verify(view.issued.back().action == "pickup_material"
		and view.issued.back().center == [13, 0, 8],
		"After route release, the E-menu finds the formed plate at either native outlet.")
	snapshot.sliding_press_assemblies[0] = {"anvil": "anvil", "center": [12, 0, 8],
		"status": "missing_head"}
	snapshot.guided_press_assemblies = [{"anvil": "anvil", "center": [12, 0, 8],
		"status": "ready", "parts": {"anvil": "anvil", "shaft": "old-shaft"},
		"open_feeds": [{"entry": [13, 0, 8], "exit": [11, 0, 8]}]}]
	panel.refresh(snapshot, "P", "anvil", true)
	verify(panel._press.get("parts", {}).has("shaft") and panel.turn_button.visible,
		"An incomplete slide candidate cannot hide a ready guided press on the same anvil.")
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"failures": failures, "scope": "invented projection and ordinary E-menu command mapping"}))
	quit(0 if failures == 0 else 1)

func _slide_inventory_render_check() -> void:
	var destination := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--slide-inventory-image-prefix="):
			destination = argument.trim_prefix("--slide-inventory-image-prefix=")
	var scene_root := get_root()
	scene_root.gui_embed_subwindows = true
	scene_root.size = Vector2i(1280, 800)
	var view := ObjectMenuWidgets.new()
	view.state = _object_menu_snapshot()
	view.state.placed_components = {
		"anvil": {"component": "anvil", "center": [12, 0, 8]},
		"head": {"component": "flat_head", "center": [12, 1, 8]},
		"slide": {"component": "wooden_slide", "center": [12, 2, 8],
			"input_ports": [[11, 2, 8], [13, 2, 8]]}}
	view.state.sliding_press_assemblies = [{"anvil": "anvil", "center": [12, 0, 8],
		"status": "ready", "work_center": [12, 0, 8], "parts": {"anvil": "anvil",
			"head": "head", "slide": "slide"},
		"open_feeds": [{"entry": [11, 0, 8], "exit": [13, 0, 8]}]}]
	view.state.cargo.P = {"raw": 2, "products": 0, "offcuts": 1,
		"work_lots": [{"id": 9, "remaining": 2, "cycle_ticks": 3, "recipe_input": 1}]}
	view.state.dropped_material = [{"center": [13, 0, 8], "raw": 0,
		"products": 1, "offcuts": 0, "work_lots": []}]
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	scene_root.add_child(view)
	view._build_interface()
	view._refresh_ui()
	view._open_object_menu_for("slide")
	await process_frame
	var panel = view.arrival_assembly_controls
	verify(view.object_menu.visible and panel.inventory_section.is_visible_in_tree()
		and not panel.feed_button.visible and panel.inventory_counts.workbed_output.text == "1",
		"The ordinary selected slide renders workbed and outlet custody without a Feed icon.")
	var player_bounds: Rect2 = panel.inventory_player_row.get_global_rect()
	var workbed_bounds: Rect2 = panel.inventory_workbed_row.get_global_rect()
	var operations: Rect2 = view.object_menu_operations.get_global_rect()
	verify(player_bounds.position.x >= operations.position.x and player_bounds.end.x <= operations.end.x
		and workbed_bounds.position.x >= operations.position.x and workbed_bounds.end.x <= operations.end.x,
		"The workbed rows fit in the ordinary press panel.")
	if not destination.is_empty():
		await RenderingServer.frame_post_draw
		verify(scene_root.get_texture().get_image().save_png(destination + "-wide.png") == OK,
			"Retain the passive workbed inventory panel at 1280 by 800.")
	var projected_press: Dictionary = view.state.sliding_press_assemblies[0]
	projected_press.open_feeds.append({"entry": [13, 0, 8], "exit": [11, 0, 8]})
	projected_press.auto_route = true
	projected_press.auto_feed = {"entry": [13, 0, 8], "exit": [11, 0, 8]}
	view._refresh_ui()
	verify(panel.auto_route_cue.visible and panel.auto_route_cue.text.contains("EAST → WEST")
		and panel.flow_diagram.is_visible_in_tree()
		and panel.flow_diagram.route == projected_press.auto_feed
		and panel.flow_diagram.accessibility_name.contains("Blue arrow")
		and not panel.route_choice.visible,
		"The ordinary workbed renders a focusable connected material diagram without a route selector.")
	if not destination.is_empty():
		await RenderingServer.frame_post_draw
		verify(scene_root.get_texture().get_image().save_png(destination + "-connected-auto.png") == OK,
			"Retain the connected Auto cue in the actual workbed panel.")
	projected_press.erase("auto_route")
	projected_press.erase("auto_feed")
	projected_press.open_feeds.pop_back()
	view._refresh_ui()
	var output_drag: Dictionary = panel.inventory_drag("workbed_output")
	var output_preview := TextureRect.new()
	output_preview.texture = panel.inventory_slots.workbed_output.icon
	panel.inventory_slots.workbed_output.force_drag(output_drag, output_preview)
	await process_frame
	verify(scene_root.gui_is_dragging() and panel.inventory_player_region.highlighted
		and output_preview.texture.resource_path.ends_with("/" + BuildingHotbar.MATERIALS.products[1]),
		"A copper plate drag keeps its literal item art and highlights the carried drop region.")
	if not destination.is_empty():
		await RenderingServer.frame_post_draw
		verify(scene_root.get_texture().get_image().save_png(destination + "-plate-drag.png") == OK,
			"Retain the plate drag and carried drop region at 1280 by 800.")
	scene_root.gui_cancel_drag()
	await process_frame
	view.state.cargo.P.raw = 0
	view.state.cargo.P.work_lots.clear()
	view._refresh_ui()
	verify(not panel.inventory_cells.has("player_raw") and not panel.inventory_cells.has("player_work")
		and not panel.inventory_slots.has("player_offcut")
		and panel.inventory_player_region.visible and panel.inventory_slots.workbed_output.icon != null,
		"A finished plate remains recoverable onto a visible carried region with no feed input tiles.")
	if not destination.is_empty():
		await RenderingServer.frame_post_draw
		verify(scene_root.get_texture().get_image().save_png(destination + "-output-no-input.png") == OK,
			"Retain the output pickup region with no available carried input.")
	view.state.dropped_material.clear()
	view._refresh_ui()
	verify(panel.inventory_slots.workbed_work.icon == null and panel.inventory_slots.workbed_output.icon == null
		and panel.inventory_counts.workbed_work.text.is_empty()
		and panel.inventory_counts.workbed_output.text.is_empty()
		and not panel.inventory_counts.workbed_work.visible
		and not panel.inventory_counts.workbed_output.visible,
		"An empty work face and outlet retain blank slots without item art or zero badges.")
	if not destination.is_empty():
		await RenderingServer.frame_post_draw
		verify(scene_root.get_texture().get_image().save_png(destination + "-empty.png") == OK,
			"Retain the empty workbed and carried pickup region.")
	view.state.dropped_material = [{"center": [12, 0, 8], "raw": 0, "products": 0,
		"offcuts": 1, "work_lots": []}]
	view._refresh_ui()
	verify(panel.inventory_slots.workbed_work.icon != null
		and panel.inventory_slots.workbed_work.icon.resource_path.ends_with("/offcut.svg")
		and panel.inventory_slots.workbed_output.icon == null
		and panel.inventory_player_region._can_drop_data(Vector2.ZERO,
			panel.inventory_drag("workbed_work")),
		"A retained offcut remains visible and recoverable, with no unusable carried offcut input.")
	if not destination.is_empty():
		await RenderingServer.frame_post_draw
		verify(scene_root.get_texture().get_image().save_png(destination + "-offcut.png") == OK,
			"Retain the recoverable offcut at the work face.")
	scene_root.size = Vector2i(640, 480)
	view._fit_object_menu(Vector2i(640, 480))
	await process_frame
	player_bounds = panel.inventory_player_row.get_global_rect()
	workbed_bounds = panel.inventory_workbed_row.get_global_rect()
	operations = view.object_menu_operations.get_global_rect()
	verify(player_bounds.position.x >= operations.position.x and player_bounds.end.x <= operations.end.x
		and workbed_bounds.position.x >= operations.position.x and workbed_bounds.end.x <= operations.end.x,
		"The workbed rows fit at a 640 by 480 view.")
	if not destination.is_empty():
		await RenderingServer.frame_post_draw
		verify(scene_root.get_texture().get_image().get_region(Rect2i(0, 0, 640, 480))
			.save_png(destination + "-narrow.png") == OK,
			"Retain the passive workbed inventory panel at 640 by 480.")
	projected_press.auto_route = true
	projected_press.auto_feed = {"entry": [13, 0, 8], "exit": [11, 0, 8]}
	view._refresh_ui()
	await process_frame
	var diagram_bounds: Rect2 = panel.flow_diagram.get_global_rect()
	operations = view.object_menu_operations.get_global_rect()
	verify(panel.flow_diagram.is_visible_in_tree()
		and diagram_bounds.position.x >= operations.position.x
		and diagram_bounds.end.x <= operations.end.x
		and diagram_bounds.position.y >= operations.position.y
		and diagram_bounds.end.y <= operations.end.y,
		"The connected native material diagram fits within the narrow workbed panel.")
	if not destination.is_empty():
		await RenderingServer.frame_post_draw
		verify(scene_root.get_texture().get_image().get_region(Rect2i(0, 0, 640, 480))
			.save_png(destination + "-connected-auto-narrow.png") == OK,
			"Retain the narrow connected material diagram.")
	projected_press.erase("auto_feed")
	view._refresh_ui()
	verify(panel.flow_diagram.route.is_empty()
		and panel.flow_diagram.accessibility_name.contains("ROUTE BLOCKED"),
		"The ordinary blocked view removes directional arrows with no invented feed.")
	if not destination.is_empty():
		await RenderingServer.frame_post_draw
		verify(scene_root.get_texture().get_image().get_region(Rect2i(0, 0, 640, 480))
			.save_png(destination + "-blocked-auto-narrow.png") == OK,
			"Retain the narrow blocked material diagram.")
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"failures": failures, "scope": "ordinary slide E-panel rendered over an invented projection"}))
	quit(0 if failures == 0 else 1)

func _object_menu_check() -> void:
	var root := get_root()
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)
	var view := ObjectMenuWidgets.new()
	view.state = _object_menu_snapshot()
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	root.add_child(view)
	view._build_interface()
	view._refresh_ui()
	var picker := StaticBody3D.new()
	picker.set_meta("component_entity", "bench")
	view.add_child(picker)
	view.hit = {"collider": picker}
	view.distance = 0.0
	view._refresh_pointed_summary()
	verify(view.pointed_summary.visible and view.pointed_name.text.to_lower() == "wooden workbench"
		and view.pointed_detail.text.contains("E") and view.pointed_summary.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"A pointed bench shows a small passive summary without capturing the pointer.")
	verify(view.selected.is_empty() and view.issued.is_empty(),
		"Passive inspection creates no selection or authority request.")
	view.mode = "collector"
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_I
	view._unhandled_input(key)
	verify(view.mode == "collector" and view.selected.is_empty(), "I no longer selects an Inspect tool.")
	view.mode = "inspect"
	view._world_click(Vector2i.ZERO, "bench")
	verify(view.selected.is_empty() and view.issued.is_empty(),
		"Clicking while idle does not pin an inspector or send a command.")
	view._open_pointed_machine()
	await process_frame
	var inventory = view.building_hotbar
	verify(inventory.catalog.visible and inventory.context_bench == "bench"
		and not view.object_menu.visible and inventory.recipe_buttons["component:wooden_frame"].visible,
		"E opens the built bench recipes in the shared inventory window.")
	verify(not view._can_control_character() and view._can_choose_tool()
		and inventory.recipe_buttons["component:wooden_frame"].focus_mode == Control.FOCUS_ALL,
		"The inventory holds movement and keeps recipe icons keyboard focusable.")
	for viewport_size in [Vector2i(800, 600), Vector2i(640, 480)]:
		root.size = viewport_size
		inventory._configure_catalog_layout(viewport_size)
		inventory._place_catalog()
		await process_frame
		var panel_rect := Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size))
		verify(panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0
			and panel_rect.end.x <= viewport_size.x and panel_rect.end.y <= viewport_size.y
			and absf(panel_rect.get_center().x - viewport_size.x / 2.0) <= 2.0,
			"The E-opened inventory fits a simulated resized viewport.")
	root.size = Vector2i(1280, 800)
	inventory._configure_catalog_layout(Vector2i(1280, 800))
	await process_frame
	key.keycode = KEY_D
	key.ctrl_pressed = true
	view._input(key)
	verify(inventory.catalog.visible and not view.stock_label.is_visible_in_tree(),
		"Ctrl+D cannot open generic worksite details over inventory.")
	key.ctrl_pressed = false
	verify(view.issued.is_empty(), "Opening the workbench remains a read-only view action.")
	inventory.recipe_buttons["component:wooden_frame"].pressed.emit()
	verify(view.issued == [{"action": "craft_component", "entity": "bench", "component": "wooden_frame"}],
		"The focused bench recipe submits its exact native component command.")
	view.issued.clear()
	verify(inventory.recipe_buttons["component:wooden_shaft"].visible,
		"The second component remains discoverable without a selection dropdown.")
	inventory.recipe_buttons["component:wooden_shaft"].pressed.emit()
	verify(view.issued == [{"action": "craft_component", "entity": "bench", "component": "wooden_shaft"}],
		"The second recipe crafts at the same selected bench.")
	view.issued.clear()
	view.state.part_recipes = [
		{"kind": "shaft", "teeth": 0, "half_span": 2, "timber": 1, "copper": 0},
		{"kind": "wheel", "teeth": 0, "half_span": 0, "timber": 2, "copper": 0}]
	view._refresh_ui()
	verify(inventory.recipe_buttons.has("part:1") and inventory.recipe_buttons["part:1"].visible,
		"A valid transmission recipe appears in the open inventory.")
	inventory.recipe_buttons["part:1"].pressed.emit()
	verify(view.issued == [{"action": "craft_part", "entity": "bench", "role": "waterwheel", "half_span": 0}],
		"The waterwheel recipe crafts at the selected bench.")
	view.issued.clear()
	view.state.actors.P.ready = false
	view._refresh_ui()
	verify(inventory.recipe_buttons["component:wooden_frame"].disabled
		and inventory.recipe_buttons["part:1"].disabled,
		"An unready actor cannot enable either recipe action.")
	view.state.actors.P.ready = true
	view._refresh_ui()
	verify(view.issued.is_empty(), "Read-only inventory navigation creates no native command.")
	key.keycode = KEY_ESCAPE
	inventory._input(key)
	await process_frame
	verify(not inventory.catalog.visible and not view.object_menu_scrim.visible
		and view.issued.is_empty(),
		"Escape closes inventory without a game request.")
	view.hit = {}
	view.source_id = "tree"
	view._refresh_pointed_summary()
	verify(view.pointed_summary.visible and view.pointed_name.text == "Timber tree"
		and view.pointed_detail.text.contains("8 left"),
		"The same passive summary identifies a confirmed harvestable source.")
	view.source_id = ""
	view.state.transmission_parts = {"shaft": {"kind": "shaft", "axis": 0, "center": [4, 0, 0]}}
	picker.set_meta("entity", "shaft")
	view.hit = {"collider": picker}
	view._refresh_ui()
	view._open_pointed_machine()
	await process_frame
	verify(view.object_menu.visible and view.object_menu_title.text == "Shaft"
		and not view.object_menu_operations.visible and view.object_menu.size.x <= 550,
		"E gives an ordinary part its details without unrelated workshop operations.")
	view.object_menu.hide()
	await process_frame
	var prefix := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--image-prefix="):
			prefix = argument.trim_prefix("--image-prefix=")
	if not prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
		picker.remove_meta("entity")
		view.state.transmission_parts.erase("shaft")
		view._refresh_ui()
		view._refresh_pointed_summary()
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-hover.png") == OK,
			"Retain the passive pointer summary pixels.")
		view._open_pointed_machine()
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(prefix + "-menu.png") == OK,
			"Retain the E-opened bench inventory pixels.")
	view.free()
	var shared := SharedWidgets.new()
	shared.session = SessionStub.new()
	shared.client = "P"
	shared.state = _object_menu_snapshot()
	shared.state.parts = {}
	shared.pointed = "bench"
	shared.camera = Camera3D.new()
	shared.add_child(shared.camera)
	shared.selection_ring = MeshInstance3D.new()
	shared.add_child(shared.selection_ring)
	root.add_child(shared)
	shared._build_interface()
	shared._refresh_ui()
	shared._open_pointed_machine()
	await process_frame
	verify(shared.building_hotbar.catalog.visible
		and not shared.building_hotbar.recipe_buttons["component:wooden_frame"].disabled,
		"A connected shared worker can use the selected workbench while movement is held.")
	verify(shared.building_hotbar.recipe_buttons["component:wooden_shaft"].visible,
		"The shared worker sees another valid recipe without a dropdown.")
	shared.pending_actions = {"waiting": {}}
	shared._refresh_ui()
	verify(shared.building_hotbar.recipe_buttons["component:wooden_frame"].disabled,
		"An unresolved shared action disables the inventory recipe.")
	shared.building_hotbar.catalog.hide()
	await process_frame
	verify(shared._can_control_character(),
		"An unresolved shared action does not stop ordinary character movement after closing the panel.")
	shared.pending_actions.clear()
	shared._open_pointed_machine()
	await process_frame
	shared.session.ready = false
	shared._refresh_ui()
	verify(shared.building_hotbar.recipe_buttons["component:wooden_frame"].disabled,
		"Disconnection makes the retained shared workbench inventory read-only.")
	shared.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"models": 0, "desktop_operations": 0, "scope": "isolated ordinary workbench UI"}))
	quit(0 if failures == 0 else 1)
func _slide_view_check() -> void:
	var cycle := 4096
	var at_rest := {"subticks": 0, "remainder": 0, "denominator": 1, "cycle_subticks": cycle}
	var halfway := {"subticks": 2048, "remainder": 0, "denominator": 1, "cycle_subticks": cycle}
	var quarter := {"subticks": 1024, "remainder": 0, "denominator": 1, "cycle_subticks": cycle}
	verify(is_zero_approx(ComponentPresenter.slide_carriage_drop(at_rest, 0.37)),
		"The native rest phase presents the carriage at its top position.")
	verify(is_equal_approx(ComponentPresenter.slide_carriage_drop(halfway, 0.37), -0.37),
		"Half a native cycle presents the bottom of the stroke.")
	verify(is_equal_approx(ComponentPresenter.slide_carriage_drop(quarter, 0.37), -0.185),
		"A quarter native cycle presents an intermediate carriage position.")
	verify(is_zero_approx(ComponentPresenter.slide_carriage_drop({"subticks": 4096,
		"remainder": 0, "denominator": 1, "cycle_subticks": cycle}, 0.37)),
		"An invalid phase cannot put the carriage outside its occupied volume.")
	var presenter := ComponentPresenter.new()
	root.add_child(presenter)
	var samples := [
		{"kind": "wooden_slide", "phase": null, "x": -0.7, "name": "Preview"},
		{"kind": "wooden_slide", "phase": halfway, "x": 0.0, "name": "PlacedWood"},
		{"kind": "copper_slide", "phase": quarter, "x": 0.7, "name": "PlacedMetal"}]
	for sample: Dictionary in samples:
		var anchor := Node3D.new()
		anchor.name = sample.name
		anchor.position = Vector3(sample.x, 0.55, 0)
		presenter.add_child(anchor)
		if sample.phase == null:
			presenter.preview_component(anchor, sample.kind, Vector3(0.42, 0.825, 0.42))
		else:
			presenter._placed_component(anchor, sample.kind, Vector3.ZERO,
				Vector3(0.42, 0.825, 0.42), "", 0.0, 0.0, Vector3.ZERO, sample.phase)
		verify(anchor.has_node("SlideRail") and anchor.has_node("SlideCrown")
			and anchor.has_node("IntegralInputShaft") and anchor.has_node("SlideCarriage"),
			"Each slide has fixed rails, an exposed input and a separate carriage.")
		verify(is_equal_approx((anchor.get_node("IntegralInputShaft").mesh as CylinderMesh).height,
			Geometry.PITCH * 0.5),
			"The visible input rod reaches the native one-quarter-pitch shaft ports.")
		var carriage := anchor.get_node("SlideCarriage") as Node3D
		verify(carriage.position.y - 0.103 > -0.4125 and carriage.position.y + 0.07 < 0.4125,
			"The native phase keeps the carriage inside the admitted swept height.")
	verify(presenter.get_node("Preview/SlideCarriage").position.y >
		presenter.get_node("PlacedMetal/SlideCarriage").position.y and
		presenter.get_node("PlacedMetal/SlideCarriage").position.y >
		presenter.get_node("PlacedWood/SlideCarriage").position.y,
		"Projected phases change visible carriage positions in stroke order.")
	var image_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--slide-image="):
			image_path = argument.trim_prefix("--slide-image=")
	if not image_path.is_empty():
		verify(DisplayServer.get_name().to_lower() != "headless",
			"A passive pixel capture needs a rendered display.")
		root.size = Vector2i(1280, 760)
		var world := WorldEnvironment.new()
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("313b39")
		world.environment = environment
		presenter.add_child(world)
		var floor := MeshInstance3D.new()
		var floor_mesh := BoxMesh.new()
		floor_mesh.size = Vector3(2.2, 0.06, 1.2)
		floor.mesh = floor_mesh
		floor.position.y = 0.03
		presenter.add_child(floor)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, -30, 0)
		presenter.add_child(sun)
		var camera := Camera3D.new()
		camera.position = Vector3(1.3, 1.3, 2.7)
		camera.fov = 38
		presenter.add_child(camera)
		camera.look_at(Vector3(0, 0.56, 0))
		camera.make_current()
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(image_path) == OK,
			"The slide mesh can be inspected in a passive render.")
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail",
		"checks": checks, "failures": failures, "models": 0, "desktop_operations": 0,
		"scope": "isolated preview and projected-phase meshes"}))
	quit(0 if failures == 0 else 1)
