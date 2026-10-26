extends SceneTree
## Synthetic projection unit test for the native-authoritative challenge presenter.

const Challenge = preload("res://opening/upstream_drive_challenge.gd")
var checks := 0
var failures := 0

class HostStub extends RefCounted:
	var state: Dictionary
	var client := "P"

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
	verify(challenge.evaluate().diagnostic_code == "missing_drive_shaft", "A disconnected machine asks for a physical drive connection.")

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
