extends SceneTree
## Invented confirmed samples check a visual rig, never a physical actor.
const Presenter = preload("res://opening/character_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")
var checks := 0
var failed := false
var mesh_count := 0
var tangent_error := 0.0
var source_bones := 0
var source_vertices := 0
var source_triangles := 0
var adult_measurements := {}

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

func skeleton_of(body: Node3D) -> Skeleton3D:
	return body.get_node(body.get_meta("skeleton_path"))

func leg_rotation(body: Node3D) -> Quaternion:
	if body.get_meta("sourced_character", false):
		return skeleton_of(body).get_bone_pose_rotation(skeleton_of(body).find_bone("Bip01 L Thigh"))
	return body.get_node("LeftHip").quaternion

func knee_forward_offset(body: Node3D, side: String) -> float:
	var skeleton := skeleton_of(body)
	skeleton.force_update_all_bone_transforms()
	var to_body: Transform3D = body.global_transform.affine_inverse() * skeleton.global_transform
	var hip: Vector3 = to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 " + side + " Thigh")).origin
	var knee: Vector3 = to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 " + side + " Calf")).origin
	var ankle: Vector3 = to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 " + side + " Foot")).origin
	var reach := (ankle - hip).normalized()
	var forward := (Vector3.BACK - reach * reach.dot(Vector3.BACK)).normalized()
	return (knee - hip).dot(forward)

func skin_points(body: Node3D) -> PackedVector3Array:
	# Independent vertex oracle: use each exported skin bind and its current
	# named bone pose, then the actual scene transform into BodyView space.
	var skeleton := skeleton_of(body)
	skeleton.force_update_all_bone_transforms()
	var mesh: MeshInstance3D = body.find_children("*", "MeshInstance3D", true, false)[0]
	var to_body: Transform3D = body.global_transform.affine_inverse() * skeleton.global_transform
	var points := PackedVector3Array()
	for surface in range(mesh.mesh.get_surface_count()):
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride: int = bones.size() / vertices.size()
		for vertex in range(vertices.size()):
			var point := Vector3.ZERO
			var total := 0.0
			for influence in range(stride):
				var offset := vertex * stride + influence
				var weight: float = weights[offset]
				if weight == 0.0:
					continue
				var bind: int = bones[offset]
				var bone: int = mesh.skin.get_bind_bone(bind)
				if bone < 0:
					bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
				point += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weight
				total += weight
			verify(point.is_finite() and absf(total - 1.0) < 0.0001,
				"Every source vertex has finite normalized skin weights and a resolved bone.")
			points.append(to_body * point)
	return points

func point_bounds(points: PackedVector3Array) -> AABB:
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds

func inspect_adult(body: Node3D, other: Node3D, presenter: Node) -> void:
	var skeleton := skeleton_of(body)
	var other_skeleton := skeleton_of(other)
	var mesh: MeshInstance3D = body.find_children("*", "MeshInstance3D", true, false)[0]
	var other_mesh: MeshInstance3D = other.find_children("*", "MeshInstance3D", true, false)[0]
	source_bones = skeleton.get_bone_count()
	verify(mesh.skin.get_bind_count() == 80 and mesh.mesh.get_surface_count() == 3,
		"The shipped adult retains all eighty source skin bindings and three materials.")
	verify(mesh.mesh == other_mesh.mesh and mesh.skin == other_mesh.skin and skeleton != other_skeleton,
		"Actors share immutable geometry, skin and textures while owning separate skeleton poses.")
	for node in body.find_children("*", "", true, false):
		verify(not node is CollisionObject3D and not node is CollisionShape3D and not node is AnimationPlayer,
			"The adult asset contains only visual nodes, without physical or autonomous animation authority.")
	for surface in range(mesh.mesh.get_surface_count()):
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		source_vertices += arrays[Mesh.ARRAY_VERTEX].size()
		source_triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
		var material: StandardMaterial3D = mesh.mesh.surface_get_material(surface)
		verify(material.albedo_color == Color.WHITE and material.albedo_texture != null
			and material.albedo_texture.get_image().has_mipmaps(),
			"Source skin, clothing and hair colors are bound without a whole-body tint.")
		if material.resource_name == "f001_opacity":
			verify(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				and material.cull_mode == BaseMaterial3D.CULL_DISABLED and material.metallic_specular == 0.0,
				"Hair and lashes use their captured alpha texture without glass-like highlights.")
		else:
			verify(material.normal_enabled and material.normal_texture.get_width() == 512
				and material.normal_texture.get_image().has_mipmaps(),
				"Body and face bind the prepared normal maps and normalized mipmaps.")
	verify(source_vertices == 5438 and source_triangles == 8732,
		"The representative asset uses the exact converted original mesh level.")
	verify(Presenter.adult_run_clip != null and Presenter.adult_run_clip.get_track_count() == 34
		and absf(Presenter.adult_run_clip.length - 0.83333333333333) < 0.00001
		and body.get_meta("run_bindings").size() >= 28,
		"The captured run clip is directly available without an editor import cache and binds to the adult skeleton.")
	verify(Presenter.adult_walk_clip != null and Presenter.adult_walk_clip.get_track_count() >= 30
		and absf(Presenter.adult_walk_clip.length - 1.23333333333333) < 0.00001
		and body.get_meta("walk_channels").size() >= 28,
		"The captured walk clip is directly available and binds to the adult skeleton.")
	var neutral := point_bounds(skin_points(body))
	var appearance: Node3D = body.get_node("AdultHuman")
	var source_rest: AABB = body.get_meta("source_rest_bounds")
	adult_measurements = {"neutral_min": [neutral.position.x, neutral.position.y, neutral.position.z],
		"neutral_size": [neutral.size.x, neutral.size.y, neutral.size.z],
		"source_min": [source_rest.position.x, source_rest.position.y, source_rest.position.z],
		"source_size": [source_rest.size.x, source_rest.size.y, source_rest.size.z],
		"appearance_scale": appearance.scale.x, "appearance_y": appearance.position.y,
		"upper_arm_pose": str(skeleton.get_bone_pose_rotation(skeleton.find_bone("Bip01 L UpperArm"))),
		"rig": str(body.get_meta("rig")["L UpperArm"])}
	verify(absf(neutral.position.y + 0.9) < 0.00001 and absf(neutral.size.y - 1.8) < 0.00001,
		"Actual skinned standing geometry fits the original 1.8-metre height and body-origin foot plane.")
	verify(maxf(absf(neutral.position.x), absf(neutral.end.x)) <= 0.301
		and maxf(absf(neutral.position.z), absf(neutral.end.z)) <= 0.301,
		"The lowered resting arms fit the original conservative visual width and depth.")
	var other_pose: Transform3D = other_skeleton.get_bone_global_pose(other_skeleton.find_bone("Bip01 L Thigh"))
	var resting_spine := skeleton.get_bone_pose_rotation(skeleton.find_bone("Bip01 Spine1"))
	for phase in [0.0, PI / 4.0, PI / 2.0, PI * 3.0 / 4.0,
			PI, PI * 5.0 / 4.0, PI * 1.5, PI * 7.0 / 4.0]:
		presenter._set_gait(body, phase, 1.0)
		var posed := point_bounds(skin_points(body))
		verify(posed.position.y + body.position.y >= -0.901 and body.position.x == 0.0 and body.position.z == 0.0,
			"The deformed gait and visual passing lift stay above the original foot plane without moving horizontally.")
		verify(other_skeleton.get_bone_global_pose(other_skeleton.find_bone("Bip01 L Thigh")) == other_pose,
			"Posing one actor cannot animate another actor's skeleton.")
	verify(not skeleton.get_bone_pose_rotation(skeleton.find_bone("Bip01 Spine1")).is_equal_approx(resting_spine),
		"Confirmed-distance movement articulates the upper body as well as the legs.")
	presenter._set_gait(body, 0.0, 1.0)
	verify(body.position.y > -0.051 and body.position.y < 0.056,
		"Captured root motion and stance correction shift only the visual body inside a small bounded range.")
	presenter._set_gait(body, 3.0 * PI / 4.0, 1.0)
	skeleton.force_update_all_bone_transforms()
	var to_body := body.global_transform.affine_inverse() * skeleton.global_transform
	var left_hand: Vector3 = to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 L Hand")).origin
	var right_hand: Vector3 = to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 R Hand")).origin
	verify(absf(left_hand.z - right_hand.z) > 0.08 and absf(left_hand.y - right_hand.y) > 0.04,
		"The captured running cycle separates the two arms in depth and height.")
	for mix in [0.0, 0.5, 1.0]:
		var maximum := {"L": -INF, "R": -INF}
		var minimum := {"L": INF, "R": INF}
		for sample in range(24):
			presenter._set_gait(body, float(sample) * TAU / 24.0, 1.0, 0.0, 0.0, 0.0, mix)
			for side in ["L", "R"]:
				var offset := knee_forward_offset(body, side)
				maximum[side] = maxf(maximum[side], offset)
				minimum[side] = minf(minimum[side], offset)
			if mix == 0.0:
				var toe_to_body: Transform3D = body.global_transform.affine_inverse() * skeleton.global_transform
				var left_toe: Vector3 = toe_to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 L Toe0")).origin
				var right_toe: Vector3 = toe_to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 R Toe0")).origin
				var support_height := Geometry.CAPSULE_HEIGHT / 2.0 + body.position.y \
					+ minf(left_toe.y, right_toe.y) - 0.007
				verify(support_height > -0.035 and support_height < 0.04,
					"Every captured walking phase keeps a toe near the unchanged support plane.")
		verify(maximum.L > 0.14 and maximum.R > 0.14
			and minimum.L > -0.03 and minimum.R > -0.03,
			"Both knees flex forward and avoid visible hyperextension across each grounded gait cycle.")
	var contact_samples := []
	for phase in [0.0, PI / 2.0, PI, 3.0 * PI / 2.0]:
		presenter._set_gait(body, phase, 1.0, 0.0, 0.0, 0.0, 0.0)
		skeleton.force_update_all_bone_transforms()
		var sample_to_body: Transform3D = body.global_transform.affine_inverse() * skeleton.global_transform
		contact_samples.append({"L": sample_to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 L Toe0")).origin,
			"R": sample_to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 R Toe0")).origin})
	var quarter_travel := Presenter.WALK_CYCLE_DISTANCE / 4.0
	verify(absf(contact_samples[1].R.z - contact_samples[0].R.z + quarter_travel) < 0.08
		and absf(contact_samples[3].L.z - contact_samples[2].L.z + quarter_travel) < 0.08,
		"Each planted walking toe nearly cancels confirmed forward travel over its stance quarter-cycle.")
	presenter._set_gait(body, TAU / 24.0, 1.0)
	skeleton.force_update_all_bone_transforms()
	var run_to_body: Transform3D = body.global_transform.affine_inverse() * skeleton.global_transform
	var run_left_toe: Vector3 = run_to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 L Toe0")).origin
	var run_right_toe: Vector3 = run_to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 R Toe0")).origin
	var running_support := Geometry.CAPSULE_HEIGHT / 2.0 + body.position.y \
		+ minf(run_left_toe.y, run_right_toe.y) - 0.007
	verify(running_support > -0.035 and running_support < 0.04,
		"The captured running stance approaches the support plane without moving the actor root.")
	presenter._set_gait(body, 0.0, 0.0, 0.0, 0.0, 1.0)
	var impact_bounds := point_bounds(skin_points(body))
	verify(impact_bounds.position.y + body.position.y >= -0.901
		and impact_bounds.position.y + body.position.y <= -0.85,
		"The compressed landing pose keeps the skinned boots near and above the unchanged foot plane.")
	presenter._set_gait(body, 0.0, 0.0, 1.0, 5.0, 0.0)
	var rising_knee := skeleton.get_bone_pose_rotation(skeleton.find_bone("Bip01 L Calf"))
	var rising_other_knee := skeleton.get_bone_pose_rotation(skeleton.find_bone("Bip01 R Calf"))
	presenter._set_gait(body, 0.0, 0.0, 1.0, 0.0, 0.0)
	var apex_knee := skeleton.get_bone_pose_rotation(skeleton.find_bone("Bip01 L Calf"))
	var apex_other_knee := skeleton.get_bone_pose_rotation(skeleton.find_bone("Bip01 R Calf"))
	presenter._set_gait(body, 0.0, 0.0, 1.0, -5.0, 0.0)
	var falling_knee := skeleton.get_bone_pose_rotation(skeleton.find_bone("Bip01 L Calf"))
	verify(not rising_knee.is_equal_approx(apex_knee)
		and not apex_knee.is_equal_approx(falling_knee),
		"The airborne skeleton changes from takeoff to apex to pre-landing extension.")
	var rig: Dictionary = body.get_meta("rig")
	var takeoff_split: float = absf(rising_knee.angle_to(rig["L Calf"].rotation)
		- rising_other_knee.angle_to(rig["R Calf"].rotation))
	var apex_split: float = absf(apex_knee.angle_to(rig["L Calf"].rotation)
		- apex_other_knee.angle_to(rig["R Calf"].rotation))
	verify(takeoff_split > apex_split + 0.25
		and apex_knee.angle_to(rig["L Calf"].rotation)
		> falling_knee.angle_to(rig["L Calf"].rotation) + 0.25,
		"The running jump leads with one knee, folds near the apex and extends before impact.")
	presenter._set_gait(body, 0.0, 0.0)
	verify(body.position == Vector3.ZERO, "The visual body returns to its original rest origin.")

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
	var body: Node3D = p.get_node("BodyView")
	var sourced := FileAccess.file_exists(Presenter.ADULT_ASSETS + "adult_worker.glb")
	verify(body.get_meta("sourced_character", false) == sourced and not body.get_meta("appearance_unavailable", false),
		"A complete capture uses the adult asset; a historical roster retains its identified legacy visual.")
	if body.get_meta("appearance_unavailable", false):
		presenter.free()
		host.free()
		print(JSON.stringify({"status": "fail", "checks": checks, "reason": "asset_unavailable"}))
		quit(1)
		return
	# Keep the existing legacy geometry checks without substituting them for the
	# current opening's actual sourced skeleton and material bindings.
	var legacy: MeshInstance3D = presenter._make_legacy_worker_visual()
	inspect_visual(legacy, Transform3D.IDENTITY)
	check_torso(legacy.mesh)
	check_feet(legacy, presenter)
	legacy.free()
	if sourced:
		inspect_adult(body, q.get_node("BodyView"), presenter)
	else:
		verify(body.mesh == q.get_node("BodyView").mesh and body.material_override != q.get_node("BodyView").material_override,
			"Legacy workers share geometry while retaining distinct local and remote clothing.")
		verify(body.material_override.normal_enabled and body.material_override.normal_texture.seamless,
			"Legacy workwear retains its self-contained fabric detail.")
	var neutral_leg := leg_rotation(body)
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
	verify(presenter.motion.P.phase > 0.0 and not leg_rotation(body).is_equal_approx(neutral_leg),
		"Only confirmed displacement advances the actual visual rig.")
	var first_run_mix := (1.0 / 60.0) * 5.0
	verify(absf(float(presenter.motion.P.run_mix) - first_run_mix) < 0.00001
		and absf(float(presenter.motion.P.phase) - 0.15 * TAU
		/ lerpf(Presenter.WALK_CYCLE_DISTANCE, Presenter.GAIT_CYCLE_DISTANCE, first_run_mix)) < 0.00001,
		"Confirmed travel advances the blended walk/run phase without an abrupt first-frame switch.")
	var phase: float = presenter.motion.P.phase
	var caches := [Presenter.mesh_cache.size(), Presenter.material_cache.size()]
	for n in range(30):
		presenter.refresh(1.0 / 60.0)
	verify(presenter.motion.P.phase == phase and leg_rotation(body).is_equal_approx(neutral_leg),
		"Stopped observations settle to a neutral stance without inventing travel.")
	verify(caches == [Presenter.mesh_cache.size(), Presenter.material_cache.size()],
		"Pose refresh does not rebuild meshes or materials.")
	var other: Node3D = presenter.views.Q
	for n in range(12):
		host.state.actors.P.position[0] += 0.05
		host.state.actors.Q.position[0] += 0.008
		presenter.refresh(1.0 / 60.0)
	verify(float(presenter.motion.P.weight) > float(presenter.motion.Q.weight)
		and float(presenter.motion.Q.weight) > 0.0 and absf(p.position.x - 0.75) < 0.00001
		and absf(other.position.x - 2.096) < 0.00001
		and float(presenter.motion.P.run_mix) > 0.95 and float(presenter.motion.Q.run_mix) < 0.05,
		"Separate actors animate from their own observed travel speed and exact roots.")
	for n in range(30):
		presenter.refresh(1.0 / 60.0)
	verify(float(presenter.motion.P.weight) == 0.0 and float(presenter.motion.Q.weight) == 0.0,
		"A stopped observation settles both visual rigs after the brief sample gap.")
	if sourced:
		var still_leg := leg_rotation(body)
		var other_leg := leg_rotation(other.get_node("BodyView"))
		host.state.actors.P.position[1] = 0.98
		presenter.refresh(1.0 / 60.0)
		var rising_leg := leg_rotation(body)
		verify(presenter.motion.P.mode == "ascent" and is_equal_approx(p.position.y, 0.98)
			and not leg_rotation(body).is_equal_approx(still_leg),
			"Confirmed rising motion changes the exact-root adult from idle to a distinct takeoff pose.")
		var airborne_phase: float = presenter.motion.P.phase
		for height in [1.42, 1.82, 1.86, 1.79, 1.38]:
			host.state.actors.P.position[1] = height
			host.state.actors.P.position[0] += 0.03
			presenter.refresh(1.0 / 60.0)
		verify(presenter.motion.P.mode == "descent" and presenter.motion.P.air > 0.9
			and presenter.motion.P.phase == airborne_phase and is_equal_approx(p.position.y, 1.38)
			and not leg_rotation(body).is_equal_approx(rising_leg),
			"The flight pose follows confirmed ascent and descent without cycling grounded steps or predicting root travel.")
		verify(leg_rotation(other.get_node("BodyView")).is_equal_approx(other_leg),
			"One actor's jump cannot animate another actor's skeleton.")
		host.state.actors.P.position[1] = 0.9
		presenter.refresh(1.0 / 60.0)
		verify(presenter.motion.P.mode == "landing" and body.position.y < 0.0
			and is_equal_approx(p.position.y, 0.9),
			"A confirmed return to the support height compresses only the visual rig at the exact actor root.")
		for n in range(25):
			presenter.refresh(1.0 / 60.0)
		verify(presenter.motion.P.mode == "grounded" and body.position == Vector3.ZERO
			and leg_rotation(body).is_equal_approx(still_leg),
			"Landing settles back to an unmoving neutral skeleton and body origin.")
		host.state.actors.P.position[1] = 2.1
		presenter.refresh(1.0 / 60.0)
		verify(presenter.motion.P.mode == "ascent" and is_equal_approx(p.position.y, 2.1),
			"A sparse confirmed jump sample above one metre is not mistaken for a teleport.")
		host.state.actors.P.position[1] = 0.9
		presenter.refresh(1.0 / 60.0)
		for n in range(25):
			presenter.refresh(1.0 / 60.0)
		host.state.actors.P.position[1] = 0.8
		presenter.refresh(1.0 / 60.0)
		host.state.actors.P.position[1] = 0.65
		presenter.refresh(1.0 / 60.0)
		presenter.refresh(1.0 / 60.0)
		verify(presenter.motion.P.mode == "landing" and is_equal_approx(p.position.y, 0.65),
			"A confirmed drop can land on a new height after descent becomes stationary.")
	host.state["actors"]["P"]["position"] = [10.0, 0.9, 0.0]
	presenter.refresh(1.0 / 60.0)
	verify(p.position == Vector3(10, 0.9, 0) and presenter.motion.P.phase == 0.0
		and presenter.motion.P.mode == "grounded",
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
		"maximum_packed_tangent_dot": tangent_error, "sourced_character": sourced,
		"source_bones": source_bones, "source_vertices": source_vertices, "source_triangles": source_triangles,
		"adult_measurements": adult_measurements,
		"native_actor": "not_started", "desktop": "not_used", "appearance": "not_assessed"}))
	quit(1 if failed else 0)
