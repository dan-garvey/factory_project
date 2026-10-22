extends SceneTree
## Synthetic projection unit test for the native-authoritative challenge presenter.

const Challenge = preload("res://opening/upstream_drive_challenge.gd")
const Geometry = preload("res://opening/site_geometry.gd")
var checks := 0
var failures := 0

class HostStub extends RefCounted:
	var state: Dictionary
	var client := "P"
	var legacy_fixture := false

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("UPSTREAM_DRIVE_CHALLENGE_FAILURE: " + message)

func report(actor: String, products: int, phase: String, source: bool, machines: bool, forward: bool) -> Dictionary:
	return {"schema": 1, "format": "factory-opening-engineering", "actor": actor, "known_actor": true,
		"products": products, "phase": phase, "source_at_target": source, "machines_running": machines,
		"belt_forward": forward, "wheel_cell": [-2, 0], "first_target": 4, "target": 8}

func fixture() -> Dictionary:
	return {
		"context": "presenter-unit", "options": {"native": true}, "inventories": {"P": 4, "Q": 0},
		"entities": {
			"wheel": {"kind": "wheel", "cell": [-2, 0]},
			"collector": {"kind": "collector", "cell": [0, 1]},
			"press": {"kind": "processor", "cell": [3, 1]},
		},
		"transmission_parts": {
			"first": {"kind": "shaft"}, "last": {"kind": "shaft"}, "cog": {"kind": "gear"},
		},
		"belt_spans": {"belt": {"from": "first", "to": "last"}},
		"motion": {"collector": {"state": "rotating", "numerator": 1, "denominator": 1},
			"press": {"state": "rotating", "numerator": 1, "denominator": 1}},
		"engagements": [{"a": "wheel", "b": "cog", "kind": 1}, {"a": "cog", "b": "first", "kind": 0}],
		"part_kits": {"P": {"shaft": 6, "gear": 9}, "Q": {"shaft": 0, "gear": 0}},
		"power_enabled": true,
		"opening_engineering": {"P": report("P", 4, "deliver_more", true, true, true),
			"Q": report("Q", 0, "first_shift", true, true, true)},
	}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if "--native-example-only" in OS.get_cmdline_user_args():
		_run_native_example()
		return
	var host := HostStub.new()
	host.state = fixture()
	var before := host.state.duplicate(true)
	var challenge := Challenge.new()
	challenge.configure(host, Vector2i(-2, 0))
	var current: Dictionary = challenge.evaluate()
	verify(current.phase == "deliver_more" and current.machines_placed == 2 and current.belt_forward,
		"A real-shaped shaft-span projection uses the native forward report without a belt machine.")
	verify(current.diagnostic_code == "producing_plates" and "4 / 8" in challenge.goal_text(),
		"The working route prompts collection rather than missing machine links.")
	verify(host.state == before, "Presenter configuration and inspection never mutate the projection.")
	verify(challenge.get_child_count() == 0, "Guidance creates no unbuilt world props.")
	challenge.refresh()
	verify(challenge.get_child_count() == 0 and host.state == before, "Refresh stays read-only without world props.")

	# Native progress, not synthetic local counts, determines phase and direction.
	host.state.opening_engineering.P = report("P", 4, "restore_drive", true, true, false)
	current = challenge.evaluate()
	challenge.refresh()
	verify(challenge.get_child_count() == 0,
		"A direction change keeps guidance in the UI.")
	verify(current.phase == "restore_drive" and current.diagnostic_code == "missing_material_route"
		and "toward the press" in current.diagnostic_text,
		"Disconnected or reversed routes receive non-speculative route guidance.")
	host.state.belt_spans.clear()
	current = challenge.evaluate()
	verify("shafts" in current.diagnostic_text and "belt" in current.diagnostic_text,
		"An absent span explains how to place the belt.")
	host.state.entities.erase("press")
	host.state.opening_engineering.P = report("P", 4, "restore_drive", true, false, false)
	verify(challenge.evaluate().diagnostic_code == "missing_machines", "A removed press is diagnosed as a missing machine.")
	host.state = fixture()
	host.state.opening_engineering.P = report("P", 4, "restore_drive", true, false, false)
	host.state.motion.collector.state = "stalled"
	verify(challenge.evaluate().diagnostic_code == "stalled_transmission", "A stalled component remains diagnosable.")
	host.state.motion.collector.state = "unpowered"
	host.state.power_enabled = false
	verify(challenge.evaluate().diagnostic_code == "drive_switched_off", "A connected but switched-off drive remains diagnosable.")

	host.state = fixture()
	host.state.opening_engineering.P = report("P", 4, "move_source", false, true, true)
	verify(challenge.evaluate().diagnostic_code == "relocate_wheel", "Native move-source phase controls the prompt.")
	host.client = "Q"
	verify(challenge.evaluate().phase == "first_shift" and challenge.goal_text().is_empty(), "Progress remains actor-bound.")
	host.client = "P"
	host.state.opening_engineering.P.actor = "Q"
	verify(challenge.evaluate().phase == "unavailable", "A report for the wrong actor is refused.")
	host.state = fixture()
	host.state.opening_engineering.P.products = 8
	verify(challenge.evaluate().phase == "unavailable", "A mismatched inventory and report is refused.")
	host.state = fixture()
	host.state.inventories.P = 8
	host.state.opening_engineering.P = report("P", 8, "ready", true, true, true)
	verify(challenge.evaluate().phase == "ready" and challenge.evaluate().diagnostic_code == "challenge_complete", "Native ready state is displayed.")
	host.state.options.native = false
	challenge.refresh()
	verify(not challenge.visible and challenge.get_child_count() == 0, "A non-native state hides guidance without world props.")
	challenge.free()
	var ok := failures == 0 and checks >= 17
	print("UPSTREAM_DRIVE_CHALLENGE_%s %d" % ["PASS" if ok else "FAIL", checks])
	quit(0 if ok else 1)


func _run_native_example() -> void:
	# Isolated Help component against the production native authority; no
	# game scene, player input, foreground acquisition or desktop interaction.
	var native_model = load("res://opening/native_model.gd")
	var example_script = load("res://opening/example_presenter.gd")
	var player = native_model.new("separate-player", ["P"])
	verify(player.boot_result.get("accepted", false), "Independent native player world starts.")
	var original: Dictionary = player.checkpoint()
	var example = example_script.new()
	root.add_child(example)
	var first: Dictionary = example.model.projection()
	verify(first.get("options", {}).get("native", false), "Example uses the native worksite rules.")
	verify(first.get("belt_spans", {}).size() == 1 and first.get("entities", {}).size() == 3,
		"The example constructs a span and three machines without a belt machine.")
	verify(first.get("transmission_parts", {}).size() == 12 and first.stock.source == first.initial_feed,
		"The finite kit places seven cogs and five shafts before production.")
	if failures > 0:
		example.free()
		print("NATIVE_EXAMPLE_FAIL %d" % checks)
		quit(1)
		return
	var source_posts := 0
	for part: Dictionary in first.transmission_parts.values():
		if part.center in [[0, 4, 0], [0, 4, -4]]:
			source_posts += 1
			verify(part.support.foot[1] >= Geometry.PITCH and part.support.bearing[1] > part.support.foot[1],
				"The native source-side stand begins above the outcrop on its factory floor.")
	verify(source_posts == 2 and first.foundations.size() == 4 and first.part_kits.P.foundation == 20,
		"Four aligned foundations and the remaining carried parts retain the finite native kit.")
	var has_belt := false
	for child in example.world.transmission_presenter.get_children():
		if child.get_meta("kind", "") == "belt_span":
			has_belt = true
	verify(has_belt, "The confirmed transmission presenter draws the shaft span.")
	verify(not first.powered and example.step_button.disabled, "First lesson leaves the drive off.")
	example.set_lesson(1)
	var running: Dictionary = example.model.projection()
	verify(running.powered and not example.step_button.disabled, "Drive lesson starts the actual waterwheel.")
	var belt: Dictionary = running.belt_spans.values()[0]
	var moving_shaft := str(belt.from)
	var start: Dictionary = running.transmission_parts[moving_shaft]
	var end: Dictionary = running.transmission_parts[str(belt.to)]
	var rate: Dictionary = running.motion[moving_shaft]
	verify(start.axis == 2 and end.axis == 2 and start.center == [4, 4, 4] and end.center == [8, 4, 4],
		"The working example's one-tile shaft axles cross its +X material path.")
	verify(rate.state == "rotating" and rate.numerator < 0 and rate.denominator > 0,
		"The confirmed -Z shaft rotation moves the belt top toward the press.")
	example.world._process(0.05)
	verify(example.world.transmission_presenter.visual_rotation(moving_shaft) != 0.0,
		"The example animates the belt from its confirmed native shaft rate.")
	var before_step: int = running.revision
	example._step()
	verify(example.model.projection().revision > before_step and example.ticks == 1, "One example step advances its native clock.")
	var saw_belt_blank := false
	for turn in range(64):
		var current: Dictionary = example.model.projection()
		for slot: Variant in current.belt_spans.values()[0].slots:
			if slot is Dictionary and int(slot.get("raw", 0)) > 0:
				saw_belt_blank = true
		if saw_belt_blank:
			break
		example._step()
	verify(saw_belt_blank, "A real collected blank enters the illustrated shaft-driven belt before the lesson reset.")
	example.set_lesson(2)
	var working: Dictionary = example.model.projection()
	verify(working.stock.held > 0 and example.ticks > 0, "The work lesson contains an actual in-progress lot.")
	example.set_lesson(3)
	var full: Dictionary = example.model.projection()
	verify(full.stock.output > 0 and full.stock.held > 0 and not example.recover_button.disabled,
		"The blocked lesson has a finished plate and retained work.")
	example._recover()
	var resumed: Dictionary = example.model.projection()
	verify(resumed.inventories.P == 1 and resumed.stock.source <= full.stock.source,
		"Retrieving the plate credits only the example and resumes its clock.")
	verify(player.checkpoint() == original, "Lesson setup, ticks and retrieval do not mutate the player's native state.")
	example.queue_free()
	var ok := failures == 0 and checks >= 16
	print("NATIVE_EXAMPLE_%s %d" % ["PASS" if ok else "FAIL", checks])
	quit(0 if ok else 1)
