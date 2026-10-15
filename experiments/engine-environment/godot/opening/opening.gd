extends Node3D
## Input and presentation only. Every material/build mutation goes to model.gd.

const Model = preload("res://model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
const STEP_SECONDS := 0.45
const PITCH := 1.65
const NAMES := {"collector": "Collector", "belt": "Belt", "processor": "Press", "wheel": "Waterwheel"}
const COLORS := {"collector": Color("d6a34d"), "belt": Color("538e88"), "processor": Color("bd7054"), "wheel": Color("8b9caa")}
const LESSONS := [
	["01  /  BUILD THE PATH", "Place a collector, a belt and a press in a row. Material ports face along the brass arrow. Each placed machine uses a part from your carried kit."],
	["02  /  CONNECT THE DRIVE", "Place the waterwheel beside your line. Choose Drive link, then click two neighboring machines. Carry its rotation through the whole line; the stream supplies motion without fuel."],
	["03  /  FOLLOW ONE BLANK", "The collector removes a blank from the finite seam. The belt carries it to the press. Advance the example one tick at a time. The held blank stays in the press until its plate can leave."],
	["04  /  MAKE ROOM", "A full press outlet holds up the line. Collect the example plate below: the held blank finishes without being lost. Stopping the drive keeps the parts and unfinished work where they are."]
]

var model
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
var wheel_rotor: Node3D
var status_label: Label
var stock_label: Label
var goal_label: Label
var power_label: Label
var inspector: Label
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

func _ready() -> void:
	if model == null:
		model = Model.new(16, "opening-local-1", 1, {"opening": true})
	if save_slot.is_empty():
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--save-slot="):
				configure_save_slot(argument.trim_prefix("--save-slot="))
	_build_world()
	_build_interface()
	_refresh()
	_message("Build a small line. Choose a part, then click a grid square.")

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
		last_save_result = Store.write(model, save_slot)
	if last_save_result.accepted:
		save_slot_owned = true
		_message("Worksite saved. Load returns to this moment.")
	else:
		_message("Save unavailable. Your current worksite and previous save are kept.", true)
	_refresh_ui()
	return last_save_result

func _load_worksite(path: String = "") -> Dictionary:
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
	request_sequence += 1
	var intent: Dictionary = action.duplicate(true)
	intent.merge({"context": model.projection().context, "client": client,
		"request": request_namespace + str(request_sequence)}, true)
	var outcome: Dictionary = model.command(intent)
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
	if event is InputEventKey and event.keycode in [KEY_SPACE, KEY_F5, KEY_F9]:
		if event.pressed and not event.echo and not explanation_open:
			match event.keycode:
				KEY_SPACE: _toggle_power()
				KEY_F5: _save_worksite()
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
			distance = maxf(10, distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(28, distance + 1)
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
				focus = Vector3(1.3, 0, 1.1)
				distance = 18.5
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
		if example_presenter == null:
			# Lazy loading avoids a static cycle with the geometry-only subclass.
			example_presenter = load("res://opening/example_presenter.gd").new()
			example_presenter.position = Vector2(310, 226)
			example_presenter.size = Vector2(670, 446)
			lesson_panel.get_parent().add_child(example_presenter)
		example_presenter.show()
		_set_lesson(0)
	else:
		example_presenter.hide()
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
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("17232a")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("bdd4d9")
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_color = Color("fff1d6")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
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
		_box(anchor, Vector3(0, 0.12, 0), Vector3(1.35, 0.24, 1.35), Color("273c41"))
		match kind:
			"collector":
				_box(anchor, Vector3(-0.12, 0.65, 0), Vector3(0.8, 0.85, 0.9), COLORS[kind])
				_box(anchor, Vector3(0.5, 0.4, 0), Vector3(0.5, 0.15, 0.62), Color("c9c8ac"))
				var saw := _cylinder(anchor, Vector3(-0.1, 1.18, 0), 0.36, 0.1, Color("314249"))
				saw.rotation.x = PI / 2
			"belt":
				_box(anchor, Vector3(0, 0.38, 0), Vector3(1.54, 0.18, 0.74), COLORS[kind])
				for x in range(-3, 4):
					_box(anchor, Vector3(x * 0.19, 0.49, 0), Vector3(0.065, 0.045, 0.71), Color("99b6a5"))
				_box(anchor, Vector3(0, 0.52, -0.4), Vector3(1.55, 0.16, 0.06), Color("2a4447"))
				_box(anchor, Vector3(0, 0.52, 0.4), Vector3(1.55, 0.16, 0.06), Color("2a4447"))
			"processor":
				for x in [-0.45, 0.45]:
					_box(anchor, Vector3(x, 0.85, -0.31), Vector3(0.16, 1.5, 0.3), COLORS[kind])
				_box(anchor, Vector3(0, 1.56, -0.3), Vector3(1.1, 0.22, 0.46), COLORS[kind])
				_box(anchor, Vector3(0, 0.84, 0), Vector3(0.68, 0.18, 0.65), Color("c2bca9"))
				_cylinder(anchor, Vector3(0, 1.2, -0.15), 0.1, 0.55, Color("35484d"))
				_box(anchor, Vector3(0, 0.35, 0), Vector3(0.82, 0.24, 0.82), Color("30434a"))
				_box(anchor, Vector3(0.6, 0.29, 0.15), Vector3(0.65, 0.08, 0.72), Color("c9c8ac"))
			"wheel":
				_box(anchor, Vector3(0, 0.62, 0.25), Vector3(0.16, 1.2, 0.35), Color("38464b"))
				wheel_rotor = Node3D.new()
				wheel_rotor.position = Vector3(0, 0.72, 0)
				anchor.add_child(wheel_rotor)
				var rim := _cylinder(wheel_rotor, Vector3.ZERO, 0.67, 0.12, Color("6d7f83"))
				rim.rotation.x = PI / 2
				for n in range(8):
					var spoke := _box(wheel_rotor, Vector3.ZERO, Vector3(0.12, 1.48, 0.16), Color("c2a86d"))
					spoke.rotation.z = n * PI / 4
		var body := StaticBody3D.new()
		body.set_meta("entity", entity_id)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.45, 1.65, 1.45)
		collider.shape = shape
		collider.position.y = 0.8
		body.add_child(collider)
		anchor.add_child(body)
		_text(anchor, NAMES.get(kind, kind).to_upper(), Vector3(0, 1.9, 0), Color("f2e5c5"))
	for pair in state.links:
		if state.entities.has(pair[0]) and state.entities.has(pair[1]):
			_bar(machine_root, _cell_position(state.entities[pair[0]].cell) + Vector3(0.5, 0.45, 0),
				_cell_position(state.entities[pair[1]].cell) + Vector3(-0.5, 0.45, 0), 0.18, Color("b9c1a8"))
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
			_box(item_root, pos + Vector3(0.6, 0.39, 0.15), Vector3(0.44, 0.07, 0.53), Color("e4d8b3"))
	# The finite seam stays in its marked column when machinery is rebuilt.
	for n in range(mini(16, int(state.stock.source))):
		_box(item_root, Vector3(-0.16 + (n % 2) * 0.32, 0.11, -2.9 + int(n / 2.0) * 1.15),
			Vector3(0.2, 0.18, 0.28), Color("a58c59"))

func _refresh() -> void:
	state = model.projection()
	var next_key := JSON.stringify([state.entities, state.links, state.get("drive_links", [])])
	if next_key != geometry_key:
		geometry_key = next_key
		_rebuild_machines()
	if int(state.revision) != visual_revision:
		visual_revision = int(state.revision)
		_redraw_items()
	_refresh_ui()

func _refresh_ui() -> void:
	if stock_label == null:
		return
	var inventory := int(state.inventories.get(client, 0))
	goal_label.text = "FIRST SHIFT\nBring back 4 plates\n%d / 4 collected" % inventory
	confirm_button.disabled = inventory < 4 or goal_confirmed or explanation_open
	confirm_button.text = "Objective confirmed" if goal_confirmed else "Confirm four plates"
	stock_label.text = "SEAM  %d blanks\nIN THE LINE  %d blanks\nPRESS OUTLET  %d plate" % [state.stock.source,
		state.stock.collector + state.stock.belt + state.stock.input + state.stock.held, state.stock.output]
	power_label.text = "DRIVE RUNNING" if state.get("powered", false) else "DRIVE STOPPED / UNCONNECTED"
	power_button.text = "Stop drive  [Space]" if state.get("power_enabled", true) else "Start drive  [Space]"
	power_button.disabled = explanation_open
	save_button.disabled = explanation_open or not save_slot_ready
	load_button.disabled = explanation_open or not save_slot_ready or not save_slot_owned
	for button in [save_button, load_button]:
		button.tooltip_text = "" if save_slot_ready else "Launch a fresh worksite session to enable saving."
	for tool in tool_buttons:
		var button: Button = tool_buttons[tool]
		button.disabled = explanation_open or (NAMES.has(tool) and not state.parts.has(tool))
		button.button_pressed = mode == tool
		if NAMES.has(tool):
			button.text = "%s    ·    %d carried" % [NAMES[tool], int(state.parts.get(tool, 0))]
	if state.parts.has("shaft"):
		tool_buttons.drive.text = "Drive link  [G]    ·    %d shafts" % int(state.parts.shaft)
	retrieve_button.disabled = explanation_open or state.stock.output < 1 or not state.entities.has(selected) or state.entities[selected].kind != "processor"
	remove_button.disabled = explanation_open or not state.entities.has(selected)
	selection_ring.visible = state.entities.has(selected)
	if selection_ring.visible:
		selection_ring.position = _cell_position(state.entities[selected].cell) + Vector3(0, 0.02, 0)
		inspector.text = "%s\nSquare %s" % [NAMES.get(state.entities[selected].kind, selected), str(state.entities[selected].cell)]
		if state.entities[selected].kind == "processor":
			inspector.text += "\n%d in · %d held · %d ready" % [state.stock.input, state.stock.held, state.stock.output]
	else:
		inspector.text = "Select a machine to inspect\nor collect its finished work."

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
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 15
	root.theme = theme
	var build := _panel(root, Vector2(18, 18), Vector2(275, 620))
	_label(build, "FACTORY / FIRST SHIFT", 20, Color("edcc8d"))
	_label(build, "A small line. Real materials.", 14, Color("9eb4b2"))
	build.add_child(HSeparator.new())
	goal_label = _label(build, "", 18)
	confirm_button = _button(build, "Confirm four plates", _confirm_goal)
	build.add_child(HSeparator.new())
	_label(build, "BUILD FROM CARRIED PARTS", 12, Color("9eb4b2"))
	for kind in ["collector", "belt", "processor", "wheel"]:
		var button := _button(build, NAMES[kind], _select_tool.bind(kind))
		button.toggle_mode = true
		tool_buttons[kind] = button
	tool_buttons.flow = _button(build, "Material link  [F]", _select_tool.bind("flow"))
	tool_buttons.drive = _button(build, "Drive link  [G]", _select_tool.bind("drive"))
	tool_buttons.inspect = _button(build, "Inspect  [I]", _select_tool.bind("inspect"))
	for tool in ["flow", "drive", "inspect"]:
		tool_buttons[tool].toggle_mode = true
	_button(build, "How this line works  [H]", _toggle_explanation)
	var right := _panel(root, Vector2(990, 18), Vector2(272, 490))
	_label(right, "WORKSITE", 13, Color("a3b8b4"))
	power_label = _label(right, "", 14, Color("dfbc76"))
	stock_label = _label(right, "", 16)
	inspector = _label(right, "", 15)
	retrieve_button = _button(right, "Collect plate  [R]", _retrieve)
	power_button = _button(right, "Stop drive  [Space]", _toggle_power)
	remove_button = _button(right, "Dismantle selected", _remove_selected)
	right.add_child(HSeparator.new())
	save_button = _button(right, "Save worksite  [F5]", _save_worksite)
	load_button = _button(right, "Load worksite  [F9]", _load_worksite)
	var bottom := _panel(root, Vector2(310, 694), Vector2(952, 88))
	status_label = _label(bottom, "", 16)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(bottom, "1–4 build  ·  F material / G drive  ·  Right-drag orbit  ·  Wheel zoom  ·  WASD pan  ·  Home recenter", 12, Color("9eb4b2"))
	var lesson_column := _panel(root, Vector2(346, 18), Vector2(600, 192))
	lesson_panel = lesson_column.get_parent()
	lesson_title = _label(lesson_column, "", 17, Color("edcc8d"))
	lesson_body = _label(lesson_column, "", 16)
	lesson_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	lesson_column.add_child(row)
	lesson_previous = _button(row, "Previous", func(): _set_lesson(lesson_index - 1))
	lesson_next = _button(row, "Next", func(): _set_lesson(lesson_index + 1))
	lesson_return = _button(row, "Return to building  [H]", _toggle_explanation)
	lesson_panel.visible = false
