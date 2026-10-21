extends RefCounted
## Immutable fixture geometry shared by terrain rendering and native collision.
## These dimensions and heights are adapter data, not a selected world-size rule.
const Geometry = preload("res://opening/site_geometry.gd")
const SUBDIVISIONS := 72
const SIZE := Geometry.DISPLAY_TERRAIN_SIZE
const HALF := SIZE * 0.5
const LOCAL_STEP := 0.25
const LOCAL_MIN := -10.0
const LOCAL_MAX := 12.0
static var _axis := PackedFloat32Array()
static var _vertices := PackedVector3Array()
static var _faces := PackedVector3Array()
const ROCK_SIZE := Vector3(1.35, 0.88, 1.12)
const ROCK_TRIANGLES := [
	0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
	1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
	3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
	4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
static var _rock_points := PackedVector3Array()
static var _rock_faces := PackedVector3Array()

static func _prepare_rock() -> void:
	if not _rock_points.is_empty():
		return
	var t := (1.0 + sqrt(5.0)) / 2.0
	var seeds := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	# Irregular triangular facets replace the six flat sides of a cut block.
	# Every point stays within the old conservative foliage-clearance envelope.
	var radii := [0.93, 1.0, 0.88, 0.95, 0.91, 0.98, 0.94, 0.86, 0.97, 0.9, 1.0, 0.92]
	for index in range(seeds.size()):
		_rock_points.append(seeds[index] * (ROCK_SIZE * 0.5 / t) * radii[index])
	for first in range(0, ROCK_TRIANGLES.size(), 3):
		# Godot front faces use clockwise winding.
		for offset in [0, 2, 1]:
			_rock_faces.append(_rock_points[ROCK_TRIANGLES[first + offset]])

static func rock_vertices(scale: Vector3 = Vector3.ONE) -> PackedVector3Array:
	_prepare_rock()
	var result := PackedVector3Array()
	for point in _rock_points:
		result.append(point * scale)
	return result

static func rock_faces(scale: Vector3 = Vector3.ONE) -> PackedVector3Array:
	_prepare_rock()
	var result := PackedVector3Array()
	for point in _rock_faces:
		result.append(point * scale)
	return result

static func match_native_rock(actual: PackedVector3Array, source: PackedVector3Array) -> PackedVector3Array:
	# Pinned GodotPhysics3D cooks hull points on a per-AABB integer grid.
	# Bind that documented projection without padding contacts or build reach.
	if actual.size() != source.size() or source.size() != 12:
		return PackedVector3Array()
	var bounds := AABB(source[0], Vector3.ZERO)
	for point in source:
		if not point.is_finite():
			return PackedVector3Array()
		bounds = bounds.expand(point)
	var limit := bounds.size / 10216.0 + Vector3.ONE * Geometry.NATIVE_POSE_EPSILON
	var used := {}
	var ordered := PackedVector3Array()
	for point in source:
		var found := -1
		for index in range(actual.size()):
			if not actual[index].is_finite():
				return PackedVector3Array()
			var delta := (actual[index] - point).abs()
			if delta.x <= limit.x and delta.y <= limit.y and delta.z <= limit.z:
				if found >= 0 or used.has(index):
					return PackedVector3Array()
				found = index
		if found < 0:
			return PackedVector3Array()
		used[found] = true
		ordered.append(actual[found])
	return ordered

static func rock_faces_for_vertices(points: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	if points.size() != 12:
		return result
	for first in range(0, ROCK_TRIANGLES.size(), 3):
		for offset in [0, 2, 1]:
			result.append(points[ROCK_TRIANGLES[first + offset]])
	return result

static func river_center_x(z: float) -> float:
	var reach := maxf(0.0, absf(z - 1.65) - 14.5)
	var bend := smoothstep(0.0, 26.0, reach)
	# Bend away from the construction bank, retaining its existing anchors.
	var near_bend := -0.9 * (1.0 - cos((z - 1.65) * 0.30)) - 0.05 * (1.0 - cos(z * 0.85))
	return -2.7 + bend * (sin(z * 0.042) * 8.0 + cos(z * 0.019) * 3.8) + (1.0 - bend) * near_bend

static func channel_half_width(z: float) -> float:
	var flare := smoothstep(5.5, 22.0, absf(z - 1.65))
	var bank_variation := 0.06 * sin(z * 0.82) + 0.025 * sin(z * 2.31)
	return lerpf(0.62 + bank_variation, 1.85, flare)

static func raw_height(x: float, z: float) -> float:
	# Preserve the original distant hills while resolving the natural worksite.
	# Physics and rendering use the same emitted triangles, rather than this
	# smooth vertex-height function between the emitted vertices.
	var rc := river_center_x(z)
	var half_w := channel_half_width(z)
	var dx_river := absf(x - rc)
	var downstream_drop := 0.48 * smoothstep(8.2, 10.6, z)
	var bed_y := -1.18 - downstream_drop + 0.035 * sin(z * 0.35 + x * 1.4)
	var pad_dx := maxf(0.0, absf(x - 1.65) - 6.85)
	var pad_dz := maxf(0.0, absf(z - 1.65) - 6.85)
	var pad_dist := sqrt(pad_dx * pad_dx + pad_dz * pad_dz)
	var base_y := Geometry.GROUND_HEIGHT
	if pad_dist > 0.0:
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
	var near_bank := 0.78 + 0.12 * sin(z * 0.63) if x < rc else 0.24 + 0.03 * cos(z * 0.75)
	var bank_span := lerpf(near_bank, 5.2, smoothstep(5.5, 24.0, absf(z - 1.65)))
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
	# Retain the distant lattice samples and resolve the actual clearing/banks.
	# Both renderer and collision consume these same float32 coordinates.
	var coordinates: Dictionary = {}
	for n in range(SUBDIVISIONS + 1):
		var rounded := PackedFloat32Array([-HALF + float(n) / SUBDIVISIONS * SIZE])
		coordinates[rounded[0]] = true
	for n in range(roundi(LOCAL_MIN / LOCAL_STEP), roundi(LOCAL_MAX / LOCAL_STEP) + 1):
		coordinates[float(n) * LOCAL_STEP] = true
	var ordered: Array = coordinates.keys()
	ordered.sort()
	_axis = PackedFloat32Array(ordered)
	var stride := _axis.size()
	for gz in range(stride):
		var z := _axis[gz]
		for gx in range(stride):
			var x := _axis[gx]
			_vertices.append(Vector3(x, raw_height(x, z), z))
	for gz in range(stride - 1):
		for gx in range(stride - 1):
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
	return _vertices[gz * _axis.size() + gx]

static func grid_size() -> int:
	_prepare()
	return _axis.size()

static func _axis_cell(value: float) -> int:
	var low := 0
	var high := _axis.size() - 1
	while low + 1 < high:
		var middle := (low + high) >> 1
		if value < _axis[middle]:
			high = middle
		else:
			low = middle
	return clampi(low, 0, _axis.size() - 2)

static func cell(x: float, z: float) -> Vector2i:
	# Bounds and interpolation use the emitted float32 coordinates, not an
	# unrounded analytical grid or an added gameplay/reach epsilon.
	_prepare()
	return Vector2i(_axis_cell(x), _axis_cell(z))

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
				var first := (gz * (_axis.size() - 1) + gx) * 6
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
	# Unbuilt ground is the continuous terrain, never a hidden tiled platform.
	return []

static func group_origin(group: String) -> Vector3:
	match group:
		"HeadraceGorge": return Vector3(-2.7, 0.0, -5.65)
		"TailraceCascade": return Vector3(-2.7, 0.0, 8.65)
		"NorthSeamOutcrop": return Vector3(0.0, 0.0, -5.48)
	return Vector3.ZERO

static func architecture_boxes() -> Array[Dictionary]:
	# River banks and bed come from the same natural terrain used by physics.
	return []

static func foundation_boxes() -> Array[Dictionary]:
	# There are no player-unbuilt slabs, rails, crags shaped as piers or ledges.
	return []

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
			"basis": rotation, "size": ROCK_SIZE * scale, "scale": scale,
			"points": rock_vertices(scale), "faces": rock_faces(scale),
			"color": Color("59605a").lerp(Color("7d7a6e"), float(n % 4) / 3.0)})
	return result

static func support_boxes() -> Array[Dictionary]:
	# Retain the descriptor API for cosmetic clearance. Its size is an envelope;
	# only the shared convex points/faces define visible and physical rock contact.
	return rock_boxes()

static func capsule_convex_overlap(at: Vector3, radius: float, height: float,
		solid: Transform3D, triangles: PackedVector3Array) -> float:
	if not at.is_finite() or not is_finite(radius) or not is_finite(height) or radius <= 0.0 \
		or height < radius * 2.0 or triangles.is_empty() or triangles.size() % 3 != 0:
		return INF
	var inverse := solid.affine_inverse()
	var half_segment := height / 2.0 - radius
	var p := inverse * (at - Vector3.UP * half_segment)
	var q := inverse * (at + Vector3.UP * half_segment)
	var p_inside := true
	var q_inside := true
	var distance := INF
	for first in range(0, triangles.size(), 3):
		var a := triangles[first]
		var b := triangles[first + 1]
		var c := triangles[first + 2]
		var normal := (c - a).cross(b - a)
		if not a.is_finite() or not b.is_finite() or not c.is_finite() or normal.length_squared() == 0.0:
			return INF
		# The shared convex template encloses its local origin.
		if normal.dot(a) < 0.0:
			normal = -normal
		p_inside = p_inside and normal.dot(p - a) <= 0.0
		q_inside = q_inside and normal.dot(q - a) <= 0.0
		distance = minf(distance, _segment_triangle_distance(p, q, a, b, c))
	if p_inside or q_inside:
		distance = 0.0
	# This is a labelled analytical overlap measure, not native contact depth.
	return maxf(radius - distance, 0.0)

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
