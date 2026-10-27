extends SceneTree
## Invented confirmed projections and a request sink, never a Model or game.
const Controls = preload("res://opening/native_transmission_controls.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const ActorWorld = preload("res://opening/actor_world.gd")
const PhysicalActor = preload("res://opening/actor_body.gd")
const Presenter = preload("res://opening/native_transmission_presenter.gd")
const NativeModel = preload("res://opening/native_model.gd")
const Assets = preload("res://opening/native_transmission_assets.gd")
const LooseControls = preload("res://opening/recovery_actions.gd").LooseMaterialControls
const Session = preload("res://opening-session/session.gd")
const Opening = preload("res://opening/opening.gd")
const DIRECT_MODES := [
	"--supplied-hardware-only", "--component-boxes-only", "--press-components-only",
	"--guided-press-components-only", "--broad-press-components-only", "--broad-press-raised-only",
	"--channel-components-only", "--channel-z-only", "--channel-sheet-only",
	"--physical-topology-cache-only", "--physical-actor-bridge-only", "--advance-projection-only",
	"--native-actor-view-only", "--native-view-cache-only", "--support-frame-only",
	"--finish-only", "--tool-guidance-only", "--refresh-cache-only", "--belt-surface-only",
	"--direction-basis-only", "--loose-material-only", "--slide-material-only",
	"--mechanical-collision-only", "--collision-lifecycle-only", "--cog-axle-collision-only",
	"--river-pier-collision-only", "--belt-actor-only", "--inclined-belt-actor-only",
	"--nonhorizontal-presentation-only", "--belt-picking-only", "--cog-axles-only",
	"--belt-spans-only", "--belt-spans-missing-only"]
const BENCHMARK_FLAGS := ["--supports", "--varied-supports", "--close", "--cycle-axes",
	"--verify-only", "--whole-opening", "--stopped", "--refresh-every-frame", "--trusted-revision"]
const VALUE_MODES := {
	"--broad-capture=": ["--broad-press-components-only", "--broad-press-raised-only"],
	"--channel-capture=": ["--channel-components-only", "--channel-z-only", "--channel-sheet-only"],
	"--channel-after-capture=": ["--channel-components-only", "--channel-z-only", "--channel-sheet-only"],
	"--capture=": ["--guided-press-components-only", "--scale-benchmark"],
	"--crank-capture-prefix=": ["--guided-press-components-only"],
	"--slide-material-image=": ["--slide-material-only"],
	"--loose-material-image=": ["--loose-material-only"],
	"--count=": ["--scale-benchmark"],
	"--large-every=": ["--scale-benchmark"]}
var checks := 0
var failures := 0

class SuppliedOpening extends "res://opening/opening.gd":
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass

class PickupOpening extends SuppliedOpening:
	var calls: Array = []
	func _pointed_screen_position() -> Vector2:
		return get_viewport().get_visible_rect().size * 0.5
	func issue(action: Dictionary) -> Dictionary:
		calls.append(action.duplicate(true))
		return {"accepted": false, "reason": "out_of_reach"}
	func _message(_text: String, _error: bool = false) -> void:
		pass

class CountingNativeModel extends "res://opening/native_model.gd":
	var full_projection_calls := 0
	var native_advance_calls := 0
	var native_delta_calls := 0
	var inject_bad_full := false
	var inject_bad_delta := false
	func _invoke(method: String, arguments: Array) -> Dictionary:
		if method == "projection":
			full_projection_calls += 1
		elif method == "advance":
			native_advance_calls += 1
		elif method == "advance_delta":
			native_delta_calls += 1
		var delivered: Dictionary = super._invoke(method, arguments)
		if method == "projection" and inject_bad_full:
			inject_bad_full = false
			delivered.erase("stock")
		elif method == "advance_delta" and inject_bad_delta:
			inject_bad_delta = false
			return {"changes": {"cargo": []}, "removed": []}
		return delivered

class TopologyStub extends RefCounted:
	var state: Dictionary = {}
	var calls := 0
	func projection() -> Dictionary:
		calls += 1
		return state

class ActorBridgeStub extends RefCounted:
	var actor: Dictionary = {"accepted": true, "ready": true,
		"position": [1.0, 2.0, 3.0], "native_epoch": 7}
	var narrow_calls := 0
	var full_calls := 0
	func actor_projection(_actor: String) -> Dictionary:
		narrow_calls += 1
		return actor
	func projection() -> Dictionary:
		full_calls += 1
		return {"actors": {"P": actor}}

class AdvanceProjectionStub extends RefCounted:
	var advances := 0
	var projections := 0
	var revision := 0
	var refuse_next := false
	func _state() -> Dictionary:
		return {"context": "advance-projection-fixture", "revision": revision,
			"order": 0, "entities": {}, "links": [], "options": {}}
	func advance() -> Dictionary:
		advances += 1
		if refuse_next:
			refuse_next = false
			return {"accepted": false, "reason": "native_step_failed"}
		revision += 1
		return _state()
	func projection() -> Dictionary:
		projections += 1
		return _state()

class HostStub extends RefCounted:
	var state: Dictionary
	var model: Variant = null
	var client := "P"
	var explanation_open := false
	var startup_save_pending := false
	var mutate_allowed := true
	var motion_fresh := true
	var calls: Array = []
	var messages: Array = []
	var reply_mode := "queued"
	func _can_mutate() -> bool:
		return mutate_allowed
	func _can_present_confirmed_motion() -> bool:
		return motion_fresh
	func issue(wire: Dictionary) -> Dictionary:
		calls.append(wire.duplicate(true))
		if reply_mode == "accepted":
			return {"accepted": true, "request": "request-%d" % calls.size()}
		if reply_mode == "refused":
			return {"accepted": false, "reason": "out_of_reach"}
		return {"queued": true, "accepted": false, "request": "request-%d" % calls.size()}
	func _message(words: String, _refused: bool) -> void:
		messages.append(words)

class ReadySession extends RefCounted:
	func is_ready() -> bool:
		return true

class ScaleOpening extends "res://opening/opening.gd":
	var motion_ms := 0.0
	var process_ms := 0.0
	func _start_character_world() -> bool:
		return true
	func _start_character_presenter() -> void:
		pass
	func _animate_wheel(delta: float) -> void:
		var before := Time.get_ticks_usec()
		super._animate_wheel(delta)
		motion_ms = float(Time.get_ticks_usec() - before) / 1000.0
	func _process(delta: float) -> void:
		var before := Time.get_ticks_usec()
		super._process(delta)
		process_ms = float(Time.get_ticks_usec() - before) / 1000.0

class AdvanceProjectionOpening extends "res://opening/opening.gd":
	func _ready() -> void:
		pass
	func _sync_landing_pod_visual() -> void:
		pass
	func _rebuild_machines() -> void:
		pass
	func _redraw_items() -> void:
		pass
	func _refresh_ui() -> void:
		pass
	func _refresh_machine_preview() -> void:
		pass
	func _refresh_placement_options() -> void:
		pass
	func _refresh_water() -> void:
		pass
	func _refresh_mechanical_audio() -> void:
		pass
	func _animate_wheel(_delta: float) -> void:
		pass
	func _update_camera() -> void:
		pass
	func _update_fps_counter(_delta: float) -> void:
		pass

class SharedSettlement extends "res://opening/shared_opening.gd":
	func _usable_snapshot() -> bool:
		return true
	func _refresh_ui() -> void:
		pass
	func _message(_words: String, _refused: bool = false) -> void:
		pass

class PhysicalProjection extends RefCounted:
	var state: Dictionary
	var projection_calls := 0
	func projection() -> Dictionary:
		projection_calls += 1
		return state.duplicate(true)
	func observe(actor: String, sample: Dictionary) -> void:
		state.actors[actor]["position"] = sample.position.duplicate()
		state.actors[actor]["ready"] = sample.ready
		state.actors[actor]["native_epoch"] = sample.native_epoch

func verify(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("TRANSMISSION_VIEW_FAILURE: " + reason)

func part_anchor(presenter: Node3D, id: String) -> Node3D:
	for child: Node in presenter.get_children():
		if child is Node3D and child.get_meta("entity", "") == id:
			return child
	return null

func fixture() -> Dictionary:
	return {"context": "helper-fixture", "options": {"native": true},
		"actors": {"P": {"ready": true}, "Q": {"ready": true}},
		"entities": {"wheel": {"kind": "wheel", "generation": 1, "center": [-4, 0, 4], "axis": 1}},
		"transmission_parts": {
			"a": {"kind": "gear", "generation": 2, "center": [-4, 4, 4], "axis": 1, "teeth": 2, "half_span": 0},
			"b": {"kind": "gear", "generation": 3, "center": [0, 4, 4], "axis": 1, "teeth": 2, "half_span": 0},
			"sx": {"kind": "shaft", "generation": 4, "center": [2, 0, 4], "axis": 0, "teeth": 0, "half_span": 2},
			"sy": {"kind": "shaft", "generation": 5, "center": [0, 2, 0], "axis": 1, "teeth": 0, "half_span": 2},
			"sz": {"kind": "shaft", "generation": 6, "center": [0, 0, 2], "axis": 2, "teeth": 0, "half_span": 2}},
		"part_specifications": {
			"P": [{"kind": "gear", "teeth": 2, "half_span": 0, "count": 2}, {"kind": "shaft", "teeth": 0, "half_span": 2, "count": 3}],
			"Q": [{"kind": "gear", "teeth": 2, "half_span": 0, "count": 0}, {"kind": "shaft", "teeth": 0, "half_span": 2, "count": 0}]},
		"parts": {"gear": 99, "shaft": 99}, "drive_links": [], "powered": false,
		"motion": {"a": {"state": "rotating", "numerator": 1, "denominator": 1},
			"b": {"state": "rotating", "numerator": -1, "denominator": 1},
			"sx": {"state": "unpowered", "numerator": 0, "denominator": 1},
			"sy": {"state": "rotating", "numerator": 1, "denominator": 1},
			"sz": {"state": "stalled", "numerator": 0, "denominator": 1}},
		"engagements": [{"a": "a", "b": "b", "kind": 0}]}

func _component_record(kind: String, cell: Array, center: Array, half: Array) -> Dictionary:
	return {"component": kind, "generation": 1, "center": cell,
		"occupied": {"center": center, "half": half}}

func _component_fixture() -> Dictionary:
	return {"context": "component-view-fixture", "revision": 1,
		"options": {"native": true, "physical": true}, "actors": {}, "entities": {},
		"foundations": {}, "transmission_parts": {}, "belt_spans": {}, "motion": {},
		"placed_components": {
			"frame": _component_record("wooden_frame", [0, 0, 0], [0.0, 0.45, 0.0], [0.2025, 0.45, 0.2025]),
			"mount": _component_record("tool_mount", [-1, 0, 0], [-0.4125, 0.925, 0.0], [0.2, 0.18, 0.19]),
			"edge": _component_record("cutting_edge", [-2, 0, 0], [-0.825, 0.81, 0.0], [0.21, 0.12, 0.18]),
			"tray": _component_record("receiver_tray", [0, 0, 1], [0.0, 0.7425, 0.4125], [0.18, 0.15, 0.205]),
			"shaft": _component_record("wooden_shaft", [1, 0, 0], [0.4125, 0.825, 0.0], [0.205, 0.12, 0.205])},
		"collector_assemblies": [{"center": [0, 0, 0], "toward_ore": [-1, 0, 0],
			"status": "ready", "parts": {"frame": "frame", "mount": "mount",
			"edge": "edge", "receiver": "tray", "shaft": "shaft"}}]}

func _supplied_envelope(state: Dictionary, entity: String) -> AABB:
	var envelope := AABB()
	var first_box := true
	for record: Dictionary in state.supplied_hardware_boxes.values():
		if record.entity != entity:
			continue
		var at: Array = record.center
		var half: Array = record.half
		var center := Vector3(at[0], at[1], at[2])
		var extent := Vector3(half[0], half[1], half[2])
		var box := AABB(center - extent, extent * 2.0)
		envelope = box if first_box else envelope.merge(box)
		first_box = false
	return envelope

func _meshes_inside(root_node: Node3D, envelope: AABB) -> bool:
	var meshes := root_node.find_children("*", "MeshInstance3D", true, false)
	var inside := not meshes.is_empty()
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null:
			inside = false
			continue
		var bounds := mesh.get_aabb()
		var fits := true
		for x in [0.0, 1.0]:
			for y in [0.0, 1.0]:
				for z in [0.0, 1.0]:
					fits = fits and envelope.grow(0.0001).has_point(
						mesh.global_transform * (bounds.position + bounds.size * Vector3(x, y, z)))
		if not fits:
			print(JSON.stringify({"outside_native_envelope": str(root_node.get_path_to(mesh)),
				"native_envelope": envelope, "rendered_bounds": mesh.global_transform * bounds}))
		inside = inside and fits
	return inside

func _supplied_hardware_view() -> void:
	var model := NativeModel.new("supplied-hardware-view", ["P"], true)
	verify(model.boot_result.get("accepted", false), "The supplied-hardware view boots the actual native arrival projection.")
	if not model.boot_result.get("accepted", false):
		return
	var host := HostStub.new()
	host.state = model.projection()
	var occupied: Dictionary = Geometry.component_boxes(host.state)
	verify(occupied.get("accepted", false) and occupied.boxes.size() == 20,
		"All twenty supplied solids remain available to the physics consumer.")
	var view := Presenter.new()
	root.add_child(view)
	view.configure(host)
	verify(view.find_children("*", "Node3D", false, false).is_empty(),
		"Supplied collision proxies do not create component artwork or pick bodies.")
	host.state.placed_components["player-frame"] = _component_record("wooden_frame",
		[40, 0, 0], [16.5, 0.45, 0.0], [0.2025, 0.45, 0.2025])
	view.refresh()
	var identities: Array = []
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			identities.append(node.get_meta("component_entity"))
	verify(identities == ["player-frame"],
		"The same view renders the actual placed component without supplied proxy duplicates.")
	verify(Geometry.component_boxes(host.state).boxes.size() == 21,
		"Filtering presentation does not remove supplied collision or the placed occupied box.")
	host.state.placed_components.clear()
	view.refresh()
	verify(view.get_child_count() == 0,
		"Removing the placed component leaves no proxy artwork behind.")
	view.free()
	var opening := SuppliedOpening.new()
	opening.state = model.projection()
	root.add_child(opening)
	opening._sync_landing_pod_visual()
	var bench: Node3D = opening.landing_hub_visual.get_node("FoldoutBench")
	var envelope := _supplied_envelope(opening.state, opening.state.fabrication_hub.id)
	var meshes := bench.find_children("*", "MeshInstance3D", true, false)
	verify(_meshes_inside(bench, envelope),
		"Every authored bench mesh stays within the native supplied hub envelope.")
	var shell: Node3D = opening.landing_pod_visual.get_node("OpenedPodShell")
	verify(_meshes_inside(shell, _supplied_envelope(opening.state, opening.state.landing_pod.id)),
		"Every deployed pod shell mesh stays within the native supplied pod envelope.")
	var fixed_face: MeshInstance3D = bench.get_node("ViseFixedFace")
	var sliding_face: MeshInstance3D = bench.get_node("ViseSlidingFace")
	var cutter: MeshInstance3D = bench.get_node("CuttingHead")
	var spindle: MeshInstance3D = bench.get_node("CuttingSpindle")
	var work_gap := (fixed_face.position.x + sliding_face.position.x) / 2.0
	verify(is_equal_approx(cutter.position.x, work_gap) and is_equal_approx(spindle.position.x, work_gap),
		"The cutting head and spindle are above the clamped work gap rather than a vise jaw.")
	var twin := SuppliedOpening.new()
	twin.state = model.projection()
	root.add_child(twin)
	twin._sync_landing_pod_visual()
	var other: Node3D = twin.landing_hub_visual.get_node("FoldoutBench")
	var reused := true
	for mesh: MeshInstance3D in meshes:
		var counterpart: MeshInstance3D = other.get_node(bench.get_path_to(mesh))
		reused = reused and mesh.mesh == counterpart.mesh and mesh.material_override == counterpart.material_override
	var other_shell: Node3D = twin.landing_pod_visual.get_node("OpenedPodShell")
	for mesh: MeshInstance3D in shell.find_children("*", "MeshInstance3D", true, false):
		var counterpart := other_shell.get_node_or_null(shell.get_path_to(mesh)) as MeshInstance3D
		reused = reused and counterpart != null and mesh.mesh == counterpart.mesh \
			and mesh.material_override == counterpart.material_override
	verify(reused, "Repeated pods and workshops share their authored mesh and material resources.")
	var original_position := opening.landing_hub_visual.position
	opening._sync_landing_pod_visual()
	verify(opening.landing_hub_visual.get_node("FoldoutBench") == bench,
		"An unchanged projection preserves the complete bench node tree.")
	opening.state.fabrication_hub.installed = false
	opening._sync_landing_pod_visual()
	verify(not opening.landing_hub_visual.visible and opening.landing_hub_pick.collision_layer == 0,
		"A stowed workshop hides its artwork and disables its pick target.")
	opening.state.fabrication_hub.installed = true
	opening.state.fabrication_hub.position[0] += opening.PITCH
	opening._sync_landing_pod_visual()
	verify(opening.landing_hub_visual.visible and opening.landing_hub_pick.collision_layer == Geometry.PICK_LAYER
		and opening.landing_hub_visual.position.is_equal_approx(original_position + Vector3(opening.PITCH, 0, 0))
		and opening.landing_hub_visual.get_node("FoldoutBench") == bench,
		"Redeployment moves the same bench by the projected world-grid pitch without a new local datum.")
	twin.free()
	opening.free()

func _component_view() -> void:
	# Invented native facts exercise only the existing view and Godot physics.
	var facts := PhysicalProjection.new()
	facts.state = _component_fixture()
	var parsed: Dictionary = Geometry.component_boxes(facts.state)
	verify(parsed.get("accepted", false) and parsed.boxes.size() == 5,
		"Five separately owned component boxes have a valid read-only consumer form.")
	var bad: Dictionary = facts.state.duplicate(true)
	bad.placed_components.frame.occupied.half[1] = -0.45
	verify(not Geometry.component_boxes(bad).get("accepted", false),
		"A malformed occupied box never becomes a collidable or visible part.")
	var physical := ActorWorld.new()
	root.add_child(physical)
	verify(physical.configure(facts).get("accepted", false) and physical.component_bodies.size() == 5,
		"The physical consumer registers the exact five projected identities.")
	var host := HostStub.new()
	host.state = facts.state
	var view := Presenter.new()
	root.add_child(view)
	view.configure(host)
	var anchors: Dictionary = {}
	for node in view.get_children():
		if node.has_meta("component_entity"):
			anchors[node.get_meta("component_entity")] = node
	verify(anchors.size() == 5 and anchors.frame.get_node_or_null("GroundedPost") != null
		and anchors.tray.get_node_or_null("OpenPan") != null,
		"The confirmed parts render separately with a grounded frame and open receiver.")
	var formed_stock := 0
	var joinery_pegs := 0
	for child: Node in anchors.frame.get_children():
		if child is MeshInstance3D and child.mesh is ArrayMesh:
			formed_stock += 1
			verify(child.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size() > 0,
				"Frame timber and iron use world-sized UVs on beveled stock, not raw boxes.")
		if child is MeshInstance3D and str(child.name).begins_with("JoineryPeg"):
			joinery_pegs += 1
			verify(is_equal_approx(child.position.y, 0.384),
				"Each visible post peg is seated in the confirmed work bed.")
	verify(formed_stock == 18 and joinery_pegs == 4,
		"The grounded frame keeps four posts and shoes, two braces, an open bed, a supported shelf, two straps and four pegged joints.")
	var clamp: Node3D = anchors.mount.get_node_or_null("CastToolClamp")
	verify(clamp != null and clamp.get_child_count() == 2
		and clamp.get_node_or_null("ClampCastBody") is MeshInstance3D
		and clamp.get_node_or_null("ClampFixedJaw") is MeshInstance3D,
		"Only the rigid sourced casting and fixed jaw appear on the confirmed tool mount.")
	if clamp != null:
		verify(clamp.basis.z.x > 0.99 and clamp.get_script() == null,
			"The source jaw faces the real cutting edge without a second control script.")
		for member: Node in clamp.get_children():
			var mesh := member as MeshInstance3D
			if mesh == null:
				continue
			var finish := mesh.mesh.surface_get_material(0) as StandardMaterial3D
			verify(mesh.get_child_count() == 0 and mesh.get_script() == null
				and finish != null and finish.albedo_texture != null
				and finish.normal_texture != null and finish.roughness_texture != null
				and finish.albedo_texture.get_size() == Vector2(1024, 1024)
				and finish.normal_texture.get_size() == Vector2(1024, 1024),
				"Each sourced rigid member retains the complete imported 1K PBR surface without rig or collider.")
	var fixed_feet := {"mount": "SlidingFoot", "edge": "BladeCarrier"}
	for id in fixed_feet:
		var foot_name: String = fixed_feet[id]
		var foot: MeshInstance3D = anchors[id].get_node(foot_name)
		var vertices: PackedVector3Array = foot.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var low_width := 0.0
		var high_width := 0.0
		var bottom := foot.mesh.get_aabb().position.y
		var top := foot.mesh.get_aabb().end.y
		for point in vertices:
			if absf(point.y - bottom) < 0.0001:
				low_width = maxf(low_width, absf(point.x))
			if absf(point.y - top) < 0.0001:
				high_width = maxf(high_width, absf(point.x))
		verify(foot.mesh is ArrayMesh and low_width - high_width > 0.025,
			"Each fixed cast foot has a broad bed contact and visibly inset upper shoulders.")
		var fasteners: Array[Node] = anchors[id].find_children(
			foot_name + "Fastener*", "MeshInstance3D", false, false)
		verify(fasteners.size() == 4 and foot.get_script() == null,
			"The clamp and blade each sit on one fixed four-fastener casting.")
	var carriage: MeshInstance3D = anchors.shaft.get_node_or_null("FrameMountedCarriage")
	verify(carriage != null and carriage.mesh is ArrayMesh
		and anchors.shaft.find_children("CarriageRail*", "MeshInstance3D", false, false).size() == 2
		and anchors.shaft.get_node_or_null("BearingFoot") == null,
		"A fitted shaft uses a timber carriage and two rails instead of a detached casting pedestal.")
	var blade: MeshInstance3D = anchors.edge.get_node_or_null("FormedBlade")
	verify(blade != null and blade.mesh is ArrayMesh,
		"The confirmed cutting edge has one formed steel blade instead of detached box teeth.")
	if blade == null or not blade.mesh is ArrayMesh:
		return
	var blade_arrays: Array = blade.mesh.surface_get_arrays(0)
	var blade_points: PackedVector3Array = blade_arrays[Mesh.ARRAY_VERTEX]
	var blade_normals: PackedVector3Array = blade_arrays[Mesh.ARRAY_NORMAL]
	var front_low := INF
	var front_high := -INF
	var root_low := INF
	var root_high := -INF
	var outward_winding := blade_points.size() == 36 and blade_normals.size() == 36
	for index in range(0, blade_points.size(), 3):
		if index + 2 >= blade_points.size():
			outward_winding = false
			break
		var cross: Vector3 = (blade_points[index + 1] - blade_points[index]).cross(
			blade_points[index + 2] - blade_points[index])
		outward_winding = outward_winding and cross.dot(blade_normals[index]) < -0.000001
	for point in blade_points:
		if is_equal_approx(point.x, -0.195):
			front_low = minf(front_low, point.y)
			front_high = maxf(front_high, point.y)
		if is_equal_approx(point.x, 0.075):
			root_low = minf(root_low, point.y)
			root_high = maxf(root_high, point.y)
	verify(outward_winding and is_equal_approx(front_high - front_low, 0.030)
		and is_equal_approx(root_high - root_low, 0.105),
		"The blade has outward facets and a thin cutting lip backed by a thicker clamped root.")
	var pan: MeshInstance3D = anchors.tray.get_node("OpenPan")
	var seat: PackedVector3Array = pan.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var folds: PackedVector3Array = pan.mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	var fold_normals: PackedVector3Array = pan.mesh.surface_get_arrays(1)[Mesh.ARRAY_NORMAL]
	verify(pan.mesh is ArrayMesh and pan.mesh.get_surface_count() == 2
		and seat.size() == 12 and folds.size() == 72
		and pan.mesh.surface_get_material(0) != null and pan.mesh.surface_get_material(1) != null,
		"The receiver is a two-finish formed sheet rather than five closed boxes.")
	var floor_is_level := true
	for point in seat:
		floor_is_level = floor_is_level and (is_equal_approx(point.y, 0.0425)
			or is_equal_approx(point.y, 0.0075))
	verify(floor_is_level and is_equal_approx(anchors.tray.position.y + 0.0425,
		Geometry.ANCHOR_HEIGHT - 0.04),
		"The open sheet retains a level native blank seat at the confirmed drop height.")
	var open_cavity := true
	var outward_faces := folds.size() == fold_normals.size()
	for index in range(0, folds.size(), 3):
		var point: Vector3 = folds[index]
		open_cavity = open_cavity and (absf(point.x) >= 0.15 or absf(point.z) >= 0.17)
		var cross: Vector3 = (folds[index + 1] - point).cross(folds[index + 2] - point)
		outward_faces = outward_faces and cross.dot(fold_normals[index]) < -0.000001
	verify(open_cavity and outward_faces and pan.mesh.get_aabb().size.y > 0.12,
		"Both raised sheet folds face outward while leaving the receiver cavity open.")
	var receiver_detail := {"ReceiverHook": 0, "ReceiverUnderRail": 0,
		"ReceiverRolledSide": 0, "ReceiverRolledEnd": 0, "ReceiverRivet": 0}
	var hooks_reach_near_edge := true
	for child in anchors.tray.get_children():
		for role: String in receiver_detail:
			if not str(child.name).begins_with(role):
				continue
			receiver_detail[role] += 1
			if role == "ReceiverHook":
				hooks_reach_near_edge = hooks_reach_near_edge and child.position.z < -0.18
	verify(receiver_detail == {"ReceiverHook": 2, "ReceiverUnderRail": 2,
		"ReceiverRolledSide": 2, "ReceiverRolledEnd": 2, "ReceiverRivet": 4}
		and hooks_reach_near_edge,
		"The open receiver has two frame-facing hooks, underside rails and restrained rolled-rim fasteners: %s, near=%s." %
		[str(receiver_detail), str(hooks_reach_near_edge)])
	var bed: MeshInstance3D = anchors.frame.get_node("BedCrossRailRear")
	var near_hook: MeshInstance3D = anchors.tray.get_node("ReceiverHookLeft")
	var bed_box: AABB = bed.mesh.get_aabb()
	var hook_box: AABB = near_hook.mesh.get_aabb()
	var bed_far_z: float = anchors.frame.position.z + bed.position.z + bed_box.end.z
	var hook_near_z: float = anchors.tray.position.z + near_hook.position.z + hook_box.position.z
	var bed_low_y: float = anchors.frame.position.y + bed.position.y + bed_box.position.y
	var bed_high_y: float = anchors.frame.position.y + bed.position.y + bed_box.end.y
	var hook_low_y: float = anchors.tray.position.y + near_hook.position.y + hook_box.position.y
	var hook_high_y: float = anchors.tray.position.y + near_hook.position.y + hook_box.end.y
	verify(hook_near_z > bed_far_z and hook_near_z - bed_far_z <= 0.01
		and hook_low_y < bed_high_y and hook_high_y > bed_low_y,
		"The frame bed and receiver hooks mate across only the native occupied-box clearance.")
	for id in parsed.boxes:
		var spec: Dictionary = parsed.boxes[id]
		var body: StaticBody3D = physical.component_bodies[id]
		var collider: CollisionShape3D = body.get_child(0)
		verify(body.collision_layer == Geometry.MACHINE_LAYER and body.position == spec.center
			and collider.shape.size == spec.size and anchors[id].position == spec.center,
			"The visual anchor and physical box both use the native occupied record.")
		for found: Node in anchors[id].find_children("*", "MeshInstance3D", true, false):
			var piece := found as MeshInstance3D
			var local_transform: Transform3D = anchors[id].global_transform.affine_inverse() * piece.global_transform
			var box: AABB = local_transform * piece.mesh.get_aabb()
			var occupied := AABB(-spec.size * 0.5, spec.size).grow(0.0002)
			verify(occupied.encloses(box), "Visible detail stays inside its occupied box.")
			verify(piece.material_override != null or piece.mesh.surface_get_material(0) != null,
				"Each part keeps its sourced or deliberate fallback finish.")
	await physics_frame
	verify(physical._geometry_registered(),
		"The physics server holds projected component shapes in the actor scene.")
	var query := PhysicsRayQueryParameters3D.create(Vector3(0.8, 0.45, 0.0), Vector3(-0.8, 0.45, 0.0))
	query.collision_mask = Geometry.MACHINE_LAYER
	verify(root.world_3d.direct_space_state.intersect_ray(query).get("collider") == physical.component_bodies.frame,
		"A physical ray through the frame reaches its actor-blocking body.")
	var actor := PhysicalActor.new()
	actor.position = Vector3(0.0, 0.9, -0.8)
	root.add_child(actor)
	await physics_frame
	var contact: KinematicCollision3D = actor.move_and_collide(Vector3(0, 0, 1.0))
	verify(contact != null and contact.get_collider() == physical.component_bodies.frame,
		"The existing physical character cannot walk through the grounded frame.")
	actor.queue_free()
	facts.state.placed_components.tray.center = [0, 0, -1]
	facts.state.placed_components.tray.occupied.center = [0.0, 0.7425, -0.4125]
	facts.state.placed_components.shaft.center = [0, 0, 1]
	facts.state.placed_components.shaft.occupied.center = [0.0, 0.825, 0.4125]
	facts.state.revision = 2
	host.state = facts.state
	physical.sync_topology()
	view.refresh()
	verify(is_equal_approx(physical.component_bodies.tray.position.z, -0.4125)
		and is_equal_approx(physical.component_bodies.shaft.position.z, 0.4125),
		"A mirrored receiver and side drive move the physical components.")
	verify(view.get_children().filter(func(node: Node): return node.has_meta("component_entity")).size() == 5,
		"The mirrored arrangement rebuilds five parts without duplicate visuals.")
	var mirrored_shaft: Node3D
	for node: Node in view.get_children():
		if node.get_meta("component_entity", "") == "shaft":
			mirrored_shaft = node
	var rod: Node3D = mirrored_shaft.get_node("LooseDriveShaft") if mirrored_shaft != null else null
	var core: MeshInstance3D = rod.get_node("Shaft") if rod != null else null
	verify(rod != null and core != null and core.mesh is CylinderMesh
		and absf(rod.basis.y.z) > 0.99 and is_equal_approx(core.mesh.height, 0.41)
		and mirrored_shaft.get_node_or_null("FrameJoinSocket") != null
		and mirrored_shaft.find_children("BearingShell*", "MeshInstance3D", false, false).size() == 2,
		"A ready side drive reaches its native box face and seats two journals toward the frame.")
	facts.state.placed_components.erase("tray")
	facts.state.collector_assemblies[0].status = "missing_receiver"
	facts.state.collector_assemblies[0].erase("parts")
	facts.state.revision = 3
	host.state = facts.state
	physical.sync_topology()
	view.refresh()
	verify(physical.component_bodies.size() == 4 and not physical.component_bodies.has("tray")
		and view.get_children().filter(func(node: Node): return node.has_meta("component_entity")).size() == 4,
		"Removing the receiver clears its visual and collider without inventing readiness.")
	for node: Node in view.get_children():
		if node.get_meta("component_entity", "") == "shaft":
			var unready_rod: Node3D = node.get_node("LooseDriveShaft")
			verify(absf(unready_rod.basis.y.z) > 0.99
				and is_equal_approx((unready_rod.get_node("Shaft") as MeshInstance3D).mesh.height, 0.41)
				and node.get_node_or_null("FrameJoinSocket") != null
				and node.find_children("BearingShell*", "MeshInstance3D", false, false).size() == 2,
				"Removing the receiver leaves the independently placed shaft fitted to its frame without making the collector ready.")
			var occupied_shaft: Dictionary = Geometry.component_boxes(facts.state).boxes.shaft
			for detail: Node in node.find_children("*", "MeshInstance3D", true, false):
				var mesh := detail as MeshInstance3D
				verify(AABB(occupied_shaft.center - occupied_shaft.size * 0.5,
					occupied_shaft.size).grow(0.0002).encloses(mesh.global_transform * mesh.mesh.get_aabb()),
					"The partial shaft fitting remains inside its independent native occupied box.")
	facts.state.collector_assemblies[0].status = "unsupported"
	facts.state.revision = 4
	host.state = facts.state
	view.refresh()
	for node: Node in view.get_children():
		if node.get_meta("component_entity", "") == "shaft":
			var loose_rod: Node3D = node.get_node("LooseDriveShaft")
			verify(loose_rod.basis.y.y > 0.99 and node.get_node_or_null("FrameJoinSocket") == null,
				"An unsupported face status does not supply a speculative frame fitting.")
	var south: Dictionary = _component_fixture()
	south.placed_components.mount.center = [0, 1, 1]
	south.placed_components.mount.occupied.center = [0.0, 1.3375, 0.4125]
	south.placed_components.edge.center = [0, 1, 2]
	south.placed_components.edge.occupied.center = [0.0, 1.2225, 0.825]
	south.placed_components.tray.center = [1, 0, 0]
	south.placed_components.tray.occupied.center = [0.4125, 0.7425, 0.0]
	south.placed_components.shaft.center = [-1, 0, 0]
	south.placed_components.shaft.occupied.center = [-0.4125, 0.825, 0.0]
	south.collector_assemblies[0].toward_ore = [0, 0, 1]
	facts.state = south
	host.state = south
	physical.sync_topology()
	view.refresh()
	var south_anchors: Dictionary = {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			south_anchors[node.get_meta("component_entity")] = node
	var south_blade := south_anchors.edge.get_node("FormedBlade") as MeshInstance3D
	var south_clamp := south_anchors.mount.get_node("CastToolClamp") as Node3D
	var south_receiver_hook := south_anchors.tray.get_node("ReceiverHookLeft") as MeshInstance3D
	var south_crosshead := south_anchors.tray.get_node("ReceiverFrameCrosshead") as MeshInstance3D
	var south_receiver_box: Dictionary = Geometry.component_boxes(south).boxes.tray
	verify(south_receiver_hook.position.x < -0.15
		and AABB(south_receiver_box.center - south_receiver_box.size * 0.5,
			south_receiver_box.size).grow(0.0002).encloses(
			south_crosshead.global_transform * south_crosshead.mesh.get_aabb()),
		"The south-facing receiver docks toward its frame inside its own native occupied box.")
	verify(south_blade.basis.x.z < -0.89 and south_clamp.basis.z.z < -0.99,
		"The raised south-facing native workcell turns the blade lip toward ore and its jaw toward the blade.")
	var south_front := INF
	var south_root := -INF
	for point: Vector3 in south_blade.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		south_front = minf(south_front, point.x)
		south_root = maxf(south_root, point.x)
	verify(is_equal_approx(south_front, -0.175) and is_equal_approx(south_root, 0.075)
		and south_blade.scale == Vector3.ONE,
		"The north/south blade forms a shorter lip within the box without scaling its fitted root.")
	var south_boxes: Dictionary = Geometry.component_boxes(south).boxes
	for id in ["mount", "edge"]:
		var spec: Dictionary = south_boxes[id]
		var body: StaticBody3D = physical.component_bodies[id]
		var collider: CollisionShape3D = body.get_child(0)
		verify(body.position == spec.center and collider.shape.size == spec.size,
			"Facing a raised tool preserves its exact native actor-blocking box.")
		for found: Node in south_anchors[id].find_children("*", "MeshInstance3D", true, false):
			var piece := found as MeshInstance3D
			var relative: Transform3D = south_anchors[id].global_transform.affine_inverse() * piece.global_transform
			var detail: AABB = relative * piece.mesh.get_aabb()
			verify(AABB(-spec.size * 0.5, spec.size).grow(0.0002).encloses(detail),
				"South-facing %s/%s stays inside its native occupied box: %s." % [id, piece.name, detail])
	south.placed_components.erase("shaft")
	south.collector_assemblies[0].status = "missing_receiver"
	host.state = south
	physical.sync_topology()
	view.refresh()
	for node: Node in view.get_children():
		if node.get_meta("component_entity", "") == "edge":
			verify((node.get_node("FormedBlade") as MeshInstance3D).basis.x.z < -0.89,
				"The trusted ore face keeps a placed cutter oriented while an unrelated drive part is missing.")
	verify(not physical.component_bodies.has("shaft"),
		"Removing the drive part also removes only its native physical body.")
	south.collector_assemblies[0].status = "unsupported"
	view.refresh()
	for node: Node in view.get_children():
		if node.get_meta("component_entity", "") == "edge":
			verify((node.get_node("FormedBlade") as MeshInstance3D).basis.x.x > 0.99,
				"An unknown assembly status cannot supply a speculative tool orientation.")
	var supported: Dictionary = _component_fixture()
	# A larger native occupied descriptor is a new placement generation; the
	# actor bridge deliberately keeps a placed generation's collision immutable.
	supported.placed_components.mount.generation = 2
	supported.placed_components.edge.generation = 2
	supported.placed_components.mount.center = [0, 1, 1]
	supported.placed_components.mount.occupied.center = [0.0, 0.75875, 0.4125]
	supported.placed_components.mount.occupied.half = [0.20, 0.75875, 0.21]
	supported.placed_components.edge.center = [0, 1, 2]
	supported.placed_components.edge.occupied.center = [0.0, 0.67125, 0.825]
	supported.placed_components.edge.occupied.half = [0.21, 0.67125, 0.2025]
	supported.placed_components.tray.center = [1, 0, 0]
	supported.placed_components.tray.occupied.center = [0.4125, 0.7425, 0.0]
	supported.placed_components.shaft.center = [-1, 0, 0]
	supported.placed_components.shaft.occupied.center = [-0.4125, 0.825, 0.0]
	supported.collector_assemblies[0].toward_ore = [0, 0, 1]
	facts.state = supported
	host.state = supported
	physical.sync_topology()
	view.refresh()
	var supported_boxes: Dictionary = Geometry.component_boxes(supported).boxes
	var supported_anchors: Dictionary = {}
	for node: Node in view.get_children():
		var id: Variant = node.get_meta("component_entity", "")
		if id in ["frame", "mount", "edge"]:
			supported_anchors[id] = node
		if id not in ["mount", "edge"]:
			continue
		var label := "Mount" if id == "mount" else "Edge"
		var shoe := node.get_node(label + "GroundShoeLeft") as MeshInstance3D
		var shoe_bounds: AABB = shoe.global_transform * shoe.mesh.get_aabb()
		verify(absf(shoe_bounds.position.y) < 0.001,
			"A confirmed supported %s part meets the assembly floor." % id)
		var dock := node.get_node(label + "RearDock") as MeshInstance3D
		var dock_bounds: AABB = dock.global_transform * dock.mesh.get_aabb()
		var neighbour_face := 0.2025 if id == "mount" else 0.6225
		verify(absf(dock_bounds.position.z - neighbour_face) < 0.001,
			"The %s part touches only its native neighbour face." % id)
		var spec: Dictionary = supported_boxes[id]
		var body: StaticBody3D = physical.component_bodies[id]
		verify(body.position == spec.center and (body.get_child(0) as CollisionShape3D).shape.size == spec.size,
			"The extended %s actor collider uses its exact native occupied box." % id)
		for found: Node in node.find_children("*", "MeshInstance3D", true, false):
			var piece := found as MeshInstance3D
			var detail: AABB = piece.global_transform * piece.mesh.get_aabb()
			verify(AABB(spec.center - spec.size * 0.5, spec.size).grow(0.0002).encloses(detail),
				"The supported %s/%s mesh stays inside the native occupied box." % [id, piece.name])
	var rail := supported_anchors.mount.get_node("MountForwardRailLeft") as MeshInstance3D
	var edge_dock := supported_anchors.edge.get_node("EdgeRearDock") as MeshInstance3D
	var rail_bounds: AABB = rail.global_transform * rail.mesh.get_aabb()
	var edge_dock_bounds: AABB = edge_dock.global_transform * edge_dock.mesh.get_aabb()
	verify(absf(rail_bounds.end.z - edge_dock_bounds.position.z) < 0.001
		and rail_bounds.position.y < edge_dock_bounds.end.y
		and edge_dock_bounds.position.y < rail_bounds.end.y,
		"The framed mount rails physically meet the independently placed edge dock.")
	var frame_tie := supported_anchors.mount.get_node("MountFrameTie") as MeshInstance3D
	var frame_bed := supported_anchors.frame.get_node("BedCrossRailRear") as MeshInstance3D
	var tie_bounds: AABB = frame_tie.global_transform * frame_tie.mesh.get_aabb()
	var bed_bounds: AABB = frame_bed.global_transform * frame_bed.mesh.get_aabb()
	verify(absf(tie_bounds.position.z - bed_bounds.end.z) < 0.001
		and tie_bounds.position.y < bed_bounds.end.y and bed_bounds.position.y < tie_bounds.end.y,
		"The raised mount ties to the independent frame's actual open bed.")
	supported.placed_components.erase("frame")
	supported.collector_assemblies[0].status = "missing_frame"
	facts.state = supported
	host.state = supported
	physical.sync_topology()
	view.refresh()
	var retained_supports := 0
	for node: Node in view.get_children():
		var id: Variant = node.get_meta("component_entity", "")
		if id == "mount" and node.has_node("MountSupportPostLeft"):
			retained_supports += 1
		if id == "edge" and node.has_node("EdgeSupportPostLeft"):
			retained_supports += 1
	verify(retained_supports == 2 and not physical.component_bodies.has("frame"),
		"Removing the frame removes its body while independently placed supports remain grounded.")
	supported.placed_components.mount.occupied.center = [0.0, 1.3375, 0.4125]
	supported.placed_components.mount.occupied.half = [0.20, 0.18, 0.19]
	supported.placed_components.mount.generation = 3
	facts.state = supported
	host.state = supported
	physical.sync_topology()
	view.refresh()
	for node: Node in view.get_children():
		if node.get_meta("component_entity", "") == "mount":
			verify(node.find_children("MountSupportPost*", "MeshInstance3D", true, false).is_empty(),
				"A short native occupied box cannot gain decorative load-bearing legs.")
	var west_supported: Dictionary = _component_fixture()
	west_supported.placed_components.mount.occupied.center = [-0.4125, 0.5525, 0.0]
	west_supported.placed_components.mount.occupied.half = [0.21, 0.5525, 0.19]
	west_supported.placed_components.edge.occupied.center = [-0.825, 0.465, 0.0]
	west_supported.placed_components.edge.occupied.half = [0.2025, 0.465, 0.18]
	facts.state = west_supported
	host.state = west_supported
	physical.sync_topology()
	view.refresh()
	var west_boxes: Dictionary = Geometry.component_boxes(west_supported).boxes
	var west_anchors: Dictionary = {}
	for node: Node in view.get_children():
		var id: Variant = node.get_meta("component_entity", "")
		if id not in ["mount", "edge"]:
			continue
		west_anchors[id] = node
		var label := "Mount" if id == "mount" else "Edge"
		var shoe := node.get_node(label + "GroundShoeLeft") as MeshInstance3D
		var shoe_bounds: AABB = shoe.global_transform * shoe.mesh.get_aabb()
		verify(absf(shoe_bounds.position.y) < 0.001,
			"The lower west-facing %s part also stands on the assembly floor." % id)
		var spec: Dictionary = west_boxes[id]
		for found: Node in node.find_children("*", "MeshInstance3D", true, false):
			var piece := found as MeshInstance3D
			var detail: AABB = piece.global_transform * piece.mesh.get_aabb()
			verify(AABB(spec.center - spec.size * 0.5, spec.size).grow(0.0002).encloses(detail),
				"The west-facing %s/%s stays inside its native occupied box." % [id, piece.name])
	var west_rail := west_anchors.mount.get_node("MountForwardRailLeft") as MeshInstance3D
	var west_dock := west_anchors.edge.get_node("EdgeRearDock") as MeshInstance3D
	var west_rail_bounds: AABB = west_rail.global_transform * west_rail.mesh.get_aabb()
	var west_dock_bounds: AABB = west_dock.global_transform * west_dock.mesh.get_aabb()
	verify(absf(west_rail_bounds.position.x - west_dock_bounds.end.x) < 0.001,
		"The lower west-facing independent tool parts meet at their admitted faces.")
	view.free()
	physical.free()
	await process_frame

func _verify_press_drive_contact(anchors: Dictionary, state: Dictionary) -> void:
	var rod: MeshInstance3D = anchors.shaft.get_node("LooseDriveShaft/Shaft")
	var hub: MeshInstance3D = anchors.cog.get_node("PlacedDriveCog/CogHub")
	var crown: MeshInstance3D = anchors.mount.get_node("PressCrownBearing")
	var axis: Vector3 = (hub.global_position - rod.global_position).normalized()
	var rod_half := rod.global_basis.y * (rod.mesh as CylinderMesh).height * 0.5
	var hub_half := hub.global_basis.y * (hub.mesh as CylinderMesh).height * 0.5
	var rod_tip := rod.global_position + axis * absf(rod_half.dot(axis))
	var hub_tip := hub.global_position - axis * absf(hub_half.dot(axis))
	verify(absf(rod.global_basis.y.normalized().dot(axis)) > 0.999 \
		and absf(hub.global_basis.y.normalized().dot(axis)) > 0.999,
		"The shaft core and cog hub share the actual drive axis.")
	verify(rod_tip.distance_to(hub_tip) < 0.0002,
		"The visible press shaft and cog hub meet at their confirmed common-grid positions.")
	var crown_bounds: AABB = crown.global_transform * crown.mesh.get_aabb()
	var crown_tip := crown_bounds.get_center() + axis * crown_bounds.size.dot(axis.abs()) * 0.5
	var rod_near_tip := rod.global_position - axis * absf(rod_half.dot(axis))
	verify(crown_tip.distance_to(rod_near_tip) < 0.0002,
		"The crown bearing seats the other end of the same press shaft.")
	var boxes: Dictionary = Geometry.component_boxes(state).boxes
	for member in [["shaft", rod], ["cog", hub], ["mount", crown]]:
		var box: Dictionary = boxes[member[0]]
		var mesh: MeshInstance3D = member[1]
		verify(AABB(box.center - box.size * 0.5, box.size).grow(0.0002).encloses(mesh.global_transform * mesh.mesh.get_aabb()),
			"The connected drive member remains inside its own native occupied volume.")

func _component_mesh_shapes(anchor: Node3D) -> Array:
	var shapes := []
	for node: Node in anchor.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		shapes.append({"transform": mesh.transform, "bounds": mesh.mesh.get_aabb()})
	return shapes

func _press_component_view() -> void:
	# Native Host owns these seven occupied records. This fixture inspects only
	# the existing renderer and actor collision consumer at its projected faces.
	var state := {"context": "press-component-view", "revision": 1,
		"options": {"native": true, "physical": true}, "actors": {}, "entities": {},
		"foundations": {}, "transmission_parts": {}, "belt_spans": {}, "motion": {},
		"collector_assemblies": [], "placed_components": {
			"frame": _component_record("wooden_frame", [0, 0, 0], [0.0, 0.45, 0.0], [0.2025, 0.45, 0.2025]),
			"anvil": _component_record("anvil", [0, 1, 0], [0.0, 0.61875, 0.0], [0.2025, 0.20625, 0.14]),
			"ram": _component_record("ram_face", [0, 2, 0], [0.0, 1.340625, 0.0], [0.14, 0.515625, 0.14]),
			"guide": _component_record("sliding_guide", [0, 3, 0], [0.0, 1.919375, 0.0], [0.14, 0.475625, 0.14]),
			"mount": _component_record("tool_mount", [0, 4, 0], [0.0, 2.575, 0.0], [0.2075, 0.18, 0.2075]),
			"shaft": _component_record("wooden_shaft", [1, 4, 0], [0.4125, 2.475, 0.0], [0.205, 0.12, 0.205]),
			"cog": _component_record("wooden_cog", [2, 4, 0], [0.825, 2.475, 0.0], [0.2075, 0.14, 0.2075])},
		"press_assemblies": [{"status": "ready", "parts": {"frame": "frame", "anvil": "anvil",
			"ram": "ram", "guide": "guide", "mount": "mount", "shaft": "shaft", "drive_cog": "cog"}}]}
	var parsed: Dictionary = Geometry.component_boxes(state)
	verify(parsed.get("accepted", false) and parsed.boxes.size() == 7,
		"The complete press retains seven separate native occupied boxes.")
	var facts := PhysicalProjection.new()
	facts.state = state
	var physical := ActorWorld.new()
	root.add_child(physical)
	verify(physical.configure(facts).get("accepted", false) and physical.component_bodies.size() == 7,
		"The actual actor world registers every confirmed press part separately.")
	var host := HostStub.new()
	host.state = state
	var view := Presenter.new()
	root.add_child(view)
	view.configure(host)
	var anchors := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			anchors[node.get_meta("component_entity")] = node
	verify(anchors.size() == 7 and anchors.anvil.get_node_or_null("OpenAnvilSeat") != null
		and anchors.ram.get_node_or_null("MovingDie") != null
		and anchors.guide.get_node_or_null("GuideRail") != null
		and anchors.mount.get_node_or_null("PressCrown") != null,
		"The seven identities form a supported anvil, die, guide and press crown.")
	var framed_foot := anchors.anvil.get_node("CastPedestalFoot") as MeshInstance3D
	var framed_shelf := anchors.frame.get_node("AnvilShelf") as MeshInstance3D
	var framed_web := anchors.anvil.get_node("WorkbedWeb") as MeshInstance3D
	var foot_bounds: AABB = framed_foot.global_transform * framed_foot.mesh.get_aabb()
	var shelf_bounds: AABB = framed_shelf.global_transform * framed_shelf.mesh.get_aabb()
	var web_bounds: AABB = framed_web.global_transform * framed_web.mesh.get_aabb()
	verify(absf(foot_bounds.position.y - 0.4125) < 0.0002
		and absf(shelf_bounds.end.y - foot_bounds.position.y) < 0.0002,
		"The framed anvil foot meets its raised shelf without a visible unsupported gap.")
	for rail_name in ["BedCrossRailFront", "BedCrossRailRear", "BedSideRailLeft", "BedSideRailRight"]:
		var rail := anchors.frame.get_node(rail_name) as MeshInstance3D
		verify(not (rail.global_transform * rail.mesh.get_aabb()).intersects(web_bounds),
			"The frame bed leaves real clearance around the anvil web.")
	var rotor: Node3D = anchors.cog.get_node_or_null("PlacedDriveCog")
	verify(rotor != null and rotor.find_children("CogTooth*", "MeshInstance3D", false, false).size() == 12
		and anchors.shaft.get_node_or_null("LooseDriveShaft") != null,
		"The projected shaft and cog are distinct supported drive parts.")
	_verify_press_drive_contact(anchors, state)
	for id: String in parsed.boxes:
		var spec: Dictionary = parsed.boxes[id]
		var body: StaticBody3D = physical.component_bodies[id]
		var collider: CollisionShape3D = body.get_child(0)
		verify(body.get_meta("component_entity") == id and body.position == spec.center
			and collider.shape.size == spec.size and anchors[id].position == spec.center,
			"Press visuals and actor collision share each projected native identity and occupied box.")
		for found: Node in anchors[id].find_children("*", "MeshInstance3D", true, false):
			var mesh := found as MeshInstance3D
			var relative: Transform3D = anchors[id].global_transform.affine_inverse() * mesh.global_transform
			verify(AABB(-spec.size * 0.5, spec.size).grow(0.0002).encloses(relative * mesh.mesh.get_aabb()),
				"Each visible press member stays inside its own native collision volume.")
	state.placed_components.shaft.center = [-1, 4, 0]
	state.placed_components.shaft.occupied.center = [-0.4125, 2.475, 0.0]
	state.placed_components.cog.center = [-2, 4, 0]
	state.placed_components.cog.occupied.center = [-0.825, 2.475, 0.0]
	state.revision = 2
	host.state = state
	physical.sync_topology()
	view.refresh()
	var mirrored := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			mirrored[node.get_meta("component_entity")] = node
	var mirrored_shaft: Node3D = mirrored.shaft.get_node_or_null("LooseDriveShaft")
	verify(mirrored.size() == 7 and mirrored_shaft != null and mirrored_shaft.basis.y.x > 0.99
		and physical.component_bodies.shaft.position.x < 0.0,
		"An opposite-side confirmed drive still fits the same seven-part press.")
	_verify_press_drive_contact(mirrored, state)
	var retained_shaft_length: float = (mirrored_shaft.get_node("Shaft").mesh as CylinderMesh).height
	for direction in [-1, 1]:
		state.placed_components.shaft.center = [0, 4, direction]
		state.placed_components.shaft.occupied.center = [0.0, 2.475, float(direction) * 0.4125]
		state.placed_components.cog.center = [0, 4, direction * 2]
		state.placed_components.cog.occupied.center = [0.0, 2.475, float(direction) * 0.825]
		state.revision += 1
		host.state = state
		physical.sync_topology()
		view.refresh()
		var transverse := {}
		for node: Node in view.get_children():
			if node.has_meta("component_entity"):
				transverse[node.get_meta("component_entity")] = node
		_verify_press_drive_contact(transverse, state)
		verify(physical.component_bodies.shaft.position.z * float(direction) > 0.4,
			"The transverse press keeps the shaft's native body on its confirmed grid axis.")
	state.placed_components.erase("cog")
	state.press_assemblies[0] = {"frame": "frame", "center": [0, 0, 0], "status": "missing_cog"}
	state.revision += 1
	host.state = state
	physical.sync_topology()
	view.refresh()
	var partial := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			partial[node.get_meta("component_entity")] = node
	var partial_shaft: Node3D = partial.shaft.get_node_or_null("LooseDriveShaft")
	verify(not physical.component_bodies.has("cog") and partial.size() == 6
		and partial.mount.get_node_or_null("PressCrown") != null
		and partial_shaft != null and partial_shaft.basis.y.z < -0.99 \
		and is_equal_approx((partial_shaft.get_node("Shaft").mesh as CylinderMesh).height, retained_shaft_length),
		"Reclaiming the cog clears its body while the remaining crown and shaft keep their press fitting.")
	view.free()
	physical.free()
	await process_frame

func _broad_press_component_view() -> void:
	# The twenty records use Host's one-quarter tile centers and occupied
	# dimensions. The broad row order is native z row, then x column.
	var state: Dictionary = {"context": "broad-press-component-view", "revision": 1,
		"options": {"native": true, "physical": true}, "actors": {}, "entities": {},
		"foundations": {}, "transmission_parts": {}, "belt_spans": {}, "motion": {},
		"collector_assemblies": [], "press_assemblies": [], "guided_press_assemblies": [],
		"placed_components": {}}
	var parts := {"anvils": [], "rams": [], "guides": [], "shafts": [], "drive_cogs": []}
	var raised: bool = "--broad-press-raised-only" in OS.get_cmdline_user_args()
	var base_y: int = 4 if raised else 0
	var cells := [Vector3i(0, base_y, 0), Vector3i(4, base_y, 0),
		Vector3i(0, base_y, 4), Vector3i(4, base_y, 4)]
	var sides := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.BACK, Vector3i.RIGHT]
	var step: float = Geometry.HEIGHT_STEP
	for pad in range(4):
		var cell: Vector3i = cells[pad]
		var side: Vector3i = sides[pad]
		var entries := [
			["anvils", "anvil", "anvil", cell, 0.20625, 0.20625, 0.2025],
			["rams", "ram", "ram_face", cell + Vector3i(0, 1, 0), 0.928125, 0.515625, 0.14],
			["guides", "guide", "sliding_guide", cell + Vector3i(0, 3, 0), 1.919375, 0.475625, 0.14],
			["shafts", "shaft", "wooden_shaft", cell + Vector3i(0, 4, 0) + side, 2.475, 0.12, 0.205],
			["drive_cogs", "cog", "wooden_cog", cell + Vector3i(0, 4, 0) + side * 2, 2.475, 0.14, 0.2075]]
		for entry in entries:
			var id: String = "%s%d" % [entry[1], pad]
			var point: Vector3i = entry[3]
			state.placed_components[id] = _component_record(entry[2], [point.x, point.y, point.z],
				[float(point.x) * step, entry[4] + float(base_y) * step, float(point.z) * step],
				[entry[6], entry[5], 0.14 if entry[2] == "anvil" else entry[6]])
			parts[entry[0]].append(id)
	state.broad_press_assemblies = [{"origin": [0, base_y, 0], "geometry_status": "ready",
		"status": "ready", "work_centers": [[0, base_y, 0], [4, base_y, 0],
			[0, base_y, 4], [4, base_y, 4]],
		"parts": parts}]
	state.motion.shaft0 = {"state": "rotating", "numerator": 1, "denominator": 1}
	state.motion.cog0 = {"state": "rotating", "numerator": 1, "denominator": 1}
	state.motion.shaft1 = {"state": "stalled", "numerator": 0, "denominator": 1}
	var parsed: Dictionary = Geometry.component_boxes(state)
	verify(parsed.get("accepted", false) and parsed.boxes.size() == 20,
		"Four native broad pads retain twenty individually occupied placed parts.")
	var host := HostStub.new()
	host.state = state
	var view := Presenter.new()
	root.add_child(view)
	view.configure(host)
	var anchors := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			anchors[node.get_meta("component_entity")] = node
	verify(anchors.size() == 20, "The broad press does not collapse four native pads into one visual body.")
	var broad_guide_shapes := _component_mesh_shapes(anchors.guide1)
	var broad_guide_preview := Node3D.new()
	root.add_child(broad_guide_preview)
	view.preview_component(broad_guide_preview, "sliding_guide", parsed.boxes.guide1.size)
	verify(broad_guide_shapes == _component_mesh_shapes(broad_guide_preview),
		"A broad pad guide uses the same selected rails as its standalone placement preview.")
	broad_guide_preview.free()
	for pad in range(4):
		var anvil: Node3D = anchors["anvil%d" % pad]
		var ram: Node3D = anchors["ram%d" % pad]
		var guide: Node3D = anchors["guide%d" % pad]
		var shaft: Node3D = anchors["shaft%d" % pad].get_node_or_null("LooseDriveShaft")
		var cog: Node3D = anchors["cog%d" % pad].get_node_or_null("PlacedDriveCog")
		var toward: Vector3 = Vector3(-sides[pad].x, 0, -sides[pad].z)
		verify(anvil.get_node_or_null("OpenAnvilSeat") != null
			and ram.get_node_or_null("MovingDie") != null
			and guide.get_node_or_null("GuideRail") != null
			and anchors["shaft%d" % pad].get_node_or_null("GuidedBearingSeat") != null
			and shaft != null and cog != null
			and shaft.global_basis.y.dot(toward) > 0.99
			and cog.global_basis.y.dot(toward) > 0.99,
			"Each distinct broad pad fits its work face and exterior drive toward its own guide.")
	for id: String in parsed.boxes:
		var spec: Dictionary = parsed.boxes[id]
		verify(anchors[id].position == spec.center,
			"Broad pad visuals retain the exact native occupied center of each placed identity.")
		for found: Node in anchors[id].find_children("*", "MeshInstance3D", true, false):
			var mesh := found as MeshInstance3D
			var relative: Transform3D = anchors[id].global_transform.affine_inverse() * mesh.global_transform
			verify(AABB(-spec.size * 0.5, spec.size).grow(0.0002).encloses(relative * mesh.mesh.get_aabb()),
				"Broad fittings stay inside their own native occupied boxes.")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--broad-capture=") and DisplayServer.get_name() != "headless":
			root.size = Vector2i(1280, 800)
			var environment := Environment.new()
			environment.background_mode = Environment.BG_COLOR
			environment.background_color = Color("49535d")
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.ambient_light_color = Color.WHITE
			environment.ambient_light_energy = 1.4
			var world_environment := WorldEnvironment.new()
			world_environment.environment = environment
			root.add_child(world_environment)
			var light := DirectionalLight3D.new()
			light.rotation_degrees = Vector3(-48, -35, 0)
			light.light_energy = 2.0
			root.add_child(light)
			var camera := Camera3D.new()
			camera.position = Vector3(4.2, 3.7 + float(base_y) * step, 5.0)
			root.add_child(camera)
			camera.look_at(Vector3(0.825, 1.45 + float(base_y) * step, 0.825))
			camera.fov = 45.0
			camera.current = true
			for frame in range(3):
				await process_frame
				await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(argument.trim_prefix("--broad-capture=")) == OK,
				"A passive broad-pad image retains the four distinct native work faces.")
			camera.free()
			light.free()
			world_environment.free()
	var partial: Dictionary = state.duplicate(true)
	partial.placed_components.erase("ram1")
	partial.broad_press_assemblies = [{"origin": [0, base_y, 0], "geometry_status": "missing_ram",
		"status": "missing_ram"}]
	partial.revision = 2
	host.state = partial
	view.refresh()
	var remaining := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			remaining[node.get_meta("component_entity")] = node
	verify(remaining.size() == 19 and not remaining.has("ram1")
		and remaining["ram0"].get_node_or_null("MovingDie") != null
		and remaining["shaft2"].get_node_or_null("GuidedBearingSeat") != null,
		"Losing one pad part leaves the other native identities and fittings in view.")
	verify(_component_mesh_shapes(remaining.guide1) == broad_guide_shapes,
		"Removing a broad pad ram does not resize its unchanged guide.")
	view.free()
	await process_frame

func _capture_channel_pose(path: String, along_z: bool) -> void:
	root.size = Vector2i(1280, 800)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("49535d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.4
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.light_energy = 2.0
	root.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(6.6, 3.25, 4.2) if along_z else Vector3(4.2, 3.25, 6.6)
	root.add_child(camera)
	camera.look_at(Vector3(0.7, 0.65, 2.2) if along_z else Vector3(2.2, 0.65, 0.7))
	camera.fov = 45.0
	camera.current = true
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(path) == OK,
		"A passive image retains the channel and confirmed sheet pose.")
	camera.free()
	light.free()
	world_environment.free()

func _channel_component_view() -> void:
	var along_z: bool = "--channel-z-only" in OS.get_cmdline_user_args()
	var sheet_mode: bool = "--channel-sheet-only" in OS.get_cmdline_user_args()
	var broad_kind := "channel_broad_z" if along_z else "channel_broad_x"
	var narrow_kind := "channel_narrow_z" if along_z else "channel_narrow_x"
	var broad_center := [0.825, 0.5135, 0.0] if along_z else [0.0, 0.5135, 0.825]
	var broad_half := [1.65, 0.5135, 0.825] if along_z else [0.825, 0.5135, 1.65]
	var second_cell := [0, 0, 4] if along_z else [4, 0, 0]
	var second_center := [0.825, 0.5135, 1.65] if along_z else [1.65, 0.5135, 0.825]
	var narrow_cell := [0, 0, 12] if along_z else [12, 0, 0]
	var narrow_center := [0.0, 0.5135, 4.95] if along_z else [4.95, 0.5135, 0.0]
	var state: Dictionary = {"context": "channel-component-view", "revision": 1,
		"options": {"native": true, "physical": true}, "actors": {}, "entities": {},
		"foundations": {}, "transmission_parts": {}, "belt_spans": {}, "motion": {},
		"collector_assemblies": [], "press_assemblies": [],
		"placed_components": {
			"broad0": _component_record(broad_kind, [0, 0, 0], broad_center, broad_half),
			"broad1": _component_record(broad_kind, second_cell, second_center, broad_half),
			"narrow": _component_record(narrow_kind, narrow_cell, narrow_center,
				[0.825, 0.5135, 0.825])}}
	if sheet_mode:
		state.placed_components["broad2"] = _component_record(broad_kind,
			[0, 0, 8] if along_z else [8, 0, 0],
			[0.825, 0.5135, 3.3] if along_z else [3.3, 0.5135, 0.825], broad_half)
		state.dropped_material = [{"center": [0, 0, 0], "raw": 0, "products": 0,
			"offcuts": 0, "sheets": 1, "work_lots": [],
			"sheet_items": [{"id": 7001, "rotation": 1}]}]
	var expected_parts: int = 4 if sheet_mode else 3
	var parsed: Dictionary = Geometry.component_boxes(state)
	verify(parsed.get("accepted", false) and parsed.boxes.size() == expected_parts,
		"The source-matched view uses two broad native boxes and one narrow box.")
	var invalid: Dictionary = state.duplicate(true)
	invalid.placed_components.broad0.occupied.half[0 if along_z else 2] = 1.66
	verify(not Geometry.component_boxes(invalid).get("accepted", false),
		"A broad channel cannot claim more than its two-workcell native extent.")
	invalid = state.duplicate(true)
	invalid.placed_components.narrow.occupied.half[2] = 1.65
	verify(not Geometry.component_boxes(invalid).get("accepted", false),
		"A narrow channel cannot borrow the broad geometry allowance.")
	var opening := SuppliedOpening.new()
	for id: String in parsed.boxes:
		var placed: Dictionary = state.placed_components[id]
		var preview_box: Dictionary = opening._component_candidate_box(placed.component, placed.center)
		verify(preview_box.center.distance_to(parsed.boxes[id].center) < 0.0001
			and preview_box.size.distance_to(parsed.boxes[id].size) < 0.0001,
			"The build preview covers the exact native narrow or broad footprint.")
	opening.free()
	var facts := PhysicalProjection.new()
	facts.state = state
	var physical := ActorWorld.new()
	root.add_child(physical)
	verify(physical.configure(facts).get("accepted", false) and physical.component_bodies.size() == expected_parts,
		"The physical actor scene registers each broad and narrow occupied box.")
	for id: String in parsed.boxes:
		var body: StaticBody3D = physical.component_bodies[id]
		var collider: CollisionShape3D = body.get_child(0)
		verify(body.position == parsed.boxes[id].center
			and collider.shape.size == parsed.boxes[id].size,
			"The actor collision size follows the exact selected channel footprint.")
	var host := HostStub.new()
	host.state = state
	var view := Presenter.new()
	root.add_child(view)
	view.configure(host)
	var anchors := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			anchors[node.get_meta("component_entity")] = node
	verify(anchors.size() == expected_parts,
		"Each channel segment retains its own native placed identity.")
	for id: String in parsed.boxes:
		var spec: Dictionary = parsed.boxes[id]
		verify(anchors[id].position == spec.center and anchors[id].get_node_or_null("ChannelDeck") != null,
			"The channel deck follows the selected native footprint and occupied center.")
		for found: Node in anchors[id].find_children("*", "MeshInstance3D", true, false):
			var mesh := found as MeshInstance3D
			var relative: Transform3D = anchors[id].global_transform.affine_inverse() * mesh.global_transform
			verify(AABB(-spec.size * 0.5, spec.size).grow(0.0002).encloses(relative * mesh.mesh.get_aabb()),
				"Every rail and support stays inside its selected native bounds.")
	var preview := Node3D.new()
	root.add_child(preview)
	view.preview_component(preview, broad_kind, parsed.boxes.broad0.size)
	verify(_component_mesh_shapes(anchors.broad0) == _component_mesh_shapes(preview),
		"A broad channel preview and its installed segment use the same shape.")
	preview.free()
	if sheet_mode:
		var sheet: Node3D = view.get_node_or_null("CopperSheet")
		var body: MeshInstance3D = sheet.get_node_or_null("SheetBody") if sheet != null else null
		verify(sheet != null and body != null and body.mesh.get_aabb().size.x > 3.0
			and body.mesh.get_aabb().size.z > 3.0
			and sheet.position.distance_to(Vector3(0.825, 0.938, 0.825)) < 0.0001
			and absf(sheet.rotation.y - PI * 0.5) < 0.0001,
			"One confirmed sheet spans four channel workcells above the deck with its native rotation.")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--channel-capture=") and DisplayServer.get_name() != "headless":
			await _capture_channel_pose(argument.trim_prefix("--channel-capture="), along_z)
	if sheet_mode:
		host.state.dropped_material[0].center = second_cell.duplicate()
		host.state.revision += 1
		view.refresh()
		var moved_sheet: Node3D = view.get_node_or_null("CopperSheet")
		var expected_move := Vector3(0.825, 0.938, 2.475) if along_z else Vector3(2.475, 0.938, 0.825)
		verify(moved_sheet != null and moved_sheet.position.distance_to(expected_move) < 0.0001
			and absf(moved_sheet.rotation.y - PI * 0.5) < 0.0001,
			"The same sheet projection follows one workcell step without changing form or orientation.")
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--channel-after-capture=") and DisplayServer.get_name() != "headless":
				await _capture_channel_pose(argument.trim_prefix("--channel-after-capture="), along_z)
	view.free()
	physical.free()
	await process_frame

func _capture_guided_component_view(path: String, crank_detail := false) -> void:
	root.size = Vector2i(1280, 800)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("49535d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.4
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.light_energy = 2.0
	root.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(1.2, 2.8, 2.2) if crank_detail else Vector3(3.0, 2.8, 4.2)
	root.add_child(camera)
	camera.look_at(Vector3(0.45, 2.35, 0.0) if crank_detail else Vector3(0.0, 1.2, 0.0))
	camera.fov = 45.0
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(path) == OK,
		"Retain the same camera and lighting for the guide assembly state.")
	camera.free()
	light.free()
	world_environment.free()

func _guided_press_component_view() -> void:
	var state := {"context": "guided-press-component-view", "revision": 1,
		"options": {"native": true, "physical": true}, "actors": {}, "entities": {},
		"foundations": {}, "transmission_parts": {}, "belt_spans": {}, "motion": {
			"shaft": {"state": "rotating", "numerator": 1, "denominator": 1},
			"cog": {"state": "rotating", "numerator": 1, "denominator": 1}},
		"collector_assemblies": [], "press_assemblies": [], "placed_components": {
			"anvil": _component_record("anvil", [0, 0, 0], [0.0, 0.20625, 0.0], [0.2025, 0.20625, 0.14]),
			"ram": _component_record("ram_face", [0, 1, 0], [0.0, 0.928125, 0.0], [0.14, 0.515625, 0.14]),
			"guide": _component_record("sliding_guide", [0, 3, 0], [0.0, 1.919375, 0.0], [0.14, 0.475625, 0.14]),
			"shaft": _component_record("wooden_shaft", [1, 4, 0], [0.4125, 2.475, 0.0], [0.205, 0.12, 0.205]),
			"cog": _component_record("wooden_cog", [2, 4, 0], [0.825, 2.475, 0.0], [0.2075, 0.14, 0.2075])},
		"guided_press_assemblies": [{"anvil": "anvil", "center": [0, 0, 0], "status": "ready",
			"work_center": [0, 0, 0],
			"parts": {"anvil": "anvil", "ram": "ram", "guide": "guide",
				"shaft": "shaft", "drive_cog": "cog"}}]}
	var initial_state: Dictionary = state.duplicate(true)
	var parsed: Dictionary = Geometry.component_boxes(state)
	verify(parsed.get("accepted", false) and parsed.boxes.size() == 5,
		"The frame-free guided press keeps five independent native occupied boxes.")
	var host := HostStub.new()
	host.state = state
	var view := Presenter.new()
	root.add_child(view)
	view.configure(host)
	var anchors := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			anchors[node.get_meta("component_entity")] = node
	var shaft: Node3D = anchors.shaft.get_node_or_null("LooseDriveShaft")
	var cog: Node3D = anchors.cog.get_node_or_null("PlacedDriveCog")
	verify(anchors.size() == 5 and anchors.anvil.get_node_or_null("OpenAnvilSeat") != null
		and anchors.anvil.get_node_or_null("CastBolster") != null
		and anchors.anvil.get_node_or_null("ReplaceableDiePlate") != null
		and anchors.anvil.get_node_or_null("TaperedAnvilHorn") == null
		and anchors.anvil.get_node_or_null("AnvilHeel") == null
		and anchors.ram.get_node_or_null("MovingDie") != null
		and anchors.guide.get_node_or_null("GuideRail") != null
		and anchors.shaft.get_node_or_null("GuidedBearingSeat") != null
		and anchors.anvil.get_node_or_null("PressCrown") == null,
		"The confirmed industrial workbed, ram and guide render without a blacksmith horn or frame crown.")
	var anvil_foot := anchors.anvil.get_node("CastPedestalFoot") as MeshInstance3D
	var anvil_foot_bounds: AABB = anvil_foot.global_transform * anvil_foot.mesh.get_aabb()
	verify(absf(anvil_foot_bounds.position.y) < 0.0002
		and absf(parsed.boxes.anvil.center.y - parsed.boxes.anvil.size.y * 0.5) < 0.0002,
		"The frame-free anvil mesh and native occupied body both meet the ground datum.")
	var native_anvil_size: Vector3 = parsed.boxes.anvil.size
	var native_anvil_local := AABB(-native_anvil_size * 0.5, native_anvil_size).grow(0.0005)
	var anvil_art_inside_body := true
	for child: Node in anchors.anvil.get_children():
		if child is MeshInstance3D:
			var mesh_part := child as MeshInstance3D
			anvil_art_inside_body = anvil_art_inside_body and native_anvil_local.encloses(
				mesh_part.transform * mesh_part.mesh.get_aabb())
	verify(anvil_art_inside_body,
		"Every visible anvil casting stays inside the native occupied body and below its work plane.")
	var anvil_preview := Node3D.new()
	root.add_child(anvil_preview)
	view.preview_component(anvil_preview, "anvil", parsed.boxes.anvil.size)
	verify(_component_mesh_shapes(anchors.anvil) == _component_mesh_shapes(anvil_preview),
		"The anvil preview uses the same floor-seated casting as its committed mesh.")
	anvil_preview.free()
	verify(shaft != null and cog != null and shaft.basis.y.x < -0.99 and cog.basis.y.x < -0.99,
		"The guided shaft and cog point toward the confirmed anvil work column.")
	var ready_guide_shapes := _component_mesh_shapes(anchors.guide)
	var guide_preview := Node3D.new()
	root.add_child(guide_preview)
	view.preview_component(guide_preview, "sliding_guide", parsed.boxes.guide.size)
	verify(ready_guide_shapes.size() == 3
		and ready_guide_shapes == _component_mesh_shapes(guide_preview),
		"The recognized guide has the same rails, crown and dimensions as its placement preview.")
	guide_preview.free()
	var preview_anchor := Node3D.new()
	root.add_child(preview_anchor)
	view.preview_component(preview_anchor, "wooden_shaft", Vector3(0.41, 0.24, 0.41))
	view.preview_component(preview_anchor, "wooden_cog", Vector3(0.41, 0.28, 0.41))
	var preview_shaft: Node3D = preview_anchor.get_node_or_null("LooseDriveShaft")
	var preview_cog: Node3D = preview_anchor.get_node_or_null("PlacedDriveCog")
	verify(preview_shaft != null and preview_cog != null
		and not preview_shaft.has_meta("component_rotor_base")
		and not preview_cog.has_meta("component_rotor_base"),
		"Unplaced shaft and cog previews have no confirmed motion identity.")
	preview_anchor.free()
	for id: String in parsed.boxes:
		var spec: Dictionary = parsed.boxes[id]
		verify(anchors[id].position == spec.center,
			"Each guided press visual uses its own native occupied center.")
		for found: Node in anchors[id].find_children("*", "MeshInstance3D", true, false):
			var mesh := found as MeshInstance3D
			var relative: Transform3D = anchors[id].global_transform.affine_inverse() * mesh.global_transform
			verify(AABB(-spec.size * 0.5, spec.size).grow(0.0002).encloses(relative * mesh.mesh.get_aabb()),
				"Each frame-free fitting stays inside its own native occupied volume: %s/%s." % [id, mesh.name])
	var shaft_mark: MeshInstance3D = shaft.get_node("ShaftIndexMark")
	var cog_mark: MeshInstance3D = cog.get_node("CogIndexMark")
	var shaft_before: Vector3 = shaft_mark.global_position - shaft.global_position
	var cog_before: Vector3 = cog_mark.global_position - cog.global_position
	view.advance_visual_motion(0.02)
	var shaft_after: Vector3 = shaft_mark.global_position - shaft.global_position
	var cog_after: Vector3 = cog_mark.global_position - cog.global_position
	var east_winding: float = shaft_before.cross(shaft_after).dot(Vector3.RIGHT)
	verify(absf(east_winding) > 0.0001 and absf(cog_before.cross(cog_after).dot(Vector3.RIGHT)) > 0.0001
		and anchors.shaft.position == parsed.boxes.shaft.center
		and anchors.cog.position == parsed.boxes.cog.center,
		"Confirmed signed motion turns both placed rotors while their pick anchors stay fixed.")
	state.motion.shaft = {"state": "stalled", "numerator": 0, "denominator": 1}
	state.motion.cog = {"state": "stalled", "numerator": 0, "denominator": 1}
	state.revision = 2
	host.state = state
	view.refresh()
	var stopped := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			stopped[node.get_meta("component_entity")] = node
	var held_shaft: Node3D = stopped.shaft.get_node("LooseDriveShaft")
	var held_mark: MeshInstance3D = held_shaft.get_node("ShaftIndexMark")
	var held_position: Vector3 = held_mark.global_position
	view.advance_visual_motion(0.02)
	verify(held_mark.global_position.distance_to(held_position) < 0.00001,
		"A stalled native rate freezes the placed shaft at its last confirmed phase.")
	state.motion.shaft = {"state": "rotating", "numerator": 1, "denominator": 1}
	state.motion.cog = {"state": "rotating", "numerator": 1, "denominator": 1}
	state.revision = 3
	host.state = state
	view.refresh()
	var resumed := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			resumed[node.get_meta("component_entity")] = node
	var resumed_shaft: Node3D = resumed.shaft.get_node("LooseDriveShaft")
	var resumed_mark: MeshInstance3D = resumed_shaft.get_node("ShaftIndexMark")
	verify(resumed_mark.global_position.distance_to(held_position) < 0.00001,
		"A resumed native rate starts at the retained visual phase.")
	view.advance_visual_motion(0.02)
	verify(resumed_mark.global_position.distance_to(held_position) > 0.0001,
		"The reconnected placed shaft moves only after native motion resumes.")
	state.placed_components.shaft.center = [-1, 4, 0]
	state.placed_components.shaft.occupied.center = [-0.4125, 2.475, 0.0]
	state.placed_components.cog.center = [-2, 4, 0]
	state.placed_components.cog.occupied.center = [-0.825, 2.475, 0.0]
	state.revision = 4
	host.state = state
	view.refresh()
	var mirrored := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			mirrored[node.get_meta("component_entity")] = node
	var west_shaft: Node3D = mirrored.shaft.get_node("LooseDriveShaft")
	var west_mark: MeshInstance3D = west_shaft.get_node("ShaftIndexMark")
	var west_before: Vector3 = west_mark.global_position - west_shaft.global_position
	view.advance_visual_motion(0.02)
	var west_after: Vector3 = west_mark.global_position - west_shaft.global_position
	verify(east_winding * west_before.cross(west_after).dot(Vector3.RIGHT) > 0.0,
		"Mirrored fittings preserve the signed native world-axis winding.")
	var capture_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
	if not capture_path.is_empty():
		await _capture_guided_component_view(capture_path)
	state.guided_press_assemblies[0] = {"anvil": "anvil", "center": [0, 0, 0], "status": "missing_cog"}
	state.placed_components.erase("cog")
	state.motion.clear()
	state.revision = 5
	host.state = state
	view.refresh()
	var partial := {}
	for node: Node in view.get_children():
		if node.has_meta("component_entity"):
			partial[node.get_meta("component_entity")] = node
	var loose_shaft: Node3D = partial.shaft.get_node_or_null("LooseDriveShaft")
	verify(partial.size() == 4 and loose_shaft != null
		and partial.shaft.get_node_or_null("GuidedBearingSeat") == null
		and loose_shaft.basis.y.y > 0.99,
		"A partial native assembly loses its drive fitting without inventing a ready press.")
	verify(_component_mesh_shapes(partial.guide) == ready_guide_shapes,
		"Removing a neighboring drive part does not resize or reposition the guide rails.")
	if not capture_path.is_empty():
		await _capture_guided_component_view(capture_path.get_basename() + "-partial.png")
	var standalone: Dictionary = initial_state.duplicate(true)
	standalone.placed_components = {"guide": initial_state.placed_components.guide}
	standalone.guided_press_assemblies = []
	standalone.motion = {}
	standalone.revision = 6
	host.state = standalone
	view.refresh()
	var standalone_guide: Node3D
	for node: Node in view.get_children():
		if node.get_meta("component_entity", "") == "guide":
			standalone_guide = node
	verify(standalone_guide != null and _component_mesh_shapes(standalone_guide) == ready_guide_shapes,
		"A guide alone keeps its selected rails and crown before any neighboring assembly exists.")
	if not capture_path.is_empty():
		await _capture_guided_component_view(capture_path.get_basename() + "-standalone.png")
	state = initial_state
	state.revision = 7
	host.state = state
	view.refresh()
	var rest_ram: Node3D
	for node: Node in view.get_children():
		if node.get_meta("component_entity", "") == "ram":
			rest_ram = node
	var rest_y: float = (rest_ram.get_node("MovingDie") as MeshInstance3D).position.y
	state.dropped_material = [{"center": [0, 0, 0], "raw": 0, "products": 0,
		"work_lots": [{"id": 1, "cycle_ticks": 3, "remaining": 1}]}]
	state.revision = 8
	host.state = state
	view.refresh()
	var forming_ram: Node3D
	for node: Node in view.get_children():
		if node.get_meta("component_entity", "") == "ram":
			forming_ram = node
	var forming_die: MeshInstance3D = forming_ram.get_node("MovingDie")
	var forming_slide: MeshInstance3D = forming_ram.get_node("RamSlideNear")
	var held_billet: Node3D
	for node: Node in view.get_children():
		if node.name == "WorkpieceBillet":
			held_billet = node
	verify(held_billet != null and held_billet.get_node_or_null("Label3D") == null,
		"The retained guided billet stays visible without a hovering work count.")
	var half: float = state.placed_components.ram.occupied.half[1]
	var die_box: AABB = forming_die.global_transform * forming_die.mesh.get_aabb()
	var boss: MeshInstance3D = held_billet.get_node("CenterBoss")
	var boss_box: AABB = boss.global_transform * boss.mesh.get_aabb()
	verify(absf(rest_y - forming_die.position.y -
			(Presenter.GUIDED_RAM_REST_LIFT - Presenter.GUIDED_RAM_CONTACT_LIFT)) < 0.001
		and absf(die_box.position.y - boss_box.end.y) < 0.001
		and forming_die.position.y - (forming_die.mesh as BoxMesh).size.y * 0.5 >= -half - 0.00001
		and forming_slide.position.y + (forming_slide.mesh as BoxMesh).size.y * 0.5 <= half + 0.00001,
		"Confirmed work brings the die to the retained copper crown inside the swept ram box.")
	state.dropped_material = []
	state.revision = 9
	host.state = state
	view.refresh()
	var finished_ram: Node3D
	for node: Node in view.get_children():
		if node.get_meta("component_entity", "") == "ram":
			finished_ram = node
	verify(absf((finished_ram.get_node("MovingDie") as MeshInstance3D).position.y - rest_y) < 0.001,
		"Removing the confirmed workpiece returns the guided tool to its raised rest pose.")
	var crank_capture_prefix := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--crank-capture-prefix="):
			crank_capture_prefix = argument.trim_prefix("--crank-capture-prefix=")
	state = initial_state.duplicate(true)
	state.crank_items = {"fitted-crank": {"attached_to": "shaft", "port": [1, 4, 0],
		"face": [1, 0, 0]}}
	state.revision = 10
	host.state = state
	view.refresh()
	var crank_east := view.get_node_or_null("AttachedHandCrank") as Node3D
	verify(crank_east != null and crank_east.position.x > 0.4125
		and absf(crank_east.rotation.y) < 0.001,
		"The fitted crank seats outward on the confirmed positive X spindle face.")
	if not crank_capture_prefix.is_empty():
		await _capture_guided_component_view(crank_capture_prefix + "-east.png", true)
	state.crank_items["fitted-crank"].face = [-1, 0, 0]
	state.revision = 11
	host.state = state
	view.refresh()
	var crank_west := view.get_node_or_null("AttachedHandCrank") as Node3D
	verify(crank_west != null and crank_west.position.x < 0.4125
		and absf(absf(crank_west.rotation.y) - PI) < 0.001,
		"Mirroring the fitted face moves and turns the visible grip with its shaft.")
	if not crank_capture_prefix.is_empty():
		await _capture_guided_component_view(crank_capture_prefix + "-west.png", true)
	view.free()
	await process_frame

func _fixture_arguments_valid() -> bool:
	var mode := ""
	var seen: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if DIRECT_MODES.has(argument) or argument == "--scale-benchmark":
			if not mode.is_empty():
				return false
			mode = argument
			continue
		if BENCHMARK_FLAGS.has(argument):
			if seen.has(argument):
				return false
			seen[argument] = true
			continue
		var option := ""
		var value := ""
		for prefix: String in VALUE_MODES.keys() + ["--test-purpose="]:
			if argument.begins_with(prefix):
				option = prefix
				value = argument.trim_prefix(prefix)
				break
		if option.is_empty() or value.is_empty() or seen.has(option):
			return false
		if option in ["--count=", "--large-every="] and not value.is_valid_int():
			return false
		seen[option] = true
	for option: String in seen:
		if BENCHMARK_FLAGS.has(option):
			if mode != "--scale-benchmark":
				return false
		elif option != "--test-purpose=" and not VALUE_MODES[option].has(mode):
			return false
	return true

func _initialize() -> void:
	if not Opening.apply_test_window_title(self):
		return
	if not _fixture_arguments_valid():
		push_error("Unknown, repeated or incompatible native transmission fixture argument")
		quit(2)
		return
	call_deferred("_run")

func _controls() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var view := Controls.new()
	view.configure(host)
	verify(view.gear_height == 0, "The default cog height shares the worksite machine level.")
	view.gear_height = 4
	view.snapped_height = 4
	verify(view.visible and not view.disabled and "2 carried" in view.get_popup().get_item_text(0), "P sees its own finite kit.")
	view.get_popup().emit_signal("id_pressed", 1)
	var before: Dictionary = host.state.duplicate(true)
	var center := [-4, 4, 4]
	verify(view.handle_world_click(center, ""), "An active gear tool consumes its click.")
	verify(host.calls.back() == {"action": "place_gear", "center": [-4, 4, 4], "axis": "x", "teeth": 2}, "Gear placement delegates the exact integer center and specification.")
	verify(center == [-4, 4, 4] and host.state == before and "2 carried" in view.get_popup().get_item_text(0), "A queued response creates no speculative kit credit or geometry.")
	view._axes.emit_signal("id_pressed", 1)
	view._heights.emit_signal("id_pressed", 1)
	view.handle_world_click([0, 8, 4], "")
	verify(view.selected_axis == "y" and view.gear_height == 8 and host.calls.back() == {"action": "place_gear", "center": [0, 8, 4], "axis": "y", "teeth": 2}, "The axis and height menus use the shared tile step.")
	view._heights.emit_signal("id_pressed", 0)
	view.handle_world_click([-12, 4, 16], "")
	verify(host.calls.back().center == [-12, 4, 16], "The view delegates tile points outside the obsolete restricted construction area.")
	var sent: int = host.calls.size()
	for invalid in [[0.0, 4, 4], [true, 4, 4], [0, 4], [-1000001, 4, 4], [0, 3, 4], [0, 4, 1000001], [1, 4, 4], [0, 4, 5]]:
		verify(view.handle_world_click(invalid, ""), "Invalid active-tool coordinates are consumed.")
	verify(host.calls.size() == sent, "Malformed, off-plane and out-of-profile coordinates send no request.")
	host.client = "Q"
	view.refresh()
	verify(view.get_popup().is_item_disabled(0) and "0 carried" in view.get_popup().get_item_text(0), "Q never borrows P's aggregate parts.")
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "An empty current kit refuses without click fallthrough.")
	host.client = "P"
	for flag in ["explanation_open", "startup_save_pending"]:
		host.set(flag, true)
		view.refresh()
		verify(view.disabled and view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "Blocked view clicks are consumed without a request.")
		host.set(flag, false)
	host.mutate_allowed = false
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "The shared mutation barrier suppresses submission.")
	host.mutate_allowed = true
	host.state.actors.P.ready = false
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "An unready character cannot submit.")
	host.state.actors.P.ready = true
	host.state.part_specifications.erase("P")
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "An absent actor kit does not use the compatibility alias.")
	host.state = fixture()
	host.state.part_specifications.P[1].count = 0
	host.state.part_specifications.P.append({"kind": "shaft", "teeth": 0, "half_span": 4, "count": 2})
	view.refresh()
	verify(view.get_popup().is_item_disabled(view.get_popup().get_item_index(6)), "A long-only kit does not offer a one-tile shaft.")
	view.choose_tool("place_shaft")
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "A long-only kit cannot submit a one-tile shaft.")
	host.client = "P"
	host.state = fixture()
	verify(view.get_popup().get_item_index(4) == -1 and not view.get_popup().get_item_text(0).contains("Remove"),
		"The transmission menu leaves deconstruction to the dedicated F mode.")
	view.choose_tool("bogus")
	verify(view.active_tool == "place_shaft", "Unsupported transmission tools cannot replace placement.")
	sent = host.calls.size()
	view.choose_tool("gear")
	host.state.options.native = false
	view.refresh()
	verify(not view.visible and view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "A missing native profile hides controls and consumes its stale active click.")
	view.cancel()
	verify(not view.handle_world_click([0, 4, 4], ""), "A cancelled tool returns normal input to the scene.")
	view.free()

func _gear_sizes() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.part_specifications.P.append({"kind": "gear", "teeth": 4, "half_span": 0, "count": 1})
	var view := Controls.new()
	view.configure(host)
	view.gear_height = 4
	view.snapped_height = 4
	view.choose_tool("gear")
	view._axes.id_pressed.emit(1)
	view._heights.id_pressed.emit(1)
	view._sizes.id_pressed.emit(1)
	verify(view.gear_teeth == 4 and view.selected_axis == "y" and view.gear_height == 8,
		"Selecting the large cog retains the independent axis and height selections.")
	verify("1 carried" in view.get_popup().get_item_text(0) and "Large" in view.get_popup().get_item_text(view.get_popup().get_item_index(102)),
		"The selected large cog count comes from P's exact carried specification.")
	var original: Dictionary = host.state.duplicate(true)
	view.handle_world_click([0, 8, 4], "")
	verify(host.calls.back() == {"action": "place_gear", "center": [0, 8, 4], "axis": "y", "teeth": 4} and host.state == original,
		"A large-cog request has its actual size and a queued reply changes no confirmed inventory.")
	var sent := host.calls.size()
	host.client = "Q"
	view.refresh()
	verify(view.get_popup().is_item_disabled(0) and "0 carried" in view.get_popup().get_item_text(0),
		"An actor without the selected large cog cannot borrow P's inventory.")
	verify(view.handle_world_click([0, 8, 4], "") and host.calls.size() == sent,
		"An unavailable large cog consumes the click without issuing a request.")
	host.client = "P"
	host.mutate_allowed = false
	verify(view.handle_world_click([0, 8, 4], "") and host.calls.size() == sent,
		"A disconnected or pending shared view cannot submit a large cog.")
	host.mutate_allowed = true
	view._sizes.id_pressed.emit(0)
	view.handle_world_click([0, 8, 4], "")
	verify(view.gear_teeth == 2 and host.calls.back().get("teeth") == 2 and host.calls.size() == sent + 1,
		"Reselecting the small cog submits its own specification.")
	view.free()

func _shaft_segments() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.part_specifications.P.append({"kind": "shaft", "teeth": 0, "half_span": 4, "count": 1})
	var view := Controls.new()
	view.configure(host)
	view.gear_height = 4
	view.get_popup().id_pressed.emit(6)
	var original: Dictionary = host.state.duplicate(true)
	view.handle_world_click([0, 4, 4], "")
	verify(host.calls.back() == {"action": "place_shaft", "center": [0, 4, 4], "axis": "x", "half_span": 2} and host.state == original,
		"An individual short segment delegates its exact geometry without speculative inventory.")
	verify(view.get_popup().get_item_index(104) < 0, "The obsolete endpoint menu is absent.")
	view._axes.id_pressed.emit(2)
	view.handle_world_click([0, 4, 8], "")
	verify(host.calls.back() == {"action": "place_shaft", "center": [0, 4, 8], "axis": "z", "half_span": 2},
		"The segment uses its selected axis and one-tile specification.")
	var sent := host.calls.size()
	view.handle_world_click([0, 3, 8], "")
	host.client = "Q"
	view.refresh()
	verify(view.get_popup().is_item_disabled(view.get_popup().get_item_index(6)) and view.handle_world_click([0, 4, 8], "") and host.calls.size() == sent,
		"Off-plane clicks and an actor without the selected shaft never submit a request.")
	host.client = "P"
	host.mutate_allowed = false
	verify(view.handle_world_click([0, 4, 8], "") and host.calls.size() == sent,
		"A pending shared mutation consumes the click without placing a segment.")
	view.free()
	var long_host := HostStub.new()
	long_host.state = fixture()
	long_host.state.part_specifications.P[1].count = 0
	long_host.state.part_specifications.P.append({"kind": "shaft", "teeth": 0, "half_span": 4, "count": 1})
	var long_view := Controls.new()
	long_view.configure(long_host)
	verify(long_view.get_popup().is_item_disabled(long_view.get_popup().get_item_index(6)),
		"An obsolete long shaft cannot be selected as a one-tile part.")
	long_view.choose_tool("place_shaft")
	verify(long_view.shaft_half_span == 2, "The shaft tool always uses the one-tile specification.")
	long_view.free()

func _relays() -> void:
	var host := HostStub.new()
	host.state = fixture()
	for kind in ["gearbox", "vertical_gearbox", "chain_drive"]:
		host.state.part_specifications.P.append({"kind": kind, "teeth": 0, "half_span": 0, "count": 1})
	var view := Controls.new()
	view.configure(host)
	view.choose_tool("gearbox")
	verify(view.selected_axis == "y", "The horizontal gearbox selects its four side ports.")
	view.handle_world_click([0, 8, 4], "")
	verify(host.calls.back() == {"action": "place_relay", "kind": "gearbox", "center": [0, 8, 4], "axis": "y"},
		"The horizontal gearbox sends one exact grid tile and its closed Y axis.")
	view.choose_tool("vertical_gearbox")
	verify(view.selected_axis in ["x", "z"], "The vertical gearbox closes a horizontal pair of faces.")
	view.handle_world_click([4, 8, 4], "")
	verify(host.calls.back() == {"action": "place_relay", "kind": "vertical_gearbox", "center": [4, 8, 4], "axis": view.selected_axis},
		"The vertical gearbox sends its separate finite item and orientation.")
	view.choose_tool("chain_drive")
	view._link_axis_selected(1)
	view.handle_world_click([8, 8, 4], "")
	verify(host.calls.back() == {"action": "place_relay", "kind": "chain_drive", "center": [8, 8, 4],
		"axis": view.selected_axis, "relay_axis": view.selected_link_axis} and view.selected_link_axis != view.selected_axis,
		"The encased chain case submits distinct shaft and link axes.")
	var sent := host.calls.size()
	host.client = "Q"
	view.refresh()
	verify(view.handle_world_click([12, 8, 4], "") and host.calls.size() == sent,
		"A second actor cannot spend the first actor's relay kit.")
	host.client = "P"
	view.free()
	host.state.transmission_parts["box"] = {"kind": "gearbox", "generation": 7,
		"center": [0, 8, 4], "axis": 1, "teeth": 0, "half_span": 0}
	host.state.transmission_parts["chain"] = {"kind": "chain_drive", "generation": 8,
		"center": [4, 8, 4], "axis": 0, "relay_axis": 2, "teeth": 0, "half_span": 0}
	host.state.transmission_parts["upright"] = {"kind": "vertical_gearbox", "generation": 9,
		"center": [8, 8, 4], "axis": 0, "teeth": 0, "half_span": 0}
	host.state.motion["box"] = {"state": "rotating", "numerator": 1, "denominator": 1}
	host.state.motion["chain"] = {"state": "rotating", "numerator": 1, "denominator": 1}
	host.state.motion["upright"] = {"state": "rotating", "numerator": 1, "denominator": 1}
	var presenter := Presenter.new()
	presenter.configure(host)
	var physical_state: Dictionary = host.state.duplicate(true)
	physical_state.transmission_parts = {"box": host.state.transmission_parts.box,
		"chain": host.state.transmission_parts.chain, "upright": host.state.transmission_parts.upright}
	physical_state.belt_spans = {}
	var collision: Dictionary = Geometry.mechanical_boxes(physical_state)
	verify(collision.get("accepted", false) and collision.boxes.box.size == Vector3.ONE * Geometry.PITCH and
		collision.boxes.chain.size == Vector3.ONE * Geometry.PITCH,
		"Both confirmed relay cases register one-tile physical actor bodies.")
	var invalid: Dictionary = physical_state.duplicate(true)
	invalid.transmission_parts.chain.relay_axis = invalid.transmission_parts.chain.axis
	verify(not Geometry.mechanical_boxes(invalid).accepted,
		"A malformed chain link axis cannot produce a physical body.")
	var box := _part(presenter, "box")
	var chain := _part(presenter, "chain")
	var upright := _part(presenter, "upright")
	verify(box != null and box.has_node("FixedCase") and box.has_node("ShaftPort01") and
		box.has_node("ShaftPort2-1") and box.get_node("Pick").get_meta("entity") == "box",
		"A confirmed gearbox shows a fixed case, four ports and a one-tile pick body.")
	verify(chain != null and chain.has_node("FixedCase") and chain.has_node("ChainLinkDirection") and
		chain.get_node("Pick").get_meta("entity") == "chain",
		"A confirmed chain case shows its link direction and can be selected.")
	var formed := box.get_node("FixedCase") as MeshInstance3D
	var cast: ArrayMesh = formed.mesh
	var limits := cast.get_aabb()
	var half := Geometry.PITCH * 0.5
	verify(cast.get_surface_count() == 3 and cast == Presenter.relay_shell_mesh("gearbox", 1, 0) and
		limits.position.x >= -half and limits.position.y >= -half and limits.position.z >= -half and
		limits.end.x <= half and limits.end.y <= half and limits.end.z <= half,
		"The formed gearbox reuses one casing mesh inside its unchanged physical and pick envelope.")
	verify(cast.surface_get_material(0) is StandardMaterial3D and
		(cast.surface_get_material(0) as StandardMaterial3D).normal_texture != null and
		cast.surface_get_material(1) != null and cast.surface_get_material(2) != null,
		"The fixed case carries its qualified cast, cover and worked-metal finishes.")
	verify(box.has_node("ShaftPort01/BearingSocket") and box.has_node("ShaftPort01/MachinedCollar") and
		box.has_node("ShaftPort2-1/BearingSocket") and not box.has_node("ShaftPort11") and
		upright.has_node("ShaftPort11/MachinedCollar") and not upright.has_node("ShaftPort01"),
		"Each gearbox exposes machined collars only on the native-confirmed faces.")
	verify(chain.get_node("FixedCase").mesh != cast and
		chain.get_node("FixedCase").mesh == Presenter.relay_shell_mesh("chain_drive", 0, 2) and
		chain.has_node("ShaftPort01/MachinedCollar") and not chain.has_node("ShaftPort21"),
		"The chain case has its own formed link-axis housing and only its confirmed shaft ports.")
	presenter.free()

func _belt_spans(omit_shared_product := false) -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.transmission_parts["left"] = {"kind": "shaft", "generation": 11, "center": [0, 0, 0], "axis": 2, "half_span": 2}
	host.state.transmission_parts["right"] = {"kind": "shaft", "generation": 12, "center": [12, 0, 0], "axis": 2, "half_span": 2}
	host.state.transmission_parts["middle"] = {"kind": "shaft", "generation": 14, "center": [4, 0, 0], "axis": 2, "half_span": 2}
	host.state.belt_spans = {}
	var controls := Controls.new()
	controls.configure(host)
	controls.choose_tool("belt_span")
	var before: Dictionary = host.state.duplicate(true)
	controls.handle_world_click([], "left")
	verify(host.calls == [{"action": "select_belt_shaft", "entity": "left"}], "The first endpoint submits an authoritative reach selection.")
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 1, "A queued first endpoint cannot be used before server acceptance.")
	controls.settle_belt_selection("unrelated", true)
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 1, "An unrelated outcome cannot confirm the endpoint.")
	controls.settle_belt_selection("request-1", true)
	controls.handle_world_click([], "right")
	verify(host.calls.back() == {"action": "place_selected_belt_span", "from": "left", "to": "right", "selection": "request-1"} and host.state == before,
		"Two confirmed shafts submit a span without speculative geometry or inventory.")
	controls.settle_belt_placement("request-2", true, "")
	controls.handle_world_click([], "left")
	host.state.transmission_parts.left.generation = 13
	controls.settle_belt_selection("request-3", true)
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 3, "A replaced first shaft cannot be silently reused.")
	controls.handle_world_click([], "left")
	host.mutate_allowed = false
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 4, "A pending shared request prevents a span submission.")
	host.mutate_allowed = true
	controls.settle_belt_selection("request-4", false)
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 5 and host.calls.back().action == "select_belt_shaft", "A rejected first endpoint allows a fresh first selection.")
	controls.clear_belt_selection()
	controls.handle_world_click([], "left")
	verify(host.calls.size() == 6 and host.calls.back().action == "select_belt_shaft", "A disconnected selection cannot survive into a new session.")
	var presenter := Presenter.new()
	presenter.configure(host)
	verify(_part(presenter, "span") == null, "An unconfirmed span is not rendered.")
	host.state.belt_spans["span"] = {"generation": 1, "from": "left", "to": "right"}
	presenter.refresh()
	var span := _part(presenter, "span")
	verify(span != null and span.get_node("Pick").get_meta("entity") == "span", "A confirmed span has a selectable visual.")
	verify(span.has_node("BeltLoop") and not span.has_node("BeltStrip"), "The confirmed span uses the fitted closed loop.")
	verify(_part(presenter, "left").has_node("BeltPulley") and _part(presenter, "right").has_node("BeltPulley") and _part(presenter, "middle").has_node("BeltPulley"), "Endpoint and intermediate shafts receive fitted pulleys.")
	verify(not _part(presenter, "sx").has_node("BeltPulley"), "An unrelated shaft never acquires a pulley.")
	verify(_part(presenter, "left").get_node("Pick").get_meta("entity") == "left" and _part(presenter, "right").get_node("Pick").get_meta("entity") == "right", "Both shaft picks remain independently selectable.")
	var original_parts: Dictionary = host.state.transmission_parts.duplicate(true)
	for id in ["left", "right", "middle"]:
		var old: Array = host.state.transmission_parts[id].center
		host.state.transmission_parts[id].center = [0, old[1], old[0]]
		host.state.transmission_parts[id].axis = 0
	presenter.refresh()
	span = _part(presenter, "span")
	verify(span.has_node("BeltLoop") and is_equal_approx(span.get_node("BeltLoop").rotation.y, -PI / 2.0) and _part(presenter, "middle").has_node("BeltPulley"), "The other horizontal axis rotates the fitted loop and keeps intermediate pulleys.")
	host.state.transmission_parts = original_parts
	presenter.refresh()
	var raw := {"raw": 1, "products": 0, "work_lots": []}
	var product := {"raw": 0, "products": 1, "work_lots": []}
	var work := {"raw": 0, "products": 0, "work_lots": [{"id": 7}]}
	host.state.belt_spans["span"].slots = [raw, null, product, work]
	host.state.belt_spans["span"].phase = 0
	presenter.refresh()
	span = _part(presenter, "span")
	var item0 := _belt_item(span, 0)
	var item2 := _belt_item(span, 2)
	var item3 := _belt_item(span, 3)
	verify(item0 != null and item0.get_meta("belt_item") == "raw" and is_equal_approx(item0.position.x, -2.475),
		"A confirmed raw unit is rendered on its exact first endpoint tile.")
	verify(_belt_item(span, 1) == null and item2 != null and item2.get_meta("belt_item") == "product" and item3 != null and item3.get_meta("belt_item") == "work",
		"Empty positions remain empty and distinct confirmed item types retain their positions.")
	var fixed_span_id := span.get_instance_id()
	var fixed_pick_id := span.get_node("Pick").get_instance_id()
	var fixed_shaft_id := _part(presenter, "left").get_instance_id()
	var moving_item_id := item0.get_instance_id()
	host.state.belt_spans["span"].phase = 2048
	presenter.refresh()
	span = _part(presenter, "span")
	verify(span.get_instance_id() == fixed_span_id and span.get_node("Pick").get_instance_id() == fixed_pick_id
		and _part(presenter, "left").get_instance_id() == fixed_shaft_id,
		"A belt cargo phase update retains the rotating machine and fixed pick geometry.")
	verify(_belt_item(span, 0).get_instance_id() == moving_item_id,
		"Fractional cargo progress moves the fitted item without rebuilding it.")
	verify(is_equal_approx(_belt_item(span, 0).position.x, -1.65), "A free slot shows the confirmed half-tile forward phase.")
	verify(is_equal_approx(_belt_item(span, 2).position.x, 0.825) and is_equal_approx(_belt_item(span, 3).position.x, 2.475), "A chain blocked at the end does not visually pass through its neighbor.")
	host.state.belt_spans["span"].phase = -2048
	presenter.refresh()
	span = _part(presenter, "span")
	verify(is_equal_approx(_belt_item(span, 0).position.x, -2.475) and is_equal_approx(_belt_item(span, 2).position.x, 0.0) and is_equal_approx(_belt_item(span, 3).position.x, 1.65), "Reverse phase moves an unblocked chain together while the endpoint stays bounded.")
	verify(Presenter.belt_slot_fraction([raw, null], 0, 0.5) == 0.0 and Presenter.belt_slot_fraction([raw, null], 0, 4096) == 0.0, "Malformed and out-of-range phases do not invent motion.")
	var session := Session.new()
	session.context = host.state.context
	session._ready_for_commands = true
	host.state.revision = 1
	host.state.order = 1
	if omit_shared_product:
		# A controlled missing item must fail as a test assertion, not escape as
		# a script exception followed by a misleading success marker.
		host.state.belt_spans["span"].slots[2] = null
	session._apply_frame({"context": host.state.context, "serial": 1, "snapshot": host.state})
	verify(session.projection().is_empty(),
		"An ordinary shared frame remains pending until its scheduled state flush.")
	await process_frame
	await process_frame
	var remote := HostStub.new()
	remote.state = session.projection()
	var remote_presenter := Presenter.new()
	remote_presenter.configure(remote)
	var shared_product := _belt_item(_part(remote_presenter, "span"), 2)
	verify(shared_product != null and shared_product.get_meta("belt_item") == "product",
		"A read-only Session frame preserves the same confirmed belt contents.")
	host.state.belt_spans["span"].slots = [null, raw, product, work]
	presenter.refresh()
	span = _part(presenter, "span")
	verify(_belt_item(span, 0) == null and _belt_item(span, 1).get_meta("belt_item") == "raw",
		"Only the next confirmed snapshot moves the displayed item to its new slot.")
	verify(_belt_item(_part(remote_presenter, "span"), 0) != null,
		"An older shared snapshot does not acquire the next local item position.")
	var older: Dictionary = remote.state.duplicate(true)
	host.state.revision = 2
	host.state.order = 2
	session._apply_frame({"context": host.state.context, "serial": 2, "snapshot": host.state})
	await process_frame
	await process_frame
	remote.state = session.projection()
	remote_presenter.refresh()
	var shared_raw := _belt_item(_part(remote_presenter, "span"), 1)
	verify(shared_raw != null and shared_raw.get_meta("belt_item") == "raw",
		"A newer shared frame renders the updated confirmed slot.")
	session._apply_frame({"context": host.state.context, "serial": 1, "snapshot": older})
	verify(session.projection().belt_spans["span"].slots[1] == raw,
		"An out-of-order shared frame cannot roll the item back.")
	remote_presenter.free()
	session.free()
	host.state.belt_spans.clear()
	presenter.refresh()
	verify(_part(presenter, "span") == null, "A confirmed removal clears the visual.")
	verify(not _part(presenter, "left").has_node("BeltPulley") and not _part(presenter, "middle").has_node("BeltPulley"), "Removing the span removes its fitted pulleys.")
	controls.free()
	presenter.free()

func _belt_retry() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.transmission_parts["left"] = {"kind": "shaft", "generation": 1, "center": [0, 0, 0], "axis": 2, "half_span": 2}
	host.state.transmission_parts["right"] = {"kind": "shaft", "generation": 2, "center": [12, 0, 0], "axis": 2, "half_span": 2}
	var controls := Controls.new()
	controls.configure(host)
	controls.choose_tool("belt_span")
	controls.handle_world_click([], "left")
	controls.settle_belt_selection("request-1", true)
	controls.handle_world_click([], "right")
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 2, "A pending belt placement cannot be submitted twice.")
	controls.settle_belt_placement("unrelated", false, "out_of_reach")
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 2, "An unrelated result cannot release a pending placement.")
	var shared := SharedSettlement.new()
	shared.session = ReadySession.new()
	shared.transmission_controls = controls
	shared.state = {"context": "helper-fixture", "revision": 1, "order": 1}
	shared.pending_actions = {"request-2": {"action": {"action": "place_selected_belt_span"},
		"outcome": {"context": "helper-fixture", "revision": 2, "order": 2, "accepted": false, "reason": "out_of_reach"}}}
	shared._settle_pending()
	controls.handle_world_click([], "right")
	verify(host.calls.size() == 2, "A shared refusal waits for its confirmed worksite before allowing retry.")
	shared.state.revision = 2
	shared.state.order = 2
	shared._settle_pending()
	controls.handle_world_click([], "right")
	verify(host.calls.back() == {"action": "place_selected_belt_span", "from": "left", "to": "right", "selection": "request-1"},
		"A refused second endpoint reuses the confirmed first selection.")
	controls.settle_belt_placement("request-3", true, "")
	controls.handle_world_click([], "right")
	verify(host.calls.back() == {"action": "select_belt_shaft", "entity": "right"}, "Successful placement consumes the selection.")
	controls.settle_belt_selection("request-4", true)
	controls.handle_world_click([], "left")
	controls.settle_belt_placement("request-5", false, "invalid_belt_selection")
	controls.handle_world_click([], "left")
	verify(host.calls.back() == {"action": "select_belt_shaft", "entity": "left"}, "An invalid authority selection starts over.")
	controls.choose_tool("belt_span")
	host.reply_mode = "accepted"
	controls.handle_world_click([], "left")
	host.reply_mode = "refused"
	controls.handle_world_click([], "right")
	host.reply_mode = "accepted"
	controls.handle_world_click([], "right")
	verify(host.calls.back().action == "place_selected_belt_span" and host.calls.back().selection == "request-7",
		"A synchronous refusal preserves the first selection for an ordinary local retry.")
	controls.handle_world_click([], "right")
	verify(host.calls.back().action == "select_belt_shaft", "A synchronous successful placement clears the selection.")
	shared.transmission_controls = null
	shared.free()
	controls.free()

func _span_guidance() -> void:
	var view := SharedSettlement.new()
	view.client = "P"
	view.state = fixture()
	view.state.entities = {
		"collector": {"kind": "collector", "center": [-4, 0, 0]},
		"press": {"kind": "processor", "center": [16, 0, 0]},
		"wheel": {"kind": "wheel", "center": [0, 0, -4]}}
	view.state.transmission_parts = {
		"a0": {"kind": "shaft", "center": [0, 0, 0], "axis": 2},
		"a1": {"kind": "shaft", "center": [4, 0, 0], "axis": 2},
		"b0": {"kind": "shaft", "center": [8, 0, 0], "axis": 2},
		"b1": {"kind": "shaft", "center": [12, 0, 0], "axis": 2}}
	var empty := [null, null]
	view.state.belt_spans = {"first": {"from": "a0", "to": "a1", "slots": empty.duplicate()},
		"second": {"from": "b0", "to": "b1", "slots": [{"raw": 1, "products": 0, "work_lots": []}, null]}}
	view.state.motion = {"a0": {"state": "rotating", "numerator": -1},
		"b0": {"state": "rotating", "numerator": -1},
		"collector": {"state": "rotating", "numerator": 1},
		"press": {"state": "rotating", "numerator": 1}}
	view.state.links = []
	view.state.power_enabled = true
	view.state.inventories = {"P": 0}
	view.state.stock = {"source": 0, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0}
	var kinds := {"collector": true, "processor": true, "wheel": true}
	var route: Dictionary = view._guided_span_routes()
	verify(route.physical and route.powered and route.cargo and view._guided_step(kinds).text.begins_with("Follow the material"),
		"A powered two-span line and its in-flight material need no legacy belt or manual links.")
	for item in [{"raw": 0, "products": 1, "work_lots": []}, {"raw": 0, "products": 0, "work_lots": [{"id": 7}]}]:
		view.state.belt_spans.second.slots[0] = item
		verify(view._guided_span_routes().cargo and view._guided_step(kinds).text.begins_with("Follow the material"),
			"Finished plates and workpieces on the belt receive accurate cargo guidance.")
	view.state.belt_spans.second.slots[0] = {"raw": 1, "products": 0, "work_lots": []}
	view.state.motion.b0.numerator = 1
	verify(view._guided_span_routes().physical and not view._guided_span_routes().powered and "direction" in view._guided_step(kinds).text,
		"A reversed downstream span cannot be advertised as a working route.")
	view.state.motion.b0.state = "stalled"
	verify(not view._guided_span_routes().powered and "Power the belt" in view._guided_step(kinds).text,
		"A stalled belt produces a power instruction.")
	view.state.motion.b0.state = "rotating"
	view.state.motion.b0.numerator = -1
	view.state.entities.press.center = [20, 0, 0]
	verify(not view._guided_span_routes().physical and "Connect the collector" in view._guided_step(kinds).text,
		"A separated press is not presented as connected.")
	view.state.entities.press.center = [16, 0, 0]
	view.state.belt_spans.second.from = "b1"
	view.state.belt_spans.second.to = "b0"
	view.state.motion.b1 = {"state": "rotating", "numerator": -1}
	verify(view._guided_span_routes().powered, "Reversing endpoint order preserves the actual travel direction.")
	for entity: Dictionary in view.state.entities.values():
		var center: Array = entity.center
		entity.center = [0, center[0], center[0]]
	for part: Dictionary in view.state.transmission_parts.values():
		var center: Array = part.center
		part.center = [0, center[0], center[0]]
		part.axis = 0
	for id in ["a0", "b0", "b1"]:
		view.state.motion[id].numerator = 1
	verify(view._guided_span_routes().physical and view._guided_span_routes().powered,
		"The same route is recognized on inclined belts with X-axis shafts.")
	view.state.transmission_parts.b1.center = [0, 12, 16]
	verify(not view._guided_span_routes().physical, "A disconnected sloped endpoint does not invent a route.")
	view.state.belt_spans.clear()
	kinds.erase("processor")
	verify("two parallel shafts" in view._guided_step(kinds).text and view._guided_step(kinds).tool == "drive",
		"The native opening introduces shaft endpoints for a new belt.")
	view.free()

func _nonhorizontal_presentation() -> void:
	var raw := {"raw": 1, "products": 0, "work_lots": []}
	for case in [
		{"axis": 2, "first": [0, 8, 0], "middle": [4, 12, 0], "last": [8, 16, 0], "cargo": true},
		{"axis": 0, "first": [0, 16, 0], "middle": [0, 12, 4], "last": [0, 8, 8], "cargo": true},
		{"axis": 2, "first": [0, 8, 0], "middle": [0, 12, 0], "last": [0, 16, 0], "cargo": false},
		{"axis": 1, "first": [0, 8, 0], "middle": [4, 8, 0], "last": [8, 8, 0], "cargo": false}]:
		var host := HostStub.new()
		host.state = fixture()
		host.state.transmission_parts = {}
		for id in ["first", "middle", "last"]:
			host.state.transmission_parts[id] = {"kind": "shaft", "generation": 1, "center": case[id], "axis": case.axis, "half_span": 2}
		host.state.belt_spans = {"span": {"generation": 1, "from": "first", "to": "last", "slots": [raw, null, null], "phase": 2048}}
		var controls := Controls.new()
		controls.configure(host)
		controls.choose_tool("belt_span")
		var confirmed: Dictionary = host.state.duplicate(true)
		controls.handle_world_click([], "first")
		controls.settle_belt_selection("request-1", true)
		controls.handle_world_click([], "last")
		verify(host.calls.size() == 2 and host.calls[0] == {"action": "select_belt_shaft", "entity": "first"} and host.calls[1] == {"action": "place_selected_belt_span", "from": "first", "to": "last", "selection": "request-1"} and host.state == confirmed, "Endpoint controls submit the path without inventing confirmed state.")
		controls.free()
		var presenter := Presenter.new()
		presenter.configure(host)
		var span := _part(presenter, "span")
		verify(span != null and span.has_node("BeltLoop"), "A confirmed nonhorizontal path renders a loop.")
		if span == null or not span.has_node("BeltLoop"):
			presenter.free()
			continue
		var loop: Node3D = span.get_node("BeltLoop")
		var near_rail: MeshInstance3D = loop.get_node_or_null("SpanFrameRailN")
		var far_rail: MeshInstance3D = loop.get_node_or_null("SpanFrameRailP")
		verify(near_rail != null and far_rail != null
			and loop.has_node("SpanFrameSeatNN") and loop.has_node("SpanFrameSeatPP")
			and near_rail.get_meta("span_frame_role", "") == "Rail"
			and far_rail.get_meta("span_frame_role", "") == "Rail"
			and near_rail.position.z < -Assets.SPAN_HALF_WIDTH
			and far_rail.position.z > Assets.SPAN_HALF_WIDTH,
			"The same loop carries its fixed outboard frame through horizontal and inclined orientations.")
		var start := Presenter.world_center(case.first)
		var finish := Presenter.world_center(case.last)
		var axis := Vector3.ZERO
		axis[case.axis] = 1.0
		verify(absf(loop.basis.x.dot((finish - start).normalized())) > 0.999 and absf(loop.basis.z.dot(axis)) > 0.999 and loop.basis.determinant() > 0.999, "The loop follows the path and rotates about its shaft axis.")
		verify(_part(presenter, "middle").has_node("BeltPulley") and span.get_node("Pick").basis.is_equal_approx(loop.basis), "The intermediate pulley and selection body follow the path.")
		var item := _belt_item(span, 0)
		if case.cargo:
			verify(item != null and (span.position + item.position).is_equal_approx(start.lerp(finish, 0.25) + Vector3.UP * 0.24), "Inclined cargo follows the confirmed half-slot phase.")
		else:
			verify(item == null, "Power-only vertical and sideways paths do not display cargo.")
		var session := Session.new()
		session.context = host.state.context
		session._ready_for_commands = true
		host.state.revision = 1
		host.state.order = 1
		session._apply_frame({"context": host.state.context, "serial": 1, "snapshot": host.state})
		verify(session.projection().is_empty(),
			"A normal Session frame remains pending until its scheduled state flush.")
		await process_frame
		await process_frame
		var remote := HostStub.new()
		remote.state = session.projection()
		verify(remote.state.get("belt_spans") == host.state.belt_spans,
			"The flushed Session projection retains the confirmed nonhorizontal path facts.")
		var remote_presenter := Presenter.new()
		remote_presenter.configure(remote)
		var remote_span := _part(remote_presenter, "span")
		verify(remote_span != null and remote_span.has_node("BeltLoop") and remote_span.get_node("BeltLoop").basis.is_equal_approx(loop.basis) and (_belt_item(remote_span, 0) != null) == case.cargo, "A confirmed Session frame preserves the path orientation and cargo presentation.")
		remote_presenter.free()
		session.free()
		var original_basis := loop.basis
		host.state.belt_spans.span.from = "last"
		host.state.belt_spans.span.to = "first"
		presenter.refresh()
		span = _part(presenter, "span")
		verify(span.get_node("BeltLoop").basis.is_equal_approx(original_basis), "Endpoint order does not flip the loop.")
		presenter.free()

func _belt_picking() -> void:
	for case in [
		{"axis": 2, "first": [0, 8, 0], "middle": [4, 12, 0], "last": [8, 16, 0]},
		{"axis": 0, "first": [0, 16, 0], "middle": [0, 12, 4], "last": [0, 8, 8]},
		{"axis": 2, "first": [0, 8, 0], "middle": [4, 8, 0], "last": [8, 8, 0]},
		{"axis": 2, "first": [0, 8, 0], "middle": [0, 12, 0], "last": [0, 16, 0]},
		{"axis": 1, "first": [0, 8, 0], "middle": [4, 8, 0], "last": [8, 8, 0]}]:
		var host := HostStub.new()
		host.state = fixture()
		host.state.transmission_parts = {}
		for id in ["first", "middle", "last"]:
			host.state.transmission_parts[id] = {"kind": "shaft", "generation": 1, "center": case[id], "axis": case.axis, "half_span": 2}
		host.state.belt_spans = {"span": {"generation": 1, "from": "first", "to": "last"}}
		var presenter := Presenter.new()
		root.add_child(presenter)
		presenter.configure(host)
		await physics_frame
		await physics_frame
		var span := _part(presenter, "span")
		var normal: Vector3 = span.get_node("BeltLoop").basis.y
		var first := Presenter.world_center(case.first)
		var middle := Presenter.world_center(case.middle)
		for probe in [{"point": first, "id": "first"}, {"point": middle, "id": "middle"},
			{"point": first.lerp(middle, 0.5), "id": "span"}]:
			var point: Vector3 = probe.point
			var ray := PhysicsRayQueryParameters3D.create(point + normal * 2.0, point - normal * 2.0, Geometry.PICK_LAYER)
			var hit := presenter.get_world_3d().direct_space_state.intersect_ray(ray)
			verify(not hit.is_empty() and hit.collider.get_meta("entity", "") == probe.id, "A selection ray reaches the intended %s on the belt path." % probe.id)
		presenter.queue_free()
		await process_frame

func _cog_axles() -> void:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for axis in range(3):
		for next_kind in ["gear", "shaft"]:
			var host := HostStub.new()
			host.state = fixture()
			var next_center := [0, 0, 0]
			next_center[axis] = 4
			host.state.transmission_parts = {
				"first": {"kind": "gear", "generation": 1, "center": [0, 0, 0], "axis": axis, "teeth": 2},
				"next": {"kind": next_kind, "generation": 2, "center": next_center, "axis": axis, "teeth": 4, "half_span": 2}}
			host.state.belt_spans = {}
			host.state.engagements = []
			var presenter := Presenter.new()
			root.add_child(presenter)
			presenter.configure(host)
			await physics_frame
			await physics_frame
			var first := _part(presenter, "first")
			var next := _part(presenter, "next")
			var first_shaft: CylinderMesh = first.get_node("Shaft").mesh
			var next_shaft: CylinderMesh = next.get_node("Shaft").mesh
			verify(is_equal_approx(first_shaft.height, Geometry.PITCH) and is_equal_approx(next_shaft.height, Geometry.PITCH)
				and (first.position + axes[axis] * first_shaft.height / 2.0).is_equal_approx(next.position - axes[axis] * next_shaft.height / 2.0),
				"Adjacent cog and %s integral axles meet exactly at their common tile face." % next_kind)
			var normal := Vector3.UP if axis != 1 else Vector3.RIGHT
			for probe in [{"part": first, "id": "first"}, {"part": next, "id": "next"}]:
				var point: Vector3 = probe.part.position + axes[axis] * 0.5
				var ray := PhysicsRayQueryParameters3D.create(point + normal * 0.4, point - normal * 0.4, Geometry.PICK_LAYER)
				var hit := presenter.get_world_3d().direct_space_state.intersect_ray(ray)
				verify(not hit.is_empty() and hit.collider.get_meta("entity", "") == probe.id,
					"The exposed axle selects its own confirmed %s tile." % probe.id)
			presenter.queue_free()
			await process_frame

func _belt_item(span: Node3D, slot: int) -> Node3D:
	if span == null:
		return null
	for child: Node in span.get_children():
		if child.get_meta("belt_slot", -1) == slot:
			return child
	return null

func _part(view: Node3D, id: String) -> Node3D:
	for child in view.get_children():
		if child.get_meta("entity", "") == id:
			return child
	return null

func _marks(view: Node3D) -> int:
	var count := 0
	for child in view.get_children():
		if child.has_meta("from"):
			count += 1
	return count

func _presentation() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var before: Dictionary = host.state.duplicate(true)
	var view := Presenter.new()
	view.configure(host)
	var a := _part(view, "a")
	var b := _part(view, "b")
	verify(a != null and b != null and a.position.is_equal_approx(Vector3(-1.65, 2.475, 1.65)) and b.position.is_equal_approx(Vector3(0, 2.475, 1.65)), "Quarter-grid centers map to the declared world anchors.")
	verify(a.get_node("ConfirmedDirection").get_meta("sign") == 1 and b.get_node("ConfirmedDirection").get_meta("sign") == -1, "Opposite signed rates produce opposite direction marks without a phase clock.")
	verify(_marks(view) == 1, "Only the confirmed engagement produces a contact mark.")
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var firsts := [Vector3(0, 0.825, 1.65), Vector3(0, 0.825, 0), Vector3(0, 0.825, 0)]
	var lasts := [Vector3(1.65, 0.825, 1.65), Vector3(0, 2.475, 0), Vector3(0, 0.825, 1.65)]
	for index in range(3):
		var part := _part(view, ["sx", "sy", "sz"][index])
		var mesh: CylinderMesh = part.get_node("Shaft").mesh
		verify(part.basis.y.is_equal_approx(axes[index]) and is_equal_approx(part.basis.determinant(), 1.0), "Each shaft uses a proper axis basis, including the vertical case.")
		verify((part.position - part.basis.y * mesh.height / 2).is_equal_approx(firsts[index]) and (part.position + part.basis.y * mesh.height / 2).is_equal_approx(lasts[index]), "Shaft endpoints match independent literal world coordinates.")
	verify(not _part(view, "sz").has_node("ConfirmedDirection"), "Stalled state is not animated or advertised as rotation.")
	for child in view.get_children():
		if child.has_meta("entity"):
			var body: StaticBody3D = child.get_node("Pick")
			verify(body.collision_layer == 4 and body.collision_mask == 0 and body.get_meta("entity") == child.get_meta("entity"), "Pick geometry cannot become actor or machine collision authority.")
	var first_id: int = a.get_instance_id()
	view.refresh()
	verify(_part(view, "a").get_instance_id() == first_id and host.state == before and host.calls.is_empty(), "An unchanged refresh reuses geometry and changes no projection or request.")
	for axis in range(3):
		host.state.transmission_parts.a.axis = axis
		view.refresh()
		verify(_part(view, "a").basis.y.is_equal_approx(axes[axis]), "Gear planes follow all three confirmed axes.")
	host.state.engagements = []
	view.refresh()
	verify(_marks(view) == 0, "Proximity alone never invents engagement.")
	host.state.transmission_parts.bad = {"kind": "gear", "center": [0, 0, 0], "axis": true, "teeth": 2}
	view.refresh()
	verify(_part(view, "bad") == null, "Malformed axis data does not create pick geometry.")
	host.state.options.native = false
	view.refresh()
	verify(not view.visible and view.get_child_count() == 0, "A scripted projection cannot retain old native geometry.")
	view.free()

func _belt_surface_motion() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.transmission_parts = {
		"a0": {"kind": "shaft", "generation": 10, "center": [0, 0, 0], "axis": 2, "half_span": 2},
		"a1": {"kind": "shaft", "generation": 11, "center": [8, 0, 0], "axis": 2, "half_span": 2},
		"b0": {"kind": "shaft", "generation": 12, "center": [0, 0, 8], "axis": 2, "half_span": 2},
		"b1": {"kind": "shaft", "generation": 13, "center": [8, 0, 8], "axis": 2, "half_span": 2}}
	host.state.motion = {"a0": {"state": "rotating", "numerator": 1, "denominator": 1},
		"a1": {"state": "rotating", "numerator": 1, "denominator": 1},
		"b0": {"state": "rotating", "numerator": -2, "denominator": 1},
		"b1": {"state": "rotating", "numerator": -2, "denominator": 1}}
	host.state.belt_spans = {"belt-a": {"from": "a0", "to": "a1"}, "belt-b": {"from": "b0", "to": "b1"}}
	var before: Dictionary = host.state.duplicate(true)
	var view := Presenter.new()
	view.configure(host)
	var loop_a: MeshInstance3D = _part(view, "belt-a").get_node("BeltLoop")
	var loop_b: MeshInstance3D = _part(view, "belt-b").get_node("BeltLoop")
	var material_a := loop_a.material_override as StandardMaterial3D
	var material_b := loop_b.material_override as StandardMaterial3D
	verify(material_a != material_b, "Each belt has its own surface phase without changing the cached rubber material.")
	view.advance_visual_motion(0.001)
	verify(is_equal_approx(view.visual_rotation("a0") * Assets.SPAN_OUTER_RADIUS,
		Geometry.PITCH * 0.001 / 0.45), "The pulley rim travels one tile per native tick at unit shaft rate.")
	var a_delta := wrapf(material_a.uv1_offset.x, -0.5, 0.5)
	var b_delta := wrapf(material_b.uv1_offset.x, -0.5, 0.5)
	verify(a_delta > 0.0 and b_delta < 0.0 and is_equal_approx(b_delta, -2.0 * a_delta),
		"Belt surfaces follow independent signed shaft rates.")
	var before_long_frame := view.visual_rotation("a0")
	var surface_before_long_frame := material_a.uv1_offset.x
	var factor: float = _part(view, "belt-a").get_meta("belt_uv_factor")
	view.advance_visual_motion(0.25)
	var expected_step := Presenter.VISUAL_RADIANS_PER_SECOND * 0.25
	verify(is_equal_approx(view.visual_rotation("a0") - before_long_frame, expected_step),
		"A long frame advances the shaft for the full elapsed duration.")
	verify(is_equal_approx(material_a.uv1_offset.x, fposmod(surface_before_long_frame + expected_step * factor, 1.0)),
		"A long frame advances the belt surface at the same confirmed shaft speed.")
	var prior_a := material_a.uv1_offset.x
	host.motion_fresh = false
	view.advance_visual_motion(0.1)
	verify(is_equal_approx(material_a.uv1_offset.x, prior_a), "A stale view cannot invent belt movement.")
	host.motion_fresh = true
	host.state.motion.a0 = {"state": "stalled", "numerator": 0, "denominator": 1}
	view.refresh()
	material_a = _part(view, "belt-a").get_node("BeltLoop").material_override
	verify(is_equal_approx(material_a.uv1_offset.x, prior_a), "A rebuilt stopped belt preserves its cosmetic phase.")
	view.advance_visual_motion(0.1)
	verify(is_equal_approx(material_a.uv1_offset.x, prior_a), "A stalled belt surface remains still.")
	verify(before.transmission_parts == host.state.transmission_parts and host.calls.is_empty(),
		"Cosmetic belt motion does not submit commands or alter transmission geometry.")
	view.free()
	for example in [
		{"axis": 2, "end": [8, 0, 0], "sign": 1.0},
		{"axis": 0, "end": [0, 0, 8], "sign": -1.0},
		{"axis": 2, "end": [8, 8, 0], "sign": 1.0},
		{"axis": 2, "end": [0, 8, 0], "sign": 1.0},
		{"axis": 1, "end": [8, 0, 0], "sign": 1.0}]:
		for reversed in [false, true]:
			var oriented := HostStub.new()
			oriented.state = fixture()
			oriented.state.transmission_parts = {
				"first": {"kind": "shaft", "generation": 1, "center": [0, 0, 0], "axis": example.axis, "half_span": 2},
				"last": {"kind": "shaft", "generation": 2, "center": example.end, "axis": example.axis, "half_span": 2}}
			oriented.state.motion = {"first": {"state": "rotating", "numerator": 1, "denominator": 1},
				"last": {"state": "rotating", "numerator": 1, "denominator": 1}}
			oriented.state.belt_spans = {"span": {"from": "last" if reversed else "first", "to": "first" if reversed else "last"}}
			var presenter := Presenter.new()
			presenter.configure(oriented)
			var loop: MeshInstance3D = _part(presenter, "span").get_node("BeltLoop")
			presenter.advance_visual_motion(0.001)
			var offset: float = (loop.material_override as StandardMaterial3D).uv1_offset.x
			verify(wrapf(offset, -0.5, 0.5) * example.sign > 0.0,
				"Surface travel respects axle orientation and is independent of endpoint order.")
			presenter.free()

func _belt_cargo_cadence() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.transmission_parts = {
		"first": {"kind": "shaft", "generation": 1, "center": [0, 0, 0], "axis": 2, "half_span": 2},
		"last": {"kind": "shaft", "generation": 1, "center": [8, 0, 0], "axis": 2, "half_span": 2}}
	host.state.motion = {"first": {"state": "rotating", "numerator": -1, "denominator": 1}}
	var raw := {"raw": 1, "products": 0, "work_lots": []}
	host.state.belt_spans = {"span": {"generation": 1, "from": "first", "to": "last",
		"phase": 0, "slots": [raw, null, null]}}
	var view := Presenter.new()
	view.configure(host)
	var span := _part(view, "span")
	var pick_id := span.get_node("Pick").get_instance_id()
	var authoritative: Dictionary = host.state.duplicate(true)
	var prior_x: float = _belt_item(span, 0).position.x
	var largest_step := 0.0
	for frame in 27:
		view.advance_visual_motion(1.0 / 60.0)
		var x: float = _belt_item(span, 0).position.x
		largest_step = maxf(largest_step, absf(x - prior_x))
		prior_x = x
	verify(largest_step < 0.07 and is_equal_approx(prior_x, 0.0) and host.state == authoritative,
		"Confirmed unit-rate material travels one tile in 27 render frames without altering native slots.")
	host.state.belt_spans.span.slots = [null, raw, null]
	view.refresh()
	span = _part(view, "span")
	verify(span.get_node("Pick").get_instance_id() == pick_id and
		absf(_belt_item(span, 1).position.x - prior_x) < 0.001,
		"The authoritative slot handoff meets the preceding visual at the same tile without rebuilding the pick.")
	for frame in 27:
		view.advance_visual_motion(1.0 / 60.0)
	host.state.belt_spans.span.slots = [null, null, raw]
	view.refresh()
	span = _part(view, "span")
	verify(is_equal_approx(_belt_item(span, 2).position.x, 1.65),
		"An occupied endpoint stays within the confirmed span at its next native cut.")
	host.state.motion.first = {"state": "rotating", "numerator": 1, "denominator": 1}
	view.refresh()
	span = _part(view, "span")
	for frame in 27:
		view.advance_visual_motion(1.0 / 60.0)
	verify(is_equal_approx(_belt_item(span, 2).position.x, 0.0),
		"Reversing the confirmed shaft moves the endpoint material smoothly back one tile.")
	host.state.belt_spans.span.slots = [null, raw, null]
	host.state.motion.first = {"state": "stalled", "numerator": 0, "denominator": 1}
	view.refresh()
	span = _part(view, "span")
	view.advance_visual_motion(0.45)
	verify(is_equal_approx(_belt_item(span, 1).position.x, 0.0),
		"A stalled belt holds cargo at its last confirmed position.")
	host.state.motion.first = {"state": "rotating", "numerator": -1, "denominator": 1}
	host.state.belt_spans.span.slots = [raw, raw, raw]
	view.refresh()
	span = _part(view, "span")
	view.advance_visual_motion(0.45)
	verify(is_equal_approx(_belt_item(span, 0).position.x, -1.65) and
		is_equal_approx(_belt_item(span, 1).position.x, 0.0),
		"A full downstream chain never animates cargo through another item or beyond the end.")
	view.free()
	var incline := HostStub.new()
	incline.state = fixture()
	incline.state.transmission_parts = {
		"first": {"kind": "shaft", "generation": 1, "center": [0, 0, 0], "axis": 2, "half_span": 2},
		"last": {"kind": "shaft", "generation": 1, "center": [8, 8, 0], "axis": 2, "half_span": 2}}
	incline.state.motion = {"first": {"state": "rotating", "numerator": -1, "denominator": 1}}
	incline.state.belt_spans = {"span": {"generation": 1, "from": "first", "to": "last",
		"phase": 0, "slots": [raw, null, null]}}
	var incline_view := Presenter.new()
	incline_view.configure(incline)
	var incline_start: Vector3 = _belt_item(_part(incline_view, "span"), 0).position
	incline_view.advance_visual_motion(0.45)
	var incline_end: Vector3 = _belt_item(_part(incline_view, "span"), 0).position
	var expected_distance := Geometry.PITCH * 2896.0 / 4096.0
	verify(is_equal_approx(incline_end.x - incline_start.x, expected_distance) and
		is_equal_approx(incline_end.y - incline_start.y, expected_distance),
		"An inclined run follows its native sub-tile distance along both world axes.")
	incline.state.motion.first = {"state": "rotating", "numerator": -1, "denominator": 2}
	incline_view.refresh()
	incline_view.advance_visual_motion(0.45)
	var half_end: Vector3 = _belt_item(_part(incline_view, "span"), 0).position
	verify(is_equal_approx(half_end.x - incline_start.x, expected_distance * 0.5),
		"A fractional shaft rate proportionally slows inclined cargo travel.")
	incline_view.free()

func _cache_regression() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var view := Presenter.new()
	view.configure(host)
	var first_id: int = _part(view, "a").get_instance_id()
	var pick_id: int = _part(view, "a").get_node("Pick").get_instance_id()
	view.refresh()
	verify(_part(view, "a").get_instance_id() == first_id and _part(view, "a").get_node("Pick").get_instance_id() == pick_id, "An unchanged refresh preserves both mesh subtree and pick-body identities.")
	host.state.parts.gear = 88
	view.refresh()
	verify(_part(view, "a").get_instance_id() == first_id, "An unrelated compatibility counter does not rebuild transmission geometry.")
	host.state.motion.a.numerator = -1
	view.refresh()
	verify(_part(view, "a").get_instance_id() != first_id and _part(view, "a").get_node("ConfirmedDirection").get_meta("sign") == -1, "Changed signed motion refreshes the confirmed direction mark.")
	host.state.motion.a.state = "unpowered"
	host.state.motion.a.numerator = 0
	view.refresh()
	verify(not _part(view, "a").has_node("ConfirmedDirection"), "Stopping confirmed motion removes the rotation indication.")
	host.state.transmission_parts.a.center = [-3, 4, 4]
	view.refresh()
	verify(_part(view, "a").position.is_equal_approx(Vector3(-1.2375, 2.475, 1.65)), "A changed center refreshes its world-space geometry.")
	first_id = _part(view, "a").get_instance_id()
	host.state.context = "another-context"
	view.refresh()
	verify(_part(view, "a").get_instance_id() != first_id, "A new confirmed context does not retain old pick identities.")
	host.state.engagements = []
	view.refresh()
	verify(_marks(view) == 0, "A changed engagement catalogue removes the old contact mark.")
	var before: Dictionary = host.state.duplicate(true)
	view.refresh()
	verify(host.state == before and host.calls.is_empty(), "Cache refresh reads do not mutate projection or submit a command.")
	# Shared clients hold a Session rather than NativeModel. The presence of a
	# live projection source must still batch its first cog and keep both picks.
	host.model = RefCounted.new()
	host.state.context = "session-backed-fixture"
	view.refresh()
	var batch: Dictionary = view._gear_batches.get(2, {})
	verify(not batch.is_empty() and batch.mesh.instance_count == 2
		and _part(view, "a").has_node("Pick") and _part(view, "b").has_node("Pick"),
		"A Session-backed projection batches early cogs without losing individual picks.")
	view.free()

func _direction_basis() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var view := Presenter.new()
	view.configure(host)
	for axis in range(3):
		host.state.transmission_parts.a.axis = axis
		host.state.transmission_parts.b.axis = axis
		view.refresh()
		for id in ["a", "b"]:
			var part := _part(view, id)
			var segment: MeshInstance3D = part.get_node("ConfirmedDirection").get_child(0)
			var radial := segment.position
			radial.y = 0
			var signed_normal: float = part.basis.y.dot((part.basis * radial.normalized()).cross(part.basis * segment.basis.y))
			var sign_value: int = host.state.motion[id].numerator
			verify(signed_normal * float(sign_value) > 0.9, "The actual direction arc follows signed right-hand rotation on every declared axis.")
	view.free()

func _tool_guidance() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.messages.append("Previous machine-placement advice.")
	var view := Controls.new()
	view.configure(host)
	var before: Dictionary = host.state.duplicate(true)
	verify(view.get_popup().get_item_index(4) == -1,
		"The transmission menu leaves dismantling to the F world tool instead of offering a stale remove item.")
	for choice in [[1, "cogwheel"], [6, "shaft tile"], [7, "parallel shafts"], [5, "construction tool"]]:
		var count: int = host.messages.size()
		view.get_popup().id_pressed.emit(choice[0])
		verify(host.messages.size() == count + 1 and str(host.messages.back()).contains(choice[1]),
			"Popup selection replaces stale advice for operation " + str(choice[0]))
	verify(host.calls.is_empty() and host.state == before, "Popup advice sends no request and changes no confirmed facts.")
	host.mutate_allowed = false
	var count: int = host.messages.size()
	view.get_popup().id_pressed.emit(1)
	verify(host.messages.size() == count, "An unusable view preserves connection advice.")
	print(JSON.stringify({"popup_messages": host.messages, "requests": host.calls.size()}))
	view.free()

func _pointed_loose_material() -> void:
	var opening := PickupOpening.new()
	opening.state = fixture()
	opening.state.transmission_parts = {}
	opening.state.entities = {}
	opening.state.motion = {}
	root.add_child(opening)
	opening.camera = Camera3D.new()
	opening.add_child(opening.camera)
	opening.camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	opening.add_child(light)
	var ui := Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening.add_child(ui)
	opening._build_pointed_summary(ui)
	var presenter := Presenter.new()
	opening.add_child(presenter)
	var screen := opening._pointed_screen_position()
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	verify(not opening.developer_material_tools and opening.loose_material_controls == null,
		"Ordinary opening does not opt into developer material commands.")
	for drop in [{"center": [0, 0, 0], "raw": 1, "products": 0, "work_lots": []},
			{"center": [0, 0, 0], "raw": 0, "products": 1, "work_lots": []},
			{"center": [0, 0, 0], "raw": 0, "products": 0, "work_lots": [{"id": 7}]},
			{"center": [0, 0, 0], "raw": 0, "products": 0, "work_lots": [], "offcuts": 1},
			{"center": [0, 0, 0], "raw": 0, "products": 0, "work_lots": [],
				"sheets": 1, "sheet_items": [{"id": 9, "rotation": 1}]}]:
		opening.state.dropped_material = [drop]
		presenter.configure(opening)
		await process_frame
		var pickers := presenter.find_children("LooseMaterialPicker", "StaticBody3D", true, false)
		verify(not pickers.is_empty(), "Every visible loose material form has a mesh-aligned picker.")
		if pickers.is_empty():
			continue
		var mesh: MeshInstance3D = pickers[0].get_parent()
		# Aim inside the rendered mesh, away from the stamped plate's open hole.
		var target := mesh.global_transform * mesh.get_aabb().get_center()
		opening.camera.position = target + Vector3(0.1, 2.0, 1.5)
		opening.camera.look_at(target)
		await physics_frame
		await physics_frame
		verify(opening._screen_loose_material(screen) == drop,
			"Camera ray selects the displayed item and its exact native drop.")
		var summary: Dictionary = opening._pointed_summary_data(screen)
		verify(summary.get("detail") == "E  Pick up" and not str(summary.get("name", "")).begins_with("0 "),
			"The pointed cue offers E pickup and describes occupied material only.")
		if drop.products == 1:
			for argument: String in OS.get_cmdline_user_args():
				if argument.begins_with("--loose-material-image="):
					opening._refresh_pointed_summary()
					await process_frame
					await RenderingServer.frame_post_draw
					verify(root.get_texture().get_image().save_png(argument.trim_prefix("--loose-material-image=")) == OK,
						"Capture the actual plate and pointed pickup cue.")
		var before := opening.state.duplicate(true)
		opening.calls.clear()
		opening._unhandled_input(key)
		var expected: Dictionary = drop.duplicate(true)
		expected.erase("center")
		verify(opening.calls == [{"action": "pickup_material", "center": drop.center, "expected": expected}]
				and opening.state == before,
			"E submits exact custody to the host; a refusal cannot remove or replace the item locally.")
		opening.calls.clear()
		opening.state.actors.P.ready = false
		opening._unhandled_input(key)
		verify(opening.calls.is_empty(), "An unready actor cannot submit a pickup from E.")
		opening.state.actors.P.ready = true
		opening.state.dropped_material = []
		verify(opening._screen_loose_material(screen).is_empty(), "A stale rendered item cannot be picked up after removal.")
		opening.state.dropped_material = [drop.duplicate(true)]
		opening.state.dropped_material[0].raw += 1
		verify(opening._screen_loose_material(screen).is_empty(), "Replacement custody at the same point cannot use an old picker.")
		opening.state.dropped_material = [drop]
		opening.state.context = "another-world"
		verify(opening._screen_loose_material(screen).is_empty(), "A picker from a previous world cannot submit a command.")
		opening.state.context = "helper-fixture"
		var barrier := StaticBody3D.new()
		barrier.collision_layer = Geometry.MACHINE_LAYER
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = Vector3(0.4, 0.4, 0.4)
		barrier.add_child(shape)
		opening.add_child(barrier)
		barrier.position = opening.camera.project_ray_origin(screen) + opening.camera.project_ray_normal(screen) * 0.7
		await physics_frame
		await physics_frame
		verify(opening._screen_loose_material(screen).is_empty(), "A nearer machine blocks material selection through it: " + str(drop))
		barrier.free()
	opening.free()
	await process_frame

func _loose_material() -> void:
	var host := HostStub.new()
	host.state = fixture()
	host.state.dropped_material = [{"center": [2, 0, 4], "raw": 3, "products": 0, "work_lots": []}]
	var menu := LooseControls.new()
	menu.configure(host)
	verify(menu.visible and not menu.disabled, "A confirmed loose stack is offered to the ready actor.")
	menu._open()
	var before: Dictionary = host.state.duplicate(true)
	menu._choose(0)
	verify(host.calls == [{"action": "pickup_material", "center": [2, 0, 4], "expected": {"raw": 3, "products": 0, "work_lots": []}}] and host.state == before,
		"Pickup submits the exact confirmed location without speculatively changing custody.")
	menu._open()
	host.state.context = "another-world"
	menu._choose(0)
	verify(host.calls.size() == 1, "A menu opened for another world cannot submit a stale selection.")
	host.state.context = "helper-fixture"
	menu._open()
	host.state.dropped_material = []
	menu._choose(0)
	verify(host.calls.size() == 1, "A vanished stack cannot be selected from an old menu.")
	host.state.dropped_material = [{"center": [2, 0, 4], "raw": 3, "products": 0, "work_lots": []}]
	menu._open()
	host.mutate_allowed = false
	menu._choose(0)
	verify(host.calls.size() == 1, "A shared mutation barrier prevents pickup submission.")
	var presenter := Presenter.new()
	presenter.configure(host)
	var blank := presenter.get_node_or_null("LooseBlank")
	verify(blank is MeshInstance3D and blank.position == Presenter.world_center([2, 0, 4]),
		"The confirmed stack is rendered at its world location without requiring the belt to exist.")
	host.mutate_allowed = true
	for drop in [{"center": [2, 0, 4], "raw": 0, "products": 1, "work_lots": []},
		{"center": [2, 0, 4], "raw": 0, "products": 0, "work_lots": [{"id": 7}]},
		{"center": [2, 0, 4], "raw": 0, "products": 0, "work_lots": [], "offcuts": 1, "sheets": 0}]:
		host.state.dropped_material = [drop]
		presenter.refresh()
		menu._open()
		verify(menu.get_popup().item_count == 1 and not presenter.get_node_or_null("LooseBlank"), "A plate or workpiece has a loose-material offer and a distinct visual.")
		menu._choose(0)
		var expected: Dictionary = drop.duplicate(true)
		expected.erase("center")
		verify(host.calls.back() == {"action": "pickup_material", "center": [2, 0, 4], "expected": expected}, "Typed loose cargo uses the confirmed pickup request.")
		if drop.get("offcuts", 0) > 0:
			var offcut_visual := presenter.get_node_or_null("CopperOffcuts")
			verify(offcut_visual is Node3D and offcut_visual.position == Presenter.world_center([2, 0, 4]) and offcut_visual.find_children("*", "MeshInstance3D", true, false).size() == 6 and menu.get_popup().get_item_text(0).contains("offcut"),
				"The recovered copper remnant has a distinct world visual and visible pickup offer.")
		menu._open()
		host.state.dropped_material = [{"center": [2, 0, 4], "raw": 1, "products": 0, "work_lots": []}]
		var count := host.calls.size()
		menu._choose(0)
		verify(host.calls.size() == count, "A replacement at the same location cannot use an outdated menu offer.")
	host.state.dropped_material = [{"center": [2, 0, 4], "raw": 0, "products": 4, "work_lots": []}]
	presenter.refresh()
	var plate_stack := presenter.get_node_or_null("LoosePlateStack")
	var plate_heights: Array[float] = []
	if plate_stack is Node3D:
		for child in plate_stack.get_children():
			if child is Node3D and child.get_meta("item_kind", "") == "stamped_plate":
				plate_heights.append(child.position.y)
	verify(plate_heights.size() == 4 and plate_heights[0] < plate_heights[3],
		"Four confirmed products appear as four separate stacked plates in the world.")
	host.state.dropped_material = []
	presenter.refresh()
	verify(presenter.get_node_or_null("LooseBlank") == null, "The presentation removes a picked-up stack after confirmed state changes.")
	menu.free()
	presenter.free()
	var session := Session.new()
	session.context = "helper-fixture"
	session._ready_for_commands = true
	host.state.dropped_material = [{"center": [2, 0, 4], "raw": 3, "products": 0, "work_lots": []}]
	host.state.revision = 1
	host.state.order = 1
	session._apply_frame({"context": "helper-fixture", "serial": 1, "snapshot": host.state}, true)
	verify(session.projection().dropped_material == host.state.dropped_material,
		"The read-only Session frame retains the server's loose-material projection.")
	var mixed := {"center": [2, 0, 4], "raw": 1, "products": 1, "work_lots": [{"id": 7, "recipe_input": 1, "cycle_ticks": 2, "remaining": 1, "completed_subticks": 123, "work_remainder": 1, "work_remainder_denominator": 3}]}
	host.state.dropped_material = [mixed]
	host.state.revision = 2
	host.state.order = 2
	session._apply_frame({"context": "helper-fixture", "serial": 2, "snapshot": host.state}, true)
	var remote := HostStub.new()
	remote.state = session.projection()
	var remote_menu := LooseControls.new()
	remote_menu.configure(remote)
	remote_menu._open()
	remote_menu._choose(0)
	var expected := mixed.duplicate(true)
	expected.erase("center")
	verify(remote.state.dropped_material == [mixed] and remote.calls == [{"action": "pickup_material", "center": [2, 0, 4], "expected": expected}], "A Session projection preserves a mixed stack and submits its exact confirmed work identity.")
	remote_menu.free()
	host.state.dropped_material = []
	host.state.revision = 3
	host.state.order = 3
	session._apply_frame({"context": "helper-fixture", "serial": 3, "snapshot": host.state}, true)
	verify(session.projection().dropped_material.is_empty(), "A later confirmed Session frame removes the picked-up stack.")
	session.free()

func _slide_material_seat() -> void:
	var state := {"context": "slide-material-seat", "revision": 1,
		"options": {"native": true}, "transmission_parts": {}, "belt_spans": {},
		"motion": {}, "collector_assemblies": [], "press_assemblies": [],
		"guided_press_assemblies": []}
	state.placed_components = {
		"anvil": _component_record("anvil", [0, 0, 0], [0.0, 0.20625, 0.0], [0.2025, 0.20625, 0.14]),
		"head": _component_record("flat_head", [0, 1, 0], [0.0, 0.928125, 0.0], [0.14, 0.515625, 0.14]),
		"slide": _component_record("wooden_slide", [0, 2, 0], [0.0, 1.44375, 0.0], [0.21, 0.4125, 0.21])}
	state.sliding_press_assemblies = [{"anvil": "anvil", "center": [0, 0, 0],
		"status": "ready", "work_center": [0, 0, 0],
		"parts": {"anvil": "anvil", "head": "head", "slide": "slide"}}]
	state.dropped_material = [{"center": [0, 0, 0], "raw": 1, "products": 0, "work_lots": []}]
	var host := HostStub.new()
	host.state = state
	var presenter := Presenter.new()
	root.add_child(presenter)
	presenter.configure(host)
	var anvil: Node3D
	for child: Node in presenter.get_children():
		if child.has_meta("component_entity") and child.get_meta("component_entity") == "anvil":
			anvil = child
	var seat: MeshInstance3D = anvil.get_node_or_null("OpenAnvilSeat") if anvil != null else null
	var die_plate: MeshInstance3D = anvil.get_node_or_null("ReplaceableDiePlate") if anvil != null else null
	var blank: MeshInstance3D = presenter.get_node_or_null("LooseBlank")
	var crown: float = 0.4125
	verify(seat != null and die_plate != null and blank != null
		and is_equal_approx(seat.global_position.y + 0.0275, crown)
		and is_equal_approx(die_plate.global_position.y + 0.003, crown)
		and is_equal_approx(blank.position.y - 0.04, crown - 0.02),
		"The admitted anvil crown, visible seat and native-confirmed blank share one work surface.")
	var raw_label: Label3D
	if blank != null:
		for child: Node in blank.get_children():
			if child is Label3D:
				raw_label = child
	verify(raw_label != null and raw_label.position.x > 0.2 and raw_label.position.y < 0.1,
		"The blank count sits beside the work surface instead of on the slide carriage.")
	var image_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--slide-material-image="):
			image_path = argument.trim_prefix("--slide-material-image=")
	if not image_path.is_empty():
		verify(DisplayServer.get_name().to_lower() != "headless",
			"The material frame requires a rendered display.")
		root.size = Vector2i(1280, 800)
		var environment := WorldEnvironment.new()
		var sky := Environment.new()
		sky.background_mode = Environment.BG_COLOR
		sky.background_color = Color("303c3c")
		environment.environment = sky
		root.add_child(environment)
		var floor := MeshInstance3D.new()
		var floor_mesh := BoxMesh.new()
		floor_mesh.size = Vector3(1.5, 0.05, 1.5)
		floor.mesh = floor_mesh
		floor.position.y = 0.025
		root.add_child(floor)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, -30, 0)
		root.add_child(sun)
		var camera := Camera3D.new()
		camera.position = Vector3(1.25, 1.55, 2.6)
		camera.fov = 45
		root.add_child(camera)
		camera.look_at(Vector3(0, 0.83, 0))
		camera.current = true
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(image_path.trim_suffix(".png") + "-blank.png") == OK,
			"Retain the visible supported blank frame.")
	state.dropped_material = [{"center": [0, 0, 0], "raw": 0, "products": 0,
		"work_lots": [{"id": 7, "remaining": 1, "cycle_ticks": 2}]}]
	state.slide_phases = {"slide": {"subticks": 2048, "remainder": 0,
		"denominator": 1, "cycle_subticks": 4096}}
	presenter.refresh()
	var work: MeshInstance3D = presenter.get_node_or_null("PressedWorkpiece")
	var head_face: MeshInstance3D = null
	for child: Node in presenter.get_children():
		if child.get_meta("component_entity", "") == "head":
			head_face = child.get_node_or_null("FlatHeadMovingDie/FlatHeadFace") as MeshInstance3D
	var work_top: float = (work.global_transform * work.mesh.get_aabb()).end.y if work != null else INF
	var die_bottom: float = (head_face.global_transform * head_face.mesh.get_aabb()).position.y \
		if head_face != null else -INF
	verify(work != null and is_equal_approx(work.position.y - 0.03, crown - 0.02)
		and absf(die_bottom - work_top) < 0.001
		and presenter.get_node_or_null("LooseBlank") == null,
		"The half-cycle die meets the thinner copper workpiece on the supported anvil.")
	if not image_path.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(image_path.trim_suffix(".png") + "-work.png") == OK,
			"Retain the visible supported workpiece frame.")
	state.dropped_material = [{"center": [0, 0, 0], "raw": 0, "products": 1,
		"work_lots": [], "offcuts": 1}]
	state.slide_phases.slide.subticks = 0
	presenter.refresh()
	var plate := presenter.get_node_or_null("LoosePlateStack")
	var sheet: MeshInstance3D = plate.get_node_or_null("StampedPlate/PlateSheet") if plate != null else null
	var trimmings := plate.get_node_or_null("CopperOffcuts") if plate != null else null
	var label: Label3D = null
	if plate != null:
		for child: Node in plate.get_children():
			if child is Label3D:
				label = child
	verify(plate != null and sheet != null and trimmings != null and label != null
		and is_equal_approx(plate.position.y - 0.03, crown - 0.02)
		and is_equal_approx(sheet.global_position.y - sheet.mesh.get_aabb().size.y * 0.5,
			crown - 0.02)
		and label.text == "1 plate + 1 offcut",
		"The finished plate rests on the sliding workbed with its recoverable offcut visible.")
	verify(plate != null and not plate.find_children("LooseMaterialPicker", "StaticBody3D", true, false).is_empty(),
		"The supported plate keeps a mesh-aligned pickup target.")
	if not image_path.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(image_path.trim_suffix(".png") + "-plate.png") == OK,
			"Retain the visible finished plate on its sliding workbed.")
	var opening := PickupOpening.new()
	opening.state = fixture()
	opening.state.context = state.context
	opening.state.dropped_material = state.dropped_material.duplicate(true)
	root.add_child(opening)
	var pointer_camera := Camera3D.new()
	root.add_child(pointer_camera)
	opening.camera = pointer_camera
	var target: Vector3 = sheet.global_transform * sheet.mesh.get_aabb().get_center()
	pointer_camera.position = target + Vector3(0.1, 0.42, 1.2)
	pointer_camera.look_at(target)
	pointer_camera.current = true
	verify(root.get_camera_3d() == pointer_camera,
		"The pickup frame uses the same close camera as the supported plate ray.")
	var pointer_ui := Control.new()
	pointer_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening.add_child(pointer_ui)
	opening._build_pointed_summary(pointer_ui)
	await physics_frame
	await physics_frame
	var screen := opening._pointed_screen_position()
	verify(opening._screen_loose_material(screen) == state.dropped_material[0],
		"The supported finished plate is selected by an unobstructed camera ray.")
	var summary: Dictionary = opening._pointed_summary_data(screen)
	verify(summary.get("name") == "1 copper plate, 1 copper offcut" and summary.get("detail") == "E  Pick up",
		"The supported plate has an E pickup cue that includes its recoverable offcut.")
	if not image_path.is_empty():
		opening._refresh_pointed_summary()
		verify(opening.pointed_summary.visible,
			"The supported plate pickup cue is visible in the rendered frame.")
		await process_frame
		await RenderingServer.frame_post_draw
		verify(root.get_texture().get_image().save_png(image_path.trim_suffix(".png") + "-pickup.png") == OK,
			"Retain the supported plate and its pointed pickup cue together.")
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	opening._unhandled_input(key)
	var expected: Dictionary = state.dropped_material[0].duplicate(true)
	expected.erase("center")
	verify(opening.calls == [{"action": "pickup_material", "center": [0, 0, 0], "expected": expected}],
		"E requests exactly the native confirmed supported plate and offcut.")
	opening.free()
	pointer_camera.free()
	presenter.free()

func _mechanical_collision_geometry() -> void:
	var state := {"options": {"native": true}, "transmission_parts": {
		"a": {"kind": "shaft", "center": [0, 0, 0], "axis": 2, "half_span": 2},
		"b": {"kind": "shaft", "center": [8, 0, 0], "axis": 2, "half_span": 2},
		"c": {"kind": "gear", "center": [0, 4, 4], "axis": 0, "teeth": 4}},
		"belt_spans": {"belt": {"from": "a", "to": "b"}}}
	var result := Geometry.mechanical_boxes(state)
	verify(result.accepted and result.boxes.size() == 4, "Every confirmed mechanical part receives exactly one body.")
	verify(result.boxes.a.center.is_equal_approx(Vector3(0, 0.825, 0)) and result.boxes.a.size.is_equal_approx(Vector3(0.2, 0.2, 1.65)), "Shaft bounds match Host placement dimensions.")
	verify(result.boxes.c.center.is_equal_approx(Vector3(0, 2.475, 1.65)) and result.boxes.c.size.is_equal_approx(Vector3(0.08, 1.65, 1.65)), "Cog bounds use the axle plane and shared height origin.")
	verify(result.boxes.c.axle_size.is_equal_approx(Vector3(1.65, 0.2, 0.2)), "The cog's separate axle reaches exactly its tile faces.")
	var bridge: Dictionary = state.duplicate(true)
	bridge.belt_spans.clear()
	bridge.transmission_parts.erase("b")
	bridge.transmission_parts.erase("c")
	bridge.transmission_parts.a.axis = 0
	bridge.transmission_parts.a.center = [2, 0, 0]
	var bridge_boxes := Geometry.mechanical_boxes(bridge)
	verify(bridge_boxes.accepted and bridge_boxes.boxes.a.center.is_equal_approx(Vector3(0.825, 0.825, 0))
			and bridge_boxes.boxes.a.size.is_equal_approx(Vector3(1.65, 0.2, 0.2)),
			"A half-span shaft centered between adjacent x ports has one exact physical body.")
	bridge.transmission_parts.a.center = [-2, 0, 0]
	verify(Geometry.mechanical_boxes(bridge).accepted,
			"The same half-tile shaft grid works across the global origin.")
	bridge.transmission_parts.a.center = [0, 0, 2]
	verify(not Geometry.mechanical_boxes(bridge).accepted,
			"A half-tile center perpendicular to the shaft axis cannot bypass physical validation.")
	bridge.transmission_parts.a.axis = 2
	verify(Geometry.mechanical_boxes(bridge).accepted,
			"The along-axis half-tile bridge also has a valid z-oriented physical body.")
	bridge.transmission_parts.a.kind = "gear"
	bridge.transmission_parts.a.teeth = 2
	verify(not Geometry.mechanical_boxes(bridge).accepted,
			"A gear cannot inherit the shaft-only half-tile exception.")
	verify(result.boxes.belt.center.is_equal_approx(Vector3(1.65, 0.825, 0)) and result.boxes.belt.size.is_equal_approx(Vector3(4.95, 0.3, 0.6)), "Belt bounds cover every tile including both pulleys.")
	var reversed: Dictionary = state.duplicate(true)
	reversed.belt_spans.belt = {"from": "b", "to": "a"}
	verify(Geometry.mechanical_boxes(reversed).boxes.belt == result.boxes.belt, "Reversing endpoints preserves physical bounds.")
	var moved: Dictionary = state.duplicate(true)
	moved.transmission_parts.b.center = [0, 0, 8]
	moved.transmission_parts.a.axis = 0
	moved.transmission_parts.b.axis = 0
	var rotated := Geometry.mechanical_boxes(moved)
	verify(rotated.accepted and rotated.boxes.belt.size.is_equal_approx(Vector3(0.6, 0.3, 4.95)), "The other horizontal direction rotates the span bounds.")
	for axle in [0, 2]:
		for sign_value in [-1, 1]:
			var slope: Dictionary = state.duplicate(true)
			slope.transmission_parts.a.axis = axle
			slope.transmission_parts.b.axis = axle
			slope.transmission_parts.b.center = [8 if axle == 2 else 0, 8 * sign_value, 8 if axle == 0 else 0]
			var sloped := Geometry.mechanical_boxes(slope)
			var reverse_slope: Dictionary = slope.duplicate(true)
			reverse_slope.belt_spans.belt = {"from": "b", "to": "a"}
			verify(sloped.accepted and sloped.boxes.belt.has("basis") and Geometry.mechanical_boxes(reverse_slope).boxes.belt == sloped.boxes.belt, "An inclined belt has a stable rotated body for either axle and slope.")
	var vertical: Dictionary = state.duplicate(true)
	vertical.transmission_parts.b.center = [0, 8, 0]
	verify(Geometry.mechanical_boxes(vertical).boxes.belt.size.is_equal_approx(Vector3(0.3, 4.95, 0.6)), "A vertical power-only belt has a narrow vertical body.")
	var sideways: Dictionary = state.duplicate(true)
	sideways.transmission_parts.a.axis = 1
	sideways.transmission_parts.b.axis = 1
	verify(Geometry.mechanical_boxes(sideways).boxes.belt.size.is_equal_approx(Vector3(4.95, 0.6, 0.3)), "A sideways power-only belt has a narrow side-facing body.")
	var bad_slope: Dictionary = state.duplicate(true)
	bad_slope.transmission_parts.b.center = [8, 4, 0]
	verify(not Geometry.mechanical_boxes(bad_slope).accepted, "An unequal slope is rejected by physical geometry.")
	var removed: Dictionary = state.duplicate(true)
	removed.belt_spans.clear()
	removed.transmission_parts.erase("b")
	verify(Geometry.mechanical_boxes(removed).boxes.size() == 2, "Removing a span and shaft removes their derived bodies.")
	for fault: String in ["missing_endpoint", "off_grid", "invalid_axis", "too_long", "duplicate_identity"]:
		var bad: Dictionary = state.duplicate(true)
		match fault:
			"missing_endpoint": bad.belt_spans.belt.to = "missing"
			"off_grid": bad.transmission_parts.a.center = [1, 0, 0]
			"invalid_axis": bad.transmission_parts.a.axis = true
			"too_long": bad.transmission_parts.b.center = [80, 0, 0]
			"duplicate_identity": bad.belt_spans = {"a": {"from": "a", "to": "b"}}
		verify(not Geometry.mechanical_boxes(bad).accepted, "Malformed %s topology fails closed." % fault)
	verify(Geometry.mechanical_boxes({"options": {"native": false}}).boxes.is_empty(), "Legacy fixtures do not invent transmission bodies.")

func _cog_axle_collision() -> void:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for axis in range(3):
		var authority := PhysicalProjection.new()
		authority.state = {"options": {"native": true, "physical": true}, "actors": {}, "entities": {}, "foundations": {},
			"transmission_parts": {"cog": {"kind": "gear", "center": [0, 8, 0], "axis": axis, "teeth": 2}}, "belt_spans": {}}
		var physical := ActorWorld.new()
		root.add_child(physical)
		verify(physical.configure(authority).accepted, "A cog projection initializes native collision.")
		await physics_frame
		await physics_frame
		var cog: StaticBody3D = physical.mechanical_bodies.cog
		verify(physical._geometry_registered() and PhysicsServer3D.body_get_shape_count(cog.get_rid()) == 2, "Disc and axle are registered under one cog body.")
		var query := PhysicsShapeQueryParameters3D.new()
		var probe := SphereShape3D.new()
		probe.radius = 0.04
		query.shape = probe
		query.collision_mask = Geometry.MACHINE_LAYER
		query.transform.origin = cog.position + axes[axis] * 0.6
		var hits := physical.get_world_3d().direct_space_state.intersect_shape(query)
		verify(hits.any(func(hit: Dictionary): return hit.rid == cog.get_rid() and hit.shape == 1), "A native query hits the exposed cog axle.")
		var across := Vector3.RIGHT if axis == 1 else Vector3.UP
		query.transform.origin += across * 0.5
		hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
		verify(not hits.any(func(hit: Dictionary): return hit.rid == cog.get_rid()), "The space beside the axle remains empty.")
		var actor := PhysicalActor.new()
		actor.position = cog.position + axes[axis] * (1.55 if axis == 1 else 0.6)
		root.add_child(actor)
		await physics_frame
		await physics_frame
		physical.bodies["P"] = actor
		var contacts: Array = physical._initial_overlaps("P")
		physical.bodies.erase("P")
		verify(contacts.any(func(hit: Dictionary): return hit.get("rid") == cog.get_rid().get_id() and hit.get("shape") == 1 and hit.get("unsupported_overlap", false)), "Admission measures the actual axle hit and rejects penetration.")
		actor.queue_free()
		await process_frame
		var axle: BoxShape3D = cog.get_child(1).shape
		var size := axle.size
		axle.size *= 0.5
		verify(not physical._geometry_registered(), "Changing the axle shape fails the registration guard.")
		axle.size = size
		authority.state.transmission_parts.clear()
		verify(physical.sync_topology().accepted and not physical.mechanical_bodies.has("cog"), "Removing the cog removes both collision shapes.")
		authority.state.transmission_parts["cog"] = {"kind": "gear", "center": [0, 8, 0], "axis": axis, "teeth": 2}
		verify(physical.sync_topology().accepted, "Restoring the cog rebuilds its collision body.")
		await physics_frame
		await physics_frame
		verify(physical._geometry_registered(), "Both restored shapes pass the native registration guard.")
		physical.queue_free()
		await process_frame

func _river_pier_collision() -> void:
	for axis in [0, 2]:
		var supports: Array = []
		for side in [-1.0, 1.0]:
			supports.append({"center": [side * 0.5 if axis == 0 else 0.0, 0.6375,
				side * 0.5 if axis == 2 else 0.0],
				"half": [0.18 if axis == 0 else 0.43, 1.7875, 0.18 if axis == 2 else 0.43]})
		var authority := PhysicalProjection.new()
		authority.state = {"options": {"native": true, "physical": true}, "actors": {},
			"entities": {"wheel": {"kind": "wheel", "cell": [0, 0], "level": 4,
				"axis": axis, "tiles": 3, "supports": supports}},
			"foundations": {}, "transmission_parts": {}, "belt_spans": {}}
		var physical := ActorWorld.new()
		root.add_child(physical)
		verify(physical.configure(authority).accepted, "A wheel projection registers its two fixed support shapes.")
		await physics_frame
		await physics_frame
		var wheel: StaticBody3D = physical.machines.wheel
		authority.projection_calls = 0
		verify(physical._geometry_registered() and authority.projection_calls == 1
			and PhysicsServer3D.body_get_shape_count(wheel.get_rid()) == 3,
			"The native body and river piers match one current World projection.")
		var query := PhysicsShapeQueryParameters3D.new()
		var probe := SphereShape3D.new()
		probe.radius = 0.04
		query.shape = probe
		query.collision_mask = Geometry.MACHINE_LAYER
		query.transform.origin = Vector3(0.5, 1.2, 0.0) if axis == 0 else Vector3(0.0, 1.2, 0.5)
		var hits := physical.get_world_3d().direct_space_state.intersect_shape(query)
		verify(hits.any(func(hit: Dictionary): return hit.rid == wheel.get_rid() and hit.shape == 2),
			"A support-only probe hits the pier body, beyond the rotating wheel envelope.")
		var support_shape: BoxShape3D = wheel.get_child(2).shape
		var original_size := support_shape.size
		support_shape.size *= 0.5
		verify(not physical._geometry_registered(), "Changing the projected support collider fails registration.")
		support_shape.size = original_size
		authority.state.entities.clear()
		verify(physical.sync_topology().accepted and physical.machines.is_empty(),
			"Removing the wheel removes both support colliders.")
		authority.state.entities.wheel = {"kind": "wheel", "cell": [0, 0], "level": 4,
			"axis": axis, "tiles": 3, "supports": supports}
		verify(physical.sync_topology().accepted, "Rebuilding the wheel restores its confirmed support volumes.")
		await physics_frame
		await physics_frame
		verify(physical._geometry_registered(), "The restored wheel and support shapes match the projection.")
		physical.queue_free()
		await process_frame

func _collision_body_lifecycle() -> void:
	var authority := PhysicalProjection.new()
	authority.state = {"options": {"native": true, "physical": true}, "actors": {}, "entities": {}, "foundations": {},
		"transmission_parts": {
			"left": {"kind": "shaft", "center": [0, 8, 0], "axis": 2, "half_span": 2},
			"right": {"kind": "shaft", "center": [8, 8, 0], "axis": 2, "half_span": 2},
			"cog": {"kind": "gear", "center": [0, 8, 4], "axis": 2, "teeth": 2}},
		"belt_spans": {"belt": {"from": "left", "to": "right"}}}
	var physical := ActorWorld.new()
	root.add_child(physical)
	verify(physical.configure(authority).accepted, "A synthetic projection initializes the physical geometry.")
	await physics_frame
	await physics_frame
	verify(physical._geometry_registered() and physical.mechanical_bodies.size() == 4, "Confirmed parts and span have registered native bodies.")
	var tile_center_y := 2.5 * Geometry.PITCH
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := SphereShape3D.new()
	probe.radius = 0.05
	query.shape = probe
	query.collision_mask = Geometry.MACHINE_LAYER
	query.transform.origin = Vector3(1.65, tile_center_y, 0)
	var hits := physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(hits.any(func(hit: Dictionary): return hit.rid == physical.mechanical_bodies.belt.get_rid()), "The native physics query intersects the belt body.")
	var capsule := CapsuleShape3D.new()
	capsule.radius = Geometry.CAPSULE_RADIUS
	capsule.height = Geometry.CAPSULE_HEIGHT
	query.shape = capsule
	query.transform.origin = Vector3(1.65, tile_center_y + 0.55, 0)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(hits.any(func(hit: Dictionary): return hit.rid == physical.mechanical_bodies.belt.get_rid()), "The actual character-sized capsule detects the belt body.")
	query.transform.origin = Vector3(1.65, tile_center_y, -2.0)
	query.motion = Vector3(0, 0, 4.0)
	var sweep := physical.get_world_3d().direct_space_state.cast_motion(query)
	verify(sweep.size() == 2 and sweep[0] < 1.0, "A character-sized sweep is blocked by the belt.")
	query.motion = Vector3.ZERO
	query.shape = probe
	query.transform.origin = Vector3(0, tile_center_y, 0)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(hits.any(func(hit: Dictionary): return hit.rid == physical.mechanical_bodies.left.get_rid()), "The native physics query intersects the shaft body.")
	query.transform.origin = Vector3(0, tile_center_y, 1.65)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(hits.any(func(hit: Dictionary): return hit.rid == physical.mechanical_bodies.cog.get_rid()), "The native physics query intersects the cog body.")
	var belt: StaticBody3D = physical.mechanical_bodies.belt
	var actor := PhysicalActor.new()
	actor.position = Vector3(1.65, tile_center_y, 0)
	root.add_child(actor)
	await physics_frame
	await physics_frame
	physical.bodies["P"] = actor
	var penetrating: Dictionary = physical._penetration("P", belt.get_rid())
	var occupied_contacts: Array = physical._initial_overlaps("P")
	physical.bodies.erase("P")
	verify(penetrating.get("unsupported_overlap", false), "The actor overlap guard rejects a capsule inside the belt.")
	verify(occupied_contacts.any(func(hit: Dictionary): return hit.get("rid") == belt.get_rid().get_id() and hit.get("unsupported_overlap", false)), "The admission and checkpoint query detects the actual belt penetration.")
	actor.position = Vector3(1.65, tile_center_y + 0.15 + Geometry.CAPSULE_HEIGHT / 2.0, 0)
	await physics_frame
	await physics_frame
	physical.bodies["P"] = actor
	var resting: Dictionary = physical._penetration("P", belt.get_rid())
	var resting_contacts: Array = physical._initial_overlaps("P")
	physical.bodies.erase("P")
	verify(not resting.get("unsupported_overlap", true), "The actor overlap guard accepts contact at the belt surface.")
	verify(not resting_contacts.any(func(hit: Dictionary): return hit.get("unsupported_overlap", true)), "The admission and checkpoint query accepts the supported surface contact.")
	actor.queue_free()
	await process_frame
	var belt_shape: BoxShape3D = belt.get_child(0).shape
	var original := belt_shape.size
	belt_shape.size = Vector3(0.1, 0.1, 0.1)
	verify(not physical._geometry_registered(), "A changed native collision shape fails the registration guard.")
	belt_shape.size = original
	belt.position.x += 1.0
	verify(not physical._geometry_registered(), "A displaced collision body fails the registration guard.")
	belt.position.x -= 1.0
	authority.state.belt_spans.clear()
	authority.state.transmission_parts.erase("right")
	verify(physical.sync_topology().accepted, "The removed span and shaft synchronize.")
	await physics_frame
	await physics_frame
	verify(physical._geometry_registered() and not physical.mechanical_bodies.has("belt") and not physical.mechanical_bodies.has("right"), "Removed bodies leave the native world without damaging remaining registrations.")
	query.transform.origin = Vector3(1.65, tile_center_y, 0)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(hits.is_empty(), "The removed belt no longer blocks its former center.")
	query.shape = capsule
	query.transform.origin = Vector3(1.65, tile_center_y, -2.0)
	query.motion = Vector3(0, 0, 4.0)
	sweep = physical.get_world_3d().direct_space_state.cast_motion(query)
	verify(sweep.size() == 2 and sweep[0] == 1.0, "The same character-sized sweep is clear after belt removal.")
	query.shape = probe
	query.motion = Vector3.ZERO
	query.transform.origin = Vector3(1.65, tile_center_y, 0)
	authority.state.transmission_parts["right"] = {"kind": "shaft", "center": [8, 8, 0], "axis": 2, "half_span": 2}
	authority.state.belt_spans["belt"] = {"from": "left", "to": "right"}
	verify(physical.sync_topology().accepted, "A restored projection rebuilds its span and shaft bodies.")
	await physics_frame
	await physics_frame
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(physical._geometry_registered() and hits.any(func(hit: Dictionary): return hit.rid == physical.mechanical_bodies.belt.get_rid()), "Restored bodies register and block the belt center again.")
	authority.state.transmission_parts.right.center = [8, 16, 0]
	verify(physical.sync_topology().accepted, "An inclined projection synchronizes rotated collision geometry.")
	await physics_frame
	await physics_frame
	var incline: StaticBody3D = physical.mechanical_bodies.belt
	query.transform.origin = Vector3(1.65, tile_center_y + Geometry.PITCH, 0)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(physical._geometry_registered() and hits.any(func(hit: Dictionary): return hit.rid == incline.get_rid()), "The registered inclined body blocks its actual midpoint.")
	query.transform.origin = Vector3(1.65, tile_center_y, 0)
	hits = physical.get_world_3d().direct_space_state.intersect_shape(query)
	verify(not hits.any(func(hit: Dictionary): return hit.rid == incline.get_rid()), "The inclined body does not fill the empty space below its midpoint.")
	var slope_actor := PhysicalActor.new()
	var normal := incline.basis.y
	slope_actor.position = incline.position + normal * (0.15 + Geometry.CAPSULE_RADIUS) + Vector3.UP * (Geometry.CAPSULE_HEIGHT / 2.0 - Geometry.CAPSULE_RADIUS)
	root.add_child(slope_actor)
	await physics_frame
	physical.bodies["slope"] = slope_actor
	verify(not physical._penetration("slope", incline.get_rid()).get("unsupported_overlap", true), "An upright capsule may rest against the inclined surface.")
	physical.bodies.erase("slope")
	slope_actor.position -= normal * 0.1
	await physics_frame
	await physics_frame
	physical.bodies["slope"] = slope_actor
	verify(physical._penetration("slope", incline.get_rid()).get("unsupported_overlap", false), "The inclined overlap guard rejects penetration.")
	physical.bodies.erase("slope")
	slope_actor.queue_free()
	incline.basis = Basis.IDENTITY
	verify(not physical._geometry_registered(), "A changed inclined body orientation fails the registration guard.")
	physical.queue_free()
	await process_frame

func _belt_actor_transport() -> void:
	var authority := PhysicalProjection.new()
	authority.state = {"options": {"native": true, "physical": true}, "entities": {}, "foundations": {},
		"actors": {"P": {"position": [0.0, 5.175, 0.0], "ready": false, "native_epoch": 0}},
		"transmission_parts": {
			"left": {"kind": "shaft", "center": [0, 8, 0], "axis": 2, "half_span": 2},
			"right": {"kind": "shaft", "center": [8, 8, 0], "axis": 2, "half_span": 2}},
		"belt_spans": {"belt": {"from": "left", "to": "right"}},
		"motion": {"left": {"state": "rotating", "numerator": -1, "denominator": 4}}}
	var physical := ActorWorld.new()
	physical.set_belt_step_seconds(0.45)
	physical.pose_published.connect(authority.observe)
	root.add_child(physical)
	verify(physical.configure(authority).accepted and physical.ensure_actor("P").accepted, "The synthetic character starts on a confirmed belt.")
	var belt_id: int = physical.mechanical_bodies.belt.get_instance_id()
	var sample: Dictionary = authority.projection()
	var expected_speed := Geometry.PITCH / (4.0 * 0.45)
	verify(physical._belt_surface_velocity(sample, belt_id).is_equal_approx(Vector2(expected_speed, 0)), "The X travel rate matches the native quarter-tile per simulation step.")
	sample.motion.left.denominator = 3
	var third_speed := Geometry.PITCH / (3.0 * 0.45)
	verify(physical._belt_surface_velocity(sample, belt_id).is_equal_approx(Vector2(third_speed, 0)), "Actor carry follows a third-speed shaft without rounding away each fractional subtick.")
	sample.motion.left.denominator = 8192
	var tiny_speed := physical._belt_surface_velocity(sample, belt_id).x
	verify(tiny_speed > 0.0 and absf(tiny_speed / (Geometry.PITCH / (8192.0 * 0.45)) - 1.0) < 0.0001, "A very slow belt has no artificial one-subtick minimum speed.")
	sample.motion.left.numerator = 20
	sample.motion.left.denominator = 1
	verify(physical._belt_surface_velocity(sample, belt_id).is_equal_approx(Vector2(-20.0 * Geometry.PITCH / 0.45, 0)), "Reversed actor carry follows the full high-speed shaft rate.")
	sample.motion.left.numerator = -1
	sample.motion.left.denominator = 4
	sample.transmission_parts.right.center = [8, 16, 0]
	var slope_speed := floorf(1024.0 * 2896.0 / 4096.0) / 4096.0 * Geometry.PITCH / 0.45
	verify(physical._belt_surface_velocity(sample, belt_id).is_equal_approx(Vector2(slope_speed, 0)), "Inclined actor carry uses the same fixed-point horizontal progress as cargo.")
	sample.motion.left.denominator = 3
	verify(physical._belt_surface_velocity(sample, belt_id).is_equal_approx(Vector2(third_speed * 2896.0 / 4096.0, 0)), "Inclined fractional carry follows the accumulated native distance.")
	sample.motion.left.numerator = -20
	sample.motion.left.denominator = 1
	verify(physical._belt_surface_velocity(sample, belt_id).is_equal_approx(Vector2(20.0 * Geometry.PITCH / 0.45 * 2896.0 / 4096.0, 0)), "Inclined carry follows the full native lane rate.")
	sample.motion.left.numerator = -1
	sample.motion.left.denominator = 4
	sample.transmission_parts.right.center = [8, 8, 0]
	sample.transmission_parts.left.axis = 0
	sample.motion.left.numerator = 1
	verify(physical._belt_surface_velocity(sample, belt_id).is_equal_approx(Vector2(0, expected_speed)), "The other horizontal shaft axis transports along Z with the correct sign.")
	sample.transmission_parts.right.center = [0, 16, 0]
	verify(physical._belt_surface_velocity(sample, belt_id) == Vector2.ZERO, "A vertical power-only belt does not carry actors.")
	verify(physical._belt_surface_velocity(sample, 0) == Vector2.ZERO, "A character without belt floor contact receives no transport.")
	for frame in 40:
		await physics_frame
	verify(not physical.failures.has("P") and physical.bodies.P.motion_enabled, "The native actor registers without penetrating the belt.")
	var forward: float = physical.bodies.P.position.x
	verify(forward > 0.15 and absf(physical.bodies.P.position.z) < 0.05, "A powered belt carries the uncommanded actor in the cargo direction.")
	var supported_cut: Dictionary = physical.checkpoint_status()
	verify(supported_cut.accepted and supported_cut.reason == "native_checkpoint_ready", "A capsule supported by the belt can pass checkpoint admission.")
	var body: CharacterBody3D = physical.bodies.P
	var original_pose := body.global_transform
	body.set_physics_process(false)
	var embedded_pose := original_pose
	embedded_pose.origin = Vector3(1.65, 3.8, 0.0)
	body.global_transform = embedded_pose
	await physics_frame
	await physics_frame
	var blocked_cut: Dictionary = physical.checkpoint_status()
	verify(not blocked_cut.accepted and blocked_cut.reason == "actor_pose_not_settled", "Checkpoint admission rejects a capsule embedded in the belt.")
	verify(body.global_transform == embedded_pose and PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) == embedded_pose, "The rejected checkpoint does not move the capsule.")
	body.global_transform = original_pose
	await physics_frame
	await physics_frame
	verify(physical.checkpoint_status().accepted, "Checkpoint admission succeeds again after restoring the supported pose.")
	body.set_physics_process(true)
	authority.state.motion.left.state = "stopped"
	for frame in 10:
		await physics_frame
	var stopped: float = physical.bodies.P.position.x
	verify(absf(stopped - forward) < 0.05, "Stopping the shaft stops belt transport.")
	authority.state.motion.left.state = "rotating"
	authority.state.motion.left.numerator = 1
	for frame in 25:
		await physics_frame
	var reversed: float = physical.bodies.P.position.x
	verify(reversed < stopped - 0.15, "Reversing the shaft reverses actor transport.")
	physical.set_belt_step_seconds(0.0)
	for frame in 10:
		await physics_frame
	verify(absf(physical.bodies.P.position.x - reversed) < 0.05, "A frozen simulation clock stops belt transport.")
	physical.bodies.P.set_control(Vector2(1, 0), false)
	for frame in 6:
		await physics_frame
	verify(physical.bodies.P.position.x > reversed + 0.1, "Synthetic walking control still moves the character on the belt.")
	physical.bodies.P.release_control()
	var before_jump: float = physical.bodies.P.position.y
	physical.bodies.P.set_control(Vector2.ZERO, true)
	for frame in 8:
		await physics_frame
	verify(physical.bodies.P.position.y > before_jump + 0.1, "Synthetic jump control still lifts the character off the belt.")
	physical.queue_free()
	await process_frame
	# Exercise the actual host setup with no actors or network/game startup.
	authority.state.actors = {}
	var host_root := Node.new()
	host_root.name = "OpeningShared"
	root.add_child(host_root)
	for step in [0.45, 0.0]:
		var host := Session.new()
		host.name = "Session"
		host._authoritative = true
		host.world = authority
		host._tick_seconds = step
		host_root.add_child(host)
		host.set_process(false)
		verify(host.start_physical_world() == OK and host.actor_world.belt_step_seconds == step, "The host passes its simulation clock to the physical world.")
		host.queue_free()
		await process_frame
	host_root.queue_free()

func _inclined_belt_actor() -> void:
	for axle in [0, 2]:
		for slope in [-1, 1]:
			var authority := PhysicalProjection.new()
			var first_y := 8 if slope > 0 else 16
			var last_y := 16 if slope > 0 else 8
			var end := [8 if axle == 2 else 0, last_y, 8 if axle == 0 else 0]
			var actor_position := [1.65 if axle == 2 else 0.0, 7.605, 1.65 if axle == 0 else 0.0]
			authority.state = {"options": {"native": true, "physical": true}, "entities": {}, "foundations": {},
				"actors": {"P": {"position": actor_position, "ready": false, "native_epoch": 0}},
				"transmission_parts": {"left": {"kind": "shaft", "center": [0, first_y, 0], "axis": axle, "half_span": 2},
					"right": {"kind": "shaft", "center": end, "axis": axle, "half_span": 2}},
				"belt_spans": {"belt": {"from": "left", "to": "right"}},
				"motion": {"left": {"state": "stopped", "numerator": 0, "denominator": 1}}}
			var physical := ActorWorld.new()
			physical.set_belt_step_seconds(0.45)
			physical.pose_published.connect(authority.observe)
			root.add_child(physical)
			verify(physical.configure(authority).accepted and physical.ensure_actor("P").accepted, "The inclined fixture creates its physical actor.")
			for frame in 55:
				await physics_frame
			var body = physical.bodies.P
			verify(not physical.failures.has("P") and body.motion_enabled and body.is_on_floor() and body.floor_id == physical.mechanical_bodies.belt.get_instance_id(), "An actor registers stable floor contact on an inclined belt.")
			var start: Vector3 = body.position
			authority.state.motion.left.state = "rotating"
			authority.state.motion.left.numerator = 1 if axle == 0 else -1
			authority.state.motion.left.denominator = 4
			for frame in 35:
				await physics_frame
			var forward: Vector3 = body.position
			verify(physical.checkpoint_status().accepted, "A moving actor on an inclined belt remains checkpoint-safe.")
			var travel := forward.z - start.z if axle == 0 else forward.x - start.x
			var speed := floorf(1024.0 * 2896.0 / 4096.0) / 4096.0 * Geometry.PITCH / 0.45
			var expected_forward := speed * 34.0 / float(Engine.physics_ticks_per_second)
			verify(absf(travel - expected_forward) < 0.04 and (forward.y - start.y) * slope > 0.1, "Inclined carry matches the confirmed belt speed in either slope direction.")
			authority.state.motion.left.numerator *= -1
			for frame in 50:
				await physics_frame
			var reverse: Vector3 = body.position
			var reverse_travel := reverse.z - forward.z if axle == 0 else reverse.x - forward.x
			var expected_reverse := speed * 49.0 / float(Engine.physics_ticks_per_second)
			verify(absf(reverse_travel + expected_reverse) < 0.04, "Reversing the shaft reverses inclined actor transport at the same speed.")
			authority.state.motion.left.state = "stopped"
			for frame in 12:
				await physics_frame
			var stopped: Vector3 = body.position
			verify(absf(stopped.z - reverse.z if axle == 0 else stopped.x - reverse.x) < 0.05, "A stopped inclined belt holds the actor.")
			authority.state.motion.left.state = "rotating"
			physical.set_belt_step_seconds(0.0)
			for frame in 12:
				await physics_frame
			var frozen: Vector3 = body.position
			verify(absf(frozen.z - stopped.z if axle == 0 else frozen.x - stopped.x) < 0.05, "A frozen clock stops inclined actor transport.")
			physical.set_belt_step_seconds(0.45)
			var before_jump: float = body.position.y
			body.set_control(Vector2.ZERO, true)
			for frame in 8:
				await physics_frame
			verify(body.position.y > before_jump + 0.1, "The actor can jump from the moving inclined belt.")
			physical.queue_free()
			await process_frame

func _stable_finishes() -> void:
	var host := HostStub.new()
	host.state = fixture()
	for id in ["a", "sx"]:
		host.state.motion[id] = {"state": "unpowered", "numerator": 0, "denominator": 1}
	var view := Presenter.new()
	view.configure(host)
	var gear: MeshInstance3D = _part(view, "a").get_node("Gear")
	var shaft: MeshInstance3D = _part(view, "sx").get_node("Shaft")
	var gear_finish: Material = gear.material_override
	var shaft_finish: Material = shaft.material_override
	var gear_mesh: Mesh = gear.mesh
	var shaft_mesh: Mesh = shaft.mesh
	for motion in [{"state": "rotating", "numerator": 2, "denominator": 3},
			{"state": "rotating", "numerator": -2, "denominator": 3},
			{"state": "stalled", "numerator": 0, "denominator": 1},
			{"state": "unknown", "numerator": 0, "denominator": 1}]:
		for id in ["a", "sx"]:
			host.state.motion[id] = motion.duplicate(true)
		var before: Dictionary = host.state.duplicate(true)
		view.refresh()
		gear = _part(view, "a").get_node("Gear")
		shaft = _part(view, "sx").get_node("Shaft")
		verify(gear.material_override == gear_finish and shaft.material_override == shaft_finish,
			"Confirmed motion changes do not replace the physical gear or shaft finish.")
		verify(gear.mesh == gear_mesh and shaft.mesh == shaft_mesh,
			"Changing motion preserves the fitted cached meshes.")
		var mark := _part(view, "a").get_node_or_null("ConfirmedDirection")
		verify((mark != null and mark.get_meta("sign") == (1 if motion.numerator > 0 else -1))
			if motion.state == "rotating" else mark == null,
			"Confirmed signed direction stays readable without recoloring the part.")
		verify(host.state == before and host.calls.is_empty(),
			"Finish presentation never changes native facts or sends a request.")
	view.free()

func _fixed_support_frame() -> void:
	var support := {"foot": [0.4, 1.65, -1.1], "bearing": [0.0, 4.125, -1.1], "boxes": [
		{"center": [0.4, 2.7675, -1.1], "half": [0.17, 1.1175, 0.17]},
		{"center": [0.0, 4.125, -1.1], "half": [0.185, 0.185, 0.1525]},
		{"center": [0.0, 3.925, -1.1], "half": [0.155, 0.04, 0.155]},
		{"center": [0.2, 3.885, -1.1], "half": [0.2475, 0.0475, 0.0475]}]}
	var part := {"kind": "gear", "center": [0, 8, -4], "axis": 2, "teeth": 2, "half_span": 0,
		"generation": 1, "support": support}
	var model := PhysicalProjection.new()
	model.state = {"options": {"native": true, "physical": true}, "actors": {}, "entities": {},
		"foundations": {"deck": {"cell": [0, -1], "level": 4, "generation": 1}},
		"transmission_parts": {"upper": part}, "belt_spans": {}}
	var before: Dictionary = model.state.duplicate(true)
	var physical := ActorWorld.new()
	root.add_child(physical)
	verify(physical.configure(model).accepted, "The physical adapter accepts the emitted support-box contract.")
	await physics_frame
	await physics_frame
	var body: StaticBody3D = physical.mechanical_bodies.upper
	var complete := PhysicsServer3D.body_get_shape_count(body.get_rid()) == 6
	verify(complete and physical._geometry_registered(),
		"The cog disc, axle and four fixed support boxes share one registered native body.")
	if not complete:
		physical.free()
		await process_frame
		return
	var query := PhysicsRayQueryParameters3D.create(Vector3(0.9, 3.0, -1.1), Vector3(0, 3.0, -1.1), Geometry.MACHINE_LAYER)
	var hit: Dictionary = physical.get_world_3d().direct_space_state.intersect_ray(query)
	verify(hit.get("collider") == body and int(hit.get("shape", -1)) >= 2,
		"A native query hits the relocated post where the rotating gear itself is absent.")
	query.from = Vector3(0.9, 3.0, -1.75)
	query.to = Vector3(0.0, 3.0, -1.75)
	verify(physical.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),
		"The support does not fill the empty space behind its narrow column.")
	var probe := CharacterBody3D.new()
	probe.collision_layer = Geometry.ACTOR_LAYER
	probe.collision_mask = Geometry.MACHINE_LAYER
	var capsule := CapsuleShape3D.new()
	capsule.radius = Geometry.CAPSULE_RADIUS
	capsule.height = Geometry.CAPSULE_HEIGHT
	var probe_shape := CollisionShape3D.new()
	probe_shape.shape = capsule
	probe.add_child(probe_shape)
	probe.position = Vector3(0.4, 3.0, -1.1)
	root.add_child(probe)
	await physics_frame
	physical.bodies["probe"] = probe
	verify(physical._penetration("probe", body.get_rid(), 2).get("unsupported_overlap", false),
		"The capsule admission measure uses the translated support shape's real location.")
	physical.bodies.erase("probe")
	probe.position = Vector3(0.0, 4.125, -1.65)
	await physics_frame
	physical.bodies["probe"] = probe
	verify(not physical._penetration("probe", body.get_rid(), 2).get("geometric_overlap", true),
		"The support query does not invent a column at the cog body's origin.")
	physical.bodies.erase("probe")
	probe.free()
	var support_shape := body.get_child(2) as CollisionShape3D
	var original_position := support_shape.position
	support_shape.position.x += 0.1
	verify(not physical._geometry_registered(), "A moved post collider fails native geometry registration.")
	support_shape.position = original_position
	var original_shape := support_shape.shape as BoxShape3D
	var original_size := original_shape.size
	original_shape.size *= 0.5
	verify(not physical._geometry_registered(), "A resized post collider fails native geometry registration.")
	original_shape.size = original_size
	verify(physical._geometry_registered(), "Restoring the exact support pose and size restores registration.")
	var presenter := Presenter.new()
	root.add_child(presenter)
	var frame := presenter._confirmed_support("upper", part)
	var joined := false
	for child in frame.get_children():
		if child is MeshInstance3D and (child.transform * child.mesh.get_aabb()).has_point(Vector3(0.2, 3.885, -1.1)):
			joined = true
	verify(joined, "Solid presentation geometry joins the lateral post to the coaxial bearing.")
	verify(model.state == before, "Support realization and queries leave the confirmed projection unchanged.")
	model.state.transmission_parts.clear()
	verify(physical.sync_topology().accepted and physical.mechanical_bodies.is_empty(),
		"Removing the cog also removes its fixed support body.")
	presenter.free()
	physical.free()
	await process_frame
	await physics_frame

func _physical_topology_cache_regression() -> void:
	var model := TopologyStub.new()
	model.state = {"context": "invented-geometry", "order": 0, "revision": 0,
		"options": {"native": true, "physical": true}, "actors": {}, "entities": {},
		"transmission_parts": {"cog-a": {"kind": "gear", "center": [0, 4, 0], "axis": 1, "teeth": 2}},
		"belt_spans": {}, "placed_components": {}, "foundations": {}}
	var physical := ActorWorld.new()
	physical.model = model
	root.add_child(physical)
	verify(physical.mechanical_bodies.has("cog-a"), "Startup registers the first cog collider.")
	var before_calls := model.calls
	physical._on_native_cut()
	verify(model.calls == before_calls + 1, "An unchanged native cut projects once without rederiving topology.")
	verify(physical.mechanical_bodies.has("cog-a"), "An unchanged cut keeps its collider.")
	model.state.transmission_parts.erase("cog-a")
	model.state.transmission_parts["cog-b"] = {"kind": "gear", "center": [4, 4, 0], "axis": 1, "teeth": 2}
	model.state.order += 1
	physical._on_native_cut()
	verify(not physical.mechanical_bodies.has("cog-a") and physical.mechanical_bodies.has("cog-b"),
		"A new command order replaces removed geometry before the actor cut.")
	var old_position: Vector3 = physical.mechanical_bodies["cog-b"].position
	model.state.transmission_parts["cog-b"].center = [8, 4, 0]
	verify(physical.sync_topology().accepted and physical.mechanical_bodies["cog-b"].position != old_position,
		"An explicit restore or checkpoint sync rebuilds geometry even at the same order.")
	model.state.transmission_parts["cog-b"].axis = 9
	model.state.order += 1
	verify(not physical.sync_topology().accepted, "An invalid changed topology is rejected.")
	model.state.transmission_parts["cog-b"].axis = 1
	var before_recovery := model.calls
	physical._on_native_cut()
	verify(model.calls >= before_recovery + 1 and physical.mechanical_bodies.has("cog-b"),
		"A failed sync does not poison recovery at the same order.")
	model.state.options.native = false
	physical._on_native_cut()
	verify(physical.mechanical_bodies.is_empty(), "A non-native profile does not reuse native colliders.")
	physical.free()

func _physical_actor_bridge_regression() -> void:
	var bridge := ActorBridgeStub.new()
	var physical := ActorWorld.new()
	physical.model = bridge
	var sample := {"position": [1.0, 2.0, 3.0], "native_epoch": 7}
	verify(physical._bridge_current("P", sample) and bridge.narrow_calls == 1 and bridge.full_calls == 0,
		"The native bridge verifies the published pose without a full worksite projection.")
	bridge.actor.ready = false
	verify(not physical._bridge_current("P", sample), "An invalidated actor cannot bridge as ready.")
	bridge.actor.ready = true
	bridge.actor.native_epoch = 6
	verify(not physical._bridge_current("P", sample), "A stale actor publication cannot bridge.")
	bridge.actor.native_epoch = 7
	bridge.actor.position = [1.0, 2.0, 4.0]
	verify(not physical._bridge_current("P", sample), "A different accepted position cannot bridge.")
	bridge.actor.position = sample.position
	bridge.actor.accepted = false
	verify(not physical._bridge_current("P", sample), "A refused native view cannot bridge.")
	var legacy := TopologyStub.new()
	legacy.state = {"actors": {"P": {"ready": true, "native_epoch": 7, "position": sample.position}}}
	physical.model = legacy
	verify(physical._bridge_current("P", sample) and legacy.calls == 1,
		"A non-native model retains full projection validation.")
	physical.free()

func _advance_projection_regression() -> void:
	var view := AdvanceProjectionOpening.new()
	var source := AdvanceProjectionStub.new()
	view.model = source
	view.auto_advance = true
	view._process(0.0)
	verify(source.advances == 0 and source.projections == 1 and view.state.revision == 0,
		"A render cut without an authority tick still requests the current projection.")
	source.advances = 0
	source.projections = 0
	view.elapsed = 0.0
	view._process(view.STEP_SECONDS + 0.01)
	verify(source.advances == 1 and source.projections == 0 and view.state.revision == 1,
		"One accepted tick supplies its own complete render projection.")
	source.advances = 0
	source.projections = 0
	view.elapsed = 0.0
	view._process(view.STEP_SECONDS * 3.0 + 0.01)
	verify(source.advances == 3 and source.projections == 0 and view.state.revision == 4,
		"A catch-up render cut uses the last of several accepted tick projections.")
	source.advances = 0
	source.projections = 0
	source.refuse_next = true
	view.elapsed = 0.0
	view._process(view.STEP_SECONDS + 0.01)
	verify(source.advances == 1 and source.projections == 1 and view.state.revision == 4,
		"A refused native tick falls back to a fresh authority projection.")
	view.free()

func _native_actor_view_regression() -> void:
	var model = NativeModel.new("actor-view-fixture", ["P"], true)
	verify(model.boot_result.get("accepted", false), "The real native arrival model boots for actor-view checks.")
	if not model.boot_result.get("accepted", false):
		return
	var unready: Dictionary = model.actor_projection("P")
	verify(unready.get("accepted", false) and not unready.get("ready", true) and unready.get("native_epoch", -1) == 0,
		"The extension exposes an unready physical actor without full worksite projection.")
	verify(model.publish_actor("P", [0.0, 1.0, 0.0], 1).get("accepted", false),
		"The real native Host accepts the first trusted physical sample.")
	var ready: Dictionary = model.actor_projection("P")
	verify(ready.get("accepted", false) and ready.get("ready", false) and ready.get("native_epoch", -1) == 1
		and ready.get("position", []) == [0.0, 1.0, 0.0],
		"The extension returns exactly the accepted pose and ordinal.")
	model.invalidate_actor("P")
	verify(not model.actor_projection("P").get("ready", true),
		"The extension reports explicit physical invalidation.")

func _native_view_cache_regression() -> void:
	var model := CountingNativeModel.new("view-cache-fixture", ["P"], true)
	verify(model.boot_result.get("accepted", false), "The native view-cache fixture boots the real extension.")
	if not model.boot_result.get("accepted", false):
		return
	model.full_projection_calls = 0
	var first: Dictionary = model.view_projection()
	var repeated: Dictionary = model.view_projection()
	verify(model.full_projection_calls == 1 and first == repeated and first.actors.P.ready == false,
		"Repeated view reads share one complete native observation before any tick.")
	var first_full_calls := model.full_projection_calls
	var opening_view := AdvanceProjectionOpening.new()
	opening_view.model = model
	opening_view._refresh()
	verify(model.full_projection_calls == 1 and opening_view.state == first,
		"The ordinary opening refresh reads the confirmed cached native projection.")
	opening_view.free()
	var physical := ActorWorld.new()
	physical.model = model
	root.add_child(physical)
	# ActorWorld startup reads terrain through a public projection and clears
	# the model cache. Refill it before measuring the ordinary physics cut.
	model.view_projection()
	model.full_projection_calls = 0
	physical._on_native_cut()
	verify(model.full_projection_calls == 0,
		"An ordinary physical cut does not reproject the full native worksite.")
	physical.free()
	model.full_projection_calls = first_full_calls
	repeated.entities["invented-machine"] = {}
	repeated.actors.P.ready = true
	var isolated: Dictionary = model.view_projection()
	verify(model.full_projection_calls == 1 and not isolated.entities.has("invented-machine")
		and not isolated.actors.P.ready, "A view caller cannot mutate the cached native facts.")
	var previous_scene_view: Dictionary = model._view_projection_borrowed()
	verify(model.publish_actor("P", [0.0, 1.0, 0.0], 1).get("accepted", false),
		"The real Host accepts a trusted physical pose for the cache check.")
	var moved: Dictionary = model.view_projection()
	verify(model.full_projection_calls == 1 and moved.actors.P.ready and moved.actors.P.native_epoch == 1
		and moved.actors.P.position == [0.0, 1.0, 0.0]
		and moved.actors.P == model.projection().actors.P,
		"Accepted pose publication patches only the view actor to exact Host facts.")
	verify(not previous_scene_view.actors.P.ready and moved.actors.P.ready,
		"Actor publication preserves an in-progress opening snapshot until its first-ready refresh.")
	model.full_projection_calls = 0
	var tick: Dictionary = model.advance()
	verify(tick.has("entities") and model.view_projection() == tick and model.full_projection_calls == 0,
		"A successful native tick supplies the complete next view without another projection.")
	var saved: Dictionary = model.checkpoint()
	var retained_scene_view: Dictionary = model._view_projection_borrowed()
	model.full_projection_calls = 0
	model.command_as("P", {"action": "invalid", "context": tick.context,
		"client": "P", "request": "cache-refusal"})
	var after_command: Dictionary = model.view_projection()
	verify(model.full_projection_calls == 1 and after_command == model.projection(),
		"Even a refused command invalidates the view before the next observation.")
	verify(retained_scene_view == tick and retained_scene_view.has("actors"),
		"Invalidation replaces the borrowed cache without clearing an in-progress scene view.")
	model.full_projection_calls = 0
	model.invalidate_actor("P")
	var invalidated: Dictionary = model.view_projection()
	verify(model.full_projection_calls == 1 and not invalidated.actors.P.ready
		and invalidated.actors.P == model.projection().actors.P,
		"Physical invalidation cannot leave a ready actor in the view cache.")
	verify(model.publish_actor("P", [0.0, 1.0, 0.0], 2).get("accepted", false),
		"A fresh trusted ordinal restores the invalidated actor before refusal coverage.")
	model.full_projection_calls = 0
	var rejected: Dictionary = model.publish_actor("P", [], 3)
	var after_rejection: Dictionary = model.view_projection()
	verify(not rejected.get("accepted", true) and model.full_projection_calls == 1
		and not after_rejection.actors.P.ready and after_rejection.actors.P == model.projection().actors.P,
		"A malformed rejected actor sample refreshes the view after Host revokes readiness.")
	var restored := CountingNativeModel.new("view-cache-fixture", ["P"], true)
	verify(restored.boot_result.get("accepted", false), "A fresh Host boots for saved-view restoration.")
	if not restored.boot_result.get("accepted", false):
		return
	restored.view_projection()
	restored.full_projection_calls = 0
	var restore_result: Dictionary = restored.restore_checkpoint(saved)
	var restored_view: Dictionary = restored.view_projection()
	verify(restore_result.get("accepted", false) and restored.full_projection_calls == 1
		and restored_view.revision == tick.revision and not restored_view.actors.P.ready
		and restored_view.actors.P == restored.projection().actors.P,
		"A restored Host discards the old view and requires a new physical actor publication.")
	var trusted := CountingNativeModel.new("trusted-tick-view-fixture", ["P"], true)
	verify(trusted.boot_result.get("accepted", false), "The trusted tick fixture boots one real native Host.")
	if not trusted.boot_result.get("accepted", false):
		return
	trusted.full_projection_calls = 0
	var trusted_opening := AdvanceProjectionOpening.new()
	trusted_opening.model = trusted
	trusted_opening.auto_advance = true
	trusted_opening._process(trusted_opening.STEP_SECONDS + 0.01)
	verify(trusted_opening.state.has("entities") and trusted.native_advance_calls == 1
		and trusted.full_projection_calls == 0
		and trusted_opening.state == trusted._view_projection_borrowed(),
		"The ordinary native opening consumes its accepted tick without another full read.")
	var external_view := trusted.view_projection()
	external_view.entities["invented-machine"] = {}
	external_view.actors.P.ready = true
	verify(not trusted._view_projection_borrowed().entities.has("invented-machine")
		and not trusted._view_projection_borrowed().actors.P.ready,
		"External view callers cannot edit a trusted opening tick.")
	var borrowed_tick: Dictionary = trusted._advance_borrowed()
	verify(trusted.native_delta_calls == 1 and trusted.native_advance_calls == 1
		and borrowed_tick == trusted.projection(),
		"A trusted no-change tick merges the native delta into the exact full view.")
	var public_tick := trusted.advance()
	public_tick.entities["invented-machine"] = {}
	verify(not trusted.view_projection().entities.has("invented-machine"),
		"Public advance remains isolated after a trusted opening tick.")
	var prior_trusted_view := trusted._view_projection_borrowed()
	verify(trusted.publish_actor("P", [0.0, 1.0, 0.0], 1).get("accepted", false)
		and trusted.view_projection().actors.P.ready
		and not prior_trusted_view.actors.P.ready,
		"Actor publication replaces the borrowed actor path without mutating a retained scene view.")
	trusted_opening.free()
	var complete: Dictionary = trusted.view_projection()
	var missing := complete.duplicate(true)
	missing.erase("stock")
	var wrong_type := complete.duplicate(true)
	wrong_type.cargo = []
	verify(trusted._complete_projection(complete) and not trusted._complete_projection(missing)
		and not trusted._complete_projection(wrong_type),
		"The native field contract rejects missing stock and a mistyped cargo view.")
	trusted._view_cache = {}
	trusted.inject_bad_full = true
	var bad_full: Dictionary = trusted.view_projection()
	verify(bad_full.get("uncertain", false) and trusted._view_cache.is_empty(),
		"A partial full projection never becomes a confirmed cached worksite.")
	verify(trusted.view_projection() == trusted.projection(),
		"A fresh native full projection recovers after the incomplete delivery.")
	trusted.view_projection()
	trusted.inject_bad_delta = true
	var bad_delta: Dictionary = trusted._advance_borrowed()
	verify(bad_delta.get("uncertain", false) and trusted._view_cache.is_empty(),
		"A mistyped material delta cannot publish a partial next worksite.")
	verify(trusted.view_projection() == trusted.projection(),
		"The next full native observation recovers after a rejected delta.")

func _run() -> void:
	if "--scale-benchmark" in OS.get_cmdline_user_args():
		await _scale_benchmark()
		return
	if "--supplied-hardware-only" in OS.get_cmdline_user_args():
		_supplied_hardware_view()
	elif "--component-boxes-only" in OS.get_cmdline_user_args():
		await _component_view()
	elif "--press-components-only" in OS.get_cmdline_user_args():
		await _press_component_view()
	elif "--guided-press-components-only" in OS.get_cmdline_user_args():
		await _guided_press_component_view()
	elif "--broad-press-components-only" in OS.get_cmdline_user_args():
		await _broad_press_component_view()
	elif "--broad-press-raised-only" in OS.get_cmdline_user_args():
		await _broad_press_component_view()
	elif "--channel-components-only" in OS.get_cmdline_user_args() \
			or "--channel-z-only" in OS.get_cmdline_user_args() \
			or "--channel-sheet-only" in OS.get_cmdline_user_args():
		await _channel_component_view()
	elif "--physical-topology-cache-only" in OS.get_cmdline_user_args():
		_physical_topology_cache_regression()
	elif "--physical-actor-bridge-only" in OS.get_cmdline_user_args():
		_physical_actor_bridge_regression()
	elif "--advance-projection-only" in OS.get_cmdline_user_args():
		_advance_projection_regression()
	elif "--native-actor-view-only" in OS.get_cmdline_user_args():
		_native_actor_view_regression()
	elif "--native-view-cache-only" in OS.get_cmdline_user_args():
		_native_view_cache_regression()
	elif "--support-frame-only" in OS.get_cmdline_user_args():
		await _fixed_support_frame()
	elif "--finish-only" in OS.get_cmdline_user_args():
		_stable_finishes()
	elif "--tool-guidance-only" in OS.get_cmdline_user_args():
		_tool_guidance()
	elif "--refresh-cache-only" in OS.get_cmdline_user_args():
		_cache_regression()
	elif "--belt-surface-only" in OS.get_cmdline_user_args():
		_belt_surface_motion()
		_belt_cargo_cadence()
	elif "--direction-basis-only" in OS.get_cmdline_user_args():
		_direction_basis()
	elif "--loose-material-only" in OS.get_cmdline_user_args():
		_loose_material()
		await _pointed_loose_material()
	elif "--slide-material-only" in OS.get_cmdline_user_args():
		await _slide_material_seat()
	elif "--mechanical-collision-only" in OS.get_cmdline_user_args():
		_mechanical_collision_geometry()
	elif "--collision-lifecycle-only" in OS.get_cmdline_user_args():
		await _collision_body_lifecycle()
	elif "--cog-axle-collision-only" in OS.get_cmdline_user_args():
		await _cog_axle_collision()
	elif "--river-pier-collision-only" in OS.get_cmdline_user_args():
		await _river_pier_collision()
	elif "--belt-actor-only" in OS.get_cmdline_user_args():
		await _belt_actor_transport()
	elif "--inclined-belt-actor-only" in OS.get_cmdline_user_args():
		await _inclined_belt_actor()
	elif "--nonhorizontal-presentation-only" in OS.get_cmdline_user_args():
		await _nonhorizontal_presentation()
	elif "--belt-picking-only" in OS.get_cmdline_user_args():
		await _belt_picking()
	elif "--cog-axles-only" in OS.get_cmdline_user_args():
		await _cog_axles()
	elif "--belt-spans-only" in OS.get_cmdline_user_args():
		await _belt_spans()
	elif "--belt-spans-missing-only" in OS.get_cmdline_user_args():
		await _belt_spans(true)
	else:
		_controls()
		_gear_sizes()
		_relays()
		_shaft_segments()
		await _belt_spans()
		_belt_retry()
		_span_guidance()
		_belt_surface_motion()
		_belt_cargo_cadence()
		_presentation()
		_stable_finishes()
	print("NATIVE_TRANSMISSION_VIEW_%s %d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _scale_benchmark() -> void:
	var count := 200
	var supports := false
	var varied_supports := false
	var capture := ""
	var close_view := false
	var large_every := 0
	var cycle_axes := false
	var verify_only := false
	var whole_opening := false
	var stopped := false
	var refresh_every_frame := false
	var trusted_revision := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--count="):
			count = int(argument.trim_prefix("--count="))
		elif argument == "--supports":
			supports = true
		elif argument == "--varied-supports":
			supports = true
			varied_supports = true
		elif argument.begins_with("--capture="):
			capture = argument.trim_prefix("--capture=")
		elif argument == "--close":
			close_view = true
		elif argument.begins_with("--large-every="):
			large_every = int(argument.trim_prefix("--large-every="))
		elif argument == "--cycle-axes":
			cycle_axes = true
		elif argument == "--verify-only":
			verify_only = true
		elif argument == "--whole-opening":
			whole_opening = true
		elif argument == "--stopped":
			stopped = true
		elif argument == "--refresh-every-frame":
			refresh_every_frame = true
		elif argument == "--trusted-revision":
			trusted_revision = true
	if count < 0 or count > 800:
		push_error("Choose 0 to 800 cogs.")
		quit(2)
		return
	var batch_minimum: int = Presenter.LIVE_GEAR_BATCH_THRESHOLD if trusted_revision else Presenter.GEAR_BATCH_THRESHOLD
	var scene := Node3D.new()
	var opening = null
	if whole_opening:
		opening = ScaleOpening.new()
		opening.auto_advance = false
		scene = opening
		root.add_child(scene)
		if trusted_revision:
			# Exercise the presenter's native revision fast path with a synthetic
			# projection; this does not boot or time the native World.
			opening.model = NativeModel.new()
		opening.focus = Vector3.ZERO
		opening.distance = 14.0 if close_view else 55.0
		opening.orbit_yaw = 0.0
		opening.orbit_pitch = 0.60
	else:
		root.add_child(scene)
		var camera := Camera3D.new()
		camera.position = Vector3(0, 8, 12) if close_view else Vector3(0, 30, 43)
		camera.fov = 65.0
		camera.current = true
		scene.add_child(camera)
		camera.look_at(Vector3.ZERO)
		var light := DirectionalLight3D.new()
		light.rotation = Vector3(-0.8, -0.5, 0)
		scene.add_child(light)
		if close_view:
			var environment := Environment.new()
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.ambient_light_color = Color.WHITE
			environment.ambient_light_energy = 0.8
			var world_environment := WorldEnvironment.new()
			world_environment.environment = environment
			scene.add_child(world_environment)
	var host := HostStub.new()
	if trusted_revision:
		host.model = NativeModel.new()
	host.state = opening.state.duplicate(true) if whole_opening else {"context": "synthetic-cog-scale",
		"revision": 1, "options": {"native": true},
		"entities": {}, "transmission_parts": {}, "motion": {}, "belt_spans": {}, "engagements": []}
	if whole_opening:
		host.state.options.native = true
		host.state.actors.P.ready = true
		host.state.transmission_parts = {}
		host.state.motion = {}
	var columns := ceili(sqrt(float(maxi(count, 1))))
	for index in count:
		var id := "cog-%d" % index
		var x := index % columns - columns / 2
		var z := floori(float(index) / float(columns)) - columns / 2
		host.state.transmission_parts[id] = {"kind": "gear", "generation": 1,
			"center": [x * 4, 4, z * 4], "axis": index % 3 if cycle_axes else 1,
			"teeth": 4 if large_every > 0 and index % large_every == 0 else 2}
		if supports:
			var at := Vector3(float(x) * 1.65, 0.0, float(z) * 1.65)
			if varied_supports:
				at.y = 0.06 * sin(float(index) * 0.37)
			host.state.transmission_parts[id].support = {"foot": [at.x, 0.24 + at.y, at.z],
				"bearing": [at.x, 0.7325, at.z]}
		host.state.motion[id] = {"state": "stalled" if stopped else "rotating",
			"numerator": 0 if stopped else (1 if index % 2 == 0 else -1),
			"denominator": 1}
	var presenter: Node3D
	var before := Time.get_ticks_usec()
	if whole_opening:
		opening.state = host.state
		opening._refresh_transmission()
		presenter = opening.transmission_presenter
	else:
		presenter = Presenter.new()
		scene.add_child(presenter)
		presenter.configure(host)
	if presenter == null:
		push_error("The opening did not initialize its native transmission presenter.")
		quit(1)
		return
	var build_ms := float(Time.get_ticks_usec() - before) / 1000.0
	var pick_count := 0
	var batched_count := 0
	var support_instances := 0
	var support_batches := 0
	var valid_geometry := true
	for child: Node in presenter.get_children():
		if child.has_meta("entity"):
			pick_count += int(child.has_node("Pick"))
		if child is MultiMeshInstance3D and child.get_meta("support_primitive", false):
			support_batches += 1
			support_instances += child.multimesh.instance_count
		if not child is MultiMeshInstance3D or not child.name.begins_with("CogBatch"):
			continue
		batched_count += child.multimesh.instance_count
		var mesh: Mesh = child.multimesh.mesh
		valid_geometry = valid_geometry and mesh.get_aabb().size.x > 1.4 and mesh.get_surface_count() >= 3
		for index in mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
			valid_geometry = valid_geometry and vertices.size() > 0 and vertices.size() % 3 == 0
			valid_geometry = valid_geometry and mesh.surface_get_material(index) != null
	if pick_count != count or (count >= batch_minimum and
			(batched_count != count or not valid_geometry)):
		push_error("The rendered cog geometry or individual picks failed scale validation.")
		quit(1)
		return
	if supports and count >= batch_minimum and (support_batches < 2 or support_instances < count * 8):
		push_error("The batched support primitives lost confirmed support geometry: %d batches, %d instances for %d supports." % [support_batches, support_instances, count])
		quit(1)
		return
	if verify_only:
		var unchanged: Dictionary = host.state.duplicate(true)
		var retained_anchor: Node3D = part_anchor(presenter, "cog-0") if trusted_revision and count >= batch_minimum else null
		var retained_pick: Node = retained_anchor.get_node("Pick") if retained_anchor != null else null
		presenter.advance_visual_motion(0.1)
		var matches := host.state == unchanged
		if not matches:
			print("COG_SCALE_MISMATCH host state changed")
		for group: Dictionary in presenter._gear_batches.values():
			for index in group.anchors.size():
				var anchor: Node3D = group.anchors[index]
				var id := str(anchor.get_meta("entity"))
				var angle: float = presenter.visual_angle(id)
				var expected := Transform3D(Presenter.axis_basis(int(anchor.get_meta("axis"))) *
					Basis(Vector3.UP, angle), anchor.position)
				var pose_match: bool = group.mesh.get_instance_transform(index).is_equal_approx(expected)
				var angle_match: bool = absf(angle) > 0.0 and anchor.basis.is_equal_approx(Presenter.axis_basis(int(anchor.get_meta("axis"))))
				if not pose_match or not angle_match:
					print("COG_SCALE_MISMATCH " + str([id, pose_match, angle_match,
						group.mesh.get_instance_transform(index), expected]))
				matches = matches and pose_match and angle_match
		if count >= batch_minimum and batched_count != count:
			matches = false
		if count > 0:
			var previous_key: Variant = presenter._view_key.duplicate(true)
			var original_motion: Dictionary = host.state.motion["cog-0"].duplicate(true)
			host.state.motion["cog-0"] = {"state": "stalled", "numerator": 0, "denominator": 1}
			if trusted_revision:
				host.state.revision += 1
			presenter.refresh()
			matches = matches and presenter._view_key != previous_key
			if count >= batch_minimum:
				var stopped_pose: Transform3D = presenter._gear_batches[4 if large_every > 0 else 2].mesh.get_instance_transform(0)
				presenter.advance_visual_motion(0.1)
				matches = matches and presenter._gear_batches[4 if large_every > 0 else 2].mesh.get_instance_transform(0).is_equal_approx(stopped_pose)
			host.state.motion["cog-0"] = original_motion
			if trusted_revision:
				host.state.revision += 1
			presenter.refresh()
		if retained_anchor != null:
			matches = matches and part_anchor(presenter, "cog-0") == retained_anchor \
				and retained_anchor.get_node("Pick") == retained_pick
			var extra: Dictionary = host.state.transmission_parts["cog-0"].duplicate(true)
			extra.center = [500, 4, 500]
			host.state.transmission_parts["cog-extra"] = extra
			host.state.motion["cog-extra"] = host.state.motion["cog-0"].duplicate(true)
			host.state.revision += 1
			presenter.refresh()
			var added_anchor: Node3D = part_anchor(presenter, "cog-extra")
			matches = matches and part_anchor(presenter, "cog-0") == retained_anchor \
				and retained_anchor.get_node("Pick") == retained_pick and added_anchor != null \
				and added_anchor.has_node("Pick")
			host.state.transmission_parts.erase("cog-extra")
			host.state.motion.erase("cog-extra")
			host.state.revision += 1
			presenter.refresh()
			matches = matches and not is_instance_valid(added_anchor) \
				and part_anchor(presenter, "cog-0") == retained_anchor
			var rebuilt: Dictionary = host.state.transmission_parts["cog-0"].duplicate(true)
			rebuilt.generation += 1
			host.state.transmission_parts["cog-0"] = rebuilt
			host.state.revision += 1
			presenter.refresh()
			var regenerated_anchor: Node3D = part_anchor(presenter, "cog-0")
			matches = matches and not is_instance_valid(retained_anchor) and regenerated_anchor != null \
				and regenerated_anchor.has_node("Pick")
			host.state.context = "new-synthetic-cog-context"
			host.state.revision += 1
			presenter.refresh()
			matches = matches and not is_instance_valid(regenerated_anchor) \
				and part_anchor(presenter, "cog-0").has_node("Pick")
		if count == batch_minimum:
			var last := "cog-%d" % (count - 1)
			var removed: Dictionary = host.state.transmission_parts[last]
			var removed_motion: Dictionary = host.state.motion[last]
			host.state.transmission_parts.erase(last)
			host.state.motion.erase(last)
			if trusted_revision:
				host.state.revision += 1
			presenter.refresh()
			matches = matches and presenter._gear_batches.is_empty()
			var ordinary := 0
			for child: Node in presenter.get_children():
				if child.has_meta("entity") and child.has_node("Gear") and child.has_node("Pick"):
					ordinary += 1
			matches = matches and ordinary == count - 1
			host.state.transmission_parts[last] = removed
			host.state.motion[last] = removed_motion
			if trusted_revision:
				host.state.revision += 1
			presenter.refresh()
			var restored := 0
			for group: Dictionary in presenter._gear_batches.values():
				restored += group.mesh.instance_count
			matches = matches and restored == count
		if not matches:
			push_error("Cog batch lost confirmed identity, pose, or read-only motion.")
			quit(1)
			return
		print("COG_SCALE_VALIDATION " + JSON.stringify({"count": count, "supports": supports,
			"varied_supports": varied_supports, "support_instances": support_instances,
			"support_batches": support_batches,
			"cycle_axes": cycle_axes, "large_every": large_every, "picks": pick_count,
			"batched": batched_count, "status": "pass"}))
		scene.free()
		await process_frame
		quit()
		return
	var frame_times: Array[float] = []
	var motion_times: Array[float] = []
	var process_times: Array[float] = []
	var refresh_times: Array[float] = []
	var draw_calls: Array[int] = []
	for frame in 150:
		var start := Time.get_ticks_usec()
		var refresh_start := start
		if whole_opening and refresh_every_frame:
			opening._refresh_transmission()
		var refresh_ms := float(Time.get_ticks_usec() - refresh_start) / 1000.0
		if not whole_opening:
			presenter.advance_visual_motion(1.0 / 60.0)
		var motion_ms := float(Time.get_ticks_usec() - start) / 1000.0
		await process_frame
		if frame >= 30:
			frame_times.append(float(Time.get_ticks_usec() - start) / 1000.0)
			motion_times.append(opening.motion_ms if whole_opening else motion_ms)
			if whole_opening:
				process_times.append(opening.process_ms)
				refresh_times.append(refresh_ms)
			draw_calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	frame_times.sort()
	motion_times.sort()
	process_times.sort()
	refresh_times.sort()
	draw_calls.sort()
	if not capture.is_empty():
		var image := root.get_texture().get_image()
		image.save_png(capture)
	var result := {"count": count, "build_ms": build_ms,
		"supports": supports, "varied_supports": varied_supports,
		"support_instances": support_instances, "support_batches": support_batches,
		"large_every": large_every,
		"stopped": stopped, "refresh_every_frame": refresh_every_frame,
		"trusted_revision": trusted_revision,
		"motion_median_ms": motion_times[motion_times.size() / 2],
		"frame_median_ms": frame_times[frame_times.size() / 2],
		"frame_p95_ms": frame_times[int(frame_times.size() * 0.95)],
		"draw_calls_median": draw_calls[draw_calls.size() / 2],
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"whole_opening": whole_opening}
	if whole_opening:
		result.process_median_ms = process_times[process_times.size() / 2]
		result.refresh_median_ms = refresh_times[refresh_times.size() / 2]
		if count > 0 and count < 800:
			var added: Dictionary = host.state.transmission_parts["cog-0"].duplicate(true)
			added.center = [columns * 4, 4, 0]
			added.erase("support")
			host.state.transmission_parts["cog-added"] = added
			host.state.motion["cog-added"] = host.state.motion["cog-0"].duplicate(true)
			if trusted_revision:
				host.state.revision += 1
			var refresh_start := Time.get_ticks_usec()
			opening._refresh_transmission()
			result.append_refresh_ms = float(Time.get_ticks_usec() - refresh_start) / 1000.0
	print("COG_SCALE " + JSON.stringify(result))
	scene.free()
	quit()
