extends Node3D
## Spatial inspection fixture. Existing Drive owns every source/branch phase.
## Coupons are immutable contacts, not items, resources or production outputs.
signal advanced(outcome: Dictionary)
const Drive = preload("res://mechanics/authority.gd")
const HEAD_SIZE := Vector3(0.4, 0.4, 0.4)
const REACH := 1.2
const CASES := {
	"gantry_base": ["gantry", false, "clear"], "rotary_base": ["rotary", false, "clear"],
	"gantry_grown": ["gantry", true, "clear"], "rotary_grown": ["rotary", true, "clear"],
	"duplicate": ["duplicate", true, "clear"], "overclock": ["rotary", true, "overclock"],
	"reversed_face": ["gantry", true, "reversed_face"], "low_mount": ["gantry", true, "low_mount"],
	"far_mount": ["gantry", true, "far_mount"], "shielded": ["gantry", true, "shielded"], "empty": ["gantry", true, "empty"]}
var case_name := "gantry_grown"
var layout := "gantry"
var grown := true
var variant := "clear"
var drives: Array = []
var heads: Array = []
var coupons: Array = []
var shield: StaticBody3D
var pending := false
var awaiting_heads := false
var remaining_drives := 0
var running := false
var steps := 0
var published := {}
var visited: Array[String] = []
var encounters: Array = []
var minimum := Vector3(INF, INF, INF)
var maximum := Vector3(-INF, -INF, -INF)

func configure(name: String) -> bool:
	if is_inside_tree() or not CASES.has(name):
		return false
	case_name = name
	layout = CASES[name][0]
	grown = CASES[name][1]
	variant = CASES[name][2]
	return true

func _ready() -> void:
	# The legacy rig remains real/native, separated from this query layer and
	# outside the presentation. Its completed phase is the sole drive input.
	for index in range(2 if layout == "duplicate" else 1):
		var drive = Drive.new()
		drive.position.z = 25.0 + index * 8.0
		add_child(drive)
		drive.command({"action": "gearing", "idler": true, "teeth": 20 if variant == "overclock" else 40})
		drive.advanced.connect(_drive_completed)
		drives.append(drive)
	var count := 2 if grown and variant != "overclock" else 1
	for index in range(count):
		var head := AnimatableBody3D.new()
		head.name = "Head%d" % index
		head.sync_to_physics = false
		head.collision_layer = 0
		head.collision_mask = 0
		_shape(head, HEAD_SIZE)
		add_child(head)
		heads.append(head)
	if variant != "empty":
		for row in range(2 if grown else 1):
			for side in [-1, 1]:
				var coupon := StaticBody3D.new()
				coupon.name = "Coupon_%d_%d" % [row, side]
				coupon.set_meta("work_face", true)
				coupon.collision_layer = 16
				coupon.collision_mask = 0
				_shape(coupon, Vector3(0.5, 0.2, 0.5))
				add_child(coupon)
				coupon.position = Vector3(side * 2.0, 0, row * 3.0)
				coupons.append(coupon)
	shield = StaticBody3D.new()
	shield.name = "AccessShield"
	shield.collision_layer = 32
	shield.collision_mask = 0
	_shape(shield, Vector3(5.0, 0.1, 4.0))
	add_child(shield)
	# Below moving heads: blocks inspection access, not carrier-body motion.
	shield.position = Vector3(0, 0.55 if variant == "shielded" else 5.0, 1.5)
	_move_heads()

func _shape(body: CollisionObject3D, size: Vector3) -> void:
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	node.shape = box
	body.add_child(node)

func _move_heads() -> void:
	for index in range(heads.size()):
		var phase: float = drives[index if layout == "duplicate" else 0].projection().completed.get("phases", {"B": 0.0}).B
		var at := Vector3.ZERO
		if layout == "gantry":
			at = Vector3(2.0 * sin(phase), 1.2, index * 3.0)
		else:
			var radius := sqrt(13.0) if layout == "rotary" and index == 1 else 2.0
			at = Vector3(radius * cos(phase), 1.2, radius * sin(phase) + (index * 3.0 if layout == "duplicate" else 0.0))
		if variant == "low_mount":
			at.y = -0.6
		elif variant == "far_mount":
			at.y = 2.4
		heads[index].position = at
		heads[index].rotation.z = PI if variant == "reversed_face" else 0.0

func command(intent: Dictionary) -> Dictionary:
	if pending:
		return {"accepted": false, "reason": "step_pending"}
	match intent.get("action", ""):
		"run":
			if not intent.get("active") is bool:
				return {"accepted": false, "reason": "invalid_active"}
			running = intent.active
			for drive in drives:
				drive.command(intent)
			return {"accepted": true, "reason": "applied"}
		"step":
			if not running:
				return {"accepted": false, "reason": "source_stopped"}
			if published.is_empty():
				return {"accepted": false, "reason": "initial_geometry_pending"}
			pending = true
			remaining_drives = drives.size()
			for drive in drives:
				drive.command(intent)
			return {"accepted": true, "reason": "queued_for_physics"}
	return {"accepted": false, "reason": "unsupported_action"}

func _drive_completed(outcome: Dictionary) -> void:
	assert(outcome.accepted) # The unchanged drive's own lanes are clear.
	remaining_drives -= 1
	if remaining_drives == 0:
		_move_heads()
		awaiting_heads = true

func _native(body: PhysicsBody3D) -> Transform3D:
	return PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)

func _synchronized() -> bool:
	for body in heads + coupons + [shield]:
		if not _native(body).is_equal_approx(body.global_transform):
			return false
	for drive in drives:
		if drive.projection().native_pending:
			return false
	return true

func _physics_process(_delta: float) -> void:
	if not _synchronized():
		return
	if published.is_empty():
		_publish(false)
	elif awaiting_heads:
		awaiting_heads = false
		steps += 1
		_publish(true)
		pending = false
		advanced.emit({"accepted": true, "state": projection()})

func _publish(inspect: bool) -> void:
	var poses: Array = []
	var rays: Array = []
	for head in heads:
		var native := _native(head)
		poses.append({"position": _array(native.origin), "down": _array(-native.basis.y)})
		minimum = minimum.min(native.origin - HEAD_SIZE / 2.0)
		maximum = maximum.max(native.origin + HEAD_SIZE / 2.0)
		if inspect:
			var start := native.origin - native.basis.y * HEAD_SIZE.y / 2.0
			var direction := -native.basis.y
			var query := PhysicsRayQueryParameters3D.create(start, start + direction * REACH, 48)
			query.hit_from_inside = false
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			var sample := {"from": _array(start), "to": _array(start + direction * REACH), "hit": "", "eligible": false}
			if not hit.is_empty():
				var collider: CollisionObject3D = hit.collider
				sample.hit = str(collider.name)
				sample.point = _array(hit.position)
				sample.normal = _array(hit.normal)
				# A one-sided top-face inspection, not a recipe or harvested item.
				sample.eligible = collider.get_meta("work_face", false) and direction.dot(Vector3.DOWN) > 0.99 and hit.normal.dot(Vector3.UP) > 0.99
				if sample.eligible:
					if not sample.hit in visited:
						visited.append(sample.hit)
					encounters.append({"step": steps, "head": str(head.name), "coupon": sample.hit, "point": sample.point, "normal": sample.normal})
			rays.append(sample)
	visited.sort()
	var phases: Array = []
	for drive in drives:
		phases.append(drive.projection().completed.duplicate(true))
	published = {"heads": poses, "rays": rays, "drives": phases, "steps": steps,
		"visited": visited.duplicate(), "encounters": encounters.duplicate(true),
		"bounds": {"min": _array(minimum), "max": _array(maximum)}}

func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func projection() -> Dictionary:
	return {"case": case_name, "layout": layout, "grown": grown, "variant": variant,
		"running": running, "pending": pending, "steps": steps, "head_count": heads.size(),
		"drive_count": drives.size(), "coupon_count": coupons.size(), "completed": published.duplicate(true)}
