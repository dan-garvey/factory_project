extends MenuButton
## View-local tools over confirmed native state. host.issue owns every request.

var selected_axis := "x"
var gear_height := 4
var gear_teeth := 2
var active_tool := ""
var _host: WeakRef
var _first: Dictionary = {}
var _axes: PopupMenu
var _heights: PopupMenu

func _init() -> void:
	text = "Cogwheels and shafts…"
	var menu := get_popup()
	menu.add_radio_check_item("Place cogwheel", 1)
	menu.add_radio_check_item("Connect shaft", 2)
	menu.add_radio_check_item("Disconnect shaft link", 3)
	menu.add_radio_check_item("Remove cogwheel or shaft", 4)
	menu.add_item("Leave transmission tools", 5)
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
	menu.add_submenu_item("Gear height: 4", "Height", 101)
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
	if tool not in ["", "gear", "shaft", "disconnect", "remove"]:
		return
	active_tool = tool
	_first.clear()
	refresh()

func _tool_selected(id: int) -> void:
	choose_tool({1: "gear", 2: "shaft", 3: "disconnect", 4: "remove"}.get(id, ""))

func _axis_selected(id: int) -> void:
	if id in [0, 1, 2]:
		selected_axis = ["x", "y", "z"][id]
		_first.clear()
		refresh()

func _height_selected(id: int) -> void:
	gear_height = clampi(gear_height + (-1 if id == 0 else 1), 0, 16)
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
		_first.clear()
		return
	var gears := _count(context, "gear", gear_teeth, 0)
	var shafts := _count(context, "shaft", 0, 2)
	var menu := get_popup()
	menu.set_item_text(0, "Place cogwheel · %d carried" % gears)
	menu.set_item_text(1, "Connect shaft · %d carried" % shafts)
	menu.set_item_disabled(0, gears == 0)
	menu.set_item_disabled(1, shafts == 0)
	for index in range(4):
		menu.set_item_checked(index, active_tool == ["gear", "shaft", "disconnect", "remove"][index])
	menu.set_item_text(menu.get_item_index(100), "Axis: " + selected_axis.to_upper())
	menu.set_item_text(menu.get_item_index(101), "Gear height: %d quarter steps" % gear_height)
	for index in range(3):
		_axes.set_item_checked(index, selected_axis == ["x", "y", "z"][index])
	_heights.set_item_disabled(0, gear_height <= 0)
	_heights.set_item_disabled(1, gear_height >= 16)
	text = {"gear": "Place cogwheel", "shaft": "Connect shaft", "disconnect": "Disconnect shaft", "remove": "Remove transmission"}.get(active_tool, "Cogwheels and shafts…")
	tooltip_text = "Axis %s · gear height %d quarter steps. %d cogwheels and %d shafts carried." % [selected_axis.to_upper(), gear_height, gears, shafts]
	if not context.usable:
		_first.clear()

func _part(context: Dictionary, id: String) -> Dictionary:
	var value: Variant = context.snapshot.transmission_parts.get(id, context.snapshot.entities.get(id))
	if not value is Dictionary or typeof(value.get("generation")) != TYPE_INT or value.generation < 1:
		return {}
	return value

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
	if active_tool == "gear":
		var valid := center.size() == 3 and selected_axis in ["x", "y", "z"]
		for coordinate: Variant in center:
			valid = valid and typeof(coordinate) == TYPE_INT
		if valid:
			valid = center[0] >= -8 and center[0] <= 16 and center[1] == gear_height and gear_height >= 0 and gear_height <= 16 and center[2] >= -8 and center[2] <= 16
		if not valid or _count(context, "gear", gear_teeth, 0) == 0:
			_feedback("Choose an available cogwheel at an integer grid point on the selected height.")
			return true
		_submit(context, {"action": "place_gear", "center": center.duplicate(), "axis": selected_axis, "teeth": gear_teeth})
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
	if part.get("kind") == "shaft" or (active_tool == "shaft" and _count(context, "shaft", 0, 2) == 0):
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
