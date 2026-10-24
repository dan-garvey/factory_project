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
const MATERIALS := {
	"timber": ["Timber", "timber.svg"], "raw": ["Ore blank", "ore.svg"],
	"products": ["Plate", "plate.svg"], "offcuts": ["Offcut", "offcut.svg"],
	"sheets": ["Broad sheet", "sheet.svg"], "work_lots": ["Workpiece", "press-feed.svg"],
	"hand_crank": ["Hand crank", "workshop-crank.svg"],
	"fabrication_hub": ["Pod workshop", "workshop-pod.svg"]}
const COMPONENT_ICONS := {
	"wooden_frame": "wooden_frame.svg", "wooden_shaft": "wooden_shaft.svg",
	"wooden_cog": "wooden_cog.svg", "receiver_tray": "receiver_tray.svg",
	"tool_mount": "tool_mount.svg", "sliding_guide": "sliding_guide.svg",
	"cutting_edge": "cutting_edge.svg", "anvil": "anvil.svg",
	"ram_face": "ram_face.svg", "softmetal_shaft": "softmetal_shaft.svg",
	"softmetal_cog": "softmetal_cog.svg", "wooden_workbench": "wooden_workbench.svg"}
var slots: Array[String] = ["collector", "foundation", "belt", "processor", "wheel", "gear", "drive", ""]
var buttons: Array[Button] = []
var slot_icons: Array[TextureRect] = []
var slot_counts: Array[Label] = []
var catalog_buttons: Dictionary = {}
var catalog_counts: Dictionary = {}
var catalog_button: Button
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
var recipe_costs: Dictionary = {}
var recipe_side: VBoxContainer
var recipe_scroll: ScrollContainer
var inventory_scroll: ScrollContainer
var catalog_columns: BoxContainer
var slot_targets: Array[Button] = []
var context_label: Label
var context_action: Button
var context_bench := ""
var target_slot := 0
var parts_label: Label
var focus_description: Label
var selected_slot := 0
var _arrival_active := false
var _component_labels: Dictionary = {}
var _component_names: Array[String] = []
var _host: WeakRef

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
	catalog_button = host._button(row, "", open_catalog)
	catalog_button.icon = COMPONENT_ICON
	catalog_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	catalog_button.custom_minimum_size = Vector2(54, 54)
	catalog_button.tooltip_text = "Build and inventory · B"
	catalog_button.accessibility_name = "Build and inventory, shortcut B"
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
	menu_surface.bg_color = Color(0.055, 0.09, 0.11, 1.0)
	menu_surface.set_corner_radius_all(7)
	catalog.theme.set_stylebox("panel", "PopupPanel", menu_surface)
	add_child(catalog)
	var margin := MarginContainer.new()
	catalog_margin = margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	catalog.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	parts_label = host._label(column, "BUILD / INVENTORY", 18)
	focus_description = host._label(column, " ", 12)
	context_label = host._label(column, "Carried items and craftable recipes", 12)
	catalog_columns = BoxContainer.new()
	catalog_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_columns.add_theme_constant_override("separation", 12)
	column.add_child(catalog_columns)
	var inventory_side := VBoxContainer.new()
	inventory_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_columns.add_child(inventory_side)
	host._label(inventory_side, "CARRIED", 13)
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
		var tile := Button.new()
		material_grid.add_child(tile)
		_style_inventory_tile(tile, load("res://opening/assets/build-icons/" + MATERIALS[kind][1]))
		material_buttons[kind] = tile
		material_counts[kind] = _count_badge(tile)
		tile.focus_entered.connect(_describe_focus.bind(tile))
	material_buttons.fabrication_hub.pressed.connect(_select_hub_tool)
	for tool: String in TOOLS:
		var button: Button = host._button(material_grid, "", assign.bind(tool))
		_style_inventory_tile(button, load("res://opening/assets/build-icons/" + tool + ".svg"))
		catalog_buttons[tool] = button
		catalog_counts[tool] = _count_badge(button)
		button.focus_entered.connect(_describe_focus.bind(button))
	component_grid = material_grid
	for index in 8:
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
	host._label(recipe_side, "CRAFT / BUILD", 13)
	host._label(recipe_side, "T timber · O ore · choose an icon to craft", 11)
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
	host._label(column, "HOTBAR TARGET · choose 1–8, then choose a carried part", 11)
	var targets := HBoxContainer.new()
	targets.add_theme_constant_override("separation", 4)
	column.add_child(targets)
	for index in slots.size():
		var target: Button = host._button(targets, "", _select_target.bind(index))
		target.custom_minimum_size = Vector2(42, 39)
		_style_slot(target)
		target.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		target.expand_icon = true
		target.add_theme_constant_override("icon_max_width", 25)
		var target_key := Label.new()
		target_key.text = str(index + 1)
		target_key.position = Vector2(3, 2)
		target_key.add_theme_font_size_override("font_size", 10)
		target_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target.add_child(target_key)
		target.focus_entered.connect(_describe_focus.bind(target))
		slot_targets.append(target)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	context_action = host._button(actions, "", _use_context_action)
	context_action.icon = load("res://opening/assets/build-icons/workshop-reclaim.svg")
	context_action.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	context_action.custom_minimum_size = Vector2(46, 39)
	context_action.focus_entered.connect(_describe_focus.bind(context_action))
	context_action.visible = false
	var clear: Button = host._button(actions, "", clear_slot)
	clear.icon = load("res://opening/assets/build-icons/slot-clear.svg")
	clear.tooltip_text = "Clear target slot · Delete"
	clear.accessibility_name = "Clear target slot, shortcut Delete"
	var close: Button = host._button(actions, "", catalog.hide)
	close.icon = load("res://opening/assets/menu-icons/close.svg")
	close.tooltip_text = "Close build and inventory · Esc"
	close.accessibility_name = "Close build and inventory, shortcut Escape"
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

func _input(event: InputEvent) -> void:
	if not catalog.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.alt_pressed:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_8:
		_select_target(event.keycode - KEY_1)
	elif event.keycode == KEY_DELETE:
		clear_slot()
	elif event.keycode == KEY_ESCAPE:
		catalog.hide()
	elif event.keycode == KEY_S and context_action.visible and context_bench == str(_view().state.get("fabrication_hub", {}).get("id", "")):
		_use_context_action()
	elif event.keycode == KEY_R and context_action.visible and context_bench != str(_view().state.get("fabrication_hub", {}).get("id", "")):
		_use_context_action()
	elif event.keycode == KEY_P and _arrival_active and _material_count("fabrication_hub", _view()) > 0:
		_select_hub_tool()
	elif CATALOG_KEYS.has(event.keycode):
		assign(CATALOG_KEYS[event.keycode])
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
	_configure_catalog_layout(extent)
	catalog.size = _catalog_dimensions(extent)
	catalog.position = Vector2i(maxi(0, int((extent.x - catalog.size.x) / 2.0)),
		maxi(0, int((extent.y - catalog.size.y) / 2.0)))

func _configure_catalog_layout(extent: Vector2) -> void:
	var narrow := extent.x <= 720.0
	catalog_columns.vertical = narrow
	context_label.visible = not narrow
	var scroll_height := 78 if narrow else 275
	inventory_scroll.custom_minimum_size = Vector2(0, scroll_height)
	recipe_scroll.custom_minimum_size = Vector2(0, scroll_height)
	for side in ["left", "right", "top", "bottom"]:
		catalog_margin.add_theme_constant_override("margin_" + side, 8 if narrow else 16)

func _catalog_dimensions(extent: Vector2) -> Vector2i:
	var width := int(extent.x) if extent.x <= 720.0 else mini(800, int(extent.x) - 16)
	return Vector2i(width, mini(620, int(extent.y) - 16))

func _view():
	return _host.get_ref() if _host != null else null

func _count(tool: String, parts: Dictionary) -> int:
	if tool.begins_with(COMPONENT_PREFIX):
		var host = _view()
		return maxi(0, int(host.state.get("cargo", {}).get(host.client, {}).get("components", {}).get(
			tool.trim_prefix(COMPONENT_PREFIX), 0))) if host != null else 0
	return maxi(0, int(parts.get("shaft" if tool == "drive" else tool, 0)))

func _material_count(kind: String, host) -> int:
	var cargo: Dictionary = host.state.get("cargo", {}).get(host.client, {})
	if kind == "work_lots":
		return cargo.get("work_lots", []).size()
	if kind == "hand_crank" or kind == "fabrication_hub":
		return int(host.state.get(kind, {}).get("holder", "") == host.client)
	return maxi(0, int(cargo.get(kind, 0)))

func _tool_label(tool: String) -> String:
	return str(_component_labels.get(tool.trim_prefix(COMPONENT_PREFIX), "Component")) \
		if tool.begins_with(COMPONENT_PREFIX) else str(TOOLS.get(tool, "Empty"))

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
			var button: Button = host._button(component_grid, "",
				_assign_to_slot.bind(COMPONENT_PREFIX + component))
			_style_inventory_tile(button, component_textures[component])
			component_buttons[component] = button
			component_counts[component] = _count_badge(button)
			button.focus_entered.connect(_describe_focus.bind(button))
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
	var tile: Button = host._button(recipe_grid, "", _craft_recipe.bind(key))
	_style_inventory_tile(tile, icon)
	tile.focus_entered.connect(_describe_focus.bind(tile))
	var cost := Label.new()
	cost.position = Vector2(4, 44)
	cost.size = Vector2(70, 18)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_font_size_override("font_size", 11)
	cost.add_theme_color_override("font_color", Color("f6e5c5"))
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(cost)
	recipe_buttons[key] = tile
	recipe_costs[key] = cost
	return tile

func _recipe_state(host, key: String, label: String, cost: Dictionary,
		icon: Texture2D, field_allowed: bool, ready: bool) -> void:
	var tile := _recipe_tile(key, icon)
	var cargo: Dictionary = host.state.get("cargo", {}).get(host.client, {})
	var timber := int(cost.get("timber", 0))
	var ore := int(cost.get("softmetal", 0))
	var affordable := int(cargo.get("timber", 0)) >= timber and int(cargo.get("raw", 0)) >= ore
	var at_bench := _valid_bench(host.state, context_bench)
	var station := "Field or bench" if field_allowed else "Bench"
	var rating := int(cost.get("load_rating", 0))
	var rating_detail := " · rated for %d load" % rating if rating > 0 else ""
	var reason := "Craft here" if ready and affordable and (field_allowed or at_bench) else \
		"Carry the ingredients" if not affordable else \
		"Open a fabrication bench with E" if not field_allowed and not at_bench else \
		"Wait for the character"
	var craftable := reason == "Craft here"
	tile.visible = true
	tile.disabled = not ready
	tile.modulate = Color.WHITE if craftable else Color(0.42, 0.47, 0.50) if not affordable else \
		Color(0.65, 0.70, 0.72)
	for state_name in ["normal", "hover"]:
		var surface := tile.get_theme_stylebox(state_name, "Button") as StyleBoxFlat
		surface.border_color = Color("e7b875")
		surface.border_width_bottom = 2 if craftable else 0
	tile.tooltip_text = "%s · %d timber + %d ore · %s%s · %s" % [
		label, timber, ore, station, rating_detail, reason]
	tile.accessibility_name = "%s recipe, needs %d timber and %d ore, %s%s, %s" % [
		label, timber, ore, station, rating_detail, reason]
	recipe_costs[key].text = "%dT · %dO" % [timber, ore]

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
	context_label.text = "Fabrication bench · choose a recipe" if not context_bench.is_empty() else \
		"Field recipes can be made anywhere · E opens a bench"
	var recipes: Dictionary = host.state.get("component_recipes", {})
	for component: String in _component_names:
		var cost: Dictionary = recipes.get(component, {})
		if cost.is_empty():
			continue
		var field_allowed := int(cost.get("timber", 0)) > 0 and int(cost.get("softmetal", 0)) == 0
		_recipe_state(host, COMPONENT_PREFIX + component, _component_labels[component], cost,
			component_textures[component], field_allowed, ready)
	var foundation: Dictionary = host.state.get("foundation_recipe", {})
	if not foundation.is_empty():
		_recipe_state(host, "foundation", "Foundation", foundation,
			catalog_buttons.foundation.icon, false, ready)
	var parts: Array = host.state.get("part_recipes", [])
	for index in parts.size():
		var recipe: Dictionary = parts[index]
		var kind: String = str(recipe.get("kind", ""))
		var icon_name: String = {"shaft": "drive", "belt": "belt", "wheel": "wheel"}.get(kind, "component")
		var label: String = {"shaft": "Shaft tile", "belt": "Belt span", "wheel": "Waterwheel"}.get(kind, "Part")
		if int(recipe.get("half_span", 0)) > 0:
			label += " · half-span %d" % int(recipe.half_span)
		if int(recipe.get("teeth", 0)) > 0:
			label += " · %d teeth" % int(recipe.teeth)
		_recipe_state(host, "part:%d" % index, label, recipe,
			load("res://opening/assets/build-icons/%s.svg" % icon_name), false, ready)

func _craft_recipe(key: String) -> void:
	var host = _view()
	if host == null or not _arrival_active or not host._can_choose_tool():
		return
	var cargo: Dictionary = host.state.get("cargo", {}).get(host.client, {})
	var cost: Dictionary = {}
	var action: Dictionary = {}
	if key.begins_with(COMPONENT_PREFIX):
		var component := key.trim_prefix(COMPONENT_PREFIX)
		cost = host.state.get("component_recipes", {}).get(component, {})
		if not context_bench.is_empty() and _valid_bench(host.state, context_bench):
			action = {"action": "craft_component", "entity": context_bench, "component": component}
		elif int(cost.get("timber", 0)) > 0 and int(cost.get("softmetal", 0)) == 0:
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
	if cost.is_empty() or action.is_empty():
		focus_description.text = "Open a fabrication bench with E for this recipe."
		return
	if int(cargo.get("timber", 0)) < int(cost.get("timber", 0)) or \
			int(cargo.get("raw", 0)) < int(cost.get("softmetal", 0)):
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
	catalog.hide()
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
			material_buttons[kind].tooltip_text += " · select placement · P"
			material_buttons[kind].accessibility_name += ", select placement, shortcut P"
		material_buttons[kind].visible = amount > 0 if _arrival_active else true
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
		slot_icons[index].texture = component_textures[tool.trim_prefix(COMPONENT_PREFIX)] if tool.begins_with(COMPONENT_PREFIX) else \
			catalog_buttons[tool].icon if not tool.is_empty() else null
		slot_icons[index].visible = not tool.is_empty()
		slot_counts[index].text = str(amount) if not tool.is_empty() else "+"
		buttons[index].tooltip_text = "%s · %d %s · slot %d" % [label, amount, scope, index + 1] if not tool.is_empty() else "Assign slot %d · B opens catalog" % (index + 1)
		buttons[index].accessibility_name = "%s, %d %s, slot %d" % [label, amount, scope, index + 1] if not tool.is_empty() else "Assign slot %d, shortcut B opens inventory" % (index + 1)
		buttons[index].disabled = host.explanation_open or (not tool.is_empty() and (not usable or amount < 1 or not offered))
		buttons[index].button_pressed = selected_slot == index and active == tool
		var target := slot_targets[index]
		target.icon = slot_icons[index].texture
		target.tooltip_text = "Hotbar %d: %s · %d %s. Choose this slot, then a carried item." % [
			index + 1, label, amount, scope]
		target.accessibility_name = "Hotbar slot %d, %s, %d %s" % [index + 1, label, amount, scope]
		target.add_theme_color_override("font_color", Color("f6e5c5") if index == target_slot else Color("a5bab9"))
	for tool: String in catalog_buttons:
		var button: Button = catalog_buttons[tool]
		var amount := _count(tool, parts)
		button.text = ""
		catalog_counts[tool].text = str(amount)
		button.tooltip_text = "%s · %d %s · %s" % [TOOLS[tool], amount, scope, TOOL_KEYS[tool]]
		button.accessibility_name = "%s, %d %s, shortcut %s" % [TOOLS[tool], amount, scope, TOOL_KEYS[tool]]
		button.disabled = not usable or amount < 1 or not _offered(tool, host)
		button.visible = _offered(tool, host) and (not _arrival_active or amount > 0)
	if _arrival_active:
		for component: String in _component_names:
			var count := _count(COMPONENT_PREFIX + component, parts)
			var part_button: Button = component_buttons[component]
			part_button.text = ""
			component_counts[component].text = str(count)
			part_button.disabled = not usable or count < 1
			part_button.visible = count > 0
			part_button.tooltip_text = "%s · %d carried · assign to hotbar %d" % [
				_component_labels[component], count, target_slot + 1]
			part_button.accessibility_name = "%s, %d carried, assign to hotbar %d" % [
				_component_labels[component], count, target_slot + 1]
	var shown := 0
	for tile in material_grid.get_children():
		if tile is Button and tile.visible:
			shown += 1
	for index in inventory_empty.size():
		inventory_empty[index].visible = index < maxi(0, 8 - shown)
	_refresh_recipes(host, usable)

func open_catalog(index: int = -1) -> void:
	var host = _view()
	if host == null or host.explanation_open:
		return
	if catalog.visible and index < 0:
		catalog.hide()
		return
	context_bench = ""
	refresh()
	_select_target(index if index >= 0 and index < slots.size() else maxi(0, selected_slot))
	var viewport_size: Vector2 = get_parent().size
	_configure_catalog_layout(viewport_size)
	catalog.popup_centered(_catalog_dimensions(viewport_size))
	slot_targets[target_slot].grab_focus()
	host._refresh_guided_tools()
	_place_catalog.call_deferred()

func open_at_bench(bench_id: String) -> void:
	var host = _view()
	if host == null or not _valid_bench(host.state, bench_id):
		return
	context_bench = bench_id
	refresh()
	host._release_character_controls()
	var viewport_size: Vector2 = get_parent().size
	_configure_catalog_layout(viewport_size)
	catalog.popup_centered(_catalog_dimensions(viewport_size))
	slot_targets[target_slot].grab_focus()
	_place_catalog.call_deferred()

func _select_target(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	target_slot = index
	refresh()

func _slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		open_catalog(index)
		get_viewport().set_input_as_handled()

func assign(tool: String) -> void:
	if not catalog_buttons.has(tool) or catalog_buttons[tool].disabled:
		return
	_assign_to_slot(tool)

func _assign_to_slot(tool: String) -> void:
	var index := target_slot
	slots[index] = tool
	catalog.hide()
	select_slot(index)

func clear_slot() -> void:
	var host = _view()
	if host == null or host.explanation_open:
		return
	var index := target_slot
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
