extends SceneTree

const Model = preload("res://model.gd")
const Scenario = preload("res://scenario.gd")
var failures: Array = []
var checks := 0
var serial := 0
var model = Model.new()

func send(intent: Dictionary) -> Dictionary:
	serial += 1
	intent.merge({"context": model.context, "client": "P", "request": "h-" + str(serial)})
	return model.command(intent)

func verify(condition: bool, label: String):
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _initialize():
	call_deferred("run")

func run():
	verify(not send({"action": "connect", "from": "collector-1", "to": "belt-1"}).accepted,
		"missing entity refused")
	var invalid := {"context": "other", "client": "P", "request": "x", "action": "retrieve"}
	verify(not model.command(invalid).accepted, "wrong world refused")
	Scenario.build(send)
	var state: Dictionary = model.projection()
	verify(state.entities.size() == 3 and state.links.size() == 2, "command-built topology")
	verify(not send({"action": "place", "kind": "collector", "cell": [0, 0]}).accepted,
		"occupied cell refused")
	verify(not send({"action": "place", "kind": "belt", "cell": [3, 0]}).accepted,
		"no construction stock duplication")
	model.advance(3)
	verify(model.projection().stock.input == 1 and model.projection().stock.held == 0,
		"one feed cannot satisfy two-feed fixture recipe")
	model.advance(4)
	state = model.projection()
	verify(state.stock.output == 1 and state.stock.held == 2, "first batch and next held work")
	verify(Scenario.conserved(state), "first output material accounting")
	var first: Dictionary = state.duplicate(true)
	model.advance(5)
	state = model.projection()
	verify(state.stock.output == 1 and state.stock.held == 2 and state.remaining == 0,
		"blocked output retains completed held work")
	verify(Scenario.conserved(state), "blocked material accounting")
	var blocked: Dictionary = state.duplicate(true)
	var take := {"context": model.context, "client": "Q", "request": "take-once",
		"action": "retrieve", "amount": 1}
	verify(model.command(take).accepted, "retrieve existing product")
	verify(model.command(take).duplicate, "exact duplicate request recognized")
	verify(model.projection().stock.player == 1, "duplicate retrieve does not repeat")
	take.amount = 2
	verify(not model.command(take).accepted, "changed-payload request reuse refused")
	verify(not send({"action": "retrieve", "amount": 1}).accepted, "empty output refusal")
	Scenario.finish(model, send)
	state = model.projection()
	verify(state.stock.player == 4 and state.stock.output == 0 and state.stock.held == 0,
		"eight fixture feed produces four retrieved products")
	verify(Scenario.conserved(state), "completed material accounting")
	var disconnected = Model.new()
	disconnected.advance(20)
	verify(disconnected.projection().stock.source == 8, "no collector creates no extraction")
	var pressured = Model.new(20)
	var pserial := [0]
	var psend := func(intent):
		pserial[0] += 1
		intent.merge({"context": pressured.context, "client": "P", "request": str(pserial[0])})
		return pressured.command(intent)
	Scenario.build(psend)
	pressured.advance(12)
	var stopped: Dictionary = pressured.projection().stock
	pressured.advance(4)
	verify(pressured.projection().stock == stopped and stopped.source > 0,
		"full physical path stops finite extraction")
	verify(Scenario.conserved(pressured.projection()), "backpressure retains all locations")
	var alternate = Model.new(4, "alternate-fixture", 1)
	var aserial := [0]
	var asend := func(intent):
		aserial[0] += 1
		intent.merge({"context": alternate.context, "client": "P", "request": str(aserial[0])})
		return alternate.command(intent)
	Scenario.build(asend)
	Scenario.finish(alternate, asend)
	verify(alternate.projection().stock.player == 4, "same rule path supports declared one-feed fixture")
	verify(Scenario.conserved(alternate.projection()), "alternate fixture accounting")
	# Compare stable material/topology views, not differing test request identities.
	var report := {"status": "pass" if failures.is_empty() else "fail", "checks": checks,
		"failures": failures, "first": first.stock, "blocked": blocked.stock, "final": state.stock}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file := FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(report))
	print("FACTORY_HEADLESS_PASS" if failures.is_empty() else "FACTORY_HEADLESS_FAIL")
	quit(0 if failures.is_empty() else 1)
