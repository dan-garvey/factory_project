extends SceneTree
## Default/camera modes use detached views. Footer mode mounts only real UI
## containers, without a Model, body, network or game world.

const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")
var checks := 0
var camera_failed := false
var failed := false

class SessionStub extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

class ToolStub extends RefCounted:
	var active_tool := "gear"

class FooterView extends Opening:
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass

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
		"right": {"cell": [6, 2], "level": 1, "generation": 2}}
	view._rebuild_machines()
	for _frame in range(3):
		await physics_frame
		await process_frame
	var top_point := Vector3(8.25, Opening.Geometry.HEIGHT_STEP, 3.3)
	var top_screen := view.camera.unproject_position(top_point)
	verify(view._screen_cell(top_screen) == Vector2i(5, 2) and view._screen_entity(top_screen) == "left",
		"A projected foundation remains pickable at its real top height without ActorWorld.")
	view.mode = "belt"
	verify(view._construction_level(Vector2i(5, 2)) == 1 and view._construction_level(Vector2i(6, 2)) == 1,
		"Independent projected surfaces select the same machine height.")
	view.mode = "foundation"
	view._refresh_guided_tools()
	view._adjust_foundation_level(1)
	await settle_footer()
	verify(view.foundation_level == 1 and view.foundation_level_controls.visible,
		"The foundation tool exposes an absolute height in the real controls.")
	var bounds: Rect2 = view.tool_buttons.foundation.get_parent().get_parent().get_global_rect()
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
	ack.free()
	view.free()
	finish_checks()

func settle_footer() -> void:
	for _frame in range(4):
		await process_frame

func check_footer_layout() -> void:
	root.size = Vector2i(1280, 800)
	var view := FooterView.new()
	view.state = first_target_fixture()
	root.add_child(view)
	view._build_interface()
	view._refresh_guided_tools()
	var intro := "WASD walks. Approach the mineral seam to place your collector."
	view._message(intro)
	await settle_footer()
	var panel: Control = view.status_label.get_parent().get_parent()
	var short_bounds: Rect2 = panel.get_global_rect()
	verify(not view.status_label.visible, "The fresh native footer does not repeat the visible collector instruction.")
	verify(short_bounds.size.y < 64.0 and panel.get_global_rect().encloses(view.controls_label.get_global_rect()),
		"The fresh controls fit a compact strip instead of reserving the old two-row banner.")
	verify(short_bounds.size.x < 952.0, "The fresh strip removes blank width while fitting every control hint.")
	verify(is_equal_approx(short_bounds.end.y, 782.0), "The compact footer keeps its eighteen-pixel bottom margin.")
	root.size = Vector2i(1600, 900)
	await settle_footer()
	var wide_bounds: Rect2 = panel.get_global_rect()
	verify(is_equal_approx(wide_bounds.end.x, 1582.0) and is_equal_approx(wide_bounds.end.y, 882.0) \
		and is_equal_approx(wide_bounds.size.x, short_bounds.size.x) and wide_bounds.encloses(view.controls_label.get_global_rect()),
		"A wider viewport preserves the compact controls and both outer margins.")
	root.size = Vector2i(1280, 800)
	await settle_footer()
	view._message(intro, true)
	await settle_footer()
	verify(view.status_label.visible, "Even matching introduction text remains visible when it is an explicit refusal.")
	var refusal := "Cannot place the collector here. Approach the mineral seam and leave room for the material outlet. "
	view._message(refusal.repeat(7), true)
	await settle_footer()
	var long_bounds: Rect2 = panel.get_global_rect()
	verify(view.status_label.visible and view.status_label.get_line_count() > 1 and view.status_label.text == refusal.repeat(7),
		"A long refusal remains complete and wraps across multiple lines.")
	verify(long_bounds.size.y > short_bounds.size.y and long_bounds.position.y >= 0.0 and is_equal_approx(long_bounds.end.y, 782.0) \
		and long_bounds.encloses(view.status_label.get_global_rect()) and long_bounds.encloses(view.controls_label.get_global_rect()),
		"The footer grows upward around a refusal while keeping both rows inside the viewport.")
	view._message(intro)
	view.show_details = true
	view._refresh_guided_tools()
	await settle_footer()
	verify(view.status_label.visible, "Details keeps the explicit introductory status available.")
	view.show_details = false
	view.show_all_tools = true
	view._refresh_guided_tools()
	await settle_footer()
	verify(view.status_label.visible, "All tools retains the full status row.")
	view.show_all_tools = false
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
	view.free()
	var legacy := FooterView.new()
	legacy.legacy_fixture = true
	legacy.state = fixture()
	root.add_child(legacy)
	legacy._build_interface()
	legacy._message(intro)
	await settle_footer()
	var historical: Control = legacy.status_label.get_parent().get_parent()
	verify(legacy.status_label.visible and is_equal_approx(historical.get_global_rect().size.y, 88.0),
		"The historical fixture retains its original status and footer dimensions.")
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
	view.geometry_key = JSON.stringify([{}, [], []])
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

func check_first_target() -> void:
	var view = Opening.new()
	view.state = first_target_fixture()
	view.mode = "collector"
	view.request_sequence = 23
	view._build_placement_hint()
	var original: Dictionary = view.state.duplicate(true)
	var original_namespace: String = view.request_namespace
	verify(view._guided_placement_cell() == [0, 1], "A fresh native collector has a concrete starter-path suggestion.")
	view._refresh_placement_hint()
	var label := view.placement_hint.get_node_or_null("MineralSeamTarget") as Label3D
	verify(label != null and label.visible and label.text == "MINERAL SEAM", "The first target identifies the mineral seam in the world.")
	var ground: float = Opening.ProductionEnvironment.Surface.height_at(0.0, 1.65)
	verify(view.placement_hint.visible and view.placement_hint.position.is_equal_approx(Vector3(0.0, ground + 0.055, 1.65)),
		"The advisory footprint follows the shared natural surface at the source column.")
	verify(view.state == original and view.model == null and view.actor_world == null and view.request_sequence == 23 \
		and view.request_namespace == original_namespace and view.selected.is_empty() and view.pending_link.is_empty(),
		"Target presentation leaves confirmed facts, authority and intent unchanged.")
	var original_hint_id: int = view.placement_hint.get_instance_id()
	view._refresh_placement_hint()
	verify(view.placement_hint.get_instance_id() == original_hint_id and label != null \
		and view.placement_hint.get_node_or_null("MineralSeamTarget") == label, "Repeated refresh reuses the footprint and annotation.")
	view.transmission_controls = ToolStub.new()
	view._refresh_placement_hint()
	verify(not view.placement_hint.visible and (label == null or not label.visible), "An active transmission tool clears the first target.")
	view.transmission_controls = null
	view.state.actors.P.position = [-100, 1, 100]
	verify(view._guided_placement_cell() == [0, 1], "A target annotation is advice, never a reach permission.")
	view.state = first_target_fixture()
	for unavailable in ["help", "all_tools", "reopening", "actor", "kit", "source", "nonnative", "legacy", "built", "shaft", "goal"]:
		view.state = first_target_fixture()
		view.explanation_open = unavailable == "help"
		view.show_all_tools = unavailable == "all_tools"
		view.startup_save_pending = unavailable == "reopening"
		view.legacy_fixture = unavailable == "legacy"
		match unavailable:
			"actor": view.state.actors.P.ready = false
			"kit": view.state.part_kits.P.collector = 0
			"source": view.state.stock.source = 0
			"nonnative": view.state.options.native = false
			"built": view.state.entities["collector-1"] = {"kind": "collector", "cell": [0, 1]}
			"shaft": view.state.transmission_parts["shaft-1"] = {"kind": "shaft"}
			"goal": view.state.inventories.P = 4
		view._refresh_placement_hint()
		verify(not view.placement_hint.visible and (label == null or not label.visible), "Unavailable first-target advice clears: " + unavailable)
	view.state = first_target_fixture()
	view.legacy_fixture = false
	view._refresh_placement_hint(false)
	verify(not view.placement_hint.visible, "An unavailable confirmed snapshot clears the first target.")
	view.state.entities["collector-1"] = {"kind": "collector", "cell": [0, 1]}
	view.mode = "belt"
	view._refresh_placement_hint()
	verify(view.placement_hint.visible and (label == null or not label.visible), "The next Belt footprint clears the first-target annotation.")
	view.free()
	var shared = SharedOpening.new()
	var session := SessionStub.new()
	shared.session = session
	shared.client = "P"
	shared.mode = "collector"
	shared.state = first_target_fixture()
	shared._build_placement_hint()
	shared._refresh_placement_hint()
	verify(shared.placement_hint.visible, "A ready shared native projection can identify the first target.")
	shared.pending_actions["request-1"] = {"action": {"action": "place"}, "outcome": {}}
	shared._refresh_placement_hint()
	verify(not shared.placement_hint.visible, "A pending shared command clears first-target advice.")
	shared.pending_actions.clear()
	session.ready = false
	shared._refresh_placement_hint()
	verify(not shared.placement_hint.visible, "Disconnected first-target advice is unavailable.")
	shared.free()

func fixture() -> Dictionary:
	return {"entities": {"collector-1": {"kind": "collector", "cell": [0, 1]}},
		"parts": {"collector": 0, "belt": 1, "processor": 1}, "stock": {"output": 0},
		"inventories": {"P": 0}, "actors": {"P": {"ready": true}},
		"options": {"physical": true}}

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--foundation-view-only"):
		check_foundation_view.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--footer-layout-only"):
		call_deferred("check_footer_layout")
		return
	if OS.get_cmdline_user_args().has("--camera-profile-only"):
		check_camera_profiles()
		print("OPENING_CAMERA_PROFILE_%s %d" % ["FAIL" if camera_failed else "PASS", checks])
		quit(1 if camera_failed else 0)
		return
	if OS.get_cmdline_user_args().has("--verifier-negative-control"):
		nested_failure_control()
		finish_checks()
		return
	check_first_target()
	var view = Opening.new()
	view.mode = "belt"
	view.state = fixture()
	view.request_sequence = 17
	view.selected = "collector-1"
	view.pending_link = "collector-1"
	view._build_placement_hint()
	var before: Dictionary = view.state.duplicate(true)
	var original_namespace: String = view.request_namespace
	verify(view._guided_placement_cell() == [1, 1], "A Collector suggests its +x outlet for a Belt.")
	view._refresh_placement_hint()
	verify(view.placement_hint.visible and view.placement_hint.position.is_equal_approx(Vector3(1.65, 0.055, 1.65)), "The outline uses the world-space grid position.")
	var edge_count := 0
	for edge in view.placement_hint.get_children():
		if edge is MeshInstance3D:
			edge_count += 1
			verify(edge.get_child_count() == 0, "Cue edges contain no input or collision nodes.")
		else:
			verify(edge is Label3D and not edge.visible and edge.get_child_count() == 0, "The nonnative cue keeps its target annotation hidden and passive.")
	verify(edge_count == 4, "The outline consists of four mesh edges.")
	verify(view.state == before and view.model == null and view.request_sequence == 17 and view.request_namespace == original_namespace and view.selected == "collector-1" and view.pending_link == "collector-1", "Drawing the cue leaves projection, authority and intent state unchanged.")
	view._refresh_placement_hint(false)
	verify(not view.placement_hint.visible, "An unavailable snapshot clears an already drawn cue.")
	view.show_all_tools = true
	verify(view._guided_placement_cell().is_empty(), "All tools opts out of the cue.")
	view.show_all_tools = false
	view.explanation_open = true
	verify(view._guided_placement_cell().is_empty(), "Help has no worksite cue.")
	view.explanation_open = false
	view.legacy_fixture = true
	verify(view._guided_placement_cell().is_empty(), "The legacy fixture is unchanged.")
	view.legacy_fixture = false
	view.startup_save_pending = true
	verify(view._guided_placement_cell().is_empty(), "An unfinished reopen does not suggest construction.")
	view.startup_save_pending = false
	view.state.actors.P.ready = false
	verify(view._guided_placement_cell().is_empty(), "An unready actor has no cue.")
	view.state = fixture()
	view.mode = "processor"
	verify(view._guided_placement_cell().is_empty(), "An early Press selection does not invent a Belt.")
	view.mode = "belt"
	view.state.parts.belt = 0
	verify(view._guided_placement_cell().is_empty(), "An unavailable carried part has no suggested square.")
	view.state = fixture()
	view.state.entities["wheel-1"] = {"kind": "wheel", "cell": [1, 1]}
	verify(view._guided_placement_cell().is_empty(), "An occupied outlet is not suggested.")
	view.state = fixture()
	view.state.entities["collector-2"] = {"kind": "collector", "cell": [0, 2]}
	verify(view._guided_placement_cell().is_empty(), "Multiple upstream choices do not select an arbitrary route.")
	view.state = fixture()
	view.state.entities["collector-1"].cell = [4, 1]
	verify(view._guided_placement_cell() == [5, 1], "The cue can continue beyond the retired construction rectangle.")
	view.state = fixture()
	view.state.stock.output = 1
	verify(view._guided_placement_cell().is_empty(), "An available plate takes priority over construction advice.")
	view.state = fixture()
	view.state.inventories.P = 4
	verify(view._guided_placement_cell().is_empty(), "A completed collection goal takes priority over construction.")
	view.state = fixture()
	view.goal_confirmed = true
	verify(view._guided_placement_cell().is_empty(), "A confirmed goal has no prescribed next square.")
	view.goal_confirmed = false
	view.state.entities["belt-1"] = {"kind": "belt", "cell": [1, 1]}
	view.mode = "processor"
	verify(view._guided_placement_cell() == [2, 1], "A confirmed Belt suggests the Press outlet square.")
	view.state.actors.P.position = [-100, 1, 100]
	verify(view._guided_placement_cell() == [2, 1], "The cue is advice even outside reach, never a permission check.")
	view.state.entities["processor-1"] = {"kind": "processor", "cell": [2, 1]}
	verify(view._guided_placement_cell().is_empty(), "A placed Press advances beyond construction advice.")
	view.free()

	var shared = SharedOpening.new()
	var session := SessionStub.new()
	shared.session = session
	shared.client = "P"
	shared.mode = "belt"
	shared.state = fixture()
	shared._build_placement_hint()
	shared._refresh_placement_hint()
	verify(shared.placement_hint.visible, "A usable connected projection can show the cue.")
	shared.pending_actions["request-1"] = {"action": {"action": "place"}, "outcome": {}}
	shared._refresh_placement_hint()
	verify(not shared.placement_hint.visible, "A pending command clears an existing cue.")
	shared.pending_actions.clear()
	session.ready = false
	verify(shared._guided_placement_cell().is_empty(), "A disconnected view cannot suggest a live build.")
	session.ready = true
	shared.state.erase("stock")
	verify(shared._guided_placement_cell().is_empty(), "An unusable shared snapshot has no cue.")
	shared.free()
	finish_checks()
