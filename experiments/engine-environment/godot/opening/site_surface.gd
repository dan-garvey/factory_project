extends RefCounted
## Immutable fixture geometry shared by terrain rendering and native collision.
## These dimensions and heights are adapter data, not a selected world-size rule.
const Geometry = preload("res://opening/site_geometry.gd")
const SUBDIVISIONS := 72
const SIZE := Geometry.DISPLAY_TERRAIN_SIZE
const HALF := SIZE * 0.5
static var _vertices := PackedVector3Array()
static var _faces := PackedVector3Array()

static func river_center_x(z: float) -> float:
	var reach := maxf(0.0, absf(z - 1.65) - 14.5)
	var bend := smoothstep(0.0, 26.0, reach)
	return -2.7 + bend * (sin(z * 0.042) * 8.0 + cos(z * 0.019) * 3.8)

static func channel_half_width(z: float) -> float:
	var flare := smoothstep(5.5, 22.0, absf(z - 1.65))
	return lerpf(0.62, 1.85, flare)

static func raw_height(x: float, z: float) -> float:
	# Preserve the original environment's samples. Physics and rendering use
	# the same emitted triangles, rather than treating this smooth function
	# as the height of a coarsely tessellated surface between its vertices.
	var rc := river_center_x(z)
	var half_w := channel_half_width(z)
	var dx_river := absf(x - rc)
	var downstream_drop := 0.48 * smoothstep(8.2, 10.6, z)
	var bed_y := -1.18 - downstream_drop + 0.035 * sin(z * 0.35 + x * 1.4)
	var pad_dx := maxf(0.0, absf(x - 1.65) - 6.85)
	var pad_dz := maxf(0.0, absf(z - 1.65) - 6.85)
	var pad_dist := sqrt(pad_dx * pad_dx + pad_dz * pad_dz)
	var base_y := Geometry.GROUND_HEIGHT
	if pad_dist <= 0.0:
		var edge := maxf(absf(x - 1.65), absf(z - 1.65))
		base_y = lerpf(-0.62, Geometry.GROUND_HEIGHT, smoothstep(6.2, 6.85, edge))
	else:
		var valley := smoothstep(2.2, 44.0, pad_dist)
		var far_rise := pow(smoothstep(7.5, 76.0, pad_dist), 1.15)
		var wave := (sin(x * 0.055 + z * 0.038) * 1.85
			+ cos(x * 0.092 - z * 0.071) * 1.15
			+ sin(x * 0.18 + z * 0.21) * 0.42) * smoothstep(1.8, 16.0, pad_dist)
		var north_gorge := 4.6 * smoothstep(-8.0, -54.0, z) * smoothstep(2.2, 13.0, dx_river)
		var west_bluff := 3.6 * smoothstep(-6.0, -42.0, x) * smoothstep(2.0, 12.0, pad_dist)
		var east_quarry := 2.8 * smoothstep(9.0, 46.0, x) * smoothstep(2.0, 12.0, pad_dist)
		var raw_hill := maxf(0.0, 7.8 * valley + 5.2 * far_rise + wave + north_gorge + west_bluff + east_quarry)
		var terraced := raw_hill - 0.22 * sin(raw_hill * 2.4)
		base_y = Geometry.GROUND_HEIGHT + maxf(0.0, terraced)
	if dx_river <= half_w:
		return bed_y
	var bank_span := 1.35 + 3.85 * smoothstep(5.5, 24.0, absf(z - 1.65))
	var bank_t := smoothstep(half_w, half_w + bank_span, dx_river)
	return lerpf(bed_y, base_y, bank_t)

static func normal(x: float, z: float) -> Vector3:
	var step := 0.45
	var hx := raw_height(x + step, z) - raw_height(x - step, z)
	var hz := raw_height(x, z + step) - raw_height(x, z - step)
	return Vector3(-hx, 2.0 * step, -hz).normalized()

static func _prepare() -> void:
	if not _vertices.is_empty():
		return
	for gz in range(SUBDIVISIONS + 1):
		var z := -HALF + float(gz) / SUBDIVISIONS * SIZE
		for gx in range(SUBDIVISIONS + 1):
			var x := -HALF + float(gx) / SUBDIVISIONS * SIZE
			_vertices.append(Vector3(x, raw_height(x, z), z))
	var stride := SUBDIVISIONS + 1
	for gz in range(SUBDIVISIONS):
		for gx in range(SUBDIVISIONS):
			var i00 := gz * stride + gx
			var i10 := i00 + 1
			var i01 := i00 + stride
			var i11 := i01 + 1
			for index in [i00, i10, i11, i00, i11, i01]:
				_faces.append(_vertices[index])

static func vertices() -> PackedVector3Array:
	_prepare()
	return _vertices.duplicate()

static func faces() -> PackedVector3Array:
	_prepare()
	return _faces.duplicate()

static func vertex(gx: int, gz: int) -> Vector3:
	_prepare()
	return _vertices[gz * (SUBDIVISIONS + 1) + gx]

static func cell(x: float, z: float) -> Vector2i:
	# Bounds and interpolation use the emitted float32 coordinates, not an
	# unrounded analytical grid or an added gameplay/reach epsilon.
	var gx := clampi(floori((x + HALF) / SIZE * SUBDIVISIONS), 0, SUBDIVISIONS - 1)
	var gz := clampi(floori((z + HALF) / SIZE * SUBDIVISIONS), 0, SUBDIVISIONS - 1)
	while gx > 0 and x < vertex(gx, 0).x:
		gx -= 1
	while gx < SUBDIVISIONS - 1 and x > vertex(gx + 1, 0).x:
		gx += 1
	while gz > 0 and z < vertex(0, gz).z:
		gz -= 1
	while gz < SUBDIVISIONS - 1 and z > vertex(0, gz + 1).z:
		gz += 1
	return Vector2i(gx, gz)

static func contains(x: float, z: float) -> bool:
	return is_finite(x) and is_finite(z) and x >= -HALF and x <= HALF and z >= -HALF and z <= HALF

static func height_at(x: float, z: float) -> float:
	if not contains(x, z):
		return NAN
	var at := cell(x, z)
	var p00 := vertex(at.x, at.y)
	var p10 := vertex(at.x + 1, at.y)
	var p01 := vertex(at.x, at.y + 1)
	var p11 := vertex(at.x + 1, at.y + 1)
	var u := (x - p00.x) / (p10.x - p00.x)
	var v := (z - p00.z) / (p01.z - p00.z)
	if u >= v:
		return p00.y * (1.0 - u) + p10.y * (u - v) + p11.y * v
	return p00.y * (1.0 - v) + p11.y * u + p01.y * (v - u)

static func _closest_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Voronoi-region closest point. Every terrain cell has nondegenerate X/Z
	# area; this also handles a capsule beside a face rather than above it.
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var inverse := 1.0 / (va + vb + vc)
	return a + ab * (vb * inverse) + ac * (vc * inverse)

static func _segment_triangle_distance(p: Vector3, q: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	if Geometry3D.segment_intersects_triangle(p, q, a, b, c) != null:
		return 0.0
	var distance := minf(p.distance_squared_to(_closest_triangle(p, a, b, c)),
		q.distance_squared_to(_closest_triangle(q, a, b, c)))
	for edge in [[a, b], [b, c], [c, a]]:
		var pair := Geometry3D.get_closest_points_between_segments(p, q, edge[0], edge[1])
		distance = minf(distance, pair[0].distance_squared_to(pair[1]))
	return sqrt(maxf(distance, 0.0))

static func capsule_overlap(at: Vector3, radius: float, height: float) -> Dictionary:
	# A trimesh is hollow in Godot. In addition to measuring real nearby
	# triangle contacts, explicitly reject a saved capsule buried below the
	# represented ground even when a native surface query reports no hit.
	if not at.is_finite() or not is_finite(radius) or not is_finite(height) or radius <= 0.0 or height < radius * 2.0:
		return {"analytical_overlap_measure": INF, "geometric_overlap": true, "valid": false}
	_prepare()
	var half_segment := height / 2.0 - radius
	var p := at - Vector3.UP * half_segment
	var q := at + Vector3.UP * half_segment
	var distance := INF
	var count := 0
	if at.x + radius >= -HALF and at.x - radius <= HALF and at.z + radius >= -HALF and at.z - radius <= HALF:
		var low := cell(at.x - radius, at.z - radius)
		var high := cell(at.x + radius, at.z + radius)
		for gz in range(low.y, high.y + 1):
			for gx in range(low.x, high.x + 1):
				var first := (gz * SUBDIVISIONS + gx) * 6
				for offset in [0, 3]:
					distance = minf(distance, _segment_triangle_distance(p, q,
						_faces[first + offset], _faces[first + offset + 1], _faces[first + offset + 2]))
					count += 1
	var surface := height_at(at.x, at.z)
	var buried := maxf(surface - (at.y - height / 2.0), 0.0) if is_finite(surface) else 0.0
	var measure := maxf(maxf(radius - distance, 0.0), buried)
	return {"analytical_overlap_measure": measure, "geometric_overlap": measure > 0.0,
		"minimum_triangle_distance": distance, "center_surface_height": surface,
		"subsurface_depth": buried, "triangles_measured": count, "valid": true}

static func pad_panels() -> Array[Dictionary]:
	# The renderer and physical producer share these exact flat deck rectangles.
	# Open spans over the millrace must not become an invisible solid plane.
	var result: Array[Dictionary] = []
	for x in range(-2, 5):
		for z in range(-2, 5):
			var center := Vector3(x * Geometry.PITCH, -0.08, z * Geometry.PITCH)
			var size := Vector3(Geometry.PITCH - 0.035, 0.12, Geometry.PITCH - 0.035)
			if x == -1:
				center.x = -1.41
				size.x = 1.13
			elif x == -2:
				center.x = -3.76
				size.x = 0.69
			result.append({"id": "pad_%d_%d" % [x, z], "cell": Vector2i(x, z),
				"center": center, "size": size})
	return result

static func group_origin(group: String) -> Vector3:
	match group:
		"HeadraceSluice": return Vector3(-2.7, 0.0, -5.65)
		"TailraceWeir": return Vector3(-2.7, 0.0, 8.65)
		"NorthSeamOutcrop": return Vector3(0.0, 0.0, -5.48)
	return Vector3.ZERO

static func _structure(result: Array[Dictionary], group: String, label: String,
		local: Vector3, dimensions: Vector3, finish: String, rotation: Vector3 = Vector3.ZERO) -> void:
	result.append({"id": "architecture_%d" % result.size(), "group": group, "label": label,
		"center": group_origin(group) + local, "size": dimensions,
		"basis": Basis.from_euler(rotation), "finish": finish, "solid": finish != "foam"})

static func architecture_boxes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Recessed stone-lined millrace channel bed and walls below Geometry.GROUND_HEIGHT.
	_structure(result, "MillraceArchitecture", "ChannelBed", Vector3(-2.7, -1.08, 1.4), Vector3(1.58, 0.16, 29.6), "dark_stone")
	for side in [-1.0, 1.0]:
		var wall_name := "WestChannelWall" if side < 0.0 else "EastChannelWall"
		var coping_name := "WestChannelCoping" if side < 0.0 else "EastChannelCoping"
		_structure(result, "MillraceArchitecture", wall_name, Vector3(-2.7 + side * 0.71, -0.32, 1.4),
			Vector3(0.22, 0.56, 28.4), "stone")
		_structure(result, "MillraceArchitecture", coping_name, Vector3(-2.7 + side * 0.69, -0.065, 1.65),
			Vector3(0.26, 0.08, 13.6), "dark_stone")
	for n in range(10):
		var sill_z := -4.6 + float(n) * 1.42
		_structure(result, "MillraceArchitecture", "ChannelTimberSill", Vector3(-2.7, -0.52, sill_z),
			Vector3(1.22, 0.09, 0.16), "timber")
	# Upstream headrace sluice gate and timber flume bents (north of the buildable pad).
	for side in [-1.0, 1.0]:
		var pier_tag := "West" if side < 0.0 else "East"
		_structure(result, "HeadraceSluice", pier_tag + "SluicePier", Vector3(side * 0.78, 0.52, 0.0),
			Vector3(0.46, 1.72, 0.76), "stone")
		_structure(result, "HeadraceSluice", pier_tag + "SluiceCap", Vector3(side * 0.78, 1.42, 0.0),
			Vector3(0.54, 0.12, 0.84), "dark_stone")
		_structure(result, "HeadraceSluice", pier_tag + "GuideChannel", Vector3(side * 0.55, 0.58, 0.0),
			Vector3(0.08, 1.48, 0.16), "iron")
	_structure(result, "HeadraceSluice", "SluiceHeadbeam", Vector3(0.0, 1.56, 0.0), Vector3(2.12, 0.18, 0.42), "iron")
	_structure(result, "HeadraceSluice", "SluiceApronSill", Vector3(0.0, -0.22, 0.12), Vector3(1.36, 0.24, 0.58), "dark_stone")
	_structure(result, "HeadraceSluice", "SluiceGateLeaf", Vector3(0.0, 0.46, 0.0), Vector3(1.16, 0.88, 0.09), "timber")
	for rib_y in [0.16, 0.46, 0.76]:
		_structure(result, "HeadraceSluice", "GateLeafStrap", Vector3(0.0, rib_y, 0.055), Vector3(1.18, 0.06, 0.035), "iron")
	for rack in range(-2, 3):
		_structure(result, "HeadraceSluice", "TrashRackBar", Vector3(float(rack) * 0.22, 0.22, -0.32),
			Vector3(0.035, 0.84, 0.035), "iron", Vector3(0.18, 0.0, 0.0))
	_structure(result, "HeadraceSluice", "SluiceDischargeFoam", Vector3(0.0, -0.05, 0.46), Vector3(1.12, 0.06, 0.42), "foam")
	for bent in range(4):
		var bz := -1.85 - float(bent) * 2.1
		for side in [-1.0, 1.0]:
			_structure(result, "HeadraceSluice", "FlumePost", Vector3(side * 0.78, 0.18, bz), Vector3(0.18, 1.08, 0.18), "timber")
		_structure(result, "HeadraceSluice", "FlumeCapBeam", Vector3(0.0, 0.74, bz), Vector3(1.84, 0.14, 0.18), "timber")
	# Downstream stepped spillway weir and tailrace plunge basin (south of the buildable pad).
	_structure(result, "TailraceWeir", "UpperWeirCrest", Vector3(0.0, -0.34, 0.0), Vector3(1.38, 0.38, 0.56), "stone")
	_structure(result, "TailraceWeir", "LowerWeirCrest", Vector3(0.0, -0.56, 0.68), Vector3(1.54, 0.42, 0.68), "dark_stone")
	_structure(result, "TailraceWeir", "UpperWeirFoam", Vector3(0.0, -0.14, 0.24), Vector3(1.18, 0.08, 0.32), "foam")
	_structure(result, "TailraceWeir", "LowerWeirFoam", Vector3(0.0, -0.36, 0.96), Vector3(1.32, 0.09, 0.44), "foam")
	_structure(result, "TailraceWeir", "PlungePoolFoam", Vector3(0.0, -0.58, 1.56), Vector3(1.48, 0.07, 0.58), "foam")
	for side in [-1.0, 1.0]:
		var wing_tag := "West" if side < 0.0 else "East"
		_structure(result, "TailraceWeir", wing_tag + "WeirWingwall", Vector3(side * 0.84, -0.14, 0.55),
			Vector3(0.38, 0.76, 2.2), "stone")
		_structure(result, "TailraceWeir", wing_tag + "TailraceTimberCrib", Vector3(side * 0.92, -0.38, 2.25),
			Vector3(0.28, 0.68, 1.45), "timber")
	return result

static func _foundation(result: Array[Dictionary], group: String, label: String,
		local: Vector3, dimensions: Vector3, tint: Color, metallic: float, roughness: float) -> void:
	result.append({"id": "foundation_%d" % result.size(), "group": group, "label": label,
		"center": group_origin(group) + local, "size": dimensions, "basis": Basis.IDENTITY,
		"tint": tint, "metallic": metallic, "roughness": roughness})

static func foundation_boxes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Split the foundation substructure around the recessed x=-2.7 millrace
	# channel so the 3D river gorge and masonry walls remain open underneath.
	_foundation(result, "", "EastFoundrySubstructure", Vector3(3.21, -0.55, 1.65),
		Vector3(10.28, 0.8, 13.4), Color("394641"), 0.06, 0.9)
	_foundation(result, "", "WestWharfSubstructure", Vector3(-4.25, -0.55, 1.65),
		Vector3(1.60, 0.8, 13.4), Color("394641"), 0.06, 0.9)
	_foundation(result, "", "FoundryCurbEast", Vector3(8.38, -0.11, 1.65),
		Vector3(0.18, 0.18, 13.56), Color("3b4b50"), 0.75, 0.44)
	_foundation(result, "", "FoundryCurbWest", Vector3(-5.08, -0.11, 1.65),
		Vector3(0.18, 0.18, 13.56), Color("3b4b50"), 0.75, 0.44)
	for z_idx in range(-2, 5):
		var z_pos := float(z_idx) * Geometry.PITCH
		_foundation(result, "", "EastRetainingButtress", Vector3(8.48, -0.52, z_pos),
			Vector3(0.32, 0.86, 0.36), Color("515954"), 0.08, 0.88)
		_foundation(result, "", "WestRetainingButtress", Vector3(-5.18, -0.52, z_pos),
			Vector3(0.32, 0.86, 0.36), Color("515954"), 0.08, 0.88)
		_foundation(result, "", "FoundryCrossGirder", Vector3(3.25, -0.155, z_pos - Geometry.PITCH * 0.5),
			Vector3(10.1, 0.05, 0.09), Color("2f3e43"), 0.78, 0.45)
	# Recessed 3D ore seam trench along x=0 with steel curb rails, fractured
	# slate vein bed, faceted brass-ore crystal outcrops, and a north rock headwall.
	_foundation(result, "", "SeamVeinBed", Vector3(0.0, -0.012, 1.65),
		Vector3(0.26, 0.03, 13.4), Color("2d3536"), 0.12, 0.88)
	for side in [-1.0, 1.0]:
		_foundation(result, "", "SeamCurbRail", Vector3(side * 0.155, 0.004, 1.65),
			Vector3(0.045, 0.036, 13.4), Color("46585d"), 0.78, 0.42)
	for n in range(14):
		var oz := -3.35 + float(n) * 0.78
		var ox := (-0.045 if n % 2 == 0 else 0.045)
		_foundation(result, "", "SeamOreOutcrop", Vector3(ox, 0.018, oz),
			Vector3(0.11, 0.048, 0.28), Color("b89752"), 0.68, 0.36)
	_foundation(result, "NorthSeamOutcrop", "SeamRockMass", Vector3(0.0, 0.46, -0.24),
		Vector3(1.52, 1.32, 0.74), Color("4b524e"), 0.06, 0.9)
	_foundation(result, "NorthSeamOutcrop", "SeamRockShoulderWest", Vector3(-0.78, 0.28, -0.18),
		Vector3(0.68, 0.92, 0.58), Color("585f59"), 0.05, 0.9)
	_foundation(result, "NorthSeamOutcrop", "SeamRockShoulderEast", Vector3(0.78, 0.32, -0.18),
		Vector3(0.68, 0.98, 0.58), Color("585f59"), 0.05, 0.9)
	for side in [-1.0, 1.0]:
		_foundation(result, "NorthSeamOutcrop", "MinePortalPost", Vector3(side * 0.46, 0.48, 0.14),
			Vector3(0.14, 1.04, 0.14), Color("6e5339"), 0.04, 0.84)
	_foundation(result, "NorthSeamOutcrop", "MinePortalCap", Vector3(0.0, 1.04, 0.14),
		Vector3(1.18, 0.14, 0.18), Color("6e5339"), 0.04, 0.84)
	for v_idx in range(3):
		_foundation(result, "NorthSeamOutcrop", "ExposedOreVein",
			Vector3(-0.18 + float(v_idx) * 0.18, 0.24 + float(v_idx) * 0.24, 0.12),
			Vector3(0.22, 0.18, 0.14), Color("c7a35a"), 0.74, 0.34)
	for idx in range(3):
		var crib_z := -1.8 + float(idx) * 0.4
		_foundation(result, "", "WestBankSurveyMarker", Vector3(-3.75, 0.03, crib_z),
			Vector3(0.16, 0.09, 0.24), Color("be9957"), 0.62, 0.42)
	for row in range(-2, 5):
		for offset in [-0.52, 0.0, 0.52]:
			for side in [0, 1]:
				_foundation(result, "", "MillraceWharfBeam",
					Vector3(-2.22 if side == 0 else -2.95, -0.06, row * Geometry.PITCH + offset),
					Vector3(0.50 if side == 0 else 0.94, 0.08, 0.22), Color("6e5339"), 0.04, 0.84)
	return result

static func rock_boxes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for n in range(64):
		var angle := float(n) * 2.399963 + 0.45
		var distance := 10.6 + float(posmod(n * 19, 41)) * 0.68
		var px := 1.65 + cos(angle) * distance
		var pz := 1.65 + sin(angle) * distance
		if absf(px - river_center_x(pz)) < channel_half_width(pz) + 0.85:
			px += 1.95 if px >= river_center_x(pz) else -1.95
		var scale := Vector3(0.75 + float(posmod(n * 5, 11)) * 0.12,
			0.65 + float(posmod(n * 11, 9)) * 0.14, 0.75 + float(posmod(n * 17, 13)) * 0.11)
		var rotation := Basis.from_euler(Vector3(sin(float(n) * 1.7) * 0.14, angle, cos(float(n) * 2.3) * 0.14))
		result.append({"id": "rock_%d" % n, "center": Vector3(px, height_at(px, pz), pz),
			"basis": rotation, "size": Vector3(1.35, 0.88, 1.12) * scale, "scale": scale,
			"color": Color("59605a").lerp(Color("7d7a6e"), float(n % 4) / 3.0)})
	return result

static func support_boxes() -> Array[Dictionary]:
	var result := pad_panels()
	for spec in result:
		spec.basis = Basis.IDENTITY
	result.append_array(foundation_boxes())
	for spec in architecture_boxes():
		if spec.solid:
			result.append(spec)
	result.append_array(rock_boxes())
	return result

static func capsule_box_overlap(at: Vector3, radius: float, height: float,
		box: Transform3D, half: Vector3) -> float:
	# Exact segment/AABB distance in box-local coordinates. The capsule's
	# centre segment may be tilted here because the scenery box is rotated.
	var inverse := box.affine_inverse()
	var p := inverse * (at - Vector3.UP * (height / 2.0 - radius))
	var q := inverse * (at + Vector3.UP * (height / 2.0 - radius))
	var direction := q - p
	var cuts: Array[float] = [0.0, 1.0]
	for axis in range(3):
		if direction[axis] != 0.0:
			for boundary in [-half[axis], half[axis]]:
				var t: float = (boundary - p[axis]) / direction[axis]
				if t > 0.0 and t < 1.0:
					cuts.append(t)
	cuts.sort()
	var distance_squared := INF
	for index in range(cuts.size() - 1):
		var low := cuts[index]
		var high := cuts[index + 1]
		var middle := p + direction * ((low + high) / 2.0)
		var numerator := 0.0
		var denominator := 0.0
		for axis in range(3):
			if absf(middle[axis]) > half[axis]:
				var boundary := half[axis] if middle[axis] > 0.0 else -half[axis]
				numerator += direction[axis] * (p[axis] - boundary)
				denominator += direction[axis] * direction[axis]
		var t := clampf(-numerator / denominator, low, high) if denominator > 0.0 else low
		var closest := p + direction * t
		var delta := Vector3(maxf(absf(closest.x) - half.x, 0.0),
			maxf(absf(closest.y) - half.y, 0.0), maxf(absf(closest.z) - half.z, 0.0))
		distance_squared = minf(distance_squared, delta.length_squared())
	return maxf(radius - sqrt(distance_squared), 0.0)
