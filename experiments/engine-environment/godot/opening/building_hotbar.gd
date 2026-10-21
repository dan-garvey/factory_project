extends PanelContainer
## Local slot assignments over the host's confirmed carried kit.
const TOOLS := {"collector": "Collector", "foundation": "Foundation", "belt": "Belt",
	"processor": "Press", "wheel": "Waterwheel", "gear": "Cogwheel", "drive": "Shaft"}
const SHORT_NAMES := {"wheel": "Wheel", "gear": "Cog"}
var slots: Array[String] = ["collector", "foundation", "belt", "processor", "wheel", "gear", "drive", ""]
var buttons: Array[Button] = []
var catalog_buttons: Dictionary = {}
var catalog_button: Button
var catalog: PopupPanel
var destination: OptionButton
var parts_label: Label
var selected_slot := 0
var _host: WeakRef

func configure(host, ui: Control) -> void:
	_host = weakref(host)
	name = "BuildingHotbar"
	ui.get_viewport().gui_embed_subwindows = true
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.078, 0.129, 0.157, 0.96)
	surface.border_color = Color("41565e")
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(5)
	for side in range(4):
		surface.set_content_margin(side, 8.0)
	add_theme_stylebox_override("panel", surface)
	ui.add_child(self)
	var row := HBoxContainer.new()
	add_child(row)
	catalog_button = host._button(row, "Build [B]", open_catalog)
	for index in range(slots.size()):
		var button: Button = host._button(row, "", select_slot.bind(index))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(86, 64)
		button.add_theme_font_size_override("font_size", 13)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
		button.gui_input.connect(_slot_input.bind(index))
		buttons.append(button)
	catalog = PopupPanel.new()
	catalog.name = "BuildingCatalog"
	catalog.theme = ui.theme.duplicate()
	var menu_surface := surface.duplicate() as StyleBoxFlat
	menu_surface.bg_color = Color("142129")
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
	host._label(column, "Choose a slot, then a part. Right-click a slot to replace it.", 14)
	destination = OptionButton.new()
	column.add_child(destination)
	for index in range(slots.size()):
		destination.add_item("")
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	for tool: String in TOOLS:
		var button: Button = host._button(grid, TOOLS[tool], assign.bind(tool))
		button.custom_minimum_size = Vector2(246, 68)
		button.icon = load("res://opening/assets/build-icons/" + tool + ".svg")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 36)
		catalog_buttons[tool] = button
	var actions := HBoxContainer.new()
	column.add_child(actions)
	host._button(actions, "Clear slot", clear_slot)
	host._button(actions, "Close [Esc]", catalog.hide)
	ui.resized.connect(_fit)
	minimum_size_changed.connect(func(): _fit.call_deferred())
	resized.connect(host._queue_footer_fit)
	refresh(false)
	_fit.call_deferred()

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
	return maxi(0, int(parts.get("shaft" if tool == "drive" else tool, 0)))

func refresh(snapshot_ready: bool = true) -> void:
	var host = _view()
	if host == null:
		return
	var parts: Dictionary = host._display_parts()
	var scope := "shared" if host._parts_are_shared() else "carried"
	var usable: bool = snapshot_ready and host._can_choose_tool()
	catalog_button.disabled = host.explanation_open
	if host.explanation_open:
		catalog.hide()
	var active: String = host.mode
	if host.transmission_controls != null and not host.transmission_controls.active_tool.is_empty():
		active = "drive" if host.transmission_controls.active_tool == "place_shaft" else host.transmission_controls.active_tool
	if selected_slot < 0 or slots[selected_slot] != active:
		selected_slot = slots.find(active)
	for index in range(slots.size()):
		var tool := slots[index]
		var label: String = TOOLS.get(tool, "Empty")
		var amount := _count(tool, parts)
		var offered: bool = not (tool == "foundation" and not host.state.get("options", {}).get("foundations", false)) \
			and not (tool == "gear" and not host._native_transmission())
		buttons[index].text = "%d %s\n×%d" % [index + 1, SHORT_NAMES.get(tool, label), amount] if not tool.is_empty() else "%d\nAssign" % (index + 1)
		buttons[index].icon = catalog_buttons[tool].icon if not tool.is_empty() else null
		# Expanded icons do not contribute width to Button's minimum size.
		# Reserve their actual space even when the assigned name is long.
		buttons[index].custom_minimum_size.x = maxf(86.0, buttons[index].get_minimum_size().x + 28.0)
		buttons[index].disabled = host.explanation_open or (not tool.is_empty() and (not usable or amount < 1 or not offered))
		buttons[index].button_pressed = selected_slot == index and active == tool
		destination.set_item_text(index, "%d · %s" % [index + 1, label])
	for tool: String in catalog_buttons:
		var button: Button = catalog_buttons[tool]
		var amount := _count(tool, parts)
		button.text = "%s\n%d %s" % [TOOLS[tool], amount, scope]
		button.disabled = not usable or amount < 1
		button.visible = not (tool == "foundation" and not host.state.get("options", {}).get("foundations", false)) \
			and not (tool == "gear" and not host._native_transmission())

func open_catalog(index: int = -1) -> void:
	var host = _view()
	if host == null or host.explanation_open:
		return
	if catalog.visible and index < 0:
		catalog.hide()
		return
	refresh()
	destination.select(index if index >= 0 and index < slots.size() else maxi(0, selected_slot))
	catalog.popup_centered(Vector2i(560, 470))
	host._refresh_guided_tools()
	_place_catalog.call_deferred()

func _slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		open_catalog(index)
		get_viewport().set_input_as_handled()

func assign(tool: String) -> void:
	if not catalog_buttons.has(tool) or catalog_buttons[tool].disabled:
		return
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
