extends SceneTree
## Real checkpoint files across separate producer/consumer engine processes.

const Model = preload("res://model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
var mode := ""
var artifacts := ""
var checks := 0
var failures: Array = []
var serial := 0
var outcomes: Array = []
var references: Dictionary = {}
var case_evidence: Dictionary = {}
var rejected_files: Dictionary = {}

func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--artifacts="): artifacts = arg.trim_prefix("--artifacts=")
	call_deferred("run")

func verify(condition: bool, label: String):
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func send(model, intent: Dictionary) -> Dictionary:
	serial += 1
	var actual := intent.duplicate(true)
	actual.merge({"context": model.context, "client": "Q", "request": "save-step-" + str(serial)}, true)
	var result: Dictionary = model.command(actual)
	outcomes.append({"intent": actual, "result": result})
	return result

func build():
	var model = Model.new(16, "save-fixture-1", 1, {"opening": true})
	for row in [["wheel", -1], ["collector", 0], ["belt", 1], ["processor", 2]]:
		verify(send(model, {"action": "place", "kind": row[0], "cell": [row[1], 0]}).accepted,
			"actual command places " + row[0])
	for pair in [["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
		verify(send(model, {"action": "connect", "from": pair[0], "to": pair[1]}).accepted, "actual transport connection")
	for pair in [["wheel-1", "collector-1"], ["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
		verify(send(model, {"action": "connect_drive", "from": pair[0], "to": pair[1]}).accepted, "actual mechanical power connection")
	return model

func run():
	if mode == "produce":
		for name_value in ["paused", "blocked", "identity-replay"]:
			produce(name_value)
		put(artifacts.path_join("references.bin"), var_to_bytes(references))
	elif mode == "consume":
		references = bytes_to_var(FileAccess.get_file_as_bytes(artifacts.path_join("references.bin")))
		for name_value in ["paused", "blocked", "identity-replay"]:
			consume(name_value)
		negative_inputs()
	else:
		verify(false, "known producer/consumer mode")
	var report := {"status": "pass" if failures.is_empty() else "fail", "mode": mode,
		"checks": checks, "failures": failures, "cases": case_evidence, "rejections": rejected_files}
	var file := FileAccess.open(artifacts.path_join(mode + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	print("SAVE_CONTINUATION_PASS " + mode if failures.is_empty() else "SAVE_CONTINUATION_FAIL " + mode)
	quit(0 if failures.is_empty() else 1)

func produce(name_value: String):
	serial = 0
	outcomes = []
	var model = build()
	var replay: Array = []
	if name_value == "paused":
		for _tick in range(16):
			model.advance()
			if model.projection().stock.held == 1 and model.projection().remaining == 1:
				break
		verify(model.projection().stock.held == 1 and model.projection().remaining == 1, "checkpoint has actual partial work")
		verify(send(model, {"action": "set_power", "active": false}).accepted, "pause actual work before capture")
	elif name_value == "blocked":
		model.advance(24)
		verify(model.projection().stock.output == 1 and model.projection().stock.held == 1
			and model.projection().remaining == 0, "capture completed work stalled behind full output")
	else:
		for _tick in range(16):
			model.advance()
			if model.projection().stock.output == 1:
				break
		var take := {"context": model.context, "client": "P", "request": "applied-before-ack",
			"action": "retrieve", "amount": 1}
		verify(model.command(take).accepted, "capture after real retrieve applied without acknowledgement")
		replay.append(take)
		verify(send(model, {"action": "set_power", "active": false}).accepted, "stop for identity rebuild")
		var remove := {"context": model.context, "client": "P", "request": "remove-wheel-once",
			"action": "remove", "entity": "wheel-1"}
		verify(model.command(remove).accepted, "remove through real stopped-edit command")
		replay.append(remove)
		var rebuilt: Dictionary = send(model, {"action": "place", "kind": "wheel", "cell": [-1, 0]})
		verify(rebuilt.accepted and rebuilt.entity == "wheel-2", "replacement keeps generation-safe identity")
		verify(send(model, {"action": "connect_drive", "from": "wheel-2", "to": "collector-1"}).accepted, "reconnect returned shaft")
	var snapshot: Dictionary = model.checkpoint()
	var path := artifacts.path_join(name_value + ".save")
	verify(Store.write(model, path).accepted, "write validated actual checkpoint " + name_value)
	var saved_serial := serial
	outcomes = []
	finish(model, replay)
	var final_state: Dictionary = model.projection()
	var s: Dictionary = final_state.stock
	verify(s.source == 0 and s.collector == 0 and s.belt == 0 and s.input == 0 and s.held == 0 and s.output == 0,
		"reference drains finite raw and in-process holdings")
	verify(s.player == 16, "independent one-to-one reference yields sixteen products")
	references[name_value] = {"checkpoint": snapshot, "serial": saved_serial, "replay": replay,
		"outcomes": outcomes.duplicate(true), "final": final_state, "final_checkpoint": model.checkpoint()}
	case_evidence[name_value] = {"captured_stock": snapshot.stock, "remaining": snapshot.remaining,
		"power_enabled": snapshot.power_enabled, "identities": snapshot.next_ids,
		"saved_request_count": snapshot.requests.size(), "final": final_state,
		"file_sha256": FileAccess.get_sha256(path)}

func finish(model, replay: Array):
	for request in replay:
		var before: Dictionary = model.projection()
		verify(model.command(request).duplicate and model.projection() == before, "applied request cannot repeat on continuation")
	if not replay.is_empty():
		verify(not send(model, {"action": "connect_drive", "from": "wheel-1", "to": "collector-1"}).accepted,
			"new request to retired identity cannot retarget replacement")
	verify(send(model, {"action": "set_power", "active": true}).accepted, "resume actual operating path")
	for _tick in range(128):
		var state: Dictionary = model.projection()
		if state.stock.output > 0:
			verify(send(model, {"action": "retrieve", "amount": 1}).accepted, "retrieve actual continued product")
		model.advance()
		state = model.projection()
		if state.stock.player == 16 and state.stock.output == 0 and state.stock.held == 0:
			break

func consume(name_value: String):
	var reference: Dictionary = references[name_value]
	var model = Model.new(0, "unrelated-before-load", 1)
	verify(Store.read_into(model, artifacts.path_join(name_value + ".save")).accepted,
		"fresh process loads actual checkpoint " + name_value)
	verify(model.checkpoint() == reference.checkpoint, "complete typed ownership/request state restored")
	serial = reference.serial
	outcomes = []
	finish(model, reference.replay)
	verify(outcomes == reference.outcomes, "same subsequent commands/outcomes after restore")
	verify(model.projection() == reference.final, "semantic continuation matches uninterrupted consumer")
	verify(model.checkpoint() == reference.final_checkpoint, "IDs, request cache and future state remain equivalent")
	var state: Dictionary = model.projection()
	verify(state.stock.player == 16 and state.stock.source == 0, "independent final sixteen products preserved")
	verify(state.inventories.get("P", 0) == (1 if name_value == "identity-replay" else 0), "per-client applied transfer not repeated")
	case_evidence[name_value] = {"restored_stock": reference.checkpoint.stock,
		"remaining": reference.checkpoint.remaining, "final": state,
		"identities": model.checkpoint().next_ids, "replayed_requests": reference.replay}

func negative_inputs():
	var good := artifacts.path_join("identity-replay.save")
	var original := FileAccess.get_file_as_bytes(good)
	var base: Dictionary = references["identity-replay"].checkpoint
	var invalid: Dictionary = {}
	invalid["truncated"] = original.slice(0, original.size() - 3)
	invalid["empty"] = PackedByteArray()
	var corrupted := original.duplicate()
	corrupted[corrupted.size() - 1] ^= 1
	invalid["corrupt"] = corrupted
	invalid["wrong-envelope"] = "unrelated data".to_utf8_buffer()
	var oversized := PackedByteArray()
	oversized.resize(Store.MAX_BYTES + 1)
	invalid["oversized"] = oversized
	for kind in ["schema", "missing", "negative", "fraction", "dangling", "phase", "request"]:
		var bad := base.duplicate(true)
		match kind:
			"schema": bad.schema = 99
			"missing": bad.erase("stock")
			"negative": bad.stock.source = -1
			"fraction": bad.stock.source = 0.5
			"dangling": bad.entities.erase("processor-1")
			"phase": bad.remaining = 99
			"request": bad.requests = {}
		invalid[kind] = Store.encode(bad)
		verify(not Store.write_snapshot(bad, good).accepted, "invalid capture cannot replace previous good save " + kind)
		verify(FileAccess.get_file_as_bytes(good) == original, "failed capture preserves good file " + kind)
	var model = Model.new()
	verify(Store.read_into(model, good).accepted, "seed good running authority before bad input")
	for label in invalid:
		var before: Dictionary = model.checkpoint()
		var projection: Dictionary = model.projection()
		var path := artifacts.path_join("invalid-" + label + ".save")
		put(path, invalid[label])
		var result: Dictionary = Store.read_into(model, path)
		rejected_files[label] = result
		verify(not result.accepted, "file boundary rejects " + label)
		verify(model.checkpoint() == before and model.projection() == projection, "failed load preserves current authority " + label)
		verify(FileAccess.get_file_as_bytes(good) == original, "failed load preserves previous good artifact " + label)
	put(good + ".pending", "owned collision sentinel".to_utf8_buffer())
	verify(not Store.write(model, good).accepted, "pending collision refuses overwrite")
	verify(FileAccess.get_file_as_bytes(good + ".pending") == "owned collision sentinel".to_utf8_buffer(), "existing pending artifact preserved")
	verify(FileAccess.get_file_as_bytes(good) == original, "pending collision preserves good save")
	serial = references["identity-replay"].serial
	outcomes = []
	finish(model, references["identity-replay"].replay)
	verify(model.projection() == references["identity-replay"].final,
		"prior good authority still continues after every rejected load/save")

func put(path: String, data: PackedByteArray):
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		verify(false, "owned fixture file write")
		return
	file.store_buffer(data)
	file.close()
