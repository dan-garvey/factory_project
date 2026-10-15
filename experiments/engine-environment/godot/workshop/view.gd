extends Node3D
## Build controls and completed-native presentation, not a second mechanism.
signal answered(intent: Dictionary, outcome: Dictionary, at_ack: Dictionary)
const Authority = preload("res://workshop/authority.gd")
const LABELS := {"B": "1  Tool head B", "U": "2  Tool head U", "gear20": "3  Output gear · 20",
	"gear40": "4  Output gear · 40", "idler": "5  Idler", "stop": "6  Training stop", "erase": "X  Pick up piece"}
var authority
var mode := "B"
var last_result := {}
var auto_advance := false
var elapsed := 0.0
var reset_requested := false
var yaw := 0.55
var pitch := 0.72
var distance := 17.0
var focus := Vector3(-1, 0.2, 1)
var camera: Camera3D
var body_meshes := {}
var body_labels := {}
var gear_meshes := {}
var stop_mesh: MeshInstance3D
var rails: Node3D
var rail_key := ""
var hover: MeshInstance3D
var stats: Label
var clutch_marks: Label
var message: Label
var run_button: Button
var step_button: Button
var coupling_button: Button
var stop_button: Button
var reset_button: Button
var auto_button: CheckBox
var tool_buttons := {}
var hover_cell := Vector2i(99, 99)

func _ready() -> void:
	_build_world()
	_build_interface()
	_replace_authority()

func _replace_authority() -> void:
	if authority != null:
		if authority.pending:
			reset_requested = true
			return
		remove_child(authority)
		authority.queue_free()
	authority = Authority.new()
	authority.name = "WorkshopAuthority"
	add_child(authority)
	authority.advanced.connect(_completed)
	reset_requested = false
	elapsed = 0.0
	auto_advance = false
	auto_button.button_pressed = false
	rail_key = ""
	last_result = {}
	_message("Fresh workshop. Place B, U and an output gear, then start the source.")
	_refresh()

func reset_workshop() -> void:
	reset_requested = true
	auto_advance = false
	_message("Starting a fresh workshop; the current build will be cleared.")
	if not authority.pending:
		call_deferred("_replace_authority")

func _completed(_outcome: Dictionary) -> void:
	_refresh()
	if reset_requested:
		call_deferred("_replace_authority")

func issue(intent: Dictionary) -> Dictionary:
	if reset_requested:
		return {"accepted": false, "reason": "fresh_workshop_pending"}
	var result: Dictionary = authority.command(intent)
	last_result = result.duplicate(true)
	var words: String = {"geometry_pending": "Placement requested; waiting for native geometry.",
		"applied": "Control applied.", "queued_for_physics": "Drive step requested.",
		"place_heads_and_output": "Place both tool heads and one output gear first.",
		"initial_setup_only": "This build has moved. Press R for a fresh workshop before rearranging.",
		"choose_B_mount": "B mounts on the two orange squares at (-1,0) or (0,0).",
		"choose_U_mount": "U mounts on a green square at (0,3) or (0,4).",
		"choose_output_peg": "Place the output gear on the peg at (-3,-2).",
		"choose_idler_peg": "Place the idler on the peg at (-4,-2).",
		"choose_stop_cell": "Stop mounts at x 1 or 2, on lane z 0 or 3.",
		"already_here": "That piece is already here.", "empty_cell": "There is no construction piece on that square.",
		"step_pending": "Wait for the native step to finish.", "source_stopped": "Start the source before stepping.",
		"pause_before_stop_control": "Pause the source before operating the training stop.",
		"no_training_stop": "Place a training stop during initial setup first.",
		"stop_before_engage": "Pause the source before engaging K.",
		"coupling_misaligned": "Input and B phases differ. Keep B isolated and step U until they align."}.get(result.reason, str(result.reason))
	_message(words, not result.accepted)
	_refresh()
	answered.emit(intent.duplicate(true), result.duplicate(true), authority.projection())
	return result.duplicate(true)

func _select_tool(tool: String) -> void:
	mode = tool
	_message({"B": "Choose B mount (-1,0) or (0,0). Its position changes work-zone reach.",
		"U": "Choose U mount (0,3) or (0,4). Keep its moving path clear.",
		"gear20": "Click the output peg (-3,-2) to install a 20-tooth output.",
		"gear40": "Click the output peg (-3,-2) to install a 40-tooth output.",
		"idler": "Click the idler peg (-4,-2) to reverse the mesh sign.",
		"stop": "Choose a red stop square. Native contact stalls the connected drive.",
		"erase": "Click a construction piece to pick it up, before the first movement."}[tool])
	_refresh()

func _world_click(cell: Vector2i) -> void:
	issue({"action": "erase_piece", "cell": [cell.x, cell.y]} if mode == "erase" else
		{"action": "place_piece", "kind": mode, "cell": [cell.x, cell.y]})

func _run_toggle() -> void:
	issue({"action": "run", "active": not authority.running})

func _coupling_toggle() -> void:
	issue({"action": "coupling", "active": not authority.coupled})

func _stop_toggle() -> void:
	issue({"action": "stop_control", "retracted": authority.obstacle_active})

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode in [KEY_SPACE, KEY_N, KEY_K, KEY_O, KEY_R]:
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_SPACE: _run_toggle()
				KEY_N: issue({"action": "step"})
				KEY_K: _coupling_toggle()
				KEY_O: _stop_toggle()
				KEY_R: reset_workshop()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			yaw -= event.relative.x * 0.007
			pitch = clampf(pitch + event.relative.y * 0.005, 0.35, 1.2)
		else:
			hover_cell = _screen_cell(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_world_click(_screen_cell(event.position))
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(11, distance - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(25, distance + 1)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _select_tool("B")
			KEY_2: _select_tool("U")
			KEY_3: _select_tool("gear20")
			KEY_4: _select_tool("gear40")
			KEY_5: _select_tool("idler")
			KEY_6: _select_tool("stop")
			KEY_X: _select_tool("erase")
			KEY_HOME:
				focus = Vector3(-1, 0.2, 1)
				distance = 17.0

func _screen_cell(point: Vector2) -> Vector2i:
	var hit = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
	return Vector2i(roundi(hit.x), roundi(hit.z)) if hit != null else Vector2i(99, 99)

func _process(delta: float) -> void:
	if authority != null and auto_advance and authority.running and not authority.pending and not reset_requested:
		elapsed += delta
		if elapsed >= 0.18:
			elapsed = 0.0
			issue({"action": "step"})
	var pan := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		focus += Vector3(pan.x, 0, pan.y) * delta * 3
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(focus)
	_refresh()

func _refresh() -> void:
	if authority == null or stats == null:
		return
	var state: Dictionary = authority.projection()
	var physical: Dictionary = state.completed
	var layout: Dictionary = physical.get("layout", {"pieces": {"B": null, "U": null, "gear": null, "idler": null, "stop": null}})
	for branch in ["B", "U"]:
		body_meshes[branch].visible = layout.pieces[branch] != null
		body_labels[branch].visible = body_meshes[branch].visible
		if body_meshes[branch].visible:
			var at: Array = physical.positions[branch]
			body_meshes[branch].position = Vector3(at[0], at[1], at[2])
			body_labels[branch].position = body_meshes[branch].position + Vector3(0, 0.7, 0)
	gear_meshes.output.visible = layout.pieces.gear != null
	if layout.pieces.gear != null:
		gear_meshes.output.scale = Vector3.ONE * (0.7 if layout.pieces.gear.kind == "gear20" else 1.0)
	gear_meshes.idler.visible = layout.pieces.idler != null
	gear_meshes.source.rotation.z = physical.get("source_phase", 0.0)
	gear_meshes.output.rotation.z = physical.get("phases", {"B": 0.0}).B
	gear_meshes.idler.rotation.z = -physical.get("source_phase", 0.0)
	stop_mesh.visible = layout.pieces.stop != null and not layout.get("stop_retracted", true)
	if stop_mesh.visible:
		var at: Array = physical.obstacle_position
		stop_mesh.position = Vector3(at[0], at[1], at[2])
	var next_key := JSON.stringify(layout.pieces)
	if next_key != rail_key:
		rail_key = next_key
		for child in rails.get_children():
			child.free()
		for branch in ["B", "U"]:
			if layout.pieces[branch] != null:
				var cell: Array = layout.pieces[branch].cell
				for side in [-0.48, 0.48]:
					_box(rails, Vector3(cell[0], 0.25, cell[1] + side), Vector3(4.8, 0.12, 0.12), Color("637b74"))
	var phases: Dictionary = physical.get("phases", {"B": 0.0, "U": 0.0})
	stats.text = "%s\n%s · B 20:%d %s\nSource %.3f\nB %.3f · U %.3f\n%d completed / %d attempts\nWork encounters %d\nNON-CONSUMING · NO ITEMS" % [
		"NATIVE UPDATE PENDING" if state.native_pending else "CONNECTED DRIVE STALLED" if state.blocked else "SOURCE RUNNING" if state.running else "SOURCE PAUSED",
		"K ENGAGED" if state.coupled else "K OPEN / B RETAINED", state.teeth, "positive" if state.idler else "reversed",
		physical.get("source_phase", 0.0), phases.B, phases.U, physical.get("committed", 0), state.attempts, physical.get("contact_entries", 0)]
	if not state.last_collision.is_empty():
		stats.text += "\nLast obstruction: branch " + str(state.last_collision.branch)
	# Inspect the completed geared input and retained branch. These marks do
	# not predict admission: the unchanged coupling command decides engagement.
	if state.native_pending:
		clutch_marks.text = "K SHAFT MARKS\nNative update pending"
	elif not layout.get("ready", false):
		clutch_marks.text = "K SHAFT MARKS\nPlace both heads and output."
	else:
		var input_phase: float = physical.source_phase * layout.ratio
		var offset := rad_to_deg(wrapf(input_phase - phases.B, -PI, PI))
		# Avoid a distracting negative zero after complete revolutions.
		if absf(offset) < 0.005:
			offset = 0.0
		clutch_marks.text = "K SHAFT MARKS\nGeared input %06.2f°\nRetained B %06.2f°\nOffset %+.2f°" % [
			rad_to_deg(fposmod(input_phase, TAU)), rad_to_deg(fposmod(phases.B, TAU)), offset]
	run_button.text = "Pause source [Space]" if state.running else "Start source [Space]"
	coupling_button.text = "Open K / isolate B [K]" if state.coupled else "Engage K [K]"
	stop_button.text = "Retract training stop [O]" if state.obstacle_active else "Deploy training stop [O]"
	step_button.disabled = state.pending or not state.running or reset_requested
	for tool in tool_buttons:
		tool_buttons[tool].button_pressed = mode == tool
	hover.visible = hover_cell.x >= -5 and hover_cell.x <= 3 and hover_cell.y >= -3 and hover_cell.y <= 4
	hover.position = Vector3(hover_cell.x, 0.04, hover_cell.y)

func _message(text: String, refused := false) -> void:
	message.text = text
	message.modulate = Color("e6a17d") if refused else Color("d3ddd4")

func _box(parent: Node, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

func _label3d(text: String, at: Vector3, color := Color("e2ddc0")) -> Label3D:
	var node := Label3D.new()
	node.text = text
	node.position = at
	node.modulate = color
	node.font_size = 28
	node.pixel_size = 0.006
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(node)
	return node

func _gear(at: Vector3, radius: float, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	add_child(pivot)
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.12
	mesh.mesh = cylinder
	mesh.rotation.x = PI / 2
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	pivot.add_child(mesh)
	for angle in [0.0, PI / 2]:
		var spoke := _box(pivot, Vector3.ZERO, Vector3(radius * 1.8, 0.07, 0.16), Color("34484c"))
		spoke.rotation.z = angle
	return pivot

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("19282e")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d0dbd1")
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.shadow_enabled = true
	add_child(light)
	camera = Camera3D.new()
	camera.fov = 46
	add_child(camera)
	_box(self, Vector3(-1, -0.2, 1), Vector3(10, 0.3, 9), Color("344a43"))
	for x in range(-5, 4):
		for z in range(-3, 5):
			_box(self, Vector3(x, -0.035, z), Vector3(0.96, 0.025, 0.96), Color("50635a") if (x + z) % 2 == 0 else Color("475b53"))
	for cell in Authority.B_CELLS:
		_box(self, Vector3(cell[0], 0, cell[1]), Vector3(0.9, 0.04, 0.9), Color("9a7049"))
		_label3d("B %s" % str(cell), Vector3(cell[0], 0.08, cell[1] - 0.55))
	for cell in Authority.U_CELLS:
		_box(self, Vector3(cell[0], 0, cell[1]), Vector3(0.9, 0.04, 0.9), Color("507c6e"))
		_label3d("U %s" % str(cell), Vector3(cell[0] - 0.7, 0.1, cell[1]))
	for cell in Authority.STOP_CELLS:
		_box(self, Vector3(cell[0], 0, cell[1]), Vector3(0.8, 0.035, 0.8), Color("805b4c"))
	for cell in [Authority.OUTPUT_PEG, Authority.IDLER_PEG]:
		_box(self, Vector3(cell[0], 0.02, cell[1]), Vector3(0.8, 0.09, 0.8), Color("a49561"))
	_label3d("OUTPUT\n[-3,-2]", Vector3(-3, 1.65, -2))
	_label3d("IDLER\n[-4,-2]", Vector3(-4, 1.65, -2))
	_label3d("S / 20", Vector3(-5, 1.65, -2))
	_label3d("SCHEMATIC GEAR LINK", Vector3(-4, 2.4, -2))
	gear_meshes.source = _gear(Vector3(-5, 0.65, -2), 0.42, Color("c7be8b"))
	gear_meshes.output = _gear(Vector3(-3, 0.65, -2), 0.48, Color("d3b56e"))
	gear_meshes.idler = _gear(Vector3(-4, 0.65, -2), 0.3, Color("b8a778"))
	_box(self, Vector3(-4, 0.12, -2), Vector3(2.3, 0.08, 0.08), Color("9f9a7a"))
	for branch in ["B", "U"]:
		body_meshes[branch] = _box(self, Vector3.ZERO, Authority.BODY_SIZE, Color("d69a59") if branch == "B" else Color("70b6a3"))
		body_labels[branch] = _label3d(branch, Vector3.ZERO)
	stop_mesh = _box(self, Vector3.ZERO, Vector3(0.35, 1.5, 1.1), Color("b8654d"))
	_box(self, Vector3(1.6, 0.045, 0), Vector3(0.6, 0.05, 1.2), Color("579eb4"))
	_label3d("WORK ZONE\nnon-consuming contact", Vector3(2.1, 0.35, -1.0), Color("a6d6e3"))
	rails = Node3D.new()
	add_child(rails)
	hover = _box(self, Vector3.ZERO, Vector3(0.94, 0.04, 0.94), Color("c8c59e"))
	hover.visible = false

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(252, 35)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String, size := 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _panel(parent: Node, at: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = at
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	return column

func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 15
	root.theme = theme
	layer.add_child(root)
	var build := _panel(root, Vector2(18, 18))
	_label(build, "MECHANICAL WORKSHOP", 19)
	_label(build, "Arrange the rig. Watch what changes.", 13)
	build.add_child(HSeparator.new())
	for tool in LABELS:
		tool_buttons[tool] = _button(build, LABELS[tool], _select_tool.bind(tool))
		tool_buttons[tool].toggle_mode = true
	build.add_child(HSeparator.new())
	_label(build, "Orange squares: B mounts\nGreen squares: U mounts\nRed squares: training stop\nBrass pegs: output / idler", 14)
	_label(build, "Choose a piece, then click its square.\nMove pieces only before first motion.\nR starts a completely fresh workshop.", 13)
	var controls := _panel(root, Vector2(990, 18))
	_label(controls, "DRIVE / RECOVERY", 17)
	run_button = _button(controls, "Start source [Space]", _run_toggle)
	step_button = _button(controls, "Advance one step [N]", func(): issue({"action": "step"}))
	auto_button = CheckBox.new()
	auto_button.text = "Repeat fixed cycle"
	auto_button.toggled.connect(func(active: bool):
		auto_advance = active
		elapsed = 0.0)
	controls.add_child(auto_button)
	coupling_button = _button(controls, "Open K / isolate B [K]", _coupling_toggle)
	stop_button = _button(controls, "Retract training stop [O]", _stop_toggle)
	reset_button = _button(controls, "Fresh workshop [R]", reset_workshop)
	controls.add_child(HSeparator.new())
	stats = _label(controls, "", 14)
	clutch_marks = _label(controls, "", 14)
	_label(controls, "Pause before retracting the stop.\nK re-engages only when stopped\nand the shaft phases align.", 13)
	var bottom := _panel(root, Vector2(310, 694))
	message = _label(bottom, "", 15)
	message.custom_minimum_size = Vector2(930, 40)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(bottom, "Right-drag orbit · Wheel zoom · WASD pan · Home recenter\nIdeal gears drive real native sliders. No production, inventory, network or workshop saves.", 12)
