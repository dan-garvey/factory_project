extends Node3D
## A first-click annotation, not a target, physical part or connection preview.
const Geometry = preload("res://opening/site_geometry.gd")
const UNIT := Geometry.PITCH / 4.0

var _key := ""
var _ring: MeshInstance3D
var _caption: Label3D

func _init() -> void:
	visible = false
	_ring = MeshInstance3D.new()
	_ring.name = "EndpointRing"
	var shape := TorusMesh.new()
	shape.rings = 32
	shape.ring_segments = 8
	_ring.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("edcc8d")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	_ring.material_override = material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_caption = Label3D.new()
	_caption.name = "EndpointCaption"
	_caption.text = "First endpoint"
	_caption.font_size = 24
	_caption.pixel_size = 0.005
	_caption.modulate = Color("edcc8d")
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_caption.no_depth_test = true
	add_child(_caption)

func refresh(endpoint: Dictionary) -> void:
	var center: Variant = endpoint.get("center")
	var axis: Variant = endpoint.get("axis")
	var valid: bool = typeof(endpoint.get("id")) == TYPE_STRING and not str(endpoint.get("id", "")).is_empty()
	valid = valid and center is Array and center.size() == 3 and typeof(axis) == TYPE_INT and axis in [0, 1, 2]
	valid = valid and endpoint.get("kind") in ["collector", "belt", "processor", "wheel", "gear"]
	if valid:
		for coordinate: Variant in center:
			valid = valid and typeof(coordinate) == TYPE_INT and coordinate >= -1048576 and coordinate <= 1048576
	var teeth: Variant = endpoint.get("teeth", 0)
	if endpoint.get("kind") == "gear":
		valid = valid and typeof(teeth) == TYPE_INT and teeth > 0 and teeth <= 256
	visible = valid
	if not valid:
		_key = ""
		return
	var next_key := JSON.stringify(endpoint)
	if next_key == _key:
		return
	_key = next_key
	position = Vector3(center[0] * UNIT, Geometry.ANCHOR_HEIGHT + center[1] * UNIT, center[2] * UNIT)
	match axis:
		0: basis = Basis(Vector3.DOWN, Vector3.RIGHT, Vector3.BACK)
		1: basis = Basis.IDENTITY
		2: basis = Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
	var radius: float = float(teeth) * UNIT + 0.08 if endpoint.kind == "gear" else 0.28
	var shape: TorusMesh = _ring.mesh
	shape.inner_radius = radius
	shape.outer_radius = radius + 0.04
	# Keep the caption above the spindle for every supported spindle direction.
	_caption.position = basis.inverse() * Vector3.UP * (radius + 0.25)
