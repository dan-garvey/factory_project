extends SceneTree
## Default cases inspect unmounted views. --buttons-only mounts actual widgets
## over invented projections. --carried-guidance-only also reads recovery menus.
## None of these modes creates a live Model.

const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")
const SiteSurface = preload("res://opening/site_surface.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const ComponentPresenter = preload("res://opening/native_transmission_presenter.gd")
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
	var crank_pointed := false
	func _pointed_pod_crank(_screen: Vector2) -> Dictionary:
		return state.get("hand_crank", {}) if crank_pointed else {}
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
	if "--slide-view-only" in OS.get_cmdline_user_args():
		call_deferred("_slide_view_check")
		return
	if "--component-placement-only" in OS.get_cmdline_user_args():
		call_deferred("_component_placement_check")
		return
	if "--object-menu-only" in OS.get_cmdline_user_args():
		call_deferred("_object_menu_check")
		return
	if "--workshop-pages-only" in OS.get_cmdline_user_args():
		call_deferred("_workshop_pages")
		return
	if "--field-craft-widget-only" in OS.get_cmdline_user_args():
		call_deferred("_field_craft_widget")
		return
	if "--pod-floor-only" in OS.get_cmdline_user_args():
		call_deferred("_pod_floor_views")
		return
	if "--multitool-view-only" in OS.get_cmdline_user_args():
		call_deferred("_multitool_presentation")
		return
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
	if "--arrival-hotbar-render-only" in OS.get_cmdline_user_args():
		call_deferred("_render_arrival_hotbar")
		return
	if "--hotbar-only" in OS.get_cmdline_user_args():
		call_deferred("_hotbar")
		return
	if "--arrival-hotbar-only" in OS.get_cmdline_user_args():
		call_deferred("_arrival_hotbar")
		return
	if "--carried-guidance-only" in OS.get_cmdline_user_args():
		call_deferred("_carried_guidance")
		return
	if "--shared-component-results-only" in OS.get_cmdline_user_args():
		call_deferred("_shared_component_results")
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

class ComponentPlacementChoice extends Node:
	var kind := "anvil"
	func selected_name() -> String:
		return kind
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
		and view.component_preview.has_node("CastPedestal") and not view.component_preview_blocked,
		"The frame-top anvil ghost uses the placed anvil mesh and is initially clear.")
	verify(view.component_preview_snap == "Above wooden frame"
		and "Aim at a floor or built surface" in view._component_placement_hint(),
		"The anvil hint allows a floor or built surface without requiring a press frame.")
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
		"generation": 1, "occupied": {"center": [0.0, 1.130625, 0.0],
		"half": [0.14, 0.230625, 0.14]}}
	var placed_anvil := Node3D.new()
	placed_anvil.position.y = 1.130625
	view.add_child(placed_anvil)
	presenter.preview_component(placed_anvil, "anvil", Vector3(0.28, 0.46125, 0.28))
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
	var placed_ram := Node3D.new()
	placed_ram.position = ram_box.center
	view.add_child(placed_ram)
	presenter.preview_component(placed_ram, "ram_face", ram_box.size)
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
	view.state.cargo.P.components.softmetal_cog = 1
	choice.kind = "softmetal_cog"
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
		"actors": {"P": {"ready": true, "position": [0.0, 1.0, 0.0]}, "Q": {"ready": true, "position": [3.0, 1.0, 0.0]}},
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
	var grip_center: Vector3 = tool.transform * grip.mesh.get_aabb().get_center()
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
		verify(hand.mesh.get_surface_count() > 0 and hand.mesh.get_aabb().size.length() < 0.35,
			"The close view uses a bounded hand extracted from the qualified actor, without the hidden torso.")
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
				"hand_crank": {"holder": "pod"}}
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
			var crank_at: Vector3 = view.landing_crank_visual.global_position
			view.state = before.duplicate(true)
			view.state.fabrication_hub.installed = false
			view.state.fabrication_hub.holder = "P"
			view._sync_landing_pod_visual()
			verify(not view.landing_hub_visual.visible and view.landing_hub_pick.collision_layer == 0
				and view.landing_crank_visual.is_visible_in_tree()
				and view.landing_crank_visual.global_position.is_equal_approx(crank_at),
				"Stowing the issued workshop removes its view and pick while the crank remains at the landed pod.")
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
				and view.landing_pod_visual.position.is_equal_approx(pod_floor)
				and view.landing_crank_visual.global_position.is_equal_approx(crank_at),
				"A moved workshop keeps the rigid bench and matching pick separate from the fixed pod and crank.")
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
		view.state.hand_sources = {"ore": {"kind": "ore_deposit", "position": [0.0, 0.825, 0.0], "initial": 16, "remaining": 2},
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
			and not view.goal_label.text.contains("3 timber") and not view.goal_label.text.contains("1 softmetal")
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
		verify(not view.confirm_button.visible and not view.lesson_button.visible,
			"Arrival offers neither old objective confirmation nor the completed-machine lesson.")
		view._toggle_explanation()
		verify(not view.explanation_open and view.example_presenter == null,
			"The retired lesson shortcut cannot create its historical example in arrival.")
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
		verify(view.state == before and view.model == null and view.request_sequence == 0,
			"Presentation and request selection do not debit local stock or create a Model.")
		verify(view._harvest_result_text({"moved_timber": 1, "moved_raw": 0}) == "Collected 1 timber."
			and view._harvest_result_text({"moved_timber": 0, "moved_raw": 1}) == "Collected 1 softmetal blank."
			and view._harvest_result_text({"moved_timber": 0, "moved_raw": 0}) == "Cutting…",
			"The start receipt is not mislabeled as collected stock; contact reports actual moved quantities.")
		verify("depleted" in view._material_refusal_message({"reason": "unavailable_source"}, "fallback")
			and "full" in view._material_refusal_message({"reason": "inventory_full"}, "fallback"),
			"Native stock and capacity refusals retain actionable advice.")
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
		view._refresh_ui()
		var before: Dictionary = view.state.duplicate(true)
		var bar = view.building_hotbar
		bar.open_catalog()
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = KEY_8
		bar._input(event)
		verify(bar.target_slot == 7, "Number keys choose a hotbar target without changing the world.")
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
		view._unhandled_input(event)
		verify(view.pause_menu.visible, "Escape opens the worksite menu after closing an object panel.")
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
		verify(bar.buttons.all(func(button: Button): return button.size == Vector2(54, 54) and button.text.is_empty())
			and bar.slot_icons.all(func(icon: TextureRect): return icon.size == Vector2(32, 32)),
			"The hotbar gives every part the same icon area and fixed slot size without face labels.")
		var bar_surface := bar.get_theme_stylebox("panel") as StyleBoxFlat
		verify(bar_surface.bg_color.a == 0.0 and bar_surface.border_width_left == 0
			and (bar.buttons[0].get_theme_stylebox("normal") as StyleBoxFlat).bg_color.a < 0.5,
			"The hotbar has no framing border and its idle cells leave the worksite visible.")
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
		verify(bar.catalog.visible and bar.slot_targets.size() == 8 and bar.target_slot == 7,
			"The inventory exposes eight numbered hotbar targets.")
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
		verify(bar.catalog.visible and bar.target_slot == 7, "An empty slot opens its assignment inventory.")
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
		verify(bar.buttons[0].disabled and bar.slot_counts[0].text == "0" and view.mode == "inspect",
			"An exhausted kit disables the slot without borrowing the compatibility stock alias.")
		bar._select_target(7)
		bar.catalog_buttons.collector.pressed.emit()
		verify(bar.slots[7].is_empty() and view.mode == "inspect", "An unavailable catalog item cannot activate or fill a slot.")
		view.client = "Q"
		view._refresh_ui()
		verify(bar.slot_counts[1].text == "2" and bar.buttons[0].disabled, "Every slot follows the active actor's own kit.")
		view.state.part_kits.erase("Q")
		view._refresh_ui()
		verify(bar.buttons[1].disabled and bar.slot_counts[1].text == "0", "Missing actor kits have no fallback owner.")
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
			verify(bar.catalog.size.y <= dimensions.y - 16,
				"The inventory window fits vertically and scrolls its item grid.")
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

func _arrival_hotbar() -> void:
	var view := OfflineWidgets.new()
	view.client = "P"
	view.state = hotbar_observation()
	view.state.hand_sources = {}
	view.state.cargo = {"P": {"components": {}}, "Q": {"components": {"wooden_frame": 1}}}
	view.state.fabrication_hub = {"id": "pod-fabrication-hub", "installed": true}
	view.state.component_recipes = {
		"wooden_frame": {"timber": 3, "softmetal": 0},
		"wooden_shaft": {"timber": 1, "softmetal": 0, "load_rating": 8},
		"tool_mount": {"timber": 1, "softmetal": 0},
		"cutting_edge": {"timber": 0, "softmetal": 1},
		"anvil": {"timber": 0, "softmetal": 2},
		"softmetal_cog": {"timber": 0, "softmetal": 2, "load_rating": 24},
		"wooden_slide": {"timber": 3, "softmetal": 0, "load_rating": 8},
		"softmetal_slide": {"timber": 0, "softmetal": 4, "load_rating": 24}}
	view.state.foundation_recipe = {"timber": 2, "softmetal": 0}
	view.state.part_recipes = [{"kind": "shaft", "timber": 1, "softmetal": 0,
		"teeth": 0, "half_span": 2}]
	view.state.component_capacity = 20
	view.state.placed_components = {}
	root.add_child(view)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	view._build_interface()
	view._refresh_ui()
	var bar = view.building_hotbar
	verify(bar.slots == bar.ARRIVAL_SLOTS and bar.slots[0] == "component:wooden_frame"
		and not bar.slots.has("collector") and not bar.slots.has("processor")
		and bar.slot_icons[0].texture == bar.component_buttons.wooden_frame.icon
		and bar.slot_icons[3].texture == bar.component_buttons.tool_mount.icon,
		"Native arrival quick slots begin with modular parts and a foundation, without complete machines.")
	var component_icon_paths := {}
	for component: String in bar._component_names:
		var texture: Texture2D = bar.component_buttons[component].icon
		verify(texture != null and texture.resource_path.ends_with("/" + component + ".svg"),
			"Each fabricated component uses its own named item icon in the inventory.")
		component_icon_paths[texture.resource_path] = true
	verify(component_icon_paths.size() == bar._component_names.size(),
		"Different fabricated parts never share one icon resource.")
	var slot_icon_ids := {}
	for icon: TextureRect in bar.slot_icons:
		slot_icon_ids[icon.texture.get_instance_id()] = true
	verify(slot_icon_ids.size() == 8 and bar.buttons[0].accessibility_name.contains("Wooden frame"),
		"The opening hotbar distinguishes all eight slots by icon and preserves a focus name.")
	var face_labels: Array[String] = []
	for child: Node in bar.buttons[0].get_children():
		if child is Label:
			face_labels.append(child.text)
	verify(face_labels == ["1", "0"], "Only the slot number and stock count remain on an item face.")
	verify(not bar.catalog_buttons.collector.visible and not bar.catalog_buttons.processor.visible
		and bar.recipe_side.visible and bar.component_buttons.size() == view.arrival_assembly_controls.COMPONENTS.size(),
		"The arrival inventory hides historical machines and has icons for every fabricated component.")
	verify(bar.component_buttons.has("anvil") and bar.component_buttons.has("ram_face")
		and bar.component_buttons.anvil.disabled and bar.component_buttons.ram_face.disabled,
		"The catalog names anvil and ram face directly and disables parts absent from carried cargo.")
	verify(bar.buttons[0].disabled and bar.slot_counts[0].text == "0"
		and not bar.component_buttons.wooden_frame.visible,
		"A part absent from the active actor's native cargo cannot be selected or assigned.")
	var initial: Dictionary = view.state.duplicate(true)
	view.state.cargo.P.components = {"wooden_frame": 2, "softmetal_cog": 1,
		"anvil": 1, "ram_face": 1}
	view._refresh_ui()
	verify(not bar.component_buttons.anvil.disabled and not bar.component_buttons.ram_face.disabled
		and bar.component_counts.anvil.text == "1"
		and "Anvil" in bar.component_buttons.anvil.tooltip_text,
		"The component icon shows its authoritative count and accessible name.")
	view.state.cargo.P.timber = 5
	view.state.cargo.P.raw = 3
	view.state.cargo.P.products = 1
	view.state.cargo.P.work_lots = [{"id": 7}]
	view.state.hand_crank = {"holder": "P"}
	view.state.workshop_completed_actors = ["P"]
	view._refresh_ui()
	verify(bar.material_counts.timber.text == "5" and bar.material_counts.raw.text == "3"
		and bar.material_counts.products.text == "1" and bar.material_counts.work_lots.text == "1"
		and bar.material_counts.hand_crank.text == "1"
		and "5 carried" in bar.material_buttons.timber.accessibility_name,
		"Carried material icons read the active actor's confirmed cargo and hand tools.")
	verify(bar.carried_label.text == "CARRIED · CRANK WITH YOU" and bar.material_buttons.hand_crank.visible,
		"The inventory identifies the issued crank when this actor carries it.")
	verify(not view.goal_label.text.contains("timber ·") and not view.goal_label.text.contains("ore blanks carried")
		and view.goal_label.text.contains("PLATE IN INVENTORY"),
		"The objective completes from the actor's plate while the inventory window owns counts: " + view.goal_label.text)
	bar.open_catalog(7)
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
	view.state.hand_crank.holder = "pod"
	view._refresh_ui()
	verify(bar.material_counts.timber.text == "2" and bar.material_counts.raw.text == "0"
		and bar.material_counts.hand_crank.text == "0" and bar.component_counts.anvil.text == "0"
		and not bar.material_buttons.raw.visible and not bar.component_buttons.anvil.visible,
		"Crafting, placement and return refresh icon counts from the next confirmed projection.")
	verify(bar.carried_label.text == "CARRIED · CRANK AT POD TRAY"
		and not bar.material_buttons.hand_crank.visible,
		"The inventory locates the issued crank without showing it as carried stock.")
	view.state.hand_crank.holder = "Q"
	view._refresh_ui()
	verify(bar.carried_label.text == "CARRIED · CRANK WITH OTHER WORKER"
		and not bar.material_buttons.hand_crank.visible,
		"The inventory shows foreign crank custody without inventing another carried item.")
	view.state.hand_crank.holder = "pod"
	view._refresh_ui()
	view.state.cargo.P.components.anvil = 1
	view._refresh_ui()
	verify(not bar.buttons[0].disabled and bar.slot_counts[0].text == "2",
		"A confirmed fabricated frame enables its quick slot with the active actor's count.")
	bar.select_slot(0)
	verify(view.mode == "component" and view.arrival_assembly_controls.selected_name() == "wooden_frame"
		and bar.selected_slot == 0 and view.issued.is_empty(),
		"A component quick slot changes the ordinary placement selection without issuing construction.")
	view.state.part_kits.P = {"foundation": 15}
	view._refresh_ui()
	bar.open_catalog(7)
	verify(bar.catalog_buttons.foundation.visible and not bar.catalog_buttons.belt.visible
		and not bar.catalog_buttons.wheel.visible,
		"The arrival catalog gives space to carried parts instead of unavailable machine cards.")
	var cog_index: int = bar._component_names.find("softmetal_cog")
	verify(cog_index >= 0 and bar.catalog.visible, "The catalog includes the stronger metal cog.")
	if cog_index >= 0:
		verify(not bar.component_buttons.softmetal_cog.disabled
			and bar.component_counts.softmetal_cog.text == "1",
			"The inventory reads the carried metal cog from native component cargo.")
		bar.component_buttons.softmetal_cog.pressed.emit()
		verify(bar.slots[7] == "component:softmetal_cog" and view.mode == "component"
			and view.arrival_assembly_controls.selected_name() == "softmetal_cog"
			and bar.slot_icons[7].texture == bar.component_buttons.softmetal_cog.icon
			and view.issued.is_empty(),
			"Catalog assignment selects the exact component in the existing workshop and placement path.")
	bar.open_catalog(6)
	bar.component_buttons.ram_face.pressed.emit()
	verify(bar.slots[6] == "component:ram_face" and view.mode == "component"
		and view.arrival_assembly_controls.selected_name() == "ram_face" and view.issued.is_empty(),
		"One direct catalog action assigns and selects the ram face for placement.")
	root.size = Vector2i(640, 480)
	await settle_widgets()
	bar.open_catalog(6)
	await settle_widgets()
	verify(bar.catalog.visible and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
		Rect2(Vector2(bar.catalog.position), Vector2(bar.catalog.size)))
		and bar.catalog.size.y <= 464,
		"The combined inventory stays inside the narrow viewport with a scrollable item grid.")
	bar.catalog.hide()
	view.client = "Q"
	view._refresh_ui()
	verify(bar.slot_counts[0].text == "1" and bar.slot_counts[7].text == "0" and bar.buttons[7].disabled,
		"Switching actor changes component availability without borrowing the previous actor's cargo.")
	verify(bar.material_counts.timber.text == "0" and bar.component_counts.anvil.text == "0",
		"A new actor or restored projection cannot retain another actor's inventory counts.")
	view.state.cargo.Q.timber = 4
	view._refresh_ui()
	verify(bar.material_counts.timber.text == "4", "A restored actor projection refreshes the inventory icon count.")
	view.client = "P"
	bar.select_slot(7)
	view.state.cargo.P.components.softmetal_cog = 0
	view._refresh_ui()
	bar.select_slot(7)
	verify(bar.buttons[7].disabled and bar.slot_counts[7].text == "0"
		and view.arrival_assembly_controls.selected_name() == "softmetal_cog"
		and view.issued.is_empty(),
		"An exhausted fabricated component cannot create a construction command.")
	verify(view.state.cargo.P.components.wooden_frame == 2 and initial.cargo.P.components.is_empty()
		and view.model == null and view.actor_world == null,
		"Hotbar interaction changes no component custody or simulation state.")
	view.state.cargo.P.components.wooden_slide = 1
	view.state.cargo.P.components.softmetal_slide = 1
	view.state.cargo.P.timber = 3
	view.state.cargo.P.raw = 4
	view._refresh_ui()
	bar.open_catalog()
	var slide_key := InputEventKey.new()
	slide_key.keycode = KEY_8
	slide_key.pressed = true
	bar._input(slide_key)
	bar.component_buttons.wooden_slide.grab_focus()
	await settle_widgets()
	verify(bar.focus_description.text.contains("Wooden slide")
		and bar.component_buttons.wooden_slide.icon != bar.component_buttons.softmetal_slide.icon
		and bar.component_counts.wooden_slide.text == "1",
		"Each slide has a distinct focused icon with its actual carried count.")
	bar.component_buttons.wooden_slide.pressed.emit()
	verify(bar.slots[7] == "component:wooden_slide" and view.mode == "component"
		and view.arrival_assembly_controls.selected_name() == "wooden_slide",
		"The numbered target and focused wooden slide select the ordinary placement tool.")
	bar.open_catalog(7)
	bar.recipe_buttons["component:wooden_slide"].pressed.emit()
	verify(view.issued.back() == {"action": "field_craft", "component": "wooden_slide"},
		"The wooden slide recipe uses the existing finite field craft command.")
	bar.open_at_bench("pod-fabrication-hub")
	bar.recipe_buttons["component:softmetal_slide"].pressed.emit()
	verify(view.issued.back() == {"action": "craft_component", "entity": "pod-fabrication-hub",
		"component": "softmetal_slide"},
		"The metal slide recipe uses the existing bench and native custody path.")
	view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"failures": failures, "models": 0, "desktop_operations": 0,
		"scope": "native-arrival hotbar over invented projections"}))
	quit(0 if failures == 0 else 1)

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
	view.state.part_kits.P = {"foundation": 15}
	view.state.cargo = {"P": {"components": {"wooden_frame": 2, "wooden_shaft": 1,
		"tool_mount": 1, "receiver_tray": 1, "cutting_edge": 1, "softmetal_cog": 1,
		"wooden_slide": 1, "softmetal_slide": 1},
		"timber": 7, "raw": 3, "products": 1, "offcuts": 2, "sheets": 1,
		"work_lots": [{"id": 7}]}}
	view.state.hand_crank = {"holder": "P"}
	view.state.fabrication_hub = {"id": "pod-fabrication-hub", "installed": true}
	view.state.component_recipes = {
		"wooden_frame": {"timber": 3, "softmetal": 0},
		"wooden_shaft": {"timber": 1, "softmetal": 0, "load_rating": 8},
		"tool_mount": {"timber": 1, "softmetal": 0},
		"cutting_edge": {"timber": 0, "softmetal": 1},
		"anvil": {"timber": 0, "softmetal": 2},
		"softmetal_cog": {"timber": 0, "softmetal": 2, "load_rating": 24},
		"wooden_slide": {"timber": 3, "softmetal": 0, "load_rating": 8},
		"softmetal_slide": {"timber": 0, "softmetal": 4, "load_rating": 24}}
	view.state.foundation_recipe = {"timber": 2, "softmetal": 0}
	view.state.part_recipes = [{"kind": "shaft", "timber": 1, "softmetal": 0,
		"teeth": 0, "half_span": 2}]
	view.state.component_capacity = 20
	view.state.placed_components = {}
	root.add_child(view)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	view._build_interface()
	view._refresh_ui()
	var bar = view.building_hotbar
	bar.open_catalog(7)
	bar.component_buttons.wooden_slide.pressed.emit()
	view._refresh_ui()
	await settle_widgets()
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-bar.png") == OK,
		"Retain the rendered arrival component hotbar.")
	bar.open_catalog(7)
	var inventory_scroll: ScrollContainer = bar.catalog.find_child("InventoryItems", true, false)
	inventory_scroll.ensure_control_visible(bar.component_buttons.softmetal_slide)
	await settle_widgets()
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-catalog.png") == OK,
		"Retain the rendered arrival component catalog.")
	verify(bar.recipe_buttons.has("component:wooden_frame") and
		bar.recipe_buttons.has("component:anvil") and bar.recipe_buttons.has("part:0"),
		"The item inventory presents field and bench recipes beside carried stock.")
	var stocked_cargo: Dictionary = view.state.cargo.P.duplicate(true)
	view.state.cargo.P = {"components": {}}
	view.state.hand_crank.holder = "pod"
	view.state.part_kits.P = {}
	view._refresh_ui()
	bar.open_catalog(7)
	await settle_widgets()
	verify(bar.catalog.visible and bar.carried_label.text == "CARRIED · CRANK AT POD TRAY"
		and not bar.material_buttons.timber.visible and not bar.component_buttons.wooden_frame.visible
		and bar.recipe_buttons["component:wooden_frame"].visible,
		"Empty carried stock shows the pod crank location while recipes remain discoverable.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-empty.png") == OK,
		"Retain the empty-inventory recipe catalog.")
	view.state.cargo.P = stocked_cargo
	view.state.hand_crank.holder = "P"
	view.state.part_kits.P = {"foundation": 15}
	view._refresh_ui()
	await settle_widgets()
	inventory_scroll.scroll_vertical = int(inventory_scroll.get_v_scroll_bar().max_value)
	await settle_widgets()
	verify(bar.component_buttons.wooden_frame.visible and bar.component_buttons.softmetal_cog.visible
		and inventory_scroll.get_v_scroll_bar() != null,
		"The restored cargo and scrollable inventory show named component icons.")
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(prefix + "-components.png") == OK,
		"Retain the visible component icon grid after scrolling.")
	root.size = Vector2i(640, 480)
	bar.catalog.hide()
	await settle_widgets()
	bar.open_catalog(7)
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
	bar.open_catalog(7)
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
		view.state.motion.collector.state = "stopped"
		view._refresh_ui()
		verify(view.goal_label.text.contains("Use cogs and shafts"),
			"Stopped native motion takes priority over carried-material reinsertion advice.")
		view.state.power_enabled = true
		view.state.motion.collector.state = "rotating"
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

func _shared_component_results() -> void:
	var cases := [
		{"action": "craft_component", "accepted": true, "reason": "", "text": "Component crafted from carried material."},
		{"action": "field_craft", "accepted": true, "reason": "", "text": "Wooden component shaped with your multitool."},
		{"action": "place_component", "accepted": true, "reason": "", "text": "Component placed on the shared grid."},
		{"action": "reclaim_component", "accepted": true, "reason": "", "text": "Component returned to your carried cargo."},
		{"action": "craft_component", "accepted": false, "reason": "unavailable_input", "text": "Gather the timber or softmetal shown for this component."},
		{"action": "craft_component", "accepted": false, "reason": "inventory_full", "text": "Your component bag is full. Place a carried part to make room."},
		{"action": "craft_component", "accepted": false, "reason": "out_of_reach", "text": "Move beside the selected workshop to craft this component."},
		{"action": "field_craft", "accepted": false, "reason": "unavailable_input", "text": "Gather the timber shown for this component."},
		{"action": "field_craft", "accepted": false, "reason": "unavailable_recipe", "text": "Metal components need a workshop."},
		{"action": "craft_part", "accepted": false, "reason": "out_of_reach", "text": "Move beside the selected workshop to make a transmission kit."},
		{"action": "reclaim_component", "accepted": false, "reason": "inventory_full", "text": "Your component bag is full. Place another carried part before reclaiming."}]
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
		view.state.component_recipes = {"wooden_frame": {"timber": 3, "softmetal": 0}}
		view.state.foundation_recipe = {"timber": 2, "softmetal": 0}
		view.state.part_recipes = [
			{"kind": "gearbox", "timber": 2, "softmetal": 1, "half_span": 0, "teeth": 0},
			{"kind": "vertical_gearbox", "timber": 2, "softmetal": 1, "half_span": 0, "teeth": 0},
			{"kind": "chain_drive", "timber": 2, "softmetal": 1, "half_span": 0, "teeth": 0}]
		view.state.component_capacity = 20
		view.state.workshop_completed_actors = []
		view.state.fabrication_hub = {"id": "pod-fabrication-hub", "installed": true}
		view.state.fabrication_benches = [{"id": "field-bench", "center": [4, 0, 4]}]
		view.state.placed_components = {"field-bench": {"component": "wooden_workbench", "center": [4, 0, 4]},
			"press-anvil": {"component": "anvil", "center": [8, 0, 8]},
			"press-ram": {"component": "ram_face", "center": [8, 1, 8]},
			"collector-frame": {"component": "wooden_frame", "center": [0, 0, 0]}}
		view.state.guided_press_assemblies = [{"anvil": "press-anvil", "center": [8, 0, 8],
			"work_center": [8, 0, 8], "status": "ready", "parts": {"ram": "press-ram", "shaft": "press-shaft"},
			"open_feeds": [{"entry": [9, 0, 8], "exit": [7, 0, 8]}]}]
		view.state.collector_assemblies = [{"status": "ready", "center": [0, 0, 0],
			"parts": {"frame": "collector-frame", "shaft": "collector-shaft"}}]
		view.state.hand_crank = {"id": "pod-hand-crank", "holder": view.client}
		var before: Dictionary = view.state.duplicate(true)
		root.add_child(view)
		view.selection_ring = MeshInstance3D.new()
		view.add_child(view.selection_ring)
		view._build_interface()
		view._refresh_ui()
		var panel = view.arrival_assembly_controls
		var inventory = view.building_hotbar
		verify(inventory.carried_label.text == "CARRIED · CRANK WITH YOU",
			"The local and shared inventory read this actor's confirmed crank custody.")
		view.state.hand_crank.holder = "P" if shared else "Q"
		inventory.refresh()
		verify(inventory.carried_label.text == "CARRIED · CRANK WITH OTHER WORKER"
			and not inventory.material_buttons.hand_crank.visible,
			"The local and shared inventory locate a foreign-held crank outside carried stock.")
		verify(view._crank_turn_refusal("press") == "Crank held by another worker."
			and view._crank_turn_refusal("collector") == "Crank held by another worker.",
			"Both machine refusals follow a foreign holder instead of promising a pod pickup.")
		view.state.hand_crank.holder = "pod"
		inventory.refresh()
		verify(inventory.carried_label.text == "CARRIED · CRANK AT POD TRAY"
			and not inventory.material_buttons.hand_crank.visible,
			"The local and shared inventory locate a pod-held crank outside carried stock.")
		verify(view._crank_turn_refusal("press") == "Take the pod crank before turning this press."
			and view._crank_turn_refusal("collector") == "Take the pod crank before turning this collector.",
			"Both machine refusals point to the actual pod tray while the crank is there.")
		view.state.hand_crank.holder = view.client
		inventory.refresh()
		await process_frame
		await process_frame
		verify(not view.object_menu.visible and not panel.is_visible_in_tree()
			and not inventory.catalog.visible and not panel.press_section.visible,
			"A fresh opening leaves workshop controls off the game view.")
		var escape := InputEventKey.new()
		escape.pressed = true
		escape.keycode = KEY_ESCAPE
		view._unhandled_input(escape)
		verify(view.pause_menu.visible and view.pause_menu_scrim.visible
			and view.save_button.get_parent() == view.pause_resume_button.get_parent()
			and view.load_button.get_parent() == view.pause_resume_button.get_parent()
			and view.save_button.text.is_empty() and view.load_button.text.is_empty(),
			"Idle Escape opens icon-led worksite actions outside the object panel.")
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-escape.png") == OK,
				"Retain the centered worksite menu over the ordinary scene.")
		view._input(escape)
		verify(not view.pause_menu.visible and not view.pause_menu_scrim.visible,
			"Escape resumes the worksite from the pause menu.")
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
			and "2 timber + 0 ore" in inventory.recipe_buttons["foundation"].tooltip_text,
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
		view._unhandled_input(escape)
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
			panel.compact_button, panel.pickup_button, panel.recover_work_button, panel.crank_button]
		var icons_described := true
		for button: Button in press_icons:
			icons_described = icons_described and button.text.is_empty() and button.icon != null \
				and not button.tooltip_text.is_empty() and not button.accessibility_name.is_empty() \
				and button.focus_mode == Control.FOCUS_ALL
		verify(icons_described, "Press actions use focusable icons with an action description and shortcut.")
		verify(panel.feed_button.tooltip_text.contains("F") and panel.turn_button.tooltip_text.contains("T")
			and panel.pickup_button.tooltip_text.contains("P")
			and panel.recover_work_button.tooltip_text.contains("U")
			and panel.crank_button.tooltip_text.contains("C"),
			"Press action tooltips retain their keyboard routes.")
		view.state.hand_crank.holder = "P" if shared else "Q"
		panel.refresh(view.state, view.client, view.selected, true)
		verify(panel.crank_button.disabled and panel.crank_button.tooltip_text == "Crank held by another worker"
			and panel.crank_button.accessibility_name == "Crank held by another worker"
			and "another worker" in panel.turn_button.tooltip_text
			and panel.turn_button.accessibility_name == "Crank held by another worker",
			"A foreign-held crank cannot be offered as a pod pickup at the press.")
		view.state.hand_crank.holder = "pod"
		panel.refresh(view.state, view.client, view.selected, true)
		verify(not panel.crank_button.disabled and "Take pod crank" in panel.crank_button.tooltip_text,
			"The pod-held crank retains its available pickup cue at the press.")
		view.state.hand_crank.holder = view.client
		panel.refresh(view.state, view.client, view.selected, true)
		panel.feed_button.pressed.emit()
		verify(view.issued == [{"action": "feed_press", "entity": "press-anvil", "entry": [9, 0, 8]}],
			"The pointer feed icon sends the selected anvil and route to the native adapter.")
		view.issued.clear()
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
			and "shortcut Delete" in panel.reclaim_button.accessibility_name,
			"The guided ram exposes one described placed-part reclaim icon on its press page.")
		var reclaim_key := InputEventKey.new()
		reclaim_key.keycode = KEY_DELETE
		reclaim_key.pressed = true
		view._input(reclaim_key)
		verify(view.issued == [{"action": "reclaim_component", "entity": "press-ram"}],
			"Delete reaches the same native reclaim payload when the old Remove button is hidden.")
		view.issued.clear()
		root.size = Vector2i(640, 480)
		view._fit_object_menu(Vector2i(640, 480))
		await process_frame
		var narrow_actions: Rect2 = view.object_menu_operations.get_global_rect()
		verify(panel.feed_button.get_global_rect().position.x >= narrow_actions.position.x
			and panel.compact_button.get_global_rect().end.x <= narrow_actions.end.x
			and panel.crank_button.get_global_rect().end.x <= narrow_actions.end.x,
			"Both grouped press action rows fit inside the narrow object panel.")
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
		view.pointed = "collector-frame"
		view._open_pointed_machine()
		verify(view.object_menu.visible and panel.collector_section.is_visible_in_tree()
			and not panel.press_section.visible
			and panel.collector_cut_button.is_visible_in_tree(),
			"Ordinary E on a collector shows its cutting controls without unrelated crafting.")
		verify(panel.collector_crank_button.text.is_empty() and panel.collector_cut_button.text.is_empty()
			and panel.collector_crank_button.icon != null and panel.collector_cut_button.icon != null
			and "Return crank" in panel.collector_crank_button.tooltip_text
			and "Cut one ore blank" in panel.collector_cut_button.tooltip_text
			and "shortcut T" in panel.collector_crank_button.accessibility_name
			and "shortcut X" in panel.collector_cut_button.accessibility_name,
			"Collector crank custody and cutting appear as described, focused icons.")
		view.state.hand_crank.holder = "P" if shared else "Q"
		panel.refresh(view.state, view.client, view.selected, true)
		verify(panel.collector_crank_button.disabled
			and panel.collector_crank_button.tooltip_text == "Crank held by another worker"
			and panel.collector_crank_button.accessibility_name == "Crank held by another worker"
			and "another worker" in panel.collector_cut_button.tooltip_text
			and panel.collector_cut_button.accessibility_name == "Crank held by another worker",
			"A foreign-held crank cannot be offered as a pod pickup at the collector.")
		view.state.hand_crank.holder = "pod"
		panel.refresh(view.state, view.client, view.selected, true)
		verify(not panel.collector_crank_button.disabled
			and "Take pod crank" in panel.collector_crank_button.tooltip_text,
			"The pod-held crank retains its available pickup cue at the collector.")
		view.state.hand_crank.holder = view.client
		panel.refresh(view.state, view.client, view.selected, true)
		if not shared and not image_prefix.is_empty() and DisplayServer.get_name().to_lower() != "headless":
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(image_prefix + "-collector.png") == OK,
				"Retain the ordinary collector menu with its two icon controls.")
		action_key.keycode = KEY_X
		view._input(action_key)
		verify(view.issued == [{"action": "turn_hand_crank", "entity": "collector-shaft"}],
			"X in the collector panel uses its visible cut button and existing request payload.")
		view.issued.clear()
		action_key.keycode = KEY_T
		view._input(action_key)
		verify(view.issued == [{"action": "return_hand_crank", "entity": "pod-hand-crank"}],
			"T in the collector panel retains the exact crank-custody command.")
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
		view.state = before.duplicate(true)
		view._refresh_ui()
		verify(view.state == before and view.issued.is_empty() and view.model == null,
			"Workshop disclosure changes only local presentation, with no request or native state mutation.")
		view.free()
	print(JSON.stringify({"status": "pass" if failures == 0 else "fail", "checks": checks,
		"models": 0, "desktop_operations": 0, "scope": "offline/shared workshop disclosure and ordinary E callbacks over invented projections"}))
	quit(0 if failures == 0 else 1)

func _field_craft_widget() -> void:
	var view := OfflineWidgets.new()
	view.state = fixture()
	view.state.options.native = true
	view.state.hand_sources = {}
	view.state.cargo = {"P": {"raw": 1, "timber": 3, "components": {}},
		"Q": {"raw": 0, "timber": 0, "components": {}}}
	view.state.component_recipes = {"wooden_frame": {"timber": 3, "softmetal": 0},
		"cutting_edge": {"timber": 0, "softmetal": 1},
		"wooden_shaft": {"timber": 1, "softmetal": 0, "load_rating": 8},
		"softmetal_shaft": {"timber": 0, "softmetal": 2, "load_rating": 24}}
	view.state.foundation_recipe = {"timber": 2, "softmetal": 0}
	view.state.fabrication_hub = {"id": "pod-fabrication-hub", "installed": true}
	root.add_child(view)
	view.selection_ring = MeshInstance3D.new()
	view.add_child(view.selection_ring)
	view._build_interface()
	var inventory = view.building_hotbar
	inventory.open_catalog()
	var frame: Button = inventory.recipe_buttons["component:wooden_frame"]
	var edge: Button = inventory.recipe_buttons["component:cutting_edge"]
	var foundation: Button = inventory.recipe_buttons["foundation"]
	verify(inventory.catalog.visible and frame.visible and edge.visible and foundation.visible
		and frame.icon != null and edge.icon != null and foundation.icon != null
		and "3 timber + 0 ore" in frame.tooltip_text and "Field or bench" in frame.tooltip_text
		and "Bench" in edge.tooltip_text and "2 timber + 0 ore" in foundation.tooltip_text,
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
		{"kind": "belt", "timber": 2, "softmetal": 1, "half_span": 0, "teeth": 0},
		{"kind": "gearbox", "timber": 2, "softmetal": 1, "half_span": 0, "teeth": 0},
		{"kind": "vertical_gearbox", "timber": 2, "softmetal": 1, "half_span": 0, "teeth": 0},
		{"kind": "chain_drive", "timber": 2, "softmetal": 1, "half_span": 0, "teeth": 0}]
	view.state.part_specifications = {"P": [{"kind": "belt", "teeth": 0, "half_span": 0, "count": 1}]}
	inventory.refresh()
	var belt_recipe: Button = inventory.recipe_buttons["part:0"]
	verify("2 timber + 1 ore" in belt_recipe.tooltip_text and belt_recipe.icon != null
		and "rated for 8 load" in inventory.recipe_buttons["component:wooden_shaft"].tooltip_text
		and "rated for 24 load" in inventory.recipe_buttons["component:softmetal_shaft"].tooltip_text,
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
	root.size = Vector2i(640, 480)
	inventory._configure_catalog_layout(Vector2i(640, 480))
	inventory._place_catalog()
	await process_frame
	verify(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
		Rect2(Vector2(inventory.catalog.position), Vector2(inventory.catalog.size)))
		and not inventory.recipe_scroll.get_h_scroll_bar().visible,
		"The recipe grid remains reachable without sideways scrolling at a narrow viewport.")
	var shared := SharedWidgets.new()
	shared.session = SessionStub.new()
	shared.client = "Q"
	shared.state = view.state.duplicate(true)
	root.add_child(shared)
	shared._build_interface()
	shared.building_hotbar.open_at_bench("pod-fabrication-hub")
	var shared_recipe: Button = shared.building_hotbar.recipe_buttons["component:softmetal_shaft"]
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

## Passive pointer and E-panel consumer over a confirmed-shaped snapshot.
class ObjectMenuWidgets:
	extends "res://opening/opening.gd"
	var hit := {}
	var source_id := ""
	var issued: Array = []
	var crank_pointed := false
	func _pointed_pod_crank(_screen: Vector2) -> Dictionary:
		return state.get("hand_crank", {}) if crank_pointed else {}
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

func _object_menu_snapshot() -> Dictionary:
	return {"context": "object-menu-fixture", "revision": 1, "order": 0,
		"options": {"native": true, "physical": true, "foundations": true},
		"actors": {"P": {"ready": true, "position": [0.0, 1.0, 0.0]}},
		"inventories": {"P": 0}, "parts": {}, "part_kits": {"P": {}},
		"entities": {}, "foundations": {}, "transmission_parts": {}, "belt_spans": {},
		"placed_components": {"bench": {"component": "wooden_workbench", "center": [0, 0, 0]}},
		"fabrication_benches": [{"id": "bench", "center": [0, 0, 0]}],
		"fabrication_hub": {"id": "pod", "installed": true, "center": [4, 0, 0]},
		"hand_sources": {"tree": {"kind": "tree", "position": [1.0, 1.0, 0.0], "remaining": 8}},
		"cargo": {"P": {"timber": 4, "raw": 0, "components": {}}},
		"component_recipes": {"wooden_frame": {"timber": 3, "softmetal": 0},
			"wooden_shaft": {"timber": 2, "softmetal": 0}},
		"component_capacity": 20, "part_recipes": [], "part_specifications": {"P": []},
		"guided_press_assemblies": [], "collector_assemblies": [], "dropped_material": [],
		"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
		"remaining": 0, "powered": false, "power_enabled": false, "motion": {},
		"links": [], "drive_links": [], "opening_engineering": {}}

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
	view.state.hand_crank = {"id": "pod-hand-crank", "holder": "Q"}
	view.crank_pointed = true
	verify(view._pointed_summary_data(Vector2.ZERO).detail == "Held by Q",
		"The pointed pod tray reports the other worker's confirmed crank custody.")
	view._interact_pointed()
	verify(view.issued.is_empty(), "E on a foreign-held crank sends no false pickup request.")
	view.state.hand_crank.holder = "pod"
	view._interact_pointed()
	verify(view.issued == [{"action": "take_hand_crank", "entity": "pod-hand-crank"}],
		"E on the pod-held crank still sends the native take request.")
	view.issued.clear()
	view.state.hand_crank.holder = "P"
	view._interact_pointed()
	verify(view.issued == [{"action": "return_hand_crank", "entity": "pod-hand-crank"}],
		"E on this actor's crank still sends the native return request.")
	view.issued.clear()
	view.crank_pointed = false
	view.state.erase("hand_crank")
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
		{"kind": "shaft", "teeth": 0, "half_span": 2, "timber": 1, "softmetal": 0},
		{"kind": "wheel", "teeth": 0, "half_span": 0, "timber": 2, "softmetal": 0}]
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
	shared.state.hand_crank = {"id": "pod-hand-crank", "holder": "Q"}
	shared.crank_pointed = true
	shared._interact_pointed()
	verify(shared.issued.is_empty(), "Shared E on a foreign-held crank sends no false pickup request.")
	shared.state.hand_crank.holder = "pod"
	shared._interact_pointed()
	verify(shared.issued == [{"action": "take_hand_crank", "entity": "pod-hand-crank"}],
		"Shared E still sends the native take request for a pod-held crank.")
	shared.issued.clear()
	shared.state.hand_crank.holder = "P"
	shared._interact_pointed()
	verify(shared.issued == [{"action": "return_hand_crank", "entity": "pod-hand-crank"}],
		"Shared E still sends the native return request for this actor's crank.")
	shared.issued.clear()
	shared.crank_pointed = false
	shared.state.erase("hand_crank")
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
		{"kind": "softmetal_slide", "phase": quarter, "x": 0.7, "name": "PlacedMetal"}]
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
