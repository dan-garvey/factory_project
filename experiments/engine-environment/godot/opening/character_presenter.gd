extends Node3D
## Input and confirmed actor presentation only. The native producer/server owns
## every physical pose; these meshes never grant construction permission.
const Geometry = preload("res://opening/site_geometry.gd")

var host
var views: Dictionary = {}
var held_keys: Dictionary = {}
var jump_requested := false
var last_direction := Vector2.ZERO

func configure(view) -> void:
	host = view

func _ready() -> void:
	get_window().focus_exited.connect(release)
	refresh()

func release() -> void:
	held_keys.clear()
	jump_requested = false
	last_direction = Vector2.ZERO
	if host != null:
		host._release_character_input()

func _input(event: InputEvent) -> void:
	if host == null or host.explanation_open or not event is InputEventKey:
		return
	if event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
		if event.pressed and not event.echo:
			held_keys[event.keycode] = true
		elif not event.pressed:
			held_keys.erase(event.keycode)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_SPACE:
		if event.pressed and not event.echo:
			jump_requested = true
		# Consume both edges so a focused GUI button cannot also activate.
		get_viewport().set_input_as_handled()

func _physics_process(_delta: float) -> void:
	if host == null or not host._can_control_character():
		return
	var screen := Vector2(float(held_keys.has(KEY_D)) - float(held_keys.has(KEY_A)),
		float(held_keys.has(KEY_S)) - float(held_keys.has(KEY_W)))
	var right := Vector3(cos(host.orbit_yaw), 0, -sin(host.orbit_yaw))
	var back := Vector3(sin(host.orbit_yaw), 0, cos(host.orbit_yaw))
	var desired := right * screen.x + back * screen.y
	last_direction = Vector2(desired.x, desired.z).limit_length(1.0)
	host._send_character_input(last_direction, jump_requested)
	jump_requested = false

func _process(_delta: float) -> void:
	refresh()

func _new_view(actor: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Character" + actor
	root.set_meta("actor", actor)
	var mesh := MeshInstance3D.new()
	mesh.name = "BodyView"
	var capsule := CapsuleMesh.new()
	capsule.radius = Geometry.CAPSULE_RADIUS
	capsule.height = Geometry.CAPSULE_HEIGHT
	mesh.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("e5d5ad") if actor == host.client else Color("8ab6c5")
	material.roughness = 0.8
	mesh.material_override = material
	root.add_child(mesh)
	var label := Label3D.new()
	label.text = actor + (" · YOU" if actor == host.client else "")
	label.position = Vector3(0, Geometry.CAPSULE_HEIGHT / 2 + 0.3, 0)
	label.font_size = 30
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
	add_child(root)
	return root

func refresh() -> void:
	if host == null:
		return
	var actors: Dictionary = host.state.get("actors", {})
	for actor in views.keys():
		if not actors.has(actor):
			var old: Node3D = views[actor]
			remove_child(old)
			old.queue_free()
			views.erase(actor)
	for actor in actors:
		if not views.has(actor):
			views[actor] = _new_view(actor)
		var data: Dictionary = actors[actor]
		var view: Node3D = views[actor]
		view.visible = data.get("ready", false) and Geometry.valid_position(data.get("position"))
		if view.visible:
			var at: Array = data.position
			view.position = Vector3(at[0], at[1], at[2])
	if not host.explanation_open and actors.has(host.client) and Geometry.valid_position(actors[host.client].get("position")):
		var at: Array = actors[host.client].position
		host.focus = Vector3(at[0], at[1] + 0.3, at[2])
		host._update_camera()
