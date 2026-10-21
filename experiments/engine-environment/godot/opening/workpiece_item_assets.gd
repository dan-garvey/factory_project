extends RefCounted
## Natural source clusters and fitted in-line workpiece billets
## and finished stamped plates. Pure presentation: no collision, input or state
## authority, and all geometry stays inside the existing item envelopes.

const Visuals = preload("res://opening/opening.gd").ProductionVisuals
const Scenery = preload("res://opening/opening.gd").ProductionEnvironment
const Geometry = preload("res://opening/site_geometry.gd")

const SEAM_HALF_EXTENTS := Vector3(0.10, 0.09, 0.14)
const BILLET_HALF_EXTENTS := Vector3(0.135, 0.09, 0.18)
const PLATE_HALF_EXTENTS := Vector3(0.22, 0.035, 0.265)
static var raw_seam_meshes: Dictionary = {}


static func _part(parent: Node3D, role: String, mesh: Mesh, at: Vector3,
		color: Color, metal: float = 0.84, roughness: float = 0.38) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = role
	instance.set_meta("asset_role", role)
	instance.mesh = mesh
	instance.position = at
	instance.material_override = Visuals.material(color, metal, roughness)
	parent.add_child(instance)
	return instance


static func boss_profile() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(0.044, 0.0),
		Vector2(0.050, 0.005),
		Vector2(0.050, 0.022),
		Vector2(0.042, 0.028),
		Vector2(0.0, 0.028),
	])


static func lug_profile() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(0.036, 0.0),
		Vector2(0.042, 0.004),
		Vector2(0.042, 0.020),
		Vector2(0.034, 0.025),
		Vector2(0.0, 0.025),
	])


static func bushing_profile() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.036, -0.008),
		Vector2(0.040, -0.012),
		Vector2(0.074, -0.012),
		Vector2(0.078, -0.008),
		Vector2(0.078, 0.014),
		Vector2(0.074, 0.018),
		Vector2(0.040, 0.018),
		Vector2(0.036, 0.014),
		Vector2(0.036, -0.008),
	])


static func rivet_profile() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(0.020, 0.0),
		Vector2(0.022, 0.002),
		Vector2(0.022, 0.006),
		Vector2(0.016, 0.010),
		Vector2(0.0, 0.010),
	])


static func raw_seam_mesh(variant: int = 0) -> ArrayMesh:
	var key := posmod(variant, 3)
	if raw_seam_meshes.has(key):
		return raw_seam_meshes[key]
	# Three deterministic fracture shapes, all inside the existing item envelope.
	# These are surface art, not native colliders or an extra stock ledger.
	var vertices := PackedVector3Array([Vector3(0.0, -0.09, 0.0)])
	for ring in range(2):
		for n in range(8):
			var angle := float(n) * TAU / 8.0 + float(key) * 0.18
			var radius := 0.80 + 0.12 * sin(float(n) * 2.3 + float(key) * 1.7 + float(ring) * 0.75)
			var y := -0.055 if ring == 0 else 0.035 + 0.014 * sin(float(n) * 1.9 + float(key))
			vertices.append(Vector3(cos(angle) * 0.094 * radius, y, sin(angle) * 0.133 * radius))
	vertices.append(Vector3(0.012 * sin(float(key)), 0.083, -0.01 * cos(float(key))))
	var faces: Array = []
	for n in range(8):
		var next := (n + 1) % 8
		faces.append_array([[0, 1 + n, 1 + next], [1 + n, 9 + n, 9 + next],
			[1 + n, 9 + next, 1 + next], [17, 9 + next, 9 + n]])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var a := vertices[face[0]]
		var b := vertices[face[1]]
		var c := vertices[face[2]]
		var normal := (c - a).cross(b - a).normalized()
		if normal.dot((a + b + c) / 3.0) < 0.0:
			var swap := b
			b = c
			c = swap
			normal = -normal
		for point in [a, b, c]:
			var uv := Vector2(point.x, point.z)
			if absf(normal.x) > absf(normal.y) and absf(normal.x) >= absf(normal.z):
				uv = Vector2(point.z, point.y)
			elif absf(normal.z) > absf(normal.y):
				uv = Vector2(point.x, point.y)
			surface.set_normal(normal)
			surface.set_uv(uv * 6.0)
			surface.add_vertex(point)
	surface.generate_tangents()
	var mesh := surface.commit()
	raw_seam_meshes[key] = mesh
	return mesh


static func seam_blank(parent: Node3D, at: Vector3 = Vector3.ZERO, variant: int = 0) -> Node3D:
	var key := posmod(variant, 3)
	var assembly := Node3D.new()
	assembly.name = "SeamBlank"
	assembly.position = at
	assembly.set_meta("item_kind", "seam_blank")
	assembly.set_meta("source_variant", key)
	parent.add_child(assembly)
	var host := _part(assembly, "RawHostRock", raw_seam_mesh(key), Vector3.ZERO, Color("6e6554"), 0.0, 0.88)
	host.material_override = Scenery.stone_material()
	var deposits := [Vector3(-0.03, 0.02, 0.085), Vector3(0.04, 0.036, 0.055), Vector3(-0.005, 0.041, -0.074)]
	var scales := [Vector3(0.34, 0.40, 0.32), Vector3(0.29, 0.34, 0.33), Vector3(0.34, 0.36, 0.34)]
	for n in range(3):
		var mineral := _part(assembly, "RawMineral", raw_seam_mesh(key + n + 1), deposits[n],
			Color("b69962"), 0.62, 0.48)
		mineral.scale = scales[n]
	return assembly


static func workpiece_billet(parent: Node3D, at: Vector3 = Vector3.ZERO) -> Node3D:
	var assembly := Node3D.new()
	assembly.name = "WorkpieceBillet"
	assembly.position = at
	assembly.set_meta("item_kind", "workpiece_billet")
	parent.add_child(assembly)
	_part(assembly, "CarrierTray", Visuals.box_mesh(Vector3(0.26, 0.036, 0.34)),
		Vector3(0.0, -0.068, 0.0), Color("38494e"), 0.78, 0.48)
	for side in [-1.0, 1.0]:
		var x_off: float = float(side) * 0.11
		_part(assembly, "TrayRail", Visuals.box_mesh(Vector3(0.028, 0.032, 0.32)),
			Vector3(x_off, -0.034, 0.0), Color("52666b"), 0.80, 0.44)
	_part(assembly, "BilletCore", Visuals.box_mesh(Vector3(0.18, 0.104, 0.29)),
		Vector3(0.0, 0.002, 0.0), Color("d8b26e"), 0.86, 0.34)
	for side in [-1.0, 1.0]:
		var z_off: float = float(side) * 0.085
		_part(assembly, "IndexRib", Visuals.box_mesh(Vector3(0.196, 0.028, 0.038)),
			Vector3(0.0, 0.042, z_off), Color("b87945"), 0.84, 0.38)
	_part(assembly, "CenterBoss", Visuals.turned_mesh(boss_profile(), 32),
		Vector3(0.0, 0.054, 0.0), Color("b6c2bc"), 0.88, 0.30)
	return assembly


static func stamped_plate(parent: Node3D, at: Vector3 = Vector3.ZERO) -> Node3D:
	var assembly := Node3D.new()
	assembly.name = "StampedPlate"
	assembly.position = at
	assembly.set_meta("item_kind", "stamped_plate")
	parent.add_child(assembly)
	_part(assembly, "PlateSheet", Visuals.box_mesh(Vector3(0.42, 0.032, 0.50)),
		Vector3(0.0, -0.014, 0.0), Color("dce0d9"), 0.88, 0.28)
	for side in [-1.0, 1.0]:
		var x_off: float = float(side) * 0.155
		var z_off: float = float(side) * 0.195
		_part(assembly, "StampedRim", Visuals.box_mesh(Vector3(0.044, 0.022, 0.44)),
			Vector3(x_off, 0.011, 0.0), Color("b6c2bc"), 0.86, 0.32)
		_part(assembly, "StampedRim", Visuals.box_mesh(Vector3(0.26, 0.022, 0.044)),
			Vector3(0.0, 0.011, z_off), Color("b6c2bc"), 0.86, 0.32)
	_part(assembly, "PlateBushing", Visuals.turned_mesh(bushing_profile(), 48),
		Vector3(0.0, 0.012, 0.0), Color("c89654"), 0.86, 0.32)
	var rivet_mesh: ArrayMesh = Visuals.turned_mesh(rivet_profile(), 6)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var rx: float = float(sx) * 0.155
			var rz: float = float(sz) * 0.195
			_part(assembly, "PlateFastener", rivet_mesh,
				Vector3(rx, 0.022, rz), Color("8d9c9b"), 0.85, 0.36)
	return assembly


static func populate_items(item_root: Node3D, state: Dictionary, pitch: float = Geometry.PITCH) -> void:
	for child in item_root.get_children():
		item_root.remove_child(child)
		child.free()
	var entities: Variant = state.get("entities", {})
	var stock_val: Variant = state.get("stock", {})
	if not (entities is Dictionary and stock_val is Dictionary):
		return
	var stock: Dictionary = stock_val
	for entity_id: Variant in entities.keys():
		var entity_val: Variant = entities[entity_id]
		if not (entity_val is Dictionary):
			continue
		var entity: Dictionary = entity_val
		var cell: Variant = entity.get("cell", [])
		if not (cell is Array and cell.size() == 2):
			continue
		var pos := Vector3(float(cell[0]) * pitch, 0.0, float(cell[1]) * pitch)
		var kind := str(entity.get("kind", ""))
		var amount := 0
		if kind in ["collector", "belt"]:
			amount = int(stock.get(kind, 0))
		elif kind == "processor":
			amount = int(stock.get("held", 0)) + int(stock.get("input", 0))
		for n in range(amount):
			workpiece_billet(item_root, pos + Vector3(-0.17 + float(n) * 0.32, 0.65, 0.0))
		if kind == "processor" and int(stock.get("output", 0)) > 0:
			stamped_plate(item_root, pos + Vector3(0.46, 0.39, 0.15))
	var source_count: int = mini(16, maxi(0, int(stock.get("source", 0))))
	for n in range(source_count):
		var at := Vector3(-0.16 + float(n % 2) * 0.32, 0.11, -2.9 + float(int(n / 2.0)) * 1.15)
		if state.get("options", {}).get("physical", false) and Scenery.Surface != null:
			var ground: float = Scenery.Surface.height_at(at.x, at.z)
			if not is_finite(ground):
				push_error("The physical source display requires its shared ground surface.")
				return
			# Embed the lowest host-rock vertex by 15 mm. This is unsaved
			# surface art, not a changed source position, collider or build anchor.
			at.y = ground + SEAM_HALF_EXTENTS.y - 0.015
		seam_blank(item_root, at, n)
