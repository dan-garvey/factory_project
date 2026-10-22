extends SceneTree
## Invented confirmed samples check a visual rig, never a physical actor.
const Presenter = preload("res://opening/character_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const Surface = preload("res://opening/site_surface.gd")
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

func finger_reaches(body: Node3D) -> Dictionary:
	var skeleton := skeleton_of(body)
	skeleton.force_update_all_bone_transforms()
	var result := {}
	for side in ["L", "R"]:
		var hand: Vector3 = skeleton.get_bone_global_pose(
			skeleton.find_bone("Bip01 " + side + " Hand")).origin
		for finger in range(1, 5):
			var distal: Vector3 = skeleton.get_bone_global_pose(
				skeleton.find_bone("Bip01 %s Finger%d2" % [side, finger])).origin
			result["%s%d" % [side, finger]] = hand.distance_to(distal)
	return result

func hand_forward_reaches(body: Node3D) -> Dictionary:
	var skeleton := skeleton_of(body)
	skeleton.force_update_all_bone_transforms()
	var result := {}
	for side in ["L", "R"]:
		var shoulder: Vector3 = skeleton.get_bone_global_pose(
			skeleton.find_bone("Bip01 " + side + " UpperArm")).origin
		var hand: Vector3 = skeleton.get_bone_global_pose(
			skeleton.find_bone("Bip01 " + side + " Hand")).origin
		result[side] = hand.z - shoulder.z
	return result

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
	var running_hands := []
	for arm_phase in [0.0, PI]:
		presenter._set_gait(body, arm_phase, 1.0)
		skeleton.force_update_all_bone_transforms()
		var arm_to_body := body.global_transform.affine_inverse() * skeleton.global_transform
		var left_hand: Vector3 = arm_to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 L Hand")).origin
		var right_hand: Vector3 = arm_to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 R Hand")).origin
		running_hands.append({"L": left_hand, "R": right_hand})
		verify(absf(left_hand.x) < 0.31 and absf(right_hand.x) < 0.31,
			"Running hands stay beside the trunk instead of flaring across the character width.")
	adult_measurements["running_hand_swing"] = {"first_horizontal": running_hands[0].R.z - running_hands[0].L.z,
		"second_horizontal": running_hands[1].L.z - running_hands[1].R.z,
		"first_vertical": running_hands[0].R.y - running_hands[0].L.y,
		"second_vertical": running_hands[1].L.y - running_hands[1].R.y}
	var running_hand_height := {"L": [INF, -INF], "R": [INF, -INF]}
	for sample in range(24):
		presenter._set_gait(body, float(sample) * TAU / 24.0, 1.0)
		skeleton.force_update_all_bone_transforms()
		var arm_to_body := body.global_transform.affine_inverse() * skeleton.global_transform
		for side in ["L", "R"]:
			var hand: Vector3 = arm_to_body * skeleton.get_bone_global_pose(
				skeleton.find_bone("Bip01 " + side + " Hand")).origin
			running_hand_height[side][0] = minf(float(running_hand_height[side][0]), hand.y)
			running_hand_height[side][1] = maxf(float(running_hand_height[side][1]), hand.y)
	adult_measurements["running_hand_height_range"] = {
		"L": float(running_hand_height.L[1]) - float(running_hand_height.L[0]),
		"R": float(running_hand_height.R[1]) - float(running_hand_height.R[0])}
	verify(running_hands[0].L.z < running_hands[0].R.z - 0.20
		and running_hands[1].L.z > running_hands[1].R.z + 0.20
		and running_hands[0].L.y < running_hands[0].R.y - 0.12
		and running_hands[1].L.y > running_hands[1].R.y + 0.05
		and adult_measurements.running_hand_height_range.L > 0.12
		and adult_measurements.running_hand_height_range.R > 0.12,
		"The captured run alternates opposite arm positions and height through a complete stride.")
	var torso_lead := -INF
	var torso_trail := INF
	for phase in [0.7, 2.2, 3.7, 5.2]:
		presenter._set_gait(body, phase, 1.0)
		skeleton.force_update_all_bone_transforms()
		var pelvis_at: Vector3 = presenter._adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 Pelvis"))
		var neck_at: Vector3 = presenter._adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 Neck"))
		var forward := neck_at.z - pelvis_at.z
		torso_lead = maxf(torso_lead, forward)
		torso_trail = minf(torso_trail, forward)
	verify(torso_lead > 0.04 and torso_lead - torso_trail > 0.05
		and torso_trail > -0.02,
		"The running chest moves ahead of the pelvis during a stride without an excessive bend.")
	adult_measurements["running_torso_forward"] = {"lead": torso_lead, "trail": torso_trail}
	presenter._set_gait(body, 1.5, 0.0)
	var neutral_fingers := finger_reaches(body)
	presenter._set_gait(body, 1.5, 1.0, 0.0, 0.0, 0.0, 0.0)
	var walking_fingers := finger_reaches(body)
	presenter._set_gait(body, 1.5, 1.0, 0.0, 0.0, 0.0, 1.0)
	var running_fingers := finger_reaches(body)
	presenter._set_gait(body, 1.5, 1.0, 1.0, -2.0, 0.0, 1.0)
	var airborne_fingers := finger_reaches(body)
	for side in ["L", "R"]:
		for finger in range(1, 5):
			var key := "%s%d" % [side, finger]
			verify(float(running_fingers[key]) < float(neutral_fingers[key]) - 0.004
				and float(running_fingers[key]) > 0.105
				and float(walking_fingers[key]) < float(neutral_fingers[key])
				and float(walking_fingers[key]) > float(running_fingers[key])
				and absf(float(airborne_fingers[key]) - float(neutral_fingers[key])) < 0.002,
				"Grounded fingers form a loose running hand, a softer walking hand, and release in flight.")
	adult_measurements["hand_reach"] = {"neutral_middle": neutral_fingers.L2,
		"walking_middle": walking_fingers.L2, "running_middle": running_fingers.L2,
		"airborne_middle": airborne_fingers.L2}
	var walking_elbow_max := 0.0
	var walking_hand_extent := {"L": [INF, -INF], "R": [INF, -INF]}
	for sample in range(24):
		presenter._set_gait(body, float(sample) * TAU / 24.0, 1.0, 0.0, 0.0, 0.0, 0.0)
		skeleton.force_update_all_bone_transforms()
		var arm_to_body := body.global_transform.affine_inverse() * skeleton.global_transform
		for side in ["L", "R"]:
			var shoulder: Vector3 = arm_to_body * skeleton.get_bone_global_pose(
				skeleton.find_bone("Bip01 " + side + " UpperArm")).origin
			var elbow: Vector3 = arm_to_body * skeleton.get_bone_global_pose(
				skeleton.find_bone("Bip01 " + side + " Forearm")).origin
			var wrist: Vector3 = arm_to_body * skeleton.get_bone_global_pose(
				skeleton.find_bone("Bip01 " + side + " Hand")).origin
			walking_elbow_max = maxf(walking_elbow_max,
				rad_to_deg((shoulder - elbow).angle_to(wrist - elbow)))
			walking_hand_extent[side][0] = minf(walking_hand_extent[side][0], wrist.z)
			walking_hand_extent[side][1] = maxf(walking_hand_extent[side][1], wrist.z)
			verify(absf(wrist.x) < 0.31, "Walking hands remain beside the trunk.")
	verify(walking_elbow_max < 165.0 and walking_hand_extent.L[1] - walking_hand_extent.L[0] > 0.30
		and walking_hand_extent.R[1] - walking_hand_extent.R[0] > 0.30,
		"Walking elbows remain relaxed while both hands swing through a full stride.")
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
	for swing in [{"side": "L", "phase": 1.05}, {"side": "R", "phase": 4.2}]:
		presenter._set_gait(body, float(swing.phase), 1.0, 0.0, 0.0, 0.0, 0.0)
		skeleton.force_update_all_bone_transforms()
		var hip: Vector3 = presenter._adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 " + swing.side + " Thigh"))
		var knee: Vector3 = presenter._adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 " + swing.side + " Calf"))
		var ankle: Vector3 = presenter._adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 " + swing.side + " Foot"))
		var flex := 180.0 - rad_to_deg((hip - knee).angle_to(ankle - knee))
		var toe: Vector3 = presenter._adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 " + swing.side + " Toe0"))
		var clearance: float = Geometry.CAPSULE_HEIGHT / 2.0 + body.position.y + toe.y - 0.007
		verify(flex > 18.0 and clearance > 0.02 and clearance < 0.20,
			"Each forward walking swing keeps a bent knee and a clear boot before support.")
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
	# The captured run's low-toe support spans the clip seam on the right and
	# the middle of the cycle on the left. Compare each toe's actual source
	# travel against the confirmed distance that advances those phases.
	for stance in [{"side": "R", "start": 5.60, "end": 7.24},
			{"side": "L", "start": 8.61, "end": 9.97}]:
		var toes := []
		var support := []
		for sample_phase: float in [stance.start, stance.end]:
			presenter._set_gait(body, sample_phase, 1.0, 0.0, 0.0, 0.0, 1.0)
			skeleton.force_update_all_bone_transforms()
			var toe_to_body: Transform3D = body.global_transform.affine_inverse() * skeleton.global_transform
			var toe: Vector3 = toe_to_body * skeleton.get_bone_global_pose(
				skeleton.find_bone("Bip01 " + stance.side + " Toe0")).origin
			toes.append(toe)
			support.append(Geometry.CAPSULE_HEIGHT / 2.0 + body.position.y + toe.y)
		var traveled: float = Presenter.GAIT_CYCLE_DISTANCE * (stance.end - stance.start) / TAU
		verify(absf(toes[1].z - toes[0].z + traveled) < 0.08
			and maxf(support[0], support[1]) < 0.08,
			"Both low running toes nearly cancel confirmed travel during their support intervals.")
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
	var landing_toes := []
	var landing_heights := []
	for progress in [0.14, 0.50, 0.85]:
		presenter._set_gait(body, 0.0, 0.0, 1.0 - progress, 0.0, 0.6, 0.0, progress)
		var bounds := point_bounds(skin_points(body))
		var sole_y := bounds.position.y + body.position.y
		verify(sole_y >= -0.905 and sole_y <= -0.88,
			"Contact, compression and recovery keep the skinned boots at the observed support plane.")
		var landing_to_body: Transform3D = body.global_transform.affine_inverse() * skeleton.global_transform
		var left_toe: Vector3 = landing_to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 L Toe0")).origin
		var right_toe: Vector3 = landing_to_body * skeleton.get_bone_global_pose(skeleton.find_bone("Bip01 R Toe0")).origin
		landing_toes.append({"L": left_toe, "R": right_toe})
		landing_heights.append(body.position.y)
	verify(landing_toes[0].L.z > landing_toes[0].R.z + 0.25
		and landing_toes[0].L.y < landing_toes[0].R.y - 0.05
		and landing_toes[2].L.z - landing_toes[2].R.z < 0.15,
		"The forward left boot takes first contact while the trailing right boot joins during recovery.")
	verify(landing_heights[0] < landing_heights[2] - 0.08
		and other_skeleton.get_bone_global_pose(other_skeleton.find_bone("Bip01 L Thigh")) == other_pose,
		"Landing load transfers through the visual body without moving a second actor's skeleton.")
	presenter._set_gait(body, 0.0, 0.0, 0.4, 0.0, 0.65, 0.0, 0.25, 0.0)
	var still_hands := hand_forward_reaches(body)
	presenter._set_gait(body, 0.0, 0.0, 0.4, 0.0, 0.65, 0.0, 0.25, 1.0)
	var moving_hands := hand_forward_reaches(body)
	verify(absf(float(still_hands.R) - float(still_hands.L)) < 0.06
		and float(moving_hands.R) - float(moving_hands.L)
		> float(still_hands.R) - float(still_hands.L) + 0.04,
		"A moving landing swings the opposite arm ahead of the leading boot; an in-place landing stays balanced.")
	adult_measurements["landing_hand_forward"] = {"still": still_hands,
		"moving": moving_hands}
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
	presenter._set_gait(body, 0.0, 0.0, 1.0, -5.0, 0.0, 1.0, 1.0, 1.0, 0.0)
	skeleton.force_update_all_bone_transforms()
	var approach_toe_index := skeleton.find_bone("Bip01 L Toe0")
	var unextended_toe: Vector3 = presenter._adult_joint(body, skeleton, approach_toe_index)
	var unextended_hands := hand_forward_reaches(body)
	presenter._set_gait(body, 0.0, 0.0, 1.0, -5.0, 0.0, 1.0, 1.0, 1.0, 1.0)
	skeleton.force_update_all_bone_transforms()
	var extended_toe: Vector3 = presenter._adult_joint(body, skeleton, approach_toe_index)
	var extended_hands := hand_forward_reaches(body)
	adult_measurements["precontact_toe"] = {"without": unextended_toe, "with": extended_toe}
	adult_measurements["precontact_hands"] = {"without": unextended_hands,
		"with": extended_hands}
	verify(extended_toe.z > unextended_toe.z + 0.25
		and extended_toe.y < unextended_toe.y + 0.04,
		"The moving landing reaches the lead boot forward before contact without lifting it away from support.")
	verify(extended_hands.R > unextended_hands.R + 0.06
		and extended_hands.R - extended_hands.L > unextended_hands.R - unextended_hands.L + 0.04
		and extended_hands.L < unextended_hands.L + 0.12,
		"The approaching moving landing brings the counterbalancing hand forward without a two-arm brace.")
	presenter._set_gait(body, 0.0, 0.0)
	verify(body.position == Vector3.ZERO, "The visual body returns to its original rest origin.")

func check_walking_support() -> void:
	var host := HostFixture.new()
	host.state.context = "walking-support"
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	host.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var view: Node3D = presenter.views.P
	var body: Node3D = view.get_node("BodyView")
	var skeleton: Skeleton3D = skeleton_of(body)
	var toes := {"L": skeleton.find_bone("Bip01 L Toe0"),
		"R": skeleton.find_bone("Bip01 R Toe0")}
	var previous := {"L": {}, "R": {}}
	var travel := {"L": 0.0, "R": 0.0}
	var samples := {"L": 0, "R": 0}
	var x := 0.0
	for frame in range(160):
		x += 0.018 # Confirmed 1.08 m/s walk at 60 Hz.
		host.state.actors.P.position = [x, 0.9, 0.0]
		presenter.refresh(1.0 / 60.0)
		if frame < 20:
			continue # Let the visible pose reach its steady walking weight.
		skeleton.force_update_all_bone_transforms()
		var phase := fposmod(float(presenter.motion.P.phase), TAU)
		for side in ["L", "R"]:
			var stance := phase >= PI and phase <= PI * 1.5 if side == "L" \
				else phase <= PI * 0.5
			var toe: Vector3 = body.global_transform * presenter._adult_joint(body, skeleton, toes[side])
			var prior: Dictionary = previous[side]
			if stance and prior.get("stance", false):
				travel[side] += absf(toe.x - float(prior.x))
				samples[side] += 1
			previous[side] = {"x": toe.x, "stance": stance}
	for side in ["L", "R"]:
		verify(samples[side] > 20 and travel[side] / float(samples[side]) < 0.008,
			"The walking support toe stays near its world position across repeated confirmed steps.")
	verify(float(presenter.motion.P.weight) > 0.99 and is_equal_approx(view.position.x, x)
		and host.control_calls == 0,
		"A full walking stride remains visual and leaves the confirmed actor and input untouched.")
	host.free()

func check_native_cadence_walking_contact() -> void:
	var host := HostFixture.new()
	host.state.context = "walking-contact"
	host.state.actors.P.native_epoch = 1
	host.state.actors.P.position = [-1.5, Surface.height_at(-1.5, 3.3) + 0.9, 3.3]
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	host.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var view: Node3D = presenter.views.P
	var body: Node3D = view.get_node("BodyView")
	var skeleton: Skeleton3D = skeleton_of(body)
	var previous := {"L": {}, "R": {}}
	var step_sum := {"L": 0.0, "R": 0.0}
	var step_max := {"L": 0.0, "R": 0.0}
	var samples := {"L": 0, "R": 0}
	var minimum_knee := INF
	var exact_root := true
	var x := -1.5
	for frame in range(120):
		x += 0.035 # Confirmed 1.05 m/s walk, observed at 30 Hz.
		var at := Vector3(x, Surface.height_at(x, 3.3) + 0.9, 3.3)
		host.state.actors.P.position = [at.x, at.y, at.z]
		host.state.actors.P.native_epoch += 2
		presenter.refresh(1.0 / 30.0)
		exact_root = exact_root and view.position.is_equal_approx(at)
		if frame < 15:
			continue
		skeleton.force_update_all_bone_transforms()
		for side in ["L", "R"]:
			var toe: Vector3 = body.to_global(presenter._adult_joint(body, skeleton,
				skeleton.find_bone("Bip01 " + side + " Toe0")))
			var clearance := toe.y - Surface.height_at(toe.x, toe.z)
			var prior: Dictionary = previous[side]
			if clearance < 0.035 and prior.get("clearance", INF) < 0.035:
				var step := Vector2(toe.x - float(prior.x), toe.z - float(prior.z)).length()
				step_sum[side] += step
				step_max[side] = maxf(step_max[side], step)
				samples[side] += 1
			previous[side] = {"x": toe.x, "z": toe.z, "clearance": clearance}
			minimum_knee = minf(minimum_knee, knee_forward_offset(body, side))
	adult_measurements["walking_contact"] = {"samples": samples,
		"maximum_step": step_max, "mean_step": {"L": step_sum.L / maxf(1, samples.L),
		"R": step_sum.R / maxf(1, samples.R)}, "minimum_knee_forward": minimum_knee}
	verify(samples.L > 10 and samples.R > 10
		and step_max.L < 0.035 and step_max.R < 0.035
		and step_sum.L / float(samples.L) < 0.015
		and step_sum.R / float(samples.R) < 0.015,
		"Walking support boots stay near their world contact points at native snapshot cadence.")
	verify(minimum_knee > 0.015 and exact_root and host.control_calls == 0,
		"Walking contact keeps both knees forward and changes neither confirmed root nor input.")
	host.free()

func check_native_cadence_running_contact() -> void:
	var host := HostFixture.new()
	host.state.context = "running-contact"
	host.state.actors.P.native_epoch = 1
	host.state.actors.P.position = [-1.5, Surface.height_at(-1.5, 3.3) + 0.9, 3.3]
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	host.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var view: Node3D = presenter.views.P
	var body: Node3D = view.get_node("BodyView")
	var skeleton: Skeleton3D = skeleton_of(body)
	var previous := {"L": {}, "R": {}}
	var early_steps := {"L": [], "R": []}
	var toe_off := {"L": false, "R": false}
	var minimum_knee := INF
	var exact_root := true
	var x := -1.5
	for frame in range(100):
		x += 0.1 # Confirmed 3 m/s run, observed at 30 Hz.
		var at := Vector3(x, Surface.height_at(x, 3.3) + 0.9, 3.3)
		host.state.actors.P.position = [at.x, at.y, at.z]
		host.state.actors.P.native_epoch += 2
		presenter.refresh(1.0 / 30.0)
		exact_root = exact_root and view.position.is_equal_approx(at)
		if frame < 15:
			continue
		skeleton.force_update_all_bone_transforms()
		for side in ["L", "R"]:
			var toe: Vector3 = body.to_global(presenter._adult_joint(body, skeleton,
				skeleton.find_bone("Bip01 " + side + " Toe0")))
			var clearance := toe.y - Surface.height_at(toe.x, toe.z)
			var age: float = float(presenter.motion.P.get("support_contact_age", -1.0))
			var planted: bool = presenter.motion.P.get("support_contact_side", "") == side
			var early := planted and age <= 0.11 and clearance < 0.07
			var prior: Dictionary = previous[side]
			if early and prior.get("early", false):
				early_steps[side].append(Vector2(toe.x - float(prior.x),
					toe.z - float(prior.z)).length())
			if planted and age >= 0.16 and clearance > 0.08:
				toe_off[side] = true
			previous[side] = {"x": toe.x, "z": toe.z, "early": early}
			minimum_knee = minf(minimum_knee, knee_forward_offset(body, side))
	var maximum_step := {"L": 0.0, "R": 0.0}
	for side in ["L", "R"]:
		for step in early_steps[side]:
			maximum_step[side] = maxf(maximum_step[side], float(step))
	adult_measurements["running_contact"] = {"early_steps": early_steps,
		"maximum_step": maximum_step, "toe_off": toe_off,
		"minimum_knee_forward": minimum_knee}
	verify(early_steps.L.size() >= 3 and early_steps.R.size() >= 3
		and maximum_step.L < 0.02 and maximum_step.R < 0.02,
		"Each running support boot remains at its world point during its short early plant.")
	verify(toe_off.L and toe_off.R and minimum_knee > -0.03
		and exact_root and host.control_calls == 0,
		"Both running boots lift into toe-off without a backwards knee or actor input change.")
	host.free()

func check_native_cadence_jog_contact() -> void:
	var host := HostFixture.new()
	host.state.context = "jogging-contact"
	host.state.actors.P.native_epoch = 1
	host.state.actors.P.position = [-1.5, Surface.height_at(-1.5, 3.3) + 0.9, 3.3]
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	host.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var view: Node3D = presenter.views.P
	var body: Node3D = view.get_node("BodyView")
	var skeleton: Skeleton3D = skeleton_of(body)
	var previous := {"L": {}, "R": {}}
	var early_steps := {"L": [], "R": []}
	var anchored := {"L": 0, "R": 0}
	var maximum_early_clearance := {"L": 0.0, "R": 0.0}
	var minimum_knee := INF
	var exact_root := true
	var x := -1.5
	for frame in range(140):
		x += 2.01 / 30.0
		var at := Vector3(x, Surface.height_at(x, 3.3) + 0.9, 3.3)
		host.state.actors.P.position = [at.x, at.y, at.z]
		host.state.actors.P.native_epoch += 2
		presenter.refresh(1.0 / 30.0)
		exact_root = exact_root and view.position.is_equal_approx(at)
		if frame < 15:
			continue
		skeleton.force_update_all_bone_transforms()
		for side in ["L", "R"]:
			var toe: Vector3 = body.to_global(presenter._adult_joint(body, skeleton,
				skeleton.find_bone("Bip01 " + side + " Toe0")))
			var clearance := toe.y - Surface.height_at(toe.x, toe.z)
			var age: float = float(presenter.motion.P.get("support_contact_age", -1.0))
			var planted: bool = presenter.motion.P.get("support_contact_side", "") == side
			var early := planted and age <= 0.12 and clearance < 0.075
			if early:
				anchored[side] += 1
				maximum_early_clearance[side] = maxf(maximum_early_clearance[side], clearance)
			var prior: Dictionary = previous[side]
			if early and prior.get("early", false):
				early_steps[side].append(Vector2(toe.x - float(prior.x),
					toe.z - float(prior.z)).length())
			previous[side] = {"x": toe.x, "z": toe.z, "early": early}
			minimum_knee = minf(minimum_knee, knee_forward_offset(body, side))
	var maximum_step := {"L": 0.0, "R": 0.0}
	for side in ["L", "R"]:
		for step in early_steps[side]:
			maximum_step[side] = maxf(maximum_step[side], float(step))
	adult_measurements["jogging_contact"] = {"anchored": anchored,
		"early_steps": early_steps, "maximum_step": maximum_step,
		"maximum_early_clearance": maximum_early_clearance,
		"minimum_knee_forward": minimum_knee}
	verify(anchored.L >= 5 and anchored.R >= 5
		and early_steps.L.size() >= 2 and early_steps.R.size() >= 2
		and maximum_step.L < 0.02 and maximum_step.R < 0.02
		and maximum_early_clearance.L < 0.06 and maximum_early_clearance.R < 0.06,
		"Both jogging support boots acquire world contact and stay near it through early plant.")
	verify(minimum_knee > 0.0 and exact_root and host.control_calls == 0,
		"Jogging contact keeps knees forward and preserves confirmed root and input authority.")
	host.free()

func check_sparse_confirmed_walk() -> void:
	var host := HostFixture.new()
	host.state.context = "sparse-confirmed-walk"
	host.state.actors.P.native_epoch = 1
	host.state.actors.Q.native_epoch = 1
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	host.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var delta := 1.0 / 60.0
	presenter.refresh(delta)
	for frame in range(1, 31):
		host.state.actors.P.position[0] += 0.0175
		host.state.actors.P.native_epoch += 1
		if frame % 3 == 0:
			host.state.actors.Q.position[0] += 0.0525
			host.state.actors.Q.native_epoch += 3
		presenter.refresh(delta)
	var dense: Dictionary = presenter.motion.P
	var sparse: Dictionary = presenter.motion.Q
	verify(absf(float(dense.horizontal_speed) - 1.05) < 0.02
		and absf(float(sparse.horizontal_speed) - 1.05) < 0.02
		and absf(float(dense.weight) - float(sparse.weight)) < 0.12
		and absf(float(dense.run_mix) - float(sparse.run_mix)) < 0.05
		and absf(float(dense.phase) - float(sparse.phase)) < 0.05,
		"Equal confirmed walking travel has comparable cadence and weight at dense and sparse snapshot rates.")
	verify(is_equal_approx(presenter.views.P.position.x, 0.525)
		and is_equal_approx(presenter.views.Q.position.x, 2.525)
		and host.control_calls == 0,
		"Sparse observations leave each exact actor root and input authority untouched.")
	for frame in range(20):
		host.state.actors.P.native_epoch += 1
		presenter.refresh(delta)
	verify(float(presenter.motion.Q.weight) < 0.1
		and is_equal_approx(presenter.views.Q.position.x, 2.525),
		"A stale native pose settles its visual stride without predicting more actor travel.")
	for frame in range(12):
		host.state.actors.P.native_epoch += 1
		host.state.actors.Q.native_epoch += 1
		presenter.refresh(delta)
	verify(float(presenter.motion.P.weight) < 0.01
		and float(presenter.motion.Q.weight) < 0.01,
		"Confirmed stationary snapshots settle both visual gaits after travel ends.")
	host.state.actors.P.position[0] += 0.05
	host.state.actors.P.native_epoch += 1
	presenter.refresh(delta)
	verify(absf(float(presenter.motion.P.horizontal_speed) - 3.0) < 0.02
		and is_equal_approx(presenter.views.P.position.x, 0.575),
		"A new confirmed step after rest uses its own sample interval and exact root.")
	host.free()

func check_uneven_native_walk_samples() -> void:
	var host := HostFixture.new()
	host.state.context = "uneven-native-walk"
	host.state.actors.P.native_epoch = 1
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	host.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var delta := 1.0 / 30.0
	var x := 0.0
	var minimum_weight := 1.0
	var maximum_weight := 0.0
	for frame in range(80):
		var observed_speed: float = [0.87, 0.87, 1.53][frame % 3]
		x += observed_speed * delta
		host.state.actors.P.position = [x, 0.9, 0.0]
		host.state.actors.P.native_epoch += 2 if frame % 3 != 2 else 3
		presenter.refresh(delta)
		if frame >= 20:
			minimum_weight = minf(minimum_weight, float(presenter.motion.P.weight))
			maximum_weight = maxf(maximum_weight, float(presenter.motion.P.weight))
	verify(minimum_weight > 0.92 and maximum_weight - minimum_weight < 0.08
		and float(presenter.motion.P.run_mix) < 0.02,
		"Uneven native snapshot spacing keeps a nearly steady walking pose at steady travel.")
	verify(is_equal_approx(presenter.views.P.position.x, x) and host.control_calls == 0,
		"Walking pose smoothing does not change the confirmed root or produce input.")
	host.free()

func check_jog_blend_at_native_physics_cadence() -> void:
	var host := HostFixture.new()
	host.state.context = "native-jog-cadence"
	host.state.actors.P.native_epoch = 1
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	host.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var delta := 1.0 / 30.0
	var x := 0.0
	var physics_frame := 10
	presenter.observe_native_sample("P", {"native_epoch": 1, "physics_frame": physics_frame})
	presenter.refresh(delta)
	var maximum_speed_error := 0.0
	var maximum_blend_error := 0.0
	var exact_root := true
	for frame in range(80):
		# The same 2.01 m/s actor advances by two or three physics ticks per draw.
		var ticks := 3 if frame % 3 == 2 else 2
		physics_frame += ticks
		x += float(ticks) * 2.01 / 60.0
		host.state.actors.P.position = [x, 0.9, 0.0]
		host.state.actors.P.native_epoch += ticks
		presenter.observe_native_sample("P", {"native_epoch": host.state.actors.P.native_epoch,
			"physics_frame": physics_frame})
		presenter.refresh(delta)
		exact_root = exact_root and is_equal_approx(presenter.views.P.position.x, x)
		if frame >= 20:
			maximum_speed_error = maxf(maximum_speed_error,
				absf(float(presenter.motion.P.horizontal_speed) - 2.01))
			maximum_blend_error = maxf(maximum_blend_error,
				absf(float(presenter.motion.P.run_mix) - (2.01 - Presenter.RUN_BLEND_START)
					/ (Presenter.RUN_BLEND_END - Presenter.RUN_BLEND_START)))
	adult_measurements["native_jog_cadence"] = {"maximum_speed_error": maximum_speed_error,
		"maximum_blend_error": maximum_blend_error}
	verify(maximum_speed_error < 0.002 and maximum_blend_error < 0.015,
		"Intermediate jog speed and pose blend stay steady across two- and three-tick native cuts.")
	verify(exact_root and host.control_calls == 0,
		"Native-timed jog presentation does not move the actor root or send input.")
	host.free()

func landing_contact_case(metres_per_frame: float) -> Dictionary:
	var host := HostFixture.new()
	host.state.context = "landing-contact"
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	host.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var view: Node3D = presenter.views.P
	var body: Node3D = view.get_node("BodyView")
	var skeleton: Skeleton3D = skeleton_of(body)
	var heights := [0.9, 1.12, 1.42, 1.78, 1.68, 1.38, 0.9, 0.9]
	var x := 0.0
	var descending_toe := 0.0
	var contact_toe := 0.0
	for frame in range(heights.size()):
		if frame > 0 and frame < 6:
			x += metres_per_frame
		host.state.actors.P.position = [x, heights[frame], 0.0]
		presenter.refresh(1.0 / 60.0)
		if frame == 5 or frame == 6:
			skeleton.force_update_all_bone_transforms()
			var toe: Vector3 = presenter._adult_joint(body, skeleton,
				skeleton.find_bone("Bip01 L Toe0"))
			if frame == 5:
				descending_toe = toe.z
			else:
				contact_toe = toe.z
	skeleton.force_update_all_bone_transforms()
	var left: Vector3 = presenter._adult_joint(body, skeleton,
		skeleton.find_bone("Bip01 L Toe0"))
	var right: Vector3 = presenter._adult_joint(body, skeleton,
		skeleton.find_bone("Bip01 R Toe0"))
	var result := {"stride": float(presenter.motion.P.landing_stride),
		"toe_spread": left.z - right.z, "root_x": view.position.x,
		"first_contact_reach_jump": contact_toe - descending_toe,
		"mode": presenter.motion.P.mode, "control_calls": host.control_calls}
	host.free()
	return result

func check_landing_contact_from_motion() -> void:
	var still := landing_contact_case(0.0)
	var slow := landing_contact_case(0.015)
	var moving := landing_contact_case(0.03)
	adult_measurements["landing_contact"] = {"still": still, "slow": slow, "moving": moving}
	verify(still.mode == "landing" and slow.mode == "landing" and moving.mode == "landing"
		and still.stride < 0.01 and slow.stride > 0.1 and slow.stride < 0.9
		and moving.stride > 0.99 and still.toe_spread < 0.18
		and slow.toe_spread > still.toe_spread and slow.toe_spread < moving.toe_spread
		and moving.toe_spread > 0.28,
		"Landing foot placement progresses from under-body contact to a staged forward step with confirmed travel.")
	verify(is_zero_approx(float(still.root_x)) and is_equal_approx(float(slow.root_x), 0.075)
		and is_equal_approx(float(moving.root_x), 0.15)
		and still.control_calls == 0 and slow.control_calls == 0 and moving.control_calls == 0,
		"Landing changes only the visual contact pose, never the confirmed actor or input.")
	verify(absf(float(moving.first_contact_reach_jump)) < 0.16,
		"The moving leading toe reaches forward during descent rather than snapping across first contact.")

func landing_toe_hold_case(metres_per_frame: float) -> Dictionary:
	var host := HostFixture.new()
	host.state.context = "landing-toe-hold"
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	host.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var body: Node3D = presenter.views.P.get_node("BodyView")
	var skeleton := skeleton_of(body)
	var heights := [0.9, 1.12, 1.42, 1.78, 1.68, 1.38]
	for sample in range(24):
		heights.append(0.9)
	var x := 0.0
	for sample in range(60):
		x += metres_per_frame
		host.state.actors.P.position = [x, 0.9, 0.0]
		presenter.refresh(1.0 / 60.0)
	var toes := []
	var trailing_toes := []
	var roots_exact := true
	var knee_forward := INF
	var trailing_knee_forward := INF
	var anchored := false
	for frame in range(heights.size()):
		if frame > 0:
			x += metres_per_frame
		host.state.actors.P.position = [x, heights[frame], 0.0]
		presenter.refresh(1.0 / 60.0)
		if frame == 6:
			anchored = presenter.motion.P.has("landing_toe_anchor")
		roots_exact = roots_exact and presenter.views.P.position.is_equal_approx(
			Vector3(x, heights[frame], 0.0))
		if frame >= 6:
			skeleton.force_update_all_bone_transforms()
			var toe: Vector3 = body.to_global(presenter._adult_joint(body, skeleton,
				skeleton.find_bone("Bip01 L Toe0")))
			var trailing_toe: Vector3 = body.to_global(presenter._adult_joint(body, skeleton,
				skeleton.find_bone("Bip01 R Toe0")))
			toes.append({"x": toe.x, "y": toe.y, "mode": presenter.motion.P.mode})
			trailing_toes.append({"x": trailing_toe.x, "y": trailing_toe.y})
			if presenter.motion.P.mode == "landing":
				knee_forward = minf(knee_forward, knee_forward_offset(body, "L"))
				trailing_knee_forward = minf(trailing_knee_forward,
					knee_forward_offset(body, "R"))
	var retreat := 0.0
	var furthest := float(toes[0].x)
	var contact_step := 0.0
	var prior := {}
	for sample in toes:
		if sample.mode == "landing" and float(sample.y) < 0.07:
			retreat = maxf(retreat, furthest - float(sample.x))
			furthest = maxf(furthest, float(sample.x))
			if not prior.is_empty():
				contact_step = maxf(contact_step, absf(float(sample.x) - float(prior.x)))
			prior = sample
	var result := {"toes": toes, "trailing_toes": trailing_toes, "retreat": retreat,
		"maximum_contact_step": contact_step, "root_x": x,
		"root_exact": roots_exact, "minimum_knee_forward": knee_forward,
		"trailing_knee_forward": trailing_knee_forward,
		"anchored": anchored,
		"control_calls": host.control_calls}
	host.free()
	return result

func check_landing_recovery_profile() -> void:
	var host := HostFixture.new()
	host.state.context = "landing-recovery-profile"
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	host.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var view: Node3D = presenter.views.P
	var body: Node3D = view.get_node("BodyView")
	var skeleton: Skeleton3D = skeleton_of(body)
	var approach := [0.9, 1.12, 1.42, 1.78, 1.68, 1.38, 0.9]
	for y: float in approach:
		host.state.actors.P.position = [0.0, y, 0.0]
		presenter.refresh(1.0 / 60.0)
	var heads := []
	var lowest_toe := INF
	var roots_exact := true
	for frame in range(24):
		presenter.refresh(1.0 / 60.0)
		skeleton.force_update_all_bone_transforms()
		var head: Vector3 = body.to_global(presenter._adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 Head")))
		var left_toe: Vector3 = body.to_global(presenter._adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 L Toe0")))
		var right_toe: Vector3 = body.to_global(presenter._adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 R Toe0")))
		heads.append(head.y)
		if frame < 10:
			lowest_toe = minf(lowest_toe, minf(left_toe.y, right_toe.y))
		roots_exact = roots_exact and view.position.is_equal_approx(Vector3(0.0, 0.9, 0.0))
	adult_measurements["landing_recovery"] = {"head_first": heads[0],
		"head_low": heads.slice(1, 8).min(), "head_final": heads.back(),
		"lowest_toe": lowest_toe}
	verify(heads.slice(1, 8).min() < heads[0] - 0.01 and heads.back() > heads[0] + 0.06
		and presenter.motion.P.mode == "grounded",
		"Landing takes load after first contact, then rises to a supported neutral stance.")
	verify(lowest_toe > -0.03 and lowest_toe < 0.04
		and roots_exact and host.control_calls == 0,
		"Landing recovery keeps the boot near ground and the confirmed actor root and input untouched.")
	host.free()

func check_run_stop_contact() -> void:
	var host := HostFixture.new()
	root.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	root.add_child(presenter)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	var view: Node3D = presenter.views.P
	var body: Node3D = view.get_node("BodyView")
	for step in range(92):
		host.state.actors.P.position[0] += 0.05
		presenter.refresh(1.0 / 60.0)
	var stopped_x: float = host.state.actors.P.position[0]
	var samples := []
	for step in range(30):
		presenter.refresh(1.0 / 60.0)
		var skeleton := skeleton_of(body)
		skeleton.force_update_all_bone_transforms()
		var motion: Dictionary = presenter.motion.P
		var side: String = motion.get("stop_side", "L")
		var toe := body.to_global(presenter._adult_joint(body, skeleton,
			skeleton.find_bone("Bip01 " + side + " Toe0")))
		samples.append({"frame": step, "x": toe.x, "height": toe.y,
			"knee_forward": knee_forward_offset(body, side),
			"anchored": motion.has("stop_toe_anchor"), "weight": motion.weight})
	var contact := []
	var lifted := false
	var minimum_knee := INF
	for sample in samples:
		if sample.anchored:
			minimum_knee = minf(minimum_knee, float(sample.knee_forward))
		if sample.anchored and sample.weight > 0.0 and sample.height < 0.06:
			contact.append(sample)
		if sample.anchored and sample.weight == 0.0 and sample.height > 0.06:
			lifted = true
	var stable := contact.size() >= 2
	if stable:
		for sample in contact:
			stable = stable and absf(float(sample.x) - float(contact[0].x)) < 0.035
	verify(stable and lifted and minimum_knee > -0.02
		and absf(view.position.x - stopped_x) < 0.00001
		and not presenter.motion.P.has("stop_toe_anchor")
		and float(presenter.motion.P.weight) == 0.0 and host.control_calls == 0,
		"A running stop plants its support toe, steps it into rest, and preserves the confirmed actor root and input.")
	adult_measurements["run_stop"] = {"root_x": stopped_x, "samples": samples}
	presenter.free()
	host.free()

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
		check_walking_support()
		check_native_cadence_walking_contact()
		check_native_cadence_jog_contact()
		check_native_cadence_running_contact()
		check_sparse_confirmed_walk()
		check_uneven_native_walk_samples()
		check_jog_blend_at_native_physics_cadence()
		check_landing_contact_from_motion()
		var still_contact := landing_toe_hold_case(0.0)
		var walk_contact := landing_toe_hold_case(0.018)
		var jog_contact := landing_toe_hold_case(0.028)
		var run_contact := landing_toe_hold_case(0.05)
		adult_measurements["landing_toe_hold"] = {"still": still_contact, "walk": walk_contact,
			"jog": jog_contact, "run": run_contact}
		var walk_toes: Array = walk_contact.toes
		var walk_contact_x: float = walk_toes[0].x
		var early_grounded := true
		for sample in walk_toes.slice(0, 6):
			early_grounded = early_grounded and absf(float(sample.x) - walk_contact_x) < 0.015 \
				and absf(float(sample.y) - 0.01) < 0.015
		verify(walk_contact.anchored and early_grounded and walk_contact.root_exact
			and walk_contact.minimum_knee_forward > 0.05 and walk_contact.control_calls == 0,
			"A warmed walking landing plants the forward-facing lead boot through early contact without moving the actor root.")
		verify(jog_contact.root_exact and jog_contact.minimum_knee_forward > 0.05
			and jog_contact.maximum_contact_step < 0.02 and jog_contact.retreat < 0.005
			and walk_contact.retreat < 0.015 and jog_contact.control_calls == 0
			and run_contact.anchored and run_contact.root_exact
			and run_contact.minimum_knee_forward > 0.04
			and run_contact.retreat < 0.015 and run_contact.maximum_contact_step < 0.08
			and run_contact.control_calls == 0,
			"Jogging and running landings clear the leading boot before it scrapes backward, without a backwards knee or input side effect.")
		var run_contact_x: float = run_contact.toes[0].x
		var run_early_grounded := true
		for sample in run_contact.toes.slice(0, 6):
			run_early_grounded = run_early_grounded \
				and absf(float(sample.x) - run_contact_x) < 0.015 \
				and absf(float(sample.y) - 0.01) < 0.015
		verify(run_early_grounded,
			"A warmed running landing holds its leading toe through the first supported samples.")
		verify(float(run_contact.toes[9].y) > 0.045
			and float(run_contact.toes[9].y) < 0.09
			and float(run_contact.toes[11].y) > 0.07
			and float(run_contact.toes[11].y) < 0.095,
			"The running lead boot lifts into toe-off after its initial plant instead of dragging along support.")
		var running_swing_clear := true
		for sample in run_contact.trailing_toes.slice(3, 12):
			running_swing_clear = running_swing_clear and float(sample.y) > 0.16
		var still_boot_supported := true
		for sample in still_contact.trailing_toes.slice(2, 12):
			still_boot_supported = still_boot_supported and absf(float(sample.y) - 0.01) < 0.015
		verify(running_swing_clear and run_contact.trailing_knee_forward > 0.04
			and still_boot_supported and still_contact.root_exact
			and still_contact.control_calls == 0,
			"The trailing boot clears a moving landing without lifting the stationary support or reversing its knee.")
		check_landing_recovery_profile()
		check_run_stop_contact()
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
	verify(absf(angle_difference(body.rotation.y, PI / 2.0)) < 0.00001,
		"The first confirmed step faces sideways travel immediately after rest.")
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
	for n in range(4):
		host.state.actors.P.position[2] += 0.05
		presenter.refresh(1.0 / 60.0)
	verify(absf(angle_difference(body.rotation.y, 0.0)) < 0.11
		and is_equal_approx(p.position.z, host.state.actors.P.position[2]),
		"A confirmed right-angle running turn follows travel within four frames at the exact actor root.")
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
		host.state.actors.P.position[0] -= 0.05
		presenter.refresh(1.0 / 60.0)
		verify(absf(angle_difference(body.rotation.y, -PI / 2.0)) < 0.00001
			and is_equal_approx(p.position.x, host.state.actors.P.position[0]),
			"The first opposite step after landing faces confirmed travel without moving the actor root.")
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
		var short_fall_air: float = presenter.motion.P.air
		presenter.refresh(1.0 / 60.0)
		verify(presenter.motion.P.mode == "landing" and is_equal_approx(p.position.y, 0.65)
			and presenter.motion.P.air <= short_fall_air,
			"A short confirmed drop can land on a new height without regaining a full airborne pose.")
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
