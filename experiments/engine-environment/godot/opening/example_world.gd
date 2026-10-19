extends "res://opening/opening.gd"
## Reuse the opening's geometry only, inside the example's private World3D.
## No player UI, input, clock, save-slot configuration or gameplay commands.

func _ready() -> void:
	legacy_fixture = true # Geometry-only teaching world, no player controller.
	auto_advance = false
	set_process_input(false)
	set_process_unhandled_input(false)
	_build_world()
	_refresh()

func _process(delta: float) -> void:
	if wheel_rotor != null and state.get("powered", false):
		wheel_rotor.rotation.z += delta * 0.8
	_update_camera()

func _input(_event: InputEvent) -> void:
	pass

func _unhandled_input(_event: InputEvent) -> void:
	pass
