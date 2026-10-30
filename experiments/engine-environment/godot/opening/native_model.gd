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

func _complete_projection(value: Dictionary, changed_roots: Dictionary = {}) -> bool:
	if _projection_fields.is_empty() or _projection_records.is_empty():
		return false
	var selective := not changed_roots.is_empty() and not changed_roots.has("options")
	if selective:
		for changed_key in changed_roots:
			if not changed_key is String or not _projection_fields.has(changed_key):
				return false
	for name in (changed_roots if selective else _projection_fields):
		if not name is String:
			return false
		var expected: Variant = _projection_fields.get(name)
		var required_with := ""
		if expected is Dictionary:
			if not expected.get("type") is String or not expected.get("required_with") is String:
				return false
			required_with = expected.required_with
			expected = expected.type
		if not value.has(name):
			if not required_with.is_empty() and not _projection_requires(value, required_with):
				continue
			return false
		if not _projection_type_matches(value[name], expected):
			return false
	for name in _projection_records:
		if not name is String:
			return false
		var record: Variant = _projection_records[name]
		if not record is Dictionary or not record.get("fields") is Dictionary \
			or record.fields.is_empty():
			return false
		var required_with: Variant = record.get("required_with", "")
		var keys_with: Variant = record.get("keys_with", "")
		var identity_field: Variant = record.get("identity_field", "")
		var entry_key_map: Variant = record.get("entry_key_map", "")
		var entry_keys_with: Variant = record.get("entry_keys_with", "")
		var entry_keys_when: Variant = record.get("entry_keys_when", "")
		if not required_with is String or not keys_with is String \
			or not identity_field is String or not entry_key_map is String \
			or not entry_keys_with is String or not entry_keys_when is String \
			or typeof(record.get("engine_view_only", false)) != TYPE_BOOL:
			return false
		if selective:
			var root_segment: String = name.split(".")[0]
			var keys_root: String = keys_with.split(".")[0] if not keys_with.is_empty() else ""
			var entry_keys_root: String = entry_keys_with.split(".")[0] if not entry_keys_with.is_empty() else ""
			if not changed_roots.has(root_segment) \
				and (keys_root.is_empty() or not changed_roots.has(keys_root)) \
				and (entry_keys_root.is_empty() or not changed_roots.has(entry_keys_root)):
				continue
		var nested: Variant = value
		var missing := false
		for segment in name.split("."):
			if not nested is Dictionary or not nested.has(segment):
				missing = true
				break
			nested = nested[segment]
		if missing:
			if not required_with.is_empty() and not _projection_requires(value, required_with):
				continue
			return false
		if not keys_with.is_empty():
			var expected_keys: Variant = value
			for segment in keys_with.split("."):
				if not expected_keys is Dictionary or not expected_keys.has(segment):
					return false
				expected_keys = expected_keys[segment]
			if not expected_keys is Dictionary or not nested is Dictionary \
				or expected_keys.size() != nested.size():
				return false
			for key in expected_keys:
				if not nested.has(key): return false
		var entries: Array = []
		match record.get("container"):
			"object":
				entries = [nested]
			"object_values":
				if not nested is Dictionary: return false
				if not identity_field.is_empty():
					for key in nested:
						if not key is String or not nested[key] is Dictionary \
							or nested[key].get(identity_field) != key:
							return false
				entries = nested.values()
			"object_array_elements":
				if not nested is Dictionary: return false
				for group in nested.values():
					if not group is Array: return false
					entries.append_array(group)
			"array_elements":
				if not nested is Array: return false
				entries = nested
			_:
				return false
		for entry in entries:
			if not _projection_record_complete(entry, record.fields) \
				or not _projection_entry_keys_complete(entry, record, value):
				return false
	return true

func _projection_entry_keys_complete(entry: Variant, record: Dictionary,
		projection: Dictionary) -> bool:
	var map_field: Variant = record.get("entry_key_map", "")
	var keys_with: Variant = record.get("entry_keys_with", "")
	var when_true: Variant = record.get("entry_keys_when", "")
	if not map_field is String or not keys_with is String or not when_true is String:
		return false
	if map_field.is_empty() and keys_with.is_empty() and when_true.is_empty():
		return true
	if map_field.is_empty() or keys_with.is_empty() or when_true.is_empty() \
		or not entry is Dictionary:
		return false
	var expected: Variant = projection
	for segment in keys_with.split("."):
		if not expected is Dictionary or not expected.has(segment):
			return true # The source record is absent in this profile.
		expected = expected[segment]
	if not expected is Dictionary:
		return false
	if not _projection_requires(entry, when_true):
		return true
	var actual: Variant = entry
	for segment in map_field.split("."):
		if not actual is Dictionary or not actual.has(segment):
			return false
		actual = actual[segment]
	if not actual is Dictionary or actual.size() != expected.size():
		return false
	for key in expected:
		if not actual.has(key):
			return false
	return true

func _projection_record_complete(entry: Variant, fields: Variant) -> bool:
	if not entry is Dictionary or not fields is Dictionary or fields.is_empty():
		return false
	for field in fields:
		if not field is String:
			return false
		var expected_field: Variant = fields[field]
		var descriptor: Dictionary = {}
		var optional := false
		if expected_field is Dictionary:
			descriptor = expected_field
			if not expected_field.get("type") is String \
				or typeof(expected_field.get("optional", false)) != TYPE_BOOL:
				return false
			optional = expected_field.get("optional", false)
			expected_field = expected_field.type
		var nested_field: Variant = entry
		var field_missing := false
		for segment in field.split("."):
			if not nested_field is Dictionary or not nested_field.has(segment):
				field_missing = true
				break
			nested_field = nested_field[segment]
		if field_missing:
			if optional: continue
			return false
		if not _projection_type_matches(nested_field, expected_field):
			return false
		if descriptor.has("equals"):
			if not _projection_type_matches(descriptor.equals, expected_field) \
				or nested_field != descriptor.equals:
				return false
		if descriptor.has("allowed"):
			var allowed: Variant = descriptor.allowed
			if not allowed is Array or allowed.is_empty(): return false
			for candidate in allowed:
				if not _projection_type_matches(candidate, expected_field): return false
			if not allowed.has(nested_field): return false
	return true

func _projection_requires(value: Dictionary, path: String) -> bool:
	var marker: Variant = value
	for segment in path.split("."):
		if not marker is Dictionary or not marker.has(segment):
			return false
		marker = marker[segment]
	return typeof(marker) == TYPE_BOOL and marker

func _projection_type_matches(value: Variant, expected: Variant) -> bool:
	if not expected is String:
		return false
	match expected:
		"string": return typeof(value) == TYPE_STRING
		"nullable_string": return typeof(value) in [TYPE_NIL, TYPE_STRING]
		"integer": return typeof(value) == TYPE_INT
		"floating": return typeof(value) == TYPE_FLOAT
		"boolean": return typeof(value) == TYPE_BOOL
		"array": return typeof(value) == TYPE_ARRAY
		"object": return typeof(value) == TYPE_DICTIONARY
		"integer_values":
			if not value is Dictionary: return false
			for entry in value.values():
				if typeof(entry) != TYPE_INT: return false
			return true
		"boolean_values":
			if not value is Dictionary: return false
			for entry in value.values():
				if typeof(entry) != TYPE_BOOL: return false
			return true
		"string_array":
			if not value is Array: return false
			for entry in value:
				if typeof(entry) != TYPE_STRING: return false
			return true
		"integer2", "integer3", "floating2", "floating3":
			if not value is Array or value.size() != (2 if expected in ["integer2", "floating2"] else 3):
				return false
			var scalar_type := TYPE_FLOAT if expected in ["floating2", "floating3"] else TYPE_INT
			for coordinate in value:
				if typeof(coordinate) != scalar_type:
					return false
			return true
		"integer3_or_empty":
			return value is Array and (value.is_empty() or _projection_type_matches(value, "integer3"))
		"integer3_array":
			if not value is Array: return false
			for point in value:
				if not _projection_type_matches(point, "integer3"): return false
			return true
		"floating3_pair":
			return value is Array and value.size() == 2 \
				and _projection_type_matches(value[0], "floating3") \
				and _projection_type_matches(value[1], "floating3")
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
	var changed_roots: Dictionary = {}
	if delta.get("full") is Dictionary:
		observed = delta.full
	elif delta.get("changes") is Dictionary and delta.get("removed") is Array:
		if delta.removed.is_empty() and delta.changes.is_empty():
			return _view_cache
		observed = _view_cache.duplicate()
		for key in delta.removed:
			observed.erase(key)
		for key in delta.changes:
			observed[key] = delta.changes[key]
		if delta.removed.is_empty() and not delta.changes.is_empty():
			changed_roots = delta.changes
	else:
		# A boundary refusal is not a confirmed tick or a reusable view.
		_view_cache = {}
		return delta if delta.get("accepted") == false else _projection_unavailable()
	if not _complete_projection(observed, changed_roots):
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
			# A narrow native read must agree with the accepted publication and
			# satisfy the same actor record schema as a complete view.
			var observed: Dictionary = _invoke("actor_projection", [actor])
			var actor_record: Dictionary = _projection_records.get("actors", {})
			var updated: Dictionary = _view_cache.duplicate()
			var actors: Dictionary = _view_cache.actors.duplicate()
			var current: Dictionary = actors[actor].duplicate()
			current.position = observed.get("position")
			current.ready = observed.get("ready")
			current.native_epoch = observed.get("native_epoch")
			current.harvest_clear = observed.get("harvest_clear")
			if observed.get("accepted") != true or current.ready != true \
				or current.native_epoch != native_epoch or current.position != position \
				or not _projection_record_complete(current, actor_record.get("fields")) \
				or not _projection_entry_keys_complete(current, actor_record, _view_cache):
				_view_cache = {}
				return _projection_unavailable()
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
