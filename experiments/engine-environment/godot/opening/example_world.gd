extends "res://opening/opening.gd"
## Reuse the opening's geometry only, inside the example's private World3D.
## No player UI, input, clock, save-slot configuration or gameplay commands.

func _native_transmission() -> bool:
	# This private view uses the native projection while retaining its small
	# teaching-stage background and no player controller.
	return state.get("options", {}).get("native", false)

func _ready() -> void:
	legacy_fixture = true # Geometry-only teaching world, no player controller.
	auto_advance = false
	set_process_input(false)
	set_process_unhandled_input(false)
	_build_world()
	transmission_presenter = load("res://opening/native_transmission_presenter.gd").new()
	add_child(transmission_presenter)
	transmission_presenter.configure(self)
	if model != null and model.boot_result.get("accepted", false):
		_refresh()

func _refresh() -> void:
	super._refresh()
	if transmission_presenter != null:
		transmission_presenter.refresh()

func _process(delta: float) -> void:
	_animate_wheel(delta)
	_update_camera()

func _input(_event: InputEvent) -> void:
	pass

func _unhandled_input(_event: InputEvent) -> void:
	pass
