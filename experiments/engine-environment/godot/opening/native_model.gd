extends RefCounted
## Thin engine bridge. All quantities, commands, history and steps are native.
const Site = preload("res://opening/site_geometry.gd")

var native: Object
var boot_result: Dictionary = {"accepted": false, "reason": "native_library_missing"}
var context: String:
	get:
		return str(projection().get("context", ""))

func _init(world_context: String = "opening-native", actor_ids: Array = ["P"]):
	if not ClassDB.class_exists("FactoryNativeWorld"):
		return
	native = ClassDB.instantiate("FactoryNativeWorld")
	if native == null:
		return
	boot_result = _invoke("initialize", [world_context, actor_ids])
	if not boot_result.get("accepted", false):
		return
	# Supply the actual emitted terrain to the native placement adapter once.
	# This trusted startup call is never exposed through Session's command wire.
	var surface = load("res://opening/site_surface.gd")
	var vertices: PackedVector3Array = surface.vertices()
	var width: int = surface.grid_size()
	var axis: Array = []
	var heights: Array = []
	for x in range(width):
		axis.append(float(vertices[x].x))
	for vertex in vertices:
		heights.append(float(vertex.y))
	var obstacles: Array = []
	var source_obstacle := -1
	for solid in surface.support_boxes():
		if solid.id == "source_outcrop":
			source_obstacle = obstacles.size()
		var bounds: AABB = Transform3D(solid.basis, solid.center) * AABB(-solid.size * 0.5, solid.size)
		obstacles.append([[bounds.position.x, bounds.position.y, bounds.position.z], [bounds.end.x, bounds.end.y, bounds.end.z]])
	for fir in surface.fir_specs():
		var bounds: AABB = fir.bounds
		obstacles.append([[bounds.position.x, bounds.position.y, bounds.position.z], [bounds.end.x, bounds.end.y, bounds.end.z]])
	if source_obstacle < 0:
		boot_result = {"accepted": false, "reason": "source_outcrop_missing"}
		return
	boot_result = _invoke("configure_terrain", [{"axis": axis, "heights": heights, "obstacles": obstacles,
		"source_obstacle": source_obstacle, "flow_cells": surface.flow_cells()}])
	if not boot_result.get("accepted", false):
		return
	var profile: Dictionary = projection().get("adapter_profile", {})
	if profile.get("pitch") != Site.PITCH or profile.get("height_denominator") != Site.HEIGHT_DENOMINATOR or profile.get("height_step") != Site.HEIGHT_STEP or profile.get("foundation_depth") != Site.FOUNDATION_DEPTH or profile.get("anchor_height") != Site.ANCHOR_HEIGHT or profile.get("wheel_radius") != Site.WATERWHEEL_RADIUS_HUNDREDTHS or profile.get("wheel_axle_offset") != Site.WATERWHEEL_AXLE_OFFSET_HUNDREDTHS or profile.get("capsule_radius") != Site.CAPSULE_RADIUS or profile.get("capsule_height") != Site.CAPSULE_HEIGHT or profile.get("collector_intake_size") != Site.COLLECTOR_INTAKE_SIZE or profile.get("collector_intake_x") != Site.COLLECTOR_INTAKE_X or profile.get("collector_intake_y") != Site.COLLECTOR_INTAKE_Y or profile.get("collector_second_cell_z") != Site.COLLECTOR_SECOND_CELL_Z:
		boot_result = {"accepted": false, "reason": "native_scene_profile_mismatch"}
	if profile.get("collector_lift") != Site.COLLECTOR_LIFT_PROFILE:
		boot_result = {"accepted": false, "reason": "native_scene_profile_mismatch"}

func _invoke(method: String, arguments: Array) -> Dictionary:
	if native == null:
		return {"accepted": false, "reason": "native_library_missing"}
	var value = native.callv(method, arguments)
	if not value is Dictionary:
		# A failed native delivery is not a definitive material refusal. Stop
		# this owned session before another request can duplicate uncertain work.
		push_error("Native World delivery failed; no alternate authority is selected")
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			loop.quit(1)
		return {"accepted": false, "reason": "native_delivery_unavailable", "uncertain": true}
	return value

func projection() -> Dictionary:
	return _invoke("projection", [])

func command(intent: Dictionary) -> Dictionary:
	return command_as("P", intent)

func command_as(authenticated_actor: String, intent: Dictionary) -> Dictionary:
	# Session supplies its authenticated binding, never a client-selected actor.
	# The native Host independently requires the wire client to match it.
	return _invoke("command", [authenticated_actor, intent])

func advance() -> Dictionary:
	return _invoke("advance", [])

func publish_actor(actor: String, position: Array, native_epoch: int) -> Dictionary:
	return _invoke("publish_actor", [actor, position, native_epoch])

func invalidate_actor(actor: String) -> void:
	_invoke("invalidate_actor", [actor])

func checkpoint() -> Dictionary:
	return _invoke("checkpoint", [])

func validate_checkpoint(value: Dictionary) -> Dictionary:
	return _invoke("validate_checkpoint", [value])

func restore_checkpoint(value: Variant) -> Dictionary:
	return _invoke("restore_checkpoint", [value])
