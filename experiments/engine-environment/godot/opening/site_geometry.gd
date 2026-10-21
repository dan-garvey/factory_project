extends RefCounted
## Shared prototype geometry. These values do not select the game's scale,
## movement tuning, construction range or eventual world representation.

const PITCH := 1.65
const HEIGHT_DENOMINATOR := 4
const HEIGHT_STEP := PITCH / HEIGHT_DENOMINATOR
const GRID_COORDINATE_LIMIT := 1000000 # Native integer representation bound.
const ANCHOR_HEIGHT := 0.5
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
