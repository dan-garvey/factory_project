extends Node3D
## Confirmed-projection presenter and failure diagnostics for the post-shift
## upstream-drive engineering problem. Reads only host.state; never owns a
## second World, speculative inventory or separate progression clock.

const Geometry = preload("res://opening/site_geometry.gd")

const FIRST_TARGET := 4
const FINAL_TARGET := 8
const DEFAULT_WHEEL_CELL := Vector2i(-2, 0)

var host: Object
var target_wheel_cell := DEFAULT_WHEEL_CELL
var _cached_key: Array = []


func configure(owner_host: Object, wheel_cell: Vector2i = DEFAULT_WHEEL_CELL) -> void:
	host = owner_host
	target_wheel_cell = wheel_cell
	name = "UpstreamDriveChallenge"
	refresh()


func set_target_wheel_cell(wheel_cell: Vector2i) -> void:
	target_wheel_cell = wheel_cell
	refresh()


func _native_enabled() -> bool:
	if host == null or not (host.get("state") is Dictionary) or bool(host.get("legacy_fixture")):
		return false
	var options: Variant = host.state.get("options", {})
	return options is Dictionary and options.get("native", false) == true


func _active_actor() -> String:
	if host == null:
		return "P"
	var actor: Variant = host.get("client")
	return actor if actor is String and not actor.is_empty() else "P"


func _int_or(value: Variant, fallback: int = 0) -> int:
	return value if typeof(value) == TYPE_INT else fallback


func _spare_count(state: Dictionary, actor: String, kind: String) -> int:
	var specs: Variant = state.get("part_specifications", {})
	if specs is Dictionary and specs.has(actor) and specs[actor] is Array:
		var total := 0
		for item: Variant in specs[actor]:
			if item is Dictionary and item.get("kind") == kind and typeof(item.get("count")) == TYPE_INT:
				total += int(item.count)
		return total
	var kits: Variant = state.get("part_kits", {})
	if kits is Dictionary and kits.has(actor) and kits[actor] is Dictionary:
		var entry: Variant = kits[actor].get(kind, 0)
		return int(entry) if typeof(entry) == TYPE_INT else 0
	return 0


func evaluate() -> Dictionary:
	var actor := _active_actor()
	var unavailable := {
		"phase": "unavailable",
		"actor": actor,
		"products": 0,
		"first_target": FIRST_TARGET,
		"target": FINAL_TARGET,
		"wheel_cell": [target_wheel_cell.x, target_wheel_cell.y],
		"actual_wheel_cell": [],
		"collector_row": -999,
		"source_at_target": false,
		"power_enabled": false,
		"machines_placed": 0,
		"rotating_machines": 0,
		"machines_running": false,
		"machine_rates": {},
		"placed_gears": 0,
		"placed_shafts": 0,
		"spare_gears": 0,
		"spare_shafts": 0,
		"has_external_mesh": false,
		"arrangement": "none",
		"diagnostic_code": "not_available",
		"diagnostic_text": "Native worksite authority is unavailable.",
		"tradeoff_text": "",
	}
	if not _native_enabled():
		return unavailable
	var state: Dictionary = host.state
	var inventories: Variant = state.get("inventories", {})
	var entities: Variant = state.get("entities", {})
	var motion: Variant = state.get("motion", {})
	var transmission: Variant = state.get("transmission_parts", {})
	if not (inventories is Dictionary and entities is Dictionary and motion is Dictionary and transmission is Dictionary):
		return unavailable
	if not inventories.has(actor) or typeof(inventories[actor]) != TYPE_INT:
		return unavailable
	var products: int = int(inventories[actor])
	if products < 0:
		return unavailable

	var actual_wheel_cell: Array = []
	var wheel_id := ""
	var collector_row := -999
	var machines_placed := 0
	var rotating_machines := 0
	var all_machines_on_target_row := true
	var machine_rates := {}
	var any_stalled := false

	for id: Variant in motion.keys():
		var m_entry: Variant = motion[id]
		if m_entry is Dictionary and m_entry.get("state") == "stalled":
			any_stalled = true

	for id: Variant in entities.keys():
		var part: Variant = entities[id]
		if not (part is Dictionary):
			return unavailable
		var kind: Variant = part.get("kind", "")
		if typeof(kind) != TYPE_STRING:
			return unavailable
		var cell: Variant = part.get("cell", [])
		if kind == "wheel":
			if not (cell is Array and cell.size() == 2 and typeof(cell[0]) == TYPE_INT and typeof(cell[1]) == TYPE_INT):
				return unavailable
			actual_wheel_cell = [int(cell[0]), int(cell[1])]
			wheel_id = str(id)
		elif kind in ["collector", "belt", "processor"]:
			machines_placed += 1
			if cell is Array and cell.size() == 2 and typeof(cell[1]) == TYPE_INT:
				var row_z := int(cell[1])
				if kind == "collector":
					collector_row = row_z
				if row_z != target_wheel_cell.y:
					all_machines_on_target_row = false
			else:
				all_machines_on_target_row = false
			if not motion.has(id) or not (motion[id] is Dictionary):
				return unavailable
			var m: Dictionary = motion[id]
			var m_state: Variant = m.get("state", "")
			if typeof(m_state) != TYPE_STRING:
				return unavailable
			if m_state == "rotating":
				rotating_machines += 1
			machine_rates[str(id)] = {
				"state": str(m_state),
				"numerator": _int_or(m.get("numerator"), 0),
				"denominator": _int_or(m.get("denominator"), 1),
			}

	var placed_gears := 0
	var placed_shafts := 0

	for id: Variant in transmission.keys():
		var t_part: Variant = transmission[id]
		if not (t_part is Dictionary):
			return unavailable
		var t_kind: Variant = t_part.get("kind", "")
		if t_kind == "gear":
			placed_gears += 1
		elif t_kind == "shaft":
			placed_shafts += 1
		else:
			return unavailable

	var has_external_mesh := false
	var engagements: Variant = state.get("engagements", [])
	if engagements is Array:
		for edge: Variant in engagements:
			if edge is Dictionary and _int_or(edge.get("kind"), -1) == 0:
				has_external_mesh = true

	var wheel_coupled := false
	if not wheel_id.is_empty():
		var drive_links: Variant = state.get("drive_links", [])
		if drive_links is Array:
			for pair: Variant in drive_links:
				if pair is Array and wheel_id in pair:
					wheel_coupled = true
		if engagements is Array:
			for edge: Variant in engagements:
				if edge is Dictionary and (edge.get("a") == wheel_id or edge.get("b") == wheel_id):
					wheel_coupled = true

	var links_count := 0
	var links: Variant = state.get("links", [])
	if links is Array:
		links_count = links.size()

	var source_at_target: bool = (
		actual_wheel_cell.size() == 2
		and int(actual_wheel_cell[0]) == target_wheel_cell.x
		and int(actual_wheel_cell[1]) == target_wheel_cell.y
	)
	var machines_running: bool = machines_placed == 3 and rotating_machines == 3
	var power_enabled: bool = state.get("power_enabled", false) == true
	var spare_gears: int = _spare_count(state, actor, "gear")
	var spare_shafts: int = _spare_count(state, actor, "shaft")

	var phase := "ready"
	if products < FIRST_TARGET:
		phase = "first_shift"
	elif not source_at_target:
		phase = "move_source"
	elif not machines_running:
		phase = "restore_drive"
	elif products < FINAL_TARGET:
		phase = "deliver_more"

	var arrangement := "none"
	if source_at_target and machines_running:
		if all_machines_on_target_row:
			arrangement = "relocated_line"
		elif has_external_mesh and collector_row != target_wheel_cell.y:
			arrangement = "geared_transfer"
		else:
			arrangement = "partial"

	var tradeoff_text := (
		"Recover held material before moving a stocked line, or keep the machines in place and bridge the rows with cogs and shafts. "
		+ "Rotational rate does not alter processing speed or yield in this prototype."
	)

	var diagnostic_code := "challenge_complete"
	var diagnostic_text := "Upstream drive verified: all three machines rotate from cell [%d, %d] and %d / %d plates are in cargo." % [
		target_wheel_cell.x, target_wheel_cell.y, products, FINAL_TARGET
	]

	if phase == "first_shift":
		diagnostic_code = "complete_first_shift"
		diagnostic_text = "Complete the basic four-plate shift first (%d / %d plates collected)." % [products, FIRST_TARGET]
	elif phase == "move_source":
		if not wheel_id.is_empty() and wheel_coupled:
			diagnostic_code = "disconnect_source_shaft"
			diagnostic_text = "Disconnect the waterwheel's drive shaft, remove the waterwheel, and rebuild it at the upstream race [%d, %d]." % [
				target_wheel_cell.x, target_wheel_cell.y
			]
		else:
			diagnostic_code = "relocate_wheel"
			diagnostic_text = "Place the waterwheel on the upstream stream connection at cell [%d, %d]." % [
				target_wheel_cell.x, target_wheel_cell.y
			]
	elif phase == "restore_drive":
		if any_stalled:
			diagnostic_code = "stalled_transmission"
			diagnostic_text = "Transmission stalled: remove the conflicting parallel shaft or gear loop so each machine has a single consistent ratio."
		elif machines_placed < 3:
			diagnostic_code = "missing_machines"
			diagnostic_text = "Rebuild all three production machines (%d / 3 placed) and reinsert any recovered raw or partial work lots." % machines_placed
		elif links_count < 2:
			diagnostic_code = "missing_material_links"
			diagnostic_text = "Connect the Collector -> Belt -> Press material ports (%d / 2 belt links connected)." % links_count
		elif not wheel_coupled:
			diagnostic_code = "missing_drive_shaft"
			diagnostic_text = "Drive train incomplete (%d shafts placed): couple the upstream waterwheel and all three machines with finite shafts." % placed_shafts
		elif not power_enabled:
			diagnostic_code = "drive_switched_off"
			diagnostic_text = "Drive is switched off: press Start drive [P] near the waterwheel to power the transmission."
		else:
			diagnostic_code = "missing_drive_shaft"
			diagnostic_text = "Collector, Belt and Press must all receive rotating power from the upstream waterwheel at [%d, %d]." % [
				target_wheel_cell.x, target_wheel_cell.y
			]
	elif phase == "deliver_more":
		diagnostic_code = "producing_plates"
		if arrangement == "geared_transfer":
			diagnostic_text = "Geared transfer active (processing rate unchanged): collect %d / %d plates from the Press." % [
				products, FINAL_TARGET
			]
		elif arrangement == "relocated_line":
			diagnostic_text = "Relocated upstream line active (%d cogs spare): collect %d / %d plates from the Press." % [
				spare_gears, products, FINAL_TARGET
			]
		else:
			diagnostic_text = "Upstream drive running: collect %d / %d plates from the Press." % [products, FINAL_TARGET]

	return {
		"phase": phase,
		"actor": actor,
		"products": products,
		"first_target": FIRST_TARGET,
		"target": FINAL_TARGET,
		"wheel_cell": [target_wheel_cell.x, target_wheel_cell.y],
		"actual_wheel_cell": actual_wheel_cell,
		"collector_row": collector_row,
		"source_at_target": source_at_target,
		"power_enabled": power_enabled,
		"machines_placed": machines_placed,
		"rotating_machines": rotating_machines,
		"machines_running": machines_running,
		"machine_rates": machine_rates,
		"placed_gears": placed_gears,
		"placed_shafts": placed_shafts,
		"spare_gears": spare_gears,
		"spare_shafts": spare_shafts,
		"has_external_mesh": has_external_mesh,
		"arrangement": arrangement,
		"diagnostic_code": diagnostic_code,
		"diagnostic_text": diagnostic_text,
		"tradeoff_text": tradeoff_text,
	}


func goal_text() -> String:
	var report := evaluate()
	var phase := str(report.get("phase", "unavailable"))
	if phase in ["unavailable", "first_shift"]:
		return ""
	var header := "Upstream drive · %d / %d plates" % [int(report.get("products", 0)), FINAL_TARGET]
	return header + "\n" + str(report.get("diagnostic_text", ""))


func refresh() -> void:
	if not _native_enabled():
		visible = false
		_cached_key = []
		for child in get_children():
			remove_child(child)
			child.free()
		return
	visible = true
	var report := evaluate()
	var state: Dictionary = host.state
	var next_key := [
		state.get("context", ""),
		target_wheel_cell.x,
		target_wheel_cell.y,
		report.get("phase", ""),
		report.get("source_at_target", false),
		report.get("machines_running", false),
	]
	if next_key == _cached_key and get_child_count() > 0:
		return
	_cached_key = next_key.duplicate(true)
	for child in get_children():
		remove_child(child)
		child.free()

	var marker := Node3D.new()
	marker.name = "UpstreamRaceMarker"
	marker.position = Vector3(
		float(target_wheel_cell.x) * Geometry.PITCH,
		0.04,
		float(target_wheel_cell.y) * Geometry.PITCH
	)
	marker.set_meta("target_wheel_cell", [target_wheel_cell.x, target_wheel_cell.y])
	marker.set_meta("phase", str(report.get("phase", "")))

	var pad := MeshInstance3D.new()
	pad.name = "RacePad"
	var box := BoxMesh.new()
	box.size = Vector3(1.24, 0.06, 1.24)
	var mat := StandardMaterial3D.new()
	if bool(report.get("machines_running", false)) and bool(report.get("source_at_target", false)):
		mat.albedo_color = Color("3a8f5b")
	elif bool(report.get("source_at_target", false)):
		mat.albedo_color = Color("b88b28")
	else:
		mat.albedo_color = Color("2d728f")
	mat.roughness = 0.65
	box.material = mat
	pad.mesh = box
	marker.add_child(pad)

	var post := MeshInstance3D.new()
	post.name = "BearingPost"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.11
	cyl.height = 0.46
	cyl.material = mat
	post.mesh = cyl
	post.position = Vector3(0.0, 0.23, 0.0)
	marker.add_child(post)

	add_child(marker)
