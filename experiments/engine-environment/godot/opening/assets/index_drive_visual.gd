extends Node3D
## Optional mesh assembly. A presenter supplies every pose; this node never ticks.
## Travel is normalized to this asset's two-unit rail. Rotation is local Y only.
## Tool contact is a display input, not permission to stamp or a work-state owner.

const TRAVEL := 2.0
const ROTATION_EPSILON := 0.00001
var _meshes: Dictionary = {}
var _paint := _material(Color("295259"), 0.48, 0.56)
var _steel := _material(Color("a6b4af"), 0.85, 0.32)
var _dark := _material(Color("171f24"), 0.45, 0.66)
var _copper := _material(Color("b06133"), 0.72, 0.44)
var _carrier: Node3D
var _wheel: Node3D
var _tool: Node3D
var _contact_flag: MeshInstance3D

func _init() -> void:
	set_process(false)
	set_physics_process(false)
	_build()
	apply_visual_pose(0.0, Basis.IDENTITY, false)

func apply_visual_pose(travel_fraction: float, wheel_rotation: Basis, tool_contact: bool) -> bool:
	# Validate the complete update before changing any node. Never repair or clamp
	# an invalid supplied pose into something that could look confirmed.
	if not is_finite(travel_fraction) or travel_fraction < 0.0 or travel_fraction > 1.0:
		return false
	if not wheel_rotation.is_finite():
		return false
	for column in [wheel_rotation.x, wheel_rotation.y, wheel_rotation.z]:
		if absf(column.length_squared() - 1.0) > ROTATION_EPSILON:
			return false
	if absf(wheel_rotation.x.dot(wheel_rotation.y)) > ROTATION_EPSILON \
			or absf(wheel_rotation.x.dot(wheel_rotation.z)) > ROTATION_EPSILON \
			or absf(wheel_rotation.y.dot(wheel_rotation.z)) > ROTATION_EPSILON:
		return false
	if not wheel_rotation.y.is_equal_approx(Vector3.UP) or wheel_rotation.determinant() < 0.0:
		return false
	_carrier.position.x = TRAVEL * travel_fraction
	_wheel.basis = wheel_rotation
	_tool.position.x = -0.22 if tool_contact else 0.0
	_contact_flag.visible = tool_contact
	return true

static func _material(color: Color, metal: float, rough: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = rough
	return material

func _root(parent: Node3D, label: String, at: Vector3 = Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = label
	node.position = at
	parent.add_child(node)
	return node

func _part(parent: Node3D, label: String, mesh: Mesh, at: Vector3,
		material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.set_meta("asset_role", label)
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)
	return part

static func _face(surface: SurfaceTool, points: Array[Vector3], normal: Vector3) -> void:
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(normal) > 0.0:
		points.reverse()  # Godot front faces are clockwise.
	var direction := normal.abs()
	for i in range(1, points.size() - 1):
		for point in [points[0], points[i], points[i + 1]]:
			var uv := Vector2(point.x, point.z)
			if direction.x >= direction.y and direction.x >= direction.z:
				uv = Vector2(point.y, point.z)
			elif direction.z >= direction.y:
				uv = Vector2(point.x, point.y)
			surface.set_normal(normal)
			surface.set_uv(uv)
			surface.add_vertex(point)

func _box(size: Vector3) -> ArrayMesh:
	if _meshes.has(size):
		return _meshes[size]
	# Closed chamfers, following the worksite's machined-edge construction.
	var half := size / 2.0
	var inner := half - Vector3.ONE * minf(0.018, minf(size.x, minf(size.y, size.z)) * 0.16)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for side in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = side
			var points: Array[Vector3] = []
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = side * half[axis]
				p[u] = corner.x * inner[u]
				p[v] = corner.y * inner[v]
				points.append(p)
			_face(surface, points, normal)
	for a in range(3):
		for b in range(a + 1, 3):
			var along := 3 - a - b
			for sa in [-1.0, 1.0]:
				for sb in [-1.0, 1.0]:
					var normal := Vector3.ZERO
					var points: Array[Vector3] = []
					normal[a] = sa
					normal[b] = sb
					for end in [-1.0, 1.0]:
						var p := Vector3.ZERO
						p[a] = sa * half[a]
						p[b] = sb * inner[b]
						p[along] = end * inner[along]
						var q := p
						q[a] = sa * inner[a]
						q[b] = sb * half[b]
						points.append_array([p, q] if end < 0.0 else [q, p])
					_face(surface, points, normal.normalized())
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				_face(surface, [Vector3(x * half.x, y * inner.y, z * inner.z),
					Vector3(x * inner.x, y * half.y, z * inner.z),
					Vector3(x * inner.x, y * inner.y, z * half.z)], Vector3(x, y, z).normalized())
	surface.generate_tangents()
	var mesh := surface.commit()
	_meshes[size] = mesh
	return mesh

func _cylinder(radius: float, height: float, sides: int = 32) -> CylinderMesh:
	var key := [radius, height, sides]
	if not _meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = sides
		_meshes[key] = mesh
	return _meshes[key]

func _bolt(parent: Node3D, at: Vector3) -> void:
	_part(parent, "Washer", _cylinder(0.045, 0.012), at, _dark)
	_part(parent, "Fastener", _cylinder(0.03, 0.026, 6), at + Vector3(0, 0.015, 0), _steel)

func _build() -> void:
	var bed := _root(self, "Bed")
	_part(bed, "CastBed", _box(Vector3(3.45, 0.2, 1.5)), Vector3(1, 0.2, 0), _paint)
	for x in [-0.45, 2.45]:
		for z in [-0.55, 0.55]:
			_part(bed, "Foot", _box(Vector3(0.38, 0.11, 0.32)), Vector3(x, 0.055, z), _dark)
			_bolt(bed, Vector3(x, 0.306, z))
	for z in [-0.49, 0.49]:
		var rail := _part(bed, "GuideRail", _cylinder(0.055, 3.1), Vector3(1, 0.4, z), _steel)
		rail.rotation.z = PI / 2.0
		for x in [-0.5, 2.5]:
			_part(bed, "RailPedestal", _box(Vector3(0.18, 0.22, 0.22)), Vector3(x, 0.4, z), _paint)
			_bolt(bed, Vector3(x, 0.518, z))
	for x in [-0.58, 2.58]:
		_part(bed, "TravelStop", _box(Vector3(0.1, 0.17, 0.32)), Vector3(x, 0.42, 0), _copper)
	# Endpoints belong to this asset; they do not grant World docking authority.
	_root(bed, "DockMarker", Vector3(0, 0.84, 0))
	_root(bed, "WorkMarker", Vector3(TRAVEL, 0.84, 0))
	_carrier = _root(self, "Carrier")
	_part(_carrier, "Saddle", _box(Vector3(0.87, 0.14, 1.13)), Vector3(0, 0.54, 0), _paint)
	for x in [-0.28, 0.28]:
		for z in [-0.49, 0.49]:
			var bearing := _part(_carrier, "SlideBearing", _cylinder(0.102, 0.2), Vector3(x, 0.4, z), _copper)
			bearing.rotation.z = PI / 2.0
			_bolt(_carrier, Vector3(x, 0.618, z))
	_part(_carrier, "SpindleHousing", _cylinder(0.25, 0.17), Vector3(0, 0.685, 0), _dark)
	_part(_carrier, "SpindleCollar", _cylinder(0.21, 0.08), Vector3(0, 0.78, 0), _steel)
	_wheel = _root(_carrier, "Wheel", Vector3(0, 0.84, 0))
	# The continuous torus and hub support an open four-spoke table. The rim
	# ticks are visual registration marks, not a simulated tooth/contact system.
	var rim := TorusMesh.new()
	rim.inner_radius = 0.48
	rim.outer_radius = 0.64
	rim.rings = 48
	rim.ring_segments = 12
	_part(_wheel, "TableRim", rim, Vector3.ZERO, _dark)
	_part(_wheel, "TableHub", _cylinder(0.19, 0.2), Vector3(0, 0.03, 0), _copper)
	for quarter in range(4):
		var arm := _root(_wheel, "TableArm")
		arm.rotation.y = quarter * PI / 2.0
		_part(arm, "Spoke", _box(Vector3(0.46, 0.09, 0.14)), Vector3(0.35, 0, 0), _paint)
		_part(arm, "Registration", _box(Vector3(0.08, 0.015, 0.12)), Vector3(0.56, 0.085, 0),
			_copper if quarter == 0 else _steel)
	_part(_wheel, "NestFloor", _box(Vector3(0.65, 0.06, 0.65)), Vector3(0, 0.17, 0), _steel)
	for x in [-0.29, 0.29]:
		for z in [-0.29, 0.29]:
			_part(_wheel, "CornerJaw", _box(Vector3(0.13, 0.24, 0.13)), Vector3(x, 0.31, z), _paint)
			_bolt(_wheel, Vector3(x, 0.438, z))
	_root(_wheel, "WorkpieceMarker", Vector3(0, 0.31, 0))
	var head := _root(self, "SideToolMount")
	_part(head, "Foot", _box(Vector3(0.6, 0.15, 1.25)), Vector3(3.05, 0.075, 0), _dark)
	_part(head, "Column", _box(Vector3(0.28, 1.2, 0.44)), Vector3(3.14, 0.7, 0), _paint)
	for z in [-0.45, 0.45]:
		_bolt(head, Vector3(3.05, 0.158, z))
	var sleeve := _part(head, "ToolSleeve", _cylinder(0.16, 0.45), Vector3(2.94, 1.15, 0), _copper)
	sleeve.rotation.z = PI / 2.0
	_tool = _root(head, "Tool")
	var rod := _part(_tool, "ToolRod", _cylinder(0.07, 0.64), Vector3(2.78, 1.15, 0), _steel)
	rod.rotation.z = PI / 2.0
	_part(_tool, "ToolFace", _box(Vector3(0.08, 0.2, 0.2)), Vector3(2.48, 1.15, 0), _dark)
	_contact_flag = _part(head, "ContactDisplay", _box(Vector3(0.06, 0.09, 0.18)), Vector3(3.31, 1.2, 0), _copper)
