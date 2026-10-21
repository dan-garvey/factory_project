extends SceneTree
## Presentation controls with invented observations. No authority or desktop.
const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")

class PointerView extends Opening:
	var pointer_clear := true
	var target := Vector2i(1, 2)
	func _preview_pointer_clear() -> bool:
		return pointer_clear
	func _machine_preview_cell() -> Vector2i:
		return target

class SharedPointerView extends SharedOpening:
	var pointer_clear := true
	var target := Vector2i(1, 2)
	func _preview_pointer_clear() -> bool:
		return pointer_clear
	func _machine_preview_cell() -> Vector2i:
		return target

class ControlsStub extends RefCounted:
	var selected_axis := "x"
	var active_tool := ""

class SessionStub extends RefCounted:
	var ready := true
	func is_ready() -> bool:
		return ready

var checks := 0
var failed := false
var assembly_cases := 0

func verify(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)

func observation(native: bool = true) -> Dictionary:
	return {"context": "fixture-context", "revision": 7, "order": 0,
		"options": {"physical": true, "native": native},
		"actors": {"P": {"ready": true, "position": [0.0, 0.9, 0.0]}},
		"entities": {}, "links": [], "drive_links": [], "inventories": {"P": 0},
		"stock": {"source": 16, "collector": 0, "belt": 0, "input": 0, "held": 0, "output": 0},
		"parts": {"collector": 1, "belt": 1, "processor": 1, "wheel": 1},
		"part_kits": {"P": {"collector": 1, "belt": 1, "processor": 1, "wheel": 1}}}

func geometry(node: Node3D, pose: Transform3D = Transform3D.IDENTITY) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result.append({"pose": pose, "bounds": node.mesh.get_aabb(),
			"vertices": hash(node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])})
	for child in node.get_children():
		if child is Node3D:
			result.append_array(geometry(child, pose * child.transform))
	return result

func check_preview_nodes(node: Node, material: StandardMaterial3D) -> void:
	verify(not node is CollisionObject3D and not node is CollisionShape3D and not node is Label3D,
		"Preview assembly contains neither a pick collider nor a floating machine label.")
	verify(node.get_script() == null and node.get_signal_connection_list("tree_entered").is_empty(),
		"Preview nodes have no scripts or input/authority callbacks.")
	if node is MeshInstance3D:
		verify(node.material_override == material,
			"Every preview mesh uses the same instance-only material override.")
		verify(node.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
			and node.material_override.albedo_color == Color(0.88, 0.75, 0.49, 0.32)
			and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"Preview surfaces are neutral translucent amber without cast shadows.")
	for child in node.get_children():
		check_preview_nodes(child, material)

func check_assemblies() -> void:
	var view := PointerView.new()
	view.state = observation()
	view.transmission_controls = ControlsStub.new()
	view.machine_root = Node3D.new()
	view.wheel_rotor = Node3D.new()
	var live_rotor := view.wheel_rotor
	for kind in ["collector", "belt", "processor", "wheel"]:
		for axis in range(3):
			assembly_cases += 1
			view.mode = kind
			view.transmission_controls.selected_axis = ["x", "y", "z"][axis]
			var actual_axis: int = 2 if kind == "belt" else axis
			view.state.entities = {"placed": {"kind": kind, "axis": actual_axis, "cell": [-1, -1]}}
			var before: Dictionary = view.state.duplicate(true)
			view._rebuild_machines()
			var expected: Node3D = view.machine_root.get_child(0)
			var plinth := expected.get_node_or_null("Plinth") as MeshInstance3D
			var material: Material = plinth.material_override if plinth != null else null
			var color: Color = material.albedo_color if material != null else Color.WHITE
			var old_rotor: Node3D = view.wheel_rotor
			view._refresh_machine_preview()
			verify(view.machine_preview.visible and view.machine_preview.position == Vector3(1.65, 0, 3.3),
				"The fitted preview uses the literal target grid square and physical pitch.")
			verify(geometry(view.machine_preview) == geometry(expected),
				"Preview and placed assembly have identical meshes and local transforms for %s axis %d." % [kind, axis])
			if plinth != null:
				verify(view.machine_preview.get_node("Plinth").mesh == plinth.mesh,
					"The preview reuses the actual cached machined plinth mesh.")
			verify(view.wheel_rotor == old_rotor and (material == null or (material.albedo_color == color
				and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)),
				"Preview creation preserves the placed wheel target and opaque shared surface.")
			check_preview_nodes(view.machine_preview, view.machine_preview_material)
			var child_id := view.machine_preview.get_child(0).get_instance_id()
			view.target = Vector2i(2, 3)
			view._refresh_machine_preview()
			verify(view.machine_preview.get_child(0).get_instance_id() == child_id
				and view.machine_preview.position == Vector3(3.3, 0, 4.95),
				"Pointer motion moves the cached assembly without rebuilding it.")
			verify(view.state == before and view.model == null and view.actor_world == null
				and view.request_sequence == 0 and view.pending_link.is_empty() and view.selected.is_empty(),
				"The preview leaves projection, requests, selection and authority untouched.")
			view.target = Vector2i(1, 2)
	view.machine_root.free()
	live_rotor.free()
	view.free()

func check_gates(view, shared: bool) -> void:
	view.state = observation()
	view.mode = "belt"
	view._refresh_machine_preview()
	verify(view.machine_preview != null and view.machine_preview.visible, "A ready view can show its carried machine form.")
	var before: Dictionary = view.state.duplicate(true)
	view.pointer_clear = false
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "Hovering interface controls hides the form.")
	view.pointer_clear = true
	view.explanation_open = true
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "Help hides the form.")
	view.explanation_open = false
	for tool in ["inspect", "flow", "drive", "gear", "unknown"]:
		view.mode = tool
		view._refresh_machine_preview()
		verify(not view.machine_preview.visible, "Non-machine tools have no machine preview.")
	view.mode = "belt"
	for cell in [Vector2i(-250001, 0), Vector2i(250001, 0), Vector2i(0, -250001), Vector2i(0, 250001)]:
		view.target = cell
		view._refresh_machine_preview()
		verify(not view.machine_preview.visible, "Cells outside the native coordinate bound hide the form.")
	view.target = Vector2i(1, 2)
	view.state.entities = {"existing": {"kind": "collector", "cell": [1, 2]}}
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "An occupied square has no overlapping machine form.")
	view.state.entities = {}
	view.state.part_kits.P.belt = 0
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "An exhausted individual kit hides the form.")
	view.state.part_kits.P.belt = 1
	view.state.actors.P.ready = false
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "An unready physical actor hides the form.")
	view.state.actors.P.ready = true
	view.startup_save_pending = true
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "A startup save barrier hides the form.")
	view.startup_save_pending = false
	view.legacy_fixture = true
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "The legacy fixture keeps its original cursor.")
	view.legacy_fixture = false
	view.transmission_controls = ControlsStub.new()
	view.transmission_controls.active_tool = "shaft"
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "The native transmission tool takes precedence.")
	view.transmission_controls.active_tool = ""
	view.transmission_controls.selected_axis = "invalid"
	view.mode = "collector"
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "An unknown axis cannot invent an orientation.")
	view.transmission_controls.selected_axis = "z"
	view.mode = "belt"
	if shared:
		view.pending_actions = {"old-request": {"action": {"action": "place"}}}
		view._refresh_machine_preview()
		verify(not view.machine_preview.visible, "An unsettled shared request hides the form.")
		view.pending_actions = {}
		view.session.ready = false
		view._refresh_machine_preview()
		verify(not view.machine_preview.visible, "A disconnected view hides even its retained snapshot form.")
		view.session.ready = true
	view._refresh_machine_preview()
	verify(view.machine_preview.visible and view.state == before,
		"Restored readiness reuses the form without changing the observation.")
	view.state.options.native = false
	view.transmission_controls = null
	view._refresh_machine_preview()
	verify(view.machine_preview.visible, "The physical historical profile uses its original shared part schema.")
	view.state.parts.belt = 0
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "The historical physical part count also gates visibility.")
	view.free()

func check_partial_drive_guidance() -> void:
	var view := Opening.new()
	view.state = observation()
	view.state.entities = {"wheel": {"kind": "wheel"}, "collector": {"kind": "collector"},
		"belt": {"kind": "belt"}, "press": {"kind": "processor"}}
	view.state.links = [["collector", "belt"], ["belt", "press"]]
	view.state.power_enabled = true
	view.state.powered = true
	view.state.motion = {"collector": {"state": "rotating"}, "belt": {"state": "unpowered"},
		"press": {"state": "unpowered"}}
	view.state.stock.output = 0
	view.state.stock.held = 0
	view.selected = "belt"
	var kinds := {"wheel": true, "collector": true, "belt": true, "processor": true}
	var step: Dictionary = view._guided_step(kinds)
	verify(step.tool == "drive" and "each machine" in step.text,
		"A partly powered line still asks the player to connect every machine.")
	verify("Bring rotation" in view._inspection_hint(),
		"Inspecting an unpowered belt does not borrow the collector's rotation.")
	view.state.motion.belt.state = "rotating"
	view.state.motion.press.state = "rotating"
	step = view._guided_step(kinds)
	verify(step.tool != "drive", "A fully rotating line no longer asks for drive connections.")
	view.free()

func _initialize() -> void:
	var detached := Opening.new()
	verify(not detached._preview_pointer_clear(), "A detached view cannot query or invent a usable pointer.")
	detached.free()
	check_assemblies()
	check_gates(PointerView.new(), false)
	var shared := SharedPointerView.new()
	shared.session = SessionStub.new()
	check_gates(shared, true)
	check_partial_drive_guidance()
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"assembly_cases": assembly_cases, "observations": "invented", "desktop": "not_used",
		"rendered_quality": "not_assessed"}))
	quit(1 if failed else 0)
