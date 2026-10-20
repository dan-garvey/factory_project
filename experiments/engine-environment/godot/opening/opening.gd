extends Node3D
## Input and presentation only. Every material/build mutation goes to model.gd.

const Model = preload("res://model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
const ActorWorld = preload("res://opening/actor_world.gd")
const CharacterPresenter = preload("res://opening/character_presenter.gd")
const Geometry = preload("res://opening/site_geometry.gd")
const STEP_SECONDS := 0.45
const PITCH := Geometry.PITCH
const NAMES := {"collector": "Collector", "belt": "Belt", "processor": "Press", "wheel": "Waterwheel"}
const COLORS := {"collector": Color("d6a34d"), "belt": Color("538e88"), "processor": Color("bd7054"), "wheel": Color("8b9caa")}
const LESSONS := [
	["01  /  BUILD THE PATH", "Place a collector, a belt and a press in a row. Material ports face along the brass arrow. Each placed machine uses a part from your carried kit."],
	["02  /  CONNECT THE DRIVE", "Place the waterwheel beside your line. Choose Drive link, then click two neighboring machines. Carry its rotation through the whole line; the stream supplies motion without fuel."],
	["03  /  FOLLOW ONE BLANK", "The collector removes a blank from the finite seam. The belt carries it to the press. Advance the example one tick at a time. The held blank stays in the press until its plate can leave."],
	["04  /  MAKE ROOM", "A full press outlet holds up the line. Collect the example plate below: the held blank finishes without being lost. Stopping the drive keeps the parts and unfinished work where they are."]
]

var model
var legacy_fixture := false
var actor_world
var character_presenter
var actor_label: Label
var startup_save_pending := false
var startup_save_scheduled := false
var auto_advance := true
var client := "P"
var request_sequence := 0
# A fresh view must not restart request IDs into a restored authority's cache.
# This nonce identifies submitted intents; it never randomizes simulation rules.
var request_namespace := "opening-" + Crypto.new().generate_random_bytes(16).hex_encode() + "-"
var save_slot := ""
var save_slot_ready := false
var save_slot_owned := false
var last_save_result: Dictionary = {}
var last_load_result: Dictionary = {}
var startup_resume_checkpoint: Dictionary = {}
var mode := "collector"
var pending_link := ""
var selected := ""
var goal_confirmed := false
var explanation_open := false
var lesson_index := 0
var example_presenter
var lesson_next: Button
var lesson_previous: Button
var lesson_return: Button
var elapsed := 0.0
var orbit_yaw := 0.68
var orbit_pitch := 0.82
var distance := 18.5
var focus := Vector3(1.3, 0.0, 1.1)
var hover_cell := Vector2i(99, 99)
var visual_revision := -1
var geometry_key := ""
var camera: Camera3D
var machine_root: Node3D
var item_root: Node3D
var hover: MeshInstance3D
var selection_ring: MeshInstance3D
var placement_hint: Node3D
var wheel_rotor: Node3D
var status_label: Label
var stock_label: Label
var parts_label: Label
var goal_label: Label
var power_label: Label
var inspector: Label
var recovery_actions
var confirm_button: Button
var retrieve_button: Button
var power_button: Button
var remove_button: Button
var save_button: Button
var load_button: Button
var lesson_panel: PanelContainer
var lesson_title: Label
var lesson_body: Label
var tool_buttons: Dictionary = {}
var state: Dictionary = {}
var show_all_tools := false
var show_details := false
var all_tools_button: Button
var details_button: Button
var controls_label: Label

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--legacy-fixture":
			legacy_fixture = true
	if model == null:
		model = Model.new(16, "opening-local-1", 1, {"opening": true} if legacy_fixture else {"opening": true, "physical": true})
	if save_slot.is_empty():
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--save-slot="):
				configure_save_slot(argument.trim_prefix("--save-slot="))
	_build_world()
	_build_interface()
	_refresh()
	_message("Build a small line. Choose a part, then click a grid square." if legacy_fixture else "WASD walks. Build nearby; approach the wheel to operate the drive [P].")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-input="):
			var result: Dictionary = _load_worksite(argument.trim_prefix("--resume-input="), true)
			if not result.accepted or not model.projection().options.get("opening", false):
				push_error("Opening resume refused; no fresh-world fallback")
				get_tree().quit(1)
				return
			startup_resume_checkpoint = model.checkpoint()
			if legacy_fixture and not _save_worksite().accepted:
				push_error("Resumed worksite could not publish its new session slot")
				get_tree().quit(1)
				return
			startup_save_pending = not legacy_fixture
			_message("Worksite reopened in this session. Your original save is kept.")
	if not legacy_fixture:
		if not _start_character_world():
			return
		_start_character_presenter()

func _start_character_world() -> bool:
	actor_world = ActorWorld.new()
	actor_world.name = "OpeningActors"
	actor_world.pose_published.connect(_actor_pose)
	actor_world.initialization_failed.connect(_actor_failed)
	var configured: Dictionary = actor_world.configure(model)
	if not configured.accepted:
		actor_world.free()
		actor_world = null
		_actor_failed(client, configured.reason)
		return false
	add_child(actor_world)
	for actor in model.projection().actors:
		if not actor_world.ensure_actor(actor).accepted:
			return false
	return true

func _start_character_presenter() -> void:
	distance = 14.0
	character_presenter = CharacterPresenter.new()
	character_presenter.name = "Characters"
	character_presenter.configure(self)
	add_child(character_presenter)

func _actor_pose(actor: String, sample: Dictionary) -> void:
	var result: Dictionary = model.publish_actor(actor, sample.position, sample.native_epoch)
	if not result.accepted:
		_actor_failed(actor, result.reason)
		return
	_refresh()
	if startup_save_pending and not startup_save_scheduled:
		var all_ready := true
		for current in model.projection().actors.values():
			all_ready = all_ready and current.ready
		if all_ready:
			startup_save_scheduled = true
			call_deferred("_finish_startup_save")

func _finish_startup_save() -> void:
	var saved: Dictionary = _save_worksite()
	if not saved.accepted:
		_actor_failed(client, "resume_save_failed:" + str(saved.reason))
		return
	startup_save_pending = false
	_refresh_ui()
	_message("Worksite reopened in this session. Your original save is kept.")

func _actor_failed(actor: String, reason: String) -> void:
	if model != null and model.has_method("invalidate_actor"):
		model.invalidate_actor(actor)
	push_error("Physical character unavailable for " + actor + ": " + reason)
	get_tree().quit(1)

func _can_control_character() -> bool:
	return not legacy_fixture and not explanation_open and not startup_save_pending and state.get("actors", {}).get(client, {}).get("ready", false)

func _send_character_input(direction: Vector2, jump: bool) -> void:
	if actor_world != null:
		actor_world.set_control(client, direction, jump)

func _release_character_input() -> void:
	if actor_world != null:
		actor_world.release_control(client)

func _release_character_controls() -> void:
	if character_presenter != null:
		character_presenter.release()

func _power_key() -> String:
	return "Space" if legacy_fixture else "P"

func configure_save_slot(path: String) -> void:
	# The launcher supplies a fresh external session directory. One cooperating
	# writer owns this slot; this is not a cross-process filesystem lock.
	save_slot = path
	save_slot_owned = false
	save_slot_ready = path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://") and DirAccess.dir_exists_absolute(path.get_base_dir()) and not _path_exists(path) and not _path_exists(path + ".pending")

func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

func _save_worksite() -> Dictionary:
	if explanation_open or not save_slot_ready:
		last_save_result = {"accepted": false, "reason": "save_unavailable"}
	elif not save_slot_owned and _path_exists(save_slot):
		last_save_result = {"accepted": false, "reason": "existing_destination"}
	else:
		var physical := {"accepted": true}
		if not legacy_fixture:
			physical = actor_world.checkpoint_status() if actor_world != null else {"accepted": false, "reason": "actor_unready"}
		last_save_result = Store.write(model, save_slot) if physical.accepted else {"accepted": false, "reason": physical.reason}
		if not legacy_fixture:
			last_save_result["native_preflight"] = physical.duplicate(true)
	if last_save_result.accepted:
		save_slot_owned = true
		_message("Worksite saved. Load returns to this moment." if legacy_fixture else "Worksite saved. Reopen this save through the launcher in a new session.")
	else:
		_message("Save unavailable. Your current worksite and previous save are kept.", true)
	_refresh_ui()
	return last_save_result

func _load_worksite(path: String = "", startup_resume := false) -> Dictionary:
	if not legacy_fixture and not startup_resume:
		last_load_result = {"accepted": false, "reason": "load_requires_restart"}
		_message("Reopen the saved worksite through the launcher in a new session. The live worksite is kept.", true)
		return last_load_result
	if explanation_open or not save_slot_ready:
		last_load_result = {"accepted": false, "reason": "load_unavailable"}
	else:
		last_load_result = Store.read_into(model, save_slot if path.is_empty() else path)
	if last_load_result.accepted:
		# Restored revision/order may be lower or equal. Invalidate presentation
		# caches instead of altering the restored authoritative version.
		selected = ""
		pending_link = ""
		geometry_key = ""
		visual_revision = -1
		elapsed = 0.0
		request_sequence = 0
		request_namespace = "opening-" + Crypto.new().generate_random_bytes(16).hex_encode() + "-"
		goal_confirmed = false
		_refresh()
		_message("Worksite loaded. Select a machine to continue.")
	else:
		_message("Load refused. Your current worksite and previous save are kept.", true)
	return last_load_result

func issue(action: Dictionary) -> Dictionary:
	if explanation_open:
		return {"accepted": false, "reason": "explanation_open"}
	if startup_save_pending:
		_message("Finishing the saved worksite's opening. Wait a moment.")
		return {"accepted": false, "reason": "worksite_starting"}
	if not legacy_fixture and actor_world != null:
		for actor in model.projection().actors:
			actor_world.ensure_actor(actor)
	request_sequence += 1
	var intent: Dictionary = action.duplicate(true)
	intent.merge({"context": model.projection().context, "client": client,
		"request": request_namespace + str(request_sequence)}, true)
	var outcome: Dictionary = model.command(intent)
	if not legacy_fixture and actor_world != null:
		actor_world.sync_topology()
	if outcome.accepted:
		_message({"place": "Placed. Parts stay with this worksite.",
			"connect": "Material path connected.", "connect_drive": "Drive shaft connected.",
			"retrieve": "Plate collected.", "set_power": "Drive updated.",
			"remove": "Part returned to your carried kit.",
			"disconnect": "Material connection removed.",
			"disconnect_drive": "Drive shaft returned."}.get(action.action, "Done."))
	else:
		_message({"occupied": "That square is occupied.", "no_part": "That part is already placed.",
			"ports_not_adjacent": "Connect neighboring ports, following the arrow.",
			"missing_entity": "Choose a placed machine at each end.",
			"already_connected": "Those ports are already connected.",
			"unavailable_output": "There is no finished plate to collect yet.",
			"out_of_reach": "Move closer to the target before building or interacting.",
			"actor_unready": "Your character is not ready yet. Wait a moment.",
			"actor_occupied": "A character is in that square. Move clear before placing the machine.",
			"powered": "Stop the drive before changing the machinery.",
			"not_stopped": "Stop the drive before changing the machinery.",
			"held_stock": "Retrieve the material before removing this machine.",
			"contains_stock": "Retrieve the material before removing this machine.",
			"not_at_stream": "Place the waterwheel beside the stream bank.",
			"not_at_seam": "Place the collector on the brass seam strip.",
			"no_shaft": "All carried shafts are in use."}.get(outcome.reason, "That action is unavailable here."), true)
	_refresh()
	return outcome

func _process(delta: float) -> void:
	if auto_advance:
		elapsed += delta
		while elapsed >= STEP_SECONDS:
			elapsed -= STEP_SECONDS
			model.advance()
		_refresh()
	if wheel_rotor != null and state.get("powered", false):
		wheel_rotor.rotation.z += delta * 0.8
	if explanation_open:
		example_presenter.pan(delta)
		return
	_update_camera()
	if not legacy_fixture:
		return
	var pan := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		focus += Vector3(pan.x, 0, pan.y) * delta * 4.0
		focus.x = clampf(focus.x, -4, 6)
		focus.z = clampf(focus.z, -4, 6)

func _input(event: InputEvent) -> void:
	if explanation_open:
		if event is InputEventKey:
			if event.pressed and not event.echo:
				match event.keycode:
					KEY_H, KEY_ESCAPE: _toggle_explanation()
					KEY_RIGHT: _set_lesson(lesson_index + 1)
					KEY_LEFT: _set_lesson(lesson_index - 1)
					KEY_HOME: example_presenter.recenter()
			get_viewport().set_input_as_handled()
		elif example_presenter.handle_pointer(event):
			get_viewport().set_input_as_handled()
		return
	# Consume both edges of global shortcuts so a
	# previously focused GUI button cannot also activate on the release.
	if event is InputEventKey and (event.keycode in [KEY_F5, KEY_F9] or event.keycode == (KEY_SPACE if legacy_fixture else KEY_P)):
		if event.pressed and not event.echo and not explanation_open:
			match event.keycode:
				KEY_SPACE, KEY_P: _toggle_power()
				KEY_F5:
					if not startup_save_pending:
						_save_worksite()
				KEY_F9: _load_worksite()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if explanation_open:
		return
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			orbit_yaw -= event.relative.x * 0.007
			orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.005, 0.35, 1.25)
		else:
			hover_cell = _screen_cell(event.position)
			_update_cursor()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(10 if legacy_fixture else 8, distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(28 if legacy_fixture else 24, distance + 1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_world_click(_screen_cell(event.position), _screen_entity(event.position))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _select_tool("collector")
			KEY_2: _select_tool("belt")
			KEY_3: _select_tool("processor")
			KEY_4: _select_tool("wheel")
			KEY_F: _select_tool("flow")
			KEY_G: _select_tool("drive")
			KEY_I, KEY_ESCAPE: _select_tool("inspect")
			KEY_R: _retrieve()
			KEY_H: _toggle_explanation()
			KEY_HOME:
				if legacy_fixture:
					focus = Vector3(1.3, 0, 1.1)
				distance = 18.5 if legacy_fixture else 14.0
	_update_camera()

func _select_tool(tool: String) -> void:
	if explanation_open:
		return
	mode = tool
	pending_link = ""
	_update_cursor()
	_refresh_ui()
	_message({"flow": "Click the upstream machine, then its neighbor toward the brass arrow.",
		"drive": "Click two neighboring machines to connect a drive shaft.",
		"inspect": "Click a machine to inspect it or collect its finished work.",
		"collector": "Place the collector on the brass seam strip.",
		"wheel": "Place the waterwheel on the stream bank beside the seam."}.get(tool,
		"Place %s on an empty grid square." % NAMES.get(tool, tool)))

func _world_click(cell: Vector2i, entity_id: String = "") -> void:
	if explanation_open:
		return
	if state.entities.has(entity_id):
		var actual: Array = state.entities[entity_id].cell
		cell = Vector2i(actual[0], actual[1])
	if cell.x < -2 or cell.x > 4 or cell.y < -2 or cell.y > 4:
		return
	if mode == "inspect":
		selected = entity_id if not entity_id.is_empty() else _entity_at_cell(cell)
		_refresh_ui()
	elif mode in ["flow", "drive"]:
		var target := entity_id if not entity_id.is_empty() else _entity_at_cell(cell)
		if target.is_empty():
			_message("Choose a placed machine.", true)
			return
		selected = target
		if pending_link.is_empty():
			pending_link = target
			_message("Now choose the neighboring machine.")
		else:
			issue({"action": "connect" if mode == "flow" else "connect_drive", "from": pending_link, "to": target})
			pending_link = ""
	else:
		var outcome := issue({"action": "place", "kind": mode, "cell": [cell.x, cell.y]})
		if outcome.accepted:
			selected = outcome.entity
	_refresh_ui()

func _retrieve() -> void:
	var target := selected
	if target.is_empty() or not state.entities.has(target) or state.entities[target].kind != "processor":
		_message("Select the press to collect its finished plate.", true)
		return
	issue({"action": "retrieve", "amount": 1, "entity": target})

func _toggle_power() -> void:
	issue({"action": "set_power", "active": not state.get("power_enabled", true)})

func _remove_selected() -> void:
	if not selected.is_empty():
		var outcome := issue({"action": "remove", "entity": selected})
		if outcome.accepted:
			selected = ""
			_refresh_ui()

func _confirm_goal() -> void:
	if explanation_open:
		return
	if int(model.projection().inventories.get(client, 0)) >= 4:
		goal_confirmed = true
		_message("Four plates ready. Your first production line is working.")
		_refresh_ui()

func _toggle_explanation() -> void:
	explanation_open = not explanation_open
	lesson_panel.visible = explanation_open
	if explanation_open:
		_release_character_controls()
		if example_presenter == null:
			# Lazy loading avoids a static cycle with the geometry-only subclass.
			example_presenter = load("res://opening/example_presenter.gd").new()
			lesson_panel.get_parent().add_child(example_presenter)
			# Set the far anchor first so the near anchor is not clamped.
			example_presenter.set_anchor_and_offset(SIDE_RIGHT, 0.5, 340)
			example_presenter.set_anchor_and_offset(SIDE_LEFT, 0.5, -330)
			example_presenter.set_anchor_and_offset(SIDE_TOP, 0.0, 226)
			example_presenter.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -128)
		example_presenter.show()
		example_presenter.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		example_presenter.world.set_process(true)
		_set_lesson(0)
	else:
		example_presenter.hide()
		example_presenter.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		example_presenter.world.set_process(false)
	_update_cursor()
	_refresh_ui()

func _set_lesson(index: int) -> void:
	lesson_index = posmod(index, LESSONS.size())
	lesson_title.text = LESSONS[lesson_index][0]
	lesson_body.text = LESSONS[lesson_index][1]
	if example_presenter != null:
		example_presenter.set_lesson(lesson_index)

func _screen_cell(screen: Vector2) -> Vector2i:
	var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null:
		return Vector2i(99, 99)
	return Vector2i(roundi(point.x / PITCH), roundi(point.z / PITCH))

func _screen_entity(screen: Vector2) -> String:
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 80)
	query.collision_mask = Geometry.PICK_LAYER
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return str(hit.collider.get_meta("entity", "")) if not hit.is_empty() else ""

func _entity_at_cell(cell: Vector2i) -> String:
	for entity_id in state.get("entities", {}):
		if state.entities[entity_id].cell == [cell.x, cell.y]:
			return entity_id
	return ""

func _cell_position(cell: Array) -> Vector3:
	return Vector3(cell[0] * PITCH, 0, cell[1] * PITCH)

func _update_camera() -> void:
	camera.position = focus + Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), cos(orbit_yaw) * cos(orbit_pitch)) * distance
	camera.look_at(focus)

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("536f86")
	sky_material.sky_horizon_color = Color("d8cbb2")
	sky_material.ground_bottom_color = Color("394641")
	sky_material.ground_horizon_color = Color("b5b8a1")
	var sky := Sky.new()
	sky.sky_material = sky_material
	settings.background_mode = Environment.BG_SKY
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy = 0.5
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_color = Color("fff1d6")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)
	# Keep the back of machinery readable without adding a second shadow map.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-32, 135, 0)
	fill.light_color = Color("b9d2ea")
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	add_child(fill)
	if not legacy_fixture:
		# Presentation extent only. ActorWorld owns the native floor, whose
		# backend-specific extent is recorded separately in its diagnostics.
		var terrain := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(Geometry.DISPLAY_TERRAIN_SIZE, Geometry.DISPLAY_TERRAIN_SIZE)
		terrain.mesh = plane
		terrain.position.y = Geometry.GROUND_HEIGHT - 0.01
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("394641")
		material.roughness = 1.0
		terrain.material_override = material
		add_child(terrain)
	_box(self, Vector3(1.65, -0.55, 1.65), Vector3(13.4, 0.8, 13.4), Color("394641"))
	for x in range(-2, 5):
		for z in range(-2, 5):
			var tint := Color("57605a") if (x + z) % 2 == 0 else Color("505a55")
			_box(self, Vector3(x * PITCH, -0.08, z * PITCH), Vector3(PITCH - 0.035, 0.12, PITCH - 0.035), tint)
	_box(self, Vector3(-2.7, 0.0, 1.65), Vector3(1.2, 0.06, 13.4), Color("396c76"))
	for z in range(-3, 6):
		_box(self, Vector3(-2.7, 0.04, z * 1.3), Vector3(0.85, 0.018, 0.035), Color("72a5a7"))
	_box(self, Vector3(0, 0.005, 1.65), Vector3(0.12, 0.035, 13.4), Color("a58c59"))
	var arrow := _text(self, "MATERIAL  →", Vector3(1.6, 0.08, -4.15), Color("e4bc70"), 0.005)
	arrow.rotation_degrees.x = -90
	for z in [-1.8, -1.4, -1.0]:
		_box(self, Vector3(-3.75, 0.02, z), Vector3(0.12, 0.08, 0.22), Color("be9957"))
	machine_root = Node3D.new()
	add_child(machine_root)
	item_root = Node3D.new()
	add_child(item_root)
	hover = _box(self, Vector3.ZERO, Vector3(1.5, 0.035, 1.5), Color(0.85, 0.75, 0.45, 0.45))
	hover.visible = false
	selection_ring = _box(self, Vector3.ZERO, Vector3(1.54, 0.035, 1.54), Color("c9bb86"))
	selection_ring.visible = false
	_build_placement_hint()
	camera = Camera3D.new()
	camera.fov = 45
	camera.near = 0.1
	camera.far = 100
	add_child(camera)
	camera.make_current()
	_update_camera()

func _box(parent: Node, at: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = dimensions
	mesh.mesh = shape
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if color.a < 1:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _cylinder(parent: Node, at: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 16
	mesh.mesh = shape
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _text(parent: Node, words: String, at: Vector3, color: Color, pixel_size: float = 0.007) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.position = at
	label.font_size = 36
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label

func _bar(parent: Node, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	if a.distance_to(b) < 0.01:
		return
	var bar := _box(parent, (a + b) / 2, Vector3(width, width, a.distance_to(b)), color)
	bar.look_at(b)

func _route_segment(parent: Node3D, part_name: String, a: Vector3, b: Vector3,
		width: float, color: Color) -> MeshInstance3D:
	var offset := b - a
	var part := _box(parent, (a + b) / 2.0, Vector3(width, width, offset.length()), color)
	part.name = part_name
	# Material routes join equal-height grid anchors. Local rotation keeps this
	# mesh construction independent of a camera or an attached scene tree.
	part.rotation.y = atan2(offset.x, offset.z)
	return part

func _material_route(parent: Node3D, a: Vector3, b: Vector3) -> Node3D:
	var route := Node3D.new()
	route.name = "MaterialRoute"
	parent.add_child(route)
	if a.distance_to(b) < 0.01:
		return route
	var direction := (b - a).normalized()
	var start := a + direction * 0.55 + Vector3.UP * 0.45
	var finish := b - direction * 0.55 + Vector3.UP * 0.45
	_route_segment(route, "Rail", start, finish, 0.17, Color("929e91"))
	var side := Vector3(-direction.z, 0, direction.x)
	var tip := start.lerp(finish, 0.7) + Vector3.UP * 0.115
	_route_segment(route, "ArrowLeft", tip - direction * 0.15 + side * 0.1, tip,
		0.035, Color("e2c48b"))
	_route_segment(route, "ArrowRight", tip - direction * 0.15 - side * 0.1, tip,
		0.035, Color("e2c48b"))
	return route

func _machine_box(parent: Node3D, part_name: String, at: Vector3, dimensions: Vector3,
		color: Color, metal: float = 0.55, roughness: float = 0.5) -> MeshInstance3D:
	var part := _box(parent, at, dimensions, color)
	part.name = part_name
	var finish := part.material_override as StandardMaterial3D
	finish.metallic = metal
	finish.roughness = roughness
	return part

func _machine_cylinder(parent: Node3D, part_name: String, at: Vector3, radius: float,
		height: float, color: Color, orientation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var part := _cylinder(parent, at, radius, height, color)
	part.name = part_name
	part.rotation = orientation
	var finish := part.material_override as StandardMaterial3D
	finish.metallic = 0.75
	finish.roughness = 0.4
	return part

func _collector_visual(anchor: Node3D) -> void:
	var frame: Color = COLORS.collector
	var steel := Color("a6b4af")
	_machine_box(anchor, "StockBed", Vector3(0, 0.51, 0), Vector3(1.25, 0.1, 0.67), steel)
	_machine_box(anchor, "BackHousing", Vector3(-0.22, 0.66, -0.44), Vector3(0.84, 0.78, 0.14), frame)
	for x in [-0.57, 0.18]:
		_machine_box(anchor, "HeadSupport", Vector3(x, 0.87, -0.38), Vector3(0.12, 1.1, 0.14), frame)
	_machine_box(anchor, "HeadCover", Vector3(-0.22, 1.42, -0.25), Vector3(0.86, 0.12, 0.64), frame)
	_machine_cylinder(anchor, "CutterDrum", Vector3(-0.22, 1.1, -0.19), 0.24, 0.34,
		Color("465a60"), Vector3(PI / 2, 0, 0))
	_machine_cylinder(anchor, "CutterHub", Vector3(-0.22, 1.1, 0.01), 0.085, 0.08,
		steel, Vector3(PI / 2, 0, 0))
	for z in [-0.37, 0.37]:
		_machine_box(anchor, "StockGuide", Vector3(0.05, 0.6, z), Vector3(1.15, 0.08, 0.06), frame)
	_machine_cylinder(anchor, "DriveStub", Vector3(0, 0.35, 0.55), 0.085, 0.18,
		Color("b87945"), Vector3(PI / 2, 0, 0))

func _belt_visual(anchor: Node3D) -> void:
	var frame: Color = COLORS.belt
	for x in [-0.52, 0.52]:
		for z in [-0.26, 0.26]:
			_machine_box(anchor, "ConveyorLeg", Vector3(x, 0.315, z), Vector3(0.09, 0.21, 0.09), frame)
	_machine_box(anchor, "ConveyorBand", Vector3(0, 0.465, 0), Vector3(1.38, 0.12, 0.64), Color("28383d"), 0.05, 0.9)
	for n in range(-3, 4):
		_machine_box(anchor, "ConveyorCleat", Vector3(n * 0.18, 0.54, 0), Vector3(0.06, 0.03, 0.62), Color("b2c5b7"), 0.3)
	for z in [-0.36, 0.36]:
		_machine_box(anchor, "ConveyorRail", Vector3(0, 0.57, z), Vector3(1.38, 0.08, 0.05), frame)
	for x in [-0.57, 0.57]:
		_machine_cylinder(anchor, "ConveyorRoller", Vector3(x, 0.465, 0), 0.1, 0.7,
			Color("5b7275"), Vector3(PI / 2, 0, 0))
	_machine_cylinder(anchor, "DriveStub", Vector3(0, 0.35, 0.55), 0.085, 0.18,
		Color("b87945"), Vector3(PI / 2, 0, 0))

func _press_visual(anchor: Node3D) -> void:
	var frame: Color = COLORS.processor
	var steel := Color("a6b4af")
	var dark := Color("29393f")
	for x in [-0.48, 0.48]:
		_machine_box(anchor, "PressUpright", Vector3(x, 0.82, -0.38), Vector3(0.15, 1.24, 0.28), frame)
	_machine_box(anchor, "PressBridge", Vector3(0, 1.5, -0.3), Vector3(1.2, 0.2, 0.36), frame)
	_machine_box(anchor, "Anvil", Vector3(0, 0.46, 0.05), Vector3(0.7, 0.16, 0.63), dark)
	_machine_box(anchor, "ToolHead", Vector3(0, 0.84, 0), Vector3(0.56, 0.17, 0.55), steel, 0.85, 0.32)
	_machine_cylinder(anchor, "Piston", Vector3(0, 1.14, -0.08), 0.075, 0.45, steel)
	for x in [-0.34, 0.34]:
		_machine_cylinder(anchor, "ToolGuide", Vector3(x, 1.06, -0.19), 0.04, 0.6, Color("b87945"))
	_machine_box(anchor, "OutputTray", Vector3(0.46, 0.33, 0.15), Vector3(0.48, 0.05, 0.58), Color("aaa993"))
	_machine_cylinder(anchor, "DriveStub", Vector3(0, 0.35, 0.55), 0.085, 0.18,
		Color("b87945"), Vector3(PI / 2, 0, 0))
	for x in [-0.48, 0.48]:
		_machine_cylinder(anchor, "BridgeBolt", Vector3(x, 1.5, -0.1075), 0.035, 0.025,
			steel, Vector3(PI / 2, 0, 0))

func _wheel_visual(anchor: Node3D) -> void:
	var frame := Color("465a60")
	var wood := Color("b48c52")
	for z in [-0.42, 0.42]:
		_machine_box(anchor, "WheelStand", Vector3(0, 0.51, z), Vector3(0.16, 0.54, 0.16), frame)
		_machine_cylinder(anchor, "AxleBearing", Vector3(0, 0.78, z), 0.145, 0.18,
			Color("a6b4af"), Vector3(PI / 2, 0, 0))
	wheel_rotor = Node3D.new()
	wheel_rotor.name = "WheelRotor"
	wheel_rotor.position = Vector3(0, 0.78, 0)
	anchor.add_child(wheel_rotor)
	# An open rim exposes the spokes. This is the existing decorative rotor;
	# no rendered contact or mesh position supplies a drive relationship.
	for n in range(12):
		var angle := n * TAU / 12.0
		var radial := Vector3(cos(angle), sin(angle), 0)
		for z in [-0.15, 0.15]:
			var rim := _machine_box(wheel_rotor, "WheelRim", radial * 0.55 + Vector3(0, 0, z),
				Vector3(0.075, 0.3, 0.06), frame)
			rim.rotation.z = angle
		var paddle := _machine_box(wheel_rotor, "WheelPaddle", radial * 0.62,
			Vector3(0.14, 0.16, 0.28), wood, 0.05, 0.88)
		paddle.rotation.z = angle
	for n in range(3):
		var spoke := _machine_box(wheel_rotor, "WheelSpoke", Vector3.ZERO,
			Vector3(0.065, 1.0, 0.085), wood, 0.05, 0.88)
		spoke.rotation.z = n * PI / 3.0
	_machine_cylinder(wheel_rotor, "WheelHub", Vector3.ZERO, 0.13, 0.45,
		Color("b87945"), Vector3(PI / 2, 0, 0))

func _rebuild_machines() -> void:
	for child in machine_root.get_children():
		child.free()
	wheel_rotor = null
	for entity_id in state.entities:
		var entity: Dictionary = state.entities[entity_id]
		var kind: String = entity.kind
		var anchor := Node3D.new()
		anchor.position = _cell_position(entity.cell)
		machine_root.add_child(anchor)
		_machine_box(anchor, "Plinth", Vector3(0, 0.12, 0), Vector3(1.35, 0.24, 1.35), Color("273c41"))
		match kind:
			"collector":
				_collector_visual(anchor)
			"belt":
				_belt_visual(anchor)
			"processor":
				_press_visual(anchor)
			"wheel":
				_wheel_visual(anchor)
		var body := StaticBody3D.new()
		body.collision_layer = Geometry.PICK_LAYER
		body.collision_mask = 0
		body.set_meta("entity", entity_id)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(Geometry.MACHINE_SIZE[0], Geometry.MACHINE_SIZE[1], Geometry.MACHINE_SIZE[2])
		collider.shape = shape
		collider.position.y = Geometry.MACHINE_CENTER_HEIGHT
		body.add_child(collider)
		anchor.add_child(body)
		_text(anchor, NAMES.get(kind, kind).to_upper(), Vector3(0, 1.9, 0), Color("f2e5c5"))
	for pair in state.links:
		if state.entities.has(pair[0]) and state.entities.has(pair[1]):
			_material_route(machine_root, _cell_position(state.entities[pair[0]].cell),
				_cell_position(state.entities[pair[1]].cell))
	for pair in state.get("drive_links", []):
		if state.entities.has(pair[0]) and state.entities.has(pair[1]):
			_bar(machine_root, _cell_position(state.entities[pair[0]].cell) + Vector3(0, 0.35, 0.55),
				_cell_position(state.entities[pair[1]].cell) + Vector3(0, 0.35, 0.55), 0.09, Color("d1b56e"))

func _redraw_items() -> void:
	for child in item_root.get_children():
		child.free()
	for entity_id in state.entities:
		var entity: Dictionary = state.entities[entity_id]
		var pos := _cell_position(entity.cell)
		var amount := 0
		if entity.kind in ["collector", "belt"]:
			amount = int(state.stock.get(entity.kind, 0))
		elif entity.kind == "processor":
			amount = int(state.stock.held) + int(state.stock.input)
		for n in range(amount):
			_box(item_root, pos + Vector3(-0.17 + n * 0.32, 0.65, 0), Vector3(0.27, 0.18, 0.36), Color("e2c48b"))
		if entity.kind == "processor" and state.stock.output > 0:
			_box(item_root, pos + Vector3(0.46, 0.39, 0.15), Vector3(0.44, 0.07, 0.53), Color("e4d8b3"))
	# The finite seam stays in its marked column when machinery is rebuilt.
	for n in range(mini(16, int(state.stock.source))):
		_box(item_root, Vector3(-0.16 + (n % 2) * 0.32, 0.11, -2.9 + int(n / 2.0) * 1.15),
			Vector3(0.2, 0.18, 0.28), Color("a58c59"))

func _refresh() -> void:
	state = model.projection()
	if actor_world != null:
		actor_world.sync_topology()
	var next_key := JSON.stringify([state.entities, state.links, state.get("drive_links", [])])
	if next_key != geometry_key:
		geometry_key = next_key
		_rebuild_machines()
	if int(state.revision) != visual_revision:
		visual_revision = int(state.revision)
		_redraw_items()
	if character_presenter != null:
		character_presenter.refresh()
	_refresh_ui()

func _display_parts() -> Dictionary:
	if state.get("options", {}).get("native", false):
		return state.get("part_kits", {}).get(client, {})
	return state.get("parts", {})

func _parts_are_shared() -> bool:
	return false

func _refresh_ui() -> void:
	if stock_label == null:
		return
	var inventory := int(state.inventories.get(client, 0))
	var parts := _display_parts()
	var part_scope := "shared" if _parts_are_shared() else "carried"
	parts_label.text = "BUILD FROM SHARED KIT" if _parts_are_shared() else "BUILD FROM CARRIED PARTS"
	goal_label.text = "FIRST SHIFT\nBring back 4 plates\n%d / 4 collected" % inventory
	confirm_button.disabled = inventory < 4 or goal_confirmed or explanation_open
	confirm_button.text = "Objective confirmed" if goal_confirmed else "Confirm four plates"
	stock_label.text = "SEAM  %d blanks\nIN THE LINE  %d blanks\nPRESS OUTLET  %d plate" % [state.stock.source,
		state.stock.collector + state.stock.belt + state.stock.input + state.stock.held, state.stock.output]
	power_label.text = "DRIVE RUNNING" if state.get("powered", false) else "DRIVE SWITCHED OFF" if not state.get("power_enabled", true) else "DRIVE NEEDS CONNECTIONS"
	power_button.text = ("Stop drive  [%s]" if state.get("power_enabled", true) else "Start drive  [%s]") % _power_key()
	power_button.tooltip_text = "" if legacy_fixture else "Approach the waterwheel to operate the drive."
	power_button.disabled = explanation_open
	save_button.disabled = explanation_open or not save_slot_ready or startup_save_pending or (not legacy_fixture and not state.get("actors", {}).get(client, {}).get("ready", false))
	load_button.disabled = explanation_open or not save_slot_ready or (legacy_fixture and not save_slot_owned)
	load_button.text = "Load worksite  [F9]" if legacy_fixture else "How to reopen save  [F9]"
	for button in [save_button, load_button]:
		button.tooltip_text = "" if save_slot_ready else "Launch a fresh worksite session to enable saving."
	if actor_label != null:
		actor_label.visible = not legacy_fixture
		actor_label.text = "CHARACTER READY · BUILD NEARBY" if state.get("actors", {}).get(client, {}).get("ready", false) else "CHARACTER STARTING…"
	for tool in tool_buttons:
		var button: Button = tool_buttons[tool]
		button.disabled = explanation_open or (NAMES.has(tool) and not parts.has(tool))
		button.button_pressed = mode == tool
		if NAMES.has(tool):
			button.text = "%s    ·    %d %s" % [NAMES[tool], int(parts.get(tool, 0)), part_scope]
	tool_buttons.drive.text = "Drive link  [G]    ·    %d shafts" % int(parts.get("shaft", 0))
	retrieve_button.disabled = explanation_open or state.stock.output < 1 or not state.entities.has(selected) or state.entities[selected].kind != "processor"
	remove_button.disabled = explanation_open or not state.entities.has(selected)
	selection_ring.visible = state.entities.has(selected)
	if selection_ring.visible:
		selection_ring.position = _cell_position(state.entities[selected].cell) + Vector3(0, 0.02, 0)
		inspector.text = "%s\nSquare %s" % [NAMES.get(state.entities[selected].kind, selected), str(state.entities[selected].cell)]
		if state.entities[selected].kind == "processor":
			inspector.text += "\n%d in · %d held · %d ready" % [state.stock.input, state.stock.held, state.stock.output]
		inspector.text += "\n" + _inspection_hint()
	else:
		inspector.text = "Select a machine to inspect\nor collect its finished work."
	_refresh_guided_tools()
	if recovery_actions != null:
		recovery_actions.refresh()

func _toggle_all_tools() -> void:
	if not explanation_open:
		show_all_tools = not show_all_tools
		_refresh_ui()

func _toggle_details() -> void:
	if not explanation_open:
		show_details = not show_details
		_refresh_ui()

func _refresh_guided_tools(snapshot_ready: bool = true) -> void:
	_refresh_placement_hint(snapshot_ready)
	if legacy_fixture:
		return
	# This is a view of confirmed facts, not persistent progression or admission.
	var kinds: Dictionary = {}
	for entity in state.get("entities", {}).values():
		kinds[String(entity.kind)] = true
	var offered := {"collector": true}
	if not kinds.is_empty():
		offered.inspect = true
	if kinds.has("collector"):
		offered.belt = true
	if kinds.has("belt"):
		offered.processor = true
	if kinds.has("processor"):
		offered.wheel = true
	if (kinds.has("collector") and kinds.has("belt")) or (kinds.has("belt") and kinds.has("processor")):
		offered.flow = true
	if kinds.has("wheel") and kinds.size() > 1:
		offered.drive = true
	var step := _guided_step(kinds)
	for tool in tool_buttons:
		var button: Button = tool_buttons[tool]
		# Keyboard selection stays visible even when it precedes the suggestion.
		button.visible = show_all_tools or offered.has(tool) or mode == tool
		for color_name in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			if tool == step.tool:
				button.add_theme_color_override(color_name, Color("edcc8d"))
			else:
				button.remove_theme_color_override(color_name)
	var inventory := int(state.get("inventories", {}).get(client, 0))
	goal_label.text = "Make 4 plates\n%s\n%d / 4 collected" % [step.text, inventory] if snapshot_ready else "Connect to the worksite."
	confirm_button.visible = snapshot_ready and (inventory >= 4 or goal_confirmed)
	all_tools_button.text = "Guided tools" if show_all_tools else "All tools"
	all_tools_button.disabled = explanation_open or not snapshot_ready
	details_button.text = "Less detail" if show_details else "Details"
	details_button.disabled = explanation_open
	for control in [stock_label, power_label, save_button, load_button]:
		control.visible = show_details
	actor_label.visible = show_details or not state.get("actors", {}).get(client, {}).get("ready", false)
	power_button.visible = show_all_tools or kinds.has("wheel")
	controls_label.text = "WASD walk · Space jump · Right-drag view · Wheel zoom · H help"
	if show_all_tools:
		controls_label.text = "WASD walk · Space jump · P wheel · 1–4 build · F / G links · I inspect · H help"

func _build_placement_hint() -> void:
	placement_hint = Node3D.new()
	placement_hint.name = "GuidedPlacementHint"
	placement_hint.visible = false
	add_child(placement_hint)
	for side in [-0.7, 0.7]:
		_box(placement_hint, Vector3(0, 0, side), Vector3(1.45, 0.035, 0.055), Color("edcc8d"))
		_box(placement_hint, Vector3(side, 0, 0), Vector3(0.055, 0.035, 1.45), Color("edcc8d"))

func _placement_hint_ready() -> bool:
	return _can_control_character()

func _guided_placement_cell() -> Array:
	if legacy_fixture or show_all_tools or explanation_open or not _placement_hint_ready():
		return []
	if not mode in ["belt", "processor"] or int(_display_parts().get(mode, 0)) < 1:
		return []
	# A suggestion for this starter path only, never a placement/reach decision.
	var upstream_kind := "collector" if mode == "belt" else "belt"
	var upstream: Array = []
	var kinds: Dictionary = {}
	for entity in state.get("entities", {}).values():
		kinds[String(entity.kind)] = true
		if entity.kind == upstream_kind:
			if not upstream.is_empty():
				return []
			upstream = entity.cell
	if upstream.is_empty() or _guided_step(kinds).tool != mode:
		return []
	var cell := [int(upstream[0]) + 1, int(upstream[1])]
	if cell[0] < -2 or cell[0] > 4 or cell[1] < -2 or cell[1] > 4:
		return []
	if not _entity_at_cell(Vector2i(cell[0], cell[1])).is_empty():
		return []
	return cell

func _refresh_placement_hint(snapshot_ready: bool = true) -> void:
	if placement_hint == null:
		return
	var cell: Array = _guided_placement_cell() if snapshot_ready else []
	placement_hint.visible = not cell.is_empty()
	if placement_hint.visible:
		placement_hint.position = _cell_position(cell) + Vector3(0, 0.055, 0)

func _guided_step(kinds: Dictionary) -> Dictionary:
	if goal_confirmed:
		return {"text": "Four plates confirmed. Keep building or try another layout.", "tool": "inspect"}
	if int(state.get("inventories", {}).get(client, 0)) >= 4:
		return {"text": "Four plates ready. Confirm when you are ready.", "tool": "inspect"}
	if int(state.get("stock", {}).get("output", 0)) > 0:
		return {"text": "Plate ready. Select the press, then collect [R].", "tool": "inspect"}
	if not kinds.has("collector"):
		return {"text": "Place a collector on the brass strip near you.", "tool": "collector"}
	if not kinds.has("belt"):
		return {"text": "Add a belt beside the collector.", "tool": "belt"}
	if not kinds.has("processor"):
		return {"text": "Add a press at the belt outlet.", "tool": "processor"}
	var material_pairs: Dictionary = {}
	for pair in state.get("links", []):
		var entities: Dictionary = state.get("entities", {})
		if entities.has(pair[0]) and entities.has(pair[1]):
			material_pairs["%s:%s" % [entities[pair[0]].kind, entities[pair[1]].kind]] = true
	if not material_pairs.has("collector:belt") or not material_pairs.has("belt:processor"):
		return {"text": "Connect the material path. Help [H] shows an example.", "tool": "flow"}
	if not kinds.has("wheel"):
		return {"text": "Add a waterwheel by the stream.", "tool": "wheel"}
	if not state.get("power_enabled", true):
		return {"text": "Switch on the drive near the wheel [P].", "tool": "inspect"}
	if not state.get("powered", false):
		return {"text": "Bring power to the line. Help [H] shows the current setup.", "tool": "drive"}
	var stock: Dictionary = state.get("stock", {})
	if int(stock.get("source", 0)) + int(stock.get("collector", 0)) + int(stock.get("belt", 0)) + int(stock.get("input", 0)) + int(stock.get("held", 0)) == 0:
		return {"text": "No blanks remain here. All tools stays available for experimenting.", "tool": "inspect"}
	return {"text": "Follow a blank to the press. Select a machine to inspect it.", "tool": "inspect"}

func _inspection_hint() -> String:
	# Describe confirmed projection facts only. This is advice, never admission
	# or a second power solver; the authority still decides every command.
	var kind: String = state.entities[selected].kind
	if kind == "processor" and state.stock.output > 0:
		return "Outlet full; plate ready.\n[R] collect to make room."
	if not state.get("power_enabled", true):
		return "Drive switched off.\n[%s] enables the drive%s." % [_power_key(), "" if legacy_fixture else " near wheel"]
	if kind == "processor" and state.stock.held > 0 and state.get("powered", false):
		if state.remaining == 0:
			return "Work done; blank retained.\nNext drive tick releases plate."
		return "Working: %d ticks remaining.\nHeld blank stays in the press." % state.remaining
	if kind in ["belt", "processor"] and not _has_material_connection(true):
		return (("Inlet missing. Stop [%s].\n" % _power_key()) if state.get("powered", false) else "No material inlet linked.\n") + "[F] link " + ("Collector → Belt." if kind == "belt" else "Belt → Press.")
	if kind in ["collector", "belt"] and not _has_material_connection(false):
		return (("Outlet missing. Stop [%s].\n" % _power_key()) if state.get("powered", false) else "No material outlet linked.\n") + "[F] link " + ("Collector → Belt." if kind == "collector" else "Belt → Press.")
	if not state.get("powered", false):
		return "Drive needs connections.\n[G] link wheel + all machines."
	if kind == "processor":
		if state.stock.input > 0:
			return "Blank ready to press.\nNext drive tick starts work."
		return "Waiting for a blank.\nInspect the Belt upstream."
	if kind == "collector":
		if state.stock.source == 0:
			return "Seam depleted.\nNo blanks remain to collect."
		if state.stock.collector > 0:
			return "Collector outlet occupied.\nInspect the Belt downstream."
		return "Collecting finite seam blanks.\nBelt takes the next blank."
	if kind == "belt":
		return "Belt carrying a blank.\nInspect the Press downstream." if state.stock.belt > 0 else "Waiting for a blank.\nInspect the Collector upstream."
	return "Wheel powers the whole line.\n[%s] stops it%s." % [_power_key(), " for editing" if legacy_fixture else " from nearby"]

func _has_material_connection(incoming: bool) -> bool:
	for pair in state.links:
		if pair[1 if incoming else 0] == selected:
			return true
	return false

func _update_cursor() -> void:
	hover.visible = hover_cell.x >= -2 and hover_cell.x <= 4 and hover_cell.y >= -2 and hover_cell.y <= 4 and not explanation_open
	if hover.visible:
		hover.position = _cell_position([hover_cell.x, hover_cell.y]) + Vector3(0, 0.03, 0)

func _message(words: String, refused: bool = false) -> void:
	status_label.text = words
	status_label.modulate = Color("e0a880") if refused else Color("d6dfd6")

func _label(parent: Node, words: String, size: int = 16, color: Color = Color("dde5d9")) -> Label:
	var label := Label.new()
	label.text = words
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, words: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size.y = 37
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _panel(parent: Node, at: Vector2, dimensions: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = at
	panel.size = dimensions
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.12, 0.14, 0.96)
	style.border_color = Color("536565")
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	return column

func _build_interface() -> void:
	# A revisable opening adapter limit, not a fixed window or a game-world rule.
	get_window().min_size = Vector2i(1280, 800)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font_size = 15
	root.theme = theme
	var build := _panel(root, Vector2(18, 18), Vector2(275, 620))
	_label(build, "FACTORY / FIRST SHIFT", 20, Color("edcc8d"))
	var tagline := _label(build, "A small line. Real materials.", 14, Color("9eb4b2"))
	tagline.visible = legacy_fixture
	build.add_child(HSeparator.new())
	goal_label = _label(build, "", 18)
	if not legacy_fixture:
		goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_button = _button(build, "Confirm four plates", _confirm_goal)
	build.add_child(HSeparator.new())
	parts_label = _label(build, "BUILD FROM SHARED KIT" if _parts_are_shared() else "BUILD FROM CARRIED PARTS", 12, Color("9eb4b2"))
	for kind in ["collector", "belt", "processor", "wheel"]:
		var button := _button(build, NAMES[kind], _select_tool.bind(kind))
		button.toggle_mode = true
		tool_buttons[kind] = button
	tool_buttons.flow = _button(build, "Material link  [F]", _select_tool.bind("flow"))
	tool_buttons.drive = _button(build, "Drive link  [G]", _select_tool.bind("drive"))
	tool_buttons.inspect = _button(build, "Inspect  [I]", _select_tool.bind("inspect"))
	for tool in ["flow", "drive", "inspect"]:
		tool_buttons[tool].toggle_mode = true
	var view_options := HBoxContainer.new()
	build.add_child(view_options)
	view_options.visible = not legacy_fixture
	all_tools_button = _button(view_options, "All tools", _toggle_all_tools)
	all_tools_button.tooltip_text = "Choose any available part."
	details_button = _button(view_options, "Details", _toggle_details)
	details_button.tooltip_text = "Show worksite counters and save options."
	_button(build, "How this line works  [H]", _toggle_explanation)
	var right := _panel(root, Vector2(990, 18), Vector2(272, 490))
	var right_panel: Control = right.get_parent()
	# Set the far anchor first so the near anchor is not clamped.
	right_panel.set_anchor_and_offset(SIDE_RIGHT, 1.0, -18)
	right_panel.set_anchor_and_offset(SIDE_LEFT, 1.0, -290)
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if legacy_fixture:
		_label(right, "WORKSITE", 13, Color("a3b8b4"))
	else:
		# The actor/connection rows identify the physical worksite. Leave room
		# for a selected press and pending-server advice above the status panel.
		right.add_theme_constant_override("separation", 6)
	actor_label = _label(right, "", 11, Color("a3b8b4"))
	actor_label.visible = not legacy_fixture
	power_label = _label(right, "", 14, Color("dfbc76"))
	stock_label = _label(right, "", 16)
	inspector = _label(right, "", 15)
	inspector.custom_minimum_size.x = 238
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	retrieve_button = _button(right, "Collect plate  [R]", _retrieve)
	power_button = _button(right, "Stop drive  [Space]", _toggle_power)
	remove_button = _button(right, "Dismantle selected", _remove_selected)
	# Older scripted launch payloads have a fixed roster without this native UI.
	var recovery_path := "res://opening/recovery_actions.gd"
	if ResourceLoader.exists(recovery_path, "Script"):
		var recovery_script = load(recovery_path)
		recovery_actions = recovery_script.new()
		right.add_child(recovery_actions)
		recovery_actions.configure(self)
	right.add_child(HSeparator.new())
	save_button = _button(right, "Save worksite  [F5]", _save_worksite)
	load_button = _button(right, "Load worksite  [F9]", _load_worksite)
	var bottom := _panel(root, Vector2(310, 694), Vector2(952, 88))
	var bottom_panel: Control = bottom.get_parent()
	bottom_panel.set_anchor_and_offset(SIDE_RIGHT, 1.0, -18)
	bottom_panel.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -18)
	bottom_panel.set_anchor_and_offset(SIDE_TOP, 1.0, -106)
	bottom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status_label = _label(bottom, "", 16)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label = _label(bottom, "1–4 build  ·  F material / G drive  ·  Right-drag orbit  ·  Wheel zoom  ·  WASD pan  ·  Home recenter" if legacy_fixture else "WASD walk · Space jump · P wheel · 1–4 build · F / G links · Right-drag orbit · Wheel zoom · H help", 12, Color("9eb4b2"))
	var lesson_column := _panel(root, Vector2(346, 18), Vector2(600, 192))
	lesson_panel = lesson_column.get_parent()
	lesson_panel.set_anchor_and_offset(SIDE_RIGHT, 0.5, 306)
	lesson_panel.set_anchor_and_offset(SIDE_LEFT, 0.5, -294)
	lesson_title = _label(lesson_column, "", 17, Color("edcc8d"))
	lesson_body = _label(lesson_column, "", 16)
	lesson_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	lesson_column.add_child(row)
	lesson_previous = _button(row, "Previous", func(): _set_lesson(lesson_index - 1))
	lesson_next = _button(row, "Next", func(): _set_lesson(lesson_index + 1))
	lesson_return = _button(row, "Return to building  [H]", _toggle_explanation)
	lesson_panel.visible = false
