extends RefCounted
## Experimental engine-coupled rule owner. No scene nodes or rendering callbacks.
## Neutral recipe/capacities are fixture values, not accepted chapter content.
const Site = preload("res://opening/site_geometry.gd")

var context: String
var initial_feed: int
var recipe_input: int
var revision := 0
var order := 0
var entities: Dictionary = {}
var links: Array = []
var parts := {"collector": 1, "belt": 1, "processor": 1}
var stock: Dictionary
var inventories: Dictionary = {}
var remaining := 0
var requests: Dictionary = {}
var options: Dictionary = {}
var drive_links: Array = []
var power_enabled := true
var next_ids: Dictionary = {}
# Persistent positions/capabilities; native registration and observation ordinals
# are deliberately separate from saved actor state and material request order.
var actors: Dictionary = {}
var actor_runtime: Dictionary = {}
var _admission_receipt: Dictionary = {}

func _init(feed: int = 8, world_context: String = "engine-fixture-1", required: int = 2, settings: Dictionary = {}, initial_actors: Array = ["P"]):
	assert(feed >= 0 and required > 0)
	initial_feed = feed
	context = world_context
	recipe_input = required
	options = settings.duplicate(true)
	if _opening():
		parts.merge({"wheel": 1, "shaft": 3})
	for kind in parts:
		if kind != "shaft":
			next_ids[kind] = 1
	stock = {"source": feed, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0}
	if _physical():
		assert(initial_actors.size() in [1, 2] and initial_actors.has("P"))
		for actor in initial_actors:
			assert(actor is String and actor in ["P", "Q"] and not actors.has(actor))
			actors[actor] = {"position": Site.spawn(actor), "capabilities": {"build_reach": Site.BASE_REACH}}

func _physical() -> bool:
	return _opening() and options.get("physical") is bool and options.physical

func publish_actor(actor: String, position: Array, native_epoch: int) -> Dictionary:
	# Trusted native adapter bridge only. Neither command() nor Session RPCs can
	# supply a pose/capability/epoch. This does not consume a build request.
	if not _physical() or not actors.has(actor):
		return {"accepted": false, "reason": "unknown_actor"}
	if not _finite_point(position) or not Site.valid_position(position) or native_epoch < 1:
		invalidate_actor(actor)
		return {"accepted": false, "reason": "invalid_actor_sample"}
	if native_epoch <= actor_runtime.get(actor, {}).get("native_epoch", 0):
		return {"accepted": false, "reason": "stale_actor_sample"}
	actors[actor].position = position.duplicate()
	actor_runtime[actor] = {"ready": true, "native_epoch": native_epoch}
	return {"accepted": true, "reason": "actor_published"}

func invalidate_actor(actor: String) -> void:
	if actors.has(actor):
		actor_runtime[actor] = {"ready": false, "native_epoch": 0}

func _finite_point(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
			return false
	return true

func _squared_distance(a: Array, b: Array) -> float:
	# Scalar arithmetic keeps the declared interaction anchor distinct from
	# approximate Vector3 rendering/collision coordinates; no permission epsilon.
	var result := 0.0
	for axis in range(3):
		var difference := float(a[axis]) - float(b[axis])
		result += difference * difference
	return result

func _reach_guard(intent: Dictionary, cells: Array) -> Dictionary:
	if not _physical():
		return {}
	var actor: String = intent.client
	if not actors.has(actor) or not actor_runtime.get(actor, {}).get("ready", false):
		return _outcome(false, "actor_unready")
	var state: Dictionary = actors[actor]
	var targets: Array = []
	var distances: Array = []
	var reachable := true
	var radius: float = state.capabilities.build_reach
	for cell in cells:
		var target: Array = Site.work_anchor(cell)
		targets.append(target)
		var squared := _squared_distance(state.position, target)
		if not is_finite(squared):
			# Malformed trusted samples must not poison the plain-value cache with
			# Infinity. Real native representability is checked by the adapter.
			invalidate_actor(actor)
			return _outcome(false, "invalid_actor_sample")
		distances.append(squared)
		reachable = reachable and squared <= radius * radius
	_admission_receipt = {"actor": actor, "position": state.position.duplicate(),
		"native_epoch": actor_runtime[actor].native_epoch, "build_reach": radius,
		"targets": targets, "distances_squared": distances, "reachable": reachable}
	return {} if reachable else _outcome(false, "out_of_reach")

func _actor_intersects_cell(position: Array, cell: Array) -> bool:
	# Chosen physical-demo placement policy, not a Godot constraint: never build
	# the fixture box through a ready actor's upright capsule. Tangency is allowed.
	var anchor: Array = Site.work_anchor(cell)
	var radius: float = Site.CAPSULE_RADIUS
	var segment_half: float = Site.CAPSULE_HEIGHT / 2.0 - radius
	var dx := maxf(absf(float(position[0]) - float(anchor[0])) - Site.MACHINE_SIZE[0] / 2.0, 0.0)
	var dz := maxf(absf(float(position[2]) - float(anchor[2])) - Site.MACHINE_SIZE[2] / 2.0, 0.0)
	var below: float = Site.MACHINE_CENTER_HEIGHT - Site.MACHINE_SIZE[1] / 2.0 - (float(position[1]) + segment_half)
	var above: float = float(position[1]) - segment_half - (Site.MACHINE_CENTER_HEIGHT + Site.MACHINE_SIZE[1] / 2.0)
	var dy := maxf(maxf(below, above), 0.0)
	return dx * dx + dy * dy + dz * dz < radius * radius

func _placement_blockers(cell: Array) -> Array:
	var blockers: Array = []
	for actor in actors:
		var runtime: Dictionary = actor_runtime.get(actor, {})
		if runtime.get("ready", false) and _actor_intersects_cell(actors[actor].position, cell):
			blockers.append({"actor": actor, "position": actors[actor].position.duplicate(), "native_epoch": runtime.native_epoch})
	return blockers

func command(intent: Dictionary) -> Dictionary:
	if not _plain_value(intent, [100000]):
		return _outcome(false, "non_value_intent")
	if not intent.get("context") is String or intent.context != context:
		return _outcome(false, "wrong_context")
	if not intent.get("client") is String or not intent.get("request") is String:
		return _outcome(false, "missing_request_identity")
	if intent.client.is_empty() or intent.request.is_empty():
		return _outcome(false, "missing_request_identity")
	if not intent.get("action", "") is String:
		return _outcome(false, "invalid_action")
	var key: String = JSON.stringify([intent.client, intent.request])
	if requests.has(key):
		if not _same_plain(requests[key].intent, intent):
			return _outcome(false, "request_reuse")
		var repeated: Dictionary = requests[key].result.duplicate(true)
		repeated["duplicate"] = true
		return repeated
	order += 1
	_admission_receipt = {}
	var result: Dictionary
	match intent.get("action", ""):
		"place": result = _place(intent)
		"connect": result = _connect(intent)
		"retrieve": result = _retrieve(intent)
		"connect_drive": result = _connect_drive(intent)
		"set_power": result = _set_power(intent)
		"remove": result = _remove(intent)
		"disconnect": result = _disconnect(intent, false)
		"disconnect_drive": result = _disconnect(intent, true)
		_: result = _outcome(false, "unsupported_action")
	if not _admission_receipt.is_empty():
		result["reach"] = _admission_receipt.duplicate(true)
	if result.accepted:
		revision += 1
		result.revision = revision
	result["client"] = intent.client
	result["request"] = intent.request
	requests[key] = {"intent": intent.duplicate(true), "result": result.duplicate(true)}
	return result

func _outcome(accepted: bool, reason: String, entity: String = "") -> Dictionary:
	return {"accepted": accepted, "reason": reason, "entity": entity,
		"context": context, "revision": revision, "order": order, "duplicate": false}

func _place(intent: Dictionary) -> Dictionary:
	if _opening() and _powered():
		return _outcome(false, "powered")
	var kind = intent.get("kind", "")
	var cell = intent.get("cell", [])
	if not kind is String or not parts.has(kind) or kind == "shaft":
		return _outcome(false, "unknown_kind")
	if not cell is Array or cell.size() != 2:
		return _outcome(false, "invalid_cell")
	for value in cell:
		if not value is int or value < -2 or value > 4:
			return _outcome(false, "invalid_cell")
	for entity in entities.values():
		if entity.cell == cell:
			return _outcome(false, "occupied")
	if parts[kind] < 1:
		return _outcome(false, "no_part")
	if kind == "wheel" and cell[0] != -1:
		return _outcome(false, "not_at_stream")
	if _opening() and kind == "collector" and cell[0] != 0:
		return _outcome(false, "not_at_seam")
	if _physical() and actor_runtime.get(intent.client, {}).get("ready", false):
		var blockers := _placement_blockers(cell)
		if not blockers.is_empty():
			var refusal := _outcome(false, "actor_occupied")
			refusal["blockers"] = blockers
			return refusal
	var guard := _reach_guard(intent, [cell])
	if not guard.is_empty():
		return guard
	var entity_id: String = kind + "-" + str(next_ids[kind])
	next_ids[kind] += 1
	entities[entity_id] = {"kind": kind, "cell": cell.duplicate()}
	parts[kind] -= 1
	return _outcome(true, "placed", entity_id)

func _connect(intent: Dictionary) -> Dictionary:
	if _opening() and _powered():
		return _outcome(false, "powered")
	var source = intent.get("from", "")
	var target = intent.get("to", "")
	if not source is String or not target is String or not entities.has(source) or not entities.has(target):
		return _outcome(false, "missing_entity")
	if not ["collector>belt", "belt>processor"].has(entities[source].kind + ">" + entities[target].kind):
		return _outcome(false, "unsupported_connection")
	var a: Array = entities[source].cell
	var b: Array = entities[target].cell
	if b != [a[0] + 1, a[1]]:
		return _outcome(false, "ports_not_adjacent")
	var pair := [source, target]
	if links.has(pair):
		return _outcome(false, "already_connected")
	var guard := _reach_guard(intent, [a, b])
	if not guard.is_empty():
		return guard
	links.append(pair)
	return _outcome(true, "connected")

func _retrieve(intent: Dictionary) -> Dictionary:
	if intent.has("entity") and (not intent.entity is String or intent.entity != _kind_id("processor")):
		return _outcome(false, "missing_entity")
	var amount = intent.get("amount", 1)
	if not amount is int or amount < 1 or amount > stock.output:
		return _outcome(false, "unavailable_output")
	var guard := _reach_guard(intent, [entities[_kind_id("processor")].cell]) if _physical() else {}
	if not guard.is_empty():
		return guard
	stock.output -= amount
	inventories[intent.client] = inventories.get(intent.client, 0) + amount
	return _outcome(true, "retrieved", _kind_id("processor"))

func _opening() -> bool:
	return options.get("opening") is bool and options.opening

func _kind_id(kind: String) -> String:
	for entity_id in entities:
		if entities[entity_id].kind == kind:
			return entity_id
	return ""

func _powered() -> bool:
	if not _opening():
		return true
	if not power_enabled or _kind_id("wheel").is_empty():
		return false
	var reached: Array = [_kind_id("wheel")]
	for _pass in range(entities.size()):
		for pair in drive_links:
			if reached.has(pair[0]) and not reached.has(pair[1]):
				reached.append(pair[1])
			if reached.has(pair[1]) and not reached.has(pair[0]):
				reached.append(pair[0])
	for kind in ["collector", "belt", "processor"]:
		if _kind_id(kind).is_empty() or not reached.has(_kind_id(kind)):
			return false
	return true

func _connect_drive(intent: Dictionary) -> Dictionary:
	if not _opening():
		return _outcome(false, "unsupported_action")
	if _powered():
		return _outcome(false, "powered")
	var source = intent.get("from", "")
	var target = intent.get("to", "")
	if not source is String or not target is String or not entities.has(source) or not entities.has(target) or source == target:
		return _outcome(false, "missing_entity")
	var a: Array = entities[source].cell
	var b: Array = entities[target].cell
	if absi(a[0] - b[0]) + absi(a[1] - b[1]) != 1:
		return _outcome(false, "ports_not_adjacent")
	if drive_links.has([source, target]) or drive_links.has([target, source]):
		return _outcome(false, "already_connected")
	if parts.shaft < 1:
		return _outcome(false, "no_shaft")
	var guard := _reach_guard(intent, [a, b])
	if not guard.is_empty():
		return guard
	drive_links.append([source, target])
	parts.shaft -= 1
	return _outcome(true, "connected", target)

func _set_power(intent: Dictionary) -> Dictionary:
	if not _opening() or not intent.get("active") is bool:
		return _outcome(false, "unsupported_action")
	if _physical():
		var wheel := _kind_id("wheel")
		if wheel.is_empty():
			return _outcome(false, "missing_entity")
		var guard := _reach_guard(intent, [entities[wheel].cell])
		if not guard.is_empty():
			return guard
	power_enabled = intent.active
	return _outcome(true, "power_changed", _kind_id("wheel"))

func _disconnect(intent: Dictionary, drive: bool) -> Dictionary:
	if not _opening():
		return _outcome(false, "unsupported_action")
	if _powered():
		return _outcome(false, "powered")
	if not intent.get("from") is String or not intent.get("to") is String:
		return _outcome(false, "missing_connection")
	var pair := [intent.from, intent.to]
	var connections: Array = drive_links if drive else links
	if drive and not connections.has(pair):
		pair.reverse()
	if not connections.has(pair):
		return _outcome(false, "missing_connection")
	# Receipts retain original intent endpoint order even when the undirected
	# drive edge was stored in reverse. Historical validation uses that order.
	var guard := _reach_guard(intent, [entities[intent.from].cell, entities[intent.to].cell])
	if not guard.is_empty():
		return guard
	connections.erase(pair)
	if drive:
		parts.shaft += 1
	return _outcome(true, "disconnected")

func _remove(intent: Dictionary) -> Dictionary:
	if not _opening():
		return _outcome(false, "unsupported_action")
	if _powered():
		return _outcome(false, "powered")
	var entity_id = intent.get("entity", "")
	if not entity_id is String or not entities.has(entity_id):
		return _outcome(false, "missing_entity")
	var kind: String = entities[entity_id].kind
	var occupied: int = stock.get(kind, 0)
	if kind == "processor":
		occupied = stock.input + stock.held + stock.output
	if occupied > 0:
		return _outcome(false, "held_stock")
	var guard := _reach_guard(intent, [entities[entity_id].cell])
	if not guard.is_empty():
		return guard
	for pair in links.duplicate(true):
		if pair.has(entity_id):
			links.erase(pair)
	for pair in drive_links.duplicate(true):
		if pair.has(entity_id):
			drive_links.erase(pair)
			parts.shaft += 1
	entities.erase(entity_id)
	parts[kind] += 1
	return _outcome(true, "removed", entity_id)

func advance(ticks: int = 1) -> Dictionary:
	assert(ticks >= 0)
	for _tick in range(ticks):
		# Fixed explicit authority order; view frame timing cannot create products.
		if not _powered():
			revision += 1
			continue
		if stock.held > 0:
			remaining = maxi(0, remaining - 1)
			if remaining == 0 and stock.output < 1:
				stock.held = 0
				stock.output += 1
		if not _kind_id("processor").is_empty() and stock.held == 0 and stock.input >= recipe_input:
			stock.input -= recipe_input
			stock.held = recipe_input
			remaining = 2
		if links.has([_kind_id("belt"), _kind_id("processor")]) and stock.belt > 0 and stock.input < recipe_input:
			stock.belt -= 1
			stock.input += 1
		if links.has([_kind_id("collector"), _kind_id("belt")]) and stock.collector > 0 and stock.belt < 1:
			stock.collector -= 1
			stock.belt += 1
		if not _kind_id("collector").is_empty() and stock.source > 0 and stock.collector < (1 if _opening() else 2):
			stock.source -= 1
			stock.collector += 1
		revision += 1
	return projection()

func projection() -> Dictionary:
	var counts: Dictionary = stock.duplicate(true)
	counts["player"] = 0
	for quantity in inventories.values():
		counts.player += quantity
	var value := {"context": context, "revision": revision, "order": order,
		"initial_feed": initial_feed, "recipe_input": recipe_input,
		"entities": entities.duplicate(true), "links": links.duplicate(true),
		"stock": counts, "inventories": inventories.duplicate(true),
		"remaining": remaining, "powered": _powered(), "power_enabled": power_enabled,
		"drive_links": drive_links.duplicate(true), "options": options.duplicate(true),
		"parts": parts.duplicate(true)}
	if _physical():
		value["actors"] = actors.duplicate(true)
		for actor in value.actors:
			value.actors[actor].merge(actor_runtime.get(actor, {"ready": false, "native_epoch": 0}), true)
	return value

func checkpoint() -> Dictionary:
	var value := {"schema": 2 if _physical() else 1, "context": context, "initial_feed": initial_feed,
		"recipe_input": recipe_input, "revision": revision, "order": order,
		"entities": entities.duplicate(true), "links": links.duplicate(true),
		"parts": parts.duplicate(true), "stock": stock.duplicate(true),
		"inventories": inventories.duplicate(true), "remaining": remaining,
		"requests": requests.duplicate(true), "options": options.duplicate(true),
		"drive_links": drive_links.duplicate(true), "power_enabled": power_enabled,
		"next_ids": next_ids.duplicate(true)}
	if _physical():
		value["actors"] = actors.duplicate(true)
	return value

func restore_checkpoint(snapshot: Variant) -> Dictionary:
	# The live caller selects its profile BEFORE reading input. A saved option
	# cannot turn the normal physical opening back into the unrestricted fixture.
	if _physical() and (not snapshot is Dictionary or snapshot.get("schema") != 2
		or not snapshot.get("options") is Dictionary or snapshot.options.get("physical") != true):
		return {"accepted": false, "reason": "physical_state_required"}
	if _physical() and snapshot.get("actors") is Dictionary:
		if snapshot.actors.size() != actors.size():
			return {"accepted": false, "reason": "actor_roster_mismatch"}
		for actor in actors:
			if not snapshot.actors.has(actor):
				return {"accepted": false, "reason": "actor_roster_mismatch"}
	var validation: Variant = _validate_checkpoint(snapshot)
	# Runtime failure/implicit empty return can never become a positive verdict.
	if not validation is Dictionary or not validation.get("valid") is bool:
		return {"accepted": false, "reason": "invalid_checkpoint"}
	if not validation.valid:
		return {"accepted": false, "reason": validation.get("reason", "invalid_checkpoint")}
	# Validation has no side effects. Publish only a complete owned candidate.
	actors = {}
	actor_runtime = {}
	_admission_receipt = {}
	for field in snapshot:
		if field == "schema":
			continue
		var value = snapshot[field]
		set(field, value.duplicate(true) if value is Dictionary or value is Array else value)
	return {"accepted": true, "reason": "restored"}

func _count(value: Variant) -> bool:
	return value is int and value >= 0

func _invalid_checkpoint(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}

func _plain_value(value: Variant, budget: Array, depth: int = 0) -> bool:
	# Bound this prototype's plain-data traversal; reject cycles before copying.
	if depth > 32 or budget[0] <= 0:
		return false
	budget[0] -= 1
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for child in value:
				if not _plain_value(child, budget, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not key is String or not _plain_value(value[key], budget, depth + 1):
					return false
			return true
	return false

func _same_plain(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not _same_plain(a[key], b[key]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for index in range(a.size()):
			if not _same_plain(a[index], b[index]):
				return false
		return true
	return a == b

func _validate_checkpoint(data: Variant) -> Dictionary:
	if not _plain_value(data, [100000]):
		return _invalid_checkpoint("non_value_checkpoint")
	var fields := ["schema", "context", "initial_feed", "recipe_input", "revision", "order", "entities",
		"links", "parts", "stock", "inventories", "remaining", "requests", "options", "drive_links", "power_enabled", "next_ids"]
	if data is Dictionary and data.get("schema") is int and data.schema == 2:
		fields.append("actors")
	if not data is Dictionary or data.size() != fields.size():
		return _invalid_checkpoint("invalid_fields")
	for field in fields:
		if not data.has(field):
			return _invalid_checkpoint("missing_field")
	if not data.schema is int or not data.schema in [1, 2]:
		return _invalid_checkpoint("unsupported_schema")
	if not data.context is String or data.context.is_empty():
		return _invalid_checkpoint("invalid_context")
	for field in ["initial_feed", "recipe_input", "revision", "order", "remaining"]:
		if not _count(data[field]):
			return _invalid_checkpoint("invalid_counter")
	if data.recipe_input < 1 or data.remaining > 2:
		return _invalid_checkpoint("invalid_phase")
	for field in ["entities", "parts", "stock", "inventories", "requests", "options", "next_ids"]:
		if not data[field] is Dictionary:
			return _invalid_checkpoint("invalid_dictionary")
	if not data.links is Array or not data.drive_links is Array or not data.power_enabled is bool:
		return _invalid_checkpoint("invalid_topology")
	if data.schema == 1:
		if data.options.size() > 1 or (data.options.size() == 1 and (not data.options.has("opening") or not data.options.opening is bool)):
			return _invalid_checkpoint("invalid_options")
	else:
		if data.options.size() != 2 or not data.options.get("opening") is bool or not data.options.opening or not data.options.get("physical") is bool or not data.options.physical:
			return _invalid_checkpoint("invalid_physical_profile")
		if not data.actors is Dictionary or not data.actors.size() in [1, 2] or not data.actors.has("P"):
			return _invalid_checkpoint("invalid_actors")
		for actor in data.actors:
			if not actor in ["P", "Q"]:
				return _invalid_checkpoint("invalid_actors")
		for state in data.actors.values():
			if not state is Dictionary or state.size() != 2 or not _finite_point(state.get("position")) or not Site.valid_position(state.position):
				return _invalid_checkpoint("invalid_actor_position")
			var capabilities = state.get("capabilities")
			if not capabilities is Dictionary or capabilities.size() != 1 or not capabilities.get("build_reach") is float or capabilities.build_reach != Site.BASE_REACH:
				return _invalid_checkpoint("invalid_actor_capability")
	var opening: bool = data.options.get("opening", false)
	var kinds: Array = ["collector", "belt", "processor", "wheel"] if opening else ["collector", "belt", "processor"]
	if data.next_ids.size() != kinds.size() or data.parts.size() != kinds.size() + (1 if opening else 0):
		return _invalid_checkpoint("invalid_parts")
	var counts: Dictionary = {}
	for kind in kinds:
		if not data.next_ids.has(kind) or not _count(data.next_ids[kind]) or data.next_ids[kind] < 1 or not data.parts.has(kind) or not _count(data.parts[kind]):
			return _invalid_checkpoint("invalid_parts")
		counts[kind] = 0
	var cells: Array = []
	for entity_id in data.entities:
		var entity = data.entities[entity_id]
		if not entity_id is String or not entity is Dictionary or entity.size() != 2 or not entity.has("kind") or not entity.kind is String or not kinds.has(entity.kind) or not entity.has("cell"):
			return _invalid_checkpoint("invalid_entity")
		var cell = entity.cell
		if not cell is Array or cell.size() != 2:
			return _invalid_checkpoint("invalid_cell")
		for value in cell:
			if not value is int or value < -2 or value > 4:
				return _invalid_checkpoint("invalid_cell")
		if cells.has(cell):
			return _invalid_checkpoint("invalid_cell")
		if entity.kind == "wheel" and cell[0] != -1:
			return _invalid_checkpoint("invalid_wheel_site")
		if opening and entity.kind == "collector" and cell[0] != 0:
			return _invalid_checkpoint("invalid_collector_site")
		cells.append(cell)
		counts[entity.kind] += 1
		var suffix: String = entity_id.trim_prefix(entity.kind + "-")
		if not suffix.is_valid_int() or suffix.to_int() < 1 or entity_id != entity.kind + "-" + str(suffix.to_int()) or suffix.to_int() >= data.next_ids[entity.kind]:
			return _invalid_checkpoint("invalid_identity")
	for kind in kinds:
		if counts[kind] > 1 or data.parts[kind] != 1 - counts[kind]:
			return _invalid_checkpoint("invalid_parts")
	for drive in [false, true]:
		var group: Array = data.drive_links if drive else data.links
		var seen: Array = []
		for pair in group:
			if not pair is Array or pair.size() != 2 or not pair[0] is String or not pair[1] is String or pair[0] == pair[1] or not data.entities.has(pair[0]) or not data.entities.has(pair[1]):
				return _invalid_checkpoint("dangling_connection")
			var a: Dictionary = data.entities[pair[0]]
			var b: Dictionary = data.entities[pair[1]]
			var identity: Array = pair.duplicate()
			if drive:
				identity.sort()
				if not opening or absi(a.cell[0] - b.cell[0]) + absi(a.cell[1] - b.cell[1]) != 1:
					return _invalid_checkpoint("invalid_drive")
			elif not ["collector>belt", "belt>processor"].has(a.kind + ">" + b.kind) or b.cell != [a.cell[0] + 1, a.cell[1]]:
				return _invalid_checkpoint("invalid_ports")
			if seen.has(identity):
				return _invalid_checkpoint("duplicate_connection")
			seen.append(identity)
	if opening and (not data.parts.has("shaft") or not _count(data.parts.shaft) or data.parts.shaft != 3 - data.drive_links.size()):
		return _invalid_checkpoint("invalid_shaft_stock")
	var locations := ["source", "collector", "belt", "input", "held", "output"]
	if data.stock.size() != locations.size():
		return _invalid_checkpoint("invalid_stock")
	var raw := 0
	for location in locations:
		if not data.stock.has(location) or not _count(data.stock[location]):
			return _invalid_checkpoint("invalid_stock")
		if location != "output":
			if data.stock[location] > data.initial_feed - raw:
				return _invalid_checkpoint("quantity_mismatch")
			raw += data.stock[location]
	if data.stock.collector > (1 if opening else 2) or data.stock.belt > 1 or data.stock.input > data.recipe_input or data.stock.output > 1:
		return _invalid_checkpoint("invalid_capacity")
	if not data.stock.held in [0, data.recipe_input] or (data.stock.held == 0 and data.remaining != 0):
		return _invalid_checkpoint("invalid_phase")
	for kind in ["collector", "belt", "processor"]:
		var held: int = data.stock.get(kind, 0) if kind != "processor" else data.stock.input + data.stock.held + data.stock.output
		if held > 0 and counts[kind] == 0:
			return _invalid_checkpoint("missing_stock_owner")
	var material_remaining: int = data.initial_feed - raw
	var products: Array = [data.stock.output]
	for actor in data.inventories:
		if not actor is String or actor.is_empty() or not _count(data.inventories[actor]):
			return _invalid_checkpoint("invalid_inventory")
		products.append(data.inventories[actor])
	for quantity in products:
		if quantity > material_remaining / data.recipe_input:
			return _invalid_checkpoint("quantity_mismatch")
		material_remaining -= quantity * data.recipe_input
	if material_remaining != 0:
		return _invalid_checkpoint("quantity_mismatch")
	if data.requests.size() != data.order:
		return _invalid_checkpoint("invalid_request_order")
	var orders: Array = []
	var history: Array = []
	for key in data.requests:
		var record = data.requests[key]
		if not key is String or not record is Dictionary or not record.has("intent") or not record.has("result") or not record.intent is Dictionary or not record.result is Dictionary:
			return _invalid_checkpoint("invalid_request")
		var intent: Dictionary = record.intent
		var result: Dictionary = record.result
		if not intent.get("client") is String or intent.client.is_empty() or not intent.get("request") is String or intent.request.is_empty() or not intent.get("context") is String or intent.context != data.context or not intent.get("action", "") is String or key != JSON.stringify([intent.client, intent.request]):
			return _invalid_checkpoint("invalid_request_identity")
		for field in ["accepted", "reason", "entity", "context", "revision", "order", "duplicate", "client", "request"]:
			if not result.has(field):
				return _invalid_checkpoint("invalid_request_result")
		for field in ["context", "client", "request", "reason", "entity"]:
			if not result[field] is String:
				return _invalid_checkpoint("invalid_request_result")
		if not result.accepted is bool or not result.duplicate is bool or result.duplicate or result.context != data.context or result.client != intent.client or result.request != intent.request or result.reason.is_empty():
			return _invalid_checkpoint("invalid_request_result")
		if not _count(result.revision) or result.revision > data.revision or not _count(result.order) or result.order < 1 or result.order > data.order or orders.has(result.order):
			return _invalid_checkpoint("invalid_request_order")
		orders.append(result.order)
		history.append(record)
		if result.accepted and intent.get("action") == "place":
			var kind = intent.get("kind", "")
			if not kinds.has(kind):
				return _invalid_checkpoint("invalid_request_entity")
			var suffix: String = result.entity.trim_prefix(kind + "-")
			if not suffix.is_valid_int() or suffix.to_int() < 1 or suffix.to_int() >= data.next_ids[kind] or result.entity != kind + "-" + str(suffix.to_int()):
				return _invalid_checkpoint("invalid_identity_history")
	return _validate_history(data, kinds, history)

func _historical_reach_targets(intent: Dictionary, live: Dictionary) -> Array:
	var cells: Array = []
	match intent.get("action", ""):
		"place":
			var cell = intent.get("cell")
			if not cell is Array or cell.size() != 2:
				return []
			for coordinate in cell:
				if not coordinate is int or coordinate < -2 or coordinate > 4:
					return []
			cells.append(cell)
		"connect", "connect_drive", "disconnect", "disconnect_drive":
			for endpoint in ["from", "to"]:
				var entity = intent.get(endpoint)
				if not entity is String or not live.has(entity):
					return []
				cells.append(live[entity].cell)
		"remove":
			var entity = intent.get("entity")
			if not entity is String or not live.has(entity):
				return []
			cells.append(live[entity].cell)
		"retrieve", "set_power":
			var kind := "processor" if intent.action == "retrieve" else "wheel"
			for entity in live.values():
				if entity.kind == kind:
					cells.append(entity.cell)
		_: return []
	var points: Array = []
	for cell in cells:
		points.append(Site.work_anchor(cell))
	return points

func _validate_reach_history(record: Dictionary, live: Dictionary, saved_actors: Dictionary) -> Dictionary:
	var intent: Dictionary = record.intent
	var result: Dictionary = record.result
	if not result.has("reach"):
		return _invalid_checkpoint("missing_reach_receipt") if result.accepted or result.reason == "out_of_reach" else {"valid": true}
	var receipt = result.reach
	var fields := ["actor", "position", "native_epoch", "build_reach", "targets", "distances_squared", "reachable"]
	if not receipt is Dictionary or receipt.size() != fields.size():
		return _invalid_checkpoint("invalid_reach_receipt")
	for field in fields:
		if not receipt.has(field):
			return _invalid_checkpoint("invalid_reach_receipt")
	if not receipt.actor is String or receipt.actor != intent.client or not saved_actors.has(receipt.actor):
		return _invalid_checkpoint("invalid_reach_actor")
	if not _finite_point(receipt.position) or not Site.valid_position(receipt.position) or not receipt.native_epoch is int or receipt.native_epoch < 1:
		return _invalid_checkpoint("invalid_reach_pose")
	if not receipt.build_reach is float or receipt.build_reach != Site.BASE_REACH or not receipt.reachable is bool:
		return _invalid_checkpoint("invalid_reach_capability")
	var targets := _historical_reach_targets(intent, live)
	if targets.is_empty() or not _same_plain(receipt.targets, targets) or not receipt.distances_squared is Array or receipt.distances_squared.size() != targets.size():
		return _invalid_checkpoint("invalid_reach_targets")
	var reachable := true
	for index in range(targets.size()):
		var squared := _squared_distance(receipt.position, targets[index])
		if not receipt.distances_squared[index] is float or receipt.distances_squared[index] != squared:
			return _invalid_checkpoint("invalid_reach_distance")
		reachable = reachable and squared <= receipt.build_reach * receipt.build_reach
	if receipt.reachable != reachable or result.accepted != reachable or (not reachable and result.reason != "out_of_reach"):
		return _invalid_checkpoint("contradictory_reach")
	# Receipt epochs describe their original native process, not the newly
	# restored actor. Never compare them with current/final positions or epochs.
	return {"valid": true}

func _validate_blocked_history(record: Dictionary, saved_actors: Dictionary) -> Dictionary:
	var result: Dictionary = record.result
	var intent: Dictionary = record.intent
	if result.accepted or result.reason != "actor_occupied" or intent.get("action") != "place" or result.has("reach"):
		return _invalid_checkpoint("invalid_occupied_outcome")
	var cell = intent.get("cell")
	if not cell is Array or cell.size() != 2:
		return _invalid_checkpoint("invalid_occupied_target")
	for coordinate in cell:
		if not coordinate is int or coordinate < -2 or coordinate > 4:
			return _invalid_checkpoint("invalid_occupied_target")
	var blockers = result.get("blockers")
	if not blockers is Array or blockers.is_empty() or blockers.size() > saved_actors.size():
		return _invalid_checkpoint("invalid_blocker_receipt")
	var seen: Array = []
	for blocker in blockers:
		if not blocker is Dictionary or blocker.size() != 3 or not blocker.get("actor") is String or not saved_actors.has(blocker.actor) or seen.has(blocker.actor):
			return _invalid_checkpoint("invalid_blocker_actor")
		if not _finite_point(blocker.get("position")) or not blocker.get("native_epoch") is int or blocker.native_epoch < 1 or not _actor_intersects_cell(blocker.position, cell):
			return _invalid_checkpoint("invalid_blocker_pose")
		seen.append(blocker.actor)
	# Blocker positions are historical admission evidence, not final actor poses.
	return {"valid": true}

func _validate_history(data: Dictionary, kinds: Array, history: Array) -> Dictionary:
	history.sort_custom(func(a, b): return a.result.order < b.result.order)
	var previous_revision := 0
	var generated: Dictionary = {}
	for kind in kinds:
		generated[kind] = 1
	var live: Dictionary = {}
	var material_links: Array = []
	var drives: Array = []
	var collected: Dictionary = {}
	var enabled := true
	var reasons := {"place": "placed", "connect": "connected", "connect_drive": "connected",
		"remove": "removed", "retrieve": "retrieved", "set_power": "power_changed",
		"disconnect": "disconnected", "disconnect_drive": "disconnected"}
	for record in history:
		var intent: Dictionary = record.intent
		var result: Dictionary = record.result
		if result.revision < previous_revision or (result.accepted and result.revision <= previous_revision):
			return _invalid_checkpoint("contradictory_revision_history")
		previous_revision = result.revision
		if data.schema == 2:
			if result.has("blockers") or result.reason == "actor_occupied":
				var blocked_validation := _validate_blocked_history(record, data.actors)
				if not blocked_validation.valid:
					return blocked_validation
			var reach_validation := _validate_reach_history(record, live, data.actors)
			if not reach_validation.valid:
				return reach_validation
		if not result.accepted:
			if not result.entity.is_empty():
				return _invalid_checkpoint("contradictory_rejection")
			continue
		var action: String = intent.get("action", "")
		if not reasons.has(action) or result.reason != reasons[action]:
			return _invalid_checkpoint("contradictory_outcome")
		match action:
			"place":
				var kind = intent.get("kind", "")
				var cell = intent.get("cell")
				if not kind is String or not generated.has(kind) or not cell is Array or cell.size() != 2:
					return _invalid_checkpoint("contradictory_placement")
				for value in cell:
					if not value is int or value < -2 or value > 4:
						return _invalid_checkpoint("contradictory_placement")
				var expected: String = kind + "-" + str(generated[kind])
				if result.entity != expected:
					return _invalid_checkpoint("contradictory_generated_identity")
				for existing in live.values():
					if existing.kind == kind or existing.cell == cell:
						return _invalid_checkpoint("contradictory_placement")
				live[expected] = {"kind": kind, "cell": cell.duplicate()}
				generated[kind] += 1
			"remove":
				if not intent.get("entity") is String or not live.has(intent.entity) or result.entity != intent.entity:
					return _invalid_checkpoint("contradictory_removal")
				live.erase(intent.entity)
				for edges in [material_links, drives]:
					for pair in edges.duplicate(true):
						if pair.has(intent.entity):
							edges.erase(pair)
			"retrieve":
				var amount = intent.get("amount", 1)
				if not _count(amount) or amount < 1 or not live.has(result.entity) or live[result.entity].kind != "processor":
					return _invalid_checkpoint("contradictory_retrieval")
				if intent.has("entity") and (not intent.entity is String or intent.entity != result.entity):
					return _invalid_checkpoint("contradictory_retrieval_target")
				var prior: int = collected.get(intent.client, 0)
				if amount > data.initial_feed - prior:
					return _invalid_checkpoint("contradictory_retrieval")
				collected[intent.client] = prior + amount
			"connect", "connect_drive", "disconnect", "disconnect_drive":
				if not intent.get("from") is String or not intent.get("to") is String or not live.has(intent.from) or not live.has(intent.to) or intent.from == intent.to:
					return _invalid_checkpoint("contradictory_connection")
				var expected_target: String = intent.to if action == "connect_drive" else ""
				if result.entity != expected_target:
					return _invalid_checkpoint("contradictory_connection_target")
				var pair := [intent.from, intent.to]
				var is_drive: bool = action in ["connect_drive", "disconnect_drive"]
				var edges: Array = drives if is_drive else material_links
				if action in ["connect", "connect_drive"]:
					if edges.has(pair) or (is_drive and edges.has([intent.to, intent.from])):
						return _invalid_checkpoint("contradictory_connection")
					edges.append(pair)
				else:
					if is_drive and not edges.has(pair):
						pair.reverse()
					if not edges.has(pair):
						return _invalid_checkpoint("contradictory_connection")
					edges.erase(pair)
			"set_power":
				if not intent.get("active") is bool:
					return _invalid_checkpoint("contradictory_power")
				# This is the wheel at command time, which may since be removed
				# or rebuilt. An empty result is valid before any wheel exists.
				var expected_wheel := ""
				for entity_id in live:
					if live[entity_id].kind == "wheel":
						expected_wheel = entity_id
				if result.entity != expected_wheel:
					return _invalid_checkpoint("contradictory_power_target")
				enabled = intent.active
	if not _same_plain(live, data.entities) or not _same_plain(generated, data.next_ids):
		return _invalid_checkpoint("contradictory_entity_history")
	if not _same_plain(material_links, data.links) or not _same_plain(drives, data.drive_links) or not _same_plain(collected, data.inventories) or enabled != data.power_enabled:
		return _invalid_checkpoint("contradictory_state_history")
	return {"valid": true, "reason": "validated"}
