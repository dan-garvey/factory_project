extends SceneTree
## Headless verification of the post-shift upstream-drive presenter and
## failure diagnostics against confirmed native projection structures.

const Challenge = preload("res://opening/upstream_drive_challenge.gd")
const Geometry = preload("res://opening/site_geometry.gd")

var checks := 0
var failures := 0


class HostStub extends RefCounted:
	var state: Dictionary
	var client := "P"
	var legacy_fixture := false
	var calls: Array = []

	func issue(wire: Dictionary) -> Dictionary:
		calls.append(wire.duplicate(true))
		return {"queued": true, "accepted": false}


func verify(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("UPSTREAM_DRIVE_CHALLENGE_FAILURE: " + reason)


func base_fixture(products: int = 4) -> Dictionary:
	return {
		"context": "upstream-drive-fixture",
		"options": {"native": true, "opening": true, "physical": true},
		"actors": {"P": {"ready": true}, "Q": {"ready": true}},
		"inventories": {"P": products, "Q": 0},
		"cargo": {
			"P": {"raw": 0, "products": products, "work_lots": []},
			"Q": {"raw": 0, "products": 0, "work_lots": []},
		},
		"stock": {
			"source": 16 - products - 3,
			"collector": 1,
			"belt": 1,
			"input": 0,
			"held": 1,
			"output": 0,
			"player": products,
		},
		"entities": {
			"wheel": {"kind": "wheel", "generation": 1, "cell": [-1, 1], "center": [-4, 0, 4], "axis": 0},
			"collector": {"kind": "collector", "generation": 2, "cell": [0, 1], "center": [0, 0, 4], "axis": 0},
			"belt": {"kind": "belt", "generation": 3, "cell": [1, 1], "center": [4, 0, 4], "axis": 0},
			"press": {"kind": "processor", "generation": 4, "cell": [2, 1], "center": [8, 0, 4], "axis": 0},
		},
		"transmission_parts": {
			"s1": {"kind": "shaft", "generation": 5, "center": [-2, 0, 4], "axis": 0, "teeth": 0, "half_span": 2},
			"s2": {"kind": "shaft", "generation": 6, "center": [2, 0, 4], "axis": 0, "teeth": 0, "half_span": 2},
			"s3": {"kind": "shaft", "generation": 7, "center": [6, 0, 4], "axis": 0, "teeth": 0, "half_span": 2},
		},
		"links": [["collector", "belt"], ["belt", "press"]],
		"drive_links": [["wheel", "collector"], ["collector", "belt"], ["belt", "press"]],
		"engagements": [
			{"a": "s1", "b": "wheel", "kind": 1},
			{"a": "s1", "b": "collector", "kind": 1},
			{"a": "s2", "b": "collector", "kind": 1},
			{"a": "s2", "b": "belt", "kind": 1},
			{"a": "s3", "b": "belt", "kind": 1},
			{"a": "s3", "b": "press", "kind": 1},
		],
		"motion": {
			"wheel": {"state": "rotating", "numerator": 1, "denominator": 1},
			"collector": {"state": "rotating", "numerator": 1, "denominator": 1},
			"belt": {"state": "rotating", "numerator": 1, "denominator": 1},
			"press": {"state": "rotating", "numerator": 1, "denominator": 1},
			"s1": {"state": "rotating", "numerator": 1, "denominator": 1},
			"s2": {"state": "rotating", "numerator": 1, "denominator": 1},
			"s3": {"state": "rotating", "numerator": 1, "denominator": 1},
		},
		"part_kits": {
			"P": {"collector": 0, "belt": 0, "processor": 0, "wheel": 0, "shaft": 0, "gear": 2},
			"Q": {"collector": 0, "belt": 0, "processor": 0, "wheel": 0, "shaft": 0, "gear": 0},
		},
		"part_specifications": {
			"P": [
				{"kind": "gear", "teeth": 2, "half_span": 0, "count": 2},
				{"kind": "shaft", "teeth": 0, "half_span": 2, "count": 0},
			],
			"Q": [
				{"kind": "gear", "teeth": 2, "half_span": 0, "count": 0},
				{"kind": "shaft", "teeth": 0, "half_span": 2, "count": 0},
			],
		},
		"powered": true,
		"power_enabled": true,
	}


func _initialize() -> void:
	call_deferred("_run")


func _check_basic_loop_and_isolation() -> void:
	var host := HostStub.new()
	host.state = base_fixture(3)
	var challenge := Challenge.new()
	challenge.configure(host, Vector2i(-1, 0))
	var report := challenge.evaluate()
	verify(
		report.phase == "first_shift" and report.diagnostic_code == "complete_first_shift" and challenge.goal_text().is_empty(),
		"Before four carried plates, the basic first-shift objective remains untouched."
	)

	host.state = base_fixture(4)
	report = challenge.evaluate()
	verify(
		report.phase == "move_source" and report.diagnostic_code == "relocate_wheel" and not report.source_at_target
		and "Remove the waterwheel" in report.diagnostic_text and "Disconnect" not in report.diagnostic_text,
		"Reaching four plates on the starter row requires moving the waterwheel to the upstream race."
	)
	host.state.transmission_parts.erase("s1")
	host.state.drive_links = []
	host.state.engagements = [{"a": "wheel", "b": "collector", "kind": 1}]
	report = challenge.evaluate()
	verify(report.diagnostic_code == "relocate_wheel" and "Remove the waterwheel" in report.diagnostic_text
		and "Disconnect" not in report.diagnostic_text,
		"A directly touching axle must not invent a shaft to disconnect.")
	host.state.entities.erase("wheel")
	report = challenge.evaluate()
	verify(report.diagnostic_code == "relocate_wheel" and "Place the waterwheel" in report.diagnostic_text,
		"Once removed, the guidance asks for the wheel to be placed upstream.")
	verify(
		"Upstream drive · 4 / 8 plates" in challenge.goal_text(),
		"Once four plates are collected, the upstream-drive goal banner becomes active."
	)

	host.client = "Q"
	report = challenge.evaluate()
	verify(
		report.phase == "first_shift" and report.products == 0,
		"Aggregate player stock never awards P's four-plate progress to Q."
	)
	host.client = "P"

	host.state.options.native = false
	challenge.refresh()
	verify(
		not challenge.visible and challenge.get_child_count() == 0 and challenge.evaluate().phase == "unavailable",
		"A non-native projection hides the presenter and clears its 3D marker."
	)
	challenge.free()


func _check_failure_diagnostics() -> void:
	var host := HostStub.new()
	host.state = base_fixture(4)
	var challenge := Challenge.new()
	challenge.configure(host, Vector2i(-1, 0))

	# Uncouple old wheel shaft; wheel still at [-1, 1]
	host.state.transmission_parts.erase("s1")
	host.state.drive_links = [["collector", "belt"], ["belt", "press"]]
	host.state.engagements = [
		{"a": "s2", "b": "collector", "kind": 1},
		{"a": "s2", "b": "belt", "kind": 1},
		{"a": "s3", "b": "belt", "kind": 1},
		{"a": "s3", "b": "press", "kind": 1},
	]
	verify(
		challenge.evaluate().diagnostic_code == "relocate_wheel",
		"After disconnecting the starter shaft, the diagnostic prompts placing the wheel at the upstream race."
	)

	# Move wheel to upstream target [-1, 0]; machines unpowered
	host.state.entities.wheel.cell = [-1, 0]
	host.state.entities.wheel.center = [-4, 0, 0]
	for id in ["collector", "belt", "press", "s2", "s3"]:
		host.state.motion[id] = {"state": "unpowered", "numerator": 0, "denominator": 1}

	# A disconnected elevated cog alone cannot establish a height mismatch.
	host.state.transmission_parts["g1"] = {"kind": "gear", "generation": 8, "center": [0, 4, 0], "axis": 0, "teeth": 2, "half_span": 0}
	var report := challenge.evaluate()
	verify(
		report.phase == "restore_drive" and report.diagnostic_code == "missing_drive_shaft",
		"An unrelated elevated cog is not presented as proof of a height mismatch."
	)

	# A Z-axis cog can be part of the perpendicular belt train.
	host.state.transmission_parts["g1"] = {"kind": "gear", "generation": 8, "center": [0, 0, 0], "axis": 2, "teeth": 2, "half_span": 0}
	report = challenge.evaluate()
	verify(
		report.phase == "restore_drive" and report.diagnostic_code == "missing_drive_shaft",
		"A Z-axis cog is not automatically diagnosed as the wrong axis."
	)

	# Failure 3: Only one cog placed at [0, 0, 0]
	host.state.transmission_parts["g1"] = {"kind": "gear", "generation": 8, "center": [0, 0, 0], "axis": 0, "teeth": 2, "half_span": 0}
	report = challenge.evaluate()
	verify(
		report.phase == "restore_drive" and report.diagnostic_code == "missing_drive_shaft",
		"An incomplete train reports the missing drive without prescribing a fixed cog count."
	)

	# Failure 4: Second cog placed with quarter-grid X plane mismatch ([1, 0, 4] vs [0, 0, 0])
	host.state.transmission_parts["g2"] = {"kind": "gear", "generation": 9, "center": [1, 0, 4], "axis": 0, "teeth": 2, "half_span": 0}
	report = challenge.evaluate()
	verify(
		report.phase == "restore_drive" and report.diagnostic_code == "missing_drive_shaft",
		"Two disconnected cogs do not prove which part has a plane mismatch."
	)

	# Failure 5: Cogs mesh at [0, 0, 0] and [0, 0, 4], but upstream wheel shaft is missing
	host.state.transmission_parts["g2"].center = [0, 0, 4]
	host.state.engagements.append({"a": "g1", "b": "g2", "kind": 0})
	report = challenge.evaluate()
	verify(
		report.phase == "restore_drive" and report.diagnostic_code == "missing_drive_shaft",
		"Meshed cogs without the upstream waterwheel shaft are diagnosed as an incomplete drive train."
	)

	# Failure 6: Upstream shaft added, but drive switch is off
	host.state.transmission_parts["s1"] = {"kind": "shaft", "generation": 10, "center": [-2, 0, 0], "axis": 0, "teeth": 0, "half_span": 2}
	host.state.engagements.append({"a": "s1", "b": "wheel", "kind": 1})
	host.state.engagements.append({"a": "s1", "b": "g1", "kind": 1})
	host.state.power_enabled = false
	report = challenge.evaluate()
	verify(
		report.phase == "restore_drive" and report.diagnostic_code == "drive_switched_off",
		"A complete mechanical train with power_enabled=false diagnoses that the drive switch is off."
	)

	# Failure 7: Stalled transmission conflict
	host.state.power_enabled = true
	host.state.motion.collector.state = "stalled"
	report = challenge.evaluate()
	verify(
		report.phase == "restore_drive" and report.diagnostic_code == "stalled_transmission",
		"A stalled motion state is diagnosed before any generic shaft hint."
	)
	challenge.free()


func _check_both_viable_arrangements() -> void:
	var host := HostStub.new()
	var challenge := Challenge.new()

	# Route B: Geared Transfer (keep machines on row 1, wheel at [-1, 0], 2 cogs at [0,0,0] and [0,0,4])
	host.state = base_fixture(4)
	var before_geared: Dictionary = host.state.duplicate(true)
	challenge.configure(host, Vector2i(-1, 0))
	verify(host.state == before_geared and host.calls.is_empty(), "Configuration mutates no state and sends no command.")

	host.state.entities.wheel.cell = [-1, 0]
	host.state.entities.wheel.center = [-4, 0, 0]
	host.state.transmission_parts["s1"].center = [-2, 0, 0]
	host.state.transmission_parts["g1"] = {"kind": "gear", "generation": 8, "center": [0, 0, 0], "axis": 0, "teeth": 2, "half_span": 0}
	host.state.transmission_parts["g2"] = {"kind": "gear", "generation": 9, "center": [0, 0, 4], "axis": 0, "teeth": 2, "half_span": 0}
	for n in range(5):
		host.state.transmission_parts["extra" + str(n)] = {"kind": "gear", "generation": 11 + n, "center": [n * 4, 0, 12], "axis": 2, "teeth": 2, "half_span": 0}
	host.state.part_kits.P.gear = 0
	host.state.part_specifications.P[0].count = 0
	host.state.engagements = [
		{"a": "s1", "b": "wheel", "kind": 1},
		{"a": "s1", "b": "g1", "kind": 1},
		{"a": "g1", "b": "g2", "kind": 0},
		{"a": "s2", "b": "g2", "kind": 1},
		{"a": "s2", "b": "collector", "kind": 1},
		{"a": "s2", "b": "belt", "kind": 1},
		{"a": "s3", "b": "belt", "kind": 1},
		{"a": "s3", "b": "press", "kind": 1},
	]
	for id in ["g2", "collector", "belt", "press", "s2", "s3"]:
		host.state.motion[id] = {"state": "rotating", "numerator": -1, "denominator": 1}
	host.state.motion["g1"] = {"state": "rotating", "numerator": 1, "denominator": 1}

	var geared := challenge.evaluate()
	verify(
		geared.phase == "deliver_more"
		and geared.arrangement == "geared_transfer"
		and geared.placed_gears == 7
		and geared.spare_gears == 0
		and geared.placed_shafts == 3
		and geared.machine_rates.collector.numerator == -1,
		"The two-cog transfer route powers all three original machines at -1/1 rate with 0 spare cogs."
	)
	verify(
		"processing rate unchanged" not in geared.diagnostic_text and "speed" in geared.tradeoff_text
		and "yield" in geared.tradeoff_text and "does not alter processing speed" not in geared.tradeoff_text,
		"Presenter copy reflects speed-sensitive work while retaining the same recipe yield."
	)

	host.state.inventories.P = 8
	host.state.cargo.P.products = 8
	geared = challenge.evaluate()
	verify(
		geared.phase == "ready" and geared.diagnostic_code == "challenge_complete" and geared.arrangement == "geared_transfer",
		"Collecting eight plates completes the challenge via the geared transfer route."
	)

	# Route A: Relocated Line (also test with Workhorse's [-1, 1] upstream target from row 0)
	host.state = base_fixture(4)
	challenge.set_target_wheel_cell(Vector2i(-1, 1))
	# Simulate mid-relocation: machines removed after recovery
	host.state.entities.erase("collector")
	host.state.entities.erase("belt")
	var mid := challenge.evaluate()
	verify(
		mid.phase == "restore_drive" and mid.diagnostic_code == "missing_machines",
		"Removing stocked machines for relocation is diagnosed as missing_machines until rebuilt."
	)

	# All 3 machines rebuilt on row 1 alongside wheel at [-1, 1], 0 gears placed, 2 spare gears retained
	host.state = base_fixture(6)
	var relocated := challenge.evaluate()
	verify(
		relocated.phase == "deliver_more"
		and relocated.arrangement == "relocated_line"
		and relocated.placed_gears == 0
		and relocated.spare_gears == 2
		and relocated.placed_shafts == 3
		and relocated.machine_rates.collector.numerator == 1,
		"The relocated-line route runs all three machines on the target row at +1/1 rate while keeping 2 cogs spare."
	)

	host.state.inventories.P = 8
	host.state.cargo.P.products = 8
	relocated = challenge.evaluate()
	verify(
		relocated.phase == "ready" and relocated.arrangement == "relocated_line" and relocated.products == 8,
		"Collecting eight plates completes the challenge via the relocated-line route."
	)

	# Stopping power immediately drops eligibility back to restore_drive (no sticky completion flag)
	host.state.power_enabled = false
	for id in ["wheel", "collector", "belt", "press", "s1", "s2", "s3"]:
		host.state.motion[id] = {"state": "unpowered", "numerator": 0, "denominator": 1}
	var stopped := challenge.evaluate()
	verify(
		stopped.phase == "restore_drive" and stopped.products == 8,
		"Stopping the drive re-derives restore_drive immediately rather than caching completion."
	)
	challenge.free()


func _check_marker_cache() -> void:
	var host := HostStub.new()
	host.state = base_fixture(4)
	var challenge := Challenge.new()
	challenge.configure(host, Vector2i(-1, 0))
	verify(challenge.get_child_count() == 1, "Configuring a native projection creates one UpstreamRaceMarker.")
	var marker: Node3D = challenge.get_node("UpstreamRaceMarker")
	var first_id: int = marker.get_instance_id()
	verify(
		marker.position.is_equal_approx(Vector3(-Geometry.PITCH, 0.04, 0.0)),
		"UpstreamRaceMarker sits at the exact world coordinates of target_wheel_cell."
	)
	var snapshot_before: Dictionary = host.state.duplicate(true)
	challenge.refresh()
	verify(
		challenge.get_node("UpstreamRaceMarker").get_instance_id() == first_id
		and host.state == snapshot_before
		and host.calls.is_empty(),
		"An unchanged refresh preserves the 3D marker instance and does not mutate host.state."
	)
	challenge.set_target_wheel_cell(Vector2i(-1, 1))
	var updated_marker: Node3D = challenge.get_node("UpstreamRaceMarker")
	verify(
		updated_marker.get_instance_id() != first_id
		and updated_marker.position.is_equal_approx(Vector3(-Geometry.PITCH, 0.04, Geometry.PITCH)),
		"Changing target_wheel_cell rebuilds the marker at the new stream connection."
	)
	challenge.free()


func _run() -> void:
	_check_basic_loop_and_isolation()
	_check_failure_diagnostics()
	_check_both_viable_arrangements()
	_check_marker_cache()
	var ok: bool = failures == 0 and checks >= 16
	print("UPSTREAM_DRIVE_CHALLENGE_%s %d" % ["PASS" if ok else "FAIL", checks])
	quit(0 if ok else 1)
