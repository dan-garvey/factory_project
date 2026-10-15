extends SceneTree
## Bounded test generator and read-only invariants; Model/Store stay sole owners.

const Model = preload("res://model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
const SEEDS := [7, 29, 101, 2027]
const CELLS := {"wheel": [-1, 0], "collector": [0, 0], "belt": [1, 0], "processor": [2, 0]}
const MATERIAL := [["collector", "belt"], ["belt", "processor"]]
const DRIVE := [["wheel", "collector"], ["collector", "belt"], ["belt", "processor"]]
var world
var evidence := ""
var report_path := ""
var current_seed := 0
var rng := 1
var serial := 0
var checks := 0
var before: Dictionary = {}
var failure: Dictionary = {}
var events: Array = []
var history: Array = []
var seen_ids: Array = []
var saves: Array = []
var stats: Dictionary = {}
var report := {"schema": 1, "status": "running", "seeds": SEEDS, "random_steps": 64, "cases": []}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): evidence = arg.trim_prefix("--evidence=")
		elif arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	call_deferred("run")

func expect(condition: bool, label: String) -> bool:
	checks += 1
	if not condition and failure.is_empty():
		failure = {"label": label, "seed": current_seed, "prefix": events.size(), "rng": rng,
			"before": before, "after": world.checkpoint(), "events": events.duplicate(true)}
		persist()
		push_error(label)
	return condition

func put(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot retain owned seeded-probe evidence: " + path)
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return true

func persist() -> bool:
	return put(evidence.path_join("progress.json"), {"seed": current_seed, "rng": rng, "serial": serial,
		"events": events, "before": before, "checkpoint": world.checkpoint(), "failure": failure})

func begin(value: Dictionary) -> bool:
	before = world.checkpoint()
	if not expect(events.size() < 256, "Declared 256-operation seed allowance"):
		return false
	value["index"] = events.size()
	events.append(value)
	return persist()

func complete() -> bool:
	events[-1]["state"] = world.projection()
	return invariants() and persist()

func integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0

func physical(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	for field in ["requests", "order", "revision"]: result.erase(field)
	return result

func entity(kind: String) -> String:
	for name in world.projection().entities:
		if world.projection().entities[name].kind == kind: return name
	return "missing-" + kind

func invariants() -> bool:
	var state: Dictionary = world.projection()
	var stock: Dictionary = state.stock
	var total := 0
	for location in ["source", "collector", "belt", "input", "held", "output"]:
		if not expect(integer(stock.get(location)), "Typed nonnegative material at " + location): return false
		total += stock[location]
		if location != "source" and not expect(stock[location] <= 1, "One-item buffer at " + location): return false
	var carried := 0
	for client in state.inventories:
		if not expect(client in ["P", "Q"] and integer(state.inventories[client]), "Typed per-client carried products"): return false
		carried += state.inventories[client]
	if not expect(total + carried == 16 and integer(stock.player) and stock.player == carried and state.initial_feed == 16 and state.recipe_input == 1,
		"Independent sixteen-item one-to-one ledger"): return false
	if not expect(integer(state.remaining) and state.remaining <= 2 and (stock.held == 1 or state.remaining == 0), "Retained process phase"): return false
	var counts := {"wheel": 0, "collector": 0, "belt": 0, "processor": 0}
	for name in state.entities:
		var item: Dictionary = state.entities[name]
		if not expect(name is String and CELLS.has(item.kind) and item.cell == CELLS[item.kind], "Live fixture identity and actual commanded cell"): return false
		var suffix: String = name.trim_prefix(item.kind + "-")
		if not expect(suffix.is_valid_int() and suffix.to_int() > 0 and name == item.kind + "-" + str(suffix.to_int()), "Canonical positive generation identity"): return false
		counts[item.kind] += 1
	for kind in counts:
		if not expect(integer(state.parts.get(kind)) and state.parts[kind] + counts[kind] == 1, "Independent one-part ledger for " + kind): return false
		var held: int = stock.get(kind, 0) if kind != "processor" else stock.input + stock.held + stock.output
		if not expect(held == 0 or counts[kind] == 1, "Every buffer has its live machine owner"): return false
	if not expect(integer(state.parts.shaft) and state.parts.shaft + state.drive_links.size() == 3, "Independent three-shaft ledger"): return false
	for drive in [false, true]:
		var links: Array = state.drive_links if drive else state.links
		var seen: Array = []
		for pair in links:
			if not expect(pair is Array and pair.size() == 2 and pair[0] != pair[1] and state.entities.has(pair[0]) and state.entities.has(pair[1]), "Links reference live distinct identities"): return false
			var a: Dictionary = state.entities[pair[0]]
			var b: Dictionary = state.entities[pair[1]]
			var key: Array = pair.duplicate()
			if drive: key.sort()
			if not expect(not seen.has(key), "No duplicate live link"): return false
			seen.append(key)
			if drive:
				if not expect(absi(a.cell[0] - b.cell[0]) + absi(a.cell[1] - b.cell[1]) == 1, "Drive joins neighboring fixture machines"): return false
			elif not expect(["collector>belt", "belt>processor"].has(a.kind + ">" + b.kind), "Directed material path"): return false
	# In this explicitly straight four-cell fixture there are only three legal
	# neighbor edges. This is a small independent connectivity invariant.
	var connected: bool = state.power_enabled and state.entities.size() == 4 and state.drive_links.size() == 3
	return expect(state.powered == connected, "Power agrees with this fixture's complete neighbor path")

func submit(intent: Dictionary, kind: String, expected: Variant = null, prior: Dictionary = {}) -> bool:
	if not begin({"op": kind, "intent": intent.duplicate(true)}): return false
	var outcome: Dictionary = world.command(intent)
	events[-1]["outcome"] = outcome.duplicate(true)
	var after: Dictionary = world.checkpoint()
	if not expect(outcome.accepted is bool and outcome.duplicate is bool, "Truthful typed outcome flags"): return false
	if kind == "duplicate":
		var cached: Dictionary = prior.duplicate(true)
		cached.duplicate = true
		stats.duplicates += 1
		if not expect(outcome == cached and after == before, "Replay returns original disposition without applying twice"): return false
	elif kind in ["collision", "foreign"]:
		var reason := "request_reuse" if kind == "collision" else "wrong_context"
		stats[kind] += 1
		if not expect(not outcome.accepted and outcome.reason == reason and after == before, "Identity/context refusal preserves complete authority"): return false
	else:
		if not expect(outcome.context == before.context and outcome.client == intent.client and outcome.request == intent.request,
			"Fresh outcome belongs to actual request"): return false
		if not expect(after.order == before.order + 1 and after.requests.size() == before.requests.size() + 1
			and outcome.order == after.order and outcome.revision == after.revision
			and after.revision == before.revision + (1 if outcome.accepted else 0), "Fresh request metadata advances exactly once"): return false
		if expected is bool and not expect(outcome.accepted == expected, "Directed control expected acceptance/refusal"): return false
		history.append({"intent": intent.duplicate(true), "outcome": outcome.duplicate(true)})
		if not outcome.accepted:
			stats.refused += 1
			if not expect(physical(after) == physical(before), "Fresh refusal changes only request metadata"): return false
		else:
			stats.accepted += 1
			if intent.action == "retrieve":
				if not expect(before.entities.has(intent.entity) and before.entities[intent.entity].kind == "processor"
					and outcome.entity == intent.entity and after.stock.output == before.stock.output - intent.amount
					and after.inventories.get(intent.client, 0) == before.inventories.get(intent.client, 0) + intent.amount,
					"Accepted retrieval transfers exactly the requested actual plate"): return false
				for location in ["source", "collector", "belt", "input", "held"]:
					if not expect(after.stock[location] == before.stock[location], "Retrieval cannot move raw or held material"): return false
			else:
				if not expect(after.stock == before.stock and after.inventories == before.inventories,
					"Construction/power/link command cannot move material"): return false
			if not expect(after.remaining == before.remaining, "Commands cannot reset or advance retained work"): return false
			if intent.action == "place":
				if not expect(not seen_ids.has(outcome.entity) and not before.entities.has(outcome.entity)
					and after.entities.has(outcome.entity) and after.entities[outcome.entity].kind == intent.kind
					and after.entities[outcome.entity].cell == intent.cell and after.parts[intent.kind] == before.parts[intent.kind] - 1,
					"New placement spends one carried part and has a new actual identity"): return false
				seen_ids.append(outcome.entity)
			elif intent.action == "remove":
				if not expect(before.entities.has(intent.entity) and not after.entities.has(intent.entity)
					and after.parts[before.entities[intent.entity].kind] == before.parts[before.entities[intent.entity].kind] + 1,
					"Removal refunds its actual part without touching stock"): return false
			elif intent.action in ["connect", "disconnect", "connect_drive", "disconnect_drive"]:
				var drive: bool = intent.action.ends_with("_drive")
				var edges: Array = after.drive_links if drive else after.links
				var old_edges: Array = before.drive_links if drive else before.links
				var added: bool = intent.action.begins_with("connect")
				var present: bool = edges.has([intent.from, intent.to]) or (drive and edges.has([intent.to, intent.from]))
				if not expect(present == added and edges.size() == old_edges.size() + (1 if added else -1), "Accepted link outcome matches its actual directed/undirected edge"): return false
			elif intent.action == "set_power":
				if not expect(after.power_enabled == intent.active, "Accepted power flag is actually applied"): return false
	return complete()

func send(action: Dictionary, expected: Variant = null, client: String = "P") -> bool:
	serial += 1
	if not expect(serial <= 128, "Declared fresh-request history allowance"): return false
	var intent := action.duplicate(true)
	intent.merge({"context": "opening-seed-" + str(current_seed), "client": client, "request": "seed-" + str(serial)})
	return submit(intent, "command", expected)

func replay(index: int, collision: bool = false) -> bool:
	var previous: Dictionary = history[index]
	var intent: Dictionary = previous.intent.duplicate(true)
	if collision: intent["probe_collision"] = true
	return submit(intent, "collision" if collision else "duplicate", null, previous.outcome)

func clock(ticks: int) -> bool:
	if not begin({"op": "advance", "ticks": ticks}): return false
	var was_powered: bool = world.projection().powered
	world.advance(ticks)
	stats.ticks += ticks
	var after: Dictionary = world.checkpoint()
	if not expect(after.revision == before.revision + ticks and after.order == before.order and after.requests == before.requests,
		"Explicit clock changes no request history"): return false
	if not was_powered and not expect(after.stock == before.stock and after.remaining == before.remaining, "Stopped clock retains all material and phase"): return false
	return complete()

func roundtrip(label: String) -> bool:
	var path := evidence.path_join("seed-%d-slot-%d.factory" % [current_seed, saves.size()])
	if not begin({"op": "store", "label": label, "path": path}): return false
	if not expect(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".pending"), "Use a fresh owned slot"): return false
	var written: Dictionary = Store.write(world, path)
	events[-1]["write"] = written
	if not expect(written.accepted, "Real Store accepts current live checkpoint"): return false
	var digest := FileAccess.get_sha256(path)
	saves.append({"path": path, "sha256": digest, "bytes": FileAccess.get_file_as_bytes(path).size(), "label": label,
		"stock": before.stock, "remaining": before.remaining, "power_enabled": before.power_enabled})
	var restored = Model.new(0, "unrelated-before-read", 1)
	var loaded: Dictionary = Store.read_into(restored, path)
	events[-1]["read"] = loaded
	if not expect(loaded.accepted and restored.checkpoint() == before, "Same-implementation actual file roundtrip preserves full checkpoint"): return false
	# Only this short-lived comparison uses two copies of the same implementation.
	# It is deterministic continuation evidence, not an independent rules oracle.
	world.advance()
	restored.advance()
	if not expect(restored.checkpoint() == world.checkpoint(), "Same-implementation one-step continuation after Store"): return false
	world = restored
	stats.roundtrips += 1
	stats.ticks += 1
	events[-1]["continuation_ticks"] = 1
	events[-1]["roundtrip_equal"] = true
	events[-1]["continuation_equal"] = true
	return expect(FileAccess.get_sha256(path) == digest and not FileAccess.file_exists(path + ".pending"), "Read/continuation preserve original good file") and complete()

func choose(limit: int) -> int:
	rng = (rng * 48271) % 2147483647
	return rng % limit

func prefix() -> bool:
	for kind in ["wheel", "collector", "belt", "processor"]:
		if not send({"action": "place", "kind": kind, "cell": CELLS[kind]}, true): return false
	if not send({"action": "place", "kind": "collector", "cell": [3, 1]}, false): return false
	for pair in MATERIAL:
		if not send({"action": "connect", "from": entity(pair[0]), "to": entity(pair[1])}, true): return false
	for pair in DRIVE:
		if not send({"action": "connect_drive", "from": entity(pair[0]), "to": entity(pair[1])}, true): return false
	if not send({"action": "remove", "entity": entity("processor")}, false) or not clock(4): return false
	if not expect(world.projection().stock.held == 1 and world.projection().remaining == 2, "Actual partial-work prefix"): return false
	if not send({"action": "set_power", "active": false}, true): return false
	if not send({"action": "remove", "entity": entity("processor")}, false): return false
	if not send({"action": "remove", "entity": entity("wheel")}, true): return false
	if not send({"action": "place", "kind": "wheel", "cell": CELLS.wheel}, true): return false
	if not replay(0) or not replay(0, true): return false
	if not send({"action": "connect_drive", "from": "wheel-1", "to": entity("collector")}, false): return false
	if not send({"action": "connect_drive", "from": entity("wheel"), "to": entity("collector")}, true): return false
	if not roundtrip("paused-partial"): return false
	if not send({"action": "set_power", "active": true}, true) or not clock(8): return false
	var state: Dictionary = world.projection()
	if not expect(state.stock.held == 1 and state.stock.output == 1 and state.remaining == 0, "Actual blocked-work prefix"): return false
	if not roundtrip("blocked"): return false
	if not send({"action": "retrieve", "entity": entity("processor"), "amount": 1}, true): return false
	if not replay(history.size() - 1) or not replay(history.size() - 1, true): return false
	serial += 1
	if not expect(serial <= 128, "Declared fresh-request history allowance"): return false
	return submit({"action": "set_power", "active": false, "context": "foreign-context", "client": "P", "request": "foreign-" + str(serial)}, "foreign")

func generated() -> bool:
	match choose(14):
		0: return clock(choose(4))
		1: return send({"action": "set_power", "active": choose(2) == 0})
		2: return send({"action": "retrieve", "entity": entity("processor") if choose(3) != 0 else "processor-retired", "amount": 1 + choose(2)}, null, "P" if choose(2) == 0 else "Q")
		3:
			var kinds := ["wheel", "collector", "belt", "processor"]
			var kind: String = kinds[choose(4)]
			return send({"action": "place", "kind": kind, "cell": CELLS[kind] if choose(3) != 0 else [9, 0]})
		4:
			var ids: Array = world.projection().entities.keys()
			return send({"action": "remove", "entity": ids[choose(ids.size())] if not ids.is_empty() and choose(3) != 0 else "wheel-1"})
		5, 6, 7, 8:
			# Select both link types, addition/removal and reversed shaft endpoints.
			var drive: bool = choose(2) == 0
			var pairs: Array = DRIVE if drive else MATERIAL
			var pair: Array = pairs[choose(pairs.size())]
			var a := entity(pair[0])
			var b := entity(pair[1])
			if choose(2) == 0:
				var old := a
				a = b
				b = old
			var action := "connect" if choose(2) == 0 else "disconnect"
			return send({"action": action + ("_drive" if drive else ""), "from": a, "to": b})
		9: return replay(choose(history.size()))
		10: return replay(choose(history.size()), true)
		11:
			serial += 1
			if not expect(serial <= 128, "Declared fresh-request history allowance"): return false
			return submit({"action": "set_power", "active": false, "context": "foreign-context", "client": "P", "request": "foreign-" + str(serial)}, "foreign")
		12: return send({"action": "set_power", "active": "invalid-boolean"})
		_: return send({"action": "unsupported-probe-action"})

func drain() -> bool:
	if not send({"action": "set_power", "active": false}, true): return false
	for kind in CELLS:
		if entity(kind).begins_with("missing-") and not send({"action": "place", "kind": kind, "cell": CELLS[kind]}, true): return false
	for pair in MATERIAL:
		var edge := [entity(pair[0]), entity(pair[1])]
		if not world.projection().links.has(edge) and not send({"action": "connect", "from": edge[0], "to": edge[1]}, true): return false
	for pair in DRIVE:
		var edge := [entity(pair[0]), entity(pair[1])]
		var edges: Array = world.projection().drive_links
		if not edges.has(edge) and not edges.has([edge[1], edge[0]]) and not send({"action": "connect_drive", "from": edge[0], "to": edge[1]}, true): return false
	if not send({"action": "set_power", "active": true}, true): return false
	for _tick in range(96):
		if world.projection().stock.output == 1:
			if not send({"action": "retrieve", "entity": entity("processor"), "amount": 1}, true, "Q"): return false
		if world.projection().stock.player == 16: break
		if not clock(1): return false
	return expect(world.projection().stock.player == 16, "Actual repaired line drains exactly sixteen products") and roundtrip("final")

func run() -> void:
	if not evidence.is_absolute_path() or not report_path.is_absolute_path() or not DirAccess.dir_exists_absolute(evidence):
		push_error("Seeded probe requires fresh external owned evidence/report paths")
		quit(1)
		return
	for seed_value in SEEDS:
		current_seed = seed_value
		rng = seed_value
		serial = 0
		events = []
		history = []
		seen_ids = []
		saves = []
		stats = {"accepted": 0, "refused": 0, "duplicates": 0, "collision": 0, "foreign": 0, "roundtrips": 0, "ticks": 0}
		world = Model.new(16, "opening-seed-" + str(current_seed), 1, {"opening": true})
		before = world.checkpoint()
		var okay: bool = invariants() and prefix()
		for index in range(64):
			if not okay: break
			var event_index: int = events.size()
			okay = generated()
			if okay: events[event_index]["random_index"] = index
			if okay and (index + 1) % 16 == 0: okay = roundtrip("generated-%d" % index)
		if okay: okay = drain()
		for save in saves:
			if okay: okay = expect(FileAccess.get_sha256(save.path) == save.sha256 and save.bytes <= Store.MAX_BYTES, "Every original good seeded save stays unchanged")
		if not okay:
			report.status = "fail"
			report["failure"] = failure
			break
		report.cases.append({"seed": current_seed, "random_steps": 64, "events": events.duplicate(true), "stats": stats.duplicate(true),
			"saves": saves.duplicate(true), "final": world.projection(), "final_checkpoint": world.checkpoint(), "rng_final": rng})
	report["checks"] = checks
	if report.status != "fail": report.status = "pass"
	var retained: bool = put(report_path, report)
	print("OPENING_SEQUENCES_PASS" if report.status == "pass" and retained else "OPENING_SEQUENCES_FAIL")
	quit(0 if report.status == "pass" and retained else 1)
