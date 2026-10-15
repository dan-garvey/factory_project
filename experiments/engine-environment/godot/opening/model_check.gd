extends SceneTree
## Requirement-focused opening/regression checks against the single model owner.

const Model = preload("res://model.gd")
var model
var serial := 0
var checks := 0
var failures: Array[String] = []

func verify(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func send(action: Dictionary) -> Dictionary:
	serial += 1
	var intent: Dictionary = action.duplicate(true)
	intent.merge({"context": model.context, "client": "P", "request": "domain-%d" % serial}, true)
	return model.command(intent)

func conserved(candidate) -> bool:
	var state: Dictionary = candidate.projection()
	var s: Dictionary = state.stock
	return s.source + s.collector + s.belt + s.input + s.held + state.recipe_input * (s.output + s.player) == state.initial_feed

func _initialize() -> void:
	model = Model.new(16, "opening-domain-1", 1, {"opening": true})
	verify(not send({"action": "place", "kind": "collector", "cell": [3, 0]}).accepted, "Collector placement must use the stationary finite seam.")
	verify(not send({"action": "place", "kind": "wheel", "cell": [3, 1]}).accepted, "Waterwheel placement must use the stream bank.")
	verify(model.projection().parts.collector == 1 and model.projection().parts.wheel == 1, "Refused resource/power placement retains carried parts.")
	for row in [["collector", 0], ["belt", 1], ["processor", 2]]:
		verify(send({"action": "place", "kind": row[0], "cell": [row[1], 0]}).accepted, "Finite carried part places %s." % row[0])
	for pair in [["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
		verify(send({"action": "connect", "from": pair[0], "to": pair[1]}).accepted, "Real material path connects.")
	model.advance(12)
	verify(model.projection().stock.source == 16, "Unpowered machinery cannot extract finite stock.")
	verify(send({"action": "place", "kind": "wheel", "cell": [-1, 0]}).accepted, "Starter wheel is a physical carried part.")
	for pair in [["wheel-1", "collector-1"], ["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
		verify(send({"action": "connect_drive", "from": pair[0], "to": pair[1]}).accepted, "Finite drive shaft connects.")
	verify(model.projection().powered and model.projection().parts.shaft == 0, "Wheel reachability and shaft stock determine operation.")
	model.advance(24)
	var full: Dictionary = model.projection()
	verify(full.stock.output == 1 and full.stock.held == 1 and full.remaining == 0, "Occupied output retains the next finished work.")
	verify(full.stock.collector <= 1 and full.stock.input <= 1, "Opening machine buffers have one-item capacities.")
	model.advance(8)
	verify(model.projection().stock == full.stock and conserved(model), "Full physical path stops upstream extraction without loss.")
	verify(not send({"action": "remove", "entity": "processor-1"}).accepted, "Running machinery cannot be dismantled.")
	verify(send({"action": "set_power", "active": false}).accepted, "Drive can be stopped through authority.")
	var stopped: Dictionary = model.projection()
	model.advance(7)
	verify(model.projection().stock == stopped.stock and model.projection().remaining == stopped.remaining, "Stopped power preserves phase and stock.")
	verify(not send({"action": "remove", "entity": "processor-1"}).accepted, "Stopped occupied machinery cannot erase held stock.")
	var old_remove := {"context": model.context, "client": "P", "request": "remove-wheel-once", "action": "remove", "entity": "wheel-1"}
	verify(model.command(old_remove).accepted and model.projection().parts.wheel == 1, "Empty stopped wheel returns its actual part.")
	verify(model.projection().parts.shaft == 1, "Removed endpoint returns its shaft exactly once.")
	var rebuilt: Dictionary = send({"action": "place", "kind": "wheel", "cell": [-1, 0]})
	verify(rebuilt.accepted and rebuilt.entity != "wheel-1", "Replacement at the same cell has a fresh identity.")
	var before_duplicate: Dictionary = model.projection()
	verify(model.command(old_remove).duplicate and model.projection() == before_duplicate, "Old acknowledged-or-not removal cannot remove the replacement.")
	verify(not send({"action": "connect_drive", "from": "wheel-1", "to": "collector-1"}).accepted, "A fresh request with stale entity identity is refused.")
	verify(send({"action": "connect_drive", "from": rebuilt.entity, "to": "collector-1"}).accepted, "Returned shaft powers the replacement through its new identity.")
	verify(send({"action": "set_power", "active": true}).accepted, "Stopped work can resume.")
	var take := {"context": model.context, "client": "Q", "request": "take-before-ack", "action": "retrieve", "amount": 1}
	verify(model.command(take).accepted, "Output moves to the requesting participant.")
	var checkpoint: Dictionary = model.checkpoint()
	var restored = Model.new()
	verify(restored.restore_checkpoint(checkpoint).accepted, "Complete opening checkpoint restores through the model.")
	verify(restored.projection() == model.projection() and restored.checkpoint() == checkpoint, "Restore preserves logical state and dispositions, not scene objects.")
	var after_take: Dictionary = restored.projection()
	verify(restored.command(take).duplicate and restored.projection() == after_take, "Applied-before-ack request cannot repeat after restore.")
	for _tick in range(10):
		model.advance()
		restored.advance()
		verify(model.projection() == restored.projection(), "Restored continuation matches uninterrupted actual transitions.")
	verify(conserved(model) and conserved(restored), "Both continuation branches conserve each material transformation.")
	var malformed: Array = []
	var bad: Dictionary = checkpoint.duplicate(true)
	bad.erase("stock")
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.stock.source = -1
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.stock.source += 1
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.remaining = 99
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.entities.erase("processor-1")
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.next_ids.wheel = 1
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.schema = 99
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.parts.shaft = 99
	malformed.append(bad)
	for invalid in malformed:
		var prior_projection: Dictionary = restored.projection()
		var prior_checkpoint: Dictionary = restored.checkpoint()
		verify(not restored.restore_checkpoint(invalid).accepted, "Invalid ownership/reference/version/quantity state is refused.")
		verify(restored.projection() == prior_projection and restored.checkpoint() == prior_checkpoint, "Rejected restore leaves the good world and request state intact.")
	var external: Dictionary = restored.checkpoint()
	var original: Dictionary = restored.checkpoint()
	external.stock.source = 999
	verify(restored.checkpoint() == original, "Checkpoint callers cannot mutate the live authority through aliases.")
	print("OPENING_MODEL_PASS: %d checks" % checks if failures.is_empty() else "OPENING_MODEL_FAIL: " + JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
