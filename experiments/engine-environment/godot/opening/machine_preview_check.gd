extends SceneTree
## Presentation controls with invented observations. No authority or desktop.
const Opening = preload("res://opening/opening.gd")
const SharedOpening = preload("res://opening/shared_opening.gd")

class PointerView extends Opening:
	var pointer_clear := true
	var target := Vector2i(1, 2)
	var part_target: Array = [4, 8, 12]
	var options_hovered := false
	var catalog_visible := false
	var issued: Array = []
	func _preview_pointer_clear() -> bool:
		return pointer_clear
	func _machine_preview_cell() -> Vector2i:
		return target
	func _pointed_screen_position() -> Vector2:
		return Vector2.ZERO
	func _transmission_center(_screen: Vector2) -> Array:
		return part_target.duplicate()
	func _pointer_over_placement_options() -> bool:
		return options_hovered
	func _catalog_open() -> bool:
		return catalog_visible
	func issue(action: Dictionary) -> Dictionary:
		issued.append(action.duplicate(true))
		return {"accepted": false, "reason": "fixture_only"}

class SharedPointerView extends SharedOpening:
	var pointer_clear := true
	var target := Vector2i(1, 2)
	var part_target: Array = [4, 8, 12]
	var options_hovered := false
	var catalog_visible := false
	var issued: Array = []
	func _preview_pointer_clear() -> bool:
		return pointer_clear
	func _machine_preview_cell() -> Vector2i:
		return target
	func _pointed_screen_position() -> Vector2:
		return Vector2.ZERO
	func _transmission_center(_screen: Vector2) -> Array:
		return part_target.duplicate()
	func _pointer_over_placement_options() -> bool:
		return options_hovered
	func _catalog_open() -> bool:
		return catalog_visible
	func issue(action: Dictionary) -> Dictionary:
		issued.append(action.duplicate(true))
		return {"accepted": false, "reason": "fixture_only"}

class MarkerView extends Opening:
	var pointed := Vector2.ZERO
	func _ready() -> void:
		set_process(false)
	func _update_camera() -> void:
		pass
	func _pointed_screen_position() -> Vector2:
		return pointed

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
	if node.name.begins_with("PortArrow"):
		return []
	var result: Array = []
	if node is MeshInstance3D:
		result.append({"pose": pose, "bounds": node.mesh.get_aabb(),
			"vertices": hash(node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])})
	for child in node.get_children():
		if child is Node3D:
			result.append_array(geometry(child, pose * child.transform))
	return result

func check_preview_nodes(node: Node, material: StandardMaterial3D) -> void:
	verify(not node is CollisionObject3D and not node is CollisionShape3D
		and (not node is Label3D or node.name == "MaterialPortLabel"),
		"Preview assembly contains no pick collider or unrelated floating machine label.")
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
	# Native belts use shaft spans now; only placeable machines have forms.
	for kind in ["collector", "processor", "wheel"]:
		for axis in range(3):
			assembly_cases += 1
			view.mode = kind
			var target_cell := Vector2i(0, 1) if kind == "collector" else Vector2i(1, 2)
			view.target = target_cell
			view.transmission_controls.selected_axis = ["x", "y", "z"][axis]
			var actual_axis: int = 2 if kind == "belt" else axis
			var level: int = view.wheel_level if kind == "wheel" else 0
			var height: float = level * Opening.Geometry.HEIGHT_STEP
			view.state.entities = {"placed": {"kind": kind, "axis": actual_axis,
				"cell": [target_cell.x, target_cell.y], "level": level}}
			view._rebuild_machines()
			var expected: Node3D = view.machine_root.get_child(0)
			view.state.entities.clear()
			var before: Dictionary = view.state.duplicate(true)
			var plinth := expected.get_node_or_null("Plinth") as MeshInstance3D
			var material: Material = plinth.material_override if plinth != null else null
			var color: Color = material.albedo_color if material != null else Color.WHITE
			var old_rotor: Node3D = view.wheel_rotor
			view._refresh_machine_preview()
			verify(view.machine_preview.visible and view.machine_preview.position == Vector3(
				target_cell.x * Opening.PITCH, height, target_cell.y * Opening.PITCH),
				"The fitted preview uses the target square and the common construction height.")
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
			view.target = Vector2i(0, 0) if kind == "collector" else Vector2i(2, 3)
			view._refresh_machine_preview()
			verify((view.machine_preview.get_child(0).get_instance_id() != child_id if kind == "collector"
				else view.machine_preview.get_child(0).get_instance_id() == child_id)
				and view.machine_preview.position == Vector3(view.target.x * Opening.PITCH, height,
					view.target.y * Opening.PITCH),
				"The collector rebuilds for its source-facing cell while other previews reuse their cached assembly.")
			verify(view.state == before and view.model == null and view.actor_world == null
				and view.request_sequence == 0 and view.pending_link.is_empty() and view.selected.is_empty(),
				"The preview leaves projection, requests, selection and authority untouched.")
			view.target = target_cell
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

func check_inspection_cursor(view) -> void:
	view.state = observation()
	view.hover = MeshInstance3D.new()
	view.add_child(view.hover)
	view.hover_cell = Vector2i.ZERO
	var before: Dictionary = view.state.duplicate(true)
	view.mode = "inspect"
	view._update_cursor()
	verify(not view.hover.visible,
		"Inspecting empty ground does not draw a filled construction tile.")
	view.mode = "belt"
	view._update_cursor()
	verify(view.hover.visible and view.machine_preview != null and view.machine_preview.visible,
		"Selecting a carried machine keeps its deliberate construction previews.")
	view.state.entities = {"placed": {"kind": "belt", "cell": [0, 0], "level": 0}}
	view._update_cursor()
	verify(not view.hover.visible,
		"A confirmed machine clears the filled construction tile at its occupied square.")
	view.state.entities.clear()
	view.mode = "inspect"
	view._update_cursor()
	verify(not view.hover.visible and not view.machine_preview.visible,
		"Returning to inspection clears both construction previews.")
	view.mode = "belt"
	view.explanation_open = true
	view._update_cursor()
	verify(not view.hover.visible and not view.machine_preview.visible,
		"Help still hides construction previews.")
	verify(view.state == before and view.request_sequence == 0 and view.pending_link.is_empty(),
		"Cursor changes do not alter facts, submit requests or start links.")
	view.free()

func check_selection_marker() -> void:
	var view := MarkerView.new()
	view.legacy_fixture = true
	view._build_world()
	var marker: MeshInstance3D = view.selection_ring
	var covered := false
	for surface in range(marker.mesh.get_surface_count()):
		var arrays: Array = marker.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for triangle in range((indices.size() if not indices.is_empty() else vertices.size()) / 3):
			var a: int = indices[triangle * 3] if not indices.is_empty() else triangle * 3
			var b: int = indices[triangle * 3 + 1] if not indices.is_empty() else triangle * 3 + 1
			var c: int = indices[triangle * 3 + 2] if not indices.is_empty() else triangle * 3 + 2
			var pa := Vector2(vertices[a].x, vertices[a].z)
			var pb := Vector2(vertices[b].x, vertices[b].z)
			var pc := Vector2(vertices[c].x, vertices[c].z)
			var cross_a := (pb - pa).cross(-pa)
			var cross_b := (pc - pb).cross(-pb)
			var cross_c := (pa - pc).cross(-pc)
			if (cross_a >= -0.0001 and cross_b >= -0.0001 and cross_c >= -0.0001) \
					or (cross_a <= 0.0001 and cross_b <= 0.0001 and cross_c <= 0.0001):
				covered = true
	verify(not covered, "The selected-object marker has an open center rather than a pale filled square.")
	verify(marker.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"The selection outline does not cast a square shadow.")
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

func check_foundation_heights(view) -> void:
	view.state = observation()
	view.mode = "belt"
	view.state["foundations"] = {"surface": {"cell": [1, 2], "level": 2}}
	var before: Dictionary = view.state.duplicate(true)
	verify(view.foundation_level == 4, "The default factory floor can carry a whole-tile machine.")
	view._refresh_machine_preview()
	verify(view.machine_preview == null or not view.machine_preview.visible,
		"An intermediate access step cannot suggest a machine at a height that Host rejects.")
	verify(view._construction_level(Vector2i(1, 2)) == 2,
		"The view does not round a step into a floating machine floor.")
	view.state.foundations.surface.level = 4
	view._refresh_machine_preview()
	verify(view.machine_preview != null and view.machine_preview.visible
		and is_equal_approx(view.machine_preview.position.y, 1.65),
		"An independently built aligned floor restores the preview at its real 1.65 metre top.")
	view.state.foundations.surface.level = 2
	verify(view.state == before and view.request_sequence == 0 and view.model == null and view.actor_world == null,
		"Floor preview checks neither mutate the projection nor issue a request.")
	view.free()

func check_pointer_bounds() -> void:
	var view := MarkerView.new()
	root.add_child(view)
	var extent := view.get_viewport().get_visible_rect().size
	view.pointed = extent * 0.5
	verify(view._preview_pointer_clear(), "A pointer inside the game viewport can show a preview.")
	for point in [Vector2(-1, extent.y * 0.5), Vector2(extent.x, extent.y * 0.5),
			Vector2(extent.x * 0.5, -1), Vector2(extent.x * 0.5, extent.y)]:
		view.pointed = point
		verify(not view._preview_pointer_clear(), "A pointer outside any viewport edge cannot leave a clipped ghost in the game.")
	view.free()

func check_transmission_previews(view, shared: bool) -> void:
	var assets = load("res://opening/native_transmission_assets.gd")
	var presenter = load("res://opening/native_transmission_presenter.gd")
	view.state = observation()
	view.state.transmission_parts = {}
	view.state.part_kits.P.merge({"gear": 3, "shaft": 8, "foundation": 1})
	view.state.part_specifications = {"P": [
		{"kind": "gear", "teeth": 2, "half_span": 0, "count": 2},
		{"kind": "gear", "teeth": 4, "half_span": 0, "count": 1},
		{"kind": "shaft", "teeth": 0, "half_span": 2, "count": 8}]}
	view.transmission_controls = load("res://opening/native_transmission_controls.gd").new()
	view.add_child(view.transmission_controls)
	view.transmission_controls.configure(view)
	view.hover = MeshInstance3D.new()
	view.add_child(view.hover)
	var before: Dictionary = view.state.duplicate(true)
	for selection in [["gear", 2], ["gear", 4], ["place_shaft", 2]]:
		view.mode = "gear" if selection[0] == "gear" else "drive"
		view.transmission_controls.gear_teeth = selection[1]
		view.transmission_controls.choose_tool(selection[0])
		for axis in range(3):
			view.transmission_controls.selected_axis = ["x", "y", "z"][axis]
			view.part_target = [4, 8, 12]
			view._refresh_machine_preview()
			verify(view.machine_preview != null and view.machine_preview.visible,
				"A carried native cog or shaft has a three-dimensional placement preview.")
			if view.machine_preview == null or not view.machine_preview.visible:
				view.free()
				return
			verify(view.machine_preview.position.is_equal_approx(Opening.Geometry._mechanical_center(view.part_target))
				and view.machine_preview.basis.is_equal_approx(presenter.axis_basis(axis)),
				"Every preview axis uses the same native center, height origin and orientation as a placed part.")
			if selection[0] == "gear":
				var mesh: MeshInstance3D = view.machine_preview.get_child(0)
				verify(mesh.mesh == assets.complete_gear_mesh(Opening.PITCH / 2.0, selection[1], Color("687a7b"), Opening.PITCH),
					"Both cog sizes reuse the exact fitted mesh already used by confirmed cog batches.")
			else:
				var expected := Node3D.new()
				assets.shaft(expected, Opening.PITCH, Color("687a7b"))
				verify(geometry(view.machine_preview) == geometry(expected),
					"Shaft preview geometry matches the existing one-tile shaft asset.")
				expected.free()
			if axis == 0:
				check_preview_nodes(view.machine_preview, view.machine_preview_material)
			var child_id: int = view.machine_preview.get_child(0).get_instance_id()
			view.part_target = [-4, 12, 16]
			view._refresh_machine_preview()
			verify(view.machine_preview.get_child(0).get_instance_id() == child_id
				and view.machine_preview.position.is_equal_approx(Opening.Geometry._mechanical_center(view.part_target)),
				"Moving the target changes only the cached preview's position.")
			view._update_cursor()
			verify(not view.hover.visible, "Cog and shaft tools no longer expose the obsolete flat tile marker.")
	verify(view.state == before and view.issued.is_empty() and view.request_sequence == 0
		and view.model == null and view.actor_world == null,
		"Preview assembly changes no facts and owns no Model, actor controller or authority request.")
	view.options_hovered = true
	view.part_target = [400, 0, 400]
	view.transmission_controls.auto_height = false
	view.transmission_controls.gear_height = 16
	view._refresh_machine_preview()
	verify(view.machine_preview.position.is_equal_approx(Opening.Geometry._mechanical_center([-4, 16, 16])),
		"Editing height over the options panel retains the last pointed horizontal target.")
	view.options_hovered = false
	for gate in ["pointer_clear", "catalog_visible", "explanation_open", "startup_save_pending"]:
		view.set(gate, gate != "pointer_clear")
		view._refresh_machine_preview()
		verify(not view.machine_preview.visible, "An unavailable pointer, catalog, Help or startup barrier hides the part preview.")
		view.set(gate, gate == "pointer_clear")
	view.transmission_controls.choose_tool("gear")
	view.transmission_controls.gear_teeth = 2
	view.state.part_specifications.P[0].count = 0
	view._refresh_machine_preview()
	verify(not view.machine_preview.visible, "An exhausted selected cog specification cannot borrow another size's kit.")
	view.state.part_specifications.P[0].count = 2
	if shared:
		view.pending_actions = {"pending": {"action": {"action": "place_gear"}}}
		view._refresh_machine_preview()
		verify(not view.machine_preview.visible, "A pending shared mutation hides a speculative part preview.")
		view.pending_actions.clear()
		view.session.ready = false
		view._refresh_machine_preview()
		verify(not view.machine_preview.visible, "A disconnected shared view cannot retain its visible part preview.")
		view.session.ready = true
	view.mode = "foundation"
	view.transmission_controls.cancel()
	view._refresh_machine_preview()
	verify(view.machine_preview.visible and view.machine_preview.basis.is_equal_approx(Basis.IDENTITY),
		"Returning to a foundation removes the previous shaft-axis transform.")
	view.free()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_cmdline_user_args().has("--transmission-previews-only"):
		check_pointer_bounds()
		check_transmission_previews(PointerView.new(), false)
		var transmission_shared := SharedPointerView.new()
		transmission_shared.session = SessionStub.new()
		check_transmission_previews(transmission_shared, true)
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"observations": "invented", "desktop": "not_used", "mode": "transmission_previews"}))
		quit(1 if failed else 0)
		return
	if OS.get_cmdline_user_args().has("--selection-cursor-only"):
		check_inspection_cursor(PointerView.new())
		var cursor_shared := SharedPointerView.new()
		cursor_shared.session = SessionStub.new()
		check_inspection_cursor(cursor_shared)
		check_selection_marker()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"observations": "invented", "desktop": "not_used", "mode": "selection_cursor"}))
		quit(1 if failed else 0)
		return
	if OS.get_cmdline_user_args().has("--foundation-heights-only"):
		check_foundation_heights(PointerView.new())
		var floor_shared := SharedPointerView.new()
		floor_shared.session = SessionStub.new()
		check_foundation_heights(floor_shared)
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"observations": "invented", "desktop": "not_used", "mode": "foundation_heights"}))
		quit(1 if failed else 0)
		return
	var detached := Opening.new()
	verify(not detached._preview_pointer_clear(), "A detached view cannot query or invent a usable pointer.")
	detached.free()
	check_assemblies()
	check_gates(PointerView.new(), false)
	var shared := SharedPointerView.new()
	shared.session = SessionStub.new()
	check_gates(shared, true)
	check_inspection_cursor(PointerView.new())
	var cursor_shared := SharedPointerView.new()
	cursor_shared.session = SessionStub.new()
	check_inspection_cursor(cursor_shared)
	check_selection_marker()
	check_partial_drive_guidance()
	check_pointer_bounds()
	check_transmission_previews(PointerView.new(), false)
	var transmission_shared := SharedPointerView.new()
	transmission_shared.session = SessionStub.new()
	check_transmission_previews(transmission_shared, true)
	print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
		"assembly_cases": assembly_cases, "observations": "invented", "desktop": "not_used",
		"rendered_quality": "not_assessed"}))
	quit(1 if failed else 0)
