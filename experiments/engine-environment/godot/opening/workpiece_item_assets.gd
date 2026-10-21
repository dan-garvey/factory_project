extends RefCounted
## A natural mineral exposure, fitted in-line billets and stamped plates.
## Pure presentation: no collision, input, quantities or state authority.

const Visuals = preload("res://opening/opening.gd").ProductionVisuals
const Scenery = preload("res://opening/opening.gd").ProductionEnvironment
const Geometry = preload("res://opening/site_geometry.gd")

const BILLET_HALF_EXTENTS := Vector3(0.135, 0.09, 0.18)
const PLATE_HALF_EXTENTS := Vector3(0.22, 0.035, 0.265)
static var source_bounds := Rect2()
static var source_meshes: Dictionary = {}
static var source_rock: StandardMaterial3D
static var source_mineral: StandardMaterial3D


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


static func _seam_point(point: Vector2, mineral: bool = false) -> Vector3:
	# Millimetres of surface art follow the same terrain as the native body.
	# The exposure is neither a new solid obstacle nor a local build datum.
	var lift := 0.015 + 0.008 * sin(point.x * 5.1 + point.y) * cos(point.y * 4.3)
	return Vector3(point.x, Scenery.Surface.height_at(point.x, point.y) + lift + (0.006 if mineral else 0.0), point.y)


static func _seam_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	if normal.y < 0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.set_uv(Vector2(point.x, point.z))
		surface.add_vertex(point)


static func _seam_mesh(bounds: Rect2, band: int) -> ArrayMesh:
	if bounds != source_bounds:
		source_bounds = bounds
		source_meshes.clear()
	if source_meshes.has(band):
		return source_meshes[band]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := bounds.get_center()
	var half_size := bounds.size * 0.48
	if band == -1:
		for n in range(32):
			var ring: Array[Vector2] = []
			for index in [n, (n + 1) % 32]:
				var angle := float(index) * TAU / 32.0
				var radius := 0.96 + 0.025 * sin(3.0 * angle + 0.5) + 0.015 * sin(7.0 * angle - 1.2)
				ring.append(Vector2(cos(angle), sin(angle)) * half_size * radius)
			var inner_a := _seam_point(center + ring[0] * 0.43)
			var inner_b := _seam_point(center + ring[1] * 0.43)
			var outer_a := _seam_point(center + ring[0])
			var outer_b := _seam_point(center + ring[1])
			_seam_triangle(surface, _seam_point(center), inner_a, inner_b)
			_seam_triangle(surface, inner_a, outer_a, outer_b)
			_seam_triangle(surface, inner_a, outer_b, inner_b)
	else:
		# Branching fractures, not one repeated mesh for each stored unit.
		var paths := [
			[Vector2(-0.65, -0.45), Vector2(-0.42, -0.46), Vector2(-0.20, -0.15), Vector2(0.12, 0.08), Vector2(0.18, 0.35), Vector2(0.48, 0.60), Vector2(0.64, 0.45)],
			[Vector2(-0.70, 0.32), Vector2(-0.52, 0.25), Vector2(-0.40, 0.05), Vector2(-0.20, -0.15)],
			[Vector2(0.12, 0.08), Vector2(0.46, -0.10), Vector2(0.62, -0.38), Vector2(0.62, -0.48)],
			[Vector2(0.18, 0.35), Vector2(-0.13, 0.58), Vector2(-0.20, 0.72)],
			[Vector2(-0.42, -0.46), Vector2(-0.40, -0.68)]]
		var width := 0.065 * sqrt(float(band) / 8.0)
		for branch in range(paths.size()):
			var path: Array = paths[branch]
			for segment in range(path.size() - 1):
				var start: Vector2 = center + path[segment] * half_size
				var finish: Vector2 = center + path[segment + 1] * half_size
				var along := start.direction_to(finish)
				var across := Vector2(-along.y, along.x)
				for step in range(6):
					var edges: Array[Vector3] = []
					for index in [step, step + 1]:
						var t := float(index) / 6.0
						var phase := float(branch * 7 + segment * 3) + t * 3.7
						var at := start.lerp(finish, t) + across * sin(t * PI) * sin(phase) * 0.025
						var radius := width * (0.72 + 0.28 * sin(phase + 0.9))
						edges.append(_seam_point(at - across * radius, true))
						edges.append(_seam_point(at + across * radius, true))
					_seam_triangle(surface, edges[0], edges[2], edges[3])
					_seam_triangle(surface, edges[0], edges[3], edges[1])
	surface.generate_tangents()
	var mesh := surface.commit()
	source_meshes[band] = mesh
	return mesh


static func mineral_deposit(parent: Node3D, state: Dictionary, pitch: float) -> void:
	var cells: Array = state.get("source_deposit", {}).get("cells", [])
	if cells.is_empty():
		return
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for cell in cells:
		var center := Vector2(cell[0], cell[1]) * pitch
		low = low.min(center - Vector2.ONE * pitch / 2.0)
		high = high.max(center + Vector2.ONE * pitch / 2.0)
	var bounds := Rect2(low, high - low)
	var initial := maxi(1, int(state.initial_feed))
	var fraction := clampf(float(state.stock.source) / float(initial), 0.0, 1.0)
	var band := ceili(fraction * 8.0)
	if source_rock == null:
		source_rock = Scenery.stone_material().duplicate()
		source_rock.albedo_color = Color("766c61")
		source_mineral = Scenery.stone_material().duplicate()
		source_mineral.albedo_color = Color("c2935a")
		source_mineral.metallic = 0.48
		source_mineral.roughness = 0.62
	var exposure := Node3D.new()
	exposure.name = "MineralDeposit"
	exposure.set_meta("item_kind", "mineral_deposit")
	exposure.set_meta("remaining", state.stock.source)
	exposure.set_meta("depletion_band", band)
	parent.add_child(exposure)
	var host := _part(exposure, "ExposedRock", _seam_mesh(bounds, -1), Vector3.ZERO, Color.WHITE)
	host.material_override = source_rock
	if band > 0:
		var mineral := _part(exposure, "MineralVeins", _seam_mesh(bounds, band), Vector3.ZERO, Color.WHITE)
		mineral.material_override = source_mineral


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
		var pos := Vector3(float(cell[0]) * pitch, float(entity.get("level", 0)) * Geometry.HEIGHT_STEP, float(cell[1]) * pitch)
		var kind := str(entity.get("kind", ""))
		var amount := 0
		if kind in ["collector", "belt"]:
			amount = int(stock.get(kind, 0))
		elif kind == "processor":
			amount = int(stock.get("held", 0)) + int(stock.get("input", 0))
		for n in range(amount):
			var offset := Vector3(-0.17 + float(n) * 0.32, 0.65, 0.0)
			if kind == "collector":
				# The native buffer's 32 blanks fit in a four-by-four, two-layer
				# pile inside its body, rather than spilling across other machines.
				offset = Vector3((float(n % 4) - 1.5) * 0.27,
					0.65 + float(int(n / 16.0)) * 0.18, (float(int(n / 4.0) % 4) - 1.5) * 0.36)
			workpiece_billet(item_root, pos + offset)
		if kind == "processor" and int(stock.get("output", 0)) > 0:
			stamped_plate(item_root, pos + Vector3(0.46, 0.39, 0.15))
	mineral_deposit(item_root, state, pitch)
