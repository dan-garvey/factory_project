extends RefCounted
## Shared prototype geometry. These values do not select the game's scale,
## movement tuning, construction range or eventual world representation.

const PITCH := 1.65
const HEIGHT_DENOMINATOR := 4
const HEIGHT_STEP := PITCH / HEIGHT_DENOMINATOR
const FOUNDATION_HEIGHT_UNITS := 2
const FOUNDATION_DEPTH := FOUNDATION_HEIGHT_UNITS * HEIGHT_STEP
const GRID_COORDINATE_LIMIT := 1000000 # Native integer representation bound.
const ANCHOR_HEIGHT := PITCH / 2.0
const WATERWHEEL_RADIUS_HUNDREDTHS := 224
const WATERWHEEL_AXLE_OFFSET_HUNDREDTHS := 200
const WATERWHEEL_RADIUS := WATERWHEEL_RADIUS_HUNDREDTHS * HEIGHT_STEP / 100.0
const BASE_REACH := 4.0

const CAPSULE_RADIUS := 0.3
const CAPSULE_HEIGHT := 1.8
const WALK_SPEED := 3.0
const GRAVITY := 14.0
const JUMP_SPEED := 6.0
const FLOOR_SNAP := 0.1
const SAFE_MARGIN := 0.001

const GROUND_LAYER := 1
const MACHINE_LAYER := 2
const PICK_LAYER := 4
const ACTOR_LAYER := 16
const MACHINE_SIZE := [1.45, 1.65, 1.45]
const MACHINE_CENTER_HEIGHT := 0.8
const COLLECTOR_INTAKE_SIZE := [0.28, 0.20, 0.24]
const COLLECTOR_INTAKE_X := -0.84
const COLLECTOR_INTAKE_Y := 0.50
const COLLECTOR_SECOND_CELL_Z := -0.60
const COLLECTOR_LIFT_PROFILE := {
	"pickup_x": -1.04, "pickup_y": 0.55, "pickup_size": [0.34, 0.30, 0.40],
	"carrier_x": -1.05, "carrier_bottom": 0.67, "carrier_top_offset": 1.95,
	"carrier_size_xz": [0.34, 0.42],
	"guide_offset": [0.09, 0.17], "guide_size": [0.055, 0.055],
	"flight_offset_x": -0.025, "flight_size": [0.25, 0.035, 0.30],
	"flight_count": 5, "flight_span": 0.88,
	"head_x": -0.60, "head_y_offset": 1.77,
	"head_size_xy": [0.90, 0.36], "head_z_size": [0.40, 0.86],
}

static func collector_intake_boxes(entity: Dictionary) -> Dictionary:
	if entity.get("kind") != "collector":
		return {"accepted": true, "boxes": []}
	var cell: Variant = entity.get("cell")
	var level: Variant = entity.get("level", 0)
	if not cell is Array or cell.size() != 2 or typeof(cell[0]) != TYPE_INT or typeof(cell[1]) != TYPE_INT \
			or cell[0] != 0 or cell[1] not in [0, 1] or typeof(level) != TYPE_INT or level not in [0, 4, 8]:
		return {"accepted": false, "boxes": []}
	var machine_z: float = float(cell[1]) * PITCH
	var contact_z: float = machine_z + (0.0 if cell[1] == 0 else COLLECTOR_SECOND_CELL_Z)
	if level == 0:
		return {"accepted": true, "boxes": [{"name": "pickup",
			"center": Vector3(COLLECTOR_INTAKE_X, COLLECTOR_INTAKE_Y, contact_z),
			"size": Vector3(COLLECTOR_INTAKE_SIZE[0], COLLECTOR_INTAKE_SIZE[1], COLLECTOR_INTAKE_SIZE[2])}]}
	var profile: Dictionary = COLLECTOR_LIFT_PROFILE
	var rise: float = float(level) * HEIGHT_STEP
	var top: float = rise + profile.carrier_top_offset
	var carrier := {"center": Vector3(profile.carrier_x, (profile.carrier_bottom + top) * 0.5, contact_z),
		"size": Vector3(profile.carrier_size_xz[0], top - profile.carrier_bottom, profile.carrier_size_xz[1])}
	var head := {"name": "head", "center": Vector3(profile.head_x, rise + profile.head_y_offset,
			(contact_z + machine_z) * 0.5),
		"size": Vector3(profile.head_size_xy[0], profile.head_size_xy[1],
			profile.head_z_size[0] if cell[1] == 0 else profile.head_z_size[1])}
	var bodies: Array[Dictionary] = [{"name": "pickup",
		"center": Vector3(profile.pickup_x, profile.pickup_y, contact_z),
		"size": Vector3(profile.pickup_size[0], profile.pickup_size[1], profile.pickup_size[2])}]
	for side in [-1.0, 1.0]:
		bodies.append({"name": "guide", "center": carrier.center + Vector3(
			profile.guide_offset[0], 0, side * profile.guide_offset[1]),
			"size": Vector3(profile.guide_size[0], carrier.size.y, profile.guide_size[1])})
	for step in range(profile.flight_count):
		bodies.append({"name": "flight", "center": carrier.center + Vector3(
			profile.flight_offset_x,
			carrier.size.y * (float(step) / float(profile.flight_count - 1) - 0.5) * profile.flight_span, 0),
			"size": Vector3(profile.flight_size[0], profile.flight_size[1], profile.flight_size[2])})
	bodies.append(head)
	return {"accepted": true, "boxes": bodies, "carrier": carrier, "head": head}

static func wheel_half_extents(axis: int, tiles: int) -> Vector3:
	var radius := WATERWHEEL_RADIUS * tiles
	return Vector3(0.3 if axis == 0 else radius, radius, 0.3 if axis == 2 else radius)

static func wheel_support_boxes(entity: Dictionary) -> Dictionary:
	var source: Variant = entity.get("supports")
	if not source is Array or source.size() != 2:
		return {"accepted": false}
	var boxes: Array[Dictionary] = []
	for value: Variant in source:
		if not value is Dictionary or value.size() != 2 or not value.has("center") or not value.has("half"):
			return {"accepted": false}
		var center: Variant = value.center
		var half: Variant = value.half
		if not center is Array or not half is Array or center.size() != 3 or half.size() != 3:
			return {"accepted": false}
		for coordinate: Variant in center + half:
			if typeof(coordinate) != TYPE_FLOAT or not is_finite(coordinate):
				return {"accepted": false}
		var size := Vector3(half[0], half[1], half[2]) * 2.0
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			return {"accepted": false}
		boxes.append({"center": Vector3(center[0], center[1], center[2]), "size": size})
	return {"accepted": true, "boxes": boxes}

# Match the existing grid tile tops. The adapter uses WorldBoundaryShape3D;
# its effective extent is backend-specific, not a selected game-world limit.
# This fixture adds no controller position clamp or invisible perimeter wall.
const GROUND_HEIGHT := -0.02
const DISPLAY_GRID_MIN := -2
const DISPLAY_GRID_MAX := 4
const DISPLAY_TERRAIN_SIZE := 256.0
const SPAWN_HEIGHT := 1.0

# Observation tolerance for native registration, never extra build reach.
const NATIVE_POSE_EPSILON := 0.00001

static func work_anchor(cell: Array) -> Array:
	if cell.size() != 2 or not cell[0] is int or not cell[1] is int:
		return []
	# Keep permission arithmetic in scalar floats. Converting to Vector3 here
	# would round an exact boundary before Model evaluates the reach sphere.
	return [cell[0] * PITCH, ANCHOR_HEIGHT, cell[1] * PITCH]

static func spawn(actor: String) -> Array:
	match actor:
		"P": return [-PITCH, SPAWN_HEIGHT, 2.0 * PITCH]
		"Q": return [-PITCH, SPAWN_HEIGHT, 3.0 * PITCH]
	return []

static func valid_position(position) -> bool:
	if not position is Array or position.size() != 3:
		return false
	for coordinate in position:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
			return false
	# Native representability and collision realization belong to the adapter.
	# A serialized sanity check must not invent a maximum game-world extent.
	return true

static func _mechanical_point(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate: Variant in value:
		if typeof(coordinate) != TYPE_INT or coordinate < -1000000 or coordinate > 1000000 or coordinate % 4 != 0:
			return false
	return true

static func _mechanical_center(point: Array) -> Vector3:
	return Vector3(point[0] * HEIGHT_STEP, ANCHOR_HEIGHT + point[1] * HEIGHT_STEP, point[2] * HEIGHT_STEP)

static func mechanical_boxes(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if snapshot.get("options", {}).get("native", false) != true:
		return {"accepted": true, "boxes": result}
	var parts: Variant = snapshot.get("transmission_parts")
	var spans: Variant = snapshot.get("belt_spans")
	if not parts is Dictionary or not spans is Dictionary:
		return {"accepted": false}
	for id: Variant in parts:
		var part: Variant = parts[id]
		if typeof(id) != TYPE_STRING or not part is Dictionary or not _mechanical_point(part.get("center")) or typeof(part.get("axis")) != TYPE_INT or part.axis not in [0, 1, 2]:
			return {"accepted": false}
		var half := Vector3.ONE * 0.1
		if part.get("kind") == "shaft" and part.get("half_span") == 2 and typeof(part.get("half_span")) == TYPE_INT:
			half[part.axis] = PITCH / 2.0
		elif part.get("kind") == "gear" and typeof(part.get("teeth")) == TYPE_INT and part.teeth > 0:
			half = Vector3.ONE * (PITCH / 2.0)
			half[part.axis] = 0.04
		else:
			return {"accepted": false}
		result[id] = {"center": _mechanical_center(part.center), "size": half * 2.0}
		if part.kind == "gear":
			var axle_half := Vector3.ONE * 0.1
			axle_half[part.axis] = PITCH / 2.0
			result[id]["axle_size"] = axle_half * 2.0
	for id: Variant in spans:
		var span: Variant = spans[id]
		if typeof(id) != TYPE_STRING or result.has(id) or not span is Dictionary or typeof(span.get("from")) != TYPE_STRING or typeof(span.get("to")) != TYPE_STRING:
			return {"accepted": false}
		var first: Variant = parts.get(span.from)
		var last: Variant = parts.get(span.to)
		if not first is Dictionary or not last is Dictionary or first.kind != "shaft" or last.kind != "shaft" or first.axis != last.axis:
			return {"accepted": false}
		var delta := Vector3i(last.center[0] - first.center[0], last.center[1] - first.center[1], last.center[2] - first.center[2])
		if delta[first.axis] != 0:
			return {"accepted": false}
		var distance := maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.z)))
		if distance < 4 or distance > 76:
			return {"accepted": false}
		var changed := 0
		for axis: int in 3:
			if delta[axis] != 0:
				changed += 1
				if absi(delta[axis]) != distance:
					return {"accepted": false}
		if changed > 2 or (first.axis == 1 and changed != 1):
			return {"accepted": false}
		var direction: int = 2 if delta.z != 0 else (0 if delta.x != 0 else 1)
		var size := Vector3(0.6, 0.3, 0.6)
		size[direction] = distance * HEIGHT_STEP + PITCH
		var basis := Basis.IDENTITY
		if first.axis == 1:
			size.y = 0.6
			size[2 if direction == 0 else 0] = 0.3
		elif direction == 1:
			size[2 if first.axis == 0 else 0] = 0.3
		elif delta.y != 0:
			size[direction] *= sqrt(2.0)
			var angle := atan2(float(delta.y), float(delta[direction]))
			# Normalize endpoint order so equivalent spans register the same basis.
			if delta[direction] < 0:
				angle = atan2(float(-delta.y), float(-delta[direction]))
			basis = Basis(Vector3(0, 0, 1), angle) if direction == 0 else Basis(Vector3(1, 0, 0), -angle)
		var spec := {"center": (_mechanical_center(first.center) + _mechanical_center(last.center)) / 2.0, "size": size}
		if basis != Basis.IDENTITY:
			spec["basis"] = basis
		result[id] = spec
	return {"accepted": true, "boxes": result}
