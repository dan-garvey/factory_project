extends SceneTree
## Concrete regressions from independent review of 2aea9ae and 6c47ebd.

const Model = preload("res://model.gd")
var checks := 0
var failures: Array[String] = []
var source
var original: Dictionary
var key := JSON.stringify(["P", "one"])

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func reject_unchanged(label: String, candidate: Dictionary) -> void:
	var target = Model.new(8, "preserved-live-world", 2)
	var before_projection: Dictionary = target.projection()
	var before_checkpoint: Dictionary = target.checkpoint()
	var result: Dictionary = target.restore_checkpoint(candidate)
	check(result.get("accepted") is bool and not result.accepted, label + ": reject")
	check(target.projection() == before_projection and target.checkpoint() == before_checkpoint,
		label + ": preserve complete prior world")

func target_case(world, request: String, intent: Dictionary) -> Dictionary:
	intent.merge({"context": world.context, "client": "P", "request": request})
	var outcome: Dictionary = world.command(intent)
	check(outcome.accepted, request + ": actual command accepted")
	var snapshot: Dictionary = world.checkpoint()
	var restored = Model.new()
	check(restored.restore_checkpoint(snapshot).accepted and restored.checkpoint() == snapshot,
		request + ": positive history restores exactly")
	var retry: Dictionary = restored.command(intent)
	check(retry.accepted and retry.duplicate and retry.entity == outcome.entity,
		request + ": restored retry retains actual target")
	for wrong in ["wrong-target", "", 0, [], null]:
		# Empty is correct for actions whose outcome deliberately has no entity.
		if wrong is String and wrong == outcome.entity:
			continue
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid.requests[JSON.stringify(["P", request])].result.entity = wrong
		reject_unchanged(request + ": contradictory result target " + str(wrong), invalid)
	return snapshot

func check_targets() -> void:
	var world = Model.new(16, "target-correlations", 1, {"opening": true})
	# Power results follow the historical wheel, not the final live wheel.
	target_case(world, "power-empty", {"action": "set_power", "active": false})
	target_case(world, "wheel", {"action": "place", "kind": "wheel", "cell": [-1, 0]})
	for row in [["collector", 0], ["belt", 1], ["processor", 2]]:
		target_case(world, row[0], {"action": "place", "kind": row[0], "cell": [row[1], 0]})
	target_case(world, "material", {"action": "connect", "from": "collector-1", "to": "belt-1"})
	target_case(world, "material-two", {"action": "connect", "from": "belt-1", "to": "processor-1"})
	for pair in [["wheel-1", "collector-1"], ["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
		target_case(world, pair[1] + "-drive", {"action": "connect_drive", "from": pair[0], "to": pair[1]})
	target_case(world, "power-live", {"action": "set_power", "active": true})
	world.advance(7)
	var snapshot: Dictionary = target_case(world, "take", {"action": "retrieve", "entity": "processor-1"})
	for wrong in ["processor-retired", "collector-1", "", 0, [], null]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid.requests[JSON.stringify(["P", "take"])].intent.entity = wrong
		reject_unchanged("explicit retrieve target " + str(wrong), invalid)
	# Omitting the optional target remains valid and uses the live processor.
	world.advance(2)
	target_case(world, "take-implicit", {"action": "retrieve"})
	target_case(world, "power-stop", {"action": "set_power", "active": false})
	target_case(world, "unlink", {"action": "disconnect", "from": "collector-1", "to": "belt-1"})
	# Reverse direction is accepted by the real undirected drive disconnector.
	target_case(world, "unlink-drive", {"action": "disconnect_drive", "from": "collector-1", "to": "wheel-1"})
	target_case(world, "wheel-remove", {"action": "remove", "entity": "wheel-1"})
	target_case(world, "power-removed", {"action": "set_power", "active": false})
	target_case(world, "wheel-rebuild", {"action": "place", "kind": "wheel", "cell": [-1, 0]})
	target_case(world, "power-rebuilt", {"action": "set_power", "active": false})

func _initialize() -> void:
	source = Model.new(16, "review-checkpoint", 1, {"opening": true})
	var intent := {"context": source.context, "client": "P", "request": "one",
		"action": "place", "kind": "collector", "cell": [0, 0]}
	check(source.command(intent).accepted, "Positive placement fixture")
	original = source.checkpoint()
	var positive = Model.new()
	check(positive.restore_checkpoint(original).accepted, "Positive checkpoint accepted")
	check(positive.checkpoint() == original, "Positive checkpoint exact continuation facts")
	# Each case must produce a clean negative result: the runner also fails on
	# any SCRIPT ERROR/ERROR even if a GDScript function falls through afterward.
	for value in [0, "", [], {}, null]:
		var invalid: Dictionary = original.duplicate(true)
		invalid.requests[key].result.duplicate = value
		reject_unchanged("duplicate type " + type_string(typeof(value)), invalid)
	for field in ["context", "client", "request", "entity", "reason"]:
		for value in [0, false, [], {}, null]:
			var invalid: Dictionary = original.duplicate(true)
			invalid.requests[key].result[field] = value
			reject_unchanged("result " + field + "/" + type_string(typeof(value)), invalid)
	for field in ["context", "client", "request", "action"]:
		for value in [0, false, [], {}, null]:
			var invalid: Dictionary = original.duplicate(true)
			invalid.requests[key].intent[field] = value
			reject_unchanged("intent " + field + "/" + type_string(typeof(value)), invalid)
	var invalid: Dictionary = original.duplicate(true)
	invalid.revision = 0
	invalid.requests[key].result.revision = 0
	reject_unchanged("accepted placement at revision zero", invalid)
	var opaque := RefCounted.new()
	opaque.set_meta("external", "before")
	for field in ["intent", "result"]:
		invalid = original.duplicate(true)
		invalid.requests[key][field]["opaque"] = {"nested": [opaque]}
		reject_unchanged("non-value in retained " + field, invalid)
	# Command ingress must not poison a future checkpoint before validation.
	var before: Dictionary = source.checkpoint()
	var poisoned: Dictionary = intent.duplicate(true)
	poisoned.request = "object-ingress"
	poisoned.opaque = {"nested": [opaque]}
	check(not source.command(poisoned).accepted, "Non-value command must be refused before retention")
	opaque.set_meta("external", "after")
	check(source.checkpoint() == before, "External object cannot alter retained command state")
	var cycle: Array = []
	cycle.append(cycle)
	invalid = original.duplicate(true)
	invalid.requests[key].intent["cycle"] = cycle
	reject_unchanged("cyclic metadata", invalid)
	cycle.clear()
	source.command({"context": source.context, "client": "P", "request": "remove",
		"action": "remove", "entity": "collector-1"})
	source.command({"context": source.context, "client": "P", "request": "two",
		"action": "place", "kind": "collector", "cell": [0, 0]})
	var rebuilt: Dictionary = source.checkpoint()
	check(positive.restore_checkpoint(rebuilt).accepted, "Positive removed/rebuilt history accepted")
	var retry := {"context": source.context, "client": "P", "request": "two",
		"action": "place", "kind": "collector", "cell": [0, 0]}
	var repeated: Dictionary = positive.command(retry)
	check(repeated.duplicate and repeated.entity == "collector-2" and positive.projection().entities.has(repeated.entity),
		"Positive retry names actual rebuilt entity")
	invalid = rebuilt.duplicate(true)
	invalid.requests[JSON.stringify(["P", "two"])].result.entity = "collector-1"
	reject_unchanged("accepted placements share a generated identity", invalid)
	invalid = rebuilt.duplicate(true)
	invalid.requests[JSON.stringify(["P", "two"])].result.revision = 1
	reject_unchanged("accepted revisions regress", invalid)
	invalid = rebuilt.duplicate(true)
	invalid.next_ids.collector += 1
	reject_unchanged("counter unsupported by retained generation history", invalid)
	# Well-typed extra plain metadata remains supported and owns its copies.
	var plain = Model.new(16, "plain-metadata", 1, {"opening": true})
	var plain_intent := {"context": plain.context, "client": "P", "request": "plain", "action": "place",
		"kind": "collector", "cell": [0, 0], "metadata": {"labels": ["kept", 1, true]}}
	check(plain.command(plain_intent).accepted, "Pure nested command metadata retained")
	var stored: Dictionary = plain.checkpoint()
	plain_intent.metadata.labels[0] = "external-change"
	check(plain.checkpoint() == stored, "Pure metadata is deeply owned")
	check(positive.restore_checkpoint(stored).accepted and positive.checkpoint() == stored,
		"Pure nested metadata survives restoration")
	check_targets()
	print("CHECKPOINT_REGRESSION_PASS: %d checks" % checks if failures.is_empty() else "CHECKPOINT_REGRESSION_FAIL: " + JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
