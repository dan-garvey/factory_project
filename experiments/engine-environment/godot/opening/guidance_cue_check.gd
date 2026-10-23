extends SceneTree
## Default/camera modes use detached views. Footer mode mounts only real UI
## containers, without a Model, body, network or game world.

const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")
const NativeModel = preload("res://opening/native_model.gd")
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

class FreightActionView extends FooterView:
	var requests: Array[Dictionary] = []
	func issue(action: Dictionary) -> Dictionary:
		requests.append(action.duplicate(true))
		return {"accepted": false, "reason": "view_only"}

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
	verify("Cut timber or ore" in view.manager_log_current.text,
		"A confirmed shared arrival shows the live material cue in its replayable manager log.")
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

func check_freight_beacon_view() -> void:
	var source := NativeModel.new("freight-view-fixture", ["P"], true)
	verify(source.boot_result.get("accepted", false), "The real native arrival supplies a beacon projection.")
	if not source.boot_result.get("accepted", false):
		finish_checks()
		return
	var view := FreightActionView.new()
	view.model = source
	view.client = "P"
	view.state = source.projection()
	root.add_child(view)
	view._build_world()
	view._build_interface()
	view._sync_freight_beacon_visual()
	var beacon: Dictionary = view.state.freight_beacon
	var marker: Label3D = view.freight_beacon_visual.get_node_or_null("ShipmentLabel")
	verify(view.freight_beacon_visual != null and view.freight_beacon_visual.name == "ShipmentMarker"
		and view.freight_beacon_visual.get_meta("freight_beacon") == beacon.id
		and marker != null and marker.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
		"The native beacon has a camera-facing shipment label.")
	verify(view.freight_beacon_visual.find_children("*", "MeshInstance3D", true, false).is_empty(),
		"The unbuilt freight point contains no fabricated plinth, posts or gantry meshes.")
	verify(view.freight_beacon_visual.collision_layer == Opening.Geometry.PICK_LAYER
		and view.freight_beacon_visual.collision_mask == 0,
		"The graphical marker adds only selection, not actor collision or construction authority.")
	var position: Array = beacon.position
	verify(is_equal_approx(view.freight_beacon_visual.position.x, float(position[0]))
		and is_equal_approx(view.freight_beacon_visual.position.z, float(position[2]))
		and beacon.center == [6, 0, 4],
		"The shipment marker retains the native world-space point east of the pod.")
	for _frame in range(3):
		await physics_frame
	view.camera.position = view.freight_beacon_visual.position + Vector3(0, 2.0, 5.0)
	view.camera.look_at(view.freight_beacon_visual.position + Vector3(0, 1.3, 0))
	var hit := view._screen_pick(root.get_visible_rect().size / 2.0)
	verify(not hit.is_empty() and hit.collider == view.freight_beacon_visual,
		"A camera ray selects the actual shipment label's pick target.")
	view.camera.position = view.freight_beacon_visual.position + Vector3(0, 2.5, 5.0)
	view.camera.look_at(view.freight_beacon_visual.position + Vector3(0, 2.5, 0))
	var high_hit := view._screen_pick(root.get_visible_rect().size / 2.0)
	verify(high_hit.is_empty() or high_hit.collider != view.freight_beacon_visual,
		"The removed gantry leaves no invisible tall selection body.")
	view.camera.position = view.freight_beacon_visual.position + Vector3(0, 2.0, 5.0)
	view.camera.look_at(view.freight_beacon_visual.position + Vector3(0, 1.3, 0))
	view.state.actors.P.ready = true
	view.distance = 0.0
	view._open_pointed_machine()
	verify(view.requests == [{"action": "deliver_first_plate", "entity": beacon.id}],
		"E on the pointed receiver requests exactly one native delivery and creates no client stock.")
	view._refresh_ui()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--freight-screenshot="):
			for _frame in range(3):
				await process_frame
			verify(root.get_texture().get_image().save_png(argument.trim_prefix("--freight-screenshot=")) == OK,
				"The passive beacon view can be retained for visual inspection.")
	verify("SHIP ONE PLATE" in view.goal_label.text,
		"The initial Meridian order asks for a shipment while construction remains open.")
	view.state = view.state.duplicate(true)
	view.state.cargo.P.products = 1
	view._sync_freight_beacon_visual()
	view._refresh_ui()
	verify("east freight beacon" in view.goal_label.text,
		"A carried product changes the next cue to a reachable world-space delivery.")
	verify(marker != null and "Ship one plate [E]" in marker.text,
		"A ready actor with a confirmed carried plate sees the shipping action on the marker.")
	var shared := SharedFooterView.new()
	shared.state = view.state.duplicate(true)
	shared.client = "Q"
	shared.session = SessionStub.new()
	root.add_child(shared)
	shared._sync_freight_beacon_visual()
	var remote_label: Label3D = shared.freight_beacon_visual.get_node_or_null("ShipmentLabel")
	verify(remote_label != null and "Form one plate" in remote_label.text,
		"The shared marker cannot borrow another actor's carried product.")
	var original := view.freight_beacon_visual
	view._sync_freight_beacon_visual()
	verify(view.freight_beacon_visual == original and view.freight_beacon_visual.get_node_or_null("ShipmentLabel") == marker,
		"Unchanged refresh preserves the marker and label identities.")
	view.state.freight_beacon.order_complete = true
	view.state.freight_beacon.shipped_products = 1
	view.state.cargo.P.products = 0
	view._sync_freight_beacon_visual()
	view._refresh_ui()
	verify("DELIVERED" in view.goal_label.text and "Build a belt route" in view.goal_label.text
		and marker != null and not marker.visible and view.freight_beacon_visual.collision_layer == 0,
		"The completed receipt hides the marker and selection while leaving continued building visible.")
	for _frame in range(2):
		await physics_frame
	var filled_hit := view._screen_pick(root.get_visible_rect().size / 2.0)
	verify(filled_hit.is_empty() or filled_hit.collider != view.freight_beacon_visual,
		"A completed shipment leaves no invisible delivery target.")
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
		view._refresh_guided_tools()
		await settle_footer()
		var panel: Control = view.inspector.get_parent().get_parent()
		verify(not panel.visible, "Foundation-only construction does not show unused machine inspection actions.")
		view.mode = "inspect"
		view.selected = "step-a"
		view._refresh_guided_tools()
		await settle_footer()
		verify(panel.visible, "Explicit foundation inspection retains its panel and dismantling controls.")
		view.mode = "collector"
		view.selected = ""
		view.show_details = true
		view._refresh_guided_tools()
		await settle_footer()
		verify(panel.visible, "Explicit Details retains the inspection disclosure.")
		view.show_details = false
		view._refresh_guided_tools(false)
		await settle_footer()
		verify(panel.visible, "An unavailable snapshot retains inspection readiness notices.")
		view.state.actors.P.ready = false
		view._refresh_guided_tools()
		await settle_footer()
		verify(panel.visible, "An unready physical actor retains inspection readiness notices.")
		view.state.actors.P.ready = true
		view.explanation_open = true
		view._refresh_guided_tools()
		await settle_footer()
		verify(panel.visible, "Help retains explicit inspection disclosure.")
		view.explanation_open = false
		view._refresh_guided_tools()
		await settle_footer()
		verify(not panel.visible and view.state == before and view.model == null and view.actor_world == null
			and view.request_sequence == 0, "Returning to construction hides the unused panel without authority or requests.")
		view.state.entities = {"wheel-a": {"kind": "wheel", "cell": [-2, 1]},
			"press-a": {"kind": "processor", "cell": [3, 1]}}
		var built_before: Dictionary = view.state.duplicate(true)
		view._refresh_guided_tools()
		await settle_footer()
		var idle_height: float = panel.size.y
		verify(panel.visible and view.power_label.visible and idle_height < 100.0,
			"An unselected built worksite keeps compact drive status instead of covering the machinery.")
		verify(not view.inspector.visible and not view.retrieve_button.visible and not view.remove_button.visible,
			"No target means no repeated selection prompt or unusable target actions.")
		view.selected = "press-a"
		view._refresh_guided_tools()
		await settle_footer()
		verify(view.inspector.visible and view.retrieve_button.visible and view.remove_button.visible
			and panel.size.y > idle_height,
			"Selecting the press restores its inspection, collection and dismantling actions.")
		view.selected = "wheel-a"
		view._refresh_guided_tools()
		await settle_footer()
		verify(view.inspector.visible and view.remove_button.visible and not view.retrieve_button.visible,
			"Wheel inspection does not offer plate collection.")
		view.selected = ""
		view.mode = "inspect"
		view._refresh_guided_tools()
		await settle_footer()
		verify(panel.visible and view.inspector.visible,
			"Choosing Inspect keeps the selection prompt available without a target.")
		view.mode = "collector"
		view.recovery_actions.visible = true
		view._refresh_guided_tools()
		await settle_footer()
		verify(panel.visible and view.recovery_actions.is_visible_in_tree(),
			"A disclosed recovery component remains visible without a selected target.")
		view.recovery_actions.visible = false
		verify(view.state == built_before and view.model == null and view.actor_world == null and view.request_sequence == 0,
			"Inspection disclosure never creates an authority, physical body or gameplay request.")
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
	view.show_details = true
	view._refresh_guided_tools()
	await settle_footer()
	verify(view.status_label.visible, "Details keeps the explicit introductory status available.")
	view.show_details = false
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
	if OS.get_cmdline_user_args().has("--freight-beacon-only"):
		call_deferred("check_freight_beacon_view")
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
	if OS.get_cmdline_user_args().has("--verifier-negative-control"):
		nested_failure_control()
		finish_checks()
		return
	check_native_route_report()
	finish_checks()
