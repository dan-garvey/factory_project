extends MenuButton
## View-local tools over confirmed native state. host.issue owns every request.
const Geometry = preload("res://opening/site_geometry.gd")

var selected_axis := "x"
var selected_link_axis := "z"
var gear_height := 0
var auto_height := true
var snapped_height := 0
var gear_teeth := 2
var shaft_half_span := 2
var active_tool := ""
var _belt_start: Dictionary = {}
var _host: WeakRef
var _axes: PopupMenu
var _heights: PopupMenu
var _sizes: PopupMenu
var _links: PopupMenu

func _init() -> void:
	text = "Mechanical options  [T]"
	var menu := get_popup()
	menu.add_radio_check_item("Place cogwheel", 1)
	menu.add_radio_check_item("Place shaft segment", 6)
	menu.add_radio_check_item("Place horizontal gearbox", 8)
	menu.add_radio_check_item("Place vertical gearbox", 9)
	menu.add_radio_check_item("Place encased chain drive", 10)
	menu.add_radio_check_item("Connect shafts with a belt  [Alt+3]", 7)
	menu.add_item("Leave transmission tools  [Esc]", 5)
	menu.add_separator()
	_axes = PopupMenu.new()
	_axes.name = "Axis"
	menu.add_child(_axes)
	for axis in ["X", "Y", "Z"]:
		_axes.add_radio_check_item(axis)
	_axes.id_pressed.connect(_axis_selected)
	menu.add_submenu_item("Axis: X", "Axis", 100)
	_heights = PopupMenu.new()
	_heights.name = "Height"
	menu.add_child(_heights)
	_heights.add_item("Lower one tile", 0)
	_heights.add_item("Raise one tile", 1)
	_heights.add_item("Follow pointed surface", 2)
	_heights.id_pressed.connect(_height_selected)
	menu.add_submenu_item("Placement height: Follow surface", "Height", 101)
	_sizes = PopupMenu.new()
	_sizes.name = "CogSize"
	menu.add_child(_sizes)
	_sizes.add_radio_check_item("Small cogwheel", 0)
	_sizes.add_radio_check_item("Large cogwheel", 1)
	_sizes.id_pressed.connect(_size_selected)
	menu.add_submenu_item("Cog size: Small", "CogSize", 102)
	_links = PopupMenu.new()
	_links.name = "ChainLinkAxis"
	menu.add_child(_links)
	for axis in ["X", "Y", "Z"]:
		_links.add_radio_check_item(axis)
	_links.id_pressed.connect(_link_axis_selected)
	menu.add_submenu_item("Chain link direction: Z", "ChainLinkAxis", 103)
	menu.id_pressed.connect(_tool_selected)
	menu.about_to_popup.connect(refresh)
	visible = false

func configure(host: Object) -> void:
	_host = weakref(host)
	refresh()

func cancel() -> void:
	active_tool = ""
	_belt_start.clear()
	refresh()

func clear_belt_selection() -> void:
	_belt_start.clear()

func settle_belt_selection(request: String, accepted: bool) -> void:
	if _belt_start.is_empty() or _belt_start.request != request:
		return
	if not accepted:
		_belt_start.clear()
		return
	_belt_start.pending = false
	_feedback("Move to the second parallel shaft and choose it within reach.", false)

func settle_belt_placement(request: String, accepted: bool, reason: String) -> void:
	if request.is_empty() or _belt_start.is_empty() or _belt_start.get("placement_request", "") != request:
		return
	_belt_start.erase("placement_request")
	if accepted or reason == "invalid_belt_selection":
		_belt_start.clear()

func choose_tool(tool: String) -> void:
	if tool not in ["", "gear", "place_shaft", "belt_span", "gearbox", "vertical_gearbox", "chain_drive"]:
		return
	_belt_start.clear()
	active_tool = tool
	if tool == "gearbox":
		selected_axis = "y"
	elif tool == "vertical_gearbox" and selected_axis == "y":
		selected_axis = "x"
	if selected_link_axis == selected_axis:
		selected_link_axis = "z" if selected_axis != "z" else "x"
	refresh()

func _tool_selected(id: int) -> void:
	var host: Object = _host.get_ref() if _host != null else null
	var mode: String = {1: "gear", 6: "drive", 7: "belt", 8: "gearbox",
		9: "vertical_gearbox", 10: "chain_drive", 5: "inspect"}.get(id, "")
	if host != null and host.has_method("_select_tool") and not mode.is_empty():
		host.call("_select_tool", mode)
	else:
		choose_tool({1: "gear", 6: "place_shaft", 7: "belt_span", 8: "gearbox",
			9: "vertical_gearbox", 10: "chain_drive"}.get(id, ""))
	var context := _context()
	if context.is_empty() or not context.usable:
		return
	_feedback({
		"gear": "Place a cogwheel: point at a floor or part face to choose a tile. Set axis or exact height here.",
		"place_shaft": "Place a shaft tile: point at a floor, part face or belt. Set axis or exact height here.",
		"gearbox": "Place a horizontal gearbox: its Y faces are closed and four side ports redirect rotation.",
		"vertical_gearbox": "Place a vertical gearbox: set its closed X or Z axis for vertical and side ports.",
		"chain_drive": "Place an encased chain case: its shafts use Axis and its chain links follow Link direction.",
		"belt_span": "Choose two parallel shafts within reach. The belt runs across their axle, straight or at 45 degrees.",
	}.get(active_tool, "Choose a construction tool or press E to open a machine."), false)

func _axis_selected(id: int) -> void:
	if id in [0, 1, 2]:
		selected_axis = ["x", "y", "z"][id]
		if active_tool == "gearbox":
			selected_axis = "y"
		elif active_tool == "vertical_gearbox" and selected_axis == "y":
			selected_axis = "x"
		if selected_link_axis == selected_axis:
			selected_link_axis = "z" if selected_axis != "z" else "x"
		refresh()

func _link_axis_selected(id: int) -> void:
	if id in [0, 1, 2]:
		var value: String = ["x", "y", "z"][id]
		if value != selected_axis:
			selected_link_axis = value
			refresh()

func _height_selected(id: int) -> void:
	if id == 2:
		auto_height = true
		refresh()
		return
	if id not in [0, 1]:
		return
	if auto_height:
		gear_height = snapped_height
		auto_height = false
	gear_height = clampi(gear_height + (-4 if id == 0 else 4), -Geometry.GRID_COORDINATE_LIMIT, Geometry.GRID_COORDINATE_LIMIT)
	refresh()

func _size_selected(id: int) -> void:
	if id in [0, 1]:
		gear_teeth = [2, 4][id]
		refresh()

func _context() -> Dictionary:
	if _host == null or not is_instance_valid(_host.get_ref()):
		return {}
	var host: Object = _host.get_ref()
	var snapshot: Variant = host.get("state")
	var actor: Variant = host.get("client")
	if host.get("legacy_fixture") != false or not snapshot is Dictionary or typeof(actor) != TYPE_STRING:
		return {}
	var options: Variant = snapshot.get("options")
	if not options is Dictionary or typeof(options.get("native")) != TYPE_BOOL or not options.native:
		return {}
	var world: Variant = snapshot.get("context")
	if typeof(world) != TYPE_STRING or world.is_empty() or actor.is_empty():
		return {}
	for key in ["actors", "entities", "transmission_parts", "part_specifications"]:
		if not snapshot.get(key) is Dictionary:
			return {}
	var kit: Variant = snapshot.part_specifications.get(actor, [])
	if not kit is Array:
		return {}
	var sample: Variant = snapshot.actors.get(actor, {})
	var usable: bool = sample is Dictionary and typeof(sample.get("ready")) == TYPE_BOOL and sample.ready
	usable = usable and host.get("explanation_open") == false and host.get("startup_save_pending") == false
	if host.has_method("_can_mutate"):
		usable = usable and host.call("_can_mutate") == true
	return {"host": host, "snapshot": snapshot, "world": world, "actor": actor, "kit": kit, "usable": usable}

func _count(context: Dictionary, kind: String, teeth: int, span: int) -> int:
	for entry: Variant in context.kit:
		if entry is Dictionary and entry.get("kind") == kind and typeof(entry.get("teeth")) == TYPE_INT and entry.teeth == teeth and typeof(entry.get("half_span")) == TYPE_INT and entry.half_span == span:
			var amount: Variant = entry.get("count")
			return amount if typeof(amount) == TYPE_INT and amount >= 0 else 0
	return 0

func refresh() -> void:
	var context := _context()
	visible = not context.is_empty()
	disabled = context.is_empty() or not context.usable
	if context.is_empty():
		return
	var gears := _count(context, "gear", gear_teeth, 0)
	var menu := get_popup()
	var gear_index := menu.get_item_index(1)
	menu.set_item_text(gear_index, "Place cogwheel  [Alt+1] · %d carried" % gears)
	menu.set_item_disabled(gear_index, gears == 0)
	var shaft_index := menu.get_item_index(6)
	var selected_shafts := _count(context, "shaft", 0, shaft_half_span)
	menu.set_item_text(shaft_index, "Place shaft  [Alt+2] · %d carried" % selected_shafts)
	menu.set_item_disabled(shaft_index, selected_shafts == 0)
	menu.set_item_checked(shaft_index, active_tool == "place_shaft")
	menu.set_item_checked(gear_index, active_tool == "gear")
	var belt_index := menu.get_item_index(7)
	var belts := _count(context, "belt", 0, 0)
	menu.set_item_text(belt_index, "Connect shafts with a belt  [Alt+3] · %d carried" % belts)
	menu.set_item_disabled(belt_index, belts == 0)
	menu.set_item_checked(belt_index, active_tool == "belt_span")

	for entry in [[8, "gearbox", "Horizontal gearbox  [Alt+4]"], [9, "vertical_gearbox", "Vertical gearbox  [Alt+5]"],
		[10, "chain_drive", "Encased chain drive  [Alt+6]"]]:
		var index: int = menu.get_item_index(entry[0])
		var amount: int = _count(context, entry[1], 0, 0)
		menu.set_item_text(index, "%s · %d carried" % [entry[2], amount])
		menu.set_item_disabled(index, amount == 0)
		menu.set_item_checked(index, active_tool == entry[1])
	menu.set_item_text(menu.get_item_index(100), "Axis [X]: " + selected_axis.to_upper())
	menu.set_item_text(menu.get_item_index(103), "Chain direction [Shift+X]: " + selected_link_axis.to_upper())
	menu.set_item_text(menu.get_item_index(101), "Height [Shift+PgUp/PgDn, Ctrl+Home]: %s" % ("Follow surface" if auto_height else "%d tiles" % (gear_height / 4)))
	menu.set_item_text(menu.get_item_index(102), "Cog size [K]: " + ("Small" if gear_teeth == 2 else "Large"))
	for index in range(2):
		var teeth: int = [2, 4][index]
		_sizes.set_item_checked(index, gear_teeth == teeth)
		_sizes.set_item_text(index, ("Small" if teeth == 2 else "Large") + " cogwheel · %d carried" % _count(context, "gear", teeth, 0))
	for index in range(3):
		_axes.set_item_checked(index, selected_axis == ["x", "y", "z"][index])
		_axes.set_item_disabled(index, (active_tool == "gearbox" and index != 1) or
			(active_tool == "vertical_gearbox" and index == 1))
		_links.set_item_checked(index, selected_link_axis == ["x", "y", "z"][index])
		_links.set_item_disabled(index, selected_axis == ["x", "y", "z"][index])
	var height: int = snapped_height if auto_height else gear_height
	_heights.set_item_disabled(0, height <= -Geometry.GRID_COORDINATE_LIMIT)
	_heights.set_item_disabled(1, height >= Geometry.GRID_COORDINATE_LIMIT)
	_heights.set_item_disabled(2, auto_height)
	text = {"gear": "Place cogwheel", "place_shaft": "Place shaft segment", "belt_span": "Connect shafts with belt",
		"gearbox": "Place horizontal gearbox", "vertical_gearbox": "Place vertical gearbox",
		"chain_drive": "Place encased chain drive"}.get(active_tool, "Mechanical options") + "  [T]"
	tooltip_text = "Axis %s · height %s. %d cogwheels and %d shafts carried." % [selected_axis.to_upper(), "follows surface" if auto_height else "%d tiles" % (gear_height / 4), gears, selected_shafts]

func _part(context: Dictionary, id: String) -> Dictionary:
	var value: Variant = context.snapshot.transmission_parts.get(id, context.snapshot.entities.get(id))
	if not value is Dictionary or typeof(value.get("generation")) != TYPE_INT or value.generation < 1:
		return {}
	return value

func _feedback(words: String, refused: bool = true) -> void:
	tooltip_text = words
	if _host != null and is_instance_valid(_host.get_ref()) and _host.get_ref().has_method("_message"):
		_host.get_ref().call("_message", words, refused)

func _submit(context: Dictionary, wire: Dictionary) -> Dictionary:
	# A queued reply is not native acceptance. Only the next confirmed state is
	# displayed; this method neither credits parts nor creates local geometry.
	var receipt: Dictionary = context.host.call("issue", wire)
	refresh()
	return receipt

func handle_world_click(center: Array, entity_id: String) -> bool:
	if active_tool.is_empty():
		return false
	# Even a refused active-tool click is consumed; it must not place an old tool.
	var context := _context()
	if context.is_empty() or not context.usable:
		_feedback("Wait for a ready native worksite before using transmission tools.")
		return true
	if active_tool in ["gear", "place_shaft", "gearbox", "vertical_gearbox", "chain_drive"]:
		var valid := center.size() == 3 and selected_axis in ["x", "y", "z"]
		for coordinate: Variant in center:
			valid = valid and typeof(coordinate) == TYPE_INT and coordinate >= -Geometry.GRID_COORDINATE_LIMIT and coordinate <= Geometry.GRID_COORDINATE_LIMIT and coordinate % 4 == 0
		if valid and not auto_height:
			valid = center[1] == gear_height
		var available := 0
		if active_tool == "gear":
			available = _count(context, "gear", gear_teeth, 0)
		elif active_tool == "place_shaft":
			available = _count(context, "shaft", 0, shaft_half_span)
		else:
			available = _count(context, active_tool, 0, 0)
		if not valid or available == 0:
			_feedback("Choose an available part at a whole-tile grid point on the shown height.")
			return true
		var wire: Dictionary
		if active_tool == "gear":
			wire = {"action": "place_gear", "center": center.duplicate(), "axis": selected_axis, "teeth": gear_teeth}
		elif active_tool == "place_shaft":
			wire = {"action": "place_shaft", "center": center.duplicate(), "axis": selected_axis, "half_span": shaft_half_span}
		else:
			wire = {"action": "place_relay", "kind": active_tool, "center": center.duplicate(), "axis": selected_axis}
			if active_tool == "chain_drive":
				wire["relay_axis"] = selected_link_axis
		_submit(context, wire)
		return true
	if active_tool == "belt_span":
		var shaft: Variant = context.snapshot.transmission_parts.get(entity_id, {})
		if not shaft is Dictionary or shaft.get("kind") != "shaft" or typeof(shaft.get("generation")) != TYPE_INT or shaft.generation < 1:
			_feedback("Choose a confirmed shaft.")
			return true
		if _belt_start.is_empty():
			var receipt := _submit(context, {"action": "select_belt_shaft", "entity": entity_id})
			var request: Variant = receipt.get("request")
			if (receipt.get("accepted", false) or receipt.get("queued", false)) and typeof(request) == TYPE_STRING and not request.is_empty():
				_belt_start = {"id": entity_id, "generation": shaft.generation, "world": context.world, "actor": context.actor, "request": request, "pending": not receipt.get("accepted", false)}
				_feedback("Waiting for the first shaft selection…" if _belt_start.pending else "Move to the second parallel shaft and choose it within reach.", false)
			return true
		if _belt_start.pending:
			_feedback("Waiting for the server to confirm the first shaft.", false)
			return true
		if not _belt_start.get("placement_request", "").is_empty():
			_feedback("Waiting for the server to decide on the belt.", false)
			return true
		var first: Variant = context.snapshot.transmission_parts.get(_belt_start.id, {})
		if context.world != _belt_start.world or context.actor != _belt_start.actor or not first is Dictionary or first.get("kind") != "shaft" or first.get("generation") != _belt_start.generation:
			_belt_start.clear()
			_feedback("The first shaft changed. Choose it again.")
			return true
		if entity_id == _belt_start.id:
			_feedback("Choose a different shaft for the other end.")
			return true
		var from: String = _belt_start.id
		var selection: String = _belt_start.request
		var receipt := _submit(context, {"action": "place_selected_belt_span", "from": from, "to": entity_id, "selection": selection})
		if receipt.get("accepted", false) or receipt.get("reason", "") == "invalid_belt_selection":
			_belt_start.clear()
		elif receipt.get("queued", false) and typeof(receipt.get("request")) == TYPE_STRING and not receipt.request.is_empty():
			_belt_start.placement_request = receipt.request
		return true
	var part := _part(context, entity_id)
	if part.is_empty():
		_feedback("Choose a confirmed machine, cogwheel or shaft.")
		return true
	return true
