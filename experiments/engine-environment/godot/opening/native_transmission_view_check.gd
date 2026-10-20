extends SceneTree
## Invented confirmed projections and a request sink, never a Model or game.
const Controls = preload("res://opening/native_transmission_controls.gd")
const Presenter = preload("res://opening/native_transmission_presenter.gd")
var checks := 0
var failures := 0

class HostStub extends RefCounted:
	var state: Dictionary
	var client := "P"
	var legacy_fixture := false
	var explanation_open := false
	var startup_save_pending := false
	var mutate_allowed := true
	var calls: Array = []
	var messages: Array = []
	func _can_mutate() -> bool:
		return mutate_allowed
	func issue(wire: Dictionary) -> Dictionary:
		calls.append(wire.duplicate(true))
		return {"queued": true, "accepted": false}
	func _message(words: String, _refused: bool) -> void:
		messages.append(words)

func verify(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("TRANSMISSION_VIEW_FAILURE: " + reason)

func fixture() -> Dictionary:
	return {"context": "helper-fixture", "options": {"native": true},
		"actors": {"P": {"ready": true}, "Q": {"ready": true}},
		"entities": {"wheel": {"kind": "wheel", "generation": 1, "center": [-4, 0, 4], "axis": 1}},
		"transmission_parts": {
			"a": {"kind": "gear", "generation": 2, "center": [-4, 4, 4], "axis": 1, "teeth": 2, "half_span": 0},
			"b": {"kind": "gear", "generation": 3, "center": [0, 4, 4], "axis": 1, "teeth": 2, "half_span": 0},
			"sx": {"kind": "shaft", "generation": 4, "center": [2, 0, 4], "axis": 0, "teeth": 0, "half_span": 2},
			"sy": {"kind": "shaft", "generation": 5, "center": [0, 2, 0], "axis": 1, "teeth": 0, "half_span": 2},
			"sz": {"kind": "shaft", "generation": 6, "center": [0, 0, 2], "axis": 2, "teeth": 0, "half_span": 2}},
		"part_specifications": {
			"P": [{"kind": "gear", "teeth": 2, "half_span": 0, "count": 2}, {"kind": "shaft", "teeth": 0, "half_span": 2, "count": 3}],
			"Q": [{"kind": "gear", "teeth": 2, "half_span": 0, "count": 0}, {"kind": "shaft", "teeth": 0, "half_span": 2, "count": 0}]},
		"parts": {"gear": 99, "shaft": 99}, "drive_links": [], "powered": false,
		"motion": {"a": {"state": "rotating", "numerator": 1, "denominator": 1},
			"b": {"state": "rotating", "numerator": -1, "denominator": 1},
			"sx": {"state": "unpowered", "numerator": 0, "denominator": 1},
			"sy": {"state": "rotating", "numerator": 1, "denominator": 1},
			"sz": {"state": "stalled", "numerator": 0, "denominator": 1}},
		"engagements": [{"a": "a", "b": "b", "kind": 0}]}

func _initialize() -> void:
	call_deferred("_run")

func _controls() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var view := Controls.new()
	view.configure(host)
	verify(view.visible and not view.disabled and "2 carried" in view.get_popup().get_item_text(0), "P sees its own finite kit.")
	view.get_popup().emit_signal("id_pressed", 1)
	var before: Dictionary = host.state.duplicate(true)
	var center := [-4, 4, 4]
	verify(view.handle_world_click(center, ""), "An active gear tool consumes its click.")
	verify(host.calls.back() == {"action": "place_gear", "center": [-4, 4, 4], "axis": "x", "teeth": 2}, "Gear placement delegates the exact integer center and specification.")
	verify(center == [-4, 4, 4] and host.state == before and "2 carried" in view.get_popup().get_item_text(0), "A queued response creates no speculative kit credit or geometry.")
	view._axes.emit_signal("id_pressed", 1)
	view._heights.emit_signal("id_pressed", 1)
	view.handle_world_click([0, 5, 4], "")
	verify(view.selected_axis == "y" and view.gear_height == 5 and host.calls.back() == {"action": "place_gear", "center": [0, 5, 4], "axis": "y", "teeth": 2}, "The axis and height menus affect only the explicit placement wire.")
	view._heights.emit_signal("id_pressed", 0)
	var sent: int = host.calls.size()
	for invalid in [[0.0, 4, 4], [true, 4, 4], [0, 4], [-9, 4, 4], [0, 3, 4], [0, 4, 17]]:
		verify(view.handle_world_click(invalid, ""), "Invalid active-tool coordinates are consumed.")
	verify(host.calls.size() == sent, "Malformed, off-plane and out-of-profile coordinates send no request.")
	host.client = "Q"
	view.refresh()
	verify(view.get_popup().is_item_disabled(0) and "0 carried" in view.get_popup().get_item_text(0), "Q never borrows P's aggregate parts.")
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "An empty current kit refuses without click fallthrough.")
	host.client = "P"
	for flag in ["explanation_open", "startup_save_pending"]:
		host.set(flag, true)
		view.refresh()
		verify(view.disabled and view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "Blocked view clicks are consumed without a request.")
		host.set(flag, false)
	host.mutate_allowed = false
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "The shared mutation barrier suppresses submission.")
	host.mutate_allowed = true
	host.state.actors.P.ready = false
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "An unready character cannot submit.")
	host.state.actors.P.ready = true
	host.state.part_specifications.erase("P")
	verify(view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "An absent actor kit does not use the compatibility alias.")
	host.state = fixture()
	view.choose_tool("shaft")
	view.handle_world_click([], "wheel")
	verify(host.calls.size() == sent, "The first shaft endpoint is view state only.")
	view.handle_world_click([], "a")
	verify(host.calls.back() == {"action": "connect_drive", "from": "wheel", "to": "a"}, "A shaft uses the two confirmed identifiers.")
	view.choose_tool("disconnect")
	view.handle_world_click([], "wheel")
	view.handle_world_click([], "a")
	verify(host.calls.back() == {"action": "disconnect_drive", "from": "wheel", "to": "a"}, "Disconnection delegates the existing finite-shaft command.")
	for change in ["generation", "world", "actor"]:
		host.client = "P"
		host.state = fixture()
		view.choose_tool("shaft")
		view.handle_world_click([], "wheel")
		if change == "generation":
			host.state.entities.wheel.generation = 9
		elif change == "world":
			host.state.context = "another-worksite"
		else:
			host.client = "Q"
		var count: int = host.calls.size()
		verify(view.handle_world_click([], "a") and host.calls.size() == count, "A stale endpoint, actor or world cannot complete an old pair.")
	host.client = "P"
	host.state = fixture()
	view.choose_tool("remove")
	view.handle_world_click([], "a")
	verify(host.calls.back() == {"action": "remove", "entity": "a"}, "Individual cog removal preserves its exact identifier.")
	view.handle_world_click([], "sy")
	verify(host.calls.back() == {"action": "remove", "entity": "sy"}, "An orphaned shaft remains selectable for removal.")
	sent = host.calls.size()
	verify(view.handle_world_click([], "wheel") and host.calls.size() == sent, "The transmission removal tool does not replace machine inspection.")
	view.choose_tool("gear")
	host.state.options.native = false
	view.refresh()
	verify(not view.visible and view.handle_world_click([0, 4, 4], "") and host.calls.size() == sent, "A missing native profile hides controls and consumes its stale active click.")
	view.cancel()
	verify(not view.handle_world_click([0, 4, 4], ""), "A cancelled tool returns normal input to the scene.")
	view.free()

func _part(view: Node3D, id: String) -> Node3D:
	for child in view.get_children():
		if child.get_meta("entity", "") == id:
			return child
	return null

func _marks(view: Node3D) -> int:
	var count := 0
	for child in view.get_children():
		if child.has_meta("from"):
			count += 1
	return count

func _presentation() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var before: Dictionary = host.state.duplicate(true)
	var view := Presenter.new()
	view.configure(host)
	var a := _part(view, "a")
	var b := _part(view, "b")
	verify(a != null and b != null and a.position.is_equal_approx(Vector3(-1.65, 2.15, 1.65)) and b.position.is_equal_approx(Vector3(0, 2.15, 1.65)), "Quarter-grid centers map to the declared world anchors.")
	verify(a.get_node("ConfirmedDirection").get_meta("sign") == 1 and b.get_node("ConfirmedDirection").get_meta("sign") == -1, "Opposite signed rates produce opposite direction marks without a phase clock.")
	verify(_marks(view) == 1, "Only the confirmed engagement produces a contact mark.")
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var firsts := [Vector3(0, 0.5, 1.65), Vector3(0, 0.5, 0), Vector3(0, 0.5, 0)]
	var lasts := [Vector3(1.65, 0.5, 1.65), Vector3(0, 2.15, 0), Vector3(0, 0.5, 1.65)]
	for index in range(3):
		var part := _part(view, ["sx", "sy", "sz"][index])
		var mesh: CylinderMesh = part.get_node("Shaft").mesh
		verify(part.basis.y.is_equal_approx(axes[index]) and is_equal_approx(part.basis.determinant(), 1.0), "Each shaft uses a proper axis basis, including the vertical case.")
		verify((part.position - part.basis.y * mesh.height / 2).is_equal_approx(firsts[index]) and (part.position + part.basis.y * mesh.height / 2).is_equal_approx(lasts[index]), "Shaft endpoints match independent literal world coordinates.")
	verify(not _part(view, "sz").has_node("ConfirmedDirection"), "Stalled state is not animated or advertised as rotation.")
	for child in view.get_children():
		if child.has_meta("entity"):
			var body: StaticBody3D = child.get_node("Pick")
			verify(body.collision_layer == 4 and body.collision_mask == 0 and body.get_meta("entity") == child.get_meta("entity"), "Pick geometry cannot become actor or machine collision authority.")
	var first_id: int = a.get_instance_id()
	view.refresh()
	verify(_part(view, "a").get_instance_id() == first_id and host.state == before and host.calls.is_empty(), "An unchanged refresh reuses geometry and changes no projection or request.")
	for axis in range(3):
		host.state.transmission_parts.a.axis = axis
		view.refresh()
		verify(_part(view, "a").basis.y.is_equal_approx(axes[axis]), "Gear planes follow all three confirmed axes.")
	host.state.engagements = []
	view.refresh()
	verify(_marks(view) == 0, "Proximity alone never invents engagement.")
	host.state.transmission_parts.bad = {"kind": "gear", "center": [0, 0, 0], "axis": true, "teeth": 2}
	view.refresh()
	verify(_part(view, "bad") == null, "Malformed axis data does not create pick geometry.")
	host.state.options.native = false
	view.refresh()
	verify(not view.visible and view.get_child_count() == 0, "A scripted projection cannot retain old native geometry.")
	view.free()

func _cache_regression() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var view := Presenter.new()
	view.configure(host)
	var first_id: int = _part(view, "a").get_instance_id()
	var pick_id: int = _part(view, "a").get_node("Pick").get_instance_id()
	view.refresh()
	verify(_part(view, "a").get_instance_id() == first_id and _part(view, "a").get_node("Pick").get_instance_id() == pick_id, "An unchanged refresh preserves both mesh subtree and pick-body identities.")
	host.state.parts.gear = 88
	view.refresh()
	verify(_part(view, "a").get_instance_id() == first_id, "An unrelated compatibility counter does not rebuild transmission geometry.")
	host.state.motion.a.numerator = -1
	view.refresh()
	verify(_part(view, "a").get_instance_id() != first_id and _part(view, "a").get_node("ConfirmedDirection").get_meta("sign") == -1, "Changed signed motion refreshes the confirmed direction mark.")
	host.state.motion.a.state = "unpowered"
	host.state.motion.a.numerator = 0
	view.refresh()
	verify(not _part(view, "a").has_node("ConfirmedDirection"), "Stopping confirmed motion removes the rotation indication.")
	host.state.transmission_parts.a.center = [-3, 4, 4]
	view.refresh()
	verify(_part(view, "a").position.is_equal_approx(Vector3(-1.2375, 2.15, 1.65)), "A changed center refreshes its world-space geometry.")
	first_id = _part(view, "a").get_instance_id()
	host.state.context = "another-context"
	view.refresh()
	verify(_part(view, "a").get_instance_id() != first_id, "A new confirmed context does not retain old pick identities.")
	host.state.engagements = []
	view.refresh()
	verify(_marks(view) == 0, "A changed engagement catalogue removes the old contact mark.")
	var before: Dictionary = host.state.duplicate(true)
	view.refresh()
	verify(host.state == before and host.calls.is_empty(), "Cache refresh reads do not mutate projection or submit a command.")
	view.free()

func _direction_basis() -> void:
	var host := HostStub.new()
	host.state = fixture()
	var view := Presenter.new()
	view.configure(host)
	for axis in range(3):
		host.state.transmission_parts.a.axis = axis
		host.state.transmission_parts.b.axis = axis
		view.refresh()
		for id in ["a", "b"]:
			var part := _part(view, id)
			var segment: MeshInstance3D = part.get_node("ConfirmedDirection").get_child(0)
			var radial := segment.position
			radial.y = 0
			var signed_normal: float = part.basis.y.dot((part.basis * radial.normalized()).cross(part.basis * segment.basis.y))
			var sign_value: int = host.state.motion[id].numerator
			verify(signed_normal * float(sign_value) > 0.9, "The actual direction arc follows signed right-hand rotation on every declared axis.")
	view.free()

func _run() -> void:
	if "--refresh-cache-only" in OS.get_cmdline_user_args():
		_cache_regression()
	elif "--direction-basis-only" in OS.get_cmdline_user_args():
		_direction_basis()
	else:
		_controls()
		_presentation()
	print("NATIVE_TRANSMISSION_VIEW_%s %d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
