extends SceneTree
## Adapter unit cases only: no scene enters the tree and no live world is made.

const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")
var checks := 0
var camera_failed := false

class SessionStub extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

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
		push_error(reason)
		quit(1)
		assert(condition, reason)

func fixture() -> Dictionary:
	return {"entities": {"collector-1": {"kind": "collector", "cell": [0, 1]}},
		"parts": {"collector": 0, "belt": 1, "processor": 1}, "stock": {"output": 0},
		"inventories": {"P": 0}, "actors": {"P": {"ready": true}},
		"options": {"physical": true}}

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--camera-profile-only"):
		check_camera_profiles()
		print("OPENING_CAMERA_PROFILE_%s %d" % ["FAIL" if camera_failed else "PASS", checks])
		quit(1 if camera_failed else 0)
		return
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
	verify(view.placement_hint.get_child_count() == 4, "The outline consists of four mesh edges.")
	for edge in view.placement_hint.get_children():
		verify(edge is MeshInstance3D and edge.get_child_count() == 0, "Cue edges contain no input or collision nodes.")
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
	verify(view._guided_placement_cell().is_empty(), "The cue stays within the displayed grid.")
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
	print("OPENING_GUIDANCE_CUE_PASS %d" % checks)
	quit(0)
