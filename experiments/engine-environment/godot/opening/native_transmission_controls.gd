extends MenuButton
## View-local tools over confirmed native state. host.issue owns every request.
const Geometry = preload("res://opening/site_geometry.gd")

var selected_axis := "x"
var gear_height := 0
var gear_teeth := 2
var shaft_half_span := 2
var active_tool := ""
var _host: WeakRef
var _first: Dictionary = {}
var _axes: PopupMenu
var _heights: PopupMenu
var _sizes: PopupMenu
var _lengths: PopupMenu
var _legacy_links: PopupMenu

func _init() -> void:
	text = "Cogwheels and shafts…"
	var menu := get_popup()
	menu.add_radio_check_item("Place cogwheel", 1)
	menu.add_radio_check_item("Place shaft segment", 6)
	menu.add_radio_check_item("Remove cogwheel or shaft", 4)
	menu.add_item("Leave transmission tools", 5)
	_legacy_links = PopupMenu.new()
	_legacy_links.name = "EndpointLinks"
	menu.add_child(_legacy_links)
	_legacy_links.add_radio_check_item("Connect two endpoints", 2)
	_legacy_links.add_radio_check_item("Disconnect two endpoints", 3)
	_legacy_links.id_pressed.connect(_tool_selected)
	menu.add_submenu_item("Advanced endpoint links", "EndpointLinks", 104)
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
	_heights.add_item("Lower one quarter step", 0)
	_heights.add_item("Raise one quarter step", 1)
	_heights.id_pressed.connect(_height_selected)
	menu.add_submenu_item("Gear height: 0", "Height", 101)
	_sizes = PopupMenu.new()
	_sizes.name = "CogSize"
	menu.add_child(_sizes)
	_sizes.add_radio_check_item("Small cogwheel", 0)
	_sizes.add_radio_check_item("Large cogwheel", 1)
	_sizes.id_pressed.connect(_size_selected)
	menu.add_submenu_item("Cog size: Small", "CogSize", 102)
	_lengths = PopupMenu.new()
	_lengths.name = "ShaftLength"
	menu.add_child(_lengths)
	_lengths.add_radio_check_item("Short shaft", 0)
	_lengths.add_radio_check_item("Long shaft", 1)
	_lengths.id_pressed.connect(_length_selected)
	menu.add_submenu_item("Shaft length: Short", "ShaftLength", 103)
	menu.id_pressed.connect(_tool_selected)
	menu.about_to_popup.connect(refresh)
	visible = false

func configure(host: Object) -> void:
	_host = weakref(host)
	refresh()

func cancel() -> void:
	active_tool = ""
	_first.clear()
	refresh()

func choose_tool(tool: String) -> void:
	if tool not in ["", "gear", "shaft", "disconnect", "remove", "place_shaft"]:
		return
	active_tool = tool
	_first.clear()
	if tool == "place_shaft":
		var context := _context()
		if not context.is_empty() and _count(context, "shaft", 0, shaft_half_span) == 0:
			var other := 4 if shaft_half_span == 2 else 2
			if _count(context, "shaft", 0, other) > 0:
				shaft_half_span = other
	refresh()

func _tool_selected(id: int) -> void:
	choose_tool({1: "gear", 2: "shaft", 3: "disconnect", 4: "remove", 6: "place_shaft"}.get(id, ""))
	var context := _context()
	if context.is_empty() or not context.usable:
		return
	_feedback({
		"gear": "Place a cogwheel at the highlighted point. Set axis and height in this menu.",
		"place_shaft": "Place a shaft segment at the highlighted point. Set its axis, height and length in this menu.",
		"shaft": "Choose a machine or cogwheel, then its partner. The amber ring marks the first endpoint.",
		"disconnect": "Choose the two endpoints of the shaft link to disconnect.",
		"remove": "Choose a cogwheel or shaft to remove."
	}.get(active_tool, "Choose a construction tool or Inspect."), false)

func _axis_selected(id: int) -> void:
	if id in [0, 1, 2]:
		selected_axis = ["x", "y", "z"][id]
		_first.clear()
		refresh()

func _height_selected(id: int) -> void:
	gear_height = clampi(gear_height + (-1 if id == 0 else 1), -Geometry.GRID_COORDINATE_LIMIT, Geometry.GRID_COORDINATE_LIMIT)
	refresh()

func _size_selected(id: int) -> void:
	if id in [0, 1]:
		gear_teeth = [2, 4][id]
		refresh()

func _length_selected(id: int) -> void:
	if id in [0, 1]:
		shaft_half_span = [2, 4][id]
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

func _shaft_count(context: Dictionary) -> int:
	var total := 0
	for entry: Variant in context.kit:
		if entry is Dictionary and entry.get("kind") == "shaft" and typeof(entry.get("teeth")) == TYPE_INT and entry.teeth == 0 \
			and typeof(entry.get("half_span")) == TYPE_INT and entry.half_span > 0 \
			and typeof(entry.get("count")) == TYPE_INT and entry.count > 0:
			total += entry.count
	return total

func refresh() -> void:
	var context := _context()
	visible = not context.is_empty()
	disabled = context.is_empty() or not context.usable
	if context.is_empty():
		_first.clear()
		return
	var gears := _count(context, "gear", gear_teeth, 0)
	var shafts := _shaft_count(context)
	var menu := get_popup()
	var gear_index := menu.get_item_index(1)
	menu.set_item_text(gear_index, "Place cogwheel · %d carried" % gears)
	menu.set_item_disabled(gear_index, gears == 0)
	_legacy_links.set_item_text(_legacy_links.get_item_index(2), "Connect two endpoints · %d carried" % shafts)
	_legacy_links.set_item_disabled(_legacy_links.get_item_index(2), shafts == 0)
	var shaft_index := menu.get_item_index(6)
	var selected_shafts := _count(context, "shaft", 0, shaft_half_span)
	menu.set_item_text(shaft_index, "Place shaft segment · %d carried" % selected_shafts)
	menu.set_item_disabled(shaft_index, shafts == 0)
	menu.set_item_checked(shaft_index, active_tool == "place_shaft")
	menu.set_item_checked(gear_index, active_tool == "gear")
	menu.set_item_checked(menu.get_item_index(4), active_tool == "remove")
	_legacy_links.set_item_checked(_legacy_links.get_item_index(2), active_tool == "shaft")
	_legacy_links.set_item_checked(_legacy_links.get_item_index(3), active_tool == "disconnect")
	menu.set_item_text(menu.get_item_index(100), "Axis: " + selected_axis.to_upper())
	menu.set_item_text(menu.get_item_index(101), "Placement height: %d quarter steps" % gear_height)
	menu.set_item_text(menu.get_item_index(102), "Cog size: " + ("Small" if gear_teeth == 2 else "Large"))
	menu.set_item_text(menu.get_item_index(103), "Shaft length: " + ("Short" if shaft_half_span == 2 else "Long"))
	for index in range(2):
		var teeth: int = [2, 4][index]
		_sizes.set_item_checked(index, gear_teeth == teeth)
		_sizes.set_item_text(index, ("Small" if teeth == 2 else "Large") + " cogwheel · %d carried" % _count(context, "gear", teeth, 0))
		var span: int = [2, 4][index]
		_lengths.set_item_checked(index, shaft_half_span == span)
		_lengths.set_item_text(index, ("Short" if span == 2 else "Long") + " shaft · %d carried" % _count(context, "shaft", 0, span))
	for index in range(3):
		_axes.set_item_checked(index, selected_axis == ["x", "y", "z"][index])
	_heights.set_item_disabled(0, gear_height <= -Geometry.GRID_COORDINATE_LIMIT)
	_heights.set_item_disabled(1, gear_height >= Geometry.GRID_COORDINATE_LIMIT)
	text = {"gear": "Place cogwheel", "place_shaft": "Place shaft segment", "shaft": "Connect shaft", "disconnect": "Disconnect shaft", "remove": "Remove transmission"}.get(active_tool, "Cogwheels and shafts…")
	tooltip_text = "Axis %s · placement height %d quarter steps. %d cogwheels and %d shafts carried." % [selected_axis.to_upper(), gear_height, gears, shafts]
	if not context.usable:
		_first.clear()

func _part(context: Dictionary, id: String) -> Dictionary:
	var value: Variant = context.snapshot.transmission_parts.get(id, context.snapshot.entities.get(id))
	if not value is Dictionary or typeof(value.get("generation")) != TYPE_INT or value.generation < 1:
		return {}
	return value

func pending_endpoint() -> Dictionary:
	# A view of the existing first-click stamp, never a reach or engagement verdict.
	if active_tool not in ["shaft", "disconnect"] or _first.is_empty():
		return {}
	var context := _context()
	if context.is_empty() or not context.usable:
		return {}
	if active_tool == "shaft" and _shaft_count(context) == 0:
		return {}
	var part := _part(context, _first.id)
	if _first.world != context.world or _first.actor != context.actor or part.is_empty() or part.generation != _first.generation:
		return {}
	var center: Variant = part.get("center")
	var axis: Variant = part.get("axis")
	var kind: Variant = part.get("kind")
	if not center is Array or center.size() != 3 or typeof(axis) != TYPE_INT or axis not in [0, 1, 2] or kind not in ["collector", "belt", "processor", "wheel", "gear"]:
		return {}
	for coordinate: Variant in center:
		if typeof(coordinate) != TYPE_INT or coordinate < -1048576 or coordinate > 1048576:
			return {}
	var teeth: Variant = part.get("teeth", 0)
	if kind == "gear" and (typeof(teeth) != TYPE_INT or teeth < 1 or teeth > 256):
		return {}
	return {"id": _first.id, "center": center.duplicate(), "axis": axis, "kind": kind, "teeth": teeth}

func _feedback(words: String, refused: bool = true) -> void:
	tooltip_text = words
	if _host != null and is_instance_valid(_host.get_ref()) and _host.get_ref().has_method("_message"):
		_host.get_ref().call("_message", words, refused)

func _submit(context: Dictionary, wire: Dictionary) -> void:
	# A queued reply is not native acceptance. Only the next confirmed state is
	# displayed; this method neither credits parts nor creates local geometry.
	context.host.call("issue", wire)
	refresh()

func handle_world_click(center: Array, entity_id: String) -> bool:
	if active_tool.is_empty():
		return false
	# Even a refused active-tool click is consumed; it must not place an old tool.
	var context := _context()
	if context.is_empty() or not context.usable:
		_first.clear()
		_feedback("Wait for a ready native worksite before using transmission tools.")
		return true
	if active_tool in ["gear", "place_shaft"]:
		var valid := center.size() == 3 and selected_axis in ["x", "y", "z"]
		for coordinate: Variant in center:
			valid = valid and typeof(coordinate) == TYPE_INT and coordinate >= -Geometry.GRID_COORDINATE_LIMIT and coordinate <= Geometry.GRID_COORDINATE_LIMIT
		if valid:
			valid = center[1] == gear_height
		var available := _count(context, "gear", gear_teeth, 0) if active_tool == "gear" else _count(context, "shaft", 0, shaft_half_span)
		if not valid or available == 0:
			_feedback("Choose an available part at an integer grid point on the selected height.")
			return true
		var wire := {"action": "place_gear", "center": center.duplicate(), "axis": selected_axis, "teeth": gear_teeth} if active_tool == "gear" else {"action": "place_shaft", "center": center.duplicate(), "axis": selected_axis, "half_span": shaft_half_span}
		_submit(context, wire)
		return true
	var part := _part(context, entity_id)
	if part.is_empty():
		_first.clear()
		_feedback("Choose a confirmed machine, cogwheel or shaft.")
		return true
	if active_tool == "remove":
		if not context.snapshot.transmission_parts.has(entity_id):
			_feedback("This tool removes a cogwheel or shaft; use the inspector for machines.")
		else:
			_submit(context, {"action": "remove", "entity": entity_id})
		return true
	if part.get("kind") == "shaft" or (active_tool == "shaft" and _shaft_count(context) == 0):
		_first.clear()
		_feedback("Choose two machine or cogwheel endpoints and carry an available shaft.")
		return true
	if _first.is_empty():
		_first = {"world": context.world, "actor": context.actor, "id": entity_id, "generation": part.generation}
		_feedback("Choose the second machine or cogwheel endpoint.", false)
		return true
	var original := _part(context, _first.id)
	if _first.world != context.world or _first.actor != context.actor or original.is_empty() or original.generation != _first.generation:
		_first.clear()
		_feedback("The first endpoint changed. Choose both endpoints again.")
		return true
	if _first.id == entity_id:
		_feedback("Choose a different second endpoint.")
		return true
	var wire := {"action": "connect_drive" if active_tool == "shaft" else "disconnect_drive", "from": _first.id, "to": entity_id}
	_first.clear()
	_submit(context, wire)
	return true
