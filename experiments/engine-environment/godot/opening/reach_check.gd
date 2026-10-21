extends SceneTree
## Actual Model/Store authority controls with explicitly synthetic actor samples.
## This is NOT native character/collision/input evidence; the real consumer is
## validated separately against the same Model and Session.
const Model = preload("res://model.gd")
const Store = preload("res://save-tests/checkpoint_file.gd")
const Geometry = preload("res://opening/site_geometry.gd")
var report_path := ""
var directory := ""
var checks := 0
var sequence := 0
var epoch := 0
var failures: Array = []
var cases: Dictionary = {}
var finished := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--reach-report="):
			report_path = argument.trim_prefix("--reach-report=")
		elif argument.begins_with("--reach-directory="):
			directory = argument.trim_prefix("--reach-directory=")
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		_finish()

func fresh(label: String):
	return Model.new(16, "physical-authority-" + label, 1, {"opening": true, "physical": true}, ["P", "Q"])

func publish(world, actor: String, position: Array) -> void:
	epoch += 1
	check(world.publish_actor(actor, position, epoch).accepted, "Trusted synthetic authority sample accepted")

func issue(world, action: Dictionary, actor := "P", request := "") -> Dictionary:
	sequence += 1
	var intent := action.duplicate(true)
	intent.merge({"context": world.context, "client": actor,
		"request": "control-" + str(sequence) if request.is_empty() else request}, true)
	return world.command(intent)

func custody(world) -> Dictionary:
	var snapshot: Dictionary = world.checkpoint()
	var value: Dictionary = {}
	for field in ["entities", "links", "parts", "stock", "inventories", "remaining", "drive_links", "power_enabled", "next_ids"]:
		value[field] = snapshot[field]
	return value

func roundtrip(world, label: String):
	var captured: Dictionary = world.checkpoint()
	var restored = fresh(label)
	var result: Dictionary = restored.restore_checkpoint(captured)
	check(result.accepted and restored.checkpoint() == captured, label + ": own checkpoint roundtrips exactly")
	check(not restored.projection().actors.P.ready and restored.projection().actors.P.native_epoch == 0,
		label + ": native readiness/epoch are never restored from historical receipts")
	return restored

func line(label: String):
	var world = fresh(label)
	publish(world, "P", [0.0, 0.9, 1.3])
	for entry in [["wheel", [-1, 0]], ["collector", [0, 0]], ["belt", [1, 0]], ["processor", [2, 0]]]:
		check(issue(world, {"action": "place", "kind": entry[0], "cell": entry[1]}).accepted, "Near stocked component placed")
	check(issue(world, {"action": "set_power", "active": false}).accepted, "Nearby wheel explicitly stops line")
	return world

func _run() -> void:
	check(report_path.is_absolute_path() and directory.is_absolute_path(), "Owned report and save directory supplied")
	var world = fresh("cache")
	var initial := custody(world)
	var unready := issue(world, {"action": "place", "kind": "collector", "cell": [0, 0]}, "P", "unready")
	check(not unready.accepted and unready.reason == "actor_unready" and custody(world) == initial,
		"Unregistered actor cannot build or consume an identity/part")
	publish(world, "P", [0.0, 0.9, 1.3])
	var repeated := issue(world, {"action": "place", "kind": "collector", "cell": [0, 0]}, "P", "unready")
	check(repeated.duplicate and repeated.reason == "actor_unready" and custody(world) == initial,
		"Exact old unready refusal remains cached after readiness")
	var placed := issue(world, {"action": "place", "kind": "collector", "cell": [0, 0]})
	check(placed.accepted and placed.entity == "collector-1" and world.parts.collector == 0,
		"Fresh near placement consumes exactly one real part/identity")
	placed.reach.position[0] = 999.0
	check(world.actors.P.position == [0.0, 0.9, 1.3], "Returned receipt does not alias persistent actor position")
	publish(world, "P", [0.0, 0.9, -4.0])
	var before := custody(world)
	var far := issue(world, {"action": "place", "kind": "belt", "cell": [1, 0],
		"camera_position": [1.65, 0.5, 0.0], "actor_position": [1.65, 0.9, 0.0]}, "P", "far-belt")
	check(not far.accepted and far.reason == "out_of_reach" and not far.reach.reachable and custody(world) == before,
		"Camera/caller position cannot grant reach or burn the next entity generation")
	publish(world, "P", [1.65, 0.9, 1.3])
	var old := issue(world, {"action": "place", "kind": "belt", "cell": [1, 0],
		"camera_position": [1.65, 0.5, 0.0], "actor_position": [1.65, 0.9, 0.0]}, "P", "far-belt")
	check(old.duplicate and old.reason == "out_of_reach" and custody(world) == before,
		"Walking closer does not re-evaluate an old refused identity")
	check(issue(world, {"action": "place", "kind": "belt", "cell": [1, 0]}).entity == "belt-1",
		"Fresh explicit request after walking can place the still-owned first belt")
	publish(world, "Q", [-20.0, 0.9, 0.0])
	before = custody(world)
	check(issue(world, {"action": "place", "kind": "processor", "cell": [2, 0]}, "Q").reason == "out_of_reach"
		and custody(world) == before, "Another nearby actor never lends reach to Q")
	publish(world, "Q", [3.3, 0.9, 1.3])
	check(issue(world, {"action": "place", "kind": "processor", "cell": [2, 0]}, "Q").accepted,
		"Q can build from its own admitted position")
	var projected: Dictionary = world.projection()
	projected.actors.P.capabilities.build_reach = 1000.0
	check(world.projection().actors.P.capabilities.build_reach == 4.0, "Projection cannot alias authoritative capability")
	var cached_restore = roundtrip(world, "cache-and-independent-actors")
	check(issue(cached_restore, {"action": "place", "kind": "belt", "cell": [1, 0],
		"camera_position": [1.65, 0.5, 0.0], "actor_position": [1.65, 0.9, 0.0]}, "P", "far-belt").reason == "out_of_reach",
		"Cached old refusal remains an inert historical result while restored actor is unready")
	cases["cache_and_independent_actors"] = world.checkpoint()
	var historical = fresh("cached-success")
	publish(historical, "P", [0.0, 0.9, 1.3])
	var accepted_once := issue(historical, {"action": "place", "kind": "collector", "cell": [0, 0]}, "P", "accepted-once")
	check(accepted_once.accepted, "Historical cache fixture first placement accepted")
	check(issue(historical, {"action": "remove", "entity": "collector-1"}).accepted, "Explicit removal returns that component before duplicate")
	historical.invalidate_actor("P")
	publish(historical, "Q", [0.0, 0.9, 0.0])
	before = custody(historical)
	var old_order: int = historical.order
	var old_requests: int = historical.requests.size()
	var accepted_duplicate := issue(historical, {"action": "place", "kind": "collector", "cell": [0, 0]}, "P", "accepted-once")
	check(accepted_duplicate.accepted and accepted_duplicate.duplicate and accepted_duplicate.entity == "collector-1"
		and accepted_duplicate.reach == accepted_once.reach and not historical.entities.has("collector-1")
		and historical.order == old_order and historical.requests.size() == old_requests and custody(historical) == before,
		"Cached accepted placement wins before unready/occupancy guards without replaying removed entity or consuming kit")
	roundtrip(historical, "cached-success-after-removal")
	cases["cached_accepted_historical"] = historical.checkpoint()
	var occupied = fresh("actor-clearance")
	publish(occupied, "P", [0.0, 0.9, 0.0])
	before = custody(occupied)
	var self_block := issue(occupied, {"action": "place", "kind": "collector", "cell": [0, 0]}, "P", "self-block")
	check(not self_block.accepted and self_block.reason == "actor_occupied" and self_block.blockers[0].actor == "P"
		and custody(occupied) == before, "Under-self placement refuses without part or identity loss")
	publish(occupied, "P", [0.0, 0.9, 1.3])
	check(issue(occupied, {"action": "place", "kind": "collector", "cell": [0, 0]}, "P", "self-block").reason == "actor_occupied"
		and custody(occupied) == before, "Old occupied refusal stays historical after its blocker walks away")
	publish(occupied, "Q", [0.0, 0.9, 0.0])
	var other_block := issue(occupied, {"action": "place", "kind": "collector", "cell": [0, 0]})
	check(other_block.reason == "actor_occupied" and other_block.blockers[0].actor == "Q" and custody(occupied) == before,
		"Other ready actor blocks physical placement using its own admitted sample")
	publish(occupied, "Q", [0.0, 0.9, 2.5])
	check(issue(occupied, {"action": "place", "kind": "collector", "cell": [0, 0]}).entity == "collector-1"
		and occupied.parts.collector == 0, "Fresh clear placement consumes the still-owned first component")
	roundtrip(occupied, "historical-blocker-poses")
	cases["actor_occupied_refusals"] = occupied.checkpoint()

	for entry in [["equality", Geometry.ANCHOR_HEIGHT + 4.0, true], ["outside", Geometry.ANCHOR_HEIGHT + 4.000000001, false]]:
		var edge = fresh(entry[0])
		publish(edge, "P", [0.0, entry[1], 0.0])
		var result := issue(edge, {"action": "place", "kind": "collector", "cell": [0, 0]})
		check(result.accepted == entry[2], "Scalar Model equality/just-outside is exact without permission epsilon")
		cases[entry[0]] = result
	var height = fresh("height")
	publish(height, "P", [3.8, 2.2, 0.0])
	check(issue(height, {"action": "place", "kind": "collector", "cell": [0, 0]}).reason == "out_of_reach",
		"Vertical distance matters even when the horizontal projection is near")
	publish(height, "P", [3.8, 0.9, 0.0])
	check(issue(height, {"action": "place", "kind": "collector", "cell": [0, 0]}).accepted,
		"Same horizontal position can build from the lower synthetic sample")
	cases["three_dimensional_height"] = height.checkpoint()

	var linked = line("links")
	publish(linked, "P", [-2.5, 0.9, 1.3])
	before = custody(linked)
	check(issue(linked, {"action": "connect", "from": "collector-1", "to": "belt-1"}).reason == "out_of_reach"
		and custody(linked) == before, "Both material endpoints must pass current reach")
	publish(linked, "P", [-5.0, 0.9, 1.3])
	check(issue(linked, {"action": "connect_drive", "from": "wheel-1", "to": "collector-1"}).reason == "out_of_reach"
		and custody(linked) == before, "Both mechanical endpoints must pass without a shaft debit")
	publish(linked, "P", [0.0, 0.9, 1.3])
	for pair in [["wheel-1", "collector-1"], ["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
		check(issue(linked, {"action": "connect_drive", "from": pair[0], "to": pair[1]}).accepted,
			"Nearby stopped drive connection uses one actual shaft")
	check(issue(linked, {"action": "disconnect_drive", "from": "collector-1", "to": "wheel-1"}).accepted,
		"Reverse-direction undirected drive disconnect accepted nearby")
	roundtrip(linked, "accepted-reverse-drive")
	check(issue(linked, {"action": "connect_drive", "from": "wheel-1", "to": "collector-1"}).accepted,
		"Explicit reconnect restores one drive edge")
	check(issue(linked, {"action": "disconnect_drive", "from": "wheel-1", "to": "collector-1"}).accepted,
		"Stored-direction drive disconnect accepted nearby")
	roundtrip(linked, "accepted-forward-drive")
	check(issue(linked, {"action": "connect_drive", "from": "wheel-1", "to": "collector-1"}).accepted,
		"Reconnect after stored-direction disconnect uses returned shaft")
	publish(linked, "P", [-5.0, 0.9, 1.3])
	before = custody(linked)
	var reverse_far := issue(linked, {"action": "disconnect_drive", "from": "collector-1", "to": "wheel-1"})
	check(reverse_far.reason == "out_of_reach" and custody(linked) == before,
		"Refused reverse drive disconnect changes neither edge nor refund")
	roundtrip(linked, "refused-reverse-drive")
	check(issue(linked, {"action": "disconnect_drive", "from": "wheel-1", "to": "collector-1"}).reason == "out_of_reach" and custody(linked) == before,
		"Refused stored-direction drive disconnect changes neither edge nor refund")
	roundtrip(linked, "refused-forward-drive")
	cases["reversed_drive_receipts"] = linked.checkpoint()
	publish(linked, "P", [0.0, 0.9, 1.3])
	for pair in [["collector-1", "belt-1"], ["belt-1", "processor-1"]]:
		check(issue(linked, {"action": "connect", "from": pair[0], "to": pair[1]}).accepted,
			"Nearby material links retain original flow rules")
	publish(linked, "P", [30.0, 0.9, 0.0])
	before = custody(linked)
	check(issue(linked, {"action": "set_power", "active": true}).reason == "out_of_reach" and custody(linked) == before,
		"Far camera wheel control cannot start the fixture")
	check(issue(linked, {"action": "remove", "entity": "processor-1"}).reason == "out_of_reach" and custody(linked) == before,
		"Far removal returns no kit and deletes no entity")
	check(issue(linked, {"action": "disconnect", "from": "collector-1", "to": "belt-1"}).reason == "out_of_reach" and custody(linked) == before,
		"Far material unlink changes no edge")
	publish(linked, "P", [-1.65, 0.9, 1.3])
	check(issue(linked, {"action": "set_power", "active": true}).accepted, "Physical near wheel starts real Model production")
	linked.advance(10)
	check(linked.stock.output == 1, "Actual original production law fills one press outlet")
	publish(linked, "P", [30.0, 0.9, 0.0])
	before = custody(linked)
	check(issue(linked, {"action": "retrieve", "entity": "processor-1", "amount": 1}).reason == "out_of_reach" and custody(linked) == before,
		"Remote retrieval cannot teleport an existing plate")
	publish(linked, "P", [3.3, 0.9, 1.3])
	check(issue(linked, {"action": "retrieve", "entity": "processor-1", "amount": 1}).accepted and linked.inventories.P == 1,
		"Nearby press retrieval moves exactly one real plate into P pocket")
	var continued = roundtrip(linked, "production-and-retrieval")
	# Old receipt ordinals can exceed a new native process's first ordinal.
	check(continued.publish_actor("P", [-1.65, 0.9, 1.3], 1).accepted, "Restored authority sample counter can restart without replaying historical receipts")
	check(issue(continued, {"action": "set_power", "active": false}).accepted, "Fresh actual authority request follows old saved receipt history")
	roundtrip(continued, "restored-epoch-history")
	cases["finite_production_and_retrieval"] = continued.checkpoint()

	var valid: Dictionary = continued.checkpoint()
	var mutations: Dictionary = {}
	var bad := valid.duplicate(true)
	bad.actors.P.capabilities.build_reach = 400.0
	mutations["unauthorized_capability"] = bad
	bad = valid.duplicate(true)
	bad.actors.P.position[1] = INF
	mutations["nonfinite_position"] = bad
	bad = valid.duplicate(true)
	bad.actors.P["ready"] = true
	mutations["persisted_native_readiness"] = bad
	bad = valid.duplicate(true)
	for record in bad.requests.values():
		if record.result.accepted:
			record.result.erase("reach")
			break
	mutations["missing_accepted_receipt"] = bad
	bad = valid.duplicate(true)
	for record in bad.requests.values():
		if record.result.has("reach"):
			record.result.reach.targets[0][0] += 0.1
			break
	mutations["forged_target_anchor"] = bad
	bad = valid.duplicate(true)
	for record in bad.requests.values():
		if record.result.has("reach") and record.intent.action == "disconnect_drive" and record.intent.from == "collector-1":
			# This is the literal malformed receipt produced by the retained
			# pre-compilation source finding, not a claimed old native execution.
			record.result.reach.targets.reverse()
			record.result.reach.distances_squared.reverse()
			break
	mutations["retained_reverse_order_receipt_shape"] = bad
	for label in mutations:
		var target = fresh("reject-" + label)
		var untouched: Dictionary = target.checkpoint()
		check(not target.restore_checkpoint(mutations[label]).accepted and target.checkpoint() == untouched,
			"Malformed physical checkpoint rejected atomically: " + label)
	var slot := directory.path_join("physical.factory")
	check(Store.write(continued, slot).accepted, "Existing Store validates/publishes schema2 without a second actor validator")
	var target = fresh("file-reopen")
	check(Store.read_into(target, slot).accepted and target.checkpoint() == valid and not target.projection().actors.P.ready,
		"Schema2 Store roundtrip preserves pose/kit/cache while requiring new native readiness")
	var solo = Model.new(16, "solo-profile", 1, {"opening": true, "physical": true})
	publish(solo, "P", [0.0, 0.9, 1.3])
	check(issue(solo, {"action": "place", "kind": "collector", "cell": [0, 0]}).accepted and solo.actors.size() == 1,
		"Offline roster has one real declared actor and no unused Q")
	var solo_path := directory.path_join("solo.factory")
	check(Store.write(solo, solo_path).accepted, "Format validator accepts declared P-only schema2")
	var solo_reopen = Model.new(16, "new-solo", 1, {"opening": true, "physical": true})
	check(Store.read_into(solo_reopen, solo_path).accepted and solo_reopen.checkpoint() == solo.checkpoint()
		and not solo_reopen.projection().actors.P.ready, "Same-roster P-only Store roundtrip keeps pose/cache and resets readiness")
	var dual = fresh("dual-roster")
	var roster_before: Dictionary = dual.checkpoint()
	check(dual.restore_checkpoint(solo.checkpoint()).reason == "actor_roster_mismatch" and dual.checkpoint() == roster_before,
		"Shared P/Q caller refuses P-only input without inventing Q or changing its live world")
	roster_before = solo_reopen.checkpoint()
	check(solo_reopen.restore_checkpoint(valid).reason == "actor_roster_mismatch" and solo_reopen.checkpoint() == roster_before,
		"Offline P caller refuses P/Q input without dropping Q/pockets or downgrading profile")
	cases["roster_boundaries"] = {"solo": solo.checkpoint(), "same_roster_reopened": true, "cross_roster_refused": true}
	var legacy = Model.new(16, "declared-legacy-fixture", 1, {"opening": true})
	check(issue(legacy, {"action": "place", "kind": "collector", "cell": [0, 4]}).accepted,
		"Explicit legacy control retains unrestricted historical placement, not physical proof")
	var legacy_path := directory.path_join("legacy.factory")
	check(Store.write(legacy, legacy_path).accepted, "Declared schema1 fixture remains serializable")
	var original := FileAccess.get_sha256(legacy_path)
	var untouched: Dictionary = target.checkpoint()
	var refusal: Dictionary = Store.read_into(target, legacy_path)
	check(not refusal.accepted and refusal.reason == "physical_state_required" and target.checkpoint() == untouched
		and FileAccess.get_sha256(legacy_path) == original, "Physical caller refuses old schema atomically and preserves original file")
	cases["legacy_refusal"] = refusal
	_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	var report := {"status": "pass" if failures.is_empty() else "fail", "kind": "synthetic_actor_authority_controls_not_native_character_proof",
		"pid": OS.get_process_id(), "checks": checks, "failures": failures, "cases": cases}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "", true, true))
		file.close()
	print("PHYSICAL_AUTHORITY_PASS" if failures.is_empty() else "PHYSICAL_AUTHORITY_FAIL")
	quit(0 if failures.is_empty() else 1)
