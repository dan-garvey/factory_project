extends RefCounted
## Render resources only; no scene controller or simulation authority.
const Geometry = preload("res://opening/site_geometry.gd")
const ProductionSteelFloor = preload("res://opening/production_surfaces.gd").ProductionSteelFloor
const ProductionVisuals = preload("res://opening/production_surfaces.gd").ProductionVisuals

class ProductionSkidArt:
	extends RefCounted
	## One original shared base resource. Empty channels are visual only.
	static var shared_mesh: ArrayMesh

	static func skid_mesh() -> ArrayMesh:
		if shared_mesh != null:
			return shared_mesh
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		# The mounting deck retains the exact old top and outer footprint.
		surface.append_from(ProductionVisuals.box_mesh(Vector3(1.35, 0.04, 1.35)), 0,
			Transform3D(Basis.IDENTITY, Vector3(0, 0.10, 0)))
		var channel := PackedVector2Array([Vector2(-0.105, -0.12), Vector2(0.105, -0.12),
			Vector2(0.105, -0.08), Vector2(-0.045, -0.08), Vector2(-0.045, 0.055),
			Vector2(0.105, 0.055), Vector2(0.105, 0.095), Vector2(-0.105, 0.095)])
		for side in [-1.0, 1.0]:
			var profile := channel.duplicate()
			for n in range(profile.size()):
				profile[n].x *= -side
			surface.append_from(ProductionVisuals.prism_mesh(profile, 1.35, 0.004), 0,
				Transform3D(Basis.IDENTITY, Vector3(side * 0.53, 0, 0)))
		for z in [-0.38, 0.38]:
			surface.append_from(ProductionVisuals.box_mesh(Vector3(1.08, 0.045, 0.06)), 0,
				Transform3D(Basis.IDENTITY, Vector3(0, 0.045, z)))
		shared_mesh = surface.commit()
		return shared_mesh

class ProductionFoundationArt:
	extends RefCounted
	## Passive kit below a confirmed tile's top-plane origin. No grid or state.
	const ROOT := "res://opening/assets/foundation-concrete"
	const FILES := {"albedo": "concrete_albedo.jpg", "normal": "concrete_normal_gl.webp", "arm": "concrete_arm.webp"}
	const DECK_THICKNESS := 0.024
	const WEST := 1
	const EAST := 2
	const NORTH := 4
	const SOUTH := 8
	const FOOTING_BEVEL := 0.014
	const JOIN_CORNER := 0.0002
	const COURSE_RECESS := 0.006
	const BAY_MARGIN := 0.19
	const BAY_SHOULDER := 0.018
	const BAY_RECESS := 0.018
	static var finish: StandardMaterial3D
	static var textures: Dictionary = {}
	static var source_status := "uninitialized"
	static var deck_meshes: Dictionary = {}
	static var footing_meshes: Dictionary = {}

	static func read_images(directory: String = ROOT) -> Dictionary:
		return ProductionSteelFloor.read_images(directory, FILES, Vector2i(512, 512))

	static func material() -> StandardMaterial3D:
		if source_status != "uninitialized":
			return finish
		var loaded := read_images()
		source_status = loaded.status
		if source_status != "ready":
			push_error("The player-built foundation needs its complete qualified concrete surface set.")
			return null
		for role in loaded.images:
			var image: Image = loaded.images[role]
			if image.generate_mipmaps(role == "normal") != OK:
				source_status = "invalid"
				push_error("Cannot generate foundation concrete mipmaps.")
				return null
			textures[role] = ImageTexture.create_from_image(image)
		finish = StandardMaterial3D.new()
		finish.albedo_color = Color.WHITE
		finish.albedo_texture = textures.albedo
		finish.metallic = 0.0
		finish.roughness = 1.0
		finish.roughness_texture = textures.arm
		finish.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		finish.normal_enabled = true
		finish.normal_texture = textures.normal
		finish.normal_scale = 1.0
		finish.uv1_triplanar = true
		finish.uv1_world_triplanar = true
		finish.uv1_triplanar_sharpness = 8.0
		finish.uv1_scale = Vector3.ONE * 0.5
		finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return finish

	static func _footing_outline(mask: int, cap: bool = false, bay_recess: float = 0.0) -> Array[Vector2]:
		var half := Geometry.PITCH / 2.0 - (FOOTING_BEVEL if cap else 0.0)
		var corner := FOOTING_BEVEL / 2.0 if cap else FOOTING_BEVEL
		var nw := corner if cap or (mask & (NORTH | WEST)) == 0 else JOIN_CORNER
		var ne := corner if cap or (mask & (NORTH | EAST)) == 0 else JOIN_CORNER
		var se := corner if cap or (mask & (SOUTH | EAST)) == 0 else JOIN_CORNER
		var sw := corner if cap or (mask & (SOUTH | WEST)) == 0 else JOIN_CORNER
		# Each exposed wall has one broad inset casting bay. The shoulders and
		# outer corner piers keep their physical scale when tiles join; hidden
		# faces stay flat. Every height ring has the same vertex correspondence.
		var north_bay := bay_recess if mask & NORTH == 0 else 0.0
		var east_bay := bay_recess if mask & EAST == 0 else 0.0
		var south_bay := bay_recess if mask & SOUTH == 0 else 0.0
		var west_bay := bay_recess if mask & WEST == 0 else 0.0
		return [Vector2(-half, -half + nw), Vector2(-half + nw, -half),
			Vector2(-half + BAY_MARGIN, -half),
			Vector2(-half + BAY_MARGIN + BAY_SHOULDER, -half + north_bay),
			Vector2(half - BAY_MARGIN - BAY_SHOULDER, -half + north_bay),
			Vector2(half - BAY_MARGIN, -half),
			Vector2(half - ne, -half), Vector2(half, -half + ne),
			Vector2(half, -half + BAY_MARGIN),
			Vector2(half - east_bay, -half + BAY_MARGIN + BAY_SHOULDER),
			Vector2(half - east_bay, half - BAY_MARGIN - BAY_SHOULDER),
			Vector2(half, half - BAY_MARGIN),
			Vector2(half, half - se), Vector2(half - se, half),
			Vector2(half - BAY_MARGIN, half),
			Vector2(half - BAY_MARGIN - BAY_SHOULDER, half - south_bay),
			Vector2(-half + BAY_MARGIN + BAY_SHOULDER, half - south_bay),
			Vector2(-half + BAY_MARGIN, half),
			Vector2(-half + sw, half), Vector2(-half, half - sw),
			Vector2(-half, half - BAY_MARGIN),
			Vector2(-half + west_bay, half - BAY_MARGIN - BAY_SHOULDER),
			Vector2(-half + west_bay, -half + BAY_MARGIN + BAY_SHOULDER),
			Vector2(-half, -half + BAY_MARGIN)]

	static func _footing_ring(outline: Array[Vector2], height: float, recess: float, mask: int) -> Array[Vector3]:
		var ring: Array[Vector3] = []
		for point in outline:
			var x := point.x
			var z := point.y
			if x < 0 and mask & WEST == 0:
				x += recess
			elif x > 0 and mask & EAST == 0:
				x -= recess
			if z < 0 and mask & NORTH == 0:
				z += recess
			elif z > 0 and mask & SOUTH == 0:
				z -= recess
			ring.append(Vector3(x, height, z))
		return ring

	static func _footing_seam(surface: SurfaceTool, upper: Array[Vector3], lower: Array[Vector3]) -> void:
		for index in range(upper.size()):
			var next := (index + 1) % upper.size()
			var first: Array[Vector3] = [upper[index], upper[next], lower[next]]
			var second: Array[Vector3] = [upper[index], lower[next], lower[index]]
			ProductionVisuals._face(surface, first,
				(first[1] - first[0]).cross(first[2] - first[0]).normalized())
			ProductionVisuals._face(surface, second,
				(second[1] - second[0]).cross(second[2] - second[0]).normalized())

	static func footing_mesh(mask: int = 0) -> ArrayMesh:
		assert(mask >= 0 and mask < 16)
		if footing_meshes.has(mask):
			return footing_meshes[mask]
		var half_depth := (Geometry.FOUNDATION_DEPTH - DECK_THICKNESS) / 2.0
		var outline := _footing_outline(mask)
		var bay := _footing_outline(mask, false, BAY_RECESS)
		var cap := _footing_outline(mask, true)
		var upper := _footing_ring(cap, half_depth, 0.0, mask)
		var lower := _footing_ring(cap, -half_depth, 0.0, mask)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(cap.size()):
			var next := (index + 1) % cap.size()
			ProductionVisuals._face(surface, [Vector3(0, half_depth, 0), upper[index], upper[next]], Vector3.UP)
			ProductionVisuals._face(surface, [Vector3(0, -half_depth, 0), lower[next], lower[index]], Vector3.DOWN)
		var rings: Array = [upper,
			_footing_ring(outline, half_depth - FOOTING_BEVEL, 0.0, mask),
			_footing_ring(outline, half_depth - 0.13, 0.0, mask),
			_footing_ring(bay, half_depth - 0.15, 0.0, mask),
			_footing_ring(bay, half_depth - 0.20, 0.0, mask),
			_footing_ring(bay, half_depth - 0.212, COURSE_RECESS, mask),
			_footing_ring(bay, half_depth - 0.232, COURSE_RECESS, mask),
			_footing_ring(bay, half_depth - 0.244, 0.0, mask),
			_footing_ring(bay, -half_depth + 0.09, 0.0, mask),
			_footing_ring(outline, -half_depth + 0.07, 0.0, mask),
			_footing_ring(outline, -half_depth + FOOTING_BEVEL, 0.0, mask), lower]
		for index in range(rings.size() - 1):
			_footing_seam(surface, rings[index], rings[index + 1])
		surface.generate_tangents()
		var mesh := surface.commit()
		footing_meshes[mask] = mesh
		return mesh

	static func neighbor_masks(foundations: Dictionary) -> Dictionary:
		# The native projection owns placement and height. This only selects art
		# for edges shared by already confirmed tiles at exactly the same level.
		var occupied: Dictionary = {}
		for id in foundations:
			var tile: Dictionary = foundations[id]
			occupied[Vector3i(int(tile.cell[0]), int(tile.level), int(tile.cell[1]))] = true
		var masks: Dictionary = {}
		for id in foundations:
			var tile: Dictionary = foundations[id]
			var cell := Vector3i(int(tile.cell[0]), int(tile.level), int(tile.cell[1]))
			var mask := 0
			if occupied.has(cell + Vector3i(-1, 0, 0)):
				mask |= WEST
			if occupied.has(cell + Vector3i(1, 0, 0)):
				mask |= EAST
			if occupied.has(cell + Vector3i(0, 0, -1)):
				mask |= NORTH
			if occupied.has(cell + Vector3i(0, 0, 1)):
				mask |= SOUTH
			masks[id] = mask
		return masks

	static func _deck_top_point(x_index: int, z_index: int, mask: int) -> Vector3:
		var half := Geometry.PITCH / 2.0
		var bevel := minf(0.014, DECK_THICKNESS * 0.12)
		var positions := [-half, -half + bevel, half - bevel, half]
		var joined := (x_index == 0 and mask & WEST != 0) or (x_index == 3 and mask & EAST != 0) \
			or (z_index == 0 and mask & NORTH != 0) or (z_index == 3 and mask & SOUTH != 0)
		var edge := x_index == 0 or x_index == 3 or z_index == 0 or z_index == 3
		return Vector3(positions[x_index], DECK_THICKNESS / 2.0 - (bevel if edge and not joined else 0.0), positions[z_index])

	static func _deck_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
		ProductionVisuals._face(surface, [a, b, c], outward)

	static func _deck_bottom_point(x_index: int, z_index: int) -> Vector3:
		var half := Geometry.PITCH / 2.0
		var bevel := minf(0.014, DECK_THICKNESS * 0.12)
		var inset := half - bevel
		var positions := [-inset, -inset + bevel, inset - bevel, inset]
		return Vector3(positions[x_index], -DECK_THICKNESS / 2.0, positions[z_index])

	static func _deck_side(surface: SurfaceTool, top: Array[Vector3], bottom: Array[Vector3], outward: Vector3) -> void:
		for index in range(3):
			_deck_triangle(surface, top[index], top[index + 1], bottom[index + 1], outward)
			_deck_triangle(surface, top[index], bottom[index + 1], bottom[index], outward)

	static func deck_mesh(mask: int = 0) -> ArrayMesh:
		assert(mask >= 0 and mask < 16)
		if deck_meshes.has(mask):
			return deck_meshes[mask]
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for x in range(3):
			for z in range(3):
				var a := _deck_top_point(x, z, mask)
				var b := _deck_top_point(x + 1, z, mask)
				var c := _deck_top_point(x, z + 1, mask)
				var d := _deck_top_point(x + 1, z + 1, mask)
				_deck_triangle(surface, a, c, b, Vector3.UP)
				_deck_triangle(surface, b, c, d, Vector3.UP)
		for x in range(3):
			for z in range(3):
				var a := _deck_bottom_point(x, z)
				var b := _deck_bottom_point(x + 1, z)
				var c := _deck_bottom_point(x, z + 1)
				var d := _deck_bottom_point(x + 1, z + 1)
				_deck_triangle(surface, a, b, c, Vector3.DOWN)
				_deck_triangle(surface, b, d, c, Vector3.DOWN)
		var north: Array[Vector3] = []
		var south: Array[Vector3] = []
		var west: Array[Vector3] = []
		var east: Array[Vector3] = []
		var north_bottom: Array[Vector3] = []
		var south_bottom: Array[Vector3] = []
		var west_bottom: Array[Vector3] = []
		var east_bottom: Array[Vector3] = []
		for index in range(4):
			north.append(_deck_top_point(index, 0, mask))
			south.append(_deck_top_point(index, 3, mask))
			west.append(_deck_top_point(0, index, mask))
			east.append(_deck_top_point(3, index, mask))
			north_bottom.append(_deck_bottom_point(index, 0))
			south_bottom.append(_deck_bottom_point(index, 3))
			west_bottom.append(_deck_bottom_point(0, index))
			east_bottom.append(_deck_bottom_point(3, index))
		_deck_side(surface, north, north_bottom, Vector3.FORWARD)
		_deck_side(surface, east, east_bottom, Vector3.RIGHT)
		_deck_side(surface, south, south_bottom, Vector3.BACK)
		_deck_side(surface, west, west_bottom, Vector3.LEFT)
		surface.generate_tangents()
		var mesh := surface.commit()
		deck_meshes[mask] = mesh
		return mesh

	static func mount(parent: Node3D, neighbor_mask: int = 0) -> bool:
		var concrete := material()
		var steel := ProductionSteelFloor.material()
		if concrete == null or steel == null:
			return false
		var footing := MeshInstance3D.new()
		footing.name = "FoundationBlock"
		footing.mesh = footing_mesh(neighbor_mask)
		footing.position.y = -(Geometry.FOUNDATION_DEPTH + DECK_THICKNESS) / 2.0
		footing.material_override = concrete
		parent.add_child(footing)
		var deck := MeshInstance3D.new()
		deck.name = "FoundationTop"
		deck.mesh = deck_mesh(neighbor_mask)
		deck.position.y = -DECK_THICKNESS / 2.0
		deck.material_override = steel
		parent.add_child(deck)
		return true
