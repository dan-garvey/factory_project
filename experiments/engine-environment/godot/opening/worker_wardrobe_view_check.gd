extends SceneTree
## Passive character views. This fixture never sends input or moves an actor.

const Presenter = preload("res://opening/character_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")

class HostFixture:
	extends Node3D
	var state := {"context": "worker-wardrobe-view", "actors": {
		"P": {"ready": true, "position": [0.0, Geometry.CAPSULE_HEIGHT / 2.0, 0.0]},
		"Q": {"ready": true, "position": [0.95, Geometry.CAPSULE_HEIGHT / 2.0, 0.0]}}}
	var client := "P"
	var explanation_open := false
	var distance := 2.0
	var camera: Camera3D
	var focus := Vector3.ZERO
	var control_calls := 0
	var safety_release_calls := 0
	func _update_camera() -> void:
		pass
	func _can_control_character() -> bool:
		return false
	func _send_character_input(_direction: Vector2, _jump: bool) -> void:
		control_calls += 1
	func _release_character_input() -> void:
		# A passive window can lose focus while frames render. Releasing held
		# controls is safe and distinct from sending character movement.
		safety_release_calls += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var prefix := ""
	var harvest_reach := "--harvest-reach" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			prefix = argument.trim_prefix("--capture-prefix=")
	if prefix.is_empty() or not prefix.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("A passive renderer and absolute capture prefix are required.")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.18, 0.21, 0.24)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.85, 0.9)
	environment.environment.ambient_light_energy = 0.8
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.5
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.0, 7.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.42, 0.46, 0.41)
	ground.material_override = ground_material
	stage.add_child(ground)
	var host := HostFixture.new()
	stage.add_child(host)
	var presenter := Presenter.new()
	presenter.configure(host)
	presenter.set_process(false)
	presenter.set_physics_process(false)
	stage.add_child(presenter)
	var worker: Node3D = presenter.views.get("P")
	if worker == null or worker.get_node("BodyView").get_meta("source", "") \
			!= "Microsoft Rocketbox Female_Adult_04" or host.control_calls != 0:
		push_error("The passive view did not load the sourced worker without input.")
		quit(1)
		return
	var body: Node3D = worker.get_node("BodyView")
	var skeleton: Skeleton3D = body.get_node(body.get_meta("skeleton_path"))
	if skeleton.get_node_or_null("FieldSuitMark") != null:
		push_error("The loose provisional suit mark must not appear beside the worker.")
		quit(1)
		return
	var remote_worker: Node3D = presenter.views.get("Q")
	if remote_worker == null or remote_worker.get_meta("actor", "") != "Q" or \
			remote_worker.get_node("BodyView").get_meta("source", "") != "Microsoft Rocketbox Male_Adult_05":
		push_error("The passive shared view must retain the second worker's identity and appearance.")
		quit(1)
		return
	for actor in ["P", "Q"]:
		if not presenter.views[actor].find_children("*", "Label3D", true, false).is_empty():
			push_error("Neither worker may carry a floating world-space name label: " + actor)
			quit(1)
			return
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.fov = 38.0
	camera.current = true
	host.camera = camera
	if harvest_reach:
		host.state.options = {"native": true}
		host.state.hand_sources = {"ore": {"kind": "ore_deposit",
			"position": [0.0, 0.825, -2.3],
			"contact_bounds": [[-0.25, 0.2, -3.44], [0.25, 1.1, -1.16]],
			"initial": 4096, "remaining": 4096}}
		host.state.manual_cuts = {"P": {"target": "ore", "remaining_ticks": 15,
			"interrupted": false}}
		var rock := MeshInstance3D.new()
		rock.mesh = load("res://opening/assets/mineral-outcrop/boulder.res")
		rock.position = Vector3(0.0, 0.3, -2.3)
		stage.add_child(rock)
		for spec in [["third-person", Vector3(-2.2, 1.7, 2.3), Vector3(0.0, 0.9, -1.2)],
				["first-person", Vector3(0.0, 1.55, 0.0), Vector3(0.0, 0.825, -2.3)]]:
			host.distance = 0.0 if spec[0] == "first-person" else 2.0
			camera.position = spec[1]
			camera.look_at(spec[2])
			presenter.refresh(0.25)
			await process_frame
			await RenderingServer.frame_post_draw
			var path: String = prefix + "-" + spec[0] + ".png"
			if FileAccess.file_exists(path) or viewport.get_texture().get_image().save_png(path) != OK:
				push_error("The passive harvest view could not retain its image: " + path)
				quit(1)
				return
		if presenter.eye_multitool == null or \
				presenter.eye_multitool.position.distance_to(Presenter.EYE_MULTITOOL_REST) > 0.46 or \
				host.control_calls != 0:
			push_error("A distant source pulled the first-person hand away or sent actor input.")
			quit(1)
			return
		print(JSON.stringify({"status": "pass", "captures": [prefix + "-third-person.png",
			prefix + "-first-person.png"], "input_calls": host.control_calls,
			"native_actor": "not_started", "human_view": "unassessed"}))
		viewport.free()
		call_deferred("quit", 0)
		return
	for spec in [["front", Vector3(0.0, 1.15, 4.1)],
			["quarter", Vector3(2.6, 1.3, 3.3)],
			["distant", Vector3(6.0, 3.5, 8.0)]]:
		camera.position = spec[1]
		camera.look_at(Vector3(0.0, 0.9, 0.0))
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = prefix + "-" + spec[0] + ".png"
		if FileAccess.file_exists(path) or viewport.get_texture().get_image().save_png(path) != OK:
			push_error("The passive view could not retain its image: " + path)
			quit(1)
			return
	if host.control_calls != 0:
		push_error("The passive fixture unexpectedly issued an input command.")
		quit(1)
		return
	var control_calls := host.control_calls
	var safety_release_calls := host.safety_release_calls
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.free()
	print(JSON.stringify({"status": "pass", "source": "Microsoft Rocketbox Female_Adult_04",
		"field_mark": "removed",
		"remote_actor": "Q", "remote_world_label": "absent",
		"captures": [prefix + "-front.png", prefix + "-quarter.png", prefix + "-distant.png"],
		"input_calls": control_calls, "safety_release_calls": safety_release_calls,
		"native_actor": "not_started", "human_view": "unassessed"}))
	call_deferred("quit", 0)
