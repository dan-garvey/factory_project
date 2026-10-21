extends RefCounted
## Pure render assemblies. The presenter retains axes, picks and native facts.
const Visuals = preload("res://opening/opening.gd").ProductionVisuals
const Finish = preload("res://opening/opening.gd").ProductionTransmissionFinish
const UNIT := preload("res://opening/site_geometry.gd").PITCH / 4.0
const SHAFT_CORE_RADIUS := 0.03
static var meshes: Dictionary = {}

static func _part(parent: Node3D, name_value: String, mesh: Mesh, at: Vector3,
		color: Color, metal: float = 0.85, roughness: float = 0.38) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.set_meta("asset_role", name_value)
	instance.mesh = mesh
	instance.position = at
	if name_value == "ShaftKey":
		instance.material_override = Visuals.material(color, metal, roughness)
		instance.set_meta("surface_role", "copper")
	else:
		var surface_role := "cast" if name_value in ["Gear", "GearSpoke"] else "worked"
		instance.material_override = Finish.material(surface_role, color, metal, roughness)
		instance.set_meta("surface_role", surface_role)
	parent.add_child(instance)
	return instance

static func _cylinder(radius: float, height: float, segments: int = 48) -> CylinderMesh:
	var key := [radius, height, segments]
	if not meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = segments
		meshes[key] = mesh
	return meshes[key]

static func _face(surface: SurfaceTool, points: Array[Vector3], center: Vector3) -> void:
	var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var middle := Vector3.ZERO
	for point in points:
		middle += point / float(points.size())
	if normal.dot(middle - center) < 0:
		normal = -normal
	# The common face builder reverses its input to select clockwise winding.
	# Preserve ring order for the side faces that still need these vertices.
	Visuals._face(surface, points.duplicate(), normal)

static func tooth_mesh(radius: float, teeth: int) -> ArrayMesh:
	var key := ["tooth", radius, teeth]
	if meshes.has(key):
		return meshes[key]
	var pitch := TAU * radius / float(teeth)
	var root := radius - 0.1
	var tip_width := pitch * 0.17
	# Outer corners stay inside the unchanged native radius, rather than
	# enlarging the occupied/pick envelope to accommodate decorative detail.
	var tip_x := sqrt(radius * radius - tip_width * tip_width)
	var outline := PackedVector2Array([Vector2(root - 0.015, -pitch * 0.34),
		Vector2(tip_x, -tip_width), Vector2(tip_x, tip_width), Vector2(root - 0.015, pitch * 0.34)])
	var center := Vector3((root - 0.015 + tip_x) / 2.0, 0, 0)
	var rings: Array = []
	for row in [[-0.07, 0.92], [-0.06, 1.0], [0.06, 1.0], [0.07, 0.92]]:
		var points: Array[Vector3] = []
		for point in outline:
			points.append(Vector3(lerpf(center.x, point.x, row[1]), row[0], point.y * row[1]))
		rings.append(points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_face(surface, rings[0], center)
	_face(surface, rings[3], center)
	for row in range(3):
		for side in range(4):
			var next := (side + 1) % 4
			_face(surface, [rings[row][side], rings[row][next], rings[row + 1][next], rings[row + 1][side]], center)
	surface.generate_tangents()
	var mesh := surface.commit()
	meshes[key] = mesh
	return mesh

static func _fastener(parent: Node3D, at: Vector3, positive: bool) -> void:
	var fastener := _part(parent, "HubFastener", _cylinder(0.022, 0.012, 6), at, Color("b8c3bb"))
	if not positive:
		fastener.rotation.x = PI

static func gear(parent: Node3D, radius: float, ratio_units: int, color: Color) -> void:
	# Eight render teeth per native ratio/radius unit. This tessellation stays
	# proportional; it does not change the wire parameter or model tooth contact.
	var count := ratio_units * 8
	var inner := radius * 0.56
	var outer := radius - 0.1
	var rim := PackedVector2Array([Vector2(inner + 0.006, -0.07), Vector2(outer - 0.006, -0.07),
		Vector2(outer, -0.06), Vector2(outer, 0.06), Vector2(outer - 0.006, 0.07),
		Vector2(inner + 0.006, 0.07), Vector2(inner, 0.06), Vector2(inner, -0.06), Vector2(inner + 0.006, -0.07)])
	_part(parent, "Gear", Visuals.turned_mesh(rim, maxi(48, count * 2)), Vector3.ZERO, color)
	var tooth := tooth_mesh(radius, count)
	for n in range(count):
		var part := _part(parent, "GearTooth", tooth, Vector3.ZERO, color)
		part.rotation.y = float(n) * TAU / count
	var hub_radius := minf(0.16, radius * 0.34)
	var hub := PackedVector2Array([Vector2(0, -0.11), Vector2(hub_radius - 0.008, -0.11),
		Vector2(hub_radius, -0.102), Vector2(hub_radius, 0.102),
		Vector2(hub_radius - 0.008, 0.11), Vector2(0, 0.11)])
	_part(parent, "Hub", Visuals.turned_mesh(hub), Vector3.ZERO, Color("a6b4af"))
	var spoke_length := inner - hub_radius + 0.04
	for n in range(4):
		var angle := float(n) * PI / 2.0
		var spoke := _part(parent, "GearSpoke", Visuals.box_mesh(Vector3(spoke_length, 0.08, 0.09)),
			Vector3(cos(angle), 0, sin(angle)) * (hub_radius + inner) / 2.0, color)
		spoke.rotation.y = -angle
		for side in [-1.0, 1.0]:
			_fastener(parent, Vector3(cos(angle) * hub_radius * 0.65, side * 0.108,
				sin(angle) * hub_radius * 0.65), side > 0)

static func shaft(parent: Node3D, length: float, color: Color) -> void:
	# Keep this public node's CylinderMesh and exact length for the established
	# endpoint consumer. Fitted collars do not alter the pick cylinder.
	_part(parent, "Shaft", _cylinder(SHAFT_CORE_RADIUS, length), Vector3.ZERO, color)
	var collar := PackedVector2Array([Vector2(0.03, -0.055), Vector2(0.0345, -0.055),
		Vector2(0.036, -0.0535), Vector2(0.036, 0.0535), Vector2(0.0345, 0.055),
		Vector2(0.03, 0.055), Vector2(0.03, -0.055)])
	for sign_value in [-1.0, 1.0]:
		var center: float = sign_value * (length / 2.0 - 0.06)
		_part(parent, "ShaftCollar", Visuals.turned_mesh(collar), Vector3(0, center, 0), Color("a6b4af"))
		_part(parent, "ShaftKey", Visuals.box_mesh(Vector3(0.012, 0.08, 0.012)),
			Vector3(0.031, center, 0), Color("b87945"))
