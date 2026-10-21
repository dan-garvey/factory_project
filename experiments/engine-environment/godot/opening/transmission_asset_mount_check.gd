extends SceneTree
## Exact proposed presenter mount over invented read-only native facts.
const Presenter = preload("res://opening/native_transmission_presenter.gd")
var checks := 0
var failed := false

class HostStub extends RefCounted:
	var state: Dictionary = {}
	func _can_present_confirmed_motion() -> bool:
		return true

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func part(view: Node, id: String) -> Node3D:
	for child in view.get_children():
		if child.get_meta("entity", "") == id:
			return child
	return null

func count_role(node: Node, role: String) -> int:
	var count := 1 if node.get_meta("asset_role", "") == role else 0
	if count == 1 and node is MultiMeshInstance3D:
		count = node.multimesh.instance_count
	for child in node.get_children():
		count += count_role(child, role)
	return count

func _initialize() -> void:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for axis in range(3):
		var host := HostStub.new()
		host.state = {"context": "mount-fixture", "options": {"native": true}, "entities": {},
			"transmission_parts": {
				"gear": {"kind": "gear", "center": [-4, 1, 8], "axis": axis, "teeth": 2, "generation": 1},
				"shaft": {"kind": "shaft", "center": [0, 1, 8], "axis": axis, "half_span": 2, "generation": 2}},
			"motion": {"gear": {"state": "rotating", "numerator": 1, "denominator": 1},
				"shaft": {"state": "rotating", "numerator": -1, "denominator": 1}}, "engagements": []}
		var before: Dictionary = host.state.duplicate(true)
		var view := Presenter.new()
		view.configure(host)
		var gear := part(view, "gear")
		var shaft := part(view, "shaft")
		verify(gear != null and shaft != null, "The real presenter mounts both exact confirmed parts.")
		if gear == null or shaft == null:
			view.free()
			continue
		verify(count_role(gear, "GearTooth") == 16 and count_role(gear, "GearSpoke") == 4,
			"The real gear path uses the fitted asset rather than the predecessor disk/two tabs.")
		verify(count_role(shaft, "ShaftCollar") == 2 and shaft.has_node("Keyway"),
			"The real shaft path composes fitted collars with the existing motion keyway.")
		var gear_pick: StaticBody3D = gear.get_node("Pick")
		var shaft_pick: StaticBody3D = shaft.get_node("Pick")
		var gear_shape: CylinderShape3D = gear_pick.get_child(0).shape
		var shaft_shape: CylinderShape3D = shaft_pick.get_child(0).shape
		verify(gear_pick.collision_layer == 4 and gear_pick.collision_mask == 0
			and gear_pick.get_meta("entity") == "gear" and is_equal_approx(gear_shape.radius, 0.928125)
			and is_equal_approx(gear_shape.height, 0.24), "The original gear pick identity and literal cylinder are unchanged.")
		verify(shaft_pick.collision_layer == 4 and shaft_pick.collision_mask == 0
			and is_equal_approx(shaft_shape.radius, 0.08) and is_equal_approx(shaft_shape.height, 1.65),
			"The original shaft pick envelope is unchanged.")
		view.advance_visual_motion(0.1)
		verify(gear.position == Vector3(-1.65, 0.9125, 3.3) and shaft.position == Vector3(0, 0.9125, 3.3)
			and gear.basis.y.is_equal_approx(axes[axis]) and shaft.basis.y.is_equal_approx(axes[axis]),
			"Fitted meshes turn within the existing confirmed centers and axes.")
		verify(is_equal_approx(view.visual_angle("gear"), 0.08) and is_equal_approx(view.visual_angle("shaft"), -0.08)
			and host.state == before, "The assembly seam retains signed cosmetic motion without changing host facts.")
		view.free()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"scope": "proposed asset mount with invented facts", "native_gameplay": "not_run", "desktop": "not_used"}))
	quit(1 if failed else 0)
