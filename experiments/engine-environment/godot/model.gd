extends RefCounted
## Experimental engine-coupled rule owner. No scene nodes or rendering callbacks.
## Neutral recipe/capacities are fixture values, not accepted chapter content.

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

func _init(feed: int = 8, world_context: String = "engine-fixture-1", required: int = 2, settings: Dictionary = {}):
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

func command(intent: Dictionary) -> Dictionary:
	if intent.get("context") != context:
		return _outcome(false, "wrong_context")
	if not intent.get("client") is String or not intent.get("request") is String:
		return _outcome(false, "missing_request_identity")
	if intent.client.is_empty() or intent.request.is_empty():
		return _outcome(false, "missing_request_identity")
	var key: String = JSON.stringify([intent.client, intent.request])
	if requests.has(key):
		if requests[key].intent != intent:
			return _outcome(false, "request_reuse")
		var repeated: Dictionary = requests[key].result.duplicate(true)
		repeated["duplicate"] = true
		return repeated
	order += 1
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
	if not entities.has(source) or not entities.has(target):
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
	links.append(pair)
	return _outcome(true, "connected")

func _retrieve(intent: Dictionary) -> Dictionary:
	if intent.has("entity") and intent.entity != _kind_id("processor"):
		return _outcome(false, "missing_entity")
	var amount = intent.get("amount", 1)
	if not amount is int or amount < 1 or amount > stock.output:
		return _outcome(false, "unavailable_output")
	stock.output -= amount
	inventories[intent.client] = inventories.get(intent.client, 0) + amount
	return _outcome(true, "retrieved", _kind_id("processor"))

func _opening() -> bool:
	return options.get("opening", false) == true

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
	if not entities.has(source) or not entities.has(target) or source == target:
		return _outcome(false, "missing_entity")
	var a: Array = entities[source].cell
	var b: Array = entities[target].cell
	if absi(a[0] - b[0]) + absi(a[1] - b[1]) != 1:
		return _outcome(false, "ports_not_adjacent")
	if drive_links.has([source, target]) or drive_links.has([target, source]):
		return _outcome(false, "already_connected")
	if parts.shaft < 1:
		return _outcome(false, "no_shaft")
	drive_links.append([source, target])
	parts.shaft -= 1
	return _outcome(true, "connected", target)

func _set_power(intent: Dictionary) -> Dictionary:
	if not _opening() or not intent.get("active") is bool:
		return _outcome(false, "unsupported_action")
	power_enabled = intent.active
	return _outcome(true, "power_changed", _kind_id("wheel"))

func _disconnect(intent: Dictionary, drive: bool) -> Dictionary:
	if not _opening():
		return _outcome(false, "unsupported_action")
	if _powered():
		return _outcome(false, "powered")
	var pair := [intent.get("from", ""), intent.get("to", "")]
	var connections: Array = drive_links if drive else links
	if drive and not connections.has(pair):
		pair.reverse()
	if not connections.has(pair):
		return _outcome(false, "missing_connection")
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
	if not entities.has(entity_id):
		return _outcome(false, "missing_entity")
	var kind: String = entities[entity_id].kind
	var occupied: int = stock.get(kind, 0)
	if kind == "processor":
		occupied = stock.input + stock.held + stock.output
	if occupied > 0:
		return _outcome(false, "held_stock")
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
	return {"context": context, "revision": revision, "order": order,
		"initial_feed": initial_feed, "recipe_input": recipe_input,
		"entities": entities.duplicate(true), "links": links.duplicate(true),
		"stock": counts, "inventories": inventories.duplicate(true),
		"remaining": remaining, "powered": _powered(), "power_enabled": power_enabled,
		"drive_links": drive_links.duplicate(true), "options": options.duplicate(true),
		"parts": parts.duplicate(true)}

func checkpoint() -> Dictionary:
	return {"schema": 1, "context": context, "initial_feed": initial_feed,
		"recipe_input": recipe_input, "revision": revision, "order": order,
		"entities": entities.duplicate(true), "links": links.duplicate(true),
		"parts": parts.duplicate(true), "stock": stock.duplicate(true),
		"inventories": inventories.duplicate(true), "remaining": remaining,
		"requests": requests.duplicate(true), "options": options.duplicate(true),
		"drive_links": drive_links.duplicate(true), "power_enabled": power_enabled,
		"next_ids": next_ids.duplicate(true)}

func restore_checkpoint(snapshot: Variant) -> Dictionary:
	var reason := _validate_checkpoint(snapshot)
	if not reason.is_empty():
		return {"accepted": false, "reason": reason}
	# Validation has no side effects. Publish only a complete owned candidate.
	for field in snapshot:
		if field == "schema":
			continue
		var value = snapshot[field]
		set(field, value.duplicate(true) if value is Dictionary or value is Array else value)
	return {"accepted": true, "reason": "restored"}

func _count(value: Variant) -> bool:
	return value is int and value >= 0

func _validate_checkpoint(data: Variant) -> String:
	var fields := ["schema", "context", "initial_feed", "recipe_input", "revision", "order", "entities",
		"links", "parts", "stock", "inventories", "remaining", "requests", "options", "drive_links", "power_enabled", "next_ids"]
	if not data is Dictionary or data.size() != fields.size():
		return "invalid_fields"
	for field in fields:
		if not data.has(field):
			return "missing_field"
	if not data.schema is int or data.schema != 1:
		return "unsupported_schema"
	if not data.context is String or data.context.is_empty():
		return "invalid_context"
	for field in ["initial_feed", "recipe_input", "revision", "order", "remaining"]:
		if not _count(data[field]):
			return "invalid_counter"
	if data.recipe_input < 1 or data.remaining > 2:
		return "invalid_phase"
	for field in ["entities", "parts", "stock", "inventories", "requests", "options", "next_ids"]:
		if not data[field] is Dictionary:
			return "invalid_dictionary"
	if not data.links is Array or not data.drive_links is Array or not data.power_enabled is bool:
		return "invalid_topology"
	if data.options.size() > 1 or (data.options.size() == 1 and (not data.options.has("opening") or not data.options.opening is bool)):
		return "invalid_options"
	var opening: bool = data.options.get("opening", false)
	var kinds: Array = ["collector", "belt", "processor", "wheel"] if opening else ["collector", "belt", "processor"]
	if data.next_ids.size() != kinds.size() or data.parts.size() != kinds.size() + (1 if opening else 0):
		return "invalid_parts"
	var counts: Dictionary = {}
	for kind in kinds:
		if not data.next_ids.has(kind) or not _count(data.next_ids[kind]) or data.next_ids[kind] < 1 or not data.parts.has(kind) or not _count(data.parts[kind]):
			return "invalid_parts"
		counts[kind] = 0
	var cells: Array = []
	for entity_id in data.entities:
		var entity = data.entities[entity_id]
		if not entity_id is String or not entity is Dictionary or entity.size() != 2 or not entity.has("kind") or not kinds.has(entity.kind) or not entity.has("cell"):
			return "invalid_entity"
		var cell = entity.cell
		if not cell is Array or cell.size() != 2 or cells.has(cell):
			return "invalid_cell"
		for value in cell:
			if not value is int or value < -2 or value > 4:
				return "invalid_cell"
		if entity.kind == "wheel" and cell[0] != -1:
			return "invalid_wheel_site"
		if opening and entity.kind == "collector" and cell[0] != 0:
			return "invalid_collector_site"
		cells.append(cell)
		counts[entity.kind] += 1
		var suffix: String = entity_id.trim_prefix(entity.kind + "-")
		if not suffix.is_valid_int() or suffix.to_int() < 1 or entity_id != entity.kind + "-" + str(suffix.to_int()) or suffix.to_int() >= data.next_ids[entity.kind]:
			return "invalid_identity"
	for kind in kinds:
		if counts[kind] > 1 or data.parts[kind] != 1 - counts[kind]:
			return "invalid_parts"
	for drive in [false, true]:
		var group: Array = data.drive_links if drive else data.links
		var seen: Array = []
		for pair in group:
			if not pair is Array or pair.size() != 2 or not pair[0] is String or not pair[1] is String or pair[0] == pair[1] or not data.entities.has(pair[0]) or not data.entities.has(pair[1]):
				return "dangling_connection"
			var a: Dictionary = data.entities[pair[0]]
			var b: Dictionary = data.entities[pair[1]]
			var identity: Array = pair.duplicate()
			if drive:
				identity.sort()
				if not opening or absi(a.cell[0] - b.cell[0]) + absi(a.cell[1] - b.cell[1]) != 1:
					return "invalid_drive"
			elif not ["collector>belt", "belt>processor"].has(a.kind + ">" + b.kind) or b.cell != [a.cell[0] + 1, a.cell[1]]:
				return "invalid_ports"
			if seen.has(identity):
				return "duplicate_connection"
			seen.append(identity)
	if opening and (not data.parts.has("shaft") or not _count(data.parts.shaft) or data.parts.shaft != 3 - data.drive_links.size()):
		return "invalid_shaft_stock"
	var locations := ["source", "collector", "belt", "input", "held", "output"]
	if data.stock.size() != locations.size():
		return "invalid_stock"
	var raw := 0
	for location in locations:
		if not data.stock.has(location) or not _count(data.stock[location]):
			return "invalid_stock"
		if location != "output":
			if data.stock[location] > data.initial_feed - raw:
				return "quantity_mismatch"
			raw += data.stock[location]
	if data.stock.collector > (1 if opening else 2) or data.stock.belt > 1 or data.stock.input > data.recipe_input or data.stock.output > 1:
		return "invalid_capacity"
	if not data.stock.held in [0, data.recipe_input] or (data.stock.held == 0 and data.remaining != 0):
		return "invalid_phase"
	for kind in ["collector", "belt", "processor"]:
		var held: int = data.stock.get(kind, 0) if kind != "processor" else data.stock.input + data.stock.held + data.stock.output
		if held > 0 and counts[kind] == 0:
			return "missing_stock_owner"
	var material_remaining: int = data.initial_feed - raw
	var products: Array = [data.stock.output]
	for actor in data.inventories:
		if not actor is String or actor.is_empty() or not _count(data.inventories[actor]):
			return "invalid_inventory"
		products.append(data.inventories[actor])
	for quantity in products:
		if quantity > material_remaining / data.recipe_input:
			return "quantity_mismatch"
		material_remaining -= quantity * data.recipe_input
	if material_remaining != 0:
		return "quantity_mismatch"
	if data.requests.size() != data.order:
		return "invalid_request_order"
	var orders: Array = []
	for key in data.requests:
		var record = data.requests[key]
		if not key is String or not record is Dictionary or not record.has("intent") or not record.has("result") or not record.intent is Dictionary or not record.result is Dictionary:
			return "invalid_request"
		var intent: Dictionary = record.intent
		var result: Dictionary = record.result
		if not intent.get("client") is String or intent.client.is_empty() or not intent.get("request") is String or intent.request.is_empty() or intent.get("context") != data.context or key != JSON.stringify([intent.client, intent.request]):
			return "invalid_request_identity"
		for field in ["accepted", "reason", "entity", "context", "revision", "order", "duplicate", "client", "request"]:
			if not result.has(field):
				return "invalid_request_result"
		if not result.accepted is bool or not result.reason is String or not result.entity is String or result.context != data.context or result.client != intent.client or result.request != intent.request or result.duplicate != false:
			return "invalid_request_result"
		if not _count(result.revision) or result.revision > data.revision or not _count(result.order) or result.order < 1 or result.order > data.order or orders.has(result.order):
			return "invalid_request_order"
		orders.append(result.order)
		if result.accepted and intent.get("action") == "place":
			var kind = intent.get("kind", "")
			if not kinds.has(kind):
				return "invalid_request_entity"
			var suffix: String = result.entity.trim_prefix(kind + "-")
			if not suffix.is_valid_int() or suffix.to_int() < 1 or suffix.to_int() >= data.next_ids[kind] or result.entity != kind + "-" + str(suffix.to_int()):
				return "invalid_identity_history"
	return ""
