extends SceneTree
## One joined frame with invented observations. No World, actor or desktop.
const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")

class FrameView extends Opening:
	var target := Vector2i(1, 2)
	func _ready() -> void: set_process(false)
	func _preview_pointer_clear() -> bool: return true
	func _machine_preview_cell() -> Vector2i: return target
	func _update_camera() -> void: pass

class SharedFrameView extends SharedOpening:
	var target := Vector2i(1, 2)
	func _ready() -> void: set_process(false)
	func _preview_pointer_clear() -> bool: return true
	func _machine_preview_cell() -> Vector2i: return target
	func _update_camera() -> void: pass

class ControlsStub extends RefCounted:
	var selected_axis := "z"
	var active_tool := ""
	func pending_endpoint() -> Dictionary: return {}

class SessionStub extends RefCounted:
	var ready := true
	func is_ready() -> bool: return ready

class HelpStub extends RefCounted:
	func pan(_delta: float) -> void: pass

var checks := 0
var failed := false

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func observation() -> Dictionary:
	return {"context": "joined-presentation", "revision": 7, "order": 0,
		"options": {"physical": true, "native": true},
		"actors": {"P": {"ready": true, "position": [0.0, 0.9, 0.0]}},
		"entities": {"motor": {"kind": "wheel", "axis": 0, "cell": [-1, 0]}},
		"motion": {"motor": {"state": "rotating", "numerator": 1, "denominator": 2}},
		"links": [], "drive_links": [], "inventories": {"P": 0},
		"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
		"parts": {"belt": 1}, "part_kits": {"P": {"belt": 1}}}

func check_frames(view, shared: bool) -> void:
	view.state = observation()
	view.mode = "belt"
	view.auto_advance = false
	view.transmission_controls = ControlsStub.new()
	view.example_presenter = HelpStub.new()
	view.camera = Camera3D.new()
	view.add_child(view.camera)
	root.add_child(view)
	var before: Dictionary = view.state.duplicate(true)
	view._process(0.016)
	var has_preview: bool = view.machine_preview != null and view.machine_preview.visible
	var has_audio: bool = view.mechanical_ambience != null and view.mechanical_ambience.emitters.has("motor")
	verify(has_preview and has_audio, "One actual frame updates both preview geometry and the confirmed machinery source.")
	if not has_preview or not has_audio:
		view.free()
		return
	var preview_id: int = view.machine_preview.get_child(0).get_instance_id()
	var emitter_id: int = view.mechanical_ambience.emitters.motor.get_instance_id()
	verify(view.state == before and view.model == null and view.actor_world == null and view.request_sequence == 0,
		"The joined frame leaves the observation, requests and authority untouched.")
	view.target = Vector2i(2, 2)
	view.state.actors.P.position[0] = 0.25
	before = view.state.duplicate(true)
	view._process(0.016)
	verify(view.machine_preview.position == Vector3(3.3, 0, 3.3)
		and view.mechanical_ambience.listener.position == Vector3(0.25, 1.45, 0),
		"A later frame follows the pointer and confirmed worker independently.")
	verify(view.machine_preview.get_child(0).get_instance_id() == preview_id
		and view.mechanical_ambience.emitters.motor.get_instance_id() == emitter_id,
		"Both presentations retain their resources across an ordinary frame.")
	verify(view.state == before, "Moving presentation nodes does not mutate confirmed facts.")
	view.explanation_open = true
	view._process(0.016)
	verify(not view.machine_preview.visible and view.mechanical_ambience.emitters.is_empty(),
		"Help clears both presentations through the real frame callback.")
	view.explanation_open = false
	view._process(0.016)
	verify(view.machine_preview.visible and view.mechanical_ambience.emitters.has("motor"),
		"Closing Help restores both presentations from the same confirmed observation.")
	if shared:
		view.session.ready = false
	else:
		view.state.actors.P.ready = false
	view._process(0.016)
	verify(not view.machine_preview.visible and view.mechanical_ambience.emitters.is_empty(),
		"Lost shared readiness or an unready offline actor clears both presentations.")
	view.free()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check_frames(FrameView.new(), false)
	var shared := SharedFrameView.new()
	shared.session = SessionStub.new()
	check_frames(shared, true)
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"observations": "invented", "desktop": "not_used", "gameplay": "not_run"}))
	quit(1 if failed else 0)
