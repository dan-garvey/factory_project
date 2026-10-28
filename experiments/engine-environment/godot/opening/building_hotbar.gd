extends PanelContainer
const Widgets = preload("res://opening/production_widgets.gd")
## Local slot assignments over the host's confirmed carried kit.
class PlaceableTile:
	extends Button
	var owner_view: WeakRef
	var tool := ""

	func _get_drag_data(_position: Vector2) -> Variant:
		if owner_view == null or owner_view.get_ref() == null:
			return null
		var payload: Dictionary = owner_view.get_ref()._drag_payload(tool)
		if payload.is_empty():
			return null
		var preview := TextureRect.new()
		preview.texture = icon
		preview.custom_minimum_size = Vector2(42, 42)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		set_drag_preview(preview)
		return payload

class HotbarSlot:
	extends Button
	var owner_view: WeakRef
	var index := -1

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return owner_view != null and owner_view.get_ref() != null \
			and owner_view.get_ref()._can_bind(index, data)

	func _drop_data(_position: Vector2, data: Variant) -> void:
		if _can_drop_data(Vector2.ZERO, data):
			owner_view.get_ref().bind_slot(index, str(data.tool))

const TOOLS := {"collector": "Collector", "foundation": "Foundation", "belt": "Belt",
	"processor": "Press", "wheel": "Waterwheel", "gear": "Cogwheel", "drive": "Shaft",
	"gearbox": "Horizontal gearbox", "vertical_gearbox": "Vertical gearbox", "chain_drive": "Chain drive"}
const CATALOG_KEYS := {KEY_C: "collector", KEY_F: "foundation", KEY_B: "belt",
	KEY_P: "processor", KEY_W: "wheel", KEY_G: "gear", KEY_S: "drive",
	KEY_H: "gearbox", KEY_V: "vertical_gearbox", KEY_N: "chain_drive"}
const COMPONENT_PREFIX := "component:"
const ARRIVAL_SLOTS: Array[String] = ["", "", "", "", "", "", "", ""]
const MIN_CARRIED_CELLS := 32
const COLLECTOR_PROJECT_COMPONENTS := ["wooden_frame", "tool_mount", "cutting_edge",
	"receiver_tray", "wooden_shaft", "wooden_cog", "hand_crank"]
const BELT_ROUTE_COMPONENTS := ["wooden_shaft", "wooden_cog", "hand_crank"]
const COMPONENT_ICON = preload("res://opening/assets/build-icons/component.svg")
const COLLECTOR_ICON = preload("res://opening/assets/build-icons/collector.svg")
const BELT_ICON = preload("res://opening/assets/build-icons/belt.svg")
const FOOTPRINT_ONE_ICON = preload("res://opening/assets/build-icons/footprint-one.svg")
const FOOTPRINT_FOUR_ICON = preload("res://opening/assets/build-icons/footprint-four.svg")
const MATERIALS := {
	"timber": ["Timber", "timber.svg"], "raw": ["Copper", "ore.svg"],
	"products": ["Copper plate", "plate.svg"], "offcuts": ["Copper offcut", "offcut.svg"],
	"sheets": ["Copper sheet", "sheet.svg"], "work_lots": ["Copper workpiece", "workpiece.svg"],
	"fabrication_hub": ["Pod workshop", "workshop-pod.svg"]}
const COMPONENT_ICONS := {
	"wooden_frame": "wooden_frame.svg", "wooden_shaft": "wooden_shaft.svg",
	"wooden_cog": "wooden_cog.svg", "receiver_tray": "receiver_tray.svg",
	"tool_mount": "tool_mount.svg", "sliding_guide": "sliding_guide.svg",
	"cutting_edge": "cutting_edge.svg", "anvil": "anvil.svg",
	"broad_anvil": "anvil.svg", "broad_flat_head": "flat_head.svg",
	"ram_face": "ram_face.svg", "copper_shaft": "copper_shaft.svg",
	"copper_cog": "copper_cog.svg", "wooden_workbench": "wooden_workbench.svg",
	"wooden_slide": "wooden_slide.svg", "copper_slide": "copper_slide.svg",
	"broad_copper_slide": "copper_slide.svg",
	"flat_head": "flat_head.svg", "hand_crank": "workshop-crank.svg",
	"channel_narrow_x": "channel_narrow_x.svg", "channel_narrow_z": "channel_narrow_z.svg",
	"channel_broad_x": "channel_broad_x.svg", "channel_broad_z": "channel_broad_z.svg"}
var slots: Array[String] = ["", "", "", "", "", "", "", ""]
var buttons: Array[Button] = []
var slot_icons: Array[TextureRect] = []
var slot_counts: Array[Label] = []
var catalog_buttons: Dictionary = {}
var catalog_counts: Dictionary = {}
var catalog_button: Button
var catalog_close_button: Button
var footprint_button: Button
var footprint_catalog_button: Button
var catalog: PopupPanel
var catalog_margin: MarginContainer
var material_grid: GridContainer
var material_buttons: Dictionary = {}
var material_counts: Dictionary = {}
var component_buttons: Dictionary = {}
var component_counts: Dictionary = {}
var component_textures: Dictionary = {}
var component_grid: GridContainer
var inventory_empty: Array[Control] = []
var recipe_grid: GridContainer
var recipe_buttons: Dictionary = {}
var recipe_names: Dictionary = {}
var recipe_costs: Dictionary = {}
var recipe_side: VBoxContainer
var recipe_focus_row: HBoxContainer
var recipe_focus_label: Label
var recipe_tip_label: Label
var project_focus_button: Button
var all_focus_button: Button
var recipe_focus := "project"
var recipe_scroll: ScrollContainer
var inventory_scroll: ScrollContainer
var catalog_columns: BoxContainer
var context_label: Label
var carried_label: Label
var context_action: Button
var context_bench := ""
var parts_label: Label
var focus_description: Label
var selected_slot := 0
var last_bound_slot := -1
var _hovered_tool := ""
var _arrival_active := false
var _component_labels: Dictionary = {}
var _component_names: Array[String] = []
var _host: WeakRef
# Invalidate a deferred resize restore when a later action closes or reopens the catalog.
var _catalog_session := 0
var _catalog_resize_pending := false

func configure(host, ui: Control) -> void:
	_host = weakref(host)
	for component: String in COMPONENT_ICONS:
		component_textures[component] = load("res://opening/assets/build-icons/" + COMPONENT_ICONS[component])
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
	catalog_button = Widgets.button(row, "", open_catalog)
	catalog_button.icon = COMPONENT_ICON
	catalog_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	catalog_button.custom_minimum_size = Vector2(54, 54)
	catalog_button.tooltip_text = "Build and inventory · B"
	catalog_button.accessibility_name = "Build and inventory, shortcut B"
	_style_slot(catalog_button, true)
	footprint_button = Widgets.button(row, "", host._toggle_component_footprint)
	footprint_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footprint_button.custom_minimum_size = Vector2(48, 54)
	footprint_button.focus_mode = Control.FOCUS_ALL
	_style_slot(footprint_button, true)
	footprint_button.visible = false
	for index in range(slots.size()):
		var button := HotbarSlot.new()
		button.owner_view = weakref(self)
		button.index = index
		button.pressed.connect(select_slot.bind(index))
		row.add_child(button)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(54, 54)
		_style_slot(button, true)
		var icon := TextureRect.new()
		icon.position = Vector2(11, 9)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		slot_icons.append(icon)
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
	# A world hotbar drop must not dismiss the inventory on the next frame.
	catalog.popup_window = false
	catalog.theme = ui.theme.duplicate()
	var menu_surface := StyleBoxFlat.new()
	menu_surface.bg_color = Color(0.055, 0.09, 0.11, 1.0)
	menu_surface.set_corner_radius_all(7)
	catalog.theme.set_stylebox("panel", "PopupPanel", menu_surface)
	catalog.window_input.connect(_catalog_input)
	add_child(catalog)
	var margin := MarginContainer.new()
	catalog_margin = margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	catalog.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	parts_label = Widgets.label(column, "BUILD / INVENTORY", 18)
	focus_description = Widgets.label(column, " ", 12)
	footprint_catalog_button = Widgets.button(column, "", host._toggle_component_footprint)
	footprint_catalog_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footprint_catalog_button.custom_minimum_size = Vector2(48, 44)
	footprint_catalog_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	footprint_catalog_button.focus_mode = Control.FOCUS_ALL
	footprint_catalog_button.focus_entered.connect(_describe_focus.bind(footprint_catalog_button))
	footprint_catalog_button.visible = false
	context_label = Widgets.label(column, "Carried items and craftable recipes", 12)
	catalog_columns = BoxContainer.new()
	catalog_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_columns.add_theme_constant_override("separation", 12)
	column.add_child(catalog_columns)
	var inventory_side := VBoxContainer.new()
	inventory_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_columns.add_child(inventory_side)
	carried_label = Widgets.label(inventory_side, "CARRIED", 13)
	inventory_scroll = ScrollContainer.new()
	inventory_scroll.name = "InventoryItems"
	inventory_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_side.add_child(inventory_scroll)
	material_grid = GridContainer.new()
	material_grid.columns = 4
	material_grid.add_theme_constant_override("h_separation", 6)
	material_grid.add_theme_constant_override("v_separation", 6)
	inventory_scroll.add_child(material_grid)
	for kind: String in MATERIALS:
		var tile: Button = PlaceableTile.new() if kind == "fabrication_hub" else Button.new()
		if kind == "fabrication_hub":
			var hub_tile := tile as PlaceableTile
			hub_tile.owner_view = weakref(self)
			hub_tile.tool = "pod_workshop"
		material_grid.add_child(tile)
		_style_inventory_tile(tile, load("res://opening/assets/build-icons/" + MATERIALS[kind][1]))
		material_buttons[kind] = tile
		material_counts[kind] = _count_badge(tile)
		tile.focus_entered.connect(_describe_focus.bind(tile))
		if tile is PlaceableTile:
			_track_tile_hover(tile)
	material_buttons.fabrication_hub.pressed.connect(_select_hub_tool)
	for tool: String in TOOLS:
		var button := PlaceableTile.new()
		button.owner_view = weakref(self)
		button.tool = tool
		button.pressed.connect(_select_inventory_tool.bind(tool))
		material_grid.add_child(button)
		_style_inventory_tile(button, load("res://opening/assets/build-icons/" + tool + ".svg"))
		catalog_buttons[tool] = button
		catalog_counts[tool] = _count_badge(button)
		button.focus_entered.connect(_describe_focus.bind(button))
		_track_tile_hover(button)
	for teeth in [2, 4]:
		var tool := "gear:%d" % teeth
		var button := PlaceableTile.new()
		button.owner_view = weakref(self)
		button.tool = tool
		button.pressed.connect(_select_inventory_tool.bind(tool))
		material_grid.add_child(button)
		_style_inventory_tile(button, catalog_buttons.gear.icon)
		var size_badge := Label.new()
		size_badge.text = "%dT" % teeth
		size_badge.position = Vector2(5, 3)
		size_badge.add_theme_font_size_override("font_size", 11)
		size_badge.add_theme_color_override("font_color", Color("e7b875"))
		size_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(size_badge)
		catalog_buttons[tool] = button
		catalog_counts[tool] = _count_badge(button)
		button.focus_entered.connect(_describe_focus.bind(button))
		_track_tile_hover(button)
	component_grid = material_grid
	for index in MIN_CARRIED_CELLS:
		var empty := Panel.new()
		empty.custom_minimum_size = Vector2(78, 66)
		var empty_style := StyleBoxFlat.new()
		empty_style.bg_color = Color(0.08, 0.13, 0.15, 0.55)
		empty_style.set_corner_radius_all(5)
		empty.add_theme_stylebox_override("panel", empty_style)
		material_grid.add_child(empty)
		inventory_empty.append(empty)
	recipe_side = VBoxContainer.new()
	recipe_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_columns.add_child(recipe_side)
	recipe_focus_row = HBoxContainer.new()
	recipe_focus_row.add_theme_constant_override("separation", 6)
	recipe_side.add_child(recipe_focus_row)
	var recipe_heading: Label = Widgets.label(recipe_focus_row, "CRAFT / BUILD", 13)
	recipe_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	project_focus_button = Widgets.button(recipe_focus_row, "", _set_recipe_focus.bind("project"))
	project_focus_button.icon = COLLECTOR_ICON
	project_focus_button.custom_minimum_size = Vector2(38, 34)
	project_focus_button.toggle_mode = true
	project_focus_button.tooltip_text = "Collector project · show parts for a finite ore collector"
	project_focus_button.accessibility_name = "Collector project recipes"
	_style_slot(project_focus_button)
	project_focus_button.focus_entered.connect(_describe_focus.bind(project_focus_button))
	all_focus_button = Widgets.button(recipe_focus_row, "", _set_recipe_focus.bind("all"))
	all_focus_button.icon = COMPONENT_ICON
	all_focus_button.custom_minimum_size = Vector2(38, 34)
	all_focus_button.toggle_mode = true
	all_focus_button.tooltip_text = "All parts · show every unlocked recipe"
	all_focus_button.accessibility_name = "All unlocked recipes"
	_style_slot(all_focus_button)
	all_focus_button.focus_entered.connect(_describe_focus.bind(all_focus_button))
	recipe_focus_label = Widgets.label(recipe_focus_row, "COLLECTOR PROJECT", 11)
	recipe_tip_label = Widgets.label(recipe_side, "T timber · Cu copper · choose an icon to craft", 11)
	recipe_scroll = ScrollContainer.new()
	recipe_scroll.name = "CraftRecipes"
	recipe_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	recipe_side.add_child(recipe_scroll)
	recipe_grid = GridContainer.new()
	recipe_grid.columns = 4
	recipe_grid.add_theme_constant_override("h_separation", 6)
	recipe_grid.add_theme_constant_override("v_separation", 6)
	recipe_scroll.add_child(recipe_grid)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	context_action = Widgets.button(actions, "", _use_context_action)
	context_action.icon = load("res://opening/assets/build-icons/workshop-reclaim.svg")
	context_action.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	context_action.custom_minimum_size = Vector2(46, 39)
	context_action.focus_entered.connect(_describe_focus.bind(context_action))
	context_action.visible = false
	var clear: Button = Widgets.button(actions, "", clear_slot)
	clear.icon = load("res://opening/assets/build-icons/slot-clear.svg")
	clear.tooltip_text = "Clear last assigned or selected hotbar key · Delete"
	clear.accessibility_name = "Clear last assigned or selected hotbar key, shortcut Delete"
	catalog_close_button = Widgets.button(actions, "", _close_catalog)
	catalog_close_button.icon = load("res://opening/assets/menu-icons/close.svg")
	catalog_close_button.tooltip_text = "Close build and inventory · Esc"
	catalog_close_button.accessibility_name = "Close build and inventory, shortcut Escape"
	catalog_close_button.focus_entered.connect(_describe_focus.bind(catalog_close_button))
	ui.resized.connect(_fit)
	minimum_size_changed.connect(func(): _fit.call_deferred())
	resized.connect(host._queue_footer_fit)
	refresh(false)
	_fit.call_deferred()

func _style_slot(button: Button, worksite: bool = false) -> void:
	for state_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		var alpha := 0.34 if state_name == "normal" else 0.52
		if worksite:
			alpha = 0.68 if state_name == "normal" else 0.78
		style.bg_color = Color(0.045, 0.075, 0.09, alpha)
		if state_name in ["pressed", "hover_pressed"]:
			style.bg_color = Color(0.12, 0.18, 0.19, 0.86 if worksite else 0.68)
			style.border_color = Color("e7b875")
			style.border_width_bottom = 2
		elif state_name == "disabled":
			style.bg_color.a = 0.48 if worksite else 0.22
		style.set_corner_radius_all(5)
		button.add_theme_stylebox_override(state_name, style)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER

func _style_inventory_tile(button: Button, texture: Texture2D) -> void:
	button.custom_minimum_size = Vector2(78, 66)
	button.icon = texture
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 36)
	button.focus_mode = Control.FOCUS_ALL
	_style_slot(button)

func _count_badge(button: Button) -> Label:
	var badge := Label.new()
	badge.position = Vector2(48, 44)
	badge.size = Vector2(26, 18)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color("f6e5c5"))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(badge)
	return badge

func _describe_focus(button: Button) -> void:
	focus_description.text = button.tooltip_text
	if inventory_scroll.is_ancestor_of(button):
		inventory_scroll.call_deferred("ensure_control_visible", button)

func _track_tile_hover(tile: PlaceableTile) -> void:
	tile.mouse_entered.connect(func(): _hovered_tool = tile.tool)
	tile.mouse_exited.connect(func():
		if _hovered_tool == tile.tool:
			_hovered_tool = "")

func _catalog_input(event: InputEvent) -> void:
	if (not catalog.visible and not _catalog_resize_pending) or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.alt_pressed:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_8:
		if not bind_number_key(event.keycode - KEY_1):
			return
	elif event.keycode == KEY_DELETE:
		clear_slot()
	elif event.keycode == KEY_ESCAPE:
		_close_catalog()
	elif event.keycode == KEY_V and footprint_catalog_button.visible:
		_view()._toggle_component_footprint()
	elif event.keycode == KEY_S and context_action.visible and context_bench == str(_view().state.get("fabrication_hub", {}).get("id", "")):
		_use_context_action()
	elif event.keycode == KEY_R and context_action.visible and context_bench != str(_view().state.get("fabrication_hub", {}).get("id", "")):
		_use_context_action()
	elif event.keycode == KEY_P and _arrival_active and _material_count("fabrication_hub", _view()) > 0:
		_select_hub_tool()
	elif CATALOG_KEYS.has(event.keycode):
		_select_inventory_tool(CATALOG_KEYS[event.keycode])
	else:
		return
	catalog.set_input_as_handled()

func _fit() -> void:
	if not is_inside_tree():
		return
	size = get_combined_minimum_size()
	position = Vector2((get_parent().size.x - size.x) / 2.0, get_parent().size.y - size.y - 18.0)
	if catalog != null and catalog.visible:
		_catalog_resize_pending = true
		_restore_catalog_after_resize.call_deferred(catalog.gui_get_focus_owner(), _catalog_session)

func _close_catalog() -> void:
	_catalog_session += 1
	_catalog_resize_pending = false
	_hovered_tool = ""
	catalog.hide()

func _restore_catalog_after_resize(focused: Control, session: int) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or catalog == null or session != _catalog_session:
		return
	_catalog_resize_pending = false
	# Godot hides an embedded PopupPanel when its parent viewport changes size.
	if not catalog.visible:
		catalog.popup_centered(_catalog_dimensions(get_parent().size))
	_place_catalog()
	if is_instance_valid(focused) and catalog.is_ancestor_of(focused):
		focused.grab_focus()

func _place_catalog() -> void:
	var host = _view()
	if host == null or not catalog.visible:
		return
	var extent: Vector2 = get_parent().size
	_configure_catalog_layout(extent)
	catalog.size = _catalog_dimensions(extent)
	var centered_y := int((extent.y - catalog.size.y) / 2.0)
	var above_hotbar := int(_hotbar_top(extent) - catalog.size.y - 8.0)
	catalog.position = Vector2i(maxi(0, int((extent.x - catalog.size.x) / 2.0)),
		maxi(0, mini(centered_y, above_hotbar)))

func _configure_catalog_layout(extent: Vector2) -> void:
	var compact := extent.x <= 720.0
	var stacked := extent.x < 600.0
	var starter := _arrival_active and _view() != null and not _plate_unlocked(_view())
	for button: Button in [project_focus_button, all_focus_button]:
		button.custom_minimum_size = Vector2(28, 28) if compact else Vector2(38, 34)
	recipe_focus_label.visible = project_focus_button.visible and not compact
	catalog_columns.vertical = stacked
	material_grid.columns = 3 if compact else 4
	recipe_grid.columns = 3 if compact else 4
	context_label.visible = not compact or starter
	var scroll_height := 48 if stacked else 145 if starter and compact else 100 if starter else 125 if compact else 275
	inventory_scroll.custom_minimum_size = Vector2(0, scroll_height)
	recipe_scroll.custom_minimum_size = Vector2(0, scroll_height)
	for side in ["left", "right", "top", "bottom"]:
		catalog_margin.add_theme_constant_override("margin_" + side,
			7 if compact and project_focus_button.visible else 8 if compact else 16)

func _catalog_dimensions(extent: Vector2) -> Vector2i:
	var width := int(extent.x) if extent.x <= 720.0 else mini(800, int(extent.x) - 16)
	var starter := _arrival_active and _view() != null and not _plate_unlocked(_view())
	var project: bool = _arrival_active and _view() != null and _plate_unlocked(_view())
	var starter_height := 464 if extent.x <= 720.0 else 420
	return Vector2i(width, mini(starter_height if starter else 520 if project else 620,
		maxi(1, int(_hotbar_top(extent) - 16.0))))

func _hotbar_top(extent: Vector2) -> float:
	return extent.y - maxf(size.y, get_combined_minimum_size().y) - 18.0

func _view():
	return _host.get_ref() if _host != null else null

func _count(tool: String, parts: Dictionary) -> int:
	if tool.begins_with("gear:"):
		var host = _view()
		if host == null:
			return 0
		var teeth := int(tool.trim_prefix("gear:"))
		for specification: Dictionary in host.state.get("part_specifications", {}).get(host.client, []):
			if specification.get("kind") == "gear" and int(specification.get("teeth", 0)) == teeth:
				return maxi(0, int(specification.get("count", 0)))
		return 0
	if tool == "pod_workshop":
		var hub_host = _view()
		return _material_count("fabrication_hub", hub_host) if hub_host != null else 0
	if tool.begins_with(COMPONENT_PREFIX):
		var host = _view()
		if host == null:
			return 0
		var kind := tool.trim_prefix(COMPONENT_PREFIX)
		var components: Dictionary = host.state.get("cargo", {}).get(host.client, {}).get("components", {})
		if kind in ["broad_anvil", "broad_flat_head", "broad_copper_slide"]:
			var carried := "anvil" if kind == "broad_anvil" else \
				"flat_head" if kind == "broad_flat_head" else "copper_slide"
			return maxi(0, int(components.get(carried, 0)) / 4)
		return maxi(0, int(components.get(kind, 0)))
	return maxi(0, int(parts.get("shaft" if tool == "drive" else tool, 0)))

func _material_count(kind: String, host) -> int:
	var cargo: Dictionary = host.state.get("cargo", {}).get(host.client, {})
	if kind == "work_lots":
		return cargo.get("work_lots", []).size()
	if kind == "fabrication_hub":
		return int(host.state.get(kind, {}).get("holder", "") == host.client)
	return maxi(0, int(cargo.get(kind, 0)))

func _tool_label(tool: String) -> String:
	if tool.begins_with("gear:"):
		return "Cogwheel · %s teeth" % tool.trim_prefix("gear:")
	if tool == "pod_workshop":
		return "Pod workshop"
	return str(_component_labels.get(tool.trim_prefix(COMPONENT_PREFIX), "Component")) \
		if tool.begins_with(COMPONENT_PREFIX) else str(TOOLS.get(tool, "Empty"))

func _tool_icon(tool: String) -> Texture2D:
	if tool.is_empty():
		return null
	if tool == "pod_workshop":
		return material_buttons.fabrication_hub.icon
	if tool.begins_with(COMPONENT_PREFIX):
		return component_textures[tool.trim_prefix(COMPONENT_PREFIX)]
	return catalog_buttons[tool].icon

func _offered(tool: String, host) -> bool:
	if tool == "pod_workshop":
		return _arrival_active
	if _arrival_active and not _plate_unlocked(host):
		return tool in ["component:anvil", "component:flat_head", "component:broad_anvil",
			"component:broad_flat_head", "component:wooden_slide",
			"component:hand_crank"]
	return not (_arrival_active and tool in ["collector", "processor", "gear"]) \
		and not (tool.begins_with("gear:") and not _arrival_active) \
		and not (tool == "foundation" and not host.state.get("options", {}).get("foundations", false)) \
		and not (tool in ["gear", "gearbox", "vertical_gearbox", "chain_drive"] and not host._native_transmission())

func _plate_unlocked(host) -> bool:
	return not _arrival_active or not host.state.get("first_plate_unlock", true) or \
		host.state.get("workshop_completed_actors", []).has(host.client)

func _set_recipe_focus(value: String) -> void:
	recipe_focus = value
	refresh()

func _suggested_project(host) -> String:
	if host == null:
		return "collector"
	for assembly: Dictionary in host.state.get("collector_assemblies", []):
		if assembly.get("status") == "ready":
			return "belt"
	return "collector"

func _recipe_in_focus(key: String, kind: String = "") -> bool:
	if recipe_focus == "all":
		return true
	var belt_route: bool = _suggested_project(_view()) == "belt"
	if key.begins_with(COMPONENT_PREFIX):
		return (BELT_ROUTE_COMPONENTS if belt_route else COLLECTOR_PROJECT_COMPONENTS).has(
			key.trim_prefix(COMPONENT_PREFIX))
	return kind in (["shaft", "gear", "belt", "wheel"] if belt_route else ["shaft", "gear"])

func _sync_arrival(host) -> void:
	var arrival: bool = host._native_transmission() and host.state.has("hand_sources")
	if arrival != _arrival_active:
		_arrival_active = arrival
		slots = ARRIVAL_SLOTS.duplicate()
		selected_slot = -1
		last_bound_slot = -1
	if arrival and _component_names.is_empty() and host.arrival_assembly_controls != null:
		for item in host.arrival_assembly_controls.COMPONENTS:
			var component: String = str(item[0])
			_component_names.append(component)
			_component_labels[component] = str(item[1])
			var button := PlaceableTile.new()
			button.owner_view = weakref(self)
			button.tool = COMPONENT_PREFIX + component
			button.pressed.connect(_select_inventory_tool.bind(button.tool))
			component_grid.add_child(button)
			# Keep spare cells after every owned item as new component kinds appear.
			component_grid.move_child(button, inventory_empty[0].get_index())
			_style_inventory_tile(button, component_textures[component])
			component_buttons[component] = button
			component_counts[component] = _count_badge(button)
			button.focus_entered.connect(_describe_focus.bind(button))
			_track_tile_hover(button)
	for component: String in component_buttons:
		component_buttons[component].visible = arrival
	recipe_side.visible = arrival

func _valid_bench(snapshot: Dictionary, bench_id: String) -> bool:
	if bench_id.is_empty():
		return false
	var pod: Dictionary = snapshot.get("fabrication_hub", {})
	if pod.get("installed", false) and pod.get("id", "") == bench_id:
		return true
	for bench: Variant in snapshot.get("fabrication_benches", []):
		if bench is Dictionary and bench.get("id", "") == bench_id:
			return true
	return false

func _recipe_tile(key: String, icon: Texture2D) -> Button:
	if recipe_buttons.has(key):
		return recipe_buttons[key]
	var host = _view()
	var tile: Button = Widgets.button(recipe_grid, "", _craft_recipe.bind(key))
	_style_inventory_tile(tile, icon)
	tile.custom_minimum_size = Vector2(78, 98)
	tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	tile.add_theme_constant_override("icon_max_width", 32)
	tile.clip_contents = true
	tile.focus_entered.connect(_describe_focus.bind(tile))
	var name_label := Label.new()
	name_label.name = "RecipeName"
	name_label.position = Vector2(2, 42)
	name_label.size = Vector2(74, 29)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color("dde5d9"))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(name_label)
	var cost := Label.new()
	cost.position = Vector2(2, 73)
	cost.size = Vector2(74, 18)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_font_size_override("font_size", 12)
	cost.add_theme_color_override("font_color", Color("f6e5c5"))
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(cost)
	recipe_buttons[key] = tile
	recipe_names[key] = name_label
	recipe_costs[key] = cost
	return tile

func _recipe_state(host, key: String, label: String, cost: Dictionary,
		icon: Texture2D, field_allowed: bool, ready: bool) -> void:
	var tile := _recipe_tile(key, icon)
	var cargo: Dictionary = host.state.get("cargo", {}).get(host.client, {})
	var timber := int(cost.get("timber", 0))
	var copper := int(cost.get("copper", 0))
	var affordable := int(cargo.get("timber", 0)) >= timber and int(cargo.get("raw", 0)) >= copper
	var at_bench := _valid_bench(host.state, context_bench)
	var station := "Field or bench" if field_allowed else "Bench"
	var rating := int(cost.get("load_rating", 0))
	var rating_detail := " · rated for %d load" % rating if rating > 0 else ""
	var craftable := ready and affordable and (field_allowed or at_bench)
	var reason := "Craft at selected bench; stand nearby" if craftable and at_bench else \
		"Shape with multitool" if craftable else \
		"Carry the ingredients" if not affordable else \
		"Open a fabrication bench with E" if not field_allowed and not at_bench else \
		"Wait for the character"
	tile.visible = true
	tile.disabled = not ready
	tile.modulate = Color.WHITE if craftable else Color(0.68, 0.73, 0.76) if not affordable else \
		Color(0.65, 0.70, 0.72)
	for state_name in ["normal", "hover"]:
		var surface := tile.get_theme_stylebox(state_name, "Button") as StyleBoxFlat
		surface.border_color = Color("e7b875")
		surface.border_width_bottom = 2 if craftable else 0
	tile.tooltip_text = "%s · %d timber + %d copper · %s%s · %s" % [
		label, timber, copper, station, rating_detail, reason]
	tile.accessibility_name = "%s recipe, needs %d timber and %d copper, %s%s, %s" % [
		label, timber, copper, station, rating_detail, reason]
	recipe_names[key].text = label
	recipe_costs[key].text = "%dT · %dCu" % [timber, copper]

func _refresh_recipes(host, ready: bool) -> void:
	for tile: Button in recipe_buttons.values():
		tile.visible = false
	if not _arrival_active:
		return
	if not _valid_bench(host.state, context_bench):
		context_bench = ""
	context_action.visible = not context_bench.is_empty()
	context_action.disabled = not ready
	if context_action.visible:
		var hub_id: String = str(host.state.get("fabrication_hub", {}).get("id", ""))
		var hub := context_bench == hub_id
		context_action.icon = load("res://opening/assets/build-icons/workshop-pod.svg") if hub else \
			load("res://opening/assets/build-icons/workshop-reclaim.svg")
		context_action.tooltip_text = "Stow pod workshop · S" if hub else "Reclaim wooden workbench · R"
		context_action.accessibility_name = "Stow pod workshop, shortcut S" if hub else \
			"Reclaim wooden workbench, shortcut R"
	parts_label.text = "BENCH / INVENTORY" if not context_bench.is_empty() else "BUILD / INVENTORY"
	carried_label.text = "CARRIED"
	context_label.text = "Fabrication bench · choose a recipe" if not context_bench.is_empty() else \
		"Field recipes can be made anywhere · E opens a bench"
	if not _plate_unlocked(host):
		context_label.text = "First plate: build a press with a hand crank. Feed copper, turn the crank, collect the plate."
	var project_focus: bool = _arrival_active and _plate_unlocked(host) and bool(host.state.get("first_plate_unlock", false))
	var belt_route: bool = _suggested_project(host) == "belt"
	project_focus_button.visible = project_focus
	project_focus_button.icon = BELT_ICON if belt_route else COLLECTOR_ICON
	project_focus_button.tooltip_text = "Belt route · connect two shafts and power a belt toward the press" if belt_route else \
		"Collector project · show parts for a finite ore collector"
	project_focus_button.accessibility_name = "Belt route recipes" if belt_route else "Collector project recipes"
	if catalog.gui_get_focus_owner() == project_focus_button:
		_describe_focus(project_focus_button)
	all_focus_button.visible = project_focus
	recipe_focus_label.visible = project_focus and get_parent().size.x > 720.0
	recipe_tip_label.visible = not project_focus
	recipe_focus_label.text = ("BELT ROUTE" if belt_route else "COLLECTOR PROJECT") if recipe_focus == "project" else "ALL UNLOCKED PARTS"
	project_focus_button.button_pressed = recipe_focus == "project"
	all_focus_button.button_pressed = recipe_focus == "all"
	var recipes: Dictionary = host.state.get("component_recipes", {})
	var recipe_names: Array[String] = []
	if _plate_unlocked(host):
		recipe_names.assign(_component_names)
	else:
		for starter: String in ["anvil", "flat_head", "wooden_slide", "hand_crank"]:
			recipe_names.append(starter)
	for component: String in recipe_names:
		if not _component_labels.has(component):
			continue
		var cost: Dictionary = recipes.get(component, {})
		if cost.is_empty():
			continue
		var field_allowed := int(cost.get("timber", 0)) > 0 and int(cost.get("copper", 0)) == 0
		_recipe_state(host, COMPONENT_PREFIX + component, _component_labels[component], cost,
			component_textures[component], field_allowed, ready)
		if project_focus:
			recipe_buttons[COMPONENT_PREFIX + component].visible = _recipe_in_focus(COMPONENT_PREFIX + component)
	var foundation: Dictionary = host.state.get("foundation_recipe", {})
	if _plate_unlocked(host) and not foundation.is_empty():
		_recipe_state(host, "foundation", "Foundation", foundation,
			catalog_buttons.foundation.icon, false, ready)
		if project_focus:
			recipe_buttons.foundation.visible = recipe_focus == "all" or belt_route
	var parts: Array = host.state.get("part_recipes", [])
	for index in parts.size():
		if not _plate_unlocked(host):
			break
		var recipe: Dictionary = parts[index]
		var kind: String = str(recipe.get("kind", ""))
		var icon_name := ""
		var label := ""
		match kind:
			"shaft":
				icon_name = "drive"
				label = "Shaft tile"
			"gear":
				icon_name = "gear"
				label = "Cogwheel"
			"belt":
				icon_name = "belt"
				label = "Belt span"
			"wheel":
				icon_name = "wheel"
				label = "Waterwheel"
			"gearbox":
				icon_name = "gearbox"
				label = "Horizontal gearbox"
			"vertical_gearbox":
				icon_name = "vertical_gearbox"
				label = "Vertical gearbox"
			"chain_drive":
				icon_name = "chain_drive"
				label = "Chain drive"
			_:
				push_error("Unmapped native part recipe: " + kind)
				continue
		if int(recipe.get("half_span", 0)) > 0:
			label += " · half-span %d" % int(recipe.half_span)
		if int(recipe.get("teeth", 0)) > 0:
			label += " · %d teeth" % int(recipe.teeth)
		_recipe_state(host, "part:%d" % index, label, recipe,
			load("res://opening/assets/build-icons/%s.svg" % icon_name), false, ready)
		if project_focus:
			recipe_buttons["part:%d" % index].visible = _recipe_in_focus("part:%d" % index, kind)

func _craft_recipe(key: String) -> void:
	var host = _view()
	if host == null or not _arrival_active or not host._can_choose_tool():
		return
	if not _plate_unlocked(host) and key not in ["component:anvil", "component:flat_head",
			"component:wooden_slide", "component:hand_crank"]:
		focus_description.text = "Carry your first copper plate to unlock this recipe."
		return
	if not recipe_buttons.has(key) or not recipe_buttons[key].visible:
		focus_description.text = "Choose All parts to see that unlocked recipe."
		return
	var cargo: Dictionary = host.state.get("cargo", {}).get(host.client, {})
	var cost: Dictionary = {}
	var action: Dictionary = {}
	if key.begins_with(COMPONENT_PREFIX):
		var component := key.trim_prefix(COMPONENT_PREFIX)
		cost = host.state.get("component_recipes", {}).get(component, {})
		if not context_bench.is_empty() and _valid_bench(host.state, context_bench):
			action = {"action": "craft_component", "entity": context_bench, "component": component}
		elif int(cost.get("timber", 0)) > 0 and int(cost.get("copper", 0)) == 0:
			action = {"action": "field_craft", "component": component}
	elif key == "foundation":
		cost = host.state.get("foundation_recipe", {})
		if _valid_bench(host.state, context_bench):
			action = {"action": "craft_foundation", "entity": context_bench}
	elif key.begins_with("part:"):
		var index := int(key.trim_prefix("part:"))
		var recipes: Array = host.state.get("part_recipes", [])
		if index >= 0 and index < recipes.size():
			cost = recipes[index]
			if _valid_bench(host.state, context_bench):
				action = {"action": "craft_part", "entity": context_bench,
					"role": "waterwheel" if cost.get("kind") == "wheel" else cost.get("kind"),
					"half_span": cost.get("half_span", 0)}
				if cost.get("kind") == "gear":
					action["teeth"] = int(cost.get("teeth", 0))
	if cost.is_empty() or action.is_empty():
		focus_description.text = "Open a fabrication bench with E for this recipe."
		return
	if int(cargo.get("timber", 0)) < int(cost.get("timber", 0)) or \
			int(cargo.get("raw", 0)) < int(cost.get("copper", 0)):
		focus_description.text = "Carry the ingredients shown on the recipe."
		return
	host.issue(action)
	refresh()

func _use_context_action() -> void:
	var host = _view()
	if host == null or context_action.disabled or not _valid_bench(host.state, context_bench):
		return
	var hub_id: String = str(host.state.get("fabrication_hub", {}).get("id", ""))
	host.issue({"action": "stow_fabrication_hub", "entity": context_bench} if context_bench == hub_id else
		{"action": "reclaim_component", "entity": context_bench})
	refresh()

func _select_hub_tool() -> void:
	var host = _view()
	if host == null or not _arrival_active or not host._can_choose_tool() or \
			_material_count("fabrication_hub", host) < 1:
		return
	_close_catalog()
	host._select_tool("pod_workshop")

func refresh(snapshot_ready: bool = true) -> void:
	var host = _view()
	if host == null:
		return
	_sync_arrival(host)
	var parts: Dictionary = host._display_parts()
	var scope := "shared" if host._parts_are_shared() else "carried"
	var usable: bool = snapshot_ready and host._can_choose_tool()
	for kind: String in MATERIALS:
		var amount := _material_count(kind, host) if snapshot_ready else 0
		var label: String = MATERIALS[kind][0]
		material_counts[kind].text = str(amount)
		material_buttons[kind].tooltip_text = "%s · %d carried" % [label, amount]
		material_buttons[kind].accessibility_name = "%s, %d carried" % [label, amount]
		if kind == "fabrication_hub" and amount > 0:
			material_buttons[kind].tooltip_text += " · drag to hotbar or hover and press 1–8 · click to place"
			material_buttons[kind].accessibility_name += "; drag to hotbar or focus and press a number to bind; click to place"
		material_buttons[kind].disabled = kind == "fabrication_hub" and (not usable or amount < 1)
		material_buttons[kind].visible = amount > 0 if _arrival_active else true
	catalog_button.disabled = host.explanation_open
	if host.explanation_open:
		_close_catalog()
	var active: String = host.mode
	if active == "component" and host.arrival_assembly_controls != null:
		active = COMPONENT_PREFIX + host.arrival_assembly_controls.selected_name()
	var sized_part := active in ["component:anvil", "component:broad_anvil",
		"component:flat_head", "component:broad_flat_head",
		"component:copper_slide", "component:broad_copper_slide"]
	var broad_size := active in ["component:broad_anvil", "component:broad_flat_head",
		"component:broad_copper_slide"]
	var area_icon: Texture2D = FOOTPRINT_FOUR_ICON if broad_size else FOOTPRINT_ONE_ICON
	var area_tip := "2x2 slide housing · one piston · uses four copper slides · V" \
		if active == "component:broad_copper_slide" else \
		"1x1 copper slide · one carried part · V for 2x2" \
		if active == "component:copper_slide" else \
		"2x2 joined face · one click · uses four carried flat heads · V" \
		if active == "component:broad_flat_head" else \
		"2x2 joined workbed · one click · uses four carried anvils · V" \
		if active == "component:broad_anvil" else \
		"1x1 flat head · one carried part · V for 2x2" if active == "component:flat_head" else \
		"1x1 workbed · one carried part · V for 2x2"
	for area_button: Button in [footprint_button, footprint_catalog_button]:
		area_button.visible = sized_part
		area_button.disabled = not usable
		area_button.icon = area_icon
		area_button.tooltip_text = area_tip
		area_button.accessibility_name = "%s, shortcut V toggles size" % area_tip
	if host.transmission_controls != null and not host.transmission_controls.active_tool.is_empty():
		active = {"place_shaft": "drive", "belt_span": "belt"}.get(host.transmission_controls.active_tool, host.transmission_controls.active_tool)
		if active == "gear" and _arrival_active:
			active = "gear:%d" % host.transmission_controls.gear_teeth
	if selected_slot < 0 or slots[selected_slot] != active:
		selected_slot = slots.find(active)
	for index in range(slots.size()):
		var tool := slots[index]
		var label: String = _tool_label(tool)
		var amount := _count(tool, parts)
		var offered: bool = _offered(tool, host)
		buttons[index].visible = true
		slot_icons[index].texture = _tool_icon(tool)
		slot_icons[index].visible = not tool.is_empty()
		slot_counts[index].text = str(amount) if not tool.is_empty() else "+"
		buttons[index].tooltip_text = "%s · %d %s · key %d · drag a carried part to rebind" % [label, amount, scope, index + 1] if not tool.is_empty() else "Empty key %d · B opens inventory · drag a carried part here" % (index + 1)
		buttons[index].accessibility_name = "%s, %d %s, key %d; drag a carried part to rebind" % [label, amount, scope, index + 1] if not tool.is_empty() else "Empty hotbar key %d; open inventory with B and drag a carried part here" % (index + 1)
		buttons[index].disabled = host.explanation_open or not usable
		buttons[index].modulate = Color(0.65, 0.70, 0.72) if not tool.is_empty() and (amount < 1 or not offered) else Color.WHITE
		buttons[index].button_pressed = selected_slot == index and active == tool
	for tool: String in catalog_buttons:
		var button: Button = catalog_buttons[tool]
		var amount := _count(tool, parts)
		button.text = ""
		catalog_counts[tool].text = str(amount)
		button.tooltip_text = "%s · %d %s · drag to hotbar or hover and press 1–8 · click to place" % [_tool_label(tool), amount, scope]
		button.accessibility_name = "%s, %d %s; drag to hotbar or focus and press a number to bind; click to place" % [_tool_label(tool), amount, scope]
		button.disabled = not usable or amount < 1 or not _offered(tool, host)
		button.visible = _offered(tool, host) and (not _arrival_active or amount > 0)
	if _arrival_active:
		for component: String in _component_names:
			var count := _count(COMPONENT_PREFIX + component, parts)
			var part_button: Button = component_buttons[component]
			part_button.text = ""
			component_counts[component].text = str(count)
			part_button.disabled = not usable or count < 1
			part_button.visible = count > 0 and _offered(COMPONENT_PREFIX + component, host)
			var quantity := "%d buildable from four carried parts each" % count \
				if component in ["broad_anvil", "broad_flat_head", "broad_copper_slide"] else "%d carried" % count
			part_button.tooltip_text = "%s · %s · drag to hotbar or hover and press 1–8 · click to place" % [
				_component_labels[component], quantity]
			part_button.accessibility_name = "%s, %s; drag to hotbar or focus and press a number to bind; click to place" % [
				_component_labels[component], quantity]
	var shown := 0
	for tile in material_grid.get_children():
		if tile is Button and tile.visible:
			shown += 1
	for index in inventory_empty.size():
		inventory_empty[index].visible = index < maxi(0, MIN_CARRIED_CELLS - shown)
	_refresh_recipes(host, usable)

func open_catalog() -> void:
	var host = _view()
	if host == null or host.explanation_open:
		return
	if catalog.visible or _catalog_resize_pending:
		_close_catalog()
		return
	_catalog_session += 1
	_catalog_resize_pending = false
	_hovered_tool = ""
	context_bench = ""
	refresh()
	var viewport_size: Vector2 = get_parent().size
	_configure_catalog_layout(viewport_size)
	catalog.popup_centered(_catalog_dimensions(viewport_size))
	_focus_inventory_item()
	host._refresh_guided_tools()
	_place_catalog.call_deferred()

func open_at_bench(bench_id: String) -> void:
	var host = _view()
	if host == null or not _valid_bench(host.state, bench_id):
		return
	_catalog_session += 1
	_catalog_resize_pending = false
	_hovered_tool = ""
	context_bench = bench_id
	refresh()
	host._release_character_controls()
	var viewport_size: Vector2 = get_parent().size
	_configure_catalog_layout(viewport_size)
	catalog.popup_centered(_catalog_dimensions(viewport_size))
	_focus_inventory_item()
	_place_catalog.call_deferred()

func _focus_inventory_item() -> void:
	for tile: PlaceableTile in catalog_buttons.values() + component_buttons.values() + [material_buttons.fabrication_hub]:
		if _binding_available(tile.tool):
			_focus_catalog_button(tile)
			return
	if project_focus_button.visible and not project_focus_button.disabled:
		_focus_catalog_button(project_focus_button)
		return
	for tile: Button in recipe_grid.get_children():
		if tile.visible and not tile.disabled:
			_focus_catalog_button(tile)
			return
	_focus_catalog_button(catalog_close_button)

func _focus_catalog_button(button: Button) -> void:
	button.grab_focus()
	_describe_focus(button)

func _slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if catalog.visible:
			clear_slot(index)
		else:
			open_catalog()
		get_viewport().set_input_as_handled()

func _placeable_tile(tool: String) -> PlaceableTile:
	if tool == "pod_workshop":
		return material_buttons.fabrication_hub as PlaceableTile
	if tool.begins_with(COMPONENT_PREFIX):
		return component_buttons.get(tool.trim_prefix(COMPONENT_PREFIX)) as PlaceableTile
	return catalog_buttons.get(tool) as PlaceableTile

func _binding_available(tool: String) -> bool:
	var host = _view()
	var tile := _placeable_tile(tool)
	return host != null and tile != null and tile.visible and not tile.disabled \
		and host._can_choose_tool() and _offered(tool, host) and _count(tool, host._display_parts()) > 0

func _drag_payload(tool: String) -> Dictionary:
	return {"hotbar_owner": get_instance_id(), "tool": tool} if _binding_available(tool) else {}

func _can_bind(index: int, data: Variant) -> bool:
	return index >= 0 and index < slots.size() and data is Dictionary \
		and data.get("hotbar_owner", -1) == get_instance_id() \
		and _binding_available(str(data.get("tool", "")))

func bind_slot(index: int, tool: String) -> bool:
	if index < 0 or index >= slots.size() or not _binding_available(tool):
		return false
	slots[index] = tool
	last_bound_slot = index
	refresh()
	return true

func bind_number_key(index: int) -> bool:
	if not catalog.visible:
		return false
	if not _hovered_tool.is_empty() and _binding_available(_hovered_tool):
		return bind_slot(index, _hovered_tool)
	var focused: Control = catalog.gui_get_focus_owner()
	if focused is PlaceableTile and _binding_available(focused.tool):
		return bind_slot(index, focused.tool)
	return false

func _clear_index() -> int:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered is HotbarSlot and is_ancestor_of(hovered):
		return hovered.index
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is HotbarSlot:
		return focused.index
	if last_bound_slot >= 0 and not slots[last_bound_slot].is_empty():
		return last_bound_slot
	return selected_slot

func clear_slot(index: int = -1) -> void:
	var host = _view()
	if host == null or host.explanation_open:
		return
	if index < 0:
		index = _clear_index()
	if index < 0 or index >= slots.size() or slots[index].is_empty():
		return
	slots[index] = ""
	if last_bound_slot == index:
		last_bound_slot = -1
	if selected_slot == index:
		host._select_tool("inspect")
	refresh()

func _select_inventory_tool(tool: String) -> void:
	if not _binding_available(tool):
		return
	_close_catalog()
	_select_tool(tool, -1)

func select_slot(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	refresh()
	if buttons[index].disabled or slots[index].is_empty() or not _binding_available(slots[index]):
		return
	_select_tool(slots[index], index)

func _select_tool(tool: String, index: int) -> void:
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
	if tool.begins_with("gear:") and host.transmission_controls != null:
		host.transmission_controls.gear_teeth = int(tool.trim_prefix("gear:"))
	selected_slot = index
	host._select_tool("gear" if tool.begins_with("gear:") else tool)
