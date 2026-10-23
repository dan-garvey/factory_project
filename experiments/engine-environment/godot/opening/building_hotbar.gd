extends PanelContainer
## Local slot assignments over the host's confirmed carried kit.
const TOOLS := {"collector": "Collector", "foundation": "Foundation", "belt": "Belt",
	"processor": "Press", "wheel": "Waterwheel", "gear": "Cogwheel", "drive": "Shaft",
	"gearbox": "Horizontal gearbox", "vertical_gearbox": "Vertical gearbox", "chain_drive": "Chain drive"}
const CATALOG_KEYS := {KEY_C: "collector", KEY_F: "foundation", KEY_B: "belt",
	KEY_P: "processor", KEY_W: "wheel", KEY_G: "gear", KEY_S: "drive",
	KEY_H: "gearbox", KEY_V: "vertical_gearbox", KEY_N: "chain_drive"}
const TOOL_KEYS := {"collector": "C", "foundation": "F", "belt": "B",
	"processor": "P", "wheel": "W", "gear": "G", "drive": "S",
	"gearbox": "H", "vertical_gearbox": "V", "chain_drive": "N"}
const COMPONENT_PREFIX := "component:"
const ARRIVAL_SLOTS: Array[String] = ["component:wooden_frame", "foundation", "component:wooden_shaft",
	"component:tool_mount", "component:receiver_tray", "component:cutting_edge", "belt", "wheel"]
const COMPONENT_ICON = preload("res://opening/assets/build-icons/component.svg")
var slots: Array[String] = ["collector", "foundation", "belt", "processor", "wheel", "gear", "drive", ""]
var buttons: Array[Button] = []
var slot_icons: Array[TextureRect] = []
var slot_tags: Array[Label] = []
var slot_counts: Array[Label] = []
var catalog_buttons: Dictionary = {}
var catalog_button: Button
var catalog: PopupPanel
var destination: OptionButton
var component_row: HBoxContainer
var component_choice: OptionButton
var component_assign_button: Button
var parts_label: Label
var selected_slot := 0
var _arrival_active := false
var _component_labels: Dictionary = {}
var _component_names: Array[String] = []
var _host: WeakRef

func configure(host, ui: Control) -> void:
	_host = weakref(host)
	name = "BuildingHotbar"
	ui.get_viewport().gui_embed_subwindows = true
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color.TRANSPARENT
	for side in range(4):
		surface.set_content_margin(side, 0.0)
	add_theme_stylebox_override("panel", surface)
	ui.add_child(self)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	add_child(row)
	catalog_button = host._button(row, "Build  B", open_catalog)
	catalog_button.custom_minimum_size = Vector2(72, 54)
	catalog_button.add_theme_font_size_override("font_size", 13)
	_style_slot(catalog_button)
	for index in range(slots.size()):
		var button: Button = host._button(row, "", select_slot.bind(index))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(54, 54)
		_style_slot(button)
		var icon := TextureRect.new()
		icon.position = Vector2(11, 9)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		slot_icons.append(icon)
		var tag := Label.new()
		tag.position = Vector2(5, 35)
		tag.size = Vector2(22, 15)
		tag.add_theme_font_size_override("font_size", 9)
		tag.add_theme_color_override("font_color", Color("e7b875"))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(tag)
		slot_tags.append(tag)
		var key := Label.new()
		key.text = str(index + 1)
		key.position = Vector2(5, 2)
		key.add_theme_font_size_override("font_size", 10)
		key.add_theme_color_override("font_color", Color("dce9e5"))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(key)
		var count := Label.new()
		count.position = Vector2(30, 36)
		count.size = Vector2(20, 14)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.add_theme_font_size_override("font_size", 11)
		count.add_theme_color_override("font_color", Color("f6e5c5"))
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(count)
		slot_counts.append(count)
		button.gui_input.connect(_slot_input.bind(index))
		buttons.append(button)
	catalog = PopupPanel.new()
	catalog.name = "BuildingCatalog"
	catalog.theme = ui.theme.duplicate()
	var menu_surface := StyleBoxFlat.new()
	menu_surface.bg_color = Color(0.055, 0.09, 0.11, 0.91)
	menu_surface.set_corner_radius_all(7)
	catalog.theme.set_stylebox("panel", "PopupPanel", menu_surface)
	add_child(catalog)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	catalog.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	parts_label = host._label(column, "BUILDING CATALOG", 18)
	host._label(column, "1–8 choose slot  ·  letter assigns part  ·  Delete clears", 14)
	destination = OptionButton.new()
	column.add_child(destination)
	for index in range(slots.size()):
		destination.add_item("")
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	for tool: String in TOOLS:
		var button: Button = host._button(grid, TOOLS[tool], assign.bind(tool))
		button.custom_minimum_size = Vector2(246, 54)
		button.icon = load("res://opening/assets/build-icons/" + tool + ".svg")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 36)
		catalog_buttons[tool] = button
	component_row = HBoxContainer.new()
	column.add_child(component_row)
	component_choice = OptionButton.new()
	component_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	component_choice.item_selected.connect(func(_index: int) -> void: refresh())
	component_row.add_child(component_choice)
	component_assign_button = host._button(component_row, "Assign part  [A]", assign_component)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	host._button(actions, "Clear slot  [Delete]", clear_slot)
	host._button(actions, "Close [Esc]", catalog.hide)
	ui.resized.connect(_fit)
	minimum_size_changed.connect(func(): _fit.call_deferred())
	resized.connect(host._queue_footer_fit)
	refresh(false)
	_fit.call_deferred()

func _style_slot(button: Button) -> void:
	for state_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.045, 0.075, 0.09, 0.34 if state_name == "normal" else 0.52)
		if state_name in ["pressed", "hover_pressed"]:
			style.bg_color = Color(0.12, 0.18, 0.19, 0.68)
			style.border_color = Color("e7b875")
			style.border_width_bottom = 2
		elif state_name == "disabled":
			style.bg_color.a = 0.22
		style.set_corner_radius_all(5)
		button.add_theme_stylebox_override(state_name, style)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER

func _input(event: InputEvent) -> void:
	if not catalog.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.alt_pressed:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_8:
		destination.select(event.keycode - KEY_1)
	elif event.keycode == KEY_DELETE:
		clear_slot()
	elif event.keycode == KEY_ESCAPE:
		catalog.hide()
	elif CATALOG_KEYS.has(event.keycode):
		assign(CATALOG_KEYS[event.keycode])
	elif event.keycode == KEY_A and _arrival_active:
		assign_component()
	else:
		return
	get_viewport().set_input_as_handled()

func _fit() -> void:
	if not is_inside_tree():
		return
	size = get_combined_minimum_size()
	position = Vector2((get_parent().size.x - size.x) / 2.0, get_parent().size.y - size.y - 18.0)
	if catalog != null and catalog.visible:
		_place_catalog.call_deferred()

func _place_catalog() -> void:
	var host = _view()
	if host == null or not catalog.visible:
		return
	var extent: Vector2 = get_parent().size
	var y := int((extent.y - catalog.size.y) / 2.0)
	if host.status_footer != null:
		y = mini(y, int(host.status_footer.position.y) - catalog.size.y - 12)
	catalog.position = Vector2i(int((extent.x - catalog.size.x) / 2.0), maxi(18, y))

func _view():
	return _host.get_ref() if _host != null else null

func _count(tool: String, parts: Dictionary) -> int:
	if tool.begins_with(COMPONENT_PREFIX):
		var host = _view()
		return maxi(0, int(host.state.get("cargo", {}).get(host.client, {}).get("components", {}).get(
			tool.trim_prefix(COMPONENT_PREFIX), 0))) if host != null else 0
	return maxi(0, int(parts.get("shaft" if tool == "drive" else tool, 0)))

func _tool_label(tool: String) -> String:
	return str(_component_labels.get(tool.trim_prefix(COMPONENT_PREFIX), "Component")) \
		if tool.begins_with(COMPONENT_PREFIX) else str(TOOLS.get(tool, "Empty"))

func _component_tag(tool: String) -> String:
	if not tool.begins_with(COMPONENT_PREFIX):
		return ""
	var words: PackedStringArray = _tool_label(tool).split(" ")
	return (words[0].left(1) + words[1].left(1)).to_upper() if words.size() > 1 else words[0].left(2).to_upper()

func _offered(tool: String, host) -> bool:
	return not (_arrival_active and tool in ["collector", "processor"]) \
		and not (tool == "foundation" and not host.state.get("options", {}).get("foundations", false)) \
		and not (tool in ["gear", "gearbox", "vertical_gearbox", "chain_drive"] and not host._native_transmission())

func _sync_arrival(host) -> void:
	var arrival: bool = host._native_transmission() and host.state.has("hand_sources")
	if arrival != _arrival_active:
		_arrival_active = arrival
		slots = ARRIVAL_SLOTS.duplicate() if arrival else \
			["collector", "foundation", "belt", "processor", "wheel", "gear", "drive", ""]
		selected_slot = -1
	if arrival and _component_names.is_empty() and host.arrival_assembly_controls != null:
		for item in host.arrival_assembly_controls.COMPONENTS:
			var component: String = str(item[0])
			_component_names.append(component)
			_component_labels[component] = str(item[1])
			component_choice.add_item(str(item[1]))
	component_row.visible = arrival

func refresh(snapshot_ready: bool = true) -> void:
	var host = _view()
	if host == null:
		return
	_sync_arrival(host)
	var parts: Dictionary = host._display_parts()
	var scope := "shared" if host._parts_are_shared() else "carried"
	var usable: bool = snapshot_ready and host._can_choose_tool()
	catalog_button.disabled = host.explanation_open
	if host.explanation_open:
		catalog.hide()
	var active: String = host.mode
	if active == "component" and host.arrival_assembly_controls != null:
		active = COMPONENT_PREFIX + host.arrival_assembly_controls.selected_name()
	if host.transmission_controls != null and not host.transmission_controls.active_tool.is_empty():
		active = {"place_shaft": "drive", "belt_span": "belt"}.get(host.transmission_controls.active_tool, host.transmission_controls.active_tool)
	if selected_slot < 0 or slots[selected_slot] != active:
		selected_slot = slots.find(active)
	for index in range(slots.size()):
		var tool := slots[index]
		var label: String = _tool_label(tool)
		var amount := _count(tool, parts)
		var offered: bool = _offered(tool, host)
		buttons[index].visible = true
		slot_icons[index].texture = COMPONENT_ICON if tool.begins_with(COMPONENT_PREFIX) else \
			catalog_buttons[tool].icon if not tool.is_empty() else null
		slot_icons[index].visible = not tool.is_empty()
		slot_tags[index].text = _component_tag(tool)
		slot_counts[index].text = str(amount) if not tool.is_empty() else "+"
		buttons[index].tooltip_text = "%s · %d %s · slot %d" % [label, amount, scope, index + 1] if not tool.is_empty() else "Assign slot %d · B opens catalog" % (index + 1)
		buttons[index].disabled = host.explanation_open or (not tool.is_empty() and (not usable or amount < 1 or not offered))
		buttons[index].button_pressed = selected_slot == index and active == tool
		destination.set_item_text(index, "%d · %s" % [index + 1, label])
	for tool: String in catalog_buttons:
		var button: Button = catalog_buttons[tool]
		var amount := _count(tool, parts)
		button.text = "%s  [%s]\n%d %s" % [TOOLS[tool], TOOL_KEYS[tool], amount, scope]
		button.disabled = not usable or amount < 1 or not _offered(tool, host)
		button.visible = _offered(tool, host)
	if _arrival_active:
		for index in range(_component_names.size()):
			var component: String = _component_names[index]
			component_choice.set_item_text(index, "%s  ×%d" % [_component_labels[component],
				_count(COMPONENT_PREFIX + component, parts)])
		component_assign_button.disabled = not usable or component_choice.selected < 0 or \
			_count(COMPONENT_PREFIX + _component_names[component_choice.selected], parts) < 1

func open_catalog(index: int = -1) -> void:
	var host = _view()
	if host == null or host.explanation_open:
		return
	if catalog.visible and index < 0:
		catalog.hide()
		return
	refresh()
	destination.select(index if index >= 0 and index < slots.size() else maxi(0, selected_slot))
	if _arrival_active and host.arrival_assembly_controls != null:
		var selected_component: String = host.arrival_assembly_controls.selected_name()
		if _component_names.has(selected_component):
			component_choice.select(_component_names.find(selected_component))
			refresh()
	catalog.popup_centered(Vector2i(560, 480 if _arrival_active else 470))
	destination.grab_focus()
	host._refresh_guided_tools()
	_place_catalog.call_deferred()

func _slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		open_catalog(index)
		get_viewport().set_input_as_handled()

func assign(tool: String) -> void:
	if not catalog_buttons.has(tool) or catalog_buttons[tool].disabled:
		return
	_assign_to_slot(tool)

func assign_component() -> void:
	if not _arrival_active or component_assign_button.disabled or component_choice.selected < 0:
		return
	_assign_to_slot(COMPONENT_PREFIX + _component_names[component_choice.selected])

func _assign_to_slot(tool: String) -> void:
	var index := destination.selected
	slots[index] = tool
	catalog.hide()
	select_slot(index)

func clear_slot() -> void:
	var host = _view()
	if host == null or host.explanation_open:
		return
	var index := destination.selected
	slots[index] = ""
	catalog.hide()
	if selected_slot == index:
		host._select_tool("inspect")
	refresh()

func select_slot(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	refresh()
	if buttons[index].disabled:
		return
	var tool := slots[index]
	if tool.is_empty():
		open_catalog(index)
		return
	var host = _view()
	if tool.begins_with(COMPONENT_PREFIX):
		if host.arrival_assembly_controls == null or not host.arrival_assembly_controls.select_component_name(
			tool.trim_prefix(COMPONENT_PREFIX)):
			return
		selected_slot = index
		host._select_tool("component")
		return
	if tool == "gear" and host.transmission_controls != null:
		# Prefer an available carried size; this changes selection, never stock.
		var chosen := -1
		for part: Dictionary in host.state.get("part_specifications", {}).get(host.client, []):
			if part.kind == "gear" and int(part.count) > 0:
				if part.teeth == host.transmission_controls.gear_teeth:
					chosen = part.teeth
					break
				if chosen < 0:
					chosen = part.teeth
		if chosen > 0:
			host.transmission_controls.gear_teeth = chosen
	selected_slot = index
	host._select_tool(tool)
