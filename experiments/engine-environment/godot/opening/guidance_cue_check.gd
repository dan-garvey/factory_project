extends SceneTree
## Default/camera modes use detached views. Footer mode mounts only real UI
## containers, without a Model, body, network or game world.

const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")
const NativeModel = preload("res://opening/native_model.gd")
const CharacterPresenter = preload("res://opening/character_presenter.gd")
var checks := 0
var camera_failed := false
var failed := false

class SessionStub extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

class ToolStub extends RefCounted:
	var active_tool := "gear"

class CatalogStub extends RefCounted:
	var catalog := {"visible": false}

class FooterView extends Opening:
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass

class SharedFooterView extends SharedOpening:
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass

class RevealControlsView extends FooterView:
	func _refresh_ui() -> void:
		pass
	func _pose_arrival_reveal() -> void:
		pass
	func _update_camera() -> void:
		pass

func control_view() -> RevealControlsView:
	var view := RevealControlsView.new()
	root.add_child(view)
	view.client = "P"
	view.landing_pod_visual = Node3D.new()
	view.landing_hub_visual = Node3D.new()
	view.add_child(view.landing_pod_visual)
	view.add_child(view.landing_hub_visual)
	view.actor_world = load("res://opening/actor_world.gd").new()
	var body = load("res://opening/actor_body.gd").new()
	view.actor_world.bodies.P = body
	view.actor_world.release_counts.P = 0
	view.character_presenter = load("res://opening/character_presenter.gd").new()
	view.character_presenter.configure(view)
	view.add_child(view.character_presenter)
	view.character_presenter.set_process(false)
	view.character_presenter.set_physics_process(false)
	return view

func free_control_view(view: RevealControlsView) -> void:
	view.actor_world.bodies.P.free()
	view.actor_world.free()
	view.actor_world = null
	view.free()

func check_reveal_controls() -> void:
	var view := control_view()
	var body = view.actor_world.bodies.P
	body.set_control(Vector2.RIGHT, true)
	body.velocity = Vector3(3.0, 2.0, 0.0)
	view.character_presenter.held_keys[KEY_W] = true
	view.character_presenter.jump_requested = true
	await view._maybe_start_arrival_reveal()
	verify(view.arrival_reveal_active and body.direction == Vector2.ZERO and not body.jump_requested \
		and body.velocity.x == 0.0 and body.velocity.y == 2.0 \
		and view.character_presenter.held_keys.is_empty() and not view.character_presenter.jump_requested,
		"Starting the reveal releases existing motion and keys while preserving vertical physics.")
	view.character_presenter.held_keys[KEY_W] = true
	view.character_presenter.jump_requested = true
	view._finish_arrival_reveal()
	verify(not view.arrival_reveal_active and view.character_presenter.held_keys.is_empty() \
		and not view.character_presenter.jump_requested and body.direction == Vector2.ZERO and not body.jump_requested,
		"Finishing the reveal clears queued keys and jump before ordinary input resumes.")
	verify(view.model == null and view.request_sequence == 0,
		"Reveal boundary release constructs no live Model and submits no gameplay request.")
	# Let the stopped audio playback release its stream before this short-lived tree exits.
	await create_timer(0.4).timeout
	free_control_view(view)
	await process_frame
	finish_checks()

func check_manager_controls() -> void:
	var view := control_view()
	var body = view.actor_world.bodies.P
	view.manager_log_layer = CanvasLayer.new()
	view.add_child(view.manager_log_layer)
	for expected_open in [true, false]:
		body.set_control(Vector2.RIGHT, true)
		body.velocity = Vector3(3.0, 2.0, 0.0)
		view.character_presenter.held_keys[KEY_W] = true
		view.character_presenter.jump_requested = true
		view._toggle_manager_log()
		verify(view.manager_log_open == expected_open and body.direction == Vector2.ZERO \
			and not body.jump_requested and body.velocity.x == 0.0 and body.velocity.y == 2.0 \
			and view.character_presenter.held_keys.is_empty() and not view.character_presenter.jump_requested,
			"Opening and closing the work log release motion and queued keys while preserving vertical physics.")
	verify(view.model == null and view.request_sequence == 0,
		"Work-log boundary release constructs no Model and submits no gameplay request.")
	free_control_view(view)
	finish_checks()

class AckView extends SharedOpening:
	var advice := ""
	func _refresh_ui() -> void:
		pass
	func _message(words: String, _refused: bool = false) -> void:
		advice = words

class AreaView extends FooterView:
	var requests: Array = []
	func _update_cursor() -> void:
		pass
	func issue(action: Dictionary) -> Dictionary:
		requests.append(action.duplicate(true))
		return {"accepted": false, "reason": "view-only"}
	func _refresh_ui() -> void:
		pass
	func _message(_words: String, _refused: bool = false) -> void:
		pass

func check_foundation_area_input() -> void:
	var view := AreaView.new()
	view.state = first_target_fixture()
	view.mode = "foundation"
	view.foundation_area_mode = true
	view.foundation_level = 8
	view._world_click(Vector2i(60, 20))
	verify(view.requests.is_empty() and view.foundation_area_started,
		"Choosing the first area corner sends no construction request.")
	view._world_click(Vector2i(62, 21))
	verify(view.requests == [{"action": "place_foundations", "cell": [60, 20], "end_cell": [62, 21], "level": 8}]
		and not view.foundation_area_started, "The second corner sends exactly one absolute-height rectangle request.")
	view._world_click(Vector2i(10, 10))
	view._select_tool("inspect")
	verify(not view.foundation_area_started and view.requests.size() == 1, "Changing tool cancels an unsubmitted area.")
	view.mode = "foundation"
	view.foundation_area_mode = false
	view._world_click(Vector2i(10, 10))
	verify(view.requests.back() == {"action": "place_foundation", "cell": [10, 10], "level": 8},
		"Single-tile construction retains its distinct native request.")
	view.free()

func check_foundation_view() -> void:
	# Read-only world geometry without Model, ActorWorld, Session or input.
	# This exercises the pointer path also inherited by shared clients.
	root.size = Vector2i(1280, 800)
	check_foundation_area_input()
	var view := FooterView.new()
	view.state = first_target_fixture()
	view.state.options["foundations"] = true
	view.state.part_kits.P["foundation"] = 24
	view.state["links"] = []
	root.add_child(view)
	view._build_world()
	verify(view.get_node_or_null("GuidedPlacementHint") == null,
		"The native worksite has no floating ore label over the collector target.")
	view._build_interface()
	view._refresh_guided_tools()
	for _frame in range(3):
		await physics_frame
		await process_frame
	verify(view.model == null and view.actor_world == null, "Client picking creates no authority or local physical character.")
	var terrain_point := Vector3(8.25, Opening.ProductionEnvironment.Surface.height_at(8.25, 3.3), 3.3)
	var screen := view.camera.unproject_position(terrain_point)
	verify(view._screen_cell(screen) == Vector2i(5, 2), "The client requests a tile beyond the retired build rectangle.")
	view.mode = "foundation"
	view.foundation_level = 5
	var upper_point := Vector3(8.25, 5 * Opening.Geometry.HEIGHT_STEP, 3.3)
	verify(view._screen_cell(view.camera.unproject_position(upper_point)) == Vector2i(5, 2),
		"The selected absolute height maps to the same global tile without a terrain collider.")
	view.foundation_level = 0
	view.state["foundations"] = {
		"left": {"cell": [5, 2], "level": 1, "generation": 1},
		"right": {"cell": [6, 2], "level": 1, "generation": 2},
		"ore-floor": {"cell": [0, 1], "level": 4, "generation": 3}}
	view._rebuild_machines()
	for _frame in range(3):
		await physics_frame
		await process_frame
	var top_point := Vector3(8.25, Opening.Geometry.HEIGHT_STEP, 3.3)
	var top_screen := view.camera.unproject_position(top_point)
	verify(view._screen_cell(top_screen) == Vector2i(5, 2) and view._screen_entity(top_screen) == "left",
		"A projected foundation remains pickable at its real top height without ActorWorld.")
	view.mode = "collector"
	var deposit_floor := Vector3(0.0, 4 * Opening.Geometry.HEIGHT_STEP, Opening.Geometry.PITCH)
	var deposit_screen := view.camera.unproject_position(deposit_floor)
	verify(view._screen_cell(deposit_screen) == Vector2i(0, 1)
		and view._construction_level(Vector2i(0, 1)) == 4,
		"Pointing at a foundation above the deposit selects its supported collector height.")
	view.mode = "belt"
	verify(view._construction_level(Vector2i(5, 2)) == 1 and view._construction_level(Vector2i(6, 2)) == 1,
		"Independent projected surfaces select the same machine height.")
	view.mode = "wheel"
	view._adjust_foundation_level(1)
	verify(view.wheel_level == 8, "Wheel elevation advances one whole transmission tile.")
	view._adjust_foundation_level(-1)
	verify(view.wheel_level == 4, "Wheel elevation returns to the aligned starting tile.")
	view.mode = "foundation"
	view._refresh_guided_tools()
	view._adjust_foundation_level(1)
	await settle_footer()
	verify(view.foundation_level == 2 and view.foundation_level_controls.visible
		and is_equal_approx(Opening.Geometry.FOUNDATION_HEIGHT_UNITS * Opening.Geometry.HEIGHT_STEP,
			Opening.Geometry.FOUNDATION_DEPTH),
		"One ordinary height change places the next foundation exactly one block thickness above the previous top.")
	view._adjust_foundation_level(1)
	verify(view.foundation_level == 4 and view.foundation_level_label.text == "Factory floor · 1.65 m",
		"Two ordinary height changes reach the whole-tile machine floor.")
	view.foundation_steps_toggle.button_pressed = true
	view._adjust_foundation_level(-1)
	verify(view.foundation_level == 3 and view.foundation_level_label.text.begins_with("Access step"),
		"Explicit access steps use the same quarter-height denominator for traversal.")
	view.foundation_steps_toggle.button_pressed = false
	verify(view.foundation_level == 4 and not view.foundation_steps and not view.foundation_area_started,
		"Leaving step mode snaps the selected height without moving an existing surface.")
	verify(view.state.foundations.left.level == 1 and view.state.foundations.right.level == 1,
		"The height controls do not migrate or move previously built foundations.")
	var bounds: Rect2 = view.build_column.get_parent().get_global_rect()
	verify(root.get_visible_rect().encloses(bounds), "The expanded foundation controls fit the viewport.")
	verify(view.model == null and view.actor_world == null, "All pointer and UI observations stay read-only.")
	var ack := AckView.new()
	ack.session = SessionStub.new()
	ack.state = view.state.duplicate(true)
	ack.state.merge({"context": "view-only", "revision": 1, "order": 1})
	ack.pending_actions["foundation-ack"] = {"action": {"action": "place_foundation"},
		"outcome": {"accepted": true, "context": "view-only", "revision": 1, "order": 1, "entity": "left"}}
	ack._settle_pending()
	verify(ack.selected == "left" and ack.pending_actions.is_empty() and ack.model == null,
		"A current shared foundation acknowledgement selects the confirmed surface without a client authority.")
	verify(ack._material_refusal_message({"reason": "invalid_area"}, "missing advice").begins_with("Choose a rectangle"),
		"Shared refusal advice explains the recovery action in ordinary language.")
	verify("Access steps off" in ack._material_refusal_message({"reason": "unaligned_elevation"}, "missing advice"),
		"Both shared and ordinary views explain how to align a machine with transmission tiles.")
	ack.free()
	view.free()
	finish_checks()

func settle_footer() -> void:
	for _frame in range(4):
		await process_frame

func check_shared_manager_log() -> void:
	var source := NativeModel.new("shared-manager-view-fixture", ["P"], true)
	verify(source.boot_result.get("accepted", false), "A native arrival projection is available for the detached shared log view.")
	if not source.boot_result.get("accepted", false):
		finish_checks()
		return
	var view := SharedFooterView.new()
	view.client = "P"
	view.session = SessionStub.new()
	view.state = source.projection()
	view.state.actors.P.ready = true
	var unchanged: Dictionary = view.state.duplicate(true)
	root.add_child(view)
	view._build_world()
	view._build_interface()
	view._refresh_ui()
	verify("Gather 5 timber and 4 copper pieces" in view.manager_log_current.text,
		"A confirmed shared arrival shows the live material cue in its replayable manager log.")
	var adjusted: Dictionary = unchanged.duplicate(true)
	adjusted.component_recipes.hand_crank.timber = 4
	adjusted.cargo.P.timber = 1
	view.state = adjusted
	view._refresh_ui()
	verify("Gather 6 timber and 4 copper pieces" in view.manager_log_current.text,
		"The shared cue reads projected recipe costs and accounts for material already carried.")
	view.state = unchanged
	view._refresh_ui()
	verify("first copper plate" in view._material_refusal_message({"reason": "first_plate_required"}, "missing advice"),
		"A shared worker sees the carried-plate prerequisite instead of a native reason code.")
	view.session.ready = false
	view._refresh_ui()
	verify(view.manager_log_current.text.ends_with("Reconnect to continue."),
		"A disconnected shared view replaces its stale work cue with reconnect guidance.")
	view.session.ready = true
	view.pending_actions["pending-fixture"] = {"action": {"action": "craft_component"}, "outcome": {}}
	view._refresh_ui()
	verify(view.manager_log_current.text.ends_with("Waiting for the server decision."),
		"A pending shared command does not present its unconfirmed material result as the next action.")
	view.pending_actions.clear()
	view._refresh_ui()
	view.manager_log_button.pressed.emit()
	verify(view.manager_log_open and view.manager_log_layer.visible and view.state == unchanged
		and view.model == null and view.request_sequence == 0,
		"The shared work log replays without creating a client authority or sending a request.")
	view._toggle_manager_log()
	verify(not view.manager_log_open and not view.manager_log_layer.visible,
		"A shared worker can close the work log and return to the confirmed site.")
	view.session = null
	view.free()
	finish_checks()

func check_channel_hotbar_icons() -> void:
	root.size = Vector2i(1280, 800)
	root.gui_embed_subwindows = true
	var snapshot := first_target_fixture()
	snapshot.hand_sources = {}
	snapshot.first_plate_unlock = true
	snapshot.workshop_completed_actors = ["P"]
	snapshot.cargo = {"P": {"components": {
		"channel_narrow_x": 1, "channel_narrow_z": 1,
		"channel_broad_x": 1, "channel_broad_z": 1}}}
	var view := FooterView.new()
	view.client = "P"
	view.state = snapshot
	view.workshop_completion_observed = true
	root.add_child(view)
	view._build_interface()
	view._refresh_guided_tools()
	var icon_paths := {}
	for kind in ["channel_narrow_x", "channel_narrow_z", "channel_broad_x", "channel_broad_z"]:
		var button: Button = view.building_hotbar.component_buttons[kind]
		verify(button.visible and button.icon != null and button.focus_mode == Control.FOCUS_ALL
			and button.tooltip_text.contains("1 carried") and button.accessibility_name.contains("assign to hotbar"),
			"A carried %s channel has a usable icon tile and keyboard description." % kind)
		if button.icon != null:
			icon_paths[button.icon.resource_path] = true
	verify(icon_paths.size() == 4, "Narrow, broad, X and Z channel kits have distinct directional glyphs.")
	view.building_hotbar.open_catalog()
	await settle_footer()
	verify(view.building_hotbar.catalog.visible, "The completed workshop can open its channel inventory.")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--channel-icon-normal-screenshot="):
			view.building_hotbar.inventory_scroll.scroll_vertical = 10000
			await settle_footer()
			verify(root.get_texture().get_image().save_png(
				argument.trim_prefix("--channel-icon-normal-screenshot=")) == OK,
				"Retain the ordinary channel kit inventory at 1280x800.")
		if argument.begins_with("--channel-icon-narrow-screenshot="):
			view.building_hotbar._close_catalog()
			await settle_footer()
			root.size = Vector2i(900, 600)
			view.building_hotbar.open_catalog()
			view.building_hotbar.inventory_scroll.scroll_vertical = 10000
			await settle_footer()
			verify(view.building_hotbar.catalog.visible and root.get_texture().get_image().save_png(
				argument.trim_prefix("--channel-icon-narrow-screenshot=")) == OK,
				"Retain the ordinary channel kit inventory at 900x600.")
	view.free()
	finish_checks()

func check_slide_manager_cue() -> void:
	root.size = Vector2i(1280, 800)
	root.gui_embed_subwindows = true
	var snapshot := first_target_fixture()
	snapshot.hand_sources = {}
	snapshot.cargo = {"P": {"raw": 0, "products": 0, "components": {}}}
	snapshot.workshop_completed_actors = []
	snapshot.guided_press_assemblies = []
	snapshot.sliding_press_assemblies = [{"status": "unpowered", "parts": {"slide": "slide"}}]
	var view := FooterView.new()
	view.client = "P"
	view.state = snapshot
	root.add_child(view)
	view._build_interface()
	view._refresh_guided_tools()
	view._refresh_manager_log()
	verify(not view.goal_label.text.contains("Open the working press"),
		"An unpowered slide candidate does not claim that the first press is ready.")
	view.state.first_plate_unlock = true
	view.state.cargo.P.timber = 3
	view.state.cargo.P.raw = 4
	view._refresh_guided_tools()
	view._refresh_manager_log()
	verify(view.goal_label.text.contains("Use Build [B] to craft and fit press parts from carried stock")
		and not view.goal_label.text.contains("Craft anvil, flat head"),
		"Carried stock reveals the recipe grid without prescribing a fixed four-part checklist.")
	view.state.sliding_press_assemblies[0].status = "ready"
	view._refresh_guided_tools()
	view._refresh_manager_log()
	verify(view.goal_label.text.contains("Craft a hand crank [B]")
		and view.manager_log_current.text.ends_with(
			"Craft a hand crank [B], fit it at a slide input, then open the press [E]."),
		"A geometrically ready slide without a crank asks for the missing portable input.")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--slide-missing-crank-screenshot="):
			root.size = Vector2i(900, 600)
			for _frame in range(12):
				await process_frame
			verify(root.get_texture().get_image().save_png(
				argument.trim_prefix("--slide-missing-crank-screenshot=")) == OK,
				"Retain the narrow ordinary cue before the slide has a crank.")
			root.size = Vector2i(1280, 800)
	view.state.cargo.P.components.hand_crank = 1
	view._refresh_guided_tools()
	view._refresh_manager_log()
	verify(view.goal_label.text.contains("Fit your carried crank at a slide input [B]")
		and not view.goal_label.text.contains("Craft a hand crank"),
		"A carried crank is fitted rather than crafted again.")
	view.state.cargo.P.components.hand_crank = 0
	view.state.crank_items = {"crank-1": {"holder": "", "attached_to": "slide", "port": [1, 2, 0]}}
	view._refresh_guided_tools()
	view._refresh_manager_log()
	verify(view.goal_label.text.contains("Open the fitted press [E]. Move copper to the workbed, then point at the crank and hold E.")
		and view.manager_log_current.text.ends_with("Open the fitted press [E]. Move copper to the workbed, then point at the crank and hold E."),
		"The ordinary first-shift cue and replayable log recognize a ready slide with its fitted crank.")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--slide-manager-screenshot="):
			for _frame in range(12):
				await process_frame
			verify(root.get_texture().get_image().save_png(argument.trim_prefix("--slide-manager-screenshot=")) == OK,
				"Retain the ordinary first-shift cue over a ready slide projection.")
	var shared := SharedFooterView.new()
	shared.client = "P"
	shared.session = SessionStub.new()
	shared.state = view.state.duplicate(true)
	root.add_child(shared)
	shared._build_interface()
	shared._refresh_guided_tools()
	shared._refresh_manager_log()
	verify(shared.goal_label.text.contains("Open the fitted press [E]. Move copper to the workbed, then point at the crank and hold E.")
		and shared.manager_log_current.text.ends_with("Open the fitted press [E]. Move copper to the workbed, then point at the crank and hold E."),
		"The shared worker receives the same ready-slide cue without creating local authority.")
	view.state.sliding_press_assemblies[0].open_feeds = [
		{"entry": [-1, 0, 0], "exit": [1, 0, 0]},
		{"entry": [3, 0, 0], "exit": [2, 0, 0]}]
	view.state.sliding_press_assemblies[0].selected_exit = [1, 0, 0]
	view.state.dropped_material = [{"center": [9, 0, 0], "products": 1}]
	view._refresh_guided_tools()
	verify(view.goal_label.text.contains("Move copper to the workbed"),
		"A plate elsewhere in the world does not replace the press feed cue.")
	view.state.dropped_material.append({"center": [1, 0, 0], "products": 1})
	shared.state = view.state.duplicate(true)
	view._refresh_guided_tools()
	view._refresh_manager_log()
	shared._refresh_guided_tools()
	shared._refresh_manager_log()
	verify(view.goal_label.text.contains("Plate at outlet. Open the press [E], then collect it [P].")
		and view.manager_log_current.text.ends_with("Plate at outlet. Open the press [E], then collect it [P].")
		and shared.goal_label.text == view.goal_label.text
		and shared.manager_log_current.text == view.manager_log_current.text,
		"Ordinary and shared first-shift cues guide pickup of the confirmed slide outlet plate.")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--slide-outlet-cue-screenshot="):
			shared.arrival_gameplay_canvas.visible = false
			for _frame in range(12):
				await process_frame
			verify(root.get_texture().get_image().save_png(
				argument.trim_prefix("--slide-outlet-cue-screenshot=")) == OK,
				"Retain the ordinary outlet-pickup cue as passive pixels.")
		if argument.begins_with("--slide-outlet-cue-narrow-screenshot="):
			shared.arrival_gameplay_canvas.visible = false
			root.size = Vector2i(900, 600)
			for _frame in range(12):
				await process_frame
			verify(root.get_texture().get_image().save_png(
				argument.trim_prefix("--slide-outlet-cue-narrow-screenshot=")) == OK,
				"Retain the outlet-pickup cue in the narrow ordinary viewport.")
			root.size = Vector2i(1280, 800)
	view.state.sliding_press_assemblies[0].selected_exit = [2, 0, 0]
	view._refresh_guided_tools()
	verify(view.goal_label.text.contains("Move copper to the workbed"),
		"The cue follows the native selected exit rather than an occupied alternate route.")
	view.state.dropped_material.clear()
	view.state.first_plate_unlock = true
	view.state.placed_components = {"anvil": {"component": "anvil", "center": [0, 0, 0]},
		"head": {"component": "flat_head", "center": [0, 1, 0]},
		"slide": {"component": "wooden_slide", "center": [0, 2, 0]}}
	view.state.sliding_press_assemblies[0].status = "blocked_feed"
	shared.state = view.state.duplicate(true)
	view._refresh_guided_tools()
	view._refresh_manager_log()
	shared._refresh_guided_tools()
	shared._refresh_manager_log()
	verify(view.goal_label.text.contains("Clear an X-side feed path [F]")
		and not view.goal_label.text.contains("Craft and place")
		and view.manager_log_current.text.ends_with("Clear an X-side feed path [F], then open the press [E]."),
		"A fitted first-plate slide with native blocked feed gives the obstruction action, not another recipe.")
	verify(shared.goal_label.text == view.goal_label.text
		and shared.manager_log_current.text == view.manager_log_current.text,
		"The shared worker receives the same blocked-feed action without creating local authority.")
	view.state.sliding_press_assemblies[0].status = "unpowered"
	shared.state.sliding_press_assemblies[0].status = "unpowered"
	view._refresh_guided_tools()
	view._refresh_manager_log()
	shared._refresh_guided_tools()
	shared._refresh_manager_log()
	verify(view.goal_label.text.contains("Inspect placed parts [E]")
		and not view.goal_label.text.contains("Craft anvil, flat head")
		and shared.manager_log_current.text == view.manager_log_current.text,
		"Partial press work points to the placed parts without ordering a fixed four-part list.")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--slide-partial-screenshot="):
			shared.arrival_gameplay_canvas.visible = false
			for _frame in range(12):
				await process_frame
			verify(root.get_texture().get_image().save_png(
				argument.trim_prefix("--slide-partial-screenshot=")) == OK,
				"Retain the ordinary partial-press cue without the old assembly checklist.")
	view.state.sliding_press_assemblies[0].status = "ready"
	shared.state.sliding_press_assemblies[0].status = "ready"
	view._refresh_guided_tools()
	view._refresh_manager_log()
	shared._refresh_guided_tools()
	shared._refresh_manager_log()
	verify(view.goal_label.text.contains("Open the fitted press [E]. Move copper to the workbed, then point at the crank and hold E.")
		and shared.goal_label.text == view.goal_label.text
		and shared.manager_log_current.text == view.manager_log_current.text,
		"Clearing one native feed route restores the first-plate press cue for ordinary and shared workers.")
	shared.session = null
	shared.free()
	view.free()
	finish_checks()

func check_inventory_goal_view() -> void:
	root.size = Vector2i(1280, 800)
	var source := NativeModel.new("inventory-goal-view-fixture", ["P", "Q"], true)
	verify(source.boot_result.get("accepted", false),
		"A native arrival projection supplies the local cargo for the workshop goal.")
	if not source.boot_result.get("accepted", false):
		finish_checks()
		return
	var view := FooterView.new()
	view.model = source
	view.client = "P"
	view.state = source.projection()
	root.add_child(view)
	view._build_world()
	view._build_interface()
	view._refresh_ui()
	verify(view.get_node_or_null("ShipmentMarker") == null
		and "FORM A PLATE · KEEP IT" in view.goal_label.text
		and not view.manager_log_completion_entry.visible,
		"Arrival has no freight marker, and the first workshop waits for a carried plate.")
	var shared := SharedFooterView.new()
	shared.state = view.state.duplicate(true)
	shared.client = "Q"
	shared.session = SessionStub.new()
	root.add_child(shared)
	shared._build_world()
	shared._build_interface()
	shared._refresh_ui()
	view.state = view.state.duplicate(true)
	view.state.cargo.P.products = 1
	view.state.workshop_completed_actors = ["P"]
	view._refresh_ui()
	shared.state = view.state.duplicate(true)
	shared._refresh_ui()
	verify("FIRST WORKSHOP  /  COMPLETE" in view.objective_heading.text
		and "Open Work log [J] for the collector project" in view.goal_label.text
		and view.manager_log_completion_entry.visible
		and view.manager_log_projects.visible
		and "finite ore collector" in (view.manager_log_projects.get_child(0).get_child(1) as Label).text
		and view.workshop_completion_cue_count == 1
		and "Plate collected" in view.status_label.text,
		"One native-projected product in the local inventory completes the first workshop.")
	verify("FORM A PLATE · KEEP IT" in shared.goal_label.text
		and not shared.manager_log_completion_entry.visible
		and shared.workshop_completion_cue_count == 0,
		"Another actor's product does not complete this actor's workshop cue.")
	view._refresh_ui()
	verify(view.workshop_completion_cue_count == 1,
		"Refresh does not replay the completion sound.")
	view.state.cargo.P.products = 0
	view._refresh_ui()
	verify("FIRST WORKSHOP  /  COMPLETE" in view.objective_heading.text
		and "Open Work log [J]" in view.goal_label.text
		and not view.goal_label.text.contains("PLATE IN INVENTORY")
		and view.manager_log_completion_entry.visible
		and view.manager_log_completion_entry.text.contains("You collected your first formed plate")
		and not view.manager_log_completion_entry.text.contains("is in your inventory")
		and view.workshop_completion_cue_count == 1,
		"Using the plate later keeps a truthful historical completion entry without claiming current custody.")
	var reopened := FooterView.new()
	reopened.model = source
	reopened.client = "P"
	reopened.state = view.state.duplicate(true)
	root.add_child(reopened)
	reopened._build_world()
	reopened._build_interface()
	reopened._refresh_ui()
	verify(reopened.manager_log_completion_entry.visible
		and "Open Work log [J]" in reopened.goal_label.text
		and reopened.manager_log_completion_entry.text == view.manager_log_completion_entry.text
		and reopened.workshop_completion_cue_count == 0,
		"A reopened projection shows completion without replaying the acquisition sound.")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--inventory-goal-screenshot="):
			shared.arrival_gameplay_canvas.visible = false
			reopened.arrival_gameplay_canvas.visible = false
			for _frame in range(12):
				await process_frame
			verify(root.get_texture().get_image().save_png(argument.trim_prefix("--inventory-goal-screenshot=")) == OK,
				"The completed workshop view can be retained as passive pixels.")
		if argument.begins_with("--manager-complete-log-screenshot="):
			shared.arrival_gameplay_canvas.visible = false
			view.arrival_gameplay_canvas.visible = false
			if not reopened.manager_log_open:
				reopened._toggle_manager_log()
			for _frame in range(12):
				await process_frame
			verify(reopened.manager_log_open and reopened.manager_log_layer.visible
				and root.get_texture().get_image().save_png(
					argument.trim_prefix("--manager-complete-log-screenshot=")) == OK,
				"The replayed completion entry remains visible as passive pixels after plate use.")
		if argument.begins_with("--manager-complete-log-narrow-screenshot="):
			shared.arrival_gameplay_canvas.visible = false
			view.arrival_gameplay_canvas.visible = false
			root.size = Vector2i(900, 600)
			if not reopened.manager_log_open:
				reopened._toggle_manager_log()
			reopened._refresh_manager_log()
			for _frame in range(12):
				await process_frame
			var log_scroll := reopened.manager_log_panel.get_child(0) as ScrollContainer
			log_scroll.scroll_vertical = 10000
			for _frame in range(4):
				await process_frame
			verify(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(
				reopened.manager_log_panel.get_global_rect())
				and root.get_texture().get_image().save_png(
					argument.trim_prefix("--manager-complete-log-narrow-screenshot=")) == OK,
				"The replayed completion entry fits the narrow viewport after plate use.")
	reopened.free()
	shared.free()
	view.free()
	finish_checks()

func check_foundation_inspector() -> void:
	for shared_profile in [false, true]:
		var view = SharedFooterView.new() if shared_profile else FooterView.new()
		if shared_profile:
			view.session = SessionStub.new()
		view.state = first_target_fixture()
		view.state.options.foundations = true
		view.state.foundations = {"step-a": {"cell": [5, 2], "level": 2}, "step-b": {"cell": [6, 2], "level": 2}}
		var before: Dictionary = view.state.duplicate(true)
		root.add_child(view)
		view._build_interface()
		view.object_menu.popup_hide.disconnect(view._on_object_menu_closed)
		view._refresh_guided_tools()
		await settle_footer()
		verify(not view.object_menu.visible and not view.inspector.is_visible_in_tree(),
			"An idle foundation worksite leaves its object details off the game view.")
		view.selected = "step-a"
		view.object_menu_target = "step-a"
		view.object_menu.popup_centered(Vector2i(500, 400))
		view._refresh_guided_tools()
		await settle_footer()
		verify(view.object_menu.visible and view.selected == "step-a"
			and view.inspector.is_visible_in_tree() and view.remove_button.is_visible_in_tree()
			and not view.retrieve_button.visible and not view.object_menu_operations.visible,
			"E opens only the pointed foundation's details and dismantling action.")
		verify(not view.stock_label.is_visible_in_tree(),
			"Foundation inspection does not expose generic worksite counters.")
		view.object_menu.hide()
		view.selected = ""
		view._refresh_guided_tools()
		await settle_footer()
		verify(not view.object_menu.visible and view.selected.is_empty(),
			"Closing the panel releases its selected target.")
		view._open_pause_menu()
		verify(view.pause_menu.visible and view.stock_label.is_visible_in_tree(),
			"Escape menu owns the generic worksite counters.")
		view.pause_menu.hide()
		view.state.actors.P.ready = false
		verify(not view._can_control_character(), "An unready actor cannot use object interactions.")
		view.state.actors.P.ready = true
		view.explanation_open = true
		verify(not view._can_control_character(), "Help prevents object interactions.")
		view.explanation_open = false
		verify(view.state == before and view.model == null and view.actor_world == null
			and view.request_sequence == 0, "Foundation inspection creates no authority or request.")
		view.state.entities = {"wheel-a": {"kind": "wheel", "cell": [-2, 1]},
			"press-a": {"kind": "processor", "cell": [3, 1]}}
		var built_before: Dictionary = view.state.duplicate(true)
		view._refresh_guided_tools()
		await settle_footer()
		verify(not view.object_menu.visible and not view.inspector.is_visible_in_tree(),
			"Built machinery still leaves the idle game view unobstructed.")
		view.selected = "press-a"
		view.object_menu_target = "press-a"
		view.object_menu.popup_centered(Vector2i(500, 400))
		view._refresh_guided_tools()
		await settle_footer()
		verify(view.object_menu.visible and view.inspector.is_visible_in_tree()
			and view.retrieve_button.is_visible_in_tree() and view.remove_button.is_visible_in_tree(),
			"The pointed press keeps collection and dismantling inside its E panel.")
		view.object_menu.hide()
		await settle_footer()
		view.selected = "wheel-a"
		view.object_menu_target = "wheel-a"
		view.object_menu.popup_centered(Vector2i(500, 400))
		view._refresh_guided_tools()
		await settle_footer()
		verify(view.object_menu.visible and view.remove_button.is_visible_in_tree()
			and not view.retrieve_button.visible,
			"The pointed wheel offers dismantling without a plate collection control.")
		view.object_menu.hide()
		verify(view.state == built_before and view.model == null and view.actor_world == null and view.request_sequence == 0,
			"Object panels never create an authority, physical body or gameplay request.")
		await settle_footer()
		if shared_profile:
			view.session = null
		view.free()
	finish_checks()

func check_close_camera_footer(view) -> void:
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	view.camera.fov = 45.0
	view.focus = Vector3(0, 1.18, 0)
	view.distance = 4.0
	view.orbit_pitch = 0.35
	view.orbit_yaw = 0.68
	view._message("Worksite reopened in this session. Your original save is kept.")
	view._update_camera()
	await settle_footer()
	var bounds: Rect2 = view.status_footer.get_global_rect()
	verify(is_equal_approx(bounds.position.y, 18.0)
		and bounds.encloses(view.status_label.get_global_rect())
		and bounds.encloses(view.controls_label.get_global_rect()),
		"Close third-person guidance stays readable in the upper lane between the side panels.")
	for height in [-0.02, 0.45, 0.9, 1.8]:
		var point: Vector2 = view.camera.unproject_position(Vector3(0, height, 0))
		verify(not bounds.grow(8.0).has_point(point),
			"Close-view guidance leaves the worker's feet, knees, hips and head clear.")
	view._message("Cannot place the press here. Build a factory floor at this height and leave its outlet clear.", true)
	await settle_footer()
	verify(view.status_label.visible and view.status_refused
		and view.status_footer.get_global_rect().encloses(view.status_label.get_global_rect()),
		"Moving the panel preserves the complete actionable refusal.")
	view.distance = 14.0
	view._update_camera()
	await settle_footer()
	verify(is_equal_approx(view.status_footer.get_global_rect().end.y, view.building_hotbar.position.y - 12.0),
		"Zooming out returns the guidance above the hotbar.")
	view.distance = 4.0
	view.explanation_open = true
	view._update_camera()
	await settle_footer()
	verify(is_equal_approx(view.status_footer.get_global_rect().end.y, view.building_hotbar.position.y - 12.0),
		"Help retains the upper reading lane instead of sharing it with the status panel.")
	verify(view.model == null and view.actor_world == null and view.request_sequence == 0,
		"Camera and guidance layout create no gameplay authority or requests.")

func check_footer_layout() -> void:
	root.size = Vector2i(1280, 800)
	var view := FooterView.new()
	view.state = first_target_fixture()
	root.add_child(view)
	view._build_interface()
	view._refresh_guided_tools()
	var intro := "Choose Collector [1] on the ore-colored ground beside the rock."
	view._message(intro)
	await settle_footer()
	var panel: Control = view.status_label.get_parent().get_parent()
	var short_bounds: Rect2 = panel.get_global_rect()
	verify(not view.status_label.visible, "The fresh native footer does not repeat the visible collector instruction.")
	verify(short_bounds.size.y < 64.0 and panel.get_global_rect().encloses(view.controls_label.get_global_rect()),
		"The fresh controls fit a compact strip instead of reserving the old two-row banner.")
	verify(short_bounds.size.x < 952.0, "The fresh strip removes blank width while fitting every control hint.")
	verify(is_equal_approx(short_bounds.end.y, view.building_hotbar.position.y - 12.0), "The compact footer stays above the hotbar.")
	view._message("")
	await settle_footer()
	verify(not view.status_label.visible and view.controls_label.is_visible_in_tree() \
		and is_equal_approx(panel.get_global_rect().size.y, short_bounds.size.y),
		"An empty event status reserves no row while the control legend remains readable.")
	view._message(intro)
	root.size = Vector2i(1600, 900)
	await settle_footer()
	var wide_bounds: Rect2 = panel.get_global_rect()
	verify(is_equal_approx(wide_bounds.end.x, 1582.0) and is_equal_approx(wide_bounds.end.y, view.building_hotbar.position.y - 12.0) \
		and is_equal_approx(wide_bounds.size.x, short_bounds.size.x) and wide_bounds.encloses(view.controls_label.get_global_rect()),
		"A wider viewport preserves the compact controls and both outer margins.")
	root.size = Vector2i(1280, 800)
	await settle_footer()
	view._message(intro, true)
	await settle_footer()
	verify(view.status_label.visible, "Even matching introduction text remains visible when it is an explicit refusal.")
	var refusal := "Cannot place the collector here. Approach the ore deposit and leave room for the material outlet. "
	view._message(refusal.repeat(7), true)
	await settle_footer()
	var long_bounds: Rect2 = panel.get_global_rect()
	verify(view.status_label.visible and view.status_label.get_line_count() > 1 and view.status_label.text == refusal.repeat(7),
		"A long refusal remains complete and wraps across multiple lines.")
	verify(long_bounds.size.y > short_bounds.size.y and long_bounds.position.y >= 0.0 and is_equal_approx(long_bounds.end.y, view.building_hotbar.position.y - 12.0) \
		and long_bounds.encloses(view.status_label.get_global_rect()) and long_bounds.encloses(view.controls_label.get_global_rect()),
		"The footer grows upward around a refusal while keeping both rows inside the viewport.")
	view._message(intro)
	view._open_pause_menu()
	view._refresh_guided_tools()
	await settle_footer()
	verify(view.status_label.visible, "The worksite menu keeps the explicit introductory status available.")
	view.pause_menu.hide()
	view.building_hotbar.catalog.show()
	view._refresh_guided_tools()
	await settle_footer()
	verify(view.status_label.visible, "The catalog retains the full status row.")
	view.building_hotbar.catalog.hide()
	view.explanation_open = true
	view._refresh_guided_tools()
	await settle_footer()
	verify(view.status_label.visible, "Help keeps the explicit status available.")
	view.explanation_open = false
	view._refresh_guided_tools(false)
	await settle_footer()
	verify(view.status_label.visible, "An unavailable confirmed snapshot never hides its status row.")
	view._refresh_guided_tools()
	view._message("Worksite reopened in this session. Your original save is kept.")
	await settle_footer()
	verify(view.status_label.visible, "Reopen and recovery outcomes remain visible.")
	view._message(intro)
	await settle_footer()
	verify(not view.status_label.visible and is_equal_approx(panel.get_global_rect().size.y, short_bounds.size.y),
		"Replacing an outcome with the redundant fresh introduction shrinks the strip again.")
	verify(view.model == null and view.actor_world == null and view.request_sequence == 0,
		"Real UI layout never constructs game authority or submits a request.")
	await check_close_camera_footer(view)
	view.free()
	var shared := SharedFooterView.new()
	shared.state = first_target_fixture()
	shared.session = SessionStub.new()
	root.add_child(shared)
	shared._build_interface()
	shared._refresh_guided_tools()
	await check_close_camera_footer(shared)
	shared.session = null
	shared.free()
	var legacy := FooterView.new()
	legacy.legacy_fixture = true
	legacy.state = fixture()
	root.add_child(legacy)
	legacy._build_interface()
	legacy._message(intro)
	await settle_footer()
	var historical: Control = legacy.status_label.get_parent().get_parent()
	verify(legacy.status_label.visible and historical.get_global_rect().encloses(legacy.controls_label.get_global_rect()) \
		and historical.get_global_rect().end.y <= legacy.building_hotbar.position.y - 12.0,
		"Every observation profile uses the current readable layout above the hotbar.")
	legacy.free()
	finish_checks()

class CameraProjection extends RefCounted:
	var snapshot := {"options": {}, "entities": {}, "links": [], "revision": 0}
	func projection() -> Dictionary:
		return snapshot.duplicate(true)
	func is_ready() -> bool:
		return false

class SharedCameraView extends SharedOpening:
	func _refresh_ui() -> void:
		pass

class ZoomView extends Opening:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

class MouseLookView extends ZoomView:
	var capture_allowed := false
	func _wants_mouse_capture() -> bool: return capture_allowed

class MouseLookPresenter extends CharacterPresenter:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass

class SharedZoomView extends SharedOpening:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

class ZoomPresenter extends RefCounted:
	var views: Dictionary = {}

func verify_camera(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		camera_failed = true
		push_error(reason)

func camera_view(shared_profile: bool):
	var view = SharedCameraView.new() if shared_profile else Opening.new()
	var projection := CameraProjection.new()
	view.model = projection
	if shared_profile:
		view.session = projection
	# Match the current empty machine/foundation projection so this detached
	# camera fixture never enters world geometry assembly without a world.
	view.geometry_key = JSON.stringify([{}, [], [], {}])
	view.visual_revision = 0
	return view

func check_camera_profiles() -> void:
	for shared_profile in [false, true]:
		var view = camera_view(shared_profile)
		var projection = view.model
		var original_yaw: float = view.orbit_yaw
		var original_distance: float = view.distance
		var original_focus: Vector3 = view.focus
		view._refresh()
		verify_camera(view.orbit_pitch == 0.82, "An unknown projection does not choose a native camera profile.")
		projection.snapshot.options.native = true
		var facts: Dictionary = projection.snapshot.duplicate(true)
		view._refresh()
		verify_camera(view.orbit_pitch == 0.60, "The first confirmed native projection initializes the camera after deferred arrival.")
		view.orbit_pitch = 0.94
		view._refresh()
		projection.snapshot.options = {}
		view._refresh()
		projection.snapshot.options.native = true
		view._refresh()
		verify_camera(view.orbit_pitch == 0.94, "Further snapshots and reconnect preserve a player's adjusted pitch.")
		verify_camera(view.orbit_yaw == original_yaw and view.distance == original_distance and view.focus == original_focus,
			"Profile initialization preserves yaw, zoom and character-follow focus.")
		verify_camera(projection.snapshot == facts and view.actor_world == null and view.request_sequence == 0,
			"The view does not mutate confirmed facts, create physical authority or submit requests.")
		view.free()
	for legacy_profile in [false, true]:
		var view = camera_view(false)
		var projection = view.model
		projection.snapshot.options = {"native": legacy_profile}
		view.legacy_fixture = legacy_profile
		view._refresh()
		verify_camera(view.orbit_pitch == 0.82, "Historical and nonnative profiles retain their earlier starting pitch.")
		view.free()
	var view = camera_view(true)
	var projection = view.model
	view.orbit_pitch = 1.01
	projection.snapshot.options.native = true
	view._refresh()
	verify_camera(view.orbit_pitch == 1.01, "An already adjusted pitch is preserved when the first native profile arrives.")
	view.free()

func zoom_wheel(view, button: MouseButton, times: int = 1) -> void:
	for _step in range(times):
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = true
		view._unhandled_input(event)

func check_camera_zoom_view(view) -> void:
	view.client = "P"
	view.state = {"actors": {"P": {"ready": true, "position": [2.0, 0.9, 3.0]},
		"Q": {"ready": true, "position": [4.0, 0.9, 3.0]}}}
	view.focus = Vector3(2.0, 1.2, 3.0)
	view.orbit_yaw = 0.68
	view.orbit_pitch = 0.6
	view.distance = 14.0
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	var local := Node3D.new()
	var remote := Node3D.new()
	view.add_child(local)
	view.add_child(remote)
	var presenter := ZoomPresenter.new()
	presenter.views = {"P": local, "Q": remote}
	view.character_presenter = presenter
	root.add_child(view)
	var before: Dictionary = view.state.duplicate(true)
	view._update_camera()
	var back := Vector3(sin(view.orbit_yaw) * cos(view.orbit_pitch),
		sin(view.orbit_pitch), cos(view.orbit_yaw) * cos(view.orbit_pitch))
	verify_camera(view.camera.position.distance_to(view.focus + back * 14.0) < 0.0001 and local.visible,
		"The normal follow camera and local actor begin in third person.")
	zoom_wheel(view, MOUSE_BUTTON_WHEEL_UP, 10)
	verify_camera(view.distance == 4.0 and view.camera.position.distance_to(view.focus + back * 4.0) < 0.0001,
		"The approach preserves the original orbit pose until the near blend.")
	zoom_wheel(view, MOUSE_BUTTON_WHEEL_UP, 3)
	verify_camera(view.distance == 1.0 and view.camera.position.distance_to(
		view.focus + Vector3.UP * 0.2625 + back) < 0.0001 and not local.visible and remote.visible,
		"The near view moves toward eye height without hiding another actor.")
	zoom_wheel(view, MOUSE_BUTTON_WHEEL_UP)
	verify_camera(view.distance == 0.0 and view.camera.position.distance_to(
		view.focus + Vector3.UP * 0.35) < 0.0001 and
		(-view.camera.global_basis.z).distance_to(-back) < 0.0001,
		"The wheel reaches the actor's eye and looks along the orbit ray.")
	view.orbit_pitch = -0.3
	view._update_camera()
	verify_camera((-view.camera.global_basis.z).y > 0.29,
		"The first person view can look above the horizon.")
	zoom_wheel(view, MOUSE_BUTTON_WHEEL_DOWN)
	verify_camera(view.distance == 1.0 and view.orbit_pitch == 0.35 and not local.visible,
		"Zooming out restores a ground-safe pitch before showing the local model.")
	zoom_wheel(view, MOUSE_BUTTON_WHEEL_DOWN)
	verify_camera(view.distance == 2.0 and local.visible and remote.visible,
		"The local model returns as the camera clears it.")
	verify_camera(view.state == before and view.model == null and view.actor_world == null,
		"Camera controls do not move the actor or create construction authority.")
	view.free()

func check_camera_zoom() -> void:
	check_camera_zoom_view(ZoomView.new())
	check_camera_zoom_view(SharedZoomView.new())
	print("OPENING_CAMERA_ZOOM_%s %d" % ["FAIL" if camera_failed else "PASS", checks])
	quit(1 if camera_failed else 0)

func check_mouse_look() -> void:
	var view := MouseLookView.new()
	view.client = "P"
	view.state = {"actors": {"P": {"ready": true}}}
	view.distance = 0.0
	view.orbit_yaw = 0.0
	view.orbit_pitch = 0.0
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	root.add_child(view)
	verify_camera(view._mouse_capture_allowed(true, false),
		"Focused first-person world view requests button-free mouse look.")
	verify_camera(not view._mouse_capture_allowed(false, false)
		and not view._mouse_capture_allowed(true, true),
		"Unfocused windows and active popups cannot capture the pointer.")
	view.pause_menu = PanelContainer.new()
	view.add_child(view.pause_menu)
	verify_camera(not view._mouse_capture_allowed(true, false),
		"The Worksite menu releases the pointer.")
	view.pause_menu.hide()
	view.manager_log_open = true
	verify_camera(not view._mouse_capture_allowed(true, false),
		"The Work log releases the pointer.")
	view.manager_log_open = false
	view.explanation_open = true
	verify_camera(not view._mouse_capture_allowed(true, false),
		"Help releases the pointer.")
	view.explanation_open = false
	view.arrival_reveal_active = true
	verify_camera(not view._mouse_capture_allowed(true, false),
		"The arrival reveal cannot capture the pointer.")
	view.arrival_reveal_active = false
	view.distance = 1.0
	verify_camera(not view._mouse_capture_allowed(true, false),
		"Third-person orbit retains its button-held pointer route.")
	view.distance = 0.0
	view.capture_allowed = true
	view._sync_mouse_capture()
	verify_camera(view.mouse_capture_owned and view.mouse_capture_skip_motion,
		"Entering first person requests capture and arms warp suppression.")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(160, -60)
	view._input(motion)
	verify_camera(view.orbit_yaw == 0.0 and view.orbit_pitch == 0.0,
		"The first relative event after capture cannot jump the camera.")
	view._input(motion)
	verify_camera(is_equal_approx(view.orbit_yaw, -1.12)
		and is_equal_approx(view.orbit_pitch, -0.3),
		"Button-free relative motion rotates the first-person camera.")
	view.capture_allowed = false
	view._sync_mouse_capture()
	verify_camera(not view.mouse_capture_owned and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"Closing world interaction restores a visible cursor.")
	view._input(motion)
	verify_camera(is_equal_approx(view.orbit_yaw, -1.12),
		"Relative motion while a menu owns interaction cannot drift the camera.")
	var presenter := MouseLookPresenter.new()
	presenter.configure(view)
	view.add_child(presenter)
	view.character_presenter = presenter
	var walk := InputEventKey.new()
	walk.keycode = KEY_W
	walk.pressed = true
	presenter._input(walk)
	verify_camera(presenter.held_keys.has(KEY_W),
		"World movement can begin while the world owns input.")
	view.pause_menu.show()
	view._release_character_controls()
	presenter._input(walk)
	var jump := InputEventKey.new()
	jump.keycode = KEY_SPACE
	jump.pressed = true
	presenter._input(jump)
	verify_camera(presenter.held_keys.is_empty() and not presenter.jump_requested,
		"A menu clears held world movement and cannot queue movement or jump keys.")
	view.pause_menu.hide()
	verify_camera(presenter.held_keys.is_empty() and not presenter.jump_requested,
		"Closing the menu cannot resume a previously held world action.")
	view.free()
	print("OPENING_MOUSE_LOOK_%s %d" % ["FAIL" if camera_failed else "PASS", checks])
	quit(1 if camera_failed else 0)

func verify(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(reason)

func finish_checks() -> void:
	print("OPENING_GUIDANCE_CUE_%s %d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)

func nested_failure_control() -> void:
	verify(false, "The explicit negative control must survive its nested return.")

func first_target_fixture() -> Dictionary:
	var snapshot := fixture()
	snapshot.entities.clear()
	snapshot.options.native = true
	snapshot.stock.source = 16
	snapshot.parts.collector = 1
	snapshot.part_kits = {"P": {"collector": 1, "belt": 1, "processor": 1}}
	snapshot.transmission_parts = {}
	return snapshot


func fixture() -> Dictionary:
	return {"entities": {"collector-1": {"kind": "collector", "cell": [0, 1]}},
		"parts": {"collector": 0, "belt": 1, "processor": 1}, "stock": {"output": 0},
		"inventories": {"P": 0}, "actors": {"P": {"ready": true}},
		"options": {"physical": true}}

func check_native_route_report() -> void:
	for view in [Opening.new(), SharedOpening.new()]:
		view.client = "P"
		view.state = {"options": {"native": true}, "inventories": {"P": 0}, "power_enabled": true,
			"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
			"entities": {"collector": {"kind": "collector", "center": [0, 4, 4]},
				"press": {"kind": "processor", "center": [12, 4, 4]}, "wheel": {"kind": "wheel"}},
			"transmission_parts": {"a": {"kind": "shaft", "center": [4, 4, 4], "axis": 2},
				"b": {"kind": "shaft", "center": [8, 4, 4], "axis": 2},
				"c": {"kind": "shaft", "center": [0, 4, 8], "axis": 0},
				"d": {"kind": "shaft", "center": [0, 4, 12], "axis": 0}},
			"belt_spans": {"route": {"from": "a", "to": "b", "slots": [null, null]},
				"diversion": {"from": "c", "to": "d", "slots": [null, null]}},
			"motion": {"collector": {"state": "rotating"}, "press": {"state": "rotating"},
				"a": {"state": "rotating", "numerator": -1}, "c": {"state": "rotating", "numerator": 1}},
			"opening_engineering": {"P": {"schema": 1, "format": "factory-opening-engineering",
				"actor": "P", "known_actor": true, "belt_forward": false}}}
		var kinds := {"collector": true, "processor": true, "wheel": true}
		var routes: Dictionary = view._guided_span_routes()
		verify(routes.physical and not routes.powered, "Native diversion assessment overrides a geometric forward path.")
		var advice: Dictionary = view._guided_step(kinds)
		verify(advice.tool == "drive" and "branch" in advice.text, "The next step explains a possible diverting branch.")
		view.state.opening_engineering.P.belt_forward = true
		verify(view._guided_span_routes().powered, "A valid forward report preserves the working route.")
		view.state.opening_engineering.P.actor = "Q"
		verify(view._guided_span_routes().powered, "A report for another actor cannot change local route advice.")
		view.state.erase("opening_engineering")
		verify(view._guided_span_routes().powered, "A projection without a report retains geometric advice.")
		view.free()

func run_native_route_report() -> void:
	check_native_route_report()
	finish_checks()

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--channel-hotbar-icons-only"):
		call_deferred("check_channel_hotbar_icons")
		return
	if OS.get_cmdline_user_args().has("--slide-manager-cue-only"):
		call_deferred("check_slide_manager_cue")
		return
	if OS.get_cmdline_user_args().has("--inventory-goal-only"):
		call_deferred("check_inventory_goal_view")
		return
	if OS.get_cmdline_user_args().has("--manager-controls-only"):
		call_deferred("check_manager_controls")
		return
	if OS.get_cmdline_user_args().has("--reveal-controls-only"):
		call_deferred("check_reveal_controls")
		return
	if OS.get_cmdline_user_args().has("--route-report-only"):
		run_native_route_report.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--foundation-inspector-only"):
		call_deferred("check_foundation_inspector")
		return
	if OS.get_cmdline_user_args().has("--foundation-view-only"):
		check_foundation_view.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--footer-layout-only"):
		call_deferred("check_footer_layout")
		return
	if OS.get_cmdline_user_args().has("--manager-log-shared-only"):
		call_deferred("check_shared_manager_log")
		return
	if OS.get_cmdline_user_args().has("--camera-profile-only"):
		check_camera_profiles()
		print("OPENING_CAMERA_PROFILE_%s %d" % ["FAIL" if camera_failed else "PASS", checks])
		quit(1 if camera_failed else 0)
		return
	if OS.get_cmdline_user_args().has("--camera-zoom-only"):
		call_deferred("check_camera_zoom")
		return
	if OS.get_cmdline_user_args().has("--mouse-look-only"):
		call_deferred("check_mouse_look")
		return
	if OS.get_cmdline_user_args().has("--verifier-negative-control"):
		nested_failure_control()
		finish_checks()
		return
	check_native_route_report()
	finish_checks()
