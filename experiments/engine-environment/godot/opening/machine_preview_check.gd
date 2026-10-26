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
var variant_cases := 0

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

func packed_geometry(node: Node3D, pose: Transform3D = Transform3D.IDENTITY) -> Array:
	if node.name.begins_with("PortArrow"):
		return []
	var result: Array = []
	if node is MeshInstance3D:
		var surfaces: Array = []
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			surfaces.append({"vertices": arrays[Mesh.ARRAY_VERTEX], "indices": arrays[Mesh.ARRAY_INDEX]})
		result.append({"pose": pose, "bounds": node.mesh.get_aabb(), "surfaces": surfaces})
	for child in node.get_children():
		if child is Node3D:
			result.append_array(packed_geometry(child, pose * child.transform))
	return result

func same_packed_geometry(baked: Node3D, live: Node3D) -> bool:
	var left: Array = packed_geometry(baked)
	var right: Array = packed_geometry(live)
	if left.size() != right.size():
		return false
	for index in left.size():
		var baked_pose: Transform3D = left[index].pose
		var live_pose: Transform3D = right[index].pose
		# Windows can retain subnormal coordinates in packed poses differently.
		if left[index].bounds != right[index].bounds \
				or baked_pose.origin.distance_squared_to(live_pose.origin) > 1e-12 \
				or baked_pose.basis.x.distance_squared_to(live_pose.basis.x) > 1e-12 \
				or baked_pose.basis.y.distance_squared_to(live_pose.basis.y) > 1e-12 \
				or baked_pose.basis.z.distance_squared_to(live_pose.basis.z) > 1e-12:
			return false
		var baked_surfaces: Array = left[index].surfaces
		var live_surfaces: Array = right[index].surfaces
		if baked_surfaces.size() != live_surfaces.size():
			return false
		for surface in baked_surfaces.size():
			if baked_surfaces[surface].indices != live_surfaces[surface].indices:
				return false
			var baked_vertices: PackedVector3Array = baked_surfaces[surface].vertices
			var live_vertices: PackedVector3Array = live_surfaces[surface].vertices
			if baked_vertices.size() != live_vertices.size():
				return false
			for vertex in baked_vertices.size():
				# Packed scene serialization differs from procedural generation by
				# subnormal vertex values on Windows. One micrometre still detects
				# a real part or placement change at this metre-scale worksite.
				if baked_vertices[vertex].distance_squared_to(live_vertices[vertex]) > 1e-12:
					return false
	return true

func wheel_surface_attributes(node: Node3D) -> Array:
	var result: Array = []
	if node is MeshInstance3D and not node.name.begins_with("PortArrow"):
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			result.append({"normals": arrays[Mesh.ARRAY_NORMAL],
				"tangents": arrays[Mesh.ARRAY_TANGENT], "uv": arrays[Mesh.ARRAY_TEX_UV]})
	for child in node.get_children():
		if child is Node3D:
			result.append_array(wheel_surface_attributes(child))
	return result

func same_wheel_surface_attributes(baked: Node3D, live: Node3D) -> bool:
	var left := wheel_surface_attributes(baked)
	var right := wheel_surface_attributes(live)
	if left.size() != right.size():
		return false
	for index in left.size():
		for channel in ["normals", "tangents", "uv"]:
			var first: Variant = left[index][channel]
			var second: Variant = right[index][channel]
			if first == null or second == null:
				if first != second:
					return false
				continue
			if first.size() != second.size():
				return false
			for entry in first.size():
				var difference: Variant = first[entry] - second[entry]
				if difference is Vector3 or difference is Vector2:
					if difference.length_squared() > 1e-10:
						return false
				elif absf(difference) > 1e-5:
					return false
	return true

func same_packed_geometry_unordered(baked: Node3D, live: Node3D) -> bool:
	# The collector swaps a source intake module in place. Mesh child order is
	# presentation-only; world transforms and every vertex still have to match.
	var left: Array = packed_geometry(baked)
	var right: Array = packed_geometry(live)
	if left.size() != right.size():
		return false
	var matched := {}
	for part in left:
		var found := false
		for index in right.size():
			if matched.has(index) or part.bounds != right[index].bounds:
				continue
			var pose: Transform3D = part.pose
			var other: Transform3D = right[index].pose
			if pose.origin.distance_squared_to(other.origin) > 1e-12 \
					or pose.basis.x.distance_squared_to(other.basis.x) > 1e-12 \
					or pose.basis.y.distance_squared_to(other.basis.y) > 1e-12 \
					or pose.basis.z.distance_squared_to(other.basis.z) > 1e-12:
				continue
			var surfaces: Array = part.surfaces
			var other_surfaces: Array = right[index].surfaces
			if surfaces.size() != other_surfaces.size():
				continue
			var same := true
			for surface in surfaces.size():
				if surfaces[surface].indices != other_surfaces[surface].indices:
					same = false
					break
				var vertices: PackedVector3Array = surfaces[surface].vertices
				var other_vertices: PackedVector3Array = other_surfaces[surface].vertices
				if vertices.size() != other_vertices.size():
					same = false
					break
				for vertex in vertices.size():
					if vertices[vertex].distance_squared_to(other_vertices[vertex]) > 1e-12:
						same = false
						break
				if not same:
					break
			if same:
				matched[index] = true
				found = true
				break
		if not found:
			return false
	return true

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
			if kind == "wheel":
				verify(view.machine_rotors[0].center == view.machine_root.transform * expected.transform * view.wheel_rotor.position,
					"A detached wheel records its culling center without querying a global transform.")
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
			verify((same_packed_geometry_unordered(view.machine_preview, expected) if kind == "collector"
				else same_packed_geometry(view.machine_preview, expected)),
				"Preview and placed assembly have identical meshes and local transforms for %s axis %d." % [kind, axis])
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

func check_packed_assemblies() -> void:
	var view := PointerView.new()
	view.state = observation()
	view.transmission_controls = ControlsStub.new()
	for kind in ["collector", "belt", "processor", "wheel"]:
		var path: String = "res://opening/assets/prebuilt-preview-" + kind + ".scn"
		var packed := load(path) as PackedScene
		verify(packed != null, "A prebuilt preview exists for %s." % kind)
		if packed == null:
			continue
		var source := packed.instantiate() as Node3D
		view.add_child(source)
		var expected := Node3D.new()
		var cell := [0, 1] if kind == "collector" else [1, 2]
		expected.position = view._cell_position(cell)
		view._assemble_machine(expected, {"kind": kind, "axis": 0, "tiles": 3,
			"rotation": 0, "cell": cell, "level": 0}, kind == "belt")
		if kind in ["collector", "processor"]:
			view._preview_port(expected, 0, kind == "collector")
		verify(same_packed_geometry(source, expected),
			"The baked %s preview keeps procedural mesh geometry and local transforms." % kind)
		view._style_machine_preview(source)
		check_preview_nodes(source, view.machine_preview_material)
		if kind != "belt":
			view.packed_preview_templates[kind] = packed
			view.packed_preview_nodes[kind] = source
			view.mode = kind
			view.target = Vector2i(cell[0], cell[1])
			view._refresh_machine_preview()
			verify(view.machine_preview == source and view.machine_preview.visible
				and same_packed_geometry(view.machine_preview, expected),
				"The native %s selection reuses its warmed preview without changing its form." % kind)
			check_preview_nodes(view.machine_preview, view.machine_preview_material)
			view.packed_preview_nodes.erase(kind)
			view._choose_machine_preview()
			view._refresh_machine_preview()
			verify(view.machine_preview != source and view.machine_preview.visible
				and same_packed_geometry(view.machine_preview, expected),
				"The native %s selection can also instantiate a baked preview." % kind)
			verify(view.state == observation() and view.model == null and view.request_sequence == 0,
				"The baked preview leaves %s authority unchanged." % kind)
		expected.free()
	view.free()

func check_variant_assemblies() -> void:
	var view := PointerView.new()
	view.state = observation()
	view.transmission_controls = ControlsStub.new()
	var cases: Array[Dictionary] = []
	for site in [0, 1]:
		for level in [0, 4, 8]:
			for axis in range(3):
				for facing in range(4):
					cases.append({"kind": "collector", "axis": axis, "tiles": 3,
						"rotation": facing, "cell": [0, site], "level": level})
	for axis in range(3):
		for facing in range(4):
			cases.append({"kind": "processor", "axis": axis, "tiles": 3,
				"rotation": facing, "cell": [1, 2], "level": 0})
	for axis in range(3):
		cases.append({"kind": "belt", "axis": axis, "tiles": 3,
			"rotation": 0, "cell": [1, 2], "level": 0})
		for tiles in range(3, Opening.BAKED_WHEEL_PREVIEW_MAX_TILES + 1):
			cases.append({"kind": "wheel", "axis": axis, "tiles": tiles,
				"rotation": 0, "cell": [1, 2], "level": 4})
		for tiles in [10, 16, 32, 4096]:
			cases.append({"kind": "wheel", "axis": axis, "tiles": tiles,
				"rotation": 0, "cell": [1, 2], "level": 4})
	for entity in cases:
		variant_cases += 1
		var kind: String = entity.kind
		var cell := Vector2i(entity.cell[0], entity.cell[1])
		var baked: Node3D
		if kind == "collector" and cell == Vector2i(0, 1) and entity.level == 0 \
				and entity.axis == 0 and entity.rotation == 0 \
				or kind == "processor" and entity.axis == 0 and entity.rotation == 0 \
				or kind == "belt" and entity.axis == 0 \
				or kind == "wheel" and entity.axis == 0 and entity.tiles == 3:
			baked = (load("res://opening/assets/prebuilt-preview-%s.scn" % kind) as PackedScene).instantiate() as Node3D
		else:
			baked = view._packed_machine_preview_variant(kind, entity.axis, entity.tiles,
				entity.rotation, cell, entity.level)
		var expected := Node3D.new()
		expected.position = view._cell_position(entity.cell) + Vector3.UP * entity.level * Opening.Geometry.HEIGHT_STEP
		view._assemble_machine(expected, entity, kind == "belt" and entity.axis == 0)
		if kind in ["collector", "processor"]:
			view._preview_port(expected, entity.rotation, kind == "collector")
		var same := baked != null and not view.preview_variant_pending and (
			same_packed_geometry_unordered(baked, expected) if kind == "collector"
			else same_packed_geometry(baked, expected))
		verify(same,
			"The %s preview variant preserves procedural geometry for axis %d, facing %d, size %d and site %s/%d." % [
				kind, entity.axis, entity.rotation, entity.tiles, str(cell), entity.level])
		if kind == "wheel" and entity.tiles > Opening.BAKED_WHEEL_PREVIEW_MAX_TILES:
			verify(baked != null and same_wheel_surface_attributes(baked, expected),
				"The large-wheel preview preserves normals, tangents and physical timber UVs.")
		if baked != null:
			view._style_machine_preview(baked)
			check_preview_nodes(baked, view.machine_preview_material)
			baked.free()
		expected.free()
	view.free()

func check_foundation_pool() -> void:
	var view := PointerView.new()
	view.state = observation()
	view.state.part_kits.P["foundation"] = 2
	view.transmission_controls = ControlsStub.new()
	var pooled := Node3D.new()
	view.add_child(pooled)
	view._assemble_foundation(pooled)
	view._style_machine_preview(pooled)
	view.packed_preview_nodes["foundation"] = pooled
	var expected := Node3D.new()
	view._assemble_foundation(expected)
	view.mode = "foundation"
	view.target = Vector2i(1, 2)
	var before: Dictionary = view.state.duplicate(true)
	view._refresh_machine_preview()
	verify(view.machine_preview == pooled and view.machine_preview.visible
		and geometry(view.machine_preview) == geometry(expected),
		"The native foundation preview reuses its warmed form.")
	check_preview_nodes(view.machine_preview, view.machine_preview_material)
	view.foundation_area_mode = true
	view.foundation_area_started = true
	view.foundation_area_start = Vector2i(1, 2)
	view.target = Vector2i(2, 3)
	view._refresh_machine_preview()
	verify(view.machine_preview == pooled and pooled.scale == Vector3(2, 1, 2)
		and is_equal_approx(pooled.position.x, 1.5 * Opening.PITCH)
		and is_equal_approx(pooled.position.z, 2.5 * Opening.PITCH),
		"The pooled foundation stretches across the selected grid area.")
	verify(view.state == before and view.model == null and view.request_sequence == 0,
		"The pooled foundation preview leaves construction authority untouched.")
	expected.free()
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

func _own_packed_preview(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		_own_packed_preview(child, root_node)

func _bake_packed_previews() -> void:
	# Explicit asset-generation mode. The ordinary check never writes source.
	var view := PointerView.new()
	view.state = observation()
	view.transmission_controls = ControlsStub.new()
	var results := {}
	for kind in ["collector", "belt", "processor", "wheel"]:
		var anchor := Node3D.new()
		anchor.name = "PreviewTemplate"
		var cell := [0, 1] if kind == "collector" else [1, 2]
		anchor.position = view._cell_position(cell)
		view._assemble_machine(anchor, {"kind": kind, "axis": 0, "tiles": 3,
			"rotation": 0, "cell": cell, "level": 0}, kind == "belt")
		if kind in ["collector", "processor"]:
			view._preview_port(anchor, 0, kind == "collector")
		view._style_machine_preview(anchor)
		anchor.position = Vector3.ZERO
		_own_packed_preview(anchor, anchor)
		var packed := PackedScene.new()
		var status := packed.pack(anchor)
		var path: String = "res://opening/assets/prebuilt-preview-" + kind + ".scn"
		if status == OK:
			status = ResourceSaver.save(packed, path,
				ResourceSaver.FLAG_BUNDLE_RESOURCES | ResourceSaver.FLAG_COMPRESS)
		results[kind] = {"status": status,
			"bytes": FileAccess.get_file_as_bytes(path).size() if status == OK else 0}
		anchor.free()
	view.free()
	print("PACKED_MACHINE_PREVIEWS " + JSON.stringify(results))
	quit(0 if results.values().all(func(row): return row.status == OK) else 1)

func _save_preview_variant(anchor: Node3D, path: String) -> Dictionary:
	anchor.name = "PreviewTemplate"
	_own_packed_preview(anchor, anchor)
	var packed := PackedScene.new()
	var status := packed.pack(anchor)
	if status == OK:
		# Share the rotor across axles and compress repeated sized geometry.
		var flags := ResourceSaver.FLAG_BUNDLE_RESOURCES
		if path.contains("prebuilt-preview-wheel-") or path.contains("prebuilt-preview-belt-axis-"):
			flags |= ResourceSaver.FLAG_COMPRESS
		status = ResourceSaver.save(packed, path, flags)
	var bytes := FileAccess.get_file_as_bytes(path).size() if status == OK else 0
	anchor.free()
	return {"status": status, "bytes": bytes}

func _bake_preview_variants() -> void:
	# Explicit asset-generation mode. The ordinary check never writes source.
	var view := PointerView.new()
	view.state = observation()
	view.transmission_controls = ControlsStub.new()
	var results := {}
	for site in [0, 1]:
		for level in [0, 4, 8]:
			var cell := [0, site]
			var anchor := Node3D.new()
			anchor.position = view._cell_position(cell) + Vector3.UP * level * Opening.Geometry.HEIGHT_STEP
			view._assemble_machine(anchor, {"kind": "collector", "axis": 0, "tiles": 3,
				"rotation": 0, "cell": cell, "level": level})
			var source := Node3D.new()
			for child in anchor.get_children():
				if child.name.begins_with("Source"):
					anchor.remove_child(child)
					source.add_child(child)
			view._style_machine_preview(source)
			var path: String = "res://opening/assets/prebuilt-preview-collector-source-%d-%d.scn" % [site, level]
			results[path] = _save_preview_variant(source, path)
			anchor.free()
	for axis in [1, 2]:
		var drive := Node3D.new()
		view._machine_drive_stub(drive, {"axis": axis}, true)
		view._style_machine_preview(drive)
		var drive_path: String = "res://opening/assets/prebuilt-preview-processor-drive-%d.scn" % axis
		results[drive_path] = _save_preview_variant(drive, drive_path)
		var belt := Node3D.new()
		belt.position = view._cell_position([1, 2])
		view._assemble_machine(belt, {"kind": "belt", "axis": axis, "tiles": 3,
			"rotation": 0, "cell": [1, 2], "level": 0})
		view._style_machine_preview(belt)
		belt.position = Vector3.ZERO
		var belt_path: String = "res://opening/assets/prebuilt-preview-belt-axis-%d.scn" % axis
		results[belt_path] = _save_preview_variant(belt, belt_path)
		var wheel := Node3D.new()
		view._assemble_machine(wheel, {"kind": "wheel", "axis": axis, "tiles": 3,
			"rotation": 0, "cell": [1, 2], "level": 4})
		var supports := Node3D.new()
		for child in wheel.get_children():
			if child.name != "WheelRotor":
				wheel.remove_child(child)
				supports.add_child(child)
		view._style_machine_preview(supports)
		var supports_path: String = "res://opening/assets/prebuilt-preview-wheel-support-%d.scn" % axis
		results[supports_path] = _save_preview_variant(supports, supports_path)
		wheel.free()
	for tiles in range(4, Opening.BAKED_WHEEL_PREVIEW_MAX_TILES + 1):
		var wheel := Node3D.new()
		view._assemble_machine(wheel, {"kind": "wheel", "axis": 0, "tiles": tiles,
			"rotation": 0, "cell": [1, 2], "level": 4})
		var rotor := wheel.get_node("WheelRotor") as Node3D
		wheel.remove_child(rotor)
		var rotor_part := Node3D.new()
		rotor_part.add_child(rotor)
		view._style_machine_preview(rotor_part)
		var rotor_path: String = "res://opening/assets/prebuilt-preview-wheel-rotor-%d.scn" % tiles
		results[rotor_path] = _save_preview_variant(rotor_part, rotor_path)
		wheel.free()
	view.free()
	var failures := results.values().filter(func(row: Dictionary): return row.status != OK)
	var total_bytes := 0
	for row in results.values():
		total_bytes += int(row.bytes)
	print("PACKED_PREVIEW_VARIANTS ", JSON.stringify({"count": results.size(),
		"total_bytes": total_bytes, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if OS.get_cmdline_user_args().has("--variant-assemblies-only"):
		check_variant_assemblies()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"variant_cases": variant_cases, "observations": "invented", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
	if OS.get_cmdline_user_args().has("--bake-packed-previews"):
		_bake_packed_previews()
		return
	if OS.get_cmdline_user_args().has("--bake-preview-variants"):
		_bake_preview_variants()
		return
	if OS.get_cmdline_user_args().has("--assemblies-only"):
		check_assemblies()
		print(JSON.stringify({"status": "fail" if failed else "pass", "checks": checks,
			"assembly_cases": assembly_cases, "observations": "invented", "desktop": "not_used"}))
		quit(1 if failed else 0)
		return
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
	check_packed_assemblies()
	check_variant_assemblies()
	check_foundation_pool()
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
		"assembly_cases": assembly_cases, "variant_cases": variant_cases,
		"observations": "invented", "desktop": "not_used",
		"rendered_quality": "not_assessed"}))
	quit(1 if failed else 0)
