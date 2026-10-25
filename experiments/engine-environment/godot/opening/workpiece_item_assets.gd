extends RefCounted
## A natural mineral exposure, fitted in-line billets and stamped plates.
## Pure presentation: no collision, input, quantities or state authority.

const Visuals = preload("res://opening/opening.gd").ProductionVisuals
const Scenery = preload("res://opening/opening.gd").ProductionEnvironment
const Geometry = preload("res://opening/site_geometry.gd")

const BILLET_HALF_EXTENTS := Vector3(0.135, 0.09, 0.18)
const PLATE_HALF_EXTENTS := Vector3(0.22, 0.035, 0.265)
static var source_meshes: Dictionary = {}
static var ground_meshes: Dictionary = {}
static var source_rock: StandardMaterial3D
static var source_mineral: StandardMaterial3D
static var source_ground: StandardMaterial3D
static var source_triangles: TriangleMesh
static var source_to_world := Transform3D.IDENTITY
static var world_to_source := Transform3D.IDENTITY
static var source_ray_height := 0.0


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


static func _prepare_source_query() -> void:
	if source_triangles == null:
		var spec: Dictionary = Scenery.Surface.source_outcrop()
		source_triangles = Scenery.Surface.SOURCE_OUTCROP_MESH.generate_triangle_mesh()
		source_to_world = Transform3D(spec.basis, spec.center)
		world_to_source = source_to_world.affine_inverse()
		source_ray_height = spec.center.y + spec.size.y


static func _seam_point(point: Vector2, ridge: float = 0.0) -> Vector3:
	# A native mesh query drapes the cosmetic veins over the delivered rock.
	# It never supplies construction height or a second collision authority.
	_prepare_source_query()
	var origin := Vector3(point.x, source_ray_height, point.y)
	var hit := source_triangles.intersect_ray(world_to_source * origin, world_to_source.basis * Vector3.DOWN)
	if hit.is_empty():
		push_error("A mineral vein lies outside the fixed source outcrop.")
		return Vector3(NAN, NAN, NAN)
	var at: Vector3 = source_to_world * hit.position
	return at + Vector3.UP * (0.006 + ridge)


static func _side_seam_point(point: Vector2, ridge: float = 0.0) -> Vector3:
	# Project from outside the west flank. The ridge remains cosmetic and
	# follows the same immutable rock as the top relief and actor collider.
	_prepare_source_query()
	var spec: Dictionary = Scenery.Surface.source_outcrop()
	var origin := Vector3(spec.center.x - spec.size.x * 0.5 - 0.1, point.y, point.x)
	var hit := source_triangles.intersect_ray(world_to_source * origin, world_to_source.basis * Vector3.RIGHT)
	if hit.is_empty():
		push_error("A side mineral vein lies outside the fixed source outcrop.")
		return Vector3(NAN, NAN, NAN)
	var at: Vector3 = source_to_world * hit.position
	return at + Vector3.LEFT * (0.006 + ridge)


static func _seam_radius(angle: float) -> float:
	return 0.78 + 0.12 * sin(3.0 * angle + 0.5) + 0.065 * sin(5.0 * angle - 1.7) + 0.04 * cos(9.0 * angle)


static func _seam_offset(point: Vector2, half_size: Vector2) -> Vector2:
	return point * half_size * _seam_radius(point.angle())


static func _seam_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, opacity: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	if normal.y < 0:
		var swap := b
		b = c
		c = swap
		opacity = Vector3(opacity.x, opacity.z, opacity.y)
		normal = -normal
	for index in range(3):
		var point: Vector3 = [a, b, c][index]
		surface.set_normal(normal)
		surface.set_uv(Vector2(point.x, point.z))
		surface.set_color(Color(1.0, 1.0, 1.0, opacity[index]))
		surface.add_vertex(point)


static func _side_seam_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	if normal.x > 0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.set_uv(Vector2(point.z, point.y))
		surface.set_color(Color.WHITE)
		surface.add_vertex(point)


static func _seam_mesh(band: int) -> ArrayMesh:
	if source_meshes.has(band):
		return source_meshes[band]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spec: Dictionary = Scenery.Surface.source_outcrop()
	var center := Vector2(spec.center.x, spec.center.z)
	var half_size := Vector2(spec.size.x, spec.size.z) * 0.44
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
			var start: Vector2 = path[segment]
			var finish: Vector2 = path[segment + 1]
			var along := ((finish - start) * half_size).normalized()
			var across := Vector2(-along.y, along.x)
			for step in range(6):
				var edges: Array[Vector3] = []
				var crests: Array[Vector3] = []
				for index in [step, step + 1]:
					var t := float(index) / 6.0
					var phase := float(branch * 7 + segment * 3) + t * 3.7
					var local := start.lerp(finish, t)
					var at := center + _seam_offset(local, half_size) + across * sin(t * PI) * sin(phase) * 0.025
					var radius := width * (0.72 + 0.28 * sin(phase + 0.9)) * _seam_radius(local.angle())
					edges.append(_seam_point(at - across * radius))
					edges.append(_seam_point(at + across * radius))
					crests.append(_seam_point(at, 0.008 * (0.8 + 0.2 * sin(phase))))
				_seam_triangle(surface, edges[0], crests[0], crests[1], Vector3.ONE)
				_seam_triangle(surface, edges[0], crests[1], edges[2], Vector3.ONE)
				_seam_triangle(surface, crests[0], edges[1], edges[3], Vector3.ONE)
				_seam_triangle(surface, crests[0], edges[3], crests[1], Vector3.ONE)
	# The ordinary construction view sees the rock's west flank. Carry the
	# same reserve band over that real surface instead of adding loose ore props.
	var side_paths := [
		[Vector2(-0.22, -0.12), Vector2(-0.10, -0.08), Vector2(0.02, 0.01),
			Vector2(0.13, 0.08), Vector2(0.22, 0.10)],
		[Vector2(-0.10, -0.08), Vector2(-0.06, 0.06), Vector2(0.00, 0.16)],
		[Vector2(0.13, 0.08), Vector2(0.20, -0.06)]]
	var side_width := 0.030 * sqrt(float(band) / 8.0)
	for branch in range(side_paths.size()):
		var path: Array = side_paths[branch]
		for segment in range(path.size() - 1):
			var start: Vector2 = path[segment]
			var finish: Vector2 = path[segment + 1]
			var along := (finish - start).normalized()
			var across := Vector2(-along.y, along.x)
			for step in range(6):
				var edges: Array[Vector3] = []
				var crests: Array[Vector3] = []
				for index in [step, step + 1]:
					var t := float(index) / 6.0
					var local := start.lerp(finish, t)
					var at := Vector2(spec.center.z + local.x * spec.size.z,
						spec.center.y + local.y * spec.size.y)
					var radius := side_width * (0.84 + 0.16 * sin(float(branch * 5 + segment * 2) + t * PI))
					edges.append(_side_seam_point(at - across * radius))
					edges.append(_side_seam_point(at + across * radius))
					crests.append(_side_seam_point(at, 0.008))
				_side_seam_triangle(surface, edges[0], crests[0], crests[1])
				_side_seam_triangle(surface, edges[0], crests[1], edges[2])
				_side_seam_triangle(surface, crests[0], edges[1], edges[3])
				_side_seam_triangle(surface, crests[0], edges[3], crests[1])
	surface.generate_tangents()
	var mesh := surface.commit()
	source_meshes[band] = mesh
	return mesh


static func _ore_ground_mesh(band: int, cells: Array) -> ArrayMesh:
	var key := "%d:%s" % [band, str(cells)]
	if ground_meshes.has(key):
		return ground_meshes[key]
	var first_z := int(cells[0][1])
	var last_z := first_z
	for cell: Array in cells:
		first_z = mini(first_z, int(cell[1]))
		last_z = maxi(last_z, int(cell[1]))
	var middle_z := float(first_z + last_z) * Geometry.PITCH * 0.5
	var radius_z := float(last_z - first_z + 1) * Geometry.PITCH * 0.5
	var source := SurfaceTool.new()
	source.begin(Mesh.PRIMITIVE_TRIANGLES)
	var opacity := sqrt(float(band) / 8.0)
	var radii := [0.0, 0.38, 0.70, 0.90, 1.0]
	var strengths := [0.88, 0.96, 0.74, 0.28, 0.0]
	for sector in range(32):
		var angles := [float(sector) * TAU / 32.0, float(sector + 1) * TAU / 32.0]
		# Extend the disturbed soil under the real rock toe while retaining the
		# collector-cell cue on its east side. This is passive terrain color only.
		var center := Vector2(-0.58, middle_z)
		for ring in range(4):
			var points: Array[Vector2] = []
			var opacities: Array[float] = []
			for radius_index in [ring, ring + 1]:
				for angle in angles:
					var irregular := 0.91 + 0.055 * sin(angle * 5.0 + 0.8) + 0.035 * cos(angle * 9.0)
					points.append(center + Vector2(cos(angle) * 0.95, sin(angle) * radius_z)
						* irregular * float(radii[radius_index]))
					opacities.append(opacity * float(strengths[radius_index]))
			var corners := [0, 3, 2] if ring == 0 else [0, 3, 2, 0, 1, 3]
			for corner in corners:
				var vertex: Vector2 = points[corner]
				source.set_normal(Vector3.UP)
				source.set_uv(vertex * 0.55)
				source.set_color(Color(1.0, 1.0, 1.0, opacities[corner]))
				source.add_vertex(Vector3(vertex.x, Scenery.Surface.height_at(vertex.x, vertex.y) + 0.014, vertex.y))
	var mesh := source.commit()
	ground_meshes[key] = mesh
	return mesh


static func _outcrop_material() -> StandardMaterial3D:
	if source_rock != null:
		return source_rock
	var textures := {}
	for role: String in ["albedo", "normal", "arm"]:
		var path := "res://opening/assets/mineral-outcrop/" + role + ".webp"
		var image := Visuals.read_image(path)
		var extent := 512 if role == "albedo" else 256
		if image == null or image.get_size() != Vector2i(extent, extent) \
			or image.generate_mipmaps(role == "normal") != OK:
			push_error("The mineable outcrop requires its complete qualified material: " + role)
			return null
		textures[role] = ImageTexture.create_from_image(image)
	source_rock = StandardMaterial3D.new()
	source_rock.cull_mode = BaseMaterial3D.CULL_DISABLED
	source_rock.albedo_texture = textures.albedo
	source_rock.albedo_color = Color("c78a54")
	source_rock.metallic = 0.0
	source_rock.roughness = 1.0
	source_rock.roughness_texture = textures.arm
	source_rock.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	source_rock.ao_enabled = true
	source_rock.ao_texture = textures.arm
	source_rock.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	source_rock.normal_enabled = true
	source_rock.normal_texture = textures.normal
	source_rock.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return source_rock


static func mineral_deposit(parent: Node3D, state: Dictionary) -> void:
	var cells: Array = state.get("source_deposit", {}).get("cells", [])
	if cells.is_empty():
		return
	var initial := maxi(1, int(state.initial_feed))
	var fraction := clampf(float(state.stock.source) / float(initial), 0.0, 1.0)
	var band := ceili(fraction * 8.0)
	var finish := _outcrop_material()
	if finish == null:
		return
	if source_mineral == null:
		source_mineral = StandardMaterial3D.new()
		source_mineral.albedo_color = Color("f2ae56")
		source_mineral.metallic = 0.38
		source_mineral.roughness = 0.56
	var exposure := Node3D.new()
	exposure.name = "MineralDeposit"
	exposure.set_meta("item_kind", "mineral_deposit")
	exposure.set_meta("remaining", state.stock.source)
	exposure.set_meta("depletion_band", band)
	parent.add_child(exposure)
	var spec: Dictionary = Scenery.Surface.source_outcrop()
	var host := _part(exposure, "ExposedRock", Scenery.Surface.SOURCE_OUTCROP_MESH, spec.center, Color.WHITE)
	host.basis = spec.basis
	host.material_override = finish
	if band > 0:
		if source_ground == null:
			var soil := Visuals.read_image("res://opening/assets/mineral-outcrop/ore-soil.webp")
			if soil == null or soil.generate_mipmaps() != OK:
				push_error("The mineable ground requires its prepared mineral-soil map.")
				return
			source_ground = StandardMaterial3D.new()
			source_ground.albedo_texture = ImageTexture.create_from_image(soil)
			source_ground.albedo_color = Color.WHITE
			source_ground.cull_mode = BaseMaterial3D.CULL_DISABLED
			source_ground.vertex_color_use_as_albedo = true
			source_ground.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			source_ground.roughness = 1.0
		var ground := _part(exposure, "OreSurface", _ore_ground_mesh(band, cells), Vector3.ZERO, Color.WHITE)
		ground.material_override = source_ground
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mineral := _part(exposure, "MineralVeins", _seam_mesh(band), Vector3.ZERO, Color.WHITE)
		mineral.material_override = source_mineral
		mineral.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
		Vector3(0.0, 0.002, 0.0), Color("bca17c"), 0.78, 0.44)
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
		Vector3(0.0, -0.014, 0.0), Color("ad633c"), 0.58, 0.48)
	for side in [-1.0, 1.0]:
		var x_off: float = float(side) * 0.155
		var z_off: float = float(side) * 0.195
		_part(assembly, "StampedRim", Visuals.box_mesh(Vector3(0.044, 0.022, 0.44)),
			Vector3(x_off, 0.011, 0.0), Color("ca8356"), 0.62, 0.42)
		_part(assembly, "StampedRim", Visuals.box_mesh(Vector3(0.26, 0.022, 0.044)),
			Vector3(0.0, 0.011, z_off), Color("ca8356"), 0.62, 0.42)
	_part(assembly, "PlateBushing", Visuals.turned_mesh(bushing_profile(), 48),
		Vector3(0.0, 0.012, 0.0), Color("8d4e2f"), 0.65, 0.38)
	var rivet_mesh: ArrayMesh = Visuals.turned_mesh(rivet_profile(), 6)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var rx: float = float(sx) * 0.155
			var rz: float = float(sz) * 0.195
			_part(assembly, "PlateFastener", rivet_mesh,
				Vector3(rx, 0.022, rz), Color("925033"), 0.62, 0.44)
	return assembly


static func copper_offcuts(parent: Node3D, at: Vector3 = Vector3.ZERO) -> Node3D:
	var assembly := Node3D.new()
	assembly.name = "CopperOffcuts"
	assembly.position = at
	assembly.set_meta("item_kind", "copper_offcuts")
	parent.add_child(assembly)
	# Narrow L-shaped trimmings read as press waste rather than another plate.
	# The three pieces sit slightly apart so the exposed cut edges catch light.
	for index in 3:
		var piece := Node3D.new()
		piece.name = "Trimming%d" % index
		piece.position = Vector3(-0.09 + float(index) * 0.085, 0.003 + float(index) * 0.007,
			-0.045 + float(index % 2) * 0.08)
		piece.rotation.y = float(index - 1) * 0.32
		assembly.add_child(piece)
		_part(piece, "CopperStrip", Visuals.box_mesh(Vector3(0.12, 0.014, 0.026)),
			Vector3(0.035, 0.0, 0.0), Color("bc7650"), 0.87, 0.32)
		_part(piece, "CutTab", Visuals.box_mesh(Vector3(0.028, 0.014, 0.075)),
			Vector3(-0.01, 0.0, 0.025), Color("d49168"), 0.85, 0.36)
	return assembly


static func _material_rotated(state: Dictionary, entity_id: Variant, entity: Dictionary) -> bool:
	if not state.get("options", {}).get("native", false):
		return false
	if entity.get("kind") == "belt":
		return int(entity.get("axis", 2)) == 0
	for pair in state.get("links", []):
		if pair.size() != 2 or entity_id not in pair:
			continue
		var other: Dictionary = state.get("entities", {}).get(pair[1] if pair[0] == entity_id else pair[0], {})
		if other.get("kind") == "belt":
			return int(other.get("axis", 2)) == 0
	return false

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
		var turned := _material_rotated(state, entity_id, entity)
		var orientation := Basis(Vector3.UP, -PI / 2.0) if turned else Basis.IDENTITY
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
			var billet := workpiece_billet(item_root, pos + orientation * offset)
			if turned:
				billet.rotation.y = -PI / 2.0
		if kind == "processor" and int(stock.get("output", 0)) > 0:
			var plate := stamped_plate(item_root, pos + orientation * Vector3(0.46, 0.39, 0.15))
			if turned:
				plate.rotation.y = -PI / 2.0
	mineral_deposit(item_root, state)
