extends RefCounted
## Fitted 3D render assemblies for raw seam blanks, in-line workpiece billets
## and finished stamped plates. Pure presentation: no collision, input or state
## authority, and all geometry stays inside the existing item envelopes.

const Visuals = preload("res://opening/opening.gd").ProductionVisuals
const Geometry = preload("res://opening/site_geometry.gd")

const SEAM_HALF_EXTENTS := Vector3(0.10, 0.09, 0.14)
const BILLET_HALF_EXTENTS := Vector3(0.135, 0.09, 0.18)
const PLATE_HALF_EXTENTS := Vector3(0.22, 0.035, 0.265)


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


static func seam_blank(parent: Node3D, at: Vector3 = Vector3.ZERO) -> Node3D:
	var assembly := Node3D.new()
	assembly.name = "SeamBlank"
	assembly.position = at
	assembly.set_meta("item_kind", "seam_blank")
	parent.add_child(assembly)
	_part(assembly, "SeamCradle", Visuals.box_mesh(Vector3(0.192, 0.036, 0.268)),
		Vector3(0.0, -0.068, 0.0), Color("354448"), 0.72, 0.54)
	_part(assembly, "BlankIngot", Visuals.box_mesh(Vector3(0.168, 0.112, 0.236)),
		Vector3(0.0, 0.004, 0.0), Color("b89154"), 0.78, 0.44)
	for side in [-1.0, 1.0]:
		var z_off: float = float(side) * 0.068
		_part(assembly, "ClampBand", Visuals.box_mesh(Vector3(0.182, 0.096, 0.032)),
			Vector3(0.0, 0.004, z_off), Color("54676b"), 0.82, 0.42)
	_part(assembly, "LiftingLug", Visuals.turned_mesh(lug_profile(), 32),
		Vector3(0.0, 0.060, 0.0), Color("d4ae6a"), 0.85, 0.35)
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
		seam_blank(
			item_root,
			Vector3(-0.16 + float(n % 2) * 0.32, 0.11, -2.9 + float(int(n / 2.0)) * 1.15)
		)
