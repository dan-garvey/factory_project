extends CharacterBody3D
## Local input and native character collision own player motion. No carry offset.
signal moved
const WALK := 2.0
const GRAVITY := 14.0
const JUMP := 6.0
var jump_requested := false
var ticks := 0
var walking_seconds := 0.0
var floor_id := 0
var input_direction := Vector2.ZERO

func _ready() -> void:
	collision_layer = 16
	collision_mask = 1 | 4
	platform_floor_layers = 4
	platform_wall_layers = 0
	floor_snap_length = 0.1
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	collider.shape = capsule
	add_child(collider)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed and not event.echo:
		jump_requested = true
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	ticks += 1
	input_direction = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).normalized()
	if input_direction.x > 0:
		walking_seconds += delta
	velocity.x = input_direction.x * WALK
	velocity.z = input_direction.y * WALK
	velocity.y -= GRAVITY * delta
	if jump_requested and is_on_floor():
		velocity.y = JUMP
	jump_requested = false
	move_and_slide()
	floor_id = 0
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		if collision.get_normal().y > 0.9:
			floor_id = collision.get_collider_id()
	moved.emit()
