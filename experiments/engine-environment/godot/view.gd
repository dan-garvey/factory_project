extends Node3D
## Presentation submits intents and renders projections; it never changes stock.
const Model = preload("res://model.gd")
const Scenario = preload("res://scenario.gd")
const COLORS = {"collector": Color("e69b58"), "belt": Color("59ada5"), "processor": Color("738ed4")}
var model = Model.new()
var serial := 0
var selected := "collector"
var running := false
var elapsed := 0.0
var yaw := 0.7
var distance := 17.0
var camera: Camera3D
var machines: Node3D
var markers: Node3D
var stats: Label
var message: Label
var buttons: Dictionary = {}
var last_reason := "Choose a machine, then click a grid cell. Example builds the test layout."

func _ready():
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("182530")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c4d6e6")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.shadow_enabled = true
	add_child(light)
	camera = Camera3D.new()
	camera.fov = 48
	add_child(camera)
	position_camera()
	machines = Node3D.new()
	markers = Node3D.new()
	add_child(machines)
	add_child(markers)
	for x in range(-2, 5):
		for z in range(-2, 5):
			box(self, Vector3(x * 3, -0.15, z * 3), Vector3(2.9, 0.25, 2.9),
				Color("31473f") if (x + z) % 2 == 0 else Color("2c403a"))
	make_ui()
	refresh()
	if OS.get_cmdline_user_args().has("--smoke"):
		call_deferred("smoke")

func box(parent: Node, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func add_button(row: HBoxContainer, key: String, text: String, action: Callable):
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	row.add_child(button)
	buttons[key] = button

func make_ui():
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 18)
	panel.custom_minimum_size = Vector2(780, 0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "FACTORY  /  GODOT 3D SANDBOX"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Place → connect → process → retrieve     •     Prototype fixture, not game rules"
	column.add_child(subtitle)
	var row := HBoxContainer.new()
	column.add_child(row)
	for kind in ["collector", "belt", "processor"]:
		var chosen: String = kind
		add_button(row, kind, kind.capitalize(), func(): selected = chosen; refresh())
	add_button(row, "example", "Build example", build_example)
	add_button(row, "connect", "Connect ports", connect_ports)
	add_button(row, "run", "Run / pause", func(): running = not running; refresh())
	add_button(row, "step", "Step", func(): model.advance(); refresh())
	add_button(row, "take", "Take product", func(): send({"action": "retrieve", "amount": 1}); refresh())
	add_button(row, "reset", "Reset fixture", reset_fixture)
	stats = Label.new()
	column.add_child(stats)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var footer := Label.new()
	footer.position = Vector2(24, 720)
	footer.text = "RMB drag: orbit   •   Wheel: zoom   •   Ports point +X; place adjacent cells\n" + \
		"8 finite feed • 2 feed → 1 product • fixture drive • one output slot • Reset is not recovery\n" + \
		"Scene displays the same RefCounted rules used by the headless test. No network/save/player collision yet."
	footer.add_theme_color_override("font_color", Color("d2ded7"))
	layer.add_child(footer)

func reset_fixture():
	model = Model.new()
	serial = 0
	running = false
	last_reason = "Explicit fixture reset. Initial stock restored between runs."
	refresh()

func send(intent: Dictionary) -> Dictionary:
	serial += 1
	intent.merge({"context": model.context, "client": "P", "request": "scene-" + str(serial)})
	var result: Dictionary = model.command(intent)
	last_reason = result.reason
	return result

func build_example():
	Scenario.build(send)
	refresh()

func connect_ports():
	for pair in [["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
		send({"action": "connect", "from": pair[0], "to": pair[1]})
	refresh()

func refresh():
	# Projections are copies: every displayed quantity comes from the rule owner.
	var state: Dictionary = model.projection()
	stats.text = "Source %d   Collector %d   Belt %d   Input %d   Held %d   Output %d   Retrieved %d" % [
		state.stock.source, state.stock.collector, state.stock.belt, state.stock.input,
		state.stock.held, state.stock.output, state.stock.player]
	message.text = "Selected: %s   •   %s   •   %s" % [selected, "RUNNING" if running else "PAUSED", last_reason]
	for child in machines.get_children():
		child.free()
	for child in markers.get_children():
		child.free()
	for entity_id in state.entities:
		var entity: Dictionary = state.entities[entity_id]
		var at := Vector3(entity.cell[0] * 3, 0, entity.cell[1] * 3)
		var height := 0.25 if entity.kind == "belt" else 1.8
		var shape := box(machines, at + Vector3(0, height / 2.0, 0), Vector3(2.3, height, 2.0), COLORS[entity.kind])
		shape.name = entity_id
		if entity.kind == "processor":
			box(machines, at + Vector3(0, 2.2, 0), Vector3(1.4, 0.3, 1.4), Color("c0cce5"))
		var label := Label3D.new()
		label.text = entity.kind.to_upper() + "  →"
		label.position = at + Vector3(0, 3, 0)
		label.font_size = 42
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		machines.add_child(label)
		var key: String = entity.kind if entity.kind != "processor" else "output"
		if state.stock[key] > 0:
			box(markers, at + Vector3(0, height + 0.5, 0), Vector3(0.55, 0.55, 0.55), Color("f5d27c"))
		if entity.kind == "processor" and state.stock.held > 0:
			box(markers, at + Vector3(-0.6, 1.4, 0), Vector3(0.4, 0.4, 0.4), Color("e07e74"))
	for pair in state.links:
		var a: Array = state.entities[pair[0]].cell
		box(machines, Vector3(a[0] * 3 + 1.5, 0.3, a[1] * 3), Vector3(0.7, 0.15, 0.6), Color("a7cbb7"))

func position_camera():
	var target := Vector3(3, 0, 1)
	camera.position = target + Vector3(sin(yaw) * distance, distance * 0.85, cos(yaw) * distance)
	camera.look_at(target)

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.008
		position_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 9, 28)
			position_camera()
		if event.button_index == MOUSE_BUTTON_LEFT:
			var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
			if point != null:
				send({"action": "place", "kind": selected, "cell": [roundi(point.x / 3), roundi(point.z / 3)]})
				refresh()

func _process(delta):
	if running:
		elapsed += delta
		while elapsed >= 0.6:
			elapsed -= 0.6
			model.advance()
		refresh()

func smoke():
	# Exercise actual scene signal handlers and inspect their resulting view.
	buttons.example.pressed.emit()
	for _tick in range(7):
		buttons.step.pressed.emit()
	var first: Dictionary = model.projection().stock
	for _tick in range(5):
		buttons.step.pressed.emit()
	var blocked: Dictionary = model.projection().stock
	buttons.take.pressed.emit()
	Scenario.finish(model, send)
	refresh()
	var final: Dictionary = model.projection().stock
	var good: bool = Scenario.conserved(model.projection()) and final.player == 4 \
		and machines.has_node("collector-1") and machines.has_node("belt-1") \
		and machines.has_node("processor-1") and stats.text.contains("Retrieved 4")
	# Capture the blocked fixture, where retained work and actual stock are visible.
	reset_fixture()
	buttons.example.pressed.emit()
	for _tick in range(12):
		buttons.step.pressed.emit()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var report_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			good = get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture=")) == OK and good
		if arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"status": "pass" if good else "fail", "checks": 4,
			"first": first, "blocked": blocked, "final": final}))
	print("FACTORY_SCENE_PASS" if good else "FACTORY_SCENE_FAIL")
	get_tree().quit(0 if good else 1)
