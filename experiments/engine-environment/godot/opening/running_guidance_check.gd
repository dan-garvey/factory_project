extends SceneTree
## Isolated profile-specific inspector advice; no Model, input or game startup.
const Opening = preload("res://opening/opening.gd")

var checks := 0
var failed := false

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func fixture() -> Dictionary:
	return {"options": {"native": false}, "powered": false, "power_enabled": true,
		"entities": {"collector": {"kind": "collector"}, "belt": {"kind": "belt"},
			"press": {"kind": "processor"}}, "links": [],
		"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
		"remaining": 0}

func _initialize() -> void:
	var cases := [
		{"selected": "collector", "links": [], "pair": "Collector → Belt"},
		{"selected": "belt", "links": [], "pair": "Collector → Belt"},
		{"selected": "belt", "links": [["collector", "belt"]], "pair": "Belt → Press"},
		{"selected": "press", "links": [], "pair": "Belt → Press"}]
	for native_profile in [false, true]:
		for powered in [false, true]:
			for item in cases:
				var view := Opening.new()
				view.state = fixture()
				view.state.options.native = native_profile
				view.state.powered = powered
				view.selected = item.selected
				view.state.links = item.links.duplicate(true)
				var before: Dictionary = view.state.duplicate(true)
				var hint: String = view._inspection_hint()
				verify(hint.contains("[F]") and hint.contains(item.pair),
					"Missing-link advice identifies the existing material tool and correct endpoints.")
				verify(hint.contains("Stop") == (powered and not native_profile),
					"Only a powered historical scripted profile requires stopping before linking.")
				verify(view.state == before and view.model == null and view.request_sequence == 0,
					"Inspecting an invented projection changes no state, request or authority.")
				view.free()
	var view := Opening.new()
	view.legacy_fixture = true
	view.state = fixture()
	view.state.powered = true
	view.selected = "belt"
	verify(view._inspection_hint().contains("Stop [Space]"),
		"The explicit legacy fixture retains its actual drive key.")
	view.state.options.native = true
	view.legacy_fixture = false
	view.state.power_enabled = false
	verify(view._inspection_hint().contains("Drive switched off") and not view._inspection_hint().contains("Stop"),
		"An already switched-off native drive is described without a stop instruction.")
	view.state.stock.output = 1
	view.selected = "press"
	verify(view._inspection_hint().contains("[R]"),
		"A ready product retains priority over connection advice.")
	view.free()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"scope": "native and historical scripted inspector advice", "desktop": "not_used"}))
	quit(1 if failed else 0)
