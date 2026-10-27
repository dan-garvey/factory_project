extends RefCounted
## Thin engine bridge. All quantities, commands, history and steps are native.
const Site = preload("res://opening/site_geometry.gd")

var native: Object
var boot_result: Dictionary = {"accepted": false, "reason": "native_library_missing"}
var _view_cache: Dictionary = {}
var _projection_fields: Dictionary = {}
var _projection_records: Dictionary = {}
var context: String:
	get:
		return str(projection().get("context", ""))

func _init(world_context: String = "opening-native", actor_ids: Array = ["P"], arrival: bool = false,
		advanced_fixture: bool = false):
	if not ClassDB.class_exists("FactoryNativeWorld"):
		return
	native = ClassDB.instantiate("FactoryNativeWorld")
	if native == null:
		return
	var initializer := "initialize"
	if arrival:
		initializer = "initialize_arrival_advanced_fixture" if advanced_fixture else "initialize_arrival"
	boot_result = _invoke(initializer, [world_context, actor_ids])
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
	var tree_obstacles: Dictionary = {}
	for solid in surface.support_boxes():
		if solid.id == "source_outcrop":
			source_obstacle = obstacles.size()
		var bounds: AABB = Transform3D(solid.basis, solid.center) * AABB(-solid.size * 0.5, solid.size)
		obstacles.append([[bounds.position.x, bounds.position.y, bounds.position.z], [bounds.end.x, bounds.end.y, bounds.end.z]])
	for fir in surface.fir_specs():
		var bounds: AABB = fir.collision_bounds
		tree_obstacles[fir.id] = obstacles.size()
		obstacles.append([[bounds.position.x, bounds.position.y, bounds.position.z], [bounds.end.x, bounds.end.y, bounds.end.z]])
	for broadleaf in surface.broadleaf_specs():
		var bounds: AABB = broadleaf.collision_bounds
		tree_obstacles[broadleaf.id] = obstacles.size()
		obstacles.append([[bounds.position.x, bounds.position.y, bounds.position.z], [bounds.end.x, bounds.end.y, bounds.end.z]])
	if source_obstacle < 0:
		boot_result = {"accepted": false, "reason": "source_outcrop_missing"}
		return
	if arrival:
		boot_result = _invoke("configure_terrain", [{"axis": axis, "heights": heights, "obstacles": obstacles,
			"source_obstacle": source_obstacle, "tree_obstacles": tree_obstacles,
			"flow_cells": surface.flow_cells()}])
	else:
		# The collector still needs the source-rock contact exception. Only the
		# arrival profile owns the named timber sites beside these solid trees.
		boot_result = _invoke("configure_terrain", [{"axis": axis, "heights": heights,
			"obstacles": obstacles, "source_obstacle": source_obstacle,
			"flow_cells": surface.flow_cells()}])
	if not boot_result.get("accepted", false):
		return
	_projection_fields = _invoke("projection_fields", [])
	_projection_records = _invoke("projection_record_fields", [])
	var current: Dictionary = projection()
	if not _complete_projection(current):
		boot_result = {"accepted": false, "reason": "native_projection_schema_mismatch"}
		return
	var profile: Dictionary = current.get("adapter_profile", {})
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
	# Public snapshots can be edited by callers. Do not use one as the base for
	# the next trusted tick delta.
	_view_cache = {}
	return _invoke("projection", [])

func view_projection() -> Dictionary:
	# External callers receive an isolated snapshot they may safely inspect or edit.
	return _view_projection_borrowed().duplicate(true)

func _view_projection_borrowed() -> Dictionary:
	# Only the opening and actor bridge borrow these confirmed World facts. They
	# read without modifying them; commands and ticks replace the cached value.
	if _view_cache.is_empty():
		var observed: Dictionary = projection()
		if not _complete_projection(observed):
			return _projection_unavailable()
		_view_cache = observed
	return _view_cache

func _complete_projection(value: Dictionary) -> bool:
	if _projection_fields.is_empty() or _projection_records.is_empty():
		return false
	for name in _projection_fields:
		if not name is String or not value.has(name) \
			or not _projection_type_matches(value[name], _projection_fields[name]):
			return false
	for name in _projection_records:
		if not name is String:
			return false
		var record: Variant = _projection_records[name]
		if not record is Dictionary or not record.get("fields") is Dictionary \
			or record.fields.is_empty():
			return false
		var required_with: Variant = record.get("required_with", "")
		if not required_with is String:
			return false
		var nested: Variant = value
		var missing := false
		for segment in name.split("."):
			if not nested is Dictionary or not nested.has(segment):
				missing = true
				break
			nested = nested[segment]
		if missing:
			if not required_with.is_empty() and not value.has(required_with):
				continue
			return false
		var entries: Array = []
		match record.get("container"):
			"object":
				entries = [nested]
			"object_values":
				if not nested is Dictionary: return false
				entries = nested.values()
			"array_elements":
				if not nested is Array: return false
				entries = nested
			_:
				return false
		for entry in entries:
			if not entry is Dictionary:
				return false
			for field in record.fields:
				if not field is String or not entry.has(field) \
					or not _projection_type_matches(entry[field], record.fields[field]):
					return false
	return true

func _projection_type_matches(value: Variant, expected: Variant) -> bool:
	if not expected is String:
		return false
	match expected:
		"string": return typeof(value) == TYPE_STRING
		"integer": return typeof(value) == TYPE_INT
		"floating": return typeof(value) == TYPE_FLOAT
		"boolean": return typeof(value) == TYPE_BOOL
		"array": return typeof(value) == TYPE_ARRAY
		"object": return typeof(value) == TYPE_DICTIONARY
		"integer2", "integer3", "floating2", "floating3":
			if not value is Array or value.size() != (2 if expected in ["integer2", "floating2"] else 3):
				return false
			var scalar_type := TYPE_FLOAT if expected in ["floating2", "floating3"] else TYPE_INT
			for coordinate in value:
				if typeof(coordinate) != scalar_type:
					return false
			return true
		"string_pairs", "integer_pairs":
			if not value is Array:
				return false
			var member_type := TYPE_STRING if expected == "string_pairs" else TYPE_INT
			for pair in value:
				if not pair is Array or pair.size() != 2:
					return false
				for member in pair:
					if typeof(member) != member_type:
						return false
			return true
	return false

func _projection_unavailable() -> Dictionary:
	return {"accepted": false, "reason": "native_projection_unavailable", "uncertain": true}

func command(intent: Dictionary) -> Dictionary:
	return command_as("P", intent)

func command_as(authenticated_actor: String, intent: Dictionary) -> Dictionary:
	# Session supplies its authenticated binding, never a client-selected actor.
	# The native Host independently requires the wire client to match it.
	_view_cache = {}
	return _invoke("command", [authenticated_actor, intent])

func advance() -> Dictionary:
	var observed: Dictionary = _advance_borrowed()
	_view_cache = observed.duplicate(true) if _complete_projection(observed) else {}
	return observed

func _advance_borrowed() -> Dictionary:
	# The opening reads this confirmed tick without mutating it. Public advance()
	# keeps its isolated cache for callers that may edit the returned dictionary.
	if _view_cache.is_empty():
		var complete: Dictionary = _invoke("advance", [])
		if not _complete_projection(complete):
			return _projection_unavailable()
		_view_cache = complete
		return complete
	var delta: Dictionary = _invoke("advance_delta", [])
	var observed: Dictionary = {}
	if delta.get("full") is Dictionary:
		observed = delta.full
	elif delta.get("changes") is Dictionary and delta.get("removed") is Array:
		observed = _view_cache.duplicate()
		for key in delta.removed:
			observed.erase(key)
		for key in delta.changes:
			observed[key] = delta.changes[key]
	else:
		# A boundary refusal is not a confirmed tick or a reusable view.
		_view_cache = {}
		return delta if delta.get("accepted") == false else _projection_unavailable()
	if not _complete_projection(observed):
		_view_cache = {}
		return _projection_unavailable()
	_view_cache = observed
	return observed

func publish_actor(actor: String, position: Array, native_epoch: int) -> Dictionary:
	var result: Dictionary = _invoke("publish_actor", [actor, position, native_epoch])
	if not result.get("accepted", false):
		# A rejected malformed sample may invalidate the Host actor.
		_view_cache = {}
	elif not _view_cache.is_empty():
		if not _view_cache.actors.has(actor):
			_view_cache = {}
		else:
			# Scene readers may still hold the previous snapshot. Replace only the
			# actor path so their first-ready decision observes its original state.
			var updated: Dictionary = _view_cache.duplicate()
			var actors: Dictionary = _view_cache.actors.duplicate()
			var current: Dictionary = actors[actor].duplicate()
			current.position = [float(position[0]), float(position[1]), float(position[2])]
			current.ready = true
			current.native_epoch = native_epoch
			current.harvest_clear = _invoke("actor_projection", [actor]).get("harvest_clear", {})
			actors[actor] = current
			updated.actors = actors
			_view_cache = updated
	return result

func actor_projection(actor: String) -> Dictionary:
	return _invoke("actor_projection", [actor])

func invalidate_actor(actor: String) -> void:
	_view_cache = {}
	_invoke("invalidate_actor", [actor])

func checkpoint() -> Dictionary:
	return _invoke("checkpoint", [])

func validate_checkpoint(value: Dictionary) -> Dictionary:
	return _invoke("validate_checkpoint", [value])

func restore_checkpoint(value: Variant) -> Dictionary:
	_view_cache = {}
	return _invoke("restore_checkpoint", [value])
