extends SceneTree
## Invented confirmed samples check a visual rig, never a physical actor.
const Presenter = preload("res://opening/character_presenter.gd")
var checks := 0
var failed := false
var mesh_count := 0
var tangent_error := 0.0

class HostFixture:
	extends Node3D
	var state := {"context": "worker-fixture", "actors": {
		"P": {"ready": true, "position": [0.0, 0.9, 0.0]},
		"Q": {"ready": true, "position": [2.0, 0.9, 0.0]}}}
	var client := "P"
	var explanation_open := false
	var focus := Vector3.ZERO
	var control_calls := 0
	func _update_camera() -> void:
		pass
	func _can_control_character() -> bool:
		return false
	func _send_character_input(_direction: Vector2, _jump: bool) -> void:
		control_calls += 1
	func _release_character_input() -> void:
		control_calls += 1

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func inspect_visual(node: Node3D, parent_pose: Transform3D) -> void:
	var pose := parent_pose * node.transform
	verify(not node is CollisionObject3D and not node is CollisionShape3D,
		"The rig introduces no physical or pick authority.")
	if node is MeshInstance3D:
		mesh_count += 1
		var bounds: AABB = node.mesh.get_aabb()
		var bounded := true
		for n in range(8):
			var point := pose * bounds.get_endpoint(n)
			bounded = bounded and point.is_finite() and absf(point.x) <= 0.301 and absf(point.z) <= 0.301
			bounded = bounded and point.y >= -0.901 and point.y <= 0.901
		verify(bounded, "The neutral fitted worker retains the conservative visual envelope around its body origin.")
		if node.mesh is ArrayMesh and node.name != "BodyView":
			var data: Array = node.mesh.surface_get_arrays(0)
			var points: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
			var outward := true
			for n in range(0, points.size(), 3):
				outward = outward and (points[n + 1] - points[n]).cross(points[n + 2] - points[n]).dot(normals[n]) < 0
			verify(outward, "Fitted harness and reflective patches have visible outward front faces.")
	for child in node.get_children():
		if child is Node3D:
			inspect_visual(child, pose)

func check_torso(mesh: ArrayMesh) -> void:
	var data := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = data[Mesh.ARRAY_TANGENT]
	var correct := true
	for n in range(vertices.size()):
		var gradient := (vertices[n] / Vector3(0.22 * 0.22, 0.32 * 0.32, 0.1408 * 0.1408)).normalized()
		var tangent := Vector3(tangents[n * 4], tangents[n * 4 + 1], tangents[n * 4 + 2])
		tangent_error = maxf(tangent_error, absf(tangent.dot(normals[n])))
		correct = correct and gradient.dot(normals[n]) > 0.999 and tangent.is_finite()
		correct = correct and tangent.length() > 0.99 and absf(tangent.dot(normals[n])) < 0.0002
	verify(correct, "The authored torso preserves inverse-transpose normals and usable packed tangents.")

func check_feet(body: Node3D, presenter: Node) -> void:
	for phase in [0.0, PI / 2.0, PI, PI * 1.5]:
		presenter._set_gait(body, phase, 1.0)
		for side in ["Left", "Right"]:
			var hip: Node3D = body.get_node(side + "Hip")
			var knee: Node3D = hip.get_node("Knee")
			var ankle: Node3D = knee.get_node("Ankle")
			var sole: MeshInstance3D = ankle.get_node("BootSole")
			var pose := hip.transform * knee.transform * ankle.transform * sole.transform
			var minimum := INF
			for corner in range(8):
				minimum = minf(minimum, (pose * sole.mesh.get_aabb().get_endpoint(corner)).y)
			verify(minimum >= -0.901 and absf(pose.basis.y.dot(Vector3.UP) - 1.0) < 0.00001,
				"The visual stride keeps each boot level and above the unchanged neutral foot plane.")
	presenter._set_gait(body, 0, 0)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var host := HostFixture.new()
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	root.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var p: Node3D = presenter.views.P
	var q: Node3D = presenter.views.Q
	var body: MeshInstance3D = p.get_node("BodyView")
	inspect_visual(body, Transform3D.IDENTITY)
	check_torso(body.mesh)
	check_feet(body, presenter)
	verify(body.mesh == q.get_node("BodyView").mesh and body.material_override != q.get_node("BodyView").material_override,
		"Workers share geometry while retaining distinct local and remote clothing.")
	verify(body.material_override.normal_enabled and body.material_override.normal_texture.seamless,
		"The actual workwear binds self-contained repeating fabric detail.")
	var original: Dictionary = host.state.duplicate(true)
	presenter.refresh(1.0 / 60.0)
	presenter.held_keys[KEY_W] = true
	for n in range(4):
		presenter.refresh(1.0 / 60.0)
	verify(presenter.motion.P.phase == 0.0 and host.state == original,
		"Held input without confirmed displacement cannot advance the visual gait or world.")
	host.state["actors"]["P"]["position"] = [0.15, 0.9, 0.0]
	var moved: Dictionary = host.state.duplicate(true)
	presenter.refresh(1.0 / 60.0)
	verify(p.position == Vector3(0.15, 0.9, 0.0) and host.state == moved,
		"The visible root remains exactly at the projected body origin without prediction.")
	verify(presenter.motion.P.phase > 0.0 and body.get_node("LeftHip").rotation.x != 0.0,
		"Only confirmed displacement advances the actual visual rig.")
	var phase: float = presenter.motion.P.phase
	var caches := [Presenter.mesh_cache.size(), Presenter.material_cache.size()]
	for n in range(30):
		presenter.refresh(1.0 / 60.0)
	verify(presenter.motion.P.phase == phase and is_zero_approx(body.get_node("LeftHip").rotation.x),
		"Stopped observations settle to a neutral stance without inventing travel.")
	verify(caches == [Presenter.mesh_cache.size(), Presenter.material_cache.size()],
		"Pose refresh does not rebuild meshes or materials.")
	host.state["actors"]["P"]["position"] = [10.0, 0.9, 0.0]
	presenter.refresh(1.0 / 60.0)
	verify(p.position == Vector3(10, 0.9, 0) and presenter.motion.P.phase == 0.0,
		"A discontinuous observed pose resets animation without rejecting or clamping the body.")
	host.state["context"] = "another-world"
	presenter.refresh(1.0 / 60.0)
	verify(presenter.visual_context == "another-world" and presenter.motion.P.phase == 0.0,
		"World changes cannot replay the old walking phase.")
	host.state.actors.P["ready"] = false
	presenter.refresh(1.0 / 60.0)
	verify(not p.visible and not presenter.motion.has("P"), "An unready actor has no visible or retained gait.")
	host.state.actors.P["ready"] = true
	host.state.actors.P["position"] = [1.0, 2.0, 3.0, 4.0]
	presenter.refresh(1.0 / 60.0)
	verify(not p.visible and not presenter.motion.has("P"), "A malformed fourth coordinate cannot become a visible pose.")
	host.state.actors.erase("Q")
	presenter.refresh(1.0 / 60.0)
	verify(not presenter.views.has("Q") and not presenter.motion.has("Q"), "Removed actors leave no visual or gait record.")
	verify(host.control_calls == 0, "The visual fixture issued no actor input, jump or release command.")
	presenter.free()
	host.free()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks, "meshes": mesh_count,
		"maximum_packed_tangent_dot": tangent_error, "native_actor": "not_started", "desktop": "not_used", "appearance": "not_assessed"}))
	quit(1 if failed else 0)
