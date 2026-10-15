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

func _init(feed: int = 8, world_context: String = "engine-fixture-1", required: int = 2):
	assert(feed >= 0 and required > 0)
	initial_feed = feed
	context = world_context
	recipe_input = required
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
	var kind = intent.get("kind", "")
	var cell = intent.get("cell", [])
	if not kind is String or not parts.has(kind):
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
	var entity_id: String = kind + "-1"
	entities[entity_id] = {"kind": kind, "cell": cell.duplicate()}
	parts[kind] -= 1
	return _outcome(true, "placed", entity_id)

func _connect(intent: Dictionary) -> Dictionary:
	var source = intent.get("from", "")
	var target = intent.get("to", "")
	if not entities.has(source) or not entities.has(target):
		return _outcome(false, "missing_entity")
	if not ["collector-1>belt-1", "belt-1>processor-1"].has(source + ">" + target):
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
	var amount = intent.get("amount", 1)
	if not amount is int or amount < 1 or amount > stock.output:
		return _outcome(false, "unavailable_output")
	stock.output -= amount
	inventories[intent.client] = inventories.get(intent.client, 0) + amount
	return _outcome(true, "retrieved", "processor-1")

func advance(ticks: int = 1) -> Dictionary:
	assert(ticks >= 0)
	for _tick in range(ticks):
		# Fixed explicit authority order; view frame timing cannot create products.
		if stock.held > 0:
			remaining = maxi(0, remaining - 1)
			if remaining == 0 and stock.output < 1:
				stock.held = 0
				stock.output += 1
		if entities.has("processor-1") and stock.held == 0 and stock.input >= recipe_input:
			stock.input -= recipe_input
			stock.held = recipe_input
			remaining = 2
		if links.has(["belt-1", "processor-1"]) and stock.belt > 0 and stock.input < recipe_input:
			stock.belt -= 1
			stock.input += 1
		if links.has(["collector-1", "belt-1"]) and stock.collector > 0 and stock.belt < 1:
			stock.collector -= 1
			stock.belt += 1
		if entities.has("collector-1") and stock.source > 0 and stock.collector < 2:
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
		"remaining": remaining, "powered": true, "parts": parts.duplicate(true)}
