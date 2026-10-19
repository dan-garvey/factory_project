extends CharacterBody3D
## One native movement producer. Input is supplied by the trusted offline or
## server binding; this body never reads a camera, build command or client pose.
const Geometry = preload("res://opening/site_geometry.gd")

var motion_enabled := false
var direction := Vector2.ZERO
var jump_requested := false
var ticks := 0
var floor_id := 0
var capsule: CapsuleShape3D

func _ready() -> void:
	collision_layer = Geometry.ACTOR_LAYER
	collision_mask = Geometry.GROUND_LAYER | Geometry.MACHINE_LAYER
	platform_floor_layers = collision_mask
	platform_wall_layers = 0
	floor_snap_length = Geometry.FLOOR_SNAP
	safe_margin = Geometry.SAFE_MARGIN
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	capsule = CapsuleShape3D.new()
	capsule.radius = Geometry.CAPSULE_RADIUS
	capsule.height = Geometry.CAPSULE_HEIGHT
	collider.shape = capsule
	add_child(collider)

func set_control(world_xz: Vector2, jump: bool) -> void:
	# Clamp magnitude in the producer, so a diagonal cannot increase speed.
	# Smaller analog values remain smaller; callers never choose a delta time.
	direction = world_xz.limit_length(1.0)
	jump_requested = jump_requested or jump

func release_control() -> void:
	direction = Vector2.ZERO
	jump_requested = false
	velocity.x = 0.0
	velocity.z = 0.0
	# Gravity continues. Releasing controls is not a physical time freeze.

func _physics_process(delta: float) -> void:
	if not motion_enabled:
		return
	ticks += 1
	velocity.x = direction.x * Geometry.WALK_SPEED
	velocity.z = direction.y * Geometry.WALK_SPEED
	velocity.y -= Geometry.GRAVITY * delta
	if jump_requested and is_on_floor():
		velocity.y = Geometry.JUMP_SPEED
	jump_requested = false
	move_and_slide()
	floor_id = 0
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		if collision.get_normal().y > 0.9:
			floor_id = collision.get_collider_id()
