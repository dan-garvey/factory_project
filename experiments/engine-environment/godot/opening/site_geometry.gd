extends RefCounted
## Shared prototype geometry. These values do not select the game's scale,
## movement tuning, construction range or eventual world representation.

const PITCH := 1.65
const HEIGHT_DENOMINATOR := 4
const HEIGHT_STEP := PITCH / HEIGHT_DENOMINATOR
const FOUNDATION_DEPTH := 2.0 * HEIGHT_STEP
const GRID_COORDINATE_LIMIT := 1000000 # Native integer representation bound.
const ANCHOR_HEIGHT := 0.5
const WATERWHEEL_RADIUS := 2.0 * HEIGHT_STEP
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

static func wheel_half_extents(axis: int, tiles: int) -> Vector3:
	var radius := WATERWHEEL_RADIUS * tiles
	return Vector3(0.3 if axis == 0 else radius, radius, 0.3 if axis == 2 else radius)

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
	for id: Variant in spans:
		var span: Variant = spans[id]
		if typeof(id) != TYPE_STRING or result.has(id) or not span is Dictionary or typeof(span.get("from")) != TYPE_STRING or typeof(span.get("to")) != TYPE_STRING:
			return {"accepted": false}
		var first: Variant = parts.get(span.from)
		var last: Variant = parts.get(span.to)
		if not first is Dictionary or not last is Dictionary or first.kind != "shaft" or last.kind != "shaft" or first.axis != last.axis or first.axis == 1:
			return {"accepted": false}
		var direction: int = 2 if first.axis == 0 else 0
		for axis: int in 3:
			if axis != direction and first.center[axis] != last.center[axis]:
				return {"accepted": false}
		var distance: int = absi(last.center[direction] - first.center[direction])
		if distance < 4 or distance > 76:
			return {"accepted": false}
		var size := Vector3(0.6, 0.3, 0.6)
		size[direction] = distance * HEIGHT_STEP + PITCH
		result[id] = {"center": (_mechanical_center(first.center) + _mechanical_center(last.center)) / 2.0, "size": size}
	return {"accepted": true, "boxes": result}
